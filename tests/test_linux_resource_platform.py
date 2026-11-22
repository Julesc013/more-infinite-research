from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "tools" / "lib" / "validation" / "LinuxResourceObservation.py"
LAUNCHER = ROOT / "tools" / "lib" / "validation" / "LinuxNativeLaunch.py"


def load_observation_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


OBSERVATION = load_observation_module("mir_linux_resource_observation", HELPER)


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def cgroup_files(path: Path, *, current: int, maximum: str, high: str) -> None:
    write(path / "memory.current", f"{current}\n")
    write(path / "memory.max", f"{maximum}\n")
    write(path / "memory.high", f"{high}\n")
    events = "low 0\nhigh 0\nmax 0\noom 0\noom_kill 0\noom_group_kill 0\n"
    write(path / "memory.events", events)
    write(path / "memory.events.local", events)
    write(
        path / "memory.pressure",
        "some avg10=0.00 avg60=0.00 avg300=0.00 total=0\n"
        "full avg10=0.00 avg60=0.00 avg300=0.00 total=0\n",
    )


def proc_stat(pid: int, ppid: int, start: int, session: int = 1, *, state: str = "S", flags: int = 0) -> str:
    # Fields after the final ')' start at procfs field 3.  starttime is field 22.
    fields = ["S", str(ppid), "0", str(session)] + ["0"] * 15 + [str(start)]
    fields[0], fields[6] = state, str(flags)  # procfs state field3 and flags field9.
    return f"{pid} (owned worker {pid}) {' '.join(fields)}\n"


def process_files(proc: Path, pid: int, ppid: int, start: int, children: dict[int, str], session: int = 1) -> None:
    write(proc / str(pid) / "stat", proc_stat(pid, ppid, start, session))
    write(proc / str(pid) / "status", "Name:\towned\nVmRSS:\t12 kB\n")
    write(
        proc / str(pid) / "smaps_rollup",
        "Private_Clean:        2 kB\nPrivate_Dirty:        3 kB\n"
        "Private_Hugetlb:      0 kB\nSwap:                 5 kB\n",
    )
    for tid, listed in children.items():
        write(proc / str(pid) / "task" / str(tid) / "children", listed)


