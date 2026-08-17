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
if ($registry.schema -ne 3 -or $registry.records.Count -lt 1) {
  throw "Scenario manifest schema-3 full records did not load."
}
$filtered20 = Select-MIRScenarioRegistryForTargetCapabilities `
  -Registry (Import-MIRScenarioRegistry `
    -Path (Join-Path $RepoRoot "fixtures\compat-matrix\expected-scenarios.json") `
    -TargetProfile "2.0") `
  -TargetProfile ([pscustomobject]@{features=[pscustomobject]@{
    recipe_productivity=$true
    productivity_family_adoption=$true
    scripted_techs=$true
    settings_profiles=$true
  }})
if (@($filtered20.records | Where-Object name -like "semantic-family-*").Count -ne 5) {
  throw "Factorio 2.0 scenario filtering removed supported semantic-family rows."
}
if (@($filtered20.records | Where-Object name -like "space-age-native-owner-settings-*").Count -ne 11) {
  throw "Factorio 2.0 scenario filtering removed supported native-owner settings rows."
}
if (@($filtered20.records | Where-Object name -like "space-age-vanilla-family-*").Count -ne 5) {
  throw "Factorio 2.0 scenario filtering removed supported vanilla-family rows."
}
if (@($filtered20.records | Where-Object name -eq "space-age-plates-n-circuit-productivity-compat").Count -ne 1) {
  throw "Factorio 2.0 scenario filtering removed the supported Plates n Circuit positive row."
}
if (@($filtered20.records | Where-Object name -like "space-age-plates-n-circuit-productivity-*").Count -ne 4) {
  throw "Factorio 2.0 scenario filtering removed a Plates n Circuit compatibility row."
}
$filtered21 = Select-MIRScenarioRegistryForTargetCapabilities `
  -Registry $registry `
  -TargetProfile ([pscustomobject]@{features=[pscustomobject]@{
    recipe_productivity=$true
    productivity_family_adoption=$true
    scripted_techs=$true
    settings_profiles=$true
  }})
if (@($filtered21.records | Where-Object name -like "semantic-family-*").Count -ne 5) {
  throw "Factorio 2.1 scenario filtering removed supported semantic-family rows."
}
$nativeOwnerSettings21 = @($filtered21.records | Where-Object name -like "space-age-native-owner-settings-*")
if ($nativeOwnerSettings21.Count -ne 16) {
  throw "Factorio 2.1 scenario filtering removed supported native-owner settings rows."
}
if (@($nativeOwnerSettings21 | Where-Object {
      @($_.required_features) -notcontains "productivity_family_adoption"
    }).Count -ne 0) {
  throw "Native-owner settings rows do not declare the productivity-family adoption capability."
}
$vanillaFamily21 = @($filtered21.records | Where-Object name -like "space-age-vanilla-family-*")
if ($vanillaFamily21.Count -ne 5) {
  throw "Factorio 2.1 scenario filtering removed supported vanilla-family adoption rows."
}
if (@($vanillaFamily21 | Where-Object {
      @($_.required_features) -notcontains "productivity_family_adoption"
    }).Count -ne 0) {
  throw "Vanilla-family adoption rows do not declare the productivity-family adoption capability."
}
$platesCircuitPositive21 = @($filtered21.records | Where-Object {
    $_.name -eq "space-age-plates-n-circuit-productivity-compat"
  })
if ($platesCircuitPositive21.Count -ne 1 -or
    @($platesCircuitPositive21[0].required_features) -notcontains "productivity_family_adoption") {
  throw "The Factorio 2.1 Plates n Circuit positive row is not adoption-capability-bound."
}
$semanticDeclaration = Resolve-MIRScenarioDeclaration `
  -Registry $registry `
  -ScenarioName "semantic-family-attach" `
  -Kind "runtime"
if ($semanticDeclaration.group -ne "local-mod-library" -or $semanticDeclaration.surface -ne "base") {
  throw "Semantic family scenario did not retain its declared group and surface."
}
$scale20 = @($filtered20.records | Where-Object name -like "synthetic-scale-*")
$scale21 = @($filtered21.records | Where-Object name -like "synthetic-scale-*")
if ($scale20.Count -ne 4 -or @($scale20 | Where-Object { @($_.fixtures).Count -lt 2 }).Count -ne 0) {
  throw "Factorio 2.0 scale scenarios do not all declare their source and assertion fixtures."
}
if ($scale21.Count -ne 4 -or @($scale21 | Where-Object { @($_.fixtures).Count -lt 2 }).Count -ne 0) {
  throw "Factorio 2.1 scale scenarios do not all declare their source and assertion fixtures."
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

  $zeroAssertionPath = Join-Path $testRoot "zero-assertions.json"
  Initialize-MIRValidationResult -OutputPath $zeroAssertionPath -FactorioVersion "test" `
    -ExpectedScenarios @("runtime-zero") -ExpectedScenariosSha256 "manifest" | Out-Null
  $zeroRecord = Start-MIRValidationScenario -Name "runtime-zero" -Kind "runtime" -Group "test"
  Complete-MIRValidationScenario -Record $zeroRecord -Status "passed" -AssertionsExecuted 0
  $zeroFailed = $false
  try { Complete-MIRValidationRun } catch { $zeroFailed = $_.Exception.Message -match "zero assertions" }
  if (-not $zeroFailed) { throw "Runtime scenario with zero executed assertions did not fail completion." }

  $failurePacketPath = Join-Path $testRoot "failure-packets\runtime-failure.json"
  Initialize-MIRValidationResult -OutputPath (Join-Path $testRoot "failure.json") -FactorioVersion "test" | Out-Null
  $failureRecord = Start-MIRValidationScenario -Name "runtime-failure" -Kind "runtime" -Group "test"
  Complete-MIRValidationScenario -Record $failureRecord -Status "failed" -ErrorMessage "expected failure"
  if (-not (Test-Path -LiteralPath $failurePacketPath)) { throw "Structured scenario failure packet was not written." }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}

Write-Host "[ok] MIR validation result aggregation tests passed."
