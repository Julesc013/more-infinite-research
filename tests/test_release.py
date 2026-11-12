"""Offline MIR 5 release-freeze identities; no tags, publication, or network."""
import copy
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mir5_release", ROOT / "tools/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    NORMAL_TARGETS = ("f013", "f014", "f015", "f016", "f017", "f018", "f100", "f110", "f200", "f210")
    BASE_DISTRIBUTION_VERSION = "5.0.21000"
    _default_fixture_template = None

    @staticmethod
    def _git(repository, *arguments):
        return subprocess.check_output(["git", "-C", str(repository), *arguments])

    @classmethod
    def _repository(cls, root, source_version="5.0.0"):
        cls._git(root, "init", "-q")
        cls._configure_fixture_repository(root)
        shutil.copytree(ROOT / "source", root / "source")
        record = root / release.package.TARGET_RECORD
        record.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / release.package.TARGET_RECORD, record)
        shutil.copyfile(ROOT / release.package.EARLY_TARGET_RECORD,
                        root / release.package.EARLY_TARGET_RECORD)
        cls._set_source_release(root / "source", source_version)
        cls._git(root, "add", ".")
        cls._git(root, "commit", "-qm", "frozen player source")
        return root / "source", cls._git(root, "rev-parse", "HEAD").decode().strip()

    @classmethod
    def _configure_fixture_repository(cls, repository):
        cls._git(repository, "config", "user.name", "Release test")
        cls._git(repository, "config", "user.email", "release-test@example.invalid")
        cls._git(repository, "config", "core.autocrlf", "false")

    @classmethod
    def _clone_fixture_repository(cls, source, destination):
        subprocess.check_call([
            "git", "-c", "core.autocrlf=false", "clone", "--no-hardlinks", "-q",
            str(source), str(destination),
        ])
        cls._configure_fixture_repository(destination)

    @staticmethod
    @contextlib.contextmanager
    def _without_global_git_config(root):
        empty_global = root / "empty-global.gitconfig"
        empty_global.write_text("", encoding="utf-8")
        previous = {name: os.environ.get(name) for name in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM")}
        os.environ["GIT_CONFIG_GLOBAL"] = str(empty_global)
        os.environ["GIT_CONFIG_NOSYSTEM"] = "1"
        try:
            yield
        finally:
            for name, value in previous.items():
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value

    @classmethod
    def _default_fixture(cls):
        """Build one immutable default fixture per test-process invocation."""
        if cls._default_fixture_template is None:
            temporary = tempfile.TemporaryDirectory()
            root = Path(temporary.name)
            repository = root / "repository"
            repository.mkdir()
            source, commit = cls._repository(repository)
            output = root / "output"
            release.freeze(source, output, revision=commit)
            cls._default_fixture_template = (temporary, repository, output)
        return cls._default_fixture_template

    @classmethod
    def _prepared_default_fixture(cls, root, name):
        """Copy default inputs for one test; each caller verifies its own copy."""
        _, template_repository, template_output = cls._default_fixture()
        repository = root / (name + "-repository")
        cls._clone_fixture_repository(template_repository, repository)
        output = root / (name + "-output")
        shutil.copytree(template_output, output, copy_function=shutil.copy2)
        if (repository / "source" / "info.json").samefile(template_repository / "source" / "info.json"):
            raise AssertionError("Release fixture source copy must not share files with its template")
        if (output / release.INVENTORY_NAME).samefile(template_output / release.INVENTORY_NAME):
            raise AssertionError("Release fixture output copy must not share files with its template")
        source = repository / "source"
        commit = cls._git(repository, "rev-parse", "HEAD").decode().strip()
        return repository, source, commit, output

    @classmethod
    def tearDownClass(cls):
        template = cls._default_fixture_template
        cls._default_fixture_template = None
        if template is not None:
            template[0].cleanup()

    @staticmethod
    def _set_source_release(source, source_version):
        major, minor, patch = source_version.split(".")
        distribution_version = major + "." + minor + "." + str(21000 + int(patch)).zfill(5)
        info_path = source / "info.json"
        info = json.loads(info_path.read_text(encoding="utf-8"))
        old_distribution = info["version"]
        info["version"] = distribution_version
        info_path.write_bytes((json.dumps(info, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        target_path = source / "platform/target.lua"
        target = target_path.read_text(encoding="utf-8")
        old_target_distribution = 'distribution_version="' + old_distribution + '"'
        if target.count(old_target_distribution) != 1:
            raise AssertionError("Fixture source lacks one canonical F210 distribution version")
        target_path.write_bytes(
            target.replace(old_target_distribution,
                           'distribution_version="' + distribution_version + '"').encode("utf-8"))
        changelog_path = source / "changelog.txt"
        changelog = changelog_path.read_text(encoding="utf-8")
        old_header = "Version: " + release.package.source_changelog_version(old_distribution) + "\n"
        if changelog.count(old_header) != 1:
            raise AssertionError("Fixture source lacks one current changelog header")
        requested_header = "Version: " + source_version + "\n"
        headers = [line for line in changelog.splitlines(keepends=True) if line.startswith("Version: ")]
        if requested_header in headers[1:]:
            requested_at = changelog.find(requested_header)
            separator = "-" * 99 + "\n"
            start = changelog.rfind(separator, 0, requested_at)
            if start < 0:
                raise AssertionError("Fixture changelog lacks the requested historical release")
            changelog = changelog[start:]
        else:
            changelog = changelog.replace(old_header, requested_header, 1)
        changelog_path.write_bytes(changelog.encode("utf-8"))

    @classmethod
    def _archive_name(cls, target, distribution_version=None):
        return release._archive_name(target, distribution_version or cls.BASE_DISTRIBUTION_VERSION)

    @staticmethod
    def _body(output):
        inventory = json.loads((output / release.INVENTORY_NAME).read_text(encoding="utf-8"))
        inventory.pop("inventory_sha256")
        return inventory

    @staticmethod
    def _write_body(output, body):
        (output / release.INVENTORY_NAME).write_bytes(release._inventory_bytes(body))

    def _assert_refused(self, source, output, reason):
        """Require this exact verifier refusal, not an unrelated ValueError."""
        with self.assertRaisesRegex(ValueError, re.escape(reason)):
            release.verify(source, output)

    def _assert_freeze_refused(self, source, output, reason):
        """Require this exact freeze-preflight refusal without creating output."""
        with self.assertRaisesRegex(ValueError, re.escape(reason)):
            release.freeze(source, output)
        self.assertFalse(output.exists())

    def test_freeze_builds_ten_canonical_archives_and_repeats_across_roots(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            first_repository = temporary / "first-repository"
            first_repository.mkdir()
            first_source, commit = self._repository(first_repository, "5.0.2")
            first_output = temporary / "first-output"
            inventory = release.freeze(first_source, first_output, revision=commit)
            self.assertEqual(release.TARGETS, self.NORMAL_TARGETS)
            expected = {self._archive_name(target, "5.0.21002") for target in self.NORMAL_TARGETS}
            self.assertEqual({path.name for path in first_output.iterdir()},
                             expected | {release.SUMS_NAME, release.INVENTORY_NAME})
            self.assertEqual(inventory["kind"], release.KIND)
            self.assertEqual(inventory["release"], {
                "source_version": "5.0.2", "source_label": "source5.0.2",
                "tag": "v5.0.2", "title": "MIR 5.0.2"})
            self.assertEqual([asset["target"] for asset in inventory["assets"]], list(self.NORMAL_TARGETS))
            self.assertEqual(len(inventory["assets"]), 10)
            self.assertEqual({asset["target"]: asset["label"] for asset in inventory["assets"]}, {
                "f013": "MIR 5.0.2 for Factorio 0.13.20 (zip)",
                "f014": "MIR 5.0.2 for Factorio 0.14.23 (zip)",
                "f015": "MIR 5.0.2 for Factorio 0.15.40 (zip)",
                "f016": "MIR 5.0.2 for Factorio 0.16.51 (zip)",
                "f017": "MIR 5.0.2 for Factorio 0.17.79 (zip)",
                "f018": "MIR 5.0.2 for Factorio 0.18.47 (zip)",
                "f100": "MIR 5.0.2 for Factorio 1.0.0 (zip)",
                "f110": "MIR 5.0.2 for Factorio 1.1.110 (zip)",
                "f200": "MIR 5.0.2 for Factorio 2.0.77 (zip)",
                "f210": "MIR 5.0.2 for Factorio 2.1.23 (zip)",
            })
            f018 = next(asset for asset in inventory["assets"] if asset["target"] == "f018")
            self.assertEqual(
                {key: f018[key] for key in ("version", "factorio_version", "minimum_base", "support")},
                {"version": "5.0.01802", "factorio_version": "0.18", "minimum_base": "0.18.47",
                 "support": "experimental-best-effort-github-only"},
            )
            self.assertTrue(all("support" not in asset for asset in inventory["assets"] if asset["target"] != "f018"))
            for asset in inventory["assets"]:
                with self.subTest(target=asset["target"]), zipfile.ZipFile(first_output / asset["name"]) as archive:
                    self.assertEqual(archive.namelist()[0], asset["root"] + "/" + asset["members"][0]["path"])
                    info = json.loads(archive.read(asset["root"] + "/info.json"))
                    self.assertEqual({key: info[key] for key in asset["info"]}, asset["info"])
                    self.assertEqual(info["dependencies"][0], "base >= " + asset["minimum_base"])
            self.assertEqual(release.verify(first_source, first_output), inventory)

            second_repository = temporary / "second-repository"
            self._clone_fixture_repository(first_repository, second_repository)
            second_output = temporary / "second-output"
            second_source = second_repository / "source"
            second_inventory = release.freeze(second_source, second_output, revision=commit)
            self.assertEqual(release.verify(second_source, second_output), second_inventory)
            self.assertEqual((first_output / release.INVENTORY_NAME).read_bytes(),
                             (second_output / release.INVENTORY_NAME).read_bytes())
            self.assertEqual(inventory["controller"], release._controller_identity())
            for name in expected | {release.SUMS_NAME}:
                self.assertEqual((first_output / name).read_bytes(), (second_output / name).read_bytes())

    def test_opt_in_early_cohort_binds_exact_best_effort_assets_and_delivery(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository, "5.1.0")
            frozen = temporary / "frozen"
            inventory = release.freeze(
                source,
                frozen,
                revision=commit,
                early_target_record=release.package.EARLY_TARGET_RECORD,
            )
            self.assertEqual(release.TARGETS, self.NORMAL_TARGETS)
            expected = ({self._archive_name(target, "5.1.21000") for target in self.NORMAL_TARGETS}
                        | {self._archive_name(target, "5.1.21000") for target in release.EARLY_TARGETS}
                        | {release.SUMS_NAME, release.EARLY_SUMS_NAME, release.INVENTORY_NAME})
            self.assertEqual({path.name for path in frozen.iterdir()}, expected)
            self.assertEqual(inventory["release"], {
                "source_version": "5.1.0", "source_label": "source5.1.0",
                "tag": "v5.1.0", "title": "MIR 5.1.0"})
            self.assertEqual([asset["target"] for asset in inventory["assets"]], list(self.NORMAL_TARGETS))
            self.assertEqual(
                next(asset["support"] for asset in inventory["assets"] if asset["target"] == "f018"),
                "experimental-best-effort-github-only",
            )
            self.assertTrue(all("support" not in asset for asset in inventory["assets"] if asset["target"] != "f018"))
            cohort = inventory["early_cohort"]
            self.assertEqual(cohort["kind"], release.EARLY_COHORT_KIND)
            self.assertEqual(cohort["qualification"], release.EARLY_QUALIFICATION)
            self.assertEqual(cohort["target_record"]["path"], release.package.EARLY_TARGET_RECORD)
            self.assertEqual([asset["target"] for asset in cohort["assets"]], list(release.EARLY_TARGETS))
            self.assertEqual({asset["target"]: asset["label"] for asset in cohort["assets"]}, {
                "f006": "MIR 5.1.0 for Factorio 0.6.4 (zip)",
                "f007": "MIR 5.1.0 for Factorio 0.7.5 (zip)",
                "f008": "MIR 5.1.0 for Factorio 0.8.8 (zip)",
                "f009": "MIR 5.1.0 for Factorio 0.9.8 (zip)",
                "f010": "MIR 5.1.0 for Factorio 0.10.12 (zip)",
                "f011": "MIR 5.1.0 for Factorio 0.11.22 (zip)",
                "f012": "MIR 5.1.0 for Factorio 0.12.35 (zip)",
            })
            self.assertEqual(
                {asset["target"]: asset["delivery"] for asset in cohort["assets"]},
                {"f006": "extract-to-folder", "f007": "extract-to-folder", "f008": "extract-to-folder",
                 "f009": "zip", "f010": "zip", "f011": "zip", "f012": "zip"},
            )
            for asset in cohort["assets"]:
                with self.subTest(target=asset["target"]), zipfile.ZipFile(frozen / asset["name"]) as archive:
                    info = json.loads(archive.read(asset["root"] + "/info.json"))
                    self.assertEqual(asset["name"], self._archive_name(asset["target"], "5.1.21000"))
                    self.assertEqual(info["version"], asset["version"])
                    self.assertEqual(info["dependencies"][0], "base >= " + asset["minimum_base"])
                    self.assertNotIn("support", asset)
            self.assertEqual(
                next(asset["version"] for asset in cohort["assets"] if asset["target"] == "f006"),
                "5.1.00600",
            )
            self.assertEqual(release.verify(source, frozen), inventory)
            self.assertEqual(
                release.verify(source, frozen, early_target_record=release.package.EARLY_TARGET_RECORD),
                inventory,
            )

    def test_freeze_accepts_successive_patch_and_patch_limit(self):
        cases = (
            ("5.0.1", "5.0.21001", "5.0.01301", "5.0.21001"),
            ("5.0.2", "5.0.21002", "5.0.01302", "5.0.21002"),
            ("5.0.99", "5.0.21099", "5.0.01399", "5.0.21099"),
        )
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            for source_version, distribution_version, f013_version, f210_version in cases:
                with self.subTest(source_version=source_version):
                    repository = temporary / ("repository-" + source_version.replace(".", "-"))
                    repository.mkdir()
                    source, commit = self._repository(repository, source_version)
                    frozen = temporary / ("frozen-" + source_version.replace(".", "-"))
                    inventory = release.freeze(source, frozen, revision=commit)
                    self.assertEqual(inventory["release"], {
                        "source_version": source_version,
                        "source_label": "source" + source_version,
                        "tag": "v" + source_version,
                        "title": "MIR " + source_version,
                    })
                    versions = {asset["target"]: asset["version"] for asset in inventory["assets"]}
                    self.assertEqual(versions["f013"], f013_version)
                    self.assertEqual(versions["f210"], f210_version)
                    self.assertEqual(next(asset["label"] for asset in inventory["assets"]
                                          if asset["target"] == "f210"),
                                     "MIR " + source_version + " for Factorio 2.1.23 (zip)")
                    self.assertEqual(
                        frozen / self._archive_name("f013", distribution_version),
                        frozen / ("more-infinite-research_" + f013_version + ".zip"),
                    )
                    self.assertTrue((frozen / self._archive_name("f013", distribution_version)).is_file())
                    self.assertEqual(release.verify(source, frozen), inventory)

    def test_freeze_refuses_invalid_canonical_f210_metadata_and_changelog(self):
        def set_info_version(source, version):
            path = source / "info.json"
            info = json.loads(path.read_text(encoding="utf-8"))
            info["version"] = version
            path.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        def replace_target(source, old, new):
            path = source / "platform/target.lua"
            target = path.read_bytes()
            if target.count(old) != 1:
                raise AssertionError("Fixture source lacks one target metadata literal")
            path.write_bytes(target.replace(old, new))

        def duplicate_target(source, literal):
            path = source / "platform/target.lua"
            target = path.read_bytes()
            if target.count(literal) != 1:
                raise AssertionError("Fixture source lacks one target metadata literal")
            path.write_bytes(target.replace(literal, literal + literal))

        def wrong_changelog(source):
            path = source / "changelog.txt"
            path.write_text(
                path.read_text(encoding="utf-8").replace("Version: 5.0.0\n", "Version: 5.0.1\n", 1),
                encoding="utf-8",
            )

        def mismatched_source_minimum_base(source):
            path = source / "info.json"
            info = json.loads(path.read_text(encoding="utf-8"))
            if info["dependencies"][0] != "base >= 2.1.23":
                raise AssertionError("Fixture source lacks the canonical F210 base minimum")
            info["dependencies"][0] = "base >= 2.1.0"
            path.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        cases = {
            "wrong-edition-codec": (
                lambda source: set_info_version(source, "5.0.21100"),
                "Frozen player source is not canonical F210 MIR 5 metadata",
            ),
            "invalid-six-digit-codec": (
                lambda source: set_info_version(source, "5.0.210100"),
                "Frozen player source has an invalid MIR 5 distribution codec",
            ),
            "mismatched-changelog": (
                wrong_changelog,
                "Frozen player source changelog does not match its release version",
            ),
            "mismatched-source-minimum-base": (
                mismatched_source_minimum_base,
                "Frozen player source minimum base differs from canonical F210 metadata",
            ),
            "missing-target-id": (
                lambda source: replace_target(source, b'  id="f210",\n', b""),
                "Frozen player source target metadata does not match canonical F210 metadata",
            ),
            "duplicate-target-id": (
                lambda source: duplicate_target(source, b'  id="f210",\n'),
                "Frozen player source target metadata does not match canonical F210 metadata",
            ),
            "mismatched-target-id": (
                lambda source: replace_target(source, b'  id="f210",\n', b'  id="f200",\n'),
                "Frozen player source target metadata does not match canonical F210 metadata",
            ),
            "missing-target-version": (
                lambda source: replace_target(
                    source, b'  distribution_version="5.0.21000",\n', b""),
                "Frozen player source target metadata does not match canonical F210 metadata",
            ),
            "duplicate-target-version": (
                lambda source: duplicate_target(
                    source, b'  distribution_version="5.0.21000",\n'),
                "Frozen player source target metadata does not match canonical F210 metadata",
            ),
            "mismatched-target-version": (
                lambda source: replace_target(
                    source, b'  distribution_version="5.0.21000",\n', b'  distribution_version="5.0.21001",\n'),
                "Frozen player source target metadata does not match canonical F210 metadata",
            ),
        }
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            baseline_repository, baseline_source, baseline_commit, baseline_output = self._prepared_default_fixture(
                temporary, "baseline")
            baseline = release.verify(baseline_source, baseline_output)
            self.assertEqual(baseline["kind"], release.KIND)
            for name, (mutate, reason) in cases.items():
                with self.subTest(name=name):
                    repository = temporary / ("repository-" + name)
                    self._clone_fixture_repository(baseline_repository, repository)
                    source = repository / "source"
                    mutate(source)
                    self._git(repository, "add", "source")
                    self._git(repository, "commit", "-qm", name)
                    output = temporary / ("output-" + name)
                    self._assert_freeze_refused(source, output, reason)

    def test_refusal_fixture_clones_have_local_identity_without_global_git_config(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            with self._without_global_git_config(temporary):
                baseline_repository = temporary / "baseline-repository"
                baseline_repository.mkdir()
                baseline_source, baseline_commit = self._repository(baseline_repository)
                baseline_output = temporary / "baseline-output"
                baseline = release.freeze(baseline_source, baseline_output, revision=baseline_commit)
                self.assertEqual(release.verify(baseline_source, baseline_output), baseline)

                repository = temporary / "mutation-repository"
                self._clone_fixture_repository(baseline_repository, repository)
                self.assertEqual(self._git(repository, "config", "--local", "--get", "user.name"), b"Release test\n")
                self.assertEqual(self._git(repository, "config", "--local", "--get", "user.email"),
                                 b"release-test@example.invalid\n")
                source = repository / "source"
                info_path = source / "info.json"
                info = json.loads(info_path.read_text(encoding="utf-8"))
                info["version"] = "5.0.21100"
                info_path.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                self._git(repository, "add", "source")
                self._git(repository, "commit", "-qm", "invalid canonical metadata")
                output = temporary / "invalid-output"
                self._assert_freeze_refused(
                    source, output, "Frozen player source is not canonical F210 MIR 5 metadata")

    def test_early_cohort_refuses_wrong_record_missing_asset_and_changed_delivery(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository)
            frozen = temporary / "frozen"
            inventory = release.freeze(source, frozen, revision=commit,
                                       early_target_record=release.package.EARLY_TARGET_RECORD)
            self.assertEqual(release.verify(source, frozen), inventory)
            wrong = temporary / "wrong-record"
            with self.assertRaisesRegex(ValueError, "early target record"):
                release.freeze(source, wrong, revision=commit, target_record=release.package.TARGET_RECORD,
                               early_target_record=release.package.TARGET_RECORD)
            self.assertFalse(wrong.exists())

            broken_repository = temporary / "broken-repository"
            self._clone_fixture_repository(repository, broken_repository)
            broken_source = broken_repository / "source"
            (broken_source / "adapters/early/definitions.lua").unlink()
            self._git(broken_repository, "add", "-A")
            self._git(broken_repository, "commit", "-qm", "remove early adapter dependency")
            broken_commit = self._git(broken_repository, "rev-parse", "HEAD").decode().strip()
            broken = temporary / "broken-adapter"
            with self.assertRaisesRegex(ValueError, "missing source dependency"):
                release.freeze(broken_source, broken, revision=broken_commit,
                               early_target_record=release.package.EARLY_TARGET_RECORD)
            self.assertFalse(broken.exists())

            for name, (mutate, reason) in {
                "missing": (
                    lambda output: (output / self._archive_name("f006")).unlink(),
                    "Release output has absent or extra assets",
                ),
                "delivery": (
                    lambda output: self._change_early_delivery(output),
                    "Release inventory differs from frozen source or assets",
                ),
            }.items():
                with self.subTest(name=name):
                    output = temporary / ("early-" + name)
                    shutil.copytree(frozen, output)
                    mutate(output)
                    self._assert_refused(source, output, reason)

    def test_verification_rejects_missing_extra_changed_and_duplicate_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository, source, commit, frozen = self._prepared_default_fixture(temporary, "assets")
            inventory = release.verify(source, frozen)
            self.assertEqual(inventory["kind"], release.KIND)
            with self.assertRaisesRegex(FileExistsError, "Preserve existing release output"):
                release.freeze(source, frozen, revision=commit)

            cases = {
                "missing": (
                    lambda output: (output / self._archive_name("f013")).unlink(),
                    "Release output has absent or extra assets",
                ),
                "extra": (
                    lambda output: (output / "unexpected.txt").write_text("not an asset", encoding="utf-8"),
                    "Release output has absent or extra assets",
                ),
                "changed": (
                    lambda output: (output / self._archive_name("f013")).write_bytes(b"changed"),
                    "Archive bytes differ from the frozen source",
                ),
                "duplicate": (
                    lambda output: self._duplicate_asset(output),
                    "Release inventory differs from frozen source or assets",
                ),
            }
            for name, (mutate, reason) in cases.items():
                with self.subTest(name=name):
                    output = temporary / ("case-" + name)
                    shutil.copytree(frozen, output)
                    mutate(output)
                    self._assert_refused(source, output, reason)

    def test_verification_rejects_release_source_target_and_controller_identity_mutations(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository, "5.0.2")
            frozen = temporary / "frozen"
            inventory = release.freeze(source, frozen, revision=commit)
            self.assertEqual(release.verify(source, frozen), inventory)

            def alter(path, value):
                def mutate(body):
                    cursor = body
                    for key in path[:-1]: cursor = cursor[key]
                    cursor[path[-1]] = value
                return mutate

            cases = {
                "release-source-version": (
                    alter(("release", "source_version"), "5.0.3"),
                    "Release title, tag, or source version differs",
                ),
                "release-title": (
                    alter(("release", "title"), "MIR 5.0.3"),
                    "Release title, tag, or source version differs",
                ),
                "asset-label": (
                    alter(("assets", 0, "label"), "MIR 5.0.01302 for Factorio 0.13 (zip)"),
                    "Release inventory differs from frozen source or assets",
                ),
                "release-tag": (
                    alter(("release", "tag"), "v5.0.3"),
                    "Release title, tag, or source version differs",
                ),
                "source-distribution-version": (
                    alter(("source", "source_distribution_version"), "5.0.21003"),
                    "Frozen source or target record identity differs",
                ),
                "source-tree": (
                    alter(("source", "tree"), "0" * 40),
                    "Frozen source or target record identity differs",
                ),
                "target-digest": (
                    alter(("target_record", "sha256"), "0" * 64),
                    "Frozen source or target record identity differs",
                ),
                "controller-tool": (
                    alter(("controller", "package_tool", "sha256"), "0" * 64),
                    "Local release controller or compression runtime differs",
                ),
                "controller-runtime": (
                    alter(("controller", "runtime", "zlib_runtime_version"), "0.0.0"),
                    "Local release controller or compression runtime differs",
                ),
            }
            for name, (mutate, reason) in cases.items():
                with self.subTest(name=name):
                    output = temporary / ("identity-" + name)
                    shutil.copytree(frozen, output)
                    body = self._body(output)
                    mutate(body)
                    self._write_body(output, body)
                    self._assert_refused(source, output, reason)

            tampered = temporary / "inventory-tampered"
            shutil.copytree(frozen, tampered)
            path = tampered / release.INVENTORY_NAME
            path.write_bytes(path.read_bytes().replace(b'"schema":1', b'"schema":2', 1))
            self._assert_refused(source, tampered, "Release inventory self-digest differs")

    def test_verification_rejects_archive_name_and_root_inventory_mutations(self):
        self._assert_asset_inventory_mutations({
            "asset-name": (
                ("assets", 0, "name"), "wrong.zip",
                "Release inventory differs from frozen source or assets",
            ),
            "archive-root": (
                ("assets", 0, "root"), "wrong-root",
                "Release inventory differs from frozen source or assets",
            ),
        })

    def test_verification_rejects_info_and_distribution_codec_inventory_mutations(self):
        self._assert_asset_inventory_mutations({
            "info-title": (
                ("assets", 0, "info", "title"), "Wrong title",
                "Release inventory differs from frozen source or assets",
            ),
            "distribution-codec": (
                ("assets", 0, "version"), "5.0.00000",
                "Release inventory differs from frozen source or assets",
            ),
        })

    def test_verification_rejects_absent_or_changed_f018_support_disposition(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository, source, commit, frozen = self._prepared_default_fixture(temporary, "f018-support")
            inventory = release.verify(source, frozen)
            self.assertEqual(inventory["kind"], release.KIND)
            for name, (mutate, reason) in {
                "missing": (
                    lambda asset: asset.pop("support"),
                    "Release inventory differs from frozen source or assets",
                ),
                "changed": (
                    lambda asset: asset.__setitem__("support", "stable"),
                    "Release inventory differs from frozen source or assets",
                ),
            }.items():
                with self.subTest(name=name):
                    output = temporary / ("f018-support-" + name)
                    shutil.copytree(frozen, output)
                    body = self._body(output)
                    asset = next(asset for asset in body["assets"] if asset["target"] == "f018")
                    mutate(asset)
                    self._write_body(output, body)
                    self._assert_refused(source, output, reason)

    def _assert_asset_inventory_mutations(self, cases):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository, source, commit, frozen = self._prepared_default_fixture(temporary, "asset-inventory")
            inventory = release.verify(source, frozen)
            self.assertEqual(inventory["kind"], release.KIND)
            for name, (path, value, reason) in cases.items():
                with self.subTest(name=name):
                    output = temporary / ("identity-" + name)
                    shutil.copytree(frozen, output)
                    body = self._body(output)
                    cursor = body
                    for key in path[:-1]:
                        cursor = cursor[key]
                    cursor[path[-1]] = value
                    self._write_body(output, body)
                    self._assert_refused(source, output, reason)

    def test_verification_refuses_changed_archive_root_and_info_even_with_new_inventory_digests(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository, source, commit, frozen = self._prepared_default_fixture(temporary, "archive-content")
            inventory = release.verify(source, frozen)
            self.assertEqual(inventory["kind"], release.KIND)
            for name, (transform, reason) in {
                "root": (
                    lambda member, data: (member.replace("more-infinite-research_5.0.01300", "wrong-root"), data),
                    "Archive bytes differ from the frozen source",
                ),
                "info": (self._wrong_info, "Archive bytes differ from the frozen source"),
                "changelog": (self._wrong_changelog, "Archive bytes differ from the frozen source"),
            }.items():
                with self.subTest(name=name):
                    output = temporary / ("archive-" + name)
                    shutil.copytree(frozen, output)
                    archive = output / self._archive_name("f013")
                    self._rewrite_archive(archive, transform)
                    body = self._body(output)
                    asset = body["assets"][0]
                    asset["archive_sha256"] = release.digest(archive.read_bytes())
                    asset["bytes"] = archive.stat().st_size
                    sums = release._sums(body["assets"])
                    (output / release.SUMS_NAME).write_bytes(sums)
                    body["checksums"] = {"name": release.SUMS_NAME, "sha256": release.digest(sums), "bytes": len(sums)}
                    self._write_body(output, body)
                    self._assert_refused(source, output, reason)

    @staticmethod
    def _duplicate_asset(output):
        body = ReleaseTests._body(output)
        body["assets"].append(copy.deepcopy(body["assets"][0]))
        ReleaseTests._write_body(output, body)

    @staticmethod
    def _change_early_delivery(output):
        body = ReleaseTests._body(output)
        body["early_cohort"]["assets"][0]["delivery"] = "zip"
        ReleaseTests._write_body(output, body)

    @staticmethod
    def _rewrite_archive(path, transform):
        with zipfile.ZipFile(path) as archive:
            members = [(info.filename, archive.read(info.filename)) for info in archive.infolist()]
        temporary = path.with_suffix(".rewrite")
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for member, data in members:
                member, data = transform(member, data)
                archive.writestr(member, data)
        temporary.replace(path)

    @staticmethod
    def _wrong_info(member, data):
        if member.endswith("/info.json"):
            info = json.loads(data)
            info["title"] = "Wrong title"
            data = (json.dumps(info, indent=2) + "\n").encode("utf-8")
        return member, data

    @staticmethod
    def _wrong_changelog(member, data):
        if member.endswith("/changelog.txt"):
            data = data.replace(b"Version: 5.0.0\n", b"Version: 5.0.01300\n", 1)
        return member, data


if __name__ == "__main__":
    unittest.main(verbosity=2)
