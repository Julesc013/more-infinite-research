"""Offline MIR 5 release-freeze identities; no tags, publication, or network."""
import copy
import importlib.util
import json
from pathlib import Path
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
    @staticmethod
    def _git(repository, *arguments):
        return subprocess.check_output(["git", "-C", str(repository), *arguments])

    @classmethod
    def _repository(cls, root):
        cls._git(root, "init", "-q")
        cls._git(root, "config", "user.name", "Release test")
        cls._git(root, "config", "user.email", "release-test@example.invalid")
        cls._git(root, "config", "core.autocrlf", "false")
        shutil.copytree(ROOT / "source", root / "source")
        record = root / release.package.TARGET_RECORD
        record.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / release.package.TARGET_RECORD, record)
        cls._git(root, "add", ".")
        cls._git(root, "commit", "-qm", "frozen player source")
        return root / "source", cls._git(root, "rev-parse", "HEAD").decode().strip()

    @staticmethod
    def _body(output):
        inventory = json.loads((output / release.INVENTORY_NAME).read_text(encoding="utf-8"))
        inventory.pop("inventory_sha256")
        return inventory

    @staticmethod
    def _write_body(output, body):
        (output / release.INVENTORY_NAME).write_bytes(release._inventory_bytes(body))

    def _assert_refused(self, source, output):
        with self.assertRaises(ValueError):
            release.verify(source, output)

    def test_freeze_builds_nine_canonical_archives_and_repeats_across_roots(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            first_repository = temporary / "first-repository"
            first_repository.mkdir()
            first_source, commit = self._repository(first_repository)
            first_output = temporary / "first-output"
            inventory = release.freeze(first_source, first_output, revision=commit)
            expected = {release._archive_name(target) for target in release.TARGETS}
            self.assertEqual({path.name for path in first_output.iterdir()},
                             expected | {release.SUMS_NAME, release.INVENTORY_NAME})
            self.assertEqual(inventory["kind"], release.KIND)
            self.assertEqual(inventory["release"], {
                "source_version": "5.0.0", "source_label": "source5.0.0",
                "tag": "v5.0.0", "title": "MIR 5.0.0"})
            self.assertEqual([asset["target"] for asset in inventory["assets"]], list(release.TARGETS))
            for asset in inventory["assets"]:
                with self.subTest(target=asset["target"]), zipfile.ZipFile(first_output / asset["name"]) as archive:
                    self.assertEqual(archive.namelist()[0], asset["root"] + "/" + asset["members"][0]["path"])
                    info = json.loads(archive.read(asset["root"] + "/info.json"))
                    self.assertEqual({key: info[key] for key in asset["info"]}, asset["info"])
                    self.assertEqual(info["dependencies"][0], "base >= " + asset["minimum_base"])
            self.assertEqual(release.verify(first_source, first_output), inventory)

            second_repository = temporary / "second-repository"
            subprocess.check_call(["git", "clone", "--no-hardlinks", "-q", str(first_repository), str(second_repository)])
            second_output = temporary / "second-output"
            second_source = second_repository / "source"
            release.freeze(second_source, second_output, revision=commit)
            self.assertEqual((first_output / release.INVENTORY_NAME).read_bytes(),
                             (second_output / release.INVENTORY_NAME).read_bytes())
            self.assertEqual(inventory["controller"], release._controller_identity())
            for name in expected | {release.SUMS_NAME}:
                self.assertEqual((first_output / name).read_bytes(), (second_output / name).read_bytes())

    def test_verification_rejects_missing_extra_changed_and_duplicate_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository)
            frozen = temporary / "frozen"
            release.freeze(source, frozen, revision=commit)
            with self.assertRaises(FileExistsError):
                release.freeze(source, frozen, revision=commit)

            cases = {
                "missing": lambda output: (output / release._archive_name("f013")).unlink(),
                "extra": lambda output: (output / "unexpected.txt").write_text("not an asset", encoding="utf-8"),
                "changed": lambda output: (output / release._archive_name("f013")).write_bytes(b"changed"),
                "duplicate": lambda output: self._duplicate_asset(output),
            }
            for name, mutate in cases.items():
                with self.subTest(name=name):
                    output = temporary / ("case-" + name)
                    shutil.copytree(frozen, output)
                    mutate(output)
                    self._assert_refused(source, output)

    def test_verification_rejects_release_source_target_and_controller_identity_mutations(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository)
            frozen = temporary / "frozen"
            release.freeze(source, frozen, revision=commit)

            def alter(path, value):
                def mutate(body):
                    cursor = body
                    for key in path[:-1]: cursor = cursor[key]
                    cursor[path[-1]] = value
                return mutate

            cases = {
                "release-title": alter(("release", "title"), "MIR 5.0.1"),
                "release-tag": alter(("release", "tag"), "v5.0.1"),
                "source-tree": alter(("source", "tree"), "0" * 40),
                "target-digest": alter(("target_record", "sha256"), "0" * 64),
                "controller-tool": alter(("controller", "package_tool", "sha256"), "0" * 64),
                "controller-runtime": alter(("controller", "runtime", "zlib_runtime_version"), "0.0.0"),
            }
            for name, mutate in cases.items():
                with self.subTest(name=name):
                    output = temporary / ("identity-" + name)
                    shutil.copytree(frozen, output)
                    body = self._body(output)
                    mutate(body)
                    self._write_body(output, body)
                    self._assert_refused(source, output)

            tampered = temporary / "inventory-tampered"
            shutil.copytree(frozen, tampered)
            path = tampered / release.INVENTORY_NAME
            path.write_bytes(path.read_bytes().replace(b'"schema":1', b'"schema":2', 1))
            self._assert_refused(source, tampered)

    def test_verification_rejects_archive_name_and_root_inventory_mutations(self):
        self._assert_asset_inventory_mutations({
            "asset-name": (("assets", 0, "name"), "wrong.zip"),
            "archive-root": (("assets", 0, "root"), "wrong-root"),
        })

    def test_verification_rejects_info_and_distribution_codec_inventory_mutations(self):
        self._assert_asset_inventory_mutations({
            "info-title": (("assets", 0, "info", "title"), "Wrong title"),
            "distribution-codec": (("assets", 0, "version"), "5.0.00000"),
        })

    def _assert_asset_inventory_mutations(self, cases):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository)
            frozen = temporary / "frozen"
            release.freeze(source, frozen, revision=commit)
            for name, (path, value) in cases.items():
                with self.subTest(name=name):
                    output = temporary / ("identity-" + name)
                    shutil.copytree(frozen, output)
                    body = self._body(output)
                    cursor = body
                    for key in path[:-1]:
                        cursor = cursor[key]
                    cursor[path[-1]] = value
                    self._write_body(output, body)
                    self._assert_refused(source, output)

    def test_verification_refuses_changed_archive_root_and_info_even_with_new_inventory_digests(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            repository = temporary / "repository"
            repository.mkdir()
            source, commit = self._repository(repository)
            frozen = temporary / "frozen"
            release.freeze(source, frozen, revision=commit)
            for name, transform in {
                "root": lambda member, data: (member.replace("more-infinite-research_5.0.01300", "wrong-root"), data),
                "info": self._wrong_info,
            }.items():
                with self.subTest(name=name):
                    output = temporary / ("archive-" + name)
                    shutil.copytree(frozen, output)
                    archive = output / release._archive_name("f013")
                    self._rewrite_archive(archive, transform)
                    body = self._body(output)
                    asset = body["assets"][0]
                    asset["archive_sha256"] = release.digest(archive.read_bytes())
                    asset["bytes"] = archive.stat().st_size
                    sums = release._sums(body["assets"])
                    (output / release.SUMS_NAME).write_bytes(sums)
                    body["checksums"] = {"name": release.SUMS_NAME, "sha256": release.digest(sums), "bytes": len(sums)}
                    self._write_body(output, body)
                    self._assert_refused(source, output)

    @staticmethod
    def _duplicate_asset(output):
        body = ReleaseTests._body(output)
        body["assets"].append(copy.deepcopy(body["assets"][0]))
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
