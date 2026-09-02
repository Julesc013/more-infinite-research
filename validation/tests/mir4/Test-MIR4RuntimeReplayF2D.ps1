param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path)

$ErrorActionPreference = 'Stop'
function Assert-MIR4F2D([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
$files = @(
  'tools/mir/application/package/RuntimeReplay.ps1','tools/mir/application/package/RuntimeReplayVerifier.ps1',
  'tools/mir/cli/Invoke-MIR4PackageSource.ps1','validation/tests/runtime/Test-MIRUpgrade.ps1',
  'validation/tests/runtime/Test-MIRUpgradeMatrix.ps1','tools/commands/mir4/Update-MIR4M41F2DTargetRuntimeReplayAuthority.ps1','tools/commands/mir4/Update-MIR4M41F2DFourTargetRuntimeReplayAggregate.ps1','tools/mir/application/package/RuntimeReplayAggregateVerifier.ps1','tools/mir.ps1'
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
$targetReceiptSchemaRecord = Get-Content -Raw -LiteralPath $targetReceiptSchema | ConvertFrom-Json
Assert-MIR4F2D ($targetReceiptSchemaRecord -ne $null -and [int]$targetReceiptSchemaRecord.properties.current_authorities.minItems -eq 1) 'mir4-f2d-target-receipt-schema-json'
$aggregateReceiptSchema = Join-Path $RepoRoot 'contracts/repository/mir4-m41-f2d-four-target-runtime-replay-aggregate-v1.schema.json'
Assert-MIR4F2D ((Get-Content -Raw -LiteralPath $aggregateReceiptSchema | ConvertFrom-Json) -ne $null) 'mir4-f2d-aggregate-receipt-schema-json'
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
$availabilityObservation = '.mir/evidence/mir4-r0/2026-08-16/MIR4-Bootstrap-Engine-Availability-ObservationV1.json'
$f110Lock = Get-MIR4FixedFactorioEngineLock -Target f110 -RepoRoot $RepoRoot
Assert-MIR4F2D ([string]$f110Lock.version -ceq '1.1.110' -and
  [string]$f110Lock.file_version -ceq '1.1.110.62357' -and
  [string]$f110Lock.binary_sha256 -ceq 'B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1' -and
  $availabilityObservation -in @($f110Lock.authority_paths)) 'mir4-f2d-f110-fixed-lock'
$correctF110 = [pscustomobject]@{version='1.1.110';file_version='1.1.110.62357';binary_sha256='B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1'}
Assert-MIR4F2D (Test-MIR4FixedFactorioEngineIdentity -Target f110 -ObservedIdentity $correctF110 -RepoRoot $RepoRoot) 'mir4-f2d-f110-fixed-lock-positive'
Assert-MIR4F2D (-not (Test-MIR4FixedFactorioEngineIdentity -Target f110 -ObservedIdentity ([pscustomobject]@{version='1.1.110';file_version='1.1.110.62358';binary_sha256='B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1'}) -RepoRoot $RepoRoot)) 'mir4-f2d-f110-fixed-lock-wrong-build'
$f100Lock = Get-MIR4FixedFactorioEngineLock -Target f100 -RepoRoot $RepoRoot
Assert-MIR4F2D ([string]$f100Lock.version -ceq '1.0.0' -and
  [string]$f100Lock.file_version -ceq '1.0.0.54889' -and
  [string]$f100Lock.binary_sha256 -ceq '99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70' -and
  $availabilityObservation -in @($f100Lock.authority_paths)) 'mir4-f2d-f100-fixed-lock-alias-normalized'
$correctF100 = [pscustomobject]@{version='1.0.0';file_version='1.0.0.54889';binary_sha256='99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70'}
Assert-MIR4F2D (Test-MIR4FixedFactorioEngineIdentity -Target f100 -ObservedIdentity $correctF100 -RepoRoot $RepoRoot) 'mir4-f2d-f100-fixed-lock-positive'
Assert-MIR4F2D (-not (Test-MIR4FixedFactorioEngineIdentity -Target f100 -ObservedIdentity ([pscustomobject]@{version='1.0.0-only';file_version='1.0.0.54889';binary_sha256='99F1CE207A04296EF7D797E4A98AA98DDE4F02EE653C9DF736AC33A676FD4F70'}) -RepoRoot $RepoRoot)) 'mir4-f2d-f100-authority-alias-not-product-version'
$f210Profile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/profiles/factorio-2.1.json') | ConvertFrom-Json
$resolvedF210 = Resolve-MIR4FactorioQualificationProfile -Profile $f210Profile -RepoRoot $RepoRoot
Assert-MIR4F2D ([string]$resolvedF210.qualification_factorio_selection -ceq 'latest-installed-official-2.1-experimental') 'mir4-f2d-f210-moving-channel-unchanged'
$targetWriter = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/commands/mir4/Update-MIR4M41F2DTargetRuntimeReplayAuthority.ps1')
foreach ($required in @("ValidateSet('f200','f110','f100')",'mir4-m41-f2d-target-wrong-target-evidence','mir4-m41-f2d-target-upgrade-binding','mir4-m41-f2d-target-stale-replay-commit','mir4-m41-f2d-target-missing-reload','mir4-m41-f2d-target-wrong-fixed-engine','package_visible_delta=@()','$acceptedF210Sha256')) { Assert-MIR4F2D ($targetWriter.Contains([string]$required)) "mir4-f2d-target-writer-$required" }
$programmePath = Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json'
Assert-MIR4F2D ((Get-Content -Raw -LiteralPath $programmePath) | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-4x-operating-programme-v1.schema.json')) 'mir4-f2d-programme-schema'
$programme = Get-Content -Raw -LiteralPath $programmePath | ConvertFrom-Json -Depth 40
Assert-MIR4F2D ((@($programme.package_fixed_point.target_results | ForEach-Object { "$($_.target):$($_.state)" }) -join '|') -ceq 'f210:complete|f200:complete|f110:complete|f100:complete' -and $null -eq $programme.package_fixed_point.next_target -and [string]$programme.package_fixed_point.aggregate -ceq 'complete' -and [string]$programme.package_fixed_point.package_cutover -ceq 'ready') 'mir4-f2d-programme-target-state'
$aggregateWriter = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/commands/mir4/Update-MIR4M41F2DFourTargetRuntimeReplayAggregate.ps1')
$aggregateVerifier = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/mir/application/package/RuntimeReplayAggregateVerifier.ps1')
foreach ($required in @('M41-F2D-FOUR-TARGET-RUNTIME-REPLAY-PASSED-NO-CUTOVER','M41F2DTargetRuntimeReplayTargets','RuntimeReplayAggregateVerifier.ps1','package_cutover=$false','publication=$false')) { Assert-MIR4F2D ($aggregateWriter.Contains($required)) "mir4-f2d-aggregate-writer-$required" }
foreach ($required in @('f210','f200','f110','f100','mir4-f2d-aggregate-receipt-chain','mir4-f2d-aggregate-evidence-redaction','mir4-f2d-aggregate-cross-target-substitution','old_writer_authoritative')) { Assert-MIR4F2D ($aggregateVerifier.Contains($required)) "mir4-f2d-aggregate-verifier-$required" }
$aggregateReceiptPath = Join-Path $RepoRoot 'releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json'
Assert-MIR4F2D ((Get-Content -Raw -LiteralPath $aggregateReceiptPath) | Test-Json -SchemaFile $aggregateReceiptSchema) 'mir4-f2d-aggregate-receipt-schema'
$aggregateReceipt = Get-Content -Raw -LiteralPath $aggregateReceiptPath | ConvertFrom-Json -Depth 100
Assert-MIR4F2D ([string]$aggregateReceipt.status -ceq 'M41-F2D-FOUR-TARGET-RUNTIME-REPLAY-PASSED-NO-CUTOVER' -and (@($aggregateReceipt.verification.targets.target) -join '|') -ceq 'f210|f200|f110|f100' -and [string]$aggregateReceipt.verification.external_custody -ceq 'verified' -and @($aggregateReceipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-f2d-aggregate-receipt-result'
$acceptedF200Receipt = Join-Path $RepoRoot 'releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json'
Assert-MIR4F2D ((Get-FileHash -LiteralPath $acceptedF200Receipt -Algorithm SHA256).Hash -ceq '079CCD4FC9B61A0D4CAB53F1DBE633D5FD142AC81441E95A3FF7D379E7086C9F') 'mir4-f2d-f200-accepted-receipt-byte-stable'
foreach ($forbidden in @('git clean','package_cutover=$true','publication=$true','signing=$true','sealing=$true')) { Assert-MIR4F2D (-not $coordinator.Contains($forbidden)) "mir4-f2d-forbidden-$forbidden" }
Write-Host '[ok] MIR 4 F2D runtime replay harness contract'
