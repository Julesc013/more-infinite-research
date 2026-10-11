Set-StrictMode -Version Latest

# A narrow native consumer for the current performance patch. It uses the
# repository's direct-library transaction and creates only selection, config,
# log, save, and result files under the caller-owned output root.
. (Join-Path $PSScriptRoot '../compatibility/LibraryActivation.ps1')
. (Join-Path $PSScriptRoot 'NativeProbeResources.ps1')

function Assert-MIRDirectLibraryStartupMeasurement {
  param([bool]$Condition,[string]$Code)
  if(-not $Condition){throw "[mir-direct-startup-$Code]"}
}

function Get-MIRDirectLibraryStartupArchive {
  param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$LibraryDirectory)
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  $path=(Resolve-Path -LiteralPath $Archive).Path
  Assert-MIRLibraryPath $path
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetDirectoryName($path) -ceq $library) 'archive-not-in-selected-library'
  $zip=[IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entries=@($zip.Entries|Where-Object {$_.FullName -match '^[^/]+/info[.]json$'})
    Assert-MIRDirectLibraryStartupMeasurement ($entries.Count -eq 1 -and $entries[0].Length -le 64KB) 'archive-metadata'
    $reader=[IO.StreamReader]::new($entries[0].Open())
    try {$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable} finally {$reader.Dispose()}
  } finally {$zip.Dispose()}
  Assert-MIRDirectLibraryStartupMeasurement ([string]$info.name -ceq 'more-infinite-research') 'archive-name'
  Assert-MIRDirectLibraryStartupMeasurement ([string]$info.version -match '^4[.]2[.]\d{5}$') 'archive-version'
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetFileName($path) -ceq ('more-infinite-research_'+[string]$info.version+'.zip')) 'archive-filename'
  [pscustomobject][ordered]@{path=$path;name=[string]$info.name;version=[string]$info.version;sha256=Get-MIRImmutableInputSha256 -Path $path}
}

function Get-MIRDirectLibraryPlayerReadyObserverArchive {
  param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][ValidateSet('f200','f210')][string]$Target)
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  $path=(Resolve-Path -LiteralPath $Archive).Path
  Assert-MIRLibraryPath $path
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetDirectoryName($path) -ceq $library) 'player-ready-observer-not-in-selected-library'
  $zip=[IO.Compression.ZipFile]::OpenRead($path)
  try {
    $infoEntries=@($zip.Entries|Where-Object {$_.FullName -match '^[^/]+/info[.]json$'})
    Assert-MIRDirectLibraryStartupMeasurement ($infoEntries.Count -eq 1 -and $infoEntries[0].Length -le 64KB) 'player-ready-observer-metadata'
    $root=$infoEntries[0].FullName.Substring(0,$infoEntries[0].FullName.Length-'info.json'.Length).TrimEnd('/')
    $reader=[IO.StreamReader]::new($infoEntries[0].Open())
    try {$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable} finally {$reader.Dispose()}
    Assert-MIRDirectLibraryStartupMeasurement (Test-MIRLibraryModName ([string]$info.name)) 'player-ready-observer-name'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$info.version -match '^\d+[.]\d+[.]\d+$') 'player-ready-observer-version'
    Assert-MIRDirectLibraryStartupMeasurement ($root -ceq ([string]$info.name+'_'+[string]$info.version)) 'player-ready-observer-root'
    Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetFileName($path) -ceq ($root+'.zip')) 'player-ready-observer-filename'
    $line=if($Target-ceq'f200'){'2.0'}else{'2.1'}
    Assert-MIRDirectLibraryStartupMeasurement ([string]$info.factorio_version -ceq $line) 'player-ready-observer-target'
    $dependencies=@($info.dependencies)
    Assert-MIRDirectLibraryStartupMeasurement ($dependencies.Count -eq 1 -and [string]$dependencies[0] -ceq 'base') 'player-ready-observer-dependencies'
    $files=@($zip.Entries|Where-Object {-not $_.FullName.EndsWith('/')})
    $expected=@(
      ($root+'/control.lua')
      ($root+'/info.json')
    )|Sort-Object
    Assert-MIRDirectLibraryStartupMeasurement ($files.Count -eq 2 -and ((@($files.FullName|Sort-Object) -join "`n") -ceq ($expected -join "`n"))) 'player-ready-observer-surface'
    $control=@($files|Where-Object {$_.FullName -ceq ($root+'/control.lua')})
    Assert-MIRDirectLibraryStartupMeasurement ($control.Count -eq 1 -and $control[0].Length -gt 0 -and $control[0].Length -le 64KB) 'player-ready-observer-control'
    $controlReader=[IO.StreamReader]::new($control[0].Open())
    try {$controlText=$controlReader.ReadToEnd()} finally {$controlReader.Dispose()}
    Assert-MIRDirectLibraryStartupMeasurement ($controlText.Contains('[MIR_ACTIVE_MODS]')-and$controlText.Contains('[MIR_PLAYER_READY]')) 'player-ready-observer-markers'
  } finally {$zip.Dispose()}
  [pscustomobject][ordered]@{path=$path;name=[string]$info.name;version=[string]$info.version;sha256=Get-MIRImmutableInputSha256 -Path $path;target=$Target;marker='MIR_PLAYER_READY';marker_file='factorio-current.log';scenario='base-only-player-ready-observer-v1'}
}

