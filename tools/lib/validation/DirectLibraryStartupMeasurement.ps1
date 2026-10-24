Set-StrictMode -Version Latest

# A narrow native consumer for the current performance patch. It uses the
# repository's direct-library transaction and creates only selection, config,
# log, save, and result files under the caller-owned output root.
. (Join-Path $PSScriptRoot '../compatibility/LibraryActivation.ps1')
. (Join-Path $PSScriptRoot 'NativeProbeResources.ps1')
. (Join-Path $PSScriptRoot 'ResponsiveMenuRecord.ps1')

function Assert-MIRDirectLibraryStartupMeasurement {
  param([bool]$Condition,[string]$Code)
  if(-not $Condition){throw "[mir-direct-startup-$Code]"}
}

# Admission remains the ResourceGovernor's responsibility. This bounded
# pre-launch wait only gives transient RAM/commit headroom a chance to recover;
# it neither changes reserves nor retries a sample after governed launch begins.
function Wait-MIRDirectLibraryStartupAdmission {
  param(
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][int64]$EstimatedPeakBytes,
    [Parameter(Mandatory)][int64]$ExpectedPeakMemoryBytes,
    [ValidateRange(0,300)][int]$AdmissionWaitSeconds=0,
    [Parameter(Mandatory)][string]$Phase
  )
  $record=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase $Phase
  Wait-MIR441PreStartResourceAdmission -Policy $Policy -WorkRoot $WorkRoot -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes -State $record
}

function Get-MIRDirectLibraryStartupEngineIdentity {
  param([Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$EngineDataDirectory)
  $base=Get-Content -Raw -LiteralPath (Join-Path $EngineDataDirectory 'base/info.json')|ConvertFrom-Json -Depth 20
  $file=Get-Item -LiteralPath $FactorioBin
  [pscustomobject][ordered]@{path=$file.FullName;sha256=Get-MIRImmutableInputSha256 -Path $file.FullName;file_version=[string]$file.VersionInfo.FileVersion;product_version=[string]$file.VersionInfo.ProductVersion;base_version=[string]$base.version}
}

function Read-MIRDirectLibraryStartupProfile {
  param([Parameter(Mandatory)][string]$Path)
  $value=(Get-Content -Raw -LiteralPath $Path).TrimStart([char]0xFEFF)|ConvertFrom-Json -AsHashtable
  Assert-MIRDirectLibraryStartupMeasurement ($value.ContainsKey('mods') -and $value.mods -is [array]) 'profile-shape'
  $rows=@($value.mods)
  Assert-MIRDirectLibraryStartupMeasurement ($rows.Count -gt 0 -and @($rows|Group-Object name|Where-Object Count -gt 1).Count -eq 0) 'profile-rows'
  foreach($row in $rows){
    Assert-MIRDirectLibraryStartupMeasurement ($row.enabled -is [bool] -and (Test-MIRLibraryModName ([string]$row.name))) 'profile-row'
    if($row.enabled){Assert-MIRDirectLibraryStartupMeasurement ([string]$row.version -match '^\d+[.]\d+[.]\d+$') 'profile-version'}
  }
  Assert-MIRDirectLibraryStartupMeasurement (@($rows|Where-Object {$_.enabled -and $_.name -ceq 'base'}).Count -eq 1) 'profile-base'
  return @($rows|Where-Object {$_.name -cne 'more-infinite-research'})
}

function Write-MIRDirectLibraryStartupProfile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object[]]$BaseRows,[AllowNull()]$MirArchive)
  $rows=[Collections.Generic.List[object]]::new()
  foreach($row in $BaseRows){$rows.Add([ordered]@{name=[string]$row.name;version=[string]$row.version;enabled=[bool]$row.enabled})}
  if($null -ne $MirArchive){$rows.Add([ordered]@{name='more-infinite-research';version=[string]$MirArchive.version;enabled=$true})}
  [IO.File]::WriteAllText($Path,([ordered]@{mods=@($rows)}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}

function Get-MIRDirectLibraryStartupArchiveHashes {
  param([Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][object[]]$BaseRows,[AllowNull()]$MirArchive)
  $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory)
  $wanted=@($BaseRows|Where-Object enabled)
  if($null -ne $MirArchive){$wanted+=,[pscustomobject]@{name='more-infinite-research';version=[string]$MirArchive.version;enabled=$true}}
  $hashes=@{}
  foreach($row in $wanted){
    $matches=@($inventory|Where-Object {$_.name -ceq [string]$row.name -and $_.version -ceq [string]$row.version})
    Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -eq 1) 'selected-archive-missing'
    if(-not $matches[0].builtin){$hashes[[IO.Path]::GetFileName([string]$matches[0].path)]=Get-MIRImmutableInputSha256 -Path ([string]$matches[0].path)}
  }
  return $hashes
}

