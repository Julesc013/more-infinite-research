"""Host-only controls for the MIR5 active-mods observer capture route.

These controls execute the asset-only fixture in isolated Lua 5.2 and parse
the PowerShell wrappers. They never build a ZIP or launch Factorio.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/active-mods-observer"
PROTOTYPE_CAPTURE = ROOT / "tools/Invoke-PrototypeCapture.ps1"
REPLAY_CAPTURE = ROOT / "tools/Invoke-ReplayCapture.ps1"
MENU_COMPARISON = ROOT / "tools/Invoke-MenuComparison.ps1"
NATIVE_FIXTURE = ROOT / "tools/Invoke-NativeFixture.ps1"
LIBRARY_ACTIVATION = ROOT / "tools/lib/compatibility/LibraryActivation.ps1"


def assert_powershell_parses(path: Path) -> None:
    escaped = str(path).replace("'", "''")
    command = (
        "$tokens=$null;$errors=$null;"
        "[void][System.Management.Automation.Language.Parser]::ParseFile("
        f"'{escaped}',[ref]$tokens,[ref]$errors);"
        "if($errors.Count){$errors | ForEach-Object {$_.ToString()};exit 1}"
    )
    subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )


def native_fixture_observer_guard_cases() -> dict:
    """Execute the wrapper's isolated observer-binding helper, never its runner."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-FixtureActiveModsObserver'}},$true))
