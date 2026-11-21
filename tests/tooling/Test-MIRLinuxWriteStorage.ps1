# No Factorio is launched. The opt-in Linux child exercises the real governor;
# default controls remain observation/composition only. Expectations are exact.
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$LinuxDataTestParent='',
  [string]$LinuxLibraryRoot='',
  [switch]$GovernedSplitChild
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
if($GovernedSplitChild -and (-not $IsLinux -or -not $LinuxDataTestParent -or -not $LinuxLibraryRoot)){
  throw 'Governed split-path control requires actual Linux data/library test roots.'
}
$checks=0
function Assert-Storage([bool]$Condition,[string]$Name){if(-not $Condition){throw "[storage-control-$Name]"};$script:checks++}
function Refuses-Storage([scriptblock]$Action,[string]$Expected){
  $message='';try{& $Action | Out-Null}catch{$message=$_.Exception.Message}
  Assert-Storage ($message.Contains($Expected)) "$Expected observed=$message"
}
function New-StorageRow([string]$Device,[long]$Peak,[long]$Used,[long]$Reserve,[long]$Free,[long]$Mount=42){
  [pscustomobject]@{device=$Device;mount_id=$Mount;peak_new_bytes=$Peak;used_new_bytes=$Used;reserve_bytes=$Reserve;free_bytes=$Free}
}

# Exact boundary, then one byte below; no 20 GiB constant participates.
$data=New-StorageRow '8:2' 1000 0 200 1200
$volumes=@(Assert-MIRLinuxWriteCapacity -Rows @($data))
Assert-Storage ($volumes.Count -eq 1 -and $volumes[0].remaining_bytes -eq 1000 -and $volumes[0].reserve_bytes -eq 200) 'exact-initial-boundary'
$data.free_bytes=1199
Refuses-Storage {Assert-MIRLinuxWriteCapacity -Rows @($data)} '[mir-linux-storage-capacity]'
$data.used_new_bytes=400;$data.free_bytes=800
$null=Assert-MIRLinuxWriteCapacity -Rows @($data)
Assert-Storage $true 'live-remaining-plus-margin'
$data.free_bytes=799
Refuses-Storage {Assert-MIRLinuxWriteCapacity -Rows @($data)} '[mir-linux-storage-capacity]'
$data.used_new_bytes=1001
Refuses-Storage {Assert-MIRLinuxWriteCapacity -Rows @($data)} '[mir441-resource-output-budget]'
$data.used_new_bytes=-1
Refuses-Storage {Assert-MIRLinuxWriteCapacity -Rows @($data)} '[mir-linux-storage-observation]'

# Bind mounts share one capacity pool. Add peaks, retain one maximum margin,
# and use the lower observed free count rather than adding free space.
$control=New-StorageRow '8:1' 100 0 30 370 41
$library=New-StorageRow '8:1' 200 0 70 999 42
$volumes=@(Assert-MIRLinuxWriteCapacity -Rows @($control,$library))
Assert-Storage ($volumes.Count -eq 1 -and $volumes[0].remaining_bytes -eq 300 -and $volumes[0].reserve_bytes -eq 70 -and $volumes[0].free_bytes -eq 370) 'shared-device-budget'
$control.free_bytes=369
Refuses-Storage {Assert-MIRLinuxWriteCapacity -Rows @($control,$library)} '[mir-linux-storage-capacity]'
$control.free_bytes=130;$library.device='8:2';$library.free_bytes=270
$volumes=@(Assert-MIRLinuxWriteCapacity -Rows @($control,$library))
Assert-Storage ($volumes.Count -eq 2) 'distinct-destinations-no-system-disk-row'
$library.device='bad'
Refuses-Storage {Assert-MIRLinuxWriteCapacity -Rows @($control,$library)} '[mir441-resource-linux-mount-device]'
if(-not $IsLinux){
  Refuses-Storage {Read-MIRLinuxWriteStorage -Path 'unused' -Sha256 ('A'*64) -ControlRoot $RepoRoot -LibraryRoot $RepoRoot -MaxNewOutputBytes 1MB} '[mir-linux-storage-linux-required]'
}

