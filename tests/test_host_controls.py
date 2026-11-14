"""The authoritative MIR 5 host-plan and workflow contracts.

The prior assertions exercised MIR 4 assurance classification and development
routing.  Canonical cutover replaces that affected-path lane with this full,
checkout-bound host gate for every dev/main change, so those assertions are no
longer relevant to the delivered host controls.
"""
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "tests/Test-MIR5HostControls.ps1"
WORKFLOW = ROOT / ".github/workflows/validate.yml"
VALIDATE_WORKFLOW = ROOT / ".github/workflows/validate.yml"
BRANCH_POLICY = ROOT / "tests/release/Test-MIRBranchPolicy.ps1"


def run_powershell(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pwsh", "-NoProfile", *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )


class ReportResolutionPolicyTests(unittest.TestCase):
    """Execute the claim guard; these synthetic records are not native proof."""

    COMPLETE = """Report scope: complete
Report: #1942
Reproduction evidence: failing released input and exact captured result at evidence/original.json
Regression evidence: old input fails and corrected input passes at evidence/regression.json
Native/preservation evidence: Not applicable: this fixture exercises a tooling policy only
Delivery evidence: exact delivered remedy and readback at evidence/delivery.json
"""

    def policy(self, body, messages=("Preserve evidence",), *, change_event=None, change_packet=None):
        head, base = "b" * 40, "a" * 40
        event = {"repository": {"full_name": "Julesc013/more-infinite-research"},
                 "pull_request": {"body": body, "base": {"sha": base}, "head": {"sha": head},
                                  "commits": len(messages)}}
        packet = {"base_sha": base, "head_sha": head, "commits": [
            {"sha": head if index == len(messages) - 1 else "c" * 40, "message": message}
            for index, message in enumerate(messages)]}
        if change_event:
            change_event(event)
        if change_packet:
            change_packet(packet)
        with tempfile.TemporaryDirectory(prefix="mir-report-policy-") as directory:
            event_path, commits_path = Path(directory) / "event.json", Path(directory) / "commits.json"
            event_path.write_text(json.dumps(event), encoding="utf-8")
            commits_path.write_text(json.dumps(packet), encoding="utf-8")
            return subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-File", str(BRANCH_POLICY), "-ReportPolicyOnly",
                 "-EventPath", str(event_path), "-ReportCommitsPath", str(commits_path)],
                cwd=ROOT, text=True, capture_output=True, check=False)

    def test_unrelated_legacy_and_related_partial_work_remain_usable(self):
        for body in (None, "Explain a documentation correction.", "Report scope:\nReport:\nDelivery evidence:",
                     "Report scope: none\nReport:\nRegression evidence:",
                     "Report scope: diagnostic\nRelated to #1942; the player's failure remains open."):
            with self.subTest(body=body):
                result = self.policy(body)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_partial_scopes_refuse_closing_in_body_and_new_commit(self):
        for scope in ("diagnostic", "partial", "unverified", "functional-candidate", "none"):
            for location in ("body", "commit"):
                with self.subTest(scope=scope, location=location):
                    body = "Report scope: " + scope + "\nRelated to #1942."
                    messages = ("Preserve diagnostic evidence",)
                    if location == "body":
                        body += "\nFixes #1942"
                    else:
                        messages = ("Explain refusal\n\nResolves Julesc013/more-infinite-research#1942",)
                    result = self.policy(body, messages)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("[mir-report-closure-scope]", result.stderr)

    def test_closing_syntax_requires_complete_even_on_a_legacy_pr(self):
        for directive in ("CLOSES: #1942", "Fixes:#1942", "fixed #1942", "resolve\n#1942",
                          "Closed https://github.com/Julesc013/more-infinite-research/issues/1942"):
            with self.subTest(directive=directive):
                result = self.policy(directive)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("[mir-report-closure-scope]", result.stderr)
        result = self.policy("Report scope: diagnostic", ("Fixes:#1942",))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[mir-report-closure-scope]", result.stderr)

    def test_complete_claim_needs_each_evidence_field_and_explicit_native_applicability(self):
        for field in ("Report", "Reproduction evidence", "Regression evidence",
                      "Native/preservation evidence", "Delivery evidence"):
            with self.subTest(field=field):
                body = re.sub(r"(?m)^" + re.escape(field) + r":.*$", field + ": pending", self.COMPLETE)
                result = self.policy(body + "\nCloses #1942")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("[mir-report-complete-evidence]", result.stderr)
        body = self.COMPLETE.replace("Not applicable: this fixture exercises a tooling policy only", "Not applicable")
        result = self.policy(body)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[mir-report-native-applicability]", result.stderr)
        result = self.policy(self.COMPLETE + "\nFixes #1942", ("Resolve #1942",))
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.policy(self.COMPLETE.replace("\n", "\r\n") + "\r\nCloses #1942")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.policy(self.COMPLETE + "\nCloses Julesc013/more-infinite-research#1942")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.policy(self.COMPLETE.replace("#1942", "HTTPS://GITHUB.COM/Julesc013/more-infinite-research/issues/1942")
                             + "\nCloses #1942")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.policy(self.COMPLETE.replace("Report: #1942", "Report: #1845") + "\nCloses #1942")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[mir-report-closure-target]", result.stderr)

    def test_unknown_duplicate_scope_and_unbound_commit_inputs_refuse(self):
        for body in ("Report scope: maybe", "Report scope: complete\nReport scope: partial"):
            with self.subTest(body=body):
                result = self.policy(body)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("[mir-report-scope]", result.stderr)
        result = self.policy("", change_event=lambda event: event.clear())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[mir-report-event-invalid]", result.stderr)
        changes = (
            (lambda packet: packet.update(head_sha="d" * 40), "[mir-report-commits-binding]"),
            (lambda packet: packet.update(commits=[]), "[mir-report-commits-count]"),
            (lambda packet: packet["commits"][0].update(sha="d" * 40), "[mir-report-commits-binding]"),
        )
        for change, refusal in changes:
            with self.subTest(refusal=refusal):
                result = self.policy("Report scope: partial", change_packet=change)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(refusal, result.stderr)

    def test_real_local_commit_messages_are_read_without_fetching(self):
        with tempfile.TemporaryDirectory(prefix="mir-report-git-") as directory:
            repo = Path(directory)
            script = repo / "tests/release/Test-MIRBranchPolicy.ps1"
            script.parent.mkdir(parents=True)
            script.write_bytes(BRANCH_POLICY.read_bytes())
            hooks = repo / "empty-hooks"
            hooks.mkdir()

            def git(*arguments):
                return subprocess.run(
                    ["git", "-C", str(repo), "-c", "user.name=MIR policy test", "-c",
                     "user.email=policy-test@example.invalid", "-c", "commit.gpgsign=false",
                     "-c", "core.hooksPath=" + str(hooks), *arguments],
                    text=True, capture_output=True, check=True).stdout.strip()

            git("init", "--quiet", "--template=")
            git("commit", "--allow-empty", "--quiet", "-m", "Original input")
            base = git("rev-parse", "HEAD")
            git("commit", "--allow-empty", "--quiet", "-m", "Diagnostics only\n\nFixes #1942")
            head = git("rev-parse", "HEAD")
            event = {"repository": {"full_name": "Julesc013/more-infinite-research"},
                     "pull_request": {"body": "Report scope: diagnostic\nRelated to #1942",
                                      "base": {"sha": base}, "head": {"sha": head}, "commits": 1}}
            event_path = repo / "event.json"
            event_path.write_text(json.dumps(event), encoding="utf-8")
            command = ["pwsh", "-NoLogo", "-NoProfile", "-File", str(script),
                       "-ReportPolicyOnly", "-EventPath", str(event_path)]
            result = subprocess.run(command, text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("[mir-report-closure-scope]", result.stderr)
            event["pull_request"]["body"] = self.COMPLETE
            event_path.write_text(json.dumps(event), encoding="utf-8")
            result = subprocess.run(command, text=True, capture_output=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(git("remote"), "", "The control must not depend on a remote.")

    def test_metadata_edits_recheck_the_existing_policy_without_full_host_reruns(self):
        branch = (ROOT / ".github/workflows/branch-policy.yml").read_text(encoding="utf-8")
        self.assertRegex(branch, r"pull_request:\s+types: \[opened, synchronize, reopened, edited\]")
        self.assertIn("contents: read", branch)
        permissions = re.search(r"(?ms)^permissions:\n(.*?)(?=^\S|\Z)", branch)
        self.assertIsNotNone(permissions)
        self.assertNotRegex(permissions.group(1), r"(?m)^\s+[a-z-]+:\s*write\s*$")
        self.assertNotIn("pull_request_target", branch)
        self.assertIn("Test-MIRBranchPolicy.ps1", branch)
        host = WORKFLOW.read_text(encoding="utf-8")
        pull_request = re.search(r"(?ms)^  pull_request:\n(.*?)(?=^  [a-z_]+:|\Z)", host)
        self.assertIsNotNone(pull_request)
        self.assertNotIn("edited", pull_request.group(1))


class HostControlsTests(unittest.TestCase):
    def test_wrapper_has_one_explicit_current_host_control_plan(self):
        plan_command = "& { ./tests/Test-MIR5HostControls.ps1 -Plan } | ConvertTo-Json -Depth 20 -Compress"
        plan = json.loads(run_powershell(["-Command", plan_command]).stdout)
        self.assertEqual(plan["kind"], "MIR5HostControlsPlanV1")
        self.assertFalse(plan["native_execution"])
        self.assertFalse(plan["release_qualification"])
        controls = plan["controls"]
        paths = [row["path"] for row in controls]
        self.assertEqual(paths, [
            "tests/test_generator.py",
            "tests/test_library_render_capture.py",
            "tests/test_continuation_ownership.py",
            "tests/test_native_research_speed_finite_fixture.py",
            "tests/test_secretas_continuation.py",
            "tests/test_worker_storage_continuation.py",
            "tests/test_worker_storage_history.py",
            "tests/test_worker_native_owner_data.py",
    "tests/test_worker_storage_default_native.py",
    "tests/test_worker_storage_provider_native.py",
            "tests/test_worker_default_snapshot_probe.py",
            "tests/test_ferrum_worker_storage_native.py",
            "tests/test_ric_marine.py",
            "tests/test_discovery_tree_compatibility.py",
            "tests/test_early_target_adapter.py",
            "tests/test_historical_direct.py",
            "tests/test_historical_continuations.py",
            "tests/test_historical_native_runner.py",
            "tests/test_historical_transition_fixture.py",
            "tests/test_f110_f200_transition_fixture.py",
            "tests/test_f100_f110_laser_fixture.py",
            "tests/test_published_f100_forward_fixture.py",
            "tests/test_migration_origins_f200_source_controls.py",
            "tests/test_migration_origins_f200_110_source_controls.py",
            "tests/test_migration_origins_f200_110_successor_controls.py",
            "tests/test_migration_origins_f200_120_source_controls.py",
            "tests/test_migration_origins_f200_120_successor_controls.py",
            "tests/test_migration_origins_successor_controls.py",
            "tests/test_modern_targets.py",
            "tests/test_k2_base_catalogue.py",
            "tests/test_k2_native_space_age.py",
            "tests/test_space_exploration_catalogue.py",
            "tests/test_space_exploration_pipeline.py",
            "tests/test_k2_base_native_fixture.py",
            "tests/test_aai_parity_native_controls.py",
            "tests/test_bob_angel_materials.py",
            "tests/test_bob_angel_catalogue.py",
            "tests/test_bob_angel_f200_combined_profile.py",
            "tests/test_bob_angel_f200_combined_gameplay_fixture.py",
            "tests/test_angel_f210_catalogue.py",
            "tests/test_angel_f210_pipeline.py",
            "tests/test_bob_tech_materials.py",
            "tests/test_bob_tech_gameplay_fixture.py",
            "tests/test_bob_core_materials.py",
            "tests/test_bob_material_preservation_fixture.py",
            "tests/test_bob_plates_f210_facts.py",
            "tests/test_bob_plates_f210_materials.py",
            "tests/test_bob_plates_f210_pipeline.py",
            "tests/test_bob_plates_full_base_f210_pipeline.py",
            "tests/test_bob_tech_progression_f210_pipeline.py",
            "tests/test_bob_core_progression.py",
            "tests/test_bob_core_gameplay_fixture.py",
            "tests/test_override_interactions_fixture.py",
            "tests/test_armor_py_catalogue.py",
            "tests/test_bob_warfare_f210_pipeline.py",
            "tests/test_bob_productivity_f210_pipeline.py",
            "tests/test_ironclad_f210_pipeline.py",
            "tests/test_bob_angel_f210_pipeline.py",
            "tests/test_angelbob_f210_steel_fixture.py",
            "tests/test_angelbob_preowned_steel.py",
            "tests/test_bob_angel_f210_science_oil_fixture.py",
            "tests/test_py_f210_catalogue.py",
            "tests/test_py_f210_pipeline.py",
            "tests/test_native_modded_continuations.py",
            "tests/test_bob_native_inserter.py",
            "tests/test_integration_catalogue_upgrade_fixture.py",
            "tests/test_bob_angel_native_fixture.py",
            "tests/test_bob_angel_prototype_caps.py",
            "tests/test_atan_productivity.py",
            "tests/test_atan_gameplay_fixture.py",
            "tests/test_full_catalogue_upgrade_fixture.py",
            "tests/test_full_catalogue_upgrade_f210_fixture.py",
            "tests/test_f200_f210_catalogue_upgrade_fixture.py",
            "tests/test_fixed_provider_removal_control_fixture.py",
            "tests/test_automatic_families.py",
            "tests/test_competing_productivity.py",
            "tests/test_native_credit_definitions.py",
            "tests/test_native_gun_credit_definitions.py",
            "tests/test_native_gun_credits.py",
            "tests/test_native_family_credit_definitions.py",
            "tests/test_native_credits.py",
            "tests/test_native_family_paid_credits.py",
            "tests/test_native_credit_vectors.py",
            "tests/test_native_credit_vector_fixture.py",
            "tests/test_known_base_addition_fixture.py",
            "tests/test_legacy_module_credits.py",
            "tests/test_legacy_cannon_credits.py",
            "tests/test_legacy_preference_transition_fixture.py",
            "tests/test_competing_epr_native_fixture.py",
            "tests/test_competing_fixed_reference.py",
            "tests/test_competing_fixed_native_fixture.py",
            "tests/test_competing_dynamic_native_fixture.py",
            "tests/test_science.py",
            "tests/test_sif_catalogue_policy.py",
            "tests/test_named_science_replacement_fixture.py",
            "tests/test_fresh_science_transition_fixture.py",
            "tests/test_sif_retained_manufacturing.py",
            "tests/test_sif_retained_manufacturing_native.py",
            "tests/test_sif_technology_reload_diagnostic.py",
            "tests/test_sif_science_retirement_fixture.py",
            "tests/test_cryogenic_native_fixture.py",
            "tests/test_cryogenic_gameplay_fixture.py",
            "tests/test_material_catalogue.py",
            "tests/test_material_native_fixture.py",
            "tests/test_product_targets.py",
            "tests/test_product_target_extension.py",
            "tests/test_native_family_product_targets.py",
            "tests/test_native_owner_costs.py",
            "tests/test_native_owner_fallback.py",
            "tests/test_native_owner_withheld_runtime.py",
            "tests/test_native_owner_fallback_state_boundary.py",
            "tests/test_native_owner_cap_adoption.py",
            "tests/test_native_owner_field_tuning.py",
            "tests/test_diagnostics.py",
            "tests/test_target_adapters.py",
            "tests/test_caps.py",
            "tests/test_legacy_caps.py",
            "tests/test_legacy_caps_lifecycle.py",
            "tests/test_f200_legacy_cap_fixture.py",
            "tests/test_legacy_boolean_cap_fixture.py",
            "tests/test_f200_foreign_cap_baseline_fixture.py",
            "tests/test_native_owner_cap_order_fixture.py",
            "tests/test_f200_legacy_worker_fixture.py",
            "tests/test_k2_imersite_migration.py",
            "tests/test_k2_imersite_transition_fixture.py",
            "tests/test_k2se_imersite_carrier_fixture.py",
            "tests/test_api.py",
            "tests/test_api_boundary_fixture.py",
            "tests/test_runtime_api.py",
            "tests/test_planet_discovery_api_fixture.py",
            "tests/test_discovery_recovery_fixture.py",
            "tests/test_sdk.py",
            "tests/test_fixture_controls.py",
            "tests/test_foreign_research_preservation.py",
            "tests/test_capture_controls.py",
            "tests/test_lifecycle.py",
            "tests/test_native_owners.py",
            "tests/test_module_permissions_override.py",
            "tests/test_prototype_limits.py",
            "tests/test_recipe_schema_repairs.py",
            "tests/test_prerequisite_repairs.py",
            "tests/test_module_permissions_activation.py",
            "tests/test_bootstrap.py",
            "tests/test_library.py",
            "tests/test_library_legacy_settings_search_probe.py",
            "tests/test_library_multiplayer_fixture.py",
            "tests/test_library_native_input_fixture.py",
            "tests/test_library_paired_browser_fixture.py",
            "tests/test_scripted_effects_multiplayer_fixture.py",
            "tests/test_scripted_effects_toggle_fixture.py",
            "tests/test_library_model.py",
            "tests/test_library_translations.py",
            "tests/test_passive_repair.py",
            "tests/test_repair_stress_fixture.py",
            "tests/test_agriculture.py",
            "tests/test_agriculture_scale_fixture.py",
            "tests/test_large_factory_activity_fixture.py",
            "tests/test_spoilage.py",
            "tests/test_scripted_effects_lifecycle.py",
            "tests/test_settings_profile.py",
            "tests/test_profile_native_witness.py",
            "tests/test_settings_commands.py",
            "tests/test_properties.py",
            "tests/test_replay.py",
            "tests/test_locale_catalogue.py",
            "tests/test_mod_settings_dat.py",
            "tests/test_angelbob_rebalance_space_age_profiles.py",
            "tests/test_dependency_declarations.py",
            "tests/test_library_native_input.py",
            "tests/test_library_profile_reader.py",
            "tests/test_f110_f200_runner.py",
            "tests/test_f100_f110_laser_runner.py",
            "tests/test_published_f100_forward_runner.py",
            "tests/test_native_fixture_modes.py",
            "tests/test_package.py",
            "tests/test_early_package.py",
            "tests/test_changelog.py",
            "tests/test_release.py",
            "tests/test_compose_replay.py",
            "tests/test_compare_captures.py",
            "tests/test_recover_modern_catalogue.py",
            "tests/test_historical_sources.py",
            "tests/test_menu_comparison.py",
            "tests/test_menu_comparison_analysis.py",
            "tests/test_runtime_benchmark_analysis.py",
            "tests/test_pack.py",
            "tests/test_startup_timings.py",
            "tests/test_host_controls.py",
            "tools/check_repository.py",
        ])
        self.assertEqual(len(set(paths)), len(paths))
        self.assertEqual(paths[-1], "tools/check_repository.py")
        self.assertIn("tests/test_sdk.py", paths)
        self.assertIn("tests/test_module_permissions_override.py", paths)
        self.assertIn("tests/test_library.py", paths)
        self.assertIn("tests/test_capture_controls.py", paths)
        self.assertIn("tests/test_library_model.py", paths)
        self.assertIn("tests/test_library_translations.py", paths)
        self.assertIn("tests/test_legacy_caps.py", paths)
        self.assertIn("tests/test_legacy_caps_lifecycle.py", paths)
        self.assertIn("tests/test_passive_repair.py", paths)
        self.assertIn("tests/test_agriculture.py", paths)
        self.assertIn("tests/test_spoilage.py", paths)
        self.assertIn("tests/test_scripted_effects_lifecycle.py", paths)
        self.assertIn("tests/test_settings_profile.py", paths)
        self.assertIn("tests/test_settings_commands.py", paths)
        self.assertIn("tests/test_locale_catalogue.py", paths)
        self.assertIn("tests/test_host_controls.py", paths)
        self.assertFalse(any("test_cutover.py" in path or "test_adoption.py" in path for path in paths))
        self.assertTrue(all(set(row) == {"path", "lua"} for row in controls))
        first_python_only = paths.index("tests/test_locale_catalogue.py")
        self.assertTrue(all(row["lua"] for row in controls[:first_python_only]))
        self.assertTrue(all(not row["lua"] for row in controls[first_python_only:]))

    def test_workflow_runs_the_full_host_gate_for_every_dev_main_change(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("name: MIR 5 host controls", workflow)
        self.assertIn("push:\n    branches:\n      - dev\n      - main", workflow)
        self.assertIn("pull_request:\n    branches:\n      - dev\n      - main", workflow)
        self.assertNotIn("paths:", workflow)
        self.assertIn("verification-plan:\n    name: verification-plan", workflow)
        self.assertIn("host-controls:\n    name: host-controls\n    needs: verification-plan", workflow)
        self.assertIn("git fetch --no-tags --depth=1 origin bd9774f323b6eb1561c1d9ff0c91ecc3f7acd1d1", workflow)
        self.assertIn("git fetch --no-tags --depth=1 origin 8643cc91bc915e008556a5315dbb0a743247e7ab", workflow)
        self.assertIn("git fetch --no-tags --depth=1 origin c37fca88667d550660f5b9c0efd7f272b56d6025", workflow)
        fixture_control = (ROOT / "tests/test_f200_foreign_cap_baseline_fixture.py").read_text(encoding="utf-8")
        fixture_revision = re.search(r'^FIXTURE_REVISION = "([0-9a-f]{40})"$', fixture_control, re.MULTILINE)
        self.assertIsNotNone(fixture_revision)
        required_fetch = "git fetch --no-tags --depth=1 origin " + fixture_revision.group(1)
        jobs = dict(re.findall(r"(?ms)^  ([a-z-]+):\n(.*?)(?=^  [a-z-]+:\n|\Z)", workflow))
        input_revisions = set()
        for name in ("library-input-order-neutral-prepared-r01.json", "library-input-removal-observed-prepared-r01.json"):
            declaration = json.loads((ROOT / "spec/evidence" / name).read_text(encoding="utf-8"))
            for profile in declaration["profiles"]:
                if profile["mode"] == "input":
                    input_revisions.update(member["source_revision"] for member in profile["owned_fixture"]["members"])
        observer_record = json.loads(
            (ROOT / "spec/evidence/library-native-input-observer-r15-prepared.json").read_text(encoding="utf-8")
        )
        observer_revisions = {observer_record["source"]["commit"]}
        observer_revisions.update(
            member["source_revision"]
            for prepared in observer_record["profiles_and_archives"]
            for member in prepared["archive"]["members"]
        )
        for job in ("verification-plan", "host-controls"):
            self.assertIn(required_fetch, jobs[job], job)
            for revision in input_revisions:
                self.assertRegex(revision, r"^[0-9a-f]{40}$")
                self.assertIn("git fetch --no-tags --depth=1 origin " + revision, jobs[job], (job, revision))
            for revision in observer_revisions:
                self.assertRegex(revision, r"^[0-9a-f]{40}$")
                self.assertIn("git fetch --no-tags --depth=1 origin " + revision, jobs[job], (job, revision))
        self.assertIn("actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", workflow)
        self.assertIn("actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0", workflow)
        self.assertIn("python-version: '3.14'", workflow)
        self.assertIn("lupa==2.6 --hash=sha256:b74f944fe46c421e25d0f8692aef1e842192f6f7f68034201382ac440ef9ea67", workflow)
        self.assertIn("lua52.cp314-win_amd64.pyd", workflow)
        self.assertNotIn("PackageAuthority", workflow)
        self.assertNotIn("TargetMaterializer", workflow)
        self.assertNotIn("DevelopmentValidation", workflow)
        self.assertNotIn("tools/lib/assurance", workflow)

        # Canonical layout has one full host workflow; the old mirror is retired.
        self.assertFalse((ROOT / ".github/workflows/mir5.yml").exists())
        self.assertNotIn("static.mir5-host-controls", VALIDATE_WORKFLOW.read_text(encoding="utf-8"))

    def test_workflow_binds_and_reads_back_the_exact_plan_before_controls_run(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("kind = 'MIR5HostGatePlanV1'", workflow)
        self.assertIn("git rev-parse HEAD", workflow)
        self.assertIn("git rev-parse 'HEAD^{tree}'", workflow)
        self.assertIn("driver = [ordered]@{ path = $driver; sha256 = $driverHash }", workflow)
        self.assertIn("controls = $controls", workflow)
        self.assertIn("Get-FileHash -LiteralPath $outputPath -Algorithm SHA256", workflow)
        self.assertIn("actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9", workflow)
        self.assertIn("actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333", workflow)
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
