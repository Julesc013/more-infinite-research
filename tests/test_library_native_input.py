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
          $physical=[MIRLibraryInputNative].GetMethod('SetAndVerifyPhysicalCursorPos')
          if($null-eq$physical-or$physical.ReturnType.FullName-ne'MIRLibraryInputNative+Point'){throw 'physical cursor contract differs'}
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
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_INPUT_ACTOR,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'input actor parse failed'}
          foreach($name in @('Assert-LibraryInput','Get-LibraryInputDragSchedule')){
            $node=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.FunctionDefinitionAst]-and$n.Name-ceq$name},$true))
            if($node.Count-ne1){throw "drag helper definition missing or ambiguous: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
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
          $actor=Get-Content -LiteralPath $env:MIR_INPUT_ACTOR -Raw
          foreach($required in @(
            '$schedule=@(Get-LibraryInputDragSchedule $spec)',
            "'drag'{",
            '$n=[MIRLibraryInputNative]::MouseButton([bool]$entry.down);$sent+=$n',
            '$physical=[MIRLibraryInputNative]::SetAndVerifyPhysicalCursorPos($absoluteX,$absoluteY)',
            "'physical pointer readback differs'",
            '$result.physical_pointer_positions=@($physicalPointerPositions)',
            'if($mouseHeld){$null=[MIRLibraryInputNative]::MouseButton($false)}'
          )){if(-not$actor.Contains($required)){throw "actual actor dispatch/teardown differs: $required"}}
          'PASS exact finite drag schedule and retained failure-release;zero desktop input'
        '''
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], cwd=ROOT,
                                env={**os.environ, "MIR_INPUT_ACTOR": str(ACTOR)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("zero desktop input", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
