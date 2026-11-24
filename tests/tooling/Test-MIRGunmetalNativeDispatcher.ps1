# No Factorio, package, direct library, engine, systemd manager, or native
# governor is started. This is a disposable-spool control for the dispatcher.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$dispatcher=Join-Path $RepoRoot 'tools/commands/workspace/Invoke-MIRGunmetalNativeDispatcher.ps1'
$installer=Join-Path $RepoRoot 'tools/commands/workspace/Install-MIRGunmetalNativeDispatcher.ps1'
. $dispatcher
. $installer
$readDispatcherJournal = ${function:Get-MIRGunmetalDispatcherJournalTerminal}

$script:checks=0
$script:launches=0
$script:fakeState='gone'
$script:fakeFactorioActive=$false
$script:nextLaunchState='active'
$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null}
$script:fakeInvocation='0123456789abcdef0123456789abcdef'

function Assert-Dispatcher {
  param([bool]$Condition,[string]$Name)
  if (-not $Condition) { throw "[gunmetal-dispatcher-control-$Name]" }
  $script:checks++
}

function Refuses-Dispatcher {
  param([scriptblock]$Action,[string]$Expected)
  $message = ''
  try {
    & $Action | Out-Null
  } catch {
    $message = $_.Exception.Message
  }
  Assert-Dispatcher $message.Contains($Expected) "$Expected observed=$message"
}

function Invoke-MIRGunmetalDispatcherSystemctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  switch ($script:fakeState) {
    'active' {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=active','SubState=running','MainPID=4242',('InvocationID='+$script:fakeInvocation),'Result=success','ExecMainCode=','ExecMainStatus=') }
    }
    'exited' {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=active','SubState=exited','MainPID=0',('InvocationID='+$script:fakeInvocation),'Result=success','ExecMainCode=exited','ExecMainStatus=0') }
    }
    'failed' {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=failed','SubState=failed','MainPID=0',('InvocationID='+$script:fakeInvocation),'Result=exit-code','ExecMainCode=exited','ExecMainStatus=1') }
    }
    'activating-without-pid' {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=activating','SubState=start','MainPID=0','InvocationID=','Result=success','ExecMainCode=','ExecMainStatus=') }
    }
    'query-partial' { return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=active','MainPID=4242') } }
    'query-error' { return [pscustomobject]@{ exit_code = 1; lines = @('Failed to connect to bus') } }
    default {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=not-found','ActiveState=inactive','SubState=dead','MainPID=0','InvocationID=','Result=','ExecMainCode=','ExecMainStatus=') }
    }
  }
}
function Test-MIRGunmetalDispatcherFactorioActive {
  return $script:fakeFactorioActive
}

function Invoke-MIRGunmetalDispatcherLauncher {
  param([Parameter(Mandatory)][string]$Path)
  $script:launches++
  $script:fakeState=$script:nextLaunchState
  return [pscustomobject]@{exit_code=0;lines=@('{"event":"systemd-launch-returned","exit_code":0}')}
}
function Get-MIRGunmetalDispatcherJournalTerminal {
  param([Parameter(Mandatory)][string]$InvocationId,[string]$Unit,[string]$PacketSha256)
  return $script:fakeJournal
}

function Invoke-MIRGunmetalDispatcherJournalctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $script:journalReads++
  if ($Arguments[0] -clike 'USER_INVOCATION_ID=*') { return $script:journalManagerReply }
  return $script:journalHookReply
}

