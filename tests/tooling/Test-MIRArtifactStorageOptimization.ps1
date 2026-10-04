# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$command=Join-Path $repo 'tools/commands/workspace/Optimize-MIRArtifactStorage.ps1'
. (Join-Path $repo 'tools/lib/validation/ImmutableInputStaging.ps1')
$fixtureParent=Join-Path $repo 'build/tmp/artifact-storage-optimization'
$fixture=Join-Path $fixtureParent ([guid]::NewGuid().ToString('N'))

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
  $scope='build/tests/suite/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  $scopedPreview=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $scope -OlderThanDays 7 -MaxScannedEntries 6 -PassThru)
  if($scopedPreview.Count-ne1-or[string]$scopedPreview[0].artifact-cne[string]$preview[0].artifact){throw '[mir-storage-opt-scoped-preview]'}
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

  $scopedRun=Join-Path $fixture 'repo/build/tests/scoped/11111111111111111111111111111111'
  $peerRun=Join-Path $fixture 'repo/build/tests/scoped/22222222222222222222222222222222'
  foreach($run in @($scopedRun,$peerRun)){
    [IO.Directory]::CreateDirectory((Join-Path $run 'mods'))|Out-Null
    [IO.File]::Copy($source,(Join-Path $run 'mods/example_1.0.0.zip'))
    [IO.File]::WriteAllText((Join-Path $run 'result.json'),'{"status":"passed"}',[Text.UTF8Encoding]::new($false))
    (Get-Item -LiteralPath $run).LastWriteTimeUtc=$stale
  }
  $ignoredChild=Join-Path $scopedRun 'mods/ignored-child'
  [IO.Directory]::CreateDirectory($ignoredChild)|Out-Null
  for($index=0;$index-lt20;$index++){[IO.File]::WriteAllText((Join-Path $ignoredChild "$index.txt"),'noise',[Text.UTF8Encoding]::new($false))}
  (Get-Item -LiteralPath $scopedRun).LastWriteTimeUtc=$stale
  $selectedScope='build/tests/scoped/11111111111111111111111111111111'
  $selectedArchive=Join-Path $scopedRun 'mods/example_1.0.0.zip'
  $peerArchive=Join-Path $peerRun 'mods/example_1.0.0.zip'
  $peerIdentity=Get-MIRImmutableInputFileIdentity -Path $peerArchive
  $selectedIdentity=Get-MIRImmutableInputFileIdentity -Path $selectedArchive
  $scopeControls=0
  $allPreview=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -PassThru)
  if($allPreview.Count-ne2){throw '[mir-storage-opt-peer-denominator]'}
  $scopeControls++
  $scopedPreview=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $selectedScope -OlderThanDays 7 -MaxScannedEntries 3 -MaxPendingDirectories 1 -PassThru)
  if($scopedPreview.Count-ne1-or[string]$scopedPreview[0].artifact-cne$selectedArchive){throw '[mir-storage-opt-direct-mods-bounded-scope]'}
  $scopeControls++
  $unscopedBounded=$false
  try{& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -OlderThanDays 7 -MaxScannedEntries 3 -PassThru|Out-Null}catch{$unscopedBounded=$_.Exception.Message-match'bounded 3-entry scan'}
  if(-not$unscopedBounded){throw '[mir-storage-opt-unrelated-discovery-control]'}
  $scopeControls++
  foreach($invalid in @('../build/tests/scoped/11111111111111111111111111111111',
    'build/tests/scoped/../11111111111111111111111111111111',
    $scopedRun,'build/tests/scoped','build/tests/scoped/not-a-guid',
    'build/packages/scoped/11111111111111111111111111111111',
    'build/tests/scoped/11111111111111111111111111111111/mods')){
    $rejected=$false
    try{& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $invalid -OlderThanDays 7 -Apply -Confirm:$false -PassThru|Out-Null}catch{$rejected=$_.Exception.Message-match'TestRunRoot must name'}
    if(-not$rejected){throw "[mir-storage-opt-scope-path-denial] $invalid"}
    $scopeControls++
  }
  foreach($ineligible in @('build/tests/suite/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'build/tests/suite/dddddddddddddddddddddddddddddddd',
    'build/tests/suite/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    'build/tests/scoped/33333333333333333333333333333333')){
    $rejected=$false
    try{& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $ineligible -OlderThanDays 7 -Apply -Confirm:$false -PassThru|Out-Null}catch{$rejected=$_.Exception.Message-match'plain, stale, terminal run'}
    if(-not$rejected){throw "[mir-storage-opt-scoped-eligibility-denial] $ineligible"}
    $scopeControls++
  }
  $emptyRepo=Join-Path $fixture 'empty-repo'
  [IO.Directory]::CreateDirectory($emptyRepo)|Out-Null
  $missingRootRejected=$false
  try{& $command -RepoRoot $emptyRepo -LibraryRoot $library -TestRunRoot $selectedScope -OlderThanDays 7 -PassThru|Out-Null}catch{$missingRootRejected=$_.Exception.Message-match'build/tests is absent'}
  if(-not$missingRootRejected){throw '[mir-storage-opt-explicit-missing-root]'}
  $scopeControls++
  $scopeJunction=Join-Path $fixture 'repo/build/tests/scoped-alias'
  New-Item -ItemType Junction -Path $scopeJunction -Target (Split-Path -Parent $scopedRun) -ErrorAction Stop|Out-Null
  try{
    $junctionRejected=$false
    try{& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot 'build/tests/scoped-alias/11111111111111111111111111111111' -OlderThanDays 7 -Apply -Confirm:$false -PassThru|Out-Null}catch{$junctionRejected=$_.Exception.Message-match'plain, stale, terminal run'}
    if(-not$junctionRejected){throw '[mir-storage-opt-scope-junction]'}
    $scopeControls++
  }finally{Remove-Item -LiteralPath $scopeJunction -Force}
  $scopeLease=Join-Path $scopedRun 'mir-immutable-input-lease.lock'
  $leaseHook={param($plan) [IO.File]::WriteAllText($scopeLease,'owned lease',[Text.UTF8Encoding]::new($false))}.GetNewClosure()
  try{
    $leaseRaceRejected=$false
    try{& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $selectedScope -OlderThanDays 7 -Apply -Confirm:$false -BeforeApplyTestHook $leaseHook -PassThru|Out-Null}catch{$leaseRaceRejected=$_.Exception.Message-match'eligibility changed after planning'}
    if(-not$leaseRaceRejected){throw '[mir-storage-opt-scoped-lease-recheck]'}
    if((Get-MIRImmutableInputFileIdentity -Path $selectedArchive)-cne$selectedIdentity-or(Get-MIRImmutableInputSha256 -Path $selectedArchive)-cne$sourceHash){throw '[mir-storage-opt-scoped-race-retention]'}
    $scopeControls++
  }finally{if(Test-Path -LiteralPath $scopeLease){Remove-Item -LiteralPath $scopeLease -Force};(Get-Item -LiteralPath $scopedRun).LastWriteTimeUtc=$stale}
  $scopedApplied=@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $selectedScope -OlderThanDays 7 -MaxScannedEntries 3 -Apply -Confirm:$false -PassThru)
  if($scopedApplied.Count-ne1-or[string]$scopedApplied[0].status-cne'relinked'-or(Get-MIRImmutableInputFileIdentity -Path $selectedArchive)-cne(Get-MIRImmutableInputFileIdentity -Path $source)-or(Get-MIRImmutableInputSha256 -Path $selectedArchive)-cne$sourceHash){throw '[mir-storage-opt-scoped-apply]'}
  $scopeControls++
  if((Get-MIRImmutableInputFileIdentity -Path $peerArchive)-cne$peerIdentity-or(Get-MIRImmutableInputSha256 -Path $peerArchive)-cne$sourceHash-or-not(Test-Path -LiteralPath (Join-Path $scopedRun 'result.json'))-or@(Get-ChildItem -LiteralPath $ignoredChild -File).Count-ne20){throw '[mir-storage-opt-scoped-custody-and-peer-isolation]'}
  $scopeControls++
  if(@(& $command -RepoRoot (Join-Path $fixture 'repo') -LibraryRoot $library -TestRunRoot $selectedScope -OlderThanDays 7 -MaxScannedEntries 3 -PassThru).Count-ne0){throw '[mir-storage-opt-scoped-fixed-point]'}
  $scopeControls++

  # The public command must forward the selector to the real optimizer. This
  # deliberately invalid selector fails before any primary-run discovery.
  $publicProbe=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') storage optimize --library-root $library --test-run-root 'build/tests/not-a-run' 2>&1|Out-String)
  if($LASTEXITCODE-eq0-or$publicProbe-notmatch'TestRunRoot'){throw "[mir-storage-opt-public-scope-forwarding] $publicProbe"}
  $global:LASTEXITCODE=0
  $helpProbe=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') help 2>&1|Out-String)
  if($LASTEXITCODE-ne0-or$helpProbe-notmatch'storage optimize[^\r\n]*--test-run-root'){throw '[mir-storage-opt-public-scope-help]'}
  $scopeControls+=2

  # Execute the current resolver function with controlled Git responses rather
  # than create another checkout. A real read-only common-directory query below
  # covers this checkout and, when available, one existing linked checkout.
  $parseTokens=$null;$parseErrors=$null
  $commandAst=[Management.Automation.Language.Parser]::ParseFile($command,[ref]$parseTokens,[ref]$parseErrors)
  if($parseErrors.Count){throw '[mir-storage-opt-resolver-parse]'}
  $resolverDefinitions=@($commandAst.FindAll({param($node) $node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Get-MIRStorageDefaultLibraryRoots'},$true))
  if($resolverDefinitions.Count-ne1){throw '[mir-storage-opt-resolver-authority]'}
  $resolverDefinition=[scriptblock]::Create($resolverDefinitions[0].Extent.Text)
  $project=Join-Path $fixture 'resolver-project'
  $primary=Join-Path $project 'primary'
  $linked=Join-Path $project 'worktrees/worker'
  $common=Join-Path $primary '.git'
  $savedGitExit=$global:LASTEXITCODE
  try {
    $controlledDefaults=@(& {
      param($Definition,$CallerRoot,$CommonDirectory)
      . $Definition
      function git {
        if($args.Count-ne5-or$args[0]-cne'-C'-or$args[1]-cne$CallerRoot-or$args[2]-cne'rev-parse'-or$args[3]-cne'--path-format=absolute'-or$args[4]-cne'--git-common-dir'){throw '[mir-storage-opt-resolver-git-query]'}
        $global:LASTEXITCODE=0
        $CommonDirectory
      }
      Get-MIRStorageDefaultLibraryRoots -RepositoryRoot $CallerRoot
    } $resolverDefinition $linked $common)
    $controlledFallback=@(& {
      param($Definition,$CallerRoot)
      . $Definition
      function git {$global:LASTEXITCODE=1;return ''}
      Get-MIRStorageDefaultLibraryRoots -RepositoryRoot $CallerRoot
    } $resolverDefinition $linked)
  } finally {$global:LASTEXITCODE=$savedGitExit}
  if($controlledDefaults.Count-ne2-or$controlledDefaults[0]-cne(Join-Path $project 'testmods/2.0')-or$controlledDefaults[1]-cne(Join-Path $project 'testmods/2.1')){throw '[mir-storage-opt-common-directory-defaults]'}
  if($controlledFallback.Count-ne2-or$controlledFallback[0]-cne(Join-Path (Split-Path -Parent $linked) 'testmods/2.0')){throw '[mir-storage-opt-no-git-fallback]'}
  . $resolverDefinition
  $actualCommon=(& git -C $repo rev-parse --path-format=absolute --git-common-dir|Out-String).Trim()
  if($LASTEXITCODE-ne0-or(Split-Path -Leaf $actualCommon)-cne'.git'){throw '[mir-storage-opt-real-common-directory]'}
  $actualProject=Split-Path -Parent (Split-Path -Parent $actualCommon)
  $actualDefaults=@(Get-MIRStorageDefaultLibraryRoots -RepositoryRoot $repo)
  if($actualDefaults.Count-ne2-or$actualDefaults[0]-cne(Join-Path $actualProject 'testmods/2.0')-or$actualDefaults[1]-cne(Join-Path $actualProject 'testmods/2.1')){throw '[mir-storage-opt-real-defaults]'}
  $existingLinkedObserved=$false
  $existingPaths=@(& git -C $repo worktree list --porcelain | Where-Object {$_-like'worktree *'} | Select-Object -First 16 | ForEach-Object {$_.Substring(9)})
  foreach($existing in $existingPaths){
    if(-not[string]::Equals([IO.Path]::GetFullPath($existing),$repo,[StringComparison]::OrdinalIgnoreCase)-and(Test-Path -LiteralPath $existing -PathType Container)){
      $existingDefaults=@(Get-MIRStorageDefaultLibraryRoots -RepositoryRoot $existing)
      if(($existingDefaults-join'|')-cne($actualDefaults-join'|')){throw '[mir-storage-opt-existing-linked-defaults]'}
      $existingLinkedObserved=$true
      break
    }
  }

  [pscustomobject]@{status='passed';test_id='static.mir-artifact-storage-optimization';relinked=2;scoped_controls=$scopeControls;content_preserved=$true;result_preserved=$true;qualified_terminal_status=$true;mutation_blocked=$true;rollback_proved=$true;scan_bounded=$true;reparse_rechecked=$true;recent_run_untouched=$true;leased_run_untouched=$true;nonterminal_run_untouched=$true;eligible_peer_untouched=$true;scope_lease_rechecked=$true;common_directory_defaults_controlled=$true;primary_default_query=$true;existing_linked_default_query=$existingLinkedObserved;worktree_created=$false;fixture_root='build/tmp/artifact-storage-optimization'}|ConvertTo-Json -Depth 5
}finally{
  if(Test-Path -LiteralPath $fixture){
    $resolvedFixture=(Get-Item -LiteralPath $fixture -Force).FullName
    $resolvedParent=[IO.Path]::GetFullPath($fixtureParent).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not$resolvedFixture.StartsWith($resolvedParent,[StringComparison]::OrdinalIgnoreCase)-or(Split-Path -Leaf $resolvedFixture)-cnotmatch'^[0-9a-f]{32}$'){throw '[mir-storage-opt-fixture-cleanup-boundary]'}
    Get-ChildItem -LiteralPath $resolvedFixture -Force -Recurse | Where-Object {($_.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0} | ForEach-Object {Remove-Item -LiteralPath $_.FullName -Force}
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
  }
}
