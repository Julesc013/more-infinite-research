# MIR4-CANONICAL-DEVELOPMENT-HEALTH-CHECK
[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [ValidateSet('Report','Hook')][string]$Mode = 'Report',
  [switch]$AsJson,
  [ValidateRange(1, 60)][int]$MaxScanSeconds = 15,
  [ValidateRange(1, 100000)][int]$MaxEntriesPerRoot = 10000,
  [ValidateRange(1, 128)][int]$MaxWorktrees = 16,
  [ValidateRange(1, 512)][int]$MaxBranches = 128,
  [ValidateRange(1, 3650)][int]$OldWorktreeDays = 14,
  [ValidateRange(1, 3650)][int]$OldBranchDays = 30,
  [ValidateRange(0, 65536)][int]$BuildBudgetMiB = 16384,
  [ValidateRange(0, 65536)][int]$DistBudgetMiB = 4096,
  [ValidateRange(1, 65536)][int]$MinimumFreeMiB = 20480,
  [datetime]$NowUtc = [datetime]::UtcNow
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$comparison = [StringComparison]::OrdinalIgnoreCase

function Resolve-MIRDevelopmentHealthRepoRoot {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Candidate)
  if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '../../..' }
  if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) { throw "Repository root is absent: $Candidate" }
  $resolved = (Resolve-Path -LiteralPath $Candidate).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $gitRoot = @(& git -C $resolved rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -ne 0 -or $gitRoot.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$gitRoot[0])) { throw "Repository root is not a readable Git worktree: $resolved" }
  $canonical = (Resolve-Path -LiteralPath ([string]$gitRoot[0])).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  if (-not $canonical.Equals($resolved, $comparison)) { throw "Repository root must name the Git worktree root, not a descendant: $resolved" }
  return $canonical
}

function Invoke-MIRDevelopmentHealthGit {
  param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string[]]$Arguments)
  $lines = @(& git -C $Repository @Arguments 2>$null)
  return [pscustomobject]@{ succeeded = ($LASTEXITCODE -eq 0); lines = @($lines | ForEach-Object { [string]$_ }) }
}

function Get-MIRDevelopmentHealthAgeDays {
  param([Parameter(Mandatory)][long]$UnixSeconds,[Parameter(Mandatory)][datetime]$Now)
  try { return [Math]::Max(0,[int][Math]::Floor(($Now.ToUniversalTime() - [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds).UtcDateTime).TotalDays)) } catch { return $null }
}

function Get-MIRDevelopmentHealthDirtyState {
  param([Parameter(Mandatory)][string]$Repository,[ValidateRange(1,256)][int]$ExampleLimit=12)
  $status = Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('status','--porcelain=v1','--untracked-files=normal')
  if (-not $status.succeeded) { return [pscustomobject]@{ readable=$false; count=$null; examples=@(); operations=@() } }
  # An index may be byte-clean while Git still waits for a merge/rebase/cherry-pick
  # commit. Check the per-worktree Git directory instead of guessing from porcelain.
  $gitPath=Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('rev-parse','--git-path','MERGE_HEAD')
  $operations=@()
  if($gitPath.succeeded-and$gitPath.lines.Count-eq1){
    $mergePath=if([IO.Path]::IsPathRooted([string]$gitPath.lines[0])){[string]$gitPath.lines[0]}else{Join-Path $Repository ([string]$gitPath.lines[0])}
    $gitStateRoot=Split-Path -Parent ([IO.Path]::GetFullPath($mergePath))
    foreach($name in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','BISECT_LOG')){
      if(Test-Path -LiteralPath (Join-Path $gitStateRoot $name) -PathType Leaf){$operations+=switch($name){'MERGE_HEAD'{'merge'}'CHERRY_PICK_HEAD'{'cherry-pick'}'REVERT_HEAD'{'revert'}'BISECT_LOG'{'bisect'}}}
    }
    foreach($name in @('rebase-merge','rebase-apply')){
      if(Test-Path -LiteralPath (Join-Path $gitStateRoot $name) -PathType Container){$operations+='rebase'}
    }
  }else{$operations+='git-state-unreadable'}
  return [pscustomobject]@{ readable=$true; count=@($status.lines).Count; examples=@($status.lines | Select-Object -First $ExampleLimit); operations=@($operations|Sort-Object -Unique) }
}

