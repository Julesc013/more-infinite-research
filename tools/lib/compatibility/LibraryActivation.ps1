# Serial activation over the existing archive library. No archive staging.
# FactorioRunner supplies the existing immutable-input identity helpers.
. (Join-Path $PSScriptRoot 'ModPortal.ps1')

function Assert-MIRLibraryPath {
  param([string]$Path)
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  while($null -ne $item){
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "[mir-library-reparse] $Path"}
    $item=if($item -is [IO.DirectoryInfo]){$item.Parent}else{$item.Directory}
  }
}

function Assert-MIRLibraryIdle {
  # Conservatively refuse even a personal client whose command line is unknown.
  if(@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count){throw '[mir-library-factorio-active] Wait for the existing client to exit.'}
}

function Test-MIRLibraryModName {
  param([AllowNull()][string]$Name)
  # Factorio permits names (including spaces) beyond the Portal's narrower
  # alphabet. Validate the local filename boundary, not a Portal-only rule.
  return (-not [string]::IsNullOrWhiteSpace($Name) -and $Name.Length -le 100 -and
    $Name -ceq $Name.Trim() -and $Name -notmatch '[\\/:*?"<>|\x00-\x1f]')
}

function Read-MIRLibraryControl {
  param([string]$Path)
  if(-not(Test-Path -LiteralPath $Path)){return [ordered]@{exists=$false;bytes='';sha256=''}}
  Assert-MIRLibraryPath $Path
  if((Get-Item -LiteralPath $Path).PSIsContainer -or (Get-Item -LiteralPath $Path).Length -gt 4MB){throw "[mir-library-control-size] $Path"}
  $bytes=[IO.File]::ReadAllBytes($Path)
  return [ordered]@{exists=$true;bytes=[Convert]::ToBase64String($bytes);sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
}

function Write-MIRLibraryControl {
  param([string]$Path,[byte[]]$Bytes,[switch]$Absent)
  if(Test-Path -LiteralPath $Path){Assert-MIRLibraryPath $Path}
  if($Absent){[IO.File]::Delete($Path);return}
  # Replace the small file atomically; never modify an old hard-linked inode.
  $temp=$Path+'.mir-new'
  if(Test-Path -LiteralPath $temp){Assert-MIRLibraryPath $temp;[IO.File]::Delete($temp)}
  $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($Bytes);$stream.Flush($true)}finally{$stream.Dispose()}
  [IO.File]::Move($temp,$Path,$true)
}

