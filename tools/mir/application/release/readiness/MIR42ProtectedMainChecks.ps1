Set-StrictMode -Version Latest

# The two protected status names are not interchangeable.  The current
# repository workflows emit branch-policy from the governance workflow and
# verification-gate from the MIR validation workflow.  The readback binds the
# Actions run and job that produced each check, rather than trusting a status
# name supplied by any publisher.
function Get-MIR42ProtectedMainCheckContract {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RequiredStatusCheck)

  switch ($RequiredStatusCheck) {
    'branch-policy' {
      return [pscustomobject][ordered]@{
        name = 'branch-policy'
        workflow_name = 'Branch Policy'
        workflow_path = '.github/workflows/branch-policy.yml'
        job_name = 'branch-policy'
      }
    }
    'verification-gate' {
      return [pscustomobject][ordered]@{
        name = 'verification-gate'
        workflow_name = 'MIR'
        workflow_path = '.github/workflows/validate.yml'
        job_name = 'verification-gate'
      }
    }
    default { throw '[mir42-main-check-contract]' }
  }
}

function Get-MIR42ProtectedMainChecksProperty {
  param(
    [Parameter(Mandatory)][AllowNull()]$Value,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Code
  )

  if ($null -eq $Value -or @($Value.PSObject.Properties.Match($Name)).Count -ne 1) { throw "[$Code]" }
  return $Value.PSObject.Properties[$Name].Value
}

function Assert-MIR42ProtectedMainChecksString {
  param([Parameter(Mandatory)][AllowNull()]$Value,[Parameter(Mandatory)][string]$Code,[switch]$AllowEmpty)
  if ($Value -isnot [string] -or ((-not $AllowEmpty) -and [string]::IsNullOrWhiteSpace($Value))) { throw "[$Code]" }
  return [string]$Value
}

function Assert-MIR42ProtectedMainChecksPositiveInteger {
  param([Parameter(Mandatory)][AllowNull()]$Value,[Parameter(Mandatory)][string]$Code)
  if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and $Value -isnot [int64]) { throw "[$Code]" }
  if ([int64]$Value -lt 1) { throw "[$Code]" }
  return [int64]$Value
}

function Assert-MIR42ProtectedMainChecksPage {
  param(
    [Parameter(Mandatory)]$Page,
    [Parameter(Mandatory)][string]$RowsProperty,
    [Parameter(Mandatory)][string]$Code
  )

  $total = Get-MIR42ProtectedMainChecksProperty -Value $Page -Name 'total_count' -Code $Code
  if ($total -isnot [byte] -and $total -isnot [int16] -and $total -isnot [int32] -and $total -isnot [int64]) { throw "[$Code]" }
  if ([int64]$total -lt 0 -or [int64]$total -ge 100) { throw "[$Code]" }
  $rows = @(Get-MIR42ProtectedMainChecksProperty -Value $Page -Name $RowsProperty -Code $Code)
  if ($rows.Count -ne [int64]$total) { throw "[$Code]" }
  return @($rows)
}

function Invoke-MIR42ProtectedMainChecksApi {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Endpoint,
    [Parameter(Mandatory)][string]$Code
  )

  if ($Endpoint -notmatch '^repos/Julesc013/more-infinite-research/') { throw "[$Code]" }
  $gh = Get-Command gh -CommandType Application -ErrorAction Stop
  $lines = @(& $gh.Source api --hostname github.com $Endpoint 2>&1 | ForEach-Object { [string]$_ })
  if ($LASTEXITCODE -ne 0) { throw "[$Code] $($lines -join ' ')" }
  try { return (($lines -join "`n") | ConvertFrom-Json -Depth 100 -DateKind String) }
  catch { throw "[$Code]" }
}

