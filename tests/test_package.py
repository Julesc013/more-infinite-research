"""Package boundary and reproducibility checks independent of research output."""
import importlib.util
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("mir_native_package", ROOT / "tools/package.py")
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


# `targets-baseline.json` records the historical membership and the nine local
# published 4.7.3 archives confirm these exact payload hashes.  The common
# migrations shipped everywhere; the Imersite rename was F210-only.  The
# current F110+ bridge is deliberately a new, separately bound member.
PUBLISHED_473_SHARED_MIGRATION_SHA256 = {
    "migrations/more-infinite-research_2.0.5.json": "07A2759B963321A87B1047029AE426C7B2784033BC7C4F899D2640C037C5EEE2",
    "migrations/more-infinite-research_2.1.0.json": "F427B215D77BC86608010ADC1D0D1A1C98BE61F0D7140EF716D77E46DAB8092D",
}
F210_ONLY_MIGRATION = "migrations/more-infinite-research_4.7.0.json"
PUBLISHED_473_F210_MIGRATION_SHA256 = "0980B0B6F1675F6827A8E4151F778143EA74C9C6C3440CC2318129DBCE63C379"
F110_PLUS_MIGRATION = "migrations/more-infinite-research_5.0.11000.json"
F110_PLUS_MIGRATION_SHA256 = "C26C6B21D777F3C20410C9C9ECDAFFE8ADF8DDDEAE556FE8B044146CEC40117D"
F110_PLUS_MIGRATION_TARGETS = {"f110", "f200", "f210"}