if($definition.Count -ne 1){{throw 'observer helper missing or ambiguous'}}
function Assert-Fixture([bool]$Condition,[string]$Message) {{if(-not $Condition){{throw "[mir5-native-fixture] $Message"}}}}
. ([scriptblock]::Create($definition[0].Extent.Text))
function Invoke-ObserverCase([string]$Name,[object[]]$Rows,[object[]]$Inputs) {{
  try {{[ordered]@{{valid=$true;value=(Get-FixtureActiveModsObserver -Name $Name -ProfileRows $Rows -FixtureInputs $Inputs)}}}}
  catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
$verified=@([pscustomobject]@{{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';source='fixture-source';archive='fixture.zip';sha256=('A'*64)}})
$selected=@([pscustomobject]@{{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';enabled=$true}})
$cases=[ordered]@{{
  positive=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' $selected $verified)
  blank=(Invoke-ObserverCase '   ' $selected $verified)
  missing=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' @([pscustomobject]@{{name='other';version='0.1.0';enabled=$true}}) $verified)
  unselected=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' @([pscustomobject]@{{name='mir-fixture-mir5-active-mods-observer';version='0.1.0';enabled=$false}}) $verified)
  unverified=(Invoke-ObserverCase 'mir-fixture-mir5-active-mods-observer' $selected @([pscustomobject]@{{name='other';version='0.1.0';source='other';archive='other.zip';sha256=('B'*64)}}))
}}
$cases | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_active_marker_guard_cases() -> dict:
    """Exercise only the finite active-marker reader, never Factorio."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Read-ActiveFixtureMarker'}},$true))
if($definition.Count -ne 1){{throw 'active marker helper missing or ambiguous'}}
function Assert-Fixture([bool]$Condition,[string]$Message) {{if(-not$Condition){{throw "[mir5-native-fixture] $Message"}}}}
. ([scriptblock]::Create($definition[0].Extent.Text))
function Invoke-ActiveCase([string]$Text,[string]$Kind,[string]$Stage) {{
  try {{[ordered]@{{valid=$true;value=(Read-ActiveFixtureMarker $Text $Kind $Stage)}}}}
  catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
$prepared='[MIR5_RUNTIME_ACTIVE] {{"kind":"repair-stress","stage":"prepared","status":"pending"}}'
$complete='[MIR5_RUNTIME_ACTIVE] {{"kind":"repair-stress","stage":"complete","status":"passed"}}'
$cases=[ordered]@{{
  positive=(Invoke-ActiveCase $prepared 'repair-stress' 'prepared')
  duplicate=(Invoke-ActiveCase ($prepared+"`n"+$prepared) 'repair-stress' 'prepared')
  wrong_kind=(Invoke-ActiveCase $prepared 'agriculture-scale' 'prepared')
  wrong_status=(Invoke-ActiveCase $complete 'repair-stress' 'prepared')
  unsupported_stage=(Invoke-ActiveCase $prepared 'repair-stress' 'other')
}}
$cases | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_active_selection_guard_cases() -> dict:
    """Exercise the finite published/candidate repair selection rule only."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definition=@($ast.Find({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-ActiveFixtureSelection'}},$true))
if($definition.Count -ne 1){{throw 'active selection helper missing or ambiguous'}}
function Assert-Fixture([bool]$Condition,[string]$Message) {{if(-not$Condition){{throw "[mir5-native-fixture] $Message"}}}}
. ([scriptblock]::Create($definition[0].Extent.Text))
function Invoke-SelectionCase([object[]]$Rows,[object[]]$Mir) {{
  try {{Assert-ActiveFixtureSelection 'repair-stress' $Rows $Mir;[ordered]@{{valid=$true}}}}
  catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
function New-RepairRows([string]$Version) {{@(
  [pscustomobject]@{{name='mir-fixture-mir5-repair-stress-active';version='0.1.0';enabled=$true}},
  [pscustomobject]@{{name='mir-fixture-mir5-repair-stress';version=$Version;enabled=$true}}
)}}
$cases=[ordered]@{{
  published=(Invoke-SelectionCase (New-RepairRows '0.1.0') @([pscustomobject]@{{name='more-infinite-research';version='4.7.21002'}}))
  candidate=(Invoke-SelectionCase (New-RepairRows '0.2.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21000'}}))
  candidate_wrong_base=(Invoke-SelectionCase (New-RepairRows '0.1.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21000'}}))
  unknown_mir=(Invoke-SelectionCase (New-RepairRows '0.2.0') @([pscustomobject]@{{name='more-infinite-research';version='5.0.21001'}}))
}}
$cases | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_active_create_target_cases() -> dict:
    """Execute the wrapper's own save-target and create-call AST nodes only."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$assignments=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]}},$true))
$activeSave=@($assignments|Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'activeSave' }})
$seed=@($assignments|Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'seed' -and $_.Extent.Text -match 'repair-stress' }})
$create=@($assignments|Where-Object {{ $_.Extent.Text -match '^\$record\.create\s*=\s*Invoke-FixtureStage' }})
if($activeSave.Count -ne 1 -or $seed.Count -ne 1 -or $create.Count -ne 1){{throw 'active save target assignments missing or ambiguous'}}
function Invoke-TargetCase([bool]$Active,[string]$Kind) {{
  $activeSeed=$Active;$ActiveSeedKind=$Kind;$writeData='D:\owned-write-data';$record=[ordered]@{{}}
  function Invoke-FixtureStage([string]$Stage,[object[]]$Arguments) {{[pscustomobject]@{{stage=$Stage;arguments=$Arguments;log='unused'}}}}
  . ([scriptblock]::Create($activeSave[0].Extent.Text))
  . ([scriptblock]::Create($seed[0].Extent.Text))
  . ([scriptblock]::Create($create[0].Extent.Text))
  [ordered]@{{active_save=$activeSave;seed=$seed;create=$record.create.arguments}}
}}
[ordered]@{{
  repair_active=(Invoke-TargetCase $true 'repair-stress')
  agriculture_active=(Invoke-TargetCase $true 'agriculture-scale')
  ordinary=(Invoke-TargetCase $false '')
}} | ConvertTo-Json -Compress -Depth 6
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


def native_fixture_agriculture_completion_guard_cases() -> dict:
    """Invoke the actual active-seed predicate through a separate caller scope."""
    escaped = str(NATIVE_FIXTURE).replace("'", "''")
    command = rf"""
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile('{escaped}',[ref]$tokens,[ref]$errors)
if($errors.Count){{throw ($errors | ForEach-Object {{$_.ToString()}})}}
$definitions=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Test-HistoricalFixtureSaveComplete'}},$true))
$assignments=@($ast.FindAll({{param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]}},$true))
$activeSaveCompleteAssignment=@($assignments | Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'activeSaveComplete' }})
$completion=@($assignments | Where-Object {{ $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'activeCompletion' }})
if($definitions.Count -ne 1 -or $activeSaveCompleteAssignment.Count -ne 1 -or $completion.Count -ne 1){{throw 'active agriculture completion nodes missing or ambiguous'}}
. ([scriptblock]::Create($definitions[0].Extent.Text))
function Invoke-GovernorStylePredicate([scriptblock]$Predicate) {{
  try {{
    $decision=@(& $Predicate)
    if($decision.Count -ne 1 -or $decision[0] -isnot [bool]){{throw 'completion predicate did not return one bool'}}
    [ordered]@{{valid=$true;result=$decision[0]}}
  }} catch {{[ordered]@{{valid=$false;message=$_.Exception.Message}}}}
}}
function Write-ClosedFixtureSave([string]$Path,[bool]$Complete) {{
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $stream=$null;$zip=$null
  try {{
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    if($Complete){{
      $root=[IO.Path]::GetFileNameWithoutExtension($Path)
      $entry=$zip.CreateEntry($root+'/level.dat')
      $writer=[IO.StreamWriter]::new($entry.Open())
      try {{$writer.Write('fixture')}} finally {{$writer.Dispose()}}
    }}
  }} finally {{if($null-ne$zip){{$zip.Dispose()}};if($null-ne$stream){{$stream.Dispose()}}}}
}}
function Invoke-ActiveCompletionCase([string]$Name,[AllowNull()][string]$Text,[bool]$SavePresent,[bool]$SaveComplete) {{
  $caseRoot=Join-Path $root $Name
  [IO.Directory]::CreateDirectory($caseRoot)|Out-Null
  $live=Join-Path $caseRoot 'factorio-current.log'
  $activeSave=Join-Path $caseRoot 'mir5-native-active.zip'
  if($null-ne$Text){{[IO.File]::WriteAllText($live,$Text,[Text.UTF8Encoding]::new($false))}}
  if($SavePresent){{Write-ClosedFixtureSave $activeSave $SaveComplete}}
  . ([scriptblock]::Create($activeSaveCompleteAssignment[0].Extent.Text))
  . ([scriptblock]::Create($completion[0].Extent.Text))
  Invoke-GovernorStylePredicate $activeCompletion
}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('mir5-active-completion-'+[Guid]::NewGuid().ToString('N'))
$marker='[MIR5_RUNTIME_ACTIVE] {{"kind":"agriculture-scale","stage":"prepared","status":"pending"}}'
try {{
  $cases=[ordered]@{{
    no_log=(Invoke-ActiveCompletionCase 'no-log' $null $true $true)
    missing_marker=(Invoke-ActiveCompletionCase 'missing-marker' 'Saving finished' $true $true)
    valid=(Invoke-ActiveCompletionCase 'valid' ($marker+"`nSaving finished") $true $true)
    fatal=(Invoke-ActiveCompletionCase 'fatal' ($marker+"`n0.001 Error native failure") $true $true)
    duplicate_marker=(Invoke-ActiveCompletionCase 'duplicate-marker' ($marker+"`n"+$marker+"`nSaving finished") $true $true)
    malformed_marker=(Invoke-ActiveCompletionCase 'malformed-marker' (('[MIR5_RUNTIME_ACTIVE] {{not-json}}')+"`nSaving finished") $true $true)
    unclosed_save=(Invoke-ActiveCompletionCase 'unclosed-save' ($marker+"`nSaving finished") $true $false)
    absent_save=(Invoke-ActiveCompletionCase 'absent-save' ($marker+"`nSaving finished") $false $false)
  }}
  $cases | ConvertTo-Json -Compress -Depth 6
}} finally {{if(Test-Path -LiteralPath $root){{Remove-Item -LiteralPath $root -Recurse -Force}}}}
"""
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(result.stdout)


class CaptureControlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.execute(r"""
          function execute_active_mods_fixture(path, supplied_mods, provide_mods)
            local lines = {}
            local environment = {
              log = function(message) lines[#lines + 1] = message end
            }
            if provide_mods then environment.mods = supplied_mods end
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            if chunk == nil then return false, message, lines end
            local ok, result = pcall(chunk)
            return ok, result, lines
          end
        """)

    def run_fixture(self, mods, provide_mods=True):
        self.lua.globals().fixture_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().fixture_mods = mods
        self.lua.globals().fixture_has_mods = provide_mods
        return self.lua.eval(
            "execute_active_mods_fixture(fixture_path, fixture_mods, fixture_has_mods)"
        )

    def test_fixture_has_only_the_shared_observer_and_exact_target_metadata(self):
        for member, family, minimum in (("info.json", "2.1", "2.1.23"),
                                        ("info-f200.json", "2.0", "2.0.77")):
            with self.subTest(member=member):
                info = json.loads((FIXTURE / member).read_text(encoding="utf-8"))
                self.assertEqual(info["name"], "mir-fixture-mir5-active-mods-observer")
                self.assertEqual(info["version"], "0.1.0")
                self.assertEqual(info["factorio_version"], family)
                self.assertEqual(info["dependencies"], [f"base >= {minimum}"])
        self.assertEqual(
            sorted(path.name for path in FIXTURE.iterdir()),
            ["data-final-fixes.lua", "info-f200.json", "info.json"],
        )

    def test_fixture_reports_the_actual_mod_table_in_sorted_order_once(self):
        mods = self.lua.table_from({
            "z-last": "9.0.0",
            "base": "2.1.23",
            "alpha-observer": "0.1.0",
        })
        ok, message, lines = self.run_fixture(mods)
        self.assertTrue(ok, message)
        self.assertEqual(len(lines), 1)
        self.assertEqual(
            lines[1],
            "[MIR_ACTIVE_MODS] alpha-observer@0.1.0|base@2.1.23|z-last@9.0.0",
        )

    def test_fixture_keeps_an_empty_actual_table_distinct_from_missing_mods(self):
        ok, message, lines = self.run_fixture(self.lua.table())
        self.assertTrue(ok, message)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[1], "[MIR_ACTIVE_MODS] ")

        ok, message, lines = self.run_fixture(None, provide_mods=False)
        self.assertFalse(ok)
        self.assertIn("Factorio data-stage mods dictionary is required", message)
        self.assertEqual(len(lines), 0)

    def test_fixture_rejects_a_non_string_native_mod_dictionary_row(self):
        mods = self.lua.table_from({"base": 2123})
        ok, message, lines = self.run_fixture(mods)
        self.assertFalse(ok)
        self.assertIn("mods must map string names to string versions", message)
        self.assertEqual(len(lines), 0)

    def test_fixture_does_not_touch_product_or_runtime_surfaces(self):
        source = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("data.raw", source)
        self.assertNotIn("settings", source)
        self.assertNotIn("script.", source)
        self.assertNotIn("game.", source)
        self.assertNotIn("more-infinite-research", source)

    def test_capture_wrappers_forward_an_optional_hash_bound_observer(self):
        prototype = PROTOTYPE_CAPTURE.read_text(encoding="utf-8")
        replay = REPLAY_CAPTURE.read_text(encoding="utf-8")
        menu = MENU_COMPARISON.read_text(encoding="utf-8")
        native_fixture = NATIVE_FIXTURE.read_text(encoding="utf-8")

        for source in (prototype, replay, menu, native_fixture):
            self.assertRegex(source, r"\[string\]\$ActiveModsObserver\s*=\s*''")

        self.assertIn(
            "Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $factorioLog "
            "-LatestInvocation -ActiveModsObserver $activeModsObserver",
            prototype,
        )
        self.assertIn("ActiveModsObserver must be selected exactly once", prototype)
        self.assertIn("ActiveModsObserver must be a hash-bound archive", prototype)
        self.assertIn("active_mods_observer = [ordered]", prototype)
        self.assertIn("-ActiveModsObserver $ActiveModsObserver", replay)
        self.assertIn("-ActiveModsObserver $Inputs.active_mods_observer", menu)
        self.assertIn("active_mods_observer=$activeModsObserver", menu)
        self.assertIn("function Get-FixtureActiveModsObserver", native_fixture)
        self.assertIn("ActiveModsObserver must be a verified FixtureSources input", native_fixture)
        self.assertIn("$activation.selected | Where-Object", native_fixture)
        self.assertIn("$record.active_mods_observer=[ordered]", native_fixture)
        self.assertIn(
            "-LatestInvocation -ActiveModsObserver $activeModsObserverName",
            native_fixture,
        )

    def test_native_fixture_active_seed_mode_is_finite_and_deferred(self):
        source = NATIVE_FIXTURE.read_text(encoding="utf-8")
        self.assertIn("[switch]$ActiveSeedOnly", source)
        self.assertIn(
            "[ValidateSet('','repair-stress','agriculture-scale')][string]$ActiveSeedKind=''",
            source,
        )
        self.assertIn("active seed requires a modern installed-MIR fixture run", source)
        self.assertIn("active seed must begin from its own fresh fixture save", source)
        self.assertIn("passed-private-native-active-seed-preparation", source)
        self.assertIn(
            "physical_work='deferred until the benchmark loads this exact active save'",
            source,
        )
        self.assertIn("$activeSaveComplete=${function:Test-HistoricalFixtureSaveComplete}", source)
        self.assertIn("fatal native active preparation diagnostic", source)

    def test_active_repair_forwards_create_to_its_closed_active_save_only(self):
        cases = native_fixture_active_create_target_cases()
        active = r"D:\owned-write-data\saves\mir5-native-active.zip"
        seed = r"D:\owned-write-data\saves\seed.zip"

        self.assertEqual(active, cases["repair_active"]["active_save"])
        self.assertEqual(active, cases["repair_active"]["seed"])
        self.assertEqual(["--create", active], cases["repair_active"]["create"])

        for name in ("agriculture_active", "ordinary"):
            with self.subTest(name=name):
                self.assertEqual(seed, cases[name]["seed"])
                self.assertEqual(["--create", seed], cases[name]["create"])

    def test_native_fixture_active_marker_reader_rejects_wrong_or_ambiguous_markers(self):
        cases = native_fixture_active_marker_guard_cases()
        self.assertTrue(cases["positive"]["valid"])
        self.assertEqual(cases["positive"]["value"]["stage"], "prepared")
        for name in ("duplicate", "wrong_kind", "wrong_status", "unsupported_stage"):
            with self.subTest(name=name):
                self.assertFalse(cases[name]["valid"])
                self.assertIn("active", cases[name]["message"])

    def test_agriculture_active_completion_is_self_contained_across_governor_scope(self):
        cases = native_fixture_agriculture_completion_guard_cases()

        for name in ("no_log", "missing_marker", "duplicate_marker", "malformed_marker", "unclosed_save", "absent_save"):
            with self.subTest(name=name):
                self.assertTrue(cases[name]["valid"])
                self.assertFalse(cases[name]["result"])

        self.assertTrue(cases["valid"]["valid"])
        self.assertTrue(cases["valid"]["result"])
        self.assertFalse(cases["fatal"]["valid"])
        self.assertIn("fatal native active preparation diagnostic", cases["fatal"]["message"])

    def test_active_repair_selection_allows_candidate_fixture_v020_and_refuses_drift(self):
        cases = native_fixture_active_selection_guard_cases()
        self.assertTrue(cases["published"]["valid"])
        self.assertTrue(cases["candidate"]["valid"])
        for name in ("candidate_wrong_base", "unknown_mir"):
            with self.subTest(name=name):
                self.assertFalse(cases[name]["valid"])
                self.assertIn("active", cases[name]["message"])

    def test_native_fixture_observer_binding_rejects_missing_unselected_and_unverified_inputs(self):
        cases = native_fixture_observer_guard_cases()

        self.assertTrue(cases["positive"]["valid"])
        self.assertEqual(
            cases["positive"]["value"],
            {
                "name": "mir-fixture-mir5-active-mods-observer",
                "version": "0.1.0",
                "source": "fixture-source",
                "archive": "fixture.zip",
                "sha256": "A" * 64,
            },
        )
        self.assertTrue(cases["blank"]["valid"])
        self.assertIsNone(cases["blank"]["value"])

        self.assertFalse(cases["missing"]["valid"])
        self.assertIn("must appear exactly once in the profile", cases["missing"]["message"])
        self.assertFalse(cases["unselected"]["valid"])
        self.assertIn("must be selected exactly once", cases["unselected"]["message"])
        self.assertFalse(cases["unverified"]["valid"])
        self.assertIn("must be a verified FixtureSources input", cases["unverified"]["message"])

    def test_capture_wrappers_remain_powershell_parseable(self):
        for script in (PROTOTYPE_CAPTURE, REPLAY_CAPTURE, MENU_COMPARISON, NATIVE_FIXTURE):
            assert_powershell_parses(script)

    def test_shared_contract_still_has_missing_and_unselected_observer_refusals(self):
        source = LIBRARY_ACTIVATION.read_text(encoding="utf-8")
        self.assertIn("[mir-library-loaded-observer] Observer is not selected.", source)
        self.assertIn(
            "[mir-library-loaded-observation] Expected one complete native mod table.",
            source,
        )
        self.assertIn("[mir-library-loaded-selection] Actual mod names/versions differ from the profile.", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CaptureControlTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
