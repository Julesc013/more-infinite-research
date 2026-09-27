# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42ProtectedMainChecks.ps1')

function Assert-MIR42ProtectedMainChecksTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-protected-main-checks-test-$Code]" }
}

function New-MIR42ProtectedMainChecksFixture {
  $repository = 'Julesc013/more-infinite-research'
  $head = 'c' * 40
  $branch = 'release/mir-4.2-candidate-cccccccccccc'
  $pullNumber = 42
  $runs = @(
    [pscustomobject][ordered]@{
      id = [int64]1001; check_suite_id = [int64]501; name = 'Branch Policy'; path = '.github/workflows/branch-policy.yml'; event = 'pull_request'; status = 'completed'; conclusion = 'success'; head_branch = $branch; head_sha = $head; run_attempt = [int64]1
      repository = [pscustomobject]@{full_name=$repository}; head_repository = [pscustomobject]@{full_name=$repository}
      pull_requests = @()
    },
    [pscustomobject][ordered]@{
      id = [int64]1002; check_suite_id = [int64]502; name = 'MIR'; path = '.github/workflows/validate.yml'; event = 'pull_request'; status = 'completed'; conclusion = 'success'; head_branch = $branch; head_sha = $head; run_attempt = [int64]2
      repository = [pscustomobject]@{full_name=$repository}; head_repository = [pscustomobject]@{full_name=$repository}
      pull_requests = @()
    }
  )
  $checks = @(
    [pscustomobject][ordered]@{id=[int64]11001;name='branch-policy';head_sha=$head;status='completed';conclusion='success';html_url="https://github.com/$repository/actions/runs/1001/job/2001";check_suite=[pscustomobject]@{id=[int64]501};app=[pscustomobject]@{slug='github-actions'}},
    [pscustomobject][ordered]@{id=[int64]11002;name='verification-gate';head_sha=$head;status='completed';conclusion='success';html_url="https://github.com/$repository/actions/runs/1002/job/2002";check_suite=[pscustomobject]@{id=[int64]502};app=[pscustomobject]@{slug='github-actions'}}
  )
  return [pscustomobject][ordered]@{
    repository=$repository; head=$head; branch=$branch; pull_number=$pullNumber
    responses=@{
      "repos/$repository/pulls/$pullNumber" = [pscustomobject][ordered]@{number=[int64]$pullNumber;state='closed';merged=$true;base=[pscustomobject]@{ref='main';repo=[pscustomobject]@{full_name=$repository}};head=[pscustomobject]@{ref=$branch;sha=$head;repo=[pscustomobject]@{full_name=$repository}}}
      "repos/$repository/commits/$head/check-runs?per_page=100" = [pscustomobject][ordered]@{total_count=[int64]$checks.Count;check_runs=$checks}
      "repos/$repository/actions/runs?event=pull_request&head_sha=$head&per_page=100" = [pscustomobject][ordered]@{total_count=[int64]$runs.Count;workflow_runs=$runs}
      "repos/$repository/actions/runs/1001/jobs?filter=latest&per_page=100" = [pscustomobject][ordered]@{total_count=[int64]1;jobs=@([pscustomobject][ordered]@{id=[int64]2001;run_id=[int64]1001;head_sha=$head;workflow_name='Branch Policy';name='branch-policy';status='completed';conclusion='success';check_run_url="https://api.github.com/repos/$repository/check-runs/11001"})}
      "repos/$repository/actions/runs/1002/jobs?filter=latest&per_page=100" = [pscustomobject][ordered]@{total_count=[int64]1;jobs=@([pscustomobject][ordered]@{id=[int64]2002;run_id=[int64]1002;head_sha=$head;workflow_name='MIR';name='verification-gate';status='completed';conclusion='success';check_run_url="https://api.github.com/repos/$repository/check-runs/11002"})}
    }
  }
}

function Invoke-MIR42ProtectedMainChecksFixture {
  param([Parameter(Mandatory)]$Fixture)
  $script:mir42ProtectedMainChecksResponses = $Fixture.responses
  return Get-MIR42ProtectedMainRequiredCheckObservations -CandidateHead $Fixture.head -CandidateRef ('refs/heads/' + $Fixture.branch) -PullRequestNumber $Fixture.pull_number -RequiredStatusChecks @('branch-policy','verification-gate')
}

