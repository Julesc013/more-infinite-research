"""Host controls for the governed MIR5 responsive-menu comparison plan.

These checks execute only the PowerShell planning, prerequisite, and temporary
archive-swap controls.  They never invoke ``-Execute``, Factorio, OCR, or
package construction.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/mir5/Invoke-MenuComparison.ps1"
DECLARED_POLICY = (
    "-AaAbsoluteToleranceSeconds 0.25 "
    "-AaRelativeTolerancePercent 5 "
    "-ControlRegressionToleranceSeconds 0.5 "
    "-MinimumMirAddedTimeReductionPercent 50"
)


def invoke_as_json(arguments: str) -> dict:
    command = (
        "& { . ./tools/mir5/Invoke-MenuComparison.ps1 "
        f"{arguments} }} | ConvertTo-Json -Depth 32 -Compress"
    )
    completed = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(completed.stdout)


def powershell_literal(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def invoke_dispatch_as_json() -> dict:
    """Run only the wrapper's arm dispatcher against host-local function stubs."""
    escaped = str(SCRIPT).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-MIR5MenuComparisonSample'}},$true))
if($definition.Count -ne 1){{throw 'sample dispatcher missing or ambiguous'}}
$script:dispatches=[Collections.Generic.List[object]]::new()
$script:replay_swaps=0
function Invoke-MIRDirectLibraryResponsiveMenuSample {{
  param($RepoRoot,$FactorioBin,$LibraryDirectory,$EngineDataDirectory,$BaseRows,$RunRoot,$WriteDataRoot,$Label,$Resources,$MirArchive,$TimeoutSeconds,$OrdinaryPlayerConfig,$OrdinaryMenuPreparation,$ActiveModsObserver)
  $script:dispatches.Add([ordered]@{{label=$Label;version=$(if($null -eq $MirArchive){{$null}}else{{[string]$MirArchive.version}})}})
  [pscustomobject]@{{label=$Label;version=$(if($null -eq $MirArchive){{$null}}else{{[string]$MirArchive.version}})}}
}}
function Invoke-MIR5MenuReplaySwap {{
  param($LibraryDirectory,$Published,$Replay,$WaitMilliseconds,$Action,$RecordRoot)
  $script:replay_swaps++
  [pscustomobject]@{{sample=(& $Action);swap=[ordered]@{{replay=$true}};swap_record='host-stub'}}
}}
. ([scriptblock]::Create($definition[0].Extent.Text))
$context=[pscustomobject]@{{root='host-root'}}
$inputs=[pscustomobject]@{{repo='repo';factorio=[pscustomobject]@{{path='factorio'}};library='library';engine_data='data';base_rows=@();published=[pscustomobject]@{{version='4.7.20002'}};replay=[pscustomobject]@{{version='4.7.20002'}};candidate=[pscustomobject]@{{version='5.0.20000'}};timeout_seconds=1;library_idle_wait_milliseconds=0;active_mods_observer=''}}
$ordinary=[pscustomobject]@{{}};$preparation=[pscustomobject]@{{}}
$control=Invoke-MIR5MenuComparisonSample -PlanRow ([pscustomobject]@{{arm='control-without-mir';label='control'}}) -Context $context -Inputs $inputs -OrdinaryPlayerConfig $ordinary -OrdinaryMenuPreparation $preparation -WriteDataRoot 'write-data' -RecordRoot 'records'
$candidate=Invoke-MIR5MenuComparisonSample -PlanRow ([pscustomobject]@{{arm='candidate-mir5';label='candidate'}}) -Context $context -Inputs $inputs -OrdinaryPlayerConfig $ordinary -OrdinaryMenuPreparation $preparation -WriteDataRoot 'write-data' -RecordRoot 'records'
$replay=Invoke-MIR5MenuComparisonSample -PlanRow ([pscustomobject]@{{arm='replay';label='replay'}}) -Context $context -Inputs $inputs -OrdinaryPlayerConfig $ordinary -OrdinaryMenuPreparation $preparation -WriteDataRoot 'write-data' -RecordRoot 'records'
[ordered]@{{
  dispatches=@($script:dispatches)
  candidate_swap_is_null=($null -eq $candidate.swap -and $null -eq $candidate.swap_record)
  control_swap_is_null=($null -eq $control.swap -and $null -eq $control.swap_record)
  replay_swaps=$script:replay_swaps
  replay_swap=$replay.swap
}} | ConvertTo-Json -Depth 12 -Compress
"""
    completed = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(completed.stdout)


class MenuComparisonTests(unittest.TestCase):
    def test_fixed_four_arm_two_cycle_plan_keeps_warmups_aa_pilot_and_latin_square(self):
        record = invoke_as_json(f"-PlanOnly {DECLARED_POLICY}")
        self.assertEqual(record["status"], "planned-not-executed")
        self.assertTrue(record["fixed_before_execution"])
        self.assertFalse(record["claims"]["native_execution"])
        self.assertEqual(record["tolerance_policy"]["status"], "declared-before-execution")
        self.assertEqual(record["tolerance_policy"]["counterbalanced_blocks"], 8)
        self.assertEqual(record["tolerance_policy"]["primary_samples_per_arm"], 8)
        self.assertEqual(record["tolerance_policy"]["extension_policy"].split(";", 1)[0], "none")

        rows = record["samples"]
        self.assertEqual(len(rows), 38)
        self.assertEqual([row["ordinal"] for row in rows], list(range(1, 39)))
        self.assertEqual(len({row["label"] for row in rows}), 38)

        arms = ["control-without-mir", "published-4.7", "replay", "candidate-mir5"]
        warmups = [row for row in rows if row["phase"] == "warmup"]
        self.assertEqual([row["arm"] for row in warmups], arms)
        pilot = [row for row in rows if row["phase"] == "aa-pilot"]
        self.assertEqual([row["arm"] for row in pilot], ["published-4.7", "published-4.7"])
        primary = [row for row in rows if row["phase"] == "counterbalanced-comparison"]
        self.assertEqual(len(primary), 32)
        for arm in arms:
            self.assertEqual(sorted(row["block"] for row in primary if row["arm"] == arm), list(range(1, 9)))
            self.assertEqual(sorted(row["position"] for row in primary if row["arm"] == arm), [1, 1, 2, 2, 3, 3, 4, 4])

    def test_plan_marks_undeclared_tolerances_and_preflight_requires_them(self):
        plan = invoke_as_json("-PlanOnly")
        self.assertEqual(plan["tolerance_policy"]["status"], "required-before-execution")
        self.assertFalse(plan["claims"]["performance_measurement"])

        record = invoke_as_json("-Preflight")
        self.assertEqual(record["status"], "blocked-prerequisites")
        self.assertFalse(record["claims"]["native_execution"])
        missing = {row["name"]: row["reason"] for row in record["missing"]}
        self.assertEqual(missing["AaAbsoluteToleranceSeconds"], "positive-seconds-required")
        self.assertEqual(missing["AaRelativeTolerancePercent"], "positive-percent-required")
        self.assertEqual(missing["ControlRegressionToleranceSeconds"], "positive-seconds-required")
        self.assertEqual(
            missing["MinimumMirAddedTimeReductionPercent"],
            "at-least-50-and-at-most-100-percent-required",
        )
        self.assertEqual(missing["CandidateArchive"], "path-required")

    def test_f200_preflight_accepts_the_exact_engine_family_but_requires_real_inputs(self):
        record = invoke_as_json(
            f"-Preflight -ExpectedEngineVersion 2.0.77 -ExpectedFactorioLine 2.0 {DECLARED_POLICY}"
        )
        self.assertEqual(record["required_engine_version"], "2.0.77")
        self.assertEqual(record["required_factorio_line"], "2.0")
        self.assertEqual(record["tolerance_policy"]["status"], "declared-before-execution")
        seed = [row for row in record["missing"] if row["name"] == "PlayerDataPath"]
        self.assertEqual(seed, [{
            "name": "PlayerDataPath",
            "reason": "actual-credential-free-engine-prepared-player-data-required",
            "expected_engine_version": "2.0.77",
        }])

        mismatched = invoke_as_json(
            f"-Preflight -ExpectedEngineVersion 2.0.77 -ExpectedFactorioLine 2.1 {DECLARED_POLICY}"
        )
        line = [row for row in mismatched["missing"] if row["name"] == "ExpectedFactorioLine"]
        self.assertEqual(line, [{
            "name": "ExpectedFactorioLine",
            "reason": "must-match-expected-engine-family",
            "expected_engine_version": "2.0.77",
        }])

    def test_fully_present_preflight_accepts_an_empty_missing_collection(self):
        """A valid preflight must not turn its empty diagnostic list into an error."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            library = root / "library"
            library.mkdir()
            files = {
                "factorio": root / "factorio.exe",
                "profile": root / "profile.json",
                "published": root / "published.zip",
                "replay": root / "replay.zip",
                "candidate": root / "candidate.zip",
                "ordinary": root / "player-config.ini",
                "player_data": root / "player-data.json",
            }
            for path in files.values():
                path.write_text("present", encoding="utf-8")
            digest = "A" * 64
            arguments = " ".join(
                [
                    "-Preflight",
                    "-ExpectedEngineVersion 2.0.77",
                    "-ExpectedFactorioLine 2.0",
                    f"-FactorioBin {powershell_literal(files['factorio'])}",
                    f"-ExpectedFactorioSha256 {digest}",
                    f"-ArchiveLibrary {powershell_literal(library)}",
                    f"-ProfilePath {powershell_literal(files['profile'])}",
                    f"-ExpectedProfileSha256 {digest}",
                    f"-PublishedArchive {powershell_literal(files['published'])}",
                    f"-ExpectedPublishedSha256 {digest}",
                    f"-ReplayArchive {powershell_literal(files['replay'])}",
                    f"-ExpectedReplaySha256 {digest}",
                    f"-CandidateArchive {powershell_literal(files['candidate'])}",
                    f"-ExpectedCandidateSha256 {digest}",
                    f"-OrdinaryPlayerConfigPath {powershell_literal(files['ordinary'])}",
                    f"-ExpectedOrdinaryPlayerConfigSha256 {digest}",
                    f"-PlayerDataPath {powershell_literal(files['player_data'])}",
                    f"-ExpectedPlayerDataSha256 {digest}",
                    f"-OutputRoot {powershell_literal(root / 'output')}",
                    DECLARED_POLICY,
                ]
            )
            record = invoke_as_json(arguments)

        self.assertEqual(record["status"], "inputs-present-not-executed")
        self.assertEqual(record["missing"], [])
        self.assertEqual(record["tolerance_policy"]["status"], "declared-before-execution")
        self.assertEqual(len(record["plan"]), 38)

    def test_candidate_and_control_use_direct_library_selection_while_only_replay_swaps(self):
        result = invoke_dispatch_as_json()
        self.assertEqual(
            result["dispatches"],
            [
                {"label": "control", "version": None},
                {"label": "candidate", "version": "5.0.20000"},
                {"label": "replay", "version": "4.7.20002"},
            ],
        )
        self.assertTrue(result["control_swap_is_null"])
        self.assertTrue(result["candidate_swap_is_null"])
        self.assertEqual(result["replay_swaps"], 1)
        self.assertEqual(result["replay_swap"], {"replay": True})

    def test_host_swap_control_restores_bytes_after_action_failure_and_refuses_busy_lock(self):
        record = invoke_as_json("-HostSwapSelfTest")
        self.assertEqual(record["status"], "passed")
        self.assertTrue(record["action_failure_restored"])
        self.assertTrue(record["busy_lock_refused_without_mutation"])
        self.assertFalse(record["claims"]["native_execution"])

    def test_wrapper_uses_the_governed_actor_and_has_no_custody_launcher(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Invoke-MIRDirectLibraryResponsiveMenuSample", source)
        self.assertIn("Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData", source)
        self.assertIn("Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput", source)
        self.assertIn("Assert-MIRLibraryIdle", source)
        self.assertIn("-MaxScanSeconds 1 -MaxEntriesPerRoot 100", source)
        self.assertIn("-Execute only with exclusive native ownership", source)
        self.assertIn("CandidateArchive", source)
        self.assertIn("candidate-mir5", source)
        self.assertIn("ExpectedFactorioLine", source)
        self.assertNotIn("Invoke-PrototypeCapture", source)
        self.assertNotIn("Invoke-NativeFixture", source)
        self.assertNotIn("git ", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
