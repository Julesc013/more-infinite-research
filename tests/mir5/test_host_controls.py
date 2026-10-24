"""The authoritative MIR 5 host-plan and workflow contracts.

The prior assertions exercised MIR 4 assurance classification and development
routing.  Canonical cutover replaces that affected-path lane with this full,
checkout-bound host gate for every dev/main change, so those assertions are no
longer relevant to the delivered host controls.
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "tests/mir5/Test-MIR5HostControls.ps1"
WORKFLOW = ROOT / ".github/workflows/mir5.yml"
VALIDATE_WORKFLOW = ROOT / ".github/workflows/validate.yml"


def run_powershell(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pwsh", "-NoProfile", *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )


class HostControlsTests(unittest.TestCase):
    def test_wrapper_has_one_explicit_current_host_control_plan(self):
        plan_command = "& { ./tests/mir5/Test-MIR5HostControls.ps1 -Plan } | ConvertTo-Json -Depth 20 -Compress"
        plan = json.loads(run_powershell(["-Command", plan_command]).stdout)
        self.assertEqual(plan["kind"], "MIR5HostControlsPlanV1")
        self.assertFalse(plan["native_execution"])
        self.assertFalse(plan["release_qualification"])
        controls = plan["controls"]
        paths = [row["path"] for row in controls]
        self.assertEqual(paths, [
            "tests/mir5/test_generator.py",
            "tests/mir5/test_historical_direct.py",
            "tests/mir5/test_historical_continuations.py",
            "tests/mir5/test_historical_native_runner.py",
            "tests/mir5/test_historical_transition_fixture.py",
            "tests/mir5/test_modern_targets.py",
            "tests/mir5/test_k2_base_catalogue.py",
            "tests/mir5/test_k2_base_native_fixture.py",
            "tests/mir5/test_bob_angel_materials.py",
            "tests/mir5/test_bob_angel_catalogue.py",
            "tests/mir5/test_bob_tech_materials.py",
            "tests/mir5/test_bob_core_materials.py",
            "tests/mir5/test_bob_core_progression.py",
            "tests/mir5/test_bob_core_gameplay_fixture.py",
            "tests/mir5/test_override_interactions_fixture.py",
            "tests/mir5/test_armor_py_catalogue.py",
            "tests/mir5/test_native_modded_continuations.py",
            "tests/mir5/test_integration_catalogue_upgrade_fixture.py",
            "tests/mir5/test_bob_angel_native_fixture.py",
            "tests/mir5/test_bob_angel_prototype_caps.py",
            "tests/mir5/test_atan_productivity.py",
            "tests/mir5/test_atan_gameplay_fixture.py",
            "tests/mir5/test_full_catalogue_upgrade_fixture.py",
            "tests/mir5/test_fixed_provider_removal_control_fixture.py",
            "tests/mir5/test_automatic_families.py",
            "tests/mir5/test_competing_productivity.py",
            "tests/mir5/test_native_credit_definitions.py",
            "tests/mir5/test_native_credits.py",
            "tests/mir5/test_legacy_preference_transition_fixture.py",
            "tests/mir5/test_competing_epr_native_fixture.py",
            "tests/mir5/test_competing_fixed_reference.py",
            "tests/mir5/test_competing_fixed_native_fixture.py",
            "tests/mir5/test_competing_dynamic_native_fixture.py",
            "tests/mir5/test_science.py",
            "tests/mir5/test_cryogenic_native_fixture.py",
            "tests/mir5/test_cryogenic_gameplay_fixture.py",
            "tests/mir5/test_material_catalogue.py",
            "tests/mir5/test_material_native_fixture.py",
            "tests/mir5/test_product_targets.py",
            "tests/mir5/test_product_target_extension.py",
            "tests/mir5/test_diagnostics.py",
            "tests/mir5/test_target_adapters.py",
            "tests/mir5/test_caps.py",
            "tests/mir5/test_legacy_caps.py",
            "tests/mir5/test_legacy_caps_lifecycle.py",
            "tests/mir5/test_f200_legacy_cap_fixture.py",
            "tests/mir5/test_f200_legacy_worker_fixture.py",
            "tests/mir5/test_k2_imersite_migration.py",
            "tests/mir5/test_k2_imersite_transition_fixture.py",
            "tests/mir5/test_api.py",
            "tests/mir5/test_runtime_api.py",
            "tests/mir5/test_sdk.py",
            "tests/mir5/test_fixture_controls.py",
            "tests/mir5/test_foreign_research_preservation.py",
            "tests/mir5/test_capture_controls.py",
            "tests/mir5/test_lifecycle.py",
            "tests/mir5/test_native_owners.py",
            "tests/mir5/test_module_permissions_override.py",
            "tests/mir5/test_prototype_limits.py",
            "tests/mir5/test_recipe_schema_repairs.py",
            "tests/mir5/test_module_permissions_activation.py",
            "tests/mir5/test_bootstrap.py",
            "tests/mir5/test_library.py",
            "tests/mir5/test_library_multiplayer_fixture.py",
            "tests/mir5/test_scripted_effects_multiplayer_fixture.py",
            "tests/mir5/test_scripted_effects_toggle_fixture.py",
            "tests/mir5/test_library_model.py",
            "tests/mir5/test_library_translations.py",
            "tests/mir5/test_passive_repair.py",
            "tests/mir5/test_repair_stress_fixture.py",
            "tests/mir5/test_agriculture.py",
            "tests/mir5/test_agriculture_scale_fixture.py",
            "tests/mir5/test_spoilage.py",
            "tests/mir5/test_scripted_effects_lifecycle.py",
            "tests/mir5/test_settings_profile.py",
            "tests/mir5/test_settings_commands.py",
            "tests/mir5/test_properties.py",
            "tests/mir5/test_replay.py",
            "tests/mir5/test_package.py",
            "tests/mir5/test_release.py",
            "tests/mir5/test_compose_replay.py",
            "tests/mir5/test_compare_captures.py",
            "tests/mir5/test_recover_modern_catalogue.py",
            "tests/mir5/test_historical_sources.py",
            "tests/mir5/test_menu_comparison.py",
            "tests/mir5/test_pack.py",
            "tests/mir5/test_host_controls.py",
            "tools/mir5/check_pack.py",
        ])
        self.assertEqual(len(paths), 88)
        self.assertEqual(len(set(paths)), len(paths))
        self.assertEqual(paths[-1], "tools/mir5/check_pack.py")
        self.assertIn("tests/mir5/test_sdk.py", paths)
        self.assertIn("tests/mir5/test_module_permissions_override.py", paths)
        self.assertIn("tests/mir5/test_library.py", paths)
        self.assertIn("tests/mir5/test_capture_controls.py", paths)
        self.assertIn("tests/mir5/test_library_model.py", paths)
        self.assertIn("tests/mir5/test_library_translations.py", paths)
        self.assertIn("tests/mir5/test_legacy_caps.py", paths)
        self.assertIn("tests/mir5/test_legacy_caps_lifecycle.py", paths)
        self.assertIn("tests/mir5/test_passive_repair.py", paths)
        self.assertIn("tests/mir5/test_agriculture.py", paths)
        self.assertIn("tests/mir5/test_spoilage.py", paths)
        self.assertIn("tests/mir5/test_scripted_effects_lifecycle.py", paths)
        self.assertIn("tests/mir5/test_settings_profile.py", paths)
        self.assertIn("tests/mir5/test_settings_commands.py", paths)
        self.assertIn("tests/mir5/test_host_controls.py", paths)
        self.assertFalse(any("test_cutover.py" in path or "test_adoption.py" in path for path in paths))
        self.assertTrue(all(set(row) == {"path", "lua"} for row in controls))
        self.assertTrue(all(row["lua"] for row in controls[:78]))
        self.assertTrue(all(not row["lua"] for row in controls[78:]))

    def test_workflow_runs_the_full_host_gate_for_every_dev_main_change(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("name: MIR 5 host controls", workflow)
        self.assertIn("push:\n    branches:\n      - dev\n      - main", workflow)
        self.assertIn("pull_request:\n    branches:\n      - dev\n      - main", workflow)
        self.assertNotIn("paths:", workflow)
        self.assertIn("verification-plan:\n    name: verification-plan", workflow)
        self.assertIn("host-controls:\n    name: host-controls\n    needs: verification-plan", workflow)
        self.assertIn("git fetch --no-tags --depth=1 origin bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1", workflow)
        self.assertIn("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", workflow)
        self.assertIn("actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065", workflow)
        self.assertIn("python-version: '3.14'", workflow)
        self.assertIn("lupa==2.6 --hash=sha256:b74f944fe46c421e25d0f8692aef1e842192f6f7f68034201382ac440ef9ea67", workflow)
        self.assertIn("lua52.cp314-win_amd64.pyd", workflow)
        self.assertNotIn("PackageAuthority", workflow)
        self.assertNotIn("TargetMaterializer", workflow)
        self.assertNotIn("DevelopmentValidation", workflow)
        self.assertNotIn("tools/lib/assurance", workflow)

        # The legacy matrix no longer provisions a second MIR5 host campaign.
        self.assertNotIn("static.mir5-host-controls", VALIDATE_WORKFLOW.read_text(encoding="utf-8"))

    def test_workflow_binds_and_reads_back_the_exact_plan_before_controls_run(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("kind = 'MIR5HostGatePlanV1'", workflow)
        self.assertIn("git rev-parse HEAD", workflow)
        self.assertIn("git rev-parse 'HEAD^{tree}'", workflow)
        self.assertIn("driver = [ordered]@{ path = $driver; sha256 = $driverHash }", workflow)
        self.assertIn("controls = $controls", workflow)
        self.assertIn("Get-FileHash -LiteralPath $outputPath -Algorithm SHA256", workflow)
        self.assertIn("actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a", workflow)
        self.assertIn("actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c", workflow)
        self.assertIn("needs.verification-plan.outputs.plan_sha256", workflow)
        self.assertIn("Bound MIR5 host plan does not describe this checkout.", workflow)
        self.assertIn("Bound MIR5 host driver hash differs.", workflow)
        self.assertIn("Bound MIR5 host control differs at index", workflow)
        self.assertLess(
            workflow.index("Bind the exact ordered host-control plan"),
            workflow.index("Run the bound MIR5 host controls"),
        )


if __name__ == "__main__":
    unittest.main()
