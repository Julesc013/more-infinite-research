[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$ProofOutputRoot='build/packages',
  [string]$ProofReportPath='build/reports/package-source/mir4-current-source-materializer-v1.json',
  [string]$RuntimeProofPath,
  [switch]$ProjectionOnly,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

function Get-MIR4M4202EffectOwnershipFileIdentity {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-effect-ownership-source] $RelativePath"}
  $bytes=[IO.File]::ReadAllBytes($path)
  [pscustomobject][ordered]@{path=$RelativePath;bytes=[int64]$bytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $bytes);lines=@([IO.File]::ReadAllLines($path)).Count}
}

function Get-MIR4M4202EffectOwnershipTextSha256 {
  param([Parameter(Mandatory)][string]$RelativePath)
  Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath)
}

function ConvertTo-MIR4M4202EffectOwnershipJson {
  param([Parameter(Mandatory)]$Record)
  (($Record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
}

function Set-MIR4M4202EffectOwnershipProjection {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Json)
  $path=Join-Path $repo $RelativePath
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path).Replace("`r`n","`n")-cne$Json){throw "[mir4-m42-02-effect-ownership-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$moduleMap=[ordered]@{
  'prototypes/mir/planner/effect_ownership.lua'='src/mod/families/modern/prototypes/mir/planner/effect_ownership.lua'
  'prototypes/mir/planner/effect_ownership/facts.lua'='src/mod/families/modern/prototypes/mir/planner/effect_ownership/facts.lua'
  'prototypes/mir/planner/effect_ownership/resolution.lua'='src/mod/families/modern/prototypes/mir/planner/effect_ownership/resolution.lua'
  'prototypes/mir/planner/effect_ownership/planned_operations.lua'='src/mod/families/modern/prototypes/mir/planner/effect_ownership/planned_operations.lua'
}
$identities=[ordered]@{}
foreach($entry in $moduleMap.GetEnumerator()){$identities[$entry.Key]=Get-MIR4M4202EffectOwnershipFileIdentity -RelativePath $entry.Value}
$managedOutputPaths=@($moduleMap.Keys)
$facadeOutputPath='prototypes/mir/planner/effect_ownership.lua'

$manifestPath='src/mod/package-source.json'
$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo $manifestPath)|ConvertFrom-Json -Depth 100 -DateKind String
$bindings=[Collections.Generic.List[object]]::new()
$inserted=$false
foreach($binding in @($manifest.bindings)){
  $managedBinding=[string]$binding.layer-ceq'families.modern'-and[string]$binding.output_path-in$managedOutputPaths
  if($managedBinding-and[string]$binding.output_path-ceq$facadeOutputPath){
    $identity=$identities[$facadeOutputPath]
    $binding.source_path=[string]$identity.path
    $binding.source_bytes=[int64]$identity.bytes
    $binding.source_sha256=[string]$identity.sha256
    $binding.output_bytes=[int64]$identity.bytes
    $binding.output_sha256=[string]$identity.sha256
    $bindings.Add($binding)
    foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
      $moduleIdentity=$identities[$outputPath]
      $bindings.Add([pscustomobject][ordered]@{
        layer='families.modern';target_scope=@('f210','f200');output_path=[string]$outputPath;semantic_class='target-overlay'
        source_path=[string]$moduleIdentity.path;transform='copy-exact-bytes';source_bytes=[int64]$moduleIdentity.bytes
        source_sha256=[string]$moduleIdentity.sha256;output_bytes=[int64]$moduleIdentity.bytes;output_sha256=[string]$moduleIdentity.sha256
      })
    }
    $inserted=$true
  }elseif(-not$managedBinding){$bindings.Add($binding)}
}
if(-not$inserted-or$bindings.Count-ne437){throw '[mir4-m42-02-effect-ownership-bindings]'}
$manifest.bindings=@($bindings)
$manifest.record_sha256=''
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestJson=ConvertTo-MIR4M4202EffectOwnershipJson -Record $manifest
if(-not($manifestJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))){throw '[mir4-m42-02-effect-ownership-manifest-schema]'}
Set-MIR4M4202EffectOwnershipProjection -RelativePath $manifestPath -Json $manifestJson

