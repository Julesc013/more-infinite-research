# MIR-GUNMETAL-NATIVE-DISPATCHER-INSTALLER-V2
<#
Compose is review-only. Install and Resume run solely in the reviewed policy's
execution-account user manager; neither SSHes, starts a packet, or writes an
existing unit. A durable transaction records only the new files this installer
created. A failed reload/enable is preserved for byte-identical Resume or for
Rollback of just those owned paths.
#>
[CmdletBinding()]
param(
  [ValidateSet('Compose','Install','Resume','Rollback')][string]$Mode='Compose',
  [string]$PolicyPath='',
  [string]$InstallRoot='',
  [string]$UnitDirectory=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Get-MIRGunmetalDispatcherInstallSha256 {
  param([Parameter(Mandatory)][byte[]]$Bytes)
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Write-MIRGunmetalDispatcherInstallBytes {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes,[switch]$NewOnly)
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  $temporary=Join-Path (Split-Path -Parent $Path) ('.'+[IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.new')
  try {
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
      $stream.Write($Bytes,0,$Bytes.Length)
      $stream.Flush($true)
    } finally { $stream.Dispose() }
    if($NewOnly){[IO.File]::Move($temporary,$Path)}else{[IO.File]::Move($temporary,$Path,$true)}
  } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Invoke-MIRGunmetalDispatcherInstallSystemctl {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $lines=@(& /usr/bin/systemctl --user @Arguments 2>&1)
  return [pscustomobject]@{exit_code=$LASTEXITCODE;lines=@($lines|ForEach-Object{[string]$_})}
}

function Get-MIRGunmetalDispatcherInstallLinger {
  $lines=@(& /usr/bin/loginctl show-user ([Environment]::UserName) --property=Linger --value 2>$null)
  return [pscustomobject]@{exit_code=$LASTEXITCODE;lines=@($lines|ForEach-Object{[string]$_})}
}

function Get-MIRGunmetalDispatcherInstallPlan {
  param([Parameter(Mandatory)][string]$PolicyPath,[Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$UnitDirectory)
  $dispatcher=Join-Path $PSScriptRoot 'Invoke-MIRGunmetalNativeDispatcher.ps1'
  if(-not(Test-Path -LiteralPath $dispatcher -PathType Leaf)){throw '[mir-gunmetal-dispatcher-install-dispatcher-missing]'}
  $policyFull=[IO.Path]::GetFullPath($PolicyPath)
  if(-not(Test-Path -LiteralPath $policyFull -PathType Leaf)){throw '[mir-gunmetal-dispatcher-install-policy-missing]'}
  try { & $dispatcher -Mode ValidatePolicy -PolicyPath $policyFull | Out-Null } catch { throw '[mir-gunmetal-dispatcher-install-policy-invalid]' }
  $installFull=[IO.Path]::GetFullPath($InstallRoot)
  $unitFull=[IO.Path]::GetFullPath($UnitDirectory)
  if($installFull-match'\s'-or$unitFull-match'\s'){throw '[mir-gunmetal-dispatcher-install-whitespace-path]'}
  $policyObject=Get-Content -LiteralPath $policyFull -Raw|ConvertFrom-Json
  $installedDispatcher=Join-Path $installFull 'Invoke-MIRGunmetalNativeDispatcher.ps1'
  $installedPolicy=Join-Path $installFull 'policy.json'
  $service=@"
[Unit]
Description=MIR reviewed native packet dispatcher
Documentation=file://$installedDispatcher

[Service]
Type=oneshot
UMask=0077
NoNewPrivileges=yes
PrivateTmp=yes
TimeoutStartSec=120
ExecStart=/usr/bin/pwsh -NoProfile -NonInteractive -File $installedDispatcher -Mode Consume -PolicyPath $installedPolicy
"@
  $path=@"
[Unit]
Description=Watch MIR reviewed native successor pointer

[Path]
# `pending.json` is durable and deliberately remains while a predecessor is
# active or held. The separate signal is removed by the consumer on its first
# wakeup, avoiding a PathExists restart loop/start-limit failure.
PathExists=$([string]$policyObject.spool_root)/state/pending.signal
Unit=mir-native-dispatcher.service

[Install]
WantedBy=default.target
"@
  $timer=@"
[Unit]
Description=Reconcile MIR reviewed native terminal records

[Timer]
OnActiveSec=1min
OnUnitInactiveSec=1min
AccuracySec=15s
Persistent=true
Unit=mir-native-dispatcher.service

[Install]
WantedBy=timers.target
"@
  $content=[ordered]@{}
  $content[$installedDispatcher]=[IO.File]::ReadAllBytes($dispatcher)
  $content[$installedPolicy]=[IO.File]::ReadAllBytes($policyFull)
  $content[(Join-Path $unitFull 'mir-native-dispatcher.service')]=[Text.UTF8Encoding]::new($false).GetBytes($service)
  $content[(Join-Path $unitFull 'mir-native-dispatcher.path')]=[Text.UTF8Encoding]::new($false).GetBytes($path)
  $content[(Join-Path $unitFull 'mir-native-dispatcher.timer')]=[Text.UTF8Encoding]::new($false).GetBytes($timer)
  $files=@($content.Keys|Sort-Object|ForEach-Object {[pscustomobject]@{path=$_;sha256=(Get-MIRGunmetalDispatcherInstallSha256 $content[$_]);bytes=$content[$_]}})
  return [pscustomobject]@{kind='MIRGunmetalNativeDispatcherInstallPlanV2';install_root=$installFull;unit_directory=$unitFull;policy_path=$policyFull;policy_sha256=(Get-MIRGunmetalDispatcherInstallSha256 $content[$installedPolicy]);files=$files;units=@('mir-native-dispatcher.service','mir-native-dispatcher.path','mir-native-dispatcher.timer');service=$service;path=$path;timer=$timer}
}

function Test-MIRGunmetalDispatcherInstallFileIdentity {
  param([Parameter(Mandatory)]$File)
  if(-not(Test-Path -LiteralPath $File.path -PathType Leaf)){return $false}
  if ((Get-Item -LiteralPath $File.path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
  return ((Get-FileHash -LiteralPath $File.path -Algorithm SHA256).Hash.ToUpperInvariant() -ceq $File.sha256)
}

function Enter-MIRGunmetalDispatcherInstallLock {
  param([Parameter(Mandatory)]$Plan)
  [IO.Directory]::CreateDirectory($Plan.unit_directory) | Out-Null
  $directory = if ($IsLinux -and $env:XDG_RUNTIME_DIR) { $env:XDG_RUNTIME_DIR } else { $Plan.unit_directory }
  $path = Join-Path $directory ('.' + $Plan.units[0] + '.install.lock')
  try { return [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None') }
  catch [IO.IOException] { throw '[mir-gunmetal-dispatcher-install-busy]' }
}

function Get-MIRGunmetalDispatcherInstallTransactionPath($Plan) {
  # All installations which claim these unit names share one durable record,
  # including installations that select a different script directory.
  return Join-Path $Plan.unit_directory ('.' + $Plan.units[0] + '.install.json')
}

function Get-MIRGunmetalDispatcherInstallUnits {
  param([Parameter(Mandatory)]$Plan)
  foreach ($name in $Plan.units) {
    $reply = Invoke-MIRGunmetalDispatcherInstallSystemctl -Arguments @('show','--all','--property=LoadState,ActiveState,FragmentPath,DropInPaths',$name)
    $fields = @{}
    foreach ($line in $reply.lines) {
      if ($line -cmatch '^(LoadState|ActiveState|FragmentPath|DropInPaths)=(.*)$' -and -not $fields.ContainsKey($Matches[1])) {
        $fields[$Matches[1]] = $Matches[2]
      }
    }
    if ($fields.Count -ne 4) { throw '[mir-gunmetal-dispatcher-install-unit-state-unavailable]' }
    $path = Join-Path $Plan.unit_directory $name
    $absent = ($reply.exit_code -in @(0,4) -and $fields.LoadState -ceq 'not-found' -and
               $fields.ActiveState -ceq 'inactive' -and -not $fields.FragmentPath -and -not $fields.DropInPaths)
    if (-not $absent -and ($reply.exit_code -ne 0 -or $fields.LoadState -cne 'loaded' -or
        $fields.FragmentPath -cne $path -or $fields.DropInPaths)) { throw '[mir-gunmetal-dispatcher-install-unit-identity]' }
    [pscustomobject]@{ name=$name; present=(-not $absent); active=$fields.ActiveState; path=$path }
  }
}

function Read-MIRGunmetalDispatcherInstallTransaction {
  param([Parameter(Mandatory)]$Plan)
  $path=Get-MIRGunmetalDispatcherInstallTransactionPath $Plan
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '[mir-gunmetal-dispatcher-install-transaction-missing]'}
  try{return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw '[mir-gunmetal-dispatcher-install-transaction-invalid]'}
}

function Write-MIRGunmetalDispatcherInstallTransaction {
  param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$Stage)
  $files=@($Plan.files|ForEach-Object {[ordered]@{path=$_.path;sha256=$_.sha256}})
  $record=[ordered]@{schema=1;kind='MIRGunmetalNativeDispatcherInstallTransactionV1';stage=$Stage;install_root=$Plan.install_root;unit_directory=$Plan.unit_directory;policy_sha256=$Plan.policy_sha256;files=$files;units=$Plan.units;created_utc=[datetime]::UtcNow.ToString('o')}
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 12 -Compress)+"`n")
  Write-MIRGunmetalDispatcherInstallBytes -Path (Get-MIRGunmetalDispatcherInstallTransactionPath $Plan) -Bytes $bytes -NewOnly:($Stage -ceq 'prepared')
}

function Assert-MIRGunmetalDispatcherInstallTransaction {
  param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Transaction)
  if (
    $Transaction.schema -ne 1 -or
    $Transaction.kind -cne 'MIRGunmetalNativeDispatcherInstallTransactionV1' -or
    $Transaction.install_root -cne $Plan.install_root -or
    $Transaction.unit_directory -cne $Plan.unit_directory -or
    $Transaction.policy_sha256 -cne $Plan.policy_sha256
  ) {
    throw '[mir-gunmetal-dispatcher-install-transaction-identity]'
  }
  if (@($Transaction.files).Count -ne $Plan.files.Count) { throw '[mir-gunmetal-dispatcher-install-transaction-files]' }
  foreach ($file in $Plan.files) {
    $row = @($Transaction.files | Where-Object { $_.path -ceq $file.path })
    if ($row.Count -ne 1 -or $row[0].sha256 -cne $file.sha256) {
      throw '[mir-gunmetal-dispatcher-install-transaction-files]'
    }
  }
}

function Write-MIRGunmetalDispatcherInstallFiles {
  param([Parameter(Mandatory)]$Plan)
  foreach($file in $Plan.files) {
    if(Test-Path -LiteralPath $file.path) {
      if(-not(Test-MIRGunmetalDispatcherInstallFileIdentity -File $file)){throw '[mir-gunmetal-dispatcher-install-file-conflict]'}
    } else { Write-MIRGunmetalDispatcherInstallBytes -Path $file.path -Bytes $file.bytes -NewOnly }
  }
}

function Invoke-MIRGunmetalDispatcherInstallLifecycle {
  param([Parameter(Mandatory)]$Plan,[ValidateSet('Install','Resume')][string]$Action,[switch]$TestOnly)
  if (-not $IsLinux -and -not $TestOnly) { throw '[mir-gunmetal-dispatcher-install-linux-required]' }
  $lock = Enter-MIRGunmetalDispatcherInstallLock $Plan
  try { Install-MIRGunmetalDispatcherOwnedFiles $Plan $Action } finally { $lock.Dispose() }
}

function Install-MIRGunmetalDispatcherOwnedFiles {
  param([Parameter(Mandatory)]$Plan,[ValidateSet('Install','Resume')][string]$Action)
  $linger = Get-MIRGunmetalDispatcherInstallLinger
  if ($linger.exit_code -ne 0 -or $linger.lines.Count -ne 1 -or $linger.lines[0].Trim() -cne 'yes') {
    throw '[mir-gunmetal-dispatcher-install-linger-required]'
  }
  $recordPath = Get-MIRGunmetalDispatcherInstallTransactionPath $Plan
  if (Test-Path -LiteralPath $recordPath) {
    $transaction = Read-MIRGunmetalDispatcherInstallTransaction -Plan $Plan
    Assert-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Transaction $transaction
    if ($Action -ceq 'Install') { throw '[mir-gunmetal-dispatcher-install-resume-required]' }
    if ($transaction.stage -ceq 'rolling-back') { throw '[mir-gunmetal-dispatcher-install-rollback-required]' }
    $null = Get-MIRGunmetalDispatcherInstallUnits $Plan
  } else {
    if ($Action -ceq 'Resume') { throw '[mir-gunmetal-dispatcher-install-transaction-missing]' }
    if (Test-Path -LiteralPath $Plan.install_root) { throw '[mir-gunmetal-dispatcher-install-root-exists]' }
    foreach ($file in @($Plan.files | Where-Object { $_.path.StartsWith($Plan.unit_directory + [IO.Path]::DirectorySeparatorChar) })) {
      if (Test-Path -LiteralPath $file.path) { throw '[mir-gunmetal-dispatcher-install-unit-exists]' }
    }
    if (@(Get-MIRGunmetalDispatcherInstallUnits $Plan | Where-Object present).Count) { throw '[mir-gunmetal-dispatcher-install-unit-exists]' }
    Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage prepared
  }
  # Every resume rehashes its exact planned files. It can finish a reload or
  # enable interruption, but cannot adopt altered dispatcher or unit bytes.
  Write-MIRGunmetalDispatcherInstallFiles -Plan $Plan
  Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage files-written
  $null = Get-MIRGunmetalDispatcherInstallUnits $Plan
  $reload = Invoke-MIRGunmetalDispatcherInstallSystemctl -Arguments @('daemon-reload')
  if ($reload.exit_code -ne 0) {
    Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage reload-pending
    throw '[mir-gunmetal-dispatcher-install-daemon-reload-resume-required]'
  }
  Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage reloaded
  if (@(Get-MIRGunmetalDispatcherInstallUnits $Plan | Where-Object { -not $_.present }).Count) {
    throw '[mir-gunmetal-dispatcher-install-unit-not-loaded]'
  }
  $triggerNames = @($Plan.units | Where-Object { $_ -cne $Plan.units[0] })
  $enable = Invoke-MIRGunmetalDispatcherInstallSystemctl -Arguments (@('enable','--now') + $triggerNames)
  if ($enable.exit_code -ne 0) {
    Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage enable-pending
    throw '[mir-gunmetal-dispatcher-install-enable-resume-required]'
  }
  Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage installed
  return [pscustomobject]@{
    kind = 'MIRGunmetalNativeDispatcherInstallResultV2'
    status = 'installed'
    install_root = $Plan.install_root
    units = $Plan.units
    operational_scope = 'user-manager installation; job execution is recorded in the dispatcher spool.'
  }
}

function Undo-MIRGunmetalDispatcherInstall {
  param([Parameter(Mandatory)]$Plan)
  $lock = Enter-MIRGunmetalDispatcherInstallLock $Plan
  try { Uninstall-MIRGunmetalDispatcherOwnedFiles $Plan } finally { $lock.Dispose() }
}

function Uninstall-MIRGunmetalDispatcherOwnedFiles {
  param([Parameter(Mandatory)]$Plan)
  $transaction = Read-MIRGunmetalDispatcherInstallTransaction -Plan $Plan
  Assert-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Transaction $transaction
  foreach ($file in $Plan.files) {
    if ((Test-Path -LiteralPath $file.path) -and -not (Test-MIRGunmetalDispatcherInstallFileIdentity $file)) {
      throw '[mir-gunmetal-dispatcher-install-rollback-file-conflict]'
    }
  }
  $units = @(Get-MIRGunmetalDispatcherInstallUnits $Plan)
  if (($units | Where-Object name -CEQ $Plan.units[0]).active -cnotin @('inactive','failed')) {
    throw '[mir-gunmetal-dispatcher-install-service-busy]'
  }
  # A partial install may have written only a subset. Never disable another
  # resolved fragment or remove a script while the manager still executes it.
  $triggers = @($units | Where-Object { $_.present -and $_.name -cne $Plan.units[0] -and (Test-Path -LiteralPath $_.path) } | ForEach-Object name)
  if ($triggers.Count) {
    $disable = Invoke-MIRGunmetalDispatcherInstallSystemctl -Arguments (@('disable','--now') + $triggers)
    if ($disable.exit_code -ne 0) { throw '[mir-gunmetal-dispatcher-install-disable-required]' }
  }
  $units = @(Get-MIRGunmetalDispatcherInstallUnits $Plan)
  if (@($units | Where-Object { $_.active -cnotin @('inactive','failed') }).Count) {
    throw '[mir-gunmetal-dispatcher-install-service-busy]'
  }
  Write-MIRGunmetalDispatcherInstallTransaction -Plan $Plan -Stage rolling-back
  foreach ($file in $Plan.files) {
    if (Test-Path -LiteralPath $file.path) { Remove-Item -LiteralPath $file.path -Force }
  }
  $reload = Invoke-MIRGunmetalDispatcherInstallSystemctl -Arguments @('daemon-reload')
  if ($reload.exit_code -ne 0) { throw '[mir-gunmetal-dispatcher-install-rollback-daemon-reload]' }
  if ((Test-Path -LiteralPath $Plan.install_root) -and @((Get-ChildItem -LiteralPath $Plan.install_root -Force)).Count -eq 0) {
    Remove-Item -LiteralPath $Plan.install_root -Force
  }
  Remove-Item -LiteralPath (Get-MIRGunmetalDispatcherInstallTransactionPath $Plan) -Force
  return [pscustomobject]@{
    kind = 'MIRGunmetalNativeDispatcherInstallRollbackV1'
    status = 'rolled-back'
    operational_scope = 'only transaction-owned unit and install files removed; no packet launched.'
  }
}

if($MyInvocation.InvocationName-ne'.') {
  if([string]::IsNullOrWhiteSpace($PolicyPath)){throw '[mir-gunmetal-dispatcher-install-policy-required]'}
  $dispatcher=Join-Path $PSScriptRoot 'Invoke-MIRGunmetalNativeDispatcher.ps1'
  if([string]::IsNullOrWhiteSpace($InstallRoot)){$InstallRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/lib/mir-native-dispatcher'}
  if([string]::IsNullOrWhiteSpace($UnitDirectory)){$UnitDirectory=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config/systemd/user'}
  $plan=Get-MIRGunmetalDispatcherInstallPlan -PolicyPath $PolicyPath -InstallRoot $InstallRoot -UnitDirectory $UnitDirectory
  if($Mode-ceq'Compose') {
    [pscustomobject]@{kind='MIRGunmetalNativeDispatcherInstallPlanV2';status='composed';install_root=$plan.install_root;unit_directory=$plan.unit_directory;files=[ordered]@{'mir-native-dispatcher.service'=$plan.service;'mir-native-dispatcher.path'=$plan.path;'mir-native-dispatcher.timer'=$plan.timer};operational_scope='unit composition only; no service install, packet launch, or gameplay acceptance.'}
  } elseif($Mode-ceq'Rollback') { Undo-MIRGunmetalDispatcherInstall -Plan $plan } else { Invoke-MIRGunmetalDispatcherInstallLifecycle -Plan $plan -Action $Mode }
}
