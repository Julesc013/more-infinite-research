[CmdletBinding()]
param(
    [string]$ControllerPath,
    [string]$PacketPath,
    [string]$WindowsPacketPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if([string]::IsNullOrWhiteSpace($ControllerPath)){$ControllerPath=Join-Path $repo 'tools/Invoke-WorkerStorageSECargoCapTenNative.ps1'}
if([string]::IsNullOrWhiteSpace($PacketPath)){$PacketPath=Join-Path $repo 'tests/fixtures/worker-storage-se-cap-ten-native.json'}
if([string]::IsNullOrWhiteSpace($WindowsPacketPath)){$WindowsPacketPath=Join-Path $repo 'tests/fixtures/worker-storage-se-cap-ten-native-windows.json'}
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $repo ('build/tmp/worker-storage-se-cap-ten-native-controls-'+[guid]::NewGuid().ToString('N'))}
if(-not(Test-Path -LiteralPath $ControllerPath -PathType Leaf)){throw "controller is missing: $ControllerPath"}
if(-not(Test-Path -LiteralPath $PacketPath -PathType Leaf)){throw "packet is missing: $PacketPath"}
if(-not(Test-Path -LiteralPath $WindowsPacketPath -PathType Leaf)){throw "Windows packet is missing: $WindowsPacketPath"}
if(Test-Path -LiteralPath $OutputRoot){throw "refusing to overwrite control output: $OutputRoot"}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
. $ControllerPath
. (Join-Path $repo 'tools/lib/validation/NativeProbeCommon.ps1')