function Get-MIRDevelopmentHealthBoundedDirectorySize {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][Diagnostics.Stopwatch]$Stopwatch,
    [ValidateRange(1,60)][int]$MaxSeconds,
    [ValidateRange(1,100000)][int]$MaxEntries
  )
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    return [pscustomobject]@{ path=$Root; exists=$false; bytes=[int64]0; bytes_is_lower_bound=$false; entries=0; complete=$true; limit='absent'; reparse_points_skipped=0; errors=0 }
  }
  $rootItem = Get-Item -LiteralPath $Root -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    return [pscustomobject]@{ path=$Root; exists=$true; bytes=[int64]0; bytes_is_lower_bound=$true; entries=0; complete=$false; limit='root-reparse-point'; reparse_points_skipped=1; errors=0 }
  }
  $pending = [Collections.Generic.Stack[string]]::new();$pending.Push($rootItem.FullName)
  [int64]$bytes=0;$entries=0;$reparsePoints=0;$errors=0;$limit=''
  while($pending.Count -gt 0) {
    if($Stopwatch.Elapsed.TotalSeconds -ge $MaxSeconds){$limit='time-budget';break}
    $directory=$pending.Pop()
    try {
      foreach($childPath in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
        if($Stopwatch.Elapsed.TotalSeconds -ge $MaxSeconds){$limit='time-budget';break}
        $entries++;if($entries -gt $MaxEntries){$limit='entry-budget';break}
        try {
          $child=Get-Item -LiteralPath $childPath -Force
          if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){$reparsePoints++;continue}
          if($child.PSIsContainer){$pending.Push($child.FullName)}elseif($child -is [IO.FileInfo]){$bytes+=[int64]$child.Length}
        } catch {$errors++}
      }
    } catch {$errors++}
    if(-not[string]::IsNullOrWhiteSpace($limit)){break}
  }
  # Unreadable or disappearing entries make the sum incomplete even when the
  # time and entry budgets were not exhausted. Never report that lower bound
  # as proof that the directory is within its disk budget.
  if([string]::IsNullOrWhiteSpace($limit)-and$errors-gt0){$limit='read-errors'}
  $complete=[string]::IsNullOrWhiteSpace($limit)
  return [pscustomobject]@{ path=$rootItem.FullName; exists=$true; bytes=$bytes; bytes_is_lower_bound=(-not$complete); entries=$entries; complete=$complete; limit=if($complete){'none'}else{$limit}; reparse_points_skipped=$reparsePoints; errors=$errors }
}

