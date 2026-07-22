param(
  [ValidateSet("0.12", "0.11", "0.10", "0.9", "0.8", "0.7", "0.6", "all")]
  [string]$FactorioVersion = "all",
  [switch]$SkipNegativeCases
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $PSScriptRoot "Museum\MuseumCompiler.psm1") -Force
$catalogPath = Join-Path $repo ".mir\museum-targets.json"
$catalog = Get-MIRMuseumCatalog -Path $catalogPath
$selected = if ($FactorioVersion -eq "all") { @($catalog.targets) } else { @(Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion $FactorioVersion) }
$results = @()

foreach ($target in $selected) {
  $validation = Test-MIRMuseumTarget -Catalog $catalog -Target $target
  if (-not $validation.passed) { throw "Target $($target.factorio) failed catalog validation:`n$($validation.errors -join "`n")" }
  $first = New-MIRMuseumPackage -Catalog $catalog -Target $target -RepoRoot $repo -OutputDir "build\museum-test-a"
  $second = New-MIRMuseumPackage -Catalog $catalog -Target $target -RepoRoot $repo -OutputDir "build\museum-test-b"
  if ($first.sha256 -ne $second.sha256) { throw "Target $($target.factorio) package is not deterministic." }
  if ($first.package_content_sha256 -ne $second.package_content_sha256) { throw "Target $($target.factorio) content identity is not deterministic." }
  if ($first.entries -ne 4) { throw "Target $($target.factorio) package must contain exactly four files; found $($first.entries)." }
  $results += [pscustomobject][ordered]@{
    target = [string]$target.factorio
    generated = $first.generated_count
    entries = $first.entries
    sha256 = $first.sha256
    content_sha256 = $first.package_content_sha256
    warnings = @($validation.warnings)
  }
}

$fixtureRoot = Join-Path $repo "fixtures\museum\synthetic-installation"
$syntheticTarget = ((Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion "0.12") | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
$syntheticInstallation = Resolve-MIRMuseumInstallation `
  -Target $syntheticTarget `
  -RepoRoot $repo `
  -RegistryPath (Join-Path $repo "fixtures\museum\installation-registry.json")
$syntheticBaseIdentity = Get-MIRMuseumTreeIdentity -Root $syntheticInstallation.base_data
$syntheticTarget.binary_sha256 = Get-MIRSha256 -Path $syntheticInstallation.binary
$syntheticTarget.base_file_count = [int]$syntheticBaseIdentity.file_count
$syntheticTarget.base_data_bytes = [long]$syntheticBaseIdentity.bytes
$syntheticTarget.base_data_sha256 = [string]$syntheticBaseIdentity.sha256
$syntheticValidation = Test-MIRMuseumExactInstallation -Catalog $catalog -Target $syntheticTarget -Installation $syntheticInstallation
if (-not $syntheticValidation.passed) { throw "Repository-owned synthetic museum installation failed validation:`n$($syntheticValidation.errors -join "`n")" }
$syntheticFirst = New-MIRMuseumPackage -Catalog $catalog -Target $syntheticTarget -RepoRoot $repo -OutputDir "build\museum-fixture-test-a"
$syntheticSecond = New-MIRMuseumPackage -Catalog $catalog -Target $syntheticTarget -RepoRoot $repo -OutputDir "build\museum-fixture-test-b"
if ($syntheticFirst.sha256 -ne $syntheticSecond.sha256 -or
    $syntheticFirst.package_content_sha256 -ne $syntheticSecond.package_content_sha256) {
  throw "Repository-owned synthetic museum fixture did not render deterministically."
}

$negativeResults = @()
if (-not $SkipNegativeCases) {
  $baseline = Get-MIRMuseumTarget -Catalog $catalog -FactorioVersion "0.12"
  function Copy-Target { return ($baseline | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
  function Assert-Rejected {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Mutation)
    $candidate = Copy-Target
    & $Mutation $candidate
    $test = Test-MIRMuseumTarget -Catalog $catalog -Target $candidate
    if ($test.passed) { throw "Negative case '$Name' was accepted." }
    $script:negativeResults += [pscustomobject][ordered]@{ name = $Name; status = "rejected"; errors = @($test.errors) }
  }

  Assert-Rejected "invalid-version" { param($t) $t.version = "3.2.0" }
  Assert-Rejected "invalid-branch" { param($t) $t.branch = "tmp/0.11" }
  Assert-Rejected "unsupported-locale-format" { param($t) $t.locale_format = "json" }
  Assert-Rejected "inert-configuration" { param($t) $t.configuration = "settings-lua" }
  Assert-Rejected "invalid-installation-id" { param($t) $t.installation_id = "workstation-factorio" }
  Assert-Rejected "absolute-binary-path" { param($t) $t.binary_relative_path = "Z:/Factorio.exe" }
  Assert-Rejected "traversal-base-path" { param($t) $t.base_relative_path = "../base" }
  Assert-Rejected "invalid-binary-fingerprint" { param($t) $t.binary_sha256 = "NOT-A-SHA256" }
  Assert-Rejected "invalid-base-fingerprint" { param($t) $t.base_data_sha256 = "NOT-A-SHA256" }
  Assert-Rejected "zero-base-file-count" { param($t) $t.base_file_count = 0 }
  Assert-Rejected "zero-base-byte-count" { param($t) $t.base_data_bytes = 0 }
  Assert-Rejected "unsupported-science" { param($t) $t.science[0] = "automation-science-pack" }
  Assert-Rejected "duplicate-science" { param($t) $t.science[1] = $t.science[0] }
  Assert-Rejected "duplicate-family-id" { param($t) $t.families[1].id = $t.families[0].id }
  Assert-Rejected "unknown-canonical-feature" { param($t) $t.families[0].canonical_feature_id = "missing-feature" }
  Assert-Rejected "invalid-family-id" { param($t) $t.families[0].id = "Bad Family" }
  Assert-Rejected "zero-levels" { param($t) $t.families[0].levels = 0 }
  Assert-Rejected "unbounded-levels" { param($t) $t.families[0].levels = 999 }
  Assert-Rejected "nonpositive-count" { param($t) $t.families[0].base_count = 0 }
  Assert-Rejected "negative-count-step" { param($t) $t.families[0].count_step = -1 }
  Assert-Rejected "nonpositive-time" { param($t) $t.families[0].time = 0 }
  Assert-Rejected "missing-prerequisite" { param($t) $t.families[0].prerequisite = "" }
  Assert-Rejected "unsupported-effect" { param($t) $t.families[0].effect.type = "change-recipe-productivity" }
  Assert-Rejected "nonpositive-modifier" { param($t) $t.families[0].effect.modifier = 0 }
  Assert-Rejected "missing-ammo-category" { param($t) $t.families[2].effect.ammo_category = "" }
  Assert-Rejected "missing-turret-id" { param($t) $t.families[1].effect.turret_id = "" }
  Assert-Rejected "missing-evidence-file" { param($t) $t.families[0].evidence_file = "prototypes/technology/missing.lua" }
  Assert-Rejected "unproven-prerequisite" { param($t) $t.families[0].prerequisite = "not-a-base-technology" }
  Assert-Rejected "unproven-effect" { param($t) $t.families[5].evidence_file = "prototypes/technology/bullet-upgrades.lua" }
  Assert-Rejected "missing-icon" { param($t) $t.families[0].icon = "missing.png" }
  Assert-Rejected "generated-id-collision" { param($t) $t.families[1].id = $t.families[0].id; $t.families[1].prerequisite = $t.families[0].prerequisite }

  if ($negativeResults.Count -ne 31) { throw "Expected 31 portable negative cases; ran $($negativeResults.Count)." }
}

$exactNegativeResults = @()
if (-not $SkipNegativeCases) {
  function Assert-ExactRejected {
    param(
      [Parameter(Mandatory)][string]$Name,
      [Parameter(Mandatory)][scriptblock]$Mutation,
      [Parameter(Mandatory)][string]$ExpectedError
    )
    $candidateTarget = ($syntheticTarget | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
    $candidateInstallation = ($syntheticInstallation | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
    & $Mutation $candidateTarget $candidateInstallation
    $test = Test-MIRMuseumExactInstallation -Catalog $catalog -Target $candidateTarget -Installation $candidateInstallation
    if ($test.passed -or @($test.errors | Where-Object { [string]$_ -like "*$ExpectedError*" }).Count -eq 0) {
      throw "Synthetic exact-installation negative case '$Name' was not rejected for '$ExpectedError'."
    }
    $script:exactNegativeResults += [pscustomobject][ordered]@{ name = $Name; status = "rejected"; errors = @($test.errors) }
  }

  Assert-ExactRejected "binary-fingerprint-mismatch" { param($t, $i) $t.binary_sha256 = "0" * 64 } "binary fingerprint mismatch"
  Assert-ExactRejected "base-fingerprint-mismatch" { param($t, $i) $t.base_data_sha256 = "0" * 64 } "base-data fingerprint mismatch"
  Assert-ExactRejected "missing-binary" { param($t, $i) $i.binary = Join-Path $i.root "missing-factorio.exe" } "Missing target binary"
  Assert-ExactRejected "missing-base-data" { param($t, $i) $i.base_data = Join-Path $i.root "missing-base" } "Missing target base data"

  $negativeFixtureRoot = Join-Path $repo "build\museum-synthetic-installation-negative"
  if (Test-Path -LiteralPath $negativeFixtureRoot) { Remove-Item -LiteralPath $negativeFixtureRoot -Recurse -Force }
  Copy-Item -LiteralPath $fixtureRoot -Destination $negativeFixtureRoot -Recurse
  try {
    $wrongPatchBase = Join-Path $negativeFixtureRoot "wrong-patch\data\base"
    New-Item -ItemType Directory -Force -Path $wrongPatchBase | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot "data\base\*") -Destination $wrongPatchBase -Recurse -Force
    Set-MIRUtf8Text -Path (Join-Path $wrongPatchBase "info.json") -Text "{`n  `"name`": `"base`",`n  `"version`": `"0.12.34`"`n}`n"
    Assert-ExactRejected "wrong-base-patch" { param($t, $i) $i.base_data = $wrongPatchBase } "does not match required"

    $missingEvidenceBase = Join-Path $negativeFixtureRoot "missing-evidence\data\base"
    New-Item -ItemType Directory -Force -Path $missingEvidenceBase | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot "data\base\*") -Destination $missingEvidenceBase -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $missingEvidenceBase "prototypes\technology\technology.lua") -Force
    Assert-ExactRejected "missing-evidence-file" { param($t, $i) $i.base_data = $missingEvidenceBase } "Missing evidence file"

    $missingIconBase = Join-Path $negativeFixtureRoot "missing-icon\data\base"
    New-Item -ItemType Directory -Force -Path $missingIconBase | Out-Null
    Copy-Item -Path (Join-Path $fixtureRoot "data\base\*") -Destination $missingIconBase -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $missingIconBase "graphics\technology\toolbelt.png") -Force
    Assert-ExactRejected "missing-icon" { param($t, $i) $i.base_data = $missingIconBase } "Missing icon"
  } finally {
    if (Test-Path -LiteralPath $negativeFixtureRoot) { Remove-Item -LiteralPath $negativeFixtureRoot -Recurse -Force }
  }
  if ($exactNegativeResults.Count -ne 7) { throw "Expected 7 exact-installation negative cases; ran $($exactNegativeResults.Count)." }
}

[pscustomobject][ordered]@{
  schema = 1
  status = "passed"
  targets = $results
  synthetic_fixture = [ordered]@{
    installation_id = [string]$syntheticInstallation.installation_id
    base_file_count = [int]$syntheticValidation.base_file_count
    rendered_sha256 = [string]$syntheticFirst.sha256
    rendered_content_sha256 = [string]$syntheticFirst.package_content_sha256
  }
  negative_case_count = $negativeResults.Count + $exactNegativeResults.Count
  portable_negative_cases = $negativeResults
  exact_installation_negative_cases = $exactNegativeResults
} | ConvertTo-Json -Depth 20
