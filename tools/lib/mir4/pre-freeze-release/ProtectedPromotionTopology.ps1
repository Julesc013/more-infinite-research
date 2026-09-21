Set-StrictMode -Version Latest

# A08 models the only permitted topology; it is not a release controller.
# Every external observation is supplied by a read-only provider.  The sole
# write-capable transport is explicit rehearsal-only candidate-ref creation.

function Invoke-MIR4A08Git {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string[]]$Arguments)
  $output = @(& git -C $RepoRoot -c commit.gpgSign=false @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "[mir4-a08-git] git $($Arguments -join ' ') :: $($output -join ' ')" }
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

function Resolve-MIR4A08Blob {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Commit,[Parameter(Mandatory)][string]$Path)
  if ($Path -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{1,240}$' -or $Path -match '(^|/)\.\.?(/|$)') { throw '[mir4-a08-materializer-path]' }
  $value = ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('rev-parse','--verify',"$Commit`:$Path")) -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-a08-materializer-binding]' }
  return $value
}

function Read-MIR4A08CommitJson {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Commit,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  $null = Resolve-MIR4A08Blob -RepoRoot $RepoRoot -Commit $Commit -Path $Path
  try {
    return ((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('show',"$Commit`:$Path")) -join "`n") | ConvertFrom-Json -Depth 100 -DateKind String
  } catch {
    throw $Code
  }
}

function Get-MIR4A08CommitPackageSourceFingerprint {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Commit)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  Assert-MIR4A08GitSha $Commit '[mir4-a08-package-source-fingerprint]'
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '../../validation/PackageIdentity.ps1')
  }
  $scratchParent=Join-Path $repo 'build/mir4/a08-package-source-fingerprint'
  $scratch=Join-Path $scratchParent ([guid]::NewGuid().ToString('N'))
  $archive=Join-Path $scratch 'candidate-source.zip'
  $extract=Join-Path $scratch 'source-tree'
  [IO.Directory]::CreateDirectory($extract)|Out-Null
  try {
    $null=Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('archive','--format=zip',"--output=$archive",$Commit,'source','targets')
    Expand-Archive -LiteralPath $archive -DestinationPath $extract
    return Get-MIRPackageSourceFingerprint -RepoRoot $extract
  } catch {
    throw "[mir4-a08-package-source-fingerprint] $($_.Exception.Message)"
  } finally {
    if (Test-Path -LiteralPath $scratch) {
      Get-ChildItem -LiteralPath $scratch -Force -Recurse | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReadOnly) {
          $_.Attributes=$_.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
        }
      }
      [IO.Directory]::Delete($scratch,$true)
    }
  }
}

function Get-MIR4A08OptionalRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref)
  $output = @(& git -C $RepoRoot rev-parse --verify $Ref 2>$null)
  if ($LASTEXITCODE -ne 0) { return $null }
  $value = ($output -join '').Trim()
  if ($value -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-a08-ref]' }
  return $value
}

function Get-MIR4A08RemoteRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RemoteName,[Parameter(Mandatory)][string]$Ref)
  if ($Ref -cnotmatch '^refs/heads/[A-Za-z0-9][A-Za-z0-9._/-]{0,180}$') { throw '[mir4-a08-remote-ref]' }
  $output = @(& git -C $RepoRoot ls-remote --refs $RemoteName $Ref 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "[mir4-a08-remote-read] $($output -join ' ')" }
  if ($output.Count -eq 0) { return $null }
  if ($output.Count -ne 1 -or $output[0] -cnotmatch '^([0-9a-f]{40})\s+(.+)$' -or $Matches[2] -cne $Ref) { throw '[mir4-a08-remote-read]' }
  return $Matches[1]
}

function Get-MIR4A08CanonicalJson { param([Parameter(Mandatory)]$Value) return ($Value | ConvertTo-Json -Depth 100 -Compress) }
function Get-MIR4A08Sha256 { param([Parameter(Mandatory)]$Value) return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((Get-MIR4A08CanonicalJson $Value)))) }
function Get-MIR4A08FileSha256 { param([Parameter(Mandatory)][string]$Path) if (-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw '[mir4-a08-file-missing]'};return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }

function Assert-MIR4A08PropertyNames {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Names,[Parameter(Mandatory)][string]$Code)
  $actual=@($Value.PSObject.Properties|ForEach-Object{[string]$_.Name})
  if ($actual.Count-ne$Names.Count-or@($actual|Where-Object{$_-cnotin$Names}).Count-ne0){throw $Code}
}
function Assert-MIR4A08Boolean { param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][bool]$Expected,[Parameter(Mandatory)][string]$Code) if ($Value-isnot[bool]-or[bool]$Value-ne$Expected){throw $Code} }
function Assert-MIR4A08GitSha { param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Code) if ($Value-cnotmatch'^[0-9a-f]{40}$'){throw $Code} }
function Assert-MIR4A08Sha { param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Code) if ($Value-cnotmatch'^[A-F0-9]{64}$'){throw $Code} }
function Get-MIR4A08SelfSha256 {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Property)
  $copy=[ordered]@{};foreach ($item in $Value.PSObject.Properties){$copy[$item.Name]=if ($item.Name-ceq$Property){''}else{$item.Value}};return Get-MIR4A08Sha256([pscustomobject]$copy)
}
function Get-MIR4A08PolicySha256 {
  param([Parameter(Mandatory)]$Observation)
  $copy=[ordered]@{};foreach ($item in $Observation.PSObject.Properties){if ($item.Name-notin@('observed_at','policy_sha256')){$copy[$item.Name]=$item.Value}};return Get-MIR4A08Sha256([pscustomobject]$copy)
}
function Test-MIR4A08CanonicalGitHubRemote { param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Repository) return (($Url.Trim().TrimEnd('/')-replace'\.git$','')-ceq"https://github.com/$Repository") }

function Assert-MIR4A08PolicyObservation {
  param([Parameter(Mandatory)]$Observation,[Parameter(Mandatory)][string]$CanonicalRepository,[switch]$Rehearsal)
  Assert-MIR4A08PropertyNames $Observation @('schema','kind','observation_source','repository','canonical_remote_url','main_ref','observed_at','ruleset','protection','policy_sha256') '[mir4-a08-policy-observation]'
  Assert-MIR4A08PropertyNames $Observation.ruleset @('id','enforcement','pull_request_required','linear_history_required','non_fast_forward_blocked','deletion_blocked','bypass_actor_count','required_status_checks') '[mir4-a08-policy-observation]'
  Assert-MIR4A08PropertyNames $Observation.protection @('observed','squash_merge_enabled') '[mir4-a08-policy-observation]'
  if ([int]$Observation.schema-ne1-or[string]$Observation.kind-cne'MIR42GitHubMainPolicyObservationV1'-or[string]$Observation.repository-cne$CanonicalRepository-or[string]$Observation.main_ref-cne'refs/heads/main'-or[string]$Observation.policy_sha256-cnotmatch'^[A-F0-9]{64}$'-or[string]$Observation.policy_sha256-cne(Get-MIR4A08PolicySha256 $Observation)){throw '[mir4-a08-policy-observation]'}
  if ($Rehearsal){if ([string]$Observation.observation_source-cne'synthetic-github-readonly-v1'-or[string]$Observation.canonical_remote_url-notmatch'^synthetic://'){throw '[mir4-a08-policy-source]'}}elseif([string]$Observation.observation_source-cne'github-rest-v3'-or-not(Test-MIR4A08CanonicalGitHubRemote -Url ([string]$Observation.canonical_remote_url)-Repository $CanonicalRepository)){throw '[mir4-a08-policy-source]'}
  $checks=@($Observation.ruleset.required_status_checks|ForEach-Object{[string]$_}|Sort-Object -CaseSensitive -Unique)
  if ([int]$Observation.ruleset.id-lt1-or[string]$Observation.ruleset.enforcement-cne'active'-or-not[bool]$Observation.ruleset.pull_request_required-or-not[bool]$Observation.ruleset.linear_history_required-or-not[bool]$Observation.ruleset.non_fast_forward_blocked-or-not[bool]$Observation.ruleset.deletion_blocked-or[int]$Observation.ruleset.bypass_actor_count-ne0-or-not[bool]$Observation.protection.observed-or-not[bool]$Observation.protection.squash_merge_enabled-or@('branch-policy','verification-gate'|Where-Object{$_-notin$checks}).Count-ne0){throw '[mir4-a08-policy-incompatible]'}
  return $Observation
}
function Get-MIR4A08PolicyObservation {
  param([Parameter(Mandatory)][string]$CanonicalRepository,[Parameter(Mandatory)][scriptblock]$PolicyProvider,[switch]$Rehearsal)
  try{$observation=&$PolicyProvider $CanonicalRepository 'main'}catch{throw "[mir4-a08-policy-provider] $($_.Exception.Message)"};if ($null-eq$observation){throw '[mir4-a08-policy-provider]'};return Assert-MIR4A08PolicyObservation -Observation $observation -CanonicalRepository $CanonicalRepository -Rehearsal:$Rehearsal
}

function Invoke-MIR4A08GitHubRestJson {
  param(
    [Parameter(Mandatory)][string]$GhExecutable,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$Code
  )
  $lines = @(& $GhExecutable @Arguments 2>&1 | ForEach-Object { [string]$_ })
  if ($LASTEXITCODE -ne 0) { throw "$Code $($lines -join ' ')" }
  try { return (($lines -join "`n") | ConvertFrom-Json -Depth 100 -DateKind String) }
  catch { throw "$Code invalid-json" }
}

function Get-MIR4A08EffectiveRule {
  param([Parameter(Mandatory)][object[]]$Rules,[Parameter(Mandatory)][string]$Type)
  $matches = @($Rules | Where-Object { [string]$_.type -ceq $Type })
  if ($matches.Count -ne 1) { throw "[mir4-a08-policy-rule] $Type" }
  return $matches[0]
}