function Get-MIRDevelopmentHealthWorktrees {
  param(
    [Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$CurrentRoot,
    [ValidateRange(1,128)][int]$Limit,[ValidateRange(1,3650)][int]$OldDays,[Parameter(Mandatory)][datetime]$Now,[bool]$IncludeUniqueCommitCounts = $true
  )
  $listed=Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('worktree','list','--porcelain')
  if(-not$listed.succeeded){return [pscustomobject]@{readable=$false;truncated=$false;rows=@()}}
  $records=[Collections.Generic.List[object]]::new();$current=$null
  foreach($line in @($listed.lines)+@('')) {
    if([string]::IsNullOrWhiteSpace($line)){if($null-ne$current){$records.Add([pscustomobject]$current);$current=$null};continue}
    if($line.StartsWith('worktree ')){if($null-ne$current){$records.Add([pscustomobject]$current)};$current=[ordered]@{path=$line.Substring(9);head='';branch='';detached=$false;prunable=$false}}
    elseif($null-ne$current-and$line.StartsWith('HEAD ')){$current.head=$line.Substring(5)}
    elseif($null-ne$current-and$line.StartsWith('branch ')){$current.branch=$line.Substring(7).Replace('refs/heads/','')}
    elseif($null-ne$current-and$line-eq'detached'){$current.detached=$true}
    elseif($null-ne$current-and$line.StartsWith('prunable')){$current.prunable=$true}
  }
  $rows=[Collections.Generic.List[object]]::new();$truncated=$records.Count-gt$Limit
  foreach($record in @($records|Select-Object -First $Limit)) {
    $exists=Test-Path -LiteralPath $record.path -PathType Container
    $resolvedPath=if($exists){(Resolve-Path -LiteralPath $record.path).Path.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}else{$record.path}
    $isCurrent=$exists-and$resolvedPath.Equals($CurrentRoot,$comparison)
    $dirty=if($exists){Get-MIRDevelopmentHealthDirtyState -Repository $resolvedPath}else{[pscustomobject]@{readable=$false;count=$null;examples=@();operations=@()}}
    $lastCommit=if($exists){Invoke-MIRDevelopmentHealthGit -Repository $resolvedPath -Arguments @('log','-1','--format=%ct')}else{$null}
    $commitSeconds=if($null-ne$lastCommit-and$lastCommit.succeeded-and$lastCommit.lines.Count-eq1-and$lastCommit.lines[0]-match'^\d+$'){[long]$lastCommit.lines[0]}else{$null}
    $ageDays=if($null-ne$commitSeconds){Get-MIRDevelopmentHealthAgeDays -UnixSeconds $commitSeconds -Now $Now}else{$null}
    # A fresh worktree can be checked out at an old commit. Its per-worktree
    # .git file is created by `git worktree add`, so use that age for cleanup
    # review instead of treating the commit date as the worktree's age.
    $worktreeGit=if($exists){Get-Item -LiteralPath (Join-Path $resolvedPath '.git') -Force -ErrorAction SilentlyContinue}else{$null}
    $worktreeAgeDays=if($null-ne$worktreeGit){[Math]::Max(0,[int][Math]::Floor(($Now.ToUniversalTime()-$worktreeGit.CreationTimeUtc).TotalDays))}else{$null}
    $unique=if($exists-and$IncludeUniqueCommitCounts){Invoke-MIRDevelopmentHealthGit -Repository $resolvedPath -Arguments @('rev-list','--count','HEAD','--not','--remotes')}else{$null}
    $uniqueCount=if($null-ne$unique-and$unique.succeeded-and$unique.lines.Count-eq1-and$unique.lines[0]-match'^\d+$'){[int]$unique.lines[0]}else{$null}
    $rows.Add([pscustomobject][ordered]@{
      path=$record.path;current=$isCurrent;exists=$exists;head=$record.head;branch=$record.branch;detached=[bool]$record.detached;prunable=[bool]$record.prunable;dirty=$dirty;last_commit_age_days=$ageDays;worktree_age_days=$worktreeAgeDays;unique_commit_count=$uniqueCount
      review_needed=(-not$isCurrent)-and((-not$exists)-or(-not$dirty.readable)-or[bool]$record.prunable-or@($dirty.operations).Count-gt0-or($null-ne$worktreeAgeDays-and$worktreeAgeDays-ge$OldDays))
      preservation=if((-not$exists)-or(-not$dirty.readable)){'preserve-unreadable-worktree'}elseif(@($dirty.operations).Count-gt0){'preserve-in-progress-git-operation'}elseif($dirty.count-gt0){'preserve-dirty-worktree'}elseif($null-ne$uniqueCount-and$uniqueCount-gt0){'preserve-unique-commits'}elseif(-not$IncludeUniqueCommitCounts){'unique-commits-not-scanned'}else{'review-before-any-removal'}
    })
  }
  return [pscustomobject]@{readable=$true;truncated=$truncated;rows=@($rows)}
}

function Get-MIRDevelopmentHealthBranches {
  param(
    [Parameter(Mandatory)][string]$Repository,[string]$CurrentBranch,
    [ValidateRange(1,512)][int]$Limit,[ValidateRange(1,3650)][int]$OldDays,[Parameter(Mandatory)][datetime]$Now,[bool]$IncludeUniqueCommitCounts = $true
  )
  $listed=Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('for-each-ref','--format=%(refname:short)%09%(upstream:short)%09%(committerdate:unix)','refs/heads')
  if(-not$listed.succeeded){return [pscustomobject]@{readable=$false;truncated=$false;rows=@()}}
  $truncated=$listed.lines.Count-gt$Limit;$rows=[Collections.Generic.List[object]]::new()
  foreach($line in @($listed.lines|Select-Object -First $Limit)) {
    $parts=@($line-split"`t",3);if($parts.Count-ne3){continue}
    $name=[string]$parts[0];$upstream=[string]$parts[1];$seconds=if($parts[2]-match'^\d+$'){[long]$parts[2]}else{$null}
    $ageDays=if($null-ne$seconds){Get-MIRDevelopmentHealthAgeDays -UnixSeconds $seconds -Now $Now}else{$null}
    $unique=if($IncludeUniqueCommitCounts){Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('rev-list','--count',$name,'--not','--remotes')}else{$null}
    $uniqueCount=if($null-ne$unique-and$unique.succeeded-and$unique.lines.Count-eq1-and$unique.lines[0]-match'^\d+$'){[int]$unique.lines[0]}else{$null}
    $isCurrent=(-not[string]::IsNullOrWhiteSpace($CurrentBranch))-and$name-ceq$CurrentBranch
    $rows.Add([pscustomobject][ordered]@{
      name=$name;current=$isCurrent;upstream=$upstream;last_commit_age_days=$ageDays;unique_commit_count=$uniqueCount
      # A new task branch normally has no upstream until its first push. Give
      # it a short grace period, then require an explicit cleanup disposition.
      review_needed=(-not$isCurrent)-and($null-ne$ageDays)-and(($ageDays-ge$OldDays)-or([string]::IsNullOrWhiteSpace($upstream)-and$ageDays-ge7))
      preservation=if($null-ne$uniqueCount-and$uniqueCount-gt0){'preserve-unique-commits'}elseif(-not$IncludeUniqueCommitCounts){'unique-commits-not-scanned'}else{'review-before-any-deletion'}
    })
  }
  return [pscustomobject]@{readable=$true;truncated=$truncated;rows=@($rows)}
}

function Get-MIRDevelopmentHealthCurrentBranch {
  param([Parameter(Mandatory)][string]$Repository)
  $branch=Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('symbolic-ref','--quiet','--short','HEAD')
  if($branch.succeeded-and$branch.lines.Count-eq1){return [string]$branch.lines[0]};return ''
}

function Get-MIRDevelopmentHealthUpstream {
  param([Parameter(Mandatory)][string]$Repository)
  $upstream=Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('rev-parse','--abbrev-ref','--symbolic-full-name','@{upstream}')
  if(-not$upstream.succeeded-or$upstream.lines.Count-ne1){return [pscustomobject]@{configured=$false;name='';ahead=$null;behind=$null}}
  $name=[string]$upstream.lines[0];$counts=Invoke-MIRDevelopmentHealthGit -Repository $Repository -Arguments @('rev-list','--left-right','--count',"$name...HEAD")
  $ahead=$null;$behind=$null
  if($counts.succeeded-and$counts.lines.Count-eq1-and$counts.lines[0]-match'^(\d+)\s+(\d+)$'){$behind=[int]$Matches[1];$ahead=[int]$Matches[2]}
  return [pscustomobject]@{configured=$true;name=$name;ahead=$ahead;behind=$behind}
}

if($Mode-eq'Hook'){
  # Hooks sample only; they cannot become another disk-growth source or block Git/GitHub work.
  $MaxScanSeconds=[Math]::Min($MaxScanSeconds,4);$MaxEntriesPerRoot=[Math]::Min($MaxEntriesPerRoot,512);$MaxWorktrees=[Math]::Min($MaxWorktrees,8);$MaxBranches=[Math]::Min($MaxBranches,64)
}
$repo=Resolve-MIRDevelopmentHealthRepoRoot -Candidate $RepoRoot;$clock=[Diagnostics.Stopwatch]::StartNew()
$currentBranch=Get-MIRDevelopmentHealthCurrentBranch -Repository $repo;$dirty=Get-MIRDevelopmentHealthDirtyState -Repository $repo;$upstream=Get-MIRDevelopmentHealthUpstream -Repository $repo
$includeUniqueCommitCounts = $Mode -ne 'Hook'
$worktrees=Get-MIRDevelopmentHealthWorktrees -Repository $repo -CurrentRoot $repo -Limit $MaxWorktrees -OldDays $OldWorktreeDays -Now $NowUtc -IncludeUniqueCommitCounts $includeUniqueCommitCounts
$branches=Get-MIRDevelopmentHealthBranches -Repository $repo -CurrentBranch $currentBranch -Limit $MaxBranches -OldDays $OldBranchDays -Now $NowUtc -IncludeUniqueCommitCounts $includeUniqueCommitCounts
$build=Get-MIRDevelopmentHealthBoundedDirectorySize -Root (Join-Path $repo 'build') -Stopwatch $clock -MaxSeconds $MaxScanSeconds -MaxEntries $MaxEntriesPerRoot
$dist=Get-MIRDevelopmentHealthBoundedDirectorySize -Root (Join-Path $repo 'dist') -Stopwatch $clock -MaxSeconds $MaxScanSeconds -MaxEntries $MaxEntriesPerRoot
$drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($repo));$freeMiB=[int][Math]::Floor($drive.AvailableFreeSpace/1MB);$buildMiB=[int][Math]::Ceiling($build.bytes/1MB);$distMiB=[int][Math]::Ceiling($dist.bytes/1MB)
$oldWorktrees=@($worktrees.rows|Where-Object review_needed);$oldBranches=@($branches.rows|Where-Object review_needed);$attention=@()
if($dirty.readable-and$dirty.count-gt0){$attention+="dirty:$($dirty.count)"}
if(@($dirty.operations).Count-gt0){$attention+='git-operation:'+(@($dirty.operations)-join ',')}
if(-not$upstream.configured){$attention+='upstream:missing'}elseif(($null-ne$upstream.ahead-and$upstream.ahead-gt0)-or($null-ne$upstream.behind-and$upstream.behind-gt0)){$attention+="upstream:ahead=$($upstream.ahead),behind=$($upstream.behind)"}
$buildBudgetObservation=if($buildMiB-gt$BuildBudgetMiB){if($build.complete){'over-budget'}else{'over-budget-lower-bound'}}elseif($build.complete){'within-budget'}else{'incomplete-lower-bound'}
$distBudgetObservation=if($distMiB-gt$DistBudgetMiB){if($dist.complete){'over-budget'}else{'over-budget-lower-bound'}}elseif($dist.complete){'within-budget'}else{'incomplete-lower-bound'}
if($buildMiB-gt$BuildBudgetMiB){$attention+="build:$buildMiB-MiB-over-$BuildBudgetMiB"};if(-not$build.complete){$attention+="build-scan:$($build.limit)-lower-bound"}
if($distMiB-gt$DistBudgetMiB){$attention+="dist:$distMiB-MiB-over-$DistBudgetMiB"};if(-not$dist.complete){$attention+="dist-scan:$($dist.limit)-lower-bound"}
if($freeMiB-lt$MinimumFreeMiB){$attention+="free:$freeMiB-MiB-below-$MinimumFreeMiB"}
if($oldWorktrees.Count-gt0){$attention+="worktrees:review-$($oldWorktrees.Count)"};if($oldBranches.Count-gt0){$attention+="branches:review-$($oldBranches.Count)"};if($worktrees.truncated){$attention+='worktrees:truncated'};if($branches.truncated){$attention+='branches:truncated'}
$checkpointReasons = @()
if($dirty.readable-and$dirty.count-gt0){$checkpointReasons+="dirty:$($dirty.count)"}
if(@($dirty.operations).Count-gt0){$checkpointReasons+='git-operation:'+(@($dirty.operations)-join ',')}
if($upstream.configured-and$null-ne$upstream.ahead-and$upstream.ahead-gt0){$checkpointReasons+="upstream-ahead:$($upstream.ahead)"}
if($freeMiB-lt$MinimumFreeMiB){$checkpointReasons+="free:$freeMiB-MiB-below-$MinimumFreeMiB"}
if($buildMiB-gt$BuildBudgetMiB){$checkpointReasons+="build:$buildMiB-MiB-over-$BuildBudgetMiB"}
if($distMiB-gt$DistBudgetMiB){$checkpointReasons+="dist:$distMiB-MiB-over-$DistBudgetMiB"}
if($oldWorktrees.Count-gt0){$checkpointReasons+="worktrees:review-$($oldWorktrees.Count)"}
if($oldBranches.Count-gt0){$checkpointReasons+="branches:review-$($oldBranches.Count)"}
$buildDisplay="$buildMiB-MiB" + $(if($build.bytes_is_lower_bound){'+'}else{''})
$distDisplay="$distMiB-MiB" + $(if($dist.bytes_is_lower_bound){'+'}else{''})
$summaryParts=@("branch=$currentBranch","dirty=$($dirty.count)","git-operation="+$(if(@($dirty.operations).Count-gt0){@($dirty.operations)-join ','}else{'none'}),"build=$buildDisplay","dist=$distDisplay","free=$freeMiB-MiB")
if($attention.Count-gt0){$summaryParts+=('attention='+($attention-join','))}else{$summaryParts+='attention=none'}
$hookMessage='MIR development health (advisory; no files changed): '+($summaryParts-join'; ');if($hookMessage.Length-gt900){$hookMessage=$hookMessage.Substring(0,897)+'...'}
$report=[pscustomobject][ordered]@{
  kind='MIRDevelopmentWorkspaceHealthV1';mode=$Mode.ToLowerInvariant();status=if($attention.Count-gt0){'attention'}else{'within-advisory-budgets'};repository=$repo;observed_at_utc=$NowUtc.ToUniversalTime().ToString('o');side_effects='none-report-only'
  scan_limits=[ordered]@{max_scan_seconds=$MaxScanSeconds;max_entries_per_root=$MaxEntriesPerRoot;max_worktrees=$MaxWorktrees;max_branches=$MaxBranches}
  disk=[ordered]@{free_mib=$freeMiB;minimum_free_mib=$MinimumFreeMiB;build_budget_mib=$BuildBudgetMiB;dist_budget_mib=$DistBudgetMiB;build_budget_observation=$buildBudgetObservation;dist_budget_observation=$distBudgetObservation;build=$build;dist=$dist}
  git=[ordered]@{current_branch=$currentBranch;dirty=$dirty;upstream=$upstream;worktrees=$worktrees;branches=$branches};attention=@($attention)
  checkpoint_required=($checkpointReasons.Count-gt0);checkpoint_reasons=@($checkpointReasons)
  actions=@([pscustomobject]@{kind='checkpoint';command='git status --short';automatic=$false},[pscustomobject]@{kind='worktree-review';command='git worktree list --porcelain';automatic=$false},[pscustomobject]@{kind='branch-review';command='git branch -vv';automatic=$false},[pscustomobject]@{kind='safe-storage-audit';command='.\\tools\\mir.ps1 storage audit --all-worktrees --older-than-days 7';automatic=$false},[pscustomobject]@{kind='safe-storage-clean-after-audit';command='.\\tools\\mir.ps1 storage clean --all-worktrees --older-than-days 7 --apply';automatic=$false})
  hook_message=$hookMessage
}
if($AsJson){$report|ConvertTo-Json -Depth 12 -Compress}else{Write-Output $hookMessage;Write-Output 'Suggested next step: run the named storage audit before any cleanup; review dirty or unique worktrees and branches before any Git removal.'}
