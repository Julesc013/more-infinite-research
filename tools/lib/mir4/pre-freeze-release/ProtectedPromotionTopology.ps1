Set-StrictMode -Version Latest

function Invoke-MIR4A08Git {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  $output = @(& git -C $RepoRoot @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "[mir4-a08-git] git $($Arguments -join ' ') :: $($output -join ' ')"
  }
  return @($output | ForEach-Object { [string]$_ })
}

function Resolve-MIR4A08Commit {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Revision)
  $value = ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('rev-parse','--verify',"$Revision^{commit}")) -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "[mir4-a08-commit] $Revision" }
  return $value
}

function Resolve-MIR4A08Tree {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Commit)
  $value = ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('rev-parse','--verify',"$Commit^{tree}")) -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "[mir4-a08-tree] $Commit" }
  return $value
}

function Get-MIR4A08OptionalRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref)
  $output = @(& git -C $RepoRoot rev-parse --verify $Ref 2>$null)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { return $null }
  $value = ($output -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw "[mir4-a08-ref] $Ref" }
  return $value
}

function Get-MIR4A08CanonicalJson {
  param([Parameter(Mandatory)]$Value)
  return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Get-MIR4A08Sha256 {
  param([Parameter(Mandatory)]$Value)
  $bytes = [Text.Encoding]::UTF8.GetBytes((Get-MIR4A08CanonicalJson $Value))
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-MIR4A08PlanSha256 {
  param([Parameter(Mandatory)]$Plan)
  $copy = [ordered]@{}
  foreach ($property in $Plan.PSObject.Properties) {
    $copy[$property.Name] = if ($property.Name -ceq 'plan_sha256') { '' } else { $property.Value }
  }
  return Get-MIR4A08Sha256 ([pscustomobject]$copy)
}

function Assert-MIR4A08Plan {
  param([Parameter(Mandatory)]$Plan)
  if ([string]$Plan.kind -cne 'MIR42ProtectedMainPromotionTopologyPlanV1' -or
      [string]$Plan.plan_sha256 -cne (Get-MIR4A08PlanSha256 $Plan) -or
      [string]$Plan.strategy -cne 'main-based-tree-transplant-protected-pr' -or
      [string]$Plan.promotion.merge_method -cne 'squash' -or
      -not [bool]$Plan.promotion.pull_request_required -or
      [bool]$Plan.promotion.ruleset_mutation_authorized -or
      [bool]$Plan.promotion.force_push_authorized -or
      [bool]$Plan.release_authority -or
      [bool]$Plan.publication_authority) {
    throw '[mir4-a08-plan-invalid]'
  }
  return $Plan
}

function Get-MIR4A08CandidateMessage {
  param([Parameter(Mandatory)]$Plan)
  return "MIR 4.2 protected candidate`n`nMIR-Source-Commit: $($Plan.source.commit)`nMIR-Source-Tree: $($Plan.source.tree)`nMIR-Main-Base: $($Plan.main_before.commit)"
}

function New-MIR4ProtectedPromotionTopologyPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$MainRef = 'refs/remotes/origin/main',
    [string]$SourceRef = 'refs/remotes/origin/dev',
    [Parameter(Mandatory)][string]$CandidateRef,
    [Parameter(Mandatory)]$EffectivePolicy
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($CandidateRef -cnotmatch '^refs/heads/candidate/[a-z0-9][a-z0-9._-]{2,80}$') {
    throw '[mir4-a08-candidate-ref]'
  }
  $requiredChecks = @($EffectivePolicy.required_status_checks | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive -Unique)
  if (-not [bool]$EffectivePolicy.pull_request_required -or
      -not [bool]$EffectivePolicy.linear_history_required -or
      -not [bool]$EffectivePolicy.non_fast_forward_blocked -or
      -not [bool]$EffectivePolicy.deletion_blocked -or
      [int]$EffectivePolicy.bypass_actor_count -ne 0 -or
      -not [bool]$EffectivePolicy.squash_merge_enabled -or
      @('branch-policy','verification-gate' | Where-Object { $_ -notin $requiredChecks }).Count -ne 0) {
    throw '[mir4-a08-policy-incompatible]'
  }
  $mainCommit = Resolve-MIR4A08Commit -RepoRoot $repo -Revision $MainRef
  $sourceCommit = Resolve-MIR4A08Commit -RepoRoot $repo -Revision $SourceRef
  $sourceTree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $sourceCommit
  $mainTree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $mainCommit
  $mergeBase = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('merge-base',$mainCommit,$sourceCommit)) -join '').Trim()
  $cherry = @(Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('cherry',$sourceCommit,$mainCommit))
  $unintegrated = @($cherry | Where-Object { $_ -match '^\+\s+[0-9a-f]{40}$' })
  if ($unintegrated.Count -ne 0) { throw '[mir4-a08-main-change-not-integrated]' }
  $mainUniqueCount = [int](((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('rev-list','--count',"$mergeBase..$mainCommit")) -join '').Trim())
  if ($cherry.Count -ne $mainUniqueCount) { throw '[mir4-a08-main-history-not-linear-patch-set]' }
  $plan = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42ProtectedMainPromotionTopologyPlanV1'
    strategy = 'main-based-tree-transplant-protected-pr'
    main_before = [pscustomobject][ordered]@{ ref=$MainRef;commit=$mainCommit;tree=$mainTree }
    source = [pscustomobject][ordered]@{ ref=$SourceRef;commit=$sourceCommit;tree=$sourceTree }
    reconciliation = [pscustomobject][ordered]@{
      merge_base=$mergeBase
      main_unique_commit_count=$mainUniqueCount
      patch_equivalent_main_commit_count=@($cherry | Where-Object { $_ -match '^-\s+[0-9a-f]{40}$' }).Count
      all_main_changes_integrated=$true
    }
    candidate = [pscustomobject][ordered]@{
      ref=$CandidateRef;parent_commit=$mainCommit;source_commit=$sourceCommit;tree=$sourceTree
      construction='single-parent commit carrying the exact frozen dev tree';created=$false
    }
    qualification = [pscustomobject][ordered]@{
      exact_candidate_commit_required=$true;exact_candidate_tree_required=$true
      exact_package_bytes_required=$true;qualification_before_promotion=$true
    }
    promotion = [pscustomobject][ordered]@{
      branch='main';merge_method='squash';pull_request_required=$true
      required_status_checks=$requiredChecks;linear_history_required=$true
      ruleset_mutation_authorized=$false;force_push_authorized=$false;deletion_authorized=$false
    }
    readback = [pscustomobject][ordered]@{
      final_commit_may_differ=$true;exact_tree_required=$true;exact_package_bytes_required=$true
      main_base_ancestry_required=$true;source_ref_unchanged_required=$true
    }
    tag_creation_authority=$false
    main_mutation_authority=$false
    release_authority=$false
    publication_authority=$false
    plan_sha256=''
  }
  $plan.plan_sha256 = Get-MIR4A08PlanSha256 $plan
  return Assert-MIR4A08Plan $plan
}

