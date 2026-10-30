"""Focused host controls for the published F100 forward reload matcher."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools" / "Invoke-NativeFixture.ps1"


def run_powershell(script: str, environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pwsh", "-NoProfile", "-Command", script],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )


class PublishedF100ForwardRunnerControls(unittest.TestCase):
    def test_ast_extracted_reload_predicate_requires_exact_published_forward_case_stage_role_and_target(self):
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse failed'}
          $assignments=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text -ceq '$reloadCompletion' -and
            $node.Right.Extent.Text.Contains('$reloadCase=if($f110PublishedCrossSource -or $f110SameEditionSuccessor)') -and
            $node.Right.Extent.Text.Contains('$reloadForward=') -and
            $node.Right.Extent.Text.Contains('$publishedF100Fixture.role') -and
            $node.Right.Extent.Text.Contains('$publishedF100Fixture.target')
          },$true))
          if($assignments.Count -ne 1){throw 'published forward reload predicate differs'}
          $predicate=[scriptblock]::Create($assignments[0].Extent.Text)
          $log=Join-Path $env:TEMP 'mir-published-f100-forward-reload-predicate.log'
          function Invoke-ReloadPredicate([string]$Text,[bool]$Published,[string]$Role,[string]$Target,[bool]$F110,[bool]$Laser,[bool]$Transition,[string]$TransitionStage){
            [IO.File]::WriteAllText($log,$Text,[Text.UTF8Encoding]::new($false))
            $live=$log;$publishedF100Forward=$Published;$publishedF100Fixture=[pscustomobject]@{role=$Role;target=$Target}
            $f110PublishedCrossSource=$F110;$f110SameEditionSuccessor=$false;$laserTransition=$Laser
            $historicalTransition=$Transition;$HistoricalTransitionStage=$TransitionStage
            . $predicate
            return [bool](& $reloadCompletion)
          }
          $published=@(
            [pscustomobject]@{role='source';target='f100'},
            [pscustomobject]@{role='bridge';target='f110'},
            [pscustomobject]@{role='successor';target='f110'}
          )
          foreach($entry in $published){
            $marker='[MIR5_NATIVE_FIXTURE] RESULT {"case":"published-f100-forward","stage":"reload","role":"'+$entry.role+'","target":"'+$entry.target+'","status":"passed"}'
            if(-not(Invoke-ReloadPredicate $marker $true $entry.role $entry.target $false $false $false '')){throw 'exact published forward reload marker refused'}
          }
          $expectedRole='source';$expectedTarget='f100'
          foreach($marker in @(
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"historical-native","stage":"reload","role":"source","target":"f100","status":"passed"}',
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"published-f100-forward","stage":"initial","role":"source","target":"f100","status":"passed"}',
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"published-f100-forward","stage":"reload","role":"bridge","target":"f100","status":"passed"}',
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"published-f100-forward","stage":"reload","role":"source","target":"f110","status":"passed"}',
            ''
          )){if(Invoke-ReloadPredicate $marker $true $expectedRole $expectedTarget $false $false $false ''){throw 'wrong or missing published forward marker accepted'}}
          $fatal='0.001 Error native failure'+[Environment]::NewLine+'[MIR5_NATIVE_FIXTURE] RESULT {"case":"published-f100-forward","stage":"reload","role":"source","target":"f100","status":"passed"}'
          $fatalRejected=$false;try{[void](Invoke-ReloadPredicate $fatal $true $expectedRole $expectedTarget $false $false $false '')}catch{$fatalRejected=$_.Exception.Message.Contains('fatal native historical reload diagnostic')}
          if(-not$fatalRejected){throw 'fatal published forward reload diagnostic accepted'}
          if(-not(Invoke-ReloadPredicate '[MIR5_NATIVE_FIXTURE] RESULT {"case":"historical-native","stage":"reload","status":"passed"}' $false '' '' $false $false $false '')){throw 'historical reload predicate changed'}
          if(-not(Invoke-ReloadPredicate '[MIR5_NATIVE_FIXTURE] RESULT {"case":"f110-f200-transition","stage":"reload","status":"passed"}' $false '' '' $true $false $false '')){throw 'F110 reload predicate changed'}
          if(-not(Invoke-ReloadPredicate '[MIR5_NATIVE_FIXTURE] RESULT {"case":"f100-f110-laser-transition","stage":"reload","status":"passed"}' $false '' '' $false $true $false '')){throw 'laser reload predicate changed'}
          if(-not(Invoke-ReloadPredicate '[MIR5_NATIVE_FIXTURE] RESULT {"case":"historical-transition","stage":"reload","transition_stage":"successor","status":"passed"}' $false '' '' $false $false $true 'successor')){throw 'historical transition reload predicate changed'}
        '''
        result = run_powershell(script, dict(os.environ, MIR_TEST_RUNNER=str(RUNNER)))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PublishedF100ForwardRunnerControls)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
