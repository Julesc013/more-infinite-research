# Always invoke in the governed, bounded actor process owned by the canonical
# direct-library responsive-menu runner.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-MIROwnedMenuWindow {
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  if ($null -ne ('MIROwnedMenuNative' -as [type])) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MIROwnedMenuNative {
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static bool TrySameOwnedProcess(IntPtr h, uint ownedPid, out bool sameProcess) {
    sameProcess = false;
    uint candidatePid;
    if (GetWindowThreadProcessId(h, out candidatePid) == 0 || candidatePid == 0) return false;
    sameProcess = candidatePid == ownedPid;
    return true;
  }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref Point p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flag);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint message, UIntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
'@
}

function New-MIROwnedMenuObserverDiagnostics {
  [ordered]@{
    schema=1
    capture_requests=0
    captured_frames=0
    no_main_window=0
    not_visible_or_minimized=0
    foreground_mismatch=0
    foreground_request_attempts=0
    foreground_request_refused=0
    foreground_request_not_acquired=0
    client_geometry_unavailable=0
    offscreen=0
    occluded=0
    last_occlusion=$null
    last_rejection=''
  }
}

function Add-MIROwnedMenuRejection {
  param([AllowNull()][Collections.IDictionary]$Diagnostics,[Parameter(Mandatory)][string]$Name)
  if ($null -eq $Diagnostics) { return }
  if (-not $Diagnostics.Contains($Name)) { throw "[mir-menu-observer-diagnostic-name] $Name" }
  $Diagnostics[$Name]=[int]$Diagnostics[$Name]+1
  $Diagnostics.last_rejection=$Name
}

# These small wrappers keep ownership decisions in this file and let the host
# controls exercise the Win32 boundary without a graphical Factorio process.
function Get-MIROwnedMenuMainWindowHandle {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process)
  $Process.Refresh()
  return $Process.MainWindowHandle
}

function Get-MIROwnedMenuWindowProcessId {
  param([Parameter(Mandatory)][IntPtr]$Handle)
  [uint32]$ownerId=0
  $null=[MIROwnedMenuNative]::GetWindowThreadProcessId($Handle,[ref]$ownerId)
  return $ownerId
}

function Test-MIROwnedMenuWindowHandle {
  param([Parameter(Mandatory)][IntPtr]$Handle)
  return [MIROwnedMenuNative]::IsWindow($Handle)
}

function Test-MIROwnedMenuWindowVisible {
  param([Parameter(Mandatory)][IntPtr]$Handle)
  return [MIROwnedMenuNative]::IsWindowVisible($Handle)
}

function Test-MIROwnedMenuWindowIconic {
  param([Parameter(Mandatory)][IntPtr]$Handle)
  return [MIROwnedMenuNative]::IsIconic($Handle)
}

function Get-MIROwnedMenuForegroundHandle {
  return [MIROwnedMenuNative]::GetForegroundWindow()
}

function Get-MIROwnedMenuPointRoot {
  param([Parameter(Mandatory)][int]$X,[Parameter(Mandatory)][int]$Y)
  $probe = New-Object MIROwnedMenuNative+Point
  $probe.X=$X; $probe.Y=$Y
  $under=[MIROwnedMenuNative]::WindowFromPoint($probe)
  return [MIROwnedMenuNative]::GetAncestor($under,2)
}

