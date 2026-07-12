param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "scripts\validation\ScenarioGroups.ps1")
. (Join-Path $RepoRoot "scripts\validation\ResultAggregation.ps1")
. (Join-Path $RepoRoot "scripts\validation\ScenarioRegistry.ps1")

$registry = Import-MIRScenarioRegistry `
  -Path (Join-Path $RepoRoot "fixtures\compat-matrix\expected-scenarios.json") `
  -TargetProfile "2.1"
if ($registry.schema -ne 2 -or $registry.records.Count -lt 1) {
  throw "Scenario manifest schema-2 full records did not load."
}
$semanticDeclaration = Resolve-MIRScenarioDeclaration `
  -Registry $registry `
  -ScenarioName "semantic-family-attach" `
  -Kind "runtime"
if ($semanticDeclaration.group -ne "local-mod-library" -or $semanticDeclaration.surface -ne "base") {
  throw "Semantic family scenario did not retain its declared group and surface."
}

$cases = @(
  @{ Name = "generated-prerequisite-safety"; Kind = "runtime"; SpaceAge = $false; Expected = "science-prerequisites" },
  @{ Name = "weapon-speed-overlap-safety"; Kind = "runtime"; SpaceAge = $false; Expected = "weapon-overlap" },
  @{ Name = "settings-profile-roundtrip"; Kind = "runtime"; SpaceAge = $false; Expected = "settings-codec" },
  @{ Name = "reduced-settings-surface"; Kind = "runtime"; SpaceAge = $false; Expected = "reduced-settings-surface" },
  @{ Name = "space-age-generation-integrity"; Kind = "runtime"; SpaceAge = $true; Expected = "space-age" },
  @{ Name = "package-zip-base"; Kind = "package"; SpaceAge = $false; Expected = "exact-dist" },
  @{ Name = "base-generation-integrity"; Kind = "runtime"; SpaceAge = $false; Expected = "base-load" }
)
foreach ($case in $cases) {
  $actual = Get-MIRValidationScenarioGroup -ScenarioName $case.Name -Kind $case.Kind -EnableSpaceAge:$case.SpaceAge
  if ($actual -ne $case.Expected) {
    throw "Scenario '$($case.Name)' classified as '$actual'; expected '$($case.Expected)'."
  }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mir-validation-results-" + [Guid]::NewGuid().ToString("N"))
try {
  $completePath = Join-Path $testRoot "complete.json"
  Initialize-MIRValidationResult -OutputPath $completePath -FactorioVersion "test" -RequiredGroups @("static", "base-load") `
    -MirVersion "3.0.5" -GitCommit ("a" * 40) -TargetProfileSha256 "profile" `
    -RequiredGroupsSha256 "groups" -PackageSourceSha256 "source" `
    -ValidationPackageSha256 "archive" -ValidationPackageContentSha256 "content" `
    -FactorioBinaryVersion "2.1-test" | Out-Null
  Add-MIRValidationCompletedScenario -Name "static-gate" -Group "static"
  Add-MIRValidationCompletedScenario -Name "base-load" -Group "base-load"
  Complete-MIRValidationRun
  $complete = Get-Content -Raw -LiteralPath $completePath | ConvertFrom-Json
  if ($complete.schema -ne 2) {
    throw "Completed result should use validation schema 2."
  }
  if ($complete.git_commit -ne ("a" * 40)) {
    throw "Completed result should retain its source commit."
  }
  if ($complete.package_source_sha256 -ne "source") {
    throw "Completed result should retain its package-source fingerprint."
  }
  if ($complete.status -ne "passed" -or @($complete.groups | Where-Object { $_.status -ne "passed" }).Count -ne 0) {
    throw "Completed validation summary did not report all required groups as passed."
  }

  $partialPath = Join-Path $testRoot "partial.json"
  Initialize-MIRValidationResult -OutputPath $partialPath -FactorioVersion "test" -RequiredGroups @("space-age") | Out-Null
  $null = Start-MIRValidationScenario -Name "interrupted" -Kind "runtime" -Group "space-age"
  $partial = Get-Content -Raw -LiteralPath $partialPath | ConvertFrom-Json
  if ($partial.status -ne "incomplete" -or $partial.scenarios[0].status -ne "running" -or $partial.groups[0].status -ne "incomplete") {
    throw "Interrupted validation summary did not preserve an incomplete running scenario."
  }

  $missingPath = Join-Path $testRoot "missing-scenario.json"
  Initialize-MIRValidationResult -OutputPath $missingPath -FactorioVersion "test" -RequiredGroups @("static") `
    -ExpectedScenarios @("required-one", "required-two") -ExpectedScenariosSha256 "manifest" | Out-Null
  Add-MIRValidationCompletedScenario -Name "required-one" -Group "static"
  $failedAsExpected = $false
  try {
    Complete-MIRValidationRun
  } catch {
    $failedAsExpected = $_.Exception.Message -match "scenario completeness failed"
  }
  if (-not $failedAsExpected) {
    throw "Missing expected validation scenario did not fail completion."
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}

Write-Host "[ok] MIR validation result aggregation tests passed."
