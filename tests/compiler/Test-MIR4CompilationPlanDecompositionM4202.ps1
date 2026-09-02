# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

function Assert-MIR4M4202CompilationPlan([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-compilation-plan-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-compilation-plan-decomposition-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202CompilationPlan ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202CompilationPlan (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-hash'
$currentPackageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
if([string]$receipt.package_authority.package_source_sha256-cne$currentPackageSource){
  $successorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json'
  $successorSchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-base-continuations-decomposition-v1.schema.json'
  Assert-MIR4M4202CompilationPlan (Test-Path -LiteralPath $successorPath -PathType Leaf) 'package-source-successor-receipt'
  $successorRaw=Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202CompilationPlan ($successorRaw|Test-Json -SchemaFile $successorSchemaPath) 'package-source-successor-schema'
  $successor=$successorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202CompilationPlan (Test-MIR4BootstrapRecordHash -Record $successor) 'package-source-successor-hash'
  Assert-MIR4M4202CompilationPlan ([string]$successor.predecessor.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256) 'package-source-successor-predecessor'
  if([string]$successor.package_authority.package_source_sha256-cne$currentPackageSource){
    $l3Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json'
    $l3SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'
    Assert-MIR4M4202CompilationPlan (Test-Path -LiteralPath $l3Path -PathType Leaf) 'package-source-l3-successor-receipt'
    $l3Raw=Get-Content -Raw -LiteralPath $l3Path
    Assert-MIR4M4202CompilationPlan ($l3Raw|Test-Json -SchemaFile $l3SchemaPath) 'package-source-l3-successor-schema'
    $l3=$l3Raw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202CompilationPlan (Test-MIR4BootstrapRecordHash -Record $l3) 'package-source-l3-successor-hash'
    Assert-MIR4M4202CompilationPlan ([string]$l3.predecessor.package_source_sha256-ceq[string]$successor.package_authority.package_source_sha256) 'package-source-l3-successor-predecessor'
    if([string]$l3.package_authority.package_source_sha256-cne$currentPackageSource){
      $l4Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
      $l4SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
      Assert-MIR4M4202CompilationPlan (Test-Path -LiteralPath $l4Path -PathType Leaf) 'package-source-l4-successor-receipt'
      $l4Raw=Get-Content -Raw -LiteralPath $l4Path
      Assert-MIR4M4202CompilationPlan ($l4Raw|Test-Json -SchemaFile $l4SchemaPath) 'package-source-l4-successor-schema'
      $l4=$l4Raw|ConvertFrom-Json -Depth 100 -DateKind String
      Assert-MIR4M4202CompilationPlan (Test-MIR4BootstrapRecordHash -Record $l4) 'package-source-l4-successor-hash'
      Assert-MIR4M4202CompilationPlan ([string]$l4.predecessor.package_source_sha256-ceq[string]$l3.package_authority.package_source_sha256) 'package-source-l4-successor-predecessor'
      if([string]$l4.package_authority.package_source_sha256-cne$currentPackageSource){
        $l5Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
        $l5SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
        Assert-MIR4M4202CompilationPlan (Test-Path -LiteralPath $l5Path -PathType Leaf) 'package-source-l5-successor-receipt'
        $l5Raw=Get-Content -Raw -LiteralPath $l5Path
        Assert-MIR4M4202CompilationPlan ($l5Raw|Test-Json -SchemaFile $l5SchemaPath) 'package-source-l5-successor-schema'
        $l5=$l5Raw|ConvertFrom-Json -Depth 100 -DateKind String
        Assert-MIR4M4202CompilationPlan (Test-MIR4BootstrapRecordHash -Record $l5) 'package-source-l5-successor-hash'
        Assert-MIR4M4202CompilationPlan ([string]$l5.predecessor.package_source_sha256-ceq[string]$l4.package_authority.package_source_sha256) 'package-source-l5-successor-predecessor'
        if([string]$l5.package_authority.package_source_sha256-cne$currentPackageSource){
          $l6Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
          $l6SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
          Assert-MIR4M4202CompilationPlan (Test-Path -LiteralPath $l6Path -PathType Leaf) 'package-source-l6-successor-receipt'
          $l6Raw=Get-Content -Raw -LiteralPath $l6Path
          Assert-MIR4M4202CompilationPlan ($l6Raw|Test-Json -SchemaFile $l6SchemaPath) 'package-source-l6-successor-schema'
          $l6=$l6Raw|ConvertFrom-Json -Depth 100 -DateKind String
          Assert-MIR4M4202CompilationPlan (Test-MIR4BootstrapRecordHash -Record $l6) 'package-source-l6-successor-hash'
          Assert-MIR4M4202CompilationPlan ([string]$l6.predecessor.package_source_sha256-ceq[string]$l5.package_authority.package_source_sha256-and[string]$l6.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-l6-successor-chain'
        }else{
          Assert-MIR4M4202CompilationPlan ([string]$l5.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-l5-successor-chain'
        }
      }else{
        Assert-MIR4M4202CompilationPlan ([string]$l4.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-l4-successor-chain'
      }
    }else{
      Assert-MIR4M4202CompilationPlan ([string]$l3.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-l3-successor-chain'
    }
  }else{
    Assert-MIR4M4202CompilationPlan ([string]$successor.package_authority.package_source_sha256-ceq$currentPackageSource) 'package-source-successor-chain'
  }
}

$sourceRoot='src/mod/families/modern/prototypes/mir/planner'
$facade=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compilation_plan.lua")
Assert-MIR4M4202CompilationPlan ($facade-match'compilation_plan[.]build'-and$facade-notmatch'function\s') 'thin-facade'
$required=[ordered]@{model='model.lua';build='build.lua';validate='validate.lua';fingerprint='fingerprint.lua';serialize='serialize.lua'}
foreach($entry in $required.GetEnumerator()){
  $path=Join-Path $repo "$sourceRoot/compilation_plan/$($entry.Value)"
  Assert-MIR4M4202CompilationPlan (Test-Path -LiteralPath $path -PathType Leaf) "module-$($entry.Key)"
}
$build=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compilation_plan/build.lua")
foreach($owner in @('model','validate','fingerprint')){Assert-MIR4M4202CompilationPlan ($build-match"compilation_plan[.]$owner") "build-import-$owner"}
Assert-MIR4M4202CompilationPlan ($build-notmatch'local function validate_operations'-and$build-notmatch'local function compilation_material'-and$build-notmatch'local function default_compiler_input') 'duplicate-responsibility'
Assert-MIR4M4202CompilationPlan (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compilation_plan.lua")).Count-le10) 'facade-size'
Assert-MIR4M4202CompilationPlan (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/compilation_plan/build.lua")).Count-le700) 'build-size-disposition'

foreach($target in @('f210','f200','f110','f100')){
  $rows=@($receipt.target_proof|Where-Object{[string]$_.target-ceq$target})
  Assert-MIR4M4202CompilationPlan ($rows.Count-eq1-and[string]$rows[0].archive_a-ceq[string]$rows[0].archive_b-and[bool]$rows[0].deterministic_archive_bytes) "target-determinism-$target"
  $modern=$target-in@('f210','f200')
  $expectedDelta=if($modern){5}else{0}
  Assert-MIR4M4202CompilationPlan ([int]$rows[0].entry_count_delta-eq$expectedDelta-and[bool]$rows[0].baseline_match-eq(-not$modern)) "target-delta-$target"
}
$runtime=$receipt.runtime_proof
Assert-MIR4M4202CompilationPlan ([string]$runtime.engine.review_status-ceq'current-reviewed'-and[string]$runtime.engine.binary_sha256-ceq'710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8'-and-not[bool]$runtime.cross_patch_reuse) 'runtime-engine-proof'
$f210Proof=@($receipt.target_proof|Where-Object{[string]$_.target-ceq'f210'})
Assert-MIR4M4202CompilationPlan ($f210Proof.Count-eq1-and[string]$runtime.candidate.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256-and[string]$runtime.candidate.archive_sha256-ceq[string]$f210Proof[0].archive_a-and[string]$runtime.scenario.status-ceq'passed') 'runtime-candidate-proof'
Assert-MIR4M4202CompilationPlan ([string]$runtime.custody.logical_root-notmatch'^[A-Za-z]:\\'-and[string]$runtime.custody.manifest_sha256-ceq'4AA386446D601974B8AC3DC09E5FE081373DF904B5A59888374E95266F724505'-and-not[bool]$runtime.custody.raw_log_retained) 'runtime-custody-proof'
Assert-MIR4M4202CompilationPlan (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-gates'
Assert-MIR4M4202CompilationPlan ([bool]$receipt.preservation.semantics-and[bool]$receipt.preservation.plans-and[bool]$receipt.preservation.mutation_journals-and[bool]$receipt.preservation.historical_4_0_baseline) 'preservation'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-compilation-plan-decomposition-m42-02-l1';responsibility=[string]$receipt.responsibility;modules=@($receipt.modules).Count;modern_entry_delta=5;legacy_entry_delta=0;package_source_sha256=[string]$receipt.package_authority.package_source_sha256;record_sha256=[string]$receipt.record_sha256;version_allocation=$false;publication=$false}|ConvertTo-Json -Depth 10
