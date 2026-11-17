"""Raw-peer controls for the bounded loopback RCON helper; no Factorio is launched."""
import hashlib
import json
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "tools/lib/validation/LoopbackRcon.ps1"
SESSION = ROOT / "tools/Invoke-MultiplayerSession.ps1"


def packet(request_id, packet_type, payload, terminator=b"\0\0"):
    body = struct.pack("<ii", request_id, packet_type) + payload + terminator
    return struct.pack("<i", len(body)) + body


def receive_exact(connection, count):
    data = bytearray()
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise AssertionError("peer received truncated client frame")
        data.extend(chunk)
    return bytes(data)


def receive_packet(connection):
    length = struct.unpack("<i", receive_exact(connection, 4))[0]
    if not 10 <= length <= 65536:
        raise AssertionError(f"client frame length differs: {length}")
    body = receive_exact(connection, length)
    if body[-2:] != b"\0\0":
        raise AssertionError("client terminators differ")
    request_id, packet_type = struct.unpack("<ii", body[:8])
    return request_id, packet_type, body[8:-2]


class RawRconPeer:
    def __init__(self, handler):
        self._listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._listener.bind(("127.0.0.1", 0))
        self._listener.listen(1)
        self._listener.settimeout(10)
        self.port = self._listener.getsockname()[1]
        self.handler = handler
        self.error = None
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def _serve(self):
        try:
            connection, _ = self._listener.accept()
            with connection:
                connection.settimeout(10)
                self.handler(connection)
        except ConnectionResetError:
            # Refusal paths may close immediately after the intentionally bad
            # peer frame; the test has already checked the preceding wire row.
            pass
        except Exception as error:  # surfaced to the independent test process
            self.error = error
        finally:
            self._listener.close()

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc, trace):
        self.thread.join(12)
        if self.thread.is_alive():
            raise AssertionError("raw RCON peer did not terminate")
        if self.error:
            raise self.error


def authenticate(connection, password, optional_text_frame=False, extra_text_frame=False, bad_id=False):
    request_id, packet_type, payload = receive_packet(connection)
    if request_id != 43101 or packet_type != 3 or payload != password.encode("utf-8"):
        raise AssertionError("authentication request differs")
    response_id = request_id + 1 if bad_id else request_id
    if optional_text_frame:
        connection.sendall(packet(response_id, 0, b""))
    if extra_text_frame:
        connection.sendall(packet(response_id, 0, b""))
    connection.sendall(packet(response_id, 2, b""))


def command_handler(password, expected_commands, mode="success"):
    def handler(connection):
        authenticate(connection, password, optional_text_frame=True, extra_text_frame=mode == "auth-extra-text",
                     bad_id=mode == "auth-wrong-id")
        if mode in {"auth-wrong-id", "auth-extra-text"}:
            return
        for index, expected in enumerate(expected_commands, start=43102):
            request_id, packet_type, payload = receive_packet(connection)
            if request_id != index or packet_type != 2 or payload != expected.encode("utf-8"):
                raise AssertionError("command frame differs")
            if mode == "wrong-id":
                connection.sendall(packet(request_id + 1, 0, b"wrong"))
            elif mode == "wrong-type":
                connection.sendall(packet(request_id, 2, b"wrong"))
            elif mode == "bad-terminator":
                connection.sendall(packet(request_id, 0, b"wrong", b"\x01\0"))
            elif mode == "bad-length":
                connection.sendall(struct.pack("<i", 9) + b"short-body")
            elif mode == "invalid-utf8":
                connection.sendall(packet(request_id, 0, b"\xff"))
            elif mode == "truncated":
                full = packet(request_id, 0, b"truncated")
                connection.sendall(full[:-3])
                return
            else:
                connection.sendall(packet(request_id, 0, f"reply-{index}".encode("utf-8")))
    return handler


def run_helper(port, password, commands):
    script = r'''
param([string]$Helper,[int]$Port,[string]$Password,[string]$CommandsJson)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. $Helper
try {
  $commands=@($CommandsJson|ConvertFrom-Json -AsHashtable)
  $receipt=Invoke-MIRLoopbackRconCommands -Port $Port -Password $Password -Commands $commands
  [pscustomobject]@{ok=$true;receipt=$receipt}|ConvertTo-Json -Depth 12 -Compress
} catch {
  [pscustomobject]@{ok=$false;message=$_.Exception.Message;has_cleanup=$_.Exception.Data.Contains('mir_loopback_rcon_cleanup_facts');cleanup_facts=$_.Exception.Data['mir_loopback_rcon_cleanup_facts'];receipt=$_.Exception.Data['mir_loopback_rcon_receipt']}|ConvertTo-Json -Depth 12 -Compress
}
'''
    with tempfile.TemporaryDirectory() as temporary:
        runner = Path(temporary) / "loopback-rcon-runner.ps1"
        runner.write_text(script, encoding="utf-8")
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-File", str(runner), "-Helper", str(HELPER), "-Port", str(port),
             "-Password", password, "-CommandsJson", json.dumps(commands, ensure_ascii=False)],
            cwd=ROOT, capture_output=True, text=True, timeout=20,
        )
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return json.loads(result.stdout), result


