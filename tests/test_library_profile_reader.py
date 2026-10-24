"""Controls for the bounded offline native Library profiler reader."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


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


def marker(action: str, milliseconds: str, *, role: str = "en") -> str:
    if role == "de":
        return f" [MIR5_LIBRARY_PROFILE] {action} Dauer: {milliseconds}\u202fms"
    return f" [MIR5_LIBRARY_PROFILE] {action} Duration: {milliseconds}ms"


class LibraryProfileReaderTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
