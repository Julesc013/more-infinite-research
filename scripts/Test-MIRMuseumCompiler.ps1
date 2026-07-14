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
  Assert-Rejected "missing-binary" { param($t) $t.binary = "Z:/missing/factorio.exe" }
  Assert-Rejected "missing-base-data" { param($t) $t.base_data = "Z:/missing/base" }
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

  if ($negativeResults.Count -ne 26) { throw "Expected 26 negative cases; ran $($negativeResults.Count)." }
}

[pscustomobject][ordered]@{
  schema = 1
  status = "passed"
  targets = $results
  negative_case_count = $negativeResults.Count
  negative_cases = $negativeResults
} | ConvertTo-Json -Depth 20
