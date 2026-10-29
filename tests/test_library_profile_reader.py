"""Controls for the bounded offline native Library profiler reader."""
from __future__ import annotations

import copy
import hashlib
import base64
import gzip
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import read_library_profiles as reader


# These are safe, marker-only excerpts from the accepted 40129169284 adverse
# session.  The source full logs are intentionally not retained here: session
# output can contain RCON-facing process diagnostics.  The exact raw-log
# identities make the retained excerpts reviewable without importing those logs
# into source custody.
ACTUAL_401291 = {
    "server": {
        "path": "library-multiplayer-canonical/native/session/server/factorio-current.log",
        "sha256": "66F568E05B36BE639517558BCD7B1FF2C27163FA752D2EC83DDF045F1F9F515A",
        "lines": (
            " 105.591 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] first_open Duration: 2.596300ms",
            " 105.594 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] search Duration: 2.526500ms",
            " 105.596 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] refresh Duration: 2.493000ms",
        ),
    },
    "en": {
        "path": "library-multiplayer-canonical/native/session/client-en/factorio-current.log",
        "sha256": "B34A171F295BEEA28157A57870B93C808F621EC0FB769B7A4AE3D98ABA8B019B",
        "lines": (
            " 103.889 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] first_open Duration: 3.274300ms",
            " 103.892 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] search Duration: 2.527300ms",
            " 103.895 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] refresh Duration: 3.489500ms",
        ),
    },
    "de": {
        "path": "library-multiplayer-canonical/native/session/client-de/factorio-current.log",
        "sha256": "F08C3D71E48D0600117B1B51737B3C173ED4CB6902F7A6B526E75CCCB7D66D48",
        "lines": (
            "  19.737 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] first_open Dauer: 2.725700\u202fms",
            "  19.741 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] search Dauer: 3.466800\u202fms",
            "  19.743 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:340: "
            "[MIR5_LIBRARY_PROFILE] refresh Dauer: 2.128900\u202fms",
        ),
    },
}


# These are marker-only excerpts from the complete 40133428618 phase logs.
# The full native process logs remain in external custody because they contain
# unrelated process output; the source paths and hashes retain their identity.
ACTUAL_401334 = {
    "server": (
        ("initial", "library-multiplayer-canonical/native/session/phase-server-initial.stdout.log",
         "A360C9E6BEFF02D0246B707B166202E2F8E80101684F4B26D135A8F1E66CFE63", (
             "  68.327 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] first_open Duration: 2.456200ms",
             "  68.329 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] search Duration: 2.263100ms",
             "  68.331 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] refresh Duration: 2.302600ms",
             "  92.045 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] reopen Duration: 4.471200ms",
         )),
    ),
    "en": (
        ("initial", "library-multiplayer-canonical/native/session/phase-client-initial-en.stdout.log",
         "B46B84F95FE2832D0F3282EA651B103FC99838CEAE5E70C107256B3B533C2210", (
             "  66.146 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] first_open Duration: 3.022700ms",
             "  66.148 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] search Duration: 2.514100ms",
             "  66.151 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] refresh Duration: 2.802500ms",
         )),
        ("rejoin", "library-multiplayer-canonical/native/session/phase-client-rejoin-en.stdout.log",
         "D549C8CAE9EF42C5CFC2E92737141A830799494485C5E1678014D14111FFDA9A", (
             "  20.539 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] reopen Duration: 6.716600ms",
         )),
    ),
    "de": (
        ("initial", "library-multiplayer-canonical/native/session/phase-client-initial-de.stdout.log",
         "11C72B1B68CC34C500D7FEAA902CDAB9E44E238C9D37290497B0D181A6B8468D", (
             "  16.223 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] first_open Dauer: 2.674000\u202fms",
             "  16.226 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] search Dauer: 3.749400\u202fms",
             "  16.229 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] refresh Dauer: 2.147800\u202fms",
         )),
        ("rejoin", "library-multiplayer-canonical/native/session/phase-client-rejoin-de.stdout.log",
         "A33E9261CF339C9D67BA0B35592B35FE1DDD020AC3DA7326A65C1B469F2E71E1", (
             "  11.202 Script @__mir-fixture-mir5-library-multiplayer__/control.lua:398: "
             "[MIR5_LIBRARY_PROFILE] reopen Dauer: 4.683700\u202fms",
         )),
    ),
}


def marker(action: str, milliseconds: str, *, role: str = "en") -> str:
    if role == "de":
        return f" [MIR5_LIBRARY_PROFILE] {action} Dauer: {milliseconds}\u202fms"
    return f" [MIR5_LIBRARY_PROFILE] {action} Duration: {milliseconds}ms"