function Test-DispatcherExitJournal {
  $packet = 'A' * 64
  $unit = 'mir-native.service'
  $invocation = $script:fakeInvocation
  $args = @{ Unit = $unit; InvocationId = $invocation; PacketSha256 = $packet }
  $entry = @{
    _SYSTEMD_USER_UNIT = $unit
    _SYSTEMD_INVOCATION_ID = $invocation
    _TRANSPORT = 'stdout'
    MESSAGE = "MIR_NATIVE_SYSTEMD_EXIT_V1 invocation=$invocation packet=$packet result=success code=exited status=0"
  }
  $hook = $entry | ConvertTo-Json -Compress
  $exit = ConvertFrom-MIRGunmetalDispatcherExitJournal @args -HookRecords @($hook)
  Assert-Dispatcher ($exit.observed -and $exit.exit_code -eq 0 -and $exit.source -ceq 'systemd-exit-hook') 'collected-hook-exit-zero'

  $wrongUnit = $hook.Replace($unit,'another.service')
  $wrongInvocation = $hook.Replace($invocation,('1' * 32))
  $wrongPacket = $hook.Replace($packet,('B' * 64))
  $exit = ConvertFrom-MIRGunmetalDispatcherExitJournal @args -HookRecords @($wrongUnit,$wrongInvocation,$wrongPacket,'null','[]')
  Assert-Dispatcher (-not $exit.observed -and -not $exit.conflict) 'foreign-exit-records-ignored'

  $terminal = @{USER_INVOCATION_ID=$invocation;MESSAGE='Main process exited, code=exited, status=7/NOTRUNNING'} | ConvertTo-Json -Compress
  $exit = ConvertFrom-MIRGunmetalDispatcherExitJournal @args -ManagerRecords @($terminal)
  Assert-Dispatcher ($exit.observed -and $exit.exit_code -eq 7 -and $exit.source -ceq 'manager-journal') 'legacy-manager-exit-preserved'
  $exit = ConvertFrom-MIRGunmetalDispatcherExitJournal @args -ManagerRecords @($terminal) -HookRecords @($hook)
  Assert-Dispatcher (-not $exit.observed -and $exit.conflict) 'conflicting-exit-evidence-refused'
  $exit = ConvertFrom-MIRGunmetalDispatcherExitJournal @args -HookRecords @($hook,$hook)
  Assert-Dispatcher (-not $exit.observed -and $exit.conflict) 'duplicate-hook-evidence-refused'

  $timeout = $hook.Replace('result=success code=exited status=0','result=timeout code=killed status=TERM')
  $exit = ConvertFrom-MIRGunmetalDispatcherExitJournal @args -HookRecords @($timeout)
  Assert-Dispatcher ($exit.observed -and $null -eq $exit.exit_code -and $exit.service_result -ceq 'timeout' -and $exit.exit_status -ceq 'TERM') 'collected-timeout-preserved'

  $script:journalReads = 0
  $script:journalManagerReply = [pscustomobject]@{exit_code=0;lines=@($terminal);diagnostics=$false}
  $script:journalHookReply = [pscustomobject]@{exit_code=1;lines=@();diagnostics=$false}
  $exit = & $readDispatcherJournal @args
  Assert-Dispatcher ($exit.observed -and $exit.exit_code -eq 7 -and $script:journalReads -eq 2) 'absent-optional-grep-preserves-manager-exit'

  $script:journalReads = 0
  $script:journalManagerReply.lines = @()
  $exit = & $readDispatcherJournal @args
  Assert-Dispatcher (-not $exit.observed -and -not $exit.PSObject.Properties['incomplete'] -and
    $script:journalReads -eq 8) 'two-empty-journal-queries-confirm-no-terminal'

  $script:journalReads = 0
  $script:journalManagerReply.lines = @($terminal)
  $script:journalHookReply.diagnostics = $true
  $exit = & $readDispatcherJournal @args
  Assert-Dispatcher ($exit.incomplete -and -not $exit.observed -and $script:journalReads -eq 8) 'hook-query-error-does-not-count-as-no-match'

  $script:journalReads = 0
  $script:journalManagerReply = [pscustomobject]@{exit_code=1;lines=@();diagnostics=$true}
  $script:journalHookReply = [pscustomobject]@{exit_code=0;lines=@($hook);diagnostics=$false}
  $exit = & $readDispatcherJournal @args
  Assert-Dispatcher ($exit.incomplete -and -not $exit.observed -and $script:journalReads -eq 8) 'manager-query-error-keeps-conflict-check-pending'
}

$script:installState='success'
$script:installCalls=[Collections.Generic.List[string]]::new()
function Get-MIRGunmetalDispatcherInstallLinger { return [pscustomobject]@{exit_code=0;lines=@('yes')} }
function Invoke-MIRGunmetalDispatcherInstallSystemctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $script:installCalls.Add(($Arguments -join ' '))
  if ($Arguments[0] -ceq 'show') {
    $unit = $Arguments[$Arguments.Count - 1]
    $unitPath = Join-Path $Plan.unit_directory $unit
    if (Test-Path -LiteralPath $unitPath -PathType Leaf) {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=inactive',('FragmentPath='+$unitPath),'DropInPaths=') }
    }
    return [pscustomobject]@{ exit_code = 4; lines = @('LoadState=not-found','ActiveState=inactive','FragmentPath=','DropInPaths=') }
  }
  if ($script:installState -ceq 'reload-fail' -and $Arguments[0] -ceq 'daemon-reload') {
    return [pscustomobject]@{ exit_code = 1; lines = @('reload failed') }
  }
  if ($script:installState -ceq 'enable-fail' -and $Arguments[0] -ceq 'enable') {
    return [pscustomobject]@{ exit_code = 1; lines = @('enable failed') }
  }
  return [pscustomobject]@{ exit_code = 0; lines = @() }
}

