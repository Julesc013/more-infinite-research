# MIR-GUNMETAL-NATIVE-DISPATCHER-V1
<#
Policy schema 1 contains one reviewed approval, not a general command queue.
Its execution account, checkout, result root, request ID, review reference,
exact same-directory `Launch-Transient.sh`/`packet.json` hashes, expected
`result.json` kind, and `functional-not-timing` class are all required.

`SubmitApproved` makes one immutable request snapshot and atomically points at
it. `SubmitSuccessor` may make one further distinct snapshot while one request
is active. The systemd path/timer runs `-Mode Consume`; it invokes only that
hash-pinned launcher and retains a terminal record. A launcher return is never
a pass: success additionally needs its PID/invocation acknowledgement, the
expected packet-bound controller result, and explicit terminal systemd
evidence. Missing or conflicting evidence is terminal `interrupted` and is
never retried. A held successor requires an explicit disposition reference;
the existing exact snapshot may be released, or a different reviewed snapshot
may replace it. The durable intent closes the marker-to-launch acknowledgement
window without silently relaunching an uncertain invocation.

This is an operational hand-off, not a native test runner.  It never builds a
Factorio command, chooses an engine, changes a library, establishes gameplay
acceptance, or permits timing/performance work.
#>
[CmdletBinding()]
param(
  [ValidateSet('Consume','SubmitApproved','SubmitSuccessor','ReplaceHeldSuccessor','ValidatePolicy')][string]$Mode='Consume',
  [string]$PolicyPath='',
  [string]$SuccessorPolicyPath='',
  [string]$DispositionReference=''
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
  $path = Resolve-MIRGunmetalDispatcherPath -Path $Path
  $policy = Read-MIRGunmetalDispatcherJson -Path $path
  if ($policy.schema -ne 1 -or $policy.kind -cne 'MIRGunmetalNativeDispatcherPolicyV1') {
    throw '[mir-gunmetal-dispatcher-policy-schema]'
  }
  $account = Assert-MIRGunmetalDispatcherText $policy.execution_account '[mir-gunmetal-dispatcher-policy-account]' 64
  if ($account -cne [Environment]::UserName) { throw '[mir-gunmetal-dispatcher-policy-account]' }
  $spool = Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $policy.spool_root '[mir-gunmetal-dispatcher-policy-spool]') -Directory -MayNotExist
  $checkout = Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $policy.allowed_checkout_root '[mir-gunmetal-dispatcher-policy-checkout]') -Directory
  $resultRoot = Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $policy.allowed_result_root '[mir-gunmetal-dispatcher-policy-result-root]') -Directory -MayNotExist
  $unit = Assert-MIRGunmetalDispatcherText $policy.native_unit '[mir-gunmetal-dispatcher-policy-unit]' 96
  if ($unit -cne 'mir-native.service') { throw '[mir-gunmetal-dispatcher-policy-unit]' }
  $approval = $policy.approval
  if ($null -eq $approval -or @($approval.PSObject.Properties).Count -lt 10) {
    throw '[mir-gunmetal-dispatcher-policy-approval]'
  }
  $id = Assert-MIRGunmetalDispatcherText $approval.request_id '[mir-gunmetal-dispatcher-policy-request-id]' 80
  if ($id -cnotmatch '^[a-z0-9][a-z0-9-]{2,79}$') { throw '[mir-gunmetal-dispatcher-policy-request-id]' }
  if ((Assert-MIRGunmetalDispatcherText $approval.owner '[mir-gunmetal-dispatcher-policy-owner]' 64) -cne $account) {
    throw '[mir-gunmetal-dispatcher-policy-owner]'
  }
  $null = Assert-MIRGunmetalDispatcherText $approval.reviewed_by '[mir-gunmetal-dispatcher-policy-reviewer]' 128
  $null = Assert-MIRGunmetalDispatcherText $approval.review_reference '[mir-gunmetal-dispatcher-policy-review-reference]' 1024
  $executionClass = Assert-MIRGunmetalDispatcherText $approval.execution_class '[mir-gunmetal-dispatcher-policy-execution-class]' 64
  # This tiny consumer is for functional work only.  Timed/performance work
  # remains explicitly outside this unattended lane so it cannot overlap a
  # same-machine build, host suite, or separately accepted timing window.
  if ($executionClass -cne 'functional-not-timing') { throw '[mir-gunmetal-dispatcher-policy-execution-class]' }
  foreach ($field in @('launcher_relative_path','packet_relative_path')) {
    $value = Assert-MIRGunmetalDispatcherText $approval.$field '[mir-gunmetal-dispatcher-policy-relative-path]' 512
    if ([IO.Path]::IsPathFullyQualified($value) -or $value.Contains('..') -or $value.IndexOf([char]0) -ge 0) {
      throw '[mir-gunmetal-dispatcher-policy-relative-path]'
    }
  }
  $launcher = Resolve-MIRGunmetalDispatcherPath -Path (Join-Path $checkout $approval.launcher_relative_path) -Root $checkout
  $packet = Resolve-MIRGunmetalDispatcherPath -Path (Join-Path $checkout $approval.packet_relative_path) -Root $checkout
  if ((Split-Path -Leaf $launcher) -cne 'Launch-Transient.sh') { throw '[mir-gunmetal-dispatcher-launcher-name]' }
  if ((Split-Path -Leaf $packet) -cne 'packet.json' -or (Split-Path -Parent $launcher) -cne (Split-Path -Parent $packet)) {
    throw '[mir-gunmetal-dispatcher-packet-location]'
  }
  foreach ($field in @('launcher_sha256','packet_sha256')) {
    if ((Assert-MIRGunmetalDispatcherText $approval.$field '[mir-gunmetal-dispatcher-policy-hash]' 64) -cnotmatch '^[A-Fa-f0-9]{64}$') {
      throw '[mir-gunmetal-dispatcher-policy-hash]'
    }
  }
  if ((Get-MIRGunmetalDispatcherSha256 $launcher) -cne $approval.launcher_sha256.ToUpperInvariant()) { throw '[mir-gunmetal-dispatcher-launcher-hash]' }
  if ((Get-MIRGunmetalDispatcherSha256 $packet) -cne $approval.packet_sha256.ToUpperInvariant()) { throw '[mir-gunmetal-dispatcher-packet-hash]' }
  $result = Resolve-MIRGunmetalDispatcherPath -Path (Assert-MIRGunmetalDispatcherText $approval.result_path '[mir-gunmetal-dispatcher-policy-result-path]') -Root $resultRoot -MayNotExist
  if ((Split-Path -Leaf $result) -cne 'result.json') { throw '[mir-gunmetal-dispatcher-result-name]' }
  $resultKind = Assert-MIRGunmetalDispatcherText $approval.result_kind '[mir-gunmetal-dispatcher-policy-result-kind]' 256
  return [pscustomobject][ordered]@{
    path = $path
    account = $account
    spool = $spool
    checkout = $checkout
    result_root = $resultRoot
    unit = $unit
    approval = [pscustomobject][ordered]@{
      request_id = $id
      owner = $account
      reviewed_by = $approval.reviewed_by
      review_reference = $approval.review_reference
      execution_class = $executionClass
      launcher = $launcher
      launcher_sha256 = $approval.launcher_sha256.ToUpperInvariant()
      packet = $packet
      packet_sha256 = $approval.packet_sha256.ToUpperInvariant()
      result_path = $result
      result_kind = $resultKind
    }
  }
}

