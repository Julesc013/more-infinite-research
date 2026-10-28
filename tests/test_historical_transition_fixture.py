"""Host controls for the eight exact-engine historical predecessor transition fixture.

These controls exercise only the fixture and its runner contract.  They do not
run Factorio or claim that a published save upgrades successfully.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/historical-transition"
FIXTURE_473 = FIXTURE / "metadata-473-f013-f016.json"
RUNNER = ROOT / "tools/Invoke-NativeFixture.ps1"
DIRECT_ORACLE = ROOT / "tests/fixtures/historical-direct-native-oracle.json"


class HistoricalTransitionFixtureControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        cls.direct_oracle = json.loads(DIRECT_ORACLE.read_text(encoding="utf-8"))

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def test_all_eight_profiles_pin_published_and_mir5_versions_without_extra_mods(self):
        # F013--F110 use accepted public 4.7.2 checksums. F018 is the earlier
        # published 1.8.0 archive, not an invented 4.7.018 predecessor.
        expected = {
            "f013": ("0.13.20", "4.7.01302", "5.0.01300", "69D02F628F1278B5D161B61E39DB4E3D1A5978E31D01638E2AE23E28594637C8", "preservation-only", False),
            "f014": ("0.14.23", "4.7.01402", "5.0.01400", "D34B6281A3815CD52AD91CABD1E1669650F2A2A761D9109DEDC07268D78D2CDE", "preservation-only", False),
            "f015": ("0.15.40", "4.7.01502", "5.0.01500", "758AA85BF41A10188DEA914AC456F672BAC7D3430E646CBDB6D761BE5ECC7B8A", "lab", False),
            "f016": ("0.16.51", "4.7.01602", "5.0.01600", "00053C78EE854EB8AE0CB5318F7A41E3C81E62F29FEB6E6DCE317635743520DB", "lab", False),
            "f017": ("0.17.79", "4.7.01702", "5.0.01700", "3FB8750565526816C1C33B3ADD6B82165B5AA6D026D47CD242251455FE5CFE32", "lab", True),
            "f018": ("0.18.47", "1.8.0", "5.0.01800", "D785E6EBE7A72E6E9F01A3F89774A6AA30479430410447F603FEF1E0B9BD7B24", "lab", True),
            "f100": ("1.0.0", "4.7.10002", "5.0.10000", "87A80EB76B30A73BC8F16A8F4B92AA59BA3CC400FF5921819CB5E9CEFAB745E0", "lab", True),
            "f110": ("1.1.110", "4.7.11002", "5.0.11000", "723159A24668E28EE70214CCCC727D5B104CAA0A9A7A7FD73B4938D55E5F3E91", "lab", True),
        }
        self.assertEqual(self.metadata["kind"], "MIR5HistoricalTransitionFixtureV1")
        self.assertEqual(set(self.metadata["targets"]), set(expected))
        for target, (base, published, mir5, archive_sha256, successor_mode, queue_api) in expected.items():
            with self.subTest(target=target):
                fact = self.metadata["targets"][target]
                self.assertEqual((fact["minimum_base"], fact["published_mir_version"], fact["mir_version"],
                                  fact["published_archive_sha256"]),
                                 (base, published, mir5, archive_sha256))
                self.assertEqual(fact["direct"], "recipe-prod-research_character_mining_speed-1")
                self.assertEqual(fact["successor_mode"], successor_mode)
                if successor_mode == "lab":
                    self.assertEqual(fact["partial_progress"], .42)
                else:
                    self.assertNotIn("partial_progress", fact)
                self.assertEqual(fact.get("queue_api", False), queue_api)
                if queue_api:
                    self.assertEqual(fact["queue_probe"], "braking-force-1")
                else:
                    self.assertNotIn("queue_probe", fact)
                if target == "f018":
                    self.assertEqual(fact["foreign_force_name"], "mir5-historical-transition-foreign")
                    self.assertEqual(fact["foreign_saved_progress"], .27)
                    self.assertEqual(
                        (fact["mir5_archive_sha256"], fact["published_unit_count_formula"], fact["mir5_unit_count_formula"]),
                        ("7803FC661DEFA441D1E9D508D1CA80029E619201BBECB0BF113D60D3D3ABEEB9", "8000 * 2^(L-1)", "1*(8000*2^(L-1))"),
                    )
                for role, version in (("published", published), ("mir5", mir5)):
                    profile = json.loads((ROOT / f"tests/profiles/historical-transition-{role}-{target}.json")
                                         .read_text(encoding="utf-8"))
                    self.assertEqual(profile["mods"], [
                        {"name": "base", "version": base, "enabled": True},
                        {"name": "more-infinite-research", "version": version, "enabled": True},
                        {"name": "mir-fixture-mir5-historical-transition", "version": "0.1.0", "enabled": True},
                    ])

    def test_runner_keeps_fresh_historical_mode_unchanged_and_requires_pinned_transition_input(self):
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn("[ValidateSet('','published','mir5')][string]$HistoricalTransitionStage=''", source)
        self.assertIn("Get-HistoricalTransitionFixtureTarget", source)
        self.assertIn("Assert-HistoricalTransitionFixtureArchive", source)
        self.assertIn("published historical transition must create a fresh predecessor save", source)
        self.assertIn("MIR5 historical transition requires an immutable predecessor save hash", source)
        self.assertIn("historical transition profile MIR version differs", source)
        self.assertIn("historical transition published archive hash differs", source)
        self.assertIn("f018=@{factorio_version='0.18';published_mir_version='1.8.0';mir_version='5.0.01800'}", source)
        self.assertIn("F018 historical transition foreign force differs", source)
        self.assertIn("F018 historical transition cost contract differs", source)
        self.assertIn("historical fixtures require a fresh full run", source)
        self.assertIn("historical-transition", source)
        self.assertIn("transition_stage", source)
        self.assertIn("$historical -and ($historicalFixture.target -in @('f013','f014','f015','f016'))", source)
        self.assertIn("$activationArguments.PrePinMIROwnedArchiveNames=@('more-infinite-research')", source)
        self.assertIn("freeze_source_lab", (FIXTURE / "control.lua").read_text(encoding="utf-8"))
        self.assertNotIn("New-MIR4HistoricalArchiveStage", source)

    def test_transition_metadata_literal_is_stage_specific_and_refuses_invalid_queue_contract(self):
        functions = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalTransitionFixtureTarget','ConvertTo-HistoricalTransitionFixtureTargetLiteral')){
            $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw ('missing '+$name)}
            Invoke-Expression $node[0].Extent.Text
          }
          $published=Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_METADATA -Stage published
          $mir5=Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_METADATA -Stage mir5
          if($published.mir_version -cne '4.7.01702' -or $mir5.mir_version -cne '5.0.01700'){throw 'stage version differs'}
          $literal=ConvertTo-HistoricalTransitionFixtureTargetLiteral $mir5
          if($literal -notmatch 'id="f017"' -or $literal -notmatch 'stage="mir5"' -or $literal -notmatch 'queue_probe="braking-force-1"'){throw 'literal differs'}
          $early=Get-HistoricalTransitionFixtureTarget -Target f013 -MetadataPath $env:MIR_TEST_METADATA -Stage mir5
          $earlyPublished=Get-HistoricalTransitionFixtureTarget -Target f013 -MetadataPath $env:MIR_TEST_METADATA -Stage published
          if($earlyPublished.mir_version -cne '4.7.01302' -or $early.mir_version -cne '5.0.01300'){throw 'default predecessor tuple differs'}
          $earlyLiteral=ConvertTo-HistoricalTransitionFixtureTargetLiteral $early
          if($earlyLiteral -notmatch 'successor_mode="preservation-only"' -or $earlyLiteral -match 'partial_progress'){throw 'early literal invented a successor state'}
          $f018=Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_METADATA -Stage published
          $f018Mir5=Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_METADATA -Stage mir5
          if($f018.mir_version -cne '1.8.0' -or $f018Mir5.mir_version -cne '5.0.01800'){throw 'F018 stage version differs'}
          $f018Literal=ConvertTo-HistoricalTransitionFixtureTargetLiteral $f018Mir5
          if($f018Literal -notmatch 'foreign_force_name="mir5-historical-transition-foreign"' -or $f018Literal -notmatch 'foreign_saved_progress=0.27'){throw 'F018 foreign literal differs'}
        '''
        env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_METADATA=str(FIXTURE / "metadata.json"))
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", functions], cwd=ROOT,
                                text=True, capture_output=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        # The explicit 4.7.3 predecessor variant shares this target-resolver
        # contract, while retaining the existing 4.7.2/F018 adverses below.
        expected = {
            "f013": ("4.7.01303", "5.0.01300", "3918B10A0902FABD09BEA6D1F0E7EFF06B20B84F3D8CC5EC73E36FEDAAE64D4D"),
            "f014": ("4.7.01403", "5.0.01400", "85C7798BD6DC80FAA021AB0F33519B57A740B8D3969E695A82BA55634BA1C87A"),
            "f015": ("4.7.01503", "5.0.01500", "0F8DD4DD21B8D1542FF5EDF96FDC38F75C9AB3CE577DF29C5E9DE99E0643B510"),
            "f016": ("4.7.01603", "5.0.01600", "DAC63B9B14278C952B1020F9AE600C1437A9812C79CBBA17DE3CB15AF0CED6BD"),
        }
        metadata = json.loads(FIXTURE_473.read_text(encoding="utf-8"))
        self.assertEqual((metadata["schema"], metadata["kind"], metadata["name"], metadata["version"],
                          metadata["predecessor_release"]),
                         (1, "MIR5HistoricalTransitionFixtureV1", "mir-fixture-mir5-historical-transition", "0.1.0", "v4.7.3"))
        self.assertEqual((metadata["published_release_id"], metadata["published_tag_source"]),
                         (422732162, "8643cc91bc915e008556a5315dbb0a743247e7ab"))
        self.assertEqual(set(metadata["targets"]), set(expected))
        for target, (published, mir5, archive) in expected.items():
            with self.subTest(metadata_target=target):
                fact = metadata["targets"][target]
                self.assertEqual((fact["published_mir_version"], fact["mir_version"], fact["published_archive_sha256"]),
                                 (published, mir5, archive))
                retained = self.metadata["targets"][target]
                changed_identity = {"published_mir_version", "published_archive_sha256"}
                self.assertEqual({key: value for key, value in fact.items() if key not in changed_identity},
                                 {key: value for key, value in retained.items() if key not in changed_identity})
                profile = json.loads((ROOT / f"tests/profiles/historical-transition-473-published-{target}.json")
                                     .read_text(encoding="utf-8"))
                self.assertEqual(profile["mods"], [
                    {"name": "base", "version": retained["minimum_base"], "enabled": True},
                    {"name": "more-infinite-research", "version": published, "enabled": True},
                    {"name": "mir-fixture-mir5-historical-transition", "version": "0.1.0", "enabled": True},
                ])
        v473_functions = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalTransitionFixtureTarget','ConvertTo-HistoricalTransitionFixtureTargetLiteral')){
            $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw ('missing '+$name)}
            Invoke-Expression $node[0].Extent.Text
          }
          $expected=@{
            f013=@{published='4.7.01303';mir5='5.0.01300';archive='3918B10A0902FABD09BEA6D1F0E7EFF06B20B84F3D8CC5EC73E36FEDAAE64D4D'}
            f014=@{published='4.7.01403';mir5='5.0.01400';archive='85C7798BD6DC80FAA021AB0F33519B57A740B8D3969E695A82BA55634BA1C87A'}
            f015=@{published='4.7.01503';mir5='5.0.01500';archive='0F8DD4DD21B8D1542FF5EDF96FDC38F75C9AB3CE577DF29C5E9DE99E0643B510'}
            f016=@{published='4.7.01603';mir5='5.0.01600';archive='DAC63B9B14278C952B1020F9AE600C1437A9812C79CBBA17DE3CB15AF0CED6BD'}
          }
          foreach($target in @('f013','f014','f015','f016')){
            $published=Get-HistoricalTransitionFixtureTarget -Target $target -MetadataPath $env:MIR_TEST_473 -Stage published
            $mir5=Get-HistoricalTransitionFixtureTarget -Target $target -MetadataPath $env:MIR_TEST_473 -Stage mir5
            $fact=$expected[$target]
            if($published.mir_version -cne $fact.published -or $mir5.mir_version -cne $fact.mir5 -or $published.definition.published_archive_sha256 -cne $fact.archive){throw ('v4.7.3 admission differs: '+$target)}
            $publishedLiteral=ConvertTo-HistoricalTransitionFixtureTargetLiteral $published
            $mir5Literal=ConvertTo-HistoricalTransitionFixtureTargetLiteral $mir5
            if($publishedLiteral -notmatch ('id="'+$target+'"') -or $publishedLiteral -notmatch 'stage="published"' -or $publishedLiteral -notmatch ('mir_version="'+$fact.published+'"')){throw ('v4.7.3 published literal differs: '+$target)}
            if($mir5Literal -notmatch ('id="'+$target+'"') -or $mir5Literal -notmatch 'stage="mir5"' -or $mir5Literal -notmatch ('mir_version="'+$fact.mir5+'"')){throw ('v4.7.3 MIR5 literal differs: '+$target)}
          }
        '''
        wrong_release = json.loads(json.dumps(metadata))
        wrong_release["predecessor_release"] = "v4.7.2"
        wrong_release_id = json.loads(json.dumps(metadata))
        wrong_release_id["published_release_id"] = 422732163
        wrong_release_id_type = json.loads(json.dumps(metadata))
        wrong_release_id_type["published_release_id"] = "422732162"
        wrong_tag_source = json.loads(json.dumps(metadata))
        wrong_tag_source["published_tag_source"] = "0" * 40
        wrong_hash = json.loads(json.dumps(metadata))
        wrong_hash["targets"]["f014"]["published_archive_sha256"] = "0" * 64
        stale_version = json.loads(json.dumps(metadata))
        stale_version["targets"]["f015"]["published_mir_version"] = "4.7.01502"
        extra_target = json.loads(json.dumps(metadata))
        extra_target["targets"]["f017"] = self.metadata["targets"]["f017"]
        with tempfile.TemporaryDirectory(prefix="mir5-historical-transition-473-") as work:
            root = Path(work)
            paths = {
                "release": root / "wrong-release.json",
                "release_id": root / "wrong-release-id.json",
                "release_id_type": root / "wrong-release-id-type.json",
                "tag_source": root / "wrong-tag-source.json",
                "hash": root / "wrong-hash.json",
                "version": root / "stale-version.json",
                "extra": root / "extra-target.json",
            }
            for key, value in (("release", wrong_release), ("release_id", wrong_release_id),
                               ("release_id_type", wrong_release_id_type), ("tag_source", wrong_tag_source), ("hash", wrong_hash),
                               ("version", stale_version), ("extra", extra_target)):
                paths[key].write_text(json.dumps(value), encoding="utf-8")
            v473_rejection = v473_functions + r'''
              $checks=@(
                @{path=$env:MIR_TEST_473_WRONG_RELEASE;target='f013';message='predecessor release'},
                @{path=$env:MIR_TEST_473_WRONG_RELEASE_ID;target='f013';message='published release id'},
                @{path=$env:MIR_TEST_473_WRONG_RELEASE_ID_TYPE;target='f013';message='published release id'},
                @{path=$env:MIR_TEST_473_WRONG_TAG_SOURCE;target='f013';message='published tag source'},
                @{path=$env:MIR_TEST_473_WRONG_HASH;target='f014';message='published archive hash'},
                @{path=$env:MIR_TEST_473_STALE_VERSION;target='f015';message='MIR versions differ'},
                @{path=$env:MIR_TEST_473_EXTRA_TARGET;target='f013';message='target set differs'}
              )
              foreach($check in $checks){
                $refused=$false
                try { Get-HistoricalTransitionFixtureTarget -Target $check.target -MetadataPath $check.path -Stage published | Out-Null }
                catch { if($_.Exception.Message -match $check.message){$refused=$true}else{throw} }
                if(-not $refused){throw ('invalid v4.7.3 metadata accepted: '+$check.message)}
              }
              $wrongTarget=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_473 -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'target is unsupported'){$wrongTarget=$true}else{throw} }
              if(-not $wrongTarget){throw 'v4.7.3 admitted unreviewed target'}
            '''
            v473_env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_473=str(FIXTURE_473),
                            MIR_TEST_473_WRONG_RELEASE=str(paths["release"]), MIR_TEST_473_WRONG_RELEASE_ID=str(paths["release_id"]),
                            MIR_TEST_473_WRONG_RELEASE_ID_TYPE=str(paths["release_id_type"]), MIR_TEST_473_WRONG_TAG_SOURCE=str(paths["tag_source"]),
                            MIR_TEST_473_WRONG_HASH=str(paths["hash"]),
                            MIR_TEST_473_STALE_VERSION=str(paths["version"]), MIR_TEST_473_EXTRA_TARGET=str(paths["extra"]))
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", v473_functions], cwd=ROOT,
                                    text=True, capture_output=True, env=v473_env, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", v473_rejection], cwd=ROOT,
                                    text=True, capture_output=True, env=v473_env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        broken = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        del broken["targets"]["f017"]["queue_probe"]
        stale = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        stale["targets"]["f017"]["published_mir_version"] = "4.7.01700"
        f018_wrong_version = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        f018_wrong_version["targets"]["f018"]["published_mir_version"] = "4.7.01802"
        f018_wrong_hash = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        f018_wrong_hash["targets"]["f018"]["published_archive_sha256"] = "0" * 64
        f018_wrong_mir_hash = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        f018_wrong_mir_hash["targets"]["f018"]["mir5_archive_sha256"] = "0" * 64
        f018_wrong_target = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        f018_wrong_target["targets"]["f018"] = f018_wrong_target["targets"]["f017"]
        with tempfile.TemporaryDirectory(prefix="mir5-historical-transition-bad-") as work:
            root = Path(work)
            broken_path, stale_path = root / "broken.json", root / "stale.json"
            wrong_version_path, wrong_hash_path, wrong_mir_hash_path, wrong_target_path = (
                root / "f018-wrong-version.json", root / "f018-wrong-hash.json", root / "f018-wrong-mir-hash.json", root / "f018-wrong-target.json"
            )
            broken_path.write_text(json.dumps(broken), encoding="utf-8")
            stale_path.write_text(json.dumps(stale), encoding="utf-8")
            wrong_version_path.write_text(json.dumps(f018_wrong_version), encoding="utf-8")
            wrong_hash_path.write_text(json.dumps(f018_wrong_hash), encoding="utf-8")
            wrong_mir_hash_path.write_text(json.dumps(f018_wrong_mir_hash), encoding="utf-8")
            wrong_target_path.write_text(json.dumps(f018_wrong_target), encoding="utf-8")
            rejection = functions + r'''
              $queueRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_BROKEN -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'queue probe'){$queueRefused=$true}else{throw} }
              if(-not $queueRefused){throw 'missing queue probe accepted'}
              $staleRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_STALE -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'MIR versions differ'){$staleRefused=$true}else{throw} }
              if(-not $staleRefused){throw 'stale 4.7.0 predecessor accepted'}
              $wrongVersionRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_F018_WRONG_VERSION -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'MIR versions differ'){$wrongVersionRefused=$true}else{throw} }
              if(-not $wrongVersionRefused){throw 'synthetic 4.7.018 predecessor accepted'}
              $wrongHashRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_F018_WRONG_HASH -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'published archive hash differs'){$wrongHashRefused=$true}else{throw} }
              if(-not $wrongHashRefused){throw 'wrong F018 predecessor hash accepted'}
              $wrongMirHashRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_F018_WRONG_MIR_HASH -Stage mir5 | Out-Null }
              catch { if($_.Exception.Message -match 'MIR5 archive hash differs'){$wrongMirHashRefused=$true}else{throw} }
              if(-not $wrongMirHashRefused){throw 'wrong F018 successor hash accepted'}
              $wrongTargetRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_F018_WRONG_TARGET -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'factorio version differs'){$wrongTargetRefused=$true}else{throw} }
              if(-not $wrongTargetRefused){throw 'F017 row admitted as F018'}
            '''
            env["MIR_TEST_BROKEN"] = str(broken_path)
            env["MIR_TEST_STALE"] = str(stale_path)
            env["MIR_TEST_F018_WRONG_VERSION"] = str(wrong_version_path)
            env["MIR_TEST_F018_WRONG_HASH"] = str(wrong_hash_path)
            env["MIR_TEST_F018_WRONG_MIR_HASH"] = str(wrong_mir_hash_path)
            env["MIR_TEST_F018_WRONG_TARGET"] = str(wrong_target_path)
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", rejection], cwd=ROOT,
                                    text=True, capture_output=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_transition_archive_guard_pins_stage_dependency_and_source_members(self):
        functions = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalTransitionFixtureTarget',
            'ConvertTo-HistoricalTransitionFixtureTargetLiteral','Assert-HistoricalTransitionFixtureArchive')){
            $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw ('missing '+$name)}
            Invoke-Expression $node[0].Extent.Text
          }
          $fixture=Get-HistoricalTransitionFixtureTarget -Target f013 -MetadataPath $env:MIR_TEST_METADATA -Stage published
        '''
        literal = subprocess.run(["pwsh", "-NoProfile", "-Command", functions +
                                  "ConvertTo-HistoricalTransitionFixtureTargetLiteral $fixture"], cwd=ROOT,
                                 text=True, capture_output=True, check=True,
                                 env=dict(os.environ, MIR_TEST_RUNNER=str(RUNNER),
                                          MIR_TEST_METADATA=str(FIXTURE / "metadata.json"))).stdout.strip() + "\n"
        info = {
            "name": self.metadata["name"], "version": self.metadata["version"], "factorio_version": "0.13",
            "title": "MIR historical save-transition fixture", "author": "MIR maintainers",
            "dependencies": ["base >= 0.13.20", "more-infinite-research = 4.7.01302"],
        }
        members = {name: (FIXTURE / name).read_bytes() for name in
                   ("control.lua", "settings-updates.lua", "data-final-fixes.lua", "target.lua")}
        members["target-literal.lua"] = literal.encode("utf-8")
        members["info.json"] = json.dumps(info).encode("utf-8")
        with tempfile.TemporaryDirectory(prefix="mir5-historical-transition-archive-") as work:
            root = Path(work)
            good, wrong = root / "good.zip", root / "wrong.zip"
            archive_root = self.metadata["name"] + "_" + self.metadata["version"] + "/"
            for path, dependency in ((good, info["dependencies"]),
                                     (wrong, ["base >= 0.13.20", "more-infinite-research = 4.7.01300"])):
                payload = dict(members)
                payload["info.json"] = json.dumps(dict(info, dependencies=dependency)).encode("utf-8")
                with zipfile.ZipFile(path, "w") as archive:
                    for name, value in payload.items():
                        archive.writestr(archive_root + name, value)
            for field in ("title", "author"):
                for defect in ("absent", "blank", "array"):
                    bad = dict(info)
                    if defect == "absent":
                        del bad[field]
                    else:
                        bad[field] = "  " if defect == "blank" else ["invalid"]
                    payload = dict(members)
                    payload["info.json"] = json.dumps(bad).encode("utf-8")
                    with zipfile.ZipFile(root / (field + "-" + defect + ".zip"), "w") as archive:
                        for name, value in payload.items():
                            archive.writestr(archive_root + name, value)
            check = r'''
              Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_GOOD -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $fixture
              $refused=$false
              try { Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_WRONG -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $fixture }
              catch { if($_.Exception.Message -match 'dependencies differ'){$refused=$true}else{throw} }
              if(-not $refused){throw 'wrong stage dependency accepted'}
              foreach($field in @('title','author')){
                foreach($defect in @('absent','blank','array')){
                  $refused=$false
                  try { Assert-HistoricalTransitionFixtureArchive -Archive (Join-Path $env:MIR_TEST_ARCHIVE_ROOT ($field+'-'+$defect+'.zip')) -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $fixture }
                  catch { if($_.Exception.Message -match ('info '+$field+' must be a nonempty string')){$refused=$true}else{throw} }
                  if(-not $refused){throw ('invalid metadata accepted: '+$field+'-'+$defect)}
                }
              }
            '''
            env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_METADATA=str(FIXTURE / "metadata.json"),
                       MIR_TEST_GOOD=str(good), MIR_TEST_WRONG=str(wrong), MIR_TEST_SOURCE=str(FIXTURE),
                       MIR_TEST_ARCHIVE_ROOT=str(root))
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", functions + check], cwd=ROOT,
                                    text=True, capture_output=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_f018_transition_archive_guard_composes_only_the_real_predecessor_or_successor_dependency(self):
        functions = r'''
          $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalTransitionFixtureTarget',
            'ConvertTo-HistoricalTransitionFixtureTargetLiteral','Assert-HistoricalTransitionFixtureArchive')){
            $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw ('missing '+$name)}
            Invoke-Expression $node[0].Extent.Text
          }
        '''
        members = {name: (FIXTURE / name).read_bytes() for name in
                   ("control.lua", "settings-updates.lua", "data-final-fixes.lua", "target.lua")}
        with tempfile.TemporaryDirectory(prefix="mir5-f018-transition-archive-") as work:
            root = Path(work)
            published, mir5, wrong = root / "published.zip", root / "mir5.zip", root / "wrong.zip"
            for stage, path, expected_dependency in (
                ("published", published, "more-infinite-research = 1.8.0"),
                ("mir5", mir5, "more-infinite-research = 5.0.01800"),
                ("mir5", wrong, "more-infinite-research = 4.7.01802"),
            ):
                literal = (subprocess.run(
                    ["pwsh", "-NoProfile", "-Command", functions +
                     f"$fixture=Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_METADATA -Stage {stage}; ConvertTo-HistoricalTransitionFixtureTargetLiteral $fixture"],
                    cwd=ROOT, text=True, capture_output=True, check=True,
                    env=dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_METADATA=str(FIXTURE / "metadata.json")),
                ).stdout.strip() + "\n").encode("utf-8")
                payload = dict(members)
                payload["target-literal.lua"] = literal
                payload["info.json"] = json.dumps({
                    "name": self.metadata["name"], "version": self.metadata["version"], "factorio_version": "0.18",
                    "title": "MIR historical save-transition fixture", "author": "MIR maintainers",
                    "dependencies": ["base >= 0.18.47", expected_dependency],
                }).encode("utf-8")
                archive_root = self.metadata["name"] + "_" + self.metadata["version"] + "/"
                with zipfile.ZipFile(path, "w") as archive:
                    for name, value in payload.items():
                        archive.writestr(archive_root + name, value)
            check = r'''
              $published=Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_METADATA -Stage published
              $mir5=Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_METADATA -Stage mir5
              Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_PUBLISHED -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $published
              Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_MIR5 -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $mir5
              $refused=$false
              try { Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_WRONG -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $mir5 }
              catch { if($_.Exception.Message -match 'dependencies differ'){$refused=$true}else{throw} }
              if(-not $refused){throw 'synthetic 4.7.018 transition dependency accepted'}
            '''
            result = subprocess.run(
                ["pwsh", "-NoProfile", "-Command", functions + check], cwd=ROOT, text=True, capture_output=True,
                env=dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_METADATA=str(FIXTURE / "metadata.json"),
                         MIR_TEST_PUBLISHED=str(published), MIR_TEST_MIR5=str(mir5), MIR_TEST_WRONG=str(wrong),
                         MIR_TEST_SOURCE=str(FIXTURE)), check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_published_to_mir5_mock_preserves_partial_progress_and_queue_until_real_successor_event(self):
        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.globals().control = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          package.path = fixture .. "/?.lua"
          callbacks = {events={}}
          script = {
            on_init=function(f) callbacks.init=f end,
            on_configuration_changed=function(f) callbacks.configuration=f end,
            on_load=function(f) callbacks.load=f end,
            on_event=function(event,f) callbacks.events[event]=f end,
          }
          defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
          messages,saves={},{}
          log=function(value)table.insert(messages,value)end
          function install_target(stage, queue, old_lab)
            local id=queue and "f017" or (old_lab and "f015" or "f013")
            fixture_target={id=id,stage=stage,mir_version=stage == "published" and (queue and "4.7.01702" or (old_lab and "4.7.01502" or "4.7.01302")) or (queue and "5.0.01700" or (old_lab and "5.0.01500" or "5.0.01300")),
              direct="recipe-prod-research_character_mining_speed-1",direct_effect=.05,
              direct_science=queue and {"military-science-pack","utility-science-pack"} or {"alien-science-pack"},
              successor_mode=(queue or old_lab) and "lab" or "preservation-only",partial_progress=(queue or old_lab) and .42 or nil,
              queue_api=queue,queue_probe=queue and "braking-force-1" or nil}
            package.loaded.target=nil;package.loaded["target-literal"]=nil
            package.preload["target-literal"]=function()return fixture_target end
          end
          function mock_world(queue)
            local direct={name="recipe-prod-research_character_mining_speed-1",level=1,researched=false,enabled=true,prerequisites={}}
            local braking={name="braking-force-1",level=1,researched=false,enabled=true,prerequisites={}}
            local force={technologies={[direct.name]=direct,[braking.name]=braking},manual_mining_speed_modifier=0,research_progress=0,research_queue_enabled=not queue}
            setmetatable(force,{__index=function(t,key)
              if key == "current_research" then return rawget(t,"_current") end
              if key == "research_queue" then return rawget(t,"_queue") or {} end
              if key == "get_spawn_position" then return function()return {x=0,y=0}end end
            end,__newindex=function(t,key,value)
              if key == "current_research" then
                if queue then error("LuaForce::current_research is read only") end
                rawset(t,"_current",type(value)=="string" and t.technologies[value] or value)
              elseif key == "research_queue" then
                if queue and t.research_queue_enabled ~= true then error("LuaForce::research_queue is unavailable while disabled") end
                local rows={};for index,item in ipairs(value) do rows[index]=type(item)=="string" and t.technologies[item] or item end;rawset(t,"_queue",rows);rawset(t,"_current",rows[1])
              else rawset(t,key,value) end
            end})
            function force.add_research(value)
              if type(value)=="string" then value=force.technologies[value] end
              if queue and force.research_queue_enabled ~= true then return false end
              if not value or force.current_research ~= nil then return false end
              force.research_queue={value}
              return true
            end
            local function lab()
              local counts={};local inventory={insert=function(stack)counts[stack.name]=(counts[stack.name] or 0)+stack.count;return stack.count end,get_item_count=function(name)return counts[name] or 0 end}
              return {valid=true,active=true,energy=0,get_inventory=function()return inventory end},counts
            end
            local surface={create_entity=function()local value=lab();return value end}
            direct.force=force;braking.force=force
            game={active_mods={["more-infinite-research"]=true},forces={player=force},surfaces={[1]=surface},tick=1,
              server_save=function(name)table.insert(saves,name)end}
            return force,direct,braking
          end
          function execute_transition(queue, old_lab)
            callbacks={events={}};install_target("published",queue,old_lab);local force,direct,braking=mock_world(queue);global={}
            if queue then
              local readonly,message=pcall(function()force.current_research=direct end)
              assert(not readonly and tostring(message):find("read only",1,true),"modern mock accepted a current_research write")
              assert(force.research_queue_enabled == false and force.add_research(direct) == false
                and force.current_research == nil and #force.research_queue == 0,"disabled queue admitted research")
            end
            assert(loadfile(control,"t",_ENV))();callbacks.init()
            assert(force.current_research == direct)
            if queue then assert(force.research_queue_enabled == true and #force.research_queue == 1 and force.research_queue[1] == direct) end
            -- Factorio's initial --create path invokes on_load after on_init
            -- while the published direct research is active.  It is not a
            -- completed-save reload witness and must not change fixture state.
            local before=global.mir5_historical_transition.phase;callbacks.load();assert(global.mir5_historical_transition.phase == before)
            force.manual_mining_speed_modifier=fixture_target.direct_effect
            if queue or old_lab then direct.level=2 else direct.researched=true;force.current_research=nil end
            local source=global.mir5_historical_transition.source_lab
            for _,name in ipairs(fixture_target.direct_science) do source.get_inventory().insert{name=name,count=-1} end
            callbacks.events[defines.events.on_research_finished]({research=direct})
            if queue or old_lab then
              assert(global.mir5_historical_transition.phase == "published-partial-pending" and force.current_research == direct)
              callbacks.events[defines.events.on_tick]()
              assert(global.mir5_historical_transition.phase == "published-partial-pending")
              if queue then force.research_queue={} else force.current_research=nil end
              callbacks.events[defines.events.on_tick]()
              assert(force.current_research == direct and math.abs(force.research_progress-.42)<.000001)
              if queue then assert(force.research_queue_enabled == true and #force.research_queue == 2 and force.research_queue[2] == braking) end
            else assert(force.current_research == nil and direct.researched) end
            callbacks.events[defines.events.on_tick]()
            assert(saves[#saves] == "mir5-native-complete")
            -- The initial source load above must not be mistaken for a cold
            -- reload once the published save becomes ready.
            callbacks.events[defines.events.on_tick]()
            before=global.mir5_historical_transition.phase;callbacks.load();assert(global.mir5_historical_transition.phase == before);callbacks.events[defines.events.on_tick]()
            -- Model the source save loading again immediately before the
            -- successor configuration.  The configuration callback clears
            -- its local witness latch before starting MIR5 research.
            callbacks.load();assert(global.mir5_historical_transition.phase == before)
            fixture_target.stage="mir5"
            fixture_target.mir_version=queue and "5.0.01700" or (old_lab and "5.0.01500" or "5.0.01300")
            callbacks.configuration({})
            if queue or old_lab then
              assert(global.mir5_historical_transition.phase == "mir5-successor" and force.current_research == direct)
              direct.level=3;force.manual_mining_speed_modifier=2*fixture_target.direct_effect
              if queue then force.research_queue={braking} else force.current_research=nil end
              callbacks.events[defines.events.on_research_finished]({research=direct})
              if queue then assert(force.current_research == braking and #force.research_queue == 1) else assert(force.current_research == nil) end
            else assert(global.mir5_historical_transition.phase == "mir5-complete" and direct.researched and force.current_research == nil) end
            callbacks.events[defines.events.on_tick]();assert(saves[#saves] == "mir5-native-complete")
            -- A retained published-ready latch would reject this MIR5 tick.
            -- Its absence proves configuration discarded the pre-successor
            -- source-load observation before the successor started.
            callbacks.events[defines.events.on_tick]()
            before=global.mir5_historical_transition.phase;callbacks.load();assert(global.mir5_historical_transition.phase == before);callbacks.events[defines.events.on_tick]()
            return table.concat(messages,"\n")
          end
        ''')
        for queue, old_lab in ((False, False), (False, True), (True, False)):
            with self.subTest(queue_api=queue, old_lab=old_lab):
                witness = self.lua.eval("execute_transition")(queue, old_lab)
                self.assertIn('"transition_stage":"published"', witness)
                self.assertIn('"transition_stage":"mir5"', witness)
                self.assertIn('"stage":"reload"', witness)
                target = "f017" if queue else ("f015" if old_lab else "f013")
                markers = [
                    json.loads(line.split(" RESULT ", 1)[1])
                    for line in witness.splitlines()
                    if "[MIR5_NATIVE_FIXTURE] RESULT " in line
                    and f'"target":"{target}"' in line
                ]
                self.assertTrue(markers, "fixture did not emit a parseable native result marker")
                for marker in markers:
                    self.assertEqual(marker["queue_api"], queue)
                    if queue:
                        self.assertIs(marker["research_queue_enabled"], True)
                    else:
                        self.assertIsNone(marker["research_queue_enabled"])

        self.lua.execute(r'''
          callbacks={events={}};install_target("mir5",true);mock_world(true);global={}
          assert(loadfile(control,"t",_ENV))()
          local ok,message=pcall(function()callbacks.configuration({})end)
          assert(not ok and tostring(message):find("lacks the published fixture state",1,true))
        ''')

    def test_f018_same_engine_transition_uses_force_saved_progress_and_refuses_foreign_state_before_successor_write(self):
        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.globals().control = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          package.path=fixture .. "/?.lua"
          function f018_install_target(stage)
            fixture_target={id="f018",stage=stage,mir_version=stage == "published" and "1.8.0" or "5.0.01800",
              direct="recipe-prod-research_character_mining_speed-1",direct_effect=.05,
              direct_science={"military-science-pack","utility-science-pack"},successor_mode="lab",partial_progress=.42,
              queue_api=true,queue_probe="braking-force-1",foreign_force_name="mir5-historical-transition-foreign",
              foreign_saved_progress=.27}
            package.loaded.target=nil;package.loaded["target-literal"]=nil
            package.preload["target-literal"]=function()return fixture_target end
          end
          function f018_force(name)
            local function strict_technology(name)
              local value={name=name,level=1,researched=false,enabled=true,prerequisites={}}
              setmetatable(value,{__index=function(_,key)
                if key == "saved_progress" then error("LuaTechnology::saved_progress is unavailable on 0.18") end
              end,__newindex=function(table,key,value)
                if key == "saved_progress" then error("LuaTechnology::saved_progress is unavailable on 0.18") end
                rawset(table,key,value)
              end})
              return value
            end
            local direct=strict_technology("recipe-prod-research_character_mining_speed-1")
            local braking=strict_technology("braking-force-1")
            local saved={}
            local force={name=name,technologies={[direct.name]=direct,[braking.name]=braking},manual_mining_speed_modifier=0,
              research_progress=0,research_queue_enabled=false}
            setmetatable(force,{__index=function(table,key)
              if key == "current_research" then return rawget(table,"_current") end
              if key == "research_queue" then return rawget(table,"_queue") or {} end
              if key == "get_spawn_position" then return function()return {x=0,y=0}end end
            end,__newindex=function(table,key,value)
              if key == "current_research" then error("LuaForce::current_research is read only")
              elseif key == "research_queue" then
                if table.research_queue_enabled ~= true then error("LuaForce::research_queue is unavailable while disabled") end
                local rows={};for index,item in ipairs(value) do rows[index]=type(item)=="string" and table.technologies[item] or item end
                rawset(table,"_queue",rows);rawset(table,"_current",rows[1])
              else rawset(table,key,value) end
            end})
            function force.add_research(value)
              if type(value)=="string" then value=force.technologies[value] end
              if force.research_queue_enabled ~= true or not value or force.current_research ~= nil then return false end
              force.research_queue={value};return true
            end
            function force.get_saved_technology_progress(technology)
              local name=type(technology)=="string" and technology or technology.name
              return saved[name]
            end
            function force.set_saved_technology_progress(technology,progress)
              local name=type(technology)=="string" and technology or technology.name
              local row=force.technologies[name]
              assert(row and not row.researched and force.current_research ~= row and progress > 0 and progress < 1)
              saved[name]=progress
            end
            direct.force=force;braking.force=force
            return force,direct,braking
          end
          function f018_world()
            local creates=0
            local function lab()
              local counts={};local inventory={insert=function(stack)counts[stack.name]=(counts[stack.name] or 0)+stack.count;return stack.count end,
                get_item_count=function(name)return counts[name] or 0 end}
              return {valid=true,active=true,energy=0,get_inventory=function()return inventory end}
            end
            local surface={create_entity=function()creates=creates+1;return lab()end}
            return surface,function()return creates end
          end
          function f018_run(corruption)
            callbacks={events={}};messages,saves={},{}
            script={on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.configuration=f end,
              on_load=function(f)callbacks.load=f end,on_event=function(event,f)callbacks.events[event]=f end}
            defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
            log=function(value)table.insert(messages,value)end
            local player,direct,braking=f018_force("player")
            local surface,created=f018_world()
            game={active_mods={["more-infinite-research"]=true},forces={player=player},surfaces={[1]=surface},tick=1,
              server_save=function(name)table.insert(saves,name)end}
            function game.create_force(name)
              assert(game.forces[name] == nil,"foreign force already exists")
              local force=f018_force(name);game.forces[name]=force;return force
            end
            global={};f018_install_target("published");assert(loadfile(control,"t",_ENV))();callbacks.init()
            local foreign=game.forces[fixture_target.foreign_force_name]
            assert(foreign and foreign.technologies[fixture_target.direct].enabled == false
              and math.abs(foreign.get_saved_technology_progress(fixture_target.direct)-.27)<.000001)
            local readable=pcall(function()return foreign.technologies[fixture_target.direct].saved_progress end)
            local writable=pcall(function()foreign.technologies[fixture_target.direct].saved_progress=.27 end)
            assert(not readable and not writable,"fixture read or wrote unavailable LuaTechnology.saved_progress")
            player.manual_mining_speed_modifier=.05;direct.level=2
            local source=global.mir5_historical_transition.source_lab
            for _,name in ipairs(fixture_target.direct_science) do source.get_inventory().insert{name=name,count=-1} end
            callbacks.events[defines.events.on_research_finished]({research=direct})
            player.research_queue={};callbacks.events[defines.events.on_tick]();callbacks.events[defines.events.on_tick]()
            assert(global.mir5_historical_transition.phase == "published-ready" and saves[#saves] == "mir5-native-complete")
            if corruption == "published-reload" then
              -- This is the protected predecessor save's own cold reload,
              -- before successor configuration can observe it.
              foreign.set_saved_technology_progress(fixture_target.direct,.26)
              callbacks.load();local ok,message=pcall(function()callbacks.events[defines.events.on_tick]()end)
              return ok,tostring(message),created(),created(),table.concat(messages,"\n")
            end
            callbacks.load();callbacks.events[defines.events.on_tick]()
            fixture_target.stage="mir5";fixture_target.mir_version="5.0.01800"
            if corruption == "configuration" then
              foreign.set_saved_technology_progress(fixture_target.direct,.26)
              local before=created();local ok,message=pcall(function()callbacks.configuration({})end)
              return ok,tostring(message),before,created(),table.concat(messages,"\n")
            end
            callbacks.configuration({})
            assert(global.mir5_historical_transition.phase == "mir5-successor" and created() == 2
              and math.abs(foreign.get_saved_technology_progress(fixture_target.direct)-.27)<.000001)
            direct.level=3;player.manual_mining_speed_modifier=.10;player.research_queue={braking}
            callbacks.events[defines.events.on_research_finished]({research=direct});callbacks.events[defines.events.on_tick]()
            assert(global.mir5_historical_transition.phase == "mir5-complete" and saves[#saves] == "mir5-native-complete")
            if corruption == "reload" then
              foreign.set_saved_technology_progress(fixture_target.direct,.26)
              callbacks.load();local ok,message=pcall(function()callbacks.events[defines.events.on_tick]()end)
              return ok,tostring(message),created(),created(),table.concat(messages,"\n")
            end
            callbacks.load();callbacks.events[defines.events.on_tick]()
            return true,"",created(),created(),table.concat(messages,"\n")
          end
        ''')
        good = self.lua.eval("f018_run")(None)
        self.assertTrue(good[0], good[1])
        markers = [
            json.loads(line.split(" RESULT ", 1)[1])
            for line in good[4].splitlines()
            if "[MIR5_NATIVE_FIXTURE] RESULT " in line and '"target":"f018"' in line
        ]
        self.assertTrue(markers)
        for marker in markers:
            self.assertTrue(marker["queue_api"])
            self.assertTrue(marker["research_queue_enabled"])
            self.assertEqual(marker["foreign_saved_progress"], .27)

        prewrite = self.lua.eval("f018_run")("configuration")
        self.assertFalse(prewrite[0])
        self.assertIn("disabled foreign state differs", prewrite[1])
        self.assertEqual(prewrite[2:], (1, 1, prewrite[4]))

        reload = self.lua.eval("f018_run")("reload")
        self.assertFalse(reload[0])
        self.assertIn("disabled foreign state differs", reload[1])

        corrupted_published_reload = self.lua.eval("f018_run")("published-reload")
        self.assertFalse(corrupted_published_reload[0])
        self.assertIn("disabled foreign state differs", corrupted_published_reload[1])

    def test_data_final_preflight_accepts_each_pinned_cost_shape_before_acceleration(self):
        # This retained oracle characterizes earlier 4.2.2-era native inputs;
        # it is deliberately not the default 4.7.2 source contract below.
        self.assertEqual(self.direct_oracle["kind"], "MIR5HistoricalDirectNativeCharacterizationV1")
        self.assertEqual(self.direct_oracle["status"], "historical-characterization-not-mir5-native-qualification")
        expected_costs = {
            "f013": (8000, None, None),
            "f014": (8000, None, None),
            "f015": (None, "8000*2^(L-1)", "1*(8000*2^(L-1))"),
            "f016": (None, "8000*2^(L-1)", "1*(8000*2^(L-1))"),
            "f017": (None, "8000*2^(L-1)", "1*(8000*2^(L-1))"),
            "f018": (None, "8000 * 2^(L-1)", "1*(8000*2^(L-1))"),
            "f100": (None, "8000*2^(L-1)", "1*(8000*2^(L-1))"),
            "f110": (None, "8000*2^(L-1)", "1*(8000*2^(L-1))"),
        }
        published_f017 = self.metadata["published_4_7_2_f017_preflight"]
        self.assertEqual(published_f017, {
            "kind": "published-4.7.2-native-data-stage-observation",
            "native_run": 40024011863,
            "unit_count_formula": "8000*2^(L-1)",
            "unit_time": 60,
            "direct_effect": .05,
            "direct_science": ["utility-science-pack", "military-science-pack"],
        })
        self.assertEqual(self.metadata["published_1_8_0_f018_preflight"], {
            "kind": "published-1.8.0-source-data-stage-contract",
            "source_commit": "5662c66c372e6aca025eab9f446de55a5cc6c1c9",
            "published_archive_sha256": "D785E6EBE7A72E6E9F01A3F89774A6AA30479430410447F603FEF1E0B9BD7B24",
            "unit_count_formula": "8000 * 2^(L-1)",
            "unit_time": 60,
            "direct_effect": .05,
            "direct_science": ["military-science-pack", "utility-science-pack"],
        })

        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.globals().data_final = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          package.path=fixture .. "/?.lua"
          function data_final_row(id, stage, expected_effect, actual_effect, expected_science, actual_science, count, count_formula)
            package.loaded.target=nil;package.loaded["target-literal"]=nil
            package.preload["target-literal"]=function()return {id=id,stage=stage,mir_version=id == "f018" and (stage == "published" and "1.8.0" or "5.0.01800") or ("4.7." .. id:sub(2) .. "02"),
              direct="recipe-prod-research_character_mining_speed-1",direct_effect=expected_effect,successor_mode=(id == "f013" and "preservation-only" or "lab"),partial_progress=.42,
              direct_science=expected_science,queue_api=id == "f017",queue_probe=id == "f017" and "braking-force-1" or nil}end
            local ingredients={};for index,name in ipairs(actual_science) do ingredients[index]={name,1} end
            local row={type="technology",name="recipe-prod-research_character_mining_speed-1",level=1,upgrade=true,max_level="infinite",enabled=true,
              unit={count=count,count_formula=count_formula,time=60,ingredients=ingredients},effects={{type="character-mining-speed",modifier=actual_effect}}}
            data={raw={technology={[row.name]=row}}}
            local diagnostics={};log=function(value)diagnostics[#diagnostics+1]=value end
            local ok,message=pcall(function()assert(loadfile(data_final,"t",_ENV))()end)
            return ok,tostring(message),row,diagnostics[1]
          end
        ''')
        for target, (count, published_formula, mir5_formula) in expected_costs.items():
            fact = self.metadata["targets"][target]
            for stage, formula in (("published", published_formula), ("mir5", mir5_formula)):
                with self.subTest(target=target, stage=stage):
                    observed_count = count if count is not None else 16000
                    good = self.lua.eval("data_final_row")(target, stage, fact["direct_effect"], fact["direct_effect"],
                                                            self.lua.table_from(fact["direct_science"]), self.lua.table_from(fact["direct_science"]),
                                                            observed_count, formula)
                    self.assertTrue(good[0])
                    self.assertEqual((good[2]["unit"]["count"], good[2]["unit"]["count_formula"], good[2]["unit"]["time"]),
                                     (1, None, 1))
                    self.assertIn(f"target={target}", good[3])
                    self.assertIn(f"count={observed_count}", good[3])
                    self.assertIn(f"count_formula={formula if formula is not None else 'nil'}", good[3])
                    self.assertIn("time=60", good[3])
                    self.assertIn("science=" + ",".join(f"{name}:1" for name in fact["direct_science"]), good[3])
                    self.assertIn(f"effects=character-mining-speed:modifier={fact['direct_effect']}:recipe=nil:change=nil", good[3])

                    alternate = mir5_formula if stage == "published" else published_formula
                    wrong_formula = alternate if alternate != formula else "8000*1.5^(L-1)"
                    bad_formula = self.lua.eval("data_final_row")(target, stage, fact["direct_effect"], fact["direct_effect"],
                                                                   self.lua.table_from(fact["direct_science"]), self.lua.table_from(fact["direct_science"]),
                                                                   observed_count, wrong_formula)
                    self.assertFalse(bad_formula[0])
                    self.assertIn("cost or time differs", bad_formula[1])
                    self.assertEqual((bad_formula[2]["unit"]["count"], bad_formula[2]["unit"]["count_formula"], bad_formula[2]["unit"]["time"]),
                                     (observed_count, wrong_formula, 60))
                    self.assertIn(f"count_formula={wrong_formula}", bad_formula[3])

                    reordered = list(reversed(fact["direct_science"]))
                    same_science = self.lua.eval("data_final_row")(target, stage, fact["direct_effect"], fact["direct_effect"],
                                                                      self.lua.table_from(fact["direct_science"]), self.lua.table_from(reordered),
                                                                      observed_count, formula)
                    self.assertTrue(same_science[0])
                    repeated = [fact["direct_science"][0]] * len(fact["direct_science"])
                    bad_science = self.lua.eval("data_final_row")(target, stage, fact["direct_effect"], fact["direct_effect"],
                                                                     self.lua.table_from(fact["direct_science"]), self.lua.table_from(repeated),
                                                                     observed_count, formula)
                    self.assertEqual(len(fact["direct_science"]) == 1, bad_science[0])
                    if len(fact["direct_science"]) != 1:
                        self.assertIn("science differs", bad_science[1])

        unknown = self.lua.eval("data_final_row")("f999", "published", .05, .05,
                                                   self.lua.table_from(("military-science-pack", "utility-science-pack")),
                                                   self.lua.table_from(("military-science-pack", "utility-science-pack")), 8000,
                                                   expected_costs["f015"][1])
        self.assertFalse(unknown[0])
        self.assertIn("target cost family differs", unknown[1])

    def test_data_final_preflight_rejects_wrong_authored_effect_before_acceleration(self):
        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.globals().data_final = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          package.path=fixture .. "/?.lua"
          function data_final_effect_row(id, expected_effect, actual_effect, science, count_formula)
            package.loaded.target=nil;package.loaded["target-literal"]=nil
            package.preload["target-literal"]=function()return {id=id,stage="published",mir_version="4.7." .. id:sub(2) .. "02",
              direct="recipe-prod-research_character_mining_speed-1",direct_effect=expected_effect,successor_mode="lab",partial_progress=.42,
              direct_science=science,queue_api=id == "f017",queue_probe=id == "f017" and "braking-force-1" or nil}end
            local ingredients={};for index,name in ipairs(science) do ingredients[index]={name,1} end
            local row={type="technology",name="recipe-prod-research_character_mining_speed-1",level=1,upgrade=true,max_level="infinite",enabled=true,
              unit={count=8000,count_formula=count_formula,time=60,ingredients=ingredients},effects={{type="character-mining-speed",modifier=actual_effect}}}
            data={raw={technology={[row.name]=row}}}
            log=function() end
            local ok,message=pcall(function()assert(loadfile(data_final,"t",_ENV))()end)
            return ok,tostring(message),row
          end
        ''')
        bad = self.lua.eval("data_final_effect_row")("f017", .05, .1,
                                                       self.lua.table_from(("utility-science-pack", "military-science-pack")),
                                                       "8000*2^(L-1)")
        self.assertFalse(bad[0])
        self.assertIn("effect differs", bad[1])
        self.assertEqual((bad[2]["unit"]["count"], bad[2]["unit"]["count_formula"], bad[2]["unit"]["time"]),
                         (8000, "8000*2^(L-1)", 60))

        f018_bad = self.lua.eval("data_final_effect_row")(
            "f018", .05, .1,
            self.lua.table_from(("military-science-pack", "utility-science-pack")),
            "8000 * 2^(L-1)",
        )
        self.assertFalse(f018_bad[0])
        self.assertIn("effect differs", f018_bad[1])
        # Rejection precedes the fixture's count/time acceleration.
        self.assertEqual((f018_bad[2]["unit"]["count"], f018_bad[2]["unit"]["count_formula"], f018_bad[2]["unit"]["time"]),
                         (8000, "8000 * 2^(L-1)", 60))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    global LuaRuntime
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(HistoricalTransitionFixtureControls)
    )
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
