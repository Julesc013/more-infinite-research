# A Linux-only, disposable control for the normal dispatcher state machine.
# It uses a disposable user-systemd unit for the occupied-slot and launch
# controls. It owns only that test unit and its scratch directory.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$DispatcherPath,
  [Parameter(Mandatory)][string]$Root,
  [string]$ExitRecorderPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsLinux) { throw '[mir-gunmetal-dispatcher-manager-control-linux-required]' }
$dispatcherFull = [IO.Path]::GetFullPath($DispatcherPath)
$rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('/')
if (-not (Test-Path -LiteralPath $dispatcherFull -PathType Leaf)) { throw '[mir-gunmetal-dispatcher-manager-control-dispatcher-missing]' }
if (-not $ExitRecorderPath) { $ExitRecorderPath = Join-Path (Split-Path -Parent $dispatcherFull) 'Record-MIRGunmetalNativeExit.sh' }
$exitRecorder = (Resolve-Path -LiteralPath $ExitRecorderPath).Path
if ($rootFull -cnotmatch '^/home/shared/Projects/Factorio/MIR/\.task-builds/mir-dispatcher-manager-control-[a-z0-9-]+$') { throw '[mir-gunmetal-dispatcher-manager-control-root]' }
if (Test-Path -LiteralPath $rootFull) { throw '[mir-gunmetal-dispatcher-manager-control-root-exists]' }

. $dispatcherFull
$script:checks = 0
$script:unit = 'mir-dispatcher-control-' + [guid]::NewGuid().ToString('N').Substring(0,12) + '.service'

function Assert-ManagerControl {
  param([bool]$Condition,[string]$Name)
  if (-not $Condition) { throw "[mir-gunmetal-dispatcher-manager-control-$Name]" }
  $script:checks++
}

# Process-local test injection only. The installed dispatcher still expects the
# sole production owner unit, `mir-native.service`.
function Get-MIRGunmetalDispatcherExpectedNativeUnit { return $script:unit }