function New-MIRGunmetalDispatcherDirectories {
  param([Parameter(Mandatory)]$Policy)
  foreach($name in @('requests','terminal','held','state')) {
    [IO.Directory]::CreateDirectory((Join-Path $Policy.spool $name)) | Out-Null
  }
}

function Enter-MIRGunmetalDispatcherLock {
  param([Parameter(Mandatory)]$Policy)
  try { return [IO.File]::Open((Join-Path $Policy.spool 'state/dispatcher.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) } catch [IO.IOException] { return $null }
}

function Write-MIRGunmetalDispatcherBytes {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes,[switch]$Replace)
  $directory=Split-Path -Parent $Path
  [IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary=Join-Path $directory ('.'+[IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.new')
  $stream=$null
  try {
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $stream.Write($Bytes,0,$Bytes.Length)
    $stream.Flush($true)
  } finally { if($null-ne$stream){$stream.Dispose()} }
  if($Replace){[IO.File]::Move($temporary,$Path,$true)}else{[IO.File]::Move($temporary,$Path)}
}

function Write-MIRGunmetalDispatcherJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value,[switch]$NewOnly)
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 32 -Compress)+"`n")
  Write-MIRGunmetalDispatcherBytes -Path $Path -Bytes $bytes -Replace:(-not$NewOnly)
}

function Assert-MIRGunmetalDispatcherSchedulingIdentity {
  param([Parameter(Mandatory)]$Base,[Parameter(Mandatory)]$Candidate)
  foreach($field in @('account','spool','checkout','result_root','unit')) {
    if([string]$Base.$field -cne [string]$Candidate.$field){throw '[mir-gunmetal-dispatcher-successor-scheduling-identity]'}
  }
}

function Get-MIRGunmetalDispatcherRequestDirectory {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$RequestId)
  if($RequestId -cnotmatch '^[a-z0-9][a-z0-9-]{2,79}$'){throw '[mir-gunmetal-dispatcher-request-id]'}
  return Join-Path $Policy.spool ('requests/'+$RequestId)
}

function New-MIRGunmetalDispatcherRequestSnapshot {
  param([Parameter(Mandatory)]$BasePolicy,[Parameter(Mandatory)]$CandidatePolicy,[string]$PredecessorRequestId='',[string]$DispositionReference='')
  Assert-MIRGunmetalDispatcherSchedulingIdentity -Base $BasePolicy -Candidate $CandidatePolicy
  $id=$CandidatePolicy.approval.request_id
  $directory=Get-MIRGunmetalDispatcherRequestDirectory -Policy $BasePolicy -RequestId $id
  $policyCopy=Join-Path $directory 'policy.json'
  $requestPath=Join-Path $directory 'request.json'
  $sourceBytes=[IO.File]::ReadAllBytes($CandidatePolicy.path)
  $sourceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes))
  if(Test-Path -LiteralPath $requestPath){throw '[mir-gunmetal-dispatcher-request-exists]'}
  if(Test-Path -LiteralPath $directory) {
    # A previous process may have died after copying the policy but before its
    # final request marker. Resume only byte-identical own preparation.
    if(-not(Test-Path -LiteralPath $policyCopy) -or (Get-MIRGunmetalDispatcherSha256 $policyCopy) -cne $sourceHash){throw '[mir-gunmetal-dispatcher-request-partial-conflict]'}
  } else { [IO.Directory]::CreateDirectory($directory) | Out-Null }
  if(-not(Test-Path -LiteralPath $policyCopy)){Write-MIRGunmetalDispatcherBytes -Path $policyCopy -Bytes $sourceBytes -Replace:$false}
  $request=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherRequestSnapshotV1';request_id=$id;created_utc=[datetime]::UtcNow.ToString('o');policy_sha256=$sourceHash;packet_sha256=$CandidatePolicy.approval.packet_sha256;launcher_sha256=$CandidatePolicy.approval.launcher_sha256;result_path=$CandidatePolicy.approval.result_path;result_kind=$CandidatePolicy.approval.result_kind;predecessor_request_id=$PredecessorRequestId;disposition_reference=$DispositionReference}
  # request.json is the commit marker. Consumers ignore an incomplete directory.
  Write-MIRGunmetalDispatcherJson -Path $requestPath -Value $request -NewOnly
  return [pscustomobject]@{request_id=$id;policy_sha256=$sourceHash;path=$requestPath}
}

