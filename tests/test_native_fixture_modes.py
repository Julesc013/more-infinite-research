"""Execute the real MIR-absence admission guard without launching Factorio."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeFixtureModeControls(unittest.TestCase):
    def test_absent_full_and_create_modes_refuse_any_mir_selection_or_hash(self):
        script = r'''
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'runner parse failed'}
$nodes=@($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.IfStatementAst] -and
  $node.Clauses[0].Item1.Extent.Text -ceq '$MIRAbsent' -and
  $node.Clauses[0].Item2.Extent.Text.Contains('Assert-Fixture')
},$true))
if($nodes.Count -ne 1){throw 'exact MIR absence admission not found'}
$body=[scriptblock]::Create($nodes[0].Clauses[0].Item2.Extent.Text.TrimStart('{').TrimEnd('}'))
function Assert-Fixture([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$rows=@()
foreach($CreateOnly in @($false,$true)){
 foreach($count in @(0,1,2)){
  foreach($ExpectedMIRArchiveSha256 in @('',('A'*64))){
   $mirRows=@(for($index=0;$index-lt$count;$index++){@{name='more-infinite-research';version='5.0.21000'}})
   $accepted=$true; $reason=$null
   try {& $body} catch {$accepted=$false; $reason=$_.Exception.Message}
   $rows+=@{create_only=$CreateOnly; count=$count; hash_supplied=($ExpectedMIRArchiveSha256-ne''); accepted=$accepted; reason=$reason}
  }
 }
}
ConvertTo-Json -InputObject $rows -Depth 4 -Compress
'''
        env = dict(os.environ, MIR_TEST_RUNNER=str(ROOT / 'tools/Invoke-NativeFixture.ps1'))
        result = subprocess.run(['pwsh', '-NoProfile', '-Command', script], env=env,
                                capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        rows = json.loads(result.stdout)
        self.assertEqual(12, len(rows))
        for row in rows:
            with self.subTest(row=row):
                admitted = row['count'] == 0 and not row['hash_supplied']
                self.assertEqual(admitted, row['accepted'])
                if not admitted:
                    self.assertIn('MIR absence requires a profile without MIR or its hash', row['reason'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