function Restore-MIRLibraryControls {
  param([string]$LibraryDirectory,$Journal)
  if($Journal.kind -cne 'MIRDirectLibraryActivationV1' -or $Journal.library -cne $LibraryDirectory){throw '[mir-library-recovery-identity]'}
  # Validate both backups before restoring either. Paths are fixed, not supplied
  # by the journal. Restoration is repeatable if interrupted halfway through.
  $decoded=@{}
  foreach($name in @('mod-list.json','mod-settings.dat')){
    $row=$Journal.controls[$name]
    if($null -eq $row -or $row.exists -isnot [bool]){throw '[mir-library-recovery-control]'}
    $bytes=[Convert]::FromBase64String([string]$row.bytes)
    if($bytes.Length -gt 4MB -or ($row.exists -and [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $row.sha256) -or
      (-not $row.exists -and ($bytes.Length -ne 0 -or $row.sha256 -ne ''))){throw '[mir-library-recovery-hash]'}
    $decoded[$name]=$bytes
  }
  foreach($name in @('mod-list.json','mod-settings.dat')){Write-MIRLibraryControl -Path (Join-Path $LibraryDirectory $name) -Bytes $decoded[$name] -Absent:(-not $Journal.controls[$name].exists)}
}

function Get-MIRLibraryInventory {
  param([string]$LibraryDirectory,[string]$EngineDataDirectory)
  Assert-MIRLibraryPath $LibraryDirectory
  Assert-MIRLibraryPath $EngineDataDirectory
  $files=@(Get-ChildItem -LiteralPath $LibraryDirectory -Force)
  if($files.Count -gt 4096 -or @($files|Where-Object PSIsContainer).Count){throw '[mir-library-not-flat] Only the flat archive library is supported.'}
  $rows=[Collections.Generic.List[object]]::new()
  foreach($file in @($files|Where-Object Extension -EQ '.zip')){
    Assert-MIRLibraryPath $file.FullName
    $zip=[IO.Compression.ZipFile]::OpenRead($file.FullName)
    try{
      $entries=@($zip.Entries|Where-Object FullName -Match '^[^/]+/info[.]json$')
      if($entries.Count -ne 1 -or $entries[0].Length -gt 64KB){throw "[mir-library-mod-metadata] $($file.Name)"}
      $reader=[IO.StreamReader]::new($entries[0].Open())
      try{$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable}finally{$reader.Dispose()}
    }finally{$zip.Dispose()}
    if(-not(Test-MIRLibraryModName $info.name) -or $info.version -cnotmatch '^\d+[.]\d+[.]\d+$' -or
      $file.Name -cne ($info.name+'_'+$info.version+'.zip')){throw "[mir-library-ambiguous-archive] $($file.Name)"}
    $rows.Add([pscustomobject]@{name=$info.name;version=$info.version;info=$info;path=$file.FullName;builtin=$false;identity=Get-MIRImmutableInputFileIdentity $file.FullName;sha256='';bytes=$file.Length})
  }
  foreach($directory in @(Get-ChildItem -LiteralPath $EngineDataDirectory -Directory)){
    $metadata=Join-Path $directory.FullName 'info.json'
    if($directory.Name -ceq 'core' -or -not(Test-Path -LiteralPath $metadata -PathType Leaf)){continue}
    Assert-MIRLibraryPath $metadata
    $info=Get-Content -LiteralPath $metadata -Raw|ConvertFrom-Json -AsHashtable
    $rows.Add([pscustomobject]@{name=$info.name;version=$info.version;info=$info;path=$metadata;builtin=$true;identity=Get-MIRImmutableInputFileIdentity $metadata;sha256='';bytes=(Get-Item -LiteralPath $metadata).Length})
  }
  if(@($rows|Group-Object name,version|Where-Object Count -GT 1).Count){throw '[mir-library-duplicate-mod-version]'}
  return $rows.ToArray()
}

function Assert-MIRLibraryDependencies {
  param([object[]]$Selected)
  $enabled=@{};foreach($row in $Selected){$enabled[$row.name]=$row}
  foreach($row in $Selected){
    $deps=if($row.info.ContainsKey('dependencies')){@($row.info.dependencies)}else{@('base')}
    foreach($text in $deps){
      $dep=ConvertFrom-MIRDependencyString -Dependency $text
      if($dep.kind -ceq 'incompatible'){
        if($enabled.ContainsKey($dep.name)){throw "[mir-library-incompatible] $($row.name): $text"};continue
      }
      if(-not $enabled.ContainsKey($dep.name)){
        if($dep.required){throw "[mir-library-dependency-missing] $($row.name): $text"};continue
      }
      $constraint=[regex]::Match($text,'\s+(>=|<=|=|>|<)\s*(\d+\.\d+(?:\.\d+)?)\s*$')
      if($constraint.Success){
        $expected=[version]$constraint.Groups[2].Value
        if($expected.Build -lt 0){$expected=[version]::new($expected.Major,$expected.Minor,0)}
        $compare=([version]$enabled[$dep.name].version).CompareTo($expected)
        $ok=switch($constraint.Groups[1].Value){'>='{$compare -ge 0};'<='{$compare -le 0};'='{$compare -eq 0};'>'{$compare -gt 0};'<'{$compare -lt 0}}
        if(-not $ok){throw "[mir-library-dependency-version] $($row.name): $text"}
      }elseif($text -match '[<>=]'){throw "[mir-library-dependency-syntax] $text"}
    }
  }
}

function Start-MIRLibraryActivation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$LibraryDirectory,
    [Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][Collections.IDictionary]$ArchiveHashes,
    [ValidateSet('Defaults','File')][string]$SettingsMode='Defaults',
    [string]$SettingsPath='',[string]$SettingsSha256=''
  )
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  Assert-MIRLibraryPath $library
  Assert-MIRLibraryIdle
  $lockPath=Join-Path $library '.mir-library.lock'
  if(Test-Path -LiteralPath $lockPath){Assert-MIRLibraryPath $lockPath}
  try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '[mir-library-busy] Another activation owns the library.'}
  $handles=[Collections.Generic.List[object]]::new();$journal=$null
  $journalPath=Join-Path $library '.mir-active-profile.json'
  try{
    Assert-MIRLibraryIdle
    if(Test-Path -LiteralPath $journalPath){
      Assert-MIRLibraryPath $journalPath
      if((Get-Item -LiteralPath $journalPath).Length -gt 12MB){throw '[mir-library-recovery-size]'}
      $old=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json -AsHashtable
      $owner=Get-Process -Id ([int]$old.owner_pid) -ErrorAction SilentlyContinue
      if($null -ne $owner -and $owner.StartTime.ToUniversalTime().ToString('o') -ceq $old.owner_started_utc){throw '[mir-library-recovery-owner-alive]'}
      Restore-MIRLibraryControls -LibraryDirectory $library -Journal $old
      [IO.File]::Delete($journalPath)
    }
    $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $library -EngineDataDirectory $EngineDataDirectory)
    $profile=Read-MIRLibraryControl $ProfilePath
    if(-not $profile.exists){throw '[mir-library-profile-missing]'}
    $definition=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($profile.bytes)).TrimStart([char]0xFEFF)|ConvertFrom-Json -AsHashtable
    if($definition.mods -isnot [array] -or @($definition.mods|Group-Object name|Where-Object Count -GT 1).Count){throw '[mir-library-profile-rows]'}
    foreach($row in $definition.mods){if($row.enabled -isnot [bool] -or -not(Test-MIRLibraryModName $row.name)){throw '[mir-library-profile-row]'}}
    $requested=@($definition.mods|Where-Object {$_.enabled -ceq $true})
    if(@($requested|Where-Object name -CEQ 'base').Count -ne 1){throw '[mir-library-base-required]'}
    $selected=[Collections.Generic.List[object]]::new()
    foreach($request in $requested){
      if($request.version -cnotmatch '^\d+[.]\d+[.]\d+$'){throw "[mir-library-version-required] $($request.name)"}
      $matches=@($inventory|Where-Object {$_.name -ceq $request.name -and $_.version -ceq $request.version})
      if($matches.Count -ne 1){throw "[mir-library-version-missing] $($request.name) $($request.version)"}
      $row=$matches[0]
      $handle=[IO.File]::Open($row.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
      $handles.Add($handle)
      $row.sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($handle))
      $handle.Position=0
      if(-not $row.builtin){
        $name=[IO.Path]::GetFileName($row.path)
        if(-not $ArchiveHashes.Contains($name) -or $ArchiveHashes[$name] -cnotmatch '^[0-9A-F]{64}$'){throw "[mir-library-hash-required] $name"}
        if($row.sha256 -cne $ArchiveHashes[$name]){throw "[mir-library-hash-mismatch] $name"}
        $base=@($inventory|Where-Object {$_.builtin -and $_.name -ceq 'base'})
        $line=(([version]$base[0].version).ToString(2))
        if($row.info.factorio_version -cne $line -and -not($line -ceq '1.0' -and $row.info.factorio_version -ceq '0.18')){throw "[mir-library-engine-line] $name"}
      }
      $selected.Add($row)
    }
    if($ArchiveHashes.Count -ne @($selected|Where-Object {-not $_.builtin}).Count){throw '[mir-library-unused-hash]'}
    Assert-MIRLibraryDependencies -Selected $selected.ToArray()
    $settings=$null
    if($SettingsMode -ceq 'File'){
      $settings=Read-MIRLibraryControl $SettingsPath
      if(-not $settings.exists -or $settings.sha256 -cne $SettingsSha256){throw '[mir-library-settings-hash]'}
    }elseif($SettingsPath -or $SettingsSha256){throw '[mir-library-default-settings-conflict]'}
    $activeRows=@(foreach($name in @($inventory.name|Sort-Object -Unique)){
      $chosen=@($selected|Where-Object name -CEQ $name)
      if($chosen.Count){[ordered]@{name=$name;enabled=$true;version=$chosen[0].version}}else{[ordered]@{name=$name;enabled=$false}}
    })
    $activeBytes=[Text.UTF8Encoding]::new($false).GetBytes((@{mods=$activeRows}|ConvertTo-Json -Depth 8))
    $controls=@{};foreach($name in @('mod-list.json','mod-settings.dat')){$controls[$name]=Read-MIRLibraryControl (Join-Path $library $name)}
    $journal=[ordered]@{kind='MIRDirectLibraryActivationV1';library=$library;owner_pid=$PID;owner_started_utc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');controls=$controls}
    Write-MIRLibraryControl -Path $journalPath -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($journal|ConvertTo-Json -Depth 8)))
    Write-MIRLibraryControl -Path (Join-Path $library 'mod-list.json') -Bytes $activeBytes
    if($null -eq $settings){Write-MIRLibraryControl -Path (Join-Path $library 'mod-settings.dat') -Absent}else{Write-MIRLibraryControl -Path (Join-Path $library 'mod-settings.dat') -Bytes ([Convert]::FromBase64String($settings.bytes))}
    return [pscustomobject]@{library=$library;engine_data=(Resolve-Path -LiteralPath $EngineDataDirectory).Path;lock=$lock;handles=$handles;journal=$journal;selected=$selected.ToArray();inventory=$inventory;mod_list_bytes=$activeBytes;profile_sha256=$profile.sha256;closed=$false}
  }catch{
    if($null -ne $journal){try{Assert-MIRLibraryIdle;Restore-MIRLibraryControls -LibraryDirectory $library -Journal $journal;[IO.File]::Delete($journalPath)}catch{Write-Warning 'Library controls require recovery; the durable journal was retained.'}}
    foreach($handle in $handles){$handle.Dispose()};$lock.Dispose();throw
  }
}

