"""Offline controls for the bounded Linux private-display lifecycle.

These use only temporary regular files and a fake backend.  They do not open
an X display, spawn Xtigervnc, launch Factorio, mutate a Library, or inspect a
real process tree.
"""

import contextlib
import builtins
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "lib" / "validation" / "LinuxLibraryDisplay.py"
SPEC = importlib.util.spec_from_file_location("mir_linux_library_display", MODULE_PATH)
DISPLAY = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = DISPLAY
SPEC.loader.exec_module(DISPLAY)

ENTRY_PATH = ROOT / "tools" / "Invoke-LibraryLinuxDisplay.py"
ENTRY_SPEC = importlib.util.spec_from_file_location("mir_linux_library_display_entry", ENTRY_PATH)
ENTRY = importlib.util.module_from_spec(ENTRY_SPEC)
sys.modules[ENTRY_SPEC.name] = ENTRY
ENTRY_SPEC.loader.exec_module(ENTRY)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


class FakeProcess:
    def __init__(self, pid=40193):
        self.pid = pid
        self.returncode = None


class FakeProbe:
    VIEWER_RELATIVE = "runtime/viewer.sock"

    def __init__(self, backend, pins):
        self.backend = backend
        self.PINS = pins
        self.idle_calls = 0
        self.network_checks = 0
        self.fail_binding = False
        self.replace_viewer_before_binding = False

    def idle_host(self):
        self.idle_calls += 1

    def unix_listeners(self, paths):
        return ["owned-x-listener"] if self.backend.socket_present else []

    def display_binding(self, process, socket_path, lock_path):
        self.backend.display_binding_calls += 1
        if self.replace_viewer_before_binding:
            self.backend.replace_viewer_foreign()
        if self.fail_binding:
            raise DISPLAY.DisplayError("synthetic display binding refusal")
        if not self.backend.socket_present or not self.backend.lock_present:
            raise DISPLAY.DisplayError("synthetic display binding is absent")
        if self.backend.changed_display_binding:
            return {"socket": [141, 142], "lock": [143, 144], "pid": process.pid}
        return {"socket": [41, 42], "lock": [43, 44], "pid": process.pid}

    def viewer_binding(self, process, viewer_path):
        self.backend.viewer_binding_calls += 1
        if not self.backend.viewer_present:
            raise DISPLAY.DisplayError("synthetic private viewer is absent")
        if self.backend.changed_viewer_binding:
            return {"device_inode": [71, 98], "listener": ["filesystem", 93]}
        return {"device_inode": [71, 88], "listener": ["filesystem", 73]}

    def no_network_sockets(self, pid):
        self.network_checks += 1
        if self.backend.network_present:
            raise DISPLAY.DisplayError("synthetic network listener exists")

    def listener_inode_present(self, inode):
        return self.backend.viewer_listener_present


