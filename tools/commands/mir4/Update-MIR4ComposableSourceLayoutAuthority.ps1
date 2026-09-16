[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt='',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/assurance/Hashing.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/SourceCompositionProof.ps1')

$authorityRelative='governance/repository/composable-source-layout-v1.json'
$proofRelative='assurance/repository/composable-source-layout-v1.json'
$schemaRelative='contracts/repository/mir4-composable-source-layout-migration-v1.schema.json'
$outputRelative='assurance/repository/composable-source-layout-receipt-v1.json'
$predecessorCommit='92d563ada31e82430fbf25f639267b03a8a180d1'
$predecessorManifestPath='src/mod/package-source.json'
$predecessorManifestHash='8BDB2B9D3D63A5FBD49556609D6A7371B2BF11FA1D5F15BFD696E4C17EA3EF5E'
$predecessorPackageSourceFingerprint='BD29DCCC6818E3B2593B2DD182E62F8AA68827EC58E1E27AC1CBA915C582AF57'

function Read-MIR4ComposableLayoutJson([string]$Relative){
  $path=Join-Path $repo $Relative
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-composable-layout-missing] $Relative"}
  Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100 -DateKind String
}
function Get-MIR4ComposableLayoutBinding([string]$Relative){
  [ordered]@{path=$Relative;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $Relative))}
}

$authority=Read-MIR4ComposableLayoutJson $authorityRelative
$proofPolicy=Read-MIR4ComposableLayoutJson $proofRelative
if([string]$authority.kind-cne'MIR4ComposableSourceLayoutAuthorityV1'-or[string]$authority.migration_id-cne'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1'){throw '[mir4-composable-layout-authority]'}
if([string]$proofPolicy.kind-cne'MIR4ComposableSourceLayoutProofPolicyV1'-or[string]$proofPolicy.test_id-cne'static.mir4-composable-source-layout-v1'){throw '[mir4-composable-layout-proof-policy]'}

$predecessorBytes=Read-MIR4GitBlobBytes -RepoRoot $repo -Commit $predecessorCommit -RelativePath $predecessorManifestPath
$predecessorText=([Text.UTF8Encoding]::new($false,$true)).GetString($predecessorBytes)
$predecessor=$predecessorText|ConvertFrom-Json -Depth 100 -DateKind String
if([string]$predecessor.record_sha256-cne$predecessorManifestHash-or@($predecessor.bindings).Count-ne447-or@($predecessor.bindings.source_path|Sort-Object -Unique).Count-ne447){throw '[mir4-composable-layout-predecessor]'}
$observedPredecessorPackageSourceFingerprint=Get-MIRAssuranceCommitPackageSourceHash -Commit $predecessorCommit
if($observedPredecessorPackageSourceFingerprint-cne$predecessorPackageSourceFingerprint){throw '[mir4-composable-layout-predecessor-package-source]'}
$divergentGroups=@($predecessor.bindings|Group-Object output_path|Where-Object{
  @($_.Group|Where-Object{$_.source_path-like'src/mod/families/modern/*'}).Count-gt0-and
  @($_.Group|Where-Object{$_.source_path-like'src/mod/families/legacy/*'}).Count-gt0
})
if($divergentGroups.Count-ne75){throw '[mir4-composable-layout-factorio1-divergence]'}

$manifest=Read-MIR4ComposableLayoutJson 'source/package-source.json'
$packageAuthority=Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
$registry=Read-MIR4ComposableLayoutJson 'targets/registry.json'
$currentPackageSourceFingerprint=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
if(-not(Test-MIR4BootstrapRecordHash $manifest)-or-not(Test-MIR4BootstrapRecordHash $packageAuthority)-or-not(Test-MIR4BootstrapRecordHash $registry)){throw '[mir4-composable-layout-current-record]'}
$sourcePaths=@($manifest.bindings.source_path|Sort-Object -Unique -CaseSensitive)
$predecessorPaths=@($manifest.bindings.predecessor_source_path|Sort-Object -Unique -CaseSensitive)
if(@($manifest.bindings).Count-ne447-or$sourcePaths.Count-ne439-or$predecessorPaths.Count-ne447-or[string]$manifest.predecessor_record_sha256-cne$predecessorManifestHash){throw '[mir4-composable-layout-current-cardinality]'}
$predecessorProof=Get-MIR4ComposableSourcePredecessorProof -RepoRoot $repo -PredecessorCommit $predecessorCommit
if(-not(Test-MIR4BootstrapRecordHash $predecessorProof)-or[int]$predecessorProof.binding_count-ne447-or[int]$predecessorProof.physical_source_count-ne439-or-not[bool]$predecessorProof.invariants.binary_safe_git_blob_reads-or-not[bool]$predecessorProof.invariants.resolver_round_trip_complete){throw '[mir4-composable-layout-predecessor-proof]'}

$targetBindings=[Collections.Generic.List[object]]::new()
foreach($target in @('f210','f200','f110','f100')){
  $relative="targets/$target/composition.json"
  $composition=Read-MIR4ComposableLayoutJson $relative
  if(-not(Test-MIR4BootstrapRecordHash $composition)-or[string]$composition.target-cne$target){throw "[mir4-composable-layout-composition] $target"}
  $targetBindings.Add([ordered]@{target=$target;path=$relative;record_sha256=[string]$composition.record_sha256})
}

