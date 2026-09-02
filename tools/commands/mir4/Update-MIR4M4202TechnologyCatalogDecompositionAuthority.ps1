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

function Get-MIR4M4202TechnologyCatalogFileIdentity {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-technology-catalog-source] $RelativePath"}
  $bytes=[IO.File]::ReadAllBytes($path)
  [pscustomobject][ordered]@{path=$RelativePath;bytes=[int64]$bytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $bytes);lines=@([IO.File]::ReadAllLines($path)).Count}
}

function Get-MIR4M4202TechnologyCatalogTextSha256 {
  param([Parameter(Mandatory)][string]$RelativePath)
  Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath)
}

function ConvertTo-MIR4M4202TechnologyCatalogJson {
  param([Parameter(Mandatory)]$Record)
  (($Record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
}

function Set-MIR4M4202TechnologyCatalogProjection {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Json)
  $path=Join-Path $repo $RelativePath
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path).Replace("`r`n","`n")-cne$Json){throw "[mir4-m42-02-technology-catalog-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$moduleMap=[ordered]@{
  'prototypes/mir/planner/technology_catalog.lua'='src/mod/families/modern/prototypes/mir/planner/technology_catalog.lua'
  'prototypes/mir/planner/technology_catalog/model.lua'='src/mod/families/modern/prototypes/mir/planner/technology_catalog/model.lua'
  'prototypes/mir/planner/technology_catalog/index.lua'='src/mod/families/modern/prototypes/mir/planner/technology_catalog/index.lua'
  'prototypes/mir/planner/technology_catalog/query.lua'='src/mod/families/modern/prototypes/mir/planner/technology_catalog/query.lua'
  'prototypes/mir/planner/technology_catalog/build.lua'='src/mod/families/modern/prototypes/mir/planner/technology_catalog/build.lua'
  'prototypes/mir/planner/technology_catalog/validate.lua'='src/mod/families/modern/prototypes/mir/planner/technology_catalog/validate.lua'
}
$identities=[ordered]@{}
foreach($entry in $moduleMap.GetEnumerator()){$identities[$entry.Key]=Get-MIR4M4202TechnologyCatalogFileIdentity -RelativePath $entry.Value}
$managedOutputPaths=@($moduleMap.Keys)
$facadeOutputPath='prototypes/mir/planner/technology_catalog.lua'
$correctiveMap=[ordered]@{
  'prototypes/mir/planner/compilation_plan/serialize.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan/serialize.lua'
}
$correctiveIdentities=[ordered]@{}
foreach($entry in $correctiveMap.GetEnumerator()){$correctiveIdentities[$entry.Key]=Get-MIR4M4202TechnologyCatalogFileIdentity -RelativePath $entry.Value}

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
  }elseif([string]$binding.layer-ceq'families.modern'-and$correctiveMap.Contains([string]$binding.output_path)){
    $identity=$correctiveIdentities[[string]$binding.output_path]
    $binding.source_path=[string]$identity.path
    $binding.source_bytes=[int64]$identity.bytes
    $binding.source_sha256=[string]$identity.sha256
    $binding.output_bytes=[int64]$identity.bytes
    $binding.output_sha256=[string]$identity.sha256
    $bindings.Add($binding)
  }elseif(-not$managedBinding){$bindings.Add($binding)}
}
if(-not$inserted-or$bindings.Count-ne434){throw '[mir4-m42-02-technology-catalog-bindings]'}
$manifest.bindings=@($bindings)
$manifest.record_sha256=''
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestJson=ConvertTo-MIR4M4202TechnologyCatalogJson -Record $manifest
if(-not($manifestJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))){throw '[mir4-m42-02-technology-catalog-manifest-schema]'}
Set-MIR4M4202TechnologyCatalogProjection -RelativePath $manifestPath -Json $manifestJson

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
      $operation.reason="Materialize the governed technology-catalog facade for $target."
      $operations.Add($operation)
      foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
        $moduleIdentity=$identities[$outputPath]
        $responsibility=[IO.Path]::GetFileNameWithoutExtension($outputPath)
        $operations.Add([pscustomobject][ordered]@{
          path=[string]$outputPath;operation='add';semantic_class='target-overlay';source_path=[string]$moduleIdentity.path
          transform='copy-exact-bytes';reason="Materialize the governed technology-catalog $responsibility responsibility for $target."
          capability_disposition='included-for-target';expected_bytes=[int64]$moduleIdentity.bytes;expected_sha256=[string]$moduleIdentity.sha256
          proof_obligations=@('exact-path-and-byte-identity','behavior-preserving-decomposition','four-target-current-source-determinism')
        })
      }
      $overlayInserted=$true
    }elseif($correctiveMap.Contains([string]$operation.path)){
      $identity=$correctiveIdentities[[string]$operation.path]
      $operation.source_path=[string]$identity.path
      $operation.expected_bytes=[int64]$identity.bytes
      $operation.expected_sha256=[string]$identity.sha256
      $operation.reason="Materialize the corrected eager dependency binding for $target."
      $operations.Add($operation)
    }elseif(-not$managedOperation){$operations.Add($operation)}
  }
  if(-not$overlayInserted-or$operations.Count-ne235){throw "[mir4-m42-02-technology-catalog-overlay] $target"}
  $overlay.operations=@($operations)
  $overlay.record_sha256=''
  $overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
  $overlayJson=ConvertTo-MIR4M4202TechnologyCatalogJson -Record $overlay
  if(-not($overlayJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-overlay-v1.schema.json'))){throw "[mir4-m42-02-technology-catalog-overlay-schema] $target"}
  Set-MIR4M4202TechnologyCatalogProjection -RelativePath $overlayPath -Json $overlayJson
}

$authorityPath='targets/package-authority.json'
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo $authorityPath)|ConvertFrom-Json -Depth 100 -DateKind String
$authority.source_manifest.record_sha256=[string]$manifest.record_sha256
$authority.record_sha256=''
$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
$authorityJson=ConvertTo-MIR4M4202TechnologyCatalogJson -Record $authority
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))){throw '[mir4-m42-02-technology-catalog-authority-schema]'}
Set-MIR4M4202TechnologyCatalogProjection -RelativePath $authorityPath -Json $authorityJson

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot $ProofOutputRoot -ReportPath $ProofReportPath
if($ProjectionOnly){return $proof}
if([string]::IsNullOrWhiteSpace($RuntimeProofPath)){throw '[mir4-m42-02-technology-catalog-runtime-proof-required]'}
$runtimePath=if([IO.Path]::IsPathRooted($RuntimeProofPath)){$RuntimeProofPath}else{Join-Path $repo $RuntimeProofPath}
if(-not(Test-Path -LiteralPath $runtimePath -PathType Leaf)){throw '[mir4-m42-02-technology-catalog-runtime-proof-missing]'}
$runtimeProof=Get-Content -Raw -LiteralPath $runtimePath|ConvertFrom-Json -Depth 100 -DateKind String