function Get-MIRGunmetalDispatcherRequestSnapshot {
  param([Parameter(Mandatory)]$BasePolicy,[Parameter(Mandatory)][string]$RequestId)
  $directory=Get-MIRGunmetalDispatcherRequestDirectory -Policy $BasePolicy -RequestId $RequestId
  $request=Read-MIRGunmetalDispatcherJson -Path (Join-Path $directory 'request.json') -MaximumBytes 16384
  if($request.schema-ne1-or$request.kind-cne'MIRGunmetalNativeDispatcherRequestSnapshotV1'-or$request.request_id-cne$RequestId){throw '[mir-gunmetal-dispatcher-request-schema]'}
  if($request.policy_sha256 -isnot [string]-or$request.policy_sha256 -cnotmatch '^[A-Fa-f0-9]{64}$'){throw '[mir-gunmetal-dispatcher-request-policy-hash]'}
  $policyPath=Join-Path $directory 'policy.json'
  if((Get-MIRGunmetalDispatcherSha256 $policyPath) -cne $request.policy_sha256.ToUpperInvariant()){throw '[mir-gunmetal-dispatcher-request-policy-hash]'}
  $policy=Get-MIRGunmetalDispatcherPolicy -Path $policyPath
  Assert-MIRGunmetalDispatcherSchedulingIdentity -Base $BasePolicy -Candidate $policy
  foreach($field in @('request_id','packet_sha256','launcher_sha256','result_path','result_kind')) {
    if([string]$request.$field -cne [string]$policy.approval.$field){throw '[mir-gunmetal-dispatcher-request-identity]'}
  }
  return [pscustomobject]@{request=$request;policy=$policy}
}

function Get-MIRGunmetalDispatcherStateRecord {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$Name)
  $path=Join-Path $Policy.spool ('state/'+$Name+'.json')
  if(-not(Test-Path -LiteralPath $path)){return $null}
  return Read-MIRGunmetalDispatcherJson -Path $path -MaximumBytes 65536
}

function Set-MIRGunmetalDispatcherPending {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Snapshot,[string]$PredecessorRequestId='',[string]$DispositionReference='')
  $value=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherPendingV1';request_id=$Snapshot.request_id;policy_sha256=$Snapshot.policy_sha256;queued_utc=[datetime]::UtcNow.ToString('o');predecessor_request_id=$PredecessorRequestId;disposition_reference=$DispositionReference}
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $Policy.spool 'state/pending.json') -Value $value
}

function Get-MIRGunmetalDispatcherPending {
  param([Parameter(Mandatory)]$Policy)
  $pending=Get-MIRGunmetalDispatcherStateRecord -Policy $Policy -Name pending
  if($null-eq$pending){return $null}
  if($pending.schema-ne1-or$pending.kind-cne'MIRGunmetalNativeDispatcherPendingV1'-or$pending.request_id-isnot[string]-or$pending.policy_sha256-isnot[string]){throw '[mir-gunmetal-dispatcher-pending-schema]'}
  $snapshot=Get-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $Policy -RequestId $pending.request_id
  if($snapshot.request.policy_sha256 -cne $pending.policy_sha256){throw '[mir-gunmetal-dispatcher-pending-identity]'}
  return [pscustomobject]@{pending=$pending;snapshot=$snapshot}
}

function Clear-MIRGunmetalDispatcherPending {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)][string]$RequestId)
  $path=Join-Path $Policy.spool 'state/pending.json'
  if(Test-Path -LiteralPath $path) {
    $pending=Get-MIRGunmetalDispatcherPending -Policy $Policy
    if($pending.pending.request_id-ceq$RequestId){Remove-Item -LiteralPath $path -Force}
  }
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
  $response = Invoke-MIRGunmetalDispatcherSystemctl -Arguments @(
    'show', $Unit, '--no-pager',
    '--property=LoadState', '--property=ActiveState', '--property=SubState',
    '--property=MainPID', '--property=InvocationID', '--property=Result',
    '--property=ExecMainCode', '--property=ExecMainStatus'
  )
  $values = @{}
  foreach ($line in $response.lines) {
    $split = $line.IndexOf('=')
    if ($split -gt 0) { $values[$line.Substring(0,$split)] = $line.Substring($split+1) }
  }
  $loadObserved = $values.ContainsKey('LoadState')
  $load = if ($loadObserved) { [string]$values.LoadState } else { '' }
  # Only a successful query with the actual LoadState key establishes absence.
  # An empty/partial response or an error is intentionally ambiguous.
  $absenceConfirmed = ($response.exit_code -eq 0 -and $loadObserved -and $load -ceq 'not-found')
  $found = ($response.exit_code -eq 0 -and $loadObserved -and $load -cne 'not-found')
  return [pscustomobject]@{
    query_succeeded = ($response.exit_code -eq 0)
    load_state_observed = $loadObserved
    absence_confirmed = $absenceConfirmed
    found = $found
    ambiguous = (-not $found -and -not $absenceConfirmed)
    load_state = $load
    active_state = if ($values.ContainsKey('ActiveState')) { [string]$values.ActiveState } else { '' }
    sub_state = if ($values.ContainsKey('SubState')) { [string]$values.SubState } else { '' }
    main_pid = if ($values.ContainsKey('MainPID')) { [string]$values.MainPID } else { '' }
    invocation_id = if ($values.ContainsKey('InvocationID')) { [string]$values.InvocationID } else { '' }
    result = if ($values.ContainsKey('Result')) { [string]$values.Result } else { '' }
    exec_main_code = if ($values.ContainsKey('ExecMainCode')) { [string]$values.ExecMainCode } else { '' }
    exec_main_status = if ($values.ContainsKey('ExecMainStatus')) { [string]$values.ExecMainStatus } else { '' }
  }
}