$reader = (Get-Item Function:Invoke-MIR42ProtectedMainChecksApi).ScriptBlock
try {
  Set-Item Function:Invoke-MIR42ProtectedMainChecksApi -Value {
    param($Endpoint,$Code)
    if (-not $script:mir42ProtectedMainChecksResponses.ContainsKey($Endpoint)) { throw "[$Code] unexpected-endpoint $Endpoint" }
    return $script:mir42ProtectedMainChecksResponses[$Endpoint]
  }

  $fixture = New-MIR42ProtectedMainChecksFixture
  $observed = @(Invoke-MIR42ProtectedMainChecksFixture -Fixture $fixture)
  Assert-MIR42ProtectedMainChecksTest -Condition ($observed.Count -eq 2 -and [string]$observed[0].name -ceq 'branch-policy' -and [string]$observed[1].name -ceq 'verification-gate' -and [string]$observed[1].workflow.path -ceq '.github/workflows/validate.yml' -and [string]$observed[1].job.check_run_url -ceq 'https://api.github.com/repos/Julesc013/more-infinite-research/check-runs/11002') -Code 'bound-actions-run-job-publisher'

  foreach($case in @(
    [pscustomobject]@{name='competing-publisher'; mutate={param($f)$f.responses["repos/$($f.repository)/commits/$($f.head)/check-runs?per_page=100"].check_runs[1].app.slug='untrusted-publisher'}; pattern='^\[mir42-main-check-publisher\]'},
    [pscustomobject]@{name='competing-same-publisher-wrong-workflow'; mutate={param($f)$checkPage=$f.responses["repos/$($f.repository)/commits/$($f.head)/check-runs?per_page=100"];$checkPage.check_runs+=@([pscustomobject]@{id=[int64]11999;name='verification-gate';head_sha=$f.head;status='completed';conclusion='success';html_url="https://github.com/$($f.repository)/actions/runs/1999/job/2999";check_suite=[pscustomobject]@{id=[int64]599};app=[pscustomobject]@{slug='github-actions'}});$checkPage.total_count=[int64]$checkPage.check_runs.Count;$runPage=$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"];$runPage.workflow_runs+=@([pscustomobject]@{id=[int64]1999;check_suite_id=[int64]599;name='Untrusted';path='.github/workflows/untrusted.yml';event='pull_request';status='completed';conclusion='success';head_branch=$f.branch;head_sha=$f.head;run_attempt=[int64]1;repository=[pscustomobject]@{full_name=$f.repository};head_repository=[pscustomobject]@{full_name=$f.repository};pull_requests=@()});$runPage.total_count=[int64]$runPage.workflow_runs.Count}; pattern='^\[mir42-main-check-publisher\]'},
    [pscustomobject]@{name='wrong-workflow'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"].workflow_runs[1].path='.github/workflows/untrusted.yml@refs/pull/42/merge'}; pattern='^\[mir42-main-check-publisher\]'},
    [pscustomobject]@{name='wrong-head'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"].workflow_runs[1].head_sha=('d'*40)}; pattern='^\[mir42-main-check-publisher\]'},
    [pscustomobject]@{name='wrong-pr'; mutate={param($f)$f.responses["repos/$($f.repository)/pulls/$($f.pull_number)"].head.ref='untrusted-candidate'}; pattern='^\[mir42-main-check-pr\]'},
    [pscustomobject]@{name='unfinished-run'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"].workflow_runs[1].status='in_progress';$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"].workflow_runs[1].conclusion=$null}; pattern='^\[mir42-main-check-workflow\]'},
    [pscustomobject]@{name='failed-job'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs/1002/jobs?filter=latest&per_page=100"].jobs[0].conclusion='failure'}; pattern='^\[mir42-main-check-job\]'},
    [pscustomobject]@{name='failed-check'; mutate={param($f)$f.responses["repos/$($f.repository)/commits/$($f.head)/check-runs?per_page=100"].check_runs[1].conclusion='failure'}; pattern='^\[mir42-main-check-required\]'},
    [pscustomobject]@{name='wrong-job'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs/1002/jobs?filter=latest&per_page=100"].jobs[0].name='untrusted-job'}; pattern='^\[mir42-main-check-job\]'},
    [pscustomobject]@{name='mismatched-link'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs/1002/jobs?filter=latest&per_page=100"].jobs[0].check_run_url='https://api.github.com/repos/Julesc013/more-infinite-research/check-runs/99999'}; pattern='^\[mir42-main-check-link\]'},
    [pscustomobject]@{name='cross-suite-latest-run-links-old-check'; mutate={param($f)$runPage=$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"];$runPage.workflow_runs+=@([pscustomobject]@{id=[int64]1003;check_suite_id=[int64]503;name='MIR';path='.github/workflows/validate.yml';event='pull_request';status='completed';conclusion='success';head_branch=$f.branch;head_sha=$f.head;run_attempt=[int64]3;repository=[pscustomobject]@{full_name=$f.repository};head_repository=[pscustomobject]@{full_name=$f.repository};pull_requests=@()});$runPage.total_count=[int64]$runPage.workflow_runs.Count;$f.responses["repos/$($f.repository)/actions/runs/1003/jobs?filter=latest&per_page=100"]=[pscustomobject][ordered]@{total_count=[int64]1;jobs=@([pscustomobject][ordered]@{id=[int64]2003;run_id=[int64]1003;head_sha=$f.head;workflow_name='MIR';name='verification-gate';status='completed';conclusion='success';check_run_url="https://api.github.com/repos/$($f.repository)/check-runs/11002"})}}; pattern='^\[mir42-main-check-link\]'},
    [pscustomobject]@{name='truncated-checks'; mutate={param($f)$f.responses["repos/$($f.repository)/commits/$($f.head)/check-runs?per_page=100"].total_count=[int64]100}; pattern='^\[mir42-main-check-checks-truncated\]'},
    [pscustomobject]@{name='truncated-runs'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"].total_count=[int64]100}; pattern='^\[mir42-main-check-runs-truncated\]'},
    [pscustomobject]@{name='truncated-jobs'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs/1002/jobs?filter=latest&per_page=100"].total_count=[int64]100}; pattern='^\[mir42-main-check-jobs-truncated\]'},
    [pscustomobject]@{name='wrong-event'; mutate={param($f)$f.responses["repos/$($f.repository)/actions/runs?event=pull_request&head_sha=$($f.head)&per_page=100"].workflow_runs[1].event='push'}; pattern='^\[mir42-main-check-publisher\]'}
  )) {
    $fixture = New-MIR42ProtectedMainChecksFixture
    & $case.mutate $fixture
    $rejected = $false
    try { Invoke-MIR42ProtectedMainChecksFixture -Fixture $fixture | Out-Null } catch { $rejected = $_.Exception.Message -match $case.pattern }
    Assert-MIR42ProtectedMainChecksTest -Condition $rejected -Code $case.name
  }

  $source = Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/mir/application/release/readiness/MIR42ProtectedMainChecks.ps1')
  Assert-MIR42ProtectedMainChecksTest -Condition ($source -match 'Get-Command gh -CommandType Application' -and $source -match 'api --hostname github\.com') -Code 'application-host-pinned'
  $fixture = New-MIR42ProtectedMainChecksFixture
  $runPage = $fixture.responses["repos/$($fixture.repository)/actions/runs?event=pull_request&head_sha=$($fixture.head)&per_page=100"]
  $runPage.workflow_runs[0].path += '@refs/pull/42/merge'
  $runPage.workflow_runs[1].path += '@' + $fixture.branch
  Assert-MIR42ProtectedMainChecksTest -Condition (@(Invoke-MIR42ProtectedMainChecksFixture -Fixture $fixture).Count -eq 2) -Code 'documented-at-reference-workflow-path'
  $fixture = New-MIR42ProtectedMainChecksFixture
  $fixture.responses["repos/$($fixture.repository)/actions/runs?event=pull_request&head_sha=$($fixture.head)&per_page=100"].workflow_runs[1].path += '@not?a-reference'
  $rejected = $false
  try { Invoke-MIR42ProtectedMainChecksFixture -Fixture $fixture | Out-Null } catch { $rejected = $_.Exception.Message -match '^\[mir42-main-check-publisher\]' }
  Assert-MIR42ProtectedMainChecksTest -Condition $rejected -Code 'invalid-workflow-path-suffix'
} finally {
  Set-Item Function:Invoke-MIR42ProtectedMainChecksApi -Value $reader
  Remove-Variable -Name mir42ProtectedMainChecksResponses -Scope Script -ErrorAction SilentlyContinue
}

Write-Output 'MIR42-PROTECTED-MAIN-CHECKS-PASSED checks=2 opposing=15 api=mocked-private-reader-only'