function New-MIRDirectLibraryStartupConfig {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][string]$WriteDataDirectory,[switch]$Graphics)
  $text="[path]`nread-data=$EngineDataDirectory`nwrite-data=$WriteDataDirectory`n`n[general]`nlocale=en`n`n[other]`nenable-new-mods=false`nenable-steam-networking=false`ndisable-blueprint-storage=true`n"
  if($Graphics){$text+="`n[graphics]`nfull-screen=false`ncache-sprite-atlas=false`n"}
  [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}

function Get-MIRDirectLibraryStartupTextSha256 {
  param([Parameter(Mandatory)][string]$Text)
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Text)))
}

function Get-MIRDirectLibraryOrdinaryPlayerConfigInput {
  param([Parameter(Mandatory)][string]$Path)
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $resolved -PathType Leaf) 'ordinary-player-config-file'
  $item=Get-Item -LiteralPath $resolved
  Assert-MIRDirectLibraryStartupMeasurement ($item.Length -gt 0 -and $item.Length -le 1MB) 'ordinary-player-config-size'
  [pscustomobject][ordered]@{path=$resolved;sha256=Get-MIRImmutableInputSha256 -Path $resolved;bytes=[int64]$item.Length}
}

# An ordinary menu sample may encounter Factorio's first-run version notice.
# The selected player-data is a separately captured engine input, copied once
# into the shared write-data cache before timing.  It is not a user profile,
# and the runner refuses credentials in it rather than quietly carrying them
# into a performance artifact.
function Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedEngineVersion)
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $resolved -PathType Leaf) 'ordinary-menu-player-data-file'
  $item=Get-Item -LiteralPath $resolved
  Assert-MIRDirectLibraryStartupMeasurement ($item.Length -gt 0 -and $item.Length -le 1MB) 'ordinary-menu-player-data-size'
  try{$value=[IO.File]::ReadAllText($resolved,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -AsHashtable}catch{throw '[mir-direct-startup-ordinary-menu-player-data-json]'}
  Assert-MIRDirectLibraryStartupMeasurement ($value.ContainsKey('last-played-version') -and $value['last-played-version'] -is [Collections.IDictionary]) 'ordinary-menu-player-data-last-played'
  Assert-MIRDirectLibraryStartupMeasurement ([string]$value['last-played-version']['game_version'] -ceq $ExpectedEngineVersion) 'ordinary-menu-player-data-engine-version'
  foreach($key in @('service-username','service-token')){
    if($value.ContainsKey($key)){Assert-MIRDirectLibraryStartupMeasurement ([string]$value[$key] -ceq '') 'ordinary-menu-player-data-credentials'}
  }
  [pscustomobject][ordered]@{path=$resolved;sha256=Get-MIRImmutableInputSha256 -Path $resolved;bytes=[int64]$item.Length;engine_version=$ExpectedEngineVersion;kind='actual-engine-prepared-player-data'}
}

function Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData {
  param([Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)]$PlayerData)
  Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $WriteDataRoot)) 'ordinary-menu-shared-write-data-preexisting'
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $destination=Join-Path $WriteDataRoot 'player-data.json'
  [IO.File]::Copy([string]$PlayerData.path,$destination,$false)
  Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $destination) -ceq [string]$PlayerData.sha256) 'ordinary-menu-player-data-copy'
  [pscustomobject][ordered]@{
    kind=[string]$PlayerData.kind;source=[ordered]@{path=[string]$PlayerData.path;sha256=[string]$PlayerData.sha256;bytes=[int64]$PlayerData.bytes;engine_version=[string]$PlayerData.engine_version}
    destination=[ordered]@{path=$destination;sha256=Get-MIRImmutableInputSha256 -Path $destination;bytes=[int64](Get-Item -LiteralPath $destination).Length}
    primary_measurement=$false;scope='untimed preparation; one copied engine-prepared player-data seed for the shared ordinary-menu cache across all arms'
  }
}

function Get-MIRDirectLibraryResponsiveMenuActor {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $root=Join-Path $RepoRoot 'tools/lib/validation/responsive-menu'
  $actor=Join-Path $root 'Invoke-MIRResponsiveMenuActor.ps1'
  $observation=Join-Path $root 'MenuObservation.ps1'
  $window=Join-Path $root 'OwnedMenuWindow.ps1'
  foreach($path in @($actor,$observation,$window)){
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $path -PathType Leaf) 'ordinary-menu-actor-files'
    Assert-MIRDirectLibraryStartupMeasurement ((Get-Item -LiteralPath $path).Length -gt 0 -and (Get-Item -LiteralPath $path).Length -le 128KB) 'ordinary-menu-actor-size'
  }
  $desktop=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $desktop -PathType Leaf) 'ordinary-menu-desktop-powershell'
  [pscustomobject][ordered]@{
    path=(Resolve-Path -LiteralPath $actor).Path;sha256=Get-MIRImmutableInputSha256 -Path $actor
    observation_sha256=Get-MIRImmutableInputSha256 -Path $observation;window_sha256=Get-MIRImmutableInputSha256 -Path $window
    host=(Resolve-Path -LiteralPath $desktop).Path
  }
}

function Get-MIRDirectLibraryOrdinaryConfigProtectedText {
  param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)
  $section='';$protected=[Collections.Generic.List[string]]::new()
  foreach($line in $Lines){
    $header=[regex]::Match($line,'^\s*\[(?<section>[^\]]+)\]\s*(?:;.*)?$')
    if($header.Success){$section=$header.Groups['section'].Value.Trim().ToLowerInvariant();$protected.Add($line);continue}
    $setting=[regex]::Match($line,'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)\s*=')
    $key=if($setting.Success){$setting.Groups['key'].Value.ToLowerInvariant()}else{''}
    if($setting.Success-and(($section-ceq'path'-and$key-ceq'read-data')-or($section-ceq'path'-and$key-ceq'write-data')-or($section-ceq'other'-and$key-ceq'enable-new-mods'))){continue}
    $protected.Add($line)
  }
  return ($protected -join "`n")
}