function New-DispatcherPolicy {
  param([Parameter(Mandatory)]$Control,[Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$PacketText,[string]$ResultStatus='passed')
  $case=Join-Path $Control.checkout ('build/p/'+$RequestId)
  $resultDirectory=Join-Path $Control.result_root $RequestId
  [IO.Directory]::CreateDirectory($case)|Out-Null
  [IO.Directory]::CreateDirectory($resultDirectory)|Out-Null
  $launcher=Join-Path $case 'Launch-Transient.sh'
  $packet=Join-Path $case 'packet.json'
  $result=Join-Path $resultDirectory 'result.json'
  [IO.File]::WriteAllText($launcher,"#!/bin/bash`nexit 0`n",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($packet,('{"packet":"'+$PacketText+'"}'+"`n"),[Text.UTF8Encoding]::new($false))
  $policy=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherPolicyV1';execution_account=[Environment]::UserName;spool_root=$Control.spool;allowed_checkout_root=$Control.checkout;allowed_result_root=$Control.result_root;native_unit='mir-native.service';approval=[ordered]@{request_id=$RequestId;owner=[Environment]::UserName;reviewed_by='independent-review';review_reference='https://example.invalid/review';execution_class='functional-not-timing';launcher_relative_path=('build/p/'+$RequestId+'/Launch-Transient.sh');launcher_sha256=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash;packet_relative_path=('build/p/'+$RequestId+'/packet.json');packet_sha256=(Get-FileHash -LiteralPath $packet -Algorithm SHA256).Hash;result_path=$result;result_kind='MIRDispatcherControlResultV1';result_status=$ResultStatus}}
  $path=Join-Path $Control.root ($RequestId+'-policy.json')
  $policy|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -NoNewline
  return Get-MIRGunmetalDispatcherPolicy -Path $path
}

function New-DispatcherControl {
  param([Parameter(Mandatory)][string]$Name)
  $root=Join-Path ([IO.Path]::GetTempPath()) ('mir-dispatcher-'+$Name+'-'+[guid]::NewGuid().ToString('N'))
  $control=[pscustomobject]@{root=$root;checkout=(Join-Path $root 'checkout');result_root=(Join-Path $root 'result-root');spool=(Join-Path $root 'spool')}
  foreach($directory in @($control.checkout,$control.result_root,$control.spool)){[IO.Directory]::CreateDirectory($directory)|Out-Null}
  $control|Add-Member -NotePropertyName base -NotePropertyValue (New-DispatcherPolicy -Control $control -RequestId ('native-control-'+$Name) -PacketText 'base')
  return $control
}
function Write-DispatcherResult { param([Parameter(Mandatory)]$Policy,[string]$Status=$Policy.approval.result_status)[IO.File]::WriteAllText($Policy.approval.result_path,('{"kind":"MIRDispatcherControlResultV1","status":"'+$Status+'","packet_sha256":"'+$Policy.approval.packet_sha256+'"}'+"`n"),[Text.UTF8Encoding]::new($false)) }
function Read-DispatcherTerminal { param([Parameter(Mandatory)]$Control,[Parameter(Mandatory)][string]$RequestId) return (Get-Content -LiteralPath (Join-Path $Control.spool ('terminal/'+$RequestId+'.json')) -Raw|ConvertFrom-Json) }
function Remove-DispatcherControl {
  param([Parameter(Mandatory)]$Control)
  if (-not (Test-Path -LiteralPath $Control.root -PathType Container)) { return }
  $root = Get-Item -LiteralPath (Resolve-Path -LiteralPath $Control.root).Path
  $temporary = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
  if ($root.Parent.FullName -ne $temporary -or $root.Name -notlike 'mir-dispatcher-*' -or
      ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '[gunmetal-dispatcher-control-cleanup-path]' }
  [IO.Directory]::Delete($root.FullName, $true)
}

$controls=@()
try {
  # Gunmetal's real user manager records USER_INVOCATION_ID for a transient
  # unit. Do not silently switch back to the system-manager journal field.
  Assert-Dispatcher ((Get-Content -LiteralPath $dispatcher -Raw).Contains('USER_INVOCATION_ID=$InvocationId')) 'user-manager-journal-field-pinned'

  # Packet bytes are authenticated when a policy is read, before any request
  # snapshot, and again immediately before its launcher boundary.
  $identity=New-DispatcherControl -Name 'identity';$controls+=@($identity)
  [IO.File]::AppendAllText((Join-Path $identity.checkout 'build/p/native-control-identity/packet.json'),"changed`n")
  Refuses-Dispatcher {Get-MIRGunmetalDispatcherPolicy -Path $identity.base.path} '[mir-gunmetal-dispatcher-packet-hash]'
  $policyMutation=New-DispatcherControl -Name 'policy-mutation';$controls+=@($policyMutation)
  [IO.File]::AppendAllText($policyMutation.base.path," `n")
  Refuses-Dispatcher {New-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $policyMutation.base -CandidatePolicy $policyMutation.base} '[mir-gunmetal-dispatcher-policy-source-hash]'

  # A controller success is a reviewed exact protocol conclusion, not a
  # generic exit code. The demonstrated source-controller conclusion is
  # admitted verbatim; pending independent review is deliberately not one.
  $precise=New-DispatcherControl -Name 'precise-status';$controls+=@($precise)
  $sourceConclusion=New-DispatcherPolicy -Control $precise -RequestId 'native-control-precise-source' -PacketText 'source' -ResultStatus 'source-earned-and-read-only-cold-observed'
  Write-DispatcherResult -Policy $sourceConclusion
  $sourceResult=Get-MIRGunmetalDispatcherResult -Approval $sourceConclusion.approval
  Assert-Dispatcher ($sourceResult.valid-and$sourceResult.status-ceq'source-earned-and-read-only-cold-observed') 'precise-controller-conclusion-bound'
  Refuses-Dispatcher {New-DispatcherPolicy -Control $precise -RequestId 'native-control-precise-awaiting' -PacketText 'awaiting' -ResultStatus 'completed-await-independent-review'} '[mir-gunmetal-dispatcher-policy-result-status]'

  # A submit crash may leave request.json durable before its pending pointer.
  # Retrying the exact reviewed policy adopts that snapshot; a second retry
  # adopts the exact pending pointer rather than minting another request.
  $snapshotRecovery=New-DispatcherControl -Name 'snapshot-recovery';$controls+=@($snapshotRecovery)
  New-MIRGunmetalDispatcherDirectories -Policy $snapshotRecovery.base
  $orphanSnapshot=New-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $snapshotRecovery.base -CandidatePolicy $snapshotRecovery.base
  Assert-Dispatcher ($orphanSnapshot.recovered-eq$false) 'normal-snapshot-created-before-pointer'
  $recoveredSubmission=Submit-MIRGunmetalDispatcherApproved -Policy $snapshotRecovery.base
  Assert-Dispatcher ($recoveredSubmission.status-ceq'queued'-and(Test-Path -LiteralPath (Join-Path $snapshotRecovery.spool 'state/pending.json'))) 'normal-snapshot-retry-adopted'
  $repeatedSubmission=Submit-MIRGunmetalDispatcherApproved -Policy $snapshotRecovery.base
  Assert-Dispatcher ($repeatedSubmission.status-ceq'already-queued') 'normal-pending-retry-adopted'

  # One active job can carry exactly one distinct immutable successor. The
  # successor is a copied reviewed policy, not a mutable installed-policy read.
  $normal=New-DispatcherControl -Name 'normal';$controls+=@($normal)
  $script:fakeState='gone';$script:nextLaunchState='active';$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null}
  $queued=Submit-MIRGunmetalDispatcherApproved -Policy $normal.base
  Assert-Dispatcher ($queued.status-ceq'queued'-and(Test-Path -LiteralPath (Join-Path $normal.spool 'state/pending.signal'))) 'initial-policy-snapshotted-and-signalled'
  $first=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  Assert-Dispatcher ($first.status-ceq'submitted'-and$script:launches-eq1-and-not(Test-Path -LiteralPath (Join-Path $normal.spool 'state/pending.signal'))) 'active-launch-once-and-signal-consumed'
  $successor=New-DispatcherPolicy -Control $normal -RequestId 'native-control-normal-successor' -PacketText 'successor'
  $pending=Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $normal.base -SuccessorPolicyPath $successor.path
  Assert-Dispatcher ($pending.request_id-ceq$successor.approval.request_id-and(Test-Path -LiteralPath (Join-Path $normal.spool ('requests/'+$successor.approval.request_id+'/policy.json')))) 'one-immutable-successor-snapshot'
  $secondSuccessor=New-DispatcherPolicy -Control $normal -RequestId 'native-control-normal-third' -PacketText 'third'
  Refuses-Dispatcher {Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $normal.base -SuccessorPolicyPath $secondSuccessor.path} '[mir-gunmetal-dispatcher-pending-slot-not-empty]'
  $runningPath=Join-Path $normal.spool 'state/running.json'
  $pendingPath=Join-Path $normal.spool 'state/pending.json'
  $terminalPath=Join-Path $normal.spool ('terminal/'+$normal.base.approval.request_id+'.json')
  $runningHash=(Get-FileHash -LiteralPath $runningPath).Hash
  $pendingHash=(Get-FileHash -LiteralPath $pendingPath).Hash
  foreach($mode in @('query-error','query-partial')){
    $script:fakeState=$mode
    $observation=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
    Assert-Dispatcher ($observation.status-ceq'waiting-for-native-unit-observation' -and $script:launches-eq1 -and
      (Test-Path -LiteralPath $runningPath) -and (Get-FileHash -LiteralPath $runningPath).Hash-ceq$runningHash -and
      (Get-FileHash -LiteralPath $pendingPath).Hash-ceq$pendingHash -and
      -not (Test-Path -LiteralPath $terminalPath)) "running-$mode-preserves-invocation-and-successor"
  }
  Write-DispatcherResult -Policy $normal.base
  $script:fakeState = 'gone'
  $script:fakeJournal = [pscustomobject]@{observed=$false;exit_code=$null;incomplete=$true}
  $observation = Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  Assert-Dispatcher ($null -ne $observation -and $observation.status -ceq 'waiting-for-native-exit-journal-observation' -and
    $script:launches -eq 1 -and (Get-FileHash -LiteralPath $runningPath).Hash -ceq $runningHash -and
    (Get-FileHash -LiteralPath $pendingPath).Hash -ceq $pendingHash -and
    -not (Test-Path -LiteralPath $terminalPath)) 'journal-unavailable-preserves-invocation-and-successor'
  $script:fakeJournal = [pscustomobject]@{observed=$true;exit_code=0}
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  $terminal=Read-DispatcherTerminal -Control $normal -RequestId $normal.base.approval.request_id
  Assert-Dispatcher ($terminal.status-ceq'succeeded'-and$terminal.packet_sha256-ceq$normal.base.approval.packet_sha256-and$terminal.completion_envelope_sha256-match'^[A-F0-9]{64}$') 'packet-result-invocation-envelope-success'
  $script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  Assert-Dispatcher ($script:launches-eq2-and(Get-MIRGunmetalDispatcherStateRecord -Policy $normal.base -Name running).request_id-ceq$successor.approval.request_id) 'successor-starts-only-after-prior-success'

  # A retained user-systemd oneshot reports ActiveState=active/SubState=exited.
  # That is a terminal property result, not a still-running native session.
  $retained=New-DispatcherControl -Name 'retained-exit';$controls+=@($retained)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $retained.base;$script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $retained.base
  Write-DispatcherResult -Policy $retained.base;$script:fakeState='exited';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $retained.base
  $retainedTerminal=Read-DispatcherTerminal -Control $retained -RequestId $retained.base.approval.request_id
  Assert-Dispatcher ($retainedTerminal.status-ceq'succeeded'-and$retainedTerminal.result.result.status-ceq'passed') 'retained-oneshot-exit-is-terminal-with-verbatim-status'
  Test-DispatcherExitJournal

  # An external timing service or a failed manager query leaves the same
  # request queued. A later timer wakeup can launch it after proven absence.
  $waiting=New-DispatcherControl -Name 'waiting-for-unit';$controls+=@($waiting)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $waiting.base
  $beforeLaunches=$script:launches
  $waitingPath=Join-Path $waiting.spool 'state/pending.json'
  $waitingHash=(Get-FileHash -LiteralPath $waitingPath).Hash
  foreach($mode in @('active','query-error','failed')) {
    $script:fakeState=$mode
    $wait=Invoke-MIRGunmetalDispatcherConsume -Policy $waiting.base
    Assert-Dispatcher ($wait.status -ceq 'waiting-for-native-unit' -and $wait.request_id -ceq $waiting.base.approval.request_id -and $script:launches -eq $beforeLaunches) "unit-$mode-defers-launch"
    Assert-Dispatcher ((Get-FileHash -LiteralPath $waitingPath).Hash -ceq $waitingHash -and
      -not (Test-Path -LiteralPath (Join-Path $waiting.spool 'state/pending.signal')) -and
      -not (Test-Path -LiteralPath (Join-Path $waiting.spool 'state/intent.json')) -and
      -not (Test-Path -LiteralPath (Join-Path $waiting.spool 'state/running.json')) -and
      -not (Test-Path -LiteralPath (Join-Path $waiting.spool ('terminal/'+$waiting.base.approval.request_id+'.json')))) "unit-$mode-preserves-pending-without-rearm"
  }
  $script:fakeState='gone'
  $script:nextLaunchState='active'
  $submitted=Invoke-MIRGunmetalDispatcherConsume -Policy $waiting.base
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $waiting.base
  $running=Get-MIRGunmetalDispatcherStateRecord -Policy $waiting.base -Name running
  Assert-Dispatcher ($submitted.status -ceq 'submitted' -and $script:launches -eq ($beforeLaunches+1) -and
    $running.packet_sha256 -ceq $waiting.base.approval.packet_sha256 -and -not (Test-Path -LiteralPath $waitingPath)) 'same-pending-launches-once-after-unit-disappears'

  # An external owner may hold a direct-library lease between game processes.
  # The installed policy watches both editions even for a job approved without
  # that list when its immutable snapshot was created.
  $shared = New-DispatcherControl -Name 'shared-activity'
  $controls += @($shared)
  $otherEdition = Join-Path $shared.root '2.0'
  $jobEdition = Join-Path $shared.root '2.1'
  $null = [IO.Directory]::CreateDirectory($otherEdition)
  $null = [IO.Directory]::CreateDirectory($jobEdition)
  $baseRecord = Get-Content -LiteralPath $shared.base.path -Raw | ConvertFrom-Json -AsHashtable
  $baseRecord['shared_library_roots'] = @($otherEdition, $jobEdition)
  $baseRecord | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $shared.base.path -NoNewline
  $shared.base = Get-MIRGunmetalDispatcherPolicy -Path $shared.base.path
  $job = New-DispatcherPolicy -Control $shared -RequestId 'native-control-shared-job' -PacketText 'shared'
  $null = Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $shared.base -SuccessorPolicyPath $job.path
  $pendingPath = Join-Path $shared.spool 'state/pending.json'
  $pendingHash = (Get-FileHash -LiteralPath $pendingPath).Hash
  $beforeLaunches = $script:launches
  $script:fakeState = 'gone'
  $lease = [IO.File]::Open((Join-Path $otherEdition '.mir-library.lock'), 'CreateNew', 'ReadWrite', 'None')
  try {
    foreach ($reason in @('factorio-active', 'shared-library-lease')) {
      $script:fakeFactorioActive = $reason -ceq 'factorio-active'
      $waitingForSlot = Invoke-MIRGunmetalDispatcherConsume -Policy $shared.base
      Assert-Dispatcher ($waitingForSlot.status -ceq 'waiting-for-native-slot' -and
        $waitingForSlot.reason -ceq $reason -and $waitingForSlot.request_id -ceq $job.approval.request_id -and
        $script:launches -eq $beforeLaunches) "$reason-defers-launch"
      Assert-Dispatcher ((Get-FileHash -LiteralPath $pendingPath).Hash -ceq $pendingHash -and
        -not (Test-Path -LiteralPath (Join-Path $shared.spool 'state/pending.signal')) -and
        -not (Test-Path -LiteralPath (Join-Path $shared.spool 'state/intent.json')) -and
        -not (Test-Path -LiteralPath (Join-Path $shared.spool 'state/running.json')) -and
        -not (Test-Path -LiteralPath (Join-Path $shared.spool ('terminal/' + $job.approval.request_id + '.json')))) "$reason-preserves-original-pending"
    }
  } finally {
    $lease.Dispose()
    $script:fakeFactorioActive = $false
  }
  $submitted = Invoke-MIRGunmetalDispatcherConsume -Policy $shared.base
  $null = Invoke-MIRGunmetalDispatcherConsume -Policy $shared.base
  $running = Get-MIRGunmetalDispatcherStateRecord -Policy $shared.base -Name running
  Assert-Dispatcher ($submitted.status -ceq 'submitted' -and $script:launches -eq ($beforeLaunches + 1) -and
    $running.packet_sha256 -ceq $job.approval.packet_sha256 -and -not (Test-Path -LiteralPath $pendingPath) -and
    -not (Test-Path -LiteralPath (Join-Path $jobEdition '.mir-library.lock'))) 'same-pending-launches-once-after-shared-lease-releases'

  # A durable intent is written before a launcher. Restart adopts only a live
  # unit and exact immutable snapshot; an absent unit becomes interrupted,
  # never a second launch.
  $adopt=New-DispatcherControl -Name 'adopt';$controls+=@($adopt)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $adopt.base;$snapshot=Get-MIRGunmetalDispatcherPending -Policy $adopt.base
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $adopt.spool 'state/intent.json') -Value ([ordered]@{kind='MIRGunmetalNativeDispatcherLaunchIntentV1';request_id=$adopt.base.approval.request_id;request_snapshot_sha256=$snapshot.snapshot.request.policy_sha256;packet_sha256=$adopt.base.approval.packet_sha256;launcher_sha256=$adopt.base.approval.launcher_sha256;result_path=$adopt.base.approval.result_path;dispatch_id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';written_utc='2026-11-21T00:00:00Z'})
  $beforeLaunches=$script:launches;$script:fakeState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $adopt.base
  $adopted=Get-MIRGunmetalDispatcherStateRecord -Policy $adopt.base -Name running
  Assert-Dispatcher ($adopted.launch.acknowledgement-ceq'adopted-after-durable-intent'-and$script:launches-eq$beforeLaunches) 'durable-intent-adopts-live-unit'
  $starting=New-DispatcherControl -Name 'intent-observation';$controls+=@($starting)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $starting.base
  $beforeLaunches=$script:launches;$script:fakeState='gone';$script:nextLaunchState='query-error'
  $startObservation=Invoke-MIRGunmetalDispatcherConsume -Policy $starting.base
  $intentPath=Join-Path $starting.spool 'state/intent.json'
  $startTerminalPath=Join-Path $starting.spool ('terminal/'+$starting.base.approval.request_id+'.json')
  Assert-Dispatcher ($startObservation.status-ceq'waiting-for-native-unit-observation' -and
    $script:launches-eq($beforeLaunches+1) -and (Test-Path -LiteralPath $intentPath) -and
    -not (Test-Path -LiteralPath $startTerminalPath)) 'acknowledgement-query-error-preserves-durable-intent'
  $intentHash=(Get-FileHash -LiteralPath $intentPath).Hash
  foreach($mode in @('query-partial','activating-without-pid')){
    $script:fakeState=$mode
    $recoveryObservation=Invoke-MIRGunmetalDispatcherConsume -Policy $starting.base
    Assert-Dispatcher ($recoveryObservation.status-ceq'waiting-for-native-unit-observation' -and
      $script:launches-eq($beforeLaunches+1) -and (Test-Path -LiteralPath $intentPath) -and
      (Get-FileHash -LiteralPath $intentPath).Hash-ceq$intentHash -and
      -not (Test-Path -LiteralPath $startTerminalPath)) "intent-$mode-preserves-original-intent"
  }
  $script:fakeState='active';$recovered=Invoke-MIRGunmetalDispatcherConsume -Policy $starting.base
  $started=Get-MIRGunmetalDispatcherStateRecord -Policy $starting.base -Name running
  Assert-Dispatcher ($recovered.status-ceq'intent-adopted' -and
    $started.launch.start_ack.invocation_id-ceq$script:fakeInvocation -and
    $script:launches-eq($beforeLaunches+1)) 'observation-recovery-adopts-same-invocation-once'

  $absent=New-DispatcherControl -Name 'intent-absent';$controls+=@($absent)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $absent.base;$snapshot=Get-MIRGunmetalDispatcherPending -Policy $absent.base
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $absent.spool 'state/intent.json') -Value ([ordered]@{kind='MIRGunmetalNativeDispatcherLaunchIntentV1';request_id=$absent.base.approval.request_id;request_snapshot_sha256=$snapshot.snapshot.request.policy_sha256;packet_sha256=$absent.base.approval.packet_sha256;launcher_sha256=$absent.base.approval.launcher_sha256;result_path=$absent.base.approval.result_path;dispatch_id='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';written_utc='2026-11-21T00:00:00Z'})
  $beforeLaunches=$script:launches;$script:fakeState='gone';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $absent.base
  $terminal=Read-DispatcherTerminal -Control $absent -RequestId $absent.base.approval.request_id
  Assert-Dispatcher ($terminal.status-ceq'interrupted'-and$terminal.reason-ceq'intent-recovered-without-native-unit'-and$script:launches-eq$beforeLaunches) 'durable-intent-absence-is-terminal'

  # After an adverse terminal the reviewed successor stays held. A distinct
  # policy plus a recorded disposition can replace it; a colliding request ID
  # cannot amend the immutable held policy.
  $adverse=New-DispatcherControl -Name 'adverse';$controls+=@($adverse)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $adverse.base;$script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $adverse.base
  $script:fakeState='gone';$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null};$null=Invoke-MIRGunmetalDispatcherConsume -Policy $adverse.base
  $held=New-DispatcherPolicy -Control $adverse -RequestId 'native-control-adverse-held' -PacketText 'unchanged'
  $null=Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $adverse.base -SuccessorPolicyPath $held.path
  $beforeLaunches=$script:launches;$heldResult=Invoke-MIRGunmetalDispatcherConsume -Policy $adverse.base
  Assert-Dispatcher ($heldResult.status-ceq'held-after-adverse-terminal'-and$script:launches-eq$beforeLaunches-and(Test-Path -LiteralPath (Join-Path $adverse.spool 'state/pending.json'))-and-not(Test-Path -LiteralPath (Join-Path $adverse.spool 'state/pending.signal'))) 'adverse-holds-pending-without-path-loop-signal'
  $replacement=New-DispatcherPolicy -Control $adverse -RequestId 'native-control-adverse-replacement' -PacketText 'changed'
  $heldCollisionPath=Join-Path $adverse.root 'native-control-adverse-held-collision-policy.json'
  $heldCollisionRecord=Get-Content -LiteralPath $held.path -Raw|ConvertFrom-Json
  $heldCollisionRecord.approval.reviewed_by='different-independent-reviewer'
  $heldCollisionRecord|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $heldCollisionPath -NoNewline
  $heldCollision=Get-MIRGunmetalDispatcherPolicy -Path $heldCollisionPath
  Refuses-Dispatcher {Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $adverse.base -SuccessorPolicyPath $heldCollision.path -DispositionReference 'reviewed'} '[mir-gunmetal-dispatcher-held-snapshot-policy-mismatch]'
  $holdRecord=Get-MIRGunmetalDispatcherStateRecord -Policy $adverse.base -Name hold
  $replacementSnapshot=New-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $adverse.base -CandidatePolicy $replacement -PredecessorRequestId $holdRecord.predecessor_request_id -DispositionReference 'https://example.invalid/disposition'
  Set-MIRGunmetalDispatcherPending -Policy $adverse.base -Snapshot $replacementSnapshot -PredecessorRequestId $holdRecord.predecessor_request_id -DispositionReference 'https://example.invalid/disposition'
  $resolution=Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $adverse.base -SuccessorPolicyPath $replacement.path -DispositionReference 'https://example.invalid/disposition'
  Assert-Dispatcher ($resolution.status-ceq'released'-and-not(Test-Path -LiteralPath (Join-Path $adverse.spool 'state/hold.json'))-and(Test-Path -LiteralPath (Join-Path $adverse.spool ('held/'+$holdRecord.predecessor_request_id+'-'+$replacement.approval.request_id+'.json')))) 'held-replacement-crash-recovered-idempotently'
  $script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $adverse.base
  Assert-Dispatcher ($script:launches-eq($beforeLaunches+1)) 'disposed-successor-starts-once'

  # A reviewer may also release the exact snapshot already held. The command
  # carries the new disposition reference but cannot mutate packet, launcher,
  # request ID, or policy bytes.
  $release=New-DispatcherControl -Name 'release';$controls+=@($release)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $release.base;$script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $release.base
  $script:fakeState='gone';$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null};$null=Invoke-MIRGunmetalDispatcherConsume -Policy $release.base
  $releaseHeld=New-DispatcherPolicy -Control $release -RequestId 'native-control-release-held' -PacketText 'reviewed-successor'
  $null=Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $release.base -SuccessorPolicyPath $releaseHeld.path
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $release.base
  $holdPath = Join-Path $release.spool 'state/hold.json'
  $originalHold = Read-MIRGunmetalDispatcherJson -Path $holdPath
  $originalHold.held_utc = '2026-11-21T15:36:52.6741800Z'
  Write-MIRGunmetalDispatcherJson -Path $holdPath -Value $originalHold
  $originalHoldSha256 = Get-MIRGunmetalDispatcherSha256 $holdPath
  $released=Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $release.base -SuccessorPolicyPath $releaseHeld.path -DispositionReference 'https://example.invalid/release-disposition'
  Assert-Dispatcher ($released.status-ceq'released'-and-not(Test-Path -LiteralPath $holdPath)) 'held-exact-snapshot-released-with-disposition'
  $archivedHold = Join-Path $release.spool ('held/' + $originalHold.predecessor_request_id + '-' + $releaseHeld.approval.request_id + '.json')
  Assert-Dispatcher ((Get-MIRGunmetalDispatcherSha256 $archivedHold) -ceq $originalHoldSha256) 'held-disposition-preserves-original-record-bytes'
  $beforeLaunches=$script:launches;$script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $release.base
  Assert-Dispatcher ($script:launches-eq($beforeLaunches+1)) 'released-exact-snapshot-starts-once'

  # A terminal may have reached durable custody before cleanup of running,
  # pending, or last-terminal pointers. Both the running and fresh-start paths
  # finalize that exact terminal without invoking the launcher again.
  $terminalRecovery=New-DispatcherControl -Name 'terminal-recovery';$controls+=@($terminalRecovery)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $terminalRecovery.base;$script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $terminalRecovery.base
  $savedRunning=Get-MIRGunmetalDispatcherStateRecord -Policy $terminalRecovery.base -Name running
  $savedSnapshot=Get-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $terminalRecovery.base -RequestId $terminalRecovery.base.approval.request_id
  $savedSubmission=[pscustomobject]@{request_id=$savedSnapshot.request.request_id;policy_sha256=$savedSnapshot.request.policy_sha256}
  Write-DispatcherResult -Policy $terminalRecovery.base
  $terminalResult=[ordered]@{result=(Get-MIRGunmetalDispatcherResult -Approval $terminalRecovery.base.approval);journal=[ordered]@{observed=$true;exit_code=0;source='control'}}
  New-MIRGunmetalDispatcherTerminal -Policy $terminalRecovery.base -Running $savedRunning -Status succeeded -Reason 'control-terminal' -Result $terminalResult
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $terminalRecovery.spool 'state/running.json') -Value $savedRunning
  Set-MIRGunmetalDispatcherPending -Policy $terminalRecovery.base -Snapshot $savedSubmission
  Remove-Item -LiteralPath (Join-Path $terminalRecovery.spool 'state/last-terminal.json') -Force
  $beforeLaunches=$script:launches;$finalizedRunning=Invoke-MIRGunmetalDispatcherConsume -Policy $terminalRecovery.base
  Assert-Dispatcher ($finalizedRunning.status-ceq'running-terminal-finalized'-and$script:launches-eq$beforeLaunches-and-not(Test-Path -LiteralPath (Join-Path $terminalRecovery.spool 'state/running.json'))-and-not(Test-Path -LiteralPath (Join-Path $terminalRecovery.spool 'state/pending.json'))) 'terminal-crash-finalizes-running-and-pending'
  Set-MIRGunmetalDispatcherPending -Policy $terminalRecovery.base -Snapshot $savedSubmission
  Remove-Item -LiteralPath (Join-Path $terminalRecovery.spool 'state/last-terminal.json') -Force
  $beforeLaunches=$script:launches;$finalizedStart=Invoke-MIRGunmetalDispatcherConsume -Policy $terminalRecovery.base
  Assert-Dispatcher ($finalizedStart.status-ceq'submitted'-and$script:launches-eq$beforeLaunches-and-not(Test-Path -LiteralPath (Join-Path $terminalRecovery.spool 'state/pending.json'))) 'terminal-crash-is-recognized-before-start'

  $plan=& $installer -Mode Compose -PolicyPath $normal.base.path -InstallRoot (Join-Path $normal.root 'install') -UnitDirectory (Join-Path $normal.root 'units')
  Assert-Dispatcher ($plan.files['mir-native-dispatcher.path'].Contains(('PathExists='+$normal.spool+'/state/pending.signal'))) 'edge-triggered-path-consumer-composed'
  $timer = $plan.files['mir-native-dispatcher.timer']
  Assert-Dispatcher ($timer.Contains('OnActiveSec=1min') -and $timer.Contains('OnUnitInactiveSec=1min') -and
    $plan.files['mir-native-dispatcher.service'].Contains('NoNewPrivileges=yes')) 'bounded-timer-and-unit-hardening'

  # A failed enable keeps only this transaction's bytes for a byte-identical
  # resume. Existing unrelated unit data is neither replaced nor removed.
  $installRoot=Join-Path $normal.root 'install-transaction'
  $unitRoot=Join-Path $normal.root 'units-transaction'
  [IO.Directory]::CreateDirectory($unitRoot)|Out-Null
  $unrelated=Join-Path $unitRoot 'unrelated.service';[IO.File]::WriteAllText($unrelated,'preserve',[Text.UTF8Encoding]::new($false))
  $installPlan=Get-MIRGunmetalDispatcherInstallPlan -PolicyPath $normal.base.path -InstallRoot $installRoot -UnitDirectory $unitRoot
  $script:installState='enable-fail';$script:installCalls.Clear()
  Refuses-Dispatcher {Invoke-MIRGunmetalDispatcherInstallLifecycle -Plan $installPlan -Action Install -TestOnly} '[mir-gunmetal-dispatcher-install-enable-resume-required]'
  $transaction=Read-MIRGunmetalDispatcherInstallTransaction -Plan $installPlan
  Assert-Dispatcher ($transaction.stage-ceq'enable-pending'-and(Test-Path -LiteralPath $unrelated)) 'enable-failure-preserves-owned-transaction-and-unrelated-unit'
  $script:installState='success';$resumed=Invoke-MIRGunmetalDispatcherInstallLifecycle -Plan $installPlan -Action Resume -TestOnly
  Assert-Dispatcher ($resumed.status-ceq'installed'-and(Read-MIRGunmetalDispatcherInstallTransaction -Plan $installPlan).stage-ceq'installed') 'identical-resume-completes-owned-install'
  $rolledBack=Undo-MIRGunmetalDispatcherInstall -Plan $installPlan
  Assert-Dispatcher ($rolledBack.status-ceq'rolled-back'-and(Test-Path -LiteralPath $unrelated)-and-not(Test-Path -LiteralPath (Join-Path $unitRoot 'mir-native-dispatcher.service'))) 'rollback-removes-only-owned-unit-files'
  $reloadPlan=Get-MIRGunmetalDispatcherInstallPlan -PolicyPath $normal.base.path -InstallRoot (Join-Path $normal.root 'install-reload') -UnitDirectory (Join-Path $normal.root 'units-reload')
  $script:installState='reload-fail'
  Refuses-Dispatcher {Invoke-MIRGunmetalDispatcherInstallLifecycle -Plan $reloadPlan -Action Install -TestOnly} '[mir-gunmetal-dispatcher-install-daemon-reload-resume-required]'
  Assert-Dispatcher ((Read-MIRGunmetalDispatcherInstallTransaction -Plan $reloadPlan).stage-ceq'reload-pending') 'reload-failure-is-resumable-transaction'
  $script:installState='success';$null=Invoke-MIRGunmetalDispatcherInstallLifecycle -Plan $reloadPlan -Action Resume -TestOnly;$null=Undo-MIRGunmetalDispatcherInstall -Plan $reloadPlan
  Assert-Dispatcher (-not(Test-Path -LiteralPath (Join-Path $normal.root 'install-reload'))) 'resumed-reload-transaction-rolls-back-owned-root'
} finally {
  foreach($control in @($controls)){Remove-DispatcherControl -Control $control}
}

[pscustomobject]@{kind='MIRGunmetalNativeDispatcherControlV2';status='passed';checks=$script:checks;native_execution=$false;gameplay_acceptance=$false;operational_scope='disposable spool state-machine control only'}