$moduleRows=@(
  foreach($outputPath in $moduleMap.Keys){
    $identity=$identities[$outputPath]
    [pscustomobject][ordered]@{output_path=[string]$outputPath;source_path=[string]$identity.path;bytes=[int64]$identity.bytes;lines=[int]$identity.lines;sha256=[string]$identity.sha256}
  }
)
$previousHashes=[ordered]@{
  '.mir/assurance.json'='B4F116DC8C8BE2C02BBC8973C873F506FF69F678F15381DAD6F7F4040ED21F07'
  '.mir/control/paths.yml'='B811D48C5E6ACF9B65BDACB5C02B620DD7F62BAF544111468FEC918D7039DC20'
  '.mir/modules.yml'='82286F74BE6BBE8CE0E073AA2666562155158EDD8F318547879DAD349BE461D6'
  'assurance/catalog/tests.json'='F4C1D3116774856095EAF2A8412C9DE5962FF8C6E052B4A5C5D531C685F4C5BF'
  'governance/automation/mir4-command-inventory-v1.json'='1BF57B41E9FF323BA13DF037CDDF72C2344CEB9E03FE408F0834D35A6B07C4A5'
  'spec/schemas/mir4-package-source-manifest-v1.schema.json'='580475E5F28E559935730574976B9F869D0D4A2AA2AB331CBBCDAC079CC90CEB'
  'tests/compiler/Test-MIR4CompilationPlanDecompositionM4202.ps1'='A5326EA3FBE5941AD0FE86934306EC7267F8ABC25079235DBFE8349C845A03B5'
  'tests/compiler/Test-MIR4BaseContinuationsDecompositionM4202.ps1'='C933AF6E213C5ABCF482FFF2CFC6375A053A7ADACA8847F98CF4E8AD50E870EF'
  'tests/compiler/Test-MIR4StreamCompilerDecompositionM4202.ps1'='1D74336F21F11F6CBD1A11660615621993E75A9F1E98B421C271335502B5071D'
  'tests/mir4/Test-MIR4EditableSourceMaterializer.ps1'='0C17FBAF4B3465588B49E95A7A1CCD7C1001C6B010D7C53D1095C9C514F73ACA'
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='32CBD12E2920F19A40B4DC1272584C219102FE63DBEA5D952173FA894E404AEA'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='7CCE5280CFE01E9FE3D00A517A4103F6F8CDE86ABFA24D9F5E0E70BB6C39A09D'
  'tools/lib/mir4/PreFreezeRelease.ps1'='FB2A961DFED0D024286E76932A4AF990A66E55C2650815DE71E1C511AFA9F944'
  'validation/tests.yml'='D27A12C68087C0E06DF30A31A277D982ADA109B4AF0DE3F490B82EFA298E3709'
}
$evolvedBindings=@(
  foreach($entry in $previousHashes.GetEnumerator()){
    [pscustomobject][ordered]@{path=[string]$entry.Key;previous_sha256=[string]$entry.Value;current_sha256=(Get-MIR4M4202TechnologyCatalogTextSha256 ([string]$entry.Key));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
  }
)
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202TechnologyCatalogDecompositionV1';status='M42-02-L4-TECHNOLOGY-CATALOG-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='00e31b33ae79f8d5a5022485a18aa0f968dd4b0c';tree='b01fc70214bca98aeb252a55c5dd11e859ef5f2b'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-L3';receipt='releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json';receipt_sha256='CA5BF4A1CACA309E3DA1CEA279B6CB9928231184CDAE8DB39A8952E9E189E385';record_sha256='42169B2298CCB597A87CD1F4ECDC5455BAD71DD1BF7A411C45293EF63CF09C42';package_source_sha256='37AF7B292EEAD8A04DCF699B75B94619E1585570477060C4ED1CB2F936700379'}
  evolved_bindings=$evolvedBindings
  responsibility='technology-catalog';facade=$facadeOutputPath;modules=$moduleRows
  corrective_bindings=@([pscustomobject][ordered]@{output_path='prototypes/mir/planner/compilation_plan/serialize.lua';source_path='src/mod/families/modern/prototypes/mir/planner/compilation_plan/serialize.lua';reason='Resolve the fingerprint dependency at MIR module load time so cross-mod fixture calls cannot retarget Lua require resolution.'})
  package_authority=[pscustomobject][ordered]@{source_manifest_sha256=[string]$manifest.record_sha256;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=[string]$proof.package_source_sha256}
  target_proof=@($proof.targets);runtime_proof=$runtimeProof
  exact_package_delta=[pscustomobject][ordered]@{f210=@($moduleMap.Keys)+@($correctiveMap.Keys);f200=@($moduleMap.Keys)+@($correctiveMap.Keys);f110=@();f100=@()}
  preservation=[pscustomobject][ordered]@{semantics=$true;plans=$true;mutation_journals=$true;diagnostics=$true;stable_ids=$true;settings=$true;migrations=$true;saves=$true;compatibility_claims=$true;legacy_targets=$true;historical_4_0_baseline=$true}
  size_disposition=[pscustomobject][ordered]@{former_lines=430;facade_lines=[int]$identities[$facadeOutputPath].lines;build_lines=[int]$identities['prototypes/mir/planner/technology_catalog/build.lua'].lines;validate_lines=[int]$identities['prototypes/mir/planner/technology_catalog/validate.lua'].lines;state='bounded-common-model-index-query-build-validate'}
  remaining=[pscustomobject][ordered]@{lua=@('effect-ownership','compiler-orchestrator');powershell='pending-bounded-characterization'}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-L5-EFFECT-OWNERSHIP';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$receiptJson=ConvertTo-MIR4M4202TechnologyCatalogJson -Record $receipt
if(-not($receiptJson|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'))){throw '[mir4-m42-02-technology-catalog-receipt-schema]'}
Set-MIR4M4202TechnologyCatalogProjection -RelativePath 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json' -Json $receiptJson
$receipt