$materialized=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot 'build/packages' -ReportPath 'build/reports/package-source/composable-source-layout-v1.json'
$expected=[ordered]@{
  f210='56670789F9A759EC81B09214C996B58F07A072B49D5B161228618226A778C852|337'
  f200='0FF10FEA35841F9484735C76ECF37F8D52D0AD723D5C66DD693096FAA5891D82|335'
  f110='A95978CA68F33C1685DB0C420B7EF4F50155642D666CEE3ECB9D38FB59078132|174'
  f100='CC6ED492EC3F79A6838DF48D9D8AF304A6B4A4BAF706E27F18EB468C844588D8|174'
}
$targetParity=[Collections.Generic.List[object]]::new()
foreach($target in @('f210','f200','f110','f100')){
  $row=@($materialized.targets|Where-Object target -CEQ $target)
  if($row.Count-ne1-or"$($row[0].content_sha256)|$($row[0].entry_count)"-cne$expected[$target]-or-not[bool]$row[0].deterministic_archive_bytes){throw "[mir4-composable-layout-target-parity] $target"}
  $targetParity.Add([ordered]@{target=$target;content_sha256=[string]$row[0].content_sha256;entry_count=[int]$row[0].entry_count;deterministic_archive_bytes=$true})
}

$outputPath=Join-Path $repo $outputRelative
if($Check){
  if(-not(Test-Path -LiteralPath $outputPath -PathType Leaf)){throw '[mir4-composable-layout-receipt-missing]'}
  $RecordedAt=[string](Get-Content -Raw -LiteralPath $outputPath|ConvertFrom-Json -Depth 100 -DateKind String).recorded_at
}elseif([string]::IsNullOrWhiteSpace($RecordedAt)){
  $RecordedAt=[DateTimeOffset]::Now.ToString('o')
}
$record=[ordered]@{
  schema=1
  kind='MIR4ComposableSourceLayoutMigrationV1'
  recorded_at=$RecordedAt
  status='passed-byte-preserving-source-composition-cutover'
  migration_id='MIR4-COMPOSABLE-SOURCE-LAYOUT-V1'
  authority=Get-MIR4ComposableLayoutBinding $authorityRelative
  proof_policy=Get-MIR4ComposableLayoutBinding $proofRelative
  predecessor=[ordered]@{branch='dev';commit=$predecessorCommit;package_source_fingerprint_sha256=$predecessorPackageSourceFingerprint;manifest_path=$predecessorManifestPath;manifest_record_sha256=$predecessorManifestHash;binding_count=447;physical_source_count=447}
  current=[ordered]@{
    source_root='source'
    package_source_fingerprint_sha256=$currentPackageSourceFingerprint
    manifest=[ordered]@{path='source/package-source.json';sha256=[string]$manifest.record_sha256}
    package_authority=[ordered]@{path='targets/package-authority.json';sha256=[string]$packageAuthority.record_sha256}
    target_registry=[ordered]@{path='targets/registry.json';sha256=[string]$registry.record_sha256}
    target_compositions=@($targetBindings)
    sole_writer='tools/mir/application/package/TargetMaterializer.ps1'
  }
  predecessor_proof=[ordered]@{implementation='tools/mir/application/package/SourceCompositionProof.ps1';schema='spec/schemas/mir4-composable-source-predecessor-proof-v1.schema.json';commit=$predecessorCommit;binding_count=[int]$predecessorProof.binding_count;physical_source_count=[int]$predecessorProof.physical_source_count;record_sha256=[string]$predecessorProof.record_sha256}
  relocation=[ordered]@{binding_count=447;physical_source_count=439;deduplicated_binding_count=8;unique_predecessor_path_count=447;old_live_root_absent=$true;era_lane_directories_absent=$true;target_payload_directories_empty=$true;exact_predecessor_resolution=$true}
  target_parity=@($targetParity)
  compatibility_convergence=[ordered]@{factorio_1_state='explicit-compatibility-code-pending-characterized-convergence';divergent_predecessor_same_output_modules=75;next_action='replace characterized duplicates with shared canonical modules plus exact engine adapters';claim='layout-cutover-does-not-claim-zero-compatibility-duplication'}
  invariants=[ordered]@{package_bytes_unchanged=$true;historical_records_rewritten=$false;single_editable_source_root=$true;single_package_writer=$true;gameplay_semantics_changed=$false}
  transition_gate=[ordered]@{development_merge=$true;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  record_sha256=''
}
$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record ([pscustomobject]$record)
$json=(ConvertTo-MIR4BootstrapCanonicalJson -Value $record)+"`n"
if(-not($json|Test-Json -SchemaFile (Join-Path $repo $schemaRelative))){throw '[mir4-composable-layout-receipt-schema]'}
if($Check){
  if([IO.File]::ReadAllText($outputPath).Replace("`r`n","`n")-cne$json){throw '[mir4-composable-layout-receipt-stale]'}
}else{
  [IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;record_sha256=$record.record_sha256;bindings=447;physical_sources=439;deduplicated_bindings=8;targets=4}
