"""Selection and wrapper controls for the private MIR 5 host lane only."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "tests/mir5/Test-MIR5HostControls.ps1"


def run_powershell(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pwsh", "-NoProfile", *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )


def selections() -> dict[str, dict]:
    command = r'''
      $ErrorActionPreference = 'Stop'
      $repo = (Resolve-Path -LiteralPath '.').Path
      $script:Args = @()
      . ./tools/lib/assurance/Core.ps1
      $assurance = Get-Content -Raw -LiteralPath .mir/assurance.json | ConvertFrom-Json -Depth 100
      $paths = @(
        'source/mir5/control.lua', 'targets/mir5/README.md', 'tests/mir5/test_generator.py',
        'tools/mir5/package.py', 'spec/mir5/verification.md', 'sdk/mir5/README.md',
        '.github/workflows/mir5.yml', 'docs/mir5/README.md', 'source/prototypes/mir/core/deepcopy.lua',
        '.gitattributes', 'unowned/mir5-selection-opponent.txt'
      )
      $result = [ordered]@{}
      foreach ($path in $paths) { $result[$path] = Get-MIRAssuranceClassification -Paths @($path) -Config $assurance }
      $result | ConvertTo-Json -Depth 20 -Compress
    '''
    return json.loads(run_powershell(["-Command", command]).stdout)


def development_routes() -> dict[str, dict]:
    command = r'''
      $ErrorActionPreference = 'Stop'
      $repo = (Resolve-Path -LiteralPath '.').Path
      . ./tools/mir/application/assurance/DevelopmentValidation.ps1
      . ./tools/lib/assurance/Core.ps1
      $catalog = Get-Content -Raw -LiteralPath validation/tests.yml | ConvertFrom-Json
      $assurance = Get-Content -Raw -LiteralPath .mir/assurance.json | ConvertFrom-Json -Depth 100
      $profile = 'mir4-development'
      $local = Get-MIR4DevelopmentCISelection -RepoRoot $repo -Mode local-current-profile
      $paths = [ordered]@{
        mir5 = 'source/mir5/control.lua'
        docs = 'docs/mir5/README.md'
        legacy = 'source/prototypes/mir/core/deepcopy.lua'
        unknown = 'unowned/mir5-selection-opponent.txt'
      }
      $routes = [ordered]@{}
      foreach ($entry in $paths.GetEnumerator()) {
        $classification = Get-MIRAssuranceClassification -Paths @([string]$entry.Value) -Config $assurance
        $rows = @(Select-MIR4DevelopmentAffectedStaticRows -Classification $classification -Catalog $catalog -Assurance $assurance -Profile $profile)
        $selection = [ordered]@{
          baseline = ('a' * 40)
          baseline_state = 'resolved'
          classification = $classification
          tests = @($rows | ForEach-Object { [string]$_.id })
        }
        $routes[[string]$entry.Key] = [ordered]@{
          classification = $classification
          selected_tests = @($selection.tests)
          initial_plan = Get-MIR4DevelopmentInitialPlanProfile -Selection $selection
        }
      }
      [ordered]@{
        local = [ordered]@{ tests = @($local.tests); trust_scope = $local.trust_scope }
        routes = $routes
      } | ConvertTo-Json -Depth 30 -Compress
    '''
    return json.loads(run_powershell(["-Command", command]).stdout)


class HostControlsTests(unittest.TestCase):
    def test_wrapper_has_one_explicit_current_host_control_plan(self):
        plan_command = "& { ./tests/mir5/Test-MIR5HostControls.ps1 -Plan } | ConvertTo-Json -Depth 20 -Compress"
        plan = json.loads(run_powershell(["-Command", plan_command]).stdout)
        self.assertEqual(plan["kind"], "MIR5HostControlsPlanV1")
        self.assertFalse(plan["native_execution"])
        controls = plan["controls"]
        paths = [row["path"] for row in controls]
        self.assertEqual(len(paths), 19)
        self.assertEqual(len(set(paths)), len(paths))
        self.assertEqual(paths[-1], "tools/mir5/check_pack.py")
        self.assertIn("tests/mir5/test_library.py", paths)
        self.assertIn("tests/mir5/test_library_model.py", paths)
        self.assertIn("tests/mir5/test_host_controls.py", paths)
        self.assertFalse(any("test_cutover.py" in path or "test_adoption.py" in path for path in paths))
        self.assertTrue(all(row["lua"] for row in controls[:12]))
        self.assertTrue(all(not row["lua"] for row in controls[12:]))

    def test_mir5_is_narrow_while_docs_legacy_and_unknown_selection_remain_governed(self):
        result = selections()
        mir5_paths = [
            "source/mir5/control.lua", "targets/mir5/README.md", "tests/mir5/test_generator.py",
            "tools/mir5/package.py", "spec/mir5/verification.md", "sdk/mir5/README.md",
            ".github/workflows/mir5.yml",
        ]
        for path in mir5_paths:
            self.assertEqual(result[path]["classes"], ["mir5-host-controls"], path)
            self.assertEqual(result[path]["tests"], ["static.mir5-host-controls"], path)
            self.assertFalse(result[path]["escalated"], path)

        docs = result["docs/mir5/README.md"]
        self.assertEqual(docs["classes"], ["repository-docs"])
        self.assertEqual(docs["tests"], ["docs.check"])
        self.assertFalse(docs["escalated"])

        legacy_source = result["source/prototypes/mir/core/deepcopy.lua"]
        self.assertIn("mir4-package-source-editable-materializer", legacy_source["classes"])
        self.assertIn("mir4-package-source-authority-cutover", legacy_source["classes"])
        self.assertNotIn("mir5-host-controls", legacy_source["classes"])

        attributes = result[".gitattributes"]
        self.assertIn("mir4-bootstrap", attributes["classes"])
        self.assertNotIn("mir5-host-controls", attributes["classes"])

        unknown = result["unowned/mir5-selection-opponent.txt"]
        self.assertTrue(unknown["escalated"])
        self.assertIn("unknown", unknown["classes"])
        self.assertEqual(
            unknown["tests"],
            ["runtime.ecosystem", "runtime.full", "runtime.upgrade", "static.full"],
        )
        self.assertNotIn("static.mir5-host-controls", unknown["tests"])

    def test_development_selector_profile_and_initial_plan_keep_mir5_and_opponents_governed(self):
        routes = development_routes()
        local = routes["local"]
        self.assertEqual(local["trust_scope"], "local-development-authoring")
        self.assertEqual(local["tests"].count("static.mir5-host-controls"), 1)

        mir5 = routes["routes"]["mir5"]
        self.assertEqual(mir5["classification"]["tests"], ["static.mir5-host-controls"])
        self.assertFalse(mir5["classification"]["escalated"])
        self.assertIn("static.mir5-host-controls", mir5["selected_tests"])
        self.assertEqual(mir5["initial_plan"]["profile"], "mir4-development")
        self.assertFalse(mir5["initial_plan"]["use_affected_selection"])

        docs = routes["routes"]["docs"]
        self.assertEqual(docs["classification"]["tests"], ["docs.check"])
        self.assertFalse(docs["classification"]["escalated"])
        self.assertIn("docs.check", docs["selected_tests"])
        self.assertIn("static.mir5-host-controls", docs["selected_tests"])
        self.assertEqual(docs["initial_plan"]["profile"], "mir4-development")

        legacy = routes["routes"]["legacy"]
        self.assertFalse(legacy["classification"]["escalated"])
        self.assertIn("static.architecture", legacy["selected_tests"])
        self.assertNotIn("static.mir5-host-controls", legacy["selected_tests"])
        self.assertEqual(legacy["initial_plan"]["profile"], "mir4-development")

        unknown = routes["routes"]["unknown"]
        self.assertTrue(unknown["classification"]["escalated"])
        self.assertEqual(unknown["selected_tests"], local["tests"])
        self.assertIn("static.mir5-host-controls", unknown["selected_tests"])
        self.assertEqual(unknown["initial_plan"]["profile"], "mir4-development")
        self.assertFalse(unknown["initial_plan"]["use_affected_selection"])


if __name__ == "__main__":
    unittest.main()
