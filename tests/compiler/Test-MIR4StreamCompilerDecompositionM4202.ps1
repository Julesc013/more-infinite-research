# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

function Assert-MIR4M4202StreamCompiler([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-stream-compiler-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202StreamCompiler ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202StreamCompiler (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-hash'
$currentPackageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$expectedManifestBindings=429
if([string]$receipt.package_authority.package_source_sha256-cne$currentPackageSource){
  $successorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
  $successorSchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
  Assert-MIR4M4202StreamCompiler (Test-Path -LiteralPath $successorPath -PathType Leaf) 'package-source-successor-receipt'
  $successorRaw=Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202StreamCompiler ($successorRaw|Test-Json -SchemaFile $successorSchemaPath) 'package-source-successor-schema'
  $successor=$successorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202StreamCompiler (Test-MIR4BootstrapRecordHash -Record $successor) 'package-source-successor-hash'
  Assert-MIR4M4202StreamCompiler ([string]$successor.predecessor.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256) 'package-source-successor-predecessor'
  if([string]$successor.package_authority.package_source_sha256-cne$currentPackageSource){
    $l5Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
    $l5SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
    Assert-MIR4M4202StreamCompiler (Test-Path -LiteralPath $l5Path -PathType Leaf) 'package-source-l5-successor-receipt'
    $l5Raw=Get-Content -Raw -LiteralPath $l5Path
    Assert-MIR4M4202StreamCompiler ($l5Raw|Test-Json -SchemaFile $l5SchemaPath) 'package-source-l5-successor-schema'
    $l5=$l5Raw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202StreamCompiler (Test-MIR4BootstrapRecordHash -Record $l5) 'package-source-l5-successor-hash'
    Assert-MIR4M4202StreamCompiler ([string]$l5.predecessor.package_source_sha256-ceq[string]$successor.package_authority.package_source_sha256) 'package-source-l5-successor-predecessor'
    if([string]$l5.package_authority.package_source_sha256-cne$currentPackageSource){
      $l6Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
      $l6SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
      Assert-MIR4M4202StreamCompiler (Test-Path -LiteralPath $l6Path -PathType Leaf) 'package-source-l6-successor-receipt'
      $l6Raw=Get-Content -Raw -LiteralPath $l6Path
      Assert-MIR4M4202StreamCompiler ($l6Raw|Test-Json -SchemaFile $l6SchemaPath) 'package-source-l6-successor-schema'
      $l6=$l6Raw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4M4202StreamCompiler (Test-MIR4BootstrapRecordHash -Record $l6) 'package-source-l6-successor-hash'
      Assert-MIR4M4202StreamCompiler ([string]$l6.predecessor.package_source_sha256-ceq[string]$l5.package_authority.package_source_sha256-and[string]$l6.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-l6-successor-chain'
      $expectedManifestBindings=441
    }else{$expectedManifestBindings=437}
  }else{
    $expectedManifestBindings=434
  }
}
$evolvedPaths=@($receipt.evolved_bindings|ForEach-Object{[string]$_.path})
Assert-MIR4M4202StreamCompiler ($evolvedPaths.Count-eq12-and@($evolvedPaths|Sort-Object -Unique).Count-eq12-and'.mir/control/paths.yml'-in$evolvedPaths-and'.mir/modules.yml'-in$evolvedPaths-and'governance/automation/mir4-command-inventory-v1.json'-in$evolvedPaths-and'tests/tooling/Test-MIR4TestWorkflowConvergence.ps1'-in$evolvedPaths) 'evolved-authority-bindings'

$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100
Assert-MIR4M4202StreamCompiler (@($manifest.bindings).Count-eq$expectedManifestBindings) 'manifest-binding-count'
Assert-MIR4M4202StreamCompiler (@($manifest.bindings|ForEach-Object{"$($_.layer)|$($_.output_path)"}|Sort-Object -Unique).Count-eq$expectedManifestBindings) 'manifest-binding-uniqueness'

$responsibilities=@('compile','diagnostics','discover','ownership','qualify')
$outputs=@('prototypes/mir/planner/stream_compiler.lua')+@($responsibilities|ForEach-Object{"prototypes/mir/planner/stream_compiler/$_.lua"})
foreach($target in @('f210','f200')){
  $sourceRoot="targets/$target/files/prototypes/mir/planner"
  $facade=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler.lua")
  Assert-MIR4M4202StreamCompiler ($facade-match'stream_compiler[.]compile'-and$facade-notmatch'function\s') "thin-facade-$target"
  Assert-MIR4M4202StreamCompiler (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler.lua")).Count-le5) "facade-size-$target"
  foreach($responsibility in $responsibilities){
    Assert-MIR4M4202StreamCompiler (Test-Path -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler/$responsibility.lua") -PathType Leaf) "module-$target-$responsibility"
  }
  $compile=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler/compile.lua")
  foreach($owner in @('discover','ownership','qualify')){Assert-MIR4M4202StreamCompiler ($compile-match"stream_compiler[.]$owner") "compile-import-$target-$owner"}
  Assert-MIR4M4202StreamCompiler ($compile-notmatch'local function plan_stream'-and$compile-notmatch'D[.]stream_fields') "compile-boundary-$target"
  Assert-MIR4M4202StreamCompiler (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler/compile.lua")).Count-le130) "compile-size-$target"
  $qualify=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler/qualify.lua")
  foreach($owner in @('discover','ownership','diagnostics')){Assert-MIR4M4202StreamCompiler ($qualify-match"stream_compiler[.]$owner") "qualify-import-$target-$owner"}
  Assert-MIR4M4202StreamCompiler ($qualify-notmatch'compile_active|generation_plan[.]new|context:set_state') "qualify-boundary-$target"
  Assert-MIR4M4202StreamCompiler (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/stream_compiler/qualify.lua")).Count-le250) "qualify-size-$target"
  $targetRows=@($manifest.bindings|Where-Object{[string]$_.layer-ceq"targets.$target"-and[string]$_.output_path-in$outputs})
  Assert-MIR4M4202StreamCompiler ($targetRows.Count-eq6) "target-binding-count-$target"
}

$f210Qualify=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/f210/files/prototypes/mir/planner/stream_compiler/qualify.lua')
$f200Qualify=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/f200/files/prototypes/mir/planner/stream_compiler/qualify.lua')
Assert-MIR4M4202StreamCompiler ($f210Qualify-match'science_phase_decision'-and$f200Qualify-notmatch'science_phase_decision') 'target-science-policy-preserved'
foreach($shared in @('compile.lua','diagnostics.lua','discover.lua','ownership.lua')){
  $f210Hash=(Get-FileHash -LiteralPath (Join-Path $repo "targets/f210/files/prototypes/mir/planner/stream_compiler/$shared") -Algorithm SHA256).Hash
  $f200Hash=(Get-FileHash -LiteralPath (Join-Path $repo "targets/f200/files/prototypes/mir/planner/stream_compiler/$shared") -Algorithm SHA256).Hash
  Assert-MIR4M4202StreamCompiler ($f210Hash-ceq$f200Hash) "shared-target-behavior-$shared"
}

foreach($target in @('f210','f200','f110','f100')){
  $rows=@($receipt.target_proof|Where-Object{[string]$_.target-ceq$target})
  Assert-MIR4M4202StreamCompiler ($rows.Count-eq1-and[string]$rows[0].archive_a-ceq[string]$rows[0].archive_b-and[bool]$rows[0].deterministic_archive_bytes) "target-determinism-$target"
  $modern=$target-in@('f210','f200')
  $expectedDelta=if($modern){14}else{0}
  Assert-MIR4M4202StreamCompiler ([int]$rows[0].entry_count_delta-eq$expectedDelta-and[bool]$rows[0].baseline_match-eq(-not$modern)) "target-delta-$target"
}

$runtime=$receipt.runtime_proof
$f210Proof=@($receipt.target_proof|Where-Object{[string]$_.target-ceq'f210'})
Assert-MIR4M4202StreamCompiler ([string]$runtime.engine.selection-ceq'latest-installed-official-2.1-experimental'-and[string]$runtime.engine.review_status-ceq'current-reviewed'-and-not[bool]$runtime.cross_patch_reuse) 'rolling-runtime-engine-proof'
Assert-MIR4M4202StreamCompiler ([string]$runtime.candidate.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256-and[string]$runtime.candidate.archive_sha256-ceq[string]$f210Proof[0].archive_a-and[string]$runtime.scenario.status-ceq'passed') 'runtime-candidate-proof'
Assert-MIR4M4202StreamCompiler ([string]$runtime.custody.logical_root-notmatch'^[A-Za-z]:\\'-and-not[bool]$runtime.custody.raw_log_retained-and[int]$runtime.custody.evidence_files-eq4) 'runtime-custody-proof'
Assert-MIR4M4202StreamCompiler (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0-and@($runtime.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-gates'
Assert-MIR4M4202StreamCompiler ([bool]$receipt.preservation.semantics-and[bool]$receipt.preservation.plans-and[bool]$receipt.preservation.mutation_journals-and[bool]$receipt.preservation.historical_4_0_baseline) 'preservation'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-stream-compiler-decomposition-m42-02-l3';responsibility=[string]$receipt.responsibility;target_module_sets=2;modern_entry_delta=14;legacy_entry_delta=0;package_source_sha256=[string]$receipt.package_authority.package_source_sha256;record_sha256=[string]$receipt.record_sha256;version_allocation=$false;publication=$false}|ConvertTo-Json -Depth 10
