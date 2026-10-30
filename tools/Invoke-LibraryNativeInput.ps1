# A bounded input child for an already governed, owned native client. This
# neither launches Factorio nor grants library, save or release authority.
param(
  [Parameter(Mandatory)][string]$SpecPath,
  [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$SpecSha256,
  [Parameter(Mandatory)][string]$OutputRoot,
  [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function Assert-LibraryInput([bool]$Condition,[string]$Message){if(-not$Condition){throw "[mir-library-input] $Message"}}
function Test-LibraryInputInteger($Value){return $Value-is[int] -or $Value-is[long]}
function Get-LibraryInputDragSchedule([System.Collections.IDictionary]$Spec){
  # Keep the native drag finite and inspectable.  The two settled holds are an
  # asynchronous mouse-delivery hypothesis, not a native-game observation.
  Assert-LibraryInput ($Spec.action-ceq'drag') 'drag schedule requires drag action'
  $schedule=[System.Collections.Generic.List[object]]::new()
  $null=$schedule.Add([ordered]@{operation='move';x=[int]$Spec.x;y=[int]$Spec.y})
  $null=$schedule.Add([ordered]@{operation='mouse';down=$true})
  $null=$schedule.Add([ordered]@{operation='pause';milliseconds=100})
  for($step=1;$step-le4;$step++){
    $null=$schedule.Add([ordered]@{operation='pause';milliseconds=40})
    $null=$schedule.Add([ordered]@{operation='move';x=[int][Math]::Round($Spec.x+($Spec.target_x-$Spec.x)*$step/4.0);y=[int][Math]::Round($Spec.y+($Spec.target_y-$Spec.y)*$step/4.0)})
  }
  $null=$schedule.Add([ordered]@{operation='pause';milliseconds=100})
  $null=$schedule.Add([ordered]@{operation='assert-window'})
  $null=$schedule.Add([ordered]@{operation='mouse';down=$false})
  return $schedule.ToArray()
}
function Invoke-LibraryInputDragSchedule{
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Spec,
    [Parameter(Mandatory)][scriptblock]$MovePointer,
    [Parameter(Mandatory)][scriptblock]$Pause,
    [Parameter(Mandatory)][scriptblock]$AssertWindow,
    [Parameter(Mandatory)][scriptblock]$MouseButton,
    [Parameter(Mandatory)][ref]$Sent,
    [Parameter(Mandatory)][ref]$MouseHeld
  )
  foreach($entry in @(Get-LibraryInputDragSchedule $Spec)){
    switch([string]$entry.operation){
      'move'{& $MovePointer ([int]$entry.x) ([int]$entry.y)}
      'pause'{& $Pause ([int]$entry.milliseconds)}
      'assert-window'{& $AssertWindow}
      'mouse'{
        $n=& $MouseButton ([bool]$entry.down);$Sent.Value+=$n
        if([bool]$entry.down){
          $MouseHeld.Value=($n-eq1);Assert-LibraryInput $MouseHeld.Value 'mouse down incomplete'
        }else{
          $MouseHeld.Value=($n-ne1);Assert-LibraryInput ($n-eq1) 'mouse up incomplete'
        }
      }
      default{throw '[mir-library-input] drag schedule operation differs'}
    }
  }
}
function Assert-LibraryInputPlan([System.Collections.IDictionary]$Spec){
  $common=@('schema','kind','role','process_id','process_start_utc','engine_sha256','action','client_width','client_height')
  Assert-LibraryInput ($Spec.Contains('action') -and $Spec.action-is[string] -and $Spec.action-cin@('escape','inventory','text','click','drag')) 'action differs'
  $extra=switch($Spec.action){'text'{@('text')};'click'{@('x','y')};'drag'{@('x','y','target_x','target_y')};default{@()}}
  $expected=@($common)+@($extra)
  Assert-LibraryInput ($Spec.Count-eq$expected.Count -and ((@($Spec.Keys|Sort-Object)-join'|')-ceq(@($expected|Sort-Object)-join'|'))) 'fields differ'
  Assert-LibraryInput ((Test-LibraryInputInteger $Spec.schema) -and $Spec.schema-eq1 -and $Spec.kind-is[string] -and $Spec.kind-ceq'MIRLibraryNativeInputV1') 'schema differs'
  Assert-LibraryInput ($Spec.role-is[string] -and $Spec.role-cin@('client-en','client-de')) 'client role differs'
  Assert-LibraryInput ((Test-LibraryInputInteger $Spec.process_id) -and $Spec.process_id-gt0 -and $Spec.process_id-le[int]::MaxValue) 'process identity differs'
  $parsed=[datetimeoffset]::MinValue
  Assert-LibraryInput ($Spec.process_start_utc-is[string] -and $Spec.process_start_utc.EndsWith('Z') -and [datetimeoffset]::TryParse($Spec.process_start_utc,[ref]$parsed)) 'start time differs'
  Assert-LibraryInput ($Spec.engine_sha256-is[string] -and $Spec.engine_sha256-cmatch'^[A-F0-9]{64}$') 'engine hash differs'
  Assert-LibraryInput ((Test-LibraryInputInteger $Spec.client_width) -and (Test-LibraryInputInteger $Spec.client_height) -and $Spec.client_width-eq1280 -and $Spec.client_height-eq720) 'client geometry differs'
  if($Spec.action-ceq'text'){
    Assert-LibraryInput ($Spec.text-is[string] -and $Spec.text.Length-ge1 -and $Spec.text.Length-le32 -and $Spec.text-cmatch'\A[A-Za-z0-9 -]+\z') 'text differs'
  }
  if($Spec.action-cin@('click','drag')){
    foreach($name in @('x','y')){Assert-LibraryInput (Test-LibraryInputInteger $Spec[$name]) 'point type differs'}
    Assert-LibraryInput ($Spec.x-ge2 -and $Spec.x-lt1278 -and $Spec.y-ge2 -and $Spec.y-lt718) 'point outside client'
  }
  if($Spec.action-ceq'drag'){
    foreach($name in @('target_x','target_y')){Assert-LibraryInput (Test-LibraryInputInteger $Spec[$name]) 'drag point type differs'}
    Assert-LibraryInput ($Spec.target_x-ge2 -and $Spec.target_x-lt1278 -and $Spec.target_y-ge2 -and $Spec.target_y-lt718) 'drag outside client'
    $dx=$Spec.target_x-$Spec.x;$dy=$Spec.target_y-$Spec.y
    Assert-LibraryInput ([Math]::Abs($dx)-le80 -and [Math]::Abs($dy)-le80 -and ($dx-ne0 -or $dy-ne0)) 'drag distance differs'
  }
}

$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$specFile=(Resolve-Path -LiteralPath $SpecPath).Path
Assert-LibraryInput ((Get-FileHash -LiteralPath $specFile -Algorithm SHA256).Hash-ceq$SpecSha256.ToUpperInvariant()) 'spec hash differs'
$spec=Get-Content -LiteralPath $specFile -Raw|ConvertFrom-Json -AsHashtable -DateKind String
Assert-LibraryInputPlan $spec
if($ValidateOnly){
  [ordered]@{status='validated-schema-only';action=$spec.action;native_input_sent=$false;native_process_identity_checked=$false}|ConvertTo-Json
  return
}
$output=[IO.Path]::GetFullPath($OutputRoot)
$allowedRoots=@((Join-Path $repo 'build/tmp'),(Join-Path $repo 'build/qualification'))
Assert-LibraryInput (@($allowedRoots|Where-Object {$output.StartsWith($_+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)}).Count-eq1) 'output outside owned build roots'
$receipt=Join-Path $output 'input-actor-result.json'
Assert-LibraryInput (-not(Test-Path -LiteralPath $receipt)) 'preserve existing receipt'
$null=[IO.Directory]::CreateDirectory($output)
. (Join-Path $repo 'tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1')
Initialize-MIROwnedMenuWindow
if($null-eq('MIRLibraryInputNative'-as[type])){
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MIRLibraryInputNative {
  [StructLayout(LayoutKind.Sequential)] public struct Mouse { public int x,y; public uint data,flags,time; public UIntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] public struct Key { public ushort vk,scan; public uint flags,time; public UIntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] public struct Payload { [FieldOffset(0)] public Mouse mouse; [FieldOffset(0)] public Key key; }
  [StructLayout(LayoutKind.Sequential)] public struct Input { public uint type; public Payload payload; }
  [DllImport("user32.dll",SetLastError=true)] public static extern uint SendInput(uint count,Input[] input,int size);
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int x,y; }
  [DllImport("user32.dll",SetLastError=true)] public static extern bool SetPhysicalCursorPos(int x,int y);
  [DllImport("user32.dll",SetLastError=true)] public static extern bool GetPhysicalCursorPos(out Point point);
  public static int InputSize() { return Marshal.SizeOf(typeof(Input)); }
  public static Point SetAndReadPhysicalCursorPos(int x,int y) {
    if(!SetPhysicalCursorPos(x,y)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"SetPhysicalCursorPos");
    Point actual;
    if(!GetPhysicalCursorPos(out actual)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"GetPhysicalCursorPos");
    return actual;
  }
  public static uint KeyPair(ushort value,bool unicode) {
    Input down=new Input();down.type=1;
    if(unicode){down.payload.key.scan=value;down.payload.key.flags=4;}else{down.payload.key.vk=value;}
    Input up=down;up.payload.key.flags|=2;
    return SendInput(2,new Input[]{down,up},InputSize());
  }
  public static uint MouseButton(bool down) {
    Input value=new Input();value.type=0;value.payload.mouse.flags=down?2u:4u;
    return SendInput(1,new Input[]{value},InputSize());
  }
}
'@
}
$client=$null;$mouseHeld=$false;$sent=0;$failure='';$window=$null
$physicalPointerPositions=[System.Collections.Generic.List[object]]::new()
$diagnostics=New-MIROwnedMenuObserverDiagnostics
$result=[ordered]@{kind='MIRLibraryNativeInputReceiptV1';status='started';spec_sha256=$SpecSha256.ToUpperInvariant();role=$spec.role;process_id=$spec.process_id;process_start_utc=$spec.process_start_utc;engine_sha256=$spec.engine_sha256;action=$spec.action;native_game_observation=$false;release_qualification=$false}
try{
  $client=Get-Process -Id ([int]$spec.process_id)
  $expectedStart=[datetimeoffset]::Parse($spec.process_start_utc).UtcDateTime
  Assert-LibraryInput ($client.StartTime.ToUniversalTime()-eq$expectedStart) 'client start differs'
  $engine=$client.MainModule.FileName
  Assert-LibraryInput ([IO.Path]::GetFileName($engine)-ceq'factorio.exe' -and (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash-ceq$spec.engine_sha256) 'actual client executable differs'
  $window=Get-MIROwnedMenuWindow -Process $client -ExpectedStartUtc $expectedStart -Diagnostics $diagnostics -AttemptForeground
  Assert-LibraryInput ($null-ne$window -and $window.width-eq$spec.client_width -and $window.height-eq$spec.client_height) 'owned foreground client unavailable'
  function Assert-CurrentInputWindow {
    $current=Get-MIROwnedMenuWindow -Process $client -ExpectedStartUtc $expectedStart -Diagnostics $diagnostics
    Assert-LibraryInput ($null-ne$current -and ($current|ConvertTo-Json -Compress)-ceq($window|ConvertTo-Json -Compress)) 'owned client window changed'
  }
  function Move-InputPointer([int]$X,[int]$Y){
    Assert-CurrentInputWindow
    $absoluteX=[int]($window.x+$X);$absoluteY=[int]($window.y+$Y)
    $physical=[MIRLibraryInputNative]::SetAndReadPhysicalCursorPos($absoluteX,$absoluteY)
    $null=$physicalPointerPositions.Add([ordered]@{requested_physical=[ordered]@{x=$absoluteX;y=$absoluteY};observed_physical=[ordered]@{x=[int]$physical.x;y=[int]$physical.y}})
    Assert-LibraryInput ($physical.x-eq$absoluteX -and $physical.y-eq$absoluteY) 'physical pointer readback differs'
    Assert-LibraryInput ((Get-MIROwnedMenuPointRoot -X $absoluteX -Y $absoluteY)-eq[IntPtr]$window.handle) 'pointer target is not owned'
  }
  switch($spec.action){
    'escape'{Assert-CurrentInputWindow;$n=[MIRLibraryInputNative]::KeyPair(0x1b,$false);$sent+=$n;Assert-LibraryInput ($n-eq2) 'Esc injection incomplete'}
    'inventory'{Assert-CurrentInputWindow;$n=[MIRLibraryInputNative]::KeyPair(0x45,$false);$sent+=$n;Assert-LibraryInput ($n-eq2) 'E injection incomplete'}
    'text'{foreach($character in $spec.text.ToCharArray()){
      Assert-CurrentInputWindow;$n=[MIRLibraryInputNative]::KeyPair([uint16]$character,$true);$sent+=$n
      Assert-LibraryInput ($n-eq2) 'text injection incomplete';Start-Sleep -Milliseconds 35
    }}
    'click'{
      Move-InputPointer $spec.x $spec.y
      $n=[MIRLibraryInputNative]::MouseButton($true);$sent+=$n;$mouseHeld=($n-eq1)
      Assert-LibraryInput $mouseHeld 'mouse down incomplete'
      Assert-CurrentInputWindow
      $n=[MIRLibraryInputNative]::MouseButton($false);$sent+=$n;$mouseHeld=($n-ne1)
      Assert-LibraryInput ($n-eq1) 'mouse up incomplete'
    }
    'drag'{
      Invoke-LibraryInputDragSchedule -Spec $spec -MovePointer {param([int]$X,[int]$Y)Move-InputPointer $X $Y} -Pause {param([int]$Milliseconds)Start-Sleep -Milliseconds $Milliseconds} -AssertWindow {Assert-CurrentInputWindow} -MouseButton {param([bool]$Down)[MIRLibraryInputNative]::MouseButton($Down)} -Sent ([ref]$sent) -MouseHeld ([ref]$mouseHeld)
    }
  }
  Assert-CurrentInputWindow
  $result.status='input-sent-native-readback-required'
}catch{
  $failure=$_.Exception.Message;$result.status='failed';throw
}finally{
  if($mouseHeld){$null=[MIRLibraryInputNative]::MouseButton($false)}
  $result.failure=$failure;$result.input_events_sent=$sent;$result.window=$window;$result.window_diagnostics=$diagnostics;$result.physical_pointer_positions=$physicalPointerPositions.ToArray()
  $result.input_method='Windows SendInput with physical-cursor readback;owned foreground PID/start/engine/geometry/hit-test checked;no Factorio events raised'
  $result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $receipt -Encoding utf8
  if($null-ne$client){$client.Dispose()}
}
$result|ConvertTo-Json -Depth 12
