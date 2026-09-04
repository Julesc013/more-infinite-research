Set-StrictMode -Version Latest

if (-not (Get-Command Resolve-MIR4FactorioQualificationProfile -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../../lib/validation/FactorioVersionPolicy.ps1')
}
if (-not (Get-Command Get-MIR4F210EngineResolutionV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../F210QualificationPolicy.ps1')
}

function Get-MIR441TargetEvidenceRoot {
  param([Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$Target)
  $path=Join-Path $EvidenceRoot "qualification/$Target"
  if(-not(Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Force -Path $path|Out-Null}
  return $path
}

function Get-MIR441TargetEngineIdentity {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Target)
  $binary=(Resolve-Path -LiteralPath ([string]$Target.factorio_binary)).Path
  $item=Get-Item -LiteralPath $binary
  $version=[string]$item.VersionInfo.ProductVersion
  if($version-match'^([0-9]+[.][0-9]+[.][0-9]+)'){$version=[string]$Matches[1]}
  $identity=[pscustomobject][ordered]@{version=$version;file_version=[string]$item.VersionInfo.FileVersion;binary_sha256=(Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToUpperInvariant();path=$binary}
  $profile=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation/profiles/factorio-$([string]$Target.factorio_line).json")|ConvertFrom-Json -Depth 100
  $effective=Resolve-MIR4FactorioQualificationProfile -Profile $profile -FactorioBin $binary -RepoRoot $RepoRoot
  if([string]$effective.qualification_factorio_version-cne$version){throw "[mir441-engine-profile] $([string]$Target.target)"}
  if([string]$Target.target-ceq'f210'){
    $channel=Get-MIR4F210EngineResolutionV1 -RepoRoot $RepoRoot -FactorioBin $binary
    if([string]$channel.engine.sha256-cne[string]$identity.binary_sha256){throw '[mir441-f210-engine-channel]'}
    $identity|Add-Member -NotePropertyName policy -NotePropertyValue 'latest-installed-official-experimental-exact-lock'
    $identity|Add-Member -NotePropertyName channel_record_sha256 -NotePropertyValue ([string]$channel.record_sha256)
  }elseif(-not(Test-MIR4FixedFactorioEngineIdentity -Target ([string]$Target.target) -ObservedIdentity $identity -RepoRoot $RepoRoot)){
    throw "[mir441-fixed-engine-lock] $([string]$Target.target)"
  }else{$identity|Add-Member -NotePropertyName policy -NotePropertyValue 'fixed-exact-lock'}
  return $identity
}

function Invoke-MIR441TargetQualification {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][string]$EvidenceRoot
  )
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
  $targetRows=@($contract.targets|Where-Object{[string]$_.target-ceq$Target})
  if($targetRows.Count-ne1){throw "[mir441-qualification-target] $Target"};$targetRow=$targetRows[0]
  $work=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $WorkRoot -Name WorkRoot
  $evidence=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $EvidenceRoot -Name EvidenceRoot
  $targetWork=Join-Path $work $Target
  if(Test-Path -LiteralPath $targetWork){Remove-MIR441ContainedTree -AdmittedRoot $work -Path $targetWork}
  New-Item -ItemType Directory -Force -Path $targetWork|Out-Null
  $targetEvidence=Get-MIR441TargetEvidenceRoot -EvidenceRoot $evidence -Target $Target
  $candidateManifest=Get-Content -Raw -LiteralPath (Join-Path $evidence 'candidate-manifest.json')|ConvertFrom-Json -Depth 100
  $candidateRows=@($candidateManifest.targets|Where-Object{[string]$_.target-ceq$Target})
  if($candidateRows.Count-ne1){throw "[mir441-qualification-candidate] $Target"};$candidateRow=$candidateRows[0]
  $source=Get-MIR441GitIdentity -RepoRoot $repo
  if([string]$candidateManifest.source.commit-cne[string]$source.commit-or[string]$candidateManifest.source.tree-cne[string]$source.tree){throw '[mir441-qualification-source-drift]'}
  $candidate=Join-Path $evidence "assets/$([string]$candidateRow.asset.path)"
  if((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash-cne[string]$candidateRow.asset.sha256){throw '[mir441-qualification-candidate-drift]'}
  $predecessor=Join-Path $repo "dist/more-infinite-research_$([string]$targetRow.predecessor).zip"
  if(-not(Test-Path -LiteralPath $predecessor -PathType Leaf)){throw "[mir441-qualification-predecessor] $Target"}
  $engine=Get-MIR441TargetEngineIdentity -RepoRoot $repo -Target $targetRow
  $admission=Assert-MIR441ResourceAdmission -Policy $contract.resource_policy -WorkRoot $work -EstimatedPeakBytes 4GB
  $ledger=Join-Path $targetEvidence 'resource-ledger.jsonl'
  $runtime=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/scenarios/runtime.json')|ConvertFrom-Json -Depth 100
  $profileProperty=$runtime.profiles.PSObject.Properties[[string]$targetRow.factorio_line]
  if($null-eq$profileProperty){throw "[mir441-qualification-runtime-profile] $Target"}
  $declarations=@($profileProperty.Value|Where-Object{$_.kind-ne'gate'-and$_.tags-contains'smoke'}|Sort-Object name)
  if($declarations.Count-eq0){throw "[mir441-qualification-runtime-empty] $Target"}
  $scenarioRows=[Collections.Generic.List[object]]::new()
  $pwsh=(Get-Command pwsh -ErrorAction Stop).Source
  foreach($declaration in $declarations){
    $name=[string]$declaration.name;$slug=$name-replace'[^A-Za-z0-9._-]','-'
    $scenarioWork=Join-Path $targetWork "fresh/$slug";$summary=Join-Path $targetEvidence "fresh-$slug.json"
    $run=Invoke-MIR441MonitoredProcess -FilePath $pwsh -Arguments @('-NoProfile','-File',(Join-Path $repo 'scripts/Invoke-MIRValidation.ps1'),'-ScenarioWorker','-Scenario',$name,'-FactorioBin',([string]$engine.path),'-UserDataDir',$scenarioWork,'-CandidateZip',$candidate,'-MaxParallel','1','-ValidationSummaryPath',$summary) -WorkRoot $work -LedgerPath $ledger -Policy $contract.resource_policy
    $result=Get-Content -Raw -LiteralPath $summary|ConvertFrom-Json -Depth 100
    if([string]$result.status-cne'passed'-or[string]$result.validation_package_sha256-cne[string]$candidateRow.asset.sha256-or[string]$result.validation_package_content_sha256-cne[string]$candidateRow.content_sha256){throw "[mir441-qualification-runtime] $Target/$name"}
    $scenarioRows.Add([pscustomobject][ordered]@{name=$name;status='passed';assertions=[int]$result.assertions_executed;duration_seconds=[double]$result.duration_seconds;process_peak_working_set_bytes=[int64]$run.peak_working_set_bytes;evidence=(Get-MIR441FileIdentity -Path $summary -RelativePath (Split-Path -Leaf $summary))})
    Remove-MIR441ContainedTree -AdmittedRoot $targetWork -Path $scenarioWork
  }
  $upgradeOutput=Join-Path $targetEvidence 'upgrade-matrix.json';$upgradeWork=Join-Path $targetWork 'upgrade'
  $upgradeRun=Invoke-MIR441MonitoredProcess -FilePath $pwsh -Arguments @('-NoProfile','-File',(Join-Path $repo 'tests/runtime/Test-MIRUpgradeMatrix.ps1'),'-RepoRoot',$repo,'-FactorioBin',([string]$engine.path),'-FromZip',$predecessor,'-ToZip',$candidate,'-FromVersion',([string]$targetRow.predecessor),'-ToVersion',([string]$targetRow.distribution_version),'-FixtureName',([string]$targetRow.upgrade_fixture),'-OutputPath',$upgradeOutput,'-WorkRoot',$upgradeWork,'-Retention','OnFailure') -WorkRoot $work -LedgerPath $ledger -Policy $contract.resource_policy
  $upgrade=Get-Content -Raw -LiteralPath $upgradeOutput|ConvertFrom-Json -Depth 100
  if([string]$upgrade.status-cne'passed'-or@($upgrade.rows|Where-Object{$_.status-ne'passed'}).Count-ne0-or[int]$upgrade.expanded_roots_retained-ne0){throw "[mir441-qualification-upgrade] $Target"}
  if(Test-Path -LiteralPath $upgradeWork){Remove-MIR441ContainedTree -AdmittedRoot $targetWork -Path $upgradeWork}
  $finalSnapshot=Get-MIR441ResourceSnapshot -WorkRoot $work
  $result=[pscustomobject][ordered]@{
    schema=1;kind='MIR441TargetQualificationV1';status='passed';target=$Target;source=$source;engine=$engine
    candidate=[ordered]@{distribution_version=[string]$targetRow.distribution_version;archive=$candidateRow.asset;content_sha256=[string]$candidateRow.content_sha256;entry_count=[int]$candidateRow.entry_count}
    predecessor=[ordered]@{version=[string]$targetRow.predecessor;sha256=(Get-FileHash -LiteralPath $predecessor -Algorithm SHA256).Hash.ToUpperInvariant()}
    fresh_loads=@($scenarioRows);upgrade=[ordered]@{fixture=[string]$targetRow.upgrade_fixture;archetypes=@($upgrade.required_archetypes);first_reload=$true;second_reload=$true;evidence=(Get-MIR441FileIdentity -Path $upgradeOutput -RelativePath 'upgrade-matrix.json');process_peak_working_set_bytes=[int64]$upgradeRun.peak_working_set_bytes}
    performance=[ordered]@{method='observed-fresh-load-and-upgrade-process-telemetry';fresh_duration_seconds=[Math]::Round((@($scenarioRows|Measure-Object duration_seconds -Sum).Sum),3);upgrade_duration_seconds=[double]$upgradeRun.duration_seconds;regression='none-observed'}
    resources=[ordered]@{admission=$admission;final=$finalSnapshot;factorio_process_concurrency=1;materialization_concurrency=1;expanded_success_roots='removed'}
    independent_verification='pending';technical_seal='pending';publication_authorized=$false
  }
  $resultPath=Join-Path $targetEvidence 'target-qualification.json';Write-MIR441Json -Value $result -Path $resultPath
  Remove-MIR441ContainedTree -AdmittedRoot $work -Path $targetWork
  return $result
}

function Invoke-MIR441FourTargetQualification {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$EvidenceRoot)
  $rows=[Collections.Generic.List[object]]::new()
  foreach($target in @('f210','f200','f110','f100')){$rows.Add((Invoke-MIR441TargetQualification -RepoRoot $RepoRoot -Target $target -WorkRoot $WorkRoot -EvidenceRoot $EvidenceRoot))}
  $aggregate=[pscustomobject][ordered]@{schema=1;kind='MIR441FourTargetQualificationV1';status='MIR-4.1.0-FOUR-TARGET-TECHNICAL-QUALIFICATION-PASSED';source=(Get-MIR441GitIdentity -RepoRoot $RepoRoot);targets=@($rows);all_targets_required=$true;cross_target_substitution=$false;independent_verification='pending';technical_seal='pending';publication_authorized=$false}
  Write-MIR441Json -Value $aggregate -Path (Join-Path $EvidenceRoot 'qualification/aggregate.json')
  return $aggregate
}
