# MIR-GUNMETAL-NATIVE-DISPATCHER-V1
<#
Policy schema 1 contains one `approval`, not a general command queue.  Its
execution account, checkout, result root, request ID, review reference, exact
same-directory `Launch-Transient.sh`/`packet.json` hashes, expected
`result.json` kind, and `functional-not-timing` class are all required.

The scheduler reviews and installs that policy under the named account, then
runs `-Mode SubmitApproved`.  That writes one atomically renamed marker only.
The systemd path/timer runs `-Mode Consume`; it invokes only the hash-pinned
launcher and retains a terminal record.  A launcher return is never a pass:
success additionally needs its PID/invocation acknowledgement, the expected
controller result, and matching terminal systemd evidence.  Missing or
conflicting evidence is terminal `interrupted` and is never retried.

This is an operational hand-off, not a native test runner.  It never builds a
Factorio command, chooses an engine, changes a library, establishes gameplay
acceptance, or permits timing/performance work.
#>
[CmdletBinding()]
param(
  [ValidateSet('Consume','SubmitApproved','ValidatePolicy')][string]$Mode='Consume',
  [string]$PolicyPath=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Test-MIRGunmetalDispatcherContainedPath {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path,[switch]$AllowEqual)
  $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
  $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  $pathFull=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  if($AllowEqual-and$pathFull.Equals($rootFull,$comparison)){return $true}
  return $pathFull.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,$comparison)
}

