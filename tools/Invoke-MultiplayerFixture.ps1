# One governed process tree owns a loopback host and two graphical clients.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ArchiveLibrary,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$ProfilePath,
  [Parameter(Mandatory)][string[]]$FixtureSources,
  [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedMIRArchiveSha256,
  [Parameter(Mandatory)][string]$OutputRoot,
  [ValidateSet('library-multiplayer','library-paired-browser','scripted-effects-multiplayer')][string]$FixtureCase='library-multiplayer',
  # The lower value is calibrated solely for the bounded F200 Library session.
  # Other multiplayer fixtures retain the existing 8 GiB process-tree ceiling.
  [ValidateSet(7168,8192)][int]$SessionExpectedPeakMemoryMiB=8192,
  [switch]$CollectProcessMemoryObservations,
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
function Assert-Session([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "[mir5-multiplayer-fixture] $Message"}
}
$output=Resolve-MIR441RecoveryScratchPath -Path $OutputRoot
Assert-Session (-not(Test-Path -LiteralPath $output) -or @(Get-ChildItem -LiteralPath $output -Force).Count -eq 0) 'output is not empty'
$engine=(Resolve-Path -LiteralPath $FactorioBin).Path
$library=(Resolve-Path -LiteralPath $ArchiveLibrary).Path
$profile=(Resolve-Path -LiteralPath $ProfilePath).Path
$selection=Get-Content -LiteralPath $profile -Raw|ConvertFrom-Json -AsHashtable
Assert-Session ($selection.target -ceq 'f200' -and $selection.engine.version -ceq '2.0.77') 'requires the exact F200 fixture'
Assert-Session ((Get-FileHash -LiteralPath $engine).Hash -ceq $selection.engine.sha256) 'engine hash differs'
Assert-Session ($FixtureCase -ceq 'library-multiplayer' -or $SessionExpectedPeakMemoryMiB -eq 8192) 'only the functional Library session may use the calibrated peak override'
$engineData=Join-Path (Get-Item -LiteralPath $engine).Directory.Parent.Parent.FullName 'data'
$preparation=Join-Path $output 'preparation'
& (Join-Path $PSScriptRoot 'Invoke-NativeFixture.ps1') -ArchiveLibrary $library -FactorioBin $engine -ProfilePath $profile -FixtureSources $FixtureSources -ExpectedMIRArchiveSha256 $ExpectedMIRArchiveSha256 -ActiveModsObserver 'mir-fixture-mir5-active-mods-observer' -CaseName $FixtureCase -OutputRoot $preparation -CreateOnly -ExpectedPeakMemoryMiB 4096 -TimeoutSeconds 180 -RepoRoot $repo | Out-Null
$prepared=Get-Content -LiteralPath (Join-Path $preparation 'result.json') -Raw|ConvertFrom-Json
Assert-Session ($prepared.status -ceq 'passed-private-native-runtime-load-only') 'native world preparation failed'
$seed=Join-Path $preparation 'write-data/saves/seed.zip'
Assert-Session ((Get-FileHash -LiteralPath $seed).Hash -ceq $prepared.seed_sha256) 'prepared seed differs'
$activation=$null;$resources=$null;$failure=$null
$record=[ordered]@{
  kind=$(switch($FixtureCase){'library-multiplayer'{'MIR5LibraryMultiplayerNativeResultV1'};'library-paired-browser'{'MIR5LibraryPairedBrowserNativeResultV1'};default{'MIR5ScriptedEffectsMultiplayerNativeResultV1'}});case=$FixtureCase;status='started';source_head=$prepared.source_head
  engine=$prepared.engine;profile=$prepared.profile;fixtures=$prepared.fixtures;mir_archive=$prepared.mir_archive
  preparation=$prepared;session_expected_peak_memory_mib=$SessionExpectedPeakMemoryMiB;release_qualification=$false;visual_review=$false
  harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
}
try {
  $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot (Join-Path $output 'session') -ExpectedPeakMemoryMiB $SessionExpectedPeakMemoryMiB -MaxNewOutputMiB 512 -UseExactOutputRoot
  $null=New-Item -ItemType Directory -Path $resources.root
  $serverWrite=Join-Path $resources.root 'server'
  $null=New-Item -ItemType Directory -Path $serverWrite
  $null=New-Item -ItemType Directory -Path (Join-Path $serverWrite 'saves')
  $serverConfig=Join-Path $resources.root 'server.ini'
  New-MIRDirectLibraryStartupConfig -Path $serverConfig -EngineDataDirectory $engineData -WriteDataDirectory $serverWrite
  $settings=Get-Content -LiteralPath (Join-Path $engineData 'server-settings.example.json') -Raw|ConvertFrom-Json -AsHashtable
  $settings.name='MIR5 private loopback clients';$settings.description=''
  $settings.visibility=@{public=$false;lan=$false};$settings.require_user_verification=$false
  foreach($name in @('username','password','token','game_password')){$settings[$name]=''}
  $settings.max_players=2;$settings.auto_pause=$false;$settings.autosave_interval=0
  $serverSettings=Join-Path $resources.root 'server-settings.json'
  [IO.File]::WriteAllText($serverSettings,($settings|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  # Let Windows allocate available loopback ports. Fixed ports can be in its
  # excluded ranges (the first native run failed with WSAEACCES/10013).
  $udpProbes=@();$tcpProbe=$null
  try {
    foreach($index in 0..2){
      $probe=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
      $probe.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0))
      $udpProbes+=,$probe
    }
    $udpPorts=@($udpProbes|ForEach-Object {[int]$_.Client.LocalEndPoint.Port})
    $tcpProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$tcpProbe.Start()
    $rconPort=[int]$tcpProbe.LocalEndpoint.Port
  } finally {
    foreach($probe in $udpProbes){$probe.Dispose()}
    if($null -ne $tcpProbe){$tcpProbe.Stop()}
  }
  $serverPort=$udpPorts[0];$clientIndex=1
  $record.loopback_ports=[ordered]@{udp=$udpPorts;rcon_tcp=$rconPort;selection='OS-assigned temporary loopback bindings, released before native start'}
  $clients=@()
  $rconPassword=[guid]::NewGuid().ToString('D')
  foreach($locale in @('en','de')){
    $write=Join-Path $resources.root ('client-'+$locale)
    $null=New-Item -ItemType Directory -Path $write
    $config=Join-Path $resources.root ('client-'+$locale+'.ini')
    New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $engineData -WriteDataDirectory $write -Graphics
    $text=[IO.File]::ReadAllText($config).Replace('locale=en',('locale='+$locale))
    [IO.File]::WriteAllText($config,$text,[Text.UTF8Encoding]::new($false))
    $name=if($locale -ceq 'en'){'MIR5English'}else{'MIR5Deutsch'}
    # Isolated disposable identities contain no online token or personal data.
    $player=@{'service-username'=$name;'service-token'='';'last-played-version'=@{game_version='2.0.77';build_version=84539;build_mode='full';platform='win64'}}
    [IO.File]::WriteAllText((Join-Path $write 'player-data.json'),($player|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $clients+=@{name=$name;locale=$locale;config=$config;write_data=$write;port=$udpPorts[$clientIndex]};$clientIndex++
  }
  $pairedArm=$null
  if($FixtureCase -ceq 'library-paired-browser'){
    Assert-Session ($selection.kind -ceq 'mir5-library-paired-browser-f200-native-selection') 'paired browser profile kind differs'
    $mirRows=@($selection.mods | Where-Object {[string]$_.name -ceq 'more-infinite-research'})
    $armRows=@($selection.mods | Where-Object {[string]$_.name -cmatch '^mir-fixture-mir5-library-paired-browser-arm-(published|mir5)$'})
    Assert-Session ($mirRows.Count -eq 1 -and $armRows.Count -eq 1) 'paired browser profile arm selection differs'
    $armName=[string]$armRows[0].name
    if($armName -ceq 'mir-fixture-mir5-library-paired-browser-arm-published' -and [string]$mirRows[0].version -ceq '4.7.20002'){$pairedArm='published'}
    elseif($armName -ceq 'mir-fixture-mir5-library-paired-browser-arm-mir5' -and [string]$mirRows[0].version -ceq '5.0.20000'){$pairedArm='mir5'}
    else{throw '[mir5-multiplayer-fixture] paired browser profile MIR arm/version differs'}
  }
  $hashes=@{};foreach($entry in $selection.archive_sha256.GetEnumerator()){$hashes[$entry.Key]=$entry.Value}
  $hashes[[IO.Path]::GetFileName([string]$prepared.mir_archive.path)]=$ExpectedMIRArchiveSha256.ToUpperInvariant()
  foreach($fixture in $prepared.fixtures){$hashes[[IO.Path]::GetFileName([string]$fixture.archive)]=$fixture.sha256}
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $engineData -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
  Add-MIRNativeProbeLibraryActivation -Context $resources -Activation $activation
  # Validate the entire fixed launch set before starting the governed tree.
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments @('--config',$serverConfig,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--start-server',$seed,'--server-settings',$serverSettings,'--bind','127.0.0.1','--port',[string]$serverPort,'--rcon-bind',('127.0.0.1:'+ $rconPort),'--rcon-password',$rconPassword)
  $clientGraphics=@(if($FixtureCase-ceq'scripted-effects-multiplayer'){'--force-graphics-preset';'low';'--video-memory-usage';'low'})
  foreach($client in $clients){Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $engine -Arguments (@('--config',$client.config,'--mod-directory',$library,'--disable-audio','--no-log-rotation','--window-size','1280x720','--mp-connect',('127.0.0.1:'+ $serverPort),'--port',[string]$client.port)+$clientGraphics)}
  $screenshots=@(
    if($FixtureCase-ceq'library-multiplayer'){
      foreach($client in $clients){foreach($stage in @('availability','initial','settled','rejoin','restart')){Join-Path $client.write_data ('script-output/mir5-library-multiplayer/'+$stage+'-*.png')}}
    }elseif($FixtureCase-ceq'library-paired-browser'){
      foreach($client in $clients){foreach($stage in @('first-open','search','refresh','reopen')){Join-Path $client.write_data ('script-output/mir5-library-paired-browser/'+$stage+'-*.png')}}
    }
  )
  $spec=[ordered]@{case=$FixtureCase;engine=$engine;engine_sha256=$selection.engine.sha256;archive_library=$library;workroot=$resources.root;seed_save=$seed;seed_sha256=$prepared.seed_sha256;server_config=$serverConfig;server_settings=$serverSettings;server_write_data=$serverWrite;port=$serverPort;clients=$clients;expected_screenshots=$screenshots;rcon_port=$rconPort;rcon_password=$rconPassword};if($null -ne $pairedArm){$spec.paired_arm=$pairedArm}
  if($CollectProcessMemoryObservations){
    Assert-Session ($FixtureCase -cin @('library-multiplayer','library-paired-browser')) 'process memory observations require a named Library fixture'
    $spec.process_memory_observations=$true
  }
  $specPath=Join-Path $resources.root 'session-spec.json'
  [IO.File]::WriteAllText($specPath,($spec|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $record.session_spec_sha256=(Get-FileHash -LiteralPath $specPath).Hash
  $pwsh=(Get-Command pwsh -ErrorAction Stop).Source
  $record.process=Invoke-MIRNativeProbeProcess -Context $resources -FilePath $pwsh -Arguments @('-NoLogo','-NoProfile','-File',(Join-Path $PSScriptRoot 'Invoke-MultiplayerSession.ps1'),'-SpecPath',$specPath) -TimeoutSeconds 1000 -FactorioSteamIdentity
  $session=Get-Content -LiteralPath (Join-Path $resources.root 'session.json') -Raw|ConvertFrom-Json
  Assert-Session ($session.status -ceq 'passed-private-two-client-session') 'native client session did not pass'
  $record.session=$session
  $record.status='passed-private-two-client-fixture'
} catch {
  $failure=$_;$record.status='failed';$record.failure=$_.Exception.Message
  $record.resource_admission=$_.Exception.Data['mir441_resource_admission']
} finally {
  try {
    if($null -ne $activation -and -not $activation.closed){$record.library_control_restoration=Complete-MIRLibraryActivation -Activation $activation}
    $record.input_save_byte_identical=(Get-FileHash -LiteralPath $seed).Hash -ceq $prepared.seed_sha256
    Assert-Session $record.input_save_byte_identical 'original disposable seed changed'
  } catch {if($null -eq $failure){$failure=$_;$record.status='failed';$record.failure=$_.Exception.Message}}
  if($null -ne $resources){$record.process_runs=@($resources.runs.ToArray());Write-MIRNativeProbeResult -Context $resources -Record $record}
  elseif($null -ne $record.resource_admission){
    # Admission precedes context allocation. Preserve only bounded refusal
    # facts here; the full preparation/session record can contain secrets.
    try{
      $refusal=[ordered]@{
        kind='MIR5MultiplayerAdmissionRefusalV1';status='refused-before-session';case=$record.case
        source_head=$record.source_head;harness_sha256=$record.harness_sha256;engine=$record.engine
        profile_sha256=$record.profile.sha256;mir_archive_sha256=$record.mir_archive.sha256
        failure=$record.failure;resource_admission=$record.resource_admission
        native_session_started=$false;release_qualification=$false
      }
      $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($refusal|ConvertTo-Json -Depth 12 -Compress)+"`n")
      Assert-Session ($bytes.Length -le 64KB) 'admission receipt exceeds diagnostic reserve'
      $path=Join-Path $output 'session-admission-refusal.json'
      $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }catch{
      # A diagnostic failure must not overwrite the original admission error.
      if($null -ne $failure){$failure.Exception.Data['admission_receipt_failure']=$_.Exception.Message}
    }
  }
}
if($null -ne $failure){throw $failure}
[pscustomobject]$record
