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

$script:checks=0
$script:launches=0
$script:fakeState='gone'
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
    'failed' {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=loaded','ActiveState=failed','SubState=failed','MainPID=0',('InvocationID='+$script:fakeInvocation),'Result=exit-code','ExecMainCode=exited','ExecMainStatus=1') }
    }
    'query-error' { return [pscustomobject]@{ exit_code = 1; lines = @('Failed to connect to bus') } }
    default {
      return [pscustomobject]@{ exit_code = 0; lines = @('LoadState=not-found','ActiveState=inactive','SubState=dead','MainPID=0','InvocationID=','Result=','ExecMainCode=','ExecMainStatus=') }
    }
  }
}
function Invoke-MIRGunmetalDispatcherLauncher {
  param([Parameter(Mandatory)][string]$Path)
  $script:launches++
  $script:fakeState=$script:nextLaunchState
  return [pscustomobject]@{exit_code=0;lines=@('{"event":"systemd-launch-returned","exit_code":0}')}
}
function Get-MIRGunmetalDispatcherJournalTerminal { param([Parameter(Mandatory)][string]$InvocationId) return $script:fakeJournal }

$script:installState='success'
$script:installCalls=[Collections.Generic.List[string]]::new()
function Get-MIRGunmetalDispatcherInstallLinger { return [pscustomobject]@{exit_code=0;lines=@('yes')} }
function Invoke-MIRGunmetalDispatcherInstallSystemctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $script:installCalls.Add(($Arguments -join ' '))
  if ($script:installState -ceq 'reload-fail' -and $Arguments[0] -ceq 'daemon-reload') {
    return [pscustomobject]@{ exit_code = 1; lines = @('reload failed') }
  }
  if ($script:installState -ceq 'enable-fail' -and $Arguments[0] -ceq 'enable') {
    return [pscustomobject]@{ exit_code = 1; lines = @('enable failed') }
  }
  return [pscustomobject]@{ exit_code = 0; lines = @() }
}