function Resolve-MIRGunmetalDispatcherPath {
  param([Parameter(Mandatory)][string]$Path,[string]$Root='',[switch]$Directory,[switch]$MayNotExist)
  if([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathFullyQualified($Path)){throw '[mir-gunmetal-dispatcher-absolute-path]'}
  $full=[IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  if(-not [string]::IsNullOrWhiteSpace($Root) -and -not (Test-MIRGunmetalDispatcherContainedPath -Root $Root -Path $full -AllowEqual:$Directory)){
    throw '[mir-gunmetal-dispatcher-path-containment]'
  }
  $current=$full
  while($current){
    if(Test-Path -LiteralPath $current){
      $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw '[mir-gunmetal-dispatcher-reparse-point]'}
      if($current -ceq $full-and$Directory-and$item -isnot [IO.DirectoryInfo]){throw '[mir-gunmetal-dispatcher-directory-required]'}
      if($current -ceq $full-and-not$Directory-and-not$MayNotExist-and$item -isnot [IO.FileInfo]){throw '[mir-gunmetal-dispatcher-file-required]'}
    }
    $parent=[IO.Directory]::GetParent($current)
    $current=if($null-ne$parent){$parent.FullName}else{$null}
  }
  if(-not $MayNotExist-and-not(Test-Path -LiteralPath $full)){throw '[mir-gunmetal-dispatcher-path-missing]'}
  return $full
}

function Read-MIRGunmetalDispatcherJson {
  param([Parameter(Mandatory)][string]$Path,[ValidateRange(1,8388608)][int]$MaximumBytes=65536)
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($item -isnot [IO.FileInfo]-or($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0-or$item.Length -le 0-or$item.Length -gt $MaximumBytes){throw '[mir-gunmetal-dispatcher-json-identity]'}
  try{return [Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($item.FullName)).TrimStart([char]0xFEFF)|ConvertFrom-Json -ErrorAction Stop}catch{throw '[mir-gunmetal-dispatcher-json-parse]'}
}

function Get-MIRGunmetalDispatcherSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Assert-MIRGunmetalDispatcherText {
  param($Value,[Parameter(Mandatory)][string]$Failure,[ValidateRange(1,1024)][int]$MaximumLength=512)
  if($Value -isnot [string]-or[string]::IsNullOrWhiteSpace($Value)-or$Value.Length -gt $MaximumLength){throw $Failure}
  return [string]$Value
}

function Get-MIRGunmetalDispatcherPolicy {
  param([Parameter(Mandatory)][string]$Path)
  $path=Resolve-MIRGunmetalDispatcherPath -Path $Path
  $policy=Read-MIRGunmetalDispatcherJson -Path $path
  if($policy.schema -ne 1-or$policy.kind -cne'MIRGunmetalNativeDispatcherPolicyV1'){throw '[mir-gunmetal-dispatcher-policy-schema]'}
  $account=Assert-MIRGunmetalDispatcherText $policy.execution_account '[mir-gunmetal-dispatcher-policy-account]' 64
  if($account -cne [Environment]::UserName){throw '[mir-gunmetal-dispatcher-policy-account]'}
  $spool=Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $policy.spool_root '[mir-gunmetal-dispatcher-policy-spool]') -Directory -MayNotExist
  $checkout=Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $policy.allowed_checkout_root '[mir-gunmetal-dispatcher-policy-checkout]') -Directory
  $resultRoot=Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $policy.allowed_result_root '[mir-gunmetal-dispatcher-policy-result-root]') -Directory -MayNotExist
  $unit=Assert-MIRGunmetalDispatcherText $policy.native_unit '[mir-gunmetal-dispatcher-policy-unit]' 96
  if($unit -cne 'mir-native.service'){throw '[mir-gunmetal-dispatcher-policy-unit]'}
  $approval=$policy.approval
  if($null-eq$approval-or@($approval.PSObject.Properties).Count-lt10){throw '[mir-gunmetal-dispatcher-policy-approval]'}
  $id=Assert-MIRGunmetalDispatcherText $approval.request_id '[mir-gunmetal-dispatcher-policy-request-id]' 80
  if($id -cnotmatch '^[a-z0-9][a-z0-9-]{2,79}$'){throw '[mir-gunmetal-dispatcher-policy-request-id]'}
  if((Assert-MIRGunmetalDispatcherText $approval.owner '[mir-gunmetal-dispatcher-policy-owner]' 64) -cne $account){throw '[mir-gunmetal-dispatcher-policy-owner]'}
  $null=Assert-MIRGunmetalDispatcherText $approval.reviewed_by '[mir-gunmetal-dispatcher-policy-reviewer]' 128
  $null=Assert-MIRGunmetalDispatcherText $approval.review_reference '[mir-gunmetal-dispatcher-policy-review-reference]' 1024
  $executionClass=Assert-MIRGunmetalDispatcherText $approval.execution_class '[mir-gunmetal-dispatcher-policy-execution-class]' 64
  # This tiny consumer is for functional work only.  Timed/performance work
  # remains explicitly outside this unattended lane so it cannot overlap a
  # same-machine build, host suite, or separately accepted timing window.
  if($executionClass -cne 'functional-not-timing'){throw '[mir-gunmetal-dispatcher-policy-execution-class]'}
  foreach($field in @('launcher_relative_path','packet_relative_path')){
    $value=Assert-MIRGunmetalDispatcherText $approval.$field '[mir-gunmetal-dispatcher-policy-relative-path]' 512
    if([IO.Path]::IsPathFullyQualified($value)-or$value.Contains('..')-or$value.IndexOf([char]0)-ge0){throw '[mir-gunmetal-dispatcher-policy-relative-path]'}
  }
  $launcher=Resolve-MIRGunmetalDispatcherPath -Path (Join-Path $checkout $approval.launcher_relative_path) -Root $checkout
  $packet=Resolve-MIRGunmetalDispatcherPath -Path (Join-Path $checkout $approval.packet_relative_path) -Root $checkout
  if((Split-Path -Leaf $launcher) -cne 'Launch-Transient.sh'){throw '[mir-gunmetal-dispatcher-launcher-name]'}
  if((Split-Path -Leaf $packet) -cne 'packet.json'-or(Split-Path -Parent $launcher) -cne (Split-Path -Parent $packet)){throw '[mir-gunmetal-dispatcher-packet-location]'}
  foreach($field in @('launcher_sha256','packet_sha256')){if((Assert-MIRGunmetalDispatcherText $approval.$field '[mir-gunmetal-dispatcher-policy-hash]' 64) -cnotmatch '^[A-Fa-f0-9]{64}$'){throw '[mir-gunmetal-dispatcher-policy-hash]'}}
  if((Get-MIRGunmetalDispatcherSha256 $launcher) -cne $approval.launcher_sha256.ToUpperInvariant()){throw '[mir-gunmetal-dispatcher-launcher-hash]'}
  if((Get-MIRGunmetalDispatcherSha256 $packet) -cne $approval.packet_sha256.ToUpperInvariant()){throw '[mir-gunmetal-dispatcher-packet-hash]'}
  $result=Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $approval.result_path '[mir-gunmetal-dispatcher-policy-result-path]') -Root $resultRoot -MayNotExist
  if((Split-Path -Leaf $result) -cne 'result.json'){throw '[mir-gunmetal-dispatcher-result-name]'}
  $resultKind=Assert-MIRGunmetalDispatcherText $approval.result_kind '[mir-gunmetal-dispatcher-policy-result-kind]' 256
  return [pscustomobject][ordered]@{path=$path;account=$account;spool=$spool;checkout=$checkout;result_root=$resultRoot;unit=$unit;approval=[pscustomobject][ordered]@{request_id=$id;owner=$account;reviewed_by=$approval.reviewed_by;review_reference=$approval.review_reference;execution_class=$executionClass;launcher=$launcher;launcher_sha256=$approval.launcher_sha256.ToUpperInvariant();packet=$packet;packet_sha256=$approval.packet_sha256.ToUpperInvariant();result_path=$result;result_kind=$resultKind}}
}

