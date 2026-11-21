# No Factorio, library, package, engine or systemd user manager is launched.
# This is a disposable-spool state-machine control for the reviewed launcher
# boundary.  It demonstrates that a detached launcher's zero exit code is not
# treated as an underlying native result.
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$dispatcher=Join-Path $RepoRoot 'tools/commands/workspace/Invoke-MIRGunmetalNativeDispatcher.ps1'
$installer=Join-Path $RepoRoot 'tools/commands/workspace/Install-MIRGunmetalNativeDispatcher.ps1'
. $dispatcher
$script:checks=0
$script:launches=0
$script:fakeState='not-found'
$script:nextLaunchState='active'
$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null}
$script:fakeInvocation='0123456789abcdef0123456789abcdef'

function Assert-Dispatcher([bool]$Condition,[string]$Name){if(-not$Condition){throw "[gunmetal-dispatcher-control-$Name]"};$script:checks++}
function Refuses-Dispatcher([scriptblock]$Action,[string]$Expected){$message='';try{&$Action|Out-Null}catch{$message=$_.Exception.Message};Assert-Dispatcher $message.Contains($Expected) "$Expected observed=$message"}

function Invoke-MIRGunmetalDispatcherSystemctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  switch($script:fakeState){
    'active' { return [pscustomobject]@{exit_code=0;lines=@('LoadState=loaded','ActiveState=active','SubState=running','MainPID=4242',('InvocationID='+$script:fakeInvocation),'Result=success','ExecMainCode=','ExecMainStatus=')} }
    'failed' { return [pscustomobject]@{exit_code=0;lines=@('LoadState=loaded','ActiveState=failed','SubState=failed','MainPID=0',('InvocationID='+$script:fakeInvocation),'Result=exit-code','ExecMainCode=exited','ExecMainStatus=1')} }
    default { return [pscustomobject]@{exit_code=0;lines=@('LoadState=not-found','ActiveState=inactive','SubState=dead','MainPID=0','InvocationID=','Result=','ExecMainCode=','ExecMainStatus=')} }
  }
}
function Invoke-MIRGunmetalDispatcherLauncher {param([Parameter(Mandatory)][string]$Path)$script:launches++;$script:fakeState=$script:nextLaunchState;return [pscustomobject]@{exit_code=0;lines=@('{"event":"systemd-launch-returned","exit_code":0}')}}
function Get-MIRGunmetalDispatcherJournalTerminal {param([Parameter(Mandatory)][string]$InvocationId)return $script:fakeJournal}

