# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tests/compiler/support/MIR4M4202PackageSuccession.ps1')

function Assert-MIR4M4202TechnologyCatalog([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir4-m42-02-technology-catalog-test] $Code"}}

$receiptPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
$schemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
$raw=Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4M4202TechnologyCatalog ($raw|Test-Json -SchemaFile $schemaPath) 'receipt-schema'
$receipt=$raw|ConvertFrom-Json -Depth 100 -DateKind String
Assert-MIR4M4202TechnologyCatalog (Test-MIR4BootstrapRecordHash -Record $receipt) 'receipt-hash'
$currentPackageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$expectedManifestBindings=434
if([string]$receipt.package_authority.package_source_sha256-cne$currentPackageSource){
  $successorPath=Join-Path $repo 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
  $successorSchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
  Assert-MIR4M4202TechnologyCatalog (Test-Path -LiteralPath $successorPath -PathType Leaf) 'package-source-successor-receipt'
  $successorRaw=Get-Content -Raw -LiteralPath $successorPath
  Assert-MIR4M4202TechnologyCatalog ($successorRaw|Test-Json -SchemaFile $successorSchemaPath) 'package-source-successor-schema'
  $successor=$successorRaw|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR4M4202TechnologyCatalog (Test-MIR4BootstrapRecordHash -Record $successor) 'package-source-successor-hash'
  Assert-MIR4M4202TechnologyCatalog ([string]$successor.predecessor.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256) 'package-source-successor-predecessor'
  if([string]$successor.package_authority.package_source_sha256-cne$currentPackageSource){
    $l6Path=Join-Path $repo 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
    $l6SchemaPath=Join-Path $repo 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
    Assert-MIR4M4202TechnologyCatalog (Test-Path -LiteralPath $l6Path -PathType Leaf) 'package-source-l6-successor-receipt'
    $l6Raw=Get-Content -Raw -LiteralPath $l6Path
    Assert-MIR4M4202TechnologyCatalog ($l6Raw|Test-Json -SchemaFile $l6SchemaPath) 'package-source-l6-successor-schema'
    $l6=$l6Raw|ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR4M4202TechnologyCatalog (Test-MIR4BootstrapRecordHash -Record $l6) 'package-source-l6-successor-hash'
    Assert-MIR4M4202TechnologyCatalog ([string]$l6.predecessor.package_source_sha256-ceq[string]$successor.package_authority.package_source_sha256-and(Test-MIR4M4202PackageSourceSuccession -RepoRoot $repo -PredecessorSha256 ([string]$l6.package_authority.package_source_sha256) -CurrentSha256 $currentPackageSource)) 'package-source-l6-successor-chain'
    $expectedManifestBindings=441
  }else{$expectedManifestBindings=437}
}
$evolvedPaths=@($receipt.evolved_bindings|ForEach-Object{[string]$_.path})
Assert-MIR4M4202TechnologyCatalog ($evolvedPaths.Count-eq14-and@($evolvedPaths|Sort-Object -Unique).Count-eq14-and'.mir/control/paths.yml'-in$evolvedPaths-and'.mir/modules.yml'-in$evolvedPaths-and'tests/compiler/Test-MIR4StreamCompilerDecompositionM4202.ps1'-in$evolvedPaths-and'governance/automation/mir4-command-inventory-v1.json'-in$evolvedPaths) 'evolved-authority-bindings'

$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json')|ConvertFrom-Json -Depth 100
Assert-MIR4M4202TechnologyCatalog (@($manifest.bindings).Count-eq$expectedManifestBindings) 'manifest-binding-count'
Assert-MIR4M4202TechnologyCatalog (@($manifest.bindings|ForEach-Object{"$($_.layer)|$($_.output_path)"}|Sort-Object -Unique).Count-eq$expectedManifestBindings) 'manifest-binding-uniqueness'

$sourceRoot='src/mod/families/modern/prototypes/mir/planner'
$facade=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog.lua")
Assert-MIR4M4202TechnologyCatalog ($facade-match'technology_catalog[.]build'-and$facade-match'technology_catalog[.]validate'-and$facade-match'technology_catalog[.]query'-and$facade-notmatch'function\s') 'thin-facade'
$responsibilities=@('model','index','query','build','validate')
$outputs=@('prototypes/mir/planner/technology_catalog.lua')+@($responsibilities|ForEach-Object{"prototypes/mir/planner/technology_catalog/$_.lua"})
foreach($responsibility in $responsibilities){
  Assert-MIR4M4202TechnologyCatalog (Test-Path -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog/$responsibility.lua") -PathType Leaf) "module-$responsibility"
}
$build=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog/build.lua")
foreach($owner in @('model','validate')){Assert-MIR4M4202TechnologyCatalog ($build-match"technology_catalog[.]$owner") "build-import-$owner"}
Assert-MIR4M4202TechnologyCatalog ($build-notmatch'local function candidate_catalog_material'-and$build-notmatch'local function verify') 'build-boundary'
$validate=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog/validate.lua")
foreach($owner in @('index','model')){Assert-MIR4M4202TechnologyCatalog ($validate-match"technology_catalog[.]$owner") "validate-import-$owner"}
Assert-MIR4M4202TechnologyCatalog ($validate-notmatch'function M[.]from_preselection_rows'-and$validate-notmatch'function M[.]authority_projection') 'validate-boundary'
Assert-MIR4M4202TechnologyCatalog (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog.lua")).Count-le25) 'facade-size'
Assert-MIR4M4202TechnologyCatalog (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog/build.lua")).Count-le200) 'build-size'
Assert-MIR4M4202TechnologyCatalog (@(Get-Content -LiteralPath (Join-Path $repo "$sourceRoot/technology_catalog/validate.lua")).Count-le180) 'validate-size'
$catalogRows=@($manifest.bindings|Where-Object{[string]$_.layer-ceq'families.modern'-and[string]$_.output_path-in$outputs})
Assert-MIR4M4202TechnologyCatalog ($catalogRows.Count-eq6-and@($catalogRows|Where-Object{@($_.target_scope)-join'|'-cne'f210|f200'}).Count-eq0) 'package-bindings'
foreach($row in $catalogRows){
  $source=Join-Path $repo ([string]$row.source_path)
  Assert-MIR4M4202TechnologyCatalog ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash-ceq[string]$row.source_sha256) "source-hash-$([string]$row.output_path)"
}
$serialize=Get-Content -Raw -LiteralPath (Join-Path $repo "$sourceRoot/compilation_plan/serialize.lua")
Assert-MIR4M4202TechnologyCatalog ($serialize-match'^local fingerprint = require\("prototypes[.]mir[.]core[.]fingerprint"\)'-and$serialize-notmatch'input_sanitation_fingerprint\s*=\s*require\(') 'eager-cross-mod-dependency-binding'
Assert-MIR4M4202TechnologyCatalog (@($receipt.corrective_bindings).Count-eq1-and[string]$receipt.corrective_bindings[0].output_path-ceq'prototypes/mir/planner/compilation_plan/serialize.lua') 'corrective-binding-receipt'

foreach($target in @('f210','f200','f110','f100')){
  $rows=@($receipt.target_proof|Where-Object{[string]$_.target-ceq$target})
  Assert-MIR4M4202TechnologyCatalog ($rows.Count-eq1-and[string]$rows[0].archive_a-ceq[string]$rows[0].archive_b-and[bool]$rows[0].deterministic_archive_bytes) "target-determinism-$target"
  $modern=$target-in@('f210','f200')
  $expectedDelta=if($modern){19}else{0}
  Assert-MIR4M4202TechnologyCatalog ([int]$rows[0].entry_count_delta-eq$expectedDelta-and[bool]$rows[0].baseline_match-eq(-not$modern)) "target-delta-$target"
}
$runtime=$receipt.runtime_proof
$f210Proof=@($receipt.target_proof|Where-Object{[string]$_.target-ceq'f210'})
Assert-MIR4M4202TechnologyCatalog ([string]$runtime.engine.selection-ceq'latest-installed-official-2.1-experimental'-and[string]$runtime.engine.review_status-ceq'current-reviewed'-and-not[bool]$runtime.cross_patch_reuse) 'rolling-runtime-engine-proof'
Assert-MIR4M4202TechnologyCatalog ([string]$runtime.candidate.package_source_sha256-ceq[string]$receipt.package_authority.package_source_sha256-and[string]$runtime.candidate.archive_sha256-ceq[string]$f210Proof[0].archive_a-and[string]$runtime.scenario.name-ceq'compiler-contracts'-and[string]$runtime.scenario.status-ceq'passed') 'runtime-candidate-proof'
Assert-MIR4M4202TechnologyCatalog ([string]$runtime.custody.logical_root-notmatch'^[A-Za-z]:\\'-and-not[bool]$runtime.custody.raw_log_retained-and[int]$runtime.custody.evidence_files-eq4) 'runtime-custody-proof'
Assert-MIR4M4202TechnologyCatalog (@($receipt.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0-and@($runtime.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) 'release-gates'
Assert-MIR4M4202TechnologyCatalog ([bool]$receipt.preservation.semantics-and[bool]$receipt.preservation.plans-and[bool]$receipt.preservation.mutation_journals-and[bool]$receipt.preservation.historical_4_0_baseline) 'preservation'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-technology-catalog-decomposition-m42-02-l4';responsibility=[string]$receipt.responsibility;modules=@($receipt.modules).Count;modern_entry_delta=19;legacy_entry_delta=0;package_source_sha256=[string]$receipt.package_authority.package_source_sha256;record_sha256=[string]$receipt.record_sha256;version_allocation=$false;publication=$false}|ConvertTo-Json -Depth 10
