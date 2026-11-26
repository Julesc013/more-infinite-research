"""Readback controls with pinned public bytes and a disposable primary checkout."""

from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import release
import verify_public_release as readback


class Response(BytesIO):
    status = 200


class PublicReleaseTests(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        self.primary, self.frozen = root / "primary", root / "freeze"
        self.primary.mkdir()
        self.frozen.mkdir()
        self.commit, self.tree, self.head = "1" * 40, "2" * 40, "3" * 40
        self.remote_head = self.head
        self.status = b""
        self.direct_tag = {"type": "commit", "sha": self.commit}
        self.tag_object = self.direct_tag
        self.version = "5.0.21023"
        self.tag, self.title = "v5.0.23", "MIR 5.0.23"
        self.body = b"Preserve parked research.\n"
        self.notes = b'---\ntitle: "MIR 5.0.23 release notes"\n---\n\n' + self.body
        self.upload = b"MIR 5.0.23\nChannel: GitHub.\n\n" + self.body
        self.assets = {
            "more-infinite-research_5.0.21023.zip": b"core",
            "SHA256SUMS.txt": b"core sums",
            "more-infinite-research_5.0.01023.zip": b"early",
            "SHA256SUMS-early.txt": b"early sums",
        }
        self.downloads = dict(self.assets)
        self.public = {
            "id": 34, "tag_name": self.tag, "name": self.title, "draft": False,
            "prerelease": True, "immutable": False, "published_at": "2026-11-23T00:00:00Z",
            "body": self.body.decode(), "assets": [], "html_url": f"https://github.com/{readback.REPOSITORY}/releases/tag/{self.tag}",
        }
        rows = {}
        for index, (name, data) in enumerate(self.assets.items()):
            row = {"name": name, "bytes": len(data)}
            hash_key = "archive_sha256" if name.endswith(".zip") else "sha256"
            row[hash_key] = release.digest(data)
            if hash_key == "archive_sha256":
                row["label"] = name
            public = {**row, "id": index + 40, "size": len(data), "state": "uploaded",
                      "browser_download_url": f"https://github.com/{readback.REPOSITORY}/releases/download/{self.tag}/{name}"}
            self.public["assets"].append(public)
            rows[name] = row
        body = {
            "kind": release.KIND, "schema": 1, "release": release._release_identity(self.version),
            "source": {"tree": self.tree, "source_distribution_version": self.version},
            "assets": [rows[next(iter(self.assets))]], "checksums": rows["SHA256SUMS.txt"],
            "early_cohort": {"assets": [rows["more-infinite-research_5.0.01023.zip"]],
                             "checksums": rows["SHA256SUMS-early.txt"]},
        }
        raw = release._inventory_bytes(body)
        self.inventory_sha256 = sha256(raw).hexdigest()
        (self.frozen / release.INVENTORY_NAME).write_bytes(raw)
        self.requests = []
        self.run_number = 0
        self.destination = self.primary / "dist" / self.tag

    def fake_git(self, primary, *args):
        self.assertEqual(primary, self.primary)
        return {
            ("rev-parse", self.commit + "^{tree}"): self.tree.encode(),
            ("show", f"{self.commit}:docs/release-notes.md"): self.notes,
            ("show", f"{self.commit}:docs/upload-text.txt"): self.upload,
            ("rev-parse", "--show-toplevel"): str(self.primary).encode(),
            ("remote", "get-url", "origin"): f"git@github.com:{readback.REPOSITORY}.git".encode(),
            ("branch", "--show-current"): b"dev", ("rev-parse", "HEAD"): self.head.encode(),
            ("ls-remote", "--heads", "origin", "refs/heads/dev"): f"{self.remote_head}\trefs/heads/dev".encode(),
            ("status", "--porcelain=v1", "--untracked-files=normal"): self.status,
        }[args]

    def fake_http(self, request, timeout):
        self.assertIsNone(request.get_header("Authorization"))
        url = request.full_url
        self.requests.append(url)
        if url.startswith(readback.API):
            endpoint = url.removeprefix(readback.API)
            metadata = {
                f"git/ref/tags/{self.tag}": {"object": self.tag_object},
                "git/tags/" + "4" * 40: {"object": self.direct_tag},
                "releases/34": self.public,
            }
            return Response(json.dumps(metadata[endpoint]).encode())
        return Response(self.downloads[url.rsplit("/", 1)[1]])

    def verify(self, prerelease=True):
        self.run_number += 1
        receipt = self.frozen / f"receipt-{self.run_number}"
        with patch.object(readback, "_git", self.fake_git), patch.object(readback, "urlopen", self.fake_http):
            return readback.verify_delivery(self.primary, self.frozen, self.inventory_sha256, self.commit,
                                            34, prerelease, receipt)

    def assert_no_asset_downloads(self):
        self.assertTrue(all(url.startswith(readback.API) for url in self.requests))
        self.assertFalse(self.destination.exists())

    def test_both_maturities_deliver_all_assets_notes_and_verified_idempotent_readback(self):
        self.public["prerelease"] = False
        self.tag_object = {"type": "tag", "sha": "4" * 40}
        stable = self.verify(prerelease=False)
        self.assertFalse(stable["prerelease"])
        self.public["prerelease"] = True
        self.tag_object = self.direct_tag
        beta = self.verify()
        self.assertTrue(beta["prerelease"])
        self.assertEqual(stable["local_file_sha256"], beta["local_file_sha256"])
        self.assertEqual({path.name: path.read_bytes() for path in self.destination.iterdir()},
                         {**self.assets, "release-notes.md": self.body, "upload-text.txt": self.upload})
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_transient_failures_during_asset_download_retry_anonymously(self):
        url = self.public["assets"][0]["browser_download_url"]
        faults = [HTTPError(url, 503, "temporary", None, None), ConnectionResetError()]
        fake_http = self.fake_http
        attempts = []

        def flaky_http(request, timeout):
            if request.full_url == url:
                self.assertIsNone(request.get_header("Authorization"))
                attempts.append(request)
                if faults:
                    raise faults.pop(0)
            return fake_http(request, timeout)

        with patch.object(self, "fake_http", flaky_http), patch("time.sleep") as delay:
            result = self.verify()
        self.assertEqual(len(attempts), 3)
        self.assertEqual(len({id(request) for request in attempts}), 3)
        self.assertEqual([call.args for call in delay.call_args_list], [(5,), (10,)])
        self.assertEqual({row["name"] for row in result["verified_assets"]}, set(self.assets))
        self.assertFalse(result["authorization_header_sent"])

    def test_read_stops_on_permanent_http_error_and_exhausted_retries(self):
        url = readback.API + "releases/34"
        for status, attempts, delays in ((403, 1, []), (503, 3, [(5,), (10,)])):
            with self.subTest(status=status):
                failure = HTTPError(url, status, "injected failure", None, None)
                with patch.object(readback, "urlopen", side_effect=failure) as fetch, patch("time.sleep") as delay:
                    with self.assertRaises(HTTPError) as raised:
                        readback._read(url, 128, "application/vnd.github+json")
                self.assertEqual(raised.exception.code, status)
                self.assertEqual(fetch.call_count, attempts)
                self.assertEqual([call.args for call in delay.call_args_list], delays)

    def test_stale_github_body_or_tagged_note_version_stops_before_downloads(self):
        self.public["body"] = "Old release."
        with self.assertRaisesRegex(ValueError, "body differs"):
            self.verify()
        self.public["body"] = self.body.decode()
        self.notes = self.notes.replace(b"MIR 5.0.23", b"MIR 5.0.22")
        with self.assertRaisesRegex(ValueError, "metadata names a different release"):
            self.verify()
        self.assert_no_asset_downloads()

    def test_wrong_tag_or_maturity_stops_before_downloads(self):
        self.tag_object = {"type": "commit", "sha": "0" * 40}
        with self.assertRaisesRegex(ValueError, "tag does not point"):
            self.verify()
        self.tag_object = self.direct_tag
        with self.assertRaisesRegex(ValueError, "maturity"):
            self.verify(prerelease=False)
        self.assert_no_asset_downloads()

    def test_same_length_wrong_download_cannot_replace_prior_verified_delivery(self):
        self.verify()
        name = next(iter(self.assets))
        self.downloads[name] = b"WRNG"
        with self.assertRaisesRegex(ValueError, "download bytes"):
            self.verify()
        self.assertEqual((self.destination / name).read_bytes(), self.assets[name])

    def test_existing_delivery_with_legacy_note_names_is_verified_in_place(self):
        self.destination.mkdir(parents=True)
        delivered = {**self.assets, "RELEASE_NOTES.md": self.body, "UPLOAD.txt": self.upload}
        for name, data in delivered.items():
            (self.destination / name).write_bytes(data)

        result = self.verify()

        self.assertEqual(result["local_file_sha256"], {name: release.digest(data) for name, data in delivered.items()})
        self.assertEqual({path.name: path.read_bytes() for path in self.destination.iterdir()}, delivered)
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_duplicate_note_names_preserve_existing_files_and_verified_staging(self):
        self.verify()
        (self.destination / "UPLOAD.txt").write_bytes(self.upload)
        (self.destination / "RELEASE_NOTES.md").write_bytes(self.body)
        with self.assertRaisesRegex(ValueError, "Existing delivery differs"):
            self.verify()
        self.assertEqual((self.destination / "UPLOAD.txt").read_bytes(), self.upload)
        self.assertEqual((self.destination / "upload-text.txt").read_bytes(), self.upload)
        stage, = self.destination.parent.glob(f".{self.tag}-readback-*")
        self.assertEqual((stage / "release-notes.md").read_bytes(), self.body)

    def test_conflicting_existing_notes_preserve_both_copies(self):
        self.verify()
        (self.destination / "release-notes.md").write_bytes(b"old")
        with self.assertRaisesRegex(ValueError, "Existing delivery differs"):
            self.verify()
        self.assertEqual((self.destination / "release-notes.md").read_bytes(), b"old")
        stage, = self.destination.parent.glob(f".{self.tag}-readback-*")
        self.assertEqual((stage / "release-notes.md").read_bytes(), self.body)

    def test_remote_drift_preserves_staging_without_delivering(self):
        self.remote_head = "0" * 40
        with self.assertRaisesRegex(ValueError, "equal to its remote branch"):
            self.verify()
        self.assertFalse(self.destination.exists())
        stage, = self.destination.parent.glob(f".{self.tag}-readback-*")
        self.assertEqual((stage / "upload-text.txt").read_bytes(), self.upload)

        self.remote_head = self.head
        self.status = b"?? unfinished.txt"
        with self.assertRaisesRegex(ValueError, "checkout must be clean"):
            self.verify()
        self.assertFalse(self.destination.exists())

    def test_frozen_inventory_digest_is_an_independent_input(self):
        self.inventory_sha256 = "0" * 64
        with self.assertRaisesRegex(ValueError, "inventory digest differs"):
            self.verify()
        self.assertFalse(self.requests)


if __name__ == "__main__":
    unittest.main(verbosity=2)