function New-MIR4ProtectedMainCandidate {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $null = Assert-MIR4A08Plan $Plan
  $mainNow = Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.main_before.ref)
  $sourceNow = Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.source.ref)
  if ($mainNow -cne [string]$Plan.main_before.commit) { throw '[mir4-a08-main-ref-drift]' }
  if ($sourceNow -cne [string]$Plan.source.commit) { throw '[mir4-a08-source-ref-drift]' }
  $candidateRef = [string]$Plan.candidate.ref
  $candidateCommit = Get-MIR4A08OptionalRef -RepoRoot $repo -Ref $candidateRef
  $created = $false
  if ($null -eq $candidateCommit) {
    $message = Get-MIR4A08CandidateMessage $Plan
    $candidateCommit = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('commit-tree',[string]$Plan.source.tree,'-p',[string]$Plan.main_before.commit,'-m',$message)) -join '').Trim()
    if ($candidateCommit -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-a08-candidate-commit]' }
    $null = Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('update-ref',$candidateRef,$candidateCommit,('0'*40))
    $created = $true
  }
  $tree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $candidateCommit
  $parents = @(((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('show','-s','--format=%P',$candidateCommit)) -join '').Trim() -split '\s+' | Where-Object { $_ })
  $message = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('show','-s','--format=%B',$candidateCommit)) -join "`n").TrimEnd()
  if ($tree -cne [string]$Plan.source.tree -or $parents.Count -ne 1 -or $parents[0] -cne [string]$Plan.main_before.commit -or
      $message -cne (Get-MIR4A08CandidateMessage $Plan)) {
    throw '[mir4-a08-candidate-ref-conflict]'
  }
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR42ProtectedMainCandidateV1';ref=$candidateRef;commit=$candidateCommit;tree=$tree
    parent_commit=$parents[0];source_commit=[string]$Plan.source.commit;created=$created
    remote_push_performed=$false;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false
  }
}

