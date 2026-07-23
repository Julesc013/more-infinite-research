param(
  [string]$BaselinePackage = "dist\more-infinite-research_3.1.9.zip",
  [string]$CurrentPackage = "dist\more-infinite-research_3.2.0.zip",
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$OutputPath = "approved-delta\3.1.9-to-3.2.0.json",
  [string]$EvidenceRoot = "artifacts\approved-delta",
  [string]$ExpectedBaselineSha256 = "D77B3A78DA40CD4FDD4C829A01B5030E59FB593F3387124EF5C438F6A9E8DFCD",
  [string]$ExpectedSourceCommit = "",
  [switch]$SkipExecution
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-RepoPath {
  param([Parameter(Mandatory)][string]$Path)
  $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  return [IO.Path]::GetFullPath($candidate)
}

function Get-TextSha256 {
  param([AllowEmptyString()][string]$Text)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "") }
  finally { $sha.Dispose() }
}

function Get-CanonicalJson {
  param($Value)
  if ($null -eq $Value) { return "null" }
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-ValueFingerprint {
  param($Value)
  return Get-TextSha256 -Text (Get-CanonicalJson -Value $Value)
}

function Get-ApprovedDeltaProducerFingerprint {
  $paths = @(
    "scripts/Export-MIRApprovedDelta.ps1",
    "fixtures/compat-matrix/expected-scenarios.json",
    "fixtures/export-approved-delta/data-final-fixes.lua",
    "fixtures/export-approved-delta/info.json",
    "scripts/validation/FactorioProcess.ps1",
    "scripts/validation/PackageIdentity.ps1",
    "scripts/validation/ResultAggregation.ps1",
    "scripts/validation/ScenarioRegistry.ps1",
    "scripts/validation/SettingsOverrides.ps1",
    "scripts/validation/TargetProfiles.ps1"
  )
  $rows = @()
  foreach ($relative in $paths) {
    $path = Join-Path $repo $relative
    $rows += "$relative=$((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash)"
  }
  return Get-TextSha256 -Text ($rows -join "`n")
}

function Get-ZipEntryText {
  param(
    [Parameter(Mandatory)]$Archive,
    [Parameter(Mandatory)][string]$Suffix
  )
  $entry = @($Archive.Entries | Where-Object { $_.FullName -eq $Suffix -or $_.FullName.EndsWith("/$Suffix") })[0]
  if ($null -eq $entry) { return $null }
  $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
  try { return $reader.ReadToEnd() }
  finally { $reader.Dispose() }
}

function Get-ZipEntrySha256 {
  param([Parameter(Mandatory)]$Entry)
  $stream = $Entry.Open()
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
  finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-PackageContract {
  param([Parameter(Mandatory)][string]$PackagePath)
  $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
  try {
    $infoText = Get-ZipEntryText -Archive $archive -Suffix "info.json"
    if ([string]::IsNullOrWhiteSpace($infoText)) { throw "Package lacks info.json: $PackagePath" }
    $info = $infoText | ConvertFrom-Json

    $migrationRows = [ordered]@{}
    foreach ($entry in @($archive.Entries | Where-Object { $_.FullName -match '/migrations/[^/]+\.json$' } | Sort-Object FullName)) {
      $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
      try { $migrationText = $reader.ReadToEnd() }
      finally { $reader.Dispose() }
      $migrationRows[[IO.Path]::GetFileName($entry.FullName)] = [ordered]@{
        sha256 = Get-TextSha256 -Text $migrationText
        contract = $migrationText | ConvertFrom-Json
      }
    }

    $runtimeEntries = @($archive.Entries | Where-Object {
      $_.FullName -match '/control\.lua$' -or $_.FullName -match '/prototypes/mir/(runtime/.+|stage/control\.lua|platform/factorio/runtime_state\.lua)$'
    } | Sort-Object FullName)
    $runtimeText = ""
    $runtimeFiles = [ordered]@{}
    foreach ($entry in $runtimeEntries) {
      $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
      try { $text = $reader.ReadToEnd() }
      finally { $reader.Dispose() }
      $relative = $entry.FullName.Substring($entry.FullName.IndexOf("/") + 1)
      $runtimeFiles[$relative] = Get-TextSha256 -Text $text
      $runtimeText += "`n$text"
    }

    $storageKeys = @([regex]::Matches($runtimeText, '(?:storage|global)\.([A-Za-z_][A-Za-z0-9_]*)') |
      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $bracketStorageKeys = @([regex]::Matches($runtimeText, '(?:storage|global)\[["'']([^"'']+)["'']\]') |
      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $remoteInterfaces = @([regex]::Matches($runtimeText, 'remote\.add_interface\s*\(\s*["'']([^"'']+)["'']') |
      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $commands = @([regex]::Matches($runtimeText, 'commands\.add_command\s*\(\s*["'']([^"'']+)["'']') |
      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $controlText = Get-ZipEntryText -Archive $archive -Suffix "control.lua"
    $controlModules = @([regex]::Matches([string]$controlText, 'require\s*\(?\s*["'']([^"'']+)["'']') |
      ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

    $settingsEntries = @($archive.Entries | Where-Object {
      $_.FullName -match '/settings\.lua$' -or $_.FullName -match '/prototypes/mir/settings/.+\.lua$'
    } | Sort-Object FullName)
    $settingsSourceRows = [ordered]@{}
    foreach ($entry in $settingsEntries) {
      $relative = $entry.FullName.Substring($entry.FullName.IndexOf("/") + 1)
      $settingsSourceRows[$relative] = Get-ZipEntrySha256 -Entry $entry
    }

    return [pscustomobject][ordered]@{
      version = [string]$info.version
      factorio_version = [string]$info.factorio_version
      archive_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagePath).Hash
      package_content_sha256 = Get-MIRZipContentFingerprint -Path $PackagePath
      runtime_namespaces = [ordered]@{
        storage = @($storageKeys + $bracketStorageKeys | Sort-Object -Unique)
        remote_interfaces = $remoteInterfaces
        commands = $commands
        control_modules = $controlModules
      }
      migrations = $migrationRows
      runtime_source_fingerprints = $runtimeFiles
      settings_source_fingerprints = $settingsSourceRows
    }
  } finally {
    $archive.Dispose()
  }
}

function Get-ExportFromLog {
  param([Parameter(Mandatory)][string]$LogPath)
  $marker = "[MIR_APPROVED_DELTA]"
  $match = Select-String -LiteralPath $LogPath -Pattern $marker -SimpleMatch | Select-Object -Last 1
  if ($null -eq $match) { throw "Approved-delta exporter marker is absent from $LogPath" }
  $index = $match.Line.IndexOf($marker)
  $json = $match.Line.Substring($index + $marker.Length).Trim()
  $artifact = $json | ConvertFrom-Json
  if ($artifact.schema -ne 1 -or $artifact.kind -ne "mir-approved-delta-runtime-export") {
    throw "Approved-delta runtime export has an unsupported contract in $LogPath"
  }
  return $artifact
}

function Invoke-ApprovedDeltaScenario {
  param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$Scenario,
    [Parameter(Mandatory)][string]$RawOutputPath
  )
  $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-approved-delta-" + [guid]::NewGuid().ToString("N"))
  $logPath = Join-Path $tempRoot "factorio-current.log"
  $summaryPath = Join-Path $tempRoot "validation-summary.json"
  & (Join-Path $repo "scripts\Invoke-MIRValidation.ps1") `
    -ScenarioWorker `
    -FactorioBin $FactorioBin `
    -CandidateZip $PackagePath `
    -Scenario $Scenario `
    -UserDataDir $tempRoot `
    -FactorioLog $logPath `
    -ValidationSummaryPath $summaryPath
  if ($LASTEXITCODE -ne 0) { throw "Approved-delta scenario failed: $Label/$Scenario" }
  $artifact = Get-ExportFromLog -LogPath $logPath
  $rawParent = Split-Path -Parent $RawOutputPath
  New-Item -ItemType Directory -Force -Path $rawParent | Out-Null
  [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-approved-delta-raw-evidence"
    scenario = $Scenario
    package_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagePath).Hash
    producer_sha256 = Get-ApprovedDeltaProducerFingerprint
    factorio_binary_version = [Diagnostics.FileVersionInfo]::GetVersionInfo($FactorioBin).FileVersion
    runtime_export = $artifact
  } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $RawOutputPath -Encoding UTF8
  return $artifact
}

function Get-ObjectProperties {
  param($Value)
  if ($Value -is [Collections.IDictionary]) { return @($Value.Keys | ForEach-Object { [string]$_ }) }
  if ($Value -is [pscustomobject]) { return @($Value.PSObject.Properties.Name) }
  return @()
}

function Get-ObjectValue {
  param($Value, [string]$Name)
  if ($Value -is [Collections.IDictionary]) { return $Value[$Name] }
  return $Value.PSObject.Properties[$Name].Value
}

function Add-ValueDifferences {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Results,
    [Parameter(Mandatory)][string]$Path,
    $Before,
    $After
  )
  if ($null -eq $Before -and $null -eq $After) { return }
  if ($null -eq $Before -or $null -eq $After) {
    $Results.Add([pscustomobject]@{path=$Path; before=$Before; after=$After})
    return
  }
  $beforeProperties = Get-ObjectProperties -Value $Before
  $afterProperties = Get-ObjectProperties -Value $After
  if ($beforeProperties.Count -gt 0 -or $afterProperties.Count -gt 0) {
    $names = @($beforeProperties + $afterProperties | Sort-Object -Unique)
    foreach ($name in $names) {
      $beforeHas = $beforeProperties -contains $name
      $afterHas = $afterProperties -contains $name
      $childBefore = if ($beforeHas) { Get-ObjectValue -Value $Before -Name $name } else { $null }
      $childAfter = if ($afterHas) { Get-ObjectValue -Value $After -Name $name } else { $null }
      Add-ValueDifferences -Results $Results -Path "$Path.$name" -Before $childBefore -After $childAfter
    }
    return
  }
  if ((Get-CanonicalJson -Value $Before) -ne (Get-CanonicalJson -Value $After)) {
    $Results.Add([pscustomobject]@{path=$Path; before=$Before; after=$After})
  }
}

function Test-ExactStringArrayAddition {
  param(
    $Before,
    $After,
    [Parameter(Mandatory)][string]$ExpectedAdded
  )

  $beforeValues = @($Before | ForEach-Object { [string]$_ })
  $afterValues = @($After | ForEach-Object { [string]$_ })
  $added = @($afterValues | Where-Object { $beforeValues -notcontains $_ })
  $removed = @($beforeValues | Where-Object { $afterValues -notcontains $_ })
  return $removed.Count -eq 0 -and $added.Count -eq 1 -and $added[0] -eq $ExpectedAdded
}

function Test-ExactRecipeEffectRemoval {
  param(
    $Before,
    $After,
    [Parameter(Mandatory)][string]$ExpectedRecipe
  )

  $beforeRows = @($Before)
  $removed = @($beforeRows | Where-Object { [string]$_.recipe -eq $ExpectedRecipe })
  $retained = @($beforeRows | Where-Object { [string]$_.recipe -ne $ExpectedRecipe })
  if ($removed.Count -ne 1 -or
    [string]$removed[0].type -ne "change-recipe-productivity" -or
    [double]$removed[0].change -ne 0.1) {
    return $false
  }
  return (Get-CanonicalJson -Value $retained) -eq (Get-CanonicalJson -Value @($After))
}

function Test-ExactScienceSet {
  param($Value)

  $rows = @($Value)
  if ($rows.Count -ne 4 -or @($rows | Where-Object {
    [string]$_.type -ne "item" -or [double]$_.amount -ne 1
  }).Count -ne 0) {
    return $false
  }
  $names = @($rows | ForEach-Object { [string]$_.name } | Sort-Object)
  return ($names -join "|") -eq "automation-science-pack|chemical-science-pack|logistic-science-pack|production-science-pack"
}

function Test-ExactGeneratedSteelTechnology {
  param($Value)

  if ($null -eq $Value -or [string]$Value.name -ne "recipe-prod-research_steel-1" -or
    [string]$Value.count_formula -ne "8000*2^(L-1)" -or [double]$Value.research_time -ne 60 -or
    [string]$Value.maximum_level -ne "infinite" -or $Value.upgrade -ne $true) {
    return $false
  }
  $effects = @($Value.effects)
  if ($effects.Count -ne 1 -or [string]$effects[0].type -ne "change-recipe-productivity" -or
    [string]$effects[0].recipe -ne "steel-plate" -or [double]$effects[0].change -ne 0.1) {
    return $false
  }
  $prerequisites = @($Value.prerequisites | ForEach-Object { [string]$_ } | Sort-Object)
  return ($prerequisites -join "|") -eq "automation-science-pack|chemical-science-pack|logistic-science-pack|production-science-pack" -and
    (Test-ExactScienceSet -Value $Value.science_ingredients)
}

function Test-ExactNativeSteelTechnology {
  param($Value)

  if ($null -eq $Value -or [string]$Value.name -ne "steel-plate-productivity" -or
    [string]$Value.count_formula -ne "1.5^L*1000" -or [double]$Value.research_time -ne 60 -or
    [string]$Value.maximum_level -ne "infinite" -or $Value.upgrade -ne $true -or
    (@($Value.prerequisites | ForEach-Object { [string]$_ }) -join "|") -ne "production-science-pack" -or
    -not (Test-ExactScienceSet -Value $Value.science_ingredients)) {
    return $false
  }
  $effectRows = @($Value.effects)
  if ($effectRows.Count -lt 2 -or $effectRows.Count -gt 3 -or @($effectRows | Where-Object {
    [string]$_.type -ne "change-recipe-productivity" -or [double]$_.change -ne 0.1
  }).Count -ne 0) {
    return $false
  }
  $recipes = @($effectRows | ForEach-Object { [string]$_.recipe } | Sort-Object)
  return ($recipes -join "|") -in @(
    "casting-steel|steel-plate",
    "casting-steel|mir-fixture-adopt-steel-plate|steel-plate"
  )
}

function Test-ExactSteelSettingAddition {
  param(
    [Parameter(Mandatory)][string]$Path,
    $Before,
    $After
  )

  if ($null -ne $Before -or $Path -notmatch '\.settings\.(ips-[^.]+-research_steel)$') {
    return $false
  }
  $setting = $Matches[1]
  $expected = @{
    "ips-cost-base-research_steel" = @{ type = "number"; value = 8000 }
    "ips-cost-growth-research_steel" = @{ type = "number"; value = 2 }
    "ips-effect-per-level-research_steel" = @{ type = "number"; value = 10 }
    "ips-enable-research_steel" = @{ type = "boolean"; value = $true }
    "ips-max-level-research_steel" = @{ type = "number"; value = 0 }
    "ips-research-time-research_steel" = @{ type = "number"; value = 60 }
  }
  if (-not $expected.ContainsKey($setting)) { return $false }
  return [string]$After.value_type -eq [string]$expected[$setting].type -and
    $After.current_value -eq $expected[$setting].value
}

function Test-ExactCoverageContractDifference {
  param(
    [Parameter(Mandatory)][string]$Path,
    $Before,
    $After
  )

  if ($Path -match '\.mod_data_contracts\.more-infinite-research-coverage-report-internal$') {
    return $null -eq $Before -and
      [string]$After.data_type -eq "more-infinite-research.coverage-report-internal" -and
      [int]$After.schema -eq 1 -and
      [string]$After.contract_shape.kind -eq "object" -and
      $null -ne $After.contract_shape.fields.rows -and
      $null -ne $After.contract_shape.fields.summary
  }
  $prefix = '^scenarios\.[^.]+\.mod_data_contracts\.more-infinite-research-coverage-report\.'
  if ($Path -notmatch $prefix) { return $false }
  $suffix = $Path -replace $prefix, ''
  switch ($suffix) {
    "contract_shape.fields.coverage_fingerprint" { return $null -eq $Before -and [string]$After -eq "string" }
    "contract_shape.fields.coverage_report_schema" { return $null -eq $Before -and [string]$After -eq "number" }
    "contract_shape.fields.fingerprint" { return [string]$Before -eq "string" -and $null -eq $After }
    "contract_shape.fields.public_fingerprint" { return $null -eq $Before -and [string]$After -eq "string" }
    "contract_shape.fields.rows" { return [string]$Before.kind -eq "map" -and $null -eq $After }
    "data_type" {
      return [string]$Before -eq "more-infinite-research.coverage-report" -and
        [string]$After -eq "more-infinite-research.coverage-public"
    }
    default { return $false }
  }
}

function Get-DifferenceDisposition {
  param(
    [Parameter(Mandatory)][string]$Path,
    $Before,
    $After
  )
  if ($Path -match '^package\.(version|archive_sha256|package_content_sha256|runtime_source_fingerprints|settings_source_fingerprints)') {
    return [ordered]@{
      reason = "Exact package identity and source fingerprint changed between the sealed 3.1.9 baseline and the 3.2 compiler branch."
      intentional = $true
      migration_impact = "None by itself; semantic runtime and prototype contracts are compared separately."
      required_evidence = @("sealed 3.1.9 archive hash", "deterministic current archive hash", "static package contract export")
    }
  }
  if ($Path -match '^scenarios\.[^.]+\.active_mods\.more-infinite-research$') {
    return [ordered]@{
      reason = "Scenario binds the two exact MIR package versions under comparison."
      intentional = $true
      migration_impact = "Package version transition only."
      required_evidence = @("exact-package scenario summary", "archive SHA-256")
    }
  }
  if ($Path -match '^scenarios\.[^.]+\.mod_data_contracts\.(more-infinite-research-generation-plan|more-infinite-research-compiler-evidence)') {
    return [ordered]@{
      reason = "3.2 hardens GenerationPlan authority and target-neutral CompilerEvidence contracts."
      intentional = $true
      migration_impact = "Diagnostic consumers must accept the documented 3.2 schema; save identity is unaffected."
      required_evidence = @("compiler-contracts", "base-generation-integrity", "schema drift static gate")
    }
  }
  if (Test-ExactCoverageContractDifference -Path $Path -Before $Before -After $After) {
    return [ordered]@{
      reason = "3.2 publishes compact public coverage and reserves the complete recipe ledger for explicit internal diagnostics."
      intentional = $true
      migration_impact = "Coverage mod-data consumers must migrate to the compact public schema or explicitly request the internal diagnostic artifact; save identity is unaffected."
      required_evidence = @("compiler-contracts", "coverage-report schema reference", "public compiler artifact schema drift gate")
    }
  }
  if (Test-ExactSteelSettingAddition -Path $Path -Before $Before -After $After) {
    return [ordered]@{
      reason = "3.2 adds the explicitly reviewed steel productivity stream and its stable startup-setting family."
      intentional = $true
      migration_impact = "Existing saves receive a new default-enabled base steel productivity stream; Space Age binds the same settings to the native steel owner."
      required_evidence = @("3.2 steel technology golden plan", "native-owner settings matrix", "3.2 release notes")
    }
  }
  if ($Path -match '^scenarios\.[^.]+\.generated_registry\.recipe-prod-research_steel-1$' -and
    $null -eq $Before -and [string]$After.key -eq "research_steel" -and
    [string]$After.kind -eq "stream" -and [string]$After.name -eq "recipe-prod-research_steel-1") {
    return [ordered]@{
      reason = "3.2 adds the explicitly reviewed steel productivity stream and stable generated identity."
      intentional = $true
      migration_impact = "Base saves may receive recipe-prod-research_steel-1; Space Age continues to use its native steel owner."
      required_evidence = @("3.2 steel technology golden plan", "base and Space Age generation integrity", "3.2 release notes")
    }
  }
  if ($Path -match '^scenarios\.[^.]+\.technologies\.recipe-prod-research_steel-1$' -and
    $null -eq $Before -and (Test-ExactGeneratedSteelTechnology -Value $After)) {
    return [ordered]@{
      reason = "3.2 adds the explicitly reviewed base steel productivity technology."
      intentional = $true
      migration_impact = "Base saves gain one stable infinite steel-plate productivity technology with reviewed +10% effects and progression."
      required_evidence = @("3.2 steel technology golden plan", "generation integrity", "human balance review")
    }
  }
  if ($Path -match '^scenarios\.[^.]+\.technologies\.steel-plate-productivity$' -and
    $null -eq $Before -and (Test-ExactNativeSteelTechnology -Value $After)) {
    return [ordered]@{
      reason = "3.2 adopts safe steel recipes into the existing Space Age steel productivity owner."
      intentional = $true
      migration_impact = "Space Age retains one visible native steel owner; MIR does not create a duplicate technology."
      required_evidence = @("native-owner adoption fixture", "Space Age generation integrity", "upgrade matrix")
    }
  }
  if ($Path -match '^scenarios\.[^.]+\.technology_ids$') {
    $expectedAdded = if ($Path -match '(compat-space-age-galore|native-owner-adoption|space-age)\.technology_ids$') {
      "steel-plate-productivity"
    } else {
      "recipe-prod-research_steel-1"
    }
    if (Test-ExactStringArrayAddition -Before $Before -After $After -ExpectedAdded $expectedAdded) {
      return [ordered]@{
        reason = "3.2 adds exactly one reviewed steel stream identity for the active base or Space Age ownership model."
        intentional = $true
        migration_impact = "One stable steel identity enters the normalized technology catalog without removing prior identities."
        required_evidence = @("3.2 steel technology golden plan", "base and Space Age exact-package scenarios")
      }
    }
  }
  if ($Path -eq 'scenarios.approved-delta-native-owner-adoption.technologies.recipe-prod-research_copper-1.effects' -and
    (Test-ExactRecipeEffectRemoval -Before $Before -After $After -ExpectedRecipe "mir-fixture-scrap-copper-plate-recovery")) {
    return [ordered]@{
      reason = "3.2 removes the reviewed copper scrap-recovery loop from material productivity ownership."
      intentional = $true
      migration_impact = "Unsafe scrap-input recovery recipes no longer receive copper productivity."
      required_evidence = @("scrap-recovery exclusion fixture", "native-owner adoption scenario", "3.2 changelog")
    }
  }
  if ($Path -eq 'scenarios.approved-delta-native-owner-adoption.technologies.recipe-prod-research_iron-1.effects' -and
    (Test-ExactRecipeEffectRemoval -Before $Before -After $After -ExpectedRecipe "mir-fixture-scrap-iron-plate-recovery")) {
    return [ordered]@{
      reason = "3.2 removes the reviewed iron scrap-recovery loop from material productivity ownership."
      intentional = $true
      migration_impact = "Unsafe scrap-input recovery recipes no longer receive iron productivity."
      required_evidence = @("scrap-recovery exclusion fixture", "native-owner adoption scenario", "3.2 changelog")
    }
  }
  return [ordered]@{
    reason = "Unreviewed normalized difference."
    intentional = $false
    migration_impact = "Unknown until independently classified."
    required_evidence = @("maintainer classification", "focused exact-package scenario")
  }
}

function Get-RowShapeSummary {
  param($Value)
  if ($null -eq $Value) { return $null }
  $fieldKinds = [ordered]@{}
  $variants = @($Value)
  foreach ($variant in $variants) {
    $fields = $variant.fields
    if ($null -eq $fields) { continue }
    foreach ($property in $fields.PSObject.Properties | Sort-Object Name) {
      $shape = $property.Value
      $signature = if ($shape -is [string]) {
        $shape
      } elseif ($null -ne $shape.kind -and $shape.kind -eq "object" -and $null -ne $shape.fields) {
        "object{" + (@($shape.fields.PSObject.Properties.Name | Sort-Object) -join ",") + "}"
      } elseif ($null -ne $shape.kind) {
        [string]$shape.kind
      } else {
        "table"
      }
      if (-not $fieldKinds.Contains($property.Name)) { $fieldKinds[$property.Name] = @() }
      if ($fieldKinds[$property.Name] -notcontains $signature) {
        $fieldKinds[$property.Name] = @($fieldKinds[$property.Name] + $signature | Sort-Object -Unique)
      }
    }
  }
  return [pscustomobject][ordered]@{
    variant_count = $variants.Count
    fields = $fieldKinds
  }
}

$baselinePath = Resolve-RepoPath -Path $BaselinePackage
$currentPath = Resolve-RepoPath -Path $CurrentPackage
$outputFile = Resolve-RepoPath -Path $OutputPath
$evidenceDirectory = Resolve-RepoPath -Path $EvidenceRoot
foreach ($required in @($baselinePath, $currentPath)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Package not found: $required" }
}
if (-not $SkipExecution -and ([string]::IsNullOrWhiteSpace($FactorioBin) -or -not (Test-Path -LiteralPath $FactorioBin -PathType Leaf))) {
  throw "Factorio binary is required to export approved-delta runtime evidence."
}
$actualBaselineSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $baselinePath).Hash
if ($actualBaselineSha -ne $ExpectedBaselineSha256) {
  throw "Baseline archive hash differs. Expected $ExpectedBaselineSha256 actual $actualBaselineSha"
}
$currentSourceCommit = (& git -C $repo rev-parse HEAD).Trim()
if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) {
  throw "Approved-delta export requires -ExpectedSourceCommit for the candidate package source authority."
}
if ($currentSourceCommit -ne $ExpectedSourceCommit -or (Test-MIRPackageSourceGitDirty -RepoRoot $repo)) {
  throw "Approved-delta exporter source differs. Expected $ExpectedSourceCommit actual $currentSourceCommit"
}
$releaseLedger = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\releases.json") | ConvertFrom-Json
$releaseAuthority = $releaseLedger.development."factorio-2.1"
$packageSourceCommit = [string]$releaseAuthority.package_source_commit
if ($packageSourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "Approved-delta export requires the canonical C11 package-source commit."
}
& git -C $repo merge-base --is-ancestor $packageSourceCommit $currentSourceCommit
if ($LASTEXITCODE -ne 0) {
  throw "Approved-delta package-source commit is not an ancestor of the qualification source."
}
[string[]]$packageRoots = @(Get-MIRPackageSourceRoots)
& git -C $repo diff --quiet $packageSourceCommit $currentSourceCommit -- @packageRoots
if ($LASTEXITCODE -ne 0) {
  throw "Package-visible source changed after the approved-delta package-source commit."
}

$scenarioNames = @(
  "approved-delta-automatic-family-controls",
  "approved-delta-base",
  "approved-delta-base-continuations",
  "approved-delta-compat-atan",
  "approved-delta-compat-space-age-galore",
  "approved-delta-native-owner-adoption",
  "approved-delta-space-age"
)
$snapshots = [ordered]@{baseline=[ordered]@{}; current=[ordered]@{}}
foreach ($line in @(
  [pscustomobject]@{label="baseline"; path=$baselinePath},
  [pscustomobject]@{label="current"; path=$currentPath}
)) {
  foreach ($scenario in $scenarioNames) {
    $rawPath = Join-Path $evidenceDirectory ("raw\$($line.label)\$scenario.json")
    $snapshots[$line.label][$scenario] = if ($SkipExecution) {
      if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) { throw "Raw export is absent: $rawPath" }
      $rawEvidence = Get-Content -Raw -LiteralPath $rawPath | ConvertFrom-Json
      $expectedPackageSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $line.path).Hash
      $expectedProducerSha = Get-ApprovedDeltaProducerFingerprint
      if ($rawEvidence.schema -ne 1 -or $rawEvidence.kind -ne "mir-approved-delta-raw-evidence" -or
        $rawEvidence.scenario -ne $scenario -or $rawEvidence.package_sha256 -ne $expectedPackageSha -or
        $rawEvidence.producer_sha256 -ne $expectedProducerSha) {
        throw "Raw export does not bind the exact scenario and package: $rawPath"
      }
      $rawEvidence.runtime_export
    } else {
      Invoke-ApprovedDeltaScenario -PackagePath $line.path -Label $line.label -Scenario $scenario -RawOutputPath $rawPath
    }
  }
}

$baselineContract = Get-PackageContract -PackagePath $baselinePath
$currentContract = Get-PackageContract -PackagePath $currentPath
if ($currentContract.package_content_sha256 -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
  throw "Approved-delta current package content does not match ExpectedSourceCommit package source."
}
if ([string]$releaseAuthority.archive_sha256 -ne $currentContract.archive_sha256 -or
    [string]$releaseAuthority.package_content_sha256 -ne $currentContract.package_content_sha256 -or
    [string]$releaseAuthority.package_source_sha256 -ne $currentContract.package_content_sha256) {
  throw "Approved-delta current package does not match the canonical C11 release authority."
}
$rawDifferences = [Collections.Generic.List[object]]::new()
Add-ValueDifferences -Results $rawDifferences -Path "package" -Before $baselineContract -After $currentContract
foreach ($scenario in $scenarioNames) {
  Add-ValueDifferences -Results $rawDifferences -Path "scenarios.$scenario" `
    -Before $snapshots.baseline[$scenario] -After $snapshots.current[$scenario]
}

$differences = @()
foreach ($difference in @($rawDifferences | Sort-Object path)) {
  $disposition = Get-DifferenceDisposition -Path $difference.path -Before $difference.before -After $difference.after
  $beforeValue = $difference.before
  $afterValue = $difference.after
  if ($difference.path -like "*.mod_data_contracts.more-infinite-research-generation-plan.contract_shape.fields.rows.value_shapes") {
    $beforeValue = Get-RowShapeSummary -Value $beforeValue
    $afterValue = Get-RowShapeSummary -Value $afterValue
  }
  $differences += [pscustomobject][ordered]@{
    field = $difference.path
    before = $beforeValue
    after = $afterValue
    reason = $disposition.reason
    intentional = $disposition.intentional
    migration_impact = $disposition.migration_impact
    required_evidence = $disposition.required_evidence
  }
}

$scenarioEvidence = @()
foreach ($scenario in $scenarioNames) {
  $before = $snapshots.baseline[$scenario]
  $after = $snapshots.current[$scenario]
  $scenarioDifferences = @($differences | Where-Object field -like "scenarios.$scenario.*")
  $technologyDifferences = @($scenarioDifferences | Where-Object field -like "*.technologies.*")
  $scenarioEvidence += [pscustomobject][ordered]@{
    scenario = $scenario
    baseline_fingerprint = Get-ValueFingerprint -Value $before
    current_fingerprint = Get-ValueFingerprint -Value $after
    baseline_technology_count = @($before.technology_ids).Count
    current_technology_count = @($after.technology_ids).Count
    difference_count = $scenarioDifferences.Count
    technology_difference_count = $technologyDifferences.Count
  }
}

$unapproved = @($differences | Where-Object intentional -eq $false)
$output = [pscustomobject][ordered]@{
  schema = 1
  kind = "mir-approved-delta"
  baseline = [ordered]@{
    version = $baselineContract.version
    source_commit = "79df29b50ea9b855b8665d6c9a3d8295806acde0"
    archive_sha256 = $baselineContract.archive_sha256
    package_content_sha256 = $baselineContract.package_content_sha256
  }
  current = [ordered]@{
    version = $currentContract.version
    source_commit = $packageSourceCommit
    package_source_commit = $packageSourceCommit
    archive_sha256 = $currentContract.archive_sha256
    package_content_sha256 = $currentContract.package_content_sha256
  }
  exporter = [ordered]@{
    fixture = "fixtures/export-approved-delta"
    script = "scripts/Export-MIRApprovedDelta.ps1"
    qualification_source_commit = $currentSourceCommit
    producer_sha256 = Get-ApprovedDeltaProducerFingerprint
    factorio_binary_version = if ($SkipExecution) { "reused-raw-evidence" } else { [Diagnostics.FileVersionInfo]::GetVersionInfo($FactorioBin).FileVersion }
    scenarios = $scenarioNames
  }
  scenario_evidence = $scenarioEvidence
  differences = $differences
  summary = [ordered]@{
    difference_count = $differences.Count
    intentional_count = @($differences | Where-Object intentional -eq $true).Count
    unapproved_count = $unapproved.Count
    status = if ($unapproved.Count -eq 0) { "approved" } else { "review-required" }
  }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFile) | Out-Null
$output | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $outputFile -Encoding UTF8
Write-Host "[ok] wrote MIR approved delta $outputFile differences=$($differences.Count) unapproved=$($unapproved.Count)"
if ($unapproved.Count -gt 0) {
  $unapproved | Select-Object -First 30 field,reason | Format-Table -AutoSize
}
