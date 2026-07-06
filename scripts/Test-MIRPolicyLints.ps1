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

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$policyPath = Join-Path $repo "prototypes\lib\policy\capabilities.lua"
$contractPath = Join-Path $repo "prototypes\lib\capabilities\contract.lua"
$capabilityRegistryPath = Join-Path $repo "prototypes\lib\capabilities\registry.lua"
$manifestPath = Join-Path $repo "prototypes\planner\generated-stream-manifest.json"
$claimsPath = Join-Path $repo "fixtures\compat-matrix\claims.json"
$supportLanePath = Join-Path $repo "fixtures\compat-matrix\support-lanes.json"

$policyText = Get-Content -Raw -LiteralPath $policyPath
$contractText = Get-Content -Raw -LiteralPath $contractPath
$capabilityRegistryText = Get-Content -Raw -LiteralPath $capabilityRegistryPath
$manifest = Read-MIRJson -Path $manifestPath
$claims = Read-MIRJson -Path $claimsPath
$supportLanes = Read-MIRJson -Path $supportLanePath

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
foreach ($streamProperty in @($streams.PSObject.Properties)) {
  $manifestStreamIds[[string]$streamProperty.Name] = $true
}

foreach ($claim in @(ConvertTo-MIRArray (Get-MIRProperty -Object $claims -Name "claims"))) {
  $mod = [string](Get-MIRProperty -Object $claim -Name "mod")
  if ([string]::IsNullOrWhiteSpace($mod)) { throw "Compatibility claim missing mod." }
  foreach ($field in @("claim_level", "capabilities", "tested_factorio", "generated_streams", "fixtures", "public_text")) {
    if (-not (Test-MIRProperty -Object $claim -Name $field)) {
      throw "Compatibility claim $mod missing required field: $field"
    }
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
