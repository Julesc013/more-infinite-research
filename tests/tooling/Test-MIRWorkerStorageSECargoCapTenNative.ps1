[CmdletBinding()]
param(
    [string]$ControllerPath,
    [string]$PacketPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if([string]::IsNullOrWhiteSpace($ControllerPath)){$ControllerPath=Join-Path $repo 'tools/Invoke-WorkerStorageSECargoCapTenNative.ps1'}
if([string]::IsNullOrWhiteSpace($PacketPath)){$PacketPath=Join-Path $repo 'tests/fixtures/worker-storage-se-cap-ten-native.json'}
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path $repo ('build/tmp/worker-storage-se-cap-ten-native-controls-'+[guid]::NewGuid().ToString('N'))}
if(-not(Test-Path -LiteralPath $ControllerPath -PathType Leaf)){throw "controller is missing: $ControllerPath"}
if(-not(Test-Path -LiteralPath $PacketPath -PathType Leaf)){throw "packet is missing: $PacketPath"}
if(Test-Path -LiteralPath $OutputRoot){throw "refusing to overwrite control output: $OutputRoot"}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
. $ControllerPath

$script:checks=[Collections.Generic.List[object]]::new()
function Add-Check { param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$Action) try{&$Action;[void]$script:checks.Add([ordered]@{name=$Name;passed=$true})}catch{[void]$script:checks.Add([ordered]@{name=$Name;passed=$false;error=$_.Exception.Message});throw} }
function Assert-Refuses { param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Contains) $seen=$false;try{&$Action}catch{$seen=$true;if($_.Exception.Message-notmatch[regex]::Escape($Contains)){throw "refusal had unexpected text '$($_.Exception.Message)', expected '$Contains'"}};if(-not$seen){throw "expected refusal containing '$Contains'"} }
function Copy-HashTable { param($Value) (($Value|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable -Depth 100) }
function Write-Text { param([string]$Path,[string]$Text) [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
function New-SyntheticSave { param([string]$Path,[string]$Payload) $zip=$null;$writer=$null;try{$zip=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create);$entry=$zip.CreateEntry('level.dat');$writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false));$writer.Write($Payload)}finally{if($null-ne$writer){$writer.Dispose()};if($null-ne$zip){$zip.Dispose()}} }
function New-CargoLogLine { param([string]$Phase,[int]$Tick,[string]$Level,[string]$Current,[string]$Progress,[string]$Queue,[string]$Ordinary,[hashtable]$Extra=@{}) $fields=@('[MIR_SE_CARGO_NATIVE]',"phase=$Phase","tick=$Tick","level=$Level","current=$Current","progress=$Progress","queue=$Queue","ordinary=$Ordinary",'settings_file_values=true');foreach($key in @($Extra.Keys|Sort-Object)){$fields+="$key=$($Extra[$key])"};$fields-join'|' }
function New-SyntheticCargoChain {
    param([string]$Root)
    [IO.Directory]::CreateDirectory($Root)|Out-Null
    $sourceSave=Join-Path $Root 'protected-source.zip';New-SyntheticSave $sourceSave 'source'
    $candidateSave=Join-Path $Root 'protected-candidate.zip';New-SyntheticSave $candidateSave 'candidate'
    $candidateWorking=Join-Path $Root 'candidate-working.zip';[IO.File]::Copy($sourceSave,$candidateWorking,$false)
    $coldOne=Join-Path $Root 'cold-one-working.zip';$coldTwo=Join-Path $Root 'cold-two-working.zip';[IO.File]::Copy($candidateSave,$coldOne,$false);[IO.File]::Copy($candidateSave,$coldTwo,$false)
    $queue='worker-robots-storage-4,worker-robots-storage-4,mir-fixture-worker-storage-se-cap-ten-tail'
    $sourceLog=Join-Path $Root 'source.log';Write-Text $sourceLog ((New-CargoLogLine source-begin 10 4 'worker-robots-storage-4' 0 $queue 0)+"`n"+(New-CargoLogLine source-partial 60 9 'worker-robots-storage-4' .42 $queue 5 @{partial='.42';save='mir5-se-worker-storage-cap10-source'})+"`n")
    $candidateLog=Join-Path $Root 'candidate.log';Write-Text $candidateLog ((New-CargoLogLine candidate-pre-work 2 9 'worker-robots-storage-4' .42 $queue 5 @{source_partial='.42'})+"`n"+(New-CargoLogLine candidate-closed 20 11 'false' 0 '' 5 @{candidate_events='2';cap_attempt='refused';save='mir5-se-worker-storage-cap10-candidate'})+"`n")
    $coldOneLog=Join-Path $Root 'cold-one.log';$coldTwoLog=Join-Path $Root 'cold-two.log';Write-Text $coldOneLog ((New-CargoLogLine cold-read 1 11 'false' 0 '' 5 @{cold_writes='0'})+"`n");Write-Text $coldTwoLog ((New-CargoLogLine cold-read 1 11 'false' 0 '' 5 @{cold_writes='0'})+"`n")
    [ordered]@{
        source=[ordered]@{run=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=$true;exit_code=137};log=$sourceLog;protected_save=$sourceSave}
        candidate=[ordered]@{run=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=$true;exit_code=137};log=$candidateLog;working_input=$candidateWorking;protected_save=$candidateSave}
        cold1=[ordered]@{name='cold-1';run=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0};working_input=$coldOne;log=$coldOneLog}
        cold2=[ordered]@{name='cold-2';run=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0};working_input=$coldTwo;log=$coldTwoLog}
    }
}

