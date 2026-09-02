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

function Get-MIR4M4202BaseFileIdentity {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-base-continuations-source] $RelativePath"}
  $bytes=[IO.File]::ReadAllBytes($path)
  return [pscustomobject][ordered]@{path=$RelativePath;bytes=[int64]$bytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $bytes);lines=@([IO.File]::ReadAllLines($path)).Count}
}

function Get-MIR4M4202BaseTextSha256 {
  param([Parameter(Mandatory)][string]$RelativePath)
  return Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath)
}

function ConvertTo-MIR4M4202BaseJson {
  param([Parameter(Mandatory)]$Record)
  return (($Record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
}

function Set-MIR4M4202BaseProjection {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Json)
  $path=Join-Path $repo $RelativePath
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path).Replace("`r`n","`n")-cne$Json){throw "[mir4-m42-02-base-continuations-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$targetModuleMap=[ordered]@{
  f210=[ordered]@{
    'prototypes/mir/planner/base_continuations.lua'='targets/f210/files/prototypes/mir/planner/base_continuations.lua'
    'prototypes/mir/planner/base_continuations/classify.lua'='targets/f210/files/prototypes/mir/planner/base_continuations/classify.lua'
    'prototypes/mir/planner/base_continuations/discover.lua'='targets/f210/files/prototypes/mir/planner/base_continuations/discover.lua'
    'prototypes/mir/planner/base_continuations/qualify.lua'='targets/f210/files/prototypes/mir/planner/base_continuations/qualify.lua'
    'prototypes/mir/planner/base_continuations/plan.lua'='targets/f210/files/prototypes/mir/planner/base_continuations/plan.lua'
  }
  f200=[ordered]@{
    'prototypes/mir/planner/base_continuations.lua'='targets/f200/files/prototypes/mir/planner/base_continuations.lua'
    'prototypes/mir/planner/base_continuations/classify.lua'='targets/f200/files/prototypes/mir/planner/base_continuations/classify.lua'
    'prototypes/mir/planner/base_continuations/discover.lua'='targets/f200/files/prototypes/mir/planner/base_continuations/discover.lua'
    'prototypes/mir/planner/base_continuations/qualify.lua'='targets/f200/files/prototypes/mir/planner/base_continuations/qualify.lua'
    'prototypes/mir/planner/base_continuations/plan.lua'='targets/f200/files/prototypes/mir/planner/base_continuations/plan.lua'
  }
}
$identities=[ordered]@{}
foreach($target in @('f210','f200')){
  $identities[$target]=[ordered]@{}
  foreach($entry in $targetModuleMap[$target].GetEnumerator()){
    $identities[$target][$entry.Key]=Get-MIR4M4202BaseFileIdentity -RelativePath $entry.Value
  }
}
$managedOutputPaths=@($targetModuleMap.f210.Keys)
$facadeOutputPath='prototypes/mir/planner/base_continuations.lua'

$manifestPath='src/mod/package-source.json'
$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo $manifestPath)|ConvertFrom-Json -Depth 100 -DateKind String
$bindings=[Collections.Generic.List[object]]::new()
$insertedTargets=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($binding in @($manifest.bindings)){
  $layer=[string]$binding.layer
  $target=if($layer-match'^targets[.](f210|f200)$'){$Matches[1]}else{$null}
  $managedBinding=$null-ne$target-and[string]$binding.output_path-in$managedOutputPaths
  if($managedBinding-and[string]$binding.output_path-ceq$facadeOutputPath){
    $identity=$identities[$target][$facadeOutputPath]
    $binding.source_path=[string]$identity.path
    $binding.source_bytes=[int64]$identity.bytes
    $binding.source_sha256=[string]$identity.sha256
    $binding.output_bytes=[int64]$identity.bytes
    $binding.output_sha256=[string]$identity.sha256
    $bindings.Add($binding)
    foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
      $moduleIdentity=$identities[$target][$outputPath]
      $bindings.Add([pscustomobject][ordered]@{
        layer="targets.$target"
        target_scope=@($target)
        output_path=[string]$outputPath
        semantic_class='target-replacement'
        source_path=[string]$moduleIdentity.path
        transform='copy-exact-bytes'
        source_bytes=[int64]$moduleIdentity.bytes
        source_sha256=[string]$moduleIdentity.sha256
        output_bytes=[int64]$moduleIdentity.bytes
        output_sha256=[string]$moduleIdentity.sha256
      })
    }
    [void]$insertedTargets.Add($target)
  }elseif(-not$managedBinding){$bindings.Add($binding)}
}
if($insertedTargets.Count-ne2-or$bindings.Count-ne419){throw '[mir4-m42-02-base-continuations-bindings]'}
$manifest.bindings=@($bindings)
$manifest.record_sha256=''
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestJson=ConvertTo-MIR4M4202BaseJson -Record $manifest
if(-not($manifestJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))){throw '[mir4-m42-02-base-continuations-manifest-schema]'}
Set-MIR4M4202BaseProjection -RelativePath $manifestPath -Json $manifestJson

