# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$command=Join-Path $repo 'tools/commands/workspace/Optimize-MIRArtifactStorage.ps1'
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('mir-storage-opt-'+[guid]::NewGuid().ToString('N'))

try{
  $library=Join-Path $fixture 'library'
  $staleRun=Join-Path $fixture 'repo/build/tests/suite/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  $recentRun=Join-Path $fixture 'repo/build/tests/suite/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  $leasedRun=Join-Path $fixture 'repo/build/tests/suite/dddddddddddddddddddddddddddddddd'
  $activeRun=Join-Path $fixture 'repo/build/tests/suite/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
  foreach($path in @($library,(Join-Path $staleRun 'mods'),(Join-Path $recentRun 'mods'),(Join-Path $leasedRun 'mods'),(Join-Path $activeRun 'mods'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  $source=Join-Path $library 'example_1.0.0.zip'
  [IO.File]::WriteAllText($source,'immutable archive',[Text.UTF8Encoding]::new($false))
  foreach($run in @($staleRun,$recentRun,$leasedRun,$activeRun)){
    [IO.File]::Copy($source,(Join-Path $run 'mods/example_1.0.0.zip'))
    [IO.File]::WriteAllText((Join-Path $run 'result.json'),'{"status":"passed"}',[Text.UTF8Encoding]::new($false))
  }
  [IO.File]::WriteAllText((Join-Path $staleRun 'result.json'),'{"status":"observed-not-admitted"}',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $leasedRun 'mir-immutable-input-lease.json'),'{}',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $activeRun 'result.json'),'{"status":"running"}',[Text.UTF8Encoding]::new($false))
  $stale=[DateTime]::UtcNow.AddDays(-10)
  foreach($run in @($staleRun,$leasedRun,$activeRun)){
    Get-ChildItem -LiteralPath $run -Force -Recurse|ForEach-Object{$_.LastWriteTimeUtc=$stale}
    (Get-Item -LiteralPath $run).LastWriteTimeUtc=$stale
  }

  $preview=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -PassThru)
  if($preview.Count-ne1-or[string]$preview[0].status-cne'eligible'-or[string]$preview[0].run-cne$staleRun){throw '[mir-storage-opt-preview]'}
  $scanRepo=Join-Path $fixture 'scan-repo'
  $scanLibrary=Join-Path $fixture 'scan-library'
  $noiseLeaf=Join-Path $scanRepo 'build/tests/noise/a/b'
  [IO.Directory]::CreateDirectory($noiseLeaf)|Out-Null
  [IO.Directory]::CreateDirectory($scanLibrary)|Out-Null
  [IO.File]::WriteAllText((Join-Path $noiseLeaf 'noise.txt'),'not an archive',[Text.UTF8Encoding]::new($false))
  $scanBounded=$false
  try { & $command -RepoRoot $scanRepo -LibraryRoot $scanLibrary -OlderThanDays 7 -MaxScannedEntries 2 -PassThru | Out-Null } catch { $scanBounded=$_.Exception.Message -match 'bounded 2-entry scan' }
  if(-not$scanBounded){throw '[mir-storage-opt-scan-bound]'}
  $beforeHash=Get-MIRImmutableInputSha256 -Path (Join-Path $staleRun 'mods/example_1.0.0.zip')
  $beforeIdentity=Get-MIRImmutableInputFileIdentity -Path (Join-Path $staleRun 'mods/example_1.0.0.zip')
  $sourceHash=Get-MIRImmutableInputSha256 -Path $source
  $probe=Join-Path $fixture 'post-replacement-probe.txt'
  $mutationHook={
    param($row)
    [IO.File]::WriteAllText($probe,'reached',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText([string]$row.source,'mutated',[Text.UTF8Encoding]::new($false))
  }.GetNewClosure()
  $mutationRejected=$false
  try { & $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -Apply -Confirm:$false -AfterReplacementTestHook $mutationHook -PassThru | Out-Null } catch { $mutationRejected=$true }
  if(-not$mutationRejected-or-not(Test-Path -LiteralPath $probe -PathType Leaf)){throw '[mir-storage-opt-mutation-probe]'}
  if((Get-MIRImmutableInputSha256 -Path $source)-cne$sourceHash){throw '[mir-storage-opt-source-mutation]'}
  if((Get-MIRImmutableInputSha256 -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))-cne$beforeHash-or(Get-MIRImmutableInputFileIdentity -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))-cne$beforeIdentity){throw '[mir-storage-opt-rollback]'}

  $externalLibrary=Join-Path $fixture 'external-library'
  $libraryBackup=Join-Path $fixture 'library-backup'
  [IO.Directory]::CreateDirectory($externalLibrary)|Out-Null
  [IO.File]::Copy($source,(Join-Path $externalLibrary 'example_1.0.0.zip'))
  $reparseHook={
    param($plan)
    Move-Item -LiteralPath $library -Destination $libraryBackup
    New-Item -ItemType Junction -Path $library -Target $externalLibrary -ErrorAction Stop|Out-Null
  }.GetNewClosure()
  $reparseRejected=$false
  try {
    & $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -Apply -Confirm:$false -BeforeApplyTestHook $reparseHook -PassThru|Out-Null
  } catch {
    $reparseRejected=$_.Exception.Message -match 'eligibility changed after planning'
  } finally {
    if(Test-Path -LiteralPath $library){
      $libraryItem=Get-Item -LiteralPath $library -Force
      if(($libraryItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){Remove-Item -LiteralPath $library -Force}
    }
    if(Test-Path -LiteralPath $libraryBackup -PathType Container){Move-Item -LiteralPath $libraryBackup -Destination $library}
  }
  if(-not$reparseRejected){throw '[mir-storage-opt-reparse-recheck]'}
  if((Get-MIRImmutableInputSha256 -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))-cne$beforeHash-or(Get-MIRImmutableInputFileIdentity -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))-cne$beforeIdentity){throw '[mir-storage-opt-reparse-target-isolation]'}

  $applied=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -Apply -Confirm:$false -PassThru)
  if($applied.Count-ne1-or[string]$applied[0].status-cne'relinked'){throw '[mir-storage-opt-apply]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-cne(Get-MIRImmutableInputFileIdentity -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-file-identity]'}
  if((Get-MIRImmutableInputSha256 -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))-cne$beforeHash){throw '[mir-storage-opt-content]'}
  if(-not(Test-Path -LiteralPath (Join-Path $staleRun 'result.json') -PathType Leaf)){throw '[mir-storage-opt-result-retention]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-ceq(Get-MIRImmutableInputFileIdentity -Path (Join-Path $recentRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-recent-isolation]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-ceq(Get-MIRImmutableInputFileIdentity -Path (Join-Path $leasedRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-lease-isolation]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-ceq(Get-MIRImmutableInputFileIdentity -Path (Join-Path $activeRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-active-state-isolation]'}
  if(@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -PassThru).Count-ne0){throw '[mir-storage-opt-fixed-point]'}
  & $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 | Out-Null

  $project=Join-Path $fixture 'linked-worktree-project'
  $primary=Join-Path $project 'primary'
  $linked=Join-Path $project 'worktrees/worker'
  [IO.Directory]::CreateDirectory($primary)|Out-Null
  & git -C $primary init --quiet
  if($LASTEXITCODE-ne0){throw '[mir-storage-opt-linked-init]'}
  [IO.File]::WriteAllText((Join-Path $primary 'seed.txt'),'seed',[Text.UTF8Encoding]::new($false))
  & git -C $primary add seed.txt
  & git -C $primary -c user.name='MIR test' -c user.email='mir-test@example.invalid' commit --quiet -m seed
  if($LASTEXITCODE-ne0){throw '[mir-storage-opt-linked-commit]'}
  & git -C $primary worktree add --quiet -b storage-fixture $linked
  if($LASTEXITCODE-ne0){throw '[mir-storage-opt-linked-add]'}
  $default20=Join-Path $project 'testmods/2.0'
  $default21=Join-Path $project 'testmods/2.1'
  $linkedRun=Join-Path $linked 'build/tests/suite/cccccccccccccccccccccccccccccccc'
  foreach($path in @($default20,$default21,(Join-Path $linkedRun 'mods'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  $defaultSource=Join-Path $default20 'default_1.0.0.zip'
  [IO.File]::WriteAllText($defaultSource,'default archive',[Text.UTF8Encoding]::new($false))
  [IO.File]::Copy($defaultSource,(Join-Path $linkedRun 'mods/default_1.0.0.zip'))
  [IO.File]::WriteAllText((Join-Path $linkedRun 'result.json'),'{"status":"passed"}',[Text.UTF8Encoding]::new($false))
  Get-ChildItem -LiteralPath $linkedRun -Force -Recurse|ForEach-Object{$_.LastWriteTimeUtc=$stale}
  (Get-Item -LiteralPath $linkedRun).LastWriteTimeUtc=$stale
  $linkedPreview=@(& $command -RepoRoot $linked -OlderThanDays 7 -PassThru)
  if($linkedPreview.Count-ne1-or[string]$linkedPreview[0].source-cne$defaultSource){throw '[mir-storage-opt-linked-default-library]'}
  & git -C $primary worktree remove --force $linked
  if($LASTEXITCODE-ne0){throw '[mir-storage-opt-linked-remove]'}

  [pscustomobject]@{status='passed';test_id='static.mir-artifact-storage-optimization';relinked=1;content_preserved=$true;result_preserved=$true;qualified_terminal_status=$true;mutation_blocked=$true;rollback_proved=$true;scan_bounded=$true;reparse_rechecked=$true;recent_run_untouched=$true;leased_run_untouched=$true;nonterminal_run_untouched=$true;linked_worktree_defaults=$true}|ConvertTo-Json -Depth 5
}finally{
  if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