function Get-MIROwnedMenuOcclusion {
  param([Parameter(Mandatory)][IntPtr]$Handle,[Parameter(Mandatory)][uint32]$OwnedProcessId,[Parameter(Mandatory)][int]$X,[Parameter(Mandatory)][int]$Y,[Parameter(Mandatory)][int]$Width,[Parameter(Mandatory)][int]$Height)
  $probeIndex=0
  foreach ($offset in @(@(1,1),@(($Width-2),1),@(1,($Height-2)),@(($Width-2),($Height-2)),@([int]($Width/2),[int]($Height/2)))) {
    $probeX=$X+$offset[0]; $probeY=$Y+$offset[1]
    $root=Get-MIROwnedMenuPointRoot -X $probeX -Y $probeY
    if ($root -ne $Handle) {
      # Record only our own geometry and a hit-test category. Never collect
      # foreign window identities, titles, text or pixels for this diagnostic.
      $relation=if($root-eq[IntPtr]::Zero){'unresolved'}else{Get-MIROwnedMenuHitProcessRelation -Handle $root -OwnedProcessId $OwnedProcessId}
      return [ordered]@{probe_index=$probeIndex;probe_x=$probeX;probe_y=$probeY;owned_x=$X;owned_y=$Y;owned_width=$Width;owned_height=$Height;hit=$(if($root-eq[IntPtr]::Zero){'no-window'}else{'other-window'});hit_process_relation=$relation}
    }
    $probeIndex++
  }
  return $null
}

function Get-MIROwnedMenuHitProcessRelation {
  param([Parameter(Mandatory)][IntPtr]$Handle,[Parameter(Mandatory)][uint32]$OwnedProcessId)
  # The native boundary exposes only success and equality, never another PID.
  [bool]$sameProcess=$false
  if (-not [MIROwnedMenuNative]::TrySameOwnedProcess($Handle,$OwnedProcessId,[ref]$sameProcess)) { return 'unresolved' }
  if ($sameProcess) { return 'owned-process' }
  return 'other-process'
}

function Set-MIROwnedMenuForegroundHandle {
  param([Parameter(Mandatory)][IntPtr]$Handle)
  return [MIROwnedMenuNative]::SetForegroundWindow($Handle)
}

function Request-MIROwnedMenuForeground {
  param(
    [Parameter(Mandatory)][Diagnostics.Process]$Process,
    [Parameter(Mandatory)][datetime]$ExpectedStartUtc,
    [Parameter(Mandatory)][IntPtr]$Handle,
    [Parameter(Mandatory)][Collections.IDictionary]$Diagnostics
  )
  $Process.Refresh()
  if ($Process.HasExited) { throw '[mir-menu-owned-process-exited]' }
  if ($Process.StartTime.ToUniversalTime() -ne $ExpectedStartUtc) { throw '[mir-menu-owned-process-identity]' }
  if ((Get-MIROwnedMenuWindowProcessId $Handle) -ne $Process.Id -or -not(Test-MIROwnedMenuWindowHandle $Handle)) { throw '[mir-menu-owned-window-identity]' }
  if (-not(Test-MIROwnedMenuWindowVisible $Handle) -or (Test-MIROwnedMenuWindowIconic $Handle)) {
    Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'not_visible_or_minimized'
    return $false
  }
  $Diagnostics.foreground_request_attempts=[int]$Diagnostics.foreground_request_attempts+1
  if (-not(Set-MIROwnedMenuForegroundHandle $Handle)) {
    Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'foreground_request_refused'
    return $false
  }
  if ((Get-MIROwnedMenuForegroundHandle) -ne $Handle) {
    Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'foreground_request_not_acquired'
    return $false
  }
  return $true
}

