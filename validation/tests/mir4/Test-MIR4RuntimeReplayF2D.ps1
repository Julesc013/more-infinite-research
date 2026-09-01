param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference = 'Stop'
function Assert-MIR4F2D([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
$files = @(
  'tools/mir/application/package/RuntimeReplay.ps1','tools/mir/application/package/RuntimeReplayVerifier.ps1',
  'tools/mir/cli/Invoke-MIR4PackageSource.ps1','validation/tests/runtime/Test-MIRUpgrade.ps1',
  'validation/tests/runtime/Test-MIRUpgradeMatrix.ps1','tools/commands/mir4/Update-MIR4M41F2DTargetRuntimeReplayAuthority.ps1','tools/mir.ps1'
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
$targetReceiptSchema = Join-Path $RepoRoot 'contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json'
Assert-MIR4F2D ((Get-Content -Raw -LiteralPath $targetReceiptSchema | ConvertFrom-Json) -ne $null) 'mir4-f2d-target-receipt-schema-json'
$coordinator = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplay.ps1')
foreach ($required in @('TargetMaterializer.ps1','Invoke-MIRValidation.ps1','Test-MIRUpgradeMatrix.ps1','RuntimeReplayVerifier.ps1','custody-precleanup.json','resource-receipt.json')) { Assert-MIR4F2D ($coordinator.Contains($required)) "mir4-f2d-compose-$required" }
Assert-MIR4F2D ($coordinator.Contains("'-ScenarioWorker'") -and $coordinator.Contains("runtime.exact-zip/`$scenarioName") -and -not $coordinator.Contains("'-Tier','smoke'")) 'mir4-f2d-exact-zip-worker-composition'
$verifierText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplayVerifier.ps1')
Assert-MIR4F2D ($verifierText.Contains('New-Item -ItemType Directory -Force -Path $outputParent')) 'mir4-f2d-verifier-output-parent'
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
$f200Lock = Get-MIR4FixedFactorioEngineLock -Target f200 -RepoRoot $RepoRoot
Assert-MIR4F2D ([string]$f200Lock.version -ceq '2.0.77' -and
  [string]$f200Lock.file_version -ceq '2.0.77.84539' -and
  [string]$f200Lock.binary_sha256 -ceq 'D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B') 'mir4-f2d-f200-fixed-lock'
$correctF200 = [pscustomobject]@{version='2.0.77';file_version='2.0.77.84539';binary_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B'}
Assert-MIR4F2D (Test-MIR4FixedFactorioEngineIdentity -Target f200 -ObservedIdentity $correctF200 -RepoRoot $RepoRoot) 'mir4-f2d-f200-fixed-lock-positive'
Assert-MIR4F2D (-not (Test-MIR4FixedFactorioEngineIdentity -Target f200 -ObservedIdentity ([pscustomobject]@{version='2.0.77';file_version='2.0.77.84539';binary_sha256=('0'*64)}) -RepoRoot $RepoRoot)) 'mir4-f2d-f200-fixed-lock-wrong-hash'
Assert-MIR4F2D (-not (Test-MIR4FixedFactorioEngineIdentity -Target f200 -ObservedIdentity ([pscustomobject]@{version='2.0.76';file_version='2.0.76.0';binary_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B'}) -RepoRoot $RepoRoot)) 'mir4-f2d-f200-fixed-lock-wrong-version'
$f210Profile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/profiles/factorio-2.1.json') | ConvertFrom-Json
$resolvedF210 = Resolve-MIR4FactorioQualificationProfile -Profile $f210Profile -RepoRoot $RepoRoot
Assert-MIR4F2D ([string]$resolvedF210.qualification_factorio_selection -ceq 'latest-installed-official-2.1-experimental') 'mir4-f2d-f210-moving-channel-unchanged'
$targetWriter = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/commands/mir4/Update-MIR4M41F2DTargetRuntimeReplayAuthority.ps1')
foreach ($required in @("ValidateSet('f200','f110','f100')",'mir4-m41-f2d-target-wrong-target-evidence','mir4-m41-f2d-target-stale-replay-commit','mir4-m41-f2d-target-missing-reload','mir4-m41-f2d-target-wrong-fixed-engine','package_visible_delta=@()','$acceptedF210Sha256')) { Assert-MIR4F2D ($targetWriter.Contains([string]$required)) "mir4-f2d-target-writer-$required" }
foreach ($forbidden in @('git clean','package_cutover=$true','publication=$true','signing=$true','sealing=$true')) { Assert-MIR4F2D (-not $coordinator.Contains($forbidden)) "mir4-f2d-forbidden-$forbidden" }
Write-Host '[ok] MIR 4 F2D runtime replay harness contract'
