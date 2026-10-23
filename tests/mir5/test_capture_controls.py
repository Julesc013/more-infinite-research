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

    def test_fixture_metadata_is_a_2_1_asset_only_mod(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["name"], "mir-fixture-mir5-active-mods-observer")
        self.assertEqual(info["version"], "0.1.0")
        self.assertEqual(info["factorio_version"], "2.1")
        self.assertEqual(info["dependencies"], ["base >= 2.1.23"])
        self.assertEqual(
            sorted(path.name for path in FIXTURE.iterdir()),
            ["data-final-fixes.lua", "info.json"],
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

        for source in (prototype, replay, menu):
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

    def test_capture_wrappers_remain_powershell_parseable(self):
        for script in (PROTOTYPE_CAPTURE, REPLAY_CAPTURE, MENU_COMPARISON):
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