function Write-ManagerControlText {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function New-ManagerControlPolicy {
  param([Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$PacketText,[int]$ExitCode=0)
  $checkout = Join-Path $rootFull 'checkout'
  $resultRoot = Join-Path $rootFull 'results'
  $job = Join-Path $checkout ('jobs/'+$RequestId)
  $resultDirectory = Join-Path $resultRoot $RequestId
  [IO.Directory]::CreateDirectory($job) | Out-Null
  [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
  $packet = Join-Path $job 'packet.json'
  $controller = Join-Path $job 'Controller.sh'
  $launcher = Join-Path $job 'Launch-Transient.sh'
  $result = Join-Path $resultDirectory 'result.json'
  $packetTextJson = ([ordered]@{ kind = 'MIRGunmetalNativeDispatcherManagerControlPacketV1'; request_id = $RequestId; payload = $PacketText } | ConvertTo-Json -Compress) + "`n"
  Write-ManagerControlText -Path $packet -Text $packetTextJson
  $packetHash = (Get-FileHash -LiteralPath $packet -Algorithm SHA256).Hash.ToUpperInvariant()
  $controllerText = @"
#!/usr/bin/env bash
set -euo pipefail
sleep 1
printf '%s\n' '{"kind":"MIRGunmetalNativeDispatcherManagerControlResultV1","status":"passed","packet_sha256":"$packetHash"}' > '$result'
sleep 2
exit $ExitCode
"@
  $launcherText = @"
#!/usr/bin/env bash
set -euo pipefail
/usr/bin/systemd-run --user --no-block --unit='$($script:unit)' --collect --property=Type=exec --property=StandardOutput=journal '--property=ExecStopPost=/usr/bin/bash $exitRecorder $packetHash' /usr/bin/bash '$controller'
"@
  Write-ManagerControlText -Path $controller -Text $controllerText
  Write-ManagerControlText -Path $launcher -Text $launcherText
  & /usr/bin/chmod 700 $controller $launcher
  if ($LASTEXITCODE -ne 0) { throw '[mir-gunmetal-dispatcher-manager-control-chmod]' }
  $policy = [ordered]@{
    schema = 1
    kind = 'MIRGunmetalNativeDispatcherPolicyV1'
    execution_account = [Environment]::UserName
    spool_root = (Join-Path $rootFull 'spool')
    allowed_checkout_root = $checkout
    allowed_result_root = $resultRoot
    native_unit = $script:unit
    approval = [ordered]@{
      request_id = $RequestId
      owner = [Environment]::UserName
      reviewed_by = 'dispatcher-manager-control'
      review_reference = 'local disposable user-systemd control'
      execution_class = 'functional-not-timing'
      launcher_relative_path = ('jobs/'+$RequestId+'/Launch-Transient.sh')
      launcher_sha256 = (Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash.ToUpperInvariant()
      packet_relative_path = ('jobs/'+$RequestId+'/packet.json')
      packet_sha256 = $packetHash
      result_path = $result
      result_kind = 'MIRGunmetalNativeDispatcherManagerControlResultV1'
      result_status = 'passed'
    }
  }
  $policyPath = Join-Path $rootFull ($RequestId+'-policy.json')
  Write-ManagerControlText -Path $policyPath -Text (($policy | ConvertTo-Json -Depth 12) + "`n")
  return Get-MIRGunmetalDispatcherPolicy -Path $policyPath
}

function Remove-ManagerControlUnit {
  & /usr/bin/systemctl --user stop $script:unit 2>$null | Out-Null
  & /usr/bin/systemctl --user reset-failed $script:unit 2>$null | Out-Null
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    if ((Get-MIRGunmetalDispatcherUnit -Unit $script:unit).absence_confirmed) { return }
    Start-Sleep -Milliseconds 250
  }
  throw '[mir-gunmetal-dispatcher-manager-control-unit-cleanup]'
}

function Wait-ManagerControlTerminal {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$RequestId)
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 250
    if (-not (Get-MIRGunmetalDispatcherUnit -Unit $script:unit).absence_confirmed) { continue }
    $null = Invoke-MIRGunmetalDispatcherConsume -Policy $Policy
    $terminal = Join-Path $Policy.spool ('terminal/'+$RequestId+'.json')
    if (Test-Path -LiteralPath $terminal) { return (Read-MIRGunmetalDispatcherJson -Path $terminal) }
  }
  throw '[mir-gunmetal-dispatcher-manager-control-terminal-timeout]'
}

$cleanup = 'not-started'
try {
  $first = New-ManagerControlPolicy -RequestId 'manager-control-first' -PacketText 'first'
  $second = New-ManagerControlPolicy -RequestId 'manager-control-second' -PacketText 'second'
  $submitted = Submit-MIRGunmetalDispatcherApproved -Policy $first
  Assert-ManagerControl ($submitted.status -ceq 'queued') 'first-queued'
  & /usr/bin/systemd-run --user --unit=$script:unit --collect --property=Type=exec -- /usr/bin/sleep 30 2>&1 | Out-Null
  Assert-ManagerControl ($LASTEXITCODE -eq 0) 'occupied-unit-started'
  $occupied = Get-MIRGunmetalDispatcherUnit -Unit $script:unit
  Assert-ManagerControl ($occupied.found -and $occupied.active_state -ceq 'active' -and $occupied.main_pid -match '^[1-9][0-9]*$') 'occupied-real-manager-ack'
  $pendingPath = Join-Path $first.spool 'state/pending.json'
  $pendingHash = (Get-FileHash -LiteralPath $pendingPath).Hash
  $wait = Invoke-MIRGunmetalDispatcherConsume -Policy $first
  Assert-ManagerControl ($wait.status -ceq 'waiting-for-native-unit' -and $wait.unit.invocation_id -ceq $occupied.invocation_id -and
    (Get-FileHash -LiteralPath $pendingPath).Hash -ceq $pendingHash -and
    -not (Test-Path -LiteralPath (Join-Path $first.spool 'state/running.json'))) 'occupied-unit-preserves-pending'
  Remove-ManagerControlUnit

  $started = Invoke-MIRGunmetalDispatcherConsume -Policy $first
  $running = Get-MIRGunmetalDispatcherStateRecord -Policy $first -Name running
  if ($null -eq $running) {
    $terminalPath = Join-Path $first.spool ('terminal/'+$first.approval.request_id+'.json')
    $terminalDetail = if (Test-Path -LiteralPath $terminalPath) { (Read-MIRGunmetalDispatcherJson -Path $terminalPath | ConvertTo-Json -Compress) } else { 'no-running-or-terminal-record' }
    throw "[mir-gunmetal-dispatcher-manager-control-first-running-missing:$terminalDetail]"
  }
  Assert-ManagerControl ($started.status -ceq 'submitted' -and $running.launch.start_ack.pid -gt 0 -and $running.launch.start_ack.invocation_id -match '^[a-f0-9]{32}$') 'first-real-manager-ack'
  Assert-ManagerControl ($running.launch.start_ack.invocation_id -cne $occupied.invocation_id) 'first-is-distinct-from-occupied-unit'

  $next = Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $first -SuccessorPolicyPath $second.path
  Assert-ManagerControl ($next.status -ceq 'queued' -and (Test-Path -LiteralPath (Join-Path $first.spool 'state/pending.signal'))) 'second-literal-packet-queued'
  $wake = Invoke-MIRGunmetalDispatcherConsume -Policy $first
  Assert-ManagerControl ($wake.status -ceq 'reconciled' -and -not (Test-Path -LiteralPath (Join-Path $first.spool 'state/pending.signal'))) 'held-pending-edge-consumed-without-start-loop'

  $firstTerminal = Wait-ManagerControlTerminal -Policy $first -RequestId $first.approval.request_id
  Assert-ManagerControl ($firstTerminal.status -ceq 'succeeded' -and $firstTerminal.result.result.packet_sha256 -ceq $first.approval.packet_sha256 -and $firstTerminal.result.journal.source -ceq 'systemd-exit-hook') 'first-collected-terminal-packet-bound'

  $secondStarted = Invoke-MIRGunmetalDispatcherConsume -Policy $first
  $secondRunning = Get-MIRGunmetalDispatcherStateRecord -Policy $first -Name running
  Assert-ManagerControl ($secondStarted.status -ceq 'submitted' -and $secondRunning.request_id -ceq $second.approval.request_id -and $secondRunning.packet_sha256 -ceq $second.approval.packet_sha256) 'second-distinct-packet-started'
  $secondTerminal = Wait-ManagerControlTerminal -Policy $first -RequestId $second.approval.request_id
  Assert-ManagerControl ($secondTerminal.status -ceq 'succeeded' -and $secondTerminal.result.result.packet_sha256 -ceq $second.approval.packet_sha256 -and $secondTerminal.result.journal.source -ceq 'systemd-exit-hook') 'second-collected-terminal-packet-bound'
  Assert-ManagerControl ($firstTerminal.result.journal.invocation_id -cne $secondTerminal.result.journal.invocation_id) 'distinct-collected-invocations'

  $third = New-ManagerControlPolicy -RequestId 'manager-control-failed' -PacketText 'failed' -ExitCode 7
  $null = Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $first -SuccessorPolicyPath $third.path
  $null = Invoke-MIRGunmetalDispatcherConsume -Policy $first
  $failed = Wait-ManagerControlTerminal -Policy $first -RequestId $third.approval.request_id
  Assert-ManagerControl ($failed.status -ceq 'failed' -and $failed.result.result.valid -and $failed.result.journal.exit_code -eq 7 -and $failed.result.journal.source -ceq 'systemd-exit-hook') 'nonzero-exit-preserved-with-valid-controller-result'
  $cleanup = 'unit-cleaned'

  [pscustomobject]@{
    kind = 'MIRGunmetalNativeDispatcherManagerControlV1'
    status = 'passed'
    checks = $script:checks
    unit = $script:unit
    occupied_invocation_id = $occupied.invocation_id
    first_packet_sha256 = $first.approval.packet_sha256
    second_packet_sha256 = $second.approval.packet_sha256
    exits = @($firstTerminal.result.journal, $secondTerminal.result.journal, $failed.result.journal)
    native_execution = $false
    gameplay_acceptance = $false
    operational_scope = 'An occupied-unit observation and three reviewed launches using one disposable user-systemd unit.'
  }
} finally {
  if ($cleanup -ne 'unit-cleaned') { try { Remove-ManagerControlUnit } catch { } }
  if (Test-Path -LiteralPath $rootFull) { Remove-Item -LiteralPath $rootFull -Recurse -Force }
}