function New-MIRGunmetalDispatcherDirectories {
  param([Parameter(Mandatory)]$Policy)
  foreach($name in @('incoming','accepted','terminal','rejected','state')){[IO.Directory]::CreateDirectory((Join-Path $Policy.spool $name))|Out-Null}
}

function Enter-MIRGunmetalDispatcherLock {
  param([Parameter(Mandatory)]$Policy)
  try { return [IO.File]::Open((Join-Path $Policy.spool 'state/dispatcher.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch [IO.IOException] { return $null }
}

function Write-MIRGunmetalDispatcherJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  $directory=Split-Path -Parent $Path;[IO.Directory]::CreateDirectory($directory)|Out-Null
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 32 -Compress)+"`n")
  $temporary=Join-Path $directory ('.'+[IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.new')
  $stream=$null
  try{$stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{if($null-ne$stream){$stream.Dispose()}}
  [IO.File]::Move($temporary,$Path,$true)
}

function Read-MIRGunmetalDispatcherSubmission {
  param([Parameter(Mandatory)][string]$Path)
  $submission=Read-MIRGunmetalDispatcherJson -Path $Path -MaximumBytes 8192
  if($submission.schema -ne 1-or$submission.kind -cne'MIRGunmetalNativeDispatcherSubmissionV1'){throw '[mir-gunmetal-dispatcher-submission-schema]'}
  $id=Assert-MIRGunmetalDispatcherText $submission.request_id '[mir-gunmetal-dispatcher-submission-id]' 80
  if($id -cnotmatch '^[a-z0-9][a-z0-9-]{2,79}$'){throw '[mir-gunmetal-dispatcher-submission-id]'}
  return [pscustomobject]@{request_id=$id;submitted_utc=$submission.submitted_utc}
}

function Move-MIRGunmetalDispatcherSubmission {
  param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$DestinationDirectory)
  $target=Join-Path $DestinationDirectory (Split-Path -Leaf $Source)
  if(Test-Path -LiteralPath $target){throw '[mir-gunmetal-dispatcher-submission-duplicate]'}
  [IO.File]::Move($Source,$target)
  return $target
}

function Invoke-MIRGunmetalDispatcherSystemctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $lines=@(& /usr/bin/systemctl --user @Arguments 2>&1)
  return [pscustomobject]@{exit_code=$LASTEXITCODE;lines=@($lines|ForEach-Object{[string]$_})}
}

function Invoke-MIRGunmetalDispatcherLauncher {
  param([Parameter(Mandatory)][string]$Path)
  $lines=@(& /usr/bin/bash $Path 2>&1)
  return [pscustomobject]@{exit_code=$LASTEXITCODE;lines=@($lines|ForEach-Object{[string]$_})}
}

function Get-MIRGunmetalDispatcherUnit {
  param([Parameter(Mandatory)][string]$Unit)
  $response=Invoke-MIRGunmetalDispatcherSystemctl -Arguments @('show',$Unit,'--no-pager','--property=LoadState','--property=ActiveState','--property=SubState','--property=MainPID','--property=InvocationID','--property=Result','--property=ExecMainCode','--property=ExecMainStatus')
  $values=@{};foreach($line in $response.lines){$split=$line.IndexOf('=');if($split-gt0){$values[$line.Substring(0,$split)]=$line.Substring($split+1)}}
  $load=if($values.ContainsKey('LoadState')){[string]$values.LoadState}else{'not-found'}
  return [pscustomobject]@{found=($response.exit_code-eq0-and$load-cne'not-found');load_state=$load;active_state=if($values.ContainsKey('ActiveState')){[string]$values.ActiveState}else{''};sub_state=if($values.ContainsKey('SubState')){[string]$values.SubState}else{''};main_pid=if($values.ContainsKey('MainPID')){[string]$values.MainPID}else{'0'};invocation_id=if($values.ContainsKey('InvocationID')){[string]$values.InvocationID}else{''};result=if($values.ContainsKey('Result')){[string]$values.Result}else{''};exec_main_code=if($values.ContainsKey('ExecMainCode')){[string]$values.ExecMainCode}else{''};exec_main_status=if($values.ContainsKey('ExecMainStatus')){[string]$values.ExecMainStatus}else{''}}
}

function Get-MIRGunmetalDispatcherJournalTerminal {
  param([Parameter(Mandatory)][string]$InvocationId)
  if($InvocationId -cnotmatch '^[A-Fa-f0-9]{32}$'){throw '[mir-gunmetal-dispatcher-invocation-id]'}
  $lines=@(& /usr/bin/journalctl --user --no-pager --output=json "_SYSTEMD_INVOCATION_ID=$InvocationId" 2>$null)
  $exit=$null
  foreach($line in $lines){
    try{$entry=$line|ConvertFrom-Json -ErrorAction Stop}catch{continue}
    $message=if($entry.PSObject.Properties['MESSAGE']){[string]$entry.MESSAGE}else{''}
    if($message-match'Main process exited, code=exited, status=(\d+)/'){$exit=[int]$Matches[1]}
  }
  return [pscustomobject]@{observed=($null-ne$exit);exit_code=$exit}
}

function Get-MIRGunmetalDispatcherResult {
  param([Parameter(Mandatory)]$Approval)
  if(-not(Test-Path -LiteralPath $Approval.result_path)){return [pscustomobject]@{exists=$false;valid=$false;sha256='';reason='result-absent'}}
  try{
    $result=Read-MIRGunmetalDispatcherJson -Path $Approval.result_path -MaximumBytes 8388608
    $kind=if($result.PSObject.Properties['kind']){[string]$result.kind}else{''}
    $status=if($result.PSObject.Properties['status']){[string]$result.status}else{''}
    if($kind-cne$Approval.result_kind-or$status-cne'passed'){return [pscustomobject]@{exists=$true;valid=$false;sha256=(Get-MIRGunmetalDispatcherSha256 $Approval.result_path);reason='result-contract'}}
    return [pscustomobject]@{exists=$true;valid=$true;sha256=(Get-MIRGunmetalDispatcherSha256 $Approval.result_path);reason='passed'}
  }catch{return [pscustomobject]@{exists=$true;valid=$false;sha256='';reason='result-invalid'}}
}

function New-MIRGunmetalDispatcherTerminal {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Running,[Parameter(Mandatory)][ValidateSet('succeeded','failed','interrupted','rejected')][string]$Status,[Parameter(Mandatory)][string]$Reason,$Unit=$null,$Result=$null)
  $path=Join-Path $Policy.spool ('terminal/'+$Running.request_id+'.json')
  if(Test-Path -LiteralPath $path){return}
  $record=[ordered]@{kind='MIRGunmetalNativeDispatcherTerminalV1';request_id=$Running.request_id;status=$Status;reason=$Reason;recorded_utc=[datetime]::UtcNow.ToString('o');packet_sha256=$Policy.approval.packet_sha256;launcher_sha256=$Policy.approval.launcher_sha256;operational_scope='dispatcher acknowledgement and terminal custody only; not Factorio gameplay, save, performance, or release acceptance.';review_reference=$Policy.approval.review_reference}
  if($null-ne$Running.launch){$record.launch=$Running.launch};if($null-ne$Unit){$record.unit=$Unit};if($null-ne$Result){$record.result=$Result}
  Write-MIRGunmetalDispatcherJson -Path $path -Value $record
  $active=Join-Path $Policy.spool 'state/running.json';if(Test-Path -LiteralPath $active){Remove-Item -LiteralPath $active -Force}
}

