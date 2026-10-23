# MIR5-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1')
$actorSource=Get-Content -Raw -LiteralPath (Join-Path $repo 'tools/lib/validation/responsive-menu/Invoke-MIRResponsiveMenuActor.ps1')
$assertions=0
function Assert-MIROwnedMenuWindow([bool]$Condition,[string]$Message){if(-not$Condition){throw "Owned menu window controls: $Message"};$script:assertions++}

$ownedProcess=Get-Process -Id $PID
$ownedStart=$ownedProcess.StartTime.ToUniversalTime()
$script:ownedWindowHandle=[IntPtr]7654321
$script:ownedWindowOwnerId=[uint32]$ownedProcess.Id
$script:ownedWindowFocusAccepted=$true
$script:ownedWindowForeground=[IntPtr]::Zero
$script:ownedWindowNativeCalls=[Collections.Generic.List[string]]::new()

# Host-only Win32 stubs: the implementation under test owns all admission
# checks; these stand in only for the narrow native calls after that boundary.
function Get-MIROwnedMenuMainWindowHandle { param([Diagnostics.Process]$Process) return $script:ownedWindowHandle }
function Get-MIROwnedMenuWindowProcessId { param([IntPtr]$Handle) return [uint32]$script:ownedWindowOwnerId }
function Test-MIROwnedMenuWindowHandle { param([IntPtr]$Handle) return $true }
function Test-MIROwnedMenuWindowVisible { param([IntPtr]$Handle) return $true }
function Test-MIROwnedMenuWindowIconic { param([IntPtr]$Handle) return $false }
function Get-MIROwnedMenuForegroundHandle { return [IntPtr]$script:ownedWindowForeground }
function Set-MIROwnedMenuForegroundHandle {
  param([IntPtr]$Handle)
  $script:ownedWindowNativeCalls.Add(('set-foreground:'+([int64]$Handle)))|Out-Null
  if($script:ownedWindowFocusAccepted){$script:ownedWindowForeground=$Handle}
  return [bool]$script:ownedWindowFocusAccepted
}

$accepted=New-MIROwnedMenuObserverDiagnostics
$focusAccepted=Request-MIROwnedMenuForeground -Process $ownedProcess -ExpectedStartUtc $ownedStart -Handle $script:ownedWindowHandle -Diagnostics $accepted
Assert-MIROwnedMenuWindow ($focusAccepted-and$accepted.foreground_request_attempts-eq1-and$accepted.foreground_request_refused-eq0-and$accepted.foreground_request_not_acquired-eq0-and$script:ownedWindowNativeCalls.Count-eq1) 'a validated visible owned window was not focused exactly once.'

$script:ownedWindowNativeCalls.Clear();$script:ownedWindowOwnerId=[uint32]($ownedProcess.Id+1)
$identityRejected=$false
try{Request-MIROwnedMenuForeground -Process $ownedProcess -ExpectedStartUtc $ownedStart -Handle $script:ownedWindowHandle -Diagnostics (New-MIROwnedMenuObserverDiagnostics)|Out-Null}catch{$identityRejected=$_.Exception.Message-ceq'[mir-menu-owned-window-identity]'}
Assert-MIROwnedMenuWindow ($identityRejected-and$script:ownedWindowNativeCalls.Count-eq0) 'a PID-mismatched window received a foreground request.'

$script:ownedWindowOwnerId=[uint32]$ownedProcess.Id
$script:ownedWindowFocusAccepted=$false
$script:ownedWindowForeground=[IntPtr]::Zero
$script:ownedWindowNativeCalls.Clear()
$refused=New-MIROwnedMenuObserverDiagnostics
$refusedPath=Join-Path $repo ('build/tmp/owned-window-refused-'+[guid]::NewGuid().ToString('N')+'.png')
$firstCapture=Save-MIROwnedMenuCapture -Process $ownedProcess -ExpectedStartUtc $ownedStart -Path $refusedPath -Diagnostics $refused
$secondCapture=Save-MIROwnedMenuCapture -Process $ownedProcess -ExpectedStartUtc $ownedStart -Path $refusedPath -Diagnostics $refused
Assert-MIROwnedMenuWindow ($null-eq$firstCapture-and$null-eq$secondCapture-and-not(Test-Path -LiteralPath $refusedPath)-and$refused.capture_requests-eq2-and$refused.captured_frames-eq0-and$refused.foreground_request_attempts-eq1-and$refused.foreground_request_refused-eq1-and$refused.foreground_mismatch-eq1-and$script:ownedWindowNativeCalls.Count-eq1) 'a refused owned foreground request was retried or produced a capture.'
Assert-MIROwnedMenuWindow ($actorSource.Contains('observer_diagnostics')-and$actorSource.Contains('New-MIROwnedMenuObserverDiagnostics')-and-not$actorSource.Contains('GetWindowText')-and-not$actorSource.Contains('CopyFromScreen')) 'the actor does not preserve bounded rejection diagnostics without foreign window data.'

[pscustomobject][ordered]@{status='passed';assertions=$assertions;native_factorio=$false;scope='Host Win32 stubs for validated owned foreground admission, identity rejection, and refused-focus no-capture diagnostics'}|ConvertTo-Json -Compress
