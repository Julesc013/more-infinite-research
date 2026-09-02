# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

function Assert-MIR4M4202EffectOwnership([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-effect-ownership-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202EffectOwnership ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202EffectOwnership (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-hash'
Assert-MIR4M4202EffectOwnership ([string]$receipt.package_authority.package_source_sha256-ceq(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) 'package-source-fingerprint'
$evolvedPaths=@($receipt.evolved_bindings|ForEach-Object{[string]$_.path})
Assert-MIR4M4202EffectOwnership ($evolvedPaths.Count-eq15-and@($evolvedPaths|Sort-Object -Unique).Count-eq15-and'.mir/control/paths.yml'-in$evolvedPaths-and'.mir/modules.yml'-in$evolvedPaths-and'tests/compiler/Test-MIR4TechnologyCatalogDecompositionM4202.ps1'-in$evolvedPaths-and'governance/automation/mir4-command-inventory-v1.json'-in$evolvedPaths) 'evolved-authority-bindings'

$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100
Assert-MIR4M4202EffectOwnership (@($manifest.bindings).Count-eq437) 'manifest-binding-count'
Assert-MIR4M4202EffectOwnership (@($manifest.bindings|ForEach-Object{"$($_.layer)|$($_.output_path)"}|Sort-Object -Unique).Count-eq437) 'manifest-binding-uniqueness'

$sourceRoot='src/mod/families/modern/prototypes/mir/planner'
$facade=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership.lua")
Assert-MIR4M4202EffectOwnership ($facade-match'effect_ownership[.]resolution'-and$facade-match'effect_ownership[.]planned_operations'-and$facade-notmatch'function\s') 'thin-facade'
$responsibilities=@('facts','resolution','planned_operations')
$outputs=@('prototypes/mir/planner/effect_ownership.lua')+@($responsibilities|ForEach-Object{"prototypes/mir/planner/effect_ownership/$_.lua"})
foreach($responsibility in $responsibilities){
  Assert-MIR4M4202EffectOwnership (Test-Path -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership/$responsibility.lua") -PathType Leaf) "module-$responsibility"
}
$resolution=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership/resolution.lua")
$planned=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership/planned_operations.lua")
foreach($owner in @('facts')){Assert-MIR4M4202EffectOwnership ($resolution-match"effect_ownership[.]$owner") "resolution-import-$owner"}
foreach($owner in @('facts','resolution')){Assert-MIR4M4202EffectOwnership ($planned-match"effect_ownership[.]$owner") "planned-import-$owner"}
Assert-MIR4M4202EffectOwnership ($resolution-match'function M[.]resolve\('-and$planned-match'function M[.]resolve\('-and$resolution-notmatch'function M[.]resolve_operations') 'resolution-boundary'
Assert-MIR4M4202EffectOwnership (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership.lua")).Count-le15) 'facade-size'
Assert-MIR4M4202EffectOwnership (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership/facts.lua")).Count-le160) 'facts-size'
Assert-MIR4M4202EffectOwnership (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership/resolution.lua")).Count-le140) 'resolution-size'
Assert-MIR4M4202EffectOwnership (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/effect_ownership/planned_operations.lua")).Count-le220) 'planned-operations-size'
$ownershipRows=@($manifest.bindings|Where-Object{[string]$_.layer-ceq'families.modern'-and[string]$_.output_path-in$outputs})
Assert-MIR4M4202EffectOwnership ($ownershipRows.Count-eq4-and@($ownershipRows|Where-Object{@($_.target_scope)-join'|'-cne'f210|f200'}).Count-eq0) 'package-bindings'
foreach($row in $ownershipRows){
  $source=Join-Path $repo ([string]$row.source_path)
  Assert-MIR4M4202EffectOwnership ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash-ceq[string]$row.source_sha256) "source-hash-$([string]$row.output_path)"
}
foreach($target in @('f210','f200','f110','f100')){
  $rows=@($receipt.target_proof|Where-Object{[string]$_.target-ceq$target})
  Assert-MIR4M4202EffectOwnership ($rows.Count-eq1-and[string]$rows[0].archive_a-ceq[string]$rows[0].archive_b-and[bool]$rows[0].deterministic_archive_bytes) "target-determinism-$target"
  $modern=$target-in@('f210','f200')
  $expectedDelta=if($modern){22}else{0}
  Assert-MIR4M4202EffectOwnership ([int]$rows[0].entry_count_delta-eq$expectedDelta-and[bool]$rows[0].baseline_match-eq(-not$modern)) "target-delta-$target"
}
$runtime=$receipt.runtime_proof
$f210Proof=@($receipt.target_proof|Where-Object{[string]$_.target-ceq'f210'})
Assert-MIR4M4202EffectOwnership ([string]$runtime.engine.selection-ceq'latest-installed-official-2.1-experimental'-and[string]$runtime.engine.review_status-ceq'current-reviewed'-and-not[bool]$runtime.cross_patch_reuse) 'rolling-runtime-engine-proof'
Assert-MIR4M4202EffectOwnership ([string]$runtime.candidate.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256-and[string]$runtime.candidate.archive_sha256-ceq[string]$f210Proof[0].archive_a-and[string]$runtime.scenario.name-ceq'compiler-contracts'-and[string]$runtime.scenario.status-ceq'passed') 'runtime-candidate-proof'
Assert-MIR4M4202EffectOwnership ([string]$runtime.custody.logical_root-notmatch'^[A-Za-z]:\\'-and-not[bool]$runtime.custody.raw_log_retained-and[int]$runtime.custody.evidence_files-eq4) 'runtime-custody-proof'
Assert-MIR4M4202EffectOwnership (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0-and@($runtime.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-gates'
Assert-MIR4M4202EffectOwnership ([bool]$receipt.preservation.semantics-and[bool]$receipt.preservation.plans-and[bool]$receipt.preservation.mutation_journals-and[bool]$receipt.preservation.historical_4_0_baseline) 'preservation'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-effect-ownership-decomposition-m42-02-l5';responsibility=[string]$receipt.responsibility;modules=@($receipt.modules).Count;modern_entry_delta=22;legacy_entry_delta=0;package_source_sha256=[string]$receipt.package_authority.package_source_sha256;record_sha256=[string]$receipt.record_sha256;version_allocation=$false;publication=$false}|ConvertTo-Json -Depth 10