function Reconcile-MIRGunmetalDispatcherRunning {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Running)
  if($Running.request_id-cne$Policy.approval.request_id-or$Running.packet_sha256-cne$Policy.approval.packet_sha256-or$Running.launcher_sha256-cne$Policy.approval.launcher_sha256){throw '[mir-gunmetal-dispatcher-running-identity]'}
  $unit=Get-MIRGunmetalDispatcherUnit -Unit $Policy.unit
  $expected=[string]$Running.launch.start_ack.invocation_id
  if($unit.found-and$unit.invocation_id-cne$expected){New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status interrupted -Reason 'native-unit-invocation-replaced' -Unit $unit;return}
  if($unit.found-and$unit.active_state-in@('active','activating','deactivating')){return}
  $result=Get-MIRGunmetalDispatcherResult -Approval $Policy.approval
  if($unit.found){
    $good=($unit.result-ceq'success'-and$unit.exec_main_code-ceq'exited'-and$unit.exec_main_status-ceq'0'-and$result.valid)
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status $(if($good){'succeeded'}else{'failed'}) -Reason $(if($good){'unit-and-result-passed'}else{'unit-terminal-or-result-failed'}) -Unit $unit -Result $result
    return
  }
  $journal=Get-MIRGunmetalDispatcherJournalTerminal -InvocationId $expected
  if(-not$journal.observed){New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status interrupted -Reason 'unit-unloaded-without-terminal-journal' -Result $result;return}
  $good=($journal.exit_code-eq0-and$result.valid)
  New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status $(if($good){'succeeded'}else{'failed'}) -Reason $(if($good){'journal-and-result-passed'}else{'journal-terminal-or-result-failed'}) -Result ([ordered]@{result=$result;journal=$journal})
}