function Assert-MIRDirectLibraryPublished422Manifest {
  param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)]$PublishedArchive,[Parameter(Mandatory)][string]$Target)
  Assert-MIRDirectLibraryStartupMeasurement ($ExpectedSha256 -match '^[A-Fa-f0-9]{64}$') 'published-manifest-expected-hash'
  $path=(Resolve-Path -LiteralPath $ManifestPath).Path;$actual=Get-MIRImmutableInputSha256 -Path $path
  Assert-MIRDirectLibraryStartupMeasurement ($actual -ceq $ExpectedSha256.ToUpperInvariant()) 'published-manifest-hash'
  $manifest=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100 -DateKind String
  $sourceVersion=if($manifest.PSObject.Properties['release']){[string]$manifest.release.source_version}else{[string]$manifest.source_version}
  Assert-MIRDirectLibraryStartupMeasurement ($sourceVersion -ceq '4.2.2') 'published-manifest-release'
  $assets=@()
  if($manifest.PSObject.Properties['package_assets']){$assets=@($manifest.package_assets)}
  elseif($manifest.PSObject.Properties['targets']){$assets=@($manifest.targets)}
  elseif($manifest.PSObject.Properties['assets']){$assets=@($manifest.assets|Where-Object {[string]$_.target -ceq $Target})}
  $rows=@($assets|Where-Object {[string]$_.target -ceq $Target})
  Assert-MIRDirectLibraryStartupMeasurement ($rows.Count -eq 1) 'published-manifest-target'
  $row=$rows[0]
  Assert-MIRDirectLibraryStartupMeasurement ([string]$row.distribution_version -ceq [string]$PublishedArchive.version -and [string]$row.sha256 -ceq [string]$PublishedArchive.sha256) 'published-manifest-archive'
  return [pscustomobject][ordered]@{path=$path;sha256=$actual;source_version=$sourceVersion;source_commit=$(if($manifest.PSObject.Properties['source']){[string]$manifest.source.commit}else{''});source_tree=$(if($manifest.PSObject.Properties['source']){[string]$manifest.source.tree}else{''});target=$Target;archive_sha256=[string]$row.sha256}
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

