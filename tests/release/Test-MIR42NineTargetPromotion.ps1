# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')

function Assert-MIR42NinePromotionTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-nine-promotion-test-$Code]" }
}

function New-MIR42NinePromotionProof {
  param([Parameter(Mandatory)][string]$Sha,[Parameter(Mandatory)][string]$RecordSha)
  return [pscustomobject][ordered]@{path=('C:\\synthetic-nonrelease\\' + $Sha + '.json');sha256=$Sha;record=[pscustomobject][ordered]@{record_sha256=$RecordSha}}
}

$contract = Get-MIR42SealScopeContract -Scope 'nine-target'
Assert-MIR42NinePromotionTest -Condition ([string]$contract.restore_kind -ceq 'MIR42NineTargetGovernedOfflineRestoreDrillV1') -Code 'restore-kind-contract'
Assert-MIR42NinePromotionTest -Condition ([string]$contract.restore_status -ceq 'MIR-4.2-NINE-TARGET-GOVERNED-OFFLINE-RESTORE-PASSED-POST-SEAL') -Code 'restore-status-contract'
Assert-MIR42NinePromotionTest -Condition ([string]$contract.restore_challenge_kind -ceq 'MIR42NineTargetGovernedOfflineRestoreChallengeV1') -Code 'restore-challenge-kind-contract'
Assert-MIR42NinePromotionTest -Condition ([string](Get-MIR42GovernedOfflineRestoreLedgerChallengePayload -Record ([pscustomobject]@{source=@{};candidate_manifest=@{};technical_seal=@{};protected_signing_ceremony=@{};recovery_custody=@{};clean_rehydrate=@{};restored_inventory=@();targets=@()}) -Scope 'nine-target').kind -ceq 'MIR42NineTargetGovernedOfflineRestoreChallengeV1') -Code 'restore-challenge-payload-scope'