function Get-MIRGunmetalDispatcherJournalTerminal {
  param([Parameter(Mandatory)][string]$InvocationId)
  if($InvocationId -cnotmatch '^[A-Fa-f0-9]{32}$'){throw '[mir-gunmetal-dispatcher-invocation-id]'}
  # A user-manager unit records USER_INVOCATION_ID, not the system-manager
  # _SYSTEMD_INVOCATION_ID field. The collected-unit sample intentionally
  # showed only a started message, so absence of an explicit main-process exit
  # remains interruption rather than a manufactured success.
  $lines=@(& /usr/bin/journalctl --user --no-pager --output=json "USER_INVOCATION_ID=$InvocationId" 2>$null)
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
    $packet=if($result.PSObject.Properties['packet_sha256']){[string]$result.packet_sha256}else{''}
    if($kind-cne$Approval.result_kind-or$status-cne'passed'-or$packet-cne$Approval.packet_sha256){return [pscustomobject]@{exists=$true;valid=$false;sha256=(Get-MIRGunmetalDispatcherSha256 $Approval.result_path);reason='result-contract-or-packet'}}
    return [pscustomobject]@{exists=$true;valid=$true;sha256=(Get-MIRGunmetalDispatcherSha256 $Approval.result_path);reason='passed'}
  }catch{return [pscustomobject]@{exists=$true;valid=$false;sha256='';reason='result-invalid'}}
}

function New-MIRGunmetalDispatcherTerminal {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Running,[Parameter(Mandatory)][ValidateSet('succeeded','failed','interrupted','rejected')][string]$Status,[Parameter(Mandatory)][string]$Reason,$Unit=$null,$Result=$null)
  $path = Join-Path $Policy.spool ('terminal/'+$Running.request_id+'.json')
  if (Test-Path -LiteralPath $path) { return }
  $record = [ordered]@{
    kind = 'MIRGunmetalNativeDispatcherTerminalV2'
    request_id = $Running.request_id
    status = $Status
    reason = $Reason
    recorded_utc = [datetime]::UtcNow.ToString('o')
    packet_sha256 = $Policy.approval.packet_sha256
    launcher_sha256 = $Policy.approval.launcher_sha256
    request_snapshot_sha256 = $Running.request_snapshot_sha256
    dispatch_id = $Running.dispatch_id
    operational_scope = 'dispatcher acknowledgement and terminal custody only; not Factorio gameplay, save, performance, or release acceptance.'
    review_reference = $Policy.approval.review_reference
  }
  if ($null -ne $Running.launch) { $record.launch = $Running.launch }
  if ($null -ne $Unit) { $record.unit = $Unit }
  if ($null -ne $Result) { $record.result = $Result }
  if ($Status -ceq 'succeeded') {
    $resultRecord = if ($Result -is [Collections.IDictionary] -and $Result.Contains('result')) {
      $Result['result']
    } elseif ($Result.PSObject.Properties['result']) {
      $Result.result
    } else {
      $Result
    }
    $journal = if ($Result -is [Collections.IDictionary] -and $Result.Contains('journal')) {
      $Result['journal']
    } elseif ($Result.PSObject.Properties['journal']) {
      $Result.journal
    } else {
      $null
    }
    $envelope = [ordered]@{
      kind = 'MIRGunmetalNativeDispatcherCompletionEnvelopeV1'
      request_id = $Running.request_id
      dispatch_id = $Running.dispatch_id
      packet_sha256 = $Policy.approval.packet_sha256
      result_path = $Policy.approval.result_path
      result_sha256 = $resultRecord.sha256
      invocation_id = $Running.launch.start_ack.invocation_id
      terminal_evidence = $journal
      created_utc = [datetime]::UtcNow.ToString('o')
    }
    $envelopePath = Join-Path (Get-MIRGunmetalDispatcherRequestDirectory -Policy $Policy -RequestId $Running.request_id) ('completion-'+$Running.dispatch_id+'.json')
    Write-MIRGunmetalDispatcherJson -Path $envelopePath -Value $envelope -NewOnly
    $record.completion_envelope_path=$envelopePath
    $record.completion_envelope_sha256=Get-MIRGunmetalDispatcherSha256 $envelopePath
  }
  Write-MIRGunmetalDispatcherJson -Path $path -Value $record
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $Policy.spool 'state/last-terminal.json') -Value ([ordered]@{
    request_id = $Running.request_id
    status = $Status
    reason = $Reason
    packet_sha256 = $Policy.approval.packet_sha256
    terminal_path = $path
    recorded_utc = $record.recorded_utc
  })
  foreach ($name in @('running','intent')) {
    $active = Join-Path $Policy.spool ('state/'+$name+'.json')
    if (Test-Path -LiteralPath $active) { Remove-Item -LiteralPath $active -Force }
  }
  Clear-MIRGunmetalDispatcherPending -Policy $Policy -RequestId $Running.request_id
}