class FakeBackend:
    """A process/filesystem facade whose only concrete paths are a temp root."""

    uid_value = 1000
    session_value = 7001

    def __init__(self, plan, pins):
        self.plan = plan
        self.socket_present = False
        self.lock_present = False
        self.viewer_present = False
        self.viewer_foreign = False
        self.viewer_listener_present = False
        self.network_present = False
        self.changed_display_binding = False
        self.changed_viewer_binding = False
        self.clock = 0.0
        self.signals = ["stop"]
        self.process = FakeProcess()
        self.identity = {"pid": self.process.pid, "start_ticks": 314159, "session_id": self.session_value}
        self.stale_identity = None
        self.timeout_once = False
        self.stale_after_timeout = None
        self.spawn_calls = []
        self.xauth_calls = []
        self.terminate_calls = 0
        self.kill_calls = 0
        self.unlink_calls = []
        self.display_binding_calls = 0
        self.viewer_binding_calls = 0
        self.probe = FakeProbe(self, {
            str(plan.xtigervnc): pins["xtigervnc"]["sha256"],
            str(plan.xauth): pins["xauth"]["sha256"],
        })

    def now(self):
        return self.clock

    def sleep(self, seconds):
        self.clock += seconds

    def uid(self):
        return self.uid_value

    def session(self, pid):
        return self.session_value

    def process_identity(self, pid):
        if self.stale_identity is not None:
            return dict(self.stale_identity)
        return dict(self.identity)

    def lexists(self, path):
        path = Path(path)
        if path == self.plan.socket:
            return self.socket_present
        if path == self.plan.lock:
            return self.lock_present
        if path == self.plan.viewer:
            return self.viewer_present and os.path.lexists(path)
        return os.path.lexists(path)

    def lstat(self, path):
        path = Path(path)
        if path == Path("/tmp/.X11-unix"):
            return types.SimpleNamespace(st_mode=stat.S_IFDIR | 0o1777, st_uid=0, st_dev=1, st_ino=2)
        if path == self.plan.runtime:
            return types.SimpleNamespace(st_mode=stat.S_IFDIR | 0o700, st_uid=self.uid_value, st_dev=3, st_ino=4)
        if path == self.plan.authority:
            return types.SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=self.uid_value, st_dev=5, st_ino=6)
        if path == self.plan.log:
            return types.SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=self.uid_value, st_dev=9, st_ino=10)
        if path == self.plan.viewer:
            marker = 99 if self.viewer_foreign else 88
            return types.SimpleNamespace(st_mode=stat.S_IFSOCK | 0o600, st_uid=self.uid_value, st_dev=71, st_ino=marker)
        return path.lstat()

    def iterdir(self, path):
        return Path(path).iterdir()

    def mkdir(self, path, mode):
        Path(path).mkdir(mode=mode)

    def rmdir(self, path):
        Path(path).rmdir()

    def unlink(self, path):
        self.unlink_calls.append(Path(path))
        Path(path).unlink()
        if Path(path) == self.plan.viewer:
            self.viewer_present = False
            self.viewer_listener_present = False

    def open_exclusive(self, path, mode):
        return Path(path).open("xb")

    def sync(self, stream):
        stream.flush()

    def spawn(self, argv, env, cwd, log):
        self.spawn_calls.append({"argv": list(argv), "env": dict(env), "cwd": Path(cwd)})
        self.socket_present = True
        self.lock_present = True
        self.viewer_present = True
        self.viewer_listener_present = True
        self.plan.viewer.write_bytes(b"owned-viewer")
        return self.process

    def poll(self, process):
        return process.returncode

    def terminate(self, process):
        self.terminate_calls += 1
        if self.timeout_once:
            return
        process.returncode = 0
        self.socket_present = False
        self.lock_present = False
        self.viewer_listener_present = False

    def kill(self, process):
        self.kill_calls += 1
        self.terminate(process)

    def wait(self, process, timeout):
        if self.timeout_once:
            self.timeout_once = False
            self.stale_identity = self.stale_after_timeout
            raise subprocess.TimeoutExpired("Xtigervnc", timeout)
        return process.returncode

    def xauth(self, argv, authority_input):
        self.xauth_calls.append((list(argv), authority_input))
        return 0

    def load_probe(self, path):
        return self.probe

    def stop_signal(self, stdin, timeout):
        value = self.signals.pop(0) if self.signals else "stop"
        if value is None:
            self.clock += timeout
        return value

    def replace_viewer_foreign(self):
        self.plan.viewer.unlink()
        self.plan.viewer.write_bytes(b"foreign-viewer")
        self.viewer_present = True
        self.viewer_foreign = True
        self.viewer_listener_present = True


