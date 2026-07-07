param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Read-MIRJson {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing policy lint input: $Path"
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertTo-MIRArray {
  param($Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [array]) { return @($Value) }
  return @($Value)
}

function Get-MIRProperty {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Default }
  return $property.Value
}

function Test-MIRProperty {
  param($Object, [string]$Name)
  return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-MIRTextContains {
  param([string]$Text, [string]$Snippet, [string]$Context)
  if (-not $Text.Contains($Snippet)) {
    throw "$Context missing required snippet: $Snippet"
  }
}

function Get-MIRStreamKeysFromSource {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing stream source for manifest lint: $Path"
  }

  return @(
    Select-String -LiteralPath $Path -Pattern "^\s*(research_[A-Za-z0-9_]+)\s*=\s*\{" |
      ForEach-Object { $_.Matches[0].Groups[1].Value }
  )
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$policyPath = Join-Path $repo "prototypes\mir\policy\capabilities.lua"
$contractPath = Join-Path $repo "prototypes\mir\capabilities\contract.lua"
$capabilityRegistryPath = Join-Path $repo "prototypes\mir\capabilities\registry.lua"
$manifestPath = Join-Path $repo "prototypes\planner\generated-stream-manifest.json"
$productivityStreamsPath = Join-Path $repo "prototypes\streams\productivity.lua"
$directEffectStreamsPath = Join-Path $repo "prototypes\streams\direct-effects.lua"
$claimsPath = Join-Path $repo "fixtures\compat-matrix\claims.json"
$supportLanePath = Join-Path $repo "fixtures\compat-matrix\support-lanes.json"
$compatibilityManifestPath = Join-Path $repo ".mir\compatibility.yml"
$streamsManifestPath = Join-Path $repo ".mir\streams.yml"
$claimLevelsDocPath = Join-Path $repo "docs\compatibility\claim-levels.md"
$luaClaimRegistryPath = Join-Path $repo "prototypes\mir\compatibility\claim_registry.lua"

$policyText = Get-Content -Raw -LiteralPath $policyPath
$contractText = Get-Content -Raw -LiteralPath $contractPath
$capabilityRegistryText = Get-Content -Raw -LiteralPath $capabilityRegistryPath
$manifest = Read-MIRJson -Path $manifestPath
$claims = Read-MIRJson -Path $claimsPath
$supportLanes = Read-MIRJson -Path $supportLanePath
$compatibilityManifestText = Get-Content -Raw -LiteralPath $compatibilityManifestPath
$streamsManifestText = Get-Content -Raw -LiteralPath $streamsManifestPath
$claimLevelsDocText = Get-Content -Raw -LiteralPath $claimLevelsDocPath
$luaClaimRegistryText = Get-Content -Raw -LiteralPath $luaClaimRegistryPath

Assert-MIRTextContains -Text $contractText -Snippet "schema_version" -Context "capability contract"
Assert-MIRTextContains -Text $contractText -Snippet "discover" -Context "capability contract"
Assert-MIRTextContains -Text $contractText -Snippet "diagnose" -Context "capability contract"
Assert-MIRTextContains -Text $capabilityRegistryText -Snippet "contract.validate_all(RESOLVERS)" -Context "capability registry"
Assert-MIRTextContains -Text $policyText -Snippet "P.schema_version = schema.capability_policy" -Context "capability policy"
Assert-MIRTextContains -Text $policyText -Snippet "deny_risk_flags" -Context "capability policy"
Assert-MIRTextContains -Text $policyText -Snippet "min_confidence" -Context "capability policy"
Assert-MIRTextContains -Text $policyText -Snippet "owner_policy" -Context "capability policy"

if ([int](Get-MIRProperty -Object $manifest -Name "schema" -Default 0) -ne 1) {
  throw "Generated stream manifest must use schema 1."
}

$streams = Get-MIRProperty -Object $manifest -Name "streams"
foreach ($streamProperty in @($streams.PSObject.Properties)) {
  $id = [string]$streamProperty.Name
  $stream = $streamProperty.Value
  foreach ($field in @("introduced_in", "source", "capability", "family", "policy", "stable", "generated_technology", "stream_key", "migration_policy", "targets")) {
    if ($null -eq (Get-MIRProperty -Object $stream -Name $field)) {
      throw "Generated stream manifest row $id missing required field: $field"
    }
  }
  if (-not [bool](Get-MIRProperty -Object $stream -Name "stable")) {
    throw "Generated stream manifest row $id must be stable."
  }
  if ([string](Get-MIRProperty -Object $stream -Name "migration_policy") -ne "stable") {
    throw "Generated stream manifest row $id must declare migration_policy=stable until a migration map exists."
  }
  if (@(ConvertTo-MIRArray (Get-MIRProperty -Object $stream -Name "targets")).Count -eq 0) {
    throw "Generated stream manifest row $id must list targets."
  }
}

if ([int](Get-MIRProperty -Object $claims -Name "schema" -Default 0) -ne 1) {
  throw "Compatibility claims must use schema 1."
}

$manifestStreamIds = @{}
$manifestStreamKeys = @{}
$manifestGeneratedTechnologies = @{}
foreach ($streamProperty in @($streams.PSObject.Properties)) {
  $streamId = [string]$streamProperty.Name
  $stream = $streamProperty.Value
  $streamKey = [string](Get-MIRProperty -Object $stream -Name "stream_key")
  $generatedTechnology = [string](Get-MIRProperty -Object $stream -Name "generated_technology")

  if ($manifestStreamIds[$streamId]) {
    throw "Generated stream manifest has duplicate row id: $streamId"
  }
  if ($manifestStreamKeys[$streamKey]) {
    throw "Generated stream manifest has duplicate stream_key: $streamKey"
  }
  if ($manifestGeneratedTechnologies[$generatedTechnology]) {
    throw "Generated stream manifest has duplicate generated_technology: $generatedTechnology"
  }

  $manifestStreamIds[$streamId] = $true
  $manifestStreamKeys[$streamKey] = $true
  $manifestGeneratedTechnologies[$generatedTechnology] = $true
}

$sourceStreamKeys = @(
  Get-MIRStreamKeysFromSource -Path $productivityStreamsPath
  Get-MIRStreamKeysFromSource -Path $directEffectStreamsPath
)

foreach ($streamKey in $sourceStreamKeys) {
  if (-not $manifestStreamKeys[$streamKey]) {
    throw "Generated stream manifest missing source stream_key: $streamKey"
  }

  $expectedGeneratedTechnology = "recipe-prod-$streamKey-1"
  if (-not $manifestGeneratedTechnologies[$expectedGeneratedTechnology]) {
    throw "Generated stream manifest missing emitted technology id for $streamKey`: $expectedGeneratedTechnology"
  }
}

$mirStreamIds = @(
  [regex]::Matches($streamsManifestText, "(?m)^\s{4}([A-Za-z0-9._-]+):\s*$") |
    ForEach-Object { $_.Groups[1].Value }
)
foreach ($streamId in $mirStreamIds) {
  if (-not $manifestStreamIds[$streamId]) {
    throw ".mir/streams.yml references generated stream without canonical manifest entry: $streamId"
  }
}

$allowedLevelBlock = [regex]::Match($compatibilityManifestText, "(?ms)allowed_levels:\s*(?<body>(?:\s+-\s+[^\r\n]+\r?\n)+)")
if (-not $allowedLevelBlock.Success) {
  throw ".mir/compatibility.yml must declare claims.allowed_levels."
}
$allowedLevels = @(
  [regex]::Matches($allowedLevelBlock.Groups["body"].Value, "(?m)^\s+-\s+([A-Za-z0-9._-]+)\s*$") |
    ForEach-Object { $_.Groups[1].Value }
)
foreach ($level in $allowedLevels) {
  $documentedLevel = '`' + $level + '`'
  if (-not $claimLevelsDocText.Contains($documentedLevel)) {
    throw "docs/compatibility/claim-levels.md does not document allowed claim level: $level"
  }
}

$compatibilityRecordsBlock = [regex]::Match($compatibilityManifestText, "(?ms)records:\s*(?<body>.*?)(?:\r?\nrules:|$)")
if (-not $compatibilityRecordsBlock.Success) {
  throw ".mir/compatibility.yml must declare targets.records."
}
$compatibilityRecordIds = @(
  [regex]::Matches($compatibilityRecordsBlock.Groups["body"].Value, "(?m)^\s{4}([A-Za-z0-9._-]+):\s*$") |
    ForEach-Object { $_.Groups[1].Value }
)
foreach ($recordId in $compatibilityRecordIds) {
  if (-not $luaClaimRegistryText.Contains('id = "' + $recordId + '"')) {
    throw "Lua compatibility claim registry missing .mir/compatibility.yml target id: $recordId"
  }
}

foreach ($claim in @(ConvertTo-MIRArray (Get-MIRProperty -Object $claims -Name "claims"))) {
  $mod = [string](Get-MIRProperty -Object $claim -Name "mod")
  if ([string]::IsNullOrWhiteSpace($mod)) { throw "Compatibility claim missing mod." }
  foreach ($field in @("claim_level", "capabilities", "tested_factorio", "generated_streams", "fixtures", "public_text")) {
    if (-not (Test-MIRProperty -Object $claim -Name $field)) {
      throw "Compatibility claim $mod missing required field: $field"
    }
  }
  if (-not $luaClaimRegistryText.Contains('mod = "' + $mod + '"')) {
    throw "Lua compatibility claim registry missing fixture claim mod: $mod"
  }
  foreach ($streamId in @(ConvertTo-MIRArray (Get-MIRProperty -Object $claim -Name "generated_streams"))) {
    if (-not $manifestStreamIds[[string]$streamId]) {
      throw "Compatibility claim $mod references generated stream without manifest entry: $streamId"
    }
  }
  $publicText = [string](Get-MIRProperty -Object $claim -Name "public_text")
  if ($publicText -match "(?i)\bfull support\b") {
    throw "Compatibility claim $mod uses overbroad public wording: $publicText"
  }
  if (@(ConvertTo-MIRArray (Get-MIRProperty -Object $claim -Name "fixtures")).Count -eq 0) {
    throw "Compatibility claim $mod must list backing fixtures."
  }
}

if ([int](Get-MIRProperty -Object $supportLanes -Name "schema" -Default 0) -ne 1) {
  throw "Support lanes must use schema 1."
}

foreach ($lane in @(ConvertTo-MIRArray (Get-MIRProperty -Object $supportLanes -Name "lanes"))) {
  $claimLane = [string](Get-MIRProperty -Object $lane -Name "claim_lane")
  $testedBy = @(ConvertTo-MIRArray (Get-MIRProperty -Object $lane -Name "tested_by"))
  if ($claimLane -match "fixture-backed" -and $claimLane -notmatch "planned" -and $testedBy.Count -eq 0) {
    throw "Fixture-backed support lane $([string](Get-MIRProperty -Object $lane -Name "mod")) must list tested_by fixtures."
  }
}

Write-Host "[ok] MIR policy, manifest, and claim lint passed."
