"""Retained dependency declaration expectations, without network or native work.

The six rows come from historical Test-MIRDependencyResolver.ps1, Git blob
b7bcbbc71a5cd6ee8ef94f29fbd23177ba0149cf. They cover metadata names and kinds,
not version resolution or gameplay compatibility.
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
PARSER = ROOT / "tools/lib/compatibility/ModPortal.ps1"
CASES = (
    ("base >= 2.1.0", "base", "required", True),
    ("Flare Stack >= 4.0.0", "Flare Stack", "required", True),
    ("(?) PlutoniumEnergy", "PlutoniumEnergy", "hidden_optional", False),
    ("+ Space Exploration >= 0.6.0", "Space Exploration", "recommended", False),
    ("~ no-order helper", "no-order helper", "no_order", True),
    ("! incompatible mod <= 2.0.0", "incompatible mod", "incompatible", False),
)


class DependencyDeclarationControls(unittest.TestCase):
    def test_historical_names_kinds_and_required_flags(self):
        # Declarations travel as JSON data; no declaration is evaluated as code.
        command = r"""
            $ErrorActionPreference = 'Stop'
            $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
            . $payload.parser
            $rows = @($payload.declarations | ForEach-Object {
                ConvertFrom-MIRDependencyString -Dependency $_
            })
            ConvertTo-Json -InputObject $rows -Depth 4 -Compress
        """
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
            cwd=ROOT,
            input=json.dumps({"parser": str(PARSER), "declarations": [row[0] for row in CASES]}),
            encoding="utf-8",
            capture_output=True,
            check=True,
            timeout=30,
        )
        actual = json.loads(result.stdout)
        self.assertEqual(len(CASES), len(actual))
        for (raw, name, kind, required), row in zip(CASES, actual):
            with self.subTest(declaration=raw):
                self.assertEqual(name, row["name"])
                self.assertEqual(kind, row["kind"])
                self.assertIs(required, row["required"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
