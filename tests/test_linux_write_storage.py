"""Fixed write-destination capacity and native actor composition controls."""
from pathlib import Path
import shutil
import subprocess
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


if __name__ == "__main__":
    unittest.main()
