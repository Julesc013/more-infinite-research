# MIR-GUNMETAL-NATIVE-DISPATCHER-INSTALLER-V1
# Compose is safe for review and focused tests. Install is intentionally local
# to the declared execution account; it never SSHes, changes another account,
# or launches a native packet.
[CmdletBinding()]
param(
  [ValidateSet('Compose','Install')][string]$Mode='Compose',
  [Parameter(Mandatory)][string]$PolicyPath,
  [string]$InstallRoot='',
  [string]$UnitDirectory=''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Write-MIRGunmetalDispatcherInstallFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

$dispatcher=Join-Path $PSScriptRoot 'Invoke-MIRGunmetalNativeDispatcher.ps1'
if(-not(Test-Path -LiteralPath $dispatcher -PathType Leaf)){throw '[mir-gunmetal-dispatcher-install-dispatcher-missing]'}
if([string]::IsNullOrWhiteSpace($InstallRoot)){$InstallRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/lib/mir-native-dispatcher'}
if([string]::IsNullOrWhiteSpace($UnitDirectory)){$UnitDirectory=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.config/systemd/user'}
$policyFull=[IO.Path]::GetFullPath($PolicyPath)
if(-not(Test-Path -LiteralPath $policyFull -PathType Leaf)){throw '[mir-gunmetal-dispatcher-install-policy-missing]'}
$installFull=[IO.Path]::GetFullPath($InstallRoot);$unitFull=[IO.Path]::GetFullPath($UnitDirectory)
if($Mode-ceq'Install'-and-not$IsLinux){throw '[mir-gunmetal-dispatcher-install-linux-required]'}

# Use the exact dispatcher validation before composing units. This still does
# not launch a packet, mutate a direct library, or create an engine process.
try { & $dispatcher -Mode ValidatePolicy -PolicyPath $policyFull | Out-Null } catch { throw '[mir-gunmetal-dispatcher-install-policy-invalid]' }

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
$policyObject=Get-Content -LiteralPath $policyFull -Raw|ConvertFrom-Json
$path=@"
[Unit]
Description=Watch MIR reviewed native submissions

[Path]
PathExistsGlob=$([string]$policyObject.spool_root)/incoming/*.json
Unit=mir-native-dispatcher.service

[Install]
WantedBy=default.target
"@
$timer=@"
[Unit]
Description=Reconcile MIR reviewed native terminal records

[Timer]
OnBootSec=1min
OnUnitInactiveSec=1min
AccuracySec=15s
Persistent=true
Unit=mir-native-dispatcher.service

[Install]
WantedBy=timers.target
"@

if($Mode-ceq'Compose'){
  [pscustomobject]@{kind='MIRGunmetalNativeDispatcherInstallPlanV1';status='composed';install_root=$installFull;unit_directory=$unitFull;files=[ordered]@{'mir-native-dispatcher.service'=$service;'mir-native-dispatcher.path'=$path;'mir-native-dispatcher.timer'=$timer};operational_scope='unit composition only; no service install, packet launch, or gameplay acceptance.'}
  return
}
if(Test-Path -LiteralPath $installFull){throw '[mir-gunmetal-dispatcher-install-root-exists]'}
if($installFull-match'\s'-or$unitFull-match'\s'){throw '[mir-gunmetal-dispatcher-install-whitespace-path]'}
foreach($unitName in @('mir-native-dispatcher.service','mir-native-dispatcher.path','mir-native-dispatcher.timer')){
  if(Test-Path -LiteralPath (Join-Path $unitFull $unitName)){throw '[mir-gunmetal-dispatcher-install-unit-exists]'}
}
$linger=@(& /usr/bin/loginctl show-user ([Environment]::UserName) --property=Linger --value 2>$null)
if($LASTEXITCODE-ne0-or$linger.Count-ne1-or$linger[0].Trim()-cne'yes'){throw '[mir-gunmetal-dispatcher-install-linger-required]'}
[IO.Directory]::CreateDirectory($installFull)|Out-Null
try{
  Copy-Item -LiteralPath $dispatcher -Destination $installedDispatcher -ErrorAction Stop
  Copy-Item -LiteralPath $policyFull -Destination $installedPolicy -ErrorAction Stop
  Write-MIRGunmetalDispatcherInstallFile -Path (Join-Path $unitFull 'mir-native-dispatcher.service') -Text $service
  Write-MIRGunmetalDispatcherInstallFile -Path (Join-Path $unitFull 'mir-native-dispatcher.path') -Text $path
  Write-MIRGunmetalDispatcherInstallFile -Path (Join-Path $unitFull 'mir-native-dispatcher.timer') -Text $timer
  & /usr/bin/systemctl --user daemon-reload
  if($LASTEXITCODE-ne0){throw '[mir-gunmetal-dispatcher-install-daemon-reload]'}
  & /usr/bin/systemctl --user enable --now mir-native-dispatcher.path mir-native-dispatcher.timer
  if($LASTEXITCODE-ne0){throw '[mir-gunmetal-dispatcher-install-enable]'}
  [pscustomobject]@{kind='MIRGunmetalNativeDispatcherInstallResultV1';status='installed';install_root=$installFull;units=@('mir-native-dispatcher.service','mir-native-dispatcher.path','mir-native-dispatcher.timer');operational_scope='dispatcher installed only; no native packet was launched and no gameplay acceptance is established.'}
}catch{throw}
