# The direct-library responsive-menu actor is intended only as the child of
# the existing resource governor.  The canonical caller owns activation,
# validates the hash-bound launch specification and validates loaded mods
# afterwards. This actor grants none of those authorities.
param(
  [Parameter(Mandatory)][string]$LaunchSpecPath,
  [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$LaunchSpecSha256,
  [Parameter(Mandatory)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'MenuObservation.ps1')
. (Join-Path $PSScriptRoot 'OwnedMenuWindow.ps1')
if((Get-MIRMenuFileSha256 $LaunchSpecPath)-cne$LaunchSpecSha256.ToUpperInvariant()){throw '[mir-menu-launch-spec-hash]'}
$spec=Get-Content -LiteralPath $LaunchSpecPath -Raw|ConvertFrom-Json
if($spec.kind-cne'MIRDirectLibraryOwnedMenuLaunchV1'-or$spec.timeout_seconds-lt1-or$spec.timeout_seconds-gt300){throw '[mir-menu-launch-spec-contract]'}
$engine=(Resolve-Path -LiteralPath ([string]$spec.factorio_path)).Path
if([IO.Path]::GetFileName($engine)-cne'factorio.exe'-or(Get-MIRMenuFileSha256 $engine)-cne[string]$spec.factorio_sha256){throw '[mir-menu-launch-engine-identity]'}
$allowed=@('--config','--mod-directory','--no-log-rotation')
$arguments=@($spec.arguments)
if($arguments.Count-ne5-or$arguments[0]-cne'--config'-or$arguments[2]-cne'--mod-directory'-or$arguments[4]-cne'--no-log-rotation'){throw '[mir-menu-launch-arguments]'}
if(@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count){throw '[mir-menu-existing-factorio-process]'}
if(-not[IO.Path]::IsPathRooted([string]$spec.engine_current_log)){throw '[mir-menu-launch-log-path]'}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
if(Test-Path -LiteralPath (Join-Path $OutputRoot 'actor-result.json')){throw '[mir-menu-preserve-existing-result]'}
Initialize-MIROwnedMenuWindow
$ocr=Initialize-MIRMenuOcr
# Prepare OCR/native interop before the measured engine launch. Only fixed
# Steam IDs are inherited by the owned Factorio child, matching the governor.
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=$engine;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
$start.WorkingDirectory=[IO.Path]::GetFullPath($OutputRoot)
$start.EnvironmentVariables['SteamAppId']='427520';$start.EnvironmentVariables['SteamGameId']='427520'
$quoted=@($arguments|ForEach-Object {
  $value=[string]$_
  if($value.Contains('"')-or$value.Contains("`r")-or$value.Contains("`n")-or$value.EndsWith('\')){throw '[mir-menu-launch-argument-encoding]'}
  '"'+$value+'"'
})
$start.Arguments=$quoted-join' '
$process=New-Object Diagnostics.Process;$process.StartInfo=$start
$beforeQpc=[Diagnostics.Stopwatch]::GetTimestamp()
if(-not$process.Start()){throw '[mir-menu-launch-process]'}
$afterQpc=[Diagnostics.Stopwatch]::GetTimestamp()
$startUtc=$process.StartTime.ToUniversalTime()
$result=$null;$failure='';$cleanup='not-started'
try{
  $result=Wait-MIROwnedMenuResponse $process $startUtc $ocr $OutputRoot $beforeQpc -TimeoutSeconds ([int]$spec.timeout_seconds) -RequiredInitialisedLog ([string]$spec.engine_current_log)
}catch{$failure=$_.Exception.Message;throw}
finally{
  $endpointFinishedQpc=[Diagnostics.Stopwatch]::GetTimestamp()
  try{
    if(-not$process.HasExited){
      $null=$process.CloseMainWindow()
      if(-not$process.WaitForExit(2500)){$process.Kill();$null=$process.WaitForExit(2500);$cleanup='owned-process-forced-stop'}else{$cleanup='owned-process-closed'}
    }else{$cleanup='owned-process-already-exited'}
  }finally{
    $cleanupFinishedQpc=[Diagnostics.Stopwatch]::GetTimestamp()
    $record=[ordered]@{kind='MIRDirectLibraryOwnedMenuObservationV1';status=$(if($failure){'failed'}else{'observed-response-awaiting-parent-selection-validation'});launch_spec_sha256=$LaunchSpecSha256;factorio_sha256=[string]$spec.factorio_sha256;process_id=$process.Id;process_start_utc=$startUtc.ToString('o');launch_before_qpc=$beforeQpc;launch_after_qpc=$afterQpc;clock_frequency=[Diagnostics.Stopwatch]::Frequency;process_start_bracket_seconds=($afterQpc-$beforeQpc)/[double][Diagnostics.Stopwatch]::Frequency;observation=$result;failure=$failure;cleanup=$cleanup;observation_finished_qpc=$endpointFinishedQpc;cleanup_finished_qpc=$cleanupFinishedQpc;shutdown_cleanup_seconds=($cleanupFinishedQpc-$endpointFinishedQpc)/[double][Diagnostics.Stopwatch]::Frequency;full_engine_cycle_seconds=($cleanupFinishedQpc-$beforeQpc)/[double][Diagnostics.Stopwatch]::Frequency;claims_library_selection_validation=$false;claims_final_acceptance=$false}
    $record|ConvertTo-Json -Depth 18|Set-Content -LiteralPath (Join-Path $OutputRoot 'actor-result.json') -Encoding UTF8
    $process.Dispose()
  }
}
$record|ConvertTo-Json -Depth 18