function New-DispatcherControl {
  param([Parameter(Mandatory)][string]$Name)
  $root=Join-Path ([IO.Path]::GetTempPath()) ('mir-dispatcher-'+$Name+'-'+[guid]::NewGuid().ToString('N'))
  $checkout=Join-Path $root 'checkout';$packetDirectory=Join-Path $checkout 'build/p/case';$resultRoot=Join-Path $root 'result-root';$resultDirectory=Join-Path $resultRoot 'case';$spool=Join-Path $root 'spool'
  foreach($directory in @($packetDirectory,$resultDirectory,$spool)){[IO.Directory]::CreateDirectory($directory)|Out-Null}
  $launcher=Join-Path $packetDirectory 'Launch-Transient.sh';$packet=Join-Path $packetDirectory 'packet.json';$result=Join-Path $resultDirectory 'result.json'
  [IO.File]::WriteAllText($launcher,"#!/bin/bash`nexit 0`n",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($packet,"{`"packet`":`"fixed`"}`n",[Text.UTF8Encoding]::new($false))
  $request='native-control-'+$Name
  $policy=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherPolicyV1';execution_account=[Environment]::UserName;spool_root=$spool;allowed_checkout_root=$checkout;allowed_result_root=$resultRoot;native_unit='mir-native.service';approval=[ordered]@{request_id=$request;owner=[Environment]::UserName;reviewed_by='independent-review';review_reference='https://example.invalid/review';execution_class='functional-not-timing';launcher_relative_path='build/p/case/Launch-Transient.sh';launcher_sha256=(Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash;packet_relative_path='build/p/case/packet.json';packet_sha256=(Get-FileHash -LiteralPath $packet -Algorithm SHA256).Hash;result_path=$result;result_kind='MIRDispatcherControlResultV1'}}
  $policyPath=Join-Path $root 'policy.json';$policy|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $policyPath -NoNewline
  return [pscustomobject]@{root=$root;policy_path=$policyPath;policy=(Get-MIRGunmetalDispatcherPolicy -Path $policyPath);packet=$packet;result=$result;request=$request}
}
function Add-DispatcherSubmission {
  param([Parameter(Mandatory)]$Control,[string]$RequestId=$Control.request,[string]$Name='submission.json')
  New-MIRGunmetalDispatcherDirectories -Policy $Control.policy
  [ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherSubmissionV1';request_id=$RequestId;submitted_utc='2026-11-21T00:00:00Z'}|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $Control.policy.spool ('incoming/'+$Name)) -NoNewline
}
function Read-DispatcherTerminal {param([Parameter(Mandatory)]$Control)(Get-Content -LiteralPath (Join-Path $Control.policy.spool ('terminal/'+$Control.request+'.json')) -Raw|ConvertFrom-Json)}
function Remove-DispatcherControl {param([Parameter(Mandatory)]$Control)if(Test-Path -LiteralPath $Control.root){[IO.Directory]::Delete($Control.root,$true)}}

$controls=@()
try{
  # The policy permits exactly the fixed launcher and packet bytes. A changed
  # packet is refused before a spool consumer can acknowledge anything.
  $identity=New-DispatcherControl -Name 'identity';$controls+=@($identity)
  [IO.File]::AppendAllText($identity.packet,"changed`n")
  Refuses-Dispatcher {Get-MIRGunmetalDispatcherPolicy -Path $identity.policy_path} '[mir-gunmetal-dispatcher-packet-hash]'

  # Normal detached start: actual PID/invocation acknowledgement is retained,
  # and a second timer/path pass cannot start a second launcher.
  $normal=New-DispatcherControl -Name 'normal';$controls+=@($normal)
  $script:fakeState='not-found';$script:nextLaunchState='active';$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null}
  $queued=Submit-MIRGunmetalDispatcherApproved -Policy $normal.policy
  Assert-Dispatcher ($queued.status-ceq'queued') 'approved-submission-is-atomic-marker-only'
  $first=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.policy
  Assert-Dispatcher ($first.status-ceq'submitted'-and$script:launches-eq1) 'acknowledged-launch-once'
  $running=Get-Content -LiteralPath (Join-Path $normal.policy.spool 'state/running.json') -Raw|ConvertFrom-Json
  Assert-Dispatcher ($running.launch.start_ack.pid-eq4242-and$running.launch.start_ack.invocation_id-ceq$script:fakeInvocation) 'pid-and-invocation-acknowledged'
  $again=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.policy
  Assert-Dispatcher ($again.status-ceq'reconciled'-and$script:launches-eq1) 'active-job-not-relaunched'
  # A completion requires BOTH the reviewed result contract and terminal
  # systemd/journal evidence; a detached launcher exit was never a pass.
  [IO.File]::WriteAllText($normal.result,"{`"kind`":`"MIRDispatcherControlResultV1`",`"status`":`"passed`"}`n",[Text.UTF8Encoding]::new($false))
  $script:fakeState='not-found';$script:fakeJournal=[pscustomobject]@{observed=$true;exit_code=0}
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.policy
  $terminal=Read-DispatcherTerminal -Control $normal
  Assert-Dispatcher ($terminal.status-ceq'succeeded'-and$terminal.result.result.sha256-match'^[A-F0-9]{64}$') 'journal-and-result-terminal-success'
  Add-DispatcherSubmission -Control $normal -Name 'duplicate-after-terminal.json'
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $normal.policy
  Assert-Dispatcher (@(Get-ChildItem -LiteralPath (Join-Path $normal.policy.spool 'rejected') -File).Count-eq1-and$script:launches-eq1) 'terminal-duplicate-refused'

  # Two path events at once are ambiguous and are both preserved as rejected;
  # neither can win a race based on directory enumeration order.
  $ambiguous=New-DispatcherControl -Name 'ambiguous';$controls+=@($ambiguous)
  Add-DispatcherSubmission -Control $ambiguous -Name 'a.json';Add-DispatcherSubmission -Control $ambiguous -Name 'b.json'
  $beforeLaunches=$script:launches;$ambiguousResult=Invoke-MIRGunmetalDispatcherConsume -Policy $ambiguous.policy
  Assert-Dispatcher ($ambiguousResult.status-ceq'rejected-ambiguous-submissions'-and @(Get-ChildItem -LiteralPath (Join-Path $ambiguous.policy.spool 'rejected') -File).Count-eq2-and$script:launches-eq$beforeLaunches) 'duplicate-race-refused'

  # A retained result cannot be borrowed from a former attempt.  This stops
  # before the launcher and creates a terminal rejection rather than treating
  # old bytes as a successful current native operation.
  $stale=New-DispatcherControl -Name 'stale';$controls+=@($stale)
  [IO.File]::WriteAllText($stale.result,"{`"kind`":`"MIRDispatcherControlResultV1`",`"status`":`"passed`"}`n",[Text.UTF8Encoding]::new($false))
  Add-DispatcherSubmission -Control $stale;$beforeLaunches=$script:launches;$null=Invoke-MIRGunmetalDispatcherConsume -Policy $stale.policy
  $terminal=Read-DispatcherTerminal -Control $stale
  Assert-Dispatcher ($terminal.status-ceq'rejected'-and$terminal.reason-ceq'prelaunch-pinned-input-refused'-and$script:launches-eq$beforeLaunches) 'stale-result-refused-before-launch'

  # An old detached launcher could return zero after the unit had vanished.
  # That is an interrupted operational record, not a successful native test,
  # and the retained submission is never automatically retried.
  $interrupted=New-DispatcherControl -Name 'interrupted';$controls+=@($interrupted)
  Add-DispatcherSubmission -Control $interrupted;$script:fakeState='not-found';$script:nextLaunchState='not-found';$script:fakeJournal=[pscustomobject]@{observed=$false;exit_code=$null}
  $beforeLaunches=$script:launches;$null=Invoke-MIRGunmetalDispatcherConsume -Policy $interrupted.policy
  $terminal=Read-DispatcherTerminal -Control $interrupted
  Assert-Dispatcher ($terminal.status-ceq'interrupted'-and$terminal.reason-ceq'launcher-returned-without-native-start-acknowledgement'-and$script:launches-eq($beforeLaunches+1)) 'detached-exit-is-not-success'
  $null=Invoke-MIRGunmetalDispatcherConsume -Policy $interrupted.policy
  Assert-Dispatcher ($script:launches-eq($beforeLaunches+1)) 'interrupted-no-automatic-retry'

  # Composition emits a path event consumer and a low-rate reconciliation
  # timer; neither unit contains a packet shell command or claims gameplay.
  $plan=& $installer -Mode Compose -PolicyPath $normal.policy_path -InstallRoot (Join-Path $normal.root 'install') -UnitDirectory (Join-Path $normal.root 'units')
  Assert-Dispatcher ($plan.files['mir-native-dispatcher.path'].Contains(('PathExistsGlob='+$normal.policy.spool+'/incoming/*.json'))) 'path-consumer-composed'
  Assert-Dispatcher ($plan.files['mir-native-dispatcher.timer'].Contains('OnUnitInactiveSec=1min')-and$plan.files['mir-native-dispatcher.service'].Contains('NoNewPrivileges=yes')) 'bounded-timer-and-unit-hardening'
  Assert-Dispatcher (-not$plan.files['mir-native-dispatcher.service'].Contains('packet.json')) 'no-packet-command-in-unit'
}finally{
  foreach($control in @($controls)){Remove-DispatcherControl -Control $control}
}

[pscustomobject]@{kind='MIRGunmetalNativeDispatcherControlV1';status='passed';checks=$script:checks;native_execution=$false;gameplay_acceptance=$false;operational_scope='disposable spool state-machine control only'}
