[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$ProofOutputRoot='build/packages',
  [string]$ProofReportPath='build/reports/package-source/mir4-current-source-materializer-v1.json',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')

function Get-MIR4M4202FileIdentity {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path=Join-Path $repo $RelativePath
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-m42-02-compilation-plan-source] $RelativePath"}
  $bytes=[IO.File]::ReadAllBytes($path)
  return [pscustomobject][ordered]@{path=$RelativePath;bytes=[int64]$bytes.Length;sha256=(Get-MIR4Sha256Bytes -Bytes $bytes);lines=@([IO.File]::ReadAllLines($path)).Count}
}

function Get-MIR4M4202TextSha256 {
  param([Parameter(Mandatory)][string]$RelativePath)
  return Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath)
}

function ConvertTo-MIR4M4202Json {
  param([Parameter(Mandatory)]$Record)
  return (($Record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
}

function Set-MIR4M4202Projection {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Json)
  $path=Join-Path $repo $RelativePath
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or[IO.File]::ReadAllText($path).Replace("`r`n","`n")-cne$Json){throw "[mir4-m42-02-compilation-plan-stale] $RelativePath"}
    return
  }
  [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
}

$moduleMap=[ordered]@{
  'prototypes/mir/planner/compilation_plan.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan.lua'
  'prototypes/mir/planner/compilation_plan/model.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan/model.lua'
  'prototypes/mir/planner/compilation_plan/build.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan/build.lua'
  'prototypes/mir/planner/compilation_plan/validate.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan/validate.lua'
  'prototypes/mir/planner/compilation_plan/fingerprint.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan/fingerprint.lua'
  'prototypes/mir/planner/compilation_plan/serialize.lua'='src/mod/families/modern/prototypes/mir/planner/compilation_plan/serialize.lua'
}
$identities=[ordered]@{}
foreach($entry in $moduleMap.GetEnumerator()){$identities[$entry.Key]=Get-MIR4M4202FileIdentity -RelativePath $entry.Value}
$managedOutputPaths=@($moduleMap.Keys)
$facadeOutputPath='prototypes/mir/planner/compilation_plan.lua'

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
        layer='families.modern'
        target_scope=@('f210','f200')
        output_path=[string]$outputPath
        semantic_class='target-overlay'
        source_path=[string]$moduleIdentity.path
        transform='copy-exact-bytes'
        source_bytes=[int64]$moduleIdentity.bytes
        source_sha256=[string]$moduleIdentity.sha256
        output_bytes=[int64]$moduleIdentity.bytes
        output_sha256=[string]$moduleIdentity.sha256
      })
    }
    $inserted=$true
  }elseif(-not$managedBinding){$bindings.Add($binding)}
}
if(-not$inserted-or$bindings.Count-ne411){throw '[mir4-m42-02-compilation-plan-bindings]'}
$manifest.bindings=@($bindings)
$manifest.record_sha256=''
$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
$manifestJson=ConvertTo-MIR4M4202Json -Record $manifest
if(-not($manifestJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-source-manifest-v1.schema.json'))){throw '[mir4-m42-02-compilation-plan-manifest-schema]'}
Set-MIR4M4202Projection -RelativePath $manifestPath -Json $manifestJson

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
      $operation.reason="Materialize the governed compilation-plan facade for $target."
      $operations.Add($operation)
      foreach($outputPath in @($managedOutputPaths|Where-Object{$_-cne$facadeOutputPath})){
        $moduleIdentity=$identities[$outputPath]
        $responsibility=[IO.Path]::GetFileNameWithoutExtension($outputPath)
        $operations.Add([pscustomobject][ordered]@{
          path=[string]$outputPath
          operation='add'
          semantic_class='target-overlay'
          source_path=[string]$moduleIdentity.path
          transform='copy-exact-bytes'
          reason="Materialize the governed compilation-plan $responsibility responsibility for $target."
          capability_disposition='included-for-target'
          expected_bytes=[int64]$moduleIdentity.bytes
          expected_sha256=[string]$moduleIdentity.sha256
          proof_obligations=@('exact-path-and-byte-identity','behavior-preserving-decomposition','four-target-current-source-determinism')
        })
      }
      $overlayInserted=$true
    }elseif(-not$managedOperation){$operations.Add($operation)}
  }
  if(-not$overlayInserted-or$operations.Count-ne221){throw "[mir4-m42-02-compilation-plan-overlay] $target"}
  $overlay.operations=@($operations)
  $overlay.record_sha256=''
  $overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
  $overlayJson=ConvertTo-MIR4M4202Json -Record $overlay
  if(-not($overlayJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-target-overlay-v1.schema.json'))){throw "[mir4-m42-02-compilation-plan-overlay-schema] $target"}
  Set-MIR4M4202Projection -RelativePath $overlayPath -Json $overlayJson
}

$authorityPath='targets/package-authority.json'
$authority=Get-Content -Raw -LiteralPath (Join-Path $repo $authorityPath)|ConvertFrom-Json -Depth 100 -DateKind String
$authority.source_manifest.record_sha256=[string]$manifest.record_sha256
$authority.record_sha256=''
$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
$authorityJson=ConvertTo-MIR4M4202Json -Record $authority
if(-not($authorityJson|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-canonical-package-authority-v1.schema.json'))){throw '[mir4-m42-02-compilation-plan-authority-schema]'}
Set-MIR4M4202Projection -RelativePath $authorityPath -Json $authorityJson

$proof=Invoke-MIR4CurrentSourceMaterializerProof -RepoRoot $repo -OutputRoot $ProofOutputRoot -ReportPath $ProofReportPath
$moduleRows=@(
  foreach($outputPath in $moduleMap.Keys){
    $identity=$identities[$outputPath]
    [pscustomobject][ordered]@{output_path=[string]$outputPath;source_path=[string]$identity.path;bytes=[int64]$identity.bytes;lines=[int]$identity.lines;sha256=[string]$identity.sha256}
  }
)
$receipt=[pscustomobject][ordered]@{
  schema=1
  kind='MIR4M4202CompilationPlanDecompositionV1'
  status='M42-02-L1-COMPILATION-PLAN-DECOMPOSED'
  starting_dev=[pscustomobject][ordered]@{commit='9ad319d5dc48e27c61a7a6c92f1f0d70f832cb56';tree='b445deca9973a377d2b42d2ba7cdbfe6706fd384'}
  predecessor=[pscustomobject][ordered]@{work_package='M42-01';receipt='releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json';receipt_sha256='A27ABD652775F39E5F880A3A65D3EE4D006BFAC6352473C3B87D629450A0C3C5';package_source_sha256='632E71A660AB5DEE4C3286E21AAA348BA7162674DFB15AEEECEFEF4B2525948E'}
  evolved_bindings=@(
    [pscustomobject][ordered]@{path='.mir/assurance.json';previous_sha256='A9305CBC2FF8F92D1A797C6035C6DE150F71EF3D28F04B0F2D696F2B12EE6A40';current_sha256=(Get-MIR4M4202TextSha256 '.mir/assurance.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='assurance/catalog/tests.json';previous_sha256='EDEAE7E1E4AE226E58A8CA66CDC241D2EA51DDD48C7CB73531D5D28DEBF448E7';current_sha256=(Get-MIR4M4202TextSha256 'assurance/catalog/tests.json');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4EditableSourceMaterializer.ps1';previous_sha256='D36D0BCBC2E880982DBE978E56C2BF62DF7DDCC8AF08EBCF3CF2B44F5A60E732';current_sha256=(Get-MIR4M4202TextSha256 'tests/mir4/Test-MIR4EditableSourceMaterializer.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1';previous_sha256='A02635793012FF06F82A3056C9851D4500935DFC9126782747D1D727A0B8645D';current_sha256=(Get-MIR4M4202TextSha256 'tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1';previous_sha256='BD3374A8F0900403FD9F0774CAA088E0E1C8A9523E6EE30ACE75356A58AE75D7';current_sha256=(Get-MIR4M4202TextSha256 'tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tools/lib/mir4/PreFreezeRelease.ps1';previous_sha256='B67ACC47B41E6C5706B8EA4AC5EDC110CB70FF203828CB3140D0A5B8E2D9818A';current_sha256=(Get-MIR4M4202TextSha256 'tools/lib/mir4/PreFreezeRelease.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tools/mir/application/repository/RepositoryCharacterization.ps1';previous_sha256='3A2301D8C2EAA4FCD64AF1A7B616D31184FE08170E4AE01A506DA2AFB901B465';current_sha256=(Get-MIR4M4202TextSha256 'tools/mir/application/repository/RepositoryCharacterization.ps1');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='validation/tests.yml';previous_sha256='514D66D65F55F9F8FA95832285DE34BC110952202AEBA87223C6812E04BED1D1';current_sha256=(Get-MIR4M4202TextSha256 'validation/tests.yml');hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
  )
  current_authorities=@(
    [pscustomobject][ordered]@{path='contracts/release/mir4-release-narrative-result-v1.schema.json';sha256=(Get-MIR4M4202TextSha256 'contracts/release/mir4-release-narrative-result-v1.schema.json');hash_mode='canonical-text-v1';role='current-release-narrative-result-contract';package_visible=$false;release_authority=$false}
    [pscustomobject][ordered]@{path='tools/mir/application/release/ReleaseNarratives.ps1';sha256=(Get-MIR4M4202TextSha256 'tools/mir/application/release/ReleaseNarratives.ps1');hash_mode='canonical-text-v1';role='current-release-narrative-application-service';package_visible=$false;release_authority=$false}
  )
  responsibility='compilation-plan'
  facade='prototypes/mir/planner/compilation_plan.lua'
  modules=$moduleRows
  package_authority=[pscustomobject][ordered]@{source_manifest_sha256=[string]$manifest.record_sha256;package_authority_sha256=[string]$authority.record_sha256;package_source_sha256=[string]$proof.package_source_sha256}
  target_proof=@($proof.targets)
  runtime_proof=[pscustomobject][ordered]@{
    engine=[pscustomobject][ordered]@{version='2.1.17';file_version='2.1.17.87315';binary_sha256='710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8';runtime_api_sha256='2E1FD436404B712AF6FE7B6C53E21A8F5688092A9E132FD2A5571327A96E5211';prototype_api_sha256='156F33CB4BC7EE2C538BB93F291F5270F2CDC45BE654BBE6F226E402BF8F5368';changelog_sha256='10CC3B613AD653B11FBDA0A6D9D9CE2FD9D7EA334B5240707AE4F5FA58EFE07C';review_status='current-reviewed'}
    candidate=[pscustomobject][ordered]@{target='f210';distribution_version='4.0.21000';archive_sha256='85D3FBEA22064BEA382BF9DBC12F0937469A84BE51B0F3A7187266B6485CB524';content_sha256='F7566232B36E355D5DC5F9F3E5CABD331FD1BF5DBB35E329B0CEA366EA222E86';entries=310;package_source_sha256='D964D8A932B94489776CBC4A06345264AFA476B57FF7E198C96EF7E76EE10B20'}
    scenario=[pscustomobject][ordered]@{name='space-age-generation-integrity';status='passed';assertions_executed=1}
    custody=[pscustomobject][ordered]@{logical_root='MIR_EVIDENCE_HOME/mir4-4.1-ultimate/20260902T141633+1000-f6cef04f/evidence/U05-L1-compilation-plan';manifest_sha256='4AA386446D601974B8AC3DC09E5FE081373DF904B5A59888374E95266F724505';evidence_files=4;evidence_bytes=1078209;raw_log_retained=$false;raw_log_sha256='978158432E8124E81EB38464F8B252FA53298BBAC8C01B12E7E000B791025F21'}
    cross_patch_reuse=$false
  }
  exact_package_delta=[pscustomobject][ordered]@{
    f210=@('prototypes/mir/planner/compilation_plan.lua','prototypes/mir/planner/compilation_plan/model.lua','prototypes/mir/planner/compilation_plan/build.lua','prototypes/mir/planner/compilation_plan/validate.lua','prototypes/mir/planner/compilation_plan/fingerprint.lua','prototypes/mir/planner/compilation_plan/serialize.lua')
    f200=@('prototypes/mir/planner/compilation_plan.lua','prototypes/mir/planner/compilation_plan/model.lua','prototypes/mir/planner/compilation_plan/build.lua','prototypes/mir/planner/compilation_plan/validate.lua','prototypes/mir/planner/compilation_plan/fingerprint.lua','prototypes/mir/planner/compilation_plan/serialize.lua')
    f110=@()
    f100=@()
  }
  preservation=[pscustomobject][ordered]@{semantics=$true;plans=$true;mutation_journals=$true;diagnostics=$true;stable_ids=$true;settings=$true;migrations=$true;saves=$true;compatibility_claims=$true;legacy_targets=$true;historical_4_0_baseline=$true}
  size_disposition=[pscustomobject][ordered]@{former_lines=937;facade_lines=[int]$identities['prototypes/mir/planner/compilation_plan.lua'].lines;build_lines=[int]$identities['prototypes/mir/planner/compilation_plan/build.lua'].lines;state='accepted-cohesive-build-owner-with-l6-orchestrator-follow-up'}
  remaining=[pscustomobject][ordered]@{lua=@('base-continuations','stream-compiler','technology-catalog','effect-ownership','compiler-orchestrator');powershell='pending-bounded-characterization'}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-02-L2-BASE-CONTINUATIONS'
  record_sha256=''
}
$receipt.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $receipt
$receiptJson=ConvertTo-MIR4M4202Json -Record $receipt
if(-not($receiptJson|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m42-02-compilation-plan-decomposition-v1.schema.json'))){throw '[mir4-m42-02-compilation-plan-receipt-schema]'}
Set-MIR4M4202Projection -RelativePath 'releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json' -Json $receiptJson

$receipt