class LinuxResourcePlatformTests(unittest.TestCase):
    def make_fixture(self) -> tuple[Path, Path]:
        temporary = Path(tempfile.mkdtemp(prefix="mir-linux-resource-platform-"))
        proc = temporary / "proc"
        cgroup = temporary / "cgroup"
        write(proc / "meminfo", "MemTotal:       8192 kB\nMemAvailable:  4096 kB\nCommitted_AS: 999999 kB\n")
        write(proc / "self" / "cgroup", "0::/leaf/work\n")
        write(
            proc / "self" / "mountinfo",
            "35 25 8:1 / / rw,relatime - ext4 /dev/test rw\n"
            "36 35 8:1 / /work rw,relatime - ext4 /dev/test rw\n"
            f"40 31 0:44 / {cgroup.as_posix()} rw,nosuid,nodev - cgroup2 cgroup rw\n",
        )
        cgroup_files(cgroup, current=100, maximum="max", high="max")
        cgroup_files(cgroup / "leaf", current=200, maximum="9000", high="max")
        cgroup_files(cgroup / "leaf" / "work", current=300, maximum="5000", high="1000")
        return temporary, proc

    def run_helper(self, *arguments: str) -> tuple[int, dict[str, object]]:
        completed = subprocess.run(
            [sys.executable, str(HELPER), *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual("", completed.stderr)
        return completed.returncode, json.loads(completed.stdout)

    @staticmethod
    def run_session_race(module, *, initial_root, scan_rows, root_after_scan):
        child = {"pid": 101, "ppid": 1, "start_ticks": 1001, "session_id": 100}
        root_reads = [initial_root, root_after_scan]

        def read_stat(_proc_root, pid, *, missing_is_exit):
            assert missing_is_exit
            if pid == 100:
                return root_reads.pop(0)
            if pid == 101:
                return child
            raise AssertionError(f"unexpected pid {pid}")

        with (
            mock.patch.object(module, "read_proc_stat", side_effect=read_stat),
            mock.patch.object(module, "iter_proc_stats", return_value=scan_rows),
            mock.patch.object(module, "read_status_rss", return_value=12 * 1024),
            mock.patch.object(module, "read_private_memory", return_value=(5 * 1024, 5 * 1024)),
        ):
            return module.process_tree(Path("/synthetic/proc"), 100, 1000, 100)

    def test_snapshot_reads_memavailable_and_every_cgroup_v2_ancestor(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: __import__("shutil").rmtree(temporary, ignore_errors=True))
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(0, status)
        self.assertTrue(payload["ok"])
        value = payload["value"]
        self.assertEqual(8192 * 1024, value["memory"]["total_bytes"])
        self.assertEqual(4096 * 1024, value["memory"]["available_bytes"])
        self.assertNotIn("Committed_AS", json.dumps(value, sort_keys=True))
        cgroup = value["cgroup_v2"]
        self.assertEqual("v2", cgroup["version"])
        self.assertEqual(700, cgroup["effective_headroom_bytes"])
        self.assertEqual(["/leaf/work", "/leaf", "/"], [row["relative_path"] for row in cgroup["ancestors"]])
        leaf = cgroup["ancestors"][0]
        self.assertEqual(4700, leaf["max_headroom_bytes"])
        self.assertEqual(700, leaf["high_headroom_bytes"])
        self.assertEqual({"some", "full"}, set(leaf["pressure"]))
        self.assertEqual(0, leaf["events_local"]["oom_kill"])

    def test_mount_identity_uses_the_longest_case_sensitive_mount_boundary(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        write(
            proc / "self" / "mountinfo",
            "35 25 8:1 / / rw,relatime - ext4 /dev/test rw\n"
            "36 35 8:1 / /work rw,relatime - ext4 /dev/test rw\n",
        )
        status, payload = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "/work/future/output")
        self.assertEqual(0, status)
        self.assertEqual({"mount_id": 36, "device": "8:1", "mount_point": "/work", "filesystem_type": "ext4"}, payload["value"])
        status, payload = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "/Work/future/output")
        self.assertEqual(0, status)
        self.assertEqual({"mount_id": 35, "device": "8:1", "mount_point": "/", "filesystem_type": "ext4"}, payload["value"])
        status, payload = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "relative")
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-mount-identity", payload["code"])

    def test_mount_identity_binds_the_underlying_device_not_only_mount_id(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        write(
            proc / "self" / "mountinfo",
            "35 25 8:1 / / rw,relatime - ext4 /dev/root rw\n"
            "36 35 8:1 / /work rw,relatime - ext4 /dev/work rw\n",
        )
        status, root = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "/")
        self.assertEqual(0, status)
        status, bind = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "/work/output")
        self.assertEqual(0, status)
        self.assertNotEqual(root["value"]["mount_id"], bind["value"]["mount_id"])
        self.assertEqual("8:1", root["value"]["device"])
        self.assertEqual(root["value"]["device"], bind["value"]["device"])

        write(
            proc / "self" / "mountinfo",
            "35 25 8:1 / / rw,relatime - ext4 /dev/root rw\n"
            "36 35 8:2 / /work rw,relatime - ext4 /dev/work rw\n",
        )
        status, distinct = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "/work/output")
        self.assertEqual(0, status)
        self.assertEqual("8:2", distinct["value"]["device"])

        write(proc / "self" / "mountinfo", "35 25 malformed / / rw,relatime - ext4 /dev/root rw\n")
        status, payload = self.run_helper("mount-identity", "--proc-root", str(proc), "--path", "/")
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-mount-identity", payload["code"])

    def test_snapshot_refuses_malformed_or_missing_required_cgroup_facts(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: __import__("shutil").rmtree(temporary, ignore_errors=True))
        write(proc / "meminfo", "MemTotal: 9 kB\nMemAvailable: 10 kB\n")
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-proc-meminfo", payload["code"])

        write(proc / "meminfo", "MemTotal: 8192 kB\nMemAvailable: 4096 kB\n")
        (temporary / "cgroup" / "leaf" / "work" / "memory.pressure").unlink()
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-cgroup-pressure", payload["code"])

    def test_snapshot_refuses_cgroup_high_below_current(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: __import__("shutil").rmtree(temporary, ignore_errors=True))
        write(temporary / "cgroup" / "leaf" / "work" / "memory.high", "299\n")
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-cgroup-memory", payload["code"])

    def test_snapshot_keeps_pressure_when_the_actual_hierarchy_root_has_no_memory_controls(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        for name in ("memory.current", "memory.max", "memory.high", "memory.events", "memory.events.local"):
            (temporary / "cgroup" / name).unlink()
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(0, status)
        root = payload["value"]["cgroup_v2"]["ancestors"][-1]
        self.assertEqual("/", root["relative_path"])
        self.assertEqual("root-control-not-applicable", root["control_applicability"])
        self.assertEqual({"some", "full"}, set(root["pressure"]))
        self.assertIsNone(root["events"])

    def test_snapshot_refuses_partial_or_namespace_root_memory_control_absence(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        (temporary / "cgroup" / "memory.events.local").unlink()
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-cgroup-events", payload["code"])

        cgroup = temporary / "cgroup"
        cgroup_files(cgroup, current=100, maximum="max", high="max")
        for name in ("memory.current", "memory.max", "memory.high", "memory.events", "memory.events.local"):
            (cgroup / name).unlink()
        write(proc / "self" / "cgroup", "0::/delegated\n")
        write(
            proc / "self" / "mountinfo",
            f"40 31 0:44 /delegated {cgroup.as_posix()} rw,nosuid,nodev - cgroup2 cgroup rw\n",
        )
        status, payload = self.run_helper("snapshot", "--proc-root", str(proc))
        self.assertEqual(2, status)
        self.assertEqual("mir441-linux-cgroup-memory", payload["code"])

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux procfs, cgroup v2, and pwsh")
    def test_host_managed_memory_keeps_disk_checks_and_records_usage(self) -> None:
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell is unavailable")
        run_root = ROOT / "build" / "tmp" / f"linux-host-memory-{uuid.uuid4().hex}"
        run_root.mkdir(parents=True)
        self.addCleanup(lambda: shutil.rmtree(run_root, ignore_errors=True))
        governor = ROOT / "tools" / "lib" / "validation" / "ResourceGovernor.ps1"
        script = rf"""
$ErrorActionPreference='Stop'
. '{governor.as_posix()}'
$work='{run_root.as_posix()}'
$ledger=Join-Path $work 'ledger.jsonl'
$policy=[pscustomobject]@{{}}
$script:actualSnapshot=${{function:Get-MIR441ResourceSnapshot}}
$script:lowHost=$true
$script:lowDisk=$false
function Get-MIR441ResourceSnapshot([string]$WorkRoot) {{
  $row=& $script:actualSnapshot -WorkRoot $WorkRoot
  $row.memory.free_bytes=if($script:lowHost){{0L}}else{{$row.memory.total_bytes}}
  $row.memory.cgroup_v2.effective_headroom_bytes=1L
  $row.system_volume.total_bytes=128GB
  $row.system_volume.free_bytes=64GB
  $row.work_volume.total_bytes=128GB
  $row.work_volume.free_bytes=if($script:lowDisk){{0L}}else{{64GB}}
  return $row
}}
function Get-Refusal {{
  try {{ $null=Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $work -EstimatedPeakBytes 8MB -ExpectedPeakMemoryBytes 1MB }}
  catch {{ return $_.Exception.Message }}
  return ''
}}
$env:MIR_NATIVE_USE_HOST_MEMORY='0'
$hostRefusal=Get-Refusal
$script:lowHost=$false
$cgroupRefusal=Get-Refusal
$env:MIR_NATIVE_USE_HOST_MEMORY='1'
$script:lowHost=$true
$script:lowDisk=$true
$diskRefusal=Get-Refusal
$script:lowDisk=$false
$result=Invoke-MIR441MonitoredProcess -FilePath '{Path(pwsh).resolve().as_posix()}' -Arguments @('-NoProfile','-Command','Start-Sleep -Milliseconds 1700; exit 0') -WorkRoot $work -LedgerPath $ledger -Policy $policy -EstimatedPeakBytes 8MB -ExpectedPeakMemoryBytes 1MB -TimeoutSeconds 20
$rows=@(Get-Content -LiteralPath $ledger | ForEach-Object {{ $_ | ConvertFrom-Json -AsHashtable }} | Where-Object {{ $_.Contains('process') }})
[ordered]@{{host=$hostRefusal;cgroup=$cgroupRefusal;disk=$diskRefusal;status=$result.status;rows=$rows}} | ConvertTo-Json -Depth 16 -Compress
"""
        completed = subprocess.run(
            [pwsh, "-NoProfile", "-NonInteractive", "-Command", script],
            cwd=ROOT, check=False, capture_output=True, text=True, timeout=45,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual("[mir441-resource-admission-memory]", result["host"])
        self.assertEqual("[mir441-resource-admission-cgroup]", result["cgroup"])
        self.assertEqual("[mir441-resource-admission-work-disk]", result["disk"])
        self.assertEqual("passed", result["status"])
        samples = [row["process"] for row in result["rows"] if row["process"].get("phase") == "running"]
        self.assertTrue(samples)
        self.assertEqual({"linux-host-managed"}, {row["memory_enforcement"] for row in samples})
        self.assertGreater(max(row["peak_working_set_bytes"] for row in samples), 1024**2)

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires real Linux procfs, cgroup v2, and pwsh")
    def test_real_linux_new_workroot_uses_existing_volume_and_case_sensitive_containment(self) -> None:
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell is unavailable")
        run_root = ROOT / "build" / "tmp" / f"linux-resource-real-{uuid.uuid4().hex}"
        harness = run_root.with_suffix(".ps1")
        script = rf"""
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. '{(ROOT / "tools" / "lib" / "validation" / "ResourceGovernor.ps1").as_posix()}'
$runRoot='{run_root.as_posix()}'
$newWork=Join-Path $runRoot 'new-output/not-created-yet'
$caseWork=Join-Path $runRoot 'work'
$caseOther=Join-Path $runRoot 'Work'
New-Item -ItemType Directory -Force -Path $runRoot,$caseWork,$caseOther | Out-Null
try {{
  $snapshot=Get-MIR441ResourceSnapshot -WorkRoot $newWork
  $caseRoot=''
  try {{ Resolve-MIR441RecoveryScratchPath -Path '{(ROOT / "BUILD" / "tmp" / "wrong-case").as_posix()}' | Out-Null }} catch {{ $caseRoot=$_.Exception.Message }}
  $caseOutput=''
  try {{ Invoke-MIR441MonitoredProcess -FilePath '/not-used' -Arguments @('--version') -WorkRoot $caseWork -LedgerPath (Join-Path $caseOther 'ledger.jsonl') -Policy ([pscustomobject]@{{}}) -EstimatedPeakBytes 16MB -ExpectedPeakMemoryBytes 64MB | Out-Null }} catch {{ $caseOutput=$_.Exception.Message }}
  [pscustomobject]@{{filesystem=$snapshot.work_volume.filesystem_type;work_root=$snapshot.work_root;new_work_exists=(Test-Path -LiteralPath $newWork);case_root=$caseRoot;case_output=$caseOutput}} | ConvertTo-Json -Compress
}} finally {{
  if(Test-Path -LiteralPath $runRoot) {{ Remove-Item -LiteralPath $runRoot -Recurse -Force }}
}}
"""
        harness.write_text(script, encoding="utf-8")
        self.addCleanup(lambda: harness.unlink(missing_ok=True))
        self.addCleanup(lambda: shutil.rmtree(run_root, ignore_errors=True))
        completed = subprocess.run(
            [pwsh, "-NoProfile", "-File", str(harness)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=45,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual("ext4", result["filesystem"])
        self.assertEqual(str(run_root / "new-output" / "not-created-yet"), result["work_root"])
        self.assertFalse(result["new_work_exists"])
        self.assertIn("[mir441-resource-output-root]", result["case_root"])
        self.assertIn("[mir441-resource-output-work-root]", result["case_output"])

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux setsid and procfs")
    def test_real_linux_launcher_retains_a_child_after_the_session_leader_exits(self) -> None:
        temporary = Path(tempfile.mkdtemp(prefix="mir-linux-session-launch-", dir=ROOT / "build" / "tmp"))
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        receipt = temporary / "launch.json"
        target = temporary / "leader.py"
        write(
            target,
            "import os, time\n"
            "child = os.fork()\n"
            "if child:\n"
            "    os._exit(0)\n"
            "time.sleep(15)\n",
        )
        process = subprocess.Popen(
            [sys.executable, "-I", str(LAUNCHER), "--receipt", str(receipt), "--", sys.executable, "-I", str(target)],
            cwd=ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.monotonic() + 5
            while not receipt.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(receipt.exists())
            launch = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual("MIR441LinuxNativeLaunchV1", launch["kind"])
            self.assertEqual(process.pid, launch["pid"])
            self.assertEqual(process.pid, launch["session_id"])
            self.assertGreater(launch["start_ticks"], 0)
            process.stdin.write((json.dumps(dict(launch, kind="MIR441LinuxNativeAckV1")) + "\n").encode())
            process.stdin.flush()
            process.wait(timeout=5)
            self.assertEqual(0, process.returncode)
            status, payload = self.run_helper(
                "process-tree",
                "--pid",
                str(launch["pid"]),
                "--root-start-ticks",
                str(launch["start_ticks"]),
                "--session-id",
                str(launch["session_id"]),
            )
            self.assertEqual(0, status)
            value = payload["value"]
            self.assertTrue(value["root_exited"])
            self.assertEqual(1, len(value["children"]))
            self.assertEqual(launch["session_id"], value["children"][0]["session_id"])
        finally:
            if receipt.exists():
                try:
                    launch = json.loads(receipt.read_text(encoding="utf-8"))
                    status, payload = self.run_helper(
                        "process-tree",
                        "--pid",
                        str(launch["pid"]),
                        "--root-start-ticks",
                        str(launch["start_ticks"]),
                        "--session-id",
                        str(launch["session_id"]),
                    )
                    for child in payload.get("value", {}).get("children", []):
                        try:
                            os.kill(child["id"], 15)
                        except ProcessLookupError:
                            pass
                except (OSError, ValueError, json.JSONDecodeError):
                    pass
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            process.stdin.close()

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux setsid and procfs")
    def test_real_linux_launcher_never_executes_without_a_matching_ack(self) -> None:
        for mode in ("absent", "wrong-identity", "malformed", "matching-file-only"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix="mir-linux-ack-", dir=ROOT / "build" / "tmp") as directory:
                temporary = Path(directory)
                receipt, ack, marker = (temporary / name for name in ("receipt.json", "ack.json", "executed"))
                process = subprocess.Popen(
                    [sys.executable, "-I", str(LAUNCHER), "--receipt", str(receipt), "--",
                     sys.executable, "-I", "-c", "from pathlib import Path; import sys; Path(sys.argv[1]).touch()", str(marker)],
                    cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                )
                try:
                    deadline = time.monotonic() + 5
                    while not receipt.exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(receipt.exists())
                    value = json.loads(receipt.read_text())
                    self.assertFalse(marker.exists(), "Target ran before ownership acknowledgement")
                    if mode == "wrong-identity":
                        value.update(kind="MIR441LinuxNativeAckV1", start_ticks=value["start_ticks"] + 1)
                        process.stdin.write((json.dumps(value) + "\n").encode())
                        process.stdin.flush()
                    elif mode == "malformed":
                        process.stdin.write(b"{\n")
                        process.stdin.flush()
                    elif mode == "matching-file-only":
                        value["kind"] = "MIR441LinuxNativeAckV1"
                        ack.write_text(json.dumps(value))
                    # Keep the pipe open: absence must time out rather than
                    # accidentally passing because communicate() closed stdin.
                    process.wait(timeout=5)
                    stdout, stderr = process.communicate(timeout=5)
                    self.assertEqual(125, process.returncode, (stdout, stderr))
                    self.assertFalse(marker.exists(), "Unacknowledged target executed")
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate(timeout=5)

    @unittest.skipUnless(sys.platform.startswith("linux"), "requires Linux procfs, cgroup v2, and pwsh")
    def test_real_linux_production_monitor_stops_an_orphaned_session_child(self) -> None:
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell is unavailable")
        run_root = ROOT / "build" / "tmp" / f"linux-production-session-{uuid.uuid4().hex}"
        child_receipt = run_root / "child.json"
        target = run_root / "leader.py"
        harness = run_root.with_suffix(".ps1")
        target_body = r"""
import json
import os
import sys
import time

receipt = sys.argv[1]
child = os.fork()
if child:
    deadline = time.monotonic() + 2
    while not os.path.exists(receipt) and time.monotonic() < deadline:
        time.sleep(0.005)
    os._exit(0 if os.path.exists(receipt) else 2)
text = open(f"/proc/{os.getpid()}/stat", encoding="utf-8").read()
close = text.rfind(")")
fields = text[close + 1:].split()
with open(receipt, "x", encoding="utf-8") as stream:
    json.dump({"pid": os.getpid(), "start_ticks": int(fields[19]), "session_id": os.getsid(0)}, stream)
    stream.flush()
    os.fsync(stream.fileno())
time.sleep(20)
""".lstrip()
        write(target, target_body)
        script = rf"""
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. '{(ROOT / "tools" / "lib" / "validation" / "NativeProbeCommon.ps1").as_posix()}'
. '{(ROOT / "tools" / "lib" / "validation" / "ResourceGovernor.ps1").as_posix()}'
$runRoot='{run_root.as_posix()}'
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
try {{
  $result=Invoke-MIR441MonitoredProcess -FilePath '{Path(sys.executable).as_posix()}' -Arguments @('-I','{target.as_posix()}','{child_receipt.as_posix()}') -WorkRoot $runRoot -LedgerPath (Join-Path $runRoot 'ledger.jsonl') -Policy ([pscustomobject]@{{}}) -EstimatedPeakBytes 16MB -ExpectedPeakMemoryBytes 64MB -TimeoutSeconds 20
  [pscustomobject]@{{status=$result.status;ledger=(Join-Path $runRoot 'ledger.jsonl');child='{child_receipt.as_posix()}'}} | ConvertTo-Json -Compress
}} catch {{
  [pscustomobject]@{{error=$_.Exception.Message}} | ConvertTo-Json -Compress
  exit 1
}}
"""
        harness.write_text(script, encoding="utf-8")
        self.addCleanup(lambda: harness.unlink(missing_ok=True))
        self.addCleanup(lambda: shutil.rmtree(run_root, ignore_errors=True))
        completed = subprocess.run(
            [pwsh, "-NoProfile", "-File", str(harness)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=45,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual("passed", result["status"])
        child = json.loads(child_receipt.read_text(encoding="utf-8"))
        rows = [json.loads(line) for line in Path(result["ledger"]).read_text(encoding="utf-8").splitlines()]
        process_rows = [row for row in rows if "process" in row]
        self.assertGreaterEqual(len(process_rows), 1)
        self.assertTrue(process_rows[0]["process"]["root_exited"])
        leader = process_rows[0]["process"]["start_identity"]
        status, payload = self.run_helper(
            "process-tree",
            "--pid",
            str(leader["pid"]),
            "--root-start-ticks",
            str(leader["start_ticks"]),
            "--session-id",
            str(leader["session_id"]),
        )
        self.assertEqual(0, status)
        self.assertTrue(payload["value"]["root_exited"])
        self.assertEqual([], payload["value"]["children"])
        status, payload = self.run_helper("process-identity", "--pid", str(child["pid"]))
        self.assertEqual(0, status)
        self.assertTrue(payload["value"]["exited"])

    def test_process_tree_uses_all_owned_threads_and_start_identities_without_cmdline(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: __import__("shutil").rmtree(temporary, ignore_errors=True))
        process_files(proc, 100, 1, 1000, {100: "101", 200: "102"})
        process_files(proc, 101, 100, 1001, {101: "103"})
        process_files(proc, 102, 100, 1002, {102: ""})
        process_files(proc, 103, 101, 1003, {103: ""})
        # No cmdline or environ files exist in this fixture.  The helper must
        # still observe only the owned descendant closure successfully.
        status, identity = self.run_helper("process-identity", "--proc-root", str(proc), "--pid", "100")
        self.assertEqual(0, status)
        self.assertEqual({"pid": 100, "start_ticks": 1000, "session_id": 1}, identity["value"])
        status, payload = self.run_helper(
            "process-tree", "--proc-root", str(proc), "--pid", "100", "--root-start-ticks", "1000"
        )
        self.assertEqual(0, status)
        value = payload["value"]
        self.assertFalse(value["root_exited"])
        self.assertEqual([101, 102, 103], [row["id"] for row in value["children"]])
        self.assertEqual(4 * 12 * 1024, value["working_set_bytes"])
        self.assertEqual(4 * 5 * 1024, value["private_resident_bytes"])
        self.assertEqual(4 * 5 * 1024, value["private_swap_bytes"])
        self.assertEqual(4 * 10 * 1024, value["private_bytes"])
        self.assertEqual("smaps_rollup_private_resident_plus_swap", value["private_measure"])

    def test_released_r_state_member_keeps_peer_memory_and_root_lifetime_separate(self) -> None:
        for released in (100, 101):
            with self.subTest(released=released), tempfile.TemporaryDirectory(prefix="mir-linux-released-mm-") as directory:
                proc = Path(directory)
                process_files(proc, 100, 1, 1000, {100: "101"}, session=100)
                process_files(proc, 101, 100, 1001, {101: ""}, session=100)
                parent, start = (1, 1000) if released == 100 else (100, 1001)
                write(proc / str(released) / "stat", proc_stat(released, parent, start, 100, state="R", flags=4))
                write(proc / str(released) / "status", f"Name:\towned\nState:\tR (running)\nPid:\t{released}\n")
                (proc / str(released) / "smaps_rollup").unlink()
                original_private = OBSERVATION.read_private_memory
                with mock.patch.object(OBSERVATION, "read_private_memory", wraps=original_private) as private:
                    value = OBSERVATION.process_tree(proc, 100, 1000, 100)
                self.assertEqual([(proc, 101 if released == 100 else 100)], [call.args for call in private.call_args_list])
                self.assertFalse(value["root_exited"])
                self.assertEqual(12 * 1024, value["working_set_bytes"])
                self.assertEqual(10 * 1024, value["private_bytes"])
                self.assertEqual([{
                    "pid": released, "start_ticks": start, "session_id": 100,
                    "state": "R", "flags": 4, "reason": "exiting-address-space-released",
                }], value["released_address_space_members"])
                self.assertNotIn("working_set_bytes", value["released_address_space_members"][0])
                self.assertEqual([101] if released == 100 else [], [row["id"] for row in value["children"]])

    def test_exit_between_rss_and_private_reads_needs_fresh_release_proof_and_discards_fragment(self) -> None:
        for released in (100, 101):
            with self.subTest(released=released), tempfile.TemporaryDirectory(prefix="mir-linux-mm-between-reads-") as directory:
                proc = Path(directory)
                process_files(proc, 100, 1, 1000, {100: "101"}, session=100)
                process_files(proc, 101, 100, 1001, {101: ""}, session=100)
                parent, start = (1, 1000) if released == 100 else (100, 1001)
                original = OBSERVATION.read_private_memory
                cause = OBSERVATION.ObservationFailure("mir441-linux-process-smaps")
                def exit_after_rss(root, pid):
                    if pid == released:
                        write(proc / str(pid) / "stat", proc_stat(pid, parent, start, 100, state="R", flags=4))
                        write(proc / str(pid) / "status", f"Name:\towned\nState:\tR (running)\nPid:\t{pid}\n")
                        raise cause
                    return original(root, pid)
                with mock.patch.object(OBSERVATION, "read_private_memory", side_effect=exit_after_rss):
                    value = OBSERVATION.process_tree(proc, 100, 1000, 100)
                self.assertFalse(value["root_exited"])
                self.assertEqual(12 * 1024, value["working_set_bytes"])
                self.assertEqual(10 * 1024, value["private_bytes"])
                self.assertEqual([released], [row["pid"] for row in value["released_address_space_members"]])

    def test_final_release_confirmation_cannot_hide_identity_replacement_or_unreadability(self) -> None:
        for opponent, code in (("pid-reused", "mir441-owned-child-identity"), ("unreadable-stat", "mir441-linux-process-status")):
            with self.subTest(opponent=opponent), tempfile.TemporaryDirectory(prefix="mir-linux-mm-confirmation-") as directory:
                proc = Path(directory)
                process_files(proc, 100, 1, 1000, {100: ""}, session=100)
                write(proc / "100/stat", proc_stat(100, 1, 1000, 100, state="R", flags=4))
                write(proc / "100/status", "Name:\towned\nState:\tR (running)\nPid:\t100\n")
                original = OBSERVATION.read_status_rss
                calls = 0
                def confirm(root, pid):
                    nonlocal calls
                    value = original(root, pid)
                    calls += 1
                    if calls == 2:
                        if opponent == "pid-reused":
                            write(proc / "100/stat", proc_stat(100, 1, 9999, 100, state="R", flags=4))
                        else:
                            write(proc / "100/stat", "not a proc stat record\n")
                    return value
                with mock.patch.object(OBSERVATION, "read_status_rss", side_effect=confirm):
                    with self.assertRaises(OBSERVATION.ObservationFailure) as raised:
                        OBSERVATION.process_tree(proc, 100, 1000, 100)
                self.assertEqual(code, raised.exception.code)

    def test_pf_exiting_with_memory_still_requires_and_counts_the_complete_sample(self) -> None:
        for missing_private in (False, True):
            with self.subTest(missing_private=missing_private), tempfile.TemporaryDirectory(prefix="mir-linux-exiting-live-mm-") as directory:
                proc = Path(directory)
                process_files(proc, 100, 1, 1000, {100: ""}, session=100)
                write(proc / "100/stat", proc_stat(100, 1, 1000, 100, state="R", flags=4))
                if missing_private:
                    (proc / "100/smaps_rollup").unlink()
                    with self.assertRaises(OBSERVATION.ObservationFailure) as raised:
                        OBSERVATION.process_tree(proc, 100, 1000, 100)
                    self.assertEqual("mir441-linux-process-smaps", raised.exception.code)
                else:
                    value = OBSERVATION.process_tree(proc, 100, 1000, 100)
                    self.assertFalse(value["root_exited"])
                    self.assertEqual(12 * 1024, value["working_set_bytes"])
                    self.assertEqual(10 * 1024, value["private_bytes"])
                    self.assertEqual([], value["released_address_space_members"])

    def test_missing_rss_needs_readable_unambiguous_pid_state_and_exit_flags(self) -> None:
        base = "Name:\towned\nState:\tR (running)\nPid:\t100\n"
        opponents = {
            "live-unflagged": (base, "R", 0),
            "sleeping-stat": (base, "S", 4),
            "sleeping-status": (base.replace("R (running)", "S (sleeping)"), "R", 4),
            "missing-state": ("Name:\towned\nPid:\t100\n", "R", 4),
            "malformed-state": (base.replace("R (running)", "running"), "R", 4),
            "duplicate-state": (base + "State:\tR (running)\n", "R", 4),
            "missing-pid": ("Name:\towned\nState:\tR (running)\n", "R", 4),
            "foreign-pid": (base.replace("Pid:\t100", "Pid:\t999"), "R", 4),
            "duplicate-pid": (base + "Pid:\t100\n", "R", 4),
            "malformed-rss": (base + "VmRSS:\tbroken kB\n", "R", 4),
            "duplicate-rss": (base + "VmRSS:\t12 kB\nVmRSS:\t13 kB\n", "R", 4),
            "malformed-second-rss": (base + "VmRSS:\t12 kB\nVmRSS:\tbroken kB\n", "R", 4),
            "other-memory-still-present": (base + "VmSize:\t12 kB\n", "R", 4),
            "unreadable-status": (None, "R", 4),
        }
        for name, (status, state, flags) in opponents.items():
            with self.subTest(opponent=name), tempfile.TemporaryDirectory(prefix="mir-linux-no-mm-opponent-") as directory:
                proc = Path(directory)
                process_files(proc, 100, 1, 1000, {100: ""}, session=100)
                write(proc / "100/stat", proc_stat(100, 1, 1000, 100, state=state, flags=flags))
                if status is None:
                    (proc / "100/status").unlink()
                else:
                    write(proc / "100/status", status)
                with self.assertRaises(OBSERVATION.ObservationFailure) as raised:
                    OBSERVATION.process_tree(proc, 100, 1000, 100)
                self.assertEqual("mir441-linux-process-status", raised.exception.code)

    def test_released_address_space_reread_preserves_identity_and_flag_refusals(self) -> None:
        for name, start, session, flags, code in (
            ("reused-pid", 9999, 100, 4, "mir441-owned-child-identity"),
            ("foreign-session", 1000, 999, 4, "mir441-owned-child-identity"),
            ("exit-flag-disappeared", 1000, 100, 0, "mir441-linux-process-status"),
        ):
            with self.subTest(opponent=name), tempfile.TemporaryDirectory(prefix="mir-linux-no-mm-reread-") as directory:
                proc = Path(directory)
                process_files(proc, 100, 1, 1000, {100: ""}, session=100)
                write(proc / "100/stat", proc_stat(100, 1, 1000, 100, state="R", flags=4))
                write(proc / "100/status", "Name:\towned\nState:\tR (running)\nPid:\t100\n")
                original = OBSERVATION.read_status_rss
                def transition(root, pid):
                    value = original(root, pid)
                    write(proc / "100/stat", proc_stat(100, 1, start, session, state="R", flags=flags))
                    return value
                with mock.patch.object(OBSERVATION, "read_status_rss", side_effect=transition):
                    with self.assertRaises(OBSERVATION.ObservationFailure) as raised:
                        OBSERVATION.process_tree(proc, 100, 1000, 100)
                self.assertEqual(code, raised.exception.code)

    def test_unexpected_status_reader_failure_is_never_a_released_address_space(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mir-linux-no-mm-unexpected-") as directory:
            proc = Path(directory)
            process_files(proc, 100, 1, 1000, {100: ""}, session=100)
            write(proc / "100/stat", proc_stat(100, 1, 1000, 100, state="R", flags=4))
            failure = RuntimeError("unexpected status reader failure")
            with mock.patch.object(OBSERVATION, "read_status_rss", side_effect=failure):
                with self.assertRaises(RuntimeError) as raised:
                    OBSERVATION.process_tree(proc, 100, 1000, 100)
            self.assertIs(failure, raised.exception)

    def test_zombie_leader_has_no_address_space_but_live_session_child_is_still_counted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mir-linux-zombie-accounting-") as directory:
            proc = Path(directory)
            process_files(proc, 100, 1, 1000, {100: "101"}, session=100)
            process_files(proc, 101, 100, 1001, {101: ""}, session=100)
            write(proc / "100/stat", proc_stat(100, 1, 1000, 100).replace(") S ", ") Z "))
            write(proc / "100/status", "Name:\towned\nState:\tZ (zombie)\n")
            (proc / "100/smaps_rollup").unlink()
            value = OBSERVATION.process_tree(proc, 100, 1000, 100)
            self.assertTrue(value["root_exited"])
            self.assertEqual(12 * 1024, value["working_set_bytes"])
            self.assertEqual(10 * 1024, value["private_bytes"])
            self.assertEqual([101], [row["id"] for row in value["children"]])

    def test_exit_between_identity_and_memory_reads_discards_only_that_terminal_sample(self) -> None:
        for phase in ("rss", "private"):
            for transition in ("vanished", "zombie"):
                with self.subTest(phase=phase, transition=transition), tempfile.TemporaryDirectory(
                    prefix="mir-linux-memory-exit-race-"
                ) as directory:
                    proc = Path(directory)
                    process_files(proc, 100, 1, 1000, {100: "101"}, session=100)
                    process_files(proc, 101, 100, 1001, {101: ""}, session=100)
                    rss, private = OBSERVATION.read_status_rss, OBSERVATION.read_private_memory

                    def failed_read(function, label):
                        def read(root, pid):
                            if pid == 101:
                                if transition == "vanished":
                                    (proc / "101/stat").unlink()
                                else:
                                    write(proc / "101/stat", proc_stat(101, 100, 1001, 100).replace(") S ", ") Z "))
                                raise OBSERVATION.ObservationFailure(label)
                            return function(root, pid)
                        return read

                    with (
                        mock.patch.object(OBSERVATION, "read_status_rss", side_effect=failed_read(
                            rss, "mir441-linux-process-status") if phase == "rss" else rss),
                        mock.patch.object(OBSERVATION, "read_private_memory", side_effect=failed_read(
                            private, "mir441-linux-process-smaps") if phase == "private" else private),
                    ):
                        value = OBSERVATION.process_tree(proc, 100, 1000, 100)
                    self.assertFalse(value["root_exited"])
                    self.assertEqual([], value["children"])
                    self.assertEqual(12 * 1024, value["working_set_bytes"])
                    self.assertEqual(10 * 1024, value["private_bytes"])

    def test_memory_read_fault_on_a_live_or_replaced_identity_is_not_terminal_absence(self) -> None:
        for phase in ("rss", "private"):
            for opponent in ("live", "reused-pid", "foreign-session"):
                with self.subTest(phase=phase, opponent=opponent), tempfile.TemporaryDirectory(
                    prefix="mir-linux-live-memory-fault-"
                ) as directory:
                    proc = Path(directory)
                    process_files(proc, 100, 1, 1000, {100: "101"}, session=100)
                    process_files(proc, 101, 100, 1001, {101: ""}, session=100)
                    label = "mir441-linux-process-status" if phase == "rss" else "mir441-linux-process-smaps"
                    cause = OBSERVATION.ObservationFailure(label)
                    original = OBSERVATION.read_status_rss if phase == "rss" else OBSERVATION.read_private_memory

                    def failed_read(root, pid):
                        if pid == 101:
                            if opponent == "reused-pid":
                                write(proc / "101/stat", proc_stat(101, 100, 9999, 100))
                            elif opponent == "foreign-session":
                                write(proc / "101/stat", proc_stat(101, 100, 1001, 999))
                            raise cause
                        return original(root, pid)

                    method = "read_status_rss" if phase == "rss" else "read_private_memory"
                    with mock.patch.object(OBSERVATION, method, side_effect=failed_read):
                        with self.assertRaises(OBSERVATION.ObservationFailure) as raised:
                            OBSERVATION.process_tree(proc, 100, 1000, 100)
                    if opponent == "live":
                        self.assertIs(cause, raised.exception)
                    else:
                        self.assertEqual("mir441-owned-child-identity", raised.exception.code)

    @unittest.skipUnless(sys.platform == "linux" and hasattr(os, "waitid") and hasattr(os, "WNOWAIT"), "requires Linux procfs and an unreaped owned child")
    def test_real_linux_zombie_is_observed_without_reading_its_released_memory(self) -> None:
        pid = os.fork()
        if pid == 0:
            os.setsid()
            os._exit(0)
        try:
            result = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOWAIT)
            self.assertEqual(0, result.si_status)
            identity = OBSERVATION.read_proc_stat(Path("/proc"), pid, missing_is_exit=False)
            value = OBSERVATION.process_tree(Path("/proc"), pid, identity["start_ticks"], pid)
            self.assertTrue(value["root_exited"])
            self.assertEqual([], value["children"])
            self.assertEqual(0, value["working_set_bytes"])
            self.assertEqual(0, value["private_bytes"])
        finally:
            reaped, status = os.waitpid(pid, 0)
            self.assertEqual(pid, reaped)
            self.assertEqual(0, status)

    def test_process_tree_refuses_replaced_root_or_foreign_child(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: __import__("shutil").rmtree(temporary, ignore_errors=True))
        process_files(proc, 100, 1, 1000, {100: "101"})
        process_files(proc, 101, 999, 1001, {101: ""})
        status, payload = self.run_helper(
            "process-tree", "--proc-root", str(proc), "--pid", "100", "--root-start-ticks", "999"
        )
        self.assertEqual(2, status)
        self.assertEqual("mir441-owned-root-identity", payload["code"])
        status, payload = self.run_helper(
            "process-tree", "--proc-root", str(proc), "--pid", "100", "--root-start-ticks", "1000"
        )
        self.assertEqual(2, status)
        self.assertEqual("mir441-owned-child-identity", payload["code"])

    def test_process_identity_marks_a_retired_child_without_reading_foreign_data(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        status, payload = self.run_helper("process-identity", "--proc-root", str(proc), "--pid", "999")
        self.assertEqual(0, status)
        self.assertEqual({"pid": 999, "exited": True}, payload["value"])

    def test_session_tree_retains_an_orphan_after_its_session_leader_exits(self) -> None:
        temporary, proc = self.make_fixture()
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        process_files(proc, 101, 1, 1001, {101: ""}, session=100)
        status, payload = self.run_helper(
            "process-tree", "--proc-root", str(proc), "--pid", "100", "--root-start-ticks", "1000", "--session-id", "100"
        )
        self.assertEqual(0, status)
        self.assertTrue(payload["value"]["root_exited"])
        self.assertEqual([101], [row["id"] for row in payload["value"]["children"]])
        self.assertEqual(100, payload["value"]["children"][0]["session_id"])

        status, payload = self.run_helper(
            "process-tree", "--proc-root", str(proc), "--pid", "100", "--root-start-ticks", "1000", "--session-id", "101"
        )
        self.assertEqual(2, status)
        self.assertEqual("mir441-owned-session-identity", payload["code"])

        process_files(proc, 100, 1, 9999, {100: ""}, session=100)
        status, payload = self.run_helper(
            "process-tree", "--proc-root", str(proc), "--pid", "100", "--root-start-ticks", "1000", "--session-id", "100"
        )
        self.assertEqual(2, status)
        self.assertEqual("mir441-owned-root-identity", payload["code"])

    def test_process_tree_accepts_a_mid_scan_root_exit_and_retains_its_session_orphan(self) -> None:
        """The leader can retire between the initial stat and proc scan."""
        root = {"pid": 100, "ppid": 1, "start_ticks": 1000, "session_id": 100}
        child = {"pid": 101, "ppid": 1, "start_ticks": 1001, "session_id": 100}

        source = HELPER.read_text(encoding="utf-8")
        replacement = """        rows = iter_proc_stats(proc_root)
        scanned_root = next((row for row in rows if row[\"pid\"] == root_pid), None)
        owned = {row[\"pid\"]: row for row in rows if row[\"session_id\"] == session_id}
        if scanned_root is not None:
            if scanned_root[\"start_ticks\"] != root_start_ticks:
                fail(\"mir441-owned-root-identity\")
            if scanned_root[\"session_id\"] != session_id:
                fail(\"mir441-owned-session-identity\")
            root = scanned_root
        elif root is not None:
            reread_root = read_proc_stat(proc_root, root_pid, missing_is_exit=True)
            if reread_root is None:
                root = None
            else:
                if reread_root[\"start_ticks\"] != root_start_ticks:
                    fail(\"mir441-owned-root-identity\")
                if reread_root[\"session_id\"] != session_id:
                    fail(\"mir441-owned-session-identity\")
                fail(\"mir441-owned-session-identity\")
"""
        old = """        owned = {row[\"pid\"]: row for row in iter_proc_stats(proc_root) if row[\"session_id\"] == session_id}
        if root is not None and root_pid not in owned:
            fail(\"mir441-owned-session-identity\")
"""
        self.assertEqual(1, source.count(replacement))
        old_source = source.replace(replacement, old)
        with tempfile.TemporaryDirectory(prefix="mir-linux-resource-root-exit-") as directory:
            old_path = Path(directory) / "LinuxResourceObservation.py"
            old_path.write_text(old_source, encoding="utf-8")
            old_module = load_observation_module(f"mir_linux_resource_observation_old_{uuid.uuid4().hex}", old_path)
            with self.assertRaises(old_module.ObservationFailure) as old_failure:
                self.run_session_race(old_module, initial_root=root, scan_rows=[child], root_after_scan=None)
        self.assertEqual("mir441-owned-session-identity", old_failure.exception.code)

        value = self.run_session_race(OBSERVATION, initial_root=root, scan_rows=[child], root_after_scan=None)
        self.assertTrue(value["root_exited"])
        self.assertEqual([101], [row["id"] for row in value["children"]])
        self.assertEqual(12 * 1024, value["working_set_bytes"])

    def test_process_tree_refuses_an_alive_root_omitted_from_the_session_scan(self) -> None:
        root = {"pid": 100, "ppid": 1, "start_ticks": 1000, "session_id": 100}
        child = {"pid": 101, "ppid": 1, "start_ticks": 1001, "session_id": 100}
        with self.assertRaises(OBSERVATION.ObservationFailure) as failure:
            self.run_session_race(OBSERVATION, initial_root=root, scan_rows=[child], root_after_scan=root)
        self.assertEqual("mir441-owned-session-identity", failure.exception.code)

    def test_process_tree_requires_a_matching_identity_if_root_appears_after_initial_absence(self) -> None:
        replaced_root = {"pid": 100, "ppid": 1, "start_ticks": 9999, "session_id": 100}
        with self.assertRaises(OBSERVATION.ObservationFailure) as failure:
            self.run_session_race(
                OBSERVATION, initial_root=None, scan_rows=[replaced_root], root_after_scan=replaced_root
            )
        self.assertEqual("mir441-owned-root-identity", failure.exception.code)

    def test_process_tree_accepts_only_the_matching_root_identity_after_initial_absence(self) -> None:
        root = {"pid": 100, "ppid": 1, "start_ticks": 1000, "session_id": 100}
        child = {"pid": 101, "ppid": 1, "start_ticks": 1001, "session_id": 100}
        value = self.run_session_race(OBSERVATION, initial_root=None, scan_rows=[root, child], root_after_scan=root)
        self.assertFalse(value["root_exited"])
        self.assertEqual([101], [row["id"] for row in value["children"]])

    def test_process_tree_refuses_a_session_change_when_root_appears_after_initial_absence(self) -> None:
        changed_root = {"pid": 100, "ppid": 1, "start_ticks": 1000, "session_id": 999}
        with self.assertRaises(OBSERVATION.ObservationFailure) as failure:
            self.run_session_race(OBSERVATION, initial_root=None, scan_rows=[changed_root], root_after_scan=changed_root)
        self.assertEqual("mir441-owned-session-identity", failure.exception.code)

    def test_linux_observer_preserves_owned_identity_failure_codes(self) -> None:
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell is unavailable for the governor control")
        governor = ROOT / "tools" / "lib" / "validation" / "ResourceGovernor.ps1"
        script = (
            f". '{governor.as_posix()}';"
            "$codes=@('mir441-owned-root-identity','mir441-owned-child-identity','mir441-owned-session-identity','other');"
            "$codes|ForEach-Object {[pscustomobject]@{input=$_;output=(Resolve-MIR441LinuxObservationFailureCode -Code $_)}}|ConvertTo-Json -Compress"
        )
        completed = subprocess.run(
            [pwsh, "-NoProfile", "-NonInteractive", "-Command", script],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        values = json.loads(completed.stdout)
        self.assertEqual(
            {
                "mir441-owned-root-identity": "mir441-owned-root-identity",
                "mir441-owned-child-identity": "mir441-owned-child-identity",
                "mir441-owned-session-identity": "mir441-owned-session-identity",
                "other": "mir441-resource-linux-observer",
            },
            {row["input"]: row["output"] for row in values},
        )

    def test_tiny_output_budget_reaches_the_live_governor_at_its_declared_reserve(self) -> None:
        """Exercise the production monitor with host-only admission doubles.

        The child is a short PowerShell sleep, not Factorio.  The double makes
        disk/RAM availability deterministic while the real governor still
        acquires its locks, starts an owned process, samples it, and records
        the exact output reserve supplied at initial, under-lock, and live
        admission points.  The old fixed 32 MiB live call fails this control.
        """
        pwsh = shutil.which("pwsh")
        if pwsh is None:
            self.skipTest("PowerShell is unavailable for the governor smoke control")
        temporary = Path(tempfile.mkdtemp(prefix="mir-linux-resource-governor-"))
        self.addCleanup(lambda: shutil.rmtree(temporary, ignore_errors=True))
        run_root = ROOT / "build" / "tmp" / f"linux-governor-host-only-{temporary.name}"
        harness = temporary / "tiny-output-governor.ps1"
        script = rf"""
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. '{(ROOT / "tools" / "lib" / "validation" / "ResourceGovernor.ps1").as_posix()}'
$runRoot='{run_root.as_posix()}'
$ledger=Join-Path $runRoot 'ledger.jsonl'
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$volumeName=[IO.DriveInfo]::new($runRoot).Name;$mountId=1L
if($IsLinux) {{ $mount=Invoke-MIR441LinuxResourceObservation -Operation mount-identity -Path $runRoot;$volumeName=$mount.mount_point;$mountId=[int64]$mount.mount_id }}
$script:admissionBytes=[Collections.Generic.List[long]]::new()
$events=[pscustomobject]@{{low=0;high=0;max=0;oom=0;oom_kill=0}}
$pressure=[pscustomobject]@{{some=[pscustomobject]@{{avg10=0.0;avg60=0.0;avg300=0.0;total=0}};full=[pscustomobject]@{{avg10=0.0;avg60=0.0;avg300=0.0;total=0}}}}
$cgroup=[pscustomobject]@{{ancestors=@([pscustomobject]@{{relative_path='/host-only';control_applicability='applicable';events=$events;events_local=$events;pressure=$pressure}})}}
$snapshot=[pscustomobject]@{{memory=[pscustomobject]@{{total_bytes=[int64]32GB;free_bytes=[int64]32GB;commit_limit_bytes=[int64]32GB;committed_bytes=0L;cgroup_v2=$cgroup}};work_volume=[pscustomobject]@{{name=$volumeName;mount_id=$mountId;free_bytes=[int64]64GB;total_bytes=[int64]128GB}};system_volume=[pscustomobject]@{{name=$volumeName;free_bytes=[int64]64GB;total_bytes=[int64]128GB}}}}
function Assert-MIR441ResourceAdmission {{
  param($Policy,[string]$WorkRoot,[int64]$EstimatedPeakBytes,[int64]$ExpectedPeakMemoryBytes)
  $script:admissionBytes.Add($EstimatedPeakBytes)
  return ($snapshot | Select-Object *)
}}
function Write-MIR441Json {{
  param($Value,[string]$Path,[switch]$Append)
  # The real caller supplies the append-only writer. This host-only monitor
  # control owns no receipt and only observes its admission calls.
}}
try {{
  $result=Invoke-MIR441MonitoredProcess -FilePath '{Path(pwsh).as_posix()}' -Arguments @('-NoProfile','-Command','Start-Sleep -Milliseconds 350; exit 0') -WorkRoot $runRoot -LedgerPath $ledger -Policy ([pscustomobject]@{{}}) -EstimatedPeakBytes 16MB -ExpectedPeakMemoryBytes 1GB -TimeoutSeconds 20
  [pscustomobject]@{{status=$result.status;admissions=@($script:admissionBytes)}} | ConvertTo-Json -Compress
}} finally {{
  if(Test-Path -LiteralPath $runRoot) {{ Remove-Item -LiteralPath $runRoot -Recurse -Force }}
}}
"""
        harness.write_text(script, encoding="utf-8")
        completed = subprocess.run(
            [pwsh, "-NoProfile", "-File", str(harness)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=45,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual("passed", result["status"])
        self.assertGreaterEqual(len(result["admissions"]), 3)
        self.assertEqual([16 * 1024 * 1024] * 3, result["admissions"][:3])


if __name__ == "__main__":
    unittest.main()
