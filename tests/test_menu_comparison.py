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

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/Invoke-MenuComparison.ps1"
DECLARED_POLICY = (
    "-AaAbsoluteToleranceSeconds 0.25 "
    "-AaRelativeTolerancePercent 5 "
    "-ControlRegressionToleranceSeconds 0.5 "
    "-MinimumMirAddedTimeReductionPercent 50"
)


def invoke_as_json(arguments: str) -> dict:
    command = (
        "& { . ./tools/Invoke-MenuComparison.ps1 "
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


def invoke_failure(arguments: str) -> subprocess.CompletedProcess[str]:
    command = (
        "$ErrorActionPreference = 'Stop'; & { . ./tools/Invoke-MenuComparison.ps1 "
        f"{arguments} }}"
    )
    return subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


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
    def test_occlusion_reports_only_process_relation_and_rejects_every_other_root(self):
        command = r'''
. ./tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path ./tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'window helper parse failure'}
$native=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('public static class MIROwnedMenuNative')},$true))
if($native.Count-ne1){throw 'window native boundary absent or ambiguous'}
$declaration='[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);'
$double=@'
public static uint FixtureCandidatePid = 1234;
  public static uint FixtureThread = 1;
  public static int FixtureIdentityReads = 0;
  public static uint GetWindowThreadProcessId(IntPtr h, out uint pid) {
    FixtureIdentityReads++;
    pid = FixtureCandidatePid;
    return FixtureThread;
  }
'@
if(-not$native[0].Value.Contains($declaration)){throw 'native identity seam differs'}
# Compile the real equality/status helper, doubling only the Win32 lookup.
Add-Type -TypeDefinition $native[0].Value.Replace($declaration,$double)
$script:probeIndex=0;$script:coveredProbe=-1;$script:hitRoot=[IntPtr]43
function Get-MIROwnedMenuPointRoot {
  param([int]$X,[int]$Y)
  $index=$script:probeIndex;$script:probeIndex++
  if($index-eq$script:coveredProbe){return $script:hitRoot}
  return [IntPtr]42
}
$records=@()
foreach($covered in @(0,4)){
  foreach($case in @(
    @{pid=1234;thread=1;root=43;hit='other-window';relation='owned-process'},
    @{pid=4321;thread=1;root=43;hit='other-window';relation='other-process'},
    @{pid=1234;thread=0;root=43;hit='other-window';relation='unresolved'},
    @{pid=0;thread=1;root=43;hit='other-window';relation='unresolved'},
    @{pid=4321;thread=1;root=0;hit='no-window';relation='unresolved'}
  )){
    $script:probeIndex=0;$script:coveredProbe=$covered;$script:hitRoot=[IntPtr]$case.root
    [MIROwnedMenuNative]::FixtureCandidatePid=$case.pid
    [MIROwnedMenuNative]::FixtureThread=$case.thread
    [MIROwnedMenuNative]::FixtureIdentityReads=0
    $record=Get-MIROwnedMenuOcclusion -Handle ([IntPtr]42) -OwnedProcessId 1234 -X 0 -Y 0 -Width 2560 -Height 1440
    if($null-eq$record-or$record.probe_index-ne$covered-or$record.hit-cne$case.hit-or$record.hit_process_relation-cne$case.relation){throw 'covered window accepted or misclassified'}
    if(($record.Keys-join',')-cne'probe_index,probe_x,probe_y,owned_x,owned_y,owned_width,owned_height,hit,hit_process_relation'){throw 'diagnostic exposes fields beyond own geometry and category'}
    $expectedReads=if($case.root-eq0){0}else{1}
    if([MIROwnedMenuNative]::FixtureIdentityReads-ne$expectedReads){throw 'unexpected identity lookup'}
    $records+=$record
  }
}
$script:probeIndex=0;$script:coveredProbe=-1
[MIROwnedMenuNative]::FixtureIdentityReads=0
$clear=Get-MIROwnedMenuOcclusion -Handle ([IntPtr]42) -OwnedProcessId 1234 -X 0 -Y 0 -Width 2560 -Height 1440
if($null-ne$clear-or[MIROwnedMenuNative]::FixtureIdentityReads-ne0){throw 'clear window changed or queried another process'}
[ordered]@{covered_rejections=$records.Count;clear_window_unchanged=$true;native_execution=$false}|ConvertTo-Json -Compress
'''
        completed = subprocess.run(
            ["pwsh", "-NoProfile", "-Command", command], cwd=ROOT,
            text=True, capture_output=True, check=True,
        )
        result = json.loads(completed.stdout)
        self.assertEqual(result["covered_rejections"], 10)
        self.assertTrue(result["clear_window_unchanged"])
        self.assertFalse(result["native_execution"])

    def test_owned_capture_png_writer_replaces_an_existing_longer_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "latest-owned-window.png"
            command = rf'''
Add-Type -AssemblyName System.Drawing
. ./tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1
$target={powershell_literal(target)}
[IO.File]::WriteAllBytes($target,[byte[]]::new(65536))
$source=[Drawing.Bitmap]::new(2,2)
$roundtrip=$null
try {{
  $source.SetPixel(0,0,[Drawing.Color]::FromArgb(255,17,34,51))
  $source.SetPixel(1,1,[Drawing.Color]::FromArgb(255,68,85,102))
  $written=Save-MIROwnedMenuBitmapPng -Bitmap $source -Path $target
  $bytes=[IO.File]::ReadAllBytes($target)
  $iend='0,0,0,0,73,69,78,68,174,66,96,130'
  $tail=[int[]]$bytes[($bytes.Length-12)..($bytes.Length-1)]
  if($bytes.Length-ge65536-or(($tail-join',')-cne$iend)){{throw 'capture image retained stale trailing bytes'}}
  $roundtrip=[Drawing.Bitmap]::new($target)
  if($roundtrip.GetPixel(0,0).ToArgb()-ne$source.GetPixel(0,0).ToArgb()-or$roundtrip.GetPixel(1,1).ToArgb()-ne$source.GetPixel(1,1).ToArgb()){{throw 'capture image pixels changed'}}
  [ordered]@{{path=$written;bytes=$bytes.Length;iend_is_terminal=$true;pixels_preserved=$true;native_execution=$false}}|ConvertTo-Json -Compress
}} finally {{
  if($null-ne$roundtrip){{$roundtrip.Dispose()}}
  $source.Dispose()
}}
'''
            completed = subprocess.run(
                ["pwsh", "-NoProfile", "-Command", command], cwd=ROOT,
                text=True, capture_output=True, check=True,
            )
            result = json.loads(completed.stdout)
        self.assertEqual(Path(result["path"]), target)
        self.assertLess(result["bytes"], 65536)
        self.assertTrue(result["iend_is_terminal"])
        self.assertTrue(result["pixels_preserved"])
        self.assertFalse(result["native_execution"])

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
        expected_cycle = [
            ["control-without-mir", "published-4.7", "replay", "candidate-mir5"],
            ["published-4.7", "replay", "candidate-mir5", "control-without-mir"],
            ["replay", "candidate-mir5", "control-without-mir", "published-4.7"],
            ["candidate-mir5", "control-without-mir", "published-4.7", "replay"],
        ]
        self.assertEqual(
            [[row["arm"] for row in primary[index:index + 4]] for index in range(0, 32, 4)],
            expected_cycle * 2,
        )
        expected_primary = []
        for block, arms_in_block in enumerate(expected_cycle * 2, start=1):
            for position, arm in enumerate(arms_in_block, start=1):
                ordinal = 6 + len(expected_primary) + 1
                expected_primary.append({
                    "phase": "counterbalanced-comparison",
                    "arm": arm,
                    "block": block,
                    "position": position,
                    "label": f"{ordinal:02d}-counterbalanced-comparison-{arm}",
                })
        self.assertEqual(
            [{field: row[field] for field in expected_primary[0]} for row in primary],
            expected_primary,
        )
        for arm in arms:
            self.assertEqual(sorted(row["block"] for row in primary if row["arm"] == arm), list(range(1, 9)))
            self.assertEqual(sorted(row["position"] for row in primary if row["arm"] == arm), [1, 1, 2, 2, 3, 3, 4, 4])

    def test_published_only_repeatability_diagnostic_is_fixed_five_launches_and_not_a_comparison_plan(self):
        record = invoke_as_json(f"-PlanOnly -RepeatabilityDiagnostic {DECLARED_POLICY}")
        self.assertEqual(record["kind"], "MIR5ResponsiveMenuRepeatabilityDiagnosticPlanV1")
        self.assertEqual(record["status"], "planned-not-executed")
        self.assertEqual(record["endpoint"], "ordinary-responsive-menu")
        self.assertTrue(record["fixed_before_execution"])
        self.assertEqual(record["diagnostic"], {
            "mode": "published-only-repeatability",
            "warmup_samples": 1,
            "observation_samples": 4,
            "comparison": False,
            "release_qualification": False,
        })
        self.assertFalse(record["claims"]["native_execution"])
        self.assertFalse(record["claims"]["performance_comparison"])
        self.assertFalse(record["claims"]["release_qualification"])
        self.assertEqual(record["tolerance_policy"]["control_regression_tolerance_seconds"], 0.5)
        self.assertEqual(record["tolerance_policy"]["same_version_aa_pilot"]["relative_tolerance_percent"], 5)
        self.assertEqual(record["tolerance_policy"]["diagnostic_pair_count"], 2)
        self.assertNotIn("primary_samples_per_arm", record["tolerance_policy"])
        self.assertNotIn("counterbalanced_blocks", record["tolerance_policy"])
        self.assertEqual(
            record["samples"],
            [
                {"ordinal": 1, "phase": "repeatability-warmup", "arm": "published-4.7", "block": 0,
                 "position": 1, "label": "01-repeatability-warmup-published-4.7"},
                *[
                    {"ordinal": ordinal, "phase": "repeatability-observation", "arm": "published-4.7", "block": 1,
                     "position": ordinal - 1,
                     "label": f"{ordinal:02d}-repeatability-observation-published-4.7"}
                    for ordinal in range(2, 6)
                ],
            ],
        )
        refused = invoke_failure(f"-PlanOnly -RepeatabilityDiagnostic -CounterbalancedBlocks 64 {DECLARED_POLICY}")
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("repeatability-diagnostic-sample-count", refused.stderr + refused.stdout)

    def test_repeatability_preflight_does_not_require_replay_or_candidate_inputs(self):
        record = invoke_as_json(f"-Preflight -RepeatabilityDiagnostic {DECLARED_POLICY}")
        self.assertEqual(record["kind"], "MIR5ResponsiveMenuRepeatabilityDiagnosticPreflightV1")
        self.assertEqual(len(record["plan"]), 5)
        missing = {row["name"]: row["reason"] for row in record["missing"]}
        self.assertIn("PublishedArchive", missing)
        self.assertNotIn("ReplayArchive", missing)
        self.assertNotIn("CandidateArchive", missing)

    def test_sixty_four_block_plan_repeats_the_fixed_latin_cycle_with_balanced_positions(self):
        record = invoke_as_json(f"-PlanOnly -CounterbalancedBlocks 64 -MaxNewOutputMiB 8192 {DECLARED_POLICY}")
        self.assertEqual(record["tolerance_policy"]["counterbalanced_blocks"], 64)
        self.assertEqual(record["tolerance_policy"]["primary_samples_per_arm"], 64)
        rows = record["samples"]
        self.assertEqual(len(rows), 262)
        self.assertEqual([row["ordinal"] for row in rows], list(range(1, 263)))
        self.assertEqual(len({row["label"] for row in rows}), 262)
        self.assertEqual([row["arm"] for row in rows if row["phase"] == "warmup"], [
            "control-without-mir", "published-4.7", "replay", "candidate-mir5",
        ])
        self.assertEqual([row["arm"] for row in rows if row["phase"] == "aa-pilot"], ["published-4.7", "published-4.7"])
        primary = [row for row in rows if row["phase"] == "counterbalanced-comparison"]
        self.assertEqual(len(primary), 256)
        cycle = [
            ["control-without-mir", "published-4.7", "replay", "candidate-mir5"],
            ["published-4.7", "replay", "candidate-mir5", "control-without-mir"],
            ["replay", "candidate-mir5", "control-without-mir", "published-4.7"],
            ["candidate-mir5", "control-without-mir", "published-4.7", "replay"],
        ]
        self.assertEqual(
            [[row["arm"] for row in primary[index:index + 4]] for index in range(0, 256, 4)],
            cycle * 16,
        )
        for arm in ("control-without-mir", "published-4.7", "replay", "candidate-mir5"):
            arm_rows = [row for row in primary if row["arm"] == arm]
            self.assertEqual(sorted(row["block"] for row in arm_rows), list(range(1, 65)))
            self.assertEqual(sorted(row["position"] for row in arm_rows), [1] * 16 + [2] * 16 + [3] * 16 + [4] * 16)

    def test_counterbalanced_block_count_refuses_undeclared_values(self):
        for blocks in (0, 7, 9, 63, 65):
            refused = invoke_failure(f"-PlanOnly -CounterbalancedBlocks {blocks} {DECLARED_POLICY}")
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("CounterbalancedBlocks", refused.stderr + refused.stdout)

    def test_declared_ten_gib_peak_is_admitted_by_the_menu_parameter_contract_only(self):
        plan = invoke_as_json(f"-PlanOnly -ExpectedPeakMemoryMiB 10240 {DECLARED_POLICY}")
        self.assertEqual(plan["status"], "planned-not-executed")
        refused = invoke_failure(f"-PlanOnly -ExpectedPeakMemoryMiB 10241 {DECLARED_POLICY}")
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("ExpectedPeakMemoryMiB", refused.stderr + refused.stdout)

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

    def test_fully_present_repeatability_preflight_needs_no_replay_or_candidate_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            library = root / "library"
            library.mkdir()
            files = {
                "factorio": root / "factorio.exe",
                "profile": root / "profile.json",
                "published": root / "published.zip",
                "ordinary": root / "player-config.ini",
                "player_data": root / "player-data.json",
            }
            for path in files.values():
                path.write_text("present", encoding="utf-8")
            digest = "A" * 64
            arguments = " ".join(
                [
                    "-Preflight -RepeatabilityDiagnostic",
                    "-ExpectedEngineVersion 2.0.77",
                    "-ExpectedFactorioLine 2.0",
                    f"-FactorioBin {powershell_literal(files['factorio'])}",
                    f"-ExpectedFactorioSha256 {digest}",
                    f"-ArchiveLibrary {powershell_literal(library)}",
                    f"-ProfilePath {powershell_literal(files['profile'])}",
                    f"-ExpectedProfileSha256 {digest}",
                    f"-PublishedArchive {powershell_literal(files['published'])}",
                    f"-ExpectedPublishedSha256 {digest}",
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
        self.assertEqual(record["kind"], "MIR5ResponsiveMenuRepeatabilityDiagnosticPreflightV1")
        self.assertEqual(len(record["plan"]), 5)

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
        self.assertIn("RepeatabilityDiagnostic", source)
        self.assertIn("MIR5ResponsiveMenuRepeatabilityDiagnosticObservationV1", source)
        self.assertIn(
            "Assert-MIRDirectLibraryStartupDeclaredInputs -ProfileDefinition $profileRaw "
            "-EngineIdentity $engine -ArchiveHashes $profileArchiveHashes -ErrorPrefix 'mir5-menu'",
            source,
        )
        self.assertIn("ExpectedFactorioLine", source)
        self.assertNotIn("Invoke-PrototypeCapture", source)
        self.assertNotIn("Invoke-NativeFixture", source)
        self.assertNotIn("git ", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
