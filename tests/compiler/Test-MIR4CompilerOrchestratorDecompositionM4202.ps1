# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tests/compiler/support/MIR4M4202PackageSuccession.ps1')

function Assert-MIR4M4202CompilerOrchestrator([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-compiler-orchestrator-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202CompilerOrchestrator ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202CompilerOrchestrator (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-hash'
$currentPackageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
Assert-MIR4M4202CompilerOrchestrator (Test-MIR4M4202PackageSourceSuccession -RepoRoot $repo -PredecessorSha256 ([string]$receipt.package_authority.package_source_sha256) -CurrentSha256 $currentPackageSource) 'package-source-fingerprint'
$evolvedPaths=@($receipt.evolved_bindings|ForEach-Object{[string]$_.path})
Assert-MIR4M4202CompilerOrchestrator ($evolvedPaths.Count-eq16-and@($evolvedPaths|Sort-Object -Unique).Count-eq16-and'.mir/control/paths.yml'-in$evolvedPaths-and'.mir/modules.yml'-in$evolvedPaths-and'tests/compiler/Test-MIR4EffectOwnershipDecompositionM4202.ps1'-in$evolvedPaths-and'governance/automation/mir4-command-inventory-v1.json'-in$evolvedPaths) 'evolved-authority-bindings'

$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100
Assert-MIR4M4202CompilerOrchestrator (@($manifest.bindings).Count-eq441) 'manifest-binding-count'
Assert-MIR4M4202CompilerOrchestrator (@($manifest.bindings|ForEach-Object{"$($_.layer)|$($_.output_path)"}|Sort-Object -Unique).Count-eq441) 'manifest-binding-uniqueness'

$sourceRoot='src/mod/families/modern/prototypes/mir/pipeline'
$facade=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator.lua")
$responsibilities=@('context_construction','phase_invocation','contract_checks','publication')
$outputs=@('prototypes/mir/pipeline/compiler_orchestrator.lua')+@($responsibilities|ForEach-Object{"prototypes/mir/pipeline/compiler_orchestrator/$_.lua"})
foreach($responsibility in $responsibilities){
  Assert-MIR4M4202CompilerOrchestrator ($facade-match"compiler_orchestrator[.]$responsibility") "facade-import-$responsibility"
  Assert-MIR4M4202CompilerOrchestrator (Test-Path -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/$responsibility.lua") -PathType Leaf) "module-$responsibility"
}
foreach($member in @('compile','apply_streams','apply_base_extensions','snapshot','assert_output','publish')){
  Assert-MIR4M4202CompilerOrchestrator ($facade-match"function M[.]$member\(") "facade-member-$member"
}
$context=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/context_construction.lua")
$phases=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/phase_invocation.lua")
$contracts=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/contract_checks.lua")
$publication=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/publication.lua")
Assert-MIR4M4202CompilerOrchestrator ($context-match'function M[.]compile\('-and$context-notmatch'function M[.]publish\(') 'context-construction-boundary'
Assert-MIR4M4202CompilerOrchestrator ($phases-match'function M[.]apply_streams\('-and$phases-match'function M[.]apply_base_extensions\('-and$phases-notmatch'function M[.]assert_output\(') 'phase-invocation-boundary'
Assert-MIR4M4202CompilerOrchestrator ($contracts-match'function M[.]snapshot\('-and$contracts-match'function M[.]assert_output\('-and$contracts-notmatch'function M[.]publish\(') 'contract-check-boundary'
Assert-MIR4M4202CompilerOrchestrator ($publication-match'function M[.]publish\('-and$publication-notmatch'function M[.]apply_streams\(') 'publication-boundary'
Assert-MIR4M4202CompilerOrchestrator (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator.lua")).Count-le15) 'facade-size'
Assert-MIR4M4202CompilerOrchestrator (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/context_construction.lua")).Count-le180) 'context-construction-size'
Assert-MIR4M4202CompilerOrchestrator (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/phase_invocation.lua")).Count-le50) 'phase-invocation-size'
Assert-MIR4M4202CompilerOrchestrator (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/contract_checks.lua")).Count-le120) 'contract-checks-size'
Assert-MIR4M4202CompilerOrchestrator (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compiler_orchestrator/publication.lua")).Count-le180) 'publication-size'
$rows=@($manifest.bindings|Where-Object{[string]$_.layer-ceq'families.modern'-and[string]$_.output_path-in$outputs})
Assert-MIR4M4202CompilerOrchestrator ($rows.Count-eq5-and@($rows|Where-Object{@($_.target_scope)-join'|'-cne'f210|f200'}).Count-eq0) 'package-bindings'
foreach($row in $rows){Assert-MIR4M4202CompilerOrchestrator ((Get-FileHash -LiteralPath (Join-Path $repo ([string]$row.source_path)) -Algorithm SHA256).Hash-ceq[string]$row.source_sha256) "source-hash-$([string]$row.output_path)"}
foreach($target in @('f210','f200','f110','f100')){
  $targetRows=@($receipt.target_proof|Where-Object{[string]$_.target-ceq$target})
  Assert-MIR4M4202CompilerOrchestrator ($targetRows.Count-eq1-and[string]$targetRows[0].archive_a-ceq[string]$targetRows[0].archive_b-and[bool]$targetRows[0].deterministic_archive_bytes) "target-determinism-$target"
  $modern=$target-in@('f210','f200');$expectedDelta=if($modern){26}else{0}
  Assert-MIR4M4202CompilerOrchestrator ([int]$targetRows[0].entry_count_delta-eq$expectedDelta-and[bool]$targetRows[0].baseline_match-eq(-not$modern)) "target-delta-$target"
}
$runtime=$receipt.runtime_proof;$f210=@($receipt.target_proof|Where-Object{[string]$_.target-ceq'f210'})
Assert-MIR4M4202CompilerOrchestrator ([string]$runtime.engine.selection-ceq'latest-installed-official-2.1-experimental'-and[string]$runtime.engine.review_status-ceq'current-reviewed'-and-not[bool]$runtime.cross_patch_reuse) 'rolling-runtime-engine-proof'
Assert-MIR4M4202CompilerOrchestrator ([string]$runtime.candidate.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256-and[string]$runtime.candidate.archive_sha256-ceq[string]$f210[0].archive_a-and[string]$runtime.scenario.name-ceq'compiler-contracts'-and[string]$runtime.scenario.status-ceq'passed') 'runtime-candidate-proof'
Assert-MIR4M4202CompilerOrchestrator ([string]$runtime.custody.logical_root-notmatch'^[A-Za-z]:\\'-and-not[bool]$runtime.custody.raw_log_retained-and[int]$runtime.custody.evidence_files-eq4) 'runtime-custody-proof'
Assert-MIR4M4202CompilerOrchestrator (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0-and@($runtime.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-gates'
Assert-MIR4M4202CompilerOrchestrator ([bool]$receipt.preservation.semantics-and[bool]$receipt.preservation.plans-and[bool]$receipt.preservation.mutation_journals-and[bool]$receipt.preservation.historical_4_0_baseline) 'preservation'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-compiler-orchestrator-decomposition-m42-02-l6';responsibility=[string]$receipt.responsibility;modules=@($receipt.modules).Count;modern_entry_delta=26;legacy_entry_delta=0;package_source_sha256=[string]$receipt.package_authority.package_source_sha256;record_sha256=[string]$receipt.record_sha256;version_allocation=$false;publication=$false}|ConvertTo-Json -Depth 10