class LinuxLibraryDisplaySchemaTests(unittest.TestCase):
    def make_layout(self):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        checkout = root / "checkout"
        output = checkout / "build" / "p"
        output.mkdir(parents=True)
        role_root = output / "case"
        role_root.mkdir()
        pins = {}
        for name in ("xtigervnc", "xauth", "probe_display"):
            path = root / name
            path.write_bytes((name + "\n").encode("ascii"))
            pins[name] = {"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)}
        return temporary, checkout, role_root, pins

    def plan(self, root, pins, *, role="client-en", geometry=None, **changes):
        value = {
            "schema": 1,
            "kind": "MIRLinuxLibraryDisplayPlanV1",
            "role": role,
            "geometry": [1280, 720] if geometry is None else geometry,
            "role_root": str(root),
            "deadline_seconds": 30,
            **pins,
        }
        value.update(changes)
        return value

    @contextlib.contextmanager
    def admitted_probe(self, pins):
        with mock.patch.object(DISPLAY, "PINNED_PROBE_DISPLAY_SHA256", pins["probe_display"]["sha256"]):
            yield

    @contextlib.contextmanager
    def linux(self):
        with mock.patch.object(DISPLAY.sys, "platform", "linux"):
            yield

    def validated_backend(self, *, role="client-en", deadline=30):
        temporary, checkout, root, pins = self.make_layout()
        self.addCleanup(temporary.cleanup)
        plan = self.plan(root, pins, role=role, deadline_seconds=deadline)
        with self.admitted_probe(pins):
            validated = DISPLAY.validate_plan(plan, checkout)
        return validated, FakeBackend(validated, pins), pins

    def assert_refuses(self, call, message):
        with self.assertRaisesRegex(DISPLAY.DisplayError, message):
            call()

    def test_fixed_roles_geometry_and_role_root_are_the_only_schema_admissions(self):
        for role, display in (("client-en", ":193"), ("client-de", ":194")):
            with self.subTest(role=role):
                temporary, checkout, root, pins = self.make_layout()
                self.addCleanup(temporary.cleanup)
                with self.admitted_probe(pins):
                    validated = DISPLAY.validate_plan(self.plan(root, pins, role=role), checkout)
                self.assertEqual(validated.display, display)
                self.assertEqual(validated.socket.name, "X" + display[1:])
                self.assertEqual(validated.lock.name, ".X" + display[1:] + "-lock")
                self.assertEqual(validated.viewer, root / "runtime" / "viewer.sock")

        temporary, checkout, root, pins = self.make_layout()
        self.addCleanup(temporary.cleanup)
        outside = Path(temporary.name) / "outside"
        outside.mkdir()
        with self.admitted_probe(pins):
            self.assert_refuses(lambda: DISPLAY.validate_plan(self.plan(outside, pins), checkout), "role_root escapes")
            self.assert_refuses(lambda: DISPLAY.validate_plan(self.plan(root, pins, geometry=[1920, 1080]), checkout), "geometry is not admitted")
            self.assert_refuses(lambda: DISPLAY.validate_plan(self.plan(root, pins, role="client-fr"), checkout), "role differs")

    def test_bound_plan_rejects_wrong_hash_duplicate_json_and_oversize_before_execution(self):
        temporary, checkout, root, pins = self.make_layout()
        self.addCleanup(temporary.cleanup)
        plan_path = Path(temporary.name) / "plan.json"
        with self.admitted_probe(pins):
            raw = json.dumps(self.plan(root, pins), separators=(",", ":")).encode("utf-8")
            plan_path.write_bytes(raw)
            self.assert_refuses(lambda: DISPLAY.load_bound_plan(plan_path, "A" * 64, checkout), "raw plan bytes differ")

            duplicate = b'{"schema":1,"schema":1}'
            plan_path.write_bytes(duplicate)
            self.assert_refuses(lambda: DISPLAY.load_bound_plan(plan_path, hashlib.sha256(duplicate).hexdigest().upper(), checkout), "duplicate JSON")

            oversized = b"x" * (DISPLAY.MAX_PLAN_BYTES + 1)
            plan_path.write_bytes(oversized)
            self.assert_refuses(lambda: DISPLAY.load_bound_plan(plan_path, hashlib.sha256(oversized).hexdigest().upper(), checkout), "plan size differs")

    def test_bound_plan_hashes_the_same_raw_buffer_it_parses(self):
        temporary, checkout, root, pins = self.make_layout()
        self.addCleanup(temporary.cleanup)
        plan_path = Path(temporary.name) / "plan.json"
        raw = json.dumps(self.plan(root, pins), separators=(",", ":")).encode("utf-8")
        replacement = b'{"not":"the original plan"}'
        plan_path.write_bytes(raw)
        original_read = Path.read_bytes

        def read_then_replace(path):
            value = original_read(path)
            if path == plan_path:
                plan_path.write_bytes(replacement)
            return value

        with self.admitted_probe(pins), mock.patch.object(Path, "read_bytes", read_then_replace):
            validated = DISPLAY.load_bound_plan(plan_path, hashlib.sha256(raw).hexdigest().upper(), checkout)
        self.assertEqual(validated.role, "client-en")
        self.assertEqual(plan_path.read_bytes(), replacement)

    def test_schema_cli_has_no_execution_backend_or_x_side_effect(self):
        temporary, checkout, root, pins = self.make_layout()
        self.addCleanup(temporary.cleanup)
        plan_path = Path(temporary.name) / "plan.json"
        raw = json.dumps(self.plan(root, pins), separators=(",", ":")).encode("utf-8")
        plan_path.write_bytes(raw)
        stdout = io.StringIO()
        with self.admitted_probe(pins), \
             mock.patch.object(DISPLAY, "run_display", side_effect=AssertionError("schema must not execute")), \
             mock.patch.object(sys, "stdout", stdout):
            code = DISPLAY.main(["--mode", "schema", "--checkout", str(checkout), "--plan", str(plan_path),
                                 "--plan-sha256", hashlib.sha256(raw).hexdigest().upper()])
        self.assertEqual(code, 0)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["status"], "validated-schema-only")
        self.assertEqual(result["display"], ":193")
        self.assertEqual(result["factorio_processes"], 0)
        self.assertFalse((root / "authority").exists())
        self.assertFalse((root / "runtime").exists())

    def test_loader_refuses_wrong_module_pin_before_compilation(self):
        with mock.patch.object(builtins, "compile", side_effect=AssertionError("module must not compile")):
            with self.assertRaisesRegex(RuntimeError, "module identity differs"):
                ENTRY.load_verified_module(MODULE_PATH, "0" * 64)

    def test_loader_compiles_the_verified_module_buffer_once(self):
        loaded = ENTRY.load_verified_module(MODULE_PATH, digest(MODULE_PATH))
        self.assertEqual(loaded.PLAN_KIND, "MIRLinuxLibraryDisplayPlanV1")
        self.assertTrue(callable(loaded.main))

    def test_stop_signal_keeps_partial_stdin_framing_bounded(self):
        backend = DISPLAY.SystemBackend()
        read_descriptor, write_descriptor = os.pipe()
        stream = os.fdopen(read_descriptor, "rb", buffering=0)
        self.addCleanup(stream.close)
        try:
            os.write(write_descriptor, b"sto")
            with mock.patch.object(DISPLAY.select, "select", return_value=([read_descriptor], [], [])):
                started = time.monotonic()
                self.assertIsNone(backend.stop_signal(stream, 0.01))
                self.assertLess(time.monotonic() - started, 0.25)
            with mock.patch.object(DISPLAY.select, "select", return_value=([], [], [])):
                self.assertIsNone(backend.stop_signal(stream, 0.01))
            os.write(write_descriptor, b"p\n")
            with mock.patch.object(DISPLAY.select, "select", return_value=([read_descriptor], [], [])):
                self.assertEqual(backend.stop_signal(stream, 0.01), "stop")
        finally:
            os.close(write_descriptor)

    def test_probe_pin_is_fixed_in_production_and_changed_member_refuses(self):
        self.assertEqual(
            DISPLAY.PINNED_PROBE_DISPLAY_SHA256,
            "F2DF1A32CA48119010E5DBE42326B3ED46E13A01A08B487AFDF0CDA5B180B423",
        )
        temporary, checkout, root, pins = self.make_layout()
        self.addCleanup(temporary.cleanup)
        with self.admitted_probe(pins):
            pins["probe_display"] = dict(pins["probe_display"])
            pins["probe_display"]["sha256"] = "0" * 64
            self.assert_refuses(lambda: DISPLAY.validate_plan(self.plan(root, pins), checkout), "probe_display identity differs")

    def test_execution_refuses_foreign_global_and_role_root_objects_before_mutation(self):
        for target in ("socket", "lock", "authority", "viewer"):
            with self.subTest(target=target):
                validated, backend, _ = self.validated_backend()
                if target == "socket":
                    backend.socket_present = True
                elif target == "lock":
                    backend.lock_present = True
                elif target == "authority":
                    validated.authority.write_bytes(b"foreign-authority")
                else:
                    validated.runtime.mkdir()
                    validated.viewer.write_bytes(b"foreign-viewer")
                    backend.viewer_present = True
                    backend.viewer_foreign = True
                with self.linux():
                    self.assert_refuses(lambda: DISPLAY.start_display(validated, backend),
                                        "preserve existing X display/lock|role_root changed")
                self.assertEqual(backend.spawn_calls, [])
                self.assertEqual(backend.xauth_calls, [])
                if target == "authority":
                    self.assertEqual(validated.authority.read_bytes(), b"foreign-authority")
                if target == "viewer":
                    self.assertEqual(validated.viewer.read_bytes(), b"foreign-viewer")

    def test_rehashes_execution_inputs_before_output_or_spawn(self):
        validated, backend, _ = self.validated_backend()
        validated.probe_display.write_bytes(b"changed after plan validation\n")
        with self.linux():
            self.assert_refuses(lambda: DISPLAY.start_display(validated, backend), "probe_display identity differs")
        self.assertEqual(backend.spawn_calls, [])
        self.assertEqual(backend.xauth_calls, [])
        self.assertEqual(list(validated.root.iterdir()), [])

    def test_stop_receipt_is_secret_free_and_owns_only_the_private_display(self):
        validated, backend, _ = self.validated_backend()
        backend.signals = ["stop"]
        with self.linux():
            result = DISPLAY.run_display(validated, backend, io.BytesIO(b""))
        self.assertEqual(result["status"], "stop")
        self.assertEqual(result["factorio_processes"], 0)
        self.assertEqual(backend.terminate_calls, 1)
        self.assertFalse(backend.socket_present)
        self.assertFalse(backend.lock_present)
        self.assertFalse(backend.viewer_present)
        self.assertEqual(backend.spawn_calls[0]["argv"][:2], [str(validated.xtigervnc), ":193"])
        self.assertIn("-rfbport", backend.spawn_calls[0]["argv"])
        self.assertNotIn("MIT-MAGIC-COOKIE-1", backend.spawn_calls[0]["argv"])
        cookie = backend.xauth_calls[0][1].split()[-1]
        durable = "\n".join(
            [validated.ready.read_text(encoding="utf-8"), validated.status.read_text(encoding="utf-8"),
             validated.result.read_text(encoding="utf-8"), json.dumps(backend.spawn_calls[0], default=str)],
        )
        self.assertNotIn(cookie, durable)
        self.assertGreaterEqual(backend.probe.network_checks, 2)
        self.assertEqual(backend.probe.idle_calls, 0)

    def test_eof_and_deadline_are_bounded_without_factorio_or_library_authority(self):
        for signal_values, expected in ((["eof"], "eof"), ([None, None, None, None, None], "deadline")):
            with self.subTest(expected=expected):
                validated, backend, _ = self.validated_backend(deadline=1)
                backend.signals = list(signal_values)
                with self.linux():
                    result = DISPLAY.run_display(validated, backend, io.BytesIO(b""))
                self.assertEqual(result["status"], expected)
                self.assertEqual(result["factorio_processes"], 0)
                self.assertEqual(backend.terminate_calls, 1)
                self.assertFalse(backend.socket_present)
                self.assertFalse(backend.lock_present)

    def test_partial_start_removes_owned_viewer_but_preserves_a_foreign_replacement(self):
        for replacement in (False, True):
            with self.subTest(replacement=replacement):
                validated, backend, _ = self.validated_backend()
                backend.probe.fail_binding = True
                backend.probe.replace_viewer_before_binding = replacement
                with self.linux():
                    self.assert_refuses(lambda: DISPLAY.start_display(validated, backend), "synthetic display binding refusal")
                self.assertEqual(backend.terminate_calls, 1)
                self.assertFalse(backend.socket_present)
                self.assertFalse(backend.lock_present)
                self.assertFalse(validated.authority.exists())
                if replacement:
                    self.assertTrue(validated.viewer.exists())
                    self.assertEqual(validated.viewer.read_bytes(), b"foreign-viewer")
                    self.assertNotIn(validated.viewer, backend.unlink_calls)
                else:
                    self.assertFalse(validated.viewer.exists())

    def test_stale_identity_refuses_before_terminating_or_removing_owned_credentials(self):
        for stale in (
            {"pid": 40193, "start_ticks": 314160, "session_id": 7001},
            {"pid": 40193, "start_ticks": 314159, "session_id": 7002},
        ):
            with self.subTest(stale=stale):
                validated, backend, _ = self.validated_backend()
                with self.linux():
                    state = DISPLAY.start_display(validated, backend)
                    backend.stale_identity = stale
                    result = DISPLAY.stop_display(state, "stop")
                self.assertEqual(result["status"], "failed-cleanup")
                self.assertEqual(backend.terminate_calls, 0)
                self.assertTrue(validated.authority.exists())
                self.assertTrue(validated.viewer.exists())
                self.assertNotIn(validated.authority, backend.unlink_calls)
                self.assertNotIn(validated.viewer, backend.unlink_calls)

    def test_stop_rechecks_display_viewer_and_network_before_termination(self):
        for changed in ("display", "viewer", "network"):
            with self.subTest(changed=changed):
                validated, backend, _ = self.validated_backend()
                with self.linux():
                    state = DISPLAY.start_display(validated, backend)
                    if changed == "display":
                        backend.changed_display_binding = True
                    elif changed == "viewer":
                        backend.changed_viewer_binding = True
                    else:
                        backend.network_present = True
                    result = DISPLAY.stop_display(state, "stop")
                self.assertEqual(result["status"], "failed-cleanup")
                self.assertEqual(backend.terminate_calls, 1)
                self.assertFalse(validated.authority.exists())
                self.assertFalse(validated.viewer.exists())

    def test_stop_rehashes_a_changed_helper_before_result_publication(self):
        validated, backend, _ = self.validated_backend()
        with self.linux():
            state = DISPLAY.start_display(validated, backend)
            validated.probe_display.write_bytes(b"post-start helper replacement\n")
            result = DISPLAY.stop_display(state, "stop")
        self.assertEqual(result["status"], "failed-cleanup")
        self.assertFalse(result["pins_rechecked"])
        self.assertEqual(backend.terminate_calls, 1)

    def test_forced_cleanup_rechecks_the_owned_identity_before_kill(self):
        for stale_after_timeout, expected_kills in (
            (None, 1),
            ({"pid": 40193, "start_ticks": 314160, "session_id": 7001}, 0),
        ):
            with self.subTest(stale_after_timeout=stale_after_timeout):
                validated, backend, _ = self.validated_backend()
                backend.timeout_once = True
                backend.stale_after_timeout = stale_after_timeout
                with self.linux():
                    state = DISPLAY.start_display(validated, backend)
                    result = DISPLAY.stop_display(state, "stop")
                self.assertEqual(result["status"], "failed-cleanup")
                self.assertEqual(backend.terminate_calls, 1 + expected_kills)
                self.assertEqual(backend.kill_calls, expected_kills)
                if stale_after_timeout is None:
                    self.assertFalse(validated.authority.exists())
                else:
                    self.assertTrue(validated.authority.exists())
                    self.assertNotIn(validated.authority, backend.unlink_calls)


if __name__ == "__main__":
    unittest.main()
