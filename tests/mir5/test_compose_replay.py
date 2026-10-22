"""Synthetic controls for private, offline MIR 4.7 replay composition.

These ZIPs model custody inputs.  They neither load a mod nor establish native
execution, package acceptance, or release evidence.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
COMPOSER_PATH = ROOT / "tools/mir5/compose_replay.py"
SPEC = importlib.util.spec_from_file_location("mir5_compose_replay", COMPOSER_PATH)
assert SPEC and SPEC.loader
composer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(composer)


class ComposeReplayTests(unittest.TestCase):
    def _sha(self, content: bytes) -> str:
        return hashlib.sha256(content).hexdigest().upper()

    def _write_json(self, path: Path, value: dict) -> bytes:
        content = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
        path.write_bytes(content)
        return content

    def _write_replay(self, root: Path, published_archive_sha256: str = "0" * 64) -> dict[str, bytes]:
        root.mkdir()
        stages = {name: ("-- synthetic replay " + name + "\n").encode("utf-8")
                  for name in composer.STAGE_ENTRYPOINTS}
        records = [
            {"path": name, "sha256": self._sha(content), "bytes": len(content)}
            for name, content in sorted(stages.items())
        ]
        for name, content in stages.items():
            (root / name).write_bytes(content)
        receipt = {
            "schema": 1,
            "kind": "MIR5OfflineDiagnosticReplayV1",
            "status": "generated-offline-diagnostic-not-native-evidence",
            "claims": {
                "native_qualification": False,
                "player_package": False,
                "replay_execution": False,
            },
            "published_mir": {
                "name": composer.MOD_NAME,
                "version": composer.MOD_VERSION,
                "sha256": published_archive_sha256,
            },
            "outputs": records,
        }
        receipt_bytes = self._write_json(root / composer.REPLAY_RECEIPT, receipt)
        inventory = {
            "schema": 1,
            "kind": "MIR5OfflineDiagnosticReplayHashInventoryV1",
            "outputs": records + [{
                "path": composer.REPLAY_RECEIPT,
                "sha256": self._sha(receipt_bytes),
                "bytes": len(receipt_bytes),
            }],
        }
        self._write_json(root / composer.REPLAY_INVENTORY, inventory)
        return stages

    def _write_archive(self, path: Path, *, root: str | None = None,
                       extra_members: list[tuple[str, bytes]] | None = None,
                       omit_stages: tuple[str, ...] = ()) -> dict[str, bytes]:
        archive_root = composer.ARCHIVE_ROOT if root is None else root
        original_stages = {name: ("-- published " + name + "\n").encode("utf-8")
                           for name in composer.STAGE_ENTRYPOINTS}
        members = {
            f"{archive_root}/info.json": json.dumps({
                "name": composer.MOD_NAME,
                "version": composer.MOD_VERSION,
                "factorio_version": "2.1",
            }, sort_keys=True).encode("utf-8"),
            f"{archive_root}/control.lua": b"return require('published-control')\n",
            f"{archive_root}/graphics/icons/published.png": b"\x89PNG\r\nsynthetic-asset",
            f"{archive_root}/migrations/4.7.0.lua": b"return {published = true}\n",
        }
        members.update({f"{archive_root}/{name}": content for name, content in original_stages.items()
                        if name not in omit_stages})
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, content in members.items():
                archive.writestr(name, content)
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                for name, content in extra_members or []:
                    archive.writestr(name, content)
        return members

    def _compose(self, root: Path) -> tuple[Path, Path, Path, dict[str, bytes]]:
        archive = root / composer.PUBLISHED_ARCHIVE_NAME
        original = self._write_archive(archive)
        replay_root = root / "replay"
        self._write_replay(replay_root, self._sha(archive.read_bytes()))
        return archive, replay_root, root / "private-output", original

    def test_streams_published_members_and_replaces_only_verified_stage_entrypoints(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, replay_root, output, original = self._compose(root)
            receipt = composer.compose_replay(archive, self._sha(archive.read_bytes()), replay_root, output)
            output_archive = output / composer.PUBLISHED_ARCHIVE_NAME
            self.assertTrue(output_archive.is_file())
            self.assertTrue((output / composer.COMPOSITION_RECEIPT).is_file())
            self.assertEqual(receipt["status"], "composed-offline-diagnostic-nonrelease-not-native-execution")
            self.assertEqual(receipt["claims"], {
                "diagnostic": True, "release": False, "native_execution": False, "player_package": False,
            })
            self.assertEqual({row["path"] for row in receipt["changed_members"]}, {
                f"{composer.ARCHIVE_ROOT}/{name}" for name in composer.STAGE_ENTRYPOINTS
            })
            self.assertEqual({row["change"] for row in receipt["changed_members"]}, {"replaced"})
            self.assertEqual(len(receipt["unchanged_members"]), len(original) - len(composer.STAGE_ENTRYPOINTS))

            with zipfile.ZipFile(archive) as source, zipfile.ZipFile(output_archive) as composed:
                self.assertEqual(source.namelist(), composed.namelist())
                for name in source.namelist():
                    relative = name[len(composer.ARCHIVE_ROOT) + 1:]
                    if relative in composer.STAGE_ENTRYPOINTS:
                        self.assertEqual(composed.read(name), (replay_root / relative).read_bytes())
                    else:
                        self.assertEqual(composed.read(name), source.read(name), name)
                self.assertEqual(
                    composed.read(f"{composer.ARCHIVE_ROOT}/info.json"),
                    source.read(f"{composer.ARCHIVE_ROOT}/info.json"),
                )
                self.assertEqual(json.loads(composed.read(f"{composer.ARCHIVE_ROOT}/info.json")), {
                    "factorio_version": "2.1", "name": composer.MOD_NAME, "version": composer.MOD_VERSION,
                })

            recorded = json.loads((output / composer.COMPOSITION_RECEIPT).read_text(encoding="utf-8"))
            self.assertEqual(recorded, receipt)
            self.assertNotIn(composer.COMPOSITION_RECEIPT, zipfile.ZipFile(output_archive).namelist())

    def test_adds_verified_stage_entrypoints_absent_from_the_published_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / composer.PUBLISHED_ARCHIVE_NAME
            self._write_archive(archive, omit_stages=("settings-updates.lua", "settings-final-fixes.lua"))
            replay_root = root / "replay"
            self._write_replay(replay_root, self._sha(archive.read_bytes()))
            output = root / "private-output"
            receipt = composer.compose_replay(archive, self._sha(archive.read_bytes()), replay_root, output)
            added = {row["path"] for row in receipt["changed_members"] if row["change"] == "added"}
            self.assertEqual(added, {
                f"{composer.ARCHIVE_ROOT}/settings-updates.lua",
                f"{composer.ARCHIVE_ROOT}/settings-final-fixes.lua",
            })
            with zipfile.ZipFile(output / composer.PUBLISHED_ARCHIVE_NAME) as composed:
                for name in added:
                    self.assertEqual(composed.read(name), (replay_root / Path(name).name).read_bytes())

    def test_rejects_tampered_generated_stage_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, replay_root, output, _ = self._compose(root)
            (replay_root / "data.lua").write_bytes(b"-- tampered\n")
            with self.assertRaisesRegex(composer.ComposeReplayError, "differs from its recorded hash inventory"):
                composer.compose_replay(archive, self._sha(archive.read_bytes()), replay_root, output)
            self.assertFalse(output.exists())

    def test_rejects_unsafe_duplicate_and_root_mismatched_archive_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            replay_root = root / "replay"
            self._write_replay(replay_root)
            cases = [
                ("unsafe", composer.ARCHIVE_ROOT, [(f"{composer.ARCHIVE_ROOT}/../escape.lua", b"bad")], "unsafe member name"),
                ("duplicate", composer.ARCHIVE_ROOT, [(f"{composer.ARCHIVE_ROOT}/control.lua", b"duplicate")], "duplicates member"),
                ("root", "other-root", [], "root does not match"),
            ]
            for label, archive_root, extra_members, message in cases:
                with self.subTest(label=label):
                    # Keep the external filename canonical while varying only ZIP members.
                    archive = root / composer.PUBLISHED_ARCHIVE_NAME
                    if archive.exists():
                        archive.unlink()
                    self._write_archive(archive, root=archive_root, extra_members=extra_members)
                    output = root / f"output-{label}"
                    with self.assertRaisesRegex(composer.ComposeReplayError, message):
                        composer.compose_replay(archive, self._sha(archive.read_bytes()), replay_root, output)
                    self.assertFalse(output.exists())

    def test_rejects_missing_expected_hash_preexisting_or_dist_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, replay_root, output, _ = self._compose(root)
            with self.assertRaisesRegex(composer.ComposeReplayError, "expected published archive SHA-256"):
                composer.compose_replay(archive, "", replay_root, output)
            self.assertFalse(output.exists())

            output.mkdir()
            with self.assertRaisesRegex(composer.ComposeReplayError, "must be fresh"):
                composer.compose_replay(archive, self._sha(archive.read_bytes()), replay_root, output)

            dist_output = ROOT / "dist" / "mir5-compose-replay-test-output"
            self.assertFalse(dist_output.exists())
            with self.assertRaisesRegex(composer.ComposeReplayError, "never be inside dist"):
                composer.compose_replay(archive, self._sha(archive.read_bytes()), replay_root, dist_output)
            self.assertFalse(dist_output.exists())

    def test_rejects_same_identity_archive_when_replay_captured_a_different_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_dir = root / "supplied"
            captured_dir = root / "captured"
            source_dir.mkdir()
            captured_dir.mkdir()
            supplied = source_dir / composer.PUBLISHED_ARCHIVE_NAME
            captured = captured_dir / composer.PUBLISHED_ARCHIVE_NAME
            self._write_archive(supplied)
            self._write_archive(captured, extra_members=[(
                f"{composer.ARCHIVE_ROOT}/custody-marker.txt", b"different published bytes",
            )])
            replay_root = root / "replay"
            self._write_replay(replay_root, self._sha(captured.read_bytes()))
            output = root / "private-output"

            with self.assertRaisesRegex(
                    composer.ComposeReplayError,
                    "does not match the replay's published native-capture archive"):
                composer.compose_replay(supplied, self._sha(supplied.read_bytes()), replay_root, output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