$root = Join-Path $repo ('build/test-results/mir42-nine-target-promotion-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
  $mainCommit = '1' * 40
  $devCommit = '2' * 40
  $source = [pscustomobject][ordered]@{commit=$devCommit;tree=('3' * 40);package_source_sha256=('4' * 64)}
  $targets = @(
    foreach ($target in @($script:MIR42SealNineTargetCandidates)) {
      [pscustomobject][ordered]@{target=[string]$target;distribution_version=('4.2.' + $target.Substring(1) + '00');archive_sha256=(('A' + $target.Substring(1)).PadRight(64,'A'));content_sha256=(('B' + $target.Substring(1)).PadRight(64,'B'));entry_count=1}
    }
  )
  $candidate = [pscustomobject][ordered]@{
    identity=[pscustomobject][ordered]@{sha256=('C' * 64);record=[pscustomobject][ordered]@{record_sha256=('D' * 64)}}
    source=$source;scope='nine-target';targets=$targets
  }
  $qualification = New-MIR42NinePromotionProof -Sha ('E' * 64) -RecordSha ('F' * 64)
  $campaign = New-MIR42NinePromotionProof -Sha ('1' * 64) -RecordSha ('2' * 64)
  $independent = New-MIR42NinePromotionProof -Sha ('3' * 64) -RecordSha ('4' * 64)
  $signing = New-MIR42NinePromotionProof -Sha ('5' * 64) -RecordSha ('6' * 64)
  $freeze = New-MIR42NinePromotionProof -Sha ('7' * 64) -RecordSha ('8' * 64)
  $freeze.record = [pscustomobject][ordered]@{record_sha256=('8' * 64);promotion_base=[pscustomobject][ordered]@{commit=$mainCommit};frozen_dev=[pscustomobject][ordered]@{commit=$devCommit;tree=[string]$source.tree}}
  $reviewer = New-MIR42NinePromotionProof -Sha ('9' * 64) -RecordSha ('A' * 64)
  $acl = [pscustomobject][ordered]@{record=[pscustomobject][ordered]@{owner_sid='S-1-5-21-42';mutation_sids=@('S-1-5-21-42')};custodian_sid_set_sha256=('B' * 64)}
  $trustRoot = [pscustomobject][ordered]@{
    path='C:\\synthetic-nonrelease\\trust-root.json';sha256=('C' * 64)
    record=[pscustomobject][ordered]@{kind=[string]$contract.trust_root_kind;record_sha256=('D' * 64)}
    protected_root='C:\\synthetic-nonrelease\\protected-root';immutable_anchor='C:\\synthetic-nonrelease\\immutable-anchor'
  }
  $programme = [pscustomobject][ordered]@{
    path='.mir/releases/governance/mir4/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json';sha256=('E' * 64)
    record=[pscustomobject][ordered]@{kind=[string]$contract.programme_kind;record_sha256=('F' * 64);selected_targets=@($targets | ForEach-Object {[string]$_.target});direct_predecessors=@($targets | ForEach-Object {[pscustomobject][ordered]@{target=[string]$_.target}})}
  }
  $state = [pscustomobject][ordered]@{candidate=$candidate;programme=$programme;qualification=$qualification;campaign=$campaign;independent=$independent;t16_acl_contract=$acl;t16_trust_root=$trustRoot;signing=$signing;freeze=$freeze;reviewer=$reviewer}
  $readiness = [pscustomobject][ordered]@{
    schema=1;kind=[string]$contract.readiness_kind;status=(([string]$contract.readiness_status_prefix) + 'READY');checks=[pscustomobject]@{all=$true};blockers=@();technical_seal_authorized=$true
    protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;_state=$state
  }
  $assertedContract = Assert-MIR42PromotionReadinessScope -Readiness $readiness -RequiredScope 'nine-target'
  Assert-MIR42NinePromotionTest -Condition ([string]$assertedContract.seal_kind -ceq [string]$contract.seal_kind) -Code 'nine-readiness-current-programme-predecessors-trust-root'

  $sealRecord = [pscustomobject][ordered]@{
    schema=1;kind=[string]$contract.seal_kind;status=[string]$contract.seal_status;source=$source
    candidate_manifest=[ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    qualification=[ordered]@{sha256=[string]$qualification.sha256;record_sha256=[string]$qualification.record.record_sha256}
    real_engine_campaign=[ordered]@{sha256=[string]$campaign.sha256;record_sha256=[string]$campaign.record.record_sha256}
    independent_verification=[ordered]@{sha256=[string]$independent.sha256;record_sha256=[string]$independent.record.record_sha256}
    t16_acl_contract=[ordered]@{owner_sid=[string]$acl.record.owner_sid;mutation_sids=@($acl.record.mutation_sids);custodian_sid_set_sha256=[string]$acl.custodian_sid_set_sha256}
    t16_protected_root=[string]$trustRoot.protected_root;t16_immutable_anchor=[string]$trustRoot.immutable_anchor
    t16_ledger_trust_root=[ordered]@{path=[string]$trustRoot.path;sha256=[string]$trustRoot.sha256;record_sha256=[string]$trustRoot.record.record_sha256}
    signing_ceremony=[ordered]@{sha256=[string]$signing.sha256;record_sha256=[string]$signing.record.record_sha256}
    source_freeze_authority=[ordered]@{sha256=[string]$freeze.sha256;record_sha256=[string]$freeze.record.record_sha256}
    independent_reviewer_attestation=[ordered]@{sha256=[string]$reviewer.sha256;record_sha256=[string]$reviewer.record.record_sha256}
    targets=@($targets);protected_main_promotion_authorized=$false;human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  $sealRecord.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $sealRecord
  $seal = [pscustomobject][ordered]@{path=(Join-Path $root 'synthetic-nine-seal.json');sha256=('F' * 64);record=$sealRecord}
  Assert-MIR42ExpectedTechnicalSeal -Seal $seal -Readiness $readiness -Scope 'nine-target'

  $assetMismatch = $sealRecord | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $assetMismatch.targets[8].archive_sha256 = '0' * 64
  $assetMismatch.record_sha256 = ''
  $assetMismatch.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $assetMismatch
  $assetMismatchRejected = $false
  try { Assert-MIR42ExpectedTechnicalSeal -Seal ([pscustomobject]@{path=$seal.path;sha256=$seal.sha256;record=$assetMismatch}) -Readiness $readiness -Scope 'nine-target' } catch { $assetMismatchRejected = $_.Exception.Message -match '^\[mir42-promotion-seal-reconstruction\]' }
  Assert-MIR42NinePromotionTest -Condition $assetMismatchRejected -Code 'ninth-asset-mismatch-rejected'

  $scopeMismatch = $false
  try { Get-MIR42GovernedOfflineRestoreDrill -RepoRoot $repo -Path (Join-Path $root 'never-read.json') -Candidate $candidate -Seal $seal -Signing $signing -SshKeygenPath 'synthetic' -Scope 'four-target' | Out-Null } catch { $scopeMismatch = $_.Exception.Message -match '^\[mir42-promotion-governed-restore-candidate-scope\]' }
  Assert-MIR42NinePromotionTest -Condition $scopeMismatch -Code 'mixed-restore-scope-rejected-before-read'

  $nineReader = (Get-Item Function:Get-MIR42NineTargetTechnicalSealReadiness).ScriptBlock
  $fourReader = (Get-Item Function:Get-MIR42FourTargetTechnicalSealReadiness).ScriptBlock
  $sealReader = (Get-Item Function:Read-MIR42SealRecord).ScriptBlock
  $restoreReader = (Get-Item Function:Get-MIR42GovernedOfflineRestoreDrill).ScriptBlock
  $remoteReader = (Get-Item Function:Get-MIR42PromotionRemoteRef).ScriptBlock
  $candidateRefReader = (Get-Item Function:Assert-MIR42PromotionRemoteRefAbsent).ScriptBlock
  $sealReadCount = 0
  $restoreReadCount = 0
  try {
    Set-Item Function:Get-MIR42NineTargetTechnicalSealReadiness -Value { param($RepoRoot,$CandidateManifestPath,$QualificationPath,$RealEngineCampaignPath,$IndependentVerificationPath,$SigningCeremonyPath,$T16TrustRootPath,$OperatorTrustSourcePath,$T16ProtectedRootPath,$T16ImmutableAnchorPath,$T16ApprovedOwnerSid,$T16ApprovedMutationSids,$SourceFreezeAuthorityPath,$ReviewerAttestationPath,$SshKeygenPath) return $readiness }
    Set-Item Function:Get-MIR42FourTargetTechnicalSealReadiness -Value { throw '[mir42-nine-promotion-four-reader-forbidden]' }
    Set-Item Function:Read-MIR42SealRecord -Value { param($Path,$Code) if ($Code -cne 'mir42-promotion-seal') { throw "[mir42-nine-promotion-unexpected-read] $Code" }; $script:sealReadCount++; return $seal }
    Set-Item Function:Get-MIR42GovernedOfflineRestoreDrill -Value { param($RepoRoot,$Path,$Candidate,$Seal,$Signing,$SshKeygenPath,$Scope) if ($Scope -cne 'nine-target') { throw '[mir42-nine-promotion-restore-scope]' }; $script:restoreReadCount++; return [pscustomobject][ordered]@{sha256=('A' * 64);record=[pscustomobject][ordered]@{record_sha256=('B' * 64)}} }
    Set-Item Function:Get-MIR42PromotionRemoteRef -Value { param($RepoRoot,$Ref,$Code) if ($Ref -ceq 'refs/heads/main') { return $mainCommit }; if ($Ref -ceq 'refs/heads/dev') { return $devCommit }; throw '[mir42-nine-promotion-unexpected-ref]' }
    Set-Item Function:Assert-MIR42PromotionRemoteRefAbsent -Value { param($RepoRoot,$Ref) if ($Ref -cne ('refs/heads/release/mir-4.2-candidate-' + $devCommit.Substring(0,12))) { throw '[mir42-nine-promotion-candidate-ref]' } }
    $plan = Get-MIR42NineTargetProtectedMainPromotionPlan -RepoRoot $repo -TechnicalSealPath $seal.path -CandidateManifestPath 'synthetic-candidate.json' -QualificationPath 'synthetic-qualification.json' -RealEngineCampaignPath 'synthetic-campaign.json' -IndependentVerificationPath 'synthetic-independent.json' -SigningCeremonyPath 'synthetic-signing.json' -SourceFreezeAuthorityPath 'synthetic-freeze.json' -ReviewerAttestationPath 'synthetic-reviewer.json' -SshKeygenPath 'synthetic' -OfflineRestoreDrillPath 'synthetic-restore.json'
    Assert-MIR42NinePromotionTest -Condition ([string]$plan.kind -ceq 'MIR42NineTargetProtectedMainPromotionPlanV1' -and [string]$plan.scope -ceq 'nine-target' -and @($plan.target_assets).Count -eq 9 -and @($plan.direct_predecessors).Count -eq 9 -and [string]$plan.current_programme.record_sha256 -ceq [string]$programme.record.record_sha256 -and -not [bool]$plan.protected_main_promotion_authorized -and -not [bool]$plan.tagging_authorized -and -not [bool]$plan.publication_authorized) -Code 'nine-plan-binds-assets-predecessors-programme-proofs'
    Assert-MIR42NinePromotionTest -Condition ($sealReadCount -eq 1 -and $restoreReadCount -eq 1) -Code 'nine-seal-and-restore-read-once'

    $snapshot=[pscustomobject][ordered]@{branch='main';commit=('a'*40);tree=$source.tree;parents=@($mainCommit);message=$plan.candidate.source_commit_trailer;package_source_sha256=$source.package_source_sha256;remote='origin';ref='refs/heads/main';origin='https://github.com/Julesc013/more-infinite-research.git';remote_commit=('a'*40);dev_commit=$devCommit;working_tree_clean=$true;observed_at=[DateTimeOffset]::UtcNow.ToString('o')}
    Assert-MIR42NineTargetMainReadbackBinding -PromotionPlan $plan -PrimarySnapshot $snapshot
    foreach($mutation in @('tree','package_source_sha256','remote_commit','dev_commit','parents','message','branch','ref','working_tree_clean','same-dev-commit')) {
      $opposing=$snapshot|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
      switch($mutation) {
        'tree' {$opposing.tree='b'*40}
        'package_source_sha256' {$opposing.package_source_sha256='B'*64}
        'remote_commit' {$opposing.remote_commit='b'*40}
        'dev_commit' {$opposing.dev_commit='b'*40}
        'parents' {$opposing.parents=@('b'*40)}
        'message' {$opposing.message='Unbound merge'}
        'branch' {$opposing.branch='dev'}
        'ref' {$opposing.ref='refs/heads/dev'}
        'working_tree_clean' {$opposing.working_tree_clean='true'}
        'same-dev-commit' {$opposing.commit=$devCommit;$opposing.remote_commit=$devCommit}
      }
      $rejected=$false
      try {Assert-MIR42NineTargetMainReadbackBinding -PromotionPlan $plan -PrimarySnapshot $opposing} catch {$rejected=$_.Exception.Message -match '^\[mir42-main-readback-qualified-tree-package-binding\]'}
      Assert-MIR42NinePromotionTest -Condition $rejected -Code ('main-opposing-'+$mutation)
    }
    foreach($flag in @('protected_main_promotion_authorized','human_go_required_after_main_readback','tagging_authorized','publication_authorized')) {
      $opposingPlan=$plan|ConvertTo-Json -Depth 100|ConvertFrom-Json -Depth 100 -DateKind String
      $opposingPlan.$flag='false'
      $rejected=$false
      try {Assert-MIR42NineTargetMainReadbackBinding -PromotionPlan $opposingPlan -PrimarySnapshot $snapshot} catch {$rejected=$_.Exception.Message -match '^\[mir42-main-readback-nine-plan-state\]'}
      Assert-MIR42NinePromotionTest -Condition $rejected -Code ('main-typed-flag-'+$flag)
    }
    Set-Item Function:Get-MIR42PromotionRemoteRef -Value {throw '[mir42-nine-main-pre-promotion-ref-replay-forbidden]'}
    Set-Item Function:Assert-MIR42PromotionRemoteRefAbsent -Value {throw '[mir42-nine-main-candidate-must-already-exist]'}
    $postPlan=Get-MIR42ProtectedMainPromotionPlanShared -RequiredScope 'nine-target' -PostPromotionReadback -RepoRoot $repo -TechnicalSealPath $seal.path -CandidateManifestPath 'synthetic-candidate.json' -QualificationPath 'synthetic-qualification.json' -RealEngineCampaignPath 'synthetic-campaign.json' -IndependentVerificationPath 'synthetic-independent.json' -SigningCeremonyPath 'synthetic-signing.json' -SourceFreezeAuthorityPath 'synthetic-freeze.json' -ReviewerAttestationPath 'synthetic-reviewer.json' -SshKeygenPath 'synthetic' -OfflineRestoreDrillPath 'synthetic-restore.json'
    Assert-MIR42NinePromotionTest -Condition ([string]$postPlan.source.commit -ceq $devCommit -and [string]$postPlan.main_before -ceq $mainCommit -and $sealReadCount -eq 2 -and $restoreReadCount -eq 2) -Code 'post-main-reconstructs-signed-proof-without-pre-promotion-ref-replay'

    $script:prFixture=[pscustomobject]@{merged=$true;draft=$false;state='closed';base=@{ref='main';repo=@{full_name='Julesc013/more-infinite-research'}};head=@{ref=$plan.candidate.ref.Substring(11);sha=('c'*40);repo=@{full_name='Julesc013/more-infinite-research'}};merge_commit_sha=$snapshot.commit;html_url='https://github.com/Julesc013/more-infinite-research/pull/999';merged_at='2026-09-27T00:00:00Z'}
    $script:commitFixture=[pscustomobject]@{sha=('c'*40);tree=@{sha=$source.tree};parents=@(@{sha=$mainCommit});message=$plan.candidate.source_commit_trailer}
    $transport=[pscustomobject]@{candidate=@{ref=$plan.candidate.ref;commit=('c'*40);expected_commit_message=$plan.candidate.source_commit_trailer}}
    $script:checkFixture=[pscustomobject]@{total_count=2;check_runs=@(@{id=1;name='branch-policy';head_sha=('c'*40);status='completed';conclusion='success';html_url='https://github.com/Julesc013/more-infinite-research/actions/runs/1'},@{id=2;name='verification-gate';head_sha=('c'*40);status='completed';conclusion='success';html_url='https://github.com/Julesc013/more-infinite-research/actions/runs/2'})}
    $savedApi=(Get-Item Function:Invoke-MIR42PromotionGitHubApiJson).ScriptBlock
    $savedChecks=(Get-Item Function:Get-MIR42ProtectedMainRequiredCheckObservations).ScriptBlock
    try {
      function Invoke-MIR42PromotionGitHubApiJson {
        param($Endpoint,$Code)
        switch($Endpoint) {
          'repos/Julesc013/more-infinite-research/pulls/999' {$script:prFixture}
          ('repos/Julesc013/more-infinite-research/git/commits/'+('c'*40)) {$script:commitFixture}
          ('repos/Julesc013/more-infinite-research/commits/'+('c'*40)+'/check-runs?per_page=100') {$script:checkFixture}
          default {throw '[mir42-nine-main-fixture-unexpected-endpoint]'}
        }
      }
      function Get-MIR42ProtectedMainRequiredCheckObservations {
        param($CandidateHead,$CandidateRef,$PullRequestNumber,$RequiredStatusChecks)
        if($CandidateHead -cne ('c'*40) -or $CandidateRef -cne $plan.candidate.ref -or $PullRequestNumber -ne 999 -or ($RequiredStatusChecks -join '|') -cne 'branch-policy|verification-gate'){throw '[mir42-nine-main-fixture-check-contract]'}
        if($script:checkFixture.check_runs[1].conclusion -cne 'success'){throw '[mir42-main-check-required] verification-gate'}
        return @($script:checkFixture.check_runs)
      }
      $observation=Get-MIR42NineTargetMergedPromotionObservation -PromotionPlan $plan -PrimarySnapshot $snapshot -Transport $transport -PullRequestNumber 999
      Assert-MIR42NinePromotionTest -Condition ([string]$observation.merge_commit -ceq $snapshot.commit -and @($observation.required_checks).Count -eq 2) -Code 'main-actual-observer-contract-with-synthetic-api'

      # Exercise the complete producer chain with synthetic proof/readers.
      # The real carrier and required-check readers have separate opposing tests.
      $topReaders=@{}
      foreach($name in @('Read-MIR4A08NineTargetPromotionTransport','Get-MIR42PrimaryMainSnapshot','New-MIR4A08GitHubRestPolicyProvider','Get-MIR4A08PolicyObservation','Get-MIR42PromotionRemoteRef')){
        $item=Get-Item ('Function:'+$name) -ErrorAction SilentlyContinue
        $topReaders[$name]=if($null -ne $item){$item.ScriptBlock}else{$null}
      }
      $syntheticTransport=[pscustomobject]@{scope='nine-target';binding_sha256=('A'*64);promotion_plan_sha256=('B'*64);candidate=$transport.candidate;policy=@{policy_sha256=('C'*64)};request=@{path='synthetic-request';sha256=('D'*64);request_sha256=('E'*64);expected_commit_message=$snapshot.message};intention=@{path='synthetic-intention';sha256=('F'*64);intention_sha256=('1'*64)}}
      $script:syntheticPolicyHash='C'*64
      try{
        function Read-MIR4A08NineTargetPromotionTransport {param($IntentionPath,$PromotionRequestPath,$PromotionPlan) if($IntentionPath -cne 'synthetic-intention' -or $PromotionRequestPath -cne 'synthetic-request' -or $PromotionPlan.scope -cne 'nine-target' -or $PromotionPlan.source.commit -cne $devCommit){throw '[mir42-nine-main-synthetic-transport-binding]'};return $syntheticTransport}
        function Get-MIR42PrimaryMainSnapshot {param($PrimaryRepoRoot) if($PrimaryRepoRoot -cne $root){throw '[mir42-nine-main-synthetic-primary]'};return $snapshot}
        function New-MIR4A08GitHubRestPolicyProvider {param($GhExecutable) return {}}
        function Get-MIR4A08PolicyObservation {param($CanonicalRepository,$PolicyProvider) if($CanonicalRepository -cne 'Julesc013/more-infinite-research'){throw '[mir42-nine-main-synthetic-repository]'};return [pscustomobject]@{policy_sha256=$script:syntheticPolicyHash}}
        function Get-MIR42PromotionRemoteRef {param($RepoRoot,$Ref,$Code) if($RepoRoot -cne $root -or $Ref -cne $plan.candidate.ref){throw '[mir42-nine-main-synthetic-candidate-ref]'};return ('c'*40)}
        $topArguments=@{RepoRoot=$repo;PrimaryRepoRoot=$root;PullRequestNumber=999;IntentionPath='synthetic-intention';PromotionRequestPath='synthetic-request';TechnicalSealPath=$seal.path;CandidateManifestPath='synthetic-candidate.json';QualificationPath='synthetic-qualification.json';RealEngineCampaignPath='synthetic-campaign.json';IndependentVerificationPath='synthetic-independent.json';SigningCeremonyPath='synthetic-signing.json';SourceFreezeAuthorityPath='synthetic-freeze.json';ReviewerAttestationPath='synthetic-reviewer.json';SshKeygenPath='synthetic';OfflineRestoreDrillPath='synthetic-restore.json'}
        $complete=Get-MIR42NineTargetProtectedMainReadback @topArguments
        Assert-MIR42NinePromotionTest -Condition ((Test-MIR4BootstrapRecordHash -Record $complete) -and $complete.main_readback_verified -and $complete.source_rebinding.explicit_commit_rebinding -and @($complete.target_assets).Count -eq 9 -and -not $complete.tagging_authorized -and -not $complete.publication_authorized) -Code 'complete-main-producer-chain-synthetic-only'
        $script:syntheticPolicyHash='D'*64
        $rejected=$false
        try{Get-MIR42NineTargetProtectedMainReadback @topArguments|Out-Null}catch{$rejected=$_.Exception.Message -match '^\[mir42-main-readback-protected-policy-drift\]'}
        Assert-MIR42NinePromotionTest -Condition $rejected -Code 'complete-main-producer-rejects-policy-drift'
      }finally{
        foreach($name in $topReaders.Keys){if($null -ne $topReaders[$name]){Set-Item ('Function:'+$name) -Value $topReaders[$name]}else{Remove-Item ('Function:'+$name) -ErrorAction SilentlyContinue}}
        Remove-Variable -Name syntheticPolicyHash -Scope Script -ErrorAction SilentlyContinue
      }

      $script:prFixture.merged=$false
      $rejected=$false
      try {Get-MIR42NineTargetMergedPromotionObservation -PromotionPlan $plan -PrimarySnapshot $snapshot -Transport $transport -PullRequestNumber 999|Out-Null} catch {$rejected=$_.Exception.Message -match '^\[mir42-main-readback-pr-binding\]'}
      Assert-MIR42NinePromotionTest -Condition $rejected -Code 'unmerged-pr-rejected'
      $script:prFixture.merged=$true
      $transport.candidate.commit='d'*40
      $rejected=$false
      try {Get-MIR42NineTargetMergedPromotionObservation -PromotionPlan $plan -PrimarySnapshot $snapshot -Transport $transport -PullRequestNumber 999|Out-Null} catch {$rejected=$_.Exception.Message -match '^\[mir42-main-readback-pr-binding\]'}
      Assert-MIR42NinePromotionTest -Condition $rejected -Code 'head-different-from-persisted-candidate-rejected'
      $transport.candidate.commit='c'*40
      $script:commitFixture.parents=@(@{sha=('d'*40)})
      $rejected=$false
      try {Get-MIR42NineTargetMergedPromotionObservation -PromotionPlan $plan -PrimarySnapshot $snapshot -Transport $transport -PullRequestNumber 999|Out-Null} catch {$rejected=$_.Exception.Message -match '^\[mir42-main-readback-pr-head-topology\]'}
      Assert-MIR42NinePromotionTest -Condition $rejected -Code 'candidate-wrong-main-parent-rejected'
      $script:commitFixture.parents=@(@{sha=$mainCommit})
      $script:checkFixture.check_runs[1].conclusion='failure'
      $rejected=$false
      try {Get-MIR42NineTargetMergedPromotionObservation -PromotionPlan $plan -PrimarySnapshot $snapshot -Transport $transport -PullRequestNumber 999|Out-Null} catch {$rejected=$_.Exception.Message -match '^\[mir42-main-check-required\]'}
      Assert-MIR42NinePromotionTest -Condition $rejected -Code 'failed-verification-check-rejected'
    } finally {
      Set-Item Function:Invoke-MIR42PromotionGitHubApiJson -Value $savedApi
      Set-Item Function:Get-MIR42ProtectedMainRequiredCheckObservations -Value $savedChecks
    }

    $outputRecord=[pscustomobject][ordered]@{schema=1;kind='MIR42NineTargetProtectedMainReadbackV1';scope='nine-target';synthetic=$true;record_sha256=''}
    $outputRecord.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $outputRecord
    $outputPath=Join-Path $root 'build/release-readback/synthetic.json'
    $syntheticSealReader=(Get-Item Function:Read-MIR42SealRecord).ScriptBlock
    try {
      Set-Item Function:Read-MIR42SealRecord -Value $sealReader
      $written=Write-MIR42NineTargetProtectedMainReadback -Record $outputRecord -PrimaryRepoRoot $root -OutputPath $outputPath
      Assert-MIR42NinePromotionTest -Condition ([string]$written.record.record_sha256 -ceq [string]$outputRecord.record_sha256) -Code 'readback-create-only-contained-output'
      foreach($opposingPath in @($outputPath,(Join-Path $root 'outside.json'),(Join-Path $root 'build/release-readback/../escape.json'))) {
        $rejected=$false
        try{Write-MIR42NineTargetProtectedMainReadback -Record $outputRecord -PrimaryRepoRoot $root -OutputPath $opposingPath|Out-Null}catch{$rejected=$_.Exception.Message -match '^\[mir42-main-readback-output-(?:exists|containment)\]'}
        Assert-MIR42NinePromotionTest -Condition $rejected -Code 'readback-opposing-output-preserves-or-rejects'
      }
    } finally {
      Set-Item Function:Read-MIR42SealRecord -Value $syntheticSealReader
    }

    $mixedCandidate = $candidate | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $mixedCandidate.targets = @($mixedCandidate.targets[0..3])
    $mixedCandidate.scope = 'four-target'
    $mixedReadiness = $readiness | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    $mixedReadiness._state.candidate = $mixedCandidate
    Set-Item Function:Get-MIR42NineTargetTechnicalSealReadiness -Value { param($RepoRoot,$CandidateManifestPath,$QualificationPath,$RealEngineCampaignPath,$IndependentVerificationPath,$SigningCeremonyPath,$T16TrustRootPath,$OperatorTrustSourcePath,$T16ProtectedRootPath,$T16ImmutableAnchorPath,$T16ApprovedOwnerSid,$T16ApprovedMutationSids,$SourceFreezeAuthorityPath,$ReviewerAttestationPath,$SshKeygenPath) return $mixedReadiness }
    $sealReadCount = 0
    $restoreReadCount = 0
    $mixedRejected = $false
    try { Get-MIR42NineTargetProtectedMainPromotionPlan -RepoRoot $repo -TechnicalSealPath $seal.path -CandidateManifestPath 'synthetic-candidate.json' -QualificationPath 'synthetic-qualification.json' -RealEngineCampaignPath 'synthetic-campaign.json' -IndependentVerificationPath 'synthetic-independent.json' -SigningCeremonyPath 'synthetic-signing.json' -SourceFreezeAuthorityPath 'synthetic-freeze.json' -ReviewerAttestationPath 'synthetic-reviewer.json' -SshKeygenPath 'synthetic' -OfflineRestoreDrillPath 'synthetic-restore.json' | Out-Null } catch { $mixedRejected = $_.Exception.Message -match '^\[mir42-promotion-candidate-scope\]' }
    Assert-MIR42NinePromotionTest -Condition ($mixedRejected -and $sealReadCount -eq 0 -and $restoreReadCount -eq 0) -Code 'mixed-four-nine-rejected-before-seal-or-restore-output'
  } finally {
    Set-Item Function:Get-MIR42NineTargetTechnicalSealReadiness -Value $nineReader
    Set-Item Function:Get-MIR42FourTargetTechnicalSealReadiness -Value $fourReader
    Set-Item Function:Read-MIR42SealRecord -Value $sealReader
    Set-Item Function:Get-MIR42GovernedOfflineRestoreDrill -Value $restoreReader
    Set-Item Function:Get-MIR42PromotionRemoteRef -Value $remoteReader
    Set-Item Function:Assert-MIR42PromotionRemoteRefAbsent -Value $candidateRefReader
  }
} finally {
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not $root.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-promotion-fixture-containment]' }
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

Write-Output 'MIR42-NINE-TARGET-PROMOTION-PASSED synthetic-boundaries=4,9 assets=9 processes=0 remote-mutations=0'
