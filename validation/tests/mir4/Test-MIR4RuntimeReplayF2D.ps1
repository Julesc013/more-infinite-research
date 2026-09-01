param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference = 'Stop'
function Assert-MIR4F2D([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
$files = @(
  'tools/mir/application/package/RuntimeReplay.ps1','tools/mir/application/package/RuntimeReplayVerifier.ps1',
  'tools/mir/cli/Invoke-MIR4PackageSource.ps1','validation/tests/runtime/Test-MIRUpgrade.ps1',
  'validation/tests/runtime/Test-MIRUpgradeMatrix.ps1','tools/mir.ps1'
)
foreach ($relative in $files) {
  $tokens=$null;$errors=$null
  [Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $relative),[ref]$tokens,[ref]$errors)|Out-Null
  Assert-MIR4F2D ($errors.Count -eq 0) "mir4-f2d-syntax-$relative"
}
$runnerText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/tests/runtime/Test-MIRUpgrade.ps1')
Assert-MIR4F2D ($runnerText.Contains("[string]`$WorkRoot") -and $runnerText.Contains("'OnFailure','Always','Never'") -and $runnerText.Contains('MIRUpgradeExpandedRootCleanupV1')) 'mir4-f2d-runner-retention'
$matrixText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/tests/runtime/Test-MIRUpgradeMatrix.ps1')
Assert-MIR4F2D ($matrixText.Contains('expanded_root_disposition') -and $matrixText.Contains('cleanup_sha256')) 'mir4-f2d-matrix-cleanup-binding'
$cliText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/cli/Invoke-MIR4PackageSource.ps1')
Assert-MIR4F2D ($cliText.Contains("'runtime-replay'") -and $cliText.Contains('CandidateId') -and $cliText.Contains('EvidenceRoot')) 'mir4-f2d-cli-composition'

. (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplay.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mir-f2d-containment-' + [guid]::NewGuid().ToString('N'))
$child = Join-Path $testRoot 'child'
$sibling = $testRoot + '-sibling'
New-Item -ItemType Directory -Force -Path $child | Out-Null
[IO.File]::WriteAllText((Join-Path $child 'data.txt'),'x',[Text.UTF8Encoding]::new($false))
try {
  Assert-MIR4F2D (Test-MIR4RuntimeReplayContained -Root $testRoot -Path $child) 'mir4-f2d-containment-child'
  Assert-MIR4F2D (-not (Test-MIR4RuntimeReplayContained -Root $testRoot -Path $sibling)) 'mir4-f2d-containment-sibling'
  Remove-MIR4RuntimeReplayWorkRoot -WorkRoot $testRoot
  Assert-MIR4F2D (-not (Test-Path -LiteralPath $testRoot)) 'mir4-f2d-contained-cleanup'
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

$schema = Join-Path $RepoRoot 'spec/schemas/mir4-f2d-runtime-replay-evidence-v1.schema.json'
Assert-MIR4F2D ((Get-Content -Raw -LiteralPath $schema | ConvertFrom-Json) -ne $null) 'mir4-f2d-evidence-schema-json'
$coordinator = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplay.ps1')
foreach ($required in @('TargetMaterializer.ps1','Invoke-MIRValidation.ps1','Test-MIRUpgradeMatrix.ps1','RuntimeReplayVerifier.ps1','custody-precleanup.json','resource-receipt.json')) { Assert-MIR4F2D ($coordinator.Contains($required)) "mir4-f2d-compose-$required" }
Assert-MIR4F2D ($coordinator.Contains("'-ScenarioWorker'") -and $coordinator.Contains("runtime.exact-zip/`$scenarioName") -and -not $coordinator.Contains("'-Tier','smoke'")) 'mir4-f2d-exact-zip-worker-composition'
$verifierText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplayVerifier.ps1')
Assert-MIR4F2D ($verifierText.Contains('New-Item -ItemType Directory -Force -Path $outputParent')) 'mir4-f2d-verifier-output-parent'
foreach ($forbidden in @('git clean','package_cutover=$true','publication=$true','signing=$true','sealing=$true')) { Assert-MIR4F2D (-not $coordinator.Contains($forbidden)) "mir4-f2d-forbidden-$forbidden" }
Write-Host '[ok] MIR 4 F2D runtime replay harness contract'