function Get-MIR4A08PackageSetSha256 {
  param([Parameter(Mandatory)][object[]]$Packages)
  $normalized = @(foreach ($package in @($Packages | Sort-Object { [string]$_.target })) {
    [pscustomobject][ordered]@{
      target=[string]$package.target;archive_sha256=[string]$package.archive_sha256
      content_sha256=[string]$package.content_sha256;bytes=[long]$package.bytes;entry_count=[int]$package.entry_count
    }
  })
  if ($normalized.Count -eq 0 -or @($normalized.target | Sort-Object -Unique).Count -ne $normalized.Count -or
      @($normalized | Where-Object { $_.archive_sha256 -cnotmatch '^[A-F0-9]{64}$' -or $_.content_sha256 -cnotmatch '^[A-F0-9]{64}$' -or $_.bytes -lt 1 -or $_.entry_count -lt 1 }).Count -ne 0) {
    throw '[mir4-a08-package-set]'
  }
  return Get-MIR4A08Sha256 $normalized
}

function Test-MIR4ProtectedPromotionReadback {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Candidate,
    [string]$MainAfterRef = 'refs/remotes/origin/main',
    [Parameter(Mandatory)][object[]]$QualifiedPackages,
    [Parameter(Mandatory)][object[]]$ObservedPackages
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $null = Assert-MIR4A08Plan $Plan
  $candidateNow = Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Candidate.ref)
  if ($candidateNow -cne [string]$Candidate.commit -or [string]$Candidate.tree -cne [string]$Plan.source.tree) {
    throw '[mir4-a08-candidate-drift]'
  }
  $sourceNow = Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.source.ref)
  if ($sourceNow -cne [string]$Plan.source.commit) { throw '[mir4-a08-source-ref-drift-after-promotion]' }
  $mainAfter = Resolve-MIR4A08Commit -RepoRoot $repo -Revision $MainAfterRef
  $mainAfterTree = Resolve-MIR4A08Tree -RepoRoot $repo -Commit $mainAfter
  if ($mainAfterTree -cne [string]$Candidate.tree) { throw '[mir4-a08-readback-tree-mismatch]' }
  $null = Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('merge-base','--is-ancestor',[string]$Plan.main_before.commit,$mainAfter)
  if ($mainAfter -ceq [string]$Plan.main_before.commit) { throw '[mir4-a08-readback-no-promotion]' }
  $qualifiedPackageSet = Get-MIR4A08PackageSetSha256 $QualifiedPackages
  $observedPackageSet = Get-MIR4A08PackageSetSha256 $ObservedPackages
  if ($qualifiedPackageSet -cne $observedPackageSet) { throw '[mir4-a08-readback-package-mismatch]' }
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR42ProtectedMainPromotionReadbackV1';status='qualified-tree-on-main-awaiting-maintainer-playtest'
    main_before=[string]$Plan.main_before.commit;qualified_candidate_commit=[string]$Candidate.commit
    main_after=$mainAfter;tree=$mainAfterTree;commit_rewritten=($mainAfter -cne [string]$Candidate.commit)
    source_ref=[string]$Plan.source.ref;source_commit=$sourceNow;package_set_sha256=$observedPackageSet
    checks=@('protected-pr-topology','main-base-ancestry','exact-qualified-tree','exact-package-bytes','source-ref-unchanged')
    ruleset_mutation_performed=$false;force_push_performed=$false;tag_created=$false
    publication_performed=$false;publication_authorized=$false;human_playtest='pending'
  }
}
