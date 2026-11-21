# Exercise the installation transaction in a disposable, simulated user manager.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$checkout = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $checkout 'tools/commands/workspace/Install-MIRGunmetalNativeDispatcher.ps1')
$scratch = Join-Path $checkout 'build/tmp'
$root = Join-Path $scratch ('dispatcher-install-' + [guid]::NewGuid().ToString('N'))
$unitRoot = Join-Path $root 'units'
$script:foreignFragment = ''
$script:serviceState = 'inactive'
$script:enableFails = $true
$script:changes = [Collections.Generic.List[string]]::new()

function New-InstallPlanForControl([string]$Name) {
  $ownedRoot = Join-Path $root $Name
  $units = 'mir-native-dispatcher.service','mir-native-dispatcher.path','mir-native-dispatcher.timer'
  $rows = foreach ($path in (@(Join-Path $ownedRoot 'dispatcher.ps1') + @($units | ForEach-Object { Join-Path $unitRoot $_ }))) {
    $bytes = [Text.Encoding]::UTF8.GetBytes("owned by $Name $(Split-Path -Leaf $path)")
    [pscustomobject]@{path=$path; bytes=$bytes; sha256=(Get-MIRGunmetalDispatcherInstallSha256 $bytes)}
  }
  [pscustomobject]@{install_root=$ownedRoot; unit_directory=$unitRoot; units=$units; files=@($rows); policy_sha256=('A' * 64)}
}

function Get-MIRGunmetalDispatcherInstallLinger { [pscustomobject]@{exit_code=0;lines=@('yes')} }
function Invoke-MIRGunmetalDispatcherInstallSystemctl([string[]]$Arguments) {
  if ($Arguments[0] -ceq 'show') {
    $name = $Arguments[-1]
    $path = Join-Path $unitRoot $name
    $active = if ($name -ceq 'mir-native-dispatcher.service') { $script:serviceState } else { 'inactive' }
    if ($name -ceq 'mir-native-dispatcher.path' -and $script:foreignFragment) { $path = $script:foreignFragment }
    if ((Test-Path -LiteralPath $path) -or $path -ceq $script:foreignFragment) {
      return [pscustomobject]@{exit_code=0;lines=@('LoadState=loaded',"ActiveState=$active","FragmentPath=$path",'DropInPaths=')}
    }
    return [pscustomobject]@{exit_code=4;lines=@('LoadState=not-found','ActiveState=inactive','FragmentPath=','DropInPaths=')}
  }
  $script:changes.Add($Arguments[0])
  $code = if ($Arguments[0] -ceq 'enable' -and $script:enableFails) { 1 } else { 0 }
  return [pscustomobject]@{exit_code=$code;lines=@()}
}

function Expect-InstallRefusal([scriptblock]$Operation, [string]$Reason) {
  try { & $Operation | Out-Null } catch {
    if ($_.Exception.Message -ceq $Reason) { return }
    throw
  }
  throw "Expected refusal $Reason"
}

try {
  $plan = New-InstallPlanForControl 'first'
  $other = New-InstallPlanForControl 'second'
  Expect-InstallRefusal { Invoke-MIRGunmetalDispatcherInstallLifecycle $plan Install -TestOnly } '[mir-gunmetal-dispatcher-install-enable-resume-required]'
  $script:changes.Clear()
  $pathFile = Join-Path $unitRoot 'mir-native-dispatcher.path'
  $original = [IO.File]::ReadAllBytes($pathFile)
  [IO.File]::WriteAllText($pathFile, 'external replacement')
  Expect-InstallRefusal { Undo-MIRGunmetalDispatcherInstall $plan } '[mir-gunmetal-dispatcher-install-rollback-file-conflict]'
  if ($script:changes.Count -or -not (Test-Path -LiteralPath $plan.files[0].path)) { throw 'Rollback changed manager or files before establishing ownership' }
  [IO.File]::WriteAllBytes($pathFile, $original)

  $script:foreignFragment = Join-Path $root 'elsewhere/mir-native-dispatcher.path'
  Expect-InstallRefusal { Undo-MIRGunmetalDispatcherInstall $plan } '[mir-gunmetal-dispatcher-install-unit-identity]'
  $script:foreignFragment = ''
  $script:serviceState = 'activating'
  Expect-InstallRefusal { Undo-MIRGunmetalDispatcherInstall $plan } '[mir-gunmetal-dispatcher-install-service-busy]'
  $script:serviceState = 'inactive'
  Expect-InstallRefusal { Invoke-MIRGunmetalDispatcherInstallLifecycle $other Install -TestOnly } '[mir-gunmetal-dispatcher-install-transaction-identity]'
  if ($script:changes.Count) { throw 'Conflicting install or active service changed the user manager' }
  $lock = Enter-MIRGunmetalDispatcherInstallLock $plan
  try {
    Expect-InstallRefusal { Undo-MIRGunmetalDispatcherInstall $plan } '[mir-gunmetal-dispatcher-install-busy]'
  } finally { $lock.Dispose() }
  $script:enableFails = $false
  $null = Invoke-MIRGunmetalDispatcherInstallLifecycle $plan Resume -TestOnly
  $rollback = Undo-MIRGunmetalDispatcherInstall $plan
  if ($rollback.status -cne 'rolled-back' -or (Test-Path -LiteralPath $plan.install_root)) { throw 'Owned resume and rollback did not finish' }
  [pscustomobject]@{status='passed';coverage='changed bytes, foreign unit, running service, second install, lock, resume and rollback'}
} finally {
  $safeRoot = [IO.Path]::GetFullPath($root)
  if ((Split-Path -Parent $safeRoot) -cne [IO.Path]::GetFullPath($scratch) -or (Split-Path -Leaf $safeRoot) -cnotmatch '^dispatcher-install-[0-9a-f]{32}$') { throw 'Unexpected scratch path' }
  if (Test-Path -LiteralPath $safeRoot) { Remove-Item -LiteralPath $safeRoot -Recurse -Force }
}
