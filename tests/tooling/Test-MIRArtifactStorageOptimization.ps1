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
  foreach($path in @($library,(Join-Path $staleRun 'mods'),(Join-Path $recentRun 'mods'),(Join-Path $leasedRun 'mods'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  $source=Join-Path $library 'example_1.0.0.zip'
  [IO.File]::WriteAllText($source,'immutable archive',[Text.UTF8Encoding]::new($false))
  foreach($run in @($staleRun,$recentRun,$leasedRun)){
    [IO.File]::Copy($source,(Join-Path $run 'mods/example_1.0.0.zip'))
    [IO.File]::WriteAllText((Join-Path $run 'result.json'),'{"status":"passed"}',[Text.UTF8Encoding]::new($false))
  }
  [IO.File]::WriteAllText((Join-Path $leasedRun 'mir-immutable-input-lease.json'),'{}',[Text.UTF8Encoding]::new($false))
  $stale=[DateTime]::UtcNow.AddDays(-10)
  foreach($run in @($staleRun,$leasedRun)){
    Get-ChildItem -LiteralPath $run -Force -Recurse|ForEach-Object{$_.LastWriteTimeUtc=$stale}
    (Get-Item -LiteralPath $run).LastWriteTimeUtc=$stale
  }

  $preview=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -PassThru)
  if($preview.Count-ne1-or[string]$preview[0].status-cne'eligible'-or[string]$preview[0].run-cne$staleRun){throw '[mir-storage-opt-preview]'}
  $beforeHash=Get-MIRImmutableInputSha256 -Path (Join-Path $staleRun 'mods/example_1.0.0.zip')
  $applied=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -Apply -Confirm:$false -PassThru)
  if($applied.Count-ne1-or[string]$applied[0].status-cne'relinked'){throw '[mir-storage-opt-apply]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-cne(Get-MIRImmutableInputFileIdentity -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-file-identity]'}
  if((Get-MIRImmutableInputSha256 -Path (Join-Path $staleRun 'mods/example_1.0.0.zip'))-cne$beforeHash){throw '[mir-storage-opt-content]'}
  if(-not(Test-Path -LiteralPath (Join-Path $staleRun 'result.json') -PathType Leaf)){throw '[mir-storage-opt-result-retention]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-ceq(Get-MIRImmutableInputFileIdentity -Path (Join-Path $recentRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-recent-isolation]'}
  if((Get-MIRImmutableInputFileIdentity -Path $source)-ceq(Get-MIRImmutableInputFileIdentity -Path (Join-Path $leasedRun 'mods/example_1.0.0.zip'))){throw '[mir-storage-opt-lease-isolation]'}
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
  [IO.File]::WriteAllText((Join-Path $linkedRun 'result.json'),'{}',[Text.UTF8Encoding]::new($false))
  Get-ChildItem -LiteralPath $linkedRun -Force -Recurse|ForEach-Object{$_.LastWriteTimeUtc=$stale}
  (Get-Item -LiteralPath $linkedRun).LastWriteTimeUtc=$stale
  $linkedPreview=@(& $command -RepoRoot $linked -OlderThanDays 7 -PassThru)
  if($linkedPreview.Count-ne1-or[string]$linkedPreview[0].source-cne$defaultSource){throw '[mir-storage-opt-linked-default-library]'}
  & git -C $primary worktree remove --force $linked
  if($LASTEXITCODE-ne0){throw '[mir-storage-opt-linked-remove]'}

  [pscustomobject]@{status='passed';test_id='static.mir-artifact-storage-optimization';relinked=1;content_preserved=$true;result_preserved=$true;recent_run_untouched=$true;leased_run_untouched=$true;linked_worktree_defaults=$true}|ConvertTo-Json -Depth 5
}finally{
  if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
