# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$root=Join-Path $repo ('build/tmp/direct-library-startup-controls-'+[guid]::NewGuid().ToString('N'))
$assertions=0
function Assert-DirectStartup([bool]$Condition,[string]$Message){if(-not $Condition){throw "Direct-library startup controls: $Message"};$script:assertions++}
$startupCaller=(Get-Command Invoke-MIRDirectLibraryStartupMeasurement).ScriptBlock.Ast
foreach($name in @('Invoke-MIRDirectLibraryStartupSample','Invoke-MIRDirectLibraryPlayerReadyPreparation')){
  $calls=@($startupCaller.FindAll({param($node) $node-is[Management.Automation.Language.CommandAst]-and$node.GetCommandName()-ceq$name},$true))
  $seedBindings=@($calls|ForEach-Object {$_.CommandElements|Where-Object {$_-is[Management.Automation.Language.CommandParameterAst]-and$_.ParameterName-ceq'MapGenerationSeed'}})
  Assert-DirectStartup ($calls.Count-eq1-and$seedBindings.Count-eq1-and(Get-Command $name).Parameters.ContainsKey('MapGenerationSeed')) "The actual $name caller must bind the declared deterministic seed parameter."
}
function Write-TestArchive([string]$Library,[string]$Version){
  $archive=Join-Path $Library ('more-infinite-research_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
  try{
    $entry=$zip.CreateEntry('more-infinite-research_'+$Version+'/info.json')
    $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
    try{$writer.Write((@{name='more-infinite-research';version=$Version;factorio_version='2.0';dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
  }finally{$zip.Dispose()}
  return $archive
}
function Write-PlayerReadyObserverArchive([string]$Library,[string]$Name='mir423-player-ready-observer',[string]$Version='1.0.0',[string[]]$Dependencies=@('base')){
  $archive=Join-Path $Library ($Name+'_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
  try{
    $root=$Name+'_'+$Version
    foreach($entryText in @(
      @{path='info.json';text=(@{name=$Name;version=$Version;factorio_version='2.0';dependencies=$Dependencies}|ConvertTo-Json -Compress)},
      @{path='control.lua';text='log("[MIR_ACTIVE_MODS] base@2.0.77|mir423-player-ready-observer@1.0.0"); log("[MIR_PLAYER_READY] {\"schema\":1,\"kind\":\"mir423-player-ready-observer\",\"status\":\"passed\",\"connected_players\":1,\"native_players\":1,\"gui_root_valid\":true,\"first_usable_tick\":1}")'}
    )){
      $entry=$zip.CreateEntry($root+'/'+$entryText.path)
      $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
      try{$writer.Write([string]$entryText.text)}finally{$writer.Dispose()}
    }
  }finally{$zip.Dispose()}
  return $archive
}
try{
  $library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';[IO.Directory]::CreateDirectory($library)|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $data 'base'))|Out-Null
  [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),(@{name='base';version='2.0.77';dependencies=@()}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $published=Write-TestArchive -Library $library -Version '4.2.20002';$candidate=Write-TestArchive -Library $library -Version '4.2.20003'
  $playerReadyArchive=Write-PlayerReadyObserverArchive -Library $library
  $publishedSha=Get-MIRImmutableInputSha256 -Path $published;$manifest=Join-Path $root 'mir-4.2.2.release.json'
  [IO.File]::WriteAllText($manifest,(@{schema=1;release=@{source_version='4.2.2'};package_assets=@(@{target='f200';distribution_version='4.2.20002';sha256=$publishedSha})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $template=Join-Path $root 'profile.json';[IO.File]::WriteAllText($template,(@{mods=@(@{name='base';version='2.0.77';enabled=$true},@{name='more-infinite-research';version='4.2.20002';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $publishedIdentity=Get-MIRDirectLibraryStartupArchive -Archive $published -LibraryDirectory $library;$candidateIdentity=Get-MIRDirectLibraryStartupArchive -Archive $candidate -LibraryDirectory $library
  Assert-DirectStartup ($publishedIdentity.version-ceq'4.2.20002'-and$candidateIdentity.version-ceq'4.2.20003') 'archive identities were not read from selected library bytes.'
  $publishedManifest=Assert-MIRDirectLibraryPublished422Manifest -ManifestPath $manifest -ExpectedSha256 (Get-MIRImmutableInputSha256 -Path $manifest) -PublishedArchive $publishedIdentity -Target f200
  Assert-DirectStartup ($publishedManifest.source_version-ceq'4.2.2'-and$publishedManifest.archive_sha256-ceq$publishedIdentity.sha256) 'published package was not authenticated against its explicit manifest hash.'
  $base=@(Read-MIRDirectLibraryStartupProfile -Path $template)
  Assert-DirectStartup ($base.Count-eq1-and$base[0].name-ceq'base') 'no-MIR profile did not remove only MIR.'
  $selection=Join-Path $root 'selection.json';Write-MIRDirectLibraryStartupProfile -Path $selection -BaseRows $base -MirArchive $candidateIdentity
  $selected=Get-Content -Raw -LiteralPath $selection|ConvertFrom-Json
  Assert-DirectStartup ((@($selected.mods|Where-Object {$_.enabled}).name-join'|')-ceq'base|more-infinite-research'-and(@($selected.mods|Where-Object name -CEQ 'more-infinite-research')[0].version-ceq'4.2.20003')) 'candidate selection was not explicitly version-pinned.'
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -MirArchive $candidateIdentity
  Assert-DirectStartup ($hashes.Count-eq1-and$hashes.ContainsKey('more-infinite-research_4.2.20003.zip')-and$hashes['more-infinite-research_4.2.20003.zip']-ceq$candidateIdentity.sha256) 'selected archive hash set is incomplete or mutable.'
  $playerReady=Get-MIRDirectLibraryPlayerReadyObserverArchive -Archive $playerReadyArchive -LibraryDirectory $library -Target f200
  Assert-DirectStartup ($playerReady.name-ceq'mir423-player-ready-observer'-and$playerReady.version-ceq'1.0.0'-and$playerReady.target-ceq'f200'-and$playerReady.sha256-ceq(Get-MIRImmutableInputSha256 -Path $playerReadyArchive)) 'base-only graphical observer is not exact library input.'
  $graphicalBase=@(Add-MIRDirectLibraryPlayerReadyObserverSelection -BaseRows $base -Observer $playerReady)
  $graphicalSelection=Join-Path $root 'graphical-selection.json';Write-MIRDirectLibraryStartupProfile -Path $graphicalSelection -BaseRows $graphicalBase -MirArchive $null
  $graphicalSelected=Get-Content -Raw -LiteralPath $graphicalSelection|ConvertFrom-Json
  Assert-DirectStartup ((@($graphicalSelected.mods|Where-Object {$_.enabled}).name-join'|')-ceq'base|mir423-player-ready-observer') 'graphical observer is not selected identically for the no-MIR arm.'
  $graphicalHashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $graphicalBase -MirArchive $candidateIdentity
  Assert-DirectStartup ($graphicalHashes.ContainsKey('mir423-player-ready-observer_1.0.0.zip')-and$graphicalHashes['mir423-player-ready-observer_1.0.0.zip']-ceq$playerReady.sha256) 'graphical observer archive is not hash-bound with the package selection.'
  $badObserver=Write-PlayerReadyObserverArchive -Library $library -Name 'mir423-player-ready-observer-bad' -Dependencies @('base','more-infinite-research')
  $badObserverRejected=$false;try{Get-MIRDirectLibraryPlayerReadyObserverArchive -Archive $badObserver -LibraryDirectory $library -Target f200|Out-Null}catch{$badObserverRejected=$_.Exception.Message-ceq'[mir-direct-startup-player-ready-observer-dependencies]'}
  Assert-DirectStartup $badObserverRejected 'observer with non-base dependency was accepted.'
  $readyLog=Join-Path $root 'player-ready.log'
  [IO.File]::WriteAllText($readyLog,'1.250 Script @__mir423-player-ready-observer__/control.lua:1: [MIR_PLAYER_READY] {"schema":1,"kind":"mir423-player-ready-observer","status":"passed","connected_players":1,"native_players":1,"gui_root_valid":true,"first_usable_tick":1}',[Text.UTF8Encoding]::new($false))
  $ready=Read-MIRDirectLibraryPlayerReadyMarker -LogPath $readyLog
  Assert-DirectStartup ($ready.engine_log_seconds-eq1.25-and[long]$ready.marker.first_usable_tick-eq1-and[bool]$ready.marker.gui_root_valid) 'graphical player-ready marker did not bind log time and GUI root at tick one.'
  [IO.File]::WriteAllText($readyLog,'1.250 Script @__mir423-player-ready-observer__/control.lua:1: [MIR_PLAYER_READY] {"schema":1,"kind":"mir423-player-ready-observer","status":"passed","connected_players":1,"native_players":1,"gui_root_valid":false,"first_usable_tick":1}',[Text.UTF8Encoding]::new($false))
  $badReadyRejected=$false;try{Read-MIRDirectLibraryPlayerReadyMarker -LogPath $readyLog|Out-Null}catch{$badReadyRejected=$_.Exception.Message-ceq'[mir-direct-startup-player-ready-marker-gui-root]'}
  Assert-DirectStartup $badReadyRejected 'invalid graphical GUI-root marker was accepted.'
  [IO.File]::WriteAllText($readyLog,'1.250 Script @__mir423-player-ready-observer__/control.lua:1: [MIR_PLAYER_READY] {"schema":1,"kind":"mir423-player-ready-observer","status":"passed","connected_players":"1","native_players":1,"gui_root_valid":true,"first_usable_tick":1}',[Text.UTF8Encoding]::new($false))
  $stringPlayerRejected=$false;try{Read-MIRDirectLibraryPlayerReadyMarker -LogPath $readyLog|Out-Null}catch{$stringPlayerRejected=$_.Exception.Message-ceq'[mir-direct-startup-player-ready-marker-player]'}
  Assert-DirectStartup $stringPlayerRejected 'string-valued player readiness was accepted.'
  [IO.File]::WriteAllText($readyLog,'1.250 Script @__mir423-player-ready-observer__/control.lua:1: [MIR_PLAYER_READY] {"schema":1,"kind":"mir423-player-ready-observer","status":"passed","connected_players":1,"native_players":1,"gui_root_valid":"false","first_usable_tick":1.5}',[Text.UTF8Encoding]::new($false))
  $typedGuiRejected=$false;try{Read-MIRDirectLibraryPlayerReadyMarker -LogPath $readyLog|Out-Null}catch{$typedGuiRejected=$_.Exception.Message-ceq'[mir-direct-startup-player-ready-marker-gui-root]'}
  Assert-DirectStartup $typedGuiRejected 'string GUI or fractional tick readiness was accepted.'
  $outside=Join-Path $root 'outside.zip';Copy-Item -LiteralPath $candidate -Destination $outside
  $refused=$false;try{Get-MIRDirectLibraryStartupArchive -Archive $outside -LibraryDirectory $library|Out-Null}catch{$refused=$_.Exception.Message-ceq'[mir-direct-startup-archive-not-in-selected-library]'}
  Assert-DirectStartup $refused 'archive outside selected library was accepted.'
  # Startup logs omit Lua loading lines for asset-only packages. The explicit
  # observer is selected from the same hash-bound library transaction and its
  # full table remains exact; an altered observer report must fail closed.
  $observerName='mir423-startup-observer'
  $observerActivation=[pscustomobject]@{selected=@(
    [pscustomobject]@{name='base';version='2.0.77'},
    [pscustomobject]@{name=$observerName;version='1.0.0'}
  )}
  $observerLog=Join-Path $root 'observer.log'
  [IO.File]::WriteAllLines($observerLog,@(
    '0.1 Loading mod base 2.0.77 (data.lua)',
    ('0.2 Script @__'+$observerName+'__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] base@2.0.77|'+$observerName+'@1.0.0')
  ))
  $observerLoaded=@(Assert-MIRLibraryLoadedSelection -Activation $observerActivation -LogPath $observerLog -ActiveModsObserver $observerName)
  Assert-DirectStartup (($observerLoaded -join '|') -ceq ('base@2.0.77|'+$observerName+'@1.0.0')) 'asset-only observer did not establish the complete selected table.'
  [IO.File]::WriteAllLines($observerLog,@(
    '0.1 Loading mod base 2.0.77 (data.lua)',
    ('0.2 Script @__'+$observerName+'__/data-final-fixes.lua:1: [MIR_ACTIVE_MODS] base@2.0.77|'+$observerName+'@1.0.1')
  ))
  $observerRejected=$false
  try{Assert-MIRLibraryLoadedSelection -Activation $observerActivation -LogPath $observerLog -ActiveModsObserver $observerName|Out-Null}catch{$observerRejected=$_.Exception.Message-ceq'[mir-library-loaded-selection] Actual mod names/versions differ from the profile.'}
  Assert-DirectStartup $observerRejected 'mismatching observer table was accepted.'
  # Admission waiting is host-only: it repeats the existing governor's exact
  # memory/commit decision before launch and records bounded snapshots without
  # starting a native process or changing its declared reservation.
  $script:admissionOutcomes=[Collections.Generic.List[object]]::new();$script:admissionCalls=0;$script:admissionSnapshotCalls=0;$script:admissionDelayMilliseconds=0;$script:admissionDelayAtCall=0
  function Assert-MIR441ResourceAdmission {
    param($Policy,$WorkRoot,$EstimatedPeakBytes,$ExpectedPeakMemoryBytes)
    $script:admissionCalls++
    if($script:admissionDelayMilliseconds -gt 0 -and $script:admissionCalls -ge $script:admissionDelayAtCall){$delay=[int]$script:admissionDelayMilliseconds;$script:admissionDelayMilliseconds=0;Start-Sleep -Milliseconds $delay}
    if($script:admissionOutcomes.Count-eq0){throw '[mir441-resource-admission-memory]'}
    $outcome=$script:admissionOutcomes[0];$script:admissionOutcomes.RemoveAt(0)
    if($outcome -is [string]){throw $outcome}
    return [pscustomobject]@{memory=$outcome.memory;observed_at=$outcome.observed_at}
  }
  function Get-MIR441ResourceSnapshot {
    param($WorkRoot)
    $script:admissionSnapshotCalls++
    [pscustomobject][ordered]@{observed_at='2026-10-12T00:00:00.0000000+00:00';memory=[ordered]@{free_bytes=5GB;committed_bytes=4GB;commit_limit_bytes=16GB};work_volume=[ordered]@{free_bytes=80GB};system_volume=[ordered]@{free_bytes=80GB}}
  }
  $noWait=Wait-MIRDirectLibraryStartupAdmission -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) -WorkRoot $root -EstimatedPeakBytes 120MB -ExpectedPeakMemoryBytes 750MB -AdmissionWaitSeconds 0 -Phase 'host-no-wait'
  Assert-DirectStartup ($noWait.status-ceq'not-requested'-and$noWait.attempt_count-eq0-and$script:admissionCalls-eq0) 'zero admission-wait option performed a new preflight or changed the existing default path.'
  $script:admissionOutcomes.Add('[mir441-resource-admission-commit]');$script:admissionOutcomes.Add([pscustomobject]@{memory=[ordered]@{free_bytes=6GB};observed_at='2026-10-12T00:00:01.0000000+00:00'})
  $waited=Wait-MIRDirectLibraryStartupAdmission -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) -WorkRoot $root -EstimatedPeakBytes 120MB -ExpectedPeakMemoryBytes 750MB -AdmissionWaitSeconds 1 -Phase 'host-retry'
  Assert-DirectStartup ($waited.status-ceq'admitted-after-wait'-and$waited.attempt_count-eq2-and$waited.refusal_count-eq1-and$waited.last_error-ceq'[mir441-resource-admission-commit]'-and$null-ne$waited.first_refusal.snapshot-and$null-ne$waited.last_refusal.snapshot-and$waited.elapsed_seconds-ge0) 'commit admission retry did not retain one bounded pre-launch refusal and exact succeeding governor decision.'
  $script:admissionOutcomes.Add('[mir441-resource-output-budget]');$unrelatedAdmissionRejected=$false
  try{Wait-MIRDirectLibraryStartupAdmission -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) -WorkRoot $root -EstimatedPeakBytes 120MB -ExpectedPeakMemoryBytes 750MB -AdmissionWaitSeconds 1 -Phase 'host-unrelated'|Out-Null}catch{$unrelatedAdmissionRejected=$_.Exception.Message-ceq'[mir441-resource-output-budget]'}
  Assert-DirectStartup $unrelatedAdmissionRejected 'admission wait retried an unrelated output/path governor failure.'
  $script:admissionOutcomes.Add('[mir441-resource-admission-memory]');$script:admissionOutcomes.Add('[mir441-resource-admission-memory]');$capacityTimeoutError='';$capacityTimeoutRecord=$null
  try{Wait-MIRDirectLibraryStartupAdmission -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) -WorkRoot $root -EstimatedPeakBytes 120MB -ExpectedPeakMemoryBytes 750MB -AdmissionWaitSeconds 1 -Phase 'host-timeout'|Out-Null}catch{$capacityTimeoutError=$_.Exception.Message;$capacityTimeoutRecord=$_.Exception.Data['mir_direct_startup_admission_wait']}
  Assert-DirectStartup ($capacityTimeoutError-ceq'[mir441-resource-admission-memory]'-and$null-ne$capacityTimeoutRecord-and$capacityTimeoutRecord.status-ceq'capacity-timeout'-and$capacityTimeoutRecord.refusal_count-ge2-and$capacityTimeoutRecord.first_refusal.error-ceq'[mir441-resource-admission-memory]'-and$capacityTimeoutRecord.last_refusal.error-ceq'[mir441-resource-admission-memory]') 'admission wait obscured the original exhausted-memory disposition or lost bounded timeout evidence.'
  # The governor owns both pre-start admissions.  Exercise the real guarded
  # actor with a controlled admission sequence: first check admits, the
  # under-lock check refuses, then the same phase deadline admits before one
  # child starts.  This is deliberately not a retry of a launched process.
  function Add-DirectAdmissionOutcomes([object[]]$Values){
    $script:admissionOutcomes.Clear()
    foreach($value in $Values){$script:admissionOutcomes.Add($value)}
  }
  $admitted=[pscustomobject]@{memory=[ordered]@{free_bytes=6GB};observed_at='2026-10-12T00:00:02.0000000+00:00'}
  $nativePolicy=[pscustomobject]@{minimum_free_ram_gib=4}
  $nativeBin=(Get-Command pwsh).Source
  $prelaunchMarker=Join-Path $root 'prelaunch-once.marker'
  Add-DirectAdmissionOutcomes @($admitted,'[mir441-resource-admission-memory]',$admitted,$admitted,$admitted,$admitted,$admitted,$admitted)
  $script:admissionDelayMilliseconds=3500
  # Delay the under-lock check, after the old governor started its watchdog.
  # Delaying only the first admission would not detect that clock defect.
  $script:admissionDelayAtCall=$script:admissionCalls+2
  $prelaunchWait=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds 6 -Phase 'controlled-prelaunch'
  $prelaunchCommand="[IO.File]::WriteAllText('$prelaunchMarker','started'); Start-Sleep -Milliseconds 600"
  $prelaunchRun=Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command',$prelaunchCommand) -WorkRoot $root -LedgerPath (Join-Path $root 'prelaunch.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 3 -PreStartAdmissionWait $prelaunchWait
  Assert-DirectStartup ($prelaunchRun.passed-and(Test-Path -LiteralPath $prelaunchMarker)-and$prelaunchWait.status-ceq'admitted-after-wait'-and$prelaunchWait.attempt_count-eq3-and$prelaunchWait.refusal_count-eq1-and$null-ne$prelaunchRun.admission_wait) 'governor did not retain one deadline across admitted/refused/admitted pre-launch checks.'
  Assert-DirectStartup ($prelaunchWait.elapsed_seconds-ge3.5-and$prelaunchRun.duration_seconds-lt3) 'pre-start delay must exceed the native timeout while the child itself completes within that timeout.'
  $timeoutMarker=Join-Path $root 'timeout-not-started.marker'
  Add-DirectAdmissionOutcomes @('[mir441-resource-admission-memory]')
  $timeoutWait=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds 1 -Phase 'controlled-timeout';$timeoutStarted=[DateTimeOffset]::UtcNow.AddSeconds(-2);$timeoutWait.started_at=$timeoutStarted.ToString('o');$timeoutWait.deadline_at=$timeoutStarted.AddSeconds(1).ToString('o')
  $timeoutError=$null;$timeoutAlias=$null
  try{Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command',("[IO.File]::WriteAllText('$timeoutMarker','started')")) -WorkRoot $root -LedgerPath (Join-Path $root 'timeout.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 5 -PreStartAdmissionWait $timeoutWait|Out-Null}catch{$timeoutError=$_.Exception.Message;$timeoutAlias=$_.Exception.Data['mir441_prestart_admission_wait']}
  Assert-DirectStartup ($timeoutError-ceq'[mir441-resource-admission-wait-timeout]'-and$timeoutAlias-eq$timeoutWait-and$timeoutWait.status-ceq'capacity-timeout'-and-not(Test-Path -LiteralPath $timeoutMarker)) 'governor timeout launched a child or lost its canonical pre-start wait receipt.'
  $invalidDeadline=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds 1 -Phase 'forged-deadline';$invalidStarted=[DateTimeOffset]::Parse([string]$invalidDeadline.started_at);$invalidDeadline.deadline_at=$invalidStarted.AddSeconds(2).ToString('o');$invalidDeadlineError=''
  try{Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command','exit 0') -WorkRoot $root -LedgerPath (Join-Path $root 'forged-deadline.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 5 -PreStartAdmissionWait $invalidDeadline|Out-Null}catch{$invalidDeadlineError=$_.Exception.Message}
  Assert-DirectStartup ($invalidDeadlineError-ceq'[mir441-resource-prestart-wait-state]') 'governor accepted a pre-start wait state whose deadline was extended beyond its admitted budget.'
  $forgedZero=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds 0 -Phase 'forged-zero';$forgedZeroError=''
  try{Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command','exit 0') -WorkRoot $root -LedgerPath (Join-Path $root 'forged-zero.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 5 -PreStartAdmissionWait $forgedZero|Out-Null}catch{$forgedZeroError=$_.Exception.Message}
  Assert-DirectStartup ($forgedZeroError-ceq'[mir441-resource-prestart-wait-state]') 'governor accepted a zero-second pre-start wait state and bypassed its admission guards.'
  $diskMarker=Join-Path $root 'disk-not-started.marker'
  Add-DirectAdmissionOutcomes @('[mir441-resource-admission-system-disk]')
  $diskWait=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds 1 -Phase 'controlled-disk';$diskError=''
  try{Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command',("[IO.File]::WriteAllText('$diskMarker','started')")) -WorkRoot $root -LedgerPath (Join-Path $root 'disk.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 5 -PreStartAdmissionWait $diskWait|Out-Null}catch{$diskError=$_.Exception.Message}
  Assert-DirectStartup ($diskError-ceq'[mir441-resource-admission-system-disk]'-and$diskWait.attempt_count-eq1-and-not(Test-Path -LiteralPath $diskMarker)) 'governor retried a non-memory pre-start refusal or launched a child.'
  $defaultMarker=Join-Path $root 'default-once.marker'
  Add-DirectAdmissionOutcomes @($admitted,$admitted,$admitted,$admitted,$admitted,$admitted,$admitted,$admitted)
  $defaultRun=Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command',("[IO.File]::WriteAllText('$defaultMarker','started')")) -WorkRoot $root -LedgerPath (Join-Path $root 'default.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 5
  Assert-DirectStartup ($defaultRun.passed-and(Test-Path -LiteralPath $defaultMarker)-and$null-eq$defaultRun.PSObject.Properties['admission_wait']) 'default governed actor changed its immediate-admission result shape or launch behavior.'
  $postlaunchMarker=Join-Path $root 'postlaunch-once.marker'
  Add-DirectAdmissionOutcomes @($admitted,$admitted,'[mir441-resource-admission-memory]')
  $postlaunchWait=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds 1 -Phase 'controlled-postlaunch';$postlaunchError=''
  try{Invoke-MIR441MonitoredProcess -FilePath $nativeBin -Arguments @('-NoProfile','-Command',("[IO.File]::WriteAllText('$postlaunchMarker','started'); Start-Sleep -Seconds 3")) -WorkRoot $root -LedgerPath (Join-Path $root 'postlaunch.resources.jsonl') -Policy $nativePolicy -EstimatedPeakBytes 64KB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 5 -PreStartAdmissionWait $postlaunchWait|Out-Null}catch{$postlaunchError=$_.Exception.Message}
  Assert-DirectStartup ($postlaunchError-ceq'[mir441-resource-admission-memory]'-and(Test-Path -LiteralPath $postlaunchMarker)-and([IO.File]::ReadAllText($postlaunchMarker)-ceq'started')-and$postlaunchWait.attempt_count-eq2-and$postlaunchWait.refusal_count-eq0) 'governor retried after a post-launch admission error.'
  # Exercise the graphical diagnostic's narrow launch shape without starting
  # Factorio. The native process, library transaction and loaded-selection
  # actor are replaced only inside this host control.
  $script:graphicalArguments=@();$script:mutatePreparedSave=$false
  $script:graphicalObserverSelection=[pscustomobject]@{name=$playerReady.name;version=$playerReady.version;path=$playerReady.path;sha256=$playerReady.sha256;builtin=$false}
  function Start-MIRLibraryActivation {param($LibraryDirectory,$EngineDataDirectory,$ProfilePath,$ArchiveHashes,$SettingsMode)[pscustomobject]@{library=$LibraryDirectory;selected=@($script:graphicalObserverSelection);closed=$false}}
  function Add-MIRNativeProbeLibraryActivation {param($Context,$Activation)}
  function Complete-MIRLibraryActivation {param($Activation);$Activation.closed=$true;[pscustomobject]@{status='restored'}}
  function Assert-MIRLibraryLaunch {param($Activation,$FactorioBin,$Arguments);$script:graphicalArguments=@($Arguments)}
  function Assert-MIRLibraryLoadedSelection {param($Activation,$LogPath,[switch]$LatestInvocation,$ActiveModsObserver,[ValidateSet('data-final-fixes.lua','control.lua')]$ActiveModsObserverScript='data-final-fixes.lua');if($ActiveModsObserverScript-cne'control.lua'){throw 'Graphical player-ready observer must explicitly select control.lua.'};@('base@2.0.77',$ActiveModsObserver+'@1.0.0')}
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds)
    $config=[string]$Arguments[[Array]::IndexOf($Arguments,'--config')+1]
    $writeData=[regex]::Match((Get-Content -Raw -LiteralPath $config),'(?m)^write-data=(?<path>.+)$').Groups['path'].Value
    [IO.Directory]::CreateDirectory($writeData)|Out-Null
    [IO.File]::WriteAllText((Join-Path $writeData 'factorio-current.log'),'1.250 Script @__mir423-player-ready-observer__/control.lua:1: [MIR_PLAYER_READY] {"schema":1,"kind":"mir423-player-ready-observer","status":"passed","connected_players":1,"native_players":1,"gui_root_valid":true,"first_usable_tick":1}',[Text.UTF8Encoding]::new($false))
    if($script:mutatePreparedSave){$save=[string]$Arguments[[Array]::IndexOf($Arguments,'--benchmark-graphics')+1];[IO.File]::AppendAllText($save,'mutated',[Text.UTF8Encoding]::new($false))}
    $ledger=Join-Path $Context.root 'mock-graphical-ledger.json';[IO.File]::WriteAllText($ledger,'{}',[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{result=[pscustomobject]@{passed=$true;timed_out=$false;exit_code=0;duration_seconds=2.5;peak_working_set_bytes=1024;peak_sampled_private_bytes=512};ledger=$ledger}
  }
  $prepared=Join-Path $root 'prepared-neutral.zip';[IO.File]::WriteAllText($prepared,'fixture',[Text.UTF8Encoding]::new($false))
  $preparedSha=Get-MIRImmutableInputSha256 -Path $prepared
  $graphicalResult=Invoke-MIRDirectLibraryGraphicalPlayerReadySample -FactorioBin (Join-Path $root 'factorio.exe') -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $graphicalBase -RunRoot (Join-Path $root 'graphical-run') -WriteDataRoot (Join-Path $root 'graphical-write-data') -PreparedSave $prepared -PreparedSaveSha256 $preparedSha -Label 'without-mir' -Resources ([pscustomobject]@{root=$root}) -MirArchive $null -TimeoutSeconds 30 -PlayerReadyBenchmarkTicks 60 -ActiveModsObserver $playerReady.name
  Assert-DirectStartup ($graphicalResult.endpoint_class-ceq'graphical-player-ready-diagnostic'-and$graphicalResult.elapsed_seconds-eq2.5-and$graphicalResult.engine_log_player_ready_seconds-eq1.25-and$graphicalResult.player_ready_marker.gui_root_valid-and$graphicalResult.prepared_save_sha256_before-ceq$preparedSha-and$graphicalResult.prepared_save_sha256_after-ceq$preparedSha-and$graphicalResult.active_mods_observer.sha256-ceq$playerReady.sha256-and$graphicalResult.ready_endpoint.Contains('not a main-menu')) 'graphical diagnostic did not distinguish the usable-player marker from whole-process elapsed and immutable prepared-save evidence.'
  $wrongSaveRejected=$false;try{Invoke-MIRDirectLibraryGraphicalPlayerReadySample -FactorioBin (Join-Path $root 'factorio.exe') -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $graphicalBase -RunRoot (Join-Path $root 'graphical-wrong-save') -WriteDataRoot (Join-Path $root 'graphical-wrong-save-data') -PreparedSave $prepared -PreparedSaveSha256 ('0'*64) -Label 'without-mir' -Resources ([pscustomobject]@{root=$root}) -MirArchive $null -TimeoutSeconds 30 -PlayerReadyBenchmarkTicks 60 -ActiveModsObserver $playerReady.name|Out-Null}catch{$wrongSaveRejected=$_.Exception.Message-ceq'[mir-direct-startup-player-ready-prepared-save-before]'}
  Assert-DirectStartup $wrongSaveRejected 'mismatched preparation save identity was accepted.'
  $script:mutatePreparedSave=$true;$mutatedSaveRejected=$false;try{Invoke-MIRDirectLibraryGraphicalPlayerReadySample -FactorioBin (Join-Path $root 'factorio.exe') -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $graphicalBase -RunRoot (Join-Path $root 'graphical-mutated-save') -WriteDataRoot (Join-Path $root 'graphical-mutated-save-data') -PreparedSave $prepared -PreparedSaveSha256 $preparedSha -Label 'without-mir' -Resources ([pscustomobject]@{root=$root}) -MirArchive $null -TimeoutSeconds 30 -PlayerReadyBenchmarkTicks 60 -ActiveModsObserver $playerReady.name|Out-Null}catch{$mutatedSaveRejected=$_.Exception.Message-ceq'[mir-direct-startup-player-ready-prepared-save-after]'}finally{$script:mutatePreparedSave=$false}
  Assert-DirectStartup $mutatedSaveRejected 'prepared save changed by graphical invocation was accepted.'
  $graphicalConfig=(Get-Content -Raw -LiteralPath (Join-Path $root 'graphical-run/config.ini')).Contains('[graphics]')
  $graphicalArgumentsBound=($script:graphicalArguments -contains '--benchmark-graphics')-and($script:graphicalArguments -contains '--force-graphics-preset')-and($script:graphicalArguments -contains '--single-thread-loading')-and($script:graphicalArguments -contains '--benchmark-ticks')-and($script:graphicalArguments -notcontains '--create')
  Assert-DirectStartup ($graphicalArgumentsBound-and$graphicalConfig) 'graphical diagnostic does not retain the bounded browser graphics launch shape.'
  # The ordinary-window diagnostic must copy an actual player configuration
  # verbatim apart from the three custody controls required by the existing
  # direct-library guard. Its capture endpoint is deliberately weaker than a
  # rendered, responsive main-menu claim.
  $ordinaryConfigSource=Join-Path $root 'ordinary-player-config.ini'
  # Keep the fixture CRLF-specific: Git checkout settings must not decide
  # whether the mock INI reader is exercised against the hosted Windows form.
  $ordinaryConfigText=(@'
[path]
read-data=C:\Factorio\data
write-data=C:\Factorio\write-data

[graphics]
full-screen=true
cache-sprite-atlas=true
video-memory-usage=all

[sound]
master-volume=0.500000

[other]
enable-new-mods=true
loading-multithreading=true
'@ -replace "`r?`n","`r`n")
  Assert-DirectStartup ($ordinaryConfigText.Contains("`r`n") -and -not [regex]::IsMatch($ordinaryConfigText,'(?<!\r)\n')) 'ordinary player configuration fixture does not force CRLF.'
  [IO.File]::WriteAllText($ordinaryConfigSource,$ordinaryConfigText,[Text.UTF8Encoding]::new($false))
  $ordinaryInput=Get-MIRDirectLibraryOrdinaryPlayerConfigInput -Path $ordinaryConfigSource
  $ordinaryPrivate=Join-Path $root 'ordinary-private-config.ini'
  $ordinaryIdentity=New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput $ordinaryInput -Path $ordinaryPrivate -EngineDataDirectory $data -WriteDataDirectory (Join-Path $root 'ordinary-write-data')
  $ordinaryPrivateText=Get-Content -Raw -LiteralPath $ordinaryPrivate
  Assert-DirectStartup ($ordinaryIdentity.source.sha256-ceq$ordinaryInput.sha256-and$ordinaryPrivateText.Contains('full-screen=true')-and$ordinaryPrivateText.Contains('cache-sprite-atlas=true')-and$ordinaryPrivateText.Contains('video-memory-usage=all')-and$ordinaryPrivateText.Contains('master-volume=0.500000')-and$ordinaryPrivateText.Contains('loading-multithreading=true')-and$ordinaryPrivateText.Contains(('read-data='+$data))-and$ordinaryPrivateText.Contains(('write-data='+(Join-Path $root 'ordinary-write-data')))-and$ordinaryPrivateText.Contains('enable-new-mods=false')) 'ordinary player configuration did not preserve ordinary graphics, sound, and thread-loading choices around its private custody overrides.'
  $uppercaseOrdinaryConfig=Join-Path $root 'ordinary-player-config-uppercase.ini'
  $uppercaseOrdinaryText=$ordinaryConfigText.Replace('read-data','READ-DATA').Replace('write-data','WRITE-DATA').Replace('enable-new-mods','ENABLE-NEW-MODS')
  [IO.File]::WriteAllText($uppercaseOrdinaryConfig,$uppercaseOrdinaryText,[Text.UTF8Encoding]::new($false))
  $uppercaseOrdinaryIdentity=New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput (Get-MIRDirectLibraryOrdinaryPlayerConfigInput -Path $uppercaseOrdinaryConfig) -Path (Join-Path $root 'ordinary-private-config-uppercase.ini') -EngineDataDirectory $data -WriteDataDirectory (Join-Path $root 'ordinary-write-data-uppercase')
  Assert-DirectStartup ($uppercaseOrdinaryIdentity.overrides.enable_new_mods-eq$false-and(Get-Content -Raw -LiteralPath $uppercaseOrdinaryIdentity.private_config.path).Contains('enable-new-mods=false')) 'case-insensitive ordinary custody keys were not normalized and copied.'
  $badOrdinaryConfig=Join-Path $root 'ordinary-player-config-duplicate.ini'
  [IO.File]::WriteAllText($badOrdinaryConfig,($ordinaryConfigText -replace 'write-data=C:\\Factorio\\write-data',"READ-DATA=C:\\Factorio\\duplicate`r`nwrite-data=C:\\Factorio\\write-data"),[Text.UTF8Encoding]::new($false))
  $badOrdinaryRejected=$false;try{New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput (Get-MIRDirectLibraryOrdinaryPlayerConfigInput -Path $badOrdinaryConfig) -Path (Join-Path $root 'ordinary-private-config-duplicate.ini') -EngineDataDirectory $data -WriteDataDirectory (Join-Path $root 'ordinary-write-data')|Out-Null}catch{$badOrdinaryRejected=$_.Exception.Message-ceq'[mir-direct-startup-ordinary-player-config-keys]'}
  Assert-DirectStartup $badOrdinaryRejected 'ordinary player configuration with duplicate custody keys was accepted.'
  $script:ordinaryArguments=@();$script:ordinaryCompletionObserved=$true;$script:ordinaryLogInitialised=$true;$script:ordinaryWindowReturned=$false;$script:ordinaryObserverScript=''
  function Start-MIRLibraryActivation {param($LibraryDirectory,$EngineDataDirectory,$ProfilePath,$ArchiveHashes,$SettingsMode)[pscustomobject]@{library=$LibraryDirectory;selected=@();closed=$false}}
  function Add-MIRNativeProbeLibraryActivation {param($Context,$Activation)}
  function Complete-MIRLibraryActivation {param($Activation);$Activation.closed=$true;[pscustomobject]@{status='restored'}}
  function Assert-MIRLibraryLaunch {param($Activation,$FactorioBin,$Arguments);$script:ordinaryArguments=@($Arguments)}
  function Assert-MIRLibraryLoadedSelection {param($Activation,$LogPath,[switch]$LatestInvocation,$ActiveModsObserver,[ValidateSet('data-final-fixes.lua','control.lua')]$ActiveModsObserverScript='data-final-fixes.lua');$script:ordinaryObserverScript=$ActiveModsObserverScript;@('base@2.0.77')}
  function Get-MIRDirectLibraryOrdinaryWindowObservation {
    param($FactorioBin,$LaunchNotBefore)
    if($script:ordinaryWindowReturned){return $null}
    $script:ordinaryWindowReturned=$true;$observed=[DateTime]::UtcNow
    [pscustomobject]@{pid=123;process_started_utc=$observed.AddSeconds(-2).ToString('o');observed_utc=$observed.ToString('o');observed_seconds_since_process_start=2.0;window_handle=[int64]4321;window_visible=$true;window_minimized=$false;window_foreground=$false;capture=[pscustomobject]@{attempted=$false;succeeded=$false;print_window_returned=$false;complete='not-observable';unoccluded='not-observable';path='';sha256='';bytes=0;bounds=[ordered]@{left=1;top=2;width=640;height=480};error='automatic-window-image-not-attempted'}}
  }
  function Invoke-MIRNativeProbeFactorioProcess {
    param($Context,$FilePath,$Arguments,$TimeoutSeconds,$CompletionPredicate)
    $config=[string]$Arguments[[Array]::IndexOf($Arguments,'--config')+1]
    $writeData=[regex]::Match((Get-Content -Raw -LiteralPath $config),'(?m)^write-data=(?<path>[^\r\n]+)\r?$').Groups['path'].Value
    [IO.Directory]::CreateDirectory($writeData)|Out-Null
    $nativeLog=if($script:ordinaryLogInitialised){'1.250 Factorio initialised'}else{'0.100 Starting Factorio'}
    [IO.File]::WriteAllText((Join-Path $writeData 'factorio-current.log'),$nativeLog,[Text.UTF8Encoding]::new($false))
    $observed=if($null-ne$CompletionPredicate){[bool](& $CompletionPredicate)}else{$false}
    $ledger=Join-Path $Context.root 'mock-ordinary-ledger.json';[IO.File]::WriteAllText($ledger,'{}',[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{result=[pscustomobject]@{passed=$true;timed_out=$false;completion_predicate_observed=([bool]($observed-and$script:ordinaryCompletionObserved));exit_code=0;duration_seconds=3.5;peak_working_set_bytes=2048;peak_sampled_private_bytes=1024};ledger=$ledger}
  }
  $ordinaryResult=Invoke-MIRDirectLibraryOrdinaryWindowSample -FactorioBin (Join-Path $root 'factorio.exe') -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot (Join-Path $root 'ordinary-run') -WriteDataRoot (Join-Path $root 'ordinary-write-data-run') -Label 'without-mir' -Resources ([pscustomobject]@{root=$root}) -MirArchive $null -TimeoutSeconds 30 -OrdinaryPlayerConfig $ordinaryInput
  $forbiddenOrdinaryArguments=@('--benchmark-graphics','--force-graphics-preset','--single-thread-loading','--disable-audio','--window-size','--create')
  Assert-DirectStartup ($ordinaryResult.endpoint_class-ceq'ordinary-native-window-diagnostic'-and$ordinaryResult.menu_ready_confirmation-ceq'unavailable-from-engine-log-window-observation'-and$ordinaryResult.ready_endpoint.Contains('not proof')-and-not$ordinaryResult.window.capture.attempted-and-not$ordinaryResult.window.capture.succeeded-and$ordinaryResult.window.capture.complete-ceq'not-observable'-and$ordinaryResult.window.capture.unoccluded-ceq'not-observable'-and$ordinaryResult.window.capture.error-ceq'automatic-window-image-not-attempted'-and$ordinaryResult.ordinary_player_config.preserved_settings_sha256-ceq$ordinaryIdentity.preserved_settings_sha256-and($script:ordinaryObserverScript-ceq'data-final-fixes.lua')-and(@($forbiddenOrdinaryArguments|Where-Object {$script:ordinaryArguments-contains$_}).Count-eq0)-and($script:ordinaryArguments-contains'--config')-and($script:ordinaryArguments-contains'--mod-directory')-and($script:ordinaryArguments-contains'--no-log-rotation')) 'ordinary window diagnostic used a benchmark launch shape, omitted custody evidence, changed its data-stage observer contract, or claimed menu confirmation.'
  $script:ordinaryWindowReturned=$false;$script:ordinaryCompletionObserved=$false;$ordinaryEndpointRejected=$false
  try{Invoke-MIRDirectLibraryOrdinaryWindowSample -FactorioBin (Join-Path $root 'factorio.exe') -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot (Join-Path $root 'ordinary-run-no-endpoint') -WriteDataRoot (Join-Path $root 'ordinary-write-data-no-endpoint') -Label 'without-mir' -Resources ([pscustomobject]@{root=$root}) -MirArchive $null -TimeoutSeconds 30 -OrdinaryPlayerConfig $ordinaryInput|Out-Null}catch{$ordinaryEndpointRejected=$_.Exception.Message-ceq'[mir-direct-startup-ordinary-window-process]'}finally{$script:ordinaryCompletionObserved=$true}
  Assert-DirectStartup $ordinaryEndpointRejected 'ordinary window diagnostic accepted a native result without its selected visible-window completion predicate.'
  $script:ordinaryWindowReturned=$false;$script:ordinaryLogInitialised=$false;$ordinarySplashRejected=$false
  try{Invoke-MIRDirectLibraryOrdinaryWindowSample -FactorioBin (Join-Path $root 'factorio.exe') -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot (Join-Path $root 'ordinary-run-before-initialised') -WriteDataRoot (Join-Path $root 'ordinary-write-data-before-initialised') -Label 'without-mir' -Resources ([pscustomobject]@{root=$root}) -MirArchive $null -TimeoutSeconds 30 -OrdinaryPlayerConfig $ordinaryInput|Out-Null}catch{$ordinarySplashRejected=$_.Exception.Message-ceq'[mir-direct-startup-ordinary-window-process]'}finally{$script:ordinaryLogInitialised=$true}
  Assert-DirectStartup ($ordinarySplashRejected-and-not$script:ordinaryWindowReturned) 'ordinary window diagnostic accepted or captured a splash/loading window before the Factorio initialisation boundary.'
  $source=Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
  Assert-DirectStartup ($source.Contains('Invoke-MIRNativeProbeFactorioProcess')-and$source.Contains('Add-MIRNativeProbeLibraryActivation')-and$source.Contains('Wait-MIRDirectLibraryStartupAdmission')-and$source.Contains('AdmissionWaitSeconds')-and$source.Contains('Get-MIRNativeProbeRemainingOutputBytes')-and$source.Contains('changed-configuration')-and$source.Contains('same-selection')-and$source.Contains('prior_selection_label')-and$source.Contains('warm-repeat')-and$source.Contains('headless-create-diagnostic')-and$source.Contains('graphical-player-ready-diagnostic')-and$source.Contains('ordinary-native-window-diagnostic')-and$source.Contains('Get-MIRDirectLibraryPlayerReadyObserverArchive')-and$source.Contains('Invoke-MIRDirectLibraryPlayerReadyPreparation')-and$source.Contains('New-MIRDirectLibraryOrdinaryPlayerConfig')-and$source.Contains('automatic-window-image-not-attempted')-and$source.Contains('menu_ready_confirmation')-and$source.Contains('--benchmark-graphics')-and$source.Contains('[MIR_PLAYER_READY]')-and$source.Contains('engine_log_player_ready_seconds')-and$source.Contains('factorio-current.log')-and$source.Contains('ready-initialised')-and$source.Contains('ready-save-map-data')-and$source.Contains('run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot)')-and-not$source.Contains('PrintWindow')-and-not$source.Contains('[Diagnostics.Process]::Start')) 'runner bypasses the governed native process actor, does not bind the base-only graphical observer and its prepared save, or omits bounded pre-launch admission handling.'
  . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
  $runner=(Get-Command Invoke-MIRDirectLibraryStartupMeasurement)
  $runnerPatterns=@($runner.Parameters['StartupCandidateSourceVersion'].Attributes|Where-Object {$_ -is [Management.Automation.ValidatePatternAttribute]}|ForEach-Object RegexPattern)
  Assert-DirectStartup ($runnerPatterns.Count-eq1-and$runnerPatterns[0]-ceq'^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$') 'startup candidate source must bind the canonical source-version shape.'
  foreach($case in @(@{source='4.2.3';distribution='4.2.20003'},@{source='4.3.0';distribution='4.3.20000'},@{source='4.3.1';distribution='4.3.20001'},@{source='4.4.0';distribution='4.4.20000'},@{source='4.4.2';distribution='4.4.20002'})){
    $identity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target f200 -SourceVersion $case.source
    Assert-DirectStartup ($identity.source_version-ceq$case.source-and$identity.distribution_version-ceq$case.distribution) "startup runner cannot project $($case.source) to its f200 candidate identity."
  }
  Assert-DirectStartup ($source.Contains(". (Join-Path `$repo 'tools/mir/application/package/PackageAuthority.ps1')")-and$source.Contains(". (Join-Path `$repo 'tools/mir/application/package/TargetMaterializer.ps1')")-and$source.Contains('$candidateIdentity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $Target -SourceVersion $StartupCandidateSourceVersion')-and$source.Contains('Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateMaterializationArchive -ReceiptPath $CandidateMaterializationReceiptPath -Target $Target -SourceVersion $StartupCandidateSourceVersion')-and$source.Contains("label=('candidate-'+`$StartupCandidateSourceVersion)")-and$source.Contains('candidate=$(if($hasCandidate){[ordered]@{source_version=$StartupCandidateSourceVersion;archive=$candidate')) 'startup runner does not load its canonical identity authority or bind the selected candidate source identity through archive validation, receipt validation, label, and report input.'
  $entry=Get-Content -Raw -LiteralPath (Join-Path $repo 'scripts/Measure-MIRPerformanceRegression.ps1')
  Assert-DirectStartup ($entry.Contains('Invoke-MIRDirectLibraryStartupMeasurement')-and$entry.Contains('ObserveStartup')-and$entry.Contains('ObserveResearchAll')-and$entry.Contains('ActiveModsObserver')-and$entry.Contains('GraphicalPlayerReady')-and$entry.Contains('PlayerReadyObserverArchive')-and$entry.Contains('PlayerReadyBenchmarkTicks')-and$entry.Contains('OrdinaryMenu')-and$entry.Contains('OrdinaryPlayerConfigPath')-and$entry.Contains('AdmissionWaitSeconds')-and$entry.Contains('endpoint-mode-conflict')-and$entry.Contains('ExpectedPeakMemoryMiB')-and$entry.Contains('mir-native-obsolete-runner')) 'performance entrypoint does not preserve direct-library admission-wait forwarding around its selected endpoint mode.'
  Assert-DirectStartup ($entry.Contains("[ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]`$StartupCandidateSourceVersion='4.2.3'")-and$entry.Contains('StartupCandidateSourceVersion=$StartupCandidateSourceVersion')) 'performance entrypoint does not preserve the default or selected startup candidate source version.'
  $entryPath=Join-Path $repo 'scripts/Measure-MIRPerformanceRegression.ps1'
  $startupCliInputs=@{RepoRoot=$repo;ObserveStartup=$true;FactorioBin='fixture-factorio.exe';LocalModZipDir='fixture-library';StartupProfileTemplatePath='fixture-profile.json';Published422Archive='fixture-published.zip';Published422ManifestPath='fixture-manifest.json';Published422ManifestSha256=('0'*64);StartupOutputRoot='fixture-output';ExpectedSourceCommit=('0'*40)}
  $conflictingEndpointRejected=$false;try{& $entryPath @startupCliInputs -GraphicalPlayerReady -OrdinaryMenu|Out-Null}catch{$conflictingEndpointRejected=$_.Exception.Message-ceq'[mir-direct-startup-endpoint-mode-conflict]'}
  Assert-DirectStartup $conflictingEndpointRejected 'performance entrypoint accepted simultaneous graphical-player and ordinary-window endpoint flags.'
  $missingOrdinaryConfigRejected=$false;try{& $entryPath @startupCliInputs -OrdinaryMenu|Out-Null}catch{$missingOrdinaryConfigRejected=$_.Exception.Message-ceq'[mir-direct-startup-input-required] OrdinaryPlayerConfigPath'}
  Assert-DirectStartup $missingOrdinaryConfigRejected 'performance entrypoint accepted ordinary-window mode without an explicit player configuration input.'
  $readerPatterns=@((Get-Command Read-MIRNativeProbeCurrentCandidate).Parameters['SourceVersion'].Attributes|Where-Object {$_ -is [Management.Automation.ValidatePatternAttribute]}|ForEach-Object RegexPattern)
  Assert-DirectStartup ($readerPatterns.Count-eq1-and$readerPatterns[0]-ceq'^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$') 'native candidate receipt reader must validate canonical source-version shape.'
  $privateReadme=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes ([Text.UTF8Encoding]::new($false).GetBytes('MIR package')) -DistributionVersion '4.2.20003' -SourceVersion '4.2.3'
  Assert-DirectStartup (([Text.UTF8Encoding]::new($false).GetString($privateReadme)).StartsWith("MIR 4.2.20003, source 4.2.3.`n`n",[StringComparison]::Ordinal)) 'materializer does not support private 4.2.3 package identity presentation.'
  foreach($case in @(@{source='4.3.0';distribution='4.3.20000'},@{source='4.3.1';distribution='4.3.20001'})){
    $currentReadme=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes ([Text.UTF8Encoding]::new($false).GetBytes('MIR package')) -DistributionVersion $case.distribution -SourceVersion $case.source
    Assert-DirectStartup (([Text.UTF8Encoding]::new($false).GetString($currentReadme)).StartsWith("MIR $($case.distribution), source $($case.source).`n`n",[StringComparison]::Ordinal)) "materializer does not preserve the canonical $($case.source) package identity."
  }
  $crossMinorRejected=$false;try{Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes ([byte[]]@(65)) -DistributionVersion '4.2.20001' -SourceVersion '4.3.1'|Out-Null}catch{$crossMinorRejected=$_.Exception.Message-ceq'[mir4-private-patch-package-source-identity]'}
  Assert-DirectStartup $crossMinorRejected 'materializer accepted a distribution version from the wrong source minor.'
  # Exercise the actual orchestration with controlled process actors. The
  # predecessor actor deliberately fails if candidate-only mode touches it.
  $stressCandidate=Write-TestArchive -Library $library -Version '4.3.20000'
  $stressCandidateSha=Get-MIRImmutableInputSha256 -Path $stressCandidate
  $stressReceipt=Join-Path $root 'controlled-stress-materialization.json'
  [IO.File]::WriteAllText($stressReceipt,'{}',[Text.UTF8Encoding]::new($false))
  $stressEngine=Join-Path $root 'engine/bin/x64/factorio.exe'
  [IO.Directory]::CreateDirectory((Split-Path -Parent $stressEngine))|Out-Null
  [IO.File]::WriteAllText($stressEngine,'controlled-process-actor-not-an-engine',[Text.UTF8Encoding]::new($false))
  $script:stressCalls=[Collections.Generic.List[object]]::new();$script:stressSampleFailure=$false;$script:stressLastRecord=$null
  function Wait-MIRDirectLibraryStartupAdmission {param($Policy,$WorkRoot,$EstimatedPeakBytes,$ExpectedPeakMemoryBytes,$AdmissionWaitSeconds,$Phase);[pscustomobject]@{status='controlled-no-native-actor'}}
  function New-MIRNativeProbeResourceContext {param($RepoRoot,$OutputRoot,$ExpectedPeakMemoryMiB,$MaxNewOutputMiB,[switch]$UseExactOutputRoot);[pscustomobject]@{root=$OutputRoot;policy=[pscustomobject]@{minimum_free_ram_gib=4};peak_memory_bytes=[int64]$ExpectedPeakMemoryMiB*1MB;max_new_output_bytes=[int64]$MaxNewOutputMiB*1MB;runs=@()}}
  function Get-MIRNativeProbeRemainingOutputBytes {param($Context);[int64]1MB}
  function Read-MIRNativeProbeCurrentCandidate {
    param($Repository,$Archive,$ReceiptPath,$Target,$SourceVersion)
    [pscustomobject]@{path=$Archive;receipt=[pscustomobject]@{archive_sha256=(Get-MIRImmutableInputSha256 -Path $Archive);source_version=$SourceVersion;package_source_sha256=('0'*64);source_manifest_sha256=('0'*64)}}
  }
  function Assert-MIRDirectLibraryPublished422Manifest {throw 'Controlled predecessor must never execute in candidate-only mode.'}
  function Invoke-MIRDirectLibraryStartupSample {
    param($FactorioBin,$LibraryDirectory,$EngineDataDirectory,$BaseRows,$RunRoot,$WriteDataRoot,$Label,$Resources,$MirArchive,$TimeoutSeconds,$ActiveModsObserver,$MapGenerationSeed)
    if($script:stressSampleFailure){throw '[controlled-startup-sample-failure]'}
    $script:stressCalls.Add([pscustomobject]@{label=$Label;archive=$MirArchive;seed=$MapGenerationSeed})
    [pscustomobject]@{label=$Label;endpoint_class='headless-create-diagnostic';exit_code=0;controlled_actor=$true}
  }
  function Write-MIRNativeProbeResult {param($Context,$Record);$script:stressLastRecord=$Record}
  $stressArgs=@{FactorioBin=$stressEngine;LibraryDirectory=$library;ProfileTemplatePath=$template;CandidateArchive=$stressCandidate;CandidateMaterializationArchive=$stressCandidate;CandidateMaterializationReceiptPath=$stressReceipt;StartupCandidateSourceVersion='4.3.0';OutputRoot=(Join-Path $root 'candidate-only-run');Target='f200';WarmupRuns=0;MeasuredRuns=1;TimeoutSeconds=1;ExpectedPeakMemoryMiB=1;MaxNewOutputMiB=1;SourceCommit=(& git -C $repo rev-parse HEAD).Trim();CandidateOnly=$true}
  $stressResult=Invoke-MIRDirectLibraryStartupMeasurement @stressArgs
  Assert-DirectStartup ($stressResult.mode-ceq'candidate-only-stress-diagnostic'-and$null-eq$stressResult.inputs.baseline-and$null-eq$stressResult.inputs.published_422-and$stressResult.samples.Count-eq2) 'candidate-only orchestration invented a comparison or did not perform the selected cold/warm pair.'
  Assert-DirectStartup ($script:stressCalls.Count-eq2-and@($script:stressCalls|Where-Object {$_.label-cne'candidate-4.3.0'-or$_.archive.sha256-cne$stressCandidateSha}).Count-eq0) 'candidate-only orchestration called a baseline or a different candidate.'
  Assert-DirectStartup ($stressResult.samples[0].cache_state-ceq'initial-selection'-and$stressResult.samples[1].cache_state-ceq'warm-repeat'-and$stressResult.samples[0].sample-eq1-and$stressResult.samples[1].sample-eq2) 'candidate-only sample sequencing is not explicit.'
  Assert-DirectStartup (@($stressResult.measurement_notes|Where-Object {$_-match'no relative speedup'}).Count-eq1) 'candidate-only result lacks its comparison limitation.'
  $candidate440=Write-TestArchive -Library $library -Version '4.4.20000'
  $args440=$stressArgs.Clone();$args440.StartupCandidateSourceVersion='4.4.0';$args440.CandidateArchive=$candidate440;$args440.CandidateMaterializationArchive=$candidate440;$args440.OutputRoot=Join-Path $root 'candidate-only-440-run'
  $script:stressCalls.Clear()
  $result440=Invoke-MIRDirectLibraryStartupMeasurement @args440
  Assert-DirectStartup ($result440.inputs.candidate.source_version-ceq'4.4.0'-and$result440.inputs.candidate.materialization.source_version-ceq'4.4.0'-and$result440.samples.Count-eq2-and$script:stressCalls.Count-eq2-and@($script:stressCalls|Where-Object {$_.label-cne'candidate-4.4.0'-or$_.archive.sha256-cne(Get-MIRImmutableInputSha256 -Path $candidate440)}).Count-eq0) '4.4 orchestration lost the selected package, source identity or sample labels.'
  $wrong440=$args440.Clone();$wrong440.CandidateArchive=$stressCandidate;$wrong440.OutputRoot=Join-Path $root 'reject-440-wrong-source'
  $wrong440Rejected=$false;try{Invoke-MIRDirectLibraryStartupMeasurement @wrong440|Out-Null}catch{$wrong440Rejected=$_.Exception.Message-ceq'[mir-direct-startup-candidate-identity]'}
  Assert-DirectStartup $wrong440Rejected '4.4 measurement accepted a 4.3 candidate archive.'
  $candidate442=Write-TestArchive -Library $library -Version '4.4.20002'
  $args442=$stressArgs.Clone();$args442.StartupCandidateSourceVersion='4.4.2';$args442.CandidateArchive=$candidate442;$args442.CandidateMaterializationArchive=$candidate442;$args442.OutputRoot=Join-Path $root 'candidate-only-442-run'
  $script:stressCalls.Clear()
  $result442=Invoke-MIRDirectLibraryStartupMeasurement @args442
  Assert-DirectStartup ($result442.inputs.candidate.source_version-ceq'4.4.2'-and$result442.inputs.candidate.materialization.source_version-ceq'4.4.2'-and$result442.samples.Count-eq2-and$script:stressCalls.Count-eq2-and@($script:stressCalls|Where-Object {$_.label-cne'candidate-4.4.2'-or$_.archive.sha256-cne(Get-MIRImmutableInputSha256 -Path $candidate442)}).Count-eq0) '4.4.2 orchestration lost its exact CCC02 package, source identity, or sample labels.'
  $wrong442=$args442.Clone();$wrong442.CandidateArchive=$candidate440;$wrong442.OutputRoot=Join-Path $root 'reject-442-wrong-source'
  $wrong442Rejected=$false;try{Invoke-MIRDirectLibraryStartupMeasurement @wrong442|Out-Null}catch{$wrong442Rejected=$_.Exception.Message-ceq'[mir-direct-startup-candidate-identity]'}
  Assert-DirectStartup $wrong442Rejected '4.4.2 measurement accepted a non-CCC02 candidate archive.'
  $unadmitted443=$args442.Clone();$unadmitted443.StartupCandidateSourceVersion='4.7.0';$unadmitted443.OutputRoot=Join-Path $root 'reject-current-source-wrong-archive'
  $unadmitted443Rejected=$false;try{Invoke-MIRDirectLibraryStartupMeasurement @unadmitted443|Out-Null}catch{$unadmitted443Rejected=$_.Exception.Message-ceq'[mir-direct-startup-candidate-identity]'}
  Assert-DirectStartup $unadmitted443Rejected 'startup runner accepted a current source version paired with another version archive.'
  foreach($case in @('missing-comparison','preliminary','supplied-comparison','graphical')){
    $argsCopy=$stressArgs.Clone();$argsCopy.OutputRoot=Join-Path $root ('reject-'+$case)
    $code=switch($case){
      'missing-comparison' {$argsCopy.CandidateOnly=$false;'published-inputs'}
      'preliminary' {$argsCopy.Preliminary=$true;'candidate-only-mode'}
      'supplied-comparison' {$argsCopy.Published422Archive=$published;'candidate-only-no-comparison'}
      'graphical' {$argsCopy.GraphicalPlayerReady=$true;'candidate-only-mode'}
    }
    $rejected=$false
    try{Invoke-MIRDirectLibraryStartupMeasurement @argsCopy|Out-Null}catch{$rejected=$_.Exception.Message-ceq('[mir-direct-startup-'+$code+']')}
    Assert-DirectStartup $rejected ('candidate-only mode did not reject '+$case)
  }
  $zeroWarmupBound=$false
  try{& $entryPath @startupCliInputs -WarmupRuns 0 -StartupCandidateOnly -PreliminaryStartup|Out-Null}catch{$zeroWarmupBound=$_.Exception.Message-ceq'[mir-direct-startup-candidate-only-mode]'}
  Assert-DirectStartup $zeroWarmupBound 'actual public caller still rejects the callee zero-warmup binding before mode validation.'

  foreach($future in @(@{source='4.7.0';distribution='4.7.20000'},@{source='4.7.3';distribution='4.7.20003'},@{source='4.10.0';distribution='4.10.20000'})){
    $futureArchive=Write-TestArchive -Library $library -Version $future.distribution
    $futureArgs=$stressArgs.Clone();$futureArgs.StartupCandidateSourceVersion=$future.source;$futureArgs.CandidateArchive=$futureArchive;$futureArgs.CandidateMaterializationArchive=$futureArchive;$futureArgs.OutputRoot=Join-Path $root ('candidate-only-'+$future.source)
    $futureResult=Invoke-MIRDirectLibraryStartupMeasurement @futureArgs
    Assert-DirectStartup ($futureResult.inputs.candidate.source_version-ceq$future.source-and$futureResult.inputs.candidate.archive.version-ceq$future.distribution-and$null-eq$futureResult.inputs.baseline-and@($futureResult.samples|Where-Object label -CNE ('candidate-'+$future.source)).Count-eq0) 'Current-version orchestration lost the source/codec/archive/baseline binding.'
  }
  $failedArgs=$stressArgs.Clone();$failedArgs.OutputRoot=Join-Path $root 'candidate-only-expected-failure'
  $script:stressSampleFailure=$true;$actualFailure=''
  try{Invoke-MIRDirectLibraryStartupMeasurement @failedArgs|Out-Null}catch{$actualFailure=$_.Exception.Message}finally{$script:stressSampleFailure=$false}
  Assert-DirectStartup ($actualFailure-ceq'[controlled-startup-sample-failure]'-and$script:stressLastRecord.status-ceq'failed'-and$script:stressLastRecord.mode-ceq'candidate-only-stress-diagnostic'-and$null-eq$script:stressLastRecord.inputs.baseline) 'Candidate-only failure receipt invented a baseline or lost the original error.'

  $legacyArgs=$stressArgs.Clone();$legacyArgs.CandidateOnly=$false;$legacyArgs.BaselineSourceVersion='4.2.2';$legacyArgs.BaselineArchive=$published;$legacyArgs.BaselineManifestPath=$manifest;$legacyArgs.BaselineManifestSha256=Get-MIRImmutableInputSha256 -Path $manifest;$legacyArgs.OutputRoot=Join-Path $root 'legacy-matched-receipt'
  $legacyResult=Invoke-MIRDirectLibraryStartupMeasurement @legacyArgs
  Assert-DirectStartup ($legacyResult.inputs.published_422.archive.sha256-ceq$publishedSha-and($legacyResult.inputs.published_422|ConvertTo-Json -Depth 10 -Compress)-ceq($legacyResult.inputs.baseline|ConvertTo-Json -Depth 10 -Compress)) 'Legacy V1 baseline receipt lost its exact published_422 field.'
  $genericBaseline=Write-TestArchive -Library $library -Version '4.6.20000'
  $genericManifest=Join-Path $root 'generic-baseline-manifest.json'
  [IO.File]::WriteAllText($genericManifest,(@{schema=1;release=@{source_version='4.6.0'};package_assets=@(@{target='f200';distribution_version='4.6.20000';sha256=(Get-MIRImmutableInputSha256 -Path $genericBaseline)})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $genericArgs=$legacyArgs.Clone();$genericArgs.BaselineSourceVersion='4.6.0';$genericArgs.BaselineArchive=$genericBaseline;$genericArgs.BaselineManifestPath=$genericManifest;$genericArgs.BaselineManifestSha256=Get-MIRImmutableInputSha256 -Path $genericManifest;$genericArgs.OutputRoot=Join-Path $root 'generic-matched-receipt'
  $genericResult=Invoke-MIRDirectLibraryStartupMeasurement @genericArgs
  Assert-DirectStartup ($null-eq$genericResult.inputs.published_422-and$genericResult.inputs.baseline.archive.version-ceq'4.6.20000'-and$genericResult.inputs.baseline.authenticated_manifest.source_version-ceq'4.6.0') 'New baseline was mislabeled as historical 4.2.2.'

  foreach($noncanonical in @('4.07.0','4.7.00','4.00.0')){
    $badSpelling=$stressArgs.Clone();$badSpelling.StartupCandidateSourceVersion=$noncanonical;$badSpelling.OutputRoot=Join-Path $root ('reject-spelling-'+$noncanonical)
    $spellingRejected=$false
    try{Invoke-MIRDirectLibraryStartupMeasurement @badSpelling|Out-Null}catch{$spellingRejected=$_.FullyQualifiedErrorId-match'^ParameterArgumentValidationError'}
    Assert-DirectStartup $spellingRejected ('Noncanonical source spelling was admitted: '+$noncanonical)
  }

  [pscustomobject][ordered]@{status='MIR-DIRECT-LIBRARY-STARTUP-CONTROLS-PASSED';assertions=$assertions;engine_runs=0;archive_copies_created=0;archive_links_created=0;populated_profiles_created=0}
}finally{
  $buildPrefix=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
  if(-not [IO.Path]::GetFullPath($root).StartsWith($buildPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Preserve fixture outside the intended build workspace.'}
  if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
