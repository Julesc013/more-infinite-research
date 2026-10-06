# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
. (Join-Path $repo 'tools/mir/application/package/HistoricalSourceAuthority.ps1')
. (Join-Path $repo 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $repo 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $repo 'tools/lib/validation/SettingsOverrides.ps1')
. (Join-Path $repo 'tools/lib/assurance/evidence/CommandExecution.ps1')
$assertions=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw "V2 migration inputs: $Message"};$script:assertions++}
function Refuses([scriptblock]$Action,[string]$Expected){$failure='';try{& $Action|Out-Null}catch{$failure=$_.Exception.Message};Check ($failure.Contains($Expected)) "expected $Expected; got $failure"}
# Capacity is synthetic only for tiny stage/actor controls. No engine executes.
function Get-MIR441ResourceSnapshot {
  param([string]$WorkRoot)
  [pscustomobject]@{observed_at=[DateTimeOffset]::UtcNow.ToString('o');memory=[pscustomobject]@{total_bytes=16GB;free_bytes=12GB;committed_bytes=4GB;commit_limit_bytes=20GB};system_volume=[pscustomobject]@{free_bytes=100GB};work_volume=[pscustomobject]@{free_bytes=100GB}}
}
$scratch=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo ('build/tmp/v2-input-controls-'+[guid]::NewGuid().ToString('N')))
$inputLeases=[Collections.Generic.List[object]]::new()
$tokens=$null;$errors=$null
$harness=Join-Path $repo 'tests/runtime/Test-MIR42V2V3CapMigration.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
Check (@($errors).Count -eq 0) 'migration harness no longer parses.'
foreach($name in @('Assert-Migration','New-Stage','Invoke-Engine','Invoke-ServerSave','Get-MigrationGovernedEngineResolution')){
  $definition=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$false))
  Check ($definition.Count -eq 1) "consumed function is ambiguous: $name"
  . ([scriptblock]::Create($definition[0].Extent.Text))
}
try {
  $null=New-Item -ItemType Directory -Path $scratch
  # One bounded 337-entry source coupon, built with the existing archive writer.
  # It authenticates pinned source bytes; it is not native predecessor evidence.
  $pinned=Get-MIR421PinnedV2PackageInputs -RepoRoot $repo
  Check ($pinned.commit -ceq 'f7f9bab7bb1d1a63c98b5e21178fbaed418a3f6e' -and $pinned.tree -ceq 'cfba4858cee79ddc326064862b829d29895bb81d' -and $pinned.entries.Count -eq 337 -and -not $pinned.publication_authorized) 'pinned authority differs.'
  $tree=Join-Path $scratch 'pinned-coupon-source'
  foreach($entry in $pinned.entries.GetEnumerator()){
    $path=Join-Path $tree $entry.Key;$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    [IO.File]::WriteAllBytes($path,$entry.Value)
  }
  $coupon=Join-Path $scratch 'more-infinite-research_4.2.21000.zip'
  $root='more-infinite-research_4.2.21000'
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot $root -OutputPath $coupon -ContainmentRoot $scratch
  $verified=Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive $coupon
  Check ($verified.verified_bindings -eq 337 -and $verified.source_commit -ceq $pinned.commit -and $verified.archive_sha256 -ceq (Get-MIRImmutableInputSha256 $coupon)) 'complete pinned source coupon was not authenticated.'
  Check ($verified.distribution_version -ceq '4.2.21000' -and $verified.classification -ceq 'pinned-private-V2-source-input-only') 'private predecessor acquired another identity.'
  Refuses {Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive (Join-Path $tree 'info.json')} 'mir421-v2-archive-identity'
  function Replace-CouponEntry([string]$Member,[byte[]]$Bytes){
    $zip=[IO.Compression.ZipFile]::Open($coupon,[IO.Compression.ZipArchiveMode]::Update)
    try{$old=$zip.GetEntry($root+'/'+$Member);if($null -ne $old){$old.Delete()};$entry=$zip.CreateEntry($root+'/'+$Member);$stream=$entry.Open();try{$stream.Write($Bytes,0,$Bytes.Length)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
  }
  $controller='prototypes/mir/runtime/maximum_level_control.lua'
  $changed=[Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($pinned.entries[$controller]).Replace('local POLICY_VERSION = 1','local POLICY_VERSION = 3'))
  Replace-CouponEntry $controller $changed
  Refuses {Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive $coupon} 'mir421-v2-archive-binding'
  Replace-CouponEntry $controller $pinned.entries[$controller]
  $info=$pinned.entries['info.json'];$changed=[Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($info).Replace('4.2.21000','4.2.21002'))
  Replace-CouponEntry 'info.json' $changed
  Refuses {Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive $coupon} 'mir421-v2-archive-binding'
  Replace-CouponEntry 'info.json' $info
  Replace-CouponEntry 'unexpected.lua' ([Text.Encoding]::UTF8.GetBytes('tiny unexpected member'))
  Refuses {Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive $coupon} 'mir421-v2-archive-membership'
  $zip=[IO.Compression.ZipFile]::Open($coupon,[IO.Compression.ZipArchiveMode]::Update)
  try{$zip.GetEntry($root+'/unexpected.lua').Delete();$zip.GetEntry($root+'/'+$controller).Delete();$entry=$zip.CreateEntry($root+'/info.json');$stream=$entry.Open();try{$stream.Write($info,0,$info.Length)}finally{$stream.Dispose()}}finally{$zip.Dispose()}
  Refuses {Read-MIR421PinnedV2Candidate -RepoRoot $repo -Archive $coupon} 'mir421-v2-archive-binding'

  # Stage controls use tiny files rather than another materialized mod profile.
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $scratch -ExpectedPeakMemoryMiB 256 -MaxNewOutputMiB 4
  $run=$resources.root;$engineRoot=$scratch;$engine='controlled engine';$FactorioBin='controlled requested engine';$SteamManifest='controlled manifest'
  $predecessorCommit=$pinned.commit;$currentCommit='A'*40
  $predecessorCandidate=Join-Path $scratch 'tiny-v2_4.2.21000.zip';$currentCandidate=Join-Path $scratch 'tiny-v3_4.2.21001.zip'
  [IO.File]::WriteAllText($predecessorCandidate,'tiny verified predecessor control');[IO.File]::WriteAllText($currentCandidate,'tiny verified current control')
  $predecessorInput=[pscustomobject]@{archive_sha256=Get-MIRImmutableInputSha256 $predecessorCandidate;source_commit=$pinned.commit}
  $currentInput=[pscustomobject]@{receipt=[pscustomobject]@{archive_sha256=Get-MIRImmutableInputSha256 $currentCandidate;package_source_sha256='B'*64}}
  $fixture=Join-Path $repo 'fixtures/assert-mir42-v2-v3-cap-migration';$fixtureName='mir-fixture-assert-mir42-v2-v3-cap-migration'
  $stages=@((New-Stage v2-unbounded $predecessorCandidate '0.1.0' 0),(New-Stage v2-capped $predecessorCandidate '0.1.1' 3),(New-Stage v3-capped $currentCandidate '0.1.2' 3),(New-Stage v3-relaxed $currentCandidate '0.1.3' 0))
  foreach($stage in $stages){
    $input=$stage.lease.record.inputs[0]
    Check ($stage.lease.record.require_hard_links -and $input.staging_mode -ceq 'hardlink' -and (Get-MIRImmutableInputFileIdentity $input.source_path) -ceq (Get-MIRImmutableInputFileIdentity $input.stage_path)) "$($stage.name) copied its input."
    Check (($input.role -ceq 'predecessor') -eq $stage.name.StartsWith('v2-')) "$($stage.name) selected the wrong input lineage."
    $zip=[IO.Compression.ZipFile]::OpenRead($stage.settings_archive)
    try{$reader=[IO.StreamReader]::new($zip.GetEntry('mir-validation-settings-overrides_0.1.0/settings-updates.lua').Open());try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}}finally{$zip.Dispose()}
    Check ($text.Contains('override("ips-max-level-research_copper", '+$stage.cap+')')) "$($stage.name) lost its private cap."
    [IO.File]::WriteAllText((Join-Path $stage.mods 'mod-settings.dat'),$stage.name)
  }
  Check (@($stages|ForEach-Object {Get-MIRImmutableInputFileIdentity (Join-Path $_.mods 'mod-settings.dat')}|Sort-Object -Unique).Count -eq 4) 'mutable settings share identities.'
  $script:archiveCopies=0
  function New-Item {[CmdletBinding()]param([string]$ItemType,[string[]]$Path,[string]$Target,[switch]$Force);if($ItemType -ceq 'HardLink'){throw 'controlled unavailable link'};Microsoft.PowerShell.Management\New-Item @PSBoundParameters}
  function Copy-Item {$script:archiveCopies++;throw 'copy attempted'}
  try{Refuses {New-Stage unavailable $currentCandidate '0.1.3' 0} 'requires a verified hard link';Check ($script:archiveCopies -eq 0) 'link failure attempted archive copying.'}finally{Remove-Item Function:\New-Item;Remove-Item Function:\Copy-Item}
  function Invoke-MIRNativeProbeProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds)
    Check ($Context -eq $resources -and $FilePath -ceq (Get-Command pwsh).Source -and $TimeoutSeconds -eq 30 -and $Arguments -contains $FactorioBin -and $Arguments -contains $SteamManifest) 'resolver lost its governed transport.'
    $driver=Get-Content -Raw (Join-Path $Context.root 'resolve-engine.ps1')
    Check ($driver.Contains("-HarnessId 'runtime.maximum-level-v2-v3-migration-f210'") -and $driver.Contains('Resolve-MIR4F210CurrentEngineCapHarnessAdmissionV3')) 'existing engine oracle was bypassed.'
    [IO.File]::WriteAllText((Join-Path $Context.root 'engine-resolution.json'),'{"engine":{"version":"controlled"}}')
  }
  Check ((Get-MigrationGovernedEngineResolution).engine.version -ceq 'controlled') 'resolver response was lost.'
  $expectedSave=Join-Path $stages[2].userdata 'saves/successor.zip';$observed=$true
  $stdout=Join-Path $run 'tiny.stdout.txt';$stderr=Join-Path $run 'tiny.stderr.txt';[IO.File]::WriteAllText($stdout,'tiny output');[IO.File]::WriteAllText($stderr,'')
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds,[scriptblock]$CompletionPredicate)
    Check ($Context -eq $resources -and $FilePath -ceq $engine -and $Arguments -contains $stages[2].config) 'actor lost its private stage or engine.'
    $log=Join-Path $stages[2].userdata 'factorio-current.log'
    if($null -eq $CompletionPredicate){Check ($TimeoutSeconds -eq 120 -and $Arguments -contains '--create') 'create actor arguments changed.';[IO.File]::WriteAllText($log,'tiny creation');return [pscustomobject]@{stdout=$stdout;stderr=$stderr}}
    Check ($TimeoutSeconds -eq 60 -and $Arguments -contains '--start-server' -and $Arguments -contains $stages[2].server) 'server actor arguments changed.'
    if(Test-Path $expectedSave){Remove-Item -LiteralPath $expectedSave}
    Check (-not (& $CompletionPredicate)) 'completion accepted missing save/log.'
    [IO.File]::WriteAllText($log,'Saving finished');Check (-not (& $CompletionPredicate)) 'completion accepted missing save.'
    [IO.File]::WriteAllText($expectedSave,'tiny save');Check (-not (& $CompletionPredicate)) 'completion accepted missing state.'
    [IO.File]::WriteAllText($log,'[mir42-v2-v3-cap-migration] STATE JSON {"stage":"v3-relaxed"} Saving finished');Check (-not (& $CompletionPredicate)) 'completion accepted another stage.'
    [IO.File]::WriteAllText($log,'[mir42-v2-v3-cap-migration] STATE JSON {"stage":"v3-capped"}');Check (-not (& $CompletionPredicate)) 'completion accepted an unfinished save.'
    [IO.File]::WriteAllText($log,'[mir42-v2-v3-cap-migration] STATE JSON {"stage":"v3-capped"} Saving finished');Check (& $CompletionPredicate) 'original completion conditions were rejected.'
    [pscustomobject]@{result=[pscustomobject]@{completion_predicate_observed=$observed}}
  }
  $null=Invoke-Engine $stages[2] create @('--create','controlled save')
  $null=Invoke-ServerSave $stages[2] capped 'controlled seed' $expectedSave 'v3-capped'
  $observed=$false;Refuses {Invoke-ServerSave $stages[2] capped 'controlled seed' $expectedSave 'v3-capped'} 'did not create capped successor'
  foreach($stage in $stages){$terminal=Complete-MIRImmutableInputLease -Lease $stage.lease -Outcome passed;$null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal;$null=Assert-MIRImmutableInputLeaseReclaimable -RunRoot $stage.root -Context 'completed tiny migration stage';Remove-Item -LiteralPath $stage.root -Recurse}
  Check ((Test-Path $predecessorCandidate) -and (Test-Path $currentCandidate)) 'retirement lost shared inputs.'
  $catalog=Get-Content -LiteralPath (Join-Path $repo 'validation/tests.yml') -Raw|ConvertFrom-Json
  $row=@($catalog.tests|Where-Object id -CEQ 'runtime.maximum-level-v2-v3-migration-f210')
  Check ($row.Count -eq 1 -and 'candidate' -in $row[0].inputs -and 'prior-release' -in $row[0].inputs -and 'factorio' -in $row[0].inputs) 'consumed command lost exact native input fingerprints.'
  $commandContext=[pscustomobject]@{factorio='controlled engine with spaces';candidate='controlled current package';candidate_materialization='controlled canonical receipt';prior_release='controlled pinned V2 input'}
  $command=Resolve-MIRAssuranceCommandText -Command $row[0].command -Context $commandContext -Plan ([pscustomobject]@{})
  foreach($expected in @("-FactorioBin 'controlled engine with spaces'","-CandidateZip 'controlled current package'","-SourceMaterializationPath 'controlled canonical receipt'","-PredecessorCandidateZip 'controlled pinned V2 input'",'-ExpectedPeakMemoryMiB 2048','-MaxNewOutputMiB 120')){Check ($command.Contains($expected)) "consumed command lost $expected"}
  $commandContext.prior_release='';Refuses {Resolve-MIRAssuranceCommandText -Command $row[0].command -Context $commandContext -Plan ([pscustomobject]@{})} 'requires <prior-release>'
  $commandContext.prior_release='controlled pinned V2 input';$commandContext.candidate_materialization='';Refuses {Resolve-MIRAssuranceCommandText -Command $row[0].command -Context $commandContext -Plan ([pscustomobject]@{})} 'requires <candidate-materialization>'
  [pscustomobject]@{status='passed';assertions=$assertions;controlled_source_coupon_entries=337;controlled_stages=4;archive_payload_bytes_copied=0;factorio_processes=0;qualification='none; pinned-input authentication and consumed adapter controls only'}
} finally {
  foreach($lease in $inputLeases){if(-not $lease.closed){$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}}
  if(Test-Path $scratch){$resolved=(Resolve-Path -LiteralPath $scratch).Path;$prefix=(Resolve-Path -LiteralPath (Join-Path $repo 'build/tmp')).Path.TrimEnd('\')+'\';if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Synthetic migration cleanup escapes its owned parent'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