function Get-MIROwnedMenuWindow {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process, [Parameter(Mandatory)][datetime]$ExpectedStartUtc,[AllowNull()][Collections.IDictionary]$Diagnostics=$null,[switch]$AttemptForeground)
  $Process.Refresh()
  if ($Process.HasExited) { throw '[mir-menu-owned-process-exited]' }
  if ($Process.StartTime.ToUniversalTime() -ne $ExpectedStartUtc) { throw '[mir-menu-owned-process-identity]' }
  $handle = Get-MIROwnedMenuMainWindowHandle $Process
  if ($handle -eq [IntPtr]::Zero) { Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'no_main_window'; return $null }
  if ((Get-MIROwnedMenuWindowProcessId $handle) -ne $Process.Id -or -not(Test-MIROwnedMenuWindowHandle $handle)) { throw '[mir-menu-owned-window-identity]' }
  if (-not(Test-MIROwnedMenuWindowVisible $handle) -or (Test-MIROwnedMenuWindowIconic $handle)) { Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'not_visible_or_minimized'; return $null }
  if ((Get-MIROwnedMenuForegroundHandle) -ne $handle) {
    if ($AttemptForeground -and $null-ne$Diagnostics -and [int]$Diagnostics.foreground_request_attempts-eq0) {
      if (-not(Request-MIROwnedMenuForeground -Process $Process -ExpectedStartUtc $ExpectedStartUtc -Handle $handle -Diagnostics $Diagnostics)) { return $null }
    }
    if ((Get-MIROwnedMenuForegroundHandle) -ne $handle) { Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'foreground_mismatch'; return $null }
  }
  $rect = New-Object MIROwnedMenuNative+Rect
  $point = New-Object MIROwnedMenuNative+Point
  if (-not [MIROwnedMenuNative]::GetClientRect($handle, [ref]$rect) -or -not [MIROwnedMenuNative]::ClientToScreen($handle, [ref]$point)) { Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'client_geometry_unavailable'; return $null }
  $width = $rect.Right - $rect.Left; $height = $rect.Bottom - $rect.Top
  if ($width -lt 100 -or $height -lt 100 -or $width -gt 4096 -or $height -gt 4096) { throw '[mir-menu-owned-window-bounds]' }
  $screen = [Windows.Forms.SystemInformation]::VirtualScreen
  if ($point.X -lt $screen.Left -or $point.Y -lt $screen.Top -or $point.X + $width -gt $screen.Right -or $point.Y + $height -gt $screen.Bottom) { Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'offscreen'; return $null }
  # Reject covered capture regions, including a foreign always-on-top window.
  $occlusion=Get-MIROwnedMenuOcclusion -Handle $handle -OwnedProcessId $Process.Id -X $point.X -Y $point.Y -Width $width -Height $height
  if ($null-ne$occlusion) {
    if ($null-ne$Diagnostics) { $Diagnostics.last_occlusion=$occlusion }
    Add-MIROwnedMenuRejection -Diagnostics $Diagnostics -Name 'occluded'
    return $null
  }
  [pscustomobject]@{process_id=$Process.Id;start_utc=$ExpectedStartUtc.ToString('o');handle=$handle.ToInt64();x=$point.X;y=$point.Y;width=$width;height=$height}
}