function Start-MIRGunmetalDispatcherApprovedSubmission {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Submission)
  if($Submission.request_id-cne$Policy.approval.request_id){throw '[mir-gunmetal-dispatcher-submission-not-approved]'}
  $record=[pscustomobject]@{request_id=$Submission.request_id;launch=$null}
  # Rehash immediately before the only launch boundary.  Validation at policy
  # read time alone would leave a mutable-checkout race between a timer wakeup
  # and the reviewed launch.
  try {
    if((Get-MIRGunmetalDispatcherSha256 $Policy.approval.launcher) -cne $Policy.approval.launcher_sha256){throw '[mir-gunmetal-dispatcher-launcher-hash]'}
    if((Get-MIRGunmetalDispatcherSha256 $Policy.approval.packet) -cne $Policy.approval.packet_sha256){throw '[mir-gunmetal-dispatcher-packet-hash]'}
    if(Test-Path -LiteralPath $Policy.approval.result_path){throw '[mir-gunmetal-dispatcher-result-preexists]'}
  } catch {
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status rejected -Reason 'prelaunch-pinned-input-refused'
    return
  }
  $before=Get-MIRGunmetalDispatcherUnit -Unit $Policy.unit
  if($before.found){New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status interrupted -Reason 'native-unit-busy-before-launch' -Unit $before;return}
  $launched=Invoke-MIRGunmetalDispatcherLauncher -Path $Policy.approval.launcher
  $launch=[ordered]@{acknowledged_utc=[datetime]::UtcNow.ToString('o');launcher_exit_code=$launched.exit_code;launcher_output=@($launched.lines|Select-Object -Last 16)}
  if($launched.exit_code-ne0){
    $record.launch=$launch;New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status failed -Reason 'reviewed-launcher-refused-before-acknowledgement';return
  }
  $after=Get-MIRGunmetalDispatcherUnit -Unit $Policy.unit
  if(-not$after.found-or$after.active_state-notin@('active','activating')-or$after.main_pid-notmatch'^[1-9][0-9]*$'-or$after.invocation_id-cnotmatch'^[A-Fa-f0-9]{32}$'){
    $record.launch=$launch;New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status interrupted -Reason 'launcher-returned-without-native-start-acknowledgement' -Unit $after;return
  }
  $launch.start_ack=[ordered]@{pid=[int]$after.main_pid;invocation_id=$after.invocation_id.ToLowerInvariant();active_state=$after.active_state;sub_state=$after.sub_state}
  $running=[ordered]@{kind='MIRGunmetalNativeDispatcherRunningV1';request_id=$Submission.request_id;packet_sha256=$Policy.approval.packet_sha256;launcher_sha256=$Policy.approval.launcher_sha256;started_utc=[datetime]::UtcNow.ToString('o');launch=$launch}
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $Policy.spool 'state/running.json') -Value $running
}

