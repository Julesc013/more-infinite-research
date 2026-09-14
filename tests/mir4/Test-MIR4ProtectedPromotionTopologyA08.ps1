# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/pre-freeze-release/ProtectedPromotionTopology.ps1')

$authorityPath=Join-Path $RepoRoot 'spec/releases/mir4-protected-main-promotion-topology-v1.json'
$schemaPath=Join-Path $RepoRoot 'spec/schemas/mir4-protected-main-promotion-topology-v1.schema.json'
$authorityText=Get-Content -Raw -LiteralPath $authorityPath
if(-not($authorityText|Test-Json -SchemaFile $schemaPath)){throw '[mir4-a08-authority-schema]'}
$authority=$authorityText|ConvertFrom-Json -Depth 30
if([string]$authority.status-cne'accepted-and-synthetically-rehearsed-release-blocked'-or
   [string]$authority.strategy-cne'main-based-tree-transplant-protected-pr'-or
   -not[bool]$authority.candidate.exact_dev_tree-or-not[bool]$authority.qualification.before_promotion-or
   -not[bool]$authority.readback.exact_tree_required-or-not[bool]$authority.readback.exact_package_bytes_required-or
   -not[bool]$authority.promotion.commit_identity_changes_at_squash_boundary-or
   [bool]$authority.authority.main_mutation-or[bool]$authority.authority.tagging-or[bool]$authority.authority.publication){throw '[mir4-a08-authority-contract]'}

function Expect-A08Failure {
  param([scriptblock]$Action,[string]$Code)
  try { & $Action | Out-Null } catch {
    if ($_.Exception.Message.StartsWith($Code,[StringComparison]::Ordinal)) { return }
    throw
  }
  throw "Expected A08 failure: $Code"
}

function Invoke-A08Git {
  param([string]$Root,[string[]]$Arguments)
  $output=@(& git -C $Root @Arguments 2>&1);if($LASTEXITCODE-ne0){throw "synthetic git failure: $($Arguments-join' ') :: $($output-join' ')"};return @($output)
}

