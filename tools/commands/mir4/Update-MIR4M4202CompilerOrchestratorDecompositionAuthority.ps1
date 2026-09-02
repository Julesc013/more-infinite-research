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

function Get-MIR4M4202CompilerOrchestratorFileIdentity {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-compiler-orchestrator-source] $RelativePath"}
  $bytes=[IO.File]::ReadAllBytes($path)
  [pscustomobject][ordered]@{path=$RelativePath;bytes=[int64]$bytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $bytes);lines=@([IO.File]::ReadAllLines($path)).Count}
}

function Get-MIR4M4202CompilerOrchestratorTextSha256 {
  param([Parameter(Mandatory)][string]$RelativePath)
  Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath)
}

function ConvertTo-MIR4M4202CompilerOrchestratorJson {
  param([Parameter(Mandatory)]$Record)
  (($Record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
}

function Set-MIR4M4202CompilerOrchestratorProjection {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Json)
  $path=Join-Path $repo $RelativePath
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path).Replace("`r`n","`n")-cne$Json){throw "[mir4-m42-02-compiler-orchestrator-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$moduleMap=[ordered]@{
  'prototypes/mir/pipeline/compiler_orchestrator.lua'='src/mod/families/modern/prototypes/mir/pipeline/compiler_orchestrator.lua'
  'prototypes/mir/pipeline/compiler_orchestrator/context_construction.lua'='src/mod/families/modern/prototypes/mir/pipeline/compiler_orchestrator/context_construction.lua'
  'prototypes/mir/pipeline/compiler_orchestrator/phase_invocation.lua'='src/mod/families/modern/prototypes/mir/pipeline/compiler_orchestrator/phase_invocation.lua'
  'prototypes/mir/pipeline/compiler_orchestrator/contract_checks.lua'='src/mod/families/modern/prototypes/mir/pipeline/compiler_orchestrator/contract_checks.lua'
  'prototypes/mir/pipeline/compiler_orchestrator/publication.lua'='src/mod/families/modern/prototypes/mir/pipeline/compiler_orchestrator/publication.lua'
}
$identities=[ordered]@{}
foreach($entry in $moduleMap.GetEnumerator()){$identities[$entry.Key]=Get-MIR4M4202CompilerOrchestratorFileIdentity -RelativePath $entry.Value}
$managedOutputPaths=@($moduleMap.Keys)
$facadeOutputPath='prototypes/mir/pipeline/compiler_orchestrator.lua'

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
if(-not$inserted-or$bindings.Count-ne441){throw '[mir4-m42-02-compiler-orchestrator-bindings]'}
$manifest.bindings=@($bindings)
$manifest.record_sha256=''
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestJson=ConvertTo-MIR4M4202CompilerOrchestratorJson -Record $manifest
if(-not($manifestJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))){throw '[mir4-m42-02-compiler-orchestrator-manifest-schema]'}
Set-MIR4M4202CompilerOrchestratorProjection -RelativePath $manifestPath -Json $manifestJson

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
      $operation.reason="Materialize the governed compiler-orchestrator facade for $target."
      $operations.Add($operation)
      foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
        $moduleIdentity=$identities[$outputPath]
        $responsibility=[IO.Path]::GetFileNameWithoutExtension($outputPath)
        $operations.Add([pscustomobject][ordered]@{
          path=[string]$outputPath;operation='add';semantic_class='target-overlay';source_path=[string]$moduleIdentity.path
          transform='copy-exact-bytes';reason="Materialize the governed compiler-orchestrator $responsibility responsibility for $target."
          capability_disposition='included-for-target';expected_bytes=[int64]$moduleIdentity.bytes;expected_sha256=[string]$moduleIdentity.sha256
          proof_obligations=@('exact-path-and-byte-identity','behavior-preserving-decomposition','four-target-current-source-determinism')
        })
      }
      $overlayInserted=$true
    }elseif(-not$managedOperation){$operations.Add($operation)}
  }
  if(-not$overlayInserted-or$operations.Count-ne242){throw "[mir4-m42-02-compiler-orchestrator-overlay] $target"}
  $overlay.operations=@($operations)
  $overlay.record_sha256=''
  $overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
  $overlayJson=ConvertTo-MIR4M4202CompilerOrchestratorJson -Record $overlay
  if(-not($overlayJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-overlay-v1.schema.json'))){throw "[mir4-m42-02-compiler-orchestrator-overlay-schema] $target"}
  Set-MIR4M4202CompilerOrchestratorProjection -RelativePath $overlayPath -Json $overlayJson
}

$authorityPath='targets/package-authority.json'
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo $authorityPath)|ConvertFrom-Json -Depth 100 -DateKind String
$authority.source_manifest.record_sha256=[string]$manifest.record_sha256
$authority.record_sha256=''
$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
$authorityJson=ConvertTo-MIR4M4202CompilerOrchestratorJson -Record $authority
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))){throw '[mir4-m42-02-compiler-orchestrator-authority-schema]'}
Set-MIR4M4202CompilerOrchestratorProjection -RelativePath $authorityPath -Json $authorityJson

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot $ProofOutputRoot -ReportPath $ProofReportPath
if($ProjectionOnly){return $proof}
if([string]::IsNullOrWhiteSpace($RuntimeProofPath)){throw '[mir4-m42-02-compiler-orchestrator-runtime-proof-required]'}
$runtimePath=if([IO.Path]::IsPathRooted($RuntimeProofPath)){$RuntimeProofPath}else{Join-Path $repo $RuntimeProofPath}
if(-not(Test-Path -LiteralPath $runtimePath -PathType Leaf)){throw '[mir4-m42-02-compiler-orchestrator-runtime-proof-missing]'}
$runtimeProof=Get-Content -Raw -LiteralPath $runtimePath|ConvertFrom-Json -Depth 100 -DateKind String