function Reconcile-MIRGunmetalDispatcherRunning {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Running)
  if (
    $Running.request_id -cne $Policy.approval.request_id -or
    $Running.packet_sha256 -cne $Policy.approval.packet_sha256 -or
    $Running.launcher_sha256 -cne $Policy.approval.launcher_sha256
  ) {
    throw '[mir-gunmetal-dispatcher-running-identity]'
  }
  $unit = Get-MIRGunmetalDispatcherUnit -Unit $Policy.unit
  $expected = [string]$Running.launch.start_ack.invocation_id
  if ($unit.ambiguous) {
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status interrupted -Reason 'native-unit-state-ambiguous' -Unit $unit
    return
  }
  if ($unit.found -and $unit.invocation_id -cne $expected) {
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status interrupted -Reason 'native-unit-invocation-replaced' -Unit $unit
    return
  }
  if ($unit.found -and $unit.active_state -in @('active','activating','deactivating')) { return }

  $result = Get-MIRGunmetalDispatcherResult -Approval $Policy.approval
  if ($unit.found) {
    $good = (
      $unit.result -ceq 'success' -and
      $unit.exec_main_code -ceq 'exited' -and
      $unit.exec_main_status -ceq '0' -and
      $result.valid
    )
    $terminalResult = [ordered]@{
      result = $result
      journal = [ordered]@{ observed = $true; exit_code = 0; source = 'systemctl-properties' }
    }
    $reason = if ($good) { 'unit-and-result-passed' } else { 'unit-terminal-or-result-failed' }
    $status = if ($good) { 'succeeded' } else { 'failed' }
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status $status -Reason $reason -Unit $unit -Result $terminalResult
    return
  }
  $journal = Get-MIRGunmetalDispatcherJournalTerminal -InvocationId $expected
  if (-not $journal.observed) {
    # A collected unit's disappearance/deactivation is not an exit status.
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status interrupted -Reason 'unit-unloaded-without-terminal-journal' -Result $result
    return
  }
  $good = ($journal.exit_code -eq 0 -and $result.valid)
  $reason = if ($good) { 'journal-and-result-passed' } else { 'journal-terminal-or-result-failed' }
  $status = if ($good) { 'succeeded' } else { 'failed' }
  New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $Running -Status $status -Reason $reason -Result ([ordered]@{ result = $result; journal = $journal })
}

function Start-MIRGunmetalDispatcherApprovedSubmission {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$Snapshot)
  if ($Snapshot.request.request_id -cne $Policy.approval.request_id) {
    throw '[mir-gunmetal-dispatcher-submission-not-approved]'
  }
  $record = [pscustomobject]@{
    request_id = $Policy.approval.request_id
    request_snapshot_sha256 = $Snapshot.request.policy_sha256
    dispatch_id = [guid]::NewGuid().ToString('N')
    launch = $null
  }
  # Rehash immediately before the only launch boundary.  Validation at policy
  # read time alone would leave a mutable-checkout race between a timer wakeup
  # and the reviewed launch.
  try {
    if ((Get-MIRGunmetalDispatcherSha256 $Policy.approval.launcher) -cne $Policy.approval.launcher_sha256) {
      throw '[mir-gunmetal-dispatcher-launcher-hash]'
    }
    if ((Get-MIRGunmetalDispatcherSha256 $Policy.approval.packet) -cne $Policy.approval.packet_sha256) {
      throw '[mir-gunmetal-dispatcher-packet-hash]'
    }
    if (Test-Path -LiteralPath $Policy.approval.result_path) { throw '[mir-gunmetal-dispatcher-result-preexists]' }
  } catch {
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status rejected -Reason 'prelaunch-pinned-input-refused'
    return
  }
  $before = Get-MIRGunmetalDispatcherUnit -Unit $Policy.unit
  if (-not $before.absence_confirmed) {
    $reason = if ($before.found) { 'native-unit-busy-before-launch' } else { 'native-unit-absence-not-confirmed' }
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status interrupted -Reason $reason -Unit $before
    return
  }

  # This write is deliberately before the only launcher call. If the consumer
  # is killed in that window, the next Consume adopts the matching invocation
  # or records interruption; it cannot launch the packet a second time.
  $intent = [ordered]@{
    kind = 'MIRGunmetalNativeDispatcherLaunchIntentV1'
    request_id = $record.request_id
    request_snapshot_sha256 = $record.request_snapshot_sha256
    packet_sha256 = $Policy.approval.packet_sha256
    launcher_sha256 = $Policy.approval.launcher_sha256
    result_path = $Policy.approval.result_path
    dispatch_id = $record.dispatch_id
    written_utc = [datetime]::UtcNow.ToString('o')
  }
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $Policy.spool 'state/intent.json') -Value $intent
  $launched = Invoke-MIRGunmetalDispatcherLauncher -Path $Policy.approval.launcher
  $launch = [ordered]@{
    acknowledged_utc = [datetime]::UtcNow.ToString('o')
    launcher_exit_code = $launched.exit_code
    launcher_output = @($launched.lines | Select-Object -Last 16)
  }
  if ($launched.exit_code -ne 0) {
    $record.launch = $launch
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status failed -Reason 'reviewed-launcher-refused-before-acknowledgement'
    return
  }
  $after = Get-MIRGunmetalDispatcherUnit -Unit $Policy.unit
  $acknowledged = (
    $after.found -and
    $after.active_state -in @('active','activating') -and
    $after.main_pid -match '^[1-9][0-9]*$' -and
    $after.invocation_id -cmatch '^[A-Fa-f0-9]{32}$'
  )
  if (-not $acknowledged) {
    $record.launch = $launch
    New-MIRGunmetalDispatcherTerminal -Policy $Policy -Running $record -Status interrupted -Reason 'launcher-returned-without-native-start-acknowledgement' -Unit $after
    return
  }
  $launch.start_ack = [ordered]@{
    pid = [int]$after.main_pid
    invocation_id = $after.invocation_id.ToLowerInvariant()
    active_state = $after.active_state
    sub_state = $after.sub_state
  }
  $running = [ordered]@{
    kind = 'MIRGunmetalNativeDispatcherRunningV2'
    request_id = $record.request_id
    request_snapshot_sha256 = $record.request_snapshot_sha256
    dispatch_id = $record.dispatch_id
    packet_sha256 = $Policy.approval.packet_sha256
    launcher_sha256 = $Policy.approval.launcher_sha256
    started_utc = [datetime]::UtcNow.ToString('o')
    launch = $launch
  }
  Write-MIRGunmetalDispatcherJson -Path (Join-Path $Policy.spool 'state/running.json') -Value $running
  Remove-Item -LiteralPath (Join-Path $Policy.spool 'state/intent.json') -Force
  Clear-MIRGunmetalDispatcherPending -Policy $Policy -RequestId $record.request_id
}