class PackageTests(unittest.TestCase):
    @staticmethod
    def _git(repository, *arguments):
        return subprocess.check_output(["git", "-C", str(repository), *arguments])

    @classmethod
    def _write_layout_repository(cls, repository, source_path, target_record):
        cls._git(repository, "init", "-q")
        cls._git(repository, "config", "user.name", "Package test")
        cls._git(repository, "config", "user.email", "package-test@example.invalid")
        cls._git(repository, "config", "core.autocrlf", "false")
        staged_source = ROOT / "source"
        for file in staged_source.rglob("*"):
            if file.is_file():
                destination = repository / source_path / file.relative_to(staged_source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(file, destination)
        # This is deliberately present in both layouts and must stay outside
        # the selected player member set.
        excluded = repository / source_path / "tools/not-a-player-member.lua"
        excluded.parent.mkdir(parents=True, exist_ok=True)
        excluded.write_text("error('developer-only')\n", encoding="utf-8")
        record = repository / target_record
        record.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / pack.TARGET_RECORD, record)
        cls._git(repository, "add", ".")
        cls._git(repository, "commit", "-qm", "player and target record")
        return cls._git(repository, "rev-parse", "HEAD").decode().strip()

    def test_selected_editions_have_one_actual_import_closure_and_exact_codec(self):
        source = ROOT / "source"
        published = json.loads((ROOT / "spec/inventory/target-load-order-470.json").read_text())
        dependencies = {row["target"]: row["dependencies"] for row in published["records"]}
        sif_ordering = "? space-is-fake"
        for target, family, minimum in [
            ("f013", "0.13", "0.13.20"), ("f014", "0.14", "0.14.23"),
            ("f015", "0.15", "0.15.40"), ("f016", "0.16", "0.16.51"),
            ("f017", "0.17", "0.17.79"), ("f018", "0.18", "0.18.47"), ("f100", "1.0", "1.0.0"),
            ("f110", "1.1", "1.1.110"), ("f200", "2.0", "2.0.77"), ("f210", "2.1", "2.1.23"),
        ]:
            with self.subTest(target=target):
                info, rows = pack.members(source, target=target)
                files = dict(rows)
                expected_dependencies = ([*dependencies[target]] if target in dependencies
                                         else ["base >= " + minimum])
                if target == "f210":
                    # The named mortar binding consumes Ironclad's final
                    # native predecessor edits. Preserve the historical
                    # inventory and assert this new ordering explicitly.
                    ironclad_ordering = "(?) aai-vehicles-ironclad"
                    self.assertNotIn(ironclad_ordering, dependencies[target])
                    expected_dependencies.insert(1, ironclad_ordering)
                if target in ("f200", "f210"):
                    # The retained 4.7 inventory predates this MIR5 ordering
                    # correction. Current modern packages must run after SIF
                    # when it is active, so their final-stage source checks
                    # see SIF's authored promethium owner.
                    self.assertNotIn(sif_ordering, dependencies[target])
                    if target == "f210":
                        # The retained 4.7.0 receipt records its prior 2.1.18
                        # optional floors. Current F210 metadata binds both
                        # official engine-coupled dependencies to 2.1.23.
                        expected_dependencies = [
                            dependency.replace(" >= 2.1.18", " >= 2.1.23")
                            for dependency in expected_dependencies
                        ]
                    expected_dependencies.append(sif_ordering)
                self.assertEqual(info["factorio_version"], family)
                self.assertEqual(info["dependencies"], expected_dependencies)
                self.assertEqual(info["dependencies"][0], "base >= " + minimum)
                self.assertEqual(info["version"], "5.0." + target[1:] + "00")
                self.assertEqual(json.loads(files["info.json"])["version"], info["version"])
                self.assertIn(('id = "' + target + '"').encode(), files["platform/target.lua"])
                probability = "independent_probability" if target == "f210" else "probability"
                self.assertIn(('recipe_probability = "' + probability + '"').encode(), files["platform/target.lua"])
                self.assertIn(('receiver_limits = ' + str(target == "f210").lower()).encode(), files["platform/target.lua"])
                reduced = target not in ("f200", "f210")
                self.assertEqual("research/historical_direct.lua" in files, reduced)
                self.assertEqual("runtime/bootstrap.lua" in files, not reduced)
                self.assertEqual("research/modern.lua" in files, not reduced)
                self.assertEqual(any(path.startswith("adapters/") for path in files), reduced)
                self.assertIn("api/v1/data.lua", files)
                self.assertIn("api/v1/runtime.lua", files)
                if target == "f018":
                    for literal in (
                        'id = "f018"', 'factorio_version = "0.18"', 'minimum_base = "0.18.47"',
                        "reduced = true", "research_levels = true", "recipe_productivity = false",
                        'recipe_probability = "probability"', "productivity_ignores_stats = false",
                        "receiver_limits = false", "cargo_research = false",
                    ):
                        self.assertIn(literal.encode(), files["platform/target.lua"])
                    self.assertEqual(
                        {name: files[name] for name in pack.ENTRYPOINTS},
                        {
                            "data.lua": b'require("adapters.reduced.data").apply()\n',
                            "settings.lua": b'require("adapters.reduced.settings").apply()\n',
                            "data-final-fixes.lua": b'require("adapters.reduced.data-final-fixes").apply()\n',
                            "control.lua": b'require("adapters.reduced.control").apply()\n',
                        },
                    )
                    self.assertNotIn("data-updates.lua", files)
                    self.assertNotIn("presentation/library.lua", files)
                expected_migrations = dict(PUBLISHED_473_SHARED_MIGRATION_SHA256)
                if target == "f210":
                    expected_migrations[F210_ONLY_MIGRATION] = PUBLISHED_473_F210_MIGRATION_SHA256
                if target in F110_PLUS_MIGRATION_TARGETS:
                    expected_migrations[F110_PLUS_MIGRATION] = F110_PLUS_MIGRATION_SHA256
                actual_migrations = {path for path in files if path.startswith("migrations/")}
                self.assertEqual(actual_migrations, set(expected_migrations))
                for path, expected_sha256 in expected_migrations.items():
                    self.assertEqual(hashlib.sha256(files[path]).hexdigest().upper(), expected_sha256)

                # Target selection removes only engine-inapplicable migration
                # members; all retained player members remain byte-identical.
                source_files = {
                    path.relative_to(source).as_posix(): path.read_bytes()
                    for path in source.rglob("*")
                    if path.is_file() and pack.admitted(path.relative_to(source).as_posix())
                }
                editions, _ = pack.read_editions(source)
                unfiltered_info = json.loads(source_files["info.json"])
                unfiltered = pack.select_edition(source_files, unfiltered_info, target, editions)
                unfiltered["info.json"] = (json.dumps(unfiltered_info, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
                excluded = set()
                if target != "f210":
                    excluded.add(F210_ONLY_MIGRATION)
                if target not in F110_PLUS_MIGRATION_TARGETS:
                    excluded.add(F110_PLUS_MIGRATION)
                self.assertEqual(set(unfiltered) - set(files), excluded)
                self.assertEqual({path: value for path, value in files.items() if path not in excluded},
                                 {path: value for path, value in unfiltered.items() if path not in excluded})
                for name in files:
                    self.assertFalse(name.startswith(("source/", "targets/", "tests/", "spec/")))

    def test_early_target_selection_excludes_all_normal_migration_members(self):
        source = ROOT / "source"
        editions, _ = pack.read_editions(source, target_record=pack.EARLY_TARGET_RECORD)
        for target in sorted(editions):
            with self.subTest(target=target):
                _, rows = pack.members(source, target=target, editions=editions,
                                       target_record=pack.EARLY_TARGET_RECORD)
                self.assertFalse(any(path.startswith("migrations/") for path, _ in rows))

    def test_f210_engine_coupled_optional_minima_match_the_selected_base_floor(self):
        editions, _ = pack.read_editions(ROOT / "source")
        minimum = editions["f210"]["minimum_base"]
        source_info = json.loads((ROOT / "source/info.json").read_text())
        _, rows = pack.members(ROOT / "source", target="f210")
        packaged_info = json.loads(dict(rows)["info.json"])
        expected = {"? recycler >= " + minimum, "? space-age >= " + minimum}
        for info in (source_info, packaged_info):
            self.assertTrue(expected.issubset(info["dependencies"]))

    def test_unimplemented_unknown_and_arbitrary_edition_versions_refuse_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            for target in ("f005", "../f210"):
                output = Path(temporary) / target.replace("/", "_") / "more-infinite-research_5.0.20000.zip"
                with self.assertRaises(ValueError):
                    pack.build(ROOT / "source", output, target=target)
                self.assertFalse(output.exists())
                self.assertFalse(output.parent.exists())
            with self.assertRaises(ValueError):
                pack.members(ROOT / "source", version="5.0.01501", target="f015")
            editions, _ = pack.read_editions(ROOT / "source")
            editions["f200"]["source_available"] = False
            with self.assertRaisesRegex(ValueError, "adaptation remains incomplete"):
                pack.members(ROOT / "source", target="f200", editions=editions)

    def test_generic_local_mir_version_updates_only_its_declared_runtime_target(self):
        source = ROOT / "source"
        source_info, source_rows = pack.members(source)
        source_files = dict(source_rows)
        selected_info, selected_rows = pack.members(source, target="f210")

        local_version = "6.1.21002"
        local_info, local_rows = pack.members(source, version=local_version)
        local_files = dict(local_rows)

        self.assertEqual(local_info["version"], local_version)
        self.assertEqual(json.loads(local_files["info.json"])["version"], local_version)
        self.assertIn(b"Version: 6.1.2\n", local_files["changelog.txt"])
        self.assertNotIn(local_version.encode("ascii"), local_files["changelog.txt"])
        expected_target = source_files["platform/target.lua"].replace(
            source_info["version"].encode("ascii"), local_version.encode("ascii"))
        self.assertEqual(local_files["platform/target.lua"], expected_target)
        changed = {"info.json", "changelog.txt", "platform/target.lua"}
        self.assertEqual({name: data for name, data in local_files.items() if name not in changed},
                         {name: data for name, data in source_files.items() if name not in changed})

        # A generic local-version call cannot alter selected-target materialization.
        selected_after_info, selected_after_rows = pack.members(source, target="f210")
        self.assertEqual((selected_after_info, selected_after_rows), (selected_info, selected_rows))

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "wrong/more-infinite-research_5.0.20000.zip"
            for wrong_edition in ("5.0.20000", "5.0.01501"):
                with self.subTest(version=wrong_edition):
                    with self.assertRaisesRegex(ValueError, "different MIR edition"):
                        pack.build(source, output, version=wrong_edition)
                    self.assertFalse(output.exists())
                    self.assertFalse(output.parent.exists())

    def test_generic_local_mir_version_refuses_malformed_target_contract_and_leaves_fixture_lua_raw(self):
        source = ROOT / "source"
        _, rows = pack.members(source)
        files = dict(rows)
        target = files["platform/target.lua"]
        malformed = {
            "missing": target.replace(b"distribution_version", b"distribution_verson"),
            "duplicate": target + b'\n  distribution_version="5.0.21000",\n',
            "missing-id": target.replace(b"id=", b"edition="),
            "duplicate-id": target + b'\n  id="f210",\n',
            "malformed-duplicate-id": target + b'\n  id="poison",\n',
            "wrong-source-codec": target.replace(b'id="f210"', b'id="f200"'),
            "malformed-duplicate-version": target + b'\n  distribution_version="poison",\n',
        }
        for name, broken_target in malformed.items():
            with self.subTest(contract=name):
                broken = dict(files, **{"platform/target.lua": broken_target})
                with self.assertRaisesRegex(ValueError, "source target"):
                    pack.members(source, version="5.0.21001", committed_files=broken)
                if name.startswith("malformed-duplicate"):
                    with tempfile.TemporaryDirectory() as temporary:
                        fixture = Path(temporary) / "source"
                        (fixture / "platform").mkdir(parents=True)
                        (fixture / "info.json").write_bytes(files["info.json"])
                        (fixture / "data.lua").write_text("data:extend({})\n")
                        (fixture / "platform/target.lua").write_bytes(broken_target)
                        output = Path(temporary) / "never/more-infinite-research_5.0.21001.zip"
                        with self.assertRaisesRegex(ValueError, "source target"):
                            pack.build(fixture, output, version="5.0.21001")
                        self.assertFalse(output.exists())
                        self.assertFalse(output.parent.exists())

        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary) / "fixture"
            (fixture / "platform").mkdir(parents=True)
            (fixture / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (fixture / "data.lua").write_text("data:extend({})\n")
            decoy = b'return { id="f210", distribution_version="0.1.0" }\n'
            (fixture / "platform/target.lua").write_bytes(decoy)
            _, fixture_rows = pack.members(fixture, version="0.2.0")
            fixture_files = dict(fixture_rows)
            self.assertEqual(fixture_files["platform/target.lua"], decoy)
            self.assertEqual(json.loads(fixture_files["info.json"])["version"], "0.2.0")

    def test_selected_edition_missing_module_refuses_instead_of_shipping_broken_imports(self):
        source = ROOT / "source"
        _, rows = pack.members(source)
        files = dict(rows)
        del files["adapters/reduced/control.lua"]
        with self.assertRaisesRegex(ValueError, "missing source dependency"):
            pack.members(source, committed_files=files, target="f015")

    def test_committed_target_record_is_frozen_with_the_player_source_and_refuses_dirty_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(["git", "-C", str(root), *arguments])
            git("init", "-q")
            git("config", "user.name", "Package test")
            git("config", "user.email", "package-test@example.invalid")
            source = root / "player"
            for name in [*pack.ENTRYPOINTS, "api/v1/data.lua", "api/v1/runtime.lua", "platform/target.lua"]:
                file = source / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("return {}\n")
            (source / "info.json").write_text(json.dumps({"name":"more-infinite-research",
                "version":"5.0.21000","factorio_version":"2.1","dependencies":["base >= 2.1.23"]}))
            for name in ("LICENSE", "thumbnail.png", "changelog.txt"):
                destination = source / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / "source" / name, destination)
            edition = root / pack.TARGET_RECORD
            edition.parent.mkdir(parents=True)
            original = (ROOT / pack.TARGET_RECORD).read_bytes()
            edition.write_bytes(original)
            git("add", ".")
            git("commit", "-qm", "frozen player and edition")
            commit = git("rev-parse", "HEAD").decode().strip()
            record = pack.build(source, root / "out/more-infinite-research_5.0.21000.zip",
                                revision=commit, target="f210")
            self.assertEqual(record["edition_record_sha256"], hashlib.sha256(original).hexdigest())
            self.assertEqual(record["source_commit"], commit)
            self.assertEqual(record["target"], "f210")
            self.assertEqual(record["target_record"], pack.TARGET_RECORD)
            with zipfile.ZipFile(record["archive"]) as archive:
                info = json.loads(archive.read("more-infinite-research_5.0.21000/info.json"))
                self.assertEqual(info["dependencies"], ["base >= 2.1.23"])
            edition.write_text('{"schema":1,"targets":{}}\n')
            git("add", edition.relative_to(root).as_posix())
            rejected = root / "dirty/more-infinite-research_5.0.21000.zip"
            with self.assertRaisesRegex(ValueError, "target record differs from the frozen revision"):
                pack.build(source, rejected, revision=commit, target="f210")
            self.assertFalse(rejected.exists())
            self.assertEqual(edition.read_text(), '{"schema":1,"targets":{}}\n')

    def test_staged_and_canonical_target_record_layouts_have_identical_selected_members(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            staged_repository = temporary / "staged"
            canonical_repository = temporary / "canonical"
            staged_repository.mkdir()
            canonical_repository.mkdir()
            staged_commit = self._write_layout_repository(
                staged_repository, Path("source/mir5"), Path("targets/mir5/editions.json"))
            canonical_commit = self._write_layout_repository(
                canonical_repository, Path("source"), Path("targets/editions.json"))
            editions = json.loads((ROOT / pack.TARGET_RECORD).read_bytes())["targets"]
            self.assertEqual(set(editions), {"f013", "f014", "f015", "f016", "f017", "f018", "f100", "f110", "f200", "f210"})
            for target_id, edition in editions.items():
                with self.subTest(target=target_id):
                    version = "5.0." + target_id[1:] + "00"
                    member_root = "more-infinite-research_" + version
                    filename = member_root + ".zip"
                    staged = pack.build(
                        staged_repository / "source/mir5", staged_repository / "out" / filename,
                        revision=staged_commit, target=target_id, target_record="targets/mir5/editions.json")
                    canonical = pack.build(
                        canonical_repository / "source", canonical_repository / "out" / filename,
                        revision=canonical_commit, target=target_id, target_record="targets/editions.json")
                    self.assertEqual(staged["target_record"], "targets/mir5/editions.json")
                    self.assertEqual(canonical["target_record"], "targets/editions.json")
                    self.assertEqual(staged["edition_record_sha256"], canonical["edition_record_sha256"])
                    self.assertEqual(staged["members"], canonical["members"])
                    self.assertEqual(staged["sha256"], canonical["sha256"])
                    self.assertEqual(staged["version"], version)
                    with zipfile.ZipFile(canonical["archive"]) as archive:
                        info = json.loads(archive.read(member_root + "/info.json"))
                        target = archive.read(member_root + "/platform/target.lua")
                        names = archive.namelist()
                    self.assertEqual(info["factorio_version"], edition["factorio_version"])
                    self.assertEqual(info["dependencies"][0], "base >= " + edition["minimum_base"])
                    self.assertIn(('id = "' + target_id + '"').encode(), target)
                    self.assertFalse(any("/tools/" in name or "/tests/" in name for name in names))

    def test_target_record_path_refuses_external_or_ambiguous_repository_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            commit = self._write_layout_repository(root, Path("source"), Path(pack.TARGET_RECORD))
            for value in (
                root.parent / "external-editions.json",
                "../targets/editions.json",
                "targets/../targets/editions.json",
                "source/editions.json",
                "targets//editions.json",
            ):
                with self.subTest(target_record=str(value)):
                    output = root / ("out-" + str(len(str(value)))) / "more-infinite-research_5.0.20000.zip"
                    with self.assertRaisesRegex(ValueError, "Target record"):
                        pack.build(source, output, revision=commit, target="f200", target_record=value)
                    self.assertFalse(output.exists())

    def test_every_edition_gets_the_complete_master_history_and_preserves_player_assets(self):
        source = ROOT / "source"
        recovered = json.loads((ROOT / "spec/inventory/package-presentation-472.json").read_bytes())
        self.assertEqual(recovered["sums_sha256"], "5DF0282024F4CA376CBA56E6E848F8512D768E1520D47E1C6AD257567BC561A9")
        self.assertEqual(len(recovered["records"]), 9)
        latest = json.loads((ROOT / "spec/inventory/package-presentation-473.json").read_bytes())
        self.assertEqual(latest["release_tag"], "v4.7.3")
        self.assertEqual(latest["published_source"], "8643cc91bc915e008556a5315dbb0a743247e7ab")
        self.assertEqual(latest["sums_sha256"], "D46F37750BAF0ED950E1F87EAC458726555171B10BE4562E0C90EFDB96D6CBFF")
        latest_records = {record["target"]: record for record in latest["records"]}
        self.assertEqual(len(latest["records"]), 9)
        self.assertEqual(set(latest_records), {record["target"] for record in recovered["records"]})
        entry = (source / "changelog.txt").read_bytes()
        self.assertLessEqual(max(map(len, entry.splitlines())), 132)
        masters = json.loads((ROOT / "spec/inventory/changelog-history.json").read_bytes())
        prior = {row["target"]: row for row in masters["prior_edition_histories"]}
        for record in recovered["records"]:
            with self.subTest(target=record["target"]):
                info, rows = pack.members(source, target=record["target"])
                files = dict(rows)
                current = latest_records[record["target"]]
                self.assertEqual(prior[record["target"]]["path"], current["source"])
                self.assertEqual(prior[record["target"]]["bytes"], current["bytes"])
                self.assertEqual(prior[record["target"]]["sha256"], current["history_sha256"])
                self.assertEqual(current["previous_history_bytes"], record["bytes"])
                self.assertEqual(current["previous_history_sha256"], record["history_sha256"])
                self.assertEqual(current["license_sha256"], record["license_sha256"])
                self.assertEqual(files["changelog.txt"], entry)
                self.assertTrue(files["changelog.txt"].startswith(
                    b"-" * 99 + b"\nVersion: 5.0.0\n"))
                self.assertEqual(files["changelog.txt"].count(b"Version: 1.0.0\n"), 1)
                self.assertNotIn(b"Version: 1.9.5\n", files["changelog.txt"])
                self.assertEqual(hashlib.sha256(files["LICENSE"]).hexdigest().upper(), record["license_sha256"])
                self.assertEqual(files["thumbnail.png"], (source / "thumbnail.png").read_bytes())
                self.assertFalse(any(name.startswith("presentation/changelog/") for name in files))

    def test_missing_shared_history_or_asset_is_not_a_partial_player_package(self):
        source = ROOT / "source"
        files = {path.relative_to(source).as_posix(): path.read_bytes()
                 for path in source.rglob("*") if path.is_file() and pack.admitted(path.relative_to(source).as_posix())}
        for required in ("LICENSE", "thumbnail.png", "changelog.txt"):
            with self.subTest(missing=required):
                broken = dict(files)
                del broken[required]
                with self.assertRaisesRegex(ValueError, "missing player presentation"):
                    pack.members(source, committed_files=broken, target="f200")

        for corrupt in (b"Version: 5.0.1\n", files["changelog.txt"] * 2):
            broken = dict(files, **{"changelog.txt": corrupt})
            with self.assertRaisesRegex(ValueError, "source-version header"):
                pack.members(source, committed_files=broken, target="f200")

    def test_committed_build_ignores_dirty_untracked_and_line_ending_worktree_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(["git", "-C", str(repository), *arguments])
            git("init", "-q")
            git("config", "user.name", "Package test")
            git("config", "user.email", "package-test@example.invalid")
            source = repository / "player"
            source.mkdir()
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (source / "data.lua").write_bytes(b"return 'committed'\n")
            git("add", ".")
            git("commit", "-qm", "fixture")
            commit = git("rev-parse", "HEAD").decode().strip()
            (source / "data.lua").write_bytes(b"error('dirty')\r\n")
            (source / "new.lua").write_text("error('untracked')")
            output = repository / "package/test-fixture_0.1.0.zip"
            record = pack.build(source, output, revision=commit)
            self.assertEqual(record["source_commit"], commit)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read("test-fixture_0.1.0/data.lua"), b"return 'committed'\n")
                self.assertNotIn("test-fixture_0.1.0/new.lua", archive.namelist())
            self.assertEqual((source / "data.lua").read_bytes(), b"error('dirty')\r\n")
            self.assertTrue((source / "new.lua").is_file())
            with self.assertRaises(ValueError):
                pack.build(repository, repository / "invalid/test-fixture_0.1.0.zip", revision=commit)

    def test_reproducible_members_and_fixture_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "source"
            source.mkdir()
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (source / "data.lua").write_text("data:extend({})\n")
            (source / "README.md").write_text("developer instructions")
            (source / "tests").mkdir()
            (source / "tests/leak.lua").write_text("error('developer-only')")
            first = directory / "one/test-fixture_0.2.0.zip"
            second = directory / "two/test-fixture_0.2.0.zip"
            a = pack.build(source, first, "0.2.0")
            b = pack.build(source, second, "0.2.0")
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(a["sha256"], b["sha256"])
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist(), ["test-fixture_0.2.0/data.lua", "test-fixture_0.2.0/info.json"])
                self.assertEqual(json.loads(archive.read("test-fixture_0.2.0/info.json"))["version"], "0.2.0")
            self.assertEqual(json.loads((source / "info.json").read_text())["version"], "0.1.0")
            with self.assertRaises(FileExistsError):
                pack.build(source, first, "0.2.0")

    def test_only_top_level_migration_json_is_admitted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            (source / "migrations" / "nested").mkdir(parents=True)
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (source / "data.lua").write_text("data:extend({})\n")
            (source / "migrations" / "more-infinite-research_4.7.0.json").write_bytes(b'{"technology": []}\n')
            (source / "migrations" / "nested" / "not-a-factorio-migration.json").write_text("{}\n")
            (source / "unrelated.json").write_text("{}\n")
            output = root / "package/test-fixture_0.1.0.zip"
            pack.build(source, output)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
            self.assertIn("test-fixture_0.1.0/migrations/more-infinite-research_4.7.0.json", names)
            self.assertNotIn("test-fixture_0.1.0/migrations/nested/not-a-factorio-migration.json", names)
            self.assertNotIn("test-fixture_0.1.0/unrelated.json", names)

    def test_archive_identity_mismatch_is_refused_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            source.mkdir()
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            output = Path(temporary) / "wrong.zip"
            with self.assertRaises(ValueError):
                pack.build(source, output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
