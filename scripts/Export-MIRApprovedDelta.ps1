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
    $identity = Get-MIRFileContentIdentity -Path $path -RelativePath $relative
    $rows += "$relative=$([string]$identity.Sha256)"
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
  # Keep the engine's write-data root inside a short governed workspace path.
  # Some Windows hosts deny Factorio access to user temp, while long scenario
  # paths can make Factorio 2.0 silently miss a fixture's data-stage file.
  $tempRoot = Join-Path $repo ("artifacts\ad-runs\" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
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

function Test-ExactTechnologyCatalogContractAddition {
  param(
    [Parameter(Mandatory)][string]$Path,
    $Before,
    $After
  )

  if ($null -ne $Before -or
      $Path -notmatch '^scenarios\.[^.]+\.mod_data_contracts\.(?<catalog>more-infinite-research-technology-catalog(?:-internal)?)$' -or
      [string]$After.contract_shape.kind -ne "object") {
    return $false
  }

  $actualFields = @($After.contract_shape.fields.PSObject.Properties.Name | Sort-Object)
  if ($Matches.catalog -eq "more-infinite-research-technology-catalog") {
    $expectedFields = @(
      "catalog_fingerprint", "counts", "kind", "provider_summary", "public_fingerprint",
      "reason_histogram", "samples", "schema", "selected", "technology_catalog_schema", "truncation"
    ) | Sort-Object
    return [string]$After.data_type -eq "more-infinite-research.technology-catalog-public" -and
      [int]$After.schema -eq 1 -and
      ($actualFields -join "|") -eq ($expectedFields -join "|")
  }

  $expectedFields = @(
    "alternative_qualifications", "base_candidates", "candidate_catalog_fingerprint", "candidates",
    "catalog_fingerprint", "compilation_plan_fingerprint", "context_fingerprint", "current_selections",
    "generation_plan_fingerprint", "mutation_authority", "phase", "preselection_catalog_fingerprint",
    "qualification_catalog_fingerprint", "qualifications", "schema", "selection_authority",
    "selection_fingerprint"
  ) | Sort-Object
  return [string]$After.data_type -eq "more-infinite-research.technology-catalog-v3-internal" -and
    [int]$After.schema -eq 3 -and
    ($actualFields -join "|") -eq ($expectedFields -join "|")
}

function Test-ExactBackportSettingDifference {
  param([string]$Path, $Before, $After)

  if ($Path -match '^scenarios\.[^.]+\.settings\.(?<setting>ips-(?<field>cost-base|cost-growth|effect-per-level|enable|max-level|research-time)-(?<stream>research_capture_robot_rockets|research_nutrients))$') {
    $expected = @{
      'cost-base' = @{ type = 'number'; value = 8000 }
      'cost-growth' = @{ type = 'number'; value = 2 }
      'effect-per-level' = @{ type = 'number'; value = 10 }
      'enable' = @{ type = 'boolean'; value = $true }
      'max-level' = @{ type = 'number'; value = 0 }
      'research-time' = @{ type = 'number'; value = 60 }
    }[$Matches.field]
    return $null -eq $Before -and [string]$After.value_type -eq $expected.type -and
      $After.current_value -eq $expected.value -and @($After.PSObject.Properties.Name).Count -eq 2
  }
  if ($Path -match '^scenarios\.[^.]+\.settings\.(ips-enable-research_spoilage_preservation|mir-enable-inserter-capacity-bonus)\.current_value$') {
    return $Before -eq $false -and $After -eq $true
  }
  return $false
}

function Test-ExactBackportRegistryAddition {
  param([string]$Path, $Before, $After)

  if ($null -ne $Before -or $Path -notmatch '^scenarios\.(?<scenario>[^.]+)\.generated_registry\.(?<name>[^.]+)$') { return $false }
  $expected = @{
    'inserter-capacity-bonus-8' = @{ kind = 'base_extension'; key = 'inserter-capacity-bonus' }
    'recipe-prod-research_capture_robot_rockets-1' = @{ kind = 'stream'; key = 'research_capture_robot_rockets' }
    'recipe-prod-research_nutrients-1' = @{ kind = 'stream'; key = 'research_nutrients' }
    'recipe-prod-research_spoilage_preservation-1' = @{ kind = 'stream'; key = 'research_spoilage_preservation' }
  }[$Matches.name]
  if ($null -eq $expected) { return $false }
  if ($Matches.name -ne 'inserter-capacity-bonus-8' -and $Matches.scenario -notin @(
      'approved-delta-compat-space-age-galore', 'approved-delta-native-owner-adoption', 'approved-delta-space-age')) { return $false }
  return [string]$After.name -eq $Matches.name -and [string]$After.kind -eq $expected.kind -and
    [string]$After.key -eq $expected.key -and @($After.PSObject.Properties.Name).Count -eq 3
}

function Test-ExactBackportTechnologyAddition {
  param([string]$Path, $Before, $After)

  if ($null -ne $Before -or $Path -notmatch '^scenarios\.(?<scenario>[^.]+)\.technologies\.(?<name>[^.]+)$') { return $false }
  $hash = Get-TextSha256 -Text (Get-CanonicalJson -Value $After)
  if ($Matches.name -eq 'inserter-capacity-bonus-8') {
    $expected = if ($Matches.scenario -in @(
      'approved-delta-compat-space-age-galore', 'approved-delta-native-owner-adoption', 'approved-delta-space-age')) {
      'B1486F405DED05DD05F8A90FD5CDE0558E570C8691AC58C892E6F1E136F0DBE6'
    } else {
      '974F990F706CD1FD7264BB4F19C89CEDFD4431EA388AB11D226B4B22D94F892B'
    }
    return $hash -eq $expected
  }
  if ($Matches.scenario -notin @(
      'approved-delta-compat-space-age-galore', 'approved-delta-native-owner-adoption', 'approved-delta-space-age')) { return $false }
  $expectedHashes = @{
    'recipe-prod-research_capture_robot_rockets-1' = '3C8275FE50D8CCCF025A7059616EA3690D4AE9EB3D82CE19521D71632939078A'
    'recipe-prod-research_nutrients-1' = 'A6F74FF94EEA1B3AA4C5E38615E06300566387902B37086E1DEC286D5B77204B'
    'recipe-prod-research_spoilage_preservation-1' = '8A2DCBA105609A72D7555AD9910AAC10B942C3E5F9288054EB9533AA8E71D6D4'
  }
  return $expectedHashes.ContainsKey($Matches.name) -and $hash -eq $expectedHashes[$Matches.name]
}

function Test-ExactBackportTechnologyIdentityAddition {
  param([string]$Path, $Before, $After)

  if ($Path -notmatch '^scenarios\.(?<scenario>[^.]+)\.technology_ids$') { return $false }
  $expected = @('inserter-capacity-bonus-8')
  if ($Matches.scenario -in @(
      'approved-delta-compat-space-age-galore', 'approved-delta-native-owner-adoption', 'approved-delta-space-age')) {
    $expected += @(
      'recipe-prod-research_capture_robot_rockets-1',
      'recipe-prod-research_nutrients-1',
      'recipe-prod-research_platform-1',
      'recipe-prod-research_spoilage_preservation-1'
    )
  }
  $beforeValues = @($Before | ForEach-Object { [string]$_ })
  $afterValues = @($After | ForEach-Object { [string]$_ })
  $added = @($afterValues | Where-Object { $beforeValues -notcontains $_ } | Sort-Object)
  $removed = @($beforeValues | Where-Object { $afterValues -notcontains $_ })
  return $removed.Count -eq 0 -and ($added -join '|') -eq (@($expected | Sort-Object) -join '|')
}

function Test-ExactP11PlatformSettingAddition {
  param([string]$Path, $Before, $After)

  if ($null -ne $Before -or
      $Path -notmatch '^scenarios\.(?<scenario>[^.]+)\.settings\.ips-(?<field>cost-base|cost-growth|effect-per-level|enable|max-level|research-time)-research_platform$' -or
      $Matches.scenario -notin @(
        'approved-delta-automatic-family-controls', 'approved-delta-base',
        'approved-delta-base-continuations', 'approved-delta-compat-atan',
        'approved-delta-compat-space-age-galore', 'approved-delta-native-owner-adoption',
        'approved-delta-space-age')) {
    return $false
  }
  $expected = @{
    'cost-base' = @{ type = 'number'; value = 8000 }
    'cost-growth' = @{ type = 'number'; value = 2 }
    'effect-per-level' = @{ type = 'number'; value = 10 }
    'enable' = @{ type = 'boolean'; value = $true }
    'max-level' = @{ type = 'number'; value = 0 }
    'research-time' = @{ type = 'number'; value = 60 }
  }[$Matches.field]
  return [string]$After.value_type -eq $expected.type -and
    $After.current_value -eq $expected.value -and @($After.PSObject.Properties.Name).Count -eq 2
}

function Test-ExactP11PlatformRegistryAddition {
  param([string]$Path, $Before, $After)

  if ($null -ne $Before -or
      $Path -notmatch '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.generated_registry\.recipe-prod-research_platform-1$') {
    return $false
  }
  return [string]$After.name -eq 'recipe-prod-research_platform-1' -and
    [string]$After.kind -eq 'stream' -and [string]$After.key -eq 'research_platform' -and
    @($After.PSObject.Properties.Name).Count -eq 3
}

function Test-ExactP11PlatformTechnologyAddition {
  param([string]$Path, $Before, $After)

  if ($null -ne $Before -or
      $Path -notmatch '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.technologies\.recipe-prod-research_platform-1$') {
    return $false
  }
  return (Get-TextSha256 -Text (Get-CanonicalJson -Value $After)) -eq
    '56C55DB207F8F98DB890EE61305DF9505DBBB34D39237DCAEE86792D6BDB87A9'
}

function Test-ExactP11IceCryogenicProgression {
  param([string]$Path, $Before, $After)

  if ($Path -notmatch '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.technologies\.recipe-prod-research_ice-1\.(?<field>prerequisites|science_ingredients)$') {
    return $false
  }
  $expected = if ($Matches.field -eq 'prerequisites') {
    @{
      before = '914EA9D35CFFBA28CA6BDD71C9D902A9C4D1A0F0EAE78290BFC2A42A931927FA'
      after = 'FA7E140331E84C21C2CED61C21DDD3AAFC9769D4C7C2CAE11FEF895B5C1A8FE0'
    }
  } else {
    @{
      before = '25C4CBD4F9A8ADBCE69287662D34C0530D1BCCB627FF1E24EA5FE5F9552211B0'
      after = 'D31E32A1C2B021B35CB37AE8F861F9BD80D97BDB82FCE2712E7B848C3E22142D'
    }
  }
  return (Get-TextSha256 -Text (Get-CanonicalJson -Value $Before)) -eq $expected.before -and
    (Get-TextSha256 -Text (Get-CanonicalJson -Value $After)) -eq $expected.after
}

function Test-ExactP11StructuralBeltsExpansion {
  param([string]$Path, $Before, $After)

  if ($Path -ne 'scenarios.approved-delta-automatic-family-controls.technologies.recipe-prod-research_belts-1.effects') {
    return $false
  }
  return (Get-TextSha256 -Text (Get-CanonicalJson -Value $Before)) -eq
      'FB22FADC4B630F12E98DF57AFE9F7606BBCCB68DCBA44F8BDFD62B3BF2BDB112' -and
    (Get-TextSha256 -Text (Get-CanonicalJson -Value $After)) -eq
      '3DF8EAC7FEF97A62F17C3FBF51C7719237B6D9AE3DA16D93F05F092EFAEA4486'
}

function Test-ExactBackportBreedingExpansion {
  param([string]$Path, $Before, $After)

  if ($Path -notmatch '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.technologies\.recipe-prod-research_breeding-1\.effects\.(?<field>change|recipe|type)$' -or $null -ne $After) { return $false }
  return ($Matches.field -eq 'change' -and [double]$Before -eq 0.1) -or
    ($Matches.field -eq 'recipe' -and [string]$Before -eq 'biter-egg') -or
    ($Matches.field -eq 'type' -and [string]$Before -eq 'change-recipe-productivity')
}

function Test-ExactBackportLandfillExpansion {
  param([string]$Path, $Before, $After)

  if ($Path -notmatch '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.technologies\.recipe-prod-research_landfill-1\.effects$') { return $false }
  return (Get-TextSha256 -Text (Get-CanonicalJson -Value $Before)) -eq '7AF5B974AC7742708F15D8E1AE01348BCC43B313B83ED0DC1478E4E33403976B' -and
    (Get-TextSha256 -Text (Get-CanonicalJson -Value $After)) -eq 'D76029747337E24523D9CE9431592BCBB9B093CF06B62ECC537E1F1304DC5A61'
}

function Test-ExactBackportAdoptionShapeCleanup {
  param([string]$Path, $Before, $After)

  if ($Path -notmatch '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.mod_data_contracts\.more-infinite-research-productivity-family-adoption\.contract_shape\.fields\.bindings\.item_shapes\.fields\.legacy_output_unit$' -or $null -ne $After) { return $false }
  return (Get-CanonicalJson -Value $Before) -eq '{"kind":"object","fields":{"count_formula":"string","ingredients":{"kind":"table","bounded":true},"time":"number"}}'
}

function Get-MIR255DifferenceDisposition {
  param([string]$Path, $Before, $After)

  $evidence = @("exact 2.5.0 to 2.5.5 runtime delta", "2.5.0 direct-upgrade matrix", "2.5.5 target disposition ledger")
  if ($Path -eq 'package.version' -and [string]$Before -eq '2.5.0' -and [string]$After -eq '2.5.5') {
    return [ordered]@{ reason='The package version advances from the published 2.5.0 predecessor to 2.5.5.'; intentional=$true; migration_impact='Factorio performs the governed direct package upgrade.'; required_evidence=$evidence }
  }
  if ($Path -eq 'package.archive_sha256' -and [string]$Before -eq '65C1610BAE120F135E328583899672E3636EAAD6D946DF104FD045B2D9AB10F1' -and [string]$After -eq '03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C') {
    return [ordered]@{ reason='The archive identity changes to the deterministic 2.5.5 P12 package.'; intentional=$true; migration_impact='Package custody changes; semantic differences are classified separately.'; required_evidence=$evidence }
  }
  if ($Path -eq 'package.package_content_sha256' -and [string]$Before -eq '5BBE4D09FD4F65D8A91D2F4AF1664D1C68B846288B9BEF7858162F3F156158F1' -and [string]$After -eq '047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154') {
    return [ordered]@{ reason='The normalized package content advances to the exact 2.5.5 projection.'; intentional=$true; migration_impact='All behavioral differences remain independently classified.'; required_evidence=$evidence }
  }
  if ($Path -match '^package\.(runtime_source_fingerprints\.prototypes/mir/runtime/productivity_family_adoption\.lua|settings_source_fingerprints\.prototypes/mir/settings/(catalog|cost_contract|defaults|registry|stage_builder)\.lua)$' -and
      ($null -eq $Before -or [string]$Before -match '^[0-9A-F]{64}$') -and [string]$After -match '^[0-9A-F]{64}$') {
    return [ordered]@{ reason='The governed cost contract and target adoption adapter sources advance to the 3.2.5 semantic projection.'; intentional=$true; migration_impact='Unified cost behavior and the target-2.0 compiled-out adoption boundary are verified separately.'; required_evidence=$evidence }
  }
  if ($Path -match '^scenarios\.[^.]+\.active_mods\.more-infinite-research$' -and [string]$Before -eq '2.5.0' -and [string]$After -eq '2.5.5') {
    return [ordered]@{ reason='The scenario binds the exact predecessor and candidate package versions.'; intentional=$true; migration_impact='Package version transition only.'; required_evidence=$evidence }
  }
  $removedContracts = @(
    'more-infinite-research-compiler-evidence', 'more-infinite-research-compiler-evidence-internal',
    'more-infinite-research-coverage-report', 'more-infinite-research-coverage-report-internal',
    'more-infinite-research-generation-plan', 'more-infinite-research-generation-plan-internal',
    'more-infinite-research-productivity-family-adoption', 'more-infinite-research-technology-catalog',
    'more-infinite-research-technology-catalog-internal'
  )
  if ($Path -match '^scenarios\.[^.]+\.mod_data_contracts\.(?<contract>[^.]+)$' -and
      $removedContracts -contains $Matches.contract -and $null -ne $Before -and $null -eq $After) {
    return [ordered]@{ reason='Factorio 2.0 uses the bounded log/report adapter and emits no unsupported mod-data contract.'; intentional=$true; migration_impact='Diagnostics move to the documented target log transport; save and prototype identities are unaffected.'; required_evidence=@('target log/report transport fixture', 'target profile compiled-out assertion', 'exact 2.5.0 to 2.5.5 runtime delta') }
  }
  if ($Path -match '^scenarios\.[^.]+\.settings\.ips-cost-linear-increment-research_[a-z0-9_]+$' -and
      $null -eq $Before -and [string]$After.value_type -eq 'number' -and [double]$After.current_value -eq 0) {
    return [ordered]@{ reason='2.5.5 adds the neutral-default linear cost increment setting for every governed research stream.'; intentional=$true; migration_impact='Existing exponential behavior is unchanged until a player selects a non-zero linear increment.'; required_evidence=@('unified cost-model static proof', 'all sixteen curve transitions', '2.5.0 direct-upgrade matrix') }
  }
  $nativeLinearSettings = @(
    'mir-cost-linear-increment-braking-force', 'mir-cost-linear-increment-inserter-capacity-bonus',
    'mir-cost-linear-increment-laser-shooting-speed', 'mir-cost-linear-increment-research-speed',
    'mir-cost-linear-increment-weapon-shooting-speed', 'mir-cost-linear-increment-worker-robots-storage'
  )
  if ($Path -match '^scenarios\.[^.]+\.settings\.(?<setting>mir-cost-linear-increment-[a-z0-9-]+)$' -and
      $nativeLinearSettings -contains $Matches.setting -and $null -eq $Before -and
      [string]$After.value_type -eq 'number' -and [double]$After.current_value -eq 0) {
    return [ordered]@{ reason='2.5.5 adds the neutral-default linear cost increment for each governed native infinite research.'; intentional=$true; migration_impact='Native continuation costs retain the predecessor curve until explicitly configured.'; required_evidence=@('native cost contract fixture', 'all sixteen curve transitions', 'configuration-change progress preservation') }
  }
  $formulaRows = [ordered]@{
    'braking-force-8' = @('115*1.33333^(L-1)', '861.51212960553*1.33333^(L-8)')
    'inserter-capacity-bonus-8' = @('200*3.33333^(L-1)', '914488.340211249*3.33333^(L-8)')
    'laser-shooting-speed-8' = @('60*1.5^(L-1)', '1025.15625*1.5^(L-8)')
    'research-speed-7' = @('60*1.5^(L-1)', '683.4375*1.5^(L-7)')
    'weapon-shooting-speed-7' = @('60*1.5^(L-1)', '683.4375*1.5^(L-7)')
    'worker-robots-storage-4' = @('200*1.5^(L-1)', '675*1.5^(L-4)')
  }
  if ($Path -match '^scenarios\.[^.]+\.technologies\.(?<technology>[^.]+)\.count_formula$' -and
      $formulaRows.Contains($Matches.technology)) {
    $expected = $formulaRows[$Matches.technology]
    if ([string]$Before -eq $expected[0] -and [string]$After -eq $expected[1]) {
      return [ordered]@{ reason='2.5.5 rebases the native continuation formula at its controlled anchor while preserving the exact historical coefficient.'; intentional=$true; migration_impact='Completed science-unit work and continuation progression are preserved across configuration change and reload.'; required_evidence=@('native cost contract fixture', 'configuration-change progress preservation', 'first and second reload proof') }
    }
  }
  $nativeOwners = @('low-density-structure-productivity','plastic-bar-productivity','processing-unit-productivity','rocket-fuel-productivity','steel-plate-productivity')
  if ($Path -match '^scenarios\.(approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.technologies\.(?<owner>[^.]+)$' -and
      $nativeOwners -contains $Matches.owner -and $null -ne $Before -and [string]$Before.name -eq $Matches.owner -and $null -eq $After) {
    return [ordered]@{ reason='The Factorio 2.0 target compiles out modern productivity-family adoption instead of mutating an external native owner.'; intentional=$true; migration_impact='Unsupported adoption is omitted; governed MIR-owned replacements appear only in the explicit adoption fixture.'; required_evidence=@('target profile adoption exclusion', 'native-owner fixture', 'one-owner invariant') }
  }
  $replacementKeys = @('low_density_structure','plastic','processing_unit','rocket_fuel','steel')
  if ($Path -match '^scenarios\.approved-delta-native-owner-adoption\.technologies\.recipe-prod-research_(?<key>[a-z_]+)-1$' -and
      $replacementKeys -contains $Matches.key -and $null -eq $Before -and
      [string]$After.name -eq "recipe-prod-research_$($Matches.key)-1" -and
      [string]$After.count_formula -eq '8000*2^(L-1)' -and [string]$After.maximum_level -eq 'infinite' -and $After.upgrade -eq $true) {
    return [ordered]@{ reason='With adoption compiled out, the explicit target fixture receives the exact governed MIR-owned productivity stream.'; intentional=$true; migration_impact='Stable MIR identities replace unsupported external-owner adoption without duplicate ownership.'; required_evidence=@('native-owner fixture', 'generated registry integrity', 'one-owner invariant') }
  }
  if ($Path -match '^scenarios\.approved-delta-native-owner-adoption\.generated_registry\.recipe-prod-research_(?<key>[a-z_]+)-1$' -and
      $replacementKeys -contains $Matches.key -and $null -eq $Before -and
      [string]$After.name -eq "recipe-prod-research_$($Matches.key)-1" -and [string]$After.key -eq "research_$($Matches.key)" -and [string]$After.kind -eq 'stream') {
    return [ordered]@{ reason='The target registry records the exact stable MIR-owned replacement identity.'; intentional=$true; migration_impact='No existing MIR stable identity is renamed or reused.'; required_evidence=@('generated registry integrity', 'stable-ID inventory', 'native-owner fixture') }
  }
  if ($Path -match '^scenarios\.(?<scenario>approved-delta-compat-space-age-galore|approved-delta-native-owner-adoption|approved-delta-space-age)\.technology_ids$') {
    $beforeIds = @($Before | ForEach-Object { [string]$_ })
    $afterIds = @($After | ForEach-Object { [string]$_ })
    $removed = @($beforeIds | Where-Object { $afterIds -notcontains $_ } | Sort-Object)
    $added = @($afterIds | Where-Object { $beforeIds -notcontains $_ } | Sort-Object)
    $expectedRemoved = @($nativeOwners | Sort-Object)
    $expectedAdded = if ($Matches.scenario -eq 'approved-delta-native-owner-adoption') {
      @($replacementKeys | ForEach-Object { "recipe-prod-research_$($_)-1" } | Sort-Object)
    } else { @() }
    if (($removed -join '|') -eq ($expectedRemoved -join '|') -and ($added -join '|') -eq ($expectedAdded -join '|')) {
      return [ordered]@{ reason='The exact technology identity set reflects the target-2.0 adoption omission and governed replacement policy.'; intentional=$true; migration_impact='Only the five explicitly classified owner identities change; all other stable IDs remain fixed.'; required_evidence=@('exact technology identity delta', 'target omission inventory', 'native-owner fixture') }
    }
  }
  return $null
}

function Get-DifferenceDisposition {
  param(
    [Parameter(Mandatory)][string]$Path,
    $Before,
    $After
  )
  if ($script:IsFactorio20DotFiveReleaseDelta) {
    $mir255Disposition = Get-MIR255DifferenceDisposition -Path $Path -Before $Before -After $After
    if ($null -ne $mir255Disposition) { return $mir255Disposition }
  }
  if ($script:IsFactorio20TerminalShadowDelta) {
    $evidence = @(
      "exact 2.5.5 to 2.5.9 runtime delta",
      "MIR3TerminalProductAdmissionBundleV1",
      "2.5.9 shadow package manifest"
    )
    if ($Path -eq 'package.version' -and [string]$Before -eq '2.5.5' -and [string]$After -eq '2.5.9') {
      return [ordered]@{ reason='The package version advances from immutable 2.5.5 to the unfrozen 2.5.9 terminal shadow.'; intentional=$true; migration_impact='Factorio performs the governed direct package upgrade; candidate allocation remains forbidden at this phase.'; required_evidence=$evidence }
    }
    if ($Path -eq 'package.archive_sha256' -and
        [string]$Before -eq '03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C' -and
        [string]$After -eq [string]$script:TerminalShadowArchiveSha256) {
      return [ordered]@{ reason='The archive identity advances from immutable 2.5.5 to the exact current 2.5.9 development shadow.'; intentional=$true; migration_impact='Development package custody changes; all semantic differences remain independently classified.'; required_evidence=$evidence }
    }
    if ($Path -eq 'package.package_content_sha256' -and
        [string]$Before -eq '047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154' -and
        [string]$After -eq [string]$script:TerminalShadowContentSha256) {
      return [ordered]@{ reason='The normalized package identity advances to the exact current 2.5.9 development shadow.'; intentional=$true; migration_impact='Package content changes only within the admitted target projection; every observed semantic row remains independently classified.'; required_evidence=$evidence }
    }
    $terminalScenarios = @(
      'approved-delta-automatic-family-controls',
      'approved-delta-base',
      'approved-delta-base-continuations',
      'approved-delta-compat-atan',
      'approved-delta-compat-space-age-galore',
      'approved-delta-native-owner-adoption',
      'approved-delta-space-age'
    )
    foreach ($scenario in $terminalScenarios) {
      if ($Path -eq "scenarios.$scenario.active_mods.more-infinite-research" -and
          [string]$Before -eq '2.5.5' -and [string]$After -eq '2.5.9') {
        return [ordered]@{
          reason = 'The exact scenario reports the governed MIR package version transition and no normalized semantic change.'
          intentional = $true
          migration_impact = 'Mod identity advances to 2.5.9; the scenario technology, prerequisite, setting, registry, and mod-data projections remain byte-equivalent after normalization.'
          required_evidence = @('fourteen exact Factorio 2.0.77 loads', 'zero technology differences', '2.5.9 shadow package manifest')
        }
      }
    }
    return [ordered]@{
      reason = "Unreviewed 2.5.9 terminal-shadow normalized difference."
      intentional = $false
      migration_impact = "Unknown until independently classified against the admitted route-policy delta."
      required_evidence = @("maintainer classification", "exact 2.5.5 to 2.5.9 runtime delta", "generated-prerequisite-safety")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactP11PlatformSettingAddition -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "P11 carries the exact governed Platform Productivity setting surface in every target-2.0 delta environment."
      intentional = $true
      migration_impact = "The new Space Age-only stream uses the standard reviewed defaults without changing existing setting identities."
      required_evidence = @("P11 settings schema and locale gates", "Space Age platform progression fixture", "exact 2.0 runtime delta")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactP11PlatformRegistryAddition -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "P11 registers the one stable Platform Productivity stream identity only in the exact Space Age environments."
      intentional = $true
      migration_impact = "Existing identities remain unchanged; Space Age saves gain one new unresearched Aquilo-gated technology."
      required_evidence = @("generated identity registry", "Platform owner-transfer fixture", "2.4.9 upgrade matrix")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactP11PlatformTechnologyAddition -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "P11 adds the exact Space Age Platform Productivity technology with 10% ice-platform and 5% space-platform-foundation effects."
      intentional = $true
      migration_impact = "Platform ownership moves from Landfill to a separate unresearched cryogenic-gated identity; Landfill and Ice research levels are retained."
      required_evidence = @("exact Platform technology contract", "owner-transfer and upgrade assertions", "exact 2.0 runtime delta")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactP11IceCryogenicProgression -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "P11 adds cryogenic science to the final emitted Ice Productivity prerequisites and science ingredients."
      intentional = $true
      migration_impact = "Completed Ice levels and current progress remain; continuing research now respects Aquilo progression."
      required_evidence = @("final emitted science invariant", "accepting-lab and researchability checks", "2.4.9 upgrade matrix")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactP11StructuralBeltsExpansion -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "P11 attaches the exact opaque-name belt fixture through the conservative structural fallback at 0.5% per level."
      intentional = $true
      migration_impact = "Known reviewed belt tiers retain precedence; eligible unknown belt-family recipes gain the conservative fallback."
      required_evidence = @("semantic family attachment fixture", "disabled automatic-productivity regression", "native AdvancedBeltsSA gate")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportSettingDifference -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 adds exact settings for nutrients and capture-robot-rocket productivity and default-enables the reviewed disruptive continuations."
      intentional = $true
      migration_impact = "New settings use reviewed defaults; spoilage preservation and inserter capacity remain classified and tooltip-warned as disruptive."
      required_evidence = @("settings schema and locale gates", "default-enablement fixtures", "exact 2.0 runtime delta")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportRegistryAddition -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 registers the exact reviewed inserter, nutrients, capture-robot-rocket, and spoilage identities."
      intentional = $true
      migration_impact = "Stable generated identities are added without renaming or removing existing 2.4.9 identities."
      required_evidence = @("generated identity registry", "2.4.9 upgrade matrix", "exact 2.0 runtime delta")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportTechnologyAddition -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 adds exact reviewed infinite technologies for inserter capacity and supported Space Age production families."
      intentional = $true
      migration_impact = "Existing saves receive stable new infinite technologies under the documented default and risk policy."
      required_evidence = @("technology contract fixtures", "2.4.9 upgrade matrix", "exact 2.0 runtime delta")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportTechnologyIdentityAddition -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 extends the normalized technology identity set by only the exact reviewed additions."
      intentional = $true
      migration_impact = "No 2.4.9 technology identity is removed or renamed."
      required_evidence = @("exact identity-set delta", "generated identity registry", "upgrade matrix")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportBreedingExpansion -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 expands breeding productivity from biter eggs to the exact reviewed biter-egg, fish-breeding, and pentapod-egg set."
      intentional = $true
      migration_impact = "The existing breeding identity is retained while two supported forward-production effects are added."
      required_evidence = @("exact Space Age breeding fixture", "effect-target integrity", "approved-delta scenario fingerprints")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportLandfillExpansion -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 adds exact 2% ice-platform and 1% space-platform-foundation effects to landfill/foundation productivity."
      intentional = $true
      migration_impact = "The existing landfill and foundation effects remain unchanged and two reviewed Space Age targets are appended."
      required_evidence = @("landfill/foundation exact-effect fixture", "effect-target integrity", "exact 2.0 runtime delta")
    }
  }
  if ($script:IsFactorio20BackportDelta -and (Test-ExactBackportAdoptionShapeCleanup -Path $Path -Before $Before -After $After)) {
    return [ordered]@{
      reason = "2.5 removes the obsolete legacy_output_unit diagnostic field from the target-2.0 adoption contract shape."
      intentional = $true
      migration_impact = "Compiler behavior and save identity are unchanged; diagnostic consumers use the canonical target-neutral binding fields."
      required_evidence = @("compiler contract gate", "target-profile parity", "exact 2.0 runtime delta")
    }
  }
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
  if (Test-ExactTechnologyCatalogContractAddition -Path $Path -Before $Before -After $After) {
    return [ordered]@{
      reason = "3.2 adds bounded public and explicit internal TechnologyCatalog evidence contracts."
      intentional = $true
      migration_impact = "Diagnostic consumers may read the bounded public schema; complete internal catalog data remains an explicit diagnostics surface and save identity is unaffected."
      required_evidence = @("technology lifecycle schema gate", "public artifact budget gate", "compiler-contracts", "catalog publication reference")
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
$currentContract = Get-PackageContract -PackagePath $currentPath
$baselineContract = Get-PackageContract -PackagePath $baselinePath
if ($baselineContract.factorio_version -ne $currentContract.factorio_version) {
  throw "Approved-delta packages target different Factorio lines."
}
$script:IsFactorio20BackportDelta = $baselineContract.version -eq '2.4.9' -and
  $currentContract.version -eq '2.5.0' -and $currentContract.factorio_version -eq '2.0'
$script:IsFactorio20DotFiveReleaseDelta = $baselineContract.version -eq '2.5.0' -and
  $currentContract.version -eq '2.5.5' -and $currentContract.factorio_version -eq '2.0'
$script:IsFactorio20TerminalShadowDelta = $baselineContract.version -eq '2.5.5' -and
  $currentContract.version -eq '2.5.9' -and $currentContract.factorio_version -eq '2.0'
$targetAuthorityKey = "factorio-$($currentContract.factorio_version)"
$releaseAuthority = $releaseLedger.development.$targetAuthorityKey
$baselineAuthority = $releaseLedger.published_baselines.$targetAuthorityKey
if ($script:IsFactorio20DotFiveReleaseDelta) {
  $baselineTagCommit = (& git -C $repo rev-parse '2.5.0^{}').Trim()
  if ($LASTEXITCODE -ne 0 -or $baselineTagCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Approved-delta export requires the immutable local 2.5.0 predecessor tag."
  }
  $baselineAuthority = [pscustomobject][ordered]@{
    mir_version = '2.5.0'
    tag_commit = $baselineTagCommit
    archive_sha256 = $baselineContract.archive_sha256
    package_content_sha256 = $baselineContract.package_content_sha256
  }
}
if ($script:IsFactorio20TerminalShadowDelta) {
  $shadowManifestPath = Join-Path $repo '.mir\releases\terminal\shadows\2.5.9\package-manifest.json'
  if (-not (Test-Path -LiteralPath $shadowManifestPath -PathType Leaf)) {
    throw 'Approved-delta export requires the governed 2.5.9 shadow package manifest.'
  }
  $shadowManifest = Get-Content -Raw -LiteralPath $shadowManifestPath | ConvertFrom-Json -Depth 100
  $shadowPerformance = $shadowManifest.source.performance_transition
  $shadowDevelopment = $shadowPerformance.development_package
  $shadowBaseline = $shadowPerformance.baseline
  $script:TerminalShadowArchiveSha256 = [string]$shadowDevelopment.archive_sha256
  $script:TerminalShadowContentSha256 = [string]$shadowDevelopment.package_content_sha256
  if ([int]$shadowManifest.schema -ne 1 -or [string]$shadowManifest.kind -ne 'Mir3TerminalPackageManifestV1' -or
      [string]$shadowManifest.release -ne '2.5.9' -or [string]$shadowManifest.target -ne '2.0' -or
      $shadowManifest.source_frozen -ne $false -or $null -ne $shadowManifest.candidate_id -or
      [string]$shadowPerformance.phase -ne 'shadow-convergence' -or
      [string]$shadowDevelopment.version -ne '2.5.9' -or [string]$shadowBaseline.version -ne '2.5.5' -or
      [string]$shadowManifest.source.immutable_dot5_predecessor.commit -ne '27877275854eb131efeb42672d3676c9c513c85e') {
    throw 'Approved-delta 2.5.9 authority is not an unfrozen, candidate-unassigned projection of immutable 2.5.5.'
  }
  $releaseAuthority = [pscustomobject][ordered]@{
    mir_version = '2.5.9'
    candidate_id = $null
    phase = 'shadow-convergence'
    package_source_commit = [string]$shadowDevelopment.package_source_commit
    package_source_sha256 = [string]$shadowDevelopment.package_source_sha256
    archive_sha256 = [string]$shadowDevelopment.archive_sha256
    package_content_sha256 = [string]$shadowDevelopment.package_content_sha256
  }
  $baselineAuthority = [pscustomobject][ordered]@{
    mir_version = '2.5.5'
    tag_commit = [string]$shadowManifest.source.immutable_dot5_predecessor.commit
    archive_sha256 = [string]$shadowBaseline.archive_sha256
    package_content_sha256 = [string]$shadowBaseline.package_content_sha256
  }
}
if ($null -eq $releaseAuthority -or $null -eq $baselineAuthority) {
  throw "Approved-delta release authority is absent for $targetAuthorityKey."
}
$packageSourceCommit = [string]$releaseAuthority.package_source_commit
if ($packageSourceCommit -notmatch '^[0-9a-f]{40}$') {
  throw "Approved-delta export requires the active release candidate's canonical package-source commit."
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

if ($currentContract.package_content_sha256 -ne (Get-MIRPackageSourceFingerprint -RepoRoot $repo)) {
  throw "Approved-delta current package content does not match ExpectedSourceCommit package source."
}
if ([string]$releaseAuthority.archive_sha256 -ne $currentContract.archive_sha256 -or
    [string]$releaseAuthority.package_content_sha256 -ne $currentContract.package_content_sha256 -or
    [string]$releaseAuthority.package_source_sha256 -ne $currentContract.package_content_sha256) {
  throw "Approved-delta current package does not match the active release candidate authority."
}
if ([string]$baselineAuthority.mir_version -ne $baselineContract.version -or
    [string]$baselineAuthority.archive_sha256 -ne $baselineContract.archive_sha256 -or
    [string]$baselineAuthority.package_content_sha256 -ne $baselineContract.package_content_sha256) {
  throw "Approved-delta baseline package does not match the published baseline authority."
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
    factorio_version = $baselineContract.factorio_version
    source_commit = [string]$baselineAuthority.tag_commit
    archive_sha256 = $baselineContract.archive_sha256
    package_content_sha256 = $baselineContract.package_content_sha256
  }
  current = [ordered]@{
    version = $currentContract.version
    factorio_version = $currentContract.factorio_version
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