foreach($target in @('f210','f200')){
  $overlayPath="targets/$target/overlay.json"
  $overlay=Get-Content -Raw -LiteralPath (Join-Path $repo $overlayPath)|ConvertFrom-Json -Depth 100 -DateKind String
  $operations=[Collections.Generic.List[object]]::new()
  $overlayInserted=$false
  foreach($operation in @($overlay.operations)){
    $managedOperation=[string]$operation.path-in$managedOutputPaths
    if($managedOperation-and[string]$operation.path-ceq$facadeOutputPath){
      $identity=$identities[$target][$facadeOutputPath]
      $operation.source_path=[string]$identity.path
      $operation.expected_bytes=[int64]$identity.bytes
      $operation.expected_sha256=[string]$identity.sha256
      $operation.reason="Materialize the governed base-continuations facade for $target."
      $operations.Add($operation)
      foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
        $moduleIdentity=$identities[$target][$outputPath]
        $responsibility=[IO.Path]::GetFileNameWithoutExtension($outputPath)
        $operations.Add([pscustomobject][ordered]@{
          path=[string]$outputPath
          operation='add'
          semantic_class='target-replacement'
          source_path=[string]$moduleIdentity.path
          transform='copy-exact-bytes'
          reason="Materialize the governed base-continuations $responsibility responsibility for $target."
          capability_disposition='included-for-target'
          expected_bytes=[int64]$moduleIdentity.bytes
          expected_sha256=[string]$moduleIdentity.sha256
          proof_obligations=@('exact-path-and-byte-identity','behavior-preserving-decomposition','four-target-current-source-determinism')
        })
      }
      $overlayInserted=$true
    }elseif(-not$managedOperation){$operations.Add($operation)}
  }
  if(-not$overlayInserted-or$operations.Count-ne225){throw "[mir4-m42-02-base-continuations-overlay] $target"}
  $overlay.operations=@($operations)
  $overlay.record_sha256=''
  $overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
  $overlayJson=ConvertTo-MIR4M4202BaseJson -Record $overlay
  if(-not($overlayJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-overlay-v1.schema.json'))){throw "[mir4-m42-02-base-continuations-overlay-schema] $target"}
  Set-MIR4M4202BaseProjection -RelativePath $overlayPath -Json $overlayJson
}

$authorityPath='targets/package-authority.json'
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo $authorityPath)|ConvertFrom-Json -Depth 100 -DateKind String
$authority.source_manifest.record_sha256=[string]$manifest.record_sha256
$authority.record_sha256=''
$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
$authorityJson=ConvertTo-MIR4M4202BaseJson -Record $authority
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))){throw '[mir4-m42-02-base-continuations-authority-schema]'}
Set-MIR4M4202BaseProjection -RelativePath $authorityPath -Json $authorityJson

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot $ProofOutputRoot -ReportPath $ProofReportPath
if($ProjectionOnly){return $proof}
if([string]::IsNullOrWhiteSpace($RuntimeProofPath)){throw '[mir4-m42-02-base-continuations-runtime-proof-required]'}
$runtimePath=if([IO.Path]::IsPathRooted($RuntimeProofPath)){$RuntimeProofPath}else{Join-Path $repo $RuntimeProofPath}
if(-not(Test-Path -LiteralPath $runtimePath -PathType Leaf)){throw '[mir4-m42-02-base-continuations-runtime-proof-missing]'}
$runtimeProof=Get-Content -Raw -LiteralPath $runtimePath|ConvertFrom-Json -Depth 100 -DateKind String