$testRoot=Join-Path $RepoRoot ('build/tests/protected-promotion-a08/'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot|Out-Null
try {
  $null=Invoke-A08Git $testRoot @('init','-q','--initial-branch=main')
  $null=Invoke-A08Git $testRoot @('config','user.name','MIR A08 Rehearsal')
  $null=Invoke-A08Git $testRoot @('config','user.email','mir-a08@example.invalid')
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','base')
  $base=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()

  $null=Invoke-A08Git $testRoot @('switch','-q','-c','dev',$base)
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`nstable repair`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','forward-port stable repair')
  $null=Invoke-A08Git $testRoot @('switch','-q','main')
  [IO.File]::WriteAllText((Join-Path $testRoot 'README.md'),"base`nstable repair`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','README.md');$null=Invoke-A08Git $testRoot @('commit','-q','-m','stable repair')
  $mainBefore=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('switch','-q','dev')
  [IO.File]::WriteAllText((Join-Path $testRoot 'feature.txt'),"qualified feature tree`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','feature.txt');$null=Invoke-A08Git $testRoot @('commit','-q','-m','qualified feature')
  $source=((Invoke-A08Git $testRoot @('rev-parse','HEAD'))-join'').Trim()

  $policy=[pscustomobject][ordered]@{
    pull_request_required=$true;linear_history_required=$true;non_fast_forward_blocked=$true
    deletion_blocked=$true;bypass_actor_count=0;squash_merge_enabled=$true
    required_status_checks=@('verification-gate','branch-policy')
  }
  $candidateRef='refs/heads/candidate/mir42-a08-rehearsal'
  $plan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $candidateRef -EffectivePolicy $policy
  if([string]$plan.main_before.commit-cne$mainBefore-or[string]$plan.source.commit-cne$source-or
     [int]$plan.reconciliation.main_unique_commit_count-ne1-or[int]$plan.reconciliation.patch_equivalent_main_commit_count-ne1-or
     -not[bool]$plan.reconciliation.all_main_changes_integrated-or[bool]$plan.main_mutation_authority-or
     [bool]$plan.tag_creation_authority-or[bool]$plan.publication_authority){throw '[mir4-a08-plan-contract]'}
  $candidate=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan
  $adopted=New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $plan
  if(-not[bool]$candidate.created-or[bool]$adopted.created-or[string]$candidate.commit-cne[string]$adopted.commit-or
     [string]$candidate.parent_commit-cne$mainBefore-or[string]$candidate.tree-cne[string]$plan.source.tree){throw '[mir4-a08-candidate-recovery]'}

  $driftPlan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef refs/heads/candidate/mir42-a08-source-drift -EffectivePolicy $policy
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/dev',$base,$source)
  Expect-A08Failure { New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $driftPlan } '[mir4-a08-source-ref-drift]'
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/dev',$source,$base)

  $conflictRef='refs/heads/candidate/mir42-a08-conflict'
  $conflictPlan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $conflictRef -EffectivePolicy $policy
  $null=Invoke-A08Git $testRoot @('update-ref',$conflictRef,$base,('0'*40))
  Expect-A08Failure { New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $conflictPlan } '[mir4-a08-candidate-ref-conflict]'
  $forgedRef='refs/heads/candidate/mir42-a08-forged-message'
  $forgedPlan=New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef $forgedRef -EffectivePolicy $policy
  $forgedCommit=((Invoke-A08Git $testRoot @('commit-tree',[string]$forgedPlan.source.tree,'-p',$mainBefore,'-m','unbound candidate'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('update-ref',$forgedRef,$forgedCommit,('0'*40))
  Expect-A08Failure { New-MIR4ProtectedMainCandidate -RepoRoot $testRoot -Plan $forgedPlan } '[mir4-a08-candidate-ref-conflict]'

  $badPolicy=$policy|ConvertTo-Json -Depth 10|ConvertFrom-Json;$badPolicy.linear_history_required=$false
  Expect-A08Failure { New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main -SourceRef refs/heads/dev -CandidateRef refs/heads/candidate/mir42-a08-policy -EffectivePolicy $badPolicy } '[mir4-a08-policy-incompatible]'

  $null=Invoke-A08Git $testRoot @('branch','main-unintegrated',$mainBefore)
  $null=Invoke-A08Git $testRoot @('switch','-q','main-unintegrated')
  [IO.File]::WriteAllText((Join-Path $testRoot 'unintegrated.txt'),"not in dev`n",[Text.UTF8Encoding]::new($false))
  $null=Invoke-A08Git $testRoot @('add','unintegrated.txt');$null=Invoke-A08Git $testRoot @('commit','-q','-m','unintegrated stable change')
  Expect-A08Failure { New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $testRoot -MainRef refs/heads/main-unintegrated -SourceRef refs/heads/dev -CandidateRef refs/heads/candidate/mir42-a08-unintegrated -EffectivePolicy $policy } '[mir4-a08-main-change-not-integrated]'

  $finalMain=((Invoke-A08Git $testRoot @('commit-tree',[string]$candidate.tree,'-p',$mainBefore,'-m','synthetic protected squash result'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/main',$finalMain,$mainBefore)
  $packages=@(
    [pscustomobject]@{target='F200';archive_sha256='A'*64;content_sha256='B'*64;bytes=100;entry_count=10},
    [pscustomobject]@{target='F210';archive_sha256='C'*64;content_sha256='D'*64;bytes=200;entry_count=20}
  )
  $readback=Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -Plan $plan -Candidate $candidate -MainAfterRef refs/heads/main -QualifiedPackages $packages -ObservedPackages @($packages[1],$packages[0])
  if([string]$readback.status-cne'qualified-tree-on-main-awaiting-maintainer-playtest'-or-not[bool]$readback.commit_rewritten-or
     [string]$readback.main_after-cne$finalMain-or[bool]$readback.tag_created-or[bool]$readback.publication_authorized){throw '[mir4-a08-readback-contract]'}

  $badPackages=@($packages|ForEach-Object{$_|ConvertTo-Json|ConvertFrom-Json});$badPackages[0].archive_sha256='E'*64
  Expect-A08Failure { Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -Plan $plan -Candidate $candidate -MainAfterRef refs/heads/main -QualifiedPackages $packages -ObservedPackages $badPackages } '[mir4-a08-readback-package-mismatch]'
  $wrongTreeMain=((Invoke-A08Git $testRoot @('commit-tree',((Invoke-A08Git $testRoot @('rev-parse',"$base^{tree}"))-join'').Trim(),'-p',$mainBefore,'-m','wrong tree'))-join'').Trim()
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/main',$wrongTreeMain,$finalMain)
  Expect-A08Failure { Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -Plan $plan -Candidate $candidate -MainAfterRef refs/heads/main -QualifiedPackages $packages -ObservedPackages $packages } '[mir4-a08-readback-tree-mismatch]'
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/main',$finalMain,$wrongTreeMain)
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/dev',$base,$source)
  Expect-A08Failure { Test-MIR4ProtectedPromotionReadback -RepoRoot $testRoot -Plan $plan -Candidate $candidate -MainAfterRef refs/heads/main -QualifiedPackages $packages -ObservedPackages $packages } '[mir4-a08-source-ref-drift-after-promotion]'
  $null=Invoke-A08Git $testRoot @('update-ref','refs/heads/dev',$source,$base)
  if(@(Invoke-A08Git $testRoot @('tag','--list')).Count-ne0){throw '[mir4-a08-tag-created]'}
  Write-Host '[ok] A08 main-based candidate construction, protected squash readback, exact tree/package equivalence, drift recovery and fail-closed policy rehearsal passed without remote or release effects.'
} finally {
  if(Test-Path -LiteralPath $testRoot){
    Get-ChildItem -LiteralPath $testRoot -Force -Recurse | ForEach-Object {
      if(($_.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0){$_.Attributes=$_.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)}
    }
    [IO.Directory]::Delete($testRoot,$true)
  }
}