$script:checks=[Collections.Generic.List[object]]::new()
function Add-Check { param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$Action) try{&$Action;[void]$script:checks.Add([ordered]@{name=$Name;passed=$true})}catch{[void]$script:checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message});throw} }
function Assert-Refuses { param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Contains) $seen=$false;try{&$Action}catch{$seen=$true;if($_.Exception.Message-notmatch[regex]::Escape($Contains)){throw "refusal had unexpected text '$($_.Exception.Message)', expected '$Contains'"}};if(-not$seen){throw "expected refusal containing '$Contains'"} }
function Copy-HashTable { param($Value) (($Value|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable -Depth 100) }
function Write-Text { param([string]$Path,[string]$Text) [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
function New-SyntheticSave { param([string]$Path,[string]$Payload) $zip=$null;$writer=$null;try{$zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create);$entry=$zip.CreateEntry('level.dat');$writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false));$writer.Write($Payload)}finally{if($null-ne$writer){$writer.Dispose()};if($null-ne$zip){$zip.Dispose()}} }
function New-CargoLogLine {
    param([string]$Phase,[int]$Tick,[string]$Worker,[string]$Level,[string]$Current,[string]$Progress,[string]$Queue,[string]$Ordinary,[double]$Bonus,[double]$Debit,[hashtable]$Extra=@{})
    $issued=@();$remaining=@();$debits=@()
    foreach($pack in $script:CargoSciencePacks){$issued+="$pack`:200";$remaining+="$pack`:$([string](200-$Debit))";$debits+="$pack`:$([string]$Debit)"}
    $fields=@('[MIR_SE_CARGO_NATIVE]',"phase=$Phase","tick=$Tick","worker=$Worker","level=$Level","current=$Current","progress=$Progress","queue=$Queue","ordinary=$Ordinary","bonus=$Bonus","force_bonuses=1:$Bonus,2:0",'laboratory_productivity_bonus=0','technology_price_multiplier=1',("science_issued="+($issued-join',')),("science_remaining="+($remaining-join',')),("science_debit="+($debits-join',')),'unit_count=5126','unit_time=3600','settings_file_values=true',"expected_worker_bonus=$Bonus")
    foreach($key in @($Extra.Keys|Sort-Object)){$fields+="$key=$($Extra[$key])"};$fields-join'|'
}
function New-CargoSettingsLine { '[MIR_WORKER_STORAGE_SETTINGS] mir-enable-worker-robots-storage=boolean:true|mir-max-level-worker-robots-storage=number:10|mir-cost-base-worker-robots-storage=number:200|mir-cost-linear-increment-worker-robots-storage=number:0|mir-cost-growth-worker-robots-storage=number:1.5|mir-research-time-worker-robots-storage=number:60|mir-effect-per-level-worker-robots-storage=number:1' }
function New-CargoActiveModsLine { param([string]$MirVersion) '[MIR_ACTIVE_MODS] aai-containers@0.3.2|aai-industry@0.6.16|aai-signal-transmission@0.5.3|alien-biomes-graphics@0.7.1|alien-biomes@0.7.4|base@2.0.77|informatron@0.4.0|jetpack@0.4.17|mir-fixture-mir5-worker-storage-se-cap-ten-native@0.1.0|more-infinite-research@'+$MirVersion+'|robot_attrition@0.6.6|shield-projector@0.2.2|space-exploration-graphics-2@0.7.2|space-exploration-graphics-3@0.7.2|space-exploration-graphics-4@0.7.2|space-exploration-graphics-5@0.7.3|space-exploration-graphics@0.7.5|space-exploration-menu-simulations@0.7.4|space-exploration-postprocess@0.7.5|space-exploration@0.7.57' }
function New-CargoConstructionLine { '[MIR_SE_CARGO_CONSTRUCTION] name=worker-robots-storage-4|prerequisite=worker-robots-storage-3|formula=675*1.5^(L-4)|time=60|ingredients=automation-science-pack:1,chemical-science-pack:1,logistic-science-pack:1,production-science-pack:1,se-material-science-pack-1:1,se-rocket-science-pack:1,space-science-pack:1|effects=worker-robot-storage:1' }
function New-SyntheticCargoChain {
    param([string]$Root)
    [IO.Directory]::CreateDirectory($Root)|Out-Null
    $sourceSave=Join-Path $Root 'protected-source.zip';New-SyntheticSave $sourceSave 'source'
    $candidateSave=Join-Path $Root 'protected-candidate.zip';New-SyntheticSave $candidateSave 'candidate'
    $candidateWorking=Join-Path $Root 'candidate-working.zip';[IO.File]::Copy($sourceSave,$candidateWorking,$false)
    $coldOne=Join-Path $Root 'cold-one-working.zip';$coldTwo=Join-Path $Root 'cold-two-working.zip';[IO.File]::Copy($candidateSave,$coldOne,$false);[IO.File]::Copy($candidateSave,$coldTwo,$false)
    $queue='worker-robots-storage-4,worker-robots-storage-4,mir-fixture-worker-storage-se-cap-ten-tail'
    $sourceLog=Join-Path $Root 'source.log';Write-Text $sourceLog ((New-CargoActiveModsLine '4.7.20002')+"`n"+(New-CargoSettingsLine)+"`n"+(New-CargoConstructionLine)+"`n"+(New-CargoLogLine -Phase source-begin -Tick 10 -Worker $script:CargoSourceWorker -Level 4 -Current $script:CargoSourceWorker -Progress 0 -Queue $queue -Ordinary 0 -Bonus 0 -Debit 0)+"`n"+(New-CargoLogLine -Phase source-partial -Tick 60 -Worker $script:CargoSourceWorker -Level 9 -Current $script:CargoSourceWorker -Progress .42 -Queue $queue -Ordinary 5 -Bonus 5 -Debit 5.42 -Extra @{partial='.42';save='mir5-se-worker-storage-cap10-source';source_role="$script:CargoSourceWorker`:9:false:true:false"})+"`n")
    $privateQueue="$script:CargoPrivateWorker,$script:CargoPrivateWorker,$script:CargoTail";$candidateLog=Join-Path $Root 'candidate.log';Write-Text $candidateLog ((New-CargoActiveModsLine '5.0.20018')+"`n"+(New-CargoSettingsLine)+"`n"+(New-CargoConstructionLine)+"`n"+(New-CargoLogLine -Phase candidate-pre-work -Tick 2 -Worker $script:CargoPrivateWorker -Level 9 -Current $script:CargoPrivateWorker -Progress .42 -Queue $privateQueue -Ordinary 5 -Bonus 5 -Debit 5.42 -Extra @{source_partial='.42';source_role="$script:CargoSourceWorker`:9:false:true:false";canonical_role="$script:CargoSourceWorker`:5:false:false:false";private_role="$script:CargoPrivateWorker`:9:false:true:false";head_role="$script:CargoHeadWorker`:5:false:false:false";configuration_startup_settings_changed='true'})+"`n"+(New-CargoLogLine -Phase candidate-closed -Tick 20 -Worker $script:CargoPrivateWorker -Level 11 -Current $script:CargoTail -Progress 0 -Queue $script:CargoTail -Ordinary 5 -Bonus 7 -Debit 7.42 -Extra @{candidate_events='2';cap_attempt='refused';save='mir5-se-worker-storage-cap10-candidate';configuration_startup_settings_changed='true'})+"`n")
    $coldOneLog=Join-Path $Root 'cold-one.log';$coldTwoLog=Join-Path $Root 'cold-two.log';$coldPrefix=(New-CargoActiveModsLine '5.0.20018')+"`n"+(New-CargoSettingsLine)+"`n"+(New-CargoConstructionLine)+"`n";Write-Text $coldOneLog ($coldPrefix+(New-CargoLogLine -Phase cold-read -Tick 1 -Worker $script:CargoPrivateWorker -Level 11 -Current $script:CargoTail -Progress 0 -Queue $script:CargoTail -Ordinary 5 -Bonus 7 -Debit 7.42 -Extra @{cold_writes='0';configuration_startup_settings_changed='true'})+"`n");Write-Text $coldTwoLog ($coldPrefix+(New-CargoLogLine -Phase cold-read -Tick 1 -Worker $script:CargoPrivateWorker -Level 11 -Current $script:CargoTail -Progress 0 -Queue $script:CargoTail -Ordinary 5 -Bonus 7 -Debit 7.42 -Extra @{cold_writes='0';configuration_startup_settings_changed='true'})+"`n")
    $sourceInitial=Get-CargoCapTenFingerprint $sourceSave;$candidateProtectedInitial=Get-CargoCapTenFingerprint $candidateSave;$candidateInitial=Get-CargoCapTenFingerprint $candidateWorking;$coldOneInitial=Get-CargoCapTenFingerprint $coldOne;$coldTwoInitial=Get-CargoCapTenFingerprint $coldTwo
    [ordered]@{
        source=[ordered]@{run=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=$true;exit_code=137};log=$sourceLog;protected_save=$sourceSave;protected_initial=$sourceInitial}
        candidate=[ordered]@{run=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=$true;exit_code=137};log=$candidateLog;working_input=$candidateWorking;initial_working_copy=$candidateInitial;mutable_working_input=$candidateInitial;protected_save=$candidateSave;protected_initial=$candidateProtectedInitial}
        cold1=[ordered]@{name='cold-1';run=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0};working_input=$coldOne;initial_working_copy=$coldOneInitial;mutable_working_input=$coldOneInitial;log=$coldOneLog}
        cold2=[ordered]@{name='cold-2';run=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0};working_input=$coldTwo;initial_working_copy=$coldTwoInitial;mutable_working_input=$coldTwoInitial;log=$coldTwoLog}
    }
}