function Add-MIRDirectLibraryPlayerReadyObserverSelection {
  param([Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)]$Observer)
  $rows=[Collections.Generic.List[object]]::new()
  foreach($row in $BaseRows){$rows.Add([pscustomobject]@{name=[string]$row.name;version=[string]$row.version;enabled=[bool]$row.enabled})}
  $matches=@($rows|Where-Object {$_.name -ceq [string]$Observer.name})
  Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -le 1) 'player-ready-observer-profile-duplicate'
  if($matches.Count -eq 1){
    Assert-MIRDirectLibraryStartupMeasurement ([bool]$matches[0].enabled -and [string]$matches[0].version -ceq [string]$Observer.version) 'player-ready-observer-profile'
  } else {
    $rows.Add([pscustomobject]@{name=[string]$Observer.name;version=[string]$Observer.version;enabled=$true})
  }
  return @($rows)
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

function Invoke-MIRDirectLibraryStartupSample {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[string]$ActiveModsObserver=''
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$saveDirectory=Join-Path $RunRoot 'saves';$save=Join-Path $saveDirectory 'startup-ready.zip';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log'
  [IO.Directory]::CreateDirectory($saveDirectory)|Out-Null
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  # The first sample and immediate warm-repeat samples for one selected
  # configuration share this private write-data root. Per-sample logs and
  # saves remain isolated in RunRoot, so a prior ready endpoint cannot be
  # mistaken for the successor's result.
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $save)) 'ready-save-preexisting'
    # write-data is intentionally retained for this configuration's warm
    # repeat. The engine log is not: remove only this owned previous log so
    # every snapshot has a native invocation boundary from this run.
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio','--create',$save)
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'process-exit'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $save -PathType Leaf) 'ready-save'
    # Factorio 2.0 writes its actual current log beneath write-data. Snapshot
    # it after process exit so the per-sample evidence survives the warm run.
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'ready-initialised'
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match ('(?m)^\s*\d+[.]\d+ Info Create[.]cpp:\d+: Creating new map '+[regex]::Escape($save)+'\s*$')) 'ready-create'
    $zip=[IO.Compression.ZipFile]::OpenRead($save)
    try {$mapEntries=@($zip.Entries|Where-Object {$_.FullName -match '(^|/)level(?:-init)?[.]dat$'});Assert-MIRDirectLibraryStartupMeasurement ($mapEntries.Count -eq 1) 'ready-save-map-data';$mapEntry=[string]$mapEntries[0].FullName} finally {$zip.Dispose()}
    $observerIdentity=$null
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
      $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
      Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count -eq 1) 'active-mods-observer-selection'
      $observer=$observerRows[0]
      Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'active-mods-observer-identity'
      $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    }
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver)
    $initialised=[regex]::Matches($logText,'(?m)^\s*(?<seconds>\d+[.]\d+) Factorio initialised\s*$')|Select-Object -Last 1
    [pscustomobject][ordered]@{label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$native.result.duration_seconds;engine_log_initialised_seconds=[double]::Parse($initialised.Groups['seconds'].Value,[Globalization.CultureInfo]::InvariantCulture);exit_code=$native.result.exit_code;endpoint_class='headless-create-diagnostic';ready_endpoint='Factorio --create exits successfully after the actual current log records initialisation and map creation, with one initial map-data entry in the new save ZIP';ready_save=[IO.Path]::GetRelativePath($RunRoot,$save).Replace('\','/');ready_save_map_entry=$mapEntry;loaded_selection=$loaded;active_mods_observer=$observerIdentity;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored process tree; values are not whole-system memory'};resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Invoke-MIRDirectLibraryPlayerReadyPreparation {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$PreparationRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[Parameter(Mandatory)][string]$ActiveModsObserver,[Parameter(Mandatory)]$PlayerReadyObserver
  )
  [IO.Directory]::CreateDirectory($PreparationRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $PreparationRoot 'selection.json';$config=Join-Path $PreparationRoot 'config.ini';$saveDirectory=Join-Path $PreparationRoot 'saves';$save=Join-Path $saveDirectory 'neutral-player-ready.zip';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log';$log=Join-Path $PreparationRoot 'factorio.log'
  [IO.Directory]::CreateDirectory($saveDirectory)|Out-Null
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $save)) 'player-ready-preparation-save-preexisting'
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio','--create',$save)
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'player-ready-preparation-process-exit'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $save -PathType Leaf) 'player-ready-preparation-save'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'player-ready-preparation-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText-match'(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'player-ready-preparation-initialised'
    $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver
    $zip=[IO.Compression.ZipFile]::OpenRead($save)
    try {$entries=@($zip.Entries|Where-Object {$_.FullName -match '(^|/)level(?:-init)?[.]dat$'});Assert-MIRDirectLibraryStartupMeasurement ($entries.Count -eq 1) 'player-ready-preparation-map-data'}finally{$zip.Dispose()}
    [pscustomobject][ordered]@{label=$Label;scenario=[string]$PlayerReadyObserver.scenario;prepared_save=[IO.Path]::GetRelativePath($Resources.root,$save).Replace('\','/');prepared_save_sha256=Get-MIRImmutableInputSha256 -Path $save;preparation_log=[IO.Path]::GetRelativePath($Resources.root,$log).Replace('\','/');resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');measurement='preparation only; the native --create process is not a startup sample and contributes no elapsed value to comparison samples'}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Read-MIRDirectLibraryPlayerReadyMarker {
  param([Parameter(Mandatory)][string]$LogPath)
  $text=Get-Content -Raw -LiteralPath $LogPath
  $matches=@([regex]::Matches($text,'(?m)^\s*(?<seconds>\d+[.]\d+)\s+.*\[MIR_PLAYER_READY\]\s+(?<json>\{[^\r\n]+\})\s*$'))
  Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -eq 1) 'player-ready-marker-count'
  try{$marker=$matches[0].Groups['json'].Value|ConvertFrom-Json -AsHashtable -Depth 16}catch{throw '[mir-direct-startup-player-ready-marker-json]'}
  $isInteger={param($value) $value -is [byte] -or $value -is [sbyte] -or $value -is [int16] -or $value -is [uint16] -or $value -is [int32] -or $value -is [uint32] -or $value -is [int64] -or $value -is [uint64]}
  Assert-MIRDirectLibraryStartupMeasurement ($marker.ContainsKey('schema') -and (& $isInteger $marker['schema']) -and [long]$marker['schema'] -eq 1 -and [string]$marker['kind'] -ceq 'mir423-player-ready-observer' -and [string]$marker['status'] -ceq 'passed') 'player-ready-marker-shape'
  Assert-MIRDirectLibraryStartupMeasurement ($marker.ContainsKey('connected_players') -and (& $isInteger $marker['connected_players']) -and [long]$marker['connected_players'] -ge 1 -and $marker.ContainsKey('native_players') -and (& $isInteger $marker['native_players']) -and [long]$marker['native_players'] -ge 1) 'player-ready-marker-player'
  Assert-MIRDirectLibraryStartupMeasurement ($marker.ContainsKey('gui_root_valid') -and $marker['gui_root_valid'] -is [bool] -and $marker['gui_root_valid'] -and $marker.ContainsKey('first_usable_tick') -and (& $isInteger $marker['first_usable_tick']) -and [long]$marker['first_usable_tick'] -eq 1) 'player-ready-marker-gui-root'
  [pscustomobject][ordered]@{engine_log_seconds=[double]::Parse($matches[0].Groups['seconds'].Value,[Globalization.CultureInfo]::InvariantCulture);marker=$marker}
}