function New-DispatcherPolicy {
  param([Parameter(Mandatory)]$Control,[Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$PacketText)
  $case=Join-Path $Control.checkout ('build/p/'+$RequestId)
  $resultDirectory=Join-Path $Control.result_root $RequestId
  [IO.Directory]::CreateDirectory($case)|Out-Null
  [IO.Directory]::CreateDirectory($resultDirectory)|Out-Null
  $launcher=Join-Path $case 'Launch-Transient.sh'
  $packet=Join-Path $case 'packet.json'
  $result=Join-Path $resultDirectory 'result.json'
  [IO.File]::WriteAllText($launcher,"#!/bin/bash`nexit 0`n",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($packet,('{"packet":"'+$PacketText+'"}'+"`n"),[Text.UTF8Encoding]::new($false))
  $policy=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherPolicyV1';execution_account=[Environment]::UserName;spool_root=$Control.spool;allowed_checkout_root=$Control.checkout;allowed_result_root=$Control.result_root;native_unit='mir-native.service';approval=[ordered]@{request_id=$RequestId;owner=[Environment]::UserName;reviewed_by='independent-review';review_reference='https://example.invalid/review';execution_class='functional-not-timing';launcher_relative_path=('build/p/'+$RequestId+'/Launch-Transient.sh');launcher_sha256=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash;packet_relative_path=('build/p/'+$RequestId+'/packet.json');packet_sha256=(Get-FileHash -LiteralPath $packet -Algorithm SHA256).Hash;result_path=$result;result_kind='MIRDispatcherControlResultV1'}}
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
function Write-DispatcherResult { param([Parameter(Mandatory)]$Policy)[IO.File]::WriteAllText($Policy.approval.result_path,('{"kind":"MIRDispatcherControlResultV1","status":"passed","packet_sha256":"'+$Policy.approval.packet_sha256+'"}'+"`n"),[Text.UTF8Encoding]::new($false)) }
function Read-DispatcherTerminal { param([Parameter(Mandatory)]$Control,[Parameter(Mandatory)][string]$RequestId) return (Get-Content -LiteralPath (Join-Path $Control.spool ('terminal/'+$RequestId+'.json')) -Raw|ConvertFrom-Json) }
function Remove-DispatcherControl { param([Parameter(Mandatory)]$Control)if(Test-Path -LiteralPath $Control.root){[IO.Directory]::Delete($Control.root,$true)} }

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

  # One active job can carry exactly one distinct immutable successor. The
  # successor is a copied reviewed policy, not a mutable installed-policy read.
  $normal=New-DispatcherControl -Name 'normal';$controls+=@($normal)
  $script:fakeState='gone';$script:nextLaunchState='active';$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null}
  $queued=Submit-MIRGunmetalDispatcherApproved -Policy $normal.base
  Assert-Dispatcher ($queued.status-ceq'queued') 'initial-policy-snapshotted'
  $first=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  Assert-Dispatcher ($first.status-ceq'submitted'-and$script:launches-eq1) 'active-launch-once'
  $successor=New-DispatcherPolicy -Control $normal -RequestId 'native-control-normal-successor' -PacketText 'successor'
  $pending=Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $normal.base -SuccessorPolicyPath $successor.path
  Assert-Dispatcher ($pending.request_id-ceq$successor.approval.request_id-and(Test-Path -LiteralPath (Join-Path $normal.spool ('requests/'+$successor.approval.request_id+'/policy.json')))) 'one-immutable-successor-snapshot'
  $secondSuccessor=New-DispatcherPolicy -Control $normal -RequestId 'native-control-normal-third' -PacketText 'third'
  Refuses-Dispatcher {Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $normal.base -SuccessorPolicyPath $secondSuccessor.path} '[mir-gunmetal-dispatcher-pending-slot-not-empty]'
  Write-DispatcherResult -Policy $normal.base;$script:fakeState='gone';$script:fakeJournal=[pscustomobject]@{observed=$true;exit_code=0}
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  $terminal=Read-DispatcherTerminal -Control $normal -RequestId $normal.base.approval.request_id
  Assert-Dispatcher ($terminal.status-ceq'succeeded'-and$terminal.packet_sha256-ceq$normal.base.approval.packet_sha256-and$terminal.completion_envelope_sha256-match'^[A-F0-9]{64}$') 'packet-result-invocation-envelope-success'
  $script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.base
  Assert-Dispatcher ($script:launches-eq2-and(Get-MIRGunmetalDispatcherStateRecord -Policy $normal.base -Name running).request_id-ceq$successor.approval.request_id) 'successor-starts-only-after-prior-success'

  # A failed/unavailable unit query is not proof of absence; no launcher runs.
  $uncertain=New-DispatcherControl -Name 'uncertain';$controls+=@($uncertain)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $uncertain.base;$beforeLaunches=$script:launches;$script:fakeState='query-error'
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $uncertain.base
  $terminal=Read-DispatcherTerminal -Control $uncertain -RequestId $uncertain.base.approval.request_id
  Assert-Dispatcher ($terminal.status-ceq'interrupted'-and$terminal.reason-ceq'native-unit-absence-not-confirmed'-and$script:launches-eq$beforeLaunches) 'unit-query-error-is-not-absence'

  # A durable intent is written before a launcher. Restart adopts only a live
  # unit and exact immutable snapshot; an absent unit becomes interrupted,
  # never a second launch.
  $adopt=New-DispatcherControl -Name 'adopt';$controls+=@($adopt)
  $null=Submit-MIRGunmetalDispatcherApproved -Policy $adopt.base;$snapshot=Get-MIRGunmetalDispatcherPending -Policy $adopt.base
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $adopt.spool 'state/intent.json') -Value ([ordered]@{kind='MIRGunmetalNativeDispatcherLaunchIntentV1';request_id=$adopt.base.approval.request_id;request_snapshot_sha256=$snapshot.snapshot.request.policy_sha256;packet_sha256=$adopt.base.approval.packet_sha256;launcher_sha256=$adopt.base.approval.launcher_sha256;result_path=$adopt.base.approval.result_path;dispatch_id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';written_utc='2026-11-21T00:00:00Z'})
  $beforeLaunches=$script:launches;$script:fakeState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $adopt.base
  $adopted=Get-MIRGunmetalDispatcherStateRecord -Policy $adopt.base -Name running
  Assert-Dispatcher ($adopted.launch.acknowledgement-ceq'adopted-after-durable-intent'-and$script:launches-eq$beforeLaunches) 'durable-intent-adopts-live-unit'
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
  Assert-Dispatcher ($heldResult.status-ceq'held-after-adverse-terminal'-and$script:launches-eq$beforeLaunches) 'adverse-holds-pending-successor'
  $replacement=New-DispatcherPolicy -Control $adverse -RequestId 'native-control-adverse-replacement' -PacketText 'changed'
  $heldCollisionPath=Join-Path $adverse.root 'native-control-adverse-held-collision-policy.json'
  $heldCollisionRecord=Get-Content -LiteralPath $held.path -Raw|ConvertFrom-Json
  $heldCollisionRecord.approval.reviewed_by='different-independent-reviewer'
  $heldCollisionRecord|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $heldCollisionPath -NoNewline
  $heldCollision=Get-MIRGunmetalDispatcherPolicy -Path $heldCollisionPath
  Refuses-Dispatcher {Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $adverse.base -SuccessorPolicyPath $heldCollision.path -DispositionReference 'reviewed'} '[mir-gunmetal-dispatcher-held-snapshot-policy-mismatch]'
  $resolution=Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $adverse.base -SuccessorPolicyPath $replacement.path -DispositionReference 'https://example.invalid/disposition'
  Assert-Dispatcher ($resolution.status-ceq'replaced'-and-not(Test-Path -LiteralPath (Join-Path $adverse.spool 'state/hold.json'))) 'held-successor-replaced-by-distinct-policy'
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
  $released=Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $release.base -SuccessorPolicyPath $releaseHeld.path -DispositionReference 'https://example.invalid/release-disposition'
  Assert-Dispatcher ($released.status-ceq'released'-and-not(Test-Path -LiteralPath (Join-Path $release.spool 'state/hold.json'))) 'held-exact-snapshot-released-with-disposition'
  $beforeLaunches=$script:launches;$script:fakeState='gone';$script:nextLaunchState='active';$null=Invoke-MIRGunmetalDispatcherConsume -Policy $release.base
  Assert-Dispatcher ($script:launches-eq($beforeLaunches+1)) 'released-exact-snapshot-starts-once'

  $plan=& $installer -Mode Compose -PolicyPath $normal.base.path -InstallRoot (Join-Path $normal.root 'install') -UnitDirectory (Join-Path $normal.root 'units')
  Assert-Dispatcher ($plan.files['mir-native-dispatcher.path'].Contains(('PathExists='+$normal.spool+'/state/pending.json'))) 'path-consumer-composed'
  Assert-Dispatcher ($plan.files['mir-native-dispatcher.timer'].Contains('OnUnitInactiveSec=1min')-and$plan.files['mir-native-dispatcher.service'].Contains('NoNewPrivileges=yes')) 'bounded-timer-and-unit-hardening'

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
