from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "tools" / "lib" / "validation" / "LinuxResourceObservation.py"


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


def proc_stat(pid: int, ppid: int, start: int) -> str:
    # Fields after the final ')' start at procfs field 3.  starttime is field 22.
    fields = ["S", str(ppid)] + ["0"] * 17 + [str(start)]
    return f"{pid} (owned worker {pid}) {' '.join(fields)}\n"


def process_files(proc: Path, pid: int, ppid: int, start: int, children: dict[int, str]) -> None:
    write(proc / str(pid) / "stat", proc_stat(pid, ppid, start))
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
        self.assertEqual({"pid": 100, "start_ticks": 1000}, identity["value"])
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
$script:admissionBytes=[Collections.Generic.List[long]]::new()
$events=[pscustomobject]@{{low=0;high=0;max=0;oom=0;oom_kill=0}}
$pressure=[pscustomobject]@{{some=[pscustomobject]@{{avg10=0.0;avg60=0.0;avg300=0.0;total=0}};full=[pscustomobject]@{{avg10=0.0;avg60=0.0;avg300=0.0;total=0}}}}
$cgroup=[pscustomobject]@{{ancestors=@([pscustomobject]@{{relative_path='/host-only';events=$events;events_local=$events;pressure=$pressure}})}}
$snapshot=[pscustomobject]@{{memory=[pscustomobject]@{{total_bytes=[int64]32GB;free_bytes=[int64]32GB;commit_limit_bytes=[int64]32GB;committed_bytes=0L;cgroup_v2=$cgroup}};work_volume=[pscustomobject]@{{name='host-only';free_bytes=[int64]64GB;total_bytes=[int64]128GB}};system_volume=[pscustomobject]@{{name='host-only';free_bytes=[int64]64GB;total_bytes=[int64]128GB}}}}
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