foreach($target in @('f210','f200')){
  $overlayPath="targets/$target/overlay.json"
  $overlay=Get-Content -Raw -LiteralPath (Join-Path $repo $overlayPath)|ConvertFrom-Json -Depth 100 -DateKind String
  $operations=[Collections.Generic.List[object]]::new()
  $overlayInserted=$false
  foreach($operation in @($overlay.operations)){
    $managedOperation=[string]$operation.path-in$managedOutputPaths
    if($managedOperation-and[string]$operation.path-ceq$facadeOutputPath){
      $identity=$identities[$facadeOutputPath]
      $operation.source_path=[string]$identity.path
      $operation.expected_bytes=[int64]$identity.bytes
      $operation.expected_sha256=[string]$identity.sha256
      $operation.reason="Materialize the governed effect-ownership facade for $target."
      $operations.Add($operation)
      foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
        $moduleIdentity=$identities[$outputPath]
        $responsibility=[IO.Path]::GetFileNameWithoutExtension($outputPath)
        $operations.Add([pscustomobject][ordered]@{
          path=[string]$outputPath;operation='add';semantic_class='target-overlay';source_path=[string]$moduleIdentity.path
          transform='copy-exact-bytes';reason="Materialize the governed effect-ownership $responsibility responsibility for $target."
          capability_disposition='included-for-target';expected_bytes=[int64]$moduleIdentity.bytes;expected_sha256=[string]$moduleIdentity.sha256
          proof_obligations=@('exact-path-and-byte-identity','behavior-preserving-decomposition','four-target-current-source-determinism')
        })
      }
      $overlayInserted=$true
    }elseif(-not$managedOperation){$operations.Add($operation)}
  }
  if(-not$overlayInserted-or$operations.Count-ne238){throw "[mir4-m42-02-effect-ownership-overlay] $target"}
  $overlay.operations=@($operations)
  $overlay.record_sha256=''
  $overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
  $overlayJson=ConvertTo-MIR4M4202EffectOwnershipJson -Record $overlay
  if(-not($overlayJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-overlay-v1.schema.json'))){throw "[mir4-m42-02-effect-ownership-overlay-schema] $target"}
  Set-MIR4M4202EffectOwnershipProjection -RelativePath $overlayPath -Json $overlayJson
}

$authorityPath='targets/package-authority.json'
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo $authorityPath)|ConvertFrom-Json -Depth 100 -DateKind String
$authority.source_manifest.record_sha256=[string]$manifest.record_sha256
$authority.record_sha256=''
$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
$authorityJson=ConvertTo-MIR4M4202EffectOwnershipJson -Record $authority
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))){throw '[mir4-m42-02-effect-ownership-authority-schema]'}
Set-MIR4M4202EffectOwnershipProjection -RelativePath $authorityPath -Json $authorityJson

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot $ProofOutputRoot -ReportPath $ProofReportPath
if($ProjectionOnly){return $proof}
if([string]::IsNullOrWhiteSpace($RuntimeProofPath)){throw '[mir4-m42-02-effect-ownership-runtime-proof-required]'}
$runtimePath=if([IO.Path]::IsPathRooted($RuntimeProofPath)){$RuntimeProofPath}else{Join-Path $repo $RuntimeProofPath}
if(-not(Test-Path -LiteralPath $runtimePath -PathType Leaf)){throw '[mir4-m42-02-effect-ownership-runtime-proof-missing]'}
$runtimeProof=Get-Content -Raw -LiteralPath $runtimePath|ConvertFrom-Json -Depth 100 -DateKind String