$targetModules=[ordered]@{}
foreach($target in @('f210','f200')){
  $targetModules[$target]=@(
    foreach($outputPath in $targetModuleMap[$target].Keys){
      $identity=$identities[$target][$outputPath]
      [pscustomobject][ordered]@{output_path=[string]$outputPath;source_path=[string]$identity.path;bytes=[int64]$identity.bytes;lines=[int]$identity.lines;sha256=[string]$identity.sha256}
    }
  )
}
$receipt=[pscustomobject][ordered]@{
  schema=1
  kind='MIR4M4202BaseContinuationsDecompositionV1'
  status='M42-02-L2-BASE-CONTINUATIONS-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='78dc6e5c6c0a0dda6d7ca6f73f0a212762ff03a2';tree='9e9847d62940c64da241c3d99e3c22a49d38d6cd'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-L1';receipt='releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json';receipt_sha256='008C87C0649340C2D6E5624675FB9EC93B0B0B7312D5DB8AF3A921110D8B83AB';record_sha256='68200C8D0C286FEDD645E043306147520F9EA5D0236DBC2B0BEB594592EBD50D';package_source_sha256='D964D8A932B94489776CBC4A06345264AFA476B57FF7E198C96EF7E76EE10B20'}
  evolved_bindings=@(
    [pscustomobject][ordered]@{path='.mir/assurance.json';previous_sha256='43148BD64301B2A1F3CDEBAD2AB6AE8C3FEE5721E7C3AD4E9F8CC162AC1948B9';current_sha256=(Get-MIR4M4202BaseTextSha256 '.mir/assurance.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='assurance/catalog/tests.json';previous_sha256='2EF3DA41982B4A327AEC5B9F8C8F3BCE534287C07A2E8ADEF8A0C9C5F8160A63';current_sha256=(Get-MIR4M4202BaseTextSha256 'assurance/catalog/tests.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4EditableSourceMaterializer.ps1';previous_sha256='9C772D2D310EF3C1EE57DC80E88A58AFB5F37C3EB32A97AA2AD05F21DBAFD0AD';current_sha256=(Get-MIR4M4202BaseTextSha256 'tests/mir4/Test-MIR4EditableSourceMaterializer.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tools/lib/mir4/PreFreezeRelease.ps1';previous_sha256='4CD8F5FDF0A228A0E21C430F87813485B5A33A9E091DED405C45F02EF39B120F';current_sha256=(Get-MIR4M4202BaseTextSha256 'tools/lib/mir4/PreFreezeRelease.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='validation/tests.yml';previous_sha256='6C1FCE904525AEF1E9F2D6477E7157F2ADB3DF720D7D29A548890127F400DF08';current_sha256=(Get-MIR4M4202BaseTextSha256 'validation/tests.yml');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
  )
  responsibility='base-continuations'
  facade='prototypes/mir/planner/base_continuations.lua'
  target_modules=$targetModules
  package_authority=[pscustomobject][ordered]@{source_manifest_sha256=[string]$manifest.record_sha256;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=[string]$proof.package_source_sha256}
  target_proof=@($proof.targets)
  runtime_proof=$runtimeProof
  exact_package_delta=[pscustomobject][ordered]@{f210=@($targetModuleMap.f210.Keys);f200=@($targetModuleMap.f200.Keys);f110=@();f100=@()}
  preservation=[pscustomobject][ordered]@{semantics=$true;plans=$true;mutation_journals=$true;diagnostics=$true;stable_ids=$true;settings=$true;migrations=$true;saves=$true;compatibility_claims=$true;legacy_targets=$true;historical_4_0_baseline=$true}
  size_disposition=[pscustomobject][ordered]@{
    former_lines=[pscustomobject][ordered]@{f210=696;f200=696}
    facade_lines=[pscustomobject][ordered]@{f210=[int]$identities.f210[$facadeOutputPath].lines;f200=[int]$identities.f200[$facadeOutputPath].lines}
    plan_lines=[pscustomobject][ordered]@{f210=[int]$identities.f210['prototypes/mir/planner/base_continuations/plan.lua'].lines;f200=[int]$identities.f200['prototypes/mir/planner/base_continuations/plan.lua'].lines}
    state='bounded-target-owned-discover-classify-qualify-plan'
  }
  remaining=[pscustomobject][ordered]@{lua=@('stream-compiler','technology-catalog','effect-ownership','compiler-orchestrator');powershell='pending-bounded-characterization'}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-L3-STREAM-COMPILER'
  record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$receiptJson=ConvertTo-MIR4M4202BaseJson -Record $receipt
if(-not($receiptJson|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-base-continuations-decomposition-v1.schema.json'))){throw '[mir4-m42-02-base-continuations-receipt-schema]'}
Set-MIR4M4202BaseProjection -RelativePath 'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json' -Json $receiptJson

$receipt