$packet=Read-CargoCapTenJson $PacketPath
$windowsPacket=Read-CargoCapTenJson $WindowsPacketPath

# This controller tests the immutable 2287 case, not the current actor source.
# Project its five exact historical members into disposable host input custody;
# current helpers remain current so their strict historical-pin refusal is real.
$currentRepo=$repo
$frozenRepo=Join-Path $OutputRoot 'frozen-source'
$python=Get-Command python -ErrorAction Stop
$projection=@'
from pathlib import Path
import hashlib,json,subprocess,sys
repo,out=Path(sys.argv[1]),Path(sys.argv[2])
pins=json.loads(sys.argv[3]);revision='7cfad2708e790b024e2493d00ed5892ac0c2601a'
prefix='tests/fixtures/worker-storage-se-cap-ten-native/'
assert {r['path'] for r in pins['actors']}=={'control.lua','data-final-fixes.lua','data.lua','info-f200.json','prerequisites.lua'}
for row in pins['actors']:
 raw=subprocess.check_output(['git','-C',str(repo),'show',revision+':'+prefix+row['path']])
 assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest().upper()==row['sha256'],row['path']
 destination=out/prefix/row['path'];destination.parent.mkdir(parents=True,exist_ok=True)
 with destination.open('xb') as stream:stream.write(raw)
for row in pins['helpers']:
 relative=Path(row['path']);assert not relative.is_absolute() and '..' not in relative.parts and relative.parts[0]=='tools'
 destination=out/relative;destination.parent.mkdir(parents=True,exist_ok=True)
 with destination.open('xb') as stream:stream.write((repo/relative).read_bytes())
'@
$projectionPins=[ordered]@{actors=$script:CargoActorMembers;helpers=$script:CargoHelperPins}|ConvertTo-Json -Depth 8 -Compress
& $python.Source -I -c $projection $currentRepo $frozenRepo $projectionPins
if($LASTEXITCODE-ne0){throw 'Exact historical Cargo host-input projection failed; fetch7cfad2708e790b024e2493d00ed5892ac0c2601a as documented in CI.'}
$repo=$frozenRepo