function Invoke-MIRGunmetalDispatcherConsume {
  param([Parameter(Mandatory)]$Policy)
  New-MIRGunmetalDispatcherDirectories -Policy $Policy
  $lock=Enter-MIRGunmetalDispatcherLock -Policy $Policy;if($null-eq$lock){return [pscustomobject]@{status='busy';side_effects='none'}}
  try{
    $runningPath=Join-Path $Policy.spool 'state/running.json'
    if(Test-Path -LiteralPath $runningPath){Reconcile-MIRGunmetalDispatcherRunning -Policy $Policy -Running (Read-MIRGunmetalDispatcherJson -Path $runningPath);return [pscustomobject]@{status='reconciled';side_effects='state-only'}}
    $incoming=@(Get-ChildItem -LiteralPath (Join-Path $Policy.spool 'incoming') -File -Filter '*.json' -Force | Sort-Object Name)
    if($incoming.Count-eq0){return [pscustomobject]@{status='idle';side_effects='none'}}
    if($incoming.Count-ne1){
      foreach($file in $incoming){Move-MIRGunmetalDispatcherSubmission -Source $file.FullName -DestinationDirectory (Join-Path $Policy.spool 'rejected')|Out-Null}
      return [pscustomobject]@{status='rejected-ambiguous-submissions';side_effects='spool-only'}
    }
    $file=$incoming[0];$submission=$null
    try{$submission=Read-MIRGunmetalDispatcherSubmission -Path $file.FullName;if($submission.request_id-cne$Policy.approval.request_id){throw '[mir-gunmetal-dispatcher-submission-not-approved]'}}catch{
      Move-MIRGunmetalDispatcherSubmission -Source $file.FullName -DestinationDirectory (Join-Path $Policy.spool 'rejected')|Out-Null
      return [pscustomobject]@{status='rejected-submission';side_effects='spool-only'}
    }
    $terminal=Join-Path $Policy.spool ('terminal/'+$submission.request_id+'.json')
    if(Test-Path -LiteralPath $terminal){Move-MIRGunmetalDispatcherSubmission -Source $file.FullName -DestinationDirectory (Join-Path $Policy.spool 'rejected')|Out-Null;return [pscustomobject]@{status='rejected-terminal-duplicate';side_effects='spool-only'}}
    Move-MIRGunmetalDispatcherSubmission -Source $file.FullName -DestinationDirectory (Join-Path $Policy.spool 'accepted')|Out-Null
    Start-MIRGunmetalDispatcherApprovedSubmission -Policy $Policy -Submission $submission
    return [pscustomobject]@{status='submitted';side_effects='spool-and-reviewed-launcher'}
  }finally{$lock.Dispose()}
}