function Save-MIROwnedMenuBitmapPng {
  param([Parameter(Mandatory)][Drawing.Bitmap]$Bitmap,[Parameter(Mandatory)][string]$Path)
  # The observer reuses this path on every capture.  Saving through an explicit
  # Create stream prevents bytes from an earlier, longer PNG surviving after
  # the new image's IEND chunk.
  $stream=$null
  $fullPath=[IO.Path]::GetFullPath($Path)
  try {
    $stream=[IO.File]::Open($fullPath,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $Bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
    $stream.Flush($true)
  } finally {
    if($null-ne$stream){$stream.Dispose()}
  }
  return $fullPath
}

function Save-MIROwnedMenuCapture {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$ExpectedStartUtc,[Parameter(Mandatory)][string]$Path,[AllowNull()][Collections.IDictionary]$Diagnostics=$null)
  if ($null-ne$Diagnostics) { $Diagnostics.capture_requests=[int]$Diagnostics.capture_requests+1 }
  $before = Get-MIROwnedMenuWindow -Process $Process -ExpectedStartUtc $ExpectedStartUtc -Diagnostics $Diagnostics -AttemptForeground
  if ($null -eq $before) { return $null }
  $startQpc = [Diagnostics.Stopwatch]::GetTimestamp()
  $bitmap = New-Object Drawing.Bitmap($before.width,$before.height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  try {
    # Ask only this owned HWND for its client pixels. Screen copying during
    # window animation can include the desktop beneath a translucent frame.
    # The outer governed actor bounds a stalled rendering API call.
    $dc = $graphics.GetHdc()
    try {
      if (-not [MIROwnedMenuNative]::PrintWindow([IntPtr]$before.handle,$dc,3)) { throw '[mir-menu-owned-window-capture-failed]' }
    } finally { $graphics.ReleaseHdc($dc) }
    $after = Get-MIROwnedMenuWindow -Process $Process -ExpectedStartUtc $ExpectedStartUtc -Diagnostics $Diagnostics
    if ($null -eq $after -or ($before | ConvertTo-Json -Compress) -cne ($after | ConvertTo-Json -Compress)) { return $null }
    $capturedPath=Save-MIROwnedMenuBitmapPng -Bitmap $bitmap -Path $Path
    if ($null-ne$Diagnostics) { $Diagnostics.captured_frames=[int]$Diagnostics.captured_frames+1 }
    [pscustomobject]@{window=$after;method='owned-hwnd-printwindow-client';capture_started_qpc=$startQpc;capture_completed_qpc=[Diagnostics.Stopwatch]::GetTimestamp();path=$capturedPath}
  } finally { $graphics.Dispose(); $bitmap.Dispose() }
}

function Send-MIROwnedMenuSettingsAction {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$ExpectedStartUtc,[Parameter(Mandatory)]$Capture,[Parameter(Mandatory)]$Observation,[AllowNull()][Collections.IDictionary]$Diagnostics=$null)
  $current = Get-MIROwnedMenuWindow -Process $Process -ExpectedStartUtc $ExpectedStartUtc -Diagnostics $Diagnostics
  if ($null -eq $current -or ($current | ConvertTo-Json -Compress) -cne ($Capture.window | ConvertTo-Json -Compress)) { throw '[mir-menu-owned-action-window-changed]' }
  if ($Observation.width -ne $current.width -or $Observation.height -ne $current.height) { throw '[mir-menu-owned-action-image-size]' }
  $target = Get-MIRMenuSettingsTarget $Observation
  $position = [IntPtr](([int64]$target.y -shl 16) -bor $target.x)
  $handle = [IntPtr]$current.handle
  $actionQpc = [Diagnostics.Stopwatch]::GetTimestamp()
  # Input targets only the exact owned HWND; no global pointer/keyboard injection.
  foreach ($message in @(0x0200,0x0201,0x0202)) {
    $buttons = if ($message -eq 0x0201) { [UIntPtr]::new([uint32]1) } else { [UIntPtr]::Zero }
    if (-not [MIROwnedMenuNative]::PostMessage($handle,[uint32]$message,$buttons,$position)) { throw '[mir-menu-owned-action-post-failed]' }
  }
  [pscustomobject]@{kind='owned-window-settings-click';process_id=$Process.Id;window_handle=$current.handle;x=$target.x;y=$target.y;posted_qpc=$actionQpc}
}

function Read-MIRMenuInitialisedLiveLog {
  param([Parameter(Mandatory)][string]$Path)
  # Factorio keeps its log writer open. Read with compatible sharing and a
  # bounded tail; a failed read is not an initialization observation.
  $stream=$null;$reader=$null
  try {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $null=$stream.Seek([Math]::Max(0,$stream.Length-65536),[IO.SeekOrigin]::Begin)
    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true,4096,$true)
    return $reader.ReadToEnd() -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$'
  } catch [IO.IOException] { return $false }
  finally { if($null-ne$reader){$reader.Dispose()};if($null-ne$stream){$stream.Dispose()} }
}