function Assert-MIR42ProtectedMainChecksPullRequest {
  param(
    [Parameter(Mandatory)]$PullRequest,
    [Parameter(Mandatory)][int]$PullRequestNumber,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$CandidateBranch,
    [Parameter(Mandatory)][string]$CandidateHead
  )

  $number = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $PullRequest -Name 'number' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  $state = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $PullRequest -Name 'state' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  $merged = Get-MIR42ProtectedMainChecksProperty -Value $PullRequest -Name 'merged' -Code 'mir42-main-check-pr'
  $base = Get-MIR42ProtectedMainChecksProperty -Value $PullRequest -Name 'base' -Code 'mir42-main-check-pr'
  $head = Get-MIR42ProtectedMainChecksProperty -Value $PullRequest -Name 'head' -Code 'mir42-main-check-pr'
  $baseRef = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $base -Name 'ref' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  $baseRepository = Get-MIR42ProtectedMainChecksProperty -Value $base -Name 'repo' -Code 'mir42-main-check-pr'
  $baseFullName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $baseRepository -Name 'full_name' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  $headRef = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $head -Name 'ref' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  $headSha = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $head -Name 'sha' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  $headRepository = Get-MIR42ProtectedMainChecksProperty -Value $head -Name 'repo' -Code 'mir42-main-check-pr'
  $headFullName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $headRepository -Name 'full_name' -Code 'mir42-main-check-pr') -Code 'mir42-main-check-pr'
  if ($number -ne $PullRequestNumber -or $state -cne 'closed' -or $merged -isnot [bool] -or -not $merged -or
      $baseRef -cne 'main' -or $baseFullName -cne $Repository -or
      $headRef -cne $CandidateBranch -or $headSha -cne $CandidateHead -or $headFullName -cne $Repository) {
    throw '[mir42-main-check-pr]'
  }
}

function Test-MIR42ProtectedMainChecksWorkflowPath {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedPath)

  if ($Path -ceq $ExpectedPath) { return $true }
  $reference = '(?:[0-9a-f]{40}|(?:refs/(?:heads|tags|pull)/)?[A-Za-z0-9][A-Za-z0-9._/-]*)'
  return $Path -cmatch ('^' + [regex]::Escape($ExpectedPath) + '@' + $reference + '$')
}

