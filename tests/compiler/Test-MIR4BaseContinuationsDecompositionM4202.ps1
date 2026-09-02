# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

function Assert-MIR4M4202BaseContinuations([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-base-continuations-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-base-continuations-decomposition-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202BaseContinuations ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202BaseContinuations (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-hash'
$currentPackageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$expectedManifestBindings=419
if([string]$receipt.package_authority.package_source_sha256-cne$currentPackageSource){
  $successorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json'
  $successorSchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'
  Assert-MIR4M4202BaseContinuations (Test-Path -LiteralPath $successorPath -PathType Leaf) 'package-source-successor-receipt'
  $successorRaw=Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202BaseContinuations ($successorRaw|Test-Json -SchemaFile $successorSchemaPath) 'package-source-successor-schema'
  $successor=$successorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202BaseContinuations (Test-MIR4BootstrapRecordHash -Record $successor) 'package-source-successor-hash'
  Assert-MIR4M4202BaseContinuations ([string]$successor.predecessor.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256) 'package-source-successor-predecessor'
  if([string]$successor.package_authority.package_source_sha256-cne$currentPackageSource){
    $l4Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
    $l4SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
    Assert-MIR4M4202BaseContinuations (Test-Path -LiteralPath $l4Path -PathType Leaf) 'package-source-l4-successor-receipt'
    $l4Raw=Get-Content -Raw -LiteralPath $l4Path
    Assert-MIR4M4202BaseContinuations ($l4Raw|Test-Json -SchemaFile $l4SchemaPath) 'package-source-l4-successor-schema'
    $l4=$l4Raw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202BaseContinuations (Test-MIR4BootstrapRecordHash -Record $l4) 'package-source-l4-successor-hash'
    Assert-MIR4M4202BaseContinuations ([string]$l4.predecessor.package_source_sha256-ceq[string]$successor.package_authority.package_source_sha256) 'package-source-l4-successor-predecessor'
    if([string]$l4.package_authority.package_source_sha256-cne$currentPackageSource){
      $l5Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
      $l5SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
      Assert-MIR4M4202BaseContinuations (Test-Path -LiteralPath $l5Path -PathType Leaf) 'package-source-l5-successor-receipt'
      $l5Raw=Get-Content -Raw -LiteralPath $l5Path
      Assert-MIR4M4202BaseContinuations ($l5Raw|Test-Json -SchemaFile $l5SchemaPath) 'package-source-l5-successor-schema'
      $l5=$l5Raw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4M4202BaseContinuations (Test-MIR4BootstrapRecordHash -Record $l5) 'package-source-l5-successor-hash'
      Assert-MIR4M4202BaseContinuations ([string]$l5.predecessor.package_source_sha256-ceq[string]$l4.package_authority.package_source_sha256) 'package-source-l5-successor-predecessor'
      if([string]$l5.package_authority.package_source_sha256-cne$currentPackageSource){
        $l6Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
        $l6SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
        Assert-MIR4M4202BaseContinuations (Test-Path -LiteralPath $l6Path -PathType Leaf) 'package-source-l6-successor-receipt'
        $l6Raw=Get-Content -Raw -LiteralPath $l6Path
        Assert-MIR4M4202BaseContinuations ($l6Raw|Test-Json -SchemaFile $l6SchemaPath) 'package-source-l6-successor-schema'
        $l6=$l6Raw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4M4202BaseContinuations (Test-MIR4BootstrapRecordHash -Record $l6) 'package-source-l6-successor-hash'
        Assert-MIR4M4202BaseContinuations ([string]$l6.predecessor.package_source_sha256-ceq[string]$l5.package_authority.package_source_sha256-and[string]$l6.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-l6-successor-chain'
        $expectedManifestBindings=441
      }else{$expectedManifestBindings=437}
    }else{
      $expectedManifestBindings=434
    }
  }else{
    $expectedManifestBindings=429
  }
}

$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100
Assert-MIR4M4202BaseContinuations (@($manifest.bindings).Count-eq$expectedManifestBindings) 'manifest-binding-count'
Assert-MIR4M4202BaseContinuations (@($manifest.bindings|ForEach-Object{"$($_.layer)|$($_.output_path)"}|Sort-Object -Unique).Count-eq$expectedManifestBindings) 'manifest-binding-uniqueness'

$outputs=@('prototypes/mir/planner/base_continuations.lua','prototypes/mir/planner/base_continuations/classify.lua','prototypes/mir/planner/base_continuations/discover.lua','prototypes/mir/planner/base_continuations/qualify.lua','prototypes/mir/planner/base_continuations/plan.lua')
foreach($target in @('f210','f200')){
  $sourceRoot="targets/$target/files/prototypes/mir/planner"
  $facade=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/base_continuations.lua")
  Assert-MIR4M4202BaseContinuations ($facade-match'base_continuations[.]plan'-and$facade-notmatch'function\s') "thin-facade-$target"
  Assert-MIR4M4202BaseContinuations (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/base_continuations.lua")).Count-le5) "facade-size-$target"
  foreach($responsibility in @('classify','discover','qualify','plan')){
    Assert-MIR4M4202BaseContinuations (Test-Path -LiteralPath (Join-Path $repo "$sourceRoot/base_continuations/$responsibility.lua") -PathType Leaf) "module-$target-$responsibility"
  }
  $plan=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/base_continuations/plan.lua")
  foreach($owner in @('classify','discover','qualify')){Assert-MIR4M4202BaseContinuations ($plan-match"base_continuations[.]$owner") "plan-import-$target-$owner"}
  foreach($superseded in @('local function rejected_candidate','local function find_equivalent_infinite_extension','local function resolve_science_packs','local function build_prerequisites')){Assert-MIR4M4202BaseContinuations ($plan-notmatch[regex]::Escape($superseded)) "duplicate-responsibility-$target-$superseded"}
  Assert-MIR4M4202BaseContinuations (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/base_continuations/plan.lua")).Count-le400) "plan-size-$target"
  $targetRows=@($manifest.bindings|Where-Object{[string]$_.layer-ceq"targets.$target"-and[string]$_.output_path-in$outputs})
  Assert-MIR4M4202BaseContinuations ($targetRows.Count-eq5) "target-binding-count-$target"
}

$f210Qualify=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/f210/files/prototypes/mir/planner/base_continuations/qualify.lua')
$f200Qualify=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/f200/files/prototypes/mir/planner/base_continuations/qualify.lua')
Assert-MIR4M4202BaseContinuations ($f210Qualify-match'planner_science[.]normalize_ingredients'-and$f200Qualify-notmatch'planner_science') 'target-science-policy-preserved'
foreach($shared in @('classify.lua','discover.lua')){
  $f210Hash=(Get-FileHash -LiteralPath (Join-Path $repo "targets/f210/files/prototypes/mir/planner/base_continuations/$shared") -Algorithm SHA256).Hash
  $f200Hash=(Get-FileHash -LiteralPath (Join-Path $repo "targets/f200/files/prototypes/mir/planner/base_continuations/$shared") -Algorithm SHA256).Hash
  Assert-MIR4M4202BaseContinuations ($f210Hash-ceq$f200Hash) "shared-target-behavior-$shared"
}

foreach($target in @('f210','f200','f110','f100')){
  $rows=@($receipt.target_proof|Where-Object{[string]$_.target-ceq$target})
  Assert-MIR4M4202BaseContinuations ($rows.Count-eq1-and[string]$rows[0].archive_a-ceq[string]$rows[0].archive_b-and[bool]$rows[0].deterministic_archive_bytes) "target-determinism-$target"
  $modern=$target-in@('f210','f200')
  $expectedDelta=if($modern){9}else{0}
  Assert-MIR4M4202BaseContinuations ([int]$rows[0].entry_count_delta-eq$expectedDelta-and[bool]$rows[0].baseline_match-eq(-not$modern)) "target-delta-$target"
}

$runtime=$receipt.runtime_proof
$f210Proof=@($receipt.target_proof|Where-Object{[string]$_.target-ceq'f210'})
Assert-MIR4M4202BaseContinuations ([string]$runtime.engine.selection-ceq'latest-installed-official-2.1-experimental'-and[string]$runtime.engine.review_status-ceq'current-reviewed'-and-not[bool]$runtime.cross_patch_reuse) 'rolling-runtime-engine-proof'
Assert-MIR4M4202BaseContinuations ([string]$runtime.candidate.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256-and[string]$runtime.candidate.archive_sha256-ceq[string]$f210Proof[0].archive_a-and[string]$runtime.scenario.status-ceq'passed') 'runtime-candidate-proof'
Assert-MIR4M4202BaseContinuations ([string]$runtime.custody.logical_root-notmatch'^[A-Za-z]:\\'-and-not[bool]$runtime.custody.raw_log_retained-and[int]$runtime.custody.evidence_files-eq4) 'runtime-custody-proof'
Assert-MIR4M4202BaseContinuations (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0-and@($runtime.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-gates'
Assert-MIR4M4202BaseContinuations ([bool]$receipt.preservation.semantics-and[bool]$receipt.preservation.plans-and[bool]$receipt.preservation.mutation_journals-and[bool]$receipt.preservation.historical_4_0_baseline) 'preservation'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-base-continuations-decomposition-m42-02-l2';responsibility=[string]$receipt.responsibility;target_module_sets=2;modern_entry_delta=9;legacy_entry_delta=0;package_source_sha256=[string]$receipt.package_authority.package_source_sha256;record_sha256=[string]$receipt.record_sha256;version_allocation=$false;publication=$false}|ConvertTo-Json -Depth 10
