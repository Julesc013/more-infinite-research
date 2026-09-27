# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$checker = Join-Path $repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1'
$hook = Join-Path $repo 'tools/commands/workspace/Invoke-MIRDevelopmentHealthHook.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('mir-development-health-' + [guid]::NewGuid().ToString('N'))
$linked = Join-Path ([IO.Path]::GetTempPath()) ('mir-development-health-linked-' + [guid]::NewGuid().ToString('N'))
$cleanFixture = Join-Path ([IO.Path]::GetTempPath()) ('mir-development-health-clean-' + [guid]::NewGuid().ToString('N'))
$previousAuthorDate = $env:GIT_AUTHOR_DATE
$previousCommitterDate = $env:GIT_COMMITTER_DATE

function Invoke-HealthFixtureGit {
  param([Parameter(Mandatory)][string[]]$Arguments)
  & git -C $fixture @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: git -C $fixture $($Arguments -join ' ')" }
}

function Invoke-HealthNativeHook {
  param([Parameter(Mandatory)][string]$ScriptPath,[Parameter(Mandatory)]$Payload,[string]$CheckerRepoRoot = '')
  $binary = Join-Path $PSHOME 'pwsh.exe'
  if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { $binary = (Get-Command pwsh -ErrorAction Stop).Source }
  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $binary
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $arguments = @('-NoProfile','-File',$ScriptPath,'-Event','Stop')
  if (-not [string]::IsNullOrWhiteSpace($CheckerRepoRoot)) { $arguments += @('-CheckerRepoRoot',$CheckerRepoRoot) }
  foreach ($argument in $arguments) { $null = $psi.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $psi
  if (-not $process.Start()) { throw '[mir-development-health-native-hook-start]' }
  $process.StandardInput.Write(($Payload | ConvertTo-Json -Compress -Depth 8))
  $process.StandardInput.Close()
  if (-not $process.WaitForExit(15000)) { $process.Kill($true); throw '[mir-development-health-native-hook-timeout]' }
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  if ($process.ExitCode -ne 0) { throw "[mir-development-health-native-hook-exit] $stderr" }
  return @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

try {
  if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) { throw '[mir-development-health-checker-missing]' }
  if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) { throw '[mir-development-health-hook-missing]' }
  $sourceRoot = (Resolve-Path -LiteralPath $repo).Path.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  $defaultHookReport = (& $checker -Mode Hook -AsJson | ConvertFrom-Json -Depth 16)
  if ([string]$defaultHookReport.repository -cne $sourceRoot -or [string]$defaultHookReport.mode -cne 'hook' -or [string]$defaultHookReport.side_effects -cne 'none-report-only') { throw '[mir-development-health-default-root-hook]' }
  New-Item -ItemType Directory -Path $fixture -Force | Out-Null
  Invoke-HealthFixtureGit -Arguments @('init','--quiet')
  Invoke-HealthFixtureGit -Arguments @('config','user.email','mir-health@example.invalid')
  Invoke-HealthFixtureGit -Arguments @('config','user.name','MIR development health test')
  Invoke-HealthFixtureGit -Arguments @('config','core.autocrlf','false')
  [IO.File]::WriteAllText((Join-Path $fixture '.gitignore'),"/build/`n/dist/`n",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $fixture 'tracked.txt'),'baseline',[Text.UTF8Encoding]::new($false))
  Invoke-HealthFixtureGit -Arguments @('add','--','.gitignore','tracked.txt')
  Invoke-HealthFixtureGit -Arguments @('commit','--quiet','-m','fixture: baseline')
  Invoke-HealthFixtureGit -Arguments @('branch','-M','main')

  $env:GIT_AUTHOR_DATE = '2024-01-01T00:00:00Z'
  $env:GIT_COMMITTER_DATE = '2024-01-01T00:00:00Z'
  Invoke-HealthFixtureGit -Arguments @('checkout','--quiet','-b','health-old')
  [IO.File]::WriteAllText((Join-Path $fixture 'old.txt'),'old branch',[Text.UTF8Encoding]::new($false))
  Invoke-HealthFixtureGit -Arguments @('add','--','old.txt')
  Invoke-HealthFixtureGit -Arguments @('commit','--quiet','-m','fixture: retained old branch')
  Remove-Item Env:GIT_AUTHOR_DATE
  Remove-Item Env:GIT_COMMITTER_DATE
  Invoke-HealthFixtureGit -Arguments @('checkout','--quiet','main')

  [IO.File]::WriteAllText((Join-Path $fixture 'tracked.txt'),'dirty current worktree',[Text.UTF8Encoding]::new($false))
  foreach ($leaf in @('one.bin','two.bin','three.bin')) {
    $path = Join-Path $fixture ("build/scan/$leaf")
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path,$leaf,[Text.UTF8Encoding]::new($false))
  }
  $distPath = Join-Path $fixture 'dist/preview.bin'
  New-Item -ItemType Directory -Path (Split-Path -Parent $distPath) -Force | Out-Null
  [IO.File]::WriteAllText($distPath,'preview',[Text.UTF8Encoding]::new($false))
  Invoke-HealthFixtureGit -Arguments @('worktree','add','--quiet','-b','health-linked',$linked,'main')
  [IO.File]::WriteAllText((Join-Path $linked 'linked-uncommitted.txt'),'preserve me',[Text.UTF8Encoding]::new($false))
  $fixtureToolRoot = Join-Path $fixture 'tools/commands/workspace'
  New-Item -ItemType Directory -Path $fixtureToolRoot -Force | Out-Null
  Copy-Item -LiteralPath $checker -Destination (Join-Path $fixtureToolRoot 'Test-MIRDevelopmentHealth.ps1')
  Copy-Item -LiteralPath $hook -Destination (Join-Path $fixtureToolRoot 'Invoke-MIRDevelopmentHealthHook.ps1')
  $fixtureHook = Join-Path $fixtureToolRoot 'Invoke-MIRDevelopmentHealthHook.ps1'

  New-Item -ItemType Directory -Path $cleanFixture -Force | Out-Null
  & git -C $cleanFixture init --quiet
  if ($LASTEXITCODE -ne 0) { throw '[mir-development-health-clean-fixture-init]' }
  & git -C $cleanFixture config user.email 'mir-health@example.invalid'
  & git -C $cleanFixture config user.name 'MIR development health test'
  & git -C $cleanFixture config core.autocrlf false
  '/build/' | Set-Content -LiteralPath (Join-Path $cleanFixture '.gitignore') -NoNewline
  & git -C $cleanFixture add -- .gitignore
  & git -C $cleanFixture commit --quiet -m 'fixture: clean partial scan'
  if ($LASTEXITCODE -ne 0) { throw '[mir-development-health-clean-fixture-commit]' }
  & git -C $cleanFixture branch -M main
  $partialRoot = Join-Path $cleanFixture 'build/partial'
  New-Item -ItemType Directory -Path $partialRoot -Force | Out-Null
  foreach ($number in 1..513) { [IO.File]::WriteAllText((Join-Path $partialRoot ("$number.bin")),"x",[Text.UTF8Encoding]::new($false)) }

  $trackedBefore = [IO.File]::ReadAllText((Join-Path $fixture 'tracked.txt'))
  $linkedBefore = [IO.File]::ReadAllText((Join-Path $linked 'linked-uncommitted.txt'))
  $report = (& $checker -RepoRoot $fixture -AsJson -MaxEntriesPerRoot 2 -MaxScanSeconds 10 -MaxWorktrees 4 -MaxBranches 8 -OldWorktreeDays 7 -OldBranchDays 7 -BuildBudgetMiB 0 -NowUtc ([datetime]'2026-09-27T00:00:00Z') | ConvertFrom-Json -Depth 16)
  if ([string]$report.kind -cne 'MIRDevelopmentWorkspaceHealthV1' -or [string]$report.side_effects -cne 'none-report-only' -or -not [bool]$report.checkpoint_required -or @($report.checkpoint_reasons | Where-Object { $_ -match '^dirty:' }).Count -ne 1) { throw '[mir-development-health-report-shape]' }
  if ($report.git.dirty.count -lt 1) { throw '[mir-development-health-dirty-current]' }
  if ([bool]$report.disk.build.complete -or -not [bool]$report.disk.build.bytes_is_lower_bound -or [string]$report.disk.build.limit -cne 'entry-budget' -or [string]$report.disk.build_budget_observation -cne 'over-budget-lower-bound') { throw '[mir-development-health-bounded-build]' }
  $linkedIdentity = (Resolve-Path -LiteralPath $linked).Path.Replace('\','/').TrimEnd('/')
  $linkedRow = @($report.git.worktrees.rows | Where-Object { ([string]$_.path).Replace('\','/').TrimEnd('/') -ceq $linkedIdentity })
  if ($linkedRow.Count -ne 1 -or $linkedRow[0].dirty.count -lt 1 -or [string]$linkedRow[0].preservation -cne 'preserve-dirty-worktree') { throw '[mir-development-health-linked-preservation]' }
  $oldBranch = @($report.git.branches.rows | Where-Object name -ceq 'health-old')
  if ($oldBranch.Count -ne 1 -or -not [bool]$oldBranch[0].review_needed -or [string]$oldBranch[0].preservation -cne 'preserve-unique-commits') { throw '[mir-development-health-old-branch]' }
  if (@($report.actions | Where-Object { $_.command -match 'Remove-Item|git clean|worktree remove|branch -D' }).Count -ne 0) { throw '[mir-development-health-unsafe-action]' }
  if (@($report.actions | Where-Object kind -ceq 'safe-storage-audit').Count -ne 1) { throw '[mir-development-health-named-cleanup-authority]' }
  $cleanAction = @($report.actions | Where-Object kind -ceq 'safe-storage-clean-after-audit')
  if ($cleanAction.Count -ne 1 -or [string]$cleanAction[0].command -notmatch 'storage clean .* --apply$' -or [bool]$cleanAction[0].automatic) { throw '[mir-development-health-explicit-cleanup]' }
  if ([IO.File]::ReadAllText((Join-Path $fixture 'tracked.txt')) -cne $trackedBefore -or [IO.File]::ReadAllText((Join-Path $linked 'linked-uncommitted.txt')) -cne $linkedBefore) { throw '[mir-development-health-report-mutated-worktree]' }

  $hookReport = (& $checker -RepoRoot $fixture -Mode Hook -AsJson -MaxScanSeconds 60 -MaxEntriesPerRoot 100000 -MaxWorktrees 128 -MaxBranches 512 -NowUtc ([datetime]'2026-09-27T00:00:00Z') | ConvertFrom-Json -Depth 16)
  if ($hookReport.scan_limits.max_scan_seconds -gt 4 -or $hookReport.scan_limits.max_entries_per_root -gt 512 -or $hookReport.scan_limits.max_worktrees -gt 8 -or $hookReport.scan_limits.max_branches -gt 64) { throw '[mir-development-health-hook-budget]' }
  if ($hookReport.hook_message.Length -gt 900 -or [string]$hookReport.side_effects -cne 'none-report-only') { throw '[mir-development-health-hook-message]' }
  if (@($hookReport.git.branches.rows | Where-Object { $null -ne $_.unique_commit_count }).Count -ne 0) { throw '[mir-development-health-hook-avoids-branch-graph-walk]' }
  if ([string]$hookReport.disk.build_budget_observation -eq 'within-budget' -and -not [bool]$hookReport.disk.build.complete) { throw '[mir-development-health-partial-budget-claim]' }

  $firstHookOutput = @(Invoke-HealthNativeHook -ScriptPath $fixtureHook -Payload @{ session_id='fixture'; hook_event_name='Stop'; stop_hook_active=$false })
  if ($firstHookOutput.Count -ne 1) { throw '[mir-development-health-hook-output-count]' }
  $firstHook = $firstHookOutput[0] | ConvertFrom-Json -Depth 8
  if ([string]$firstHook.decision -cne 'block' -or [string]$firstHook.reason -notmatch 'Checkpoint or choose the named corrective command' -or @($firstHook.PSObject.Properties.Name | Where-Object { $_ -ceq 'continue' }).Count -ne 0) { throw '[mir-development-health-hook-first-block]' }
  $repeatHookOutput = @(Invoke-HealthNativeHook -ScriptPath $fixtureHook -Payload @{ session_id='fixture'; hook_event_name='Stop'; stop_hook_active=$true })
  if ($repeatHookOutput.Count -ne 1) { throw '[mir-development-health-hook-repeat-output-count]' }
  $repeatHook = $repeatHookOutput[0] | ConvertFrom-Json -Depth 8
  if (@($repeatHook.PSObject.Properties.Name | Where-Object { $_ -ceq 'decision' -or $_ -ceq 'continue' }).Count -ne 0 -or [string]$repeatHook.systemMessage -notmatch 'already active; no further checkpoint') { throw '[mir-development-health-hook-loop-guard]' }
  $cleanHealth = (& $checker -RepoRoot $cleanFixture -Mode Hook -AsJson | ConvertFrom-Json -Depth 16)
  if ([bool]$cleanHealth.checkpoint_required -or [bool]$cleanHealth.disk.build.complete -or [string]$cleanHealth.disk.build_budget_observation -cne 'incomplete-lower-bound') { throw '[mir-development-health-clean-partial-state]' }
  $cleanHookOutput = @(Invoke-HealthNativeHook -ScriptPath $fixtureHook -CheckerRepoRoot $cleanFixture -Payload @{ session_id='clean'; hook_event_name='Stop'; stop_hook_active=$false })
  if ($cleanHookOutput.Count -ne 1) { throw '[mir-development-health-clean-partial-output]' }
  $cleanHook = $cleanHookOutput[0] | ConvertFrom-Json -Depth 8
  if (@($cleanHook.PSObject.Properties.Name | Where-Object { $_ -ceq 'decision' -or $_ -ceq 'continue' }).Count -ne 0 -or [string]$cleanHook.systemMessage -notmatch 'No workspace checkpoint action is required') { throw '[mir-development-health-clean-partial-pass]' }
  Invoke-HealthFixtureGit -Arguments @('status','--short') | Out-Null
  Invoke-HealthFixtureGit -Arguments @('branch','--show-current') | Out-Null
  if ([IO.File]::ReadAllText((Join-Path $fixture 'tracked.txt')) -cne $trackedBefore -or [IO.File]::ReadAllText((Join-Path $linked 'linked-uncommitted.txt')) -cne $linkedBefore) { throw '[mir-development-health-hook-mutated-worktree]' }

  $descendantRejected = $false
  try { & $checker -RepoRoot (Join-Path $fixture 'build') -AsJson | Out-Null } catch { $descendantRejected = $_.Exception.Message -match 'Git worktree root' }
  if (-not $descendantRejected) { throw '[mir-development-health-root-boundary]' }

  [pscustomobject]@{ status='passed'; assertions=36; fixture=$fixture; hook_budget_seconds=[int]$hookReport.scan_limits.max_scan_seconds; mutations='none' } | ConvertTo-Json -Compress
} finally {
  if ($null -ne $previousAuthorDate) { $env:GIT_AUTHOR_DATE = $previousAuthorDate } else { Remove-Item Env:GIT_AUTHOR_DATE -ErrorAction SilentlyContinue }
  if ($null -ne $previousCommitterDate) { $env:GIT_COMMITTER_DATE = $previousCommitterDate } else { Remove-Item Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $linked -PathType Container) { & git -C $fixture worktree remove --force $linked 2>$null }
  if (Test-Path -LiteralPath $fixture -PathType Container) { Remove-Item -LiteralPath $fixture -Force -Recurse }
  if (Test-Path -LiteralPath $linked -PathType Container) { Remove-Item -LiteralPath $linked -Force -Recurse }
  if (Test-Path -LiteralPath $cleanFixture -PathType Container) { Remove-Item -LiteralPath $cleanFixture -Force -Recurse }
}