function New-MIRDirectLibraryOrdinaryPlayerConfig {
  param(
    [Parameter(Mandatory)]$PlayerConfigInput,[Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][string]$WriteDataDirectory
  )
  $source=(Resolve-Path -LiteralPath ([string]$PlayerConfigInput.path)).Path
  Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $source) -ceq [string]$PlayerConfigInput.sha256) 'ordinary-player-config-drift'
  $encoding=[Text.UTF8Encoding]::new($false,$true)
  try{$text=[IO.File]::ReadAllText($source,$encoding)}catch{throw '[mir-direct-startup-ordinary-player-config-encoding]'}
  $newline=if($text.Contains("`r`n")){"`r`n"}else{"`n"};$lines=[Collections.Generic.List[string]]::new([regex]::Split($text,"`r?`n"))
  $sections=@{path=0;other=0};$settings=@{read_data=@();write_data=@();enable_new_mods=@()};$section=''
  for($index=0;$index-lt$lines.Count;$index++){
    $header=[regex]::Match($lines[$index],'^\s*\[(?<section>[^\]]+)\]\s*(?:;.*)?$')
    if($header.Success){$section=$header.Groups['section'].Value.Trim().ToLowerInvariant();if($sections.ContainsKey($section)){$sections[$section]++};continue}
    $setting=[regex]::Match($lines[$index],'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)(?<equals>\s*=\s*)(?<value>.*)$')
    if(-not$setting.Success){continue}
    $key=$setting.Groups['key'].Value.ToLowerInvariant()
    if($section-ceq'path'-and$key-ceq'read-data'){$settings.read_data+=,$index}
    elseif($section-ceq'path'-and$key-ceq'write-data'){$settings.write_data+=,$index}
    elseif($section-ceq'other'-and$key-ceq'enable-new-mods'){$settings.enable_new_mods+=,$index}
  }
  Assert-MIRDirectLibraryStartupMeasurement ($sections.path-eq1-and$sections.other-eq1) 'ordinary-player-config-sections'
  Assert-MIRDirectLibraryStartupMeasurement ($settings.read_data.Count-eq1-and$settings.write_data.Count-eq1-and$settings.enable_new_mods.Count-le1) 'ordinary-player-config-keys'
  $pathValues=@{read_data=$EngineDataDirectory;write_data=$WriteDataDirectory}
  foreach($pair in @(@('read_data','read-data'),@('write_data','write-data'))){
    $index=[int]$settings[$pair[0]][0];$setting=[regex]::Match($lines[$index],'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)(?<equals>\s*=\s*)(?<value>.*)$')
    $lines[$index]=$setting.Groups['prefix'].Value+$pair[1]+$setting.Groups['equals'].Value+$pathValues[$pair[0]]
  }
  if($settings.enable_new_mods.Count-eq1){
    $index=[int]$settings.enable_new_mods[0];$setting=[regex]::Match($lines[$index],'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)(?<equals>\s*=\s*)(?<value>.*)$')
    $lines[$index]=$setting.Groups['prefix'].Value+'enable-new-mods'+$setting.Groups['equals'].Value+'false'
  }else{
    $insertAt=$lines.Count
    for($index=0;$index-lt$lines.Count;$index++){
      $header=[regex]::Match($lines[$index],'^\s*\[(?<section>[^\]]+)\]\s*(?:;.*)?$')
      if($header.Success-and$header.Groups['section'].Value.Trim().ToLowerInvariant()-ceq'other'){$insertAt=$index+1;break}
    }
    $lines.Insert($insertAt,'enable-new-mods=false')
  }
  $privateText=$lines -join $newline
  $sourceLines=[regex]::Split($text,"`r?`n")
  Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRDirectLibraryOrdinaryConfigProtectedText -Lines $sourceLines) -ceq (Get-MIRDirectLibraryOrdinaryConfigProtectedText -Lines $lines.ToArray())) 'ordinary-player-config-preservation'
  [IO.File]::WriteAllText($Path,$privateText,[Text.UTF8Encoding]::new($false))
  [pscustomobject][ordered]@{
    source=[pscustomobject][ordered]@{path=$source;sha256=[string]$PlayerConfigInput.sha256;bytes=[int64]$PlayerConfigInput.bytes}
    private_config=[pscustomobject][ordered]@{path=$Path;sha256=Get-MIRImmutableInputSha256 -Path $Path;bytes=[int64](Get-Item -LiteralPath $Path).Length}
    preserved_settings_sha256=Get-MIRDirectLibraryStartupTextSha256 -Text (Get-MIRDirectLibraryOrdinaryConfigProtectedText -Lines $lines.ToArray())
    overrides=[ordered]@{read_data=$EngineDataDirectory;write_data=$WriteDataDirectory;enable_new_mods=$false}
  }
}