class LoopbackRconTests(unittest.TestCase):
    def test_refused_connect_retains_open_cleanup_facts(self):
        reservation = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        reservation.bind(("127.0.0.1", 0))
        refused_port = reservation.getsockname()[1]
        reservation.close()

        payload, raw = run_helper(refused_port, "generic-nonempty-password", ["/silent-command noop"])
        self.assertFalse(payload["ok"])
        self.assertTrue(payload["has_cleanup"])
        self.assertIsNone(payload["receipt"])
        self.assertEqual(
            [(row["step"], row["attempted"], row["succeeded"]) for row in payload["cleanup_facts"]],
            [("stream-dispose", False, True), ("tcp-dispose", True, True)],
        )
        self.assertNotIn("generic-nonempty-password", raw.stdout + raw.stderr)

    def test_legacy_two_kicks_keep_ids_and_never_echo_password(self):
        password = str(uuid.uuid4())
        expected = ["/kick MIR5English MIR5-rejoin-test", "/kick MIR5Deutsch MIR5-rejoin-test"]
        with RawRconPeer(command_handler(password, expected)) as peer:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-File", str(SESSION), "-RconSelfCheck", "-RconCheckPort", str(peer.port),
                 "-RconCheckPassword", password], cwd=ROOT, capture_output=True, text=True, timeout=20,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn(password, result.stdout + result.stderr)
        self.assertIn("passed-nonnative-rcon-self-check", result.stdout)
        self.assertRegex(result.stdout, r"\s2\s*$")

    def test_single_query_preserves_strict_utf8_response_and_safe_receipt(self):
        password = "generic-\nnonempty-password"
        command = "/silent-command rcon.print('MIR_ß')"
        with RawRconPeer(command_handler(password, [command])) as peer:
            payload, raw = run_helper(peer.port, password, [command])
        self.assertTrue(payload["ok"])
        receipt = payload["receipt"]
        self.assertTrue(receipt["loopback_only"])
        self.assertTrue(receipt["closed"])
        self.assertEqual([(fact["step"], fact["succeeded"]) for fact in receipt["cleanup_facts"]],
                         [("stream-dispose", True), ("tcp-dispose", True)])
        self.assertEqual(receipt["authentication_request_id"], 43101)
        self.assertEqual([(row["id"], row["type"]) for row in receipt["auth_frames"]], [(43101, 0), (43101, 2)])
        self.assertEqual(receipt["command_attempts"], 1)
        row = receipt["commands"][0]
        self.assertEqual((row["request_id"], row["command_bytes"], row["complete"]), (43102, len(command.encode("utf-8")), True))
        self.assertEqual(row["response"], {"id": 43102, "type": 0,
                                           "payload_base64": "cmVwbHktNDMxMDI=", "payload_byte_length": 11,
                                           "payload_text": "reply-43102",
                                           "payload_sha256": hashlib.sha256(b"reply-43102").hexdigest().upper()})
        self.assertLessEqual(row["write_monotonic_milliseconds"], row["response_monotonic_milliseconds"])
        self.assertNotIn(password, raw.stdout + raw.stderr)
        self.assertNotIn(command, raw.stdout + raw.stderr)

    def test_raw_peer_refusals_are_fail_closed(self):
        password = "generic-nonempty-password"
        command = "/silent-command rcon.print('MIR')"
        for mode, expected in (("auth-wrong-id", "authentication response differs"), ("auth-extra-text", "authentication response differs"),
                               ("wrong-id", "command response differs"),
                               ("wrong-type", "command response differs"), ("bad-terminator", "packet terminators are invalid"),
                               ("bad-length", "packet length is invalid"), ("invalid-utf8", "response payload is not strict UTF-8"),
                               ("truncated", "connection closed during packet read")):
            with self.subTest(mode=mode), RawRconPeer(command_handler(password, [command], mode)) as peer:
                payload, raw = run_helper(peer.port, password, [command])
            self.assertFalse(payload["ok"])
            self.assertIn(expected, payload["message"])
            self.assertNotIn(password, raw.stdout + raw.stderr)
            self.assertTrue(payload["has_cleanup"])
            if mode not in {"auth-wrong-id", "auth-extra-text"}:
                self.assertEqual(payload["receipt"]["command_attempts"], 1)
                self.assertFalse(payload["receipt"]["commands"][0]["complete"])
            if mode in {"wrong-id", "wrong-type"}:
                response = payload["receipt"]["commands"][0]["response"]
                self.assertEqual(response["payload_base64"], "d3Jvbmc=")
                self.assertEqual(response["payload_text"], "wrong")
                self.assertEqual(response["id"], 43103 if mode == "wrong-id" else 43102)
                self.assertEqual(response["type"], 0 if mode == "wrong-id" else 2)

    def test_bounds_and_one_line_rejections_happen_before_network(self):
        password = "generic-nonempty-password"
        cases = [([], "command count is invalid"), (["one", "two", "three"], "command count is invalid"),
                 (["line\nbreak"], "command is not one line"), (["x" * 16385], "command exceeds byte bound")]
        for commands, expected in cases:
            with self.subTest(commands=commands):
                payload, raw = run_helper(1, password, commands)
                self.assertFalse(payload["ok"])
                self.assertIn(expected, payload["message"])
                self.assertNotIn(password, raw.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
