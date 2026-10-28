"""Host-only guards for the fresh published F110 source runner leg.

The source leg is intentionally an F110 process mode, but not a historical
fixture protocol. These controls exercise only runner preflight and marker
parsing; no Factorio process is launched.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools" / "Invoke-NativeFixture.ps1"
MIR_SHA = "66C127D8BFC1919FA88F19D2D9B3047316A1B90401CAA05A6D05979B7A099D1E"
ENGINE_SHA = "B7B4B834FCA2E32AFA9D3476EB42CC09B02F1205BE97F688DC6FC6ACE7BA8FE1"
FIXTURE = "mir-fixture-mir5-f110-f200-transition"


def _run_powershell(script: str, env: dict[str, str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], cwd=ROOT,
        env=env, text=True, capture_output=True, check=False,
    )


class F110F200RunnerControls(unittest.TestCase):
    def _fixture_source(self, root: Path) -> Path:
        canonical = root / "tests" / "fixtures" / "f110-f200-transition" / "f110" / "published-4.7.3"
        shared = root / "tests" / "fixtures" / "f110-f200-transition" / "shared"
        canonical.mkdir(parents=True)
        shared.mkdir(parents=True)
        (canonical / "info.json").write_text(json.dumps({
            "name": FIXTURE,
            "version": "0.1.0",
            "factorio_version": "1.1",
            "dependencies": ["base >= 1.1.110", "more-infinite-research = 4.7.11003"],
        }), encoding="utf-8")
        for name in ("catalogue.lua", "control.lua", "data-final-fixes.lua", "settings-updates.lua"):
            (canonical / name).write_text(f"-- canonical {name}\n", encoding="utf-8")
        (shared / "control.lua").write_text("-- shared control bytes\n", encoding="utf-8")
        (shared / "data-final-fixes.lua").write_text("-- shared data bytes\n", encoding="utf-8")
        source = root / "build" / "f110-composed"
        source.mkdir(parents=True)
        for name in ("catalogue.lua", "control.lua", "data-final-fixes.lua", "info.json", "settings-updates.lua"):
            shutil.copyfile(canonical / name, source / name)
        shutil.copyfile(shared / "control.lua", source / "fixture_control.lua")
        shutil.copyfile(shared / "data-final-fixes.lua", source / "fixture_data_final.lua")
        return source

    def _compose_actual_fixture_source(self, source: Path, successor=False) -> None:
        canonical = ROOT / "tests" / "fixtures" / "f110-f200-transition" / "f110" / ("successor" if successor else "published-4.7.3")
        shared = ROOT / "tests" / "fixtures" / "f110-f200-transition" / "shared"
        for name in ("catalogue.lua", "control.lua", "data-final-fixes.lua", "info.json", "settings-updates.lua"):
            shutil.copyfile(canonical / name, source / name)
        shutil.copyfile(shared / "control.lua", source / "fixture_control.lua")
        shutil.copyfile(shared / "data-final-fixes.lua", source / "fixture_data_final.lua")

    def test_ast_extracted_preflight_accepts_only_the_fixed_source_closure(self):
        with tempfile.TemporaryDirectory(prefix="mir5-f110-cross-runner-") as work:
            root = Path(work) / "repo"
            source = self._fixture_source(root)
            engine_data = Path(work) / "engine" / "data"
            (engine_data / "base").mkdir(parents=True)
            (engine_data / "base" / "info.json").write_text(json.dumps({"version": "1.1.110"}), encoding="utf-8")
            engine = Path(work) / "factorio.exe"
            engine.write_bytes(b"host-only engine identity")
            engine_sha = hashlib.sha256(engine.read_bytes()).hexdigest().upper()
            profile = {
                "schema": 1,
                "kind": "mir5-f110-f200-transition-source",
                "target": "f110",
                "factorio_line": "1.1",
                "engine": {"version": "1.1.110", "sha256": engine_sha},
                "settings_mode": "Defaults",
                "mods": [
                    {"name": "base", "version": "1.1.110", "enabled": True},
                    {"name": "more-infinite-research", "version": "4.7.11003", "enabled": True},
                    {"name": FIXTURE, "version": "0.1.0", "enabled": True},
                ],
                "archive_sha256": {"more-infinite-research_4.7.11003.zip": MIR_SHA},
            }
            profile_path = Path(work) / "profile.json"
            profile_path.write_text(json.dumps(profile), encoding="utf-8")
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              $tokens=$null;$errors=$null
              $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
              if($errors.Count){throw 'runner parse failed'}
              foreach($name in @('Assert-Fixture','Get-FixtureSha','Test-F110PublishedCrossSourceRelativePath','Get-F110PublishedCrossSourceFixture')){
                $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
                if($node.Count -ne 1){throw "helper missing: $name"}
                Invoke-Expression $node[0].Extent.Text
              }
              $profile=Get-Content -LiteralPath $env:MIR_TEST_PROFILE -Raw|ConvertFrom-Json -AsHashtable
              $base=@{
                Repo=$env:MIR_TEST_REPO;ProfileDefinition=$profile;ProfileRows=@($profile.mods);Sources=@($env:MIR_TEST_SOURCE)
                EngineData=$env:MIR_TEST_ENGINE_DATA;Engine=$env:MIR_TEST_ENGINE;ExpectedMIRSha256=$env:MIR_TEST_MIR_SHA
                Case='f110-f200-transition';Historical=$false;HistoricalTransition=$false;Create=$false;Absent=$false;Active=$false
                ActiveKind='';InputSave='';InputSaveSha256='';Observer='';Markers=@();HistoricalTarget='';HistoricalMetadata='';TransitionStage='';TransitionMetadata=''
                ExpectedEngineSha256=$env:MIR_TEST_ENGINE_SHA
              }
              $result=Get-F110PublishedCrossSourceFixture @base
              if($result.name -cne 'mir-fixture-mir5-f110-f200-transition' -or $result.version -cne '0.1.0'){throw 'good source refused'}
              foreach($rooted in @('D:\outside-f110-composed','\mocked-rooted')){
                if(Test-F110PublishedCrossSourceRelativePath $rooted){throw ('rooted relative path accepted: '+$rooted)}
              }
              if(-not(Test-F110PublishedCrossSourceRelativePath ('build'+[IO.Path]::DirectorySeparatorChar+'f110-composed'))){throw 'relative composed path refused'}
              $opponents=@(
                @{name='case';patch=@{Case='historical-native'};message='case differs'},
                @{name='active';patch=@{Active=$true};message='fresh installed-MIR source run'},
                @{name='input';patch=@{InputSave='seed.zip'};message='active or input-save modes'},
                @{name='observer';patch=@{Observer='modern-observer'};message='modern observers or consumers'},
                @{name='historical';patch=@{HistoricalTarget='f110'};message='historical fixture parameters'},
                @{name='archive';patch=@{ExpectedMIRSha256=('0'*64)};message='MIR archive hash differs'},
                @{name='engine';patch=@{ExpectedEngineSha256=('0'*64)};message='profile engine differs'}
              )
              foreach($opponent in $opponents){
                $args=@{};foreach($key in $base.Keys){$args[$key]=$base[$key]};foreach($key in $opponent.patch.Keys){$args[$key]=$opponent.patch[$key]}
                $refused=$false
                try{Get-F110PublishedCrossSourceFixture @args|Out-Null}catch{$refused=$_.Exception.Message.Contains($opponent.message)}
                if(-not $refused){throw ('opponent accepted: '+$opponent.name)}
              }
              function Expect-ComposedSourceRefusal([string]$Name,[string]$Message,[hashtable]$Arguments=$base){
                $refused=$false
                try{Get-F110PublishedCrossSourceFixture @Arguments|Out-Null}catch{$refused=$_.Exception.Message.Contains($Message)}
                if(-not $refused){throw ('composed source opponent accepted: '+$Name)}
              }
              $canonical=Join-Path $env:MIR_TEST_REPO 'tests/fixtures/f110-f200-transition/f110/published-4.7.3'
              $shared=Join-Path $env:MIR_TEST_REPO 'tests/fixtures/f110-f200-transition/shared'
              $alias=Join-Path $env:MIR_TEST_SOURCE 'fixture_control.lua'
              Remove-Item -LiteralPath $alias
              Expect-ComposedSourceRefusal 'missing-alias' 'stage members differ'
              Copy-Item -LiteralPath (Join-Path $shared 'control.lua') -Destination $alias -Force
              [IO.File]::AppendAllText($alias,'changed')
              Expect-ComposedSourceRefusal 'changed-alias' 'stage member differs: fixture_control.lua'
              Copy-Item -LiteralPath (Join-Path $shared 'control.lua') -Destination $alias -Force
              $wrapper=Join-Path $env:MIR_TEST_SOURCE 'control.lua'
              [IO.File]::AppendAllText($wrapper,'changed')
              Expect-ComposedSourceRefusal 'wrong-wrapper' 'stage member differs: control.lua'
              Copy-Item -LiteralPath (Join-Path $canonical 'control.lua') -Destination $wrapper -Force
              $extra=Join-Path $env:MIR_TEST_SOURCE 'unexpected.lua'
              [IO.File]::WriteAllText($extra,'extra')
              Expect-ComposedSourceRefusal 'extra-member' 'stage members differ'
              Remove-Item -LiteralPath $extra
              $outside=Join-Path (Split-Path -Parent $env:MIR_TEST_REPO) 'outside-f110-composed'
              Copy-Item -LiteralPath $env:MIR_TEST_SOURCE -Destination $outside -Recurse
              $outsideArgs=@{};foreach($key in $base.Keys){$outsideArgs[$key]=$base[$key]};$outsideArgs.Sources=@($outside)
              Expect-ComposedSourceRefusal 'outside-checkout' 'must remain inside executing checkout' $outsideArgs
              Remove-Item -LiteralPath $outside -Recurse -Force
              $profile.mods[1].version='4.7.11002'
              $refused=$false;try{Get-F110PublishedCrossSourceFixture @base|Out-Null}catch{$refused=$_.Exception.Message.Contains('profile differs')}
              if(-not $refused){throw 'wrong three-mod profile accepted'}
              $profile.mods[1].version='4.7.11003'
              $infoPath=Join-Path $env:MIR_TEST_SOURCE 'info.json'
              $info=Get-Content -LiteralPath $infoPath -Raw|ConvertFrom-Json -AsHashtable
              $info.dependencies=@('base >= 1.1.110')
              foreach($path in @($infoPath,(Join-Path $canonical 'info.json'))){$info|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path}
              $refused=$false;try{Get-F110PublishedCrossSourceFixture @base|Out-Null}catch{$refused=$_.Exception.Message.Contains('fixture dependencies differ')}
              if(-not $refused){throw 'wrong fixture dependencies accepted'}
            '''
            env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_REPO=str(root),
                       MIR_TEST_PROFILE=str(profile_path), MIR_TEST_SOURCE=str(source),
                       MIR_TEST_ENGINE_DATA=str(engine_data), MIR_TEST_ENGINE=str(engine),
                       MIR_TEST_ENGINE_SHA=engine_sha, MIR_TEST_MIR_SHA=MIR_SHA)
            result = _run_powershell(script, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def _assert_actual_fixture_profile_composition(self, successor=False):
        """The caller-composed seven-file stage is bound to real tracked bytes."""
        with tempfile.TemporaryDirectory(prefix=".mir5-f110-composed-", dir=ROOT) as composed_work, \
                tempfile.TemporaryDirectory(prefix="mir5-f110-cross-actual-composition-") as work:
            source = Path(composed_work)
            self._compose_actual_fixture_source(source, successor)
            fixture_version = "0.3.0" if successor else "0.1.0"
            archive = Path(work) / f"{FIXTURE}_{fixture_version}.zip"
            with zipfile.ZipFile(archive, "w") as output:
                for member in sorted(source.iterdir()):
                    output.writestr(f"{FIXTURE}_{fixture_version}/{member.name}", member.read_bytes())
            engine_data = Path(work) / "engine" / "data"
            (engine_data / "base").mkdir(parents=True)
            (engine_data / "base" / "info.json").write_text(json.dumps({"version": "1.1.110"}), encoding="utf-8")
            engine = Path(work) / "factorio.exe"
            engine.write_bytes(b"host-only engine identity")
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              $tokens=$null;$errors=$null
              $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
              if($errors.Count){throw 'runner parse failed'}
              foreach($name in @('Assert-Fixture','Get-FixtureSha','Test-F110PublishedCrossSourceRelativePath','Get-F110PublishedCrossSourceFixture')){
                $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
                if($node.Count -ne 1){throw "helper missing: $name"}
                Invoke-Expression $node[0].Extent.Text
              }
              # A synthetic executable cannot have the pinned F110 digest.
              # All composed fixture members still hash through the real helper.
              function Get-FixtureSha([string]$Path){
                if([IO.Path]::GetFullPath($Path) -ceq [IO.Path]::GetFullPath($env:MIR_TEST_ENGINE)){return $env:MIR_TEST_ENGINE_SHA}
                return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
              }
              $profile=Get-Content -LiteralPath $env:MIR_TEST_PROFILE -Raw|ConvertFrom-Json -AsHashtable
              $result=Get-F110PublishedCrossSourceFixture -Repo $env:MIR_TEST_REPO -ProfileDefinition $profile -ProfileRows @($profile.mods) -Sources @($env:MIR_TEST_SOURCE) -EngineData $env:MIR_TEST_ENGINE_DATA -Engine $env:MIR_TEST_ENGINE -ExpectedMIRSha256 $env:MIR_TEST_MIR_SHA -Case 'f110-f200-transition' -Historical:$false -HistoricalTransition:$false -Create:$false -Absent:$false -Active:$false -ActiveKind '' -InputSave $env:MIR_TEST_INPUT_SAVE -InputSaveSha256 $env:MIR_TEST_INPUT_SHA -Observer '' -Markers @() -HistoricalTarget '' -HistoricalMetadata '' -TransitionStage '' -TransitionMetadata '' -ExpectedEngineSha256 $env:MIR_TEST_ENGINE_SHA -SameEditionSuccessor:($env:MIR_TEST_SAME -ceq 'true')
              if($env:MIR_TEST_SAME -ceq 'true'){
                function Expect-SuccessorRefusal([hashtable]$Changes,[string]$Message){
                  $p=@{Repo=$env:MIR_TEST_REPO;ProfileDefinition=$profile;ProfileRows=@($profile.mods);Sources=@($env:MIR_TEST_SOURCE);EngineData=$env:MIR_TEST_ENGINE_DATA;Engine=$env:MIR_TEST_ENGINE;ExpectedMIRSha256=$env:MIR_TEST_MIR_SHA;Case='f110-f200-transition';Historical=$false;HistoricalTransition=$false;Create=$false;Absent=$false;Active=$false;ActiveKind='';InputSave=$env:MIR_TEST_INPUT_SAVE;InputSaveSha256=$env:MIR_TEST_INPUT_SHA;Observer='';Markers=@();HistoricalTarget='';HistoricalMetadata='';TransitionStage='';TransitionMetadata='';ExpectedEngineSha256=$env:MIR_TEST_ENGINE_SHA;SameEditionSuccessor=$true}
                  foreach($key in $Changes.Keys){$p[$key]=$Changes[$key]}
                  $refused=$false;try{Get-F110PublishedCrossSourceFixture @p|Out-Null}catch{$refused=$_.Exception.Message.Contains($Message)}
                  if(-not $refused){throw ('successor opponent accepted: '+$Message)}
                }
                Expect-SuccessorRefusal @{InputSave=''} 'protected D524 source save'
                Expect-SuccessorRefusal @{InputSaveSha256=('0'*64)} 'protected D524 source save'
                Expect-SuccessorRefusal @{ExpectedMIRSha256=('0'*64)} 'MIR archive hash differs'
                Expect-SuccessorRefusal @{Observer='modern-observer'} 'modern observers or consumers'
                Expect-SuccessorRefusal @{Historical=$true} 'fresh installed-MIR source run'
                Expect-SuccessorRefusal @{Create=$true} 'fresh installed-MIR source run'
                $originalVersion=$profile.mods[1].version;$profile.mods[1].version='4.7.11003'
                Expect-SuccessorRefusal @{} 'profile differs'
                $profile.mods[1].version=$originalVersion
              }
              if($result.source -cne (Resolve-Path -LiteralPath $env:MIR_TEST_SOURCE).Path){throw 'actual source refused'}
              . (Join-Path $env:MIR_TEST_REPO 'tools/lib/validation/ImmutableInputStaging.ps1')
              . (Join-Path $env:MIR_TEST_REPO 'tools/lib/compatibility/LibraryActivation.ps1')
              Assert-MIRLibraryFixtureArchive -Archive $env:MIR_TEST_ARCHIVE -SourceDirectory $env:MIR_TEST_SOURCE
            '''
            env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_REPO=str(ROOT),
                       MIR_TEST_PROFILE=str(ROOT / ("tests/profiles/f110-473-current-successor-11110.json" if successor
                                                  else "tests/profiles/f110-f200-transition-published-f110-11110.json")),
                       MIR_TEST_SOURCE=str(source), MIR_TEST_ARCHIVE=str(archive),
                       MIR_TEST_ENGINE_DATA=str(engine_data), MIR_TEST_ENGINE=str(engine),
                       MIR_TEST_ENGINE_SHA=ENGINE_SHA,
                       MIR_TEST_MIR_SHA="1C3D982CD048D3C83BF75108F1F9AC769CE0DC833A2DE056CDE16EF8AE2925A9" if successor else MIR_SHA,
                       MIR_TEST_SAME="true" if successor else "false",
                       MIR_TEST_INPUT_SAVE="protected-source.zip" if successor else "",
                       MIR_TEST_INPUT_SHA="D524AA78440F242B179A1E9BC40BF89B87C1A66E99F64C14D3250DEAEBB69253" if successor else "")
            result = _run_powershell(script, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ast_extracted_preflight_accepts_the_actual_fixture_profile_composition(self):
        self._assert_actual_fixture_profile_composition()

    def test_same_edition_successor_requires_the_exact_protected_input_and_composition(self):
        self._assert_actual_fixture_profile_composition(successor=True)

    def test_generic_fixture_byte_verifier_remains_the_cross_source_archive_guard(self):
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn("Assert-MIRLibraryFixtureArchive -Archive $archive -SourceDirectory $source", source)
        self.assertNotIn("Assert-HistoricalFixtureArchive -Archive $archive -SourceDirectory $source -Fixture $f110CrossSourceFixture", source)
        with tempfile.TemporaryDirectory(prefix="mir5-f110-cross-archive-") as work:
            root = Path(work)
            source_dir = self._fixture_source(root)
            library = root / "library"
            library.mkdir()
            archive = library / f"{FIXTURE}_0.1.0.zip"
            with zipfile.ZipFile(archive, "w") as output:
                for member in source_dir.iterdir():
                    output.writestr(f"{FIXTURE}_0.1.0/{member.name}", member.read_bytes())
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              . (Join-Path $env:MIR_TEST_ROOT 'tools/lib/validation/ImmutableInputStaging.ps1')
              . (Join-Path $env:MIR_TEST_ROOT 'tools/lib/compatibility/LibraryActivation.ps1')
              Assert-MIRLibraryFixtureArchive -Archive $env:MIR_TEST_ARCHIVE -SourceDirectory $env:MIR_TEST_SOURCE
            '''
            # The generic verifier belongs to the checked-out runner's shared library;
            # the temporary fixture is only its bounded byte input.
            env = dict(os.environ, MIR_TEST_ROOT=str(ROOT), MIR_TEST_ARCHIVE=str(archive), MIR_TEST_SOURCE=str(source_dir))
            result = _run_powershell(script, env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ast_keeps_f110_process_mode_and_exact_case_stage_reload_prefixes(self):
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn("$historicalProcess=$historical -or $f110PublishedCrossSource -or $f110SameEditionSuccessor", source)
        self.assertIn("$historicalProcessVersion='1.1'", source)
        self.assertIn("if($historicalProcess){\n    # Older engines use the retained direct-library minimal form.", source)
        self.assertIn("New-HistoricalFixtureServerSettings (Join-Path $resources.root 'server-settings.json') $engineData $historicalProcessVersion", source)
        self.assertIn("$historicalServerArguments+@('--start-server',$seed)", source)
        self.assertIn("$reloadArguments=if($historicalProcess){$historicalServerArguments+@('--start-server',$complete)}", source)
        self.assertIn('[MIR5_NATIVE_FIXTURE] RESULT {"case":"f110-f200-transition","stage":"initial"', source)
        self.assertIn("$reloadCase=if($f110PublishedCrossSource -or $f110SameEditionSuccessor){'f110-f200-transition'}", source)
        script = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse failed'}
          foreach($name in @('Assert-Fixture','Read-FixtureResult')){
            $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw "helper missing: $name"};Invoke-Expression $node[0].Extent.Text
          }
          $processSelection=@($ast.FindAll({param($n)
            $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$historicalProcess'
          },$true))
          $versionSelection=@($ast.FindAll({param($n)
            $n -is [Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item2.Extent.Text.Contains('$historicalProcessVersion=')
          },$true))
          if($processSelection.Count -ne 1 -or $versionSelection.Count -ne 1){throw 'ambiguous F110 process routing'}
          $processRoute=[scriptblock]::Create($processSelection[0].Extent.Text)
          $versionRoute=[scriptblock]::Create($versionSelection[0].Extent.Text)
          foreach($mode in @('source','same-edition','neither')){
            $historical=$false;$f110PublishedCrossSource=$mode -ceq 'source';$f110SameEditionSuccessor=$mode -ceq 'same-edition'
            . $processRoute
            if($historicalProcess -ne ($mode -cne 'neither')){throw ('F110 process routing differs: '+$mode)}
            if($mode -cne 'neither'){
              $historicalProcessVersion='';. $versionRoute
              if($historicalProcessVersion -cne '1.1'){throw ('F110 server version differs: '+$mode)}
            }
          }
          $CaseName='f110-f200-transition'
          foreach($stage in @('initial','reload')){
            $text='[MIR5_NATIVE_FIXTURE] RESULT {"case":"f110-f200-transition","stage":"'+$stage+'","status":"passed"}'
            if((Read-FixtureResult $text $stage).stage -cne $stage){throw 'accepted marker changed stage'}
          }
          foreach($text in @(
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"other","stage":"initial","status":"passed"}',
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"f110-f200-transition","stage":"initial","status":"failed"}',
            '[MIR5_NATIVE_FIXTURE] RESULT {"case":"f110-f200-transition","stage":"reload","status":"passed"}'
          )){
            $refused=$false;try{Read-FixtureResult $text 'initial'|Out-Null}catch{$refused=$_.Exception.Message.Contains('missing unique passed initial witness')}
            if(-not $refused){throw 'invalid marker accepted'}
          }
        '''
        result = _run_powershell(script, dict(os.environ, MIR_TEST_RUNNER=str(RUNNER)))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path)
    parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(F110F200RunnerControls)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