function Wait-MIROwnedMenuResponse {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$ExpectedStartUtc,[Parameter(Mandatory)]$Ocr,[Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][long]$LaunchQpc,[ValidateRange(1,300)][int]$TimeoutSeconds=30,[string]$RequiredInitialisedLog='',[AllowNull()][Collections.IDictionary]$Diagnostics=$null)
  if ($null-eq$Diagnostics) { $Diagnostics=New-MIROwnedMenuObserverDiagnostics }
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $firstMenu = $null; $action = $null; $response = $null; $attempts = 0; $maxObserverSeconds = 0.0
  $path = Join-Path $OutputRoot 'latest-owned-window.png'
  $initialisedLogObserved = $false
  while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    if ($Process.HasExited) { throw '[mir-menu-owned-process-exited-before-response]' }
    if ($RequiredInitialisedLog -and -not $initialisedLogObserved) {
      $ready = $false
      if (Test-Path -LiteralPath $RequiredInitialisedLog -PathType Leaf) {
        $ready = Read-MIRMenuInitialisedLiveLog -Path $RequiredInitialisedLog
      }
      if (-not $ready) { Start-Sleep -Milliseconds 100; continue }
      $initialisedLogObserved = $true
    }
    $observerTimer = [Diagnostics.Stopwatch]::StartNew()
    $capture = Save-MIROwnedMenuCapture -Process $Process -ExpectedStartUtc $ExpectedStartUtc -Path $path -Diagnostics $Diagnostics
    if ($null -eq $capture) { Start-Sleep -Milliseconds 100; continue }
    $observation = Read-MIRMenuImage $Ocr $capture.path
    $attempts++
    $state = Get-MIRMenuState $observation
    if ($state -eq 'blocked-or-loading') { throw '[mir-menu-blocked-or-loading-after-initialisation]' }
    if ($null -eq $action -and $state -eq 'main-menu') {
      $firstMenu = [pscustomobject]@{capture=$capture;ocr=$observation;observed_qpc=[Diagnostics.Stopwatch]::GetTimestamp()}
      $mainImage = Join-Path $OutputRoot 'main-menu.png'
      [IO.File]::Copy($path,$mainImage,$true)
      $firstMenu.capture.path = [IO.Path]::GetFullPath($mainImage)
      $firstMenu.capture | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-MIRMenuFileSha256 $mainImage)
      $action = Send-MIROwnedMenuSettingsAction -Process $Process -ExpectedStartUtc $ExpectedStartUtc -Capture $capture -Observation $observation -Diagnostics $Diagnostics
    } elseif ($null -ne $action -and $state -eq 'settings-menu') {
      $response = [pscustomobject]@{capture=$capture;ocr=$observation;observed_qpc=[Diagnostics.Stopwatch]::GetTimestamp()}
      $responseImage = Join-Path $OutputRoot 'settings-response.png'
      [IO.File]::Copy($path,$responseImage,$true)
      $response.capture.path = [IO.Path]::GetFullPath($responseImage)
      $response.capture | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-MIRMenuFileSha256 $responseImage)
    }
    $maxObserverSeconds = [Math]::Max($maxObserverSeconds,$observerTimer.Elapsed.TotalSeconds)
    if ($null -ne $response) {
      $frequency = [double][Diagnostics.Stopwatch]::Frequency
      return [pscustomobject]@{status='owned-menu-settings-response-observed';process_id=$Process.Id;launch_qpc=$LaunchQpc;clock_frequency=$frequency;first_render_observed_seconds=($firstMenu.observed_qpc-$LaunchQpc)/$frequency;confirmed_response_seconds=($response.observed_qpc-$LaunchQpc)/$frequency;interaction_response_seconds=($response.observed_qpc-$action.posted_qpc)/$frequency;observer_max_iteration_seconds=$maxObserverSeconds;poll_interval_milliseconds=100;capture_attempts=$attempts;first_menu=$firstMenu;action=$action;response=$response;claims_factorio_acceptance=$false}
    }
    Start-Sleep -Milliseconds 100
  }
  if ($null -ne $action) { throw '[mir-menu-rendered-but-no-settings-response]' }
  throw '[mir-menu-main-menu-not-observed]'
}