function Invoke-MIRDirectLibraryResponsiveMenuSample {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,300)][int]$TimeoutSeconds=300,[Parameter(Mandatory)]$OrdinaryPlayerConfig,[Parameter(Mandatory)]$OrdinaryMenuPreparation,[string]$ActiveModsObserver=''
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $WriteDataRoot -PathType Container) 'ordinary-menu-shared-write-data-missing'
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log';$actorRoot=Join-Path $RunRoot 'responsive-menu-actor';$specPath=Join-Path $RunRoot 'responsive-menu-launch.json'
  $playerData=Join-Path $WriteDataRoot 'player-data.json'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $playerData -PathType Leaf) 'ordinary-menu-player-data-missing'
  $playerDataBefore=Get-MIRImmutableInputSha256 -Path $playerData
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  $configIdentity=New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput $OrdinaryPlayerConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $actor=Get-MIRDirectLibraryResponsiveMenuActor -RepoRoot $RepoRoot
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $actorRoot)) 'ordinary-menu-actor-root-preexisting'
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation')
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $executionControls=[ordered]@{
      engine_sha256=Get-MIRImmutableInputSha256 -Path $FactorioBin
      arguments_sha256=Get-MIRDirectLibraryStartupTextSha256 -Text (ConvertTo-Json -InputObject $arguments -Compress)
      config=[ordered]@{path=[IO.Path]::GetRelativePath($RunRoot,$config).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $config}
      selection=[ordered]@{path=[IO.Path]::GetRelativePath($RunRoot,$profile).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $profile}
      player_data=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,$playerData).Replace('\','/');sha256_before=$playerDataBefore;preparation_sha256=[string]$OrdinaryMenuPreparation.source.sha256}
      library_directory=[string]$activation.library
    }
    $spec=[ordered]@{kind='MIRDirectLibraryOwnedMenuLaunchV1';factorio_path=(Resolve-Path -LiteralPath $FactorioBin).Path;factorio_sha256=$executionControls.engine_sha256;arguments=$arguments;engine_current_log=$engineLog;timeout_seconds=$TimeoutSeconds}
    [IO.File]::WriteAllText($specPath,($spec|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $specSha=Get-MIRImmutableInputSha256 -Path $specPath
    $native=Invoke-MIRNativeProbeProcess -Context $Resources -FilePath $actor.host -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$actor.path,'-LaunchSpecPath',$specPath,'-LaunchSpecSha256',$specSha,'-OutputRoot',$actorRoot) -TimeoutSeconds ($TimeoutSeconds+20)
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'ordinary-menu-actor-process'
    $actorRecordPath=Join-Path $actorRoot 'actor-result.json'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $actorRecordPath -PathType Leaf) 'ordinary-menu-actor-result'
    $actorItem=Get-Item -LiteralPath $actorRecordPath
    Assert-MIRDirectLibraryStartupMeasurement ($actorItem.Length -gt 0 -and $actorItem.Length -le 2MB -and -not($actorItem.Attributes-band[IO.FileAttributes]::ReparsePoint)) 'ordinary-menu-actor-result-size'
    $actorRecord=Get-Content -Raw -LiteralPath $actorRecordPath|ConvertFrom-Json -Depth 30 -DateKind String
    Assert-MIRDirectLibraryStartupMeasurement ([string]$actorRecord.kind -ceq 'MIRDirectLibraryOwnedMenuObservationV1' -and [string]$actorRecord.status -ceq 'observed-response-awaiting-parent-selection-validation') 'ordinary-menu-actor-status'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$actorRecord.launch_spec_sha256 -ceq $specSha -and [string]$actorRecord.factorio_sha256 -ceq $executionControls.engine_sha256) 'ordinary-menu-actor-inputs'
    Assert-MIRDirectLibraryStartupMeasurement (-not[bool]$actorRecord.claims_library_selection_validation -and -not[bool]$actorRecord.claims_final_acceptance -and -not[bool]$actorRecord.observation.claims_factorio_acceptance) 'ordinary-menu-actor-claims'
    $menu=Read-MIRDirectLibraryResponsiveMenuRecord -Observation $actorRecord.observation -OwnedProcessId ([int]$actorRecord.process_id) -OwnedProcessStartUtc ([datetime]$actorRecord.process_start_utc) -LaunchBeforeQpc ([long]$actorRecord.launch_before_qpc) -LaunchAfterQpc ([long]$actorRecord.launch_after_qpc) -ClockFrequency ([long]$actorRecord.clock_frequency) -ArtifactRoot $actorRoot -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $actor.path)-ceq$actor.sha256-and(Get-MIRImmutableInputSha256 -Path (Join-Path $RepoRoot 'tools/lib/validation/responsive-menu/MenuObservation.ps1'))-ceq$actor.observation_sha256-and(Get-MIRImmutableInputSha256 -Path (Join-Path $RepoRoot 'tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1'))-ceq$actor.window_sha256) 'ordinary-menu-actor-drift'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'ordinary-menu-engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'ordinary-menu-initialised'
    $observerIdentity=$null
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
      $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
      Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count-eq1) 'ordinary-menu-active-mods-observer-selection'
      $observer=$observerRows[0]
      Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'ordinary-menu-active-mods-observer-identity'
      $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    }
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver -ActiveModsObserverScript data-final-fixes.lua)
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $FactorioBin)-ceq$executionControls.engine_sha256-and(Get-MIRImmutableInputSha256 -Path $config)-ceq$executionControls.config.sha256-and(Get-MIRImmutableInputSha256 -Path $profile)-ceq$executionControls.selection.sha256) 'ordinary-menu-execution-controls-drift'
    $playerDataAfter=Get-MIRImmutableInputSha256 -Path $playerData
    [pscustomobject][ordered]@{
      label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$menu.elapsed_seconds;endpoint_class='ordinary-responsive-menu'
      ready_endpoint='A Factorio process reached a captured owned main menu and completed a harmless owned Settings action whose distinct Settings screen was captured and OCR-confirmed. The elapsed interval is the actor QPC launch bracket to that confirmed response; actor preheat and shutdown/cleanup are excluded.'
      menu_response=$menu;ordinary_player_config=[ordered]@{source=$configIdentity.source;private_config=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,[string]$configIdentity.private_config.path).Replace('\','/');sha256=$configIdentity.private_config.sha256;bytes=$configIdentity.private_config.bytes};preserved_settings_sha256=$configIdentity.preserved_settings_sha256;overrides=$configIdentity.overrides}
      ordinary_menu_preparation=[ordered]@{source=$OrdinaryMenuPreparation.source;destination=$OrdinaryMenuPreparation.destination;primary_measurement=$false;player_data_sha256_before=$playerDataBefore;player_data_sha256_after=$playerDataAfter}
      cache_context=[ordered]@{write_data_root=[IO.Path]::GetRelativePath($Resources.root,$WriteDataRoot).Replace('\','/');configuration_sha256=$executionControls.config.sha256;selection_sha256=$executionControls.selection.sha256;player_data_sha256_before=$playerDataBefore;player_data_sha256_after=$playerDataAfter;shared_across_arms=$true}
      responsive_menu_actor=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,$actorRecordPath).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $actorRecordPath;script_sha256=$actor.sha256;observation_sha256=$actor.observation_sha256;window_sha256=$actor.window_sha256;launch_spec=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,$specPath).Replace('\','/');sha256=$specSha};actor_process_duration_seconds=[double]$native.result.duration_seconds;shutdown_cleanup_seconds=[double]$actorRecord.shutdown_cleanup_seconds;full_engine_cycle_seconds=[double]$actorRecord.full_engine_cycle_seconds;resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/')}
      loaded_selection=$loaded;active_mods_observer=$observerIdentity;execution_controls=$executionControls;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored the governed actor and its owned Factorio child; values are not whole-system memory'}
      log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')
    }
  } finally {
    if($null-ne$activation -and -not$activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}