class LibraryProfileReaderTests(unittest.TestCase):
    def test_actual_six_session_diagnostic_keeps_failed_memory_controls_unaccepted(self):
        import re
        payload = (ROOT / 'spec/evidence/library-repeatability-diagnostic-r02-native-receipts.json.gz').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest().upper(), '950162E6EE13800737EA883D87A7C517A5124BDB39DB435E8BEED71A120BD21B')
        files = {}
        for row in json.loads(gzip.decompress(payload))['files']:
            raw = base64.b64decode(row['base64'], validate=True)
            self.assertEqual(len(raw), row['bytes'])
            self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), row['sha256'])
            self.assertNotIn(row['path'], files)
            files[row['path']] = raw
        self.assertEqual(len(files), 86)
        analysis = json.loads(files['controller/analysis.json'])
        self.assertEqual(analysis['status'], 'diagnostic-observed-not-acceptance')
        self.assertFalse(analysis['performance_acceptance'])
        self.assertFalse(analysis['release_qualification'])
        actual_metrics = []
        with tempfile.TemporaryDirectory() as directory:
            for observation in analysis['observations']:
                metrics, logs = {}, []
                root = Path(directory) / observation['id']
                root.mkdir()
                for role, actor, suffix in [('server', 'server', ''), ('en', 'client', '-en'), ('de', 'client', '-de')]:
                    for phase in ('initial', 'restart'):
                        name = f'phase-{actor}-{phase}{suffix}.stdout.log'
                        path = root / name
                        path.write_bytes(files[f"native/{observation['id']}/{name}"])
                        logs.append(reader.LogInput(role, phase, path, name))
                profiles = reader._read_profiles(logs)
                self.assertTrue(profiles['complete'])
                self.assertFalse(profiles['performance_acceptance'])
                for role in profiles['roles']:
                    for value in role['observations']:
                        metrics['library/' + role['role'] + '/' + value['action']] = value['duration_ms']
                for phase in ('initial', 'restart'):
                    text = files[f"native/{observation['id']}/phase-server-{phase}.stdout.log"].decode('utf-8-sig')
                    ready = [(line, json.loads(line.split('[MIR5_LIBRARY_PAIRED_BROWSER] ', 1)[1]))
                             for line in text.splitlines() if '[MIR5_LIBRARY_PAIRED_BROWSER] ' in line]
                    ready = [(line, row) for line, row in ready if row['stage'] == 'ready']
                    self.assertEqual(len(ready), 1)
                    self.assertIsNotNone(re.match(r'^\s*[0-9]+\.[0-9]+\s', ready[0][0]))
                    metrics['save_ready/' + phase] = float(ready[0][0].split()[0])
                memory = json.loads(files[f"native/{observation['id']}/process-memory-observations.json"])
                self.assertEqual(memory['status'], 'complete-observation')
                self.assertFalse(memory['incomplete_reasons'])
                for phase in ('initial', 'restart'):
                    for role in ('server', 'client-en', 'client-de'):
                        rows = [r for r in memory['observations'] if r['phase'] == phase and r['role'] == role]
                        self.assertGreaterEqual(len(rows), 2)
                        for key in ('working_set_bytes', 'private_bytes'):
                            metrics[f'memory/{phase}/{role}/{key}'] = max(r[key] for r in rows)
                self.assertEqual(len(metrics), 26)
                self.assertEqual(metrics, observation['metrics'])
                actual_metrics.append(metrics)
        self.assertEqual(len(actual_metrics), 6)
        failures = {}
        for pair, left, right in [('1', actual_metrics[1], actual_metrics[2]), ('2', actual_metrics[3], actual_metrics[4])]:
            failed = []
            for key in sorted(left):
                floor = 5 if key.startswith('library/') else .25 if key.startswith('save_ready/') else 67108864
                limit = max(.1 * ((left[key] + right[key]) / 2), floor)
                within = abs(left[key] - right[key]) <= limit
                self.assertEqual(within, analysis['pairs'][pair][key]['within'])
                if not within:
                    failed.append(key)
            failures[pair] = failed
        self.assertEqual(failures, {
            '1': ['memory/restart/client-en/working_set_bytes', 'memory/restart/server/private_bytes', 'memory/restart/server/working_set_bytes'],
            '2': ['memory/initial/client-en/working_set_bytes', 'memory/restart/client-de/working_set_bytes'],
        })

    def test_actual_current_r01_roles_replay_without_promoting_failed_measurements(self):
        payload = (ROOT / 'spec/evidence/library-current-e9-r01-native-receipts.json.gz').read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest().upper(), '526F8B41EBD2208978EEA4E41598F800B6D18D91EF065520D2EE79A4B287B3AA')
        files = {}
        for row in json.loads(gzip.decompress(payload))['files']:
            raw = base64.b64decode(row['base64'], validate=True)
            self.assertEqual(len(raw), row['bytes'])
            self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), row['sha256'])
            self.assertNotIn(row['path'], files)
            files[row['path']] = raw
        self.assertEqual(len(files), 103)
        analysis = json.loads(files['derived/analysis-r04.json'])
        self.assertEqual(analysis['status'], 'incomplete-predeclared-measurement')
        self.assertEqual(analysis['missing_endpoints'], ['save_ready/restart'])
        self.assertEqual({key for key, value in analysis['controls'].items() if not value['within']}, {
            'library/server/refresh', 'library/server/reopen',
            'memory/initial/client-en/working_set_bytes', 'memory/initial/client-de/working_set_bytes',
        })
        self.assertFalse(analysis['release_qualification'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for observation in analysis['observations']:
                logs = []
                for role, actor, suffix in [('server', 'server', ''), ('en', 'client', '-en'), ('de', 'client', '-de')]:
                    for phase in ('initial', 'restart'):
                        name = f'phase-{actor}-{phase}{suffix}.stdout.log'
                        path = root / observation['id'] / name
                        path.parent.mkdir(exist_ok=True)
                        path.write_bytes(files[f"original/{observation['id']}/{name}"])
                        logs.append(reader.LogInput(role, phase, path, name))
                actual = reader._read_profiles(logs)
                self.assertTrue(actual['complete'])
                self.assertFalse(actual['performance_acceptance'])
                for role in actual['roles']:
                    for metric in role['observations']:
                        key = 'library/' + role['role'] + '/' + metric['action']
                        self.assertEqual(metric['duration_ms'], observation['metrics'][key])

    def write_logs(self, root: Path, rows: dict[str, tuple[str, ...]]) -> list[tuple[str, Path]]:
        result = []
        for role in reader.ROLES:
            path = root / f"{role}.log"
            path.write_text("\n".join(rows[role]) + "\n", encoding="utf-8")
            result.append((role, path))
        return result

    def complete_rows(self) -> dict[str, tuple[str, ...]]:
        return {
            role: tuple(marker(action, f"{index + 1}.{index}000", role=role)
                        for index, action in enumerate(reader.ACTIONS))
            for role in reader.ROLES
        }

    def write_manifest(self, root: Path, roles: dict[str, list[dict[str, str]]]) -> Path:
        path = root / "library-profile-manifest.json"
        path.write_text(json.dumps({
            "schema": 1,
            "kind": reader.MANIFEST_KIND,
            "roles": roles,
        }), encoding="utf-8")
        return path

    def write_actual_401334_manifest_excerpts(self, root: Path) -> Path:
        roles: dict[str, list[dict[str, str]]] = {role: [] for role in reader.ROLES}
        for role, entries in ACTUAL_401334.items():
            for process, source_path, _source_hash, lines in entries:
                path = root / source_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("\n".join(lines) + "\n", encoding="utf-8")
                roles[role].append({"process": process, "path": source_path})
        return self.write_manifest(root, roles)

    def test_accepts_complete_role_labelled_observations_without_a_performance_verdict(self):
        with tempfile.TemporaryDirectory() as temporary:
            logs = self.write_logs(Path(temporary), self.complete_rows())
            result = reader.read_profiles(logs)
        self.assertEqual(result["kind"], reader.KIND)
        self.assertEqual(result["status"], "complete-observation")
        self.assertTrue(result["complete"])
        self.assertEqual(result["timing_verdict"], "none")
        self.assertFalse(result["performance_acceptance"])
        self.assertEqual([row["role"] for row in result["roles"]], list(reader.ROLES))
        for row in result["roles"]:
            self.assertEqual([entry["action"] for entry in row["observations"]], list(reader.ACTIONS))
            self.assertEqual(row["missing_actions"], [])
            self.assertEqual(len(row["log_sha256"]), 64)
            self.assertEqual([entry["process"] for entry in row["observations"]], ["direct"] * 4)
            self.assertTrue(all("[MIR5_LIBRARY_PROFILE]" in entry["raw_line"]
                                for entry in row["observations"]))

    def test_actual_marker_only_401291_excerpts_are_partial_and_preserve_raw_lines_with_provenance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            logs = self.write_logs(root, {role: value["lines"] for role, value in ACTUAL_401291.items()})
            result = reader.read_profiles(logs)
        self.assertEqual(result["status"], "incomplete-observation")
        self.assertFalse(result["complete"])
        self.assertEqual(result["timing_verdict"], "none")
        self.assertFalse(result["performance_acceptance"])
        for row in result["roles"]:
            source = ACTUAL_401291[row["role"]]
            self.assertEqual(len(source["sha256"]), 64)
            self.assertEqual([entry["raw_line"] for entry in row["observations"]], list(source["lines"]))
            self.assertEqual([entry["action"] for entry in row["observations"]], list(reader.ACTIONS[:3]))
            self.assertEqual(row["missing_actions"], ["reopen"])
            self.assertNotEqual(row["log_sha256"], source["sha256"])
            self.assertTrue(source["path"].endswith("factorio-current.log"))

    def test_actual_401334_phase_manifest_preserves_source_process_provenance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = reader.read_manifest(self.write_actual_401334_manifest_excerpts(root))
        self.assertTrue(result["complete"])
        self.assertEqual(result["status"], "complete-observation")
        self.assertEqual(result["timing_verdict"], "none")
        self.assertFalse(result["performance_acceptance"])
        self.assertEqual(set(result["manifest"]), {"path", "sha256", "bytes"})
        for row in result["roles"]:
            entries = ACTUAL_401334[row["role"]]
            expected_logs = [(process, source_path, source_hash)
                             for process, source_path, source_hash, _lines in entries]
            self.assertEqual([(log["process"], log["original_path"])
                              for log in row["logs"]],
                             [(process, source_path)
                              for process, source_path, _source_hash in expected_logs])
            self.assertTrue(all(len(source_hash) == 64
                                for _process, _source_path, source_hash in expected_logs))
            self.assertEqual([entry["action"] for entry in row["observations"]], list(reader.ACTIONS))
            self.assertTrue(all(entry["process"] in {"initial", "rejoin"}
                                for entry in row["observations"]))
        english = next(row for row in result["roles"] if row["role"] == "en")
        self.assertEqual(english["observations"][-1]["process"], "rejoin")
        self.assertIn("rejoin-en", english["observations"][-1]["original_path"])

    def test_manifest_rejects_missing_role_process_and_duplicate_action_across_phases(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.write_actual_401334_manifest_excerpts(root)
            value = json.loads(manifest.read_text(encoding="utf-8"))
            for label, mutate, expected in (
                ("missing-role", lambda document: document["roles"].pop("de"), "roles must be exactly"),
                ("bad-process", lambda document: document["roles"]["en"][0].update(process="other"),
                 "unique initial, rejoin, or restart"),
                ("duplicate-process", lambda document: document["roles"]["en"][1].update(process="initial"),
                 "unique initial, rejoin, or restart"),
            ):
                with self.subTest(label=label):
                    changed = json.loads(json.dumps(value))
                    mutate(changed)
                    manifest.write_text(json.dumps(changed), encoding="utf-8")
                    with self.assertRaisesRegex(reader.LibraryProfileError, expected):
                        reader.read_manifest(manifest)

            duplicate = root / "en-duplicate.log"
            duplicate.write_text(marker("search", "9.0") + "\n", encoding="utf-8")
            value["roles"]["en"].append({"process": "restart", "path": duplicate.name})
            manifest.write_text(json.dumps(value), encoding="utf-8")
            with self.assertRaisesRegex(reader.LibraryProfileError, "action is duplicated"):
                reader.read_manifest(manifest)

    def test_manifest_refuses_duplicate_json_keys_nonfinite_constants_and_noninteger_schema(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.write_actual_401334_manifest_excerpts(root)
            valid = manifest.read_text(encoding="utf-8")
            opponents = (
                ("root-key", valid.replace('"schema": 1', '"schema": 1, "schema": 1', 1),
                 "duplicate JSON key: schema"),
                ("role-key", valid.replace('"server": [{', '"server": [], "server": [{', 1),
                 "duplicate JSON key: server"),
                ("entry-key", valid.replace('"process": "initial", "path"',
                                                '"process": "initial", "process": "initial", "path"', 1),
                 "duplicate JSON key: process"),
                ("nonfinite", valid.replace('"schema": 1', '"schema": NaN', 1),
                 "nonfinite JSON constant: NaN"),
                ("boolean-schema", valid.replace('"schema": 1', '"schema": true', 1),
                 "manifest schema differs"),
                ("float-schema", valid.replace('"schema": 1', '"schema": 1.0', 1),
                 "manifest schema differs"),
            )
            for label, raw, expected in opponents:
                with self.subTest(label=label):
                    manifest.write_text(raw, encoding="utf-8")
                    with self.assertRaisesRegex(reader.LibraryProfileError, expected):
                        reader.read_manifest(manifest)

    def test_manifest_rejects_reused_resolved_log_locator(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.write_actual_401334_manifest_excerpts(root)
            value = json.loads(manifest.read_text(encoding="utf-8"))
            value["roles"]["en"][1]["path"] = value["roles"]["en"][0]["path"]
            manifest.write_text(json.dumps(value), encoding="utf-8")
            with self.assertRaisesRegex(reader.LibraryProfileError, "locator is duplicated"):
                reader.read_manifest(manifest)

    def test_manifest_and_selected_log_byte_limits_reject_before_aggregation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.write_actual_401334_manifest_excerpts(root)
            with mock.patch.object(reader, "MAX_MANIFEST_BYTES", 1):
                with self.assertRaisesRegex(reader.LibraryProfileError, "manifest exceeds"):
                    reader.read_manifest(manifest)
            with mock.patch.object(reader, "MAX_TOTAL_LOG_BYTES", 32):
                with self.assertRaisesRegex(reader.LibraryProfileError, "log exceeds 32 byte input limit"):
                    reader.read_manifest(manifest)

    def test_total_budget_bounds_each_stream_before_decoding(self):
        class RecordingPath:
            def __init__(self, payload: bytes):
                self.payload = payload
                self.requests = []
                self.returned = []

            def open(self, mode: str):
                if mode != "rb":
                    raise AssertionError(f"unexpected stream mode: {mode}")
                owner = self

                class RecordingStream(io.BytesIO):
                    def read(self, amount: int) -> bytes:
                        owner.requests.append(amount)
                        data = super().read(amount)
                        owner.returned.append(len(data))
                        return data

                return RecordingStream(self.payload)

            def __str__(self):
                return "recording.log"

        cases = (
            # Three full logs exhaust the total budget; only an empty final
            # stream is admissible, with one byte requested to detect overflow.
            (24, [b"x" * 8] * 3 + [b""], [9, 9, 9, 1], [8, 8, 8, 0], False),
            (24, [b"x" * 8] * 3 + [b"\xff" * 8], [9, 9, 9, 1], [8, 8, 8, 1], True),
            # A partially remaining budget admits its exact boundary and
            # refuses overflow before attempting UTF-8 decoding.
            (26, [b"x" * 8] * 3 + [b"xx"], [9, 9, 9, 3], [8, 8, 8, 2], False),
            (26, [b"x" * 8] * 3 + [b"\xff" * 8], [9, 9, 9, 3], [8, 8, 8, 3], True),
            # The per-log bound still applies when the aggregate has room.
            (24, [b"x" * 9, b"", b"", b""], [9], [9], True),
        )
        for budget, payloads, requests, returned, overflow in cases:
            with self.subTest(budget=budget, lengths=list(map(len, payloads)), overflow=overflow):
                paths = [RecordingPath(payload) for payload in payloads]
                inputs = [reader.LogInput(role, phase, path, str(path))
                          for role, phase, path in zip(
                              ("server", "server", "en", "de"),
                              ("initial", "rejoin", "initial", "initial"), paths)]
                with mock.patch.object(reader, "MAX_LOG_BYTES", 8), \
                        mock.patch.object(reader, "MAX_TOTAL_LOG_BYTES", budget):
                    if overflow:
                        with self.assertRaisesRegex(reader.LibraryProfileError, "byte input limit"):
                            reader._read_profiles(inputs)
                    else:
                        result = reader._read_profiles(inputs)
                        self.assertFalse(result["complete"])
                        self.assertFalse(result["performance_acceptance"])
                self.assertEqual([size for path in paths for size in path.requests], requests)
                self.assertEqual([size for path in paths for size in path.returned], returned)

    def test_cli_manifest_emits_phase_provenance_without_a_performance_verdict(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = self.write_actual_401334_manifest_excerpts(root)
            completed = subprocess.run(
                [sys.executable, str(ROOT / "tools" / "read_library_profiles.py"),
                 "--manifest", str(manifest)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=True,
            )
        result = json.loads(completed.stdout)
        self.assertEqual(completed.stderr, "")
        self.assertTrue(result["complete"])
        self.assertEqual(result["timing_verdict"], "none")
        self.assertFalse(result["performance_acceptance"])
        self.assertEqual(next(row for row in result["roles"] if row["role"] == "de")
                         ["observations"][-1]["process"], "rejoin")

    def test_german_requires_observed_dauer_narrow_no_break_space_unit(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = self.complete_rows()
            rows["de"] = tuple(marker(action, "2.5", role="de") for action in reader.ACTIONS)
            result = reader.read_profiles(self.write_logs(Path(temporary), rows))
        german = next(row for row in result["roles"] if row["role"] == "de")
        self.assertEqual(german["observations"][0]["duration_ms"], 2.5)
        self.assertIn("Dauer: 2.5\u202fms", german["observations"][0]["raw_line"])

    def test_observed_english_and_german_profiler_renderings_remain_admitted(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = self.complete_rows()
            rows["en"] = tuple(marker(action, "3.011300") for action in reader.ACTIONS)
            rows["de"] = tuple(marker(action, "2.569500", role="de") for action in reader.ACTIONS)
            result = reader.read_profiles(self.write_logs(Path(temporary), rows))
        rows_by_role = {row["role"]: row for row in result["roles"]}
        self.assertEqual(rows_by_role["en"]["observations"][0]["duration_ms"], 3.0113)
        self.assertEqual(rows_by_role["de"]["observations"][0]["duration_ms"], 2.5695)

    def test_refuses_unknown_unit_malformed_marker_and_duplicate_action(self):
        opponents = (
            ("unknown-unit", "en", marker("search", "1.0").replace("ms", "us"), "unknown format or unit"),
            ("malformed", "server", " [MIR5_LIBRARY_PROFILE] search elapsed=1ms", "unknown format or unit"),
            ("duplicate", "de", marker("search", "9.0", role="de"), "action is duplicated"),
        )
        for label, role, extra, expected in opponents:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                rows = self.complete_rows()
                rows[role] = rows[role] + (extra,)
                with self.assertRaisesRegex(reader.LibraryProfileError, expected):
                    reader.read_profiles(self.write_logs(Path(temporary), rows))

    def test_refuses_bare_missing_separator_and_doubled_marker_tokens(self):
        opponents = (
            ("bare", "server", " [MIR5_LIBRARY_PROFILE]", "lacks its required separator"),
            ("missing-space", "en", " [MIR5_LIBRARY_PROFILE]search Duration: 1.0ms",
             "lacks its required separator"),
            ("doubled", "de", marker("search", "1.0", role="de") + " [MIR5_LIBRARY_PROFILE]",
             "marker is duplicated"),
        )
        for label, role, extra, expected in opponents:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                rows = self.complete_rows()
                rows[role] = rows[role] + (extra,)
                with self.assertRaisesRegex(reader.LibraryProfileError, expected):
                    reader.read_profiles(self.write_logs(Path(temporary), rows))

    def test_log_read_is_capped_and_enforces_exact_boundary_and_overflow(self):
        class RecordingStream:
            def __init__(self, payload: bytes):
                self.payload = payload
                self.requested = None

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self, amount: int) -> bytes:
                self.requested = amount
                return self.payload[:amount]

        class RecordingPath:
            def __init__(self, payload: bytes):
                self.stream = RecordingStream(payload)

            def open(self, mode: str):
                self.mode = mode
                return self.stream

            def __str__(self):
                return "recording.log"

        line = ("x" * (reader.MAX_LINE_CHARACTERS - 1) + "\n").encode("utf-8")
        exact = RecordingPath(line * (reader.MAX_LOG_BYTES // len(line)))
        # The final partial segment reaches the exact byte boundary while each
        # decoded line remains inside the independently bounded line contract.
        exact.stream.payload += b"x" * (reader.MAX_LOG_BYTES - len(exact.stream.payload))
        data, lines = reader._read_log(exact)
        self.assertEqual(exact.mode, "rb")
        self.assertEqual(exact.stream.requested, reader.MAX_LOG_BYTES + 1)
        self.assertEqual(len(data), reader.MAX_LOG_BYTES)
        self.assertTrue(lines)

        overflow = RecordingPath(b"x" * (reader.MAX_LOG_BYTES + 1))
        with self.assertRaisesRegex(reader.LibraryProfileError, "exceeds"):
            reader._read_log(overflow)
        self.assertEqual(overflow.stream.requested, reader.MAX_LOG_BYTES + 1)

    def test_refuses_missing_role_and_rejects_nonfinite_or_negative_shapes(self):
        with tempfile.TemporaryDirectory() as temporary:
            logs = self.write_logs(Path(temporary), self.complete_rows())
            with self.assertRaisesRegex(reader.LibraryProfileError, "exactly server, en, and de"):
                reader.read_profiles(logs[:2])
            rows = self.complete_rows()
            rows["server"] = tuple(marker(action, "1.0") for action in reader.ACTIONS[:-1]) + (
                marker("reopen", "-1.0"),
            )
            with self.assertRaisesRegex(reader.LibraryProfileError, "unknown format or unit"):
                reader.read_profiles(self.write_logs(Path(temporary), rows))
            rows["server"] = tuple(marker(action, "1.0") for action in reader.ACTIONS[:-1]) + (
                marker("reopen", "NaN"),
            )
            with self.assertRaisesRegex(reader.LibraryProfileError, "unknown format or unit"):
                reader.read_profiles(self.write_logs(Path(temporary), rows))

    def test_cli_outputs_only_bounded_json_observations(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            logs = self.write_logs(root, self.complete_rows())
            expected_server_hash = hashlib.sha256(logs[0][1].read_bytes()).hexdigest().upper()
            command = [sys.executable, str(ROOT / "tools" / "read_library_profiles.py")]
            for role, path in logs:
                command.extend(["--log", f"{role}={path}"])
            completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=True)
        result = json.loads(completed.stdout)
        self.assertEqual(completed.stderr, "")
        self.assertTrue(result["complete"])
        self.assertNotIn("median", completed.stdout.lower())
        self.assertNotIn("percent", completed.stdout.lower())
        self.assertNotIn("threshold", completed.stdout.lower())
        self.assertEqual(expected_server_hash, result["roles"][0]["log_sha256"])


class RetainedWindowReaderTests(unittest.TestCase):
    def inputs(self):
        roles = ("server", "client-en", "client-de")
        memory = {"kind": "MIR5OwnedProcessMemoryObservationV1", "status": "complete-observation",
                  "incomplete_reasons": [], "performance_acceptance": False,
                  "lifetime_peak_observer": {"changes_periodic_observations": False,
                                             "utc_reference_before_stopwatch_start": "2026-10-29T00:00:00Z"},
                  "observations": [], "lifetime_peak_counters": []}
        logs = {}
        for index, role in enumerate(roles):
            start = f"2026-10-29T00:00:0{index}Z"
            for phase in ("initial", "restart"):
                memory["lifetime_peak_counters"].append({"phase": phase, "role": role,
                    "pid": (200 if phase == "initial" else 100)+index,
                    "start_utc": start, "observed_utc": "2026-10-29T00:00:45Z",
                    "elapsed_monotonic_milliseconds": 45000,
                    "working_set_peak_bytes": 1000, "paged_memory_peak_bytes": 2000})
            for elapsed in range(0, 45001, 250):
                memory["observations"].append({"phase": "restart", "role": role, "pid": 100+index,
                    "start_utc": start, "elapsed_monotonic_milliseconds": elapsed,
                    "working_set_bytes": (101 if elapsed < 20000 else 202)+index,
                    "private_bytes": (303 if elapsed < 20000 else 404)+index})
            lines = []
            for stage, seconds, tick, iterations in [("baseline-start", 5, 100, 0),
                    ("baseline-end", 15, 700, 0), ("post-refresh-start", 31, 1660, 32),
                    ("post-refresh-end", 41, 2260, 32)]:
                row = {"schema": 1, "case": "library-paired-browser", "stage": stage, "arm": "published",
                       "tick": tick, "refresh_iterations": iterations, "public_calls_per_iteration": 2,
                       "window_ticks": 600, "native_snapshot_unchanged": True, "actual_keyboard_input": False,
                       "performance_acceptance": False}
                lines.append(f"  {seconds-index:.3f} Script @fixture: [MIR5_LIBRARY_RETAINED] {json.dumps(row)}")
            logs[role] = "\n".join(lines)
        return memory, logs

    def test_aligns_each_process_clock_and_preserves_distinct_observations_without_scoring(self):
        memory, logs = self.inputs()
        before = copy.deepcopy((memory, logs))
        result = reader.read_retained_windows(memory, logs, "published")
        self.assertTrue(result["complete"])
        self.assertFalse(result["performance_acceptance"])
        self.assertEqual(len(result["metrics"]), 12)
        for index, role in enumerate(("server", "client-en", "client-de")):
            self.assertEqual(result["metrics"][f"retained/baseline/{role}/working_set_bytes"], 101+index)
            self.assertEqual(result["metrics"][f"retained/post_refresh/{role}/private_bytes"], 404+index)
            self.assertEqual(result["growth"][f"retained_growth/{role}/working_set_bytes"], 101)
            self.assertEqual(result["roles"][index]["windows"]["baseline"]["samples"], 33)
        self.assertEqual((memory, logs), before)
        self.assertNotIn("threshold", result)

    def test_rejects_short_burst_missing_edges_and_internal_sampling_gaps(self):
        for opponent in ("short-burst", "missing-first-edge", "missing-last-edge", "internal-gap"):
            with self.subTest(opponent=opponent):
                memory, logs = self.inputs()
                def keep(row):
                    if row["role"] != "server":
                        return True
                    elapsed = row["elapsed_monotonic_milliseconds"]
                    if opponent == "short-burst":
                        return not 6000 <= elapsed <= 14000 or 8000 <= elapsed <= 10000
                    if opponent == "missing-first-edge":
                        return not 6000 <= elapsed <= 6500
                    if opponent == "missing-last-edge":
                        return not 13500 <= elapsed <= 14000
                    return not 8000 <= elapsed <= 8750
                memory["observations"] = [row for row in memory["observations"] if keep(row)]
                with self.assertRaisesRegex(reader.LibraryProfileError, "coverage"):
                    reader.read_retained_windows(memory, logs, "published")

    def test_rejects_incomplete_or_changed_process_and_counter_inputs(self):
        for opponent in ("incomplete", "missing-counter", "pid", "start", "clock", "nan", "memory-type", "cutoff"):
            with self.subTest(opponent=opponent):
                memory, logs = self.inputs()
                sample = memory["observations"][32]
                if opponent == "incomplete": memory["status"] = "incomplete-observation"
                elif opponent == "missing-counter": memory["lifetime_peak_counters"].pop()
                elif opponent == "pid": sample["pid"] = 999
                elif opponent == "start": sample["start_utc"] = "2026-10-29T00:00:01Z"
                elif opponent == "clock": sample["elapsed_monotonic_milliseconds"] = 0
                elif opponent == "nan": sample["elapsed_monotonic_milliseconds"] = float("nan")
                elif opponent == "memory-type": sample["private_bytes"] = "303"
                else: memory["lifetime_peak_counters"][1]["elapsed_monotonic_milliseconds"] = 10000
                with self.assertRaises(reader.LibraryProfileError):
                    reader.read_retained_windows(memory, logs, "published")

    def test_rejects_missing_duplicate_malformed_or_wrong_workload_peer_markers(self):
        for opponent in ("missing", "duplicate", "tick", "iterations", "native-state", "arm", "fields", "elapsed", "duplicate-key"):
            with self.subTest(opponent=opponent):
                memory, logs = self.inputs()
                text = logs["server"]
                if opponent == "missing": text = "\n".join(text.splitlines()[:-1])
                elif opponent == "duplicate": text += "\n" + text.splitlines()[-1]
                elif opponent == "tick": text = text.replace('"tick": 1660', '"tick": 1659')
                elif opponent == "iterations": text = text.replace('"refresh_iterations": 32', '"refresh_iterations": 31')
                elif opponent == "native-state": text = text.replace('"native_snapshot_unchanged": true', '"native_snapshot_unchanged": false')
                elif opponent == "arm": text = text.replace('"arm": "published"', '"arm": "mir5"')
                elif opponent == "fields": text = text.replace('"schema": 1', '"unknown": 1, "schema": 1')
                elif opponent == "elapsed": text = text.replace('  5.000', '  invalid')
                else: text = text.replace('"schema": 1', '"schema": 1, "schema": 1')
                logs["server"] = text
                with self.assertRaises(reader.LibraryProfileError):
                    reader.read_retained_windows(memory, logs, "published")

    def test_requires_every_initial_and_restart_os_peak_endpoint_before_pending_arm(self):
        for opponent in ("unknown-phase", "unknown-role", "duplicate-slot", "missing-working-set",
                         "nonfinite-working-set", "boolean-paged", "negative-paged", "missing-utc",
                         "naive-utc", "reused-identity", "observation-before-start", "nonfinite-clock"):
            with self.subTest(opponent=opponent):
                memory, logs = self.inputs()
                peak = memory["lifetime_peak_counters"][0]  # initial/server; restart triples remain valid
                if opponent == "unknown-phase": peak["phase"] = "unrelated"
                elif opponent == "unknown-role": peak["role"] = "other"
                elif opponent == "duplicate-slot": peak["role"] = "client-en"
                elif opponent == "missing-working-set": del peak["working_set_peak_bytes"]
                elif opponent == "nonfinite-working-set": peak["working_set_peak_bytes"] = float("nan")
                elif opponent == "boolean-paged": peak["paged_memory_peak_bytes"] = True
                elif opponent == "negative-paged": peak["paged_memory_peak_bytes"] = -1
                elif opponent == "missing-utc": del peak["observed_utc"]
                elif opponent == "naive-utc": peak["observed_utc"] = "2026-10-29T00:00:45"
                elif opponent == "reused-identity": peak["pid"] = 100
                elif opponent == "observation-before-start": peak["observed_utc"] = "2026-10-28T00:00:00Z"
                else: peak["elapsed_monotonic_milliseconds"] = float("nan")
                with self.assertRaises(reader.LibraryProfileError):
                    reader.read_retained_windows(memory, logs, "published")


if __name__ == "__main__":
    unittest.main(verbosity=2)
