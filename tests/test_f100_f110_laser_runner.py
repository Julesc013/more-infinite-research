"""Exercise the actual laser runner admission without launching Factorio."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools/Invoke-NativeFixture.ps1"
FIXTURE = ROOT / "tests/fixtures/f100-f110-laser"


class LaserRunnerControls(unittest.TestCase):
    def test_both_exact_compositions_and_opposing_inputs(self):
        for stage, version, mir, edition, fixture in (
            ("source", "1.0.0", "5.0.10000", "f100", "0.1.0"),
            ("successor", "1.1.110", "5.0.11000", "f110", "0.2.0"),
        ):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory(prefix="mir-laser-runner-") as work:
                root = Path(work) / "repo"
                canonical = root / "tests/fixtures/f100-f110-laser"
                shutil.copytree(FIXTURE, canonical)
                source = root / "build/composed"
                source.mkdir(parents=True)
                for p in (canonical / stage).iterdir():
                    shutil.copyfile(p, source / p.name)
                for p, name in (("control.lua", "fixture_control.lua"), ("data-final-fixes.lua", "fixture_data_final.lua"),
                                ("settings-updates.lua", "fixture_settings.lua")):
                    shutil.copyfile(canonical / "shared" / p, source / name)
                engine_data = Path(work) / "engine/data"
                (engine_data / "base").mkdir(parents=True)
                (engine_data / "base/info.json").write_text(json.dumps({"version": version}), encoding="utf-8")
                engine = Path(work) / "factorio.exe"
                engine.write_bytes(b"host-only engine identity")
                engine_sha = hashlib.sha256(engine.read_bytes()).hexdigest().upper()
                profile = {
                    "schema": 1, "kind": "mir-f100-f110-laser-transition", "stage": stage,
                    "target": edition, "factorio_line": "1.0" if stage == "source" else "1.1",
                    "settings_mode": "Defaults", "engine": {"version": version, "sha256": engine_sha},
                    "mods": [{"name": "base", "version": version, "enabled": True},
                             {"name": "more-infinite-research", "version": mir, "enabled": True},
                             {"name": "mir-fixture-f100-f110-laser", "version": fixture, "enabled": True}],
                    "archive_sha256": {f"more-infinite-research_{mir}.zip": "A" * 64},
                }
                if stage == "successor":
                    profile["protected_source_sha256"] = "B" * 64
                profile_path = Path(work) / "profile.json"
                profile_path.write_text(json.dumps(profile), encoding="utf-8")
                script = r'''
                  $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
                  $tokens=$null;$errors=$null
                  $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
                  if($errors.Count){throw ($errors|Out-String)}
                  foreach($name in @('Assert-Fixture','Get-FixtureSha','Test-F110PublishedCrossSourceRelativePath','Get-F100F110LaserFixture')){
                    $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
                    if($node.Count -ne 1){throw "missing admission helper: $name"}
                    Invoke-Expression $node[0].Extent.Text
                  }
                  $profile=Get-Content -LiteralPath $env:MIR_TEST_PROFILE -Raw|ConvertFrom-Json -AsHashtable
                  $parameters=@{Repo=$env:MIR_TEST_REPO;Profile=$profile;Sources=@($env:MIR_TEST_SOURCE);
                    EngineData=$env:MIR_TEST_ENGINE_DATA;Engine=$env:MIR_TEST_ENGINE;MIRSha=('A'*64);
                    Case='f100-f110-laser-transition';Stage=$env:MIR_TEST_STAGE;OtherModes=$false;
                    InputSave='';InputSha='';ExpectedEngineSha=$env:MIR_TEST_ENGINE_SHA}
                  if($env:MIR_TEST_STAGE -ceq 'successor'){$parameters.InputSave='protected.zip';$parameters.InputSha=('B'*64)}
                  $value=Get-F100F110LaserFixture @parameters
                  if($value.stage -cne $env:MIR_TEST_STAGE -or $value.name -cne 'mir-fixture-f100-f110-laser'){throw 'wrong admitted binding'}
                  function Refuse([hashtable]$Changes,[string]$Message){
                    $opposing=@{};foreach($key in $parameters.Keys){$opposing[$key]=$parameters[$key]}
                    foreach($key in $Changes.Keys){$opposing[$key]=$Changes[$key]}
                    $rejected=$false
                    try{Get-F100F110LaserFixture @opposing|Out-Null}catch{$rejected=$_.Exception.Message.Contains($Message)}
                    if(-not $rejected){throw ('opponent admitted or failed for wrong reason: '+$Message)}
                  }
                  Refuse @{OtherModes=$true} 'exclusive full fixture stage'
                  Refuse @{Stage='other'} 'exclusive full fixture stage'
                  Refuse @{Case='historical-native'} 'case differs'
                  Refuse @{MIRSha=('0'*64)} 'MIR archive pin differs'
                  Refuse @{ExpectedEngineSha=('0'*64)} 'engine pin differs'
                  Refuse @{Sources=@()} 'one composed fixture'
                  if($env:MIR_TEST_STAGE -ceq 'source'){
                    Refuse @{InputSave='arbitrary.zip';InputSha=('B'*64)} 'create its own fresh save'
                  }else{
                    Refuse @{InputSave=''} 'pinned protected source save'
                    Refuse @{InputSha=('C'*64)} 'pinned protected source save'
                  }
                  $kind=$profile.kind;$profile.kind='historical-native'
                  Refuse @{} 'profile metadata differs';$profile.kind=$kind
                  $mir=$profile.mods[1].version;$profile.mods[1].version='4.7.10003'
                  Refuse @{} 'selected closure differs';$profile.mods[1].version=$mir
                  $member=Join-Path $env:MIR_TEST_SOURCE 'fixture_control.lua'
                  $bytes=[IO.File]::ReadAllBytes($member)
                  [IO.File]::AppendAllText($member,"`n-- opponent")
                  Refuse @{} 'canonical member differs';[IO.File]::WriteAllBytes($member,$bytes)
                  $extra=Join-Path $env:MIR_TEST_SOURCE 'unexpected.txt'
                  [IO.File]::WriteAllText($extra,'opponent')
                  Refuse @{} 'membership differs';[IO.File]::Delete($extra)
                  $outside=Join-Path (Split-Path -Parent $env:MIR_TEST_REPO) 'outside'
                  [IO.Directory]::CreateDirectory($outside)|Out-Null
                  Refuse @{Sources=@($outside)} 'leaves executing checkout'
                '''
                env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_PROFILE=str(profile_path),
                           MIR_TEST_REPO=str(root), MIR_TEST_SOURCE=str(source), MIR_TEST_ENGINE_DATA=str(engine_data),
                           MIR_TEST_ENGINE=str(engine), MIR_TEST_ENGINE_SHA=engine_sha, MIR_TEST_STAGE=stage)
                result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-Command", script], cwd=ROOT,
                                        env=env, text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