function Invoke-MIRDirectLibraryGraphicalPlayerReadySample {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$PreparedSave,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$PreparedSaveSha256,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[Parameter(Mandatory)][ValidateRange(1,720)][int]$PlayerReadyBenchmarkTicks,[Parameter(Mandatory)][string]$ActiveModsObserver
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log';$save=(Resolve-Path -LiteralPath $PreparedSave).Path
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot -Graphics
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $preparedSaveBeforeSha256=Get-MIRImmutableInputSha256 -Path $save
    Assert-MIRDirectLibraryStartupMeasurement ($preparedSaveBeforeSha256 -ceq $PreparedSaveSha256) 'player-ready-prepared-save-before'
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--force-graphics-preset','low','--video-memory-usage','low','--single-thread-loading','--benchmark-graphics',$save,'--benchmark-ticks',[string]$PlayerReadyBenchmarkTicks,'--disable-audio','--window-size','1024x768')
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'player-ready-process-exit'
    $preparedSaveAfterSha256=Get-MIRImmutableInputSha256 -Path $save
    Assert-MIRDirectLibraryStartupMeasurement ($preparedSaveAfterSha256 -ceq $PreparedSaveSha256) 'player-ready-prepared-save-after'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'player-ready-engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
    Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count -eq 1) 'player-ready-observer-selection'
    $observer=$observerRows[0]
    Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'player-ready-observer-identity'
    $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver)
    $ready=Read-MIRDirectLibraryPlayerReadyMarker -LogPath $log
    [pscustomobject][ordered]@{label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$native.result.duration_seconds;engine_log_player_ready_seconds=[double]$ready.engine_log_seconds;exit_code=$native.result.exit_code;endpoint_class='graphical-player-ready-diagnostic';ready_endpoint='A prepared neutral save reached a real connected player with a valid screen GUI-root marker at tick one during --benchmark-graphics. This is not a main-menu readiness or a full-startup claim.';prepared_save=[IO.Path]::GetRelativePath($Resources.root,$save).Replace('\','/');prepared_save_sha256=$PreparedSaveSha256;prepared_save_sha256_before=$preparedSaveBeforeSha256;prepared_save_sha256_after=$preparedSaveAfterSha256;benchmark_ticks=$PlayerReadyBenchmarkTicks;player_ready_marker=$ready.marker;loaded_selection=$loaded;active_mods_observer=$observerIdentity;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored process tree; values are not whole-system memory'};resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Invoke-MIRDirectLibraryStartupMeasurement {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$ProfileTemplatePath,
    [Parameter(Mandatory)][string]$Published422Archive,[Parameter(Mandatory)][string]$Published422ManifestPath,[Parameter(Mandatory)][string]$Published422ManifestSha256,
    [string]$CandidateArchive='',[string]$CandidateMaterializationArchive='',[string]$CandidateMaterializationReceiptPath='',[switch]$Preliminary,[Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('f200','f210')][string]$Target='f200',[ValidateRange(0,5)][int]$WarmupRuns=1,[ValidateRange(1,25)][int]$MeasuredRuns=3,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,
    [Parameter(Mandatory)][ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB,[ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{40}$')][string]$SourceCommit,[string]$ActiveModsObserver='',
    [switch]$GraphicalPlayerReady,[string]$PlayerReadyObserverArchive='',[ValidateRange(1,720)][int]$PlayerReadyBenchmarkTicks=60
  )
  $repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
  $observedCommit=(& git -C $repo rev-parse HEAD).Trim().ToLowerInvariant()
  Assert-MIRDirectLibraryStartupMeasurement ($observedCommit -ceq $SourceCommit.ToLowerInvariant()) 'source-commit'
  $dirty=@(& git -C $repo status --porcelain).Count -gt 0
  $sourceObservation=[ordered]@{requested_commit=$SourceCommit.ToLowerInvariant();head_commit=$observedCommit;working_tree_dirty=$dirty}
  $engine=(Resolve-Path -LiteralPath $FactorioBin).Path;$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path;$template=(Resolve-Path -LiteralPath $ProfileTemplatePath).Path
  $engineRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine));$data=Join-Path $engineRoot 'data'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $data -PathType Container) 'engine-data'
  Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $OutputRoot)) 'output-exists'
  $engineIdentity=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $engine -EngineDataDirectory $data
  $published=Get-MIRDirectLibraryStartupArchive -Archive $Published422Archive -LibraryDirectory $library;$code=$Target.Substring(1)
  Assert-MIRDirectLibraryStartupMeasurement ($published.version -ceq "4.2.${code}02") 'published-identity'
  $publishedManifest=Assert-MIRDirectLibraryPublished422Manifest -ManifestPath $Published422ManifestPath -ExpectedSha256 $Published422ManifestSha256 -PublishedArchive $published -Target $Target
  $hasCandidate=-not [string]::IsNullOrWhiteSpace($CandidateArchive)
  Assert-MIRDirectLibraryStartupMeasurement (($hasCandidate -and -not $Preliminary) -or (-not $hasCandidate -and $Preliminary)) 'candidate-mode'
  $candidate=$null;$candidateMaterialization=$null
  if($hasCandidate){
    Assert-MIRDirectLibraryStartupMeasurement (-not [string]::IsNullOrWhiteSpace($CandidateMaterializationArchive) -and -not [string]::IsNullOrWhiteSpace($CandidateMaterializationReceiptPath)) 'candidate-materialization-inputs'
    # NativeProbeResources owns receipt validation but deliberately does not
    # load the package materializer at module import time. The matched
    # candidate path needs that authoritative reader and its dependencies.
    . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
    $candidate=Get-MIRDirectLibraryStartupArchive -Archive $CandidateArchive -LibraryDirectory $library
    Assert-MIRDirectLibraryStartupMeasurement ($candidate.version -ceq "4.2.${code}03") 'candidate-identity'
    $candidateMaterialization=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateMaterializationArchive -ReceiptPath $CandidateMaterializationReceiptPath -Target $Target -SourceVersion '4.2.3'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$candidateMaterialization.receipt.archive_sha256 -ceq [string]$candidate.sha256) 'candidate-materialization-archive'
  }
  $base=Read-MIRDirectLibraryStartupProfile -Path $template
  $playerReadyObserver=$null;$selectedActiveModsObserver=$ActiveModsObserver
  if($GraphicalPlayerReady){
    Assert-MIRDirectLibraryStartupMeasurement (-not [string]::IsNullOrWhiteSpace($PlayerReadyObserverArchive)) 'player-ready-observer-required'
    $playerReadyObserver=Get-MIRDirectLibraryPlayerReadyObserverArchive -Archive $PlayerReadyObserverArchive -LibraryDirectory $library -Target $Target
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){Assert-MIRDirectLibraryStartupMeasurement ($ActiveModsObserver -ceq [string]$playerReadyObserver.name) 'player-ready-observer-active-mods-name'}
    $selectedActiveModsObserver=[string]$playerReadyObserver.name
    $base=Add-MIRDirectLibraryPlayerReadyObserverSelection -BaseRows $base -Observer $playerReadyObserver
  }
  if(-not [string]::IsNullOrWhiteSpace($selectedActiveModsObserver)){
    Assert-MIRDirectLibraryStartupMeasurement (Test-MIRLibraryModName $selectedActiveModsObserver) 'active-mods-observer-name'
    Assert-MIRDirectLibraryStartupMeasurement (@($base|Where-Object {$_.enabled -and $_.name -ceq $selectedActiveModsObserver}).Count -eq 1) 'active-mods-observer-profile'
  }
  $templateSha=Get-MIRImmutableInputSha256 -Path $template
  $resources=$null;$records=$null;$currentLabel='';$preparations=$null;$preparedSaves=@{}
  try {
    $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB -UseExactOutputRoot
    [IO.Directory]::CreateDirectory($resources.root)|Out-Null;$records=[Collections.Generic.List[object]]::new();$preparations=[Collections.Generic.List[object]]::new()
    $kinds=@([pscustomobject]@{label='without-mir';archive=$null},[pscustomobject]@{label='released-4.2.2';archive=$published})
    if($hasCandidate){$kinds+=,[pscustomobject]@{label='candidate-4.2.3';archive=$candidate}}
    if($GraphicalPlayerReady){
      foreach($kind in $kinds){
        $currentLabel=[string]$kind.label
        $preparation=Invoke-MIRDirectLibraryPlayerReadyPreparation -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -PreparationRoot (Join-Path $resources.root ('preparations/'+$kind.label)) -WriteDataRoot (Join-Path $resources.root ('write-data/'+$kind.label)) -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -ActiveModsObserver $selectedActiveModsObserver -PlayerReadyObserver $playerReadyObserver
        $preparations.Add($preparation);$preparedSaves[[string]$kind.label]=Join-Path $resources.root ([string]$preparation.prepared_save)
      }
    }
    $ordinals=@{};foreach($kind in $kinds){$ordinals[$kind.label]=0}
    # Rotate configurations by block and record the actual predecessor for
    # every first sample. A rotation can bring the same selection to the start
    # of the next block; do not call that a changed configuration.
    $previousSelection=if($GraphicalPlayerReady){[string]$kinds[$kinds.Count-1].label}else{$null}
    for($block=1;$block-le($WarmupRuns+$MeasuredRuns);$block++){
    $offset=($block-1)%$kinds.Count
    for($position=0;$position-lt$kinds.Count;$position++){
      $kind=$kinds[($offset+$position)%$kinds.Count]
      $changed=if($null-eq$previousSelection){$null}else{[bool]($previousSelection-cne$kind.label)}
      $firstState=if($null-eq$previousSelection){'initial-selection'}elseif($changed){'changed-configuration'}else{'same-selection'}
      $samplePlan=@(
        [pscustomobject]@{cache_state=$firstState;prior_selection_label=$previousSelection;selection_changed=$changed},
        [pscustomobject]@{cache_state='warm-repeat';prior_selection_label=$kind.label;selection_changed=$false}
      )
      foreach($samplePlanRow in $samplePlan){
        $ordinals[$kind.label]++;$ordinal=$ordinals[$kind.label]
        $runRoot=Join-Path $resources.root ('runs/'+$kind.label+'/'+$ordinal+'/'+[string]$samplePlanRow.cache_state)
        $writeDataRoot=Join-Path $resources.root ('write-data/'+$kind.label)
        $currentLabel=[string]$kind.label
        if($GraphicalPlayerReady){
          $preparation=@($preparations|Where-Object {$_.label -ceq [string]$kind.label})
          Assert-MIRDirectLibraryStartupMeasurement ($preparation.Count -eq 1) 'player-ready-preparation-selection'
          $record=Invoke-MIRDirectLibraryGraphicalPlayerReadySample -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot $runRoot -WriteDataRoot $writeDataRoot -PreparedSave $preparedSaves[[string]$kind.label] -PreparedSaveSha256 ([string]$preparation[0].prepared_save_sha256) -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -PlayerReadyBenchmarkTicks $PlayerReadyBenchmarkTicks -ActiveModsObserver $selectedActiveModsObserver
        } else {
          $record=Invoke-MIRDirectLibraryStartupSample -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot $runRoot -WriteDataRoot $writeDataRoot -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -ActiveModsObserver $selectedActiveModsObserver
        }
        $record|Add-Member -NotePropertyName sample -NotePropertyValue $ordinal
        $record|Add-Member -NotePropertyName measurement_block -NotePropertyValue $block
        $record|Add-Member -NotePropertyName configuration_order -NotePropertyValue ($position+1)
        $record|Add-Member -NotePropertyName cache_state -NotePropertyValue ([string]$samplePlanRow.cache_state)
        $record|Add-Member -NotePropertyName prior_selection_label -NotePropertyValue $samplePlanRow.prior_selection_label
        $record|Add-Member -NotePropertyName selection_changed -NotePropertyValue $samplePlanRow.selection_changed
        $record|Add-Member -NotePropertyName warmup -NotePropertyValue ($block -le $WarmupRuns)
        $records.Add($record)
      }
      $previousSelection=[string]$kind.label
    }
    }
    $inputs=[ordered]@{active_mods_observer=$(if([string]::IsNullOrWhiteSpace($selectedActiveModsObserver)){$null}else{[string]$selectedActiveModsObserver});player_ready_observer=$playerReadyObserver;published_422=[ordered]@{archive=$published;authenticated_manifest=$publishedManifest};candidate_423=$(if($hasCandidate){[ordered]@{archive=$candidate;materialization=[ordered]@{archive_path=$candidateMaterialization.path;archive_sha256=$candidateMaterialization.receipt.archive_sha256;receipt_path=$CandidateMaterializationReceiptPath;receipt_sha256=Get-MIRImmutableInputSha256 -Path $CandidateMaterializationReceiptPath;source_version=$candidateMaterialization.receipt.source_version;package_source_sha256=$candidateMaterialization.receipt.package_source_sha256;source_manifest_sha256=$candidateMaterialization.receipt.source_manifest_sha256}}}else{$null})}
    $endpointClass=if($GraphicalPlayerReady){'graphical-player-ready-diagnostic'}else{'headless-create-diagnostic'}
    $notes=@('Elapsed time is native process start-to-exit time recorded by NativeProbeResources.','Peak process values are monitored process-tree samples, not whole-system memory.','Each selected configuration retains one private write-data root across blocks; per-sample logs and saves stay isolated.','Each first sample records its actual prior selection and whether it changed; immediate repeats are marked warm-repeat.','All configurations use the same selected archive library serially; controls are restored after every sample.')
    if($GraphicalPlayerReady){$notes+=@('Each configuration receives one neutral base-only observer save before samples. Preparation processes are recorded separately and are not startup samples.','Graphical process elapsed includes the bounded post-ready benchmark and exit. engine_log_player_ready_seconds is recorded separately from the Factorio log. This diagnostic is not a main-menu readiness or full-startup claim.')}
    $result=[pscustomobject][ordered]@{schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='completed';mode=$(if($hasCandidate){'matched-three-input'}else{'preliminary-two-input'});target=$Target;source_observation=$sourceObservation;factorio=$engineIdentity;library=$library;profile_template_sha256=$templateSha;inputs=$inputs;endpoint_class=$endpointClass;preparations=@($preparations);resource_context=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;processes=@($resources.runs)};samples=@($records);library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')));measurement_notes=$notes}
    Write-MIRNativeProbeResult -Context $resources -Record $result;return $result
  } catch {
    if($null-ne$resources){
      $failureInputs=[ordered]@{active_mods_observer=$(if([string]::IsNullOrWhiteSpace($selectedActiveModsObserver)){$null}else{[string]$selectedActiveModsObserver});player_ready_observer=$playerReadyObserver;published_422=[ordered]@{archive=$published;authenticated_manifest=$publishedManifest};candidate_423=$(if($hasCandidate -and $null-ne$candidate){[ordered]@{archive=$candidate;materialization=$candidateMaterialization}}else{$null})}
      $failure=[pscustomobject][ordered]@{schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='failed';mode=$(if($hasCandidate){'matched-three-input'}else{'preliminary-two-input'});target=$Target;source_observation=$sourceObservation;factorio=$engineIdentity;library=$library;profile_template_sha256=$templateSha;inputs=$failureInputs;endpoint_class=$(if($GraphicalPlayerReady){'graphical-player-ready-diagnostic'}else{'headless-create-diagnostic'});current_label=$currentLabel;preparations=$(if($null-ne$preparations){@($preparations)}else{@()});samples_so_far=$(if($null-ne$records){@($records)}else{@()});error=$_.Exception.Message;library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')));resource_context=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;processes=@($resources.runs)}}
      try{Write-MIRNativeProbeResult -Context $resources -Record $failure}catch{Write-Warning "[mir-direct-startup-failure-receipt] $($_.Exception.Message)"}
    }
    throw
  }
}