function New-MIR4A08GitHubRestPolicyProvider {
  [CmdletBinding()]
  param([string]$GhExecutable = 'gh')
  $invokeRest = ${function:Invoke-MIR4A08GitHubRestJson}
  $canonicalRemote = ${function:Test-MIR4A08CanonicalGitHubRemote}
  $effectiveRule = ${function:Get-MIR4A08EffectiveRule}
  $policyHash = ${function:Get-MIR4A08PolicySha256}
  $provider = {
    param([string]$Repository,[string]$Branch)
    if ($Branch -cne 'main') { throw '[mir4-a08-policy-branch]' }
    $repositoryRecord = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository") -Code '[mir4-a08-policy-repository]'
    if ([string]$repositoryRecord.full_name -cne $Repository -or [string]$repositoryRecord.default_branch -cne 'main' -or -not (& $canonicalRemote -Url ([string]$repositoryRecord.clone_url) -Repository $Repository)) { throw '[mir4-a08-policy-repository]' }
    $effective = @(& $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository/rules/branches/main") -Code '[mir4-a08-policy-effective-rules]')
    if ($effective.Count -eq 0) { throw '[mir4-a08-policy-effective-rules]' }
    # The effective branch-rules endpoint exposes the owning ruleset as
    # `ruleset_id`; it does not return the ruleset-detail object's `id` under
    # ruleset_source.  Accept the legacy object shape only as a compatibility
    # fallback, never as a substitute for an observed numeric source id.
    $sourceIds = @($effective | ForEach-Object {
      if ($_.PSObject.Properties.Name -contains 'ruleset_id') { [string]$_.ruleset_id }
      elseif ($null -ne $_.ruleset_source -and $_.ruleset_source.PSObject.Properties.Name -contains 'id') { [string]$_.ruleset_source.id }
    } | Where-Object { $_ -match '^[0-9]+$' } | Sort-Object -Unique)
    if ($sourceIds.Count -ne 1) { throw '[mir4-a08-policy-ruleset-source]' }
    $rulesets = @(
      foreach ($sourceId in $sourceIds) {
        & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository/rulesets/$sourceId") -Code '[mir4-a08-policy-ruleset-detail]'
      }
    )
    if (@($rulesets | Where-Object { [string]$_.enforcement -cne 'active' }).Count -ne 0) { throw '[mir4-a08-policy-incompatible]' }
    $requiredStatuses = @(
      @(foreach ($rule in @($effective | Where-Object { [string]$_.type -ceq 'required_status_checks' })) {
        foreach ($status in @($rule.parameters.required_status_checks)) {
          $name = if ($status -is [string]) { [string]$status } else { [string]$status.context }
          if (-not [string]::IsNullOrWhiteSpace($name)) { $name }
        }
      }) | Sort-Object -Unique
    )
    $null = & $effectiveRule -Rules $effective -Type 'pull_request'
    $null = & $effectiveRule -Rules $effective -Type 'required_linear_history'
    $null = & $effectiveRule -Rules $effective -Type 'non_fast_forward'
    $null = & $effectiveRule -Rules $effective -Type 'deletion'
    if ($requiredStatuses.Count -eq 0) { throw '[mir4-a08-policy-incompatible]' }
    $value = [pscustomobject][ordered]@{
      schema = 1; kind = 'MIR42GitHubMainPolicyObservationV1'; observation_source = 'github-rest-v3'; repository = $Repository
      canonical_remote_url = [string]$repositoryRecord.clone_url; main_ref = 'refs/heads/main'; observed_at = [DateTimeOffset]::UtcNow.ToString('o')
      ruleset = [pscustomobject][ordered]@{
        id = [int64]$sourceIds[0]; enforcement = 'active'; pull_request_required = $true; linear_history_required = $true; non_fast_forward_blocked = $true; deletion_blocked = $true
        bypass_actor_count = [int](@($rulesets | ForEach-Object { @($_.bypass_actors).Count } | Measure-Object -Sum).Sum)
        required_status_checks = $requiredStatuses
      }
      protection = [pscustomobject][ordered]@{ observed = $true; squash_merge_enabled = [bool]$repositoryRecord.allow_squash_merge }
      policy_sha256 = ''
    }
    $value.policy_sha256 = & $policyHash $value
    return $value
  }
  return $provider.GetNewClosure()
}

function New-MIR4A08GitHubRestPullRequestProvider {
  [CmdletBinding()]
  param([Parameter(Mandatory)][scriptblock]$PolicyProvider,[string]$GhExecutable = 'gh')
  $invokeRest = ${function:Invoke-MIR4A08GitHubRestJson}
  $selfHash = ${function:Get-MIR4A08SelfSha256}
  $provider = {
    param([string]$Repository,[string]$CandidateRef,[string]$CandidateCommit,[string]$MainAfter)
    $candidateBranch = $CandidateRef -replace '^refs/heads/', ''
    if ($candidateBranch -eq $CandidateRef) { throw '[mir4-a08-pr-provider]' }
    $owner = ($Repository -split '/', 2)[0]
    $rows = @(& $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository/pulls?state=closed&base=main&head=$owner`:$candidateBranch") -Code '[mir4-a08-pr-query]')
    $matches = @($rows | Where-Object { [bool]$_.merged -and [string]$_.head.sha -ceq $CandidateCommit })
    if ($matches.Count -ne 1) { throw '[mir4-a08-pr-identity]' }
    $pull = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository/pulls/$([int]$matches[0].number)") -Code '[mir4-a08-pr-detail]'
    $mergeCommit = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository/commits/$MainAfter") -Code '[mir4-a08-pr-merge-commit]'
    $checks = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository/commits/$MainAfter/check-runs?per_page=100") -Code '[mir4-a08-pr-checks]'
    $repositoryRecord = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$Repository") -Code '[mir4-a08-pr-repository]'
    $policy = & $PolicyProvider $Repository 'main'
    if ([string]$pull.base.ref -cne 'main' -or [string]::IsNullOrWhiteSpace([string]$pull.base.sha) -or [string]$pull.head.ref -cne $candidateBranch -or [string]$pull.head.sha -cne $CandidateCommit -or [string]$pull.merge_commit_sha -cne $MainAfter -or @($mergeCommit.parents).Count -ne 1 -or -not [bool]$repositoryRecord.allow_squash_merge) { throw '[mir4-a08-pr-identity]' }
    $record = [pscustomobject][ordered]@{
      schema = 1; kind = 'MIR42GitHubPullRequestReadbackV1'; observation_source = 'github-rest-v3'; repository = $Repository; canonical_remote_url = [string]$repositoryRecord.clone_url
      number = [int]$pull.number; state = if ([bool]$pull.merged) { 'MERGED' } else { 'OPEN' }
      base = [pscustomobject][ordered]@{ ref = [string]$pull.base.ref; commit = [string]$pull.base.sha }
      head = [pscustomobject][ordered]@{ ref = [string]$pull.head.ref; commit = [string]$pull.head.sha }
      merge = [pscustomobject][ordered]@{ method = 'squash'; commit = [string]$pull.merge_commit_sha }
      required_checks = @($checks.check_runs | ForEach-Object { [pscustomobject][ordered]@{ context = [string]$_.name; conclusion = [string]$_.conclusion } })
      policy_sha256 = [string]$policy.policy_sha256; direct_ref_update = $false; record_sha256 = ''
    }
    $record.record_sha256 = & $selfHash $record 'record_sha256'
    return $record
  }
  return $provider.GetNewClosure()
}

function New-MIR4A08GitHubRestQualificationAuthorityProvider {
  [CmdletBinding()]
  param([string]$GhExecutable = 'gh')
  $invokeRest = ${function:Invoke-MIR4A08GitHubRestJson}
  $provider = {
    param([object]$Authority,[object]$Candidate)
    $producer = $Authority.producer
    $repository = [string]$producer.repository
    if ($repository -cne 'Julesc013/more-infinite-research' -or [string]$producer.run_id -notmatch '^[0-9]+$') {
      throw '[mir4-a08-qualification-run-identity]'
    }
    $run = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api',"repos/$repository/actions/runs/$([string]$producer.run_id)") -Code '[mir4-a08-qualification-run]'
    $jobs = & $invokeRest -GhExecutable $GhExecutable -Arguments @('api','-X','GET','-f','filter=latest','-f','per_page=100',"repos/$repository/actions/runs/$([string]$producer.run_id)/jobs") -Code '[mir4-a08-qualification-jobs]'
    $matchingJobs = @($jobs.jobs | Where-Object {
      $name = [string]$_.name
      $name -ceq [string]$producer.job -or $name.EndsWith(" / $([string]$producer.job)", [StringComparison]::Ordinal)
    })
    if ([int64]$run.id -ne [int64]$producer.run_id -or [string]$run.name -cne [string]$producer.workflow -or
        [string]$run.event -cne [string]$producer.event -or [string]$run.head_sha -cne [string]$Candidate.commit -or
        [int]$run.run_attempt -ne [int]$producer.run_attempt -or [string]$run.status -cne 'completed' -or
        [string]$run.conclusion -cne 'success' -or [string]$run.actor.login -cne [string]$producer.actor -or
        $matchingJobs.Count -ne 1) {
      throw '[mir4-a08-qualification-run-identity]'
    }
    $job = $matchingJobs[0]
    $labels = @($job.labels | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ([string]$job.status -cne 'completed' -or [string]$job.conclusion -cne 'success' -or
        [string]::IsNullOrWhiteSpace([string]$job.runner_name) -or 'self-hosted' -notin $labels -or 'windows' -notin $labels) {
      throw '[mir4-a08-qualification-job-identity]'
    }
    return [pscustomobject][ordered]@{
      run_id = [string]$run.id
      run_attempt = [string]$run.run_attempt
      workflow = [string]$run.name
      event = [string]$run.event
      actor = [string]$run.actor.login
      commit = [string]$run.head_sha
      job = [string]$job.name
      runner_name = [string]$job.runner_name
      runner_identity = 'self-hosted-windows'
      ref = "refs/heads/$([string]$run.head_branch)"
    }
  }
  return $provider.GetNewClosure()
}

function Get-MIR4A08ProtectedPromotionPreflight {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateRef,
    [string]$GhExecutable = 'gh'
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policyProvider = New-MIR4A08GitHubRestPolicyProvider -GhExecutable $GhExecutable
  $policy = Get-MIR4A08PolicyObservation -CanonicalRepository 'Julesc013/more-infinite-research' -PolicyProvider $policyProvider
  $originUrl = ((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('remote','get-url','origin')) -join '').Trim()
  if (-not (Test-MIR4A08CanonicalGitHubRemote -Url $originUrl -Repository ([string]$policy.repository))) {
    throw '[mir4-a08-remote-identity]'
  }
  $null = Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('fetch','--prune','origin','main','dev')
  $plan = New-MIR4ProtectedPromotionTopologyPlan -RepoRoot $repo -MainRef 'refs/remotes/origin/main' -SourceRef 'refs/remotes/origin/dev' -CandidateRef $CandidateRef -PolicyProvider $policyProvider
  if ([string]$plan.policy.policy_sha256 -cne [string]$policy.policy_sha256 -or
      -not (Test-MIR4A08CanonicalGitHubRemote -Url $originUrl -Repository ([string]$plan.policy.repository))) {
    throw '[mir4-a08-policy-drift-before-candidate]'
  }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42ProtectedMainPromotionPreflightV1'
    status = 'read-only-preflight-passed-candidate-not-created'
    plan = $plan
    candidate_allocation_authorized = $false
    main_mutation_performed = $false
    tag_created = $false
    publication_authorized = $false
  }
}

function Get-MIR4A08PlanSha256 { param([Parameter(Mandatory)]$Plan) return Get-MIR4A08SelfSha256 -Value $Plan -Property 'plan_sha256' }
function Assert-MIR4A08Plan {
  param([Parameter(Mandatory)]$Plan)
  Assert-MIR4A08PropertyNames $Plan @('schema','kind','strategy','policy','main_before','source','reconciliation','candidate','qualification','promotion','readback','tag_creation_authority','main_mutation_authority','release_authority','publication_authority','plan_sha256') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.policy @('repository','canonical_remote_url','main_ref','observation_source','policy_sha256') '[mir4-a08-plan-invalid]';Assert-MIR4A08PropertyNames $Plan.main_before @('ref','commit','tree') '[mir4-a08-plan-invalid]';Assert-MIR4A08PropertyNames $Plan.source @('ref','commit','tree') '[mir4-a08-plan-invalid]';Assert-MIR4A08PropertyNames $Plan.reconciliation @('merge_base','main_unique_commit_count','patch_equivalent_main_commit_count','all_main_changes_integrated') '[mir4-a08-plan-invalid]';Assert-MIR4A08PropertyNames $Plan.candidate @('ref','parent_commit','source_commit','tree','construction','created') '[mir4-a08-plan-invalid]'
  Assert-MIR4A08PropertyNames $Plan.qualification @('expected_targets','exact_candidate_commit_required','exact_candidate_tree_required','exact_package_bytes_required','qualified_materializer_required','exact_package_presentation_required','exact_source_manifest_identity_required','exact_package_authority_identity_required','qualification_before_promotion','independent_governed_evidence_required') '[mir4-a08-plan-invalid]';Assert-MIR4A08PropertyNames $Plan.promotion @('branch','merge_method','pull_request_required','required_status_checks','linear_history_required','ruleset_mutation_authorized','force_push_authorized','deletion_authorized') '[mir4-a08-plan-invalid]';Assert-MIR4A08PropertyNames $Plan.readback @('final_commit_may_differ','exact_tree_required','exact_package_bytes_required','main_base_ancestry_required','source_ref_unchanged_required','fresh_remote_ref_readback_required','direct_main_child_required','commit_message_binding_required','actual_pr_observation_required','commit_rebinding_receipt_required') '[mir4-a08-plan-invalid]'
  if ([int]$Plan.schema-ne1-or[string]$Plan.kind-cne'MIR42ProtectedMainPromotionTopologyPlanV1'-or[string]$Plan.strategy-cne'main-based-tree-transplant-protected-pr'-or[string]$Plan.policy.repository-cne'Julesc013/more-infinite-research'-or[string]$Plan.policy.main_ref-cne'refs/heads/main'-or[string]$Plan.policy.policy_sha256-cnotmatch'^[A-F0-9]{64}$'-or[string]$Plan.main_before.ref-cnotmatch'^refs/'-or[string]$Plan.source.ref-cnotmatch'^refs/'-or[string]$Plan.candidate.ref-cnotmatch'^refs/heads/candidate/[a-z0-9][a-z0-9._-]{2,80}$'-or[string]$Plan.promotion.branch-cne'main'-or[string]$Plan.promotion.merge_method-cne'squash'-or[string]$Plan.candidate.construction-cne'single-parent commit carrying the exact frozen dev tree'){throw '[mir4-a08-plan-invalid]'}
  foreach ($commit in @([string]$Plan.main_before.commit,[string]$Plan.source.commit,[string]$Plan.reconciliation.merge_base,[string]$Plan.candidate.parent_commit,[string]$Plan.candidate.source_commit)){if ($commit-cnotmatch'^[0-9a-f]{40}$'){throw '[mir4-a08-plan-invalid]'}};foreach ($tree in @([string]$Plan.main_before.tree,[string]$Plan.source.tree,[string]$Plan.candidate.tree)){if ($tree-cnotmatch'^[0-9a-f]{40}$'){throw '[mir4-a08-plan-invalid]'}}
  if ((@($Plan.qualification.expected_targets|Sort-Object)-join'|')-cne'F200|F210'-or@($Plan.qualification.expected_targets|Sort-Object -Unique).Count-ne2-or(@($Plan.promotion.required_status_checks|Sort-Object -Unique)-join'|')-cne'branch-policy|verification-gate'){throw '[mir4-a08-plan-invalid]'}
  foreach ($assertion in @(@($Plan.reconciliation.all_main_changes_integrated,$true),@($Plan.candidate.created,$false),@($Plan.qualification.exact_candidate_commit_required,$true),@($Plan.qualification.exact_candidate_tree_required,$true),@($Plan.qualification.exact_package_bytes_required,$true),@($Plan.qualification.qualified_materializer_required,$true),@($Plan.qualification.exact_package_presentation_required,$true),@($Plan.qualification.exact_source_manifest_identity_required,$true),@($Plan.qualification.exact_package_authority_identity_required,$true),@($Plan.qualification.qualification_before_promotion,$true),@($Plan.qualification.independent_governed_evidence_required,$true),@($Plan.promotion.pull_request_required,$true),@($Plan.promotion.linear_history_required,$true),@($Plan.promotion.ruleset_mutation_authorized,$false),@($Plan.promotion.force_push_authorized,$false),@($Plan.promotion.deletion_authorized,$false),@($Plan.readback.final_commit_may_differ,$true),@($Plan.readback.exact_tree_required,$true),@($Plan.readback.exact_package_bytes_required,$true),@($Plan.readback.main_base_ancestry_required,$true),@($Plan.readback.source_ref_unchanged_required,$true),@($Plan.readback.fresh_remote_ref_readback_required,$true),@($Plan.readback.direct_main_child_required,$true),@($Plan.readback.commit_message_binding_required,$true),@($Plan.readback.actual_pr_observation_required,$true),@($Plan.readback.commit_rebinding_receipt_required,$true),@($Plan.tag_creation_authority,$false),@($Plan.main_mutation_authority,$false),@($Plan.release_authority,$false),@($Plan.publication_authority,$false))){Assert-MIR4A08Boolean -Value $assertion[0] -Expected $assertion[1] -Code '[mir4-a08-plan-invalid]'}
  if ([int]$Plan.reconciliation.main_unique_commit_count-lt0-or[int]$Plan.reconciliation.patch_equivalent_main_commit_count-lt0-or[string]$Plan.plan_sha256-cne(Get-MIR4A08PlanSha256 $Plan)){throw '[mir4-a08-plan-invalid]'};return $Plan
}
function Get-MIR4A08CandidateMessage { param([Parameter(Mandatory)]$Plan) return "MIR 4.2 protected candidate`n`nMIR-Source-Commit: $($Plan.source.commit)`nMIR-Source-Tree: $($Plan.source.tree)`nMIR-Main-Base: $($Plan.main_before.commit)`nMIR-Policy-SHA256: $($Plan.policy.policy_sha256)`nMIR-Promotion-Plan: $($Plan.plan_sha256)" }
function Assert-MIR4A08CandidateAgainstPlan {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$CandidateRef,[Parameter(Mandatory)][string]$CandidateCommit)
  if ($CandidateRef-cne[string]$Plan.candidate.ref){throw '[mir4-a08-candidate-ref-conflict]'};$tree=Resolve-MIR4A08Tree -RepoRoot $RepoRoot -Commit $CandidateCommit;$parents=@(((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('show','-s','--format=%P',$CandidateCommit))-join'').Trim()-split'\s+'|Where-Object{$_});$message=((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('show','-s','--format=%B',$CandidateCommit))-join"`n").TrimEnd();if ($tree-cne[string]$Plan.source.tree-or$parents.Count-ne1-or$parents[0]-cne[string]$Plan.main_before.commit-or$message-cne(Get-MIR4A08CandidateMessage $Plan)){throw '[mir4-a08-candidate-ref-conflict]'};return [pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainCandidateV1';ref=$CandidateRef;commit=$CandidateCommit;tree=$tree;parent_commit=$parents[0];source_commit=[string]$Plan.source.commit;plan_sha256=[string]$Plan.plan_sha256;candidate_message_sha256=Get-MIR4A08Sha256 $message}
}

function New-MIR4ProtectedPromotionTopologyPlan {
  [CmdletBinding()]param([Parameter(Mandatory)][string]$RepoRoot,[string]$MainRef='refs/remotes/origin/main',[string]$SourceRef='refs/remotes/origin/dev',[Parameter(Mandatory)][string]$CandidateRef,[Parameter(Mandatory)][scriptblock]$PolicyProvider,[string]$CanonicalRepository='Julesc013/more-infinite-research',[switch]$Rehearsal)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$expectedMainRef=if($Rehearsal){'refs/heads/main'}else{'refs/remotes/origin/main'};$expectedSourceRef=if($Rehearsal){'refs/heads/dev'}else{'refs/remotes/origin/dev'};if($MainRef-cne$expectedMainRef-or$SourceRef-cne$expectedSourceRef){throw '[mir4-a08-source-ref-authority]'};if ($CandidateRef-cnotmatch'^refs/heads/candidate/[a-z0-9][a-z0-9._-]{2,80}$'){throw '[mir4-a08-candidate-ref]'};$policy=Get-MIR4A08PolicyObservation -CanonicalRepository $CanonicalRepository -PolicyProvider $PolicyProvider -Rehearsal:$Rehearsal;$mainCommit=Resolve-MIR4A08Commit -RepoRoot $repo -Revision $MainRef;$sourceCommit=Resolve-MIR4A08Commit -RepoRoot $repo -Revision $SourceRef;$sourceTree=Resolve-MIR4A08Tree -RepoRoot $repo -Commit $sourceCommit;$mainTree=Resolve-MIR4A08Tree -RepoRoot $repo -Commit $mainCommit;$mergeBase=((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('merge-base',$mainCommit,$sourceCommit))-join'').Trim();$cherry=@(Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('cherry',$sourceCommit,$mainCommit));if (@($cherry|Where-Object{$_-match'^\+\s+[0-9a-f]{40}$'}).Count-ne0){throw '[mir4-a08-main-change-not-integrated]'};$mainUniqueCount=[int](((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('rev-list','--count',"$mergeBase..$mainCommit"))-join'').Trim());if ($cherry.Count-ne$mainUniqueCount){throw '[mir4-a08-main-history-not-linear-patch-set]'}
  $plan=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainPromotionTopologyPlanV1';strategy='main-based-tree-transplant-protected-pr';policy=[pscustomobject][ordered]@{repository=$CanonicalRepository;canonical_remote_url=[string]$policy.canonical_remote_url;main_ref='refs/heads/main';observation_source=[string]$policy.observation_source;policy_sha256=[string]$policy.policy_sha256};main_before=[pscustomobject][ordered]@{ref=$MainRef;commit=$mainCommit;tree=$mainTree};source=[pscustomobject][ordered]@{ref=$SourceRef;commit=$sourceCommit;tree=$sourceTree};reconciliation=[pscustomobject][ordered]@{merge_base=$mergeBase;main_unique_commit_count=$mainUniqueCount;patch_equivalent_main_commit_count=@($cherry|Where-Object{$_-match'^-\s+[0-9a-f]{40}$'}).Count;all_main_changes_integrated=$true};candidate=[pscustomobject][ordered]@{ref=$CandidateRef;parent_commit=$mainCommit;source_commit=$sourceCommit;tree=$sourceTree;construction='single-parent commit carrying the exact frozen dev tree';created=$false};qualification=[pscustomobject][ordered]@{expected_targets=@('F200','F210');exact_candidate_commit_required=$true;exact_candidate_tree_required=$true;exact_package_bytes_required=$true;qualified_materializer_required=$true;exact_package_presentation_required=$true;exact_source_manifest_identity_required=$true;exact_package_authority_identity_required=$true;qualification_before_promotion=$true;independent_governed_evidence_required=$true};promotion=[pscustomobject][ordered]@{branch='main';merge_method='squash';pull_request_required=$true;required_status_checks=@('branch-policy','verification-gate');linear_history_required=$true;ruleset_mutation_authorized=$false;force_push_authorized=$false;deletion_authorized=$false};readback=[pscustomobject][ordered]@{final_commit_may_differ=$true;exact_tree_required=$true;exact_package_bytes_required=$true;main_base_ancestry_required=$true;source_ref_unchanged_required=$true;fresh_remote_ref_readback_required=$true;direct_main_child_required=$true;commit_message_binding_required=$true;actual_pr_observation_required=$true;commit_rebinding_receipt_required=$true};tag_creation_authority=$false;main_mutation_authority=$false;release_authority=$false;publication_authority=$false;plan_sha256=''};$plan.plan_sha256=Get-MIR4A08PlanSha256 $plan;return Assert-MIR4A08Plan $plan
}
function New-MIR4ProtectedMainCandidate {
  [CmdletBinding()]param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan,[switch]$Rehearsal)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$null=Assert-MIR4A08Plan $Plan;if ((Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.main_before.ref))-cne[string]$Plan.main_before.commit){throw '[mir4-a08-main-ref-drift]'};if ((Resolve-MIR4A08Commit -RepoRoot $repo -Revision ([string]$Plan.source.ref))-cne[string]$Plan.source.commit){throw '[mir4-a08-source-ref-drift]'};$candidateRef=[string]$Plan.candidate.ref;$candidateCommit=Get-MIR4A08OptionalRef -RepoRoot $repo -Ref $candidateRef;$created=$false;if ($null-eq$candidateCommit){if(-not$Rehearsal){throw '[mir4-a08-external-effect-not-authorized]'};$candidateCommit=((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('commit-tree',[string]$Plan.source.tree,'-p',[string]$Plan.main_before.commit,'-m',(Get-MIR4A08CandidateMessage $Plan)))-join'').Trim();if ($candidateCommit-cnotmatch'^[0-9a-f]{40}$'){throw '[mir4-a08-candidate-commit]'};$null=Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('update-ref',$candidateRef,$candidateCommit,('0'*40));$created=$true};$candidate=Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $Plan -CandidateRef $candidateRef -CandidateCommit $candidateCommit;$candidate|Add-Member created $created;$candidate|Add-Member remote_push_performed $false;$candidate|Add-Member main_mutation_performed $false;$candidate|Add-Member tag_created $false;$candidate|Add-Member publication_authorized $false;return $candidate
}

function Assert-MIR4A08QualifiedEngine {
  param([Parameter(Mandatory)]$Worker,[Parameter(Mandatory)]$Independent,[Parameter(Mandatory)][string]$Target,[switch]$Rehearsal)
  if([string]$Worker.engine.sha256-cne[string]$Independent.engine_sha256){throw '[mir4-a08-qualification-engine]'}
  if($Rehearsal){
    $expectedLine=if($Target-ceq'F210'){'2.1'}else{'2.0'}
    if([string]$Worker.engine.version-cne$expectedLine-or[string]$Worker.engine.path-cne'synthetic'){throw '[mir4-a08-qualification-engine]'}
    return
  }
  $expectedPath=if($Target-ceq'F210'){'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'}else{'D:\Programs\Factorio\2.0\bin\x64\factorio.exe'}
  $claimedPath=[IO.Path]::GetFullPath([string]$Worker.engine.path)
  if(-not$claimedPath.Equals([IO.Path]::GetFullPath($expectedPath),[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $claimedPath -PathType Leaf)-or(Get-MIR4A08FileSha256 $claimedPath)-cne[string]$Worker.engine.sha256){throw '[mir4-a08-qualification-engine]'}
  $installed=([Diagnostics.FileVersionInfo]::GetVersionInfo($claimedPath).ProductVersion-replace'[^0-9.].*$','').TrimEnd('.')
  if($installed-cnotmatch'^\d+[.]\d+[.]\d+$'-or[string]$Worker.engine.version-cne$installed){throw '[mir4-a08-qualification-engine]'}
  if($Target-ceq'F210'){
    if([version]$installed-lt[version]'2.1.18'){throw '[mir4-a08-qualification-engine]'}
  }elseif($installed-cne'2.0.77'){throw '[mir4-a08-qualification-engine]'}
}

function Resolve-MIR4A08ContainedFile {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  $rootPath=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path).TrimEnd('\','/');if ([IO.Path]::IsPathRooted($RelativePath)-or$RelativePath-match'(^|[\\/])\.\.([\\/]|$)'){throw $Code};$candidate=[IO.Path]::GetFullPath((Join-Path $rootPath $RelativePath));$prefix=$rootPath+[IO.Path]::DirectorySeparatorChar;if (-not$candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $candidate -PathType Leaf)){throw $Code};$current=$rootPath;foreach ($segment in($RelativePath-split'[\\/]')){$current=Join-Path $current $segment;if (((Get-Item -LiteralPath $current -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw $Code}};return $candidate
}
function Get-MIR4A08ExpectedFactorioVersion {
  param([Parameter(Mandatory)][string]$Target)
  switch ($Target) {
    'F200' { return '2.0' }
    'F210' { return '2.1' }
    default { throw '[mir4-a08-package-target]' }
  }
}
function Get-MIR4A08PackageObservation {
  param([Parameter(Mandatory)][string]$PackagePath,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$RelativePath)
  try{$archive=[IO.Compression.ZipFile]::OpenRead($PackagePath)}catch{throw '[mir4-a08-package-archive]'};try{$entries=@($archive.Entries|Where-Object{-not[string]::IsNullOrEmpty($_.Name)}|Sort-Object -Property FullName -CaseSensitive);$roots=@($entries|ForEach-Object{([string]$_.FullName).Split('/')[0]}|Sort-Object -Unique);if ($entries.Count-eq0-or$roots.Count-ne1-or@($entries.FullName|Sort-Object -Unique).Count-ne$entries.Count){throw '[mir4-a08-package-archive]'};$info=@($entries|Where-Object{[string]$_.FullName-ceq"$($roots[0])/info.json"});if ($info.Count-ne1){throw '[mir4-a08-package-target-identity]'};try{$reader=[IO.StreamReader]::new($info[0].Open(),[Text.UTF8Encoding]::new($false),$true);try{$metadata=$reader.ReadToEnd()|ConvertFrom-Json -Depth 30 -DateKind String}finally{$reader.Dispose()}}catch{throw '[mir4-a08-package-target-identity]'};$expectedVersion=Get-MIR4A08ExpectedFactorioVersion $Target;if ([string]$metadata.factorio_version-cne$expectedVersion-or[string]::IsNullOrWhiteSpace([string]$metadata.name)){throw '[mir4-a08-package-target-identity]'};$content=[Text.StringBuilder]::new();foreach ($entry in $entries){$stream=$entry.Open();$hash=[Security.Cryptography.SHA256]::Create();try{$entrySha=[Convert]::ToHexString($hash.ComputeHash($stream))}finally{$hash.Dispose();$stream.Dispose()};[void]$content.Append($entry.FullName).Append([char]0).Append([string]$entry.Length).Append([char]0).Append($entrySha).Append("`n")};$contentSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content.ToString())));return [pscustomobject][ordered]@{target=$Target;relative_path=$RelativePath;archive_sha256=(Get-MIR4A08FileSha256 $PackagePath);content_sha256=$contentSha;bytes=[long](Get-Item -LiteralPath $PackagePath).Length;entry_count=$entries.Count;root=[string]$roots[0];factorio_version=[string]$metadata.factorio_version}}finally{$archive.Dispose()}
}
function Get-MIR4A08PackageSetSha256 {
  param([Parameter(Mandatory)][object[]]$Packages)
  $normalized=@(foreach ($package in @($Packages|Sort-Object{[string]$_.target})){[pscustomobject][ordered]@{target=[string]$package.target;archive_sha256=[string]$package.archive_sha256;content_sha256=[string]$package.content_sha256;bytes=[long]$package.bytes;entry_count=[int]$package.entry_count;root=[string]$package.root;factorio_version=[string]$package.factorio_version}});if ($normalized.Count-ne2-or(@($normalized.target|Sort-Object)-join'|')-cne'F200|F210'){throw '[mir4-a08-package-set]'};foreach ($package in $normalized){Assert-MIR4A08Sha $package.archive_sha256 '[mir4-a08-package-set]';Assert-MIR4A08Sha $package.content_sha256 '[mir4-a08-package-set]';if ($package.bytes-lt1-or$package.entry_count-lt1){throw '[mir4-a08-package-set]'}};return Get-MIR4A08Sha256 $normalized
}

