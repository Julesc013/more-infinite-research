"""Host input-plan and native interop controls; never send desktop input."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ACTOR = ROOT / "tools/Invoke-LibraryNativeInput.ps1"


class LibraryNativeInputControls(unittest.TestCase):
    def test_actual_plan_validator_refuses_wrong_identity_shape_actions_and_bounds(self):
        base = {"schema": 1, "kind": "MIRLibraryNativeInputV1", "role": "client-en", "process_id": 12345,
                "process_start_utc": "2026-10-29T09:00:00.1234567Z", "engine_sha256": "A" * 64,
                "client_width": 1280, "client_height": 720, "action": "escape"}
        accepted = [base, {**base, "action": "inventory"}, {**base, "action": "text", "text": "gears"},
                    {**base, "action": "click", "x": 600, "y": 150},
                    {**base, "action": "drag", "x": 950, "y": 130, "target_x": 920, "target_y": 100}]
        rejected = []
        for key, value in (("schema", True), ("schema", "1"), ("kind", [base["kind"]]), ("role", "server"),
                           ("process_id", "12345"), ("process_id", 0), ("process_start_utc", "not-a-date"),
                           ("process_start_utc", "2026-10-29T09:00:00+11:00"), ("engine_sha256", "bad"),
                           ("action", "console"), ("client_width", 1920), ("client_height", "720")):
            rejected.append({**base, key: value})
        rejected.extend([{**base, "extra": True}, {k: v for k, v in base.items() if k != "role"}])
        for text in ("", "a" * 33, "gears\n", "{ENTER}", "~", "☃"):
            rejected.append({**base, "action": "text", "text": text})
        for point in ((0, 150), (600, 720), ("600", 150)):
            rejected.append({**base, "action": "click", "x": point[0], "y": point[1]})
        for target in ((950, 130), (1031, 130), (950, 211), (1280, 100)):
            rejected.append({**base, "action": "drag", "x": 950, "y": 130, "target_x": target[0], "target_y": target[1]})
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_INPUT_ACTOR,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'input actor parse failed'}
          foreach($name in @('Assert-LibraryInput','Test-LibraryInputInteger','Assert-LibraryInputPlan')){
            $node=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
            if($node.Count-ne1){throw 'validator definition missing or ambiguous'}
            Invoke-Expression $node[0].Extent.Text
          }
          $cases=Get-Content -LiteralPath $env:MIR_INPUT_CASES -Raw|ConvertFrom-Json -AsHashtable -DateKind String
          foreach($case in $cases.accepted){Assert-LibraryInputPlan $case}
          foreach($case in $cases.rejected){
            $rejected=$false;try{Assert-LibraryInputPlan $case}catch{$rejected=$true}
            if(-not$rejected){throw ('accepted an invalid input plan: '+($case|ConvertTo-Json -Compress))}
          }
          # Compile exactly the actor's interop definition, but call no input or
          # window API. Verify the native INPUT union layout and the physical
          # cursor contract on this platform.
          $typeCommand=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]-and$n.GetCommandName()-ceq'Add-Type'-and$n.Extent.Text.Contains('public static class MIRLibraryInputNative')},$true))
          if($typeCommand.Count-ne1){throw 'input native declaration missing'}
          Add-Type -TypeDefinition $typeCommand[0].CommandElements[-1].Value
          $size=[MIRLibraryInputNative]::InputSize()
          if($size-ne$(if([IntPtr]::Size-eq8){40}else{28})){throw 'native INPUT layout differs'}
          $physical=[MIRLibraryInputNative].GetMethod('SetAndReadPhysicalCursorPos')
          if($null-eq$physical-or$physical.ReturnType.FullName-ne'MIRLibraryInputNative+Point'){throw 'physical cursor contract differs'}
          foreach($scan in @(1,0x12)){foreach($down in @($true,$false)){
            $input=[MIRLibraryInputNative]::HardwareInput($scan,$down)
            if($input.type-ne1-or$input.payload.key.vk-ne0-or$input.payload.key.scan-ne$scan-or$input.payload.key.flags-ne$(if($down){8}else{10})){throw 'hardware INPUT layout differs'}
          }}
          foreach($scan in @(0,0x101)){$refused=$false;try{$null=[MIRLibraryInputNative]::HardwareInput($scan,$true)}catch{$refused=$true};if(-not$refused){throw 'invalid hardware scan accepted'}}
          'PASS exact validators, native INPUT layout and physical cursor contract;zero desktop input'
        '''
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "cases.json"
            path.write_text(json.dumps({"accepted": accepted, "rejected": rejected}), encoding="utf-8")
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                    env={**os.environ, "MIR_INPUT_ACTOR": str(ACTOR), "MIR_INPUT_CASES": str(path)},
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actual_validate_only_checks_hash_and_claims_no_native_identity_or_input(self):
        spec = {"schema": 1, "kind": "MIRLibraryNativeInputV1", "role": "client-de", "process_id": 12345,
                "process_start_utc": "2026-10-29T09:00:00Z", "engine_sha256": "B" * 64,
                "client_width": 1280, "client_height": 720, "action": "text", "text": "mining"}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "input.json"
            path.write_bytes((json.dumps(spec) + "\n").encode())
            sha = hashlib.sha256(path.read_bytes()).hexdigest().upper()
            command = ["pwsh", "-NoProfile", "-File", str(ACTOR), "-SpecPath", str(path),
                       "-SpecSha256", sha, "-OutputRoot", str(Path(temporary) / "output"), "-ValidateOnly"]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            observed = json.loads(result.stdout)
            self.assertEqual(observed, {"status": "validated-schema-only", "action": "text", "native_input_sent": False,
                                        "native_process_identity_checked": False})
            self.assertFalse((Path(temporary) / "output").exists())
            bad = copy.copy(command)
            bad[bad.index(sha)] = "C" * 64
            rejected = subprocess.run(bad, cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("spec hash differs", rejected.stderr)

    def test_actual_drag_schedule_holds_before_first_move_and_before_release_without_desktop_input(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class MIRLibraryInputNative {
  public struct Point { public int x,y; }
  public static List<string> Events=new List<string>();
  public static int Calls=0, MismatchOn=0;
  public static void Reset(int mismatchOn) { Events.Clear(); Calls=0; MismatchOn=mismatchOn; }
  public static Point SetAndReadPhysicalCursorPos(int x,int y) {
    Calls++; Events.Add("point:"+x+","+y);
    return new Point { x=(Calls==MismatchOn ? x+1 : x), y=y };
  }
  public static uint MouseButton(bool down) { Events.Add(down ? "down" : "up"); return 1; }
  public static string[] ReadEvents() { return Events.ToArray(); }
}
'@
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_INPUT_ACTOR,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'input actor parse failed'}
          foreach($name in @('Assert-LibraryInput','Get-LibraryInputDragSchedule','Invoke-LibraryInputDragSchedule','Move-InputPointer')){
            $node=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
            if($node.Count-ne1){throw "drag helper definition missing or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $try=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.TryStatementAst]},$true))
          if($try.Count-ne1-or$null-eq$try[0].Finally){throw 'actual actor finally missing or ambiguous'}
          $actualFinally=(@($try[0].Finally.Statements|ForEach-Object {$_.Extent.Text})-join"`n")
          $spec=[ordered]@{
            schema=1;kind='MIRLibraryNativeInputV1';role='client-en';process_id=12345
            process_start_utc='2026-10-29T09:00:00.1234567Z';engine_sha256=('A'*64)
            action='drag';client_width=1280;client_height=720;x=950;y=130;target_x=920;target_y=100
          }
          $schedule=@(Get-LibraryInputDragSchedule $spec)
          $expected=@(
            @{operation='move';x=950;y=130},
            @{operation='mouse';down=$true},
            @{operation='pause';milliseconds=100},
            @{operation='pause';milliseconds=40},@{operation='move';x=942;y=122},
            @{operation='pause';milliseconds=40},@{operation='move';x=935;y=115},
            @{operation='pause';milliseconds=40},@{operation='move';x=928;y=108},
            @{operation='pause';milliseconds=40},@{operation='move';x=920;y=100},
            @{operation='pause';milliseconds=100},
            @{operation='assert-window'},
            @{operation='mouse';down=$false}
          )
          if($schedule.Count-ne$expected.Count){throw "drag schedule count differs: $($schedule.Count)"}
          for($index=0;$index-lt$expected.Count;$index++){
            $actual=((@($schedule[$index].Keys|Sort-Object)|ForEach-Object {"$_=$($schedule[$index][$_])"})-join'|')
            $want=((@($expected[$index].Keys|Sort-Object)|ForEach-Object {"$_=$($expected[$index][$_])"})-join'|')
            if($actual-ne$want){throw "drag schedule differs at ${index}: $actual != $want"}
          }
          function Assert-CurrentInputWindow { $script:windowChecks++ }
          function Get-MIROwnedMenuPointRoot { param([int]$X,[int]$Y) return [IntPtr]42 }
          function Start-Sleep { param([int]$Milliseconds) [MIRLibraryInputNative]::Events.Add("pause:$Milliseconds") }
          function Invoke-ActualDrag([int]$MismatchOn,[string]$Receipt) {
            [MIRLibraryInputNative]::Reset($MismatchOn)
            $script:windowChecks=0
            $script:window=[pscustomobject]@{x=100;y=200;handle=42}
            $script:physicalPointerPositions=[System.Collections.Generic.List[object]]::new()
            $sent=0;$mouseHeld=$false;$failure='';$diagnostics=[ordered]@{}
            $heldHardwareScan=[uint16]0;$hardwareKeyEvents=[Collections.Generic.List[object]]::new()
            $result=[ordered]@{status='started'};$receipt=$Receipt;$client=$null
            $failed=$false
            try {
              $null=Invoke-LibraryInputDragSchedule -Spec $spec -MovePointer {param([int]$X,[int]$Y)Move-InputPointer $X $Y} -Pause {param([int]$Milliseconds)Start-Sleep -Milliseconds $Milliseconds} -AssertWindow {Assert-CurrentInputWindow} -MouseButton {param([bool]$Down)[MIRLibraryInputNative]::MouseButton($Down)} -Sent ([ref]$sent) -MouseHeld ([ref]$mouseHeld)
            } catch {
              $failed=$true;$failure=$_.Exception.Message;$result.status='failed'
            }
            # The production actor runs its finally at script scope.  Mirror that
            # scope exactly while executing the extracted production finally body.
            $script:mouseHeld=$mouseHeld;$script:sent=$sent;$script:failure=$failure;$script:result=$result
            $script:receipt=$receipt;$script:window=$window;$script:diagnostics=$diagnostics;$script:client=$client
            $script:heldHardwareScan=$heldHardwareScan;$script:hardwareKeyEvents=$hardwareKeyEvents
            $null=Invoke-Expression $script:actualFinally
            [pscustomobject]@{
              failed=$failed;failure=$failure;sent=$sent;mouse_held=$mouseHeld
              events=@([MIRLibraryInputNative]::ReadEvents());positions=$script:physicalPointerPositions.ToArray()
              checks=$script:windowChecks;receipt=$Receipt
            }
          }
          $normal=Invoke-ActualDrag -MismatchOn 0 -Receipt (Join-Path $env:MIR_INPUT_OUTPUT 'normal.json')
          if($normal.failed-or$normal.sent-ne2-or$normal.mouse_held){throw "normal actual drag execution differs: failed=$($normal.failed) sent=$($normal.sent) held=$($normal.mouse_held) failure=$($normal.failure)"}
          $normalExpected=@('point:1050,330','down','pause:100','pause:40','point:1042,322','pause:40','point:1035,315','pause:40','point:1028,308','pause:40','point:1020,300','pause:100','up')
          if((@($normal.events)-join'|')-ne($normalExpected-join'|')){throw ('normal actual drag order differs: '+(@($normal.events)-join'|'))}
          if($normal.positions.Count-ne5-or$normal.positions[-1].requested_physical.x-ne1020-or$normal.positions[-1].requested_physical.y-ne300-or$normal.positions[-1].observed_physical.x-ne1020-or$normal.positions[-1].observed_physical.y-ne300){throw 'normal physical position receipt differs'}
          $mismatch=Invoke-ActualDrag -MismatchOn 2 -Receipt (Join-Path $env:MIR_INPUT_OUTPUT 'mismatch.json')
          if(-not$mismatch.failed-or$mismatch.failure-notmatch'physical pointer readback differs' -or$mismatch.sent-ne1){throw "physical mismatch did not fail closed: failed=$($mismatch.failed) failure=$($mismatch.failure) sent=$($mismatch.sent) held=$($mismatch.mouse_held)"}
          if((@($mismatch.events)-join'|')-ne'point:1050,330|down|pause:100|pause:40|point:1042,322|up'){throw ('physical mismatch did not release the held button exactly once: '+(@($mismatch.events)-join'|'))}
          if($mismatch.positions.Count-ne2-or$mismatch.positions[1].requested_physical.x-ne1042-or$mismatch.positions[1].observed_physical.x-ne1043){throw 'physical mismatch receipt differs'}
          $mismatchReceipt=Get-Content -LiteralPath $mismatch.receipt -Raw|ConvertFrom-Json
          if($mismatchReceipt.status-ne'failed'-or$mismatchReceipt.input_events_sent-ne1-or$mismatchReceipt.physical_pointer_positions.Count-ne2){throw 'actual finally receipt differs'}
          $actor=Get-Content -LiteralPath $env:MIR_INPUT_ACTOR -Raw
          foreach($required in @(
            "'drag'{",
            'Invoke-LibraryInputDragSchedule -Spec $spec',
            '$n=& $MouseButton ([bool]$entry.down);$Sent.Value+=$n',
            '$physical=[MIRLibraryInputNative]::SetAndReadPhysicalCursorPos($absoluteX,$absoluteY)',
            "'physical pointer readback differs'",
            '$result.physical_pointer_positions=$physicalPointerPositions.ToArray()',
            'if($mouseHeld){$null=[MIRLibraryInputNative]::MouseButton($false)}'
          )){if(-not$actor.Contains($required)){throw "actual actor dispatch/teardown differs: $required"}}
          'PASS actual finite drag dispatch, physical receipt and mismatch cleanup;zero desktop input'
        '''
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                    env={**os.environ, "MIR_INPUT_ACTOR": str(ACTOR), "MIR_INPUT_OUTPUT": temporary},
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("zero desktop input", result.stdout)

    def test_actual_hardware_key_hold_and_finally_release_without_desktop_input(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class MIRLibraryInputNative {
  public static List<string> Events=new List<string>();
  public static uint HardwareKey(ushort scan,bool down) { Events.Add("cleanup:"+scan+":"+down); return 1; }
}
'@
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_INPUT_ACTOR,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'input actor parse failed'}
          foreach($name in @('Assert-LibraryInput','Test-LibraryInputInteger','Invoke-LibraryInputHardwareKey')){
            $node=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
            if($node.Count-ne1){throw 'hardware helper missing or ambiguous'};Invoke-Expression $node[0].Extent.Text
          }
          $try=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.TryStatementAst]},$true))
          if($try.Count-ne1){throw 'actor finally differs'}
          $actualFinally=(@($try[0].Finally.Statements|ForEach-Object {$_.Extent.Text})-join"`n")
          foreach($case in @('escape','inventory','lost-window','zero-map','down-failed','up-failed')){
            [MIRLibraryInputNative]::Events.Clear();$script:checks=0
            $action=if($case-ceq'inventory'){'inventory'}else{'escape'}
            $script:sent=0;$script:heldHardwareScan=[uint16]0;$script:mouseHeld=$false
            $script:hardwareKeyEvents=[Collections.Generic.List[object]]::new()
            $script:physicalPointerPositions=[Collections.Generic.List[object]]::new()
            $script:failure='';$script:result=[ordered]@{status='started'};$script:window=$null;$script:diagnostics=@{};$script:client=$null
            $script:receipt=Join-Path $env:MIR_INPUT_OUTPUT ($case+'.json')
            $failed=$false
            try{
              Invoke-LibraryInputHardwareKey -Action $action -ResolveScan {
                param([uint16]$VirtualKey)
                [MIRLibraryInputNative]::Events.Add("map:$VirtualKey")
                if($case-ceq'zero-map'){return 0};if($VirtualKey-eq0x1b){return 1};if($VirtualKey-eq0x45){return 0x12};throw 'unexpected virtual key'
              } -KeyEvent {
                param([uint16]$Scan,[bool]$Down)
                [MIRLibraryInputNative]::Events.Add("key:${Scan}:$Down")
                if(($case-ceq'down-failed'-and$Down)-or($case-ceq'up-failed'-and-not$Down)){return 0};return 1
              } -Pause {
                param([int]$Milliseconds)
                if($Milliseconds-ne100){throw 'hold differs'};[MIRLibraryInputNative]::Events.Add("pause:$Milliseconds")
              } -AssertWindow {
                $script:checks++;[MIRLibraryInputNative]::Events.Add('window')
                if($case-ceq'lost-window'-and$script:checks-eq2){throw 'owned window changed'}
              } -Sent ([ref]$script:sent) -HeldScan ([ref]$script:heldHardwareScan) -Events $script:hardwareKeyEvents
            }catch{$failed=$true;$script:failure=$_.Exception.Message;$script:result.status='failed'}
            $null=Invoke-Expression $actualFinally
            $events=@([MIRLibraryInputNative]::Events.ToArray())-join'|'
            $expected=switch($case){
              'escape'{'window|map:27|key:1:True|pause:100|window|key:1:False'}
              'inventory'{'window|map:69|key:18:True|pause:100|window|key:18:False'}
              'lost-window'{'window|map:27|key:1:True|pause:100|window|cleanup:1:False'}
              'zero-map'{'window|map:27'}
              'down-failed'{'window|map:27|key:1:True'}
              'up-failed'{'window|map:27|key:1:True|pause:100|window|key:1:False|cleanup:1:False'}
            }
            if($events-cne$expected){throw "hardware event order differs ${case}: $events"}
            if($failed-ne($case-cnotin@('escape','inventory'))){throw 'hardware failure classification differs'}
            $r=Get-Content -LiteralPath $script:receipt -Raw|ConvertFrom-Json
            $expectedSent=if($case-cin@('zero-map','down-failed')){0}else{2}
            if($r.input_events_sent-ne$expectedSent-or$r.hardware_key_still_held){throw 'hardware cleanup receipt differs'}
            if($case-cin@('lost-window','up-failed')){if(-not$r.hardware_key_events[-1].cleanup){throw 'cleanup not recorded'}}
          }
          'PASS actual hardware key dispatch and finally cleanup;zero desktop input'
        '''
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                    env={**os.environ, "MIR_INPUT_ACTOR": str(ACTOR), "MIR_INPUT_OUTPUT": temporary},
                                    capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("zero desktop input", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
