# Current MIR5 direct-library transaction controls. No Factorio process runs.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/DirectLibraryStartupMeasurement.ps1')
$root=Join-Path $repo ('build/tmp/mir5-library-activation-controls-'+[guid]::NewGuid().ToString('N'))
$checks=0
function Assert-Library([bool]$Condition,[string]$Code){if(-not$Condition){throw "[mir5-library-$Code]"};$script:checks++}
function Refuses-Library([scriptblock]$Action,[string]$Expected){$actual='';try{&$Action|Out-Null}catch{$actual=$_.Exception.Message};Assert-Library ($actual.Contains($Expected)) "refusal-$Expected"}
function New-TestArchive([string]$Library,[string]$Name,[string]$Version,[string]$FactorioVersion='2.1',[string]$SourceDirectory='',[string]$Payload=''){
  $path=Join-Path $Library ($Name+'_'+$Version+'.zip')
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
  try{
    if($SourceDirectory){
      foreach($file in @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File)){
        $relative=[IO.Path]::GetRelativePath($SourceDirectory,$file.FullName).Replace('\','/')
        $entry=$zip.CreateEntry($Name+'_'+$Version+'/'+$relative)
        $destination=$entry.Open();$source=[IO.File]::OpenRead($file.FullName)
        try{$source.CopyTo($destination)}finally{$source.Dispose();$destination.Dispose()}
      }
    }else{
      $entry=$zip.CreateEntry($Name+'_'+$Version+'/info.json');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write((@{name=$Name;version=$Version;factorio_version=$FactorioVersion;dependencies=@('base')}|ConvertTo-Json -Compress))}finally{$writer.Dispose()}
      if($Payload){$entry=$zip.CreateEntry($Name+'_'+$Version+'/data.lua');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write($Payload)}finally{$writer.Dispose()}}
    }
  }finally{$zip.Dispose()}
  return $path
}
function New-NativeFixturePreflightPrefix([string]$Runner,[string]$Path){
  $sourceBytes=[IO.File]::ReadAllBytes($Runner);$source=[Text.UTF8Encoding]::new($false,$true).GetString($sourceBytes)
  # Stop before the health call regardless of its advisory sampling options.
  $boundary="& (Join-Path `$repo 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1')"
  $offset=$source.IndexOf($boundary,[StringComparison]::Ordinal)
  Assert-Library ($offset -gt 0 -and $offset -eq $source.LastIndexOf($boundary,[StringComparison]::Ordinal)) 'native-fixture-preflight-boundary'
  $prefix=[Text.UTF8Encoding]::new($false).GetBytes($source.Substring(0,$offset))
  Assert-Library ($prefix.Length -le $sourceBytes.Length -and [Convert]::ToHexString($prefix) -ceq [Convert]::ToHexString([byte[]]$sourceBytes[0..($prefix.Length-1)])) 'native-fixture-preflight-source-bytes'
  [IO.File]::WriteAllBytes($Path,$prefix+[Text.UTF8Encoding]::new($false).GetBytes("`nreturn`n"))
  $written=[IO.File]::ReadAllBytes($Path)
  Assert-Library ([Convert]::ToHexString([byte[]]$written[0..($prefix.Length-1)]) -ceq [Convert]::ToHexString($prefix)) 'native-fixture-preflight-prefix-bytes'
}
function New-NativeFixtureControlledPreEnforcementOpponent([string]$Prefix,[string]$Path){
  $tokens=$null;$errors=$null
  $ast=[System.Management.Automation.Language.Parser]::ParseFile($Prefix,[ref]$tokens,[ref]$errors)
  Assert-Library ($errors.Count-eq0) 'native-fixture-controlled-pre-enforcement-parse'
  $calls=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Assert-DeclaredFixtureInputs'},$true))
  Assert-Library ($calls.Count-eq1-and$calls[0].Extent.Text-ceq'Assert-DeclaredFixtureInputs -ProfileDefinition $profileDefinition -EngineIdentity $engineIdentity -ArchiveHashes $archiveHashes') 'native-fixture-controlled-pre-enforcement-call'
  $source=[IO.File]::ReadAllText($Prefix,[Text.UTF8Encoding]::new($false,$true));$call=$calls[0]
  $mutated=$source.Remove($call.Extent.StartOffset,$call.Extent.EndOffset-$call.Extent.StartOffset)
  Assert-Library ($mutated.Contains('function Assert-DeclaredFixtureInputs')) 'native-fixture-controlled-pre-enforcement-definition'
  [IO.File]::WriteAllText($Path,$mutated,[Text.UTF8Encoding]::new($false))
  $tokens=$null;$errors=$null;$mutatedAst=[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  Assert-Library ($errors.Count-eq0-and@($mutatedAst.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Assert-DeclaredFixtureInputs'},$true)).Count-eq0) 'native-fixture-controlled-pre-enforcement-only-call'
}
function Assert-NativeFixturePreflightControlsAbsent([string]$Library,[string]$Output){
  Assert-Library (-not(Test-Path -LiteralPath $Output) -and -not(Test-Path -LiteralPath (Join-Path $Library 'mod-list.json')) -and -not(Test-Path -LiteralPath (Join-Path $Library 'mod-settings.dat')) -and -not(Test-Path -LiteralPath (Join-Path $Library '.mir-active-profile.json'))) 'native-fixture-preflight-no-controls'
}
try {
  Assert-Library (-not[bool](Get-Command New-MIRCompatUserDataDir -ErrorAction SilentlyContinue)) 'no-compatibility-runner'
  $library=Join-Path $root 'library';$data=Join-Path $root 'engine/data';$profile=Join-Path $root 'profile.json'
  foreach($path in @($library,(Join-Path $data 'base'),(Join-Path $root 'engine/bin/x64'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  [IO.File]::WriteAllText((Join-Path $data 'base/info.json'),(@{name='base';version='2.1.23';dependencies=@()}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $archive=New-TestArchive -Library $library -Name 'controlled' -Version '1.0.0'
  $originalList='{"mods":[{"name":"base","enabled":true}]}'
  $originalSettings=[byte[]](1,2,3,4)
  [IO.File]::WriteAllText((Join-Path $library 'mod-list.json'),$originalList,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllBytes((Join-Path $library 'mod-settings.dat'),$originalSettings)
  [IO.File]::WriteAllText($profile,(@{mods=@(@{name='base';version='2.1.23';enabled=$true},@{name='controlled';version='1.0.0';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $hashes=@{([IO.Path]::GetFileName($archive))=(Get-MIRImmutableInputSha256 $archive)}
  Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes @{([IO.Path]::GetFileName($archive))=('0'*64)}} '[mir-library-hash-mismatch]'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json'))-ceq$originalList) 'failed-activation-restores-list'
  $activation=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes
  try {
    Assert-Library ($activation.selected.Count-eq2-and-not$activation.closed-and(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'selection-journal'
    Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes} '[mir-library-busy]'
    $active=(Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json')|ConvertFrom-Json)
    Assert-Library (@($active.mods|Where-Object {$_.name-ceq'controlled'-and$_.enabled}).Count-eq1-and-not(Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat'))) 'selection-controls'
    $log=Join-Path $root 'factorio.log';[IO.File]::WriteAllText($log,"0.1 Loading mod base 2.1.23 (data.lua)`n0.1 Loading mod controlled 1.0.0 (data.lua)`n",[Text.UTF8Encoding]::new($false))
    Assert-Library (((Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log)-join'|') -ceq 'base@2.1.23|controlled@1.0.0') 'loaded-selection'
    $config=Join-Path $root 'config.ini';$write=Join-Path $root 'write';[IO.Directory]::CreateDirectory($write)|Out-Null
    New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $data -WriteDataDirectory $write
    $factorio=Join-Path $root 'engine/bin/x64/factorio.exe';[IO.File]::WriteAllText($factorio,'controlled binary',[Text.UTF8Encoding]::new($false))
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library)
    Refuses-Library {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library,'--sync-mods')} '[mir-library-acquisition-or-ambiguous-argument]'
    # Exercise the actual launch guard, not a replacement idle implementation.
    # A transient enumeration may clear; a persistent client must still refuse
    # before the shared controls are rewritten. No engine process is created.
    $priorGetProcess=Get-Item Function:Get-Process -ErrorAction SilentlyContinue
    $script:libraryProcessPolls=0
    $script:libraryProcessPersistent=$false
    $controlPath=Join-Path $library 'mod-list.json'
    $script:libraryControlBefore=(Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks
    function Get-Process {
      param([string]$Name,$ErrorAction)
      if($Name -cne 'factorio'){throw '[mir5-library-unexpected-process-query]'}
      $script:libraryProcessPolls++
      if((Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks -ne $script:libraryControlBefore){throw '[mir5-library-controls-written-before-idle]'}
      if($script:libraryProcessPersistent -or $script:libraryProcessPolls -eq 1){[pscustomobject]@{ProcessName='factorio'}}
    }
    try {
      Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library)
      Assert-Library ($script:libraryProcessPolls -ge 2) 'launch-waits-for-transient-process'
      $script:libraryProcessPolls=0
      $script:libraryProcessPersistent=$true
      $script:libraryControlBefore=(Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks
      Refuses-Library {Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $factorio -Arguments @('--config',$config,'--mod-directory',$library)} '[mir-library-factorio-active]'
      Assert-Library ($script:libraryProcessPolls -ge 2) 'persistent-process-remains-refused'
      Assert-Library ((Get-Item -LiteralPath $controlPath).LastWriteTimeUtc.Ticks -eq $script:libraryControlBefore) 'busy-launch-preserves-controls'
    } finally {
      Remove-Item Function:Get-Process
      if($null -ne $priorGetProcess){Set-Item Function:Get-Process $priorGetProcess.ScriptBlock}
    }
  } finally {if($null-ne$activation-and-not$activation.closed){$completion=Complete-MIRLibraryActivation -Activation $activation}}
  Assert-Library ($completion.status-ceq'restored-direct-library-controls'-and-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'completion'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $library 'mod-list.json'))-ceq$originalList-and([IO.File]::ReadAllBytes((Join-Path $library 'mod-settings.dat'))-join',')-ceq($originalSettings-join',')) 'restoration'
  # Emulate the observed legacy engine writer in the disposable library only.
  # The same removal control fails against a bounded pre-JSON restore opponent.
  $legacyJson=Join-Path $library 'mod-settings.json'
  function Test-GeneratedLegacySettingsRemoval {
    $owned=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes
    try{[IO.File]::WriteAllText($legacyJson,'{"engine-generated":true}',[Text.UTF8Encoding]::new($false))}
    finally{$null=Complete-MIRLibraryActivation -Activation $owned}
    return -not(Test-Path -LiteralPath $legacyJson)
  }
  $restoreBody=${function:Restore-MIRLibraryControls}
  $jsonAdmission="if(`$Journal.controls.Contains('mod-settings.json')){`$names+='mod-settings.json'}"
  $opponentBody=$restoreBody.ToString()
  Assert-Library ([regex]::Matches($opponentBody,[regex]::Escape($jsonAdmission)).Count-eq1) 'legacy-json-opponent-one-optional-row-admission'
  try{
    # Remove only optional JSON ownership; all old two-control validation,
    # archive guards and restoration still execute. No old checkout is loaded.
    Set-Item Function:Restore-MIRLibraryControls ([scriptblock]::Create($opponentBody.Replace($jsonAdmission,'')))
    Assert-Library (-not(Test-GeneratedLegacySettingsRemoval)) 'legacy-json-controlled-old-restore-leaves-generated-file'
  }finally{Set-Item Function:Restore-MIRLibraryControls $restoreBody;[IO.File]::Delete($legacyJson)}
  Assert-Library (Test-GeneratedLegacySettingsRemoval) 'legacy-json-new-restore-removes-generated-file'
  $originalLegacyJson=[Text.UTF8Encoding]::new($false).GetBytes("{`"startup`":{`"sentinel`":`"original`"}}`r`n")
  [IO.File]::WriteAllBytes($legacyJson,$originalLegacyJson)
  $jsonOriginalHash=Get-MIRImmutableInputSha256 $legacyJson
  foreach($settingsMode in @('Defaults','File')){
    $settingsArguments=@{}
    if($settingsMode-ceq'File'){
      $settingsInput=Join-Path $root 'supplied-settings.dat';[IO.File]::WriteAllBytes($settingsInput,[byte[]](9,8,7))
      $settingsArguments=@{SettingsMode='File';SettingsPath=$settingsInput;SettingsSha256=Get-MIRImmutableInputSha256 $settingsInput}
    }
    $owned=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes @settingsArguments
    try{
      Assert-Library ($owned.journal.controls.Contains('mod-settings.json')-and-not(Test-Path -LiteralPath $legacyJson)) ('legacy-json-'+$settingsMode+'-quarantines-original')
      if($settingsMode-ceq'Defaults'){Assert-Library (-not(Test-Path -LiteralPath (Join-Path $library 'mod-settings.dat'))) 'legacy-json-defaults-removes-both-formats'}
      else{Assert-Library ((Get-MIRImmutableInputSha256 (Join-Path $library 'mod-settings.dat'))-ceq(Get-MIRImmutableInputSha256 $settingsInput)) 'legacy-json-file-still-pins-binary-settings'}
      [IO.File]::WriteAllText($legacyJson,'{"engine-replaced":true}',[Text.UTF8Encoding]::new($false))
    }finally{$null=Complete-MIRLibraryActivation -Activation $owned}
    Assert-Library ((Get-MIRImmutableInputSha256 $legacyJson)-ceq$jsonOriginalHash) ('legacy-json-'+$settingsMode+'-restores-exact-original-bytes')
  }
  # Fail after live JSON removal, then exercise the real activation catch.
  $controlWriter=${function:Write-MIRLibraryControl};$script:failLegacyDatRemoval=$true
  function Write-MIRLibraryControl {
    param([string]$Path,[byte[]]$Bytes,[switch]$Absent)
    if($script:failLegacyDatRemoval-and$Absent-and(Split-Path -Leaf $Path)-ceq'mod-settings.dat'){$script:failLegacyDatRemoval=$false;throw '[controlled-legacy-json-activation-failure]'}
    & $controlWriter @PSBoundParameters
  }
  try{Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes} '[controlled-legacy-json-activation-failure]'}
  finally{Set-Item Function:Write-MIRLibraryControl $controlWriter}
  Assert-Library ((Get-MIRImmutableInputSha256 $legacyJson)-ceq$jsonOriginalHash-and-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json'))) 'legacy-json-activation-failure-restores-original'
  # Abandon only this disposable activation's handles to emulate interrupted
  # ownership, then let Start recover the durable journal before a new launch.
  $abandoned=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes
  $recoveryJournal=$abandoned.journal|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
  foreach($handle in $abandoned.handles){$handle.Dispose()};$abandoned.lock.Dispose();$abandoned.closed=$true
  $recoveryJournal.owner_pid=[int]::MaxValue;$recoveryJournal.owner_started_utc='2000-01-01T00:00:00Z'
  [IO.File]::WriteAllText((Join-Path $library '.mir-active-profile.json'),($recoveryJournal|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($legacyJson,'{"interrupted-engine":true}',[Text.UTF8Encoding]::new($false))
  $recovered=Start-MIRLibraryActivation -LibraryDirectory $library -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes $hashes
  try{Assert-Library ($recovered.journal.controls['mod-settings.json'].sha256-ceq$jsonOriginalHash-and-not(Test-Path -LiteralPath $legacyJson)) 'legacy-json-recovery-restores-original-before-next-defaults'}
  finally{$null=Complete-MIRLibraryActivation -Activation $recovered}
  Assert-Library ((Get-MIRImmutableInputSha256 $legacyJson)-ceq$jsonOriginalHash) 'legacy-json-recovery-completes-with-exact-original'
  $oldJournal=$recoveryJournal|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
  $oldJournal.controls.Remove('mod-settings.json')
  [IO.File]::WriteAllText($legacyJson,'{"foreign-to-old-journal":true}',[Text.UTF8Encoding]::new($false))
  $foreignHash=Get-MIRImmutableInputSha256 $legacyJson;$foreignTicks=(Get-Item -LiteralPath $legacyJson).LastWriteTimeUtc.Ticks
  Restore-MIRLibraryControls -LibraryDirectory $library -Journal $oldJournal
  Assert-Library ((Get-MIRImmutableInputSha256 $legacyJson)-ceq$foreignHash-and(Get-Item -LiteralPath $legacyJson).LastWriteTimeUtc.Ticks-eq$foreignTicks) 'legacy-json-old-two-control-journal-preserves-foreign-file'
  [IO.File]::Delete($legacyJson)
  # Individually bounded backups must not create a journal larger than the
  # unchanged recovery reader can consume. Reject before any control write.
  $budgetLibrary=Join-Path $root 'aggregate-control-budget';[void][IO.Directory]::CreateDirectory($budgetLibrary)
  $budgetArchive=New-TestArchive $budgetLibrary 'controlled' '1.0.0'
  $budgetBefore=@{};$budgetBytes=[byte[]]::new(3MB)
  foreach($name in @('mod-list.json','mod-settings.dat','mod-settings.json')){
    $path=Join-Path $budgetLibrary $name;[IO.File]::WriteAllBytes($path,$budgetBytes)
    $budgetBefore[$path]=@{hash=Get-MIRImmutableInputSha256 $path;ticks=(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks}
  }
  Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $budgetLibrary -EngineDataDirectory $data -ProfilePath $profile -ArchiveHashes @{([IO.Path]::GetFileName($budgetArchive))=(Get-MIRImmutableInputSha256 $budgetArchive)}} '[mir-library-recovery-size]'
  foreach($path in $budgetBefore.Keys){Assert-Library ((Get-MIRImmutableInputSha256 $path)-ceq$budgetBefore[$path].hash-and(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks-eq$budgetBefore[$path].ticks) 'legacy-json-aggregate-budget-refuses-before-control-write'}
  Assert-Library (-not(Test-Path -LiteralPath (Join-Path $budgetLibrary '.mir-active-profile.json'))) 'legacy-json-aggregate-budget-refuses-before-live-journal'
  # Native 2.1.23 normal exit preserves names/booleans but removes enabled
  # versions. Exercise the real guard with host-only owned-process doubles.
  # Independent versions deliberately distinguish numeric from lexical order.
  $priorGetProcess=Get-Item Function:Get-Process -ErrorAction SilentlyContinue
  $priorGetCim=Get-Item Function:Get-CimInstance -ErrorAction SilentlyContinue
  $script:liveProcesses=@()
  function Get-Process {param([string]$Name,[int[]]$Id,$ErrorAction) if($Id){return Microsoft.PowerShell.Management\Get-Process -Id $Id};if($Name-cne'factorio'){throw 'unexpected live process query'};$script:liveProcesses}
  function Get-CimInstance {param([string]$ClassName,[string]$Filter) if($ClassName-cne'Win32_Process'-or$Filter-cne'ProcessId=555001'){throw 'unexpected live parent query'};[pscustomobject]@{ParentProcessId=$PID}}
  try{
    foreach($mode in @('latest','older','higher-incompatible','numeric-tie')){
      $liveLibrary=Join-Path $root ('live-'+$mode);[IO.Directory]::CreateDirectory($liveLibrary)|Out-Null
      $null=New-TestArchive $liveLibrary 'controlled' '1.9.0'
      $null=New-TestArchive $liveLibrary 'controlled' '1.10.0'
      $null=New-TestArchive $liveLibrary 'disabled' '1.0.0'
      if($mode-ceq'higher-incompatible'){$null=New-TestArchive $liveLibrary 'controlled' '2.0.0' '2.0'}
      if($mode-ceq'numeric-tie'){$null=New-TestArchive $liveLibrary 'controlled' '1.010.0'}
      $chosen=if($mode-ceq'older'){'1.9.0'}else{'1.10.0'}
      $liveProfile=Join-Path $root ('live-'+$mode+'.json')
      [IO.File]::WriteAllText($liveProfile,(@{mods=@(@{name='base';version='2.1.23';enabled=$true},@{name='controlled';version=$chosen;enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
      $liveArchive=Join-Path $liveLibrary ('controlled_'+$chosen+'.zip')
      $liveActivation=Start-MIRLibraryActivation -LibraryDirectory $liveLibrary -EngineDataDirectory $data -ProfilePath $liveProfile -ArchiveHashes @{([IO.Path]::GetFileName($liveArchive))=(Get-MIRImmutableInputSha256 $liveArchive)}
      $script:liveProcesses=@([pscustomobject]@{Id=555001;HasExited=$false;StartTime=[datetime]'2026-11-02T00:00:00Z'})
      function Assert-LiveList($Rows,[string]$Expected=''){
        $path=Join-Path $liveLibrary 'mod-list.json'
        [IO.File]::WriteAllText($path,(@{mods=@($Rows)}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        $hash=Get-MIRImmutableInputSha256 $path;$ticks=(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
        if($Expected){Refuses-Library {Assert-MIRLibraryActivation -Activation $liveActivation -OwnedProcesses $script:liveProcesses} $Expected}else{Assert-MIRLibraryActivation -Activation $liveActivation -OwnedProcesses $script:liveProcesses;Assert-Library $true ('live-'+$mode)}
        Assert-Library ((Get-MIRImmutableInputSha256 $path)-ceq$hash-and(Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks-eq$ticks) 'live-controls-never-written'
      }
      try{
        $pinned=@(@{name='base';enabled=$true;version='2.1.23'},@{name='controlled';enabled=$true;version=$chosen},@{name='disabled';enabled=$false})
        Assert-LiveList $pinned
        $native=@(@{name='base';enabled=$true},@{name='controlled';enabled=$true},@{name='disabled';enabled=$false})
        if($mode-ceq'latest'){
          Assert-LiveList $native
          Assert-LiveList @(@{name='controlled';enabled=$true;version=$chosen},@{name='disabled';enabled=$false},@{name='base';enabled=$true})
          foreach($wrong in @('1.9.0','',$null,110)){
            Assert-LiveList @(@{name='base';enabled=$true},@{name='controlled';enabled=$true;version=$wrong},@{name='disabled';enabled=$false}) '[mir-library-live-selection]'
          }
          Assert-LiveList @(@{name='base';enabled=$true},@{name='controlled';enabled=$false},@{name='disabled';enabled=$false}) '[mir-library-live-selection]'
          Assert-LiveList @(@{name='base';enabled=$true},@{name='controlled';enabled='true'},@{name='disabled';enabled=$false}) '[mir-library-live-selection]'
          Assert-LiveList ($native+@{name='unexpected';enabled=$true;version='1.0.0'}) '[mir-library-live-selection]'
          Assert-LiveList ($native+$native[0]) '[mir-library-live-selection]'
          Assert-LiveList @($native[0],$native[1]) '[mir-library-live-selection]'
          $extra=New-TestArchive $liveLibrary 'unexpected' '1.0.0'
          Assert-LiveList $native '[mir-library-inventory-changed]'
          [IO.File]::Delete($extra)
        }else{Assert-LiveList $native '[mir-library-live-selection]'}
      }finally{$script:liveProcesses=@();$null=Complete-MIRLibraryActivation -Activation $liveActivation}
    }
  }finally{
    Remove-Item Function:Get-Process,Function:Get-CimInstance -ErrorAction SilentlyContinue
    if($null-ne$priorGetProcess){Set-Item Function:Get-Process $priorGetProcess.ScriptBlock}
    if($null-ne$priorGetCim){Set-Item Function:Get-CimInstance $priorGetCim.ScriptBlock}
  }
  # Exercise the existing legacy owned-name transaction with disposable
  # authored ZIPs only. No real engine or external mod library is accessed.
  $legacy=Join-Path $root 'legacy-library';$legacyData=Join-Path $root 'legacy-engine/data'
  foreach($path in @($legacy,(Join-Path $legacyData 'base'))){[IO.Directory]::CreateDirectory($path)|Out-Null}
  [IO.File]::WriteAllText((Join-Path $legacyData 'base/info.json'),'{"name":"base","version":"0.13.20","dependencies":[]}',[Text.UTF8Encoding]::new($false))
  $chosen=New-TestArchive $legacy 'more-infinite-research' '5.0.01300' '0.13'
  $alternate=New-TestArchive $legacy 'more-infinite-research' '4.7.01303' '0.13'
  $dependency=New-TestArchive $legacy 'controlled' '1.0.0' '0.13'
  $otherDependency=New-TestArchive $legacy 'controlled' '2.0.0' '0.13'
  $originals=@{}
  foreach($path in @($chosen,$alternate,$dependency,$otherDependency)){
    $originals[$path]=@{sha256=Get-MIRImmutableInputSha256 $path;identity=Get-MIRImmutableInputFileIdentity $path}
  }
  [IO.File]::WriteAllText((Join-Path $legacy 'mod-list.json'),$originalList,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllBytes((Join-Path $legacy 'mod-settings.dat'),$originalSettings)
  $legacyProfile=Join-Path $root 'legacy-profile.json'
  [IO.File]::WriteAllText($legacyProfile,(@{mods=@(@{name='base';version='0.13.20';enabled=$true},@{name='more-infinite-research';version='5.0.01300';enabled=$true},@{name='controlled';version='1.0.0';enabled=$true})}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $legacyHashes=@{([IO.Path]::GetFileName($chosen))=$originals[$chosen].sha256;([IO.Path]::GetFileName($dependency))=$originals[$dependency].sha256}
  Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $legacy -EngineDataDirectory $legacyData -ProfilePath $legacyProfile -ArchiveHashes $legacyHashes -PrePinMIROwnedArchiveNames @('controlled')} '[mir-library-owned-version-dependency-forbidden]'
  $activation=Start-MIRLibraryActivation -LibraryDirectory $legacy -EngineDataDirectory $legacyData -ProfilePath $legacyProfile -ArchiveHashes $legacyHashes -PrePinMIROwnedArchiveNames @('more-infinite-research')
  try{
    $hidden=@(Get-ChildItem -LiteralPath $legacy -Filter '*.mir-hidden-*')
    Assert-Library ($hidden.Count-eq1-and-not(Test-Path -LiteralPath $alternate)) 'only-alternate-owned-version-hidden'
    Assert-Library ((Get-MIRImmutableInputSha256 $hidden[0].FullName)-ceq$originals[$alternate].sha256-and(Get-MIRImmutableInputFileIdentity $hidden[0].FullName)-ceq$originals[$alternate].identity) 'hidden-identity-and-bytes'
    foreach($path in @($chosen,$dependency,$otherDependency)){
      Assert-Library ((Get-MIRImmutableInputSha256 $path)-ceq$originals[$path].sha256-and(Get-MIRImmutableInputFileIdentity $path)-ceq$originals[$path].identity) 'selected-and-dependency-archives-untouched'
    }
    # All optional JSON backup checks must precede every control write and the
    # existing owned-archive visibility restore, including the real hidden ZIP.
    [IO.File]::WriteAllText((Join-Path $legacy 'mod-settings.json'),'{"live":true}',[Text.UTF8Encoding]::new($false))
    $liveControls=@{};foreach($name in @('mod-list.json','mod-settings.dat','mod-settings.json')){$liveControls[$name]=Read-MIRLibraryControl (Join-Path $legacy $name)}
    foreach($bad in @('null','boolean','base64','bytes-type','hash-type','hash','absent-bytes','size')){
      $journal=$activation.journal|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable
      $row=@{exists=$true;bytes=[Convert]::ToBase64String($originalLegacyJson);sha256=$jsonOriginalHash};$expectedRecoveryError='[mir-library-recovery-control]'
      switch($bad){
        'null'{$row=$null};'boolean'{$row.exists='true'};'base64'{$row.bytes='not-base64!'};'bytes-type'{$row.bytes=42};'hash-type'{$row.sha256=42}
        'hash'{$row.sha256='0'*64;$expectedRecoveryError='[mir-library-recovery-hash]'}
        'absent-bytes'{$row.exists=$false;$row.sha256='';$expectedRecoveryError='[mir-library-recovery-hash]'}
        'size'{$large=[byte[]]::new(4MB+1);$row.bytes=[Convert]::ToBase64String($large);$row.sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($large));$expectedRecoveryError='[mir-library-recovery-hash]'}
      }
      $journal.controls['mod-settings.json']=$row
      Refuses-Library {Restore-MIRLibraryControls -LibraryDirectory $legacy -Journal $journal} $expectedRecoveryError
      Assert-Library (-not(Test-Path -LiteralPath $alternate)-and(Test-Path -LiteralPath $hidden[0].FullName)-and(Get-MIRImmutableInputSha256 $hidden[0].FullName)-ceq$originals[$alternate].sha256) ('legacy-json-'+$bad+'-rejects-before-archive-rename')
      foreach($name in $liveControls.Keys){$actual=Read-MIRLibraryControl (Join-Path $legacy $name);Assert-Library (($actual|ConvertTo-Json -Compress)-ceq($liveControls[$name]|ConvertTo-Json -Compress)) ('legacy-json-'+$bad+'-rejects-before-control-write')}
    }
  }finally{if($null-ne$activation-and-not$activation.closed){$completion=Complete-MIRLibraryActivation -Activation $activation}}
  foreach($path in $originals.Keys){
    Assert-Library ((Get-MIRImmutableInputSha256 $path)-ceq$originals[$path].sha256-and(Get-MIRImmutableInputFileIdentity $path)-ceq$originals[$path].identity) 'legacy-original-identity-and-bytes-restored'
  }
  Assert-Library ($completion.owned_archive_names_temporarily_hidden-eq1-and@(Get-ChildItem -LiteralPath $legacy -Filter '*.mir-hidden-*').Count-eq0-and-not(Test-Path -LiteralPath (Join-Path $legacy '.mir-active-profile.json'))) 'legacy-owned-selection-restored'
  Assert-Library ((Get-Content -Raw -LiteralPath (Join-Path $legacy 'mod-list.json'))-ceq$originalList-and([IO.File]::ReadAllBytes((Join-Path $legacy 'mod-settings.dat'))-join',')-ceq($originalSettings-join',')) 'legacy-controls-restored'
  # Execute the real normal fixture-runner preflight through its existing
  # health boundary. The temporary prefix is byte-identical source up to that
  # boundary and returns before resource admission, control writes, or any
  # native process can begin.
  $preflightRoot=Join-Path $root 'native-fixture-preflight';$preflightLibrary=Join-Path $preflightRoot 'library';$preflightData=Join-Path $preflightRoot 'engine/data';$preflightOutput=Join-Path $preflightRoot 'output';$preflightProfile=Join-Path $preflightRoot 'profile.json';$fixtureSource=Join-Path $preflightRoot 'fixture-source'
  foreach($path in @($preflightLibrary,(Join-Path $preflightData 'base'),(Join-Path $preflightRoot 'engine/bin/x64'),$fixtureSource)){[IO.Directory]::CreateDirectory($path)|Out-Null}
  [IO.File]::WriteAllText((Join-Path $preflightData 'base/info.json'),'{"name":"base","version":"2.1.23","dependencies":[]}',[Text.UTF8Encoding]::new($false))
  $fixtureInfo=@{name='mir-fixture-preflight';version='0.1.0';factorio_version='2.1';dependencies=@('base')}|ConvertTo-Json -Compress
  [IO.File]::WriteAllText((Join-Path $fixtureSource 'info.json'),$fixtureInfo,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText((Join-Path $fixtureSource 'data.lua'),'-- bounded runner preflight fixture',[Text.UTF8Encoding]::new($false))
  $preflightDependency=New-TestArchive -Library $preflightLibrary -Name 'controlled' -Version '1.0.0'
  $preflightMir=New-TestArchive -Library $preflightLibrary -Name 'more-infinite-research' -Version '5.0.21000'
  $preflightFixture=New-TestArchive -Library $preflightLibrary -Name 'mir-fixture-preflight' -Version '0.1.0' -SourceDirectory $fixtureSource
  $preflightEngine=Join-Path $preflightRoot 'engine/bin/x64/factorio.exe';[IO.File]::WriteAllText($preflightEngine,'fixture preflight engine',[Text.UTF8Encoding]::new($false))
  $engineSha=Get-MIRImmutableInputSha256 $preflightEngine;$dependencyName=[IO.Path]::GetFileName($preflightDependency);$mirSha=Get-MIRImmutableInputSha256 $preflightMir
  $preflightMods=@(@{name='base';version='2.1.23';enabled=$true},@{name='controlled';version='1.0.0';enabled=$true},@{name='more-infinite-research';version='5.0.21000';enabled=$true},@{name='mir-fixture-preflight';version='0.1.0';enabled=$true})
  function New-PreflightProfile([AllowNull()]$Engine,[AllowNull()]$ArchiveHashes){
    $value=[ordered]@{mods=$preflightMods}
    if($null-ne$Engine){$value.engine=$Engine}
    if($null-ne$ArchiveHashes){$value.archive_sha256=$ArchiveHashes}
    return $value
  }
  function Set-PreflightProfile($Value){[IO.File]::WriteAllText($preflightProfile,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
  $runner=Join-Path $repo 'tools/Invoke-NativeFixture.ps1';$preflightRunner=Join-Path $preflightRoot 'Invoke-NativeFixture-preflight.ps1';New-NativeFixturePreflightPrefix -Runner $runner -Path $preflightRunner
  $runnerArguments=@{ArchiveLibrary=$preflightLibrary;FactorioBin=$preflightEngine;ProfilePath=$preflightProfile;FixtureSources=@($fixtureSource);ExpectedMIRArchiveSha256=$mirSha;CaseName='declared-input-preflight';OutputRoot=$preflightOutput;AdmissionWaitSeconds=0;RepoRoot=$repo}
  $validEngine=@{version='2.1.23';sha256=$engineSha};$removedPin=('A'*64 -join '')
  Set-PreflightProfile (New-PreflightProfile -Engine $validEngine -ArchiveHashes @{($dependencyName)=(Get-MIRImmutableInputSha256 $preflightDependency);'removed-provider_9.9.9.zip'=$removedPin;'more-infinite-research_4.7.21003.zip'=$removedPin})
  & $preflightRunner @runnerArguments
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine $validEngine -ArchiveHashes @{'removed-provider_9.9.9.zip'=$removedPin;'more-infinite-research_4.7.21003.zip'=$removedPin})
  & $preflightRunner @runnerArguments
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine $null -ArchiveHashes $null)
  & $preflightRunner @runnerArguments
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine @{version='2.1.22';sha256=$engineSha} -ArchiveHashes @{})
  Refuses-Library {& $preflightRunner @runnerArguments} '[mir5-native-fixture] profile engine base differs'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine @{version='2.1.23';sha256=('0'*64 -join '')} -ArchiveHashes @{})
  Refuses-Library {& $preflightRunner @runnerArguments} '[mir5-native-fixture] profile engine hash differs'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine '2.1.23' -ArchiveHashes @{})
  Refuses-Library {& $preflightRunner @runnerArguments} '[mir5-native-fixture] profile engine metadata differs'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  $wrongSelected=@{($dependencyName)=('0'*64 -join '')}
  Set-PreflightProfile (New-PreflightProfile -Engine $validEngine -ArchiveHashes $wrongSelected)
  # This is a controlled pre-enforcement opponent derived from this exact
  # runner prefix: it removes only the one new assertion call, never obtains
  # an old Git object, and still returns before health, controls, or launch.
  $controlledPreEnforcementRunner=Join-Path $preflightRoot 'Invoke-NativeFixture-controlled-pre-enforcement-preflight.ps1';New-NativeFixtureControlledPreEnforcementOpponent -Prefix $preflightRunner -Path $controlledPreEnforcementRunner
  & $controlledPreEnforcementRunner @runnerArguments
  Assert-Library $true 'native-fixture-controlled-pre-enforcement-admits-wrong-selected-pin'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Refuses-Library {& $preflightRunner @runnerArguments} '[mir5-native-fixture] profile selected archive hash differs'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine $validEngine -ArchiveHashes @{($dependencyName)='not-a-sha'})
  Refuses-Library {& $preflightRunner @runnerArguments} '[mir5-native-fixture] profile selected archive hash is malformed'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine $validEngine -ArchiveHashes 'not-an-archive-map')
  Refuses-Library {& $preflightRunner @runnerArguments} '[mir5-native-fixture] profile archive metadata differs'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  Set-PreflightProfile (New-PreflightProfile -Engine $validEngine -ArchiveHashes @{($dependencyName)=(Get-MIRImmutableInputSha256 $preflightDependency)})
  $capturedHashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $preflightLibrary -EngineDataDirectory $preflightData -BaseRows $preflightMods -MirArchive $null
  Remove-Item -LiteralPath $preflightDependency -Force
  $preflightDependency=New-TestArchive -Library $preflightLibrary -Name 'controlled' -Version '1.0.0' -Payload '-- same-version repack'
  Refuses-Library {Start-MIRLibraryActivation -LibraryDirectory $preflightLibrary -EngineDataDirectory $preflightData -ProfilePath $preflightProfile -ArchiveHashes $capturedHashes -SettingsMode Defaults} '[mir-library-hash-mismatch]'
  Assert-NativeFixturePreflightControlsAbsent -Library $preflightLibrary -Output $preflightOutput
  [pscustomobject]@{status='passed';checks=$checks;native_execution=$false;package_materialization=$false;controlled_pre_json_restore_leaves_generated_json=$true}|ConvertTo-Json -Compress
} finally {
  if(Test-Path -LiteralPath $root){Remove-MIR441ContainedTree -AdmittedRoot (Join-Path $repo 'build/tmp') -Path $root}
}