function Assert-MIR4A08PresentationBinding {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Binding)
  Assert-MIR4A08PropertyNames $Binding @('path','kind','git_blob','record_sha256','package_source_fingerprint_sha256','source_manifest','package_authority') '[mir4-a08-package-presentation]'
  Assert-MIR4A08PropertyNames $Binding.source_manifest @('path','kind','git_blob','record_sha256') '[mir4-a08-package-presentation]'
  Assert-MIR4A08PropertyNames $Binding.package_authority @('path','kind','git_blob','record_sha256') '[mir4-a08-package-presentation]'
  if ([string]$Binding.path-cne'spec/distribution/mir4-current-package-presentation-v6.json'-or
      [string]$Binding.kind-cne'MIR4CurrentPackagePresentationV6'-or
      [string]$Binding.source_manifest.path-cne'source/package-source.json'-or
      [string]$Binding.source_manifest.kind-cne'MIR4ComposablePackageSourceV2'-or
      [string]$Binding.package_authority.path-cne'targets/package-authority.json'-or
      [string]$Binding.package_authority.kind-cne'MIR4CanonicalPackageAuthorityV2') {
    throw '[mir4-a08-package-presentation]'
  }
  Assert-MIR4A08GitSha ([string]$Binding.git_blob) '[mir4-a08-package-presentation]'
  Assert-MIR4A08Sha ([string]$Binding.record_sha256) '[mir4-a08-package-presentation]'
  Assert-MIR4A08Sha ([string]$Binding.package_source_fingerprint_sha256) '[mir4-a08-package-presentation]'
  foreach ($identity in @($Binding.source_manifest,$Binding.package_authority)) {
    Assert-MIR4A08GitSha ([string]$identity.git_blob) '[mir4-a08-package-presentation]'
    Assert-MIR4A08Sha ([string]$identity.record_sha256) '[mir4-a08-package-presentation]'
  }
  $presentation=Read-MIR4A08CommitJson -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$Binding.path) -Code '[mir4-a08-package-presentation]'
  $manifest=Read-MIR4A08CommitJson -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$Binding.source_manifest.path) -Code '[mir4-a08-package-presentation]'
  $authority=Read-MIR4A08CommitJson -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$Binding.package_authority.path) -Code '[mir4-a08-package-presentation]'
  $candidatePackageSourceFingerprint=Get-MIR4A08CommitPackageSourceFingerprint -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit)
  if ((Resolve-MIR4A08Blob -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$Binding.path))-cne[string]$Binding.git_blob-or
      [string]$presentation.kind-cne[string]$Binding.kind-or
      [string]$presentation.record_sha256-cne[string]$Binding.record_sha256-or
      [string]$presentation.record_sha256-cne(Get-MIR4A08SelfSha256 $presentation 'record_sha256')-or
      [string]$presentation.package_source.fingerprint_sha256-cne[string]$Binding.package_source_fingerprint_sha256-or
      [string]$presentation.package_source.fingerprint_sha256-cne[string]$candidatePackageSourceFingerprint-or
      [string]$presentation.package_source.sole_writer-cne'tools/mir/application/package/TargetMaterializer.ps1'-or
      [string]$presentation.package_source.materializer_abi-cne'mir4-target-materializer/1'-or
      (@($presentation.package_source.roots)-join'|')-cne'source|targets'-or
      -not[bool]$presentation.authority_invariants.current_package_contract_bound-or
      [bool]$presentation.authority_invariants.promotion_authorized-or
      [bool]$presentation.transition_gate.main_promotion) {
    throw '[mir4-a08-package-presentation]'
  }
  $expectedCompositions=[ordered]@{f210='targets/f210/composition.json';f200='targets/f200/composition.json';f110='targets/f110/composition.json';f100='targets/f100/composition.json'}
  if (@($presentation.target_compositions).Count-ne4) { throw '[mir4-a08-package-presentation]' }
  foreach ($target in $expectedCompositions.Keys) {
    $compositionBinding=@($presentation.target_compositions|Where-Object{[string]$_.target-ceq$target})
    if ($compositionBinding.Count-ne1-or[string]$compositionBinding[0].path-cne[string]$expectedCompositions[$target]) { throw '[mir4-a08-package-presentation]' }
    Assert-MIR4A08Sha ([string]$compositionBinding[0].record_sha256) '[mir4-a08-package-presentation]'
    $composition=Read-MIR4A08CommitJson -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$compositionBinding[0].path) -Code '[mir4-a08-package-presentation]'
    if ([string]$composition.record_sha256-cne[string]$compositionBinding[0].record_sha256-or[string]$composition.record_sha256-cne(Get-MIR4A08SelfSha256 $composition 'record_sha256')) { throw '[mir4-a08-package-presentation]' }
  }
  foreach ($identity in @(@($Binding.source_manifest,$manifest,[string]$presentation.source_manifest.record_sha256),@($Binding.package_authority,$authority,[string]$presentation.package_authority.record_sha256))) {
    $bound=$identity[0];$record=$identity[1];$presentationHash=[string]$identity[2]
    if ((Resolve-MIR4A08Blob -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$bound.path))-cne[string]$bound.git_blob-or
        [string]$record.kind-cne[string]$bound.kind-or
        [string]$record.record_sha256-cne[string]$bound.record_sha256-or
        [string]$record.record_sha256-cne(Get-MIR4A08SelfSha256 $record 'record_sha256')-or
        $presentationHash-cne[string]$bound.record_sha256) {
      throw '[mir4-a08-package-presentation]'
    }
  }
  return $Binding
}