function Assert-MIRLibraryActivation {
  param([Parameter(Mandatory)]$Activation)
  if($Activation.closed -or -not $Activation.lock.CanRead){throw '[mir-library-activation-closed]'}
  Assert-MIRLibraryIdle
  $current=@(Get-MIRLibraryInventory -LibraryDirectory $Activation.library -EngineDataDirectory $Activation.engine_data)
  $signature={param($rows) @($rows|Sort-Object path|ForEach-Object {$_.path+'|'+$_.identity+'|'+$_.version}) -join "`n"}
  if((& $signature $current) -cne (& $signature $Activation.inventory)){throw '[mir-library-inventory-changed]'}
  # Reassert the complete selection before each launch; keep settings produced
  # by a previous create/reload within this activation private to this run.
  Write-MIRLibraryControl -Path (Join-Path $Activation.library 'mod-list.json') -Bytes $Activation.mod_list_bytes
}

function Assert-MIRLibraryLoadedSelection {
  param([Parameter(Mandatory)]$Activation,[Parameter(Mandatory)][string]$LogPath)
  $text=[IO.File]::ReadAllText($LogPath)
  $matches=[regex]::Matches($text,'(?m)Loading mod (?:settings )?([^\r\n]+?) (\d+\.\d+\.\d+) \(')
  $observed=@($matches|ForEach-Object {$_.Groups[1].Value+'@'+$_.Groups[2].Value}|Where-Object {$_ -notlike 'core@*'}|Sort-Object -Unique)
  $expected=@($Activation.selected|ForEach-Object {$_.name+'@'+$_.version}|Sort-Object -Unique)
  if(($observed -join '|') -cne ($expected -join '|')){throw '[mir-library-loaded-selection] Actual mod names/versions differ from the profile.'}
  return $observed
}