$moduleRows=@(
  foreach($outputPath in $moduleMap.Keys){
    $identity=$identities[$outputPath]
    [pscustomobject][ordered]@{output_path=[string]$outputPath;source_path=[string]$identity.path;bytes=[int64]$identity.bytes;lines=[int]$identity.lines;sha256=[string]$identity.sha256}
  }
)
$previousHashes=[ordered]@{
  '.mir/assurance.json'='E583BAE629BE02B5A0A571C1801F4FEE606313EB3E7F20AD3D70B8506B886C07'
  '.mir/control/paths.yml'='6971AAC48B9498D8FEA27F6717C418E649641DF904D6D80F29C8C971DC74DF6B'
  '.mir/modules.yml'='4E65EB504ED061B238FE042AEDED77BAE04C1953F4AF00D5F2F621E7A2962BD4'
  'assurance/catalog/tests.json'='744037D6318842696794E3DAFCC79231E3BFFC456482FF203C0A3CF2E1385896'
  'governance/automation/mir4-command-inventory-v1.json'='02AEF062C0CA6C490F100720C760B26AE27A7646470E828E2D5F627828E34918'
  'spec/schemas/mir4-package-source-manifest-v1.schema.json'='E653C9421730A2CCE56694FB4F815897B2F83F0962408889319262F5B780EF8C'
  'tests/compiler/Test-MIR4CompilationPlanDecompositionM4202.ps1'='533E797071CA440DD4CB91BC1ADB6CBC74A6D6360877D403DC23360F335FA7AC'
  'tests/compiler/Test-MIR4BaseContinuationsDecompositionM4202.ps1'='093CA111BD7086B8397D90A9D0C86E13D48A5300166369CFE457E6AEDA74D818'
  'tests/compiler/Test-MIR4StreamCompilerDecompositionM4202.ps1'='EDCBA7E7133D788594817BAC6DA9E07737E2425A58295A1F2004D669B302BEC2'
  'tests/compiler/Test-MIR4TechnologyCatalogDecompositionM4202.ps1'='EF50042622E53EBF1C5927E227E29EC4D795F306B67CF1823A70A37502A731E2'
  'tests/compiler/Test-MIR4EffectOwnershipDecompositionM4202.ps1'='E761F5D6F931A3F9FECCEB34DAA979D5630CA1804659F46C210A7371CEFE7808'
  'tests/mir4/Test-MIR4EditableSourceMaterializer.ps1'='BA867E07B6760B0369FB687AD39170D137BD8F644CAC2A48277E6263B1EC1B11'
  'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1'='974ECE69CA7D674902BD776C695B5A3FDB6E5002C468C79C5795D61F4D9F1755'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1'='DA5531458A2E10C5F2683C45D0008EFA791A259DBD1C0A684FB4C0E181B3758D'
  'tools/lib/mir4/PreFreezeRelease.ps1'='424632E09265D56FD1B5EC30BAE886659F3A01C4D98716709156389392C53DE9'
  'validation/tests.yml'='DF105A30CF1A609305453572E9731F615C76A8D728A5A02FEF9986146D8985E9'
}
$evolvedBindings=@(
  foreach($entry in $previousHashes.GetEnumerator()){
    [pscustomobject][ordered]@{path=[string]$entry.Key;previous_sha256=[string]$entry.Value;current_sha256=(Get-MIR4M4202CompilerOrchestratorTextSha256 ([string]$entry.Key));hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
  }
)
$receipt=[pscustomobject][ordered]@{
  schema=1;kind='MIR4M4202CompilerOrchestratorDecompositionV1';status='M42-02-L6-COMPILER-ORCHESTRATOR-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='59003038217380ef2751a1ae48d2a91b856a63bd';tree='2a2464b8db89566f34ec12b33e0f1453605c7da0'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-02-L5';receipt='releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json';receipt_sha256='373D92EA7F2A68AC3871F64D2E153E9C5C769078E8996CEABA64F418E191F32F';record_sha256='249CB594EB96C0521A7913857AD85A134E675D65A43E610DE177CCBBEA4421AC';package_source_sha256='DACF17FB2C77AA67EE38D676926323EA26635349F3B4F5FE69A51A01E98F9C76'}
  evolved_bindings=$evolvedBindings
  responsibility='compiler-orchestrator';facade=$facadeOutputPath;modules=$moduleRows
  package_authority=[pscustomobject][ordered]@{source_manifest_sha256=[string]$manifest.record_sha256;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=[string]$proof.package_source_sha256}
  target_proof=@($proof.targets);runtime_proof=$runtimeProof
  exact_package_delta=[pscustomobject][ordered]@{f210=@($moduleMap.Keys);f200=@($moduleMap.Keys);f110=@();f100=@()}
  preservation=[pscustomobject][ordered]@{semantics=$true;plans=$true;mutation_journals=$true;diagnostics=$true;stable_ids=$true;settings=$true;migrations=$true;saves=$true;compatibility_claims=$true;legacy_targets=$true;historical_4_0_baseline=$true}
  size_disposition=[pscustomobject][ordered]@{former_lines=437;facade_lines=[int]$identities[$facadeOutputPath].lines;context_construction_lines=[int]$identities['prototypes/mir/pipeline/compiler_orchestrator/context_construction.lua'].lines;phase_invocation_lines=[int]$identities['prototypes/mir/pipeline/compiler_orchestrator/phase_invocation.lua'].lines;contract_checks_lines=[int]$identities['prototypes/mir/pipeline/compiler_orchestrator/contract_checks.lua'].lines;publication_lines=[int]$identities['prototypes/mir/pipeline/compiler_orchestrator/publication.lua'].lines;state='bounded-context-construction-phase-invocation-contract-checks-final-publication'}
  remaining=[pscustomobject][ordered]@{lua=@();powershell='pending-bounded-characterization'}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-RESIDUAL-POWERSHELL-CHARACTERIZATION';record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$receiptJson=ConvertTo-MIR4M4202CompilerOrchestratorJson -Record $receipt
if(-not($receiptJson|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'))){throw '[mir4-m42-02-compiler-orchestrator-receipt-schema]'}
Set-MIR4M4202CompilerOrchestratorProjection -RelativePath 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json' -Json $receiptJson
$receipt