function Recover-MIRGunmetalDispatcherLaunchIntent {
  param([Parameter(Mandatory)]$BasePolicy,[Parameter(Mandatory)]$Intent)
  $recoveryPath=Join-Path $BasePolicy.spool 'state/intent-recovery-hold.json'
  try {
    if($Intent.kind-cne'MIRGunmetalNativeDispatcherLaunchIntentV1'-or$Intent.request_id-isnot[string]-or$Intent.request_snapshot_sha256-isnot[string]-or$Intent.dispatch_id-isnot[string]){throw '[mir-gunmetal-dispatcher-intent-schema]'}
    $snapshot=Get-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $BasePolicy -RequestId $Intent.request_id
    if($snapshot.request.policy_sha256-cne$Intent.request_snapshot_sha256-or$snapshot.policy.approval.packet_sha256-cne$Intent.packet_sha256-or$snapshot.policy.approval.launcher_sha256-cne$Intent.launcher_sha256-or$snapshot.policy.approval.result_path-cne$Intent.result_path){throw '[mir-gunmetal-dispatcher-intent-identity]'}
  } catch {
    Write-MIRGunmetalDispatcherJson -Path $recoveryPath -Value ([ordered]@{kind='MIRGunmetalNativeDispatcherIntentRecoveryHoldV1';held_utc=[datetime]::UtcNow.ToString('o');reason='intent-unreadable-or-mismatched';detail=$_.Exception.Message})
    return [pscustomobject]@{status='intent-recovery-held';side_effects='state-only'}
  }
  $runningPath=Join-Path $BasePolicy.spool 'state/running.json'
  if(Test-Path -LiteralPath $runningPath) {
    $running=Read-MIRGunmetalDispatcherJson -Path $runningPath
    if($running.request_id-ceq$Intent.request_id-and$running.dispatch_id-ceq$Intent.dispatch_id){Remove-Item -LiteralPath (Join-Path $BasePolicy.spool 'state/intent.json') -Force;return [pscustomobject]@{status='intent-already-adopted';side_effects='state-only'}}
    Write-MIRGunmetalDispatcherJson -Path $recoveryPath -Value ([ordered]@{kind='MIRGunmetalNativeDispatcherIntentRecoveryHoldV1';held_utc=[datetime]::UtcNow.ToString('o');reason='running-record-conflicts-with-intent'})
    return [pscustomobject]@{status='intent-recovery-held';side_effects='state-only'}
  }
  $record=[pscustomobject]@{request_id=$Intent.request_id;request_snapshot_sha256=$Intent.request_snapshot_sha256;dispatch_id=$Intent.dispatch_id;launch=$null}
  $unit=Get-MIRGunmetalDispatcherUnit -Unit $snapshot.policy.unit
  if($unit.ambiguous){New-MIRGunmetalDispatcherTerminal -Policy $snapshot.policy -Running $record -Status interrupted -Reason 'intent-recovery-unit-state-ambiguous' -Unit $unit;return [pscustomobject]@{status='intent-interrupted';side_effects='terminal-only'}}
  if($unit.absence_confirmed){New-MIRGunmetalDispatcherTerminal -Policy $snapshot.policy -Running $record -Status interrupted -Reason 'intent-recovered-without-native-unit' -Unit $unit;return [pscustomobject]@{status='intent-interrupted';side_effects='terminal-only'}}
  if($unit.active_state-notin@('active','activating','deactivating')-or$unit.main_pid-notmatch'^[1-9][0-9]*$'-or$unit.invocation_id-cnotmatch'^[A-Fa-f0-9]{32}$'){
    New-MIRGunmetalDispatcherTerminal -Policy $snapshot.policy -Running $record -Status interrupted -Reason 'intent-recovery-unit-not-adoptable' -Unit $unit
    return [pscustomobject]@{status='intent-interrupted';side_effects='terminal-only'}
  }
  $record.launch=[ordered]@{recovered_utc=[datetime]::UtcNow.ToString('o');acknowledgement='adopted-after-durable-intent';start_ack=[ordered]@{pid=[int]$unit.main_pid;invocation_id=$unit.invocation_id.ToLowerInvariant();active_state=$unit.active_state;sub_state=$unit.sub_state}}
  $running=[ordered]@{kind='MIRGunmetalNativeDispatcherRunningV2';request_id=$record.request_id;request_snapshot_sha256=$record.request_snapshot_sha256;dispatch_id=$record.dispatch_id;packet_sha256=$snapshot.policy.approval.packet_sha256;launcher_sha256=$snapshot.policy.approval.launcher_sha256;started_utc=[datetime]::UtcNow.ToString('o');launch=$record.launch}
  Write-MIRGunmetalDispatcherJson -Path $runningPath -Value $running
  Remove-Item -LiteralPath (Join-Path $BasePolicy.spool 'state/intent.json') -Force
  return [pscustomobject]@{status='intent-adopted';side_effects='running-state-only'}
}

