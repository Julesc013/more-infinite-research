#!/usr/bin/env python3
"""A tiny, Linux-only private X display ownership boundary.

The caller supplies an already-admitted, hash-bound plan and remains
responsible for every client, library, save, resource, and campaign decision.
This module owns only one short-lived Xtigervnc display and its private X
authority/viewer files.  It intentionally has no Factorio or input authority.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import select
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any, BinaryIO, Optional


PLAN_KIND = "MIRLinuxLibraryDisplayPlanV1"
READY_KIND = "MIRLinuxLibraryDisplayReadyV1"
RESULT_KIND = "MIRLinuxLibraryDisplayResultV1"
MAX_PLAN_BYTES = 8 * 1024
MAX_RECORD_BYTES = 8 * 1024
MAX_DEADLINE_SECONDS = 900
DISPLAY_BY_ROLE = {"client-en": ":193", "client-de": ":194"}
GEOMETRIES = {(1280, 720), (2560, 1440)}
PINNED_PROBE_DISPLAY_SHA256 = "F2DF1A32CA48119010E5DBE42326B3ED46E13A01A08B487AFDF0CDA5B180B423"
PLAN_FIELDS = {
    "schema", "kind", "role", "geometry", "role_root", "deadline_seconds",
    "xtigervnc", "xauth", "probe_display",
}
PIN_FIELDS = {"path", "bytes", "sha256"}


class DisplayError(RuntimeError):
    """A bounded refusal which never contains the X authority cookie."""


class DisplayStartError(DisplayError):
    """A startup refusal which states whether this boundary created output."""

    def __init__(self, message: str, output_started: bool):
        super().__init__(message)
        self.output_started = output_started


def require(condition: bool, message: str) -> None:
    if not condition:
        raise DisplayError(message)


def _scalar(value: object, label: str) -> str:
    require(type(value) is str and value and not value.isspace() and "\x00" not in value,
            f"{label} differs")
    return value


def _safe_error(value: object, secret: Optional[str] = None) -> str:
    text = str(value)
    if secret:
        text = text.replace(secret, "[redacted]")
    return text[:512]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _regular(path: Path, label: str) -> os.stat_result:
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and not path.is_symlink(), f"{label} must be a regular non-symlink file")
    return info


def _absolute(value: object, label: str) -> Path:
    path = Path(_scalar(value, label))
    require(path.is_absolute(), f"{label} must be absolute")
    return Path(os.path.abspath(path))


def _under(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def _strict_json(raw: bytes, label: str) -> dict[str, object]:
    def pairs(items: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for name, value in items:
            if name in result:
                raise DisplayError(f"{label} has duplicate JSON member")
            result[name] = value
        return result
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DisplayError(f"{label} is not valid UTF-8 JSON") from error
    require(type(value) is dict, f"{label} must be an object")
    return value


def _record(value: object, label: str) -> tuple[Path, dict[str, object]]:
    require(type(value) is dict and set(value) == PIN_FIELDS, f"{label} record fields differ")
    path = _absolute(value["path"], f"{label}.path")
    require(type(value["bytes"]) is int and value["bytes"] > 0, f"{label}.bytes differs")
    digest = _scalar(value["sha256"], f"{label}.sha256")
    require(re.fullmatch(r"[0-9A-F]{64}", digest) is not None, f"{label}.sha256 differs")
    info = _regular(path, label)
    require(info.st_size == value["bytes"] and _sha256(path) == digest, f"{label} identity differs")
    return path.resolve(strict=True), dict(value)


@dataclass(frozen=True)
class ValidatedPlan:
    """Validated fixed-display inputs and paths derived only from role/root."""

    raw: dict[str, object]
    checkout: Path
    role: str
    display: str
    geometry: tuple[int, int]
    root: Path
    deadline_seconds: int
    xtigervnc: Path
    xauth: Path
    probe_display: Path
    socket: Path
    lock: Path
    authority: Path
    runtime: Path
    viewer: Path
    log: Path
    ready: Path
    status: Path
    result: Path


def validate_plan(plan: dict[str, object], checkout: Path | str) -> ValidatedPlan:
    """Validate a no-side-effect display plan.

    The caller must have created an empty direct child of ``checkout/build/p``.
    All output names and both global X paths are derived here rather than being
    supplied by the plan.
    """
    require(type(plan) is dict and set(plan) == PLAN_FIELDS, "display plan fields differ")
    require(type(plan["schema"]) is int and plan["schema"] == 1 and plan["kind"] == PLAN_KIND,
            "display plan schema differs")
    role = _scalar(plan["role"], "role")
    require(role in DISPLAY_BY_ROLE, "display role differs")
    geometry = plan["geometry"]
    require(type(geometry) is list and len(geometry) == 2 and all(type(value) is int for value in geometry),
            "display geometry differs")
    size = (geometry[0], geometry[1])
    require(size in GEOMETRIES, "display geometry is not admitted")
    require(type(plan["deadline_seconds"]) is int and 1 <= plan["deadline_seconds"] <= MAX_DEADLINE_SECONDS,
            "display deadline differs")

    checkout_path = _absolute(str(checkout), "checkout")
    checkout_info = checkout_path.lstat()
    require(stat.S_ISDIR(checkout_info.st_mode) and not checkout_path.is_symlink(), "checkout differs")
    checkout_path = checkout_path.resolve(strict=True)
    output_parent = checkout_path / "build" / "p"
    parent_info = output_parent.lstat()
    require(stat.S_ISDIR(parent_info.st_mode) and not output_parent.is_symlink(), "checkout build/p differs")
    output_parent = output_parent.resolve(strict=True)

    root = _absolute(plan["role_root"], "role_root")
    root_info = root.lstat()
    require(stat.S_ISDIR(root_info.st_mode) and not root.is_symlink(), "role_root differs")
    root = root.resolve(strict=True)
    require(root.parent == output_parent and _under(root, output_parent), "role_root escapes checkout build/p")
    require(not any(root.iterdir()), "role_root must be fresh and empty")

    xtigervnc, _ = _record(plan["xtigervnc"], "Xtigervnc")
    xauth, _ = _record(plan["xauth"], "xauth")
    probe_display, probe_record = _record(plan["probe_display"], "probe_display")
    require(probe_record["sha256"] == PINNED_PROBE_DISPLAY_SHA256,
            "probe_display is not the qualified F2DF helper")
    require(len({xtigervnc, xauth, probe_display}) == 3, "display executable identities overlap")

    number = DISPLAY_BY_ROLE[role][1:]
    socket = Path("/tmp/.X11-unix") / f"X{number}"
    lock = Path(f"/tmp/.X{number}-lock")
    runtime = root / "runtime"
    return ValidatedPlan(
        raw=dict(plan), checkout=checkout_path, role=role, display=DISPLAY_BY_ROLE[role], geometry=size,
        root=root, deadline_seconds=plan["deadline_seconds"], xtigervnc=xtigervnc, xauth=xauth,
        probe_display=probe_display, socket=socket, lock=lock, authority=root / "authority", runtime=runtime,
        viewer=runtime / "viewer.sock", log=root / "display.log", ready=root / "display-ready.json",
        status=root / "display-status.json", result=root / "display-result.json",
    )


def load_bound_plan(path: Path | str, expected_sha256: str, checkout: Path | str) -> ValidatedPlan:
    """Read at most 8 KiB and bind the exact raw plan bytes before validation."""
    plan_path = _absolute(str(path), "plan")
    info = _regular(plan_path, "plan")
    require(0 < info.st_size <= MAX_PLAN_BYTES, "plan size differs")
    digest = _scalar(expected_sha256, "plan SHA-256")
    require(re.fullmatch(r"[0-9A-F]{64}", digest) is not None, "plan SHA-256 differs")
    raw = plan_path.read_bytes()
    require(len(raw) == info.st_size and hashlib.sha256(raw).hexdigest().upper() == digest,
            "raw plan bytes differ")
    return validate_plan(_strict_json(raw, "plan"), checkout)


def _identity(pid: int) -> dict[str, int]:
    text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    closing = text.rfind(")")
    require(closing >= 3 and text.startswith(f"{pid} ("), "display process stat differs")
    fields = text[closing + 1:].split()
    require(len(fields) > 19 and fields[19].isdigit() and fields[3].isdigit(), "display process stat differs")
    return {"pid": pid, "start_ticks": int(fields[19]), "session_id": int(fields[3])}


class SystemBackend:
    """The small injectable operating-system edge used by host controls.

    Tests can provide a fake implementing these methods.  Plan validation uses
    only ordinary file identity reads; execution reaches X/process state solely
    through this boundary and the qualified probe helper.
    """

    def __init__(self, probe_loader=None):
        self._probe_loader = probe_loader
        self._stop_partial = bytearray()

    def now(self) -> float:
        return time.monotonic()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)

    def uid(self) -> int:
        return os.getuid()

    def session(self, pid: int) -> int:
        return os.getsid(pid)

    def process_identity(self, pid: int) -> dict[str, int]:
        return _identity(pid)

    # Tests can map only these execution-time filesystem edges into a private
    # temporary namespace.  Plan validation stays plain read-only identity
    # checking; no test need touch /tmp/.X11-unix to prove preservation.
    def lexists(self, path: Path) -> bool:
        return os.path.lexists(path)

    def lstat(self, path: Path) -> os.stat_result:
        return path.lstat()

    def iterdir(self, path: Path):
        return path.iterdir()

    def mkdir(self, path: Path, mode: int) -> None:
        path.mkdir(mode=mode)

    def unlink(self, path: Path) -> None:
        path.unlink()

    def rename(self, path: Path, destination: Path) -> None:
        path.rename(destination)

    def read_pid_lock(self, path: Path, identity: tuple[int, int], uid: int) -> bytes:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            require(stat.S_ISREG(info.st_mode) and (info.st_dev, info.st_ino) == identity
                    and info.st_uid == uid and 0 < info.st_size <= 32, "display lock changed before read")
            return stream.read(33)

    def rmdir(self, path: Path) -> None:
        path.rmdir()

    def open_exclusive(self, path: Path, mode: int) -> BinaryIO:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        require(hasattr(os, "O_NOFOLLOW"), "safe exclusive file creation is unavailable")
        descriptor = os.open(path, flags | os.O_NOFOLLOW, mode)
        return os.fdopen(descriptor, "wb")

    def sync(self, stream: BinaryIO) -> None:
        stream.flush()
        os.fsync(stream.fileno())

    def spawn(self, argv: list[str], env: dict[str, str], cwd: Path, log: BinaryIO):
        return subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log, env=env, cwd=cwd)

    def poll(self, process) -> Optional[int]:
        return process.poll()

    def terminate(self, process) -> None:
        process.terminate()

    def kill(self, process) -> None:
        process.kill()

    def wait(self, process, timeout: float) -> int:
        return process.wait(timeout=timeout)

    def xauth(self, argv: list[str], authority_input: str) -> int:
        result = subprocess.run(argv, input=authority_input, text=True, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=5, check=False)
        return result.returncode

    def load_probe(self, path: Path, pin: dict[str, object]):
        if self._probe_loader is not None:
            return self._probe_loader(path)
        # Authenticate the exact bytes before evaluating Python code. A later
        # preflight hash check cannot undo import-time effects of a replaced
        # probe at the same pathname.
        info = _regular(path, "qualified display helper")
        require(info.st_size == pin["bytes"], "qualified display helper bytes differ")
        with path.open("rb") as stream:
            raw = stream.read(info.st_size + 1)
        require(len(raw) == info.st_size and hashlib.sha256(raw).hexdigest().upper() == pin["sha256"],
                "qualified display helper identity differs")
        specification = importlib.util.spec_from_file_location("mir_linux_library_display_probe", path)
        require(specification is not None and specification.loader is not None,
                "qualified display helper cannot be imported")
        module = importlib.util.module_from_spec(specification)
        original = sys.dont_write_bytecode
        try:
            sys.dont_write_bytecode = True
            exec(compile(raw, str(path), "exec"), module.__dict__)
        finally:
            sys.dont_write_bytecode = original
        return module

    def stop_signal(self, stdin: BinaryIO, timeout: float) -> Optional[str]:
        """Read at most one finite control frame without waiting for a newline.

        ``select`` only promises at least one byte; ``readline`` could then
        wait past the owner's deadline for an unterminated frame.  Preserve a
        bounded partial frame across polls and let the caller's monotonic
        deadline decide when no complete ``stop`` frame arrives.
        """
        try:
            descriptor = stdin.fileno()
        except (AttributeError, OSError) as error:
            raise DisplayError("owned display stdin is unavailable") from error
        readable, _, _ = select.select([descriptor], [], [], timeout)
        if not readable:
            return None
        try:
            chunk = os.read(descriptor, 128 - len(self._stop_partial))
        except BlockingIOError:
            return None
        if not chunk:
            return "eof" if not self._stop_partial else "invalid"
        self._stop_partial.extend(chunk)
        newline = self._stop_partial.find(b"\n")
        if newline < 0:
            return "invalid" if len(self._stop_partial) >= 128 else None
        complete = bytes(self._stop_partial)
        self._stop_partial.clear()
        if newline != len(complete) - 1:
            return "invalid"
        if complete in (b"stop\n", b"stop\r\n"):
            return "stop"
        return "invalid"


@dataclass
class DisplayState:
    plan: ValidatedPlan
    backend: SystemBackend
    probe: Any
    process: Any
    process_identity: dict[str, int]
    display_binding: dict[str, object]
    viewer_binding: dict[str, object]
    authority_identity: tuple[int, int]
    log: BinaryIO


def _write_exclusive_json(backend: SystemBackend, path: Path, value: dict[str, object]) -> None:
    raw = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    require(len(raw) <= MAX_RECORD_BYTES, "display receipt exceeds its bounded size")
    with backend.open_exclusive(path, 0o600) as stream:
        offset = 0
        while offset < len(raw):
            written = stream.write(raw[offset:])
            require(written > 0, "display receipt write failed")
            offset += written
        backend.sync(stream)


def _open_exclusive(backend: SystemBackend, path: Path, mode: int = 0o600) -> BinaryIO:
    return backend.open_exclusive(path, mode)


def _owned_regular(backend: SystemBackend, path: Path, uid: int, mode: int, label: str) -> tuple[int, int]:
    info = backend.lstat(path)
    require(stat.S_ISREG(info.st_mode) and not stat.S_ISLNK(info.st_mode) and info.st_uid == uid
            and stat.S_IMODE(info.st_mode) == mode, f"{label} identity or permissions differ")
    return (info.st_dev, info.st_ino)


def _owned_socket(backend: SystemBackend, path: Path, uid: int, mode: int, label: str) -> tuple[int, int]:
    info = backend.lstat(path)
    require(stat.S_ISSOCK(info.st_mode) and info.st_uid == uid and stat.S_IMODE(info.st_mode) == mode,
            f"{label} identity or permissions differ")
    return (info.st_dev, info.st_ino)


def _owned_directory(backend: SystemBackend, path: Path, uid: int, mode: int, label: str) -> tuple[int, int]:
    info = backend.lstat(path)
    require(stat.S_ISDIR(info.st_mode) and not stat.S_ISLNK(info.st_mode) and info.st_uid == uid
            and stat.S_IMODE(info.st_mode) == mode, f"{label} identity or permissions differ")
    return (info.st_dev, info.st_ino)


def _load_probe(backend: SystemBackend, plan: ValidatedPlan):
    probe = backend.load_probe(plan.probe_display, plan.raw["probe_display"])
    for name in ("PINS", "VIEWER_RELATIVE", "display_binding", "viewer_binding",
                 "no_network_sockets", "listener_inode_present", "unix_listeners"):
        require(hasattr(probe, name), f"qualified display helper lacks {name}")
    require(probe.VIEWER_RELATIVE == "runtime/viewer.sock", "qualified display helper viewer path differs")
    return probe


def _preflight_execution(plan: ValidatedPlan, backend: SystemBackend, probe) -> None:
    require(sys.platform == "linux", "Linux private display execution required")
    _recheck_pins(plan)
    require(probe.PINS.get(str(plan.xtigervnc)) == plan.raw["xtigervnc"]["sha256"],
            "qualified display helper Xtigervnc pin differs")
    require(probe.PINS.get(str(plan.xauth)) == plan.raw["xauth"]["sha256"],
            "qualified display helper xauth pin differs")
    # Global host idleness, resource admission, campaign ownership, and any
    # finite peer display receipt belong to the governed parent.  This leaf
    # owns exactly one derived role display, so it must not reject a valid
    # already-admitted :193 while the parent starts the independent :194.
    shared = Path("/tmp/.X11-unix")
    shared_info = backend.lstat(shared)
    require(stat.S_ISDIR(shared_info.st_mode) and not stat.S_ISLNK(shared_info.st_mode) and shared_info.st_uid == 0
            and stat.S_IMODE(shared_info.st_mode) == 0o1777, "expected root-owned X socket directory differs")
    require(not backend.lexists(plan.socket) and not backend.lexists(plan.lock)
            and not probe.unix_listeners({str(plan.socket), "@" + str(plan.socket)}),
            "preserve existing X display/lock")
    require(not any(backend.iterdir(plan.root)), "role_root changed before display startup")


def _recheck_pins(plan: ValidatedPlan) -> None:
    for record, path, label in ((plan.raw["xtigervnc"], plan.xtigervnc, "Xtigervnc"),
                                (plan.raw["xauth"], plan.xauth, "xauth"),
                                (plan.raw["probe_display"], plan.probe_display, "probe_display")):
        _, verified = _record(record, label)
        require(path == _absolute(verified["path"], label + ".path").resolve(strict=True),
                f"{label} changed after plan validation")


def _server_argv(plan: ValidatedPlan, probe) -> list[str]:
    width, height = plan.geometry
    return [str(plan.xtigervnc), plan.display, "-geometry", f"{width}x{height}", "-depth", "24",
            "-noreset", "-extension", "MIT-SHM", "-rfbport", "-1", "-nolisten", "tcp",
            "-rfbunixpath", probe.VIEWER_RELATIVE, "-rfbunixmode", "384", "-auth", str(plan.authority)]


def start_display(plan: ValidatedPlan, backend: Optional[SystemBackend] = None) -> DisplayState:
    """Start exactly the admitted display and publish a no-secret ready receipt."""
    backend = backend or SystemBackend()
    probe = _load_probe(backend, plan)
    uid: Optional[int] = None
    process = None
    identity: Optional[dict[str, int]] = None
    authority_identity: Optional[tuple[int, int]] = None
    viewer_identity: Optional[tuple[int, int]] = None
    runtime_identity: Optional[tuple[int, int]] = None
    log_identity: Optional[tuple[int, int]] = None
    log: Optional[BinaryIO] = None
    output_started = False
    cookie: Optional[str] = None
    try:
        _preflight_execution(plan, backend, probe)
        uid = backend.uid()
        output_started = True
        with _open_exclusive(backend, plan.authority) as authority_file:
            backend.sync(authority_file)
        authority_identity = _owned_regular(backend, plan.authority, uid, 0o600, "owned X authority")
        # The cookie intentionally remains only in the xauth stdin payload.  It
        # is absent from argv, display.log, and every durable receipt.
        cookie = os.urandom(16).hex()
        xauth_argv = [str(plan.xauth), "-f", str(plan.authority), "source", "-"]
        require(backend.xauth(xauth_argv, f"add {plan.display} MIT-MAGIC-COOKIE-1 {cookie}\n") == 0,
                "owned X authority preparation failed")
        authority_identity = _owned_regular(backend, plan.authority, uid, 0o600, "owned X authority")
        backend.mkdir(plan.runtime, 0o700)
        runtime_identity = _owned_directory(backend, plan.runtime, uid, 0o700, "private runtime directory")
        log = _open_exclusive(backend, plan.log)
        log_identity = _owned_regular(backend, plan.log, uid, 0o600, "owned display log")
        # This boundary starts no graphical client.  Do not inherit the full
        # renderer's cache/config environment or manufacture unrelated role
        # root outputs: only the private display and authority are added.
        env = dict(os.environ, DISPLAY=plan.display, XAUTHORITY=str(plan.authority))
        process = backend.spawn(_server_argv(plan, probe), env, plan.root, log)
        identity = backend.process_identity(process.pid)
        require(identity["pid"] == process.pid and identity["session_id"] == backend.session(os.getpid()),
                "display left the governed caller session")
        deadline = backend.now() + min(8, plan.deadline_seconds)
        while not (backend.lexists(plan.socket) and backend.lexists(plan.lock) and backend.lexists(plan.viewer)):
            require(backend.poll(process) is None, "owned display exited before readiness")
            require(backend.now() < deadline, "owned display readiness timed out")
            backend.sleep(0.05)
        require(backend.process_identity(process.pid) == identity, "display process identity changed before readiness")
        viewer_identity = _owned_socket(backend, plan.viewer, uid, 0o600, "private viewer socket")
        display_binding = probe.display_binding(process, plan.socket, plan.lock)
        viewer_binding = probe.viewer_binding(process, plan.viewer)
        require(tuple(viewer_binding["device_inode"]) == viewer_identity, "private viewer binding identity differs")
        probe.no_network_sockets(process.pid)
        ready = {
            "kind": READY_KIND, "role": plan.role, "display": plan.display,
            "geometry": list(plan.geometry), "display_identity": identity,
            "display_binding": display_binding, "viewer_binding": viewer_binding,
            "authority_device_inode": list(authority_identity), "factorio_processes": 0,
        }
        _write_exclusive_json(backend, plan.ready, ready)
        _write_exclusive_json(backend, plan.status, {"kind": RESULT_KIND, "status": "ready", "role": plan.role,
                                                      "display": plan.display, "factorio_processes": 0})
        require(authority_identity is not None, "authority identity was not retained")
        return DisplayState(plan, backend, probe, process, identity, display_binding, viewer_binding,
                            authority_identity, log)
    except Exception as original_error:
        cleanup_errors: list[str] = []
        if log is not None:
            try:
                log.close()
            except OSError:
                cleanup_errors.append("unable to close owned display log")
        if process is not None:
            try:
                if identity is not None and backend.poll(process) is None \
                        and backend.process_identity(process.pid) == identity:
                    backend.terminate(process)
                    try:
                        backend.wait(process, 5)
                    except subprocess.TimeoutExpired:
                        require(backend.poll(process) is None and backend.process_identity(process.pid) == identity,
                                "owned display process identity changed before forced startup cleanup")
                        backend.kill(process)
                        backend.wait(process, 5)
            except Exception as cleanup_error:
                cleanup_errors.append(_safe_error(cleanup_error, cookie)[:256])
        if process is not None:
            try:
                if backend.lexists(plan.socket) or backend.lexists(plan.lock) \
                        or probe.unix_listeners({str(plan.socket), "@" + str(plan.socket)}):
                    cleanup_errors.append("display socket or lock remains after failed startup")
            except Exception as cleanup_error:
                cleanup_errors.append(_safe_error(cleanup_error, cookie)[:256])
        # A failed startup must not retain credentials or a private listener.
        # The global X socket/lock are always left to the server itself; we
        # remove only role-root objects still carrying our exact identities.
        try:
            if uid is not None and viewer_identity is not None:
                _remove_owned(backend, plan.viewer, viewer_identity, stat.S_ISSOCK, uid,
                              "private viewer socket", cleanup_errors)
        except Exception as cleanup_error:
            cleanup_errors.append(_safe_error(cleanup_error, cookie)[:256])
        try:
            if uid is not None and authority_identity is not None:
                _remove_owned(backend, plan.authority, authority_identity, stat.S_ISREG, uid,
                              "X authority", cleanup_errors)
        except Exception as cleanup_error:
            cleanup_errors.append(_safe_error(cleanup_error, cookie)[:256])
        try:
            if uid is not None and log_identity is not None:
                _remove_owned(backend, plan.log, log_identity, stat.S_ISREG, uid,
                              "display log", cleanup_errors)
        except Exception as cleanup_error:
            cleanup_errors.append(_safe_error(cleanup_error, cookie)[:256])
        try:
            if uid is not None and runtime_identity is not None:
                info = backend.lstat(plan.runtime)
                if ((info.st_dev, info.st_ino) != runtime_identity or not stat.S_ISDIR(info.st_mode)
                        or info.st_uid != uid):
                    cleanup_errors.append("preserved changed private runtime directory")
                elif any(backend.iterdir(plan.runtime)):
                    cleanup_errors.append("private runtime directory remains nonempty")
                else:
                    backend.rmdir(plan.runtime)
        except FileNotFoundError:
            pass
        except Exception as cleanup_error:
            cleanup_errors.append(_safe_error(cleanup_error, cookie)[:256])
        message = _safe_error(original_error, cookie)[:384]
        if cleanup_errors:
            message += "; cleanup: " + "; ".join(cleanup_errors)[:384]
        raise DisplayStartError(message, output_started) from original_error


def _remove_owned(backend: SystemBackend, path: Path, identity: tuple[int, int], expected_type: int, uid: int, label: str,
                  cleanup_errors: list[str]) -> bool:
    if not backend.lexists(path):
        return True
    try:
        info = backend.lstat(path)
        if ((info.st_dev, info.st_ino) != identity or not expected_type(info.st_mode)
                or info.st_uid != uid):
            cleanup_errors.append(f"preserved changed {label}")
            return False
        backend.unlink(path)
        return True
    except OSError:
        cleanup_errors.append(f"unable to remove owned {label}")
        return False


def recover_display(plan: ValidatedPlan, ready_sha256: str, backend: Optional[SystemBackend] = None) -> dict[str, object]:
    """After the owner exits, retain only its exact abandoned global X11 entries."""
    require(sys.platform == "linux", "Linux private display recovery required")
    backend = backend or SystemBackend()
    info = _regular(plan.ready, "display-ready receipt")
    require(0 < info.st_size <= MAX_RECORD_BYTES, "display-ready size differs")
    with plan.ready.open("rb") as stream:
        body = stream.read(MAX_RECORD_BYTES + 1)
    require(len(body) == info.st_size and hashlib.sha256(body).hexdigest().upper() == ready_sha256,
            "display-ready receipt changed")
    ready = _strict_json(body, "display-ready receipt")
    require(ready.get("kind") == READY_KIND and ready.get("role") == plan.role
            and ready.get("display") == plan.display and ready.get("geometry") == list(plan.geometry),
            "display-ready receipt does not own the planned display")
    identity, binding = ready.get("display_identity"), ready.get("display_binding")
    require(type(identity) is dict and type(binding) is dict, "display-ready identity differs")
    uid, pid = backend.uid(), identity.get("pid")
    require(all(type(identity.get(key)) is int and identity[key] > 0 for key in ("pid", "start_ticks", "session_id"))
            and type(binding.get("uid")) is int and binding["uid"] == uid and binding.get("pid") == pid,
            "display-ready process ownership differs")
    _recheck_pins(plan)
    probe = _load_probe(backend, plan)
    _owned_directory(backend, Path("/tmp/.X11-unix"), 0, 0o1777, "shared X socket directory")
    addresses = {str(plan.socket), "@" + str(plan.socket)}

    def require_inactive():
        try:
            backend.process_identity(pid)
        except (FileNotFoundError, ProcessLookupError):
            pass
        else:
            raise DisplayError("preserve existing display process")
        require(not probe.unix_listeners(addresses), "preserve existing X listener")

    def check_owned(path, expected, kind):
        observed = backend.lstat(path)
        require(kind(observed.st_mode) and (observed.st_dev, observed.st_ino) == expected
                and observed.st_uid == uid, "preserve changed display socket or lock")

    require_inactive()
    destination = plan.lock.parent / f".mir-retained-display-{uid}-{ready_sha256.lower()}"
    if backend.lexists(destination):
        _owned_directory(backend, destination, uid, 0o700, "display recovery directory")
    members = []
    for path, key, kind in ((plan.lock, "lock_device_inode", stat.S_ISREG),
                            (plan.socket, "socket_device_inode", stat.S_ISSOCK)):
        known = binding.get(key)
        require(type(known) is list and len(known) == 2 and all(type(value) is int and value >= 0 for value in known),
                "display-ready filesystem identity differs")
        expected = tuple(known)
        retained = destination / path.name
        if backend.lexists(retained):
            check_owned(retained, expected, kind)
            require(not backend.lexists(path), "display binding has multiple paths")
        if backend.lexists(path):
            check_owned(path, expected, kind)
            if path == plan.lock:
                require(backend.read_pid_lock(path, expected, uid).strip() == str(pid).encode("ascii"),
                        "display lock no longer records its owned PID")
            members.append((path, retained, expected, kind))
    if members and not backend.lexists(destination):
        backend.mkdir(destination, 0o700)
    if backend.lexists(destination):
        _owned_directory(backend, destination, uid, 0o700, "display recovery directory")
    for path, retained, expected, kind in members:
        require_inactive()
        check_owned(path, expected, kind)
        require(not backend.lexists(retained), "display recovery destination already exists")
        backend.rename(path, retained)
        check_owned(retained, expected, kind)
    require_inactive()
    require(not backend.lexists(plan.lock) and not backend.lexists(plan.socket), "display recovery remains incomplete")
    return {"kind": RESULT_KIND, "status": "recovered" if backend.lexists(destination) else "already-clear",
            "role": plan.role, "display": plan.display, "ready_sha256": ready_sha256,
            "retained_path": str(destination) if backend.lexists(destination) else None, "factorio_processes": 0}


def stop_display(state: DisplayState, reason: str, error: Optional[str] = None) -> dict[str, object]:
    """Stop only an identity-matching display and remove only owned files."""
    require(reason in {"stop", "eof", "deadline", "failed"}, "display stop reason differs")
    plan, backend, probe, process = state.plan, state.backend, state.probe, state.process
    cleanup_errors: list[str] = []
    uid = backend.uid()
    result: dict[str, object] = {
        "kind": RESULT_KIND, "status": reason, "role": plan.role, "display": plan.display,
        "geometry": list(plan.geometry), "display_identity": state.process_identity,
        "factorio_processes": 0, "cleanup_errors": cleanup_errors,
    }
    if error is not None:
        result["error"] = _safe_error(error)
    process_stopped = False
    try:
        _recheck_pins(plan)
        result["pins_rechecked"] = True
    except Exception as cleanup_error:
        result["pins_rechecked"] = False
        cleanup_errors.append(_safe_error(cleanup_error)[:256])
    if backend.poll(process) is None:
        exact_process = False
        try:
            exact_process = backend.process_identity(process.pid) == state.process_identity
            require(exact_process, "owned display process identity changed before cleanup")
        except Exception as cleanup_error:
            cleanup_errors.append(_safe_error(cleanup_error)[:256])
        if exact_process:
            try:
                if probe.display_binding(process, plan.socket, plan.lock) != state.display_binding:
                    cleanup_errors.append("display binding changed before cleanup")
                if probe.viewer_binding(process, plan.viewer) != state.viewer_binding:
                    cleanup_errors.append("private viewer binding changed before cleanup")
                probe.no_network_sockets(process.pid)
            except Exception as cleanup_error:
                cleanup_errors.append(_safe_error(cleanup_error)[:256])
            try:
                backend.terminate(process)
                try:
                    backend.wait(process, 5)
                except subprocess.TimeoutExpired:
                    require(backend.poll(process) is None
                            and backend.process_identity(process.pid) == state.process_identity,
                            "owned display process identity changed before forced cleanup")
                    backend.kill(process)
                    backend.wait(process, 5)
                    cleanup_errors.append("display required forced cleanup")
            except Exception as cleanup_error:
                cleanup_errors.append(_safe_error(cleanup_error)[:256])
    elif reason in {"stop", "eof"}:
        cleanup_errors.append("display exited before requested teardown")
    process_stopped = backend.poll(process) is not None
    if not process_stopped:
        cleanup_errors.append("owned display remains live after cleanup")
    result["display_exit"] = getattr(process, "returncode", None)
    try:
        state.log.close()
    except OSError:
        cleanup_errors.append("unable to close owned display log")
    try:
        sockets_clear = (not backend.lexists(plan.socket) and not backend.lexists(plan.lock)
                         and not probe.unix_listeners({str(plan.socket), "@" + str(plan.socket)}))
        result["global_display_restored"] = sockets_clear
        if not sockets_clear:
            cleanup_errors.append("display socket or lock remains; preserved foreign/global state")
    except Exception as cleanup_error:
        result["global_display_restored"] = False
        cleanup_errors.append(str(cleanup_error)[:256])
    viewer_identity = tuple(state.viewer_binding["device_inode"])
    viewer_removed = process_stopped and _remove_owned(backend, plan.viewer, viewer_identity, stat.S_ISSOCK, uid,
                                                        "private viewer socket", cleanup_errors)
    try:
        viewer_listener = state.viewer_binding["listener"][1]
        viewer_clear = viewer_removed and not backend.lexists(plan.viewer) and not probe.listener_inode_present(viewer_listener)
    except Exception as cleanup_error:
        viewer_clear = False
        cleanup_errors.append(str(cleanup_error)[:256])
    result["private_viewer_restored"] = viewer_clear
    if not viewer_clear:
        cleanup_errors.append("private viewer socket remains")
    authority_removed = process_stopped and _remove_owned(backend, plan.authority, state.authority_identity,
                                                           stat.S_ISREG, uid, "X authority", cleanup_errors)
    result["authority_removed"] = authority_removed and not backend.lexists(plan.authority)
    if not result["authority_removed"]:
        cleanup_errors.append("owned X authority remains")
    if cleanup_errors:
        result["status"] = "failed-cleanup"
    return result


def run_display(plan: ValidatedPlan, backend: Optional[SystemBackend] = None, stdin: Optional[BinaryIO] = None) -> dict[str, object]:
    """Run the display until exactly caller stdin stop/EOF or the bounded deadline."""
    backend = backend or SystemBackend()
    stream = stdin if stdin is not None else sys.stdin.buffer
    state: Optional[DisplayState] = None
    reason, failure = "failed", None
    startup_output = False
    try:
        state = start_display(plan, backend)
        deadline = backend.now() + plan.deadline_seconds
        while True:
            remaining = deadline - backend.now()
            if remaining <= 0:
                reason = "deadline"
                break
            signal_value = backend.stop_signal(stream, min(0.25, remaining))
            if signal_value in ("stop", "eof"):
                reason = signal_value
                break
            require(signal_value is None, "unexpected display stdin control")
            require(backend.poll(state.process) is None
                    and backend.process_identity(state.process.pid) == state.process_identity,
                    "owned display changed while waiting for caller stop")
            require(state.probe.display_binding(state.process, plan.socket, plan.lock) == state.display_binding,
                    "display binding changed while waiting for caller stop")
            require(state.probe.viewer_binding(state.process, plan.viewer) == state.viewer_binding,
                    "private viewer binding changed while waiting for caller stop")
            state.probe.no_network_sockets(state.process.pid)
    except Exception as exc:
        failure = str(exc)
        startup_output = isinstance(exc, DisplayStartError) and exc.output_started
    if state is None:
        if not startup_output:
            raise DisplayError(failure or "display did not start")
        result = {"kind": RESULT_KIND, "status": "failed", "role": plan.role, "display": plan.display,
                  "geometry": list(plan.geometry), "factorio_processes": 0,
                  "error": (failure or "display did not start")[:512]}
    else:
        result = stop_display(state, reason, failure)
    _write_exclusive_json(backend, plan.result, result)
    return result


def main(argv: Optional[list[str]] = None) -> int:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("schema", "execute", "recover"), required=True)
    parser.add_argument("--checkout", required=True)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--plan-sha256", required=True)
    parser.add_argument("--ready-sha256")
    args = parser.parse_args(argv)
    receipt: dict[str, object] = {"kind": RESULT_KIND, "status": "refused", "factorio_processes": 0}
    try:
        validated = load_bound_plan(args.plan, args.plan_sha256, args.checkout)
        receipt.update(role=validated.role, display=validated.display, geometry=list(validated.geometry))
        require((args.mode == "recover") == (args.ready_sha256 is not None), "ready hash is required only for recovery")
        if args.mode == "schema":
            receipt["status"] = "validated-schema-only"
            print(json.dumps(receipt, sort_keys=True))
            return 0
        receipt = recover_display(validated, args.ready_sha256) if args.mode == "recover" else run_display(validated)
        print(json.dumps(receipt, sort_keys=True))
        return 0 if receipt["status"] in {"stop", "eof", "recovered", "already-clear"} else 1
    except Exception as exc:
        receipt["error"] = str(exc)[:512]
        print(json.dumps(receipt, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