Add-Check 'packets pin the full F200 source/candidate/File-settings/actor closure and distinct exact engines' {
    Assert-CargoCapTenPacket -Packet $packet -RepoRoot $repo -DeferLocalHelperObservation
    Assert-CargoCapTenPacket -Packet $windowsPacket -RepoRoot $repo -DeferLocalHelperObservation
}
Add-Check 'Compose defers missing local bindings without context or direct-library activation' {
    $out=Join-Path $OutputRoot 'compose.json';$receipt=Invoke-CargoCapTenExecutor -RequestedMode Compose -RequestedPacketPath $PacketPath -RepoRoot $repo -RequestedOutputPath $out
    Require-CargoCapTen ($receipt.status -cin @('COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS','COMPOSED_DEFERRED_LOCAL_HELPER_MISMATCH')) 'Compose status differs';Assert-CargoCapTenEqual $receipt.native_processes_started 0 'Compose native processes';Assert-CargoCapTenEqual $receipt.library_activation $false 'Compose activation';Assert-CargoCapTenEqual $receipt.resource_context_allocated $false 'Compose context'
    $windowsOut=Join-Path $OutputRoot 'compose-windows.json';$windowsReceipt=Invoke-CargoCapTenExecutor -RequestedMode Compose -RequestedPacketPath $WindowsPacketPath -RepoRoot $repo -RequestedOutputPath $windowsOut
    Require-CargoCapTen ($windowsReceipt.status -cin @('COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS','COMPOSED_DEFERRED_LOCAL_HELPER_MISMATCH')) 'Windows Compose status differs';Assert-CargoCapTenEqual $windowsReceipt.native_processes_started 0 'Windows Compose native processes';Assert-CargoCapTenEqual $windowsReceipt.library_activation $false 'Windows Compose activation';Assert-CargoCapTenEqual $windowsReceipt.resource_context_allocated $false 'Windows Compose context'
}
Add-Check 'helper observation preserves same-size drift while strict admission rejects it' {
    $path=Join-Path $OutputRoot 'helper-identity.txt';Write-Text $path 'ABCD'
    $descriptor=[ordered]@{path=$path;bytes=4;sha256='E12E115ACF4552B2568B55E93CBD39394C4EF81C82447FAFC997882A02D23677'}
    Assert-CargoCapTenEqual (Test-CargoCapTenFile $descriptor 'helper control' -ObserveMismatch).state 'verified_local_input' 'exact helper'
    Write-Text $path 'WXYZ';$changed=Test-CargoCapTenFile $descriptor 'helper control' -ObserveMismatch
    Require-CargoCapTen ($changed.state -ceq 'mismatched_local_input' -and $changed.sha256 -ceq $descriptor.sha256 -and $changed.observed_sha256 -ceq '21E32F5321CAD49AB4CF78BA5ED231E0F36D0C78D34108FDA1BE939F33FBA149') 'helper mismatch observation differs'
    Assert-Refuses -Contains 'helper control SHA-256 differs' -Action {Test-CargoCapTenFile $descriptor 'helper control'}
}
Add-Check 'planning cannot change frozen helper pins and Execute refuses unavailable helpers before its actor' {
    $bad=Copy-HashTable $packet;$bad.helper_pins[2].sha256='0'*64
    Assert-Refuses -Contains 'helper SHA-256' -Action {Assert-CargoCapTenPacket $bad $repo -DeferLocalHelperObservation}
    $prior=(Get-Command Invoke-CargoCapTenExecution -CommandType Function).ScriptBlock;$script:cargoUnexpectedExecution=$false
    try{
        Set-Item -Path Function:Invoke-CargoCapTenExecution -Value {param($Packet,$RepoRoot) $script:cargoUnexpectedExecution=$true;throw 'unexpected execution boundary'}
        $errorText='';try{Invoke-CargoCapTenExecutor -RequestedMode Execute -RequestedPacketPath $WindowsPacketPath -RepoRoot $repo -RequestedOutputPath (Join-Path $OutputRoot 'must-not-execute.json')|Out-Null}catch{$errorText=$_.Exception.Message}
        Require-CargoCapTen (-not $script:cargoUnexpectedExecution -and $errorText -match 'helper .+ (bytes differ|SHA-256 differs)|Execute refuses missing local bindings' -and -not(Test-Path -LiteralPath (Join-Path $OutputRoot 'must-not-execute.json'))) "unavailable helpers crossed execution: $errorText"
    }finally{Set-Item -Path Function:Invoke-CargoCapTenExecution -Value $prior}
}
Add-Check 'wrong File settings, actor, engine, and archive identities refuse before an owner can execute' {
    $mutations=@(
        @('settings SHA-256',{param($p)$p.inputs.settings.sha256='0'*64},'File settings SHA-256'),
        @('actor control SHA-256',{param($p)$p.inputs.actor_members[0].sha256='0'*64},'actor member SHA-256'),
        @('engine SHA-256',{param($p)$p.inputs.engine.factorio_binary_sha256='0'*64},'engine factorio_binary_sha256'),
        @('candidate archive SHA-256',{param($p)$p.inputs.candidate_mir.sha256='0'*64},'candidate MIR SHA-256')
    )
    foreach($row in $mutations){$mutated=Copy-HashTable $packet;&$row[1] $mutated;Assert-Refuses -Contains $row[2] -Action {Assert-CargoCapTenPacket -Packet $mutated -RepoRoot $repo}}
}
Add-Check 'two engine bindings reject wrong platform, mode, hash, and Windows byte identity before context' {
    $windowsBinding=Get-CargoCapTenEngineBinding $windowsPacket.inputs.engine;$linuxBinding=Get-CargoCapTenEngineBinding $packet.inputs.engine
    Assert-CargoCapTenEqual $windowsBinding.host_platform 'Windows' 'Windows binding platform';Assert-CargoCapTenEqual $windowsBinding.headless_build $false 'Windows binding mode';Assert-CargoCapTenEqual $linuxBinding.host_platform 'Linux' 'Linux binding platform';Assert-CargoCapTenEqual $linuxBinding.headless_build $true 'Linux binding mode'
    Assert-Refuses -Contains 'engine host platform' -Action {Assert-CargoCapTenHostEngineBinding -Packet $windowsPacket -HostPlatform Linux|Out-Null}
    foreach($mutation in @(
        @{name='headless mode';apply={param($p)$p.inputs.engine.headless_build=$true};error='engine headless mode'},
        @{name='binary hash';apply={param($p)$p.inputs.engine.factorio_binary_sha256='0'*64};error='engine factorio_binary_sha256'},
        @{name='binary bytes';apply={param($p)$p.inputs.engine.factorio_binary_bytes=1};error='engine binary bytes'},
        @{name='unknown binding';apply={param($p)$p.inputs.engine.binding_id='windows-any'};error='engine binding differs'}
    )){$bad=Copy-HashTable $windowsPacket;&$mutation.apply $bad;Assert-Refuses -Contains $mutation.error -Action {Assert-CargoCapTenPacket -Packet $bad -RepoRoot $repo}}
}
Add-Check 'engine arguments preserve Linux headless and require Windows full --disable-audio' {
    $linux=Get-CargoCapTenEngineBinding $packet.inputs.engine;$windows=Get-CargoCapTenEngineBinding $windowsPacket.inputs.engine
    $linuxArgs=@(New-CargoCapTenEngineArguments 'linux-config.ini' 'linux-mods' $linux);Require-CargoCapTen (-not($linuxArgs-contains'--disable-audio')) 'Linux headless arguments include audio disable'
    $windowsArgs=@(New-CargoCapTenEngineArguments 'windows-config.ini' 'windows-mods' $windows);Require-CargoCapTen (@($windowsArgs|Where-Object {$_-ceq'--disable-audio'}).Count-eq1) 'Windows full arguments omit audio disable'
}
Add-Check 'only the source stage sends the fixture begin command' {
    $plan=New-CargoCapTenComposePlan $packet;$source=@($plan.stages|Where-Object name -eq 'source-server')[0];$candidate=@($plan.stages|Where-Object name -eq 'candidate-server')[0]
    Assert-CargoCapTenEqual $source.console_command $packet.protocol.source_console_command 'source command';Assert-CargoCapTenEqual $candidate.configuration_callback_begins_work $true 'candidate callback';Assert-CargoCapTenEqual $candidate.no_candidate_console_command $true 'candidate command scope';if($candidate.Contains('console_command')){throw 'candidate plan contains an unauthorized console command'}
}
Add-Check 'runtime selection adds only the role MIR archive to the verified nineteen-row profile' {
    $mods=[Collections.Generic.List[object]]::new();$hashes=[ordered]@{}
    foreach($pair in $script:CargoSEMods){[void]$mods.Add([ordered]@{name=$pair[0];version=$pair[1];enabled=$true});if($pair[0]-ne'base'){$hashes[($pair[0]+'_'+$pair[1]+'.zip')]=('A'*64)}}
    $profile=[ordered]@{mods=@($mods);archive_sha256=$hashes};$path=Join-Path $OutputRoot 'runtime-profile.json';$actual=New-CargoCapTenRuntimeProfile -Profile $profile -MirFilename 'more-infinite-research_4.7.20002.zip' -MirVersion '4.7.20002' -MirSha ('B'*64) -Path $path
    $written=Read-CargoCapTenJson $path;Assert-CargoCapTenEqual $written.mods.Count 20 'runtime profile mod count';Assert-CargoCapTenEqual $actual.Count 19 'runtime profile non-base archive count';Assert-CargoCapTenEqual $written.mods[-1].name 'more-infinite-research' 'runtime MIR name';Assert-CargoCapTenEqual $written.archive_sha256['more-infinite-research_4.7.20002.zip'] ('B'*64) 'runtime MIR hash'
}
Add-Check 'complete reader accepts ordinary source/candidate events and independent cold copies' {
    $chain=New-SyntheticCargoChain (Join-Path $OutputRoot 'healthy-chain');$result=Read-CargoCapTenCompleteChain $chain;Assert-CargoCapTenEqual $result.ordinary_events.source 5 'source event count';Assert-CargoCapTenEqual $result.ordinary_events.candidate 2 'candidate event count';Assert-CargoCapTenEqual $result.cold_working_inputs.Count 2 'cold copy count'
}
Add-Check 'complete reader rejects a synthetic cold write and a protected-save alias' {
    $changed=New-SyntheticCargoChain (Join-Path $OutputRoot 'cold-write');Write-Text $changed.cold2.log ((Get-Content -LiteralPath $changed.cold2.log -Raw).Replace('cold_writes=0','cold_writes=1'));Assert-Refuses -Contains 'cold no writes' -Action {Read-CargoCapTenCompleteChain $changed|Out-Null}
    $aliased=New-SyntheticCargoChain (Join-Path $OutputRoot 'aliased-cold');$aliased.cold1.working_input=$aliased.candidate.protected_save;Assert-Refuses -Contains 'reuses protected pathname' -Action {Read-CargoCapTenCompleteChain $aliased|Out-Null}
}
Add-Check 'reader retains a recorded mutable working input but refuses any changed protected save' {
    $mutable=New-SyntheticCargoChain (Join-Path $OutputRoot 'mutable-working');$mutatedPath=Join-Path (Split-Path -Parent $mutable.candidate.working_input) 'candidate-mutated.zip';New-SyntheticSave $mutatedPath 'candidate-mutated-by-server';[IO.File]::Copy($mutatedPath,$mutable.candidate.working_input,$true);$mutable.candidate.mutable_working_input=Get-CargoCapTenFingerprint $mutable.candidate.working_input;Read-CargoCapTenCompleteChain $mutable|Out-Null
    $changed=New-SyntheticCargoChain (Join-Path $OutputRoot 'changed-protected');$changedPath=Join-Path (Split-Path -Parent $changed.source.protected_save) 'source-changed.zip';New-SyntheticSave $changedPath 'source-changed';[IO.File]::Copy($changedPath,$changed.source.protected_save,$true);Assert-Refuses -Contains 'protected source bytes' -Action {Read-CargoCapTenCompleteChain $changed|Out-Null}
}
Add-Check 'source and candidate require the exact seven typed File-setting observations' {
    $missing=New-SyntheticCargoChain (Join-Path $OutputRoot 'settings-missing');$without=@(Get-Content -LiteralPath $missing.source.log|Where-Object {$_-notmatch'\[MIR_WORKER_STORAGE_SETTINGS\]'});Write-Text $missing.source.log (($without-join"`n")+"`n");Assert-Refuses -Contains 'settings data marker differs' -Action {Read-CargoCapTenCompleteChain $missing|Out-Null}
    $wrongType=New-SyntheticCargoChain (Join-Path $OutputRoot 'settings-wrong-type');Write-Text $wrongType.source.log ((Get-Content -LiteralPath $wrongType.source.log -Raw).Replace('mir-max-level-worker-robots-storage=number:10','mir-max-level-worker-robots-storage=string:10'));Assert-Refuses -Contains 'settings data marker differs' -Action {Read-CargoCapTenCompleteChain $wrongType|Out-Null}
    $wrongValue=New-SyntheticCargoChain (Join-Path $OutputRoot 'settings-wrong-value');Write-Text $wrongValue.candidate.log ((Get-Content -LiteralPath $wrongValue.candidate.log -Raw).Replace('mir-effect-per-level-worker-robots-storage=number:1','mir-effect-per-level-worker-robots-storage=number:2'));Assert-Refuses -Contains 'settings data marker differs' -Action {Read-CargoCapTenCompleteChain $wrongValue|Out-Null}
}
Add-Check 'candidate partial progress rejects nonfinite marker values' {
    foreach($token in @('NaN','Infinity')){$malformed=New-SyntheticCargoChain (Join-Path $OutputRoot ('candidate-progress-'+$token));Write-Text $malformed.candidate.log ((Get-Content -LiteralPath $malformed.candidate.log -Raw).Replace('progress=.42','progress='+$token));Assert-Refuses -Contains 'marker numeric field is nonfinite: progress' -Action {Read-CargoCapTenCompleteChain $malformed|Out-Null}}
}
Add-Check 'candidate role, all-force, seven-pack, and configuration observations reject malformed endpoint frames' {
    $wrongRole=New-SyntheticCargoChain (Join-Path $OutputRoot 'candidate-wrong-role');Write-Text $wrongRole.candidate.log ((Get-Content -LiteralPath $wrongRole.candidate.log -Raw).Replace("worker=$script:CargoPrivateWorker", "worker=$script:CargoSourceWorker"));Assert-Refuses -Contains 'candidate pre-work worker' -Action {Read-CargoCapTenCompleteChain $wrongRole|Out-Null}
    $foreignForce=New-SyntheticCargoChain (Join-Path $OutputRoot 'candidate-foreign-force');Write-Text $foreignForce.candidate.log ((Get-Content -LiteralPath $foreignForce.candidate.log -Raw).Replace('force_bonuses=1:7,2:0','force_bonuses=1:7,2:1'));Assert-Refuses -Contains 'candidate foreign force bonus differs' -Action {Read-CargoCapTenCompleteChain $foreignForce|Out-Null}
    $wrongScience=New-SyntheticCargoChain (Join-Path $OutputRoot 'candidate-wrong-science');Write-Text $wrongScience.candidate.log ((Get-Content -LiteralPath $wrongScience.candidate.log -Raw).Replace('science_debit=automation-science-pack:7.42','science_debit=automation-science-pack:7.41'));Assert-Refuses -Contains 'candidate closed science accounting automation-science-pack' -Action {Read-CargoCapTenCompleteChain $wrongScience|Out-Null}
    $wrongConfiguration=New-SyntheticCargoChain (Join-Path $OutputRoot 'candidate-wrong-configuration');Write-Text $wrongConfiguration.candidate.log ((Get-Content -LiteralPath $wrongConfiguration.candidate.log -Raw).Replace('configuration_startup_settings_changed=true','configuration_startup_settings_changed=unknown'));Assert-Refuses -Contains 'candidate configuration observation differs' -Action {Read-CargoCapTenCompleteChain $wrongConfiguration|Out-Null}
}
Add-Check 'reader derives a nonzero player baseline and rejects source or candidate foreign-only advances' {
    $before=[ordered]@{'1'=8.0;'2'=8.0};$healthy=[ordered]@{'1'=10.0;'2'=8.0}
    Assert-CargoCapTenOnlyWorkerBonusAdvance $before $healthy 10 2 $script:CargoPlayerForceIndex 'healthy candidate'
    $foreignOnly=[ordered]@{'1'=8.0;'2'=10.0}
    Assert-Refuses -Contains 'candidate player worker bonus increment' -Action {Assert-CargoCapTenOnlyWorkerBonusAdvance $before $foreignOnly 10 2 $script:CargoPlayerForceIndex 'candidate'}

    $nonzero=New-SyntheticCargoChain (Join-Path $OutputRoot 'nonzero-player-baseline')
    $sourceText=(Get-Content -LiteralPath $nonzero.source.log -Raw).Replace('force_bonuses=1:0,2:0','force_bonuses=1:3,2:0').Replace('expected_worker_bonus=0','expected_worker_bonus=3').Replace('force_bonuses=1:5,2:0','force_bonuses=1:8,2:0').Replace('expected_worker_bonus=5','expected_worker_bonus=8');Write-Text $nonzero.source.log $sourceText
    $candidateText=(Get-Content -LiteralPath $nonzero.candidate.log -Raw).Replace('force_bonuses=1:5,2:0','force_bonuses=1:8,2:0').Replace('expected_worker_bonus=5','expected_worker_bonus=8').Replace('force_bonuses=1:7,2:0','force_bonuses=1:10,2:0').Replace('expected_worker_bonus=7','expected_worker_bonus=10');Write-Text $nonzero.candidate.log $candidateText
    foreach($cold in @($nonzero.cold1,$nonzero.cold2)){$coldText=(Get-Content -LiteralPath $cold.log -Raw).Replace('force_bonuses=1:7,2:0','force_bonuses=1:10,2:0').Replace('expected_worker_bonus=7','expected_worker_bonus=10');Write-Text $cold.log $coldText}
    Read-CargoCapTenCompleteChain $nonzero|Out-Null

    $foreignSource=New-SyntheticCargoChain (Join-Path $OutputRoot 'source-foreign-only-advance')
    $sourceText=(Get-Content -LiteralPath $foreignSource.source.log -Raw).Replace('force_bonuses=1:0,2:0','force_bonuses=1:0,2:8').Replace('force_bonuses=1:5,2:0','force_bonuses=1:5,2:10');Write-Text $foreignSource.source.log $sourceText
    Assert-Refuses -Contains 'source foreign force bonus differs' -Action {Read-CargoCapTenCompleteChain $foreignSource|Out-Null}

    $foreignCandidate=New-SyntheticCargoChain (Join-Path $OutputRoot 'candidate-foreign-only-advance')
    $sourceText=(Get-Content -LiteralPath $foreignCandidate.source.log -Raw).Replace('force_bonuses=1:0,2:0','force_bonuses=1:0,2:8').Replace('force_bonuses=1:5,2:0','force_bonuses=1:5,2:8');Write-Text $foreignCandidate.source.log $sourceText
    $candidateText=(Get-Content -LiteralPath $foreignCandidate.candidate.log -Raw).Replace('force_bonuses=1:5,2:0','force_bonuses=1:5,2:8').Replace('force_bonuses=1:7,2:0','force_bonuses=1:7,2:10');Write-Text $foreignCandidate.candidate.log $candidateText
    Assert-Refuses -Contains 'candidate foreign force bonus differs' -Action {Read-CargoCapTenCompleteChain $foreignCandidate|Out-Null}
}
Add-Check 'every source, successor, and cold stage requires its active-mod and construction data markers' {
    $wrongMod=New-SyntheticCargoChain (Join-Path $OutputRoot 'active-wrong-mir');Write-Text $wrongMod.source.log ((Get-Content -LiteralPath $wrongMod.source.log -Raw).Replace('more-infinite-research@4.7.20002','more-infinite-research@5.0.20018'));Assert-Refuses -Contains 'source active-mods data marker differs' -Action {Read-CargoCapTenCompleteChain $wrongMod|Out-Null}
    $wrongConstruction=New-SyntheticCargoChain (Join-Path $OutputRoot 'construction-wrong-formula');Write-Text $wrongConstruction.candidate.log ((Get-Content -LiteralPath $wrongConstruction.candidate.log -Raw).Replace('formula=675*1.5^(L-4)','formula=1'));Assert-Refuses -Contains 'candidate construction data marker differs' -Action {Read-CargoCapTenCompleteChain $wrongConstruction|Out-Null}
    $missingConstruction=New-SyntheticCargoChain (Join-Path $OutputRoot 'construction-missing-cold');$without=@(Get-Content -LiteralPath $missingConstruction.cold1.log|Where-Object {$_-notmatch'\[MIR_SE_CARGO_CONSTRUCTION\]'});Write-Text $missingConstruction.cold1.log (($without-join"`n")+"`n");Assert-Refuses -Contains 'construction data marker differs' -Action {Read-CargoCapTenCompleteChain $missingConstruction|Out-Null}
}
Add-Check 'source and candidate completion predicates require a complete save ZIP, not a marker file alone' {
    $valid=Join-Path $OutputRoot 'predicate-valid.zip';New-SyntheticSave $valid 'completed';if(-not(Test-CargoCapTenCompleteSave $valid 'predicate valid')){throw 'valid completed save was not admitted'}
    $invalid=Join-Path $OutputRoot 'predicate-invalid.zip';Write-Text $invalid 'not-a-zip';if(Test-CargoCapTenCompleteSave $invalid 'predicate invalid'){throw 'invalid completed save was admitted'}
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($ControllerPath,[ref]$tokens,[ref]$errors);if($errors.Count-ne0){throw 'controller parse failed'};$execution=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-CargoCapTenExecution'},$true));if($execution.Count-ne1 -or $execution[0].Extent.Text-notmatch'Test-CargoCapTenCompleteSave \$sourceSave' -or $execution[0].Extent.Text-notmatch'Test-CargoCapTenCompleteSave \$candidateSave'){throw 'execution predicate does not require completed ZIPs'}
}
Add-Check 'Execute refuses before context when frozen helpers or bindings are unavailable and preserves the output path' {
    $compatiblePacket=if((Get-CargoCapTenHostPlatform)-ceq'Windows'){$WindowsPacketPath}else{$PacketPath};$out=Join-Path $OutputRoot 'execute-with-missing-bindings.json'
    $errorText='';try{Invoke-CargoCapTenExecutor -RequestedMode Execute -RequestedPacketPath $compatiblePacket -RepoRoot $repo -RequestedOutputPath $out|Out-Null}catch{$errorText=$_.Exception.Message}
    Require-CargoCapTen ($errorText -match 'helper .+ (bytes differ|SHA-256 differs)|Execute refuses missing local bindings') "unavailable input refusal differs: $errorText"
    if(Test-Path -LiteralPath $out){throw 'unavailable-input Execute wrote an output receipt'}
}
Add-Check 'post-activation cleanup closes one owned activation and surfaces restoration failure' {
    function script:Complete-MIRLibraryActivation {param($Activation) if($Activation.fail){throw 'synthetic restoration failure'};$Activation.closed=$true;[ordered]@{status='restored'}}
    try {
        $state=[ordered]@{activation=[pscustomobject]@{closed=$false;fail=$false}};$records=[Collections.Generic.List[object]]::new();Complete-CargoCapTenActivation -Execution $state -Restoration $records;Assert-CargoCapTenEqual $state.activation $null 'closed activation';Assert-CargoCapTenEqual $records.Count 1 'restoration count'
        $bad=[ordered]@{activation=[pscustomobject]@{closed=$false;fail=$true}};Assert-Refuses -Contains 'synthetic restoration failure' -Action {Complete-CargoCapTenActivation -Execution $bad -Restoration ([Collections.Generic.List[object]]::new())}
    } finally {Remove-Item function:Complete-MIRLibraryActivation -ErrorAction SilentlyContinue}
}
Add-Check 'the execution boundary writes a failed context result after cleanup instead of treating a restoration path as success' {
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($ControllerPath,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne0){throw 'controller parse failed'}
    $execution=@($ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-ceq'Invoke-CargoCapTenExecution'},$true))
    if($execution.Count-ne1-or$execution[0].Extent.Text-notmatch'failed-retained-adverse'-or$execution[0].Extent.Text-notmatch'Write-MIRNativeProbeResult'-or$execution[0].Extent.Text-notmatch'Complete-CargoCapTenActivation'){throw 'executor lost the failed-result cleanup boundary'}
}
Add-Check 'receipt creation is exclusive and cannot replace custody' {
    $path=Join-Path $OutputRoot 'exclusive-receipt.json';Write-CargoCapTenReceipt $path ([ordered]@{first=$true});Assert-Refuses -Contains 'already exists' -Action {Write-CargoCapTenReceipt $path ([ordered]@{second=$true})};$value=Read-CargoCapTenJson $path;Assert-CargoCapTenEqual $value.first $true 'retained receipt'
}

$result=[ordered]@{schema=1;kind='MIRWorkerStorageSECargoCapTenNativeHostControlV1';controller_sha256=(Get-CargoCapTenSha256 $ControllerPath);packet_sha256=(Get-CargoCapTenSha256 $PacketPath);checks=@($script:checks);passed=(@($script:checks|Where-Object passed).Count);total=$script:checks.Count;native_processes_started=0;limit='Host-only packet, marker, copy, cleanup, and refusal controls. No engine, resource context, direct-library activation, console write, save created by Factorio, or gameplay result was produced.'}
$resultPath=Join-Path $OutputRoot 'result.json';Write-CargoCapTenReceipt $resultPath $result
if($result.passed-ne$result.total){throw 'cargo cap-ten host controls did not all pass'}
[pscustomobject]$result