function Invoke-MIRGunmetalDispatcherConsume {
  param([Parameter(Mandatory)]$Policy)
  New-MIRGunmetalDispatcherDirectories -Policy $Policy
  $lock=Enter-MIRGunmetalDispatcherLock -Policy $Policy;if($null-eq$lock){return [pscustomobject]@{status='busy';side_effects='none'}}
  try {
    $intent=Get-MIRGunmetalDispatcherStateRecord -Policy $Policy -Name intent
    if($null-ne$intent){
      return Recover-MIRGunmetalDispatcherLaunchIntent -BasePolicy $Policy -Intent $intent
    }
    $runningPath=Join-Path $Policy.spool 'state/running.json'
    if(Test-Path -LiteralPath $runningPath) {
      $running=Read-MIRGunmetalDispatcherJson -Path $runningPath
      $snapshot=Get-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $Policy -RequestId $running.request_id
      Reconcile-MIRGunmetalDispatcherRunning -Policy $snapshot.policy -Running $running
      return [pscustomobject]@{status='reconciled';side_effects='state-only'}
    }
    $pending=Get-MIRGunmetalDispatcherPending -Policy $Policy
    if($null-eq$pending){return [pscustomobject]@{status='idle';side_effects='none'}}
    $hold=Get-MIRGunmetalDispatcherStateRecord -Policy $Policy -Name hold
    if($null-ne$hold){return [pscustomobject]@{status='held-for-disposition';side_effects='none'}}
    $last=Get-MIRGunmetalDispatcherStateRecord -Policy $Policy -Name 'last-terminal'
    if($null-ne$last-and$last.status-cne'succeeded') {
      $released=($pending.pending.predecessor_request_id-ceq$last.request_id-and$pending.pending.disposition_reference-is[string]-and-not[string]::IsNullOrWhiteSpace([string]$pending.pending.disposition_reference))
      if(-not$released) {
        $holdRecord=[ordered]@{kind='MIRGunmetalNativeDispatcherHoldV1';request_id=$pending.pending.request_id;predecessor_request_id=$last.request_id;predecessor_status=$last.status;predecessor_packet_sha256=$last.packet_sha256;held_utc=[datetime]::UtcNow.ToString('o');reason='terminal-adverse-requires-explicit-reviewed-successor-disposition'}
        Write-MIRGunmetalDispatcherJson -Path (Join-Path $Policy.spool 'state/hold.json') -Value $holdRecord
        return [pscustomobject]@{status='held-after-adverse-terminal';side_effects='state-only'}
      }
    }
    Start-MIRGunmetalDispatcherApprovedSubmission -Policy $pending.snapshot.policy -Snapshot $pending.snapshot
    return [pscustomobject]@{status='submitted';side_effects='intent-and-reviewed-launcher'}
  } finally {$lock.Dispose()}
}

function Submit-MIRGunmetalDispatcherPolicy {
  param([Parameter(Mandatory)]$BasePolicy,[Parameter(Mandatory)]$CandidatePolicy,[string]$PredecessorRequestId='',[string]$DispositionReference='')
  Assert-MIRGunmetalDispatcherSchedulingIdentity -Base $BasePolicy -Candidate $CandidatePolicy
  New-MIRGunmetalDispatcherDirectories -Policy $BasePolicy
  $running=Get-MIRGunmetalDispatcherStateRecord -Policy $BasePolicy -Name running
  $intent=Get-MIRGunmetalDispatcherStateRecord -Policy $BasePolicy -Name intent
  $pending=Get-MIRGunmetalDispatcherPending -Policy $BasePolicy
  if($null-ne$pending){throw '[mir-gunmetal-dispatcher-pending-slot-not-empty]'}
  if($null-ne$running-and$running.request_id-ceq$CandidatePolicy.approval.request_id){throw '[mir-gunmetal-dispatcher-active-request-duplicate]'}
  if($null-ne$intent-and$intent.request_id-ceq$CandidatePolicy.approval.request_id){throw '[mir-gunmetal-dispatcher-intent-request-duplicate]'}
  if(Test-Path -LiteralPath (Join-Path $BasePolicy.spool ('terminal/'+$CandidatePolicy.approval.request_id+'.json'))){throw '[mir-gunmetal-dispatcher-terminal-request-duplicate]'}
  $snapshot=New-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $BasePolicy -CandidatePolicy $CandidatePolicy -PredecessorRequestId $PredecessorRequestId -DispositionReference $DispositionReference
  Set-MIRGunmetalDispatcherPending -Policy $BasePolicy -Snapshot $snapshot -PredecessorRequestId $PredecessorRequestId -DispositionReference $DispositionReference
  return [pscustomobject]@{kind='MIRGunmetalNativeDispatcherSubmissionV2';status='queued';request_id=$snapshot.request_id;policy_sha256=$snapshot.policy_sha256;side_effects='one immutable request snapshot and one atomic pending pointer; no launcher or native process was started.'}
}

