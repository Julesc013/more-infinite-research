param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot='build/mir4/m4c02-assurance-scale',
  [switch]$Check
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/AssuranceScale.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseBudget.ps1')
. (Join-Path $repo 'tools/lib/mir4/OfflineDrill.ps1')
Import-MIR4W08ControlPlane -RepoRoot $repo
$authority=Get-MIR4W08Authority -RepoRoot $repo
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-w08-output-boundary] $output"}
$dirty=@(& git -C $repo status --porcelain --untracked-files=no)
if($dirty.Count){throw '[mir4-w08-source-dirty] Commit tracked source before exporting exact records.'}
$source=[pscustomobject][ordered]@{commit=(& git -C $repo rev-parse HEAD).Trim();tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim();programme_id=[string]$authority.programme_id}

function New-SliceInput([string]$Path){
  $full=Join-Path $repo $Path
  if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "[mir4-w08-slice-input-missing] $Path"}
  return [pscustomobject][ordered]@{status='available';authority_ref=$Path;rows=@([pscustomobject][ordered]@{authority_ref=$Path;digest=(Get-MIR4W08FileSha256 $full)});reason='authority-reference-only-not-observation-proof'}
}
$sliceInputs=[pscustomobject][ordered]@{
  'recipe-facts'=New-SliceInput '.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json'
  'process-ir'=New-SliceInput 'sdk/preview/mir4/reference/t12/MIR4_T12_RECEIPT.json'
  'technology-graph'=New-SliceInput '.mir/releases/waves/mir4-r0/MIR4-Semantic-Compiler-ProgrammeV1.json'
  'science-lab-graph'=New-SliceInput '.mir/releases/waves/mir4-r0/MIR4-K2-Science-SOL06V1.json'
  ownership=New-SliceInput '.mir/control-plane/ownership.json'
  settings=New-SliceInput '.mir/settings.yml'
  'runtime-state'=New-SliceInput '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json'
  diagnostics=New-SliceInput '.mir/releases/waves/mir4-r0/MIR4-ProcessIR-Synthesis-ProgrammeV1.json'
  presentation=New-SliceInput '.mir/releases/waves/mir4-r0/MIR4-Package-Presentation-OverlayV1.json'
  locale=New-SliceInput '.mir/locales/manifest.json'
  'package-identity'=New-SliceInput '.mir/control-plane/package-locks.json'
}
$sliceSet=New-MIR4W08SliceSet -SliceInputs $sliceInputs -RepoRoot $repo
$targetRegistryPath=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json'
$targetRegistryDigest=Get-MIR4W08FileSha256 $targetRegistryPath
$candidateProjectionDigest=Get-MIR4W08FileSha256 (Join-Path $repo '.mir/control-plane/package-locks.json')
$identityInputs=[pscustomobject][ordered]@{
  capture=[pscustomobject][ordered]@{environment_signature=$targetRegistryDigest;candidate_sha256=$candidateProjectionDigest;target='f210';inputs=[ordered]@{target_registry_sha256=$targetRegistryDigest;settings_root_sha256=@($sliceSet.slices|Where-Object id -eq settings)[0].root_sha256;package_identity_root_sha256=@($sliceSet.slices|Where-Object id -eq package-identity)[0].root_sha256;scope='authority-projection-only'}}
  compilation=[pscustomobject][ordered]@{abi=1;target='f210';snapshot_refs=@($sliceSet.slices|Where-Object{$_.id-in@('recipe-facts','technology-graph','science-lab-graph','ownership')}|ForEach-Object{[string]$_.root_sha256});policy_ref='MIR4-Semantic-Compiler-ProgrammeV1'}
  realization=[pscustomobject][ordered]@{abi=1;target='f210';accepted_plan_refs=@('MIR4-Target-Compiler-ProgrammeV1','MIR4-Semantic-Compiler-ProgrammeV1');candidate_sha256=$candidateProjectionDigest;executor_ref='tools/mir/application/targets/TargetCompiler.ps1'}
  evaluation=[pscustomobject][ordered]@{abi=1;expected_status='captured'}
}
$proofFixture=Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-assurance-scale-v1/proof-cover.json')|ConvertFrom-Json -Depth 50
$recoveryFixture=Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/mir4-assurance-scale-v1/recovery.json')|ConvertFrom-Json -Depth 50
$scale=New-MIR4W08AssuranceScaleResult -RepoRoot $repo -SourceIdentity $source -SliceInputs $sliceInputs -IdentityInputs $identityInputs -ProofCoverFixture $proofFixture -RecoveryFixture $recoveryFixture
$registry=Get-Content -Raw -LiteralPath $targetRegistryPath|ConvertFrom-Json -Depth 50
$budget=New-MIR4W08ReleaseBudgetPlan -RepoRoot $repo -SourceIdentity $source -AffectedTargets @($registry.identities.target) -ProofCover $scale.proof_cover
$drillRelative=($OutputRoot.TrimEnd('/','\')+'/drill').Replace('\','/')
$drill=Invoke-MIR4W08OfflineDrill -RepoRoot $repo -SourceIdentity $source -OutputRoot $drillRelative
$records=[ordered]@{
  'MIR4_ASSURANCE_SCALE_RESULT.json'=$scale
  'MIR4_RELEASE_BUDGET_PLAN.json'=$budget
  'MIR4_OFFLINE_DRILL_RESULT.json'=$drill
}
$schemas=[ordered]@{
  'MIR4_ASSURANCE_SCALE_RESULT.json'='spec/schemas/mir4-assurance-scale-result-v1.schema.json'
  'MIR4_RELEASE_BUDGET_PLAN.json'='spec/schemas/mir4-release-budget-plan-v1.schema.json'
  'MIR4_OFFLINE_DRILL_RESULT.json'='spec/schemas/mir4-offline-drill-result-v1.schema.json'
}
foreach($entry in $records.GetEnumerator()){
  $schema=Get-Content -Raw -LiteralPath (Join-Path $repo $schemas[$entry.Key])
  if(-not(($entry.Value|ConvertTo-Json -Depth 100)|Test-Json -Schema $schema)){throw "[mir4-w08-schema] $($entry.Key)"}
  if([string]$entry.Value.record_sha256-cne(Get-MIR4W08RecordSha256 $entry.Value)){throw "[mir4-w08-record-digest] $($entry.Key)"}
  $path=Join-Path $output $entry.Key
  if($Check){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "[mir4-w08-record-missing] $($entry.Key)"}
    $actual=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
    if((ConvertTo-MIRCPCanonicalJson -Value $actual)-cne(ConvertTo-MIRCPCanonicalJson -Value $entry.Value)){throw "[mir4-w08-record-stale] $($entry.Key)"}
  }else{Write-MIR4W08CanonicalJson -Path $path -Value $entry.Value}
}
[pscustomobject][ordered]@{status='partial-with-bounded-blockers';source_identity=$source;output=$OutputRoot;records=@($records.Keys);assurance_status=[string]$scale.status;budget_status=[string]$budget.status;offline_drill_status=[string]$drill.status;package_visible=$false;public_release_proof=$false;source_freeze_authorized=$false;production_signing_or_sealing_authorized=$false;publication_authorized=$false}|ConvertTo-Json -Depth 20
