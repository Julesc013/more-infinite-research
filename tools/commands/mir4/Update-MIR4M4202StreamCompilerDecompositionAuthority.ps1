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

function Get-MIR4M4202StreamFileIdentity {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-stream-compiler-source] $RelativePath"}
  $bytes=[IO.File]::ReadAllBytes($path)
  [pscustomobject][ordered]@{path=$RelativePath;bytes=[int64]$bytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $bytes);lines=@([IO.File]::ReadAllLines($path)).Count}
}

function Get-MIR4M4202StreamTextSha256 {
  param([Parameter(Mandatory)][string]$RelativePath)
  Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath)
}

function ConvertTo-MIR4M4202StreamJson {
  param([Parameter(Mandatory)]$Record)
  (($Record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
}

function Set-MIR4M4202StreamProjection {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Json)
  $path=Join-Path $repo $RelativePath
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path).Replace("`r`n","`n")-cne$Json){throw "[mir4-m42-02-stream-compiler-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$targetModuleMap=[ordered]@{}
foreach($target in @('f210','f200')){
  $targetModuleMap[$target]=[ordered]@{
    'prototypes/mir/planner/stream_compiler.lua'="targets/$target/files/prototypes/mir/planner/stream_compiler.lua"
    'prototypes/mir/planner/stream_compiler/compile.lua'="targets/$target/files/prototypes/mir/planner/stream_compiler/compile.lua"
    'prototypes/mir/planner/stream_compiler/diagnostics.lua'="targets/$target/files/prototypes/mir/planner/stream_compiler/diagnostics.lua"
    'prototypes/mir/planner/stream_compiler/discover.lua'="targets/$target/files/prototypes/mir/planner/stream_compiler/discover.lua"
    'prototypes/mir/planner/stream_compiler/ownership.lua'="targets/$target/files/prototypes/mir/planner/stream_compiler/ownership.lua"
    'prototypes/mir/planner/stream_compiler/qualify.lua'="targets/$target/files/prototypes/mir/planner/stream_compiler/qualify.lua"
  }
}
$identities=[ordered]@{}
foreach($target in @('f210','f200')){
  $identities[$target]=[ordered]@{}
  foreach($entry in $targetModuleMap[$target].GetEnumerator()){
    $identities[$target][$entry.Key]=Get-MIR4M4202StreamFileIdentity -RelativePath $entry.Value
  }
}
$managedOutputPaths=@($targetModuleMap.f210.Keys)
$facadeOutputPath='prototypes/mir/planner/stream_compiler.lua'

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
        layer="targets.$target";target_scope=@($target);output_path=[string]$outputPath;semantic_class='target-replacement'
        source_path=[string]$moduleIdentity.path;transform='copy-exact-bytes';source_bytes=[int64]$moduleIdentity.bytes
        source_sha256=[string]$moduleIdentity.sha256;output_bytes=[int64]$moduleIdentity.bytes;output_sha256=[string]$moduleIdentity.sha256
      })
    }
    [void]$insertedTargets.Add($target)
  }elseif(-not$managedBinding){$bindings.Add($binding)}
}
if($insertedTargets.Count-ne2-or$bindings.Count-ne429){throw '[mir4-m42-02-stream-compiler-bindings]'}
$manifest.bindings=@($bindings)
$manifest.record_sha256=''
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestJson=ConvertTo-MIR4M4202StreamJson -Record $manifest
if(-not($manifestJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))){throw '[mir4-m42-02-stream-compiler-manifest-schema]'}
Set-MIR4M4202StreamProjection -RelativePath $manifestPath -Json $manifestJson

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
      $operation.reason="Materialize the governed stream-compiler facade for $target."
      $operations.Add($operation)
      foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
        $moduleIdentity=$identities[$target][$outputPath]
        $responsibility=[IO.Path]::GetFileNameWithoutExtension($outputPath)
        $operations.Add([pscustomobject][ordered]@{
          path=[string]$outputPath;operation='add';semantic_class='target-replacement';source_path=[string]$moduleIdentity.path
          transform='copy-exact-bytes';reason="Materialize the governed stream-compiler $responsibility responsibility for $target."
          capability_disposition='included-for-target';expected_bytes=[int64]$moduleIdentity.bytes;expected_sha256=[string]$moduleIdentity.sha256
          proof_obligations=@('exact-path-and-byte-identity','behavior-preserving-decomposition','four-target-current-source-determinism')
        })
      }
      $overlayInserted=$true
    }elseif(-not$managedOperation){$operations.Add($operation)}
  }
  if(-not$overlayInserted-or$operations.Count-ne230){throw "[mir4-m42-02-stream-compiler-overlay] $target"}
  $overlay.operations=@($operations)
  $overlay.record_sha256=''
  $overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
  $overlayJson=ConvertTo-MIR4M4202StreamJson -Record $overlay
  if(-not($overlayJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-overlay-v1.schema.json'))){throw "[mir4-m42-02-stream-compiler-overlay-schema] $target"}
  Set-MIR4M4202StreamProjection -RelativePath $overlayPath -Json $overlayJson
}

$authorityPath='targets/package-authority.json'
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo $authorityPath)|ConvertFrom-Json -Depth 100 -DateKind String
$authority.source_manifest.record_sha256=[string]$manifest.record_sha256
$authority.record_sha256=''
$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
$authorityJson=ConvertTo-MIR4M4202StreamJson -Record $authority
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))){throw '[mir4-m42-02-stream-compiler-authority-schema]'}
Set-MIR4M4202StreamProjection -RelativePath $authorityPath -Json $authorityJson

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot $ProofOutputRoot -ReportPath $ProofReportPath
if($ProjectionOnly){return $proof}
if([string]::IsNullOrWhiteSpace($RuntimeProofPath)){throw '[mir4-m42-02-stream-compiler-runtime-proof-required]'}
$runtimePath=if([IO.Path]::IsPathRooted($RuntimeProofPath)){$RuntimeProofPath}else{Join-Path $repo $RuntimeProofPath}
if(-not(Test-Path -LiteralPath $runtimePath -PathType Leaf)){throw '[mir4-m42-02-stream-compiler-runtime-proof-missing]'}
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
  schema=1;kind='MIR4M4202StreamCompilerDecompositionV1';status='M42-02-L3-STREAM-COMPILER-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='f2bdad3300e0da112425f44d8ff4cb41be2fb8d7';tree='8bfe0f304c1b97d53a821ac407b3a607aae8cbaa'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-L2';receipt='releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json';receipt_sha256='A6DE352284C3C7D947542A642208C070CD7C4D21249361E6DF7F43752B364220';record_sha256='2B45F0F7070335CC129FED3DBD0684B299AD4DD786A0F51E401327F1D734B42B';package_source_sha256='0A3B6591600B28B262BED9C63A8FC80ABEB2300C7FF7848D18C43B0525ADA022'}
  evolved_bindings=@(
    [pscustomobject][ordered]@{path='.mir/assurance.json';previous_sha256='D937F7BBC6F737CF2ED257D7F2C4C07F5FA2B76D2D2EF2EEE906EC9AC33A2515';current_sha256=(Get-MIR4M4202StreamTextSha256 '.mir/assurance.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='.mir/control/paths.yml';previous_sha256='E03CF1923D31F56894371A5A9AB30578B008DC548F6BAB292A80E904C595E82A';current_sha256=(Get-MIR4M4202StreamTextSha256 '.mir/control/paths.yml');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='.mir/modules.yml';previous_sha256='07C77BFF44E237B0E548FB8A563271109EF7533111678DC25811033258E88FF3';current_sha256=(Get-MIR4M4202StreamTextSha256 '.mir/modules.yml');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='assurance/catalog/tests.json';previous_sha256='A79BB8C06E69E13C06796BA437BE1498E977626E9B8D7DAB292D3EA5A04F9FF5';current_sha256=(Get-MIR4M4202StreamTextSha256 'assurance/catalog/tests.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';previous_sha256='005B22E457A01BA918FF6490416D5D914AA9A81FBBD7DE1156444794E4BA46EB';current_sha256=(Get-MIR4M4202StreamTextSha256 'governance/automation/mir4-command-inventory-v1.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='spec/schemas/mir4-package-source-manifest-v1.schema.json';previous_sha256='A8B04D8ADE76EF2718F88EF7E0B47ABA4B3699377B8FB054C99C43BA1C4358E8';current_sha256=(Get-MIR4M4202StreamTextSha256 'spec/schemas/mir4-package-source-manifest-v1.schema.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4EditableSourceMaterializer.ps1';previous_sha256='0364BB64F91243D29C0E8938B7CADD5559906364EED6E2B2307B2AEC85651573';current_sha256=(Get-MIR4M4202StreamTextSha256 'tests/mir4/Test-MIR4EditableSourceMaterializer.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1';previous_sha256='CAFE44A138E004FE4E77AE6A60072E1D334CC9472FAE85133B7A0EE46421DFDE';current_sha256=(Get-MIR4M4202StreamTextSha256 'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/repository/Test-MIR4RepositoryFixedPoint.ps1';previous_sha256='B3A535D84A910E776F4F76F5D1DB3E97381EED817A439AF90C7D2AF16BF92254';current_sha256=(Get-MIR4M4202StreamTextSha256 'tests/repository/Test-MIR4RepositoryFixedPoint.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/tooling/Test-MIR4TestWorkflowConvergence.ps1';previous_sha256='9331B3C1A140A533C8876E2EA14E7484010F19EB6A81AD6F7A4971CB61E6E18F';current_sha256=(Get-MIR4M4202StreamTextSha256 'tests/tooling/Test-MIR4TestWorkflowConvergence.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tools/lib/mir4/PreFreezeRelease.ps1';previous_sha256='78F019B38306C287226769EDBF6B08E39B6A041386B9FA722B3B8A9A941A38AE';current_sha256=(Get-MIR4M4202StreamTextSha256 'tools/lib/mir4/PreFreezeRelease.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='validation/tests.yml';previous_sha256='7227BB7E90DE37F952F0CAE93F81ED523DDA20CAE5CDAB2D557521C769A93A43';current_sha256=(Get-MIR4M4202StreamTextSha256 'validation/tests.yml');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
  )
  responsibility='stream-compiler';facade='prototypes/mir/planner/stream_compiler.lua';target_modules=$targetModules
  package_authority=[pscustomobject][ordered]@{source_manifest_sha256=[string]$manifest.record_sha256;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=[string]$proof.package_source_sha256}
  target_proof=@($proof.targets);runtime_proof=$runtimeProof
  exact_package_delta=[pscustomobject][ordered]@{f210=@($targetModuleMap.f210.Keys);f200=@($targetModuleMap.f200.Keys);f110=@();f100=@()}
  preservation=[pscustomobject][ordered]@{semantics=$true;plans=$true;mutation_journals=$true;diagnostics=$true;stable_ids=$true;settings=$true;migrations=$true;saves=$true;compatibility_claims=$true;legacy_targets=$true;historical_4_0_baseline=$true}
  size_disposition=[pscustomobject][ordered]@{former_lines=[pscustomobject][ordered]@{f210=528;f200=514};facade_lines=[pscustomobject][ordered]@{f210=[int]$identities.f210[$facadeOutputPath].lines;f200=[int]$identities.f200[$facadeOutputPath].lines};qualify_lines=[pscustomobject][ordered]@{f210=[int]$identities.f210['prototypes/mir/planner/stream_compiler/qualify.lua'].lines;f200=[int]$identities.f200['prototypes/mir/planner/stream_compiler/qualify.lua'].lines};state='bounded-target-owned-discover-ownership-qualify-compile-diagnostics'}
  remaining=[pscustomobject][ordered]@{lua=@('technology-catalog','effect-ownership','compiler-orchestrator');powershell='pending-bounded-characterization'}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-L4-TECHNOLOGY-CATALOG';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$receiptJson=ConvertTo-MIR4M4202StreamJson -Record $receipt
if(-not($receiptJson|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'))){throw '[mir4-m42-02-stream-compiler-receipt-schema]'}
Set-MIR4M4202StreamProjection -RelativePath 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json' -Json $receiptJson
$receipt