function Assert-MIRLibraryLaunch {
  param([Parameter(Mandatory)]$Activation,[string]$FactorioBin,[string[]]$Arguments)
  . (Join-Path $PSScriptRoot '../../mir/application/release/readiness/ResourceGovernor.ps1')
  foreach($arg in $Arguments){
    if($arg -match '^(?:--(?:sync-mods|apply-update|download|update-mods)(?:=|$)|--(?:config|mod-directory)=|-c$)'){throw '[mir-library-acquisition-or-ambiguous-argument]'}
  }
  foreach($flag in @('--config','--mod-directory')){
    $indices=@(0..($Arguments.Count-1)|Where-Object {$Arguments[$_] -ceq $flag})
    if($indices.Count -ne 1 -or $indices[0]+1 -ge $Arguments.Count){throw '[mir-library-launch-path-argument]'}
  }
  $mods=$Arguments[[Array]::IndexOf($Arguments,'--mod-directory')+1]
  if([IO.Path]::GetFullPath($mods) -cne $Activation.library){throw '[mir-library-launch-directory]'}
  $configPath=Resolve-MIR441RecoveryScratchPath -Path $Arguments[[Array]::IndexOf($Arguments,'--config')+1]
  $config=[IO.File]::ReadAllText($configPath)
  foreach($entry in @('read-data','write-data')){
    $matches=[regex]::Matches($config,"(?m)^\s*$entry\s*=\s*(.+?)\s*$")
    if($matches.Count -ne 1){throw '[mir-library-launch-config]'}
    if($entry -ceq 'write-data'){$null=Resolve-MIR441RecoveryScratchPath -Path $matches[0].Groups[1].Value}
    elseif([IO.Path]::GetFullPath($matches[0].Groups[1].Value) -cne $Activation.engine_data){throw '[mir-library-launch-engine-data]'}
  }
  $engineData=Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent ([IO.Path]::GetFullPath($FactorioBin))))) 'data'
  if($engineData -cne $Activation.engine_data){throw '[mir-library-launch-engine]'}
  if($config -notmatch '(?m)^enable-new-mods=false\s*$'){throw '[mir-library-auto-enable]'}
  Assert-MIRLibraryActivation -Activation $Activation
}

function Complete-MIRLibraryActivation {
  param([Parameter(Mandatory)]$Activation)
  if($Activation.closed){throw '[mir-library-activation-closed]'}
  # Keep the lock and archive handles if an engine still uses this selection.
  Assert-MIRLibraryIdle
  try{
    Restore-MIRLibraryControls -LibraryDirectory $Activation.library -Journal $Activation.journal
    [IO.File]::Delete((Join-Path $Activation.library '.mir-active-profile.json'))
    return [ordered]@{status='restored-direct-library-controls';profile_sha256=$Activation.profile_sha256;dependency_payload_bytes_copied=0;archive_links_created=0;archive_extractions=0;selected=@($Activation.selected|Select-Object name,version,path,builtin,identity,sha256,bytes)}
  }finally{
    foreach($handle in $Activation.handles){$handle.Dispose()};$Activation.lock.Dispose();$Activation.closed=$true
  }
}
