Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NativeProbeCommon.ps1')
. (Join-Path $PSScriptRoot 'ResourceGovernor.ps1')
. (Join-Path $PSScriptRoot 'ImmutableInputStaging.ps1')

# These adapters retain the existing governor and lease authorities. They own
# one probe's total new-output budget, not a second scheduler or package writer.
function New-MIRNativeProbeResourceContext {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
    [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
    [switch]$UseExactOutputRoot
  )
  $path=if([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $RepoRoot $OutputRoot }
  $output=Resolve-MIR441RecoveryScratchPath -Path ([IO.Path]::GetFullPath($path))
  if($UseExactOutputRoot -and (Test-Path -LiteralPath $output) -and
      (-not (Test-Path -LiteralPath $output -PathType Container) -or @(Get-ChildItem -LiteralPath $output -Force).Count -ne 0)) {
    throw '[mir-native-probe-exact-output-not-empty]'
  }
  if($ExpectedPeakMemoryMiB -le 0) { throw '[mir441-resource-peak-budget-required] Declare the native probe peak memory budget.' }
  $policy=[pscustomobject]@{minimum_free_ram_gib=4}
  $peak=[int64]$ExpectedPeakMemoryMiB*1MB
  $writes=[int64]$MaxNewOutputMiB*1MB
  # Candidate authentication prepares temporary source/archive inventories.
  # Release completed host allocations before the initial admission, as the
  # direct-library actor already does before each child. Keep all live inputs,
  # declared child peaks and machine reserves in the admission calculation.
  [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
  $null=Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $output -EstimatedPeakBytes $writes -ExpectedPeakMemoryBytes $peak
  [pscustomobject]@{
    root=$(if($UseExactOutputRoot){$output}else{Join-Path $output ([guid]::NewGuid().ToString('N'))})
    policy=$policy;peak_memory_bytes=$peak;max_new_output_bytes=$writes
    shared_alias_bytes=0L;process_index=0;result_reserve_bytes=64KB
    alias_paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    aliases=[Collections.Generic.List[object]]::new()
    runs=[Collections.Generic.List[object]]::new()
  }
}

function Add-MIRNativeProbeImmutableLease {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lease)
  if(-not $Lease.record.Contains('require_hard_links') -or -not $Lease.record.require_hard_links) {
    throw '[mir-native-probe-strict-lease-required]'
  }
  $receipt=Get-MIRImmutableInputLeaseReceipt -Lease $Lease
  foreach($leaseInput in $receipt.inputs) {
    $stage=Resolve-MIR441RecoveryScratchPath -Path ([string]$leaseInput.stage_path)
    if(-not (Test-MIR441PathContained -Root $Context.root -Path $stage) -or
      $Context.alias_paths.Contains($stage) -or $leaseInput.staging_mode -cne 'hardlink' -or
      (Get-MIRImmutableInputFileIdentity -Path $leaseInput.source_path) -cne (Get-MIRImmutableInputFileIdentity -Path $stage)) {
      throw '[mir-native-probe-shared-alias-identity]'
    }
    [void]$Context.alias_paths.Add($stage)
    $Context.aliases.Add([pscustomobject]@{stage_path=$stage;source_path=[string]$leaseInput.source_path;file_identity=Get-MIRImmutableInputFileIdentity -Path $stage;bytes=[int64](Get-Item -LiteralPath $stage).Length})
    # Only proved, leased aliases are excluded from logical tree totals.
    # A generated candidate's original file is still counted in the row.
    $Context.shared_alias_bytes += [int64](Get-Item -LiteralPath $stage).Length
  }
}

function Get-MIRNativeProbeRemainingOutputBytes {
  param([Parameter(Mandatory)]$Context,[switch]$IncludeResultReserve)
  foreach($alias in $Context.aliases) {
    if(-not (Test-Path -LiteralPath $alias.stage_path -PathType Leaf) -or
      -not (Test-Path -LiteralPath $alias.source_path -PathType Leaf) -or
      ((Get-Item -LiteralPath $alias.stage_path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
      (Get-MIRImmutableInputFileIdentity -Path $alias.stage_path) -cne $alias.file_identity -or
      (Get-MIRImmutableInputFileIdentity -Path $alias.source_path) -cne $alias.file_identity -or
      [int64](Get-Item -LiteralPath $alias.stage_path).Length -ne $alias.bytes) {
      throw '[mir-native-probe-shared-alias-identity]'
    }
  }
  $usage=Get-MIR441TreeUsage -Path $Context.root
  if(-not $usage.complete) { throw '[mir441-resource-output-scan-incomplete]' }
  $newBytes=[int64]$usage.bytes-[int64]$Context.shared_alias_bytes
  $activationProperty=$Context.PSObject.Properties['library_activation']
  if($null -ne $activationProperty -and $null -ne $activationProperty.Value -and -not $activationProperty.Value.closed){
    $activation=$activationProperty.Value
    $controlBytes=0L
    foreach($name in @('mod-list.json','mod-settings.dat','.mir-active-profile.json')){
      foreach($suffix in @('','.mir-new')){
        $path=Join-Path $activation.library ($name+$suffix)
        if(Test-Path -LiteralPath $path){
          Assert-MIRLibraryPath $path
          $controlBytes+=[int64](Get-Item -LiteralPath $path).Length
        }
      }
    }
    # Archives remain outside the run and are never charged as new copies.
    # Charge only additional control/journal bytes over the previous controls.
    $newBytes += [Math]::Max(0L,$controlBytes-[int64]$Context.library_control_baseline_bytes)
  }
  if($newBytes -lt 0) { throw '[mir-native-probe-shared-alias-missing]' }
  $remaining=[int64]$Context.max_new_output_bytes-$newBytes
  if(-not $IncludeResultReserve) { $remaining-=[int64]$Context.result_reserve_bytes }
  if($remaining -le 0) { throw '[mir441-resource-output-budget]' }
  return $remaining
}

function Add-MIRNativeProbeLibraryActivation {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Activation)
  if($Activation.closed -or -not $Activation.lock.CanRead -or
    (Test-MIR441PathContained -Root $Context.root -Path $Activation.library)) {throw '[mir-native-probe-library-activation]'}
  $previous=$Context.PSObject.Properties['library_activation']
  if($null -ne $previous -and $null -ne $previous.Value -and -not $previous.Value.closed){throw '[mir-native-probe-library-already-active]'}
  $baseline=0L
  foreach($name in @('mod-list.json','mod-settings.dat')){
    if($Activation.journal.controls[$name].exists){$baseline += [Convert]::FromBase64String($Activation.journal.controls[$name].bytes).Length}
  }
  $Context|Add-Member -NotePropertyName library_activation -NotePropertyValue $Activation -Force
  $Context|Add-Member -NotePropertyName library_control_baseline_bytes -NotePropertyValue $baseline -Force
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
}

function Invoke-MIRNativeProbeProcess {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=120,
    [ValidateSet(0,250)][int]$SampleMilliseconds=0,
    [scriptblock]$OwnedProcessSampleCallback=$null,
    [scriptblock]$OwnedProcessExitCallback=$null,
    [switch]$FactorioSteamIdentity,
    $PreStartAdmissionWait=$null,
    [scriptblock]$CompletionPredicate
  )
  $remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  $Context.process_index++
  $prefix=Join-Path $Context.root ('process-'+$Context.process_index)
  try {
    $governorArguments=@{
      FilePath=$FilePath;Arguments=$Arguments;WorkRoot=$Context.root;Policy=$Context.policy
      EstimatedPeakBytes=$remaining;ExpectedPeakMemoryBytes=$Context.peak_memory_bytes
      LedgerPath=($prefix+'.resources.jsonl');StdoutPath=($prefix+'.stdout.txt');StderrPath=($prefix+'.stderr.txt')
      TimeoutSeconds=$TimeoutSeconds;CompletionPredicate=$CompletionPredicate
    }
    # Do not add an unknown named parameter to existing non-Factorio mock
    # actors. Only the direct Factorio actor opts into fixed child Steam IDs.
    if($FactorioSteamIdentity){$governorArguments.FactorioSteamIdentity=$true}
    if($null -ne $PreStartAdmissionWait){$governorArguments.PreStartAdmissionWait=$PreStartAdmissionWait}
    if($SampleMilliseconds -ne 0){$governorArguments.SampleMilliseconds=$SampleMilliseconds}
    if($null -ne $OwnedProcessSampleCallback){$governorArguments.OwnedProcessSampleCallback=$OwnedProcessSampleCallback}
    if($null -ne $OwnedProcessExitCallback){$governorArguments.OwnedProcessExitCallback=$OwnedProcessExitCallback}
    # Library validation builds temporary archive inventories. Release those
    # completed host allocations before admission measures the native child.
    # The active lease, inventories and process/machine reserves remain live.
    $activationProperty=$Context.PSObject.Properties['library_activation']
    if($null -ne $activationProperty -and $null -ne $activationProperty.Value -and -not $activationProperty.Value.closed){
      [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    }
    $result=Invoke-MIR441MonitoredProcess @governorArguments
    $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  } catch {
    $Context.runs.Add([pscustomobject]@{index=$Context.process_index;status='interrupted';ledger=($prefix+'.resources.jsonl');stdout=($prefix+'.stdout.txt');stderr=($prefix+'.stderr.txt');error=$_.Exception.Message})
    throw
  }
  $completed=[pscustomobject]@{index=$Context.process_index;status='passed';ledger=($prefix+'.resources.jsonl');stdout=($prefix+'.stdout.txt');stderr=($prefix+'.stderr.txt');result=$result}
  $waitProperty=$result.PSObject.Properties['admission_wait']
  if($null-ne$waitProperty){$completed|Add-Member -NotePropertyName admission_wait -NotePropertyValue $waitProperty.Value}
  $Context.runs.Add($completed)
  return $Context.runs[$Context.runs.Count-1]
}

function Write-MIRNativeProbeResult {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Record)
  $json=($Record | ConvertTo-Json -Depth 30)+"`n"
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
  $remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $Context -IncludeResultReserve
  if($bytes.Length -ge $remaining) { throw '[mir441-resource-output-budget]' }
  [IO.File]::WriteAllBytes((Join-Path $Context.root 'result.json'),$bytes)
}

function Invoke-MIRNativeProbeFactorioProcess {
  param(
    [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=120,
    [ValidateSet(0,250)][int]$SampleMilliseconds=0,
    [scriptblock]$OwnedProcessSampleCallback=$null,
    [scriptblock]$OwnedProcessExitCallback=$null,
    [ValidateRange(0,300)][int]$AdmissionWaitSeconds=0,
    [string]$AdmissionPhase='',
    [scriptblock]$CompletionPredicate
  )
  if($Arguments.Count -lt 1 -or $Arguments.Count -gt 128){throw '[mir-native-probe-argument-budget]'}
  # Retain the historical data-size guard even though the direct actor no
  # longer serializes its arguments through a PowerShell wrapper.
  $payload=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Arguments -Compress))
  if($payload.Length -gt 16KB){throw '[mir-native-probe-argument-budget]'}
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  # The same governed ProcessStartInfo already owns the process lifetime,
  # streamed stdout/stderr, process tree, timeout and cleanup. Start Factorio
  # directly so its duration is native executable start-to-exit, rather than
  # the historical PowerShell-wrapper tree duration. This clock-scope repair
  # removes developer harness work; it is not product-speedup evidence.
  $actorArguments=@{Context=$Context;FilePath=$FilePath;Arguments=$Arguments;TimeoutSeconds=$TimeoutSeconds;FactorioSteamIdentity=$true;CompletionPredicate=$CompletionPredicate}
  if($SampleMilliseconds -ne 0){$actorArguments.SampleMilliseconds=$SampleMilliseconds}
  if($null -ne $OwnedProcessSampleCallback){$actorArguments.OwnedProcessSampleCallback=$OwnedProcessSampleCallback}
  if($null -ne $OwnedProcessExitCallback){$actorArguments.OwnedProcessExitCallback=$OwnedProcessExitCallback}
  if($AdmissionWaitSeconds -gt 0){
    if([string]::IsNullOrWhiteSpace($AdmissionPhase)){throw '[mir-native-probe-admission-phase]'}
    $actorArguments.PreStartAdmissionWait=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase $AdmissionPhase
  }
  $run=Invoke-MIRNativeProbeProcess @actorArguments
  $run.result | Add-Member -NotePropertyName duration_measurement -NotePropertyValue ([ordered]@{
    scope='direct-native-executable-start-to-exit'
    historical_scope='governed-powershell-wrapper-tree-start-to-exit'
    comparability='scope-changed; compare only fresh direct-native measurements; no product-speedup claim'
  }) -Force
  if($actorArguments.ContainsKey('PreStartAdmissionWait')){
    $run | Add-Member -NotePropertyName admission_wait -NotePropertyValue $actorArguments.PreStartAdmissionWait -Force
    $run.result | Add-Member -NotePropertyName admission_wait -NotePropertyValue $actorArguments.PreStartAdmissionWait -Force
  }
  return $run
}
