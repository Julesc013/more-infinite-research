"""Fixed write-destination capacity and native actor composition controls."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LinuxWriteStorageTests(unittest.TestCase):
    def test_capacity_and_actor_composition(self):
        pwsh = shutil.which("pwsh")
        self.assertIsNotNone(pwsh, "PowerShell is required by the native tooling controls")
        result = subprocess.run(
            [pwsh, "-NoProfile", "-File", str(ROOT / "tests/tooling/Test-MIRLinuxWriteStorage.ps1"), "-RepoRoot", str(ROOT)],
            cwd=ROOT, text=True, capture_output=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no native execution", result.stdout)

    @unittest.skipUnless(sys.platform == "linux", "requires actual Linux mounts")
    def test_actual_linux_mount_plan_and_cleanup(self):
        findmnt = shutil.which("findmnt")
        if findmnt is None:
            if os.environ.get("MIR_REQUIRE_LINUX_WRITE_MOUNTS") == "1":
                self.fail("findmnt unavailable; the required actual-mount control cannot run")
            self.skipTest("findmnt unavailable; cannot establish ext4 control input")
        mount = subprocess.run([findmnt, "-n", "-o", "FSTYPE", "-T", str(ROOT)], text=True, capture_output=True, timeout=10)
        if mount.returncode != 0 or mount.stdout.strip() != "ext4":
            if os.environ.get("MIR_REQUIRE_LINUX_WRITE_MOUNTS") == "1":
                self.fail("required actual-mount control needs checkout-local ext4")
            self.skipTest("executing checkout is not on the required ext4 control filesystem")
        with tempfile.TemporaryDirectory(prefix="mir-write-mount-controls-") as temporary:
            parent = Path(temporary)
            library = parent / "library"
            data = parent / "data"
            library.mkdir()
            data.mkdir()
            result = subprocess.run(
                [shutil.which("pwsh"), "-NoProfile", "-File", str(ROOT / "tests/tooling/Test-MIRLinuxWriteStorage.ps1"),
                 "-RepoRoot", str(ROOT), "-LinuxDataTestParent", str(data), "-LinuxLibraryRoot", str(library)],
                cwd=ROOT, text=True, capture_output=True, timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(list(data.iterdir()), [], "owned external data test child was not removed")
            self.assertEqual(list(library.iterdir()), [], "mount control changed the supplied library")


if __name__ == "__main__":
    unittest.main()