$moduleRows=@(
  foreach($outputPath in $moduleMap.Keys){
    $identity=$identities[$outputPath]
    [pscustomobject][ordered]@{output_path=[string]$outputPath;source_path=[string]$identity.path;bytes=[int64]$identity.bytes;lines=[int]$identity.lines;sha256=[string]$identity.sha256}
  }
)
$previousHashes=[ordered]@{
  '.mir/assurance.json'='8A099D8170BA2475E93DB736A296A5A991BA1DA9791FD55F3DC059BEA0D61DFF'
  '.mir/control/paths.yml'='8678D82BBDACC368FD81639081ABA188E84F839C5F4113364D1BE8BFD0B1030D'
  '.mir/modules.yml'='AEF4B629F0FBC63F7F928B85C71B5A467AAE9B5BC1A21E58FFF0545AE8B39C35'
  'assurance/catalog/tests.json'='291822E5B1A07598ACEEFEC1194500CFA4D400AB0EBCCBE860C8157023AC320F'
  'governance/automation/mir4-command-inventory-v1.json'='DA5BA8E09C52EBE85B6EB0EAE581E63D271462E04AE1D0C16F1F724D57F9CBC4'
  'spec/schemas/mir4-package-source-manifest-v1.schema.json'='85B8AC3089A367E034D18C12CCD7D663E7F0AA0317D99568D7E389ED2D6EB1ED'
  'tests/compiler/Test-MIR4CompilationPlanDecompositionM4202.ps1'='7840B1575A2AA958B0F1793014E562DA6BAA35A3B21A247BA19AE6A4F4A6B679'
  'tests/compiler/Test-MIR4BaseContinuationsDecompositionM4202.ps1'='4214ED6C55E1D6519976D6BAC865B18DB38C5FB161796B3CFB1F8E228AA80212'
  'tests/compiler/Test-MIR4StreamCompilerDecompositionM4202.ps1'='8093DBCF2326FA9E57DBBFE119EDFA5C0E2CE877BF127AACBE83ACF67FB15F8A'
  'tests/compiler/Test-MIR4TechnologyCatalogDecompositionM4202.ps1'='5177840DC386C2075D96F7A86EC679874E091001273C1F3211B81A1334428902'
  'tests/mir4/Test-MIR4EditableSourceMaterializer.ps1'='0ADFA0136CDE4060276291901942F46068476C75D251D2E05D93ABFB072B75D2'
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='B4505D031691B2BAA1861925937F8DD7880872C45E6F6FD20234ED8F3743D5E4'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='83D2F5598BEFD0AF47816D0C615813E88D9C67940CF3F93A87007CF6B1068931'
  'tools/lib/mir4/PreFreezeRelease.ps1'='E8332EC2A1266B21047DA8A81AF81FB7FB89F5A002B50690DB5EB2912F9A86FA'
  'validation/tests.yml'='349B8B683D08FDC9C044F2E86D8B7390A316F6671C6EADA293232408B09ECF57'
}
$evolvedBindings=@(
  foreach($entry in $previousHashes.GetEnumerator()){
    [pscustomobject][ordered]@{path=[string]$entry.Key;previous_sha256=[string]$entry.Value;current_sha256=(Get-MIR4M4202EffectOwnershipTextSha256 ([string]$entry.Key));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
  }
)
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202EffectOwnershipDecompositionV1';status='M42-02-L5-EFFECT-OWNERSHIP-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='798f8408d689b7574377109e9d4aad3c0b47273b';tree='43ef895d022f44e3073b674c7c38acfb139b4231'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-L4';receipt='releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json';receipt_sha256='9DAF10D681116CC7D52FBC3C3E61125DAE219765F0A3D44DC25EE6CD11719C8A';record_sha256='C130C251BA2CEE83D593BDAD61C9C91DF9A1601E03C37D28BBF592E80D564916';package_source_sha256='962F312C66EDA473FA4E0CBEF8E2ACEF01F4200831C198DD12A4E832420028F3'}
  evolved_bindings=$evolvedBindings
  responsibility='effect-ownership';facade=$facadeOutputPath;modules=$moduleRows
  package_authority=[pscustomobject][ordered]@{source_manifest_sha256=[string]$manifest.record_sha256;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=[string]$proof.package_source_sha256}
  target_proof=@($proof.targets);runtime_proof=$runtimeProof
  exact_package_delta=[pscustomobject][ordered]@{f210=@($moduleMap.Keys);f200=@($moduleMap.Keys);f110=@();f100=@()}
  preservation=[pscustomobject][ordered]@{semantics=$true;plans=$true;mutation_journals=$true;diagnostics=$true;stable_ids=$true;settings=$true;migrations=$true;saves=$true;compatibility_claims=$true;legacy_targets=$true;historical_4_0_baseline=$true}
  size_disposition=[pscustomobject][ordered]@{former_lines=409;facade_lines=[int]$identities[$facadeOutputPath].lines;facts_lines=[int]$identities['prototypes/mir/planner/effect_ownership/facts.lua'].lines;resolution_lines=[int]$identities['prototypes/mir/planner/effect_ownership/resolution.lua'].lines;planned_operations_lines=[int]$identities['prototypes/mir/planner/effect_ownership/planned_operations.lua'].lines;state='bounded-facts-row-resolution-planned-operation-resolution'}
  remaining=[pscustomobject][ordered]@{lua=@('compiler-orchestrator');powershell='pending-bounded-characterization'}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-L6-COMPILER-ORCHESTRATOR';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$receiptJson=ConvertTo-MIR4M4202EffectOwnershipJson -Record $receipt
if(-not($receiptJson|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'))){throw '[mir4-m42-02-effect-ownership-receipt-schema]'}
Set-MIR4M4202EffectOwnershipProjection -RelativePath 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json' -Json $receiptJson
$receipt
