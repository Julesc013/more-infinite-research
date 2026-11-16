"""The authoritative MIR 5 host-plan and workflow contracts.

The prior assertions exercised MIR 4 assurance classification and development
routing.  Canonical cutover replaces that affected-path lane with this full,
checkout-bound host gate for every dev/main change, so those assertions are no
longer relevant to the delivered host controls.
"""
import ast
import copy
import json
from pathlib import Path, PurePosixPath
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


# Core boundaries remain mandatory even if a source file is accidentally removed.
MANDATORY_HOST_BOUNDARIES = {
    "tests/test_generator.py", "tests/test_bootstrap.py",
    "tests/test_worker_storage_history.py", "tests/test_runtime_api.py",
    "tests/test_library.py", "tests/test_package.py", "tests/test_release.py",
    "tests/test_host_controls.py", "tools/check_repository.py",
}


def validate_host_control_plan(plan, root):
    """Compare the declared driver plan with independently inspectable contracts."""
    if (plan.get("kind") != "MIR5HostControlsPlanV1"
            or plan.get("native_execution") is not False
            or plan.get("release_qualification") is not False):
        raise ValueError("host plan authority differs")
    controls = plan.get("controls")
    if not isinstance(controls, list) or not controls:
        raise ValueError("host controls are absent")
    paths = []
    root = root.resolve(strict=True)
    for row in controls:
        if not isinstance(row, dict) or set(row) != {"path", "lua"} or type(row["lua"]) is not bool:
            raise ValueError("host control invocation shape differs")
        path = row["path"]
        if (not isinstance(path, str) or "\\" in path
                or PurePosixPath(path).is_absolute()
                or ".." in PurePosixPath(path).parts
                or PurePosixPath(path).as_posix() != path):
            raise ValueError("host control path is not canonical")
        source = root / path
        if (not source.is_file() or source.is_symlink()
                or not source.resolve(strict=True).is_relative_to(root)):
            raise ValueError("host control path is missing or outside checkout")
        paths.append(path)
        tree = ast.parse(source.read_text(encoding="utf-8-sig"), filename=path)
        lua_arguments = [node for node in ast.walk(tree)
                         if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                         and node.func.attr == "add_argument"
                         and any(isinstance(arg, ast.Constant) and arg.value == "--lua-runtime-dir"
                                 for arg in node.args)]
        requires_lua = any(any(keyword.arg == "required" and isinstance(keyword.value, ast.Constant)
                               and keyword.value.value is True for keyword in node.keywords)
                           for node in lua_arguments)
        if (row["lua"] and not lua_arguments) or (not row["lua"] and requires_lua):
            raise ValueError("host control invocation mode is unsupported: " + path)
    if len(paths) != len(set(paths)):
        raise ValueError("duplicate host control")
    inventory = {path.relative_to(root).as_posix() for path in (root / "tests").glob("test_*.py")}
    # No excluded top-level Python tests: exceptional lanes need an explicit reason here.
    eligible = inventory | {"tools/check_repository.py"}
    if set(paths) != eligible:
        raise ValueError("host control inventory differs: missing=" + repr(sorted(eligible - set(paths)))
                         + " unexpected=" + repr(sorted(set(paths) - eligible)))
    if not MANDATORY_HOST_BOUNDARIES <= set(paths):
        raise ValueError("mandatory host boundary is absent")
    if paths[-1] != "tools/check_repository.py":
        raise ValueError("repository check must finish the host plan")


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
        validate_host_control_plan(plan, ROOT)

    def test_plan_properties_reject_missing_duplicate_wrong_mode_and_escaped_controls(self):
        with tempfile.TemporaryDirectory(prefix="mir-host-plan-contract-") as directory:
            root = Path(directory)
            paths = sorted(MANDATORY_HOST_BOUNDARIES - {"tools/check_repository.py"}) + ["tools/check_repository.py"]
            for path in paths:
                source = root / path
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text("print('host control')\n", encoding="utf-8")
            lua_source = root / "tests/test_generator.py"
            lua_source.write_text("parser.add_argument('--lua-runtime-dir', required=True)\n", encoding="utf-8")
            plan = {"kind": "MIR5HostControlsPlanV1", "native_execution": False,
                    "release_qualification": False,
                    "controls": [{"path": path, "lua": path == "tests/test_generator.py"} for path in paths]}
            validate_host_control_plan(plan, root)
            # The execution plan alone owns ordinary ordering; harmless permutations pass.
            swapped = copy.deepcopy(plan)
            swapped["controls"][0:2] = reversed(swapped["controls"][0:2])
            validate_host_control_plan(swapped, root)
            opponents = []
            duplicate = copy.deepcopy(plan)
            duplicate["controls"].insert(0, duplicate["controls"][0].copy())
            opponents.append((duplicate, "duplicate"))
            missing = copy.deepcopy(plan)
            missing["controls"].pop(0)
            opponents.append((missing, "inventory"))
            wrong_mode = copy.deepcopy(plan)
            next(row for row in wrong_mode["controls"] if row["path"] == "tests/test_generator.py")["lua"] = False
            opponents.append((wrong_mode, "invocation mode"))
            unsupported_mode = copy.deepcopy(plan)
            next(row for row in unsupported_mode["controls"] if row["path"] == "tests/test_library.py")["lua"] = True
            opponents.append((unsupported_mode, "invocation mode"))
            malformed = copy.deepcopy(plan)
            malformed["controls"][0]["lua"] = 1
            opponents.append((malformed, "invocation shape"))
            escaping = copy.deepcopy(plan)
            escaping["controls"][0]["path"] = "../outside.py"
            opponents.append((escaping, "not canonical"))
            wrong_order = copy.deepcopy(plan)
            wrong_order["controls"][0], wrong_order["controls"][-1] = wrong_order["controls"][-1], wrong_order["controls"][0]
            opponents.append((wrong_order, "finish"))
            overclaim = copy.deepcopy(plan)
            overclaim["native_execution"] = True
            opponents.append((overclaim, "authority"))
            for opponent, reason in opponents:
                with self.subTest(reason=reason), self.assertRaisesRegex(ValueError, reason):
                    validate_host_control_plan(opponent, root)
            new_test = root / "tests/test_new_boundary.py"
            new_test.write_text("print('new boundary')\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "inventory"):
                validate_host_control_plan(plan, root)
            new_test.unlink()
            # Deleting a core file from both the tree and plan cannot erase its obligation.
            (root / "tests/test_bootstrap.py").unlink()
            removed_boundary = copy.deepcopy(plan)
            removed_boundary["controls"] = [row for row in removed_boundary["controls"]
                                             if row["path"] != "tests/test_bootstrap.py"]
            with self.assertRaisesRegex(ValueError, "mandatory"):
                validate_host_control_plan(removed_boundary, root)

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
        render_control = (ROOT / "tests/test_library_render_capture.py").read_text(encoding="utf-8")
        render_revisions = set(re.findall(r'^RETAINED_\d+_REVISION = "([0-9a-f]{40})"$', render_control, re.MULTILINE))
        self.assertTrue(render_revisions)
        multiplayer_control = (ROOT / "tests/test_library_multiplayer_fixture.py").read_text(encoding="utf-8")
        multiplayer_revisions = set(re.findall(
            r'"([0-9a-f]{40}):tools/Invoke-Multiplayer(?:Fixture|Session)\.ps1"', multiplayer_control))
        self.assertTrue(multiplayer_revisions)
        for job in ("verification-plan", "host-controls"):
            self.assertIn(required_fetch, jobs[job], job)
            for revision in input_revisions:
                self.assertRegex(revision, r"^[0-9a-f]{40}$")
                self.assertIn("git fetch --no-tags --depth=1 origin " + revision, jobs[job], (job, revision))
            for revision in observer_revisions:
                self.assertRegex(revision, r"^[0-9a-f]{40}$")
                self.assertIn("git fetch --no-tags --depth=1 origin " + revision, jobs[job], (job, revision))
            for revision in render_revisions:
                self.assertIn("git fetch --no-tags --depth=1 origin " + revision, jobs[job], (job, revision))
            for revision in multiplayer_revisions:
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