function Assert-MIR4A08TrustedIssuer {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$CanonicalRepository,[scriptblock]$QualificationAuthorityProvider=$null,[switch]$Rehearsal)
  Assert-MIR4A08PropertyNames $Authority @('kind','issuer_id','trust_policy','producer') '[mir4-a08-qualification-authority]';Assert-MIR4A08PropertyNames $Authority.producer @('repository','workflow','run_id','run_attempt','job','actor','commit','ref','event','environment','runner_identity','trust_class','verifier_sha256','policy_sha256') '[mir4-a08-qualification-authority]';$producer=$Authority.producer
  if ([string]$Authority.kind-cne'MIR4GovernedIndependentQualificationAuthorityV1'-or[string]::IsNullOrWhiteSpace([string]$Authority.issuer_id)-or[string]$Authority.trust_policy-cne'validation/trust.json'-or[string]$producer.repository-cne$CanonicalRepository-or[string]$producer.commit-cne[string]$Candidate.commit-or[string]$producer.job-cne[string]$Authority.issuer_id-or[string]$producer.verifier_sha256-cnotmatch'^[A-F0-9]{64}$'-or[string]$producer.policy_sha256-cnotmatch'^[A-F0-9]{64}$'){throw '[mir4-a08-qualification-authority]'}
  if ($Rehearsal){if ([string]$producer.trust_class-cne'synthetic-protected-release'-or[string]$producer.workflow-cne'synthetic-independent-verification'-or[string]$producer.event-cne'synthetic-merge'){throw '[mir4-a08-qualification-authority]'}}else{$trustPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../validation/trust.json'));$trust=Get-Content -Raw -LiteralPath $trustPath|ConvertFrom-Json -Depth 30;$class=$trust.classes.'protected-release';if ([string]$producer.trust_class-cne'protected-release'-or$null-eq$class-or-not[bool]$class.release_eligible-or[string]$producer.workflow-notin@($class.workflows)-or[string]$producer.event-notin@($class.events)-or[string]$producer.ref-notin@($class.refs)-or[string]$producer.environment-cne[string]$class.environment-or[string]$producer.runner_identity-cne[string]$class.runner_identity-or[string]$producer.policy_sha256-cne(Get-MIR4A08FileSha256 $trustPath)){throw '[mir4-a08-qualification-authority]'};if($null-eq$QualificationAuthorityProvider){$QualificationAuthorityProvider=New-MIR4A08GitHubRestQualificationAuthorityProvider};try{$observed=&$QualificationAuthorityProvider $Authority $Candidate}catch{throw "[mir4-a08-qualification-authority-provider] $($_.Exception.Message)"};Assert-MIR4A08PropertyNames $observed @('run_id','run_attempt','workflow','event','actor','commit','job','runner_name','runner_identity','ref') '[mir4-a08-qualification-authority-provider]';if([string]$observed.run_id-cne[string]$producer.run_id-or[string]$observed.run_attempt-cne[string]$producer.run_attempt-or[string]$observed.workflow-cne[string]$producer.workflow-or[string]$observed.event-cne[string]$producer.event-or[string]$observed.actor-cne[string]$producer.actor-or[string]$observed.commit-cne[string]$producer.commit-or[string]$observed.runner_identity-cne[string]$producer.runner_identity-or[string]$observed.ref-cne[string]$producer.ref-or-not(([string]$observed.job-ceq[string]$producer.job)-or([string]$observed.job).EndsWith(" / $([string]$producer.job)",[StringComparison]::Ordinal))){throw '[mir4-a08-qualification-authority-provider]'}};return $Authority
}
function Assert-MIR4A08QualificationReceipts {
  param([Parameter(Mandatory)]$Row,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Observed,[switch]$Rehearsal)
  Assert-MIR4A08PropertyNames $Row.worker_receipt @('schema','kind','producer_id','source_commit','source_tree','release_plan_digest','target','distribution_version','package','engine','evidence_sha256','status','release_identity','publication_authorized','record_sha256') '[mir4-a08-qualification-record]';Assert-MIR4A08PropertyNames $Row.worker_receipt.package @('sha256','content_sha256','bytes','entry_count') '[mir4-a08-qualification-record]';Assert-MIR4A08PropertyNames $Row.worker_receipt.engine @('version','path','sha256') '[mir4-a08-qualification-record]';Assert-MIR4A08PropertyNames $Row.independent_receipt @('schema','kind','producer_id','independent','source_commit','source_tree','release_plan_digest','target','distribution_version','package_sha256','engine_sha256','evidence_sha256','status','release_identity','publication_authorized','record_sha256') '[mir4-a08-qualification-record]';$worker=$Row.worker_receipt;$independent=$Row.independent_receipt
  if ([int]$worker.schema-ne1-or[string]$worker.kind-cne'MIR4TargetQualificationWorkerReceiptV1'-or[string]$worker.status-cne'passed'-or[string]$worker.record_sha256-cne(Get-MIR4A08SelfSha256 $worker 'record_sha256')-or[string]$worker.source_commit-cne[string]$Candidate.commit-or[string]$worker.source_tree-cne[string]$Candidate.tree-or[string]$worker.target-cne[string]$Row.target-or[string]$worker.distribution_version-cne[string]$Row.distribution_version-or[string]$worker.package.sha256-cne[string]$Observed.archive_sha256-or[string]$worker.package.content_sha256-cne[string]$Observed.content_sha256-or[long]$worker.package.bytes-ne[long]$Observed.bytes-or[int]$worker.package.entry_count-ne[int]$Observed.entry_count-or[string]::IsNullOrWhiteSpace([string]$worker.engine.version)-or[string]::IsNullOrWhiteSpace([string]$worker.engine.path)-or[string]$worker.engine.sha256-cnotmatch'^[A-F0-9]{64}$'-or[string]$worker.release_plan_digest-cnotmatch'^[A-F0-9]{64}$'-or[string]$worker.evidence_sha256-cnotmatch'^[A-F0-9]{64}$'-or[bool]$worker.release_identity-or[bool]$worker.publication_authorized){throw '[mir4-a08-qualification-record]'}
  if ([int]$independent.schema-ne1-or[string]$independent.kind-cne'MIR4IndependentVerificationReceiptV1'-or[string]$independent.status-cne'passed'-or-not[bool]$independent.independent-or[string]$independent.record_sha256-cne(Get-MIR4A08SelfSha256 $independent 'record_sha256')-or[string]$independent.source_commit-cne[string]$Candidate.commit-or[string]$independent.source_tree-cne[string]$Candidate.tree-or[string]$independent.target-cne[string]$Row.target-or[string]$independent.distribution_version-cne[string]$Row.distribution_version-or[string]$independent.package_sha256-cne[string]$Observed.archive_sha256-or[string]$independent.release_plan_digest-cne[string]$worker.release_plan_digest-or[string]$independent.producer_id-cne[string]$Authority.issuer_id-or[string]$worker.producer_id-ceq[string]$Authority.issuer_id-or[string]$independent.evidence_sha256-cnotmatch'^[A-F0-9]{64}$'-or[string]$independent.engine_sha256-cnotmatch'^[A-F0-9]{64}$'-or[string]$independent.engine_sha256-cne[string]$worker.engine.sha256-or[bool]$independent.release_identity-or[bool]$independent.publication_authorized){throw '[mir4-a08-qualification-record]'}
  Assert-MIR4A08QualifiedEngine -Worker $worker -Independent $independent -Target ([string]$Row.target) -Rehearsal:$Rehearsal
}
function Read-MIR4A08QualificationRecord {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$RecordPath,[Parameter(Mandatory)][string]$PackageRoot,[scriptblock]$QualificationAuthorityProvider=$null,[switch]$Rehearsal)
  $recordFullPath=(Resolve-Path -LiteralPath $RecordPath).Path
  try {
    $record=Get-Content -Raw -LiteralPath $recordFullPath|ConvertFrom-Json -Depth 100 -DateKind String
  } catch {
    throw '[mir4-a08-qualification-record]'
  }
  Assert-MIR4A08PropertyNames $record @('schema','kind','status','candidate','materializer','package_presentation','authority','expected_targets','targets','release_authority','publication_authority','record_sha256') '[mir4-a08-qualification-record]'
  Assert-MIR4A08PropertyNames $record.candidate @('ref','commit','tree') '[mir4-a08-qualification-record]'
  Assert-MIR4A08PropertyNames $record.materializer @('path','git_blob') '[mir4-a08-qualification-record]'
  if ([int]$record.schema-ne1-or[string]$record.kind-cne'MIR42ProtectedMainQualificationBindingV3'-or
      [string]$record.status-cne'independently-qualified'-or
      [string]$record.record_sha256-cne(Get-MIR4A08SelfSha256 $record 'record_sha256')-or
      [string]$record.candidate.ref-cne[string]$Candidate.ref-or
      [string]$record.candidate.commit-cne[string]$Candidate.commit-or
      [string]$record.candidate.tree-cne[string]$Candidate.tree-or
      [string]$record.materializer.path-cne'tools/mir/application/package/TargetMaterializer.ps1'-or
      [string]$record.materializer.git_blob-cne(Resolve-MIR4A08Blob -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$record.materializer.path))-or
      (@($record.expected_targets|Sort-Object)-join'|')-cne'F200|F210'-or
      [bool]$record.release_authority-or[bool]$record.publication_authority) {
    throw '[mir4-a08-qualification-record]'
  }
  $presentationBinding=Assert-MIR4A08PresentationBinding -RepoRoot $RepoRoot -Candidate $Candidate -Binding $record.package_presentation
  $presentation=Read-MIR4A08CommitJson -RepoRoot $RepoRoot -Commit ([string]$Candidate.commit) -Path ([string]$presentationBinding.path) -Code '[mir4-a08-package-presentation]'
  $authority=Assert-MIR4A08TrustedIssuer -Authority $record.authority -Candidate $Candidate -CanonicalRepository ([string]$Plan.policy.repository) -QualificationAuthorityProvider $QualificationAuthorityProvider -Rehearsal:$Rehearsal
  $observed=@()
  if (@($record.targets).Count-ne2) { throw '[mir4-a08-qualification-record]' }
  foreach ($row in @($record.targets)) {
    Assert-MIR4A08PropertyNames $row @('target','distribution_version','relative_path','archive_sha256','content_sha256','bytes','entry_count','root','factorio_version','worker_receipt','independent_receipt') '[mir4-a08-qualification-record]'
    if ([string]$row.target-notin@($Plan.qualification.expected_targets)-or[string]$row.distribution_version-eq'') { throw '[mir4-a08-qualification-record]' }
    $path=Resolve-MIR4A08ContainedFile -Root $PackageRoot -RelativePath ([string]$row.relative_path) -Code '[mir4-a08-qualification-record]'
    $actual=Get-MIR4A08PackageObservation -PackagePath $path -Target ([string]$row.target) -RelativePath ([string]$row.relative_path)
    foreach ($field in @('archive_sha256','content_sha256','bytes','entry_count','root','factorio_version')) {
      if ([string]$actual.$field-cne[string]$row.$field) { throw '[mir4-a08-qualified-package-mismatch]' }
    }
    $targetIdentity=@($presentation.target_content_identities|Where-Object{[string]$_.target-ceq([string]$row.target).ToLowerInvariant()})
    if ($targetIdentity.Count-ne1-or[string]$targetIdentity[0].content_sha256-cne[string]$actual.content_sha256-or[int]$targetIdentity[0].entry_count-ne[int]$actual.entry_count) {
      throw '[mir4-a08-package-presentation-target-mismatch]'
    }
    Assert-MIR4A08QualificationReceipts -Row $row -Candidate $Candidate -Authority $authority -Observed $actual -Rehearsal:$Rehearsal
    $observed+=$actual
  }
  $setSha=Get-MIR4A08PackageSetSha256 $observed
  return [pscustomobject][ordered]@{
    record_path=$recordFullPath
    record_sha256=(Get-MIR4A08FileSha256 $recordFullPath)
    record_binding_sha256=[string]$record.record_sha256
    package_root=([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackageRoot).Path))
    candidate=[pscustomobject][ordered]@{ref=[string]$Candidate.ref;commit=[string]$Candidate.commit;tree=[string]$Candidate.tree}
    materializer=$record.materializer
    package_presentation=$presentationBinding
    authority=$authority
    package_set_sha256=$setSha
    packages=@($observed|Sort-Object target)
  }
}