$scratch=Join-Path $RepoRoot ('build/tmp/linux-write-controls-'+[guid]::NewGuid().ToString('N'))
try{
  [IO.Directory]::CreateDirectory($scratch) | Out-Null
  $dataRoot=Join-Path $scratch 'data';$controlRoot=Join-Path $scratch 'control';$libraryRoot=Join-Path $scratch 'library'
  foreach($directory in @($dataRoot,$controlRoot,$libraryRoot)){[IO.Directory]::CreateDirectory($directory) | Out-Null}
  $filesystemRoot=[IO.Path]::GetPathRoot($scratch)
  Assert-Storage ((Resolve-MIRLinuxWritePath -Path $filesystemRoot) -ceq $filesystemRoot) 'filesystem-root-metadata'
  $minimal=Join-Path $scratch 'legacy-scan';[IO.Directory]::CreateDirectory($minimal) | Out-Null
  $junction=Join-Path $minimal 'excluded'
  New-Item -ItemType $(if($IsWindows){'Junction'}else{'SymbolicLink'}) -Path $junction -Target $libraryRoot | Out-Null
  try{
    Refuses-Storage {Get-MIRNativeProbeRemainingOutputBytes -Context ([pscustomobject]@{aliases=@();root=$minimal})} '[mir441-resource-output-scan-incomplete] '
  }finally{[IO.Directory]::Delete($junction)}
  if($LinuxDataTestParent -or $LinuxLibraryRoot){
    if(-not $IsLinux -or -not $LinuxDataTestParent -or -not $LinuxLibraryRoot){throw 'Linux mount controls require both explicit existing input roots.'}
    $parent=Resolve-MIRLinuxWritePath -Path $LinuxDataTestParent
    if(-not (Test-Path -LiteralPath $parent -PathType Container)){throw 'Missing external test parent.'}
    $external=Join-Path $parent ('write-storage-control-'+[guid]::NewGuid().ToString('N'))
    try{
      [IO.Directory]::CreateDirectory($external) | Out-Null
      $planRoots=@()
      foreach($spec in @(@('control',$controlRoot,1MB),@('data',$external,2MB),@('library',$LinuxLibraryRoot,1MB))){
        $mount=Invoke-MIR441LinuxResourceObservation -Operation mount-identity -Path $spec[1]
        $planRoots += [ordered]@{role=$spec[0];path=$spec[1];peak_new_bytes=[long]$spec[2];reserve_bytes=1MB;mount_id=$mount.mount_id;device=$mount.device;mount_point=$mount.mount_point;filesystem_type=$mount.filesystem_type}
      }
      $plan=[ordered]@{schema=1;execution_account=[Environment]::UserName;roots=$planRoots}
      $planPath=Join-Path $scratch 'storage.json'
      function Read-StorageControlPlan {
        $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath
        Read-MIRLinuxWriteStorage -Path $planPath -Sha256 (Get-FileHash -LiteralPath $planPath).Hash -ControlRoot $controlRoot -LibraryRoot $LinuxLibraryRoot -MaxNewOutputBytes 4MB
      }
      $storage=Read-StorageControlPlan
      $observed=Get-MIRLinuxWriteStorageObservation -Storage $storage
      Assert-Storage ($observed.roots.Count -eq 3 -and @($observed.roots | Where-Object used_new_bytes -NE 0).Count -eq 0) 'actual-linux-mounted-roots'
      [IO.File]::WriteAllBytes((Join-Path $external 'observed.bin'),[byte[]]::new(113))
      $observed=Get-MIRLinuxWriteStorageObservation -Storage $storage
      Assert-Storage (@($observed.roots | Where-Object role -CEQ 'data')[0].used_new_bytes -eq 113) 'actual-linux-data-growth'
      Remove-Item -LiteralPath (Join-Path $external 'observed.bin')
      $plan.roots[1].mount_id++
      Refuses-Storage {Read-StorageControlPlan} '[mir-linux-storage-mount-changed]'
      $plan.roots[1].mount_id--
      $plan.execution_account='not-the-execution-owner'
      Refuses-Storage {Read-StorageControlPlan} '[mir-linux-storage-execution-account]'
      $plan.execution_account=[Environment]::UserName
      # This opponent changes only data placement. Keep its mount pins true
      # to that path so a separate data filesystem does not reject the stale
      # mount/path pair before the intended checkout-containment predicate.
      $dataRow=$plan.roots[1]
      $plan.roots[1]=[ordered]@{}
      foreach($key in $dataRow.Keys){$plan.roots[1][$key]=$dataRow[$key]}
      $plan.roots[1].path=$controlRoot
      foreach($key in @('mount_id','device','mount_point','filesystem_type')){
        $plan.roots[1][$key]=$plan.roots[0][$key]
      }
      Refuses-Storage {Read-StorageControlPlan} '[mir-linux-storage-data-external]'
      $plan.roots[1]=$dataRow
      $link=Join-Path $scratch 'linked-data'
      New-Item -ItemType SymbolicLink -Path $link -Target $external | Out-Null
      Refuses-Storage {Resolve-MIRLinuxWritePath -Path $link} '[mir-linux-storage-reparse]'
      Remove-Item -LiteralPath $link
      # Run the real library launch path/config guards against this actual
      # external data mount. Only final archive activation observation is
      # substituted: this host control never leases the supplied library.
      . (Join-Path $RepoRoot 'tools/lib/compatibility/LibraryActivation.ps1')
      $activationGuard=${function:Assert-MIRLibraryActivation}
      $script:storageLaunchObservations=0
      function Assert-MIRLibraryActivation {param($Activation,$OwnedProcesses) $script:storageLaunchObservations++}
      $launchConfig=Join-Path $external 'config.ini'
      $launchWrite=Join-Path $external 'write-data'
      try{
        [IO.Directory]::CreateDirectory($launchWrite) | Out-Null
        $launchEngine=Join-Path $scratch 'launch-engine/bin/x64/factorio'
        $launchData=Join-Path $scratch 'launch-engine/data'
        [IO.Directory]::CreateDirectory($launchData) | Out-Null
        [IO.File]::WriteAllText($launchConfig,"[path]`nread-data=$launchData`nwrite-data=$launchWrite`n[other]`nenable-new-mods=false`n")
        $launchActivation=[pscustomobject]@{library=$LinuxLibraryRoot;engine_data=$launchData}
        $launchArguments=@('--config',$launchConfig,'--mod-directory',$LinuxLibraryRoot)
        $launchPolicy=[pscustomobject]@{linux_write_storage=$storage}
        Refuses-Storage {Assert-MIRLibraryLaunch -Activation $launchActivation -FactorioBin $launchEngine -Arguments $launchArguments} '[mir441-resource-output-root]'
        Assert-MIRLibraryLaunch -Activation $launchActivation -FactorioBin $launchEngine -Arguments $launchArguments -WriteStoragePolicy $launchPolicy
        Assert-Storage ($script:storageLaunchObservations -eq 1) 'external-config-launch-observation'
        # Exercise the actual generic fixture stage's handoff too. Stop at
        # the process boundary after its real path/library launch validation.
        $tokens=$null;$parseErrors=$null
        $runnerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tools/Invoke-NativeFixture.ps1'),[ref]$tokens,[ref]$parseErrors)
        $stage=@($runnerAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-FixtureStage'},$true))
        Assert-Storage ($parseErrors.Count -eq 0 -and $stage.Count -eq 1) 'actual-fixture-stage-source'
        Invoke-Expression $stage[0].Extent.Text
        $processActor=${function:Invoke-MIRNativeProbeFactorioProcess}
        function Invoke-MIRNativeProbeFactorioProcess {throw '[storage-control-before-native-process]'}
        try{
          $config=$launchConfig;$writeData=$launchWrite;$activation=$launchActivation;$engine=$launchEngine
          $historicalProcess=$true;$historical=$true;$historicalFixture=@{factorio_version='0.13'}
          $activeModsObserverName='';$resources=[pscustomobject]@{policy=$launchPolicy};$TimeoutSeconds=30;$AdmissionWaitSeconds=0
          Refuses-Storage {Invoke-FixtureStage -Name 'launch-composition-control' -StageArguments @('--create','unused.zip')} '[storage-control-before-native-process]'
        }finally{Set-Item Function:Invoke-MIRNativeProbeFactorioProcess $processActor}
        Assert-Storage ($script:storageLaunchObservations -eq 2) 'generic-fixture-admitted-launch-handoff'
        $dataPin=@($storage.roots | Where-Object role -CEQ 'data')[0]
        $dataPin.mount_id++
        try{Refuses-Storage {Assert-MIRLibraryLaunch -Activation $launchActivation -FactorioBin $launchEngine -Arguments $launchArguments -WriteStoragePolicy $launchPolicy} '[mir-linux-storage-mount-changed]'}finally{$dataPin.mount_id--}
        [IO.File]::WriteAllText($launchConfig,"[path]`nread-data=$launchData`nwrite-data=$controlRoot`n[other]`nenable-new-mods=false`n")
        Refuses-Storage {Assert-MIRLibraryLaunch -Activation $launchActivation -FactorioBin $launchEngine -Arguments $launchArguments -WriteStoragePolicy $launchPolicy} '[mir-linux-storage-output-path]'
        Assert-Storage ($script:storageLaunchObservations -eq 2) 'bad-launch-paths-stop-before-activation'
      }finally{
        Set-Item Function:Assert-MIRLibraryActivation $activationGuard
        if(Test-Path -LiteralPath $launchConfig){Remove-Item -LiteralPath $launchConfig}
        if(Test-Path -LiteralPath $launchWrite){[IO.Directory]::Delete($launchWrite)}
      }
      if($GovernedSplitChild){
        # Exercise the existing actor, not its later mock: real POSIX session,
        # control working directory/TEMP, external data captures and cleanup.
        $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath
        $context=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $controlRoot -ExpectedPeakMemoryMiB 128 -MaxNewOutputMiB 4 -UseExactOutputRoot -LinuxStoragePlanPath $planPath -LinuxStoragePlanSha256 (Get-FileHash -LiteralPath $planPath).Hash -LibraryRoot $LinuxLibraryRoot
        $payload=Join-Path $context.root 'split-child.bin'
        $actor=@'
import json, os, sys
with open(sys.argv[1], "xb") as output:
    output.write(b"Z" * 65536)
print(json.dumps({"cwd": os.getcwd(), "temp": os.environ["TMPDIR"], "pid": os.getpid(), "session": os.getsid(0)}))
'@
        $run=Invoke-MIRNativeProbeProcess -Context $context -FilePath (Get-Command python3 -ErrorAction Stop).Source -Arguments @('-I','-B','-c',$actor,$payload) -TimeoutSeconds 30
        $witness=Get-Content -LiteralPath $run.stdout -Raw | ConvertFrom-Json
        Assert-Storage ($run.result.passed -and $run.result.exit_code -eq 0 -and $witness.cwd -ceq $controlRoot) 'governed-child-control-cwd'
        Assert-Storage ((Test-MIR441PathContained -Root $controlRoot -Path $witness.temp) -and -not (Test-Path -LiteralPath $witness.temp)) 'governed-child-owned-temp-cleanup'
        Assert-Storage ($witness.pid -eq $witness.session) 'governed-child-owned-session'
        foreach($capture in @($run.stdout,$run.stderr,$run.ledger)){
          Assert-Storage ((Test-MIR441PathContained -Root $external -Path $capture) -and (Test-Path -LiteralPath $capture -PathType Leaf)) 'governed-child-data-capture-file'
        }
        $monitor=@(Get-Content -LiteralPath $run.ledger | Where-Object {$_} | ForEach-Object {$_ | ConvertFrom-Json})
        Assert-Storage ($monitor.Count -ge 2 -and @($monitor | Where-Object {$null -ne $_.PSObject.Properties['phase'] -and $_.phase -ceq 'completed'}).Count -eq 1 -and $monitor[-1].phase -ceq 'completed' -and $monitor[-1].exit_code -eq 0) 'governed-child-monitor-completion'
        Assert-Storage (@($monitor | Where-Object {$null -ne $_.PSObject.Properties['process'] -and $_.process.phase -ceq 'running'}).Count -ge 1) 'governed-child-monitor-live-sample'
        Assert-Storage (@(Get-ChildItem -LiteralPath $controlRoot -Force).Count -eq 0) 'governed-child-control-residue'
        $payloadBytes=[IO.File]::ReadAllBytes($payload)
        Assert-Storage ($payloadBytes.Length -eq 65536 -and @($payloadBytes|Where-Object {$_ -ne 90}).Count -eq 0) 'governed-child-external-file'
        Write-MIRNativeProbeResult -Context $context -Record ([ordered]@{kind='MIRLinuxGovernedSplitChildControlV1';passed=$true;factorio_started=$false;child=$witness;data_root=$context.root;payload_sha256=(Get-FileHash -LiteralPath $payload).Hash})
        Assert-Storage (Test-Path -LiteralPath (Join-Path $external 'result.json') -PathType Leaf) 'governed-child-result-custody'
      }
    }finally{
      # Recheck the actual mount before removing the single fresh child; never
      # delete the supplied parent, archive library or an unmounted fallback.
      if($null -ne (Get-Variable storage -ErrorAction SilentlyContinue)){$null=Get-MIRLinuxWriteStorageObservation -Storage $storage}
      Remove-MIR441ContainedTree -AdmittedRoot $parent -Path $external
    }
  }
  $pin=[pscustomobject]@{role='data';path=$dataRoot;device='8:2';mount_id=42L;mount_point=$scratch;filesystem_type='exfat'}
  $policy=[pscustomobject]@{linux_write_storage=[pscustomobject]@{roots=@($pin)}}
  $script:storageTestMount=[pscustomobject]@{device='8:2';mount_id=42L;mount_point=$scratch;filesystem_type='exfat'}
  function Invoke-MIR441LinuxResourceObservation {param($Operation,$Path) $script:storageTestMount}
  $log=Join-Path $dataRoot 'process.stdout.txt'
  Assert-Storage ((Resolve-MIR441ProcessOutputPath -Policy $policy -Path $log) -ceq $log) 'data-output-composition'
  Refuses-Storage {Resolve-MIR441ProcessOutputPath -Policy $policy -Path (Join-Path $controlRoot 'escape.log')} '[mir-linux-storage-output-path]'
  $script:storageTestMount.mount_id=99L
  Refuses-Storage {Resolve-MIR441ProcessOutputPath -Policy $policy -Path $log} '[mir-linux-storage-mount-changed]'
  $script:storageTestMount.mount_id=42L;$script:storageTestMount.device='8:1'
  Refuses-Storage {Resolve-MIR441ProcessOutputPath -Policy $policy -Path $log} '[mir-linux-storage-mount-changed]'
  $script:storageTestMount.device='8:2';$script:storageTestMount.filesystem_type='ext4'
  Refuses-Storage {Resolve-MIR441ProcessOutputPath -Policy $policy -Path $log} '[mir-linux-storage-mount-changed]'

  # Eight named library controls only; archives are inputs, never output copies.
  [IO.File]::WriteAllBytes((Join-Path $libraryRoot 'dependency.zip'),[byte[]]::new(4096))
  [IO.File]::WriteAllBytes((Join-Path $libraryRoot 'mod-list.json'),[byte[]]::new(11))
  [IO.File]::WriteAllBytes((Join-Path $libraryRoot 'mod-settings.json.mir-new'),[byte[]]::new(7))
  [IO.File]::WriteAllBytes((Join-Path $libraryRoot '.mir-active-profile.json.mir-new'),[byte[]]::new(19))
  Assert-Storage ((Get-MIRLinuxLibraryControlBytes -Path $libraryRoot) -eq 37) 'library-control-only-accounting'

  $script:storageTestObservation=[pscustomobject]@{roots=@(
    [pscustomobject]@{role='control';used_new_bytes=10L;peak_new_bytes=100L},
    [pscustomobject]@{role='data';used_new_bytes=20L;peak_new_bytes=200000L},
    [pscustomobject]@{role='library';used_new_bytes=30L;peak_new_bytes=100L})}
  function Get-MIRLinuxWriteStorageObservation {param($Storage) $script:storageTestObservation}
  $context=[pscustomobject]@{root=$dataRoot;control_root=$controlRoot;policy=$policy;max_new_output_bytes=200200L;result_reserve_bytes=64KB;process_index=0;runs=[Collections.Generic.List[object]]::new()}
  Assert-Storage ((Get-MIRNativeProbeRemainingOutputBytes -Context $context -IncludeResultReserve) -eq 199980) 'data-budget-bounds-remaining'
  function Invoke-MIR441MonitoredProcess {
    param($FilePath,$Arguments,$WorkRoot,$Policy,$EstimatedPeakBytes,$ExpectedPeakMemoryBytes,$LedgerPath,$StdoutPath,$StderrPath,$TimeoutSeconds,$CompletionPredicate)
    $script:storageTestInvocation=$PSBoundParameters
    [pscustomobject]@{passed=$true}
  }
  $context | Add-Member -NotePropertyName peak_memory_bytes -NotePropertyValue 1GB
  $null=Invoke-MIRNativeProbeProcess -Context $context -FilePath 'mock-engine' -Arguments @('--mock')
  Assert-Storage ($script:storageTestInvocation.WorkRoot -ceq $controlRoot -and $script:storageTestInvocation.StdoutPath -ceq (Join-Path $dataRoot 'process-1.stdout.txt') -and $script:storageTestInvocation.LedgerPath -ceq (Join-Path $dataRoot 'process-1.resources.jsonl')) 'actor-control-data-split'
  Refuses-Storage {Add-MIRNativeProbeImmutableLease -Context $context -Lease ([pscustomobject]@{})} '[mir-linux-storage-no-external-hardlinks]'
}finally{
  # Only this exact fresh, contained test tree is disposable.
  Remove-MIR441ContainedTree -AdmittedRoot (Join-Path $RepoRoot 'build/tmp') -Path $scratch
}
Write-Output "Linux write-storage controls passed: $checks; no native execution."