function Get-MIR42ProtectedMainRequiredCheckObservations {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$CandidateHead,
    [Parameter(Mandatory)][ValidatePattern('^refs/heads/release/mir-4[.]2-candidate-[0-9a-f]{12}$')][string]$CandidateRef,
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequestNumber,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RequiredStatusChecks
  )

  $repository = 'Julesc013/more-infinite-research'
  $expectedChecks = @('branch-policy','verification-gate')
  $actualChecks = @($RequiredStatusChecks | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive -Unique)
  if ($actualChecks.Count -ne $expectedChecks.Count -or ($actualChecks -join '|') -cne ($expectedChecks -join '|')) { throw '[mir42-main-check-contract]' }
  $candidateBranch = $CandidateRef.Substring('refs/heads/'.Length)

  $pullRequest = Invoke-MIR42ProtectedMainChecksApi -Endpoint "repos/$repository/pulls/$PullRequestNumber" -Code 'mir42-main-check-pr-api'
  Assert-MIR42ProtectedMainChecksPullRequest -PullRequest $pullRequest -PullRequestNumber $PullRequestNumber -Repository $repository -CandidateBranch $candidateBranch -CandidateHead $CandidateHead
  # A current GitHub Actions read of the known PR 350 returns an empty
  # workflow_run.pull_requests array.  The run is therefore bound to the
  # freshly observed PR by its pull_request event, canonical head repository,
  # exact candidate branch, and exact head SHA rather than by an absent array.

  $checkPage = Invoke-MIR42ProtectedMainChecksApi -Endpoint "repos/$repository/commits/$CandidateHead/check-runs?per_page=100" -Code 'mir42-main-check-checks-api'
  $checkRuns = @(Assert-MIR42ProtectedMainChecksPage -Page $checkPage -RowsProperty 'check_runs' -Code 'mir42-main-check-checks-truncated')
  $runPage = Invoke-MIR42ProtectedMainChecksApi -Endpoint "repos/$repository/actions/runs?event=pull_request&head_sha=$CandidateHead&per_page=100" -Code 'mir42-main-check-runs-api'
  $workflowRuns = @(Assert-MIR42ProtectedMainChecksPage -Page $runPage -RowsProperty 'workflow_runs' -Code 'mir42-main-check-runs-truncated')

  $observed = [Collections.Generic.List[object]]::new()
  foreach ($required in $expectedChecks) {
    $contract = Get-MIR42ProtectedMainCheckContract -RequiredStatusCheck $required
    $sameName = @($checkRuns | Where-Object {
      (Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $_ -Name 'name' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run') -ceq $required
    })
    if ($sameName.Count -eq 0) { throw "[mir42-main-check-required] $required" }
    foreach ($candidateCheck in $sameName) {
      $publisher = Get-MIR42ProtectedMainChecksProperty -Value $candidateCheck -Name 'app' -Code 'mir42-main-check-publisher'
      $slug = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $publisher -Name 'slug' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $head = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $candidateCheck -Name 'head_sha' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run'
      if ($slug -cne 'github-actions' -or $head -cne $CandidateHead) { throw "[mir42-main-check-publisher] $required" }
      $checkSuite = Get-MIR42ProtectedMainChecksProperty -Value $candidateCheck -Name 'check_suite' -Code 'mir42-main-check-publisher'
      $checkSuiteId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $checkSuite -Name 'id' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suiteRuns = @($workflowRuns | Where-Object {
        (Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $_ -Name 'check_suite_id' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher') -eq $checkSuiteId
      })
      if ($suiteRuns.Count -ne 1) { throw "[mir42-main-check-publisher] $required" }
      $suiteRun = $suiteRuns[0]
      $suiteName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'name' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suitePath = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'path' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suiteEvent = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'event' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suiteBranch = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'head_branch' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suiteHead = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'head_sha' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suiteRepository = Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'repository' -Code 'mir42-main-check-publisher'
      $suiteHeadRepository = Get-MIR42ProtectedMainChecksProperty -Value $suiteRun -Name 'head_repository' -Code 'mir42-main-check-publisher'
      $suiteFullName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteRepository -Name 'full_name' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      $suiteHeadFullName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $suiteHeadRepository -Name 'full_name' -Code 'mir42-main-check-publisher') -Code 'mir42-main-check-publisher'
      if ($suiteName -cne $contract.workflow_name -or -not (Test-MIR42ProtectedMainChecksWorkflowPath -Path $suitePath -ExpectedPath $contract.workflow_path) -or $suiteEvent -cne 'pull_request' -or
          $suiteBranch -cne $candidateBranch -or $suiteHead -cne $CandidateHead -or $suiteFullName -cne $repository -or $suiteHeadFullName -cne $repository) {
        throw "[mir42-main-check-publisher] $required"
      }
    }

    $trustedRuns = @($workflowRuns | Where-Object {
      $run = $_
      $id = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'id' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $name = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'name' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $path = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'path' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $event = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'event' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $headBranch = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'head_branch' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $headSha = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'head_sha' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $runRepository = Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'repository' -Code 'mir42-main-check-workflow'
      $runHeadRepository = Get-MIR42ProtectedMainChecksProperty -Value $run -Name 'head_repository' -Code 'mir42-main-check-workflow'
      $runFullName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $runRepository -Name 'full_name' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $runHeadFullName = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $runHeadRepository -Name 'full_name' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
      $id -gt 0 -and $name -ceq $contract.workflow_name -and (Test-MIR42ProtectedMainChecksWorkflowPath -Path $path -ExpectedPath $contract.workflow_path) -and
        $event -ceq 'pull_request' -and $headBranch -ceq $candidateBranch -and $headSha -ceq $CandidateHead -and $runFullName -ceq $repository -and $runHeadFullName -ceq $repository
    } | Sort-Object { [int64]$_.id } -Descending)
    if ($trustedRuns.Count -eq 0) { throw "[mir42-main-check-workflow] $required" }
    $workflowRun = $trustedRuns[0]
    $runStatus = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $workflowRun -Name 'status' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
    $runConclusion = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $workflowRun -Name 'conclusion' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
    $runId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $workflowRun -Name 'id' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
    $runAttempt = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $workflowRun -Name 'run_attempt' -Code 'mir42-main-check-workflow') -Code 'mir42-main-check-workflow'
    if ($runStatus -cne 'completed' -or $runConclusion -cne 'success') { throw "[mir42-main-check-workflow] $required" }

    $jobPage = Invoke-MIR42ProtectedMainChecksApi -Endpoint "repos/$repository/actions/runs/$runId/jobs?filter=latest&per_page=100" -Code 'mir42-main-check-jobs-api'
    $jobs = @(Assert-MIR42ProtectedMainChecksPage -Page $jobPage -RowsProperty 'jobs' -Code 'mir42-main-check-jobs-truncated')
    $matchingJobs = @($jobs | Where-Object {
      (Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $_ -Name 'name' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job') -ceq $contract.job_name
    })
    if ($matchingJobs.Count -ne 1) { throw "[mir42-main-check-job] $required" }
    $job = $matchingJobs[0]
    $jobId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'id' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    $jobRunId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'run_id' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    $jobHead = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'head_sha' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    $jobWorkflow = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'workflow_name' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    $jobStatus = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'status' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    $jobConclusion = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'conclusion' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    $jobCheckRunUrl = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $job -Name 'check_run_url' -Code 'mir42-main-check-job') -Code 'mir42-main-check-job'
    if ($jobRunId -ne $runId -or $jobHead -cne $CandidateHead -or $jobWorkflow -cne $contract.workflow_name -or $jobStatus -cne 'completed' -or $jobConclusion -cne 'success') {
      throw "[mir42-main-check-job] $required"
    }

    $linkedChecks = @($sameName | Where-Object {
      $checkId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $_ -Name 'id' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run'
      $expectedUrl = "https://api.github.com/repos/$repository/check-runs/$checkId"
      $jobCheckRunUrl -ceq $expectedUrl
    })
    if ($linkedChecks.Count -ne 1) { throw "[mir42-main-check-link] $required" }
    $check = $linkedChecks[0]
    $checkId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $check -Name 'id' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run'
    $checkSuite = Get-MIR42ProtectedMainChecksProperty -Value $check -Name 'check_suite' -Code 'mir42-main-check-link'
    $checkSuiteId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $checkSuite -Name 'id' -Code 'mir42-main-check-link') -Code 'mir42-main-check-link'
    $workflowRunSuiteId = Assert-MIR42ProtectedMainChecksPositiveInteger -Value (Get-MIR42ProtectedMainChecksProperty -Value $workflowRun -Name 'check_suite_id' -Code 'mir42-main-check-link') -Code 'mir42-main-check-link'
    if ($workflowRunSuiteId -ne $checkSuiteId) { throw "[mir42-main-check-link] $required" }
    $checkStatus = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $check -Name 'status' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run'
    $checkConclusion = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $check -Name 'conclusion' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run'
    $checkUrl = Assert-MIR42ProtectedMainChecksString -Value (Get-MIR42ProtectedMainChecksProperty -Value $check -Name 'html_url' -Code 'mir42-main-check-run') -Code 'mir42-main-check-run'
    if ($checkStatus -cne 'completed' -or $checkConclusion -cne 'success' -or $checkUrl -notmatch ('^https://github[.]com/' + [regex]::Escape($repository) + '/')) {
      throw "[mir42-main-check-required] $required"
    }

    $observed.Add([pscustomobject][ordered]@{
      name = $required
      id = $checkId
      head_sha = $CandidateHead
      conclusion = 'success'
      url = $checkUrl
      publisher = 'github-actions'
      workflow = [pscustomobject][ordered]@{
        name = $contract.workflow_name
        path = $contract.workflow_path
        run_id = $runId
        run_attempt = $runAttempt
        event = 'pull_request'
        pull_request_number = $PullRequestNumber
        head_branch = $candidateBranch
        head_sha = $CandidateHead
      }
      job = [pscustomobject][ordered]@{
        id = $jobId
        name = $contract.job_name
        check_run_url = $jobCheckRunUrl
      }
    })
  }
  return @($observed.ToArray())
}
