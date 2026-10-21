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
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref Point p);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flag);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint message, UIntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
'@
}

function Get-MIROwnedMenuWindow {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process, [Parameter(Mandatory)][datetime]$ExpectedStartUtc)
  $Process.Refresh()
  if ($Process.HasExited) { throw '[mir-menu-owned-process-exited]' }
  if ($Process.StartTime.ToUniversalTime() -ne $ExpectedStartUtc) { throw '[mir-menu-owned-process-identity]' }
  $handle = $Process.MainWindowHandle
  if ($handle -eq [IntPtr]::Zero) { return $null }
  $ownerId = [uint32]0
  $null = [MIROwnedMenuNative]::GetWindowThreadProcessId($handle, [ref]$ownerId)
  if ($ownerId -ne $Process.Id -or -not [MIROwnedMenuNative]::IsWindow($handle)) { throw '[mir-menu-owned-window-identity]' }
  if (-not [MIROwnedMenuNative]::IsWindowVisible($handle) -or [MIROwnedMenuNative]::IsIconic($handle)) { return $null }
  if ([MIROwnedMenuNative]::GetForegroundWindow() -ne $handle) { return $null }
  $rect = New-Object MIROwnedMenuNative+Rect
  $point = New-Object MIROwnedMenuNative+Point
  if (-not [MIROwnedMenuNative]::GetClientRect($handle, [ref]$rect) -or -not [MIROwnedMenuNative]::ClientToScreen($handle, [ref]$point)) { return $null }
  $width = $rect.Right - $rect.Left; $height = $rect.Bottom - $rect.Top
  if ($width -lt 100 -or $height -lt 100 -or $width -gt 4096 -or $height -gt 4096) { throw '[mir-menu-owned-window-bounds]' }
  $screen = [Windows.Forms.SystemInformation]::VirtualScreen
  if ($point.X -lt $screen.Left -or $point.Y -lt $screen.Top -or $point.X + $width -gt $screen.Right -or $point.Y + $height -gt $screen.Bottom) { return $null }
  # Reject covered capture regions, including a foreign always-on-top window.
  foreach ($offset in @(@(1,1),@(($width-2),1),@(1,($height-2)),@(($width-2),($height-2)),@([int]($width/2),[int]($height/2)))) {
    $probe = New-Object MIROwnedMenuNative+Point
    $probe.X = $point.X + $offset[0]; $probe.Y = $point.Y + $offset[1]
    $under = [MIROwnedMenuNative]::WindowFromPoint($probe)
    if ([MIROwnedMenuNative]::GetAncestor($under, 2) -ne $handle) { return $null }
  }
  [pscustomobject]@{process_id=$Process.Id;start_utc=$ExpectedStartUtc.ToString('o');handle=$handle.ToInt64();x=$point.X;y=$point.Y;width=$width;height=$height}
}

function Save-MIROwnedMenuCapture {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$ExpectedStartUtc,[Parameter(Mandatory)][string]$Path)
  $before = Get-MIROwnedMenuWindow $Process $ExpectedStartUtc
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
    $after = Get-MIROwnedMenuWindow $Process $ExpectedStartUtc
    if ($null -eq $after -or ($before | ConvertTo-Json -Compress) -cne ($after | ConvertTo-Json -Compress)) { return $null }
    $bitmap.Save([IO.Path]::GetFullPath($Path),[Drawing.Imaging.ImageFormat]::Png)
    [pscustomobject]@{window=$after;method='owned-hwnd-printwindow-client';capture_started_qpc=$startQpc;capture_completed_qpc=[Diagnostics.Stopwatch]::GetTimestamp();path=[IO.Path]::GetFullPath($Path)}
  } finally { $graphics.Dispose(); $bitmap.Dispose() }
}

function Send-MIROwnedMenuSettingsAction {
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$ExpectedStartUtc,[Parameter(Mandatory)]$Capture,[Parameter(Mandatory)]$Observation)
  $current = Get-MIROwnedMenuWindow $Process $ExpectedStartUtc
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
  param([Parameter(Mandatory)][Diagnostics.Process]$Process,[Parameter(Mandatory)][datetime]$ExpectedStartUtc,[Parameter(Mandatory)]$Ocr,[Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][long]$LaunchQpc,[ValidateRange(1,300)][int]$TimeoutSeconds=30,[string]$RequiredInitialisedLog='')
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
    $capture = Save-MIROwnedMenuCapture $Process $ExpectedStartUtc $path
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
      $action = Send-MIROwnedMenuSettingsAction $Process $ExpectedStartUtc $capture $observation
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