function Write-MIR4A08ImmutableJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Code)
  $text=(Get-MIR4A08CanonicalJson $Value)+"`n";[IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null;if (Test-Path -LiteralPath $Path){if ((Get-Content -Raw -LiteralPath $Path)-cne$text){throw $Code};return $Path};try{$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$bytes=[Text.Encoding]::UTF8.GetBytes($text);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}catch [IO.IOException]{if (-not(Test-Path -LiteralPath $Path)-or(Get-Content -Raw -LiteralPath $Path)-cne$text){throw $Code}};return $Path
}
function Assert-MIR4A08ConfiguredRemote {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RemoteName,[Parameter(Mandatory)]$Plan,[switch]$Rehearsal)
  if ($RemoteName-cnotmatch'^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$'){throw '[mir4-a08-remote-identity]'};$url=((Invoke-MIR4A08Git -RepoRoot $RepoRoot -Arguments @('remote','get-url',$RemoteName))-join'').Trim();if (-not$Rehearsal-and-not(Test-MIR4A08CanonicalGitHubRemote -Url $url -Repository ([string]$Plan.policy.repository))){throw '[mir4-a08-remote-identity]'};return $url
}
function Read-MIR4A08Intention {
  param([Parameter(Mandatory)][string]$Path)
  try{$value=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100 -DateKind String}catch{throw '[mir4-a08-intention-invalid]'};Assert-MIR4A08PropertyNames $value @('schema','kind','rehearsal','plan','candidate','qualification','remote','intention_sha256') '[mir4-a08-intention-invalid]';Assert-MIR4A08PropertyNames $value.remote @('name','canonical_remote_url','main_ref','source_ref','candidate_ref') '[mir4-a08-intention-invalid]';if ([int]$value.schema-ne1-or[string]$value.kind-cne'MIR42ProtectedMainPromotionIntentionV3'-or$value.rehearsal-isnot[bool]-or[string]$value.intention_sha256-cne(Get-MIR4A08SelfSha256 $value 'intention_sha256')){throw '[mir4-a08-intention-invalid]'};$null=Assert-MIR4A08Plan $value.plan;if ([string]$value.remote.canonical_remote_url-cne[string]$value.plan.policy.canonical_remote_url-or[string]$value.remote.candidate_ref-cne[string]$value.plan.candidate.ref-or[string]$value.remote.main_ref-cne'refs/heads/main'-or[string]$value.remote.source_ref-cnotmatch'^refs/heads/'){throw '[mir4-a08-intention-invalid]'};return $value
}
function New-MIR4A08PromotionIntention {
  [CmdletBinding()]param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$QualificationRecordPath,[Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$RemoteName,[Parameter(Mandatory)][string]$RemoteSourceRef,[Parameter(Mandatory)][string]$StateRoot,[switch]$Rehearsal)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;if($RemoteSourceRef-cne'refs/heads/dev'){throw '[mir4-a08-source-ref-authority]'};$null=Assert-MIR4A08Plan $Plan;$localCandidate=Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $Plan -CandidateRef ([string]$Candidate.ref) -CandidateCommit ([string]$Candidate.commit);if ([string]$Candidate.tree-cne[string]$localCandidate.tree-or[string]$Candidate.parent_commit-cne[string]$localCandidate.parent_commit){throw '[mir4-a08-candidate-caller-forged]'};$null=Assert-MIR4A08ConfiguredRemote -RepoRoot $repo -RemoteName $RemoteName -Plan $Plan -Rehearsal:$Rehearsal;if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName $RemoteName -Ref 'refs/heads/main')-cne[string]$Plan.main_before.commit){throw '[mir4-a08-remote-main-ref-drift]'};if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName $RemoteName -Ref $RemoteSourceRef)-cne[string]$Plan.source.commit){throw '[mir4-a08-remote-source-ref-drift]'};$qualification=Read-MIR4A08QualificationRecord -RepoRoot $repo -Plan $Plan -Candidate $localCandidate -RecordPath $QualificationRecordPath -PackageRoot $PackageRoot -Rehearsal:$Rehearsal;$intention=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainPromotionIntentionV3';rehearsal=[bool]$Rehearsal;plan=$Plan;candidate=$localCandidate;qualification=$qualification;remote=[pscustomobject][ordered]@{name=$RemoteName;canonical_remote_url=[string]$Plan.policy.canonical_remote_url;main_ref='refs/heads/main';source_ref=$RemoteSourceRef;candidate_ref=[string]$localCandidate.ref};intention_sha256=''};$intention.intention_sha256=Get-MIR4A08SelfSha256 $intention 'intention_sha256';$path=Join-Path ([IO.Path]::GetFullPath($StateRoot))("$($intention.intention_sha256.ToLowerInvariant()).promotion-intention.json");$null=Write-MIR4A08ImmutableJson -Path $path -Value $intention -Code '[mir4-a08-intention-conflict]';return [pscustomobject][ordered]@{path=$path;intention_sha256=$intention.intention_sha256;candidate_commit=$localCandidate.commit;package_set_sha256=$qualification.package_set_sha256;remote_push_performed=$false;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false}
}
function Invoke-MIR4A08CreateOnlyCandidatePush {
  [CmdletBinding()]param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$IntentionPath,[Parameter(Mandatory)][string]$StateRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$intention=Read-MIR4A08Intention $IntentionPath;if (-not[bool]$intention.rehearsal){throw '[mir4-a08-external-effect-not-authorized]'};$candidate=Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $intention.plan -CandidateRef ([string]$intention.candidate.ref) -CandidateCommit ([string]$intention.candidate.commit);if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.main_ref))-cne[string]$intention.plan.main_before.commit){throw '[mir4-a08-remote-main-ref-drift]'};if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.source_ref))-cne[string]$intention.plan.source.commit){throw '[mir4-a08-remote-source-ref-drift]'};$remoteCandidate=Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.candidate_ref);$created=$false;if ($null-eq$remoteCandidate){$output=@(&git -C $repo push --porcelain "--force-with-lease=$($intention.remote.candidate_ref):" ([string]$intention.remote.name) "$($intention.candidate.ref):$($intention.remote.candidate_ref)" 2>&1);if ($LASTEXITCODE-ne0){throw "[mir4-a08-create-only-push] $($output-join' ')"};$created=$true}elseif($remoteCandidate-cne[string]$candidate.commit){throw '[mir4-a08-remote-candidate-conflict]'};$remoteAfter=Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.candidate_ref);if ($remoteAfter-cne[string]$candidate.commit){throw '[mir4-a08-remote-candidate-readback]'};$receipt=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainCandidatePushReceiptV2';intention_sha256=[string]$intention.intention_sha256;candidate_ref=[string]$candidate.ref;candidate_commit=[string]$candidate.commit;remote_candidate_ref=[string]$intention.remote.candidate_ref;remote_candidate_commit=$remoteAfter;create_only_verified=$true;rehearsal=$true;main_mutation_performed=$false;tag_created=$false;publication_performed=$false};$path=Join-Path ([IO.Path]::GetFullPath($StateRoot))("$($intention.intention_sha256.ToLowerInvariant()).candidate-push-receipt.json");$null=Write-MIR4A08ImmutableJson -Path $path -Value $receipt -Code '[mir4-a08-candidate-push-receipt-conflict]';return [pscustomobject][ordered]@{path=$path;created=$created;candidate_commit=$candidate.commit;remote_candidate_commit=$remoteAfter;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false}
}
function Get-MIR4A08PromotionMessage { param([Parameter(Mandatory)]$Intention) return "MIR 4.2 protected promotion`n`nMIR-Candidate-Commit: $($Intention.candidate.commit)`nMIR-Candidate-Tree: $($Intention.candidate.tree)`nMIR-Source-Commit: $($Intention.plan.source.commit)`nMIR-Source-Tree: $($Intention.plan.source.tree)`nMIR-Main-Base: $($Intention.plan.main_before.commit)`nMIR-Policy-SHA256: $($Intention.plan.policy.policy_sha256)`nMIR-Qualification-Binding-SHA256: $($Intention.qualification.record_binding_sha256)`nMIR-Qualification-Package-Set-SHA256: $($Intention.qualification.package_set_sha256)`nMIR-Promotion-Intention-SHA256: $($Intention.intention_sha256)" }
function New-MIR4A08ProtectedPromotionRequest {
  [CmdletBinding()]param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$IntentionPath,[Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][scriptblock]$PolicyProvider)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$intention=Read-MIR4A08Intention $IntentionPath;$policy=Get-MIR4A08PolicyObservation -CanonicalRepository ([string]$intention.plan.policy.repository) -PolicyProvider $PolicyProvider -Rehearsal:$intention.rehearsal;if ([string]$policy.policy_sha256-cne[string]$intention.plan.policy.policy_sha256-or[string]$policy.canonical_remote_url-cne[string]$intention.remote.canonical_remote_url){throw '[mir4-a08-policy-drift-before-merge]'};if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.candidate_ref))-cne[string]$intention.candidate.commit){throw '[mir4-a08-remote-candidate-readback]'};if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.main_ref))-cne[string]$intention.plan.main_before.commit){throw '[mir4-a08-remote-main-ref-drift]'};$request=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainPromotionRequestV3';intention_sha256=[string]$intention.intention_sha256;pre_merge_policy_sha256=[string]$policy.policy_sha256;remote=[pscustomobject][ordered]@{canonical_remote_url=[string]$intention.remote.canonical_remote_url;candidate_ref=[string]$intention.remote.candidate_ref;candidate_commit=[string]$intention.candidate.commit;main_ref=[string]$intention.remote.main_ref;main_before=[string]$intention.plan.main_before.commit};protected_pull_request=[pscustomobject][ordered]@{required=$true;merge_method='squash';required_status_checks=@($intention.plan.promotion.required_status_checks);expected_commit_message=(Get-MIR4A08PromotionMessage $intention);external_execution_required=$true};main_mutation_performed=$false;tag_created=$false;publication_performed=$false;request_sha256=''};$request.request_sha256=Get-MIR4A08SelfSha256 $request 'request_sha256';$path=Join-Path ([IO.Path]::GetFullPath($StateRoot))("$($intention.intention_sha256.ToLowerInvariant()).protected-pr-request.json");$null=Write-MIR4A08ImmutableJson -Path $path -Value $request -Code '[mir4-a08-pr-request-conflict]';return [pscustomobject][ordered]@{path=$path;request_sha256=$request.request_sha256;candidate_commit=$intention.candidate.commit;protected_pr_required=$true;main_mutation_performed=$false;tag_created=$false;publication_authorized=$false}
}
function Read-MIR4A08PromotionRequest {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Intention)
  try{$request=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100 -DateKind String}catch{throw '[mir4-a08-pr-request-invalid]'};Assert-MIR4A08PropertyNames $request @('schema','kind','intention_sha256','pre_merge_policy_sha256','remote','protected_pull_request','main_mutation_performed','tag_created','publication_performed','request_sha256') '[mir4-a08-pr-request-invalid]';Assert-MIR4A08PropertyNames $request.remote @('canonical_remote_url','candidate_ref','candidate_commit','main_ref','main_before') '[mir4-a08-pr-request-invalid]';Assert-MIR4A08PropertyNames $request.protected_pull_request @('required','merge_method','required_status_checks','expected_commit_message','external_execution_required') '[mir4-a08-pr-request-invalid]';if ([int]$request.schema-ne1-or[string]$request.kind-cne'MIR42ProtectedMainPromotionRequestV3'-or[string]$request.intention_sha256-cne[string]$Intention.intention_sha256-or[string]$request.request_sha256-cne(Get-MIR4A08SelfSha256 $request 'request_sha256')-or[string]$request.pre_merge_policy_sha256-cne[string]$Intention.plan.policy.policy_sha256-or[string]$request.remote.canonical_remote_url-cne[string]$Intention.remote.canonical_remote_url-or[string]$request.remote.candidate_ref-cne[string]$Intention.remote.candidate_ref-or[string]$request.remote.candidate_commit-cne[string]$Intention.candidate.commit-or[string]$request.remote.main_ref-cne[string]$Intention.remote.main_ref-or[string]$request.remote.main_before-cne[string]$Intention.plan.main_before.commit-or[string]$request.protected_pull_request.merge_method-cne'squash'-or[string]$request.protected_pull_request.expected_commit_message-cne(Get-MIR4A08PromotionMessage $Intention)){throw '[mir4-a08-pr-request-invalid]'};Assert-MIR4A08Boolean $request.protected_pull_request.required $true '[mir4-a08-pr-request-invalid]';Assert-MIR4A08Boolean $request.protected_pull_request.external_execution_required $true '[mir4-a08-pr-request-invalid]';Assert-MIR4A08Boolean $request.main_mutation_performed $false '[mir4-a08-pr-request-invalid]';Assert-MIR4A08Boolean $request.tag_created $false '[mir4-a08-pr-request-invalid]';Assert-MIR4A08Boolean $request.publication_performed $false '[mir4-a08-pr-request-invalid]';if ((@($request.protected_pull_request.required_status_checks|Sort-Object -Unique)-join'|')-cne'branch-policy|verification-gate'){throw '[mir4-a08-pr-request-invalid]'};return $request
}
function Get-MIR4A08PullRequestObservation {
  param([Parameter(Mandatory)][string]$CanonicalRepository,[Parameter(Mandatory)][scriptblock]$PullRequestProvider,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$MainAfter,[switch]$Rehearsal)
  try{$record=&$PullRequestProvider $CanonicalRepository ([string]$Candidate.ref) ([string]$Candidate.commit) $MainAfter}catch{throw "[mir4-a08-pr-provider] $($_.Exception.Message)"};Assert-MIR4A08PropertyNames $record @('schema','kind','observation_source','repository','canonical_remote_url','number','state','base','head','merge','required_checks','policy_sha256','direct_ref_update','record_sha256') '[mir4-a08-pr-observation]';Assert-MIR4A08PropertyNames $record.base @('ref','commit') '[mir4-a08-pr-observation]';Assert-MIR4A08PropertyNames $record.head @('ref','commit') '[mir4-a08-pr-observation]';Assert-MIR4A08PropertyNames $record.merge @('method','commit') '[mir4-a08-pr-observation]';if ([int]$record.schema-ne1-or[string]$record.kind-cne'MIR42GitHubPullRequestReadbackV1'-or[string]$record.repository-cne$CanonicalRepository-or[int]$record.number-lt1-or[string]$record.state-cne'MERGED'-or[string]$record.canonical_remote_url-cne[string]$Plan.policy.canonical_remote_url-or[string]$record.base.ref-cne'main'-or[string]$record.base.commit-cne[string]$Plan.main_before.commit-or[string]$record.head.ref-cne(([string]$Candidate.ref)-replace'^refs/heads/','')-or[string]$record.head.commit-cne[string]$Candidate.commit-or[string]$record.merge.method-cne'squash'-or[string]$record.merge.commit-cne$MainAfter-or[string]$record.policy_sha256-cne[string]$Plan.policy.policy_sha256-or[string]$record.record_sha256-cne(Get-MIR4A08SelfSha256 $record 'record_sha256')){throw '[mir4-a08-pr-observation]'};if ($Rehearsal){if ([string]$record.observation_source-cne'synthetic-github-readonly-v1'){throw '[mir4-a08-pr-observation]'}}elseif([string]$record.observation_source-cne'github-rest-v3'){throw '[mir4-a08-pr-observation]'};if ([bool]$record.direct_ref_update){throw '[mir4-a08-pr-bypass]'};$checks=@($record.required_checks|ForEach-Object{[string]$_.context+':'+[string]$_.conclusion});foreach ($required in @('branch-policy','verification-gate')){if ("$required`:success"-notin$checks){throw '[mir4-a08-pr-required-check]'}};return $record
}
function Test-MIR4ProtectedPromotionReadback {
  [CmdletBinding()]param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$IntentionPath,[Parameter(Mandatory)][string]$PromotionRequestPath,[Parameter(Mandatory)][string]$StateRoot,[Parameter(Mandatory)][scriptblock]$PolicyProvider,[Parameter(Mandatory)][scriptblock]$PullRequestProvider)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$intention=Read-MIR4A08Intention $IntentionPath;$request=Read-MIR4A08PromotionRequest -Path $PromotionRequestPath -Intention $intention;$policy=Get-MIR4A08PolicyObservation -CanonicalRepository ([string]$intention.plan.policy.repository) -PolicyProvider $PolicyProvider -Rehearsal:$intention.rehearsal;if ([string]$policy.policy_sha256-cne[string]$intention.plan.policy.policy_sha256-or[string]$policy.canonical_remote_url-cne[string]$intention.remote.canonical_remote_url){throw '[mir4-a08-policy-drift-readback]'};if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.candidate_ref))-cne[string]$intention.candidate.commit){throw '[mir4-a08-remote-candidate-readback]'};if ((Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.source_ref))-cne[string]$intention.plan.source.commit){throw '[mir4-a08-remote-source-ref-drift-after-promotion]'};$mainRemote=Get-MIR4A08RemoteRef -RepoRoot $repo -RemoteName ([string]$intention.remote.name) -Ref ([string]$intention.remote.main_ref);if ($null-eq$mainRemote-or$mainRemote-ceq[string]$intention.plan.main_before.commit){throw '[mir4-a08-readback-no-promotion]'};$null=Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('fetch','--no-tags',[string]$intention.remote.name,[string]$intention.remote.main_ref);$mainAfter=Resolve-MIR4A08Commit -RepoRoot $repo -Revision 'FETCH_HEAD';if ($mainAfter-cne$mainRemote){throw '[mir4-a08-remote-main-fetch-mismatch]'};$tree=Resolve-MIR4A08Tree -RepoRoot $repo -Commit $mainAfter;$parents=@(((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('show','-s','--format=%P',$mainAfter))-join'').Trim()-split'\s+'|Where-Object{$_});$message=((Invoke-MIR4A08Git -RepoRoot $repo -Arguments @('show','-s','--format=%B',$mainAfter))-join"`n").TrimEnd();if ($tree-cne[string]$intention.candidate.tree){throw '[mir4-a08-readback-tree-mismatch]'};if ($parents.Count-ne1-or$parents[0]-cne[string]$intention.plan.main_before.commit){throw '[mir4-a08-readback-not-direct-main-child]'};if ($message-cne[string]$request.protected_pull_request.expected_commit_message){throw '[mir4-a08-readback-message-mismatch]'};$candidate=Assert-MIR4A08CandidateAgainstPlan -RepoRoot $repo -Plan $intention.plan -CandidateRef ([string]$intention.candidate.ref) -CandidateCommit ([string]$intention.candidate.commit);$null=Get-MIR4A08PullRequestObservation -CanonicalRepository ([string]$intention.plan.policy.repository) -PullRequestProvider $PullRequestProvider -Plan $intention.plan -Candidate $candidate -MainAfter $mainAfter -Rehearsal:$intention.rehearsal;$qualification=Read-MIR4A08QualificationRecord -RepoRoot $repo -Plan $intention.plan -Candidate $candidate -RecordPath ([string]$intention.qualification.record_path) -PackageRoot ([string]$intention.qualification.package_root) -Rehearsal:$intention.rehearsal;if ([string]$qualification.record_binding_sha256-cne[string]$intention.qualification.record_binding_sha256-or[string]$qualification.package_set_sha256-cne[string]$intention.qualification.package_set_sha256){throw '[mir4-a08-readback-package-mismatch]'};$receipt=[pscustomobject][ordered]@{schema=1;kind='MIR42ProtectedMainPromotionReadbackV4';status='qualified-tree-on-main-awaiting-maintainer-playtest';intention_sha256=[string]$intention.intention_sha256;request_sha256=[string]$request.request_sha256;main_before=[string]$intention.plan.main_before.commit;qualified_candidate_commit=[string]$candidate.commit;main_after=$mainAfter;tree=$tree;commit_rewritten=($mainAfter-cne[string]$candidate.commit);source_ref=[string]$intention.remote.source_ref;source_commit=[string]$intention.plan.source.commit;policy_sha256=[string]$policy.policy_sha256;package_set_sha256=[string]$qualification.package_set_sha256;package_presentation_record_sha256=[string]$qualification.package_presentation.record_sha256;checks=@('fresh-remote-ref-readback','actual-pr-identity','protected-policy-rechecked','squash-merge-method','required-checks','exact-direct-main-child','exact-qualified-tree','exact-package-bytes','source-ref-unchanged','commit-message-binding');ruleset_mutation_performed=$false;force_push_performed=$false;tag_created=$false;publication_performed=$false;publication_authorized=$false};$path=Join-Path ([IO.Path]::GetFullPath($StateRoot))("$($intention.intention_sha256.ToLowerInvariant()).commit-rebinding-receipt.json");$null=Write-MIR4A08ImmutableJson -Path $path -Value $receipt -Code '[mir4-a08-rebinding-receipt-conflict]';$receipt|Add-Member path $path;return $receipt
}
function Test-MIR4A08PromotionTopologyAuthority {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$AuthorityPath = '',
    [string]$ProgrammePath = ''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $specPath = if ([string]::IsNullOrWhiteSpace($AuthorityPath)) { Join-Path $repo 'spec/releases/mir4-protected-main-promotion-topology-v1.json' } else { [IO.Path]::GetFullPath($AuthorityPath) }
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-protected-main-promotion-topology-v1.schema.json'
  $text = Get-Content -Raw -LiteralPath $specPath
  if (-not ($text | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-a08-authority-schema]' }
  $authority = $text | ConvertFrom-Json -Depth 100 -DateKind String
  $programmeFile = if ([string]::IsNullOrWhiteSpace($ProgrammePath)) { Join-Path $repo 'spec/programmes/mir4-4x-operating-programme-v1.json' } else { [IO.Path]::GetFullPath($ProgrammePath) }
  $programme = Get-Content -Raw -LiteralPath $programmeFile | ConvertFrom-Json -Depth 100 -DateKind String
  $a08 = @($programme.synthesis.tasks | Where-Object { [string]$_.id -ceq 'A08' })
  $evidence = @('spec/releases/mir4-protected-main-promotion-topology-v1.json','tests/mir4/Test-MIR4ProtectedPromotionTopologyA08.ps1')
  if ([string]$authority.status -cne 'implemented-and-synthetically-rehearsed-release-blocked' -or
      [string]$authority.governance.policy_observation -cne 'github-rest-v3-current-observation-required' -or
      -not [bool]$authority.governance.effective_policy_rechecked_before_merge -or
      -not [bool]$authority.qualification.exact_current_package_presentation_record_bound -or
      -not [bool]$authority.qualification.source_manifest_identity_bound -or
      -not [bool]$authority.qualification.package_authority_identity_bound -or
      -not [bool]$authority.qualification.governed_independent_receipts_required -or
      -not [bool]$authority.readback.actual_pr_observation_required -or
      -not [bool]$authority.recovery.persist_before_effect -or
      $a08.Count -ne 1 -or [string]$a08[0].state -cne 'complete' -or
      (@($a08[0].evidence | Sort-Object) -join '|') -cne ($evidence -join '|')) {
    throw '[mir4-a08-authority-wiring]'
  }
  return [pscustomobject][ordered]@{authority=$specPath;programme=$programmeFile;state='implemented-and-synthetically-rehearsed-release-blocked'}
}