function Submit-MIRGunmetalDispatcherApproved {
  param([Parameter(Mandatory)]$Policy)
  New-MIRGunmetalDispatcherDirectories -Policy $Policy
  $lock=Enter-MIRGunmetalDispatcherLock -Policy $Policy;if($null-eq$lock){return [pscustomobject]@{status='busy';side_effects='none'}}
  try{
    $incoming=Join-Path $Policy.spool 'incoming'
    $accepted=Join-Path $Policy.spool ('accepted/'+$Policy.approval.request_id+'.json')
    $terminal=Join-Path $Policy.spool ('terminal/'+$Policy.approval.request_id+'.json')
    $running=Join-Path $Policy.spool 'state/running.json'
    if((Get-ChildItem -LiteralPath $incoming -File -Filter '*.json' -Force|Measure-Object).Count-ne0-or(Test-Path -LiteralPath $accepted)-or(Test-Path -LiteralPath $terminal)-or(Test-Path -LiteralPath $running)){
      throw '[mir-gunmetal-dispatcher-submission-slot-not-empty]'
    }
    $path=Join-Path $incoming ($Policy.approval.request_id+'.json')
    $submission=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherSubmissionV1';request_id=$Policy.approval.request_id;submitted_utc=[datetime]::UtcNow.ToString('o');review_reference=$Policy.approval.review_reference}
    $directory=Split-Path -Parent $path;$temporary=Join-Path $directory ('.'+[guid]::NewGuid().ToString('N')+'.new')
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($submission|ConvertTo-Json -Compress)+"`n")
    $stream=$null
    try{$stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{if($null-ne$stream){$stream.Dispose()}}
    [IO.File]::Move($temporary,$path)
    return [pscustomobject]@{kind='MIRGunmetalNativeDispatcherSubmissionV1';status='queued';request_id=$Policy.approval.request_id;side_effects='one atomic spool marker only; no launcher or native process was started.'}
  }finally{$lock.Dispose()}
}

if($MyInvocation.InvocationName -ne '.') {
  if([string]::IsNullOrWhiteSpace($PolicyPath)){throw '[mir-gunmetal-dispatcher-policy-required]'}
  if($Mode-ceq'ValidatePolicy'){
    $policy=Get-MIRGunmetalDispatcherPolicy -Path $PolicyPath
    [pscustomobject]@{kind='MIRGunmetalNativeDispatcherPolicyValidationV1';status='passed';execution_account=$policy.account;approved_request=$policy.approval.request_id;operational_scope='validation only; does not launch a native job.'}
    return
  }
  if(-not $IsLinux){throw '[mir-gunmetal-dispatcher-linux-required]'}
  $policy=Get-MIRGunmetalDispatcherPolicy -Path $PolicyPath
  if($Mode-ceq'SubmitApproved'){Submit-MIRGunmetalDispatcherApproved -Policy $policy}else{Invoke-MIRGunmetalDispatcherConsume -Policy $policy}
}