$packet=Read-CargoCapTenJson $PacketPath

Add-Check 'packet pins the full F200 source/candidate/File-settings/actor closure' {
    Assert-CargoCapTenPacket -Packet $packet -RepoRoot $repo
}
Add-Check 'Compose defers missing local bindings without context or direct-library activation' {
    $out=Join-Path $OutputRoot 'compose.json';$receipt=Invoke-CargoCapTenExecutor -RequestedMode Compose -RequestedPacketPath $PacketPath -RepoRoot $repo -RequestedOutputPath $out
    Assert-CargoCapTenEqual $receipt.status 'COMPOSED_DEFERRED_MISSING_LOCAL_BINDINGS' 'Compose status';Assert-CargoCapTenEqual $receipt.native_processes_started 0 'Compose native processes';Assert-CargoCapTenEqual $receipt.library_activation $false 'Compose activation';Assert-CargoCapTenEqual $receipt.resource_context_allocated $false 'Compose context'
}
Add-Check 'wrong File settings, actor, engine, and archive identities refuse before an owner can execute' {
    $mutations=@(
        @('settings SHA-256',{param($p)$p.inputs.settings.sha256='0'*64},'File settings SHA-256'),
        @('actor control SHA-256',{param($p)$p.inputs.actor_members[0].sha256='0'*64},'actor member SHA-256'),
        @('engine SHA-256',{param($p)$p.inputs.engine.factorio_binary_sha256='0'*64},'engine SHA-256'),
        @('candidate archive SHA-256',{param($p)$p.inputs.candidate_mir.sha256='0'*64},'candidate MIR SHA-256')
    )
    foreach($row in $mutations){$mutated=Copy-HashTable $packet;&$row[1] $mutated;Assert-Refuses -Contains $row[2] -Action {Assert-CargoCapTenPacket -Packet $mutated -RepoRoot $repo}}
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
    $changed=New-SyntheticCargoChain (Join-Path $OutputRoot 'cold-write');Write-Text $changed.cold2.log ((New-CargoLogLine cold-read 1 11 false 0 '' 5 @{cold_writes='1'})+"`n");Assert-Refuses -Contains 'cold no writes' -Action {Read-CargoCapTenCompleteChain $changed|Out-Null}
    $aliased=New-SyntheticCargoChain (Join-Path $OutputRoot 'aliased-cold');$aliased.cold1.working_input=$aliased.candidate.protected_save;Assert-Refuses -Contains 'reuses protected pathname' -Action {Read-CargoCapTenCompleteChain $aliased|Out-Null}
}
Add-Check 'Execute refuses before context when bindings are absent and preserves the requested output path' {
    $out=Join-Path $OutputRoot 'execute-with-missing-bindings.json';Assert-Refuses -Contains 'Execute refuses missing local bindings' -Action {Invoke-CargoCapTenExecutor -RequestedMode Execute -RequestedPacketPath $PacketPath -RepoRoot $repo -RequestedOutputPath $out|Out-Null};if(Test-Path -LiteralPath $out){throw 'missing-binding Execute wrote an output receipt'}
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
