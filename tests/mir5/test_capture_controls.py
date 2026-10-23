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

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/active-mods-observer"
PROTOTYPE_CAPTURE = ROOT / "tools/mir5/Invoke-PrototypeCapture.ps1"
REPLAY_CAPTURE = ROOT / "tools/mir5/Invoke-ReplayCapture.ps1"
MENU_COMPARISON = ROOT / "tools/mir5/Invoke-MenuComparison.ps1"
NATIVE_FIXTURE = ROOT / "tools/mir5/Invoke-NativeFixture.ps1"
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