function Submit-MIRGunmetalDispatcherApproved {
  param([Parameter(Mandatory)]$Policy)
  New-MIRGunmetalDispatcherDirectories -Policy $Policy
  $lock=Enter-MIRGunmetalDispatcherLock -Policy $Policy;if($null-eq$lock){return [pscustomobject]@{status='busy';side_effects='none'}}
  try { return Submit-MIRGunmetalDispatcherPolicy -BasePolicy $Policy -CandidatePolicy $Policy } finally {$lock.Dispose()}
}

function Submit-MIRGunmetalDispatcherSuccessor {
  param([Parameter(Mandatory)]$BasePolicy,[Parameter(Mandatory)][string]$SuccessorPolicyPath)
  $successor=Get-MIRGunmetalDispatcherPolicy -Path $SuccessorPolicyPath
  New-MIRGunmetalDispatcherDirectories -Policy $BasePolicy
  $lock=Enter-MIRGunmetalDispatcherLock -Policy $BasePolicy;if($null-eq$lock){return [pscustomobject]@{status='busy';side_effects='none'}}
  try { return Submit-MIRGunmetalDispatcherPolicy -BasePolicy $BasePolicy -CandidatePolicy $successor } finally {$lock.Dispose()}
}

function Replace-MIRGunmetalDispatcherHeldSuccessor {
  param([Parameter(Mandatory)]$BasePolicy,[Parameter(Mandatory)][string]$SuccessorPolicyPath,[Parameter(Mandatory)][string]$DispositionReference)
  if([string]::IsNullOrWhiteSpace($DispositionReference)-or$DispositionReference.Length-gt1024){throw '[mir-gunmetal-dispatcher-disposition-reference]'}
  $successor=Get-MIRGunmetalDispatcherPolicy -Path $SuccessorPolicyPath
  New-MIRGunmetalDispatcherDirectories -Policy $BasePolicy
  $lock=Enter-MIRGunmetalDispatcherLock -Policy $BasePolicy;if($null-eq$lock){return [pscustomobject]@{status='busy';side_effects='none'}}
  try {
    $hold=Get-MIRGunmetalDispatcherStateRecord -Policy $BasePolicy -Name hold
    $pending=Get-MIRGunmetalDispatcherPending -Policy $BasePolicy
    if($null-eq$hold-or$null-eq$pending){throw '[mir-gunmetal-dispatcher-held-successor-required]'}
    if($successor.approval.request_id-ceq$hold.predecessor_request_id){throw '[mir-gunmetal-dispatcher-held-request-not-distinct]'}
    $samePending=($successor.approval.request_id-ceq$pending.pending.request_id)
    if($samePending) {
      # A disposition can release the exact already-held immutable request. A
      # matching ID with different policy bytes is never an amendment: it is a
      # collision and must be submitted as a distinct reviewed successor.
      if((Get-MIRGunmetalDispatcherSha256 $successor.path) -cne $pending.snapshot.request.policy_sha256){throw '[mir-gunmetal-dispatcher-held-snapshot-policy-mismatch]'}
      $snapshot=[pscustomobject]@{request_id=$pending.snapshot.request.request_id;policy_sha256=$pending.snapshot.request.policy_sha256;path=(Join-Path (Get-MIRGunmetalDispatcherRequestDirectory -Policy $BasePolicy -RequestId $pending.snapshot.request.request_id) 'request.json')}
    } else {
      if($successor.approval.packet_sha256-ceq$hold.predecessor_packet_sha256-and$successor.approval.launcher_sha256-ceq$pending.snapshot.policy.approval.launcher_sha256){throw '[mir-gunmetal-dispatcher-held-unchanged-rerun]'}
      $snapshot=New-MIRGunmetalDispatcherRequestSnapshot -BasePolicy $BasePolicy -CandidatePolicy $successor -PredecessorRequestId $hold.predecessor_request_id -DispositionReference $DispositionReference
    }
    Set-MIRGunmetalDispatcherPending -Policy $BasePolicy -Snapshot $snapshot -PredecessorRequestId $hold.predecessor_request_id -DispositionReference $DispositionReference
    $archive=Join-Path $BasePolicy.spool ('held/'+$hold.predecessor_request_id+'-'+[datetime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-MIRGunmetalDispatcherJson -Path $archive -Value $hold -NewOnly
    Remove-Item -LiteralPath (Join-Path $BasePolicy.spool 'state/hold.json') -Force
    return [pscustomobject]@{kind='MIRGunmetalNativeDispatcherHeldDispositionV1';status=$(if($samePending){'released'}else{'replaced'});request_id=$snapshot.request_id;predecessor_request_id=$hold.predecessor_request_id;side_effects=$(if($samePending){'existing immutable successor snapshot was released with an explicit disposition; no launcher was started.'}else{'new immutable successor snapshot and pending pointer only; no launcher was started.'})}
  } finally {$lock.Dispose()}
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
  switch($Mode) {
    'SubmitApproved' { Submit-MIRGunmetalDispatcherApproved -Policy $policy }
    'SubmitSuccessor' { if([string]::IsNullOrWhiteSpace($SuccessorPolicyPath)){throw '[mir-gunmetal-dispatcher-successor-policy-required]'};Submit-MIRGunmetalDispatcherSuccessor -BasePolicy $policy -SuccessorPolicyPath $SuccessorPolicyPath }
    'ReplaceHeldSuccessor' { if([string]::IsNullOrWhiteSpace($SuccessorPolicyPath)){throw '[mir-gunmetal-dispatcher-successor-policy-required]'};Replace-MIRGunmetalDispatcherHeldSuccessor -BasePolicy $policy -SuccessorPolicyPath $SuccessorPolicyPath -DispositionReference $DispositionReference }
    default { Invoke-MIRGunmetalDispatcherConsume -Policy $policy }
  }
}
