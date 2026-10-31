"""Pure host controls for the target-parameterized historical native fixture.

These checks characterize source composition and runner routing only. They do
not claim an engine result; the eight exact engines execute the fixture later.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/historical-native"
TRANSITION_FIXTURE = ROOT / "tests/fixtures/historical-transition"
RUNNER = ROOT / "tools/Invoke-NativeFixture.ps1"
ALL_SCIENCE_METADATA = FIXTURE / "metadata-all-science.json"
DEFAULT_METADATA_SHA256 = "1fb15c0f79d19cc40912eb7010842d4e5c81f0986cd9d383307c03b4419bcd0a"


class HistoricalNativeFixtureControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.metadata = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))

    def test_actual_owned_version_selector_covers_fresh_and_transition_old_engines(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null; $errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile(
            $env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse failed'}
          $nodes=@($ast.FindAll({param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
            $node.Extent.Text.Contains('PrePinMIROwnedArchiveNames') -and
            $node.Extent.Text.Contains('$historicalFixture.target -in')
          },$true))
          if($nodes.Count -ne 1){throw 'owned-version selector missing or ambiguous'}
          $select=[scriptblock]::Create($nodes[0].Extent.Text)
          foreach($id in @('f013','f014','f015','f016','f017','f018','f100','f110')){
            foreach($transition in @($false,$true)){
             foreach($coexisting in @($false,$true)){
              $historical=$true; $historicalTransition=$transition
              $historicalFixture=@{target=$id}; $activationArguments=@{}
              $mirRows=@(@{version='5.0.01300'})
              $inventory=@(@{name='more-infinite-research';version='5.0.01300'})
              if($coexisting){$inventory+=@{name='more-infinite-research';version='4.7.01303'}}
              & $select
              $expected=($id -in @('f013','f014','f015','f016')) -and ($transition -or $coexisting)
              if($activationArguments.ContainsKey('PrePinMIROwnedArchiveNames') -ne $expected){
                throw "owned version selection differs: $id transition=$transition coexisting=$coexisting"
              }
              if($expected){
                $names=@($activationArguments.PrePinMIROwnedArchiveNames)
                if($names.Count -ne 1 -or $names[0] -cne 'more-infinite-research'){
                  throw 'selector included an unowned archive name'
                }
              }
             }
            }
          }
          $historical=$false; $historicalTransition=$false
          $historicalFixture=$null; $activationArguments=@{}
          & $select
          if($activationArguments.Count){throw 'modern run gained owned-version selection'}
        '''
        result = subprocess.run(
            ["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
            capture_output=True, text=True,
            env=dict(os.environ, MIR_TEST_RUNNER=str(RUNNER)), check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_eight_profiles_select_only_exact_base_mir_and_shared_fixture(self):
        expected = {
            "f013": ("0.13.20", "5.0.01300"),
            "f014": ("0.14.23", "5.0.01400"),
            "f015": ("0.15.40", "5.0.01500"),
            "f016": ("0.16.51", "5.0.01600"),
            "f017": ("0.17.79", "5.0.01700"),
            "f018": ("0.18.47", "5.0.01800"),
            "f100": ("1.0.0", "5.0.10000"),
            "f110": ("1.1.110", "5.0.11000"),
        }
        self.assertEqual(set(self.metadata["targets"]), set(expected))
        for target, (base, mir) in expected.items():
            with self.subTest(target=target):
                row = self.metadata["targets"][target]
                self.assertEqual((row["minimum_base"], row["mir_version"]), (base, mir))
                profile = json.loads(
                    (ROOT / f"tests/profiles/historical-native-{target}.json").read_text(encoding="utf-8")
                )
                self.assertEqual(profile["mods"], [
                    {"name": "base", "version": base, "enabled": True},
                    {"name": "more-infinite-research", "version": mir, "enabled": True},
                    {"name": "mir-fixture-mir5-historical-native", "version": "0.1.0", "enabled": True},
                ])

    def test_target_metadata_retains_real_direct_science_and_historical_continuation_divergence(self):
        expected = {
            "f013": ("numeric-witness", 914489, 3600, 0.05, False, "alien-science-pack", ""),
            "f014": ("numeric-witness", 914489, 3600, 0.05, False, "alien-science-pack", ""),
            "f015": (
                "lab", None, None, 0.10, False, "high-tech-science-pack,military-science-pack",
                "high-tech-science-pack,production-science-pack,science-pack-1,science-pack-2,science-pack-3",
            ),
            "f016": (
                "lab", None, None, 0.10, False, "high-tech-science-pack,military-science-pack",
                "high-tech-science-pack,production-science-pack,science-pack-1,science-pack-2,science-pack-3",
            ),
            "f017": (
                "lab", None, None, 0.10, True, "military-science-pack,utility-science-pack",
                "automation-science-pack,chemical-science-pack,logistic-science-pack,production-science-pack,utility-science-pack",
            ),
            "f018": (
                "lab", None, None, 0.10, True, "military-science-pack,utility-science-pack",
                "automation-science-pack,chemical-science-pack,logistic-science-pack,military-science-pack,utility-science-pack",
            ),
            "f100": (
                "lab", None, None, 0.10, True, "military-science-pack,utility-science-pack",
                "automation-science-pack,chemical-science-pack,logistic-science-pack,production-science-pack,utility-science-pack",
            ),
            "f110": (
                "lab", None, None, 0.10, True, "military-science-pack,utility-science-pack",
                "automation-science-pack,chemical-science-pack,logistic-science-pack,production-science-pack,utility-science-pack",
            ),
        }
        for target, wanted in expected.items():
            with self.subTest(target=target):
                row = self.metadata["targets"][target]
                self.assertEqual(row["direct"], "recipe-prod-research_character_mining_speed-1")
                self.assertEqual(
                    row["continuation"],
                    "laser-turret-speed-8" if target == "f018" else "inserter-capacity-bonus-8",
                )
                if target == "f018":
                    self.assertEqual(row["continuation_settings_family"], "laser-shooting-speed")
                    self.assertEqual(row["continuation_gun_speed_ammo"], "laser-turret")
                    self.assertEqual(row["continuation_effect_delta"], 0.01)
                actual = (
                    row["continuation_mode"], row.get("continuation_count"), row.get("continuation_energy_ticks"),
                    row["direct_effect"], row.get("queue_api", False), ",".join(row["direct_science"]),
                    ",".join(row.get("continuation_science", [])),
                )
                self.assertEqual(actual, wanted)

    def test_f018_runner_binds_the_named_laser_tail_and_only_admits_the_real_1_8_transition_protocol(self):
        script = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalFixtureTarget',
            'ConvertTo-HistoricalFixtureTargetLiteral','Get-HistoricalTransitionFixtureTarget')){
            $node=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw "helper missing: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $selected=Get-HistoricalFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_DEFAULT
          $bad=Get-Content -LiteralPath $env:MIR_TEST_DEFAULT -Raw|ConvertFrom-Json -AsHashtable
          $bad.targets.f018.continuation='inserter-capacity-bonus-8'
          $bad|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $env:MIR_TEST_BAD -NoNewline
          $badRejected=$false
          try{Get-HistoricalFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_BAD|Out-Null}
          catch{$badRejected=$_.Exception.Message -match 'F018 historical continuation differs'}
          $transition=Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_TRANSITION -Stage published
          if($transition.mir_version -cne '1.8.0'){throw 'real F018 predecessor differs'}
          $fake=Get-Content -LiteralPath $env:MIR_TEST_TRANSITION -Raw|ConvertFrom-Json -AsHashtable
          $fake.targets.f018.published_mir_version='4.7.01802'
          $fake|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $env:MIR_TEST_BAD_TRANSITION -NoNewline
          $transitionRejected=$false
          try{Get-HistoricalTransitionFixtureTarget -Target f018 -MetadataPath $env:MIR_TEST_BAD_TRANSITION -Stage published|Out-Null}
          catch{$transitionRejected=$_.Exception.Message -match 'MIR versions differ'}
          if(-not $badRejected -or -not $transitionRejected){throw 'F018 admission boundary differs'}
          [ordered]@{literal=(ConvertTo-HistoricalFixtureTargetLiteral $selected);target=$selected.target;
            factorio_version=$selected.factorio_version;minimum_base=$selected.minimum_base;mir_version=$selected.mir_version}|ConvertTo-Json -Compress
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-f018-native-admission-") as work:
            bad_path = Path(work) / "bad-f018.json"
            bad_transition_path = Path(work) / "bad-f018-transition.json"
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", script], cwd=ROOT,
                env=dict(os.environ, MIR_TEST_RUNNER=str(RUNNER),
                         MIR_TEST_DEFAULT=str(FIXTURE / "metadata.json"), MIR_TEST_BAD=str(bad_path),
                         MIR_TEST_TRANSITION=str(TRANSITION_FIXTURE / "metadata.json"),
                         MIR_TEST_BAD_TRANSITION=str(bad_transition_path)),
                text=True, capture_output=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        selected = json.loads(result.stdout)
        self.assertEqual(
            (selected["target"], selected["factorio_version"], selected["minimum_base"], selected["mir_version"]),
            ("f018", "0.18", "0.18.47", "5.0.01800"),
        )
        self.assertIn('continuation="laser-turret-speed-8",', selected["literal"])
        self.assertIn('continuation_settings_family="laser-shooting-speed",', selected["literal"])
        self.assertIn('continuation_gun_speed_ammo="laser-turret",', selected["literal"])
        self.assertIn("continuation_effect_delta=0.01,", selected["literal"])

    def test_all_science_metadata_uses_only_the_four_native_red_recipe_targets(self):
        default_blob = subprocess.run(
            ["git", "show", "HEAD:tests/fixtures/historical-native/metadata.json"], cwd=ROOT,
            capture_output=True, check=True,
        ).stdout
        self.assertEqual(hashlib.sha256(default_blob).hexdigest(), DEFAULT_METADATA_SHA256)
        self.assertTrue(all("science_policy" not in row for row in self.metadata["targets"].values()))
        alternate = json.loads(ALL_SCIENCE_METADATA.read_text(encoding="utf-8"))
        self.assertEqual(set(alternate["targets"]), {"f017", "f018", "f100", "f110"})

        functions = r'''
          $ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalFixtureTarget',
            'ConvertTo-HistoricalFixtureTargetLiteral')){
            $node=@($ast.FindAll({param($n) $n -is
              [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw "helper missing: $name"}
            Invoke-Expression $node[0].Extent.Text
          }
          $default=Get-HistoricalFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_DEFAULT
          $rows=@()
          foreach($target in @('f017','f018','f100','f110')){
            $selected=Get-HistoricalFixtureTarget -Target $target -MetadataPath $env:MIR_TEST_ALL
            $rows+=[ordered]@{target=$target;policy=$selected.science_policy;
              literal=(ConvertTo-HistoricalFixtureTargetLiteral $selected)}
          }
          foreach($target in @('f013','f014','f015','f016')){
            $rejected=$false
            try{Get-HistoricalFixtureTarget -Target $target -MetadataPath $env:MIR_TEST_BAD|Out-Null}
            catch{$rejected=$_.Exception.Message -match 'historical science policy differs'}
            if(-not $rejected){throw "all science policy accepted non-red-recipe target: $target"}
          }
          [ordered]@{default_literal=(ConvertTo-HistoricalFixtureTargetLiteral $default);rows=$rows}|ConvertTo-Json -Compress
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-historical-all-metadata-") as work:
            bad = json.loads(ALL_SCIENCE_METADATA.read_text(encoding="utf-8"))
            for target in ("f013", "f014", "f015", "f016"):
                bad["targets"][target] = bad["targets"]["f018"]
            bad_path = Path(work) / "bad.json"
            bad_path.write_text(json.dumps(bad), encoding="utf-8")
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-Command", functions], cwd=ROOT,
                env=dict(os.environ, MIR_TEST_RUNNER=str(RUNNER),
                         MIR_TEST_DEFAULT=str(FIXTURE / "metadata.json"),
                         MIR_TEST_ALL=str(ALL_SCIENCE_METADATA), MIR_TEST_BAD=str(bad_path)),
                text=True, capture_output=True, check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        rendered = json.loads(result.stdout)
        self.assertEqual(rendered["default_literal"], """return {
  id=\"f017\",
  mir_version=\"5.0.01700\",
  direct=\"recipe-prod-research_character_mining_speed-1\",
  continuation=\"inserter-capacity-bonus-8\",
  continuation_mode=\"lab\",
  direct_effect=0.1,
  queue_api=true,
  direct_science={\"military-science-pack\",\"utility-science-pack\"},
  continuation_science={\"automation-science-pack\",\"chemical-science-pack\",\"logistic-science-pack\",\"production-science-pack\",\"utility-science-pack\"},
}
""")
        expected_direct = ("military-science-pack", "utility-science-pack", "automation-science-pack",
                           "logistic-science-pack", "chemical-science-pack", "production-science-pack",
                           "space-science-pack")
        expected_continuation = ("automation-science-pack", "chemical-science-pack", "logistic-science-pack",
                                 "production-science-pack", "utility-science-pack", "military-science-pack",
                                 "space-science-pack")
        expected_f018_continuation = ("automation-science-pack", "chemical-science-pack", "logistic-science-pack",
                                      "military-science-pack", "utility-science-pack", "production-science-pack",
                                      "space-science-pack")
        for row in rendered["rows"]:
            with self.subTest(target=row["target"]):
                self.assertEqual(row["policy"], "all")
                self.assertIn('science_policy="all",', row["literal"])
                self.assertIn('direct_science={' + ",".join(f'"{name}"' for name in expected_direct) + '}', row["literal"])
                expected = expected_f018_continuation if row["target"] == "f018" else expected_continuation
                self.assertIn('continuation_science={' + ",".join(f'"{name}"' for name in expected) + '}', row["literal"])
                if row["target"] == "f018":
                    self.assertIn('continuation="laser-turret-speed-8",', row["literal"])
                    self.assertIn('continuation_gun_speed_ammo="laser-turret",', row["literal"])
                    self.assertIn("continuation_effect_delta=0.01,", row["literal"])

    def test_shared_science_source_emits_the_all_policy_historical_vectors(self):
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          local science = require("research.science")
          local packs = {
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack"
          }
          function shared_all_vector(id, source)
            local raw = {tool={}, item={}, recipe={}, technology={}, lab={all={inputs={}}}}
            for _, pack in ipairs(packs) do
              raw.tool[pack] = {name=pack}
              raw.lab.all.inputs[#raw.lab.all.inputs + 1] = pack
              raw.recipe[pack] = {enabled=false, result=pack}
              raw.technology[pack] = {effects={{type="unlock-recipe", recipe=pack}}, prerequisites={}}
            end
            -- These engines retain the Base initial red recipe rather than a
            -- same-named owner technology.
            raw.recipe["automation-science-pack"] = {result="automation-science-pack"}
            raw.technology["automation-science-pack"] = nil
            raw.item.satellite = {rocket_launch_product={"space-science-pack", 1000}}
            raw.technology["space-science-pack"] = {
              effects={{type="unlock-recipe", recipe="satellite"}}, prerequisites={}
            }
            local row = {name="historical-all-policy", enabled=true, prerequisites={},
              unit={count=1, time=1, ingredients=source}}
            local report = science.apply(row, {}, science.prepare({raw=raw, target={id=id}, mods={},
              options={["mir-science-pack-ingredient-policy"]="all"}}))
            local names, red_gate = {}, false
            for _, ingredient in ipairs(row.unit.ingredients) do names[#names + 1] = ingredient[1] end
            for _, prerequisite in ipairs(row.prerequisites) do
              red_gate = red_gate or prerequisite == "automation-science-pack"
            end
            return report.enabled, report.reason, table.concat(names, ","), red_gate
          end
        ''')
        expected = {
            "direct": "military-science-pack,utility-science-pack,automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack",
            "continuation": "automation-science-pack,chemical-science-pack,logistic-science-pack,production-science-pack,utility-science-pack,military-science-pack,space-science-pack",
            "f018_continuation": "automation-science-pack,chemical-science-pack,logistic-science-pack,military-science-pack,utility-science-pack,production-science-pack,space-science-pack",
        }
        for target in ("f017", "f018", "f100", "f110"):
            vectors = [
                ("direct", (("military-science-pack", 1), ("utility-science-pack", 1))),
                ("continuation", (("automation-science-pack", 1), ("chemical-science-pack", 1),
                                  ("logistic-science-pack", 1), ("production-science-pack", 1),
                                  ("utility-science-pack", 1))),
            ]
            if target == "f018":
                vectors[1] = ("f018_continuation", (("automation-science-pack", 1),
                              ("chemical-science-pack", 1), ("logistic-science-pack", 1),
                              ("military-science-pack", 1), ("utility-science-pack", 1)))
            for name, source in vectors:
                with self.subTest(target=target, vector=name):
                    lua_source = self.lua.table_from([self.lua.table_from(item) for item in source])
                    enabled, reason, actual, red_gate = self.lua.eval("shared_all_vector")(target, lua_source)
                    self.assertTrue(enabled)
                    self.assertEqual(reason, "all")
                    self.assertEqual(actual, expected[name])
                    self.assertFalse(red_gate)

    def test_control_and_on_load_do_not_need_game_or_runtime_active_mods(self):
        self.lua.globals().fixture_root = FIXTURE.as_posix()
        self.lua.execute(r'''
          package.path = fixture_root .. "/?.lua"
          package.preload["target-literal"] = function()
            return {
              id="f013", mir_version="5.0.01300",
              direct="recipe-prod-research_character_mining_speed-1",
              direct_effect=0.05,
              direct_science={"alien-science-pack"},
              continuation="inserter-capacity-bonus-8", continuation_mode="numeric-witness",
              continuation_count=914489, continuation_energy_ticks=3600,
            }
          end
          target = require("target")
          assert(target.id == "f013")
          game = nil
          callbacks = {}
          script = {
            on_init=function(callback) callbacks.init=callback end,
            on_load=function(callback) callbacks.load=callback end,
            on_event=function(event, callback) callbacks[event]=callback end,
          }
          defines = {inventory={lab_input=1}, events={on_research_finished=2, on_tick=3}}
          global = {mir5_historical_native={
            phase="complete", direct_finished=1, continuation_finished=0,
            before_mining=0, before_continuation_effect=0,
          }}
          log=function() end
          assert(loadfile(fixture_root .. "/control.lua", "t", _ENV))()
          assert(callbacks.load)
          assert(pcall(callbacks.load))
        ''')

    def test_direct_completion_uses_each_stamped_effect_and_the_old_runtime_tick_energy(self):
        self.lua.globals().fixture_root = FIXTURE.as_posix()
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          package.path = fixture_root .. "/?.lua"

          function exercise_direct_completion(id, expected_effect, actual_effect, missing_direct_pack, missing_continuation_pack,
              restored_lab, actual_continuation_effect, direct_unit_count, direct_unit_energy,
              continuation_unit_count, continuation_unit_energy, science_policy)
            local ok, value = pcall(function()
              package.loaded["target"] = nil
              package.loaded["target-literal"] = nil
              package.preload["target-literal"] = function()
                if id == "f013" then
                  return {
                    id=id, mir_version="5.0.01300", direct="recipe-prod-research_character_mining_speed-1",
                    direct_effect=expected_effect, direct_science={"alien-science-pack"},
                    continuation="inserter-capacity-bonus-8", continuation_mode="numeric-witness",
                    continuation_count=914489, continuation_energy_ticks=3600,
                  }
                end
                if id == "f017" then
                  return {
                    id=id, mir_version="5.0.01700", science_policy="all",
                    direct="recipe-prod-research_character_mining_speed-1", direct_effect=expected_effect,
                    direct_science={"military-science-pack", "utility-science-pack", "automation-science-pack",
                      "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"},
                    continuation="inserter-capacity-bonus-8", continuation_mode="lab",
                    continuation_science={"automation-science-pack", "chemical-science-pack", "logistic-science-pack",
                      "production-science-pack", "utility-science-pack", "military-science-pack", "space-science-pack"},
                    queue_api=true,
                  }
                end
                if id == "f018" then
                  local direct_science = {"military-science-pack", "utility-science-pack"}
                  local continuation_science = {"automation-science-pack", "chemical-science-pack",
                    "logistic-science-pack", "military-science-pack", "utility-science-pack"}
                  if science_policy == "all" then
                    direct_science = {"military-science-pack", "utility-science-pack", "automation-science-pack",
                      "logistic-science-pack", "chemical-science-pack", "production-science-pack", "space-science-pack"}
                    continuation_science = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack",
                      "military-science-pack", "utility-science-pack", "production-science-pack", "space-science-pack"}
                  end
                  return {
                    id=id, mir_version="5.0.01800", science_policy=science_policy,
                    direct="recipe-prod-research_character_mining_speed-1",
                    direct_effect=expected_effect,
                    direct_science=direct_science,
                    continuation="laser-turret-speed-8", continuation_mode="lab",
                    continuation_settings_family="laser-shooting-speed",
                    continuation_gun_speed_ammo="laser-turret", continuation_effect_delta=0.01,
                    continuation_science=continuation_science,
                    queue_api=true,
                  }
                end
                return {
                  id=id, mir_version="5.0.01500", direct="recipe-prod-research_character_mining_speed-1",
                  direct_effect=expected_effect,
                  direct_science={"high-tech-science-pack", "military-science-pack"},
                  continuation="inserter-capacity-bonus-8", continuation_mode="lab",
                  continuation_science={"high-tech-science-pack", "production-science-pack",
                    "science-pack-1", "science-pack-2", "science-pack-3"},
                }
              end

              local function inventory()
                local counts = {}
                return {
                  insert=function(spec) counts[spec.name] = (counts[spec.name] or 0) + spec.count; return spec.count end,
                  get_item_count=function(name) return counts[name] or 0 end,
                  consume=function(name, count) counts[name] = counts[name] - count end,
                }
              end
              local created = {}
              local surface = {
                create_entity=function()
                  local input = inventory()
                  local lab = {valid=true, energy=0, get_inventory=function() return input end}
                  created[#created + 1] = lab
                  return lab
                end,
              }
              local force = {manual_mining_speed_modifier=0, stack_inserter_capacity_bonus=0, technologies={}}
              local gun_speed = {}
              force.get_gun_speed_modifier = function(category) return gun_speed[category] or 0 end
              local current_research
              setmetatable(force, {
                __index=function(_, key)
                  if key == "current_research" then return current_research end
                end,
                __newindex=function(self, key, value)
                  if key == "current_research" then
                    assert(value == nil or type(value) == "string", "old native research setter requires a name")
                    current_research = value and self.technologies[value] or nil
                  else rawset(self, key, value) end
                end,
              })
              local direct = {name="recipe-prod-research_character_mining_speed-1", force=force,
                prerequisites={}, enabled=true, researched=false}
              local continuation = {name=id == "f018" and "laser-turret-speed-8" or "inserter-capacity-bonus-8",
                force=force, prerequisites={}, enabled=true,
                researched=false, research_unit_count=914489, research_unit_energy=3600}
              if id == "f017" or id == "f018" then
                direct.research_unit_count = direct_unit_count == nil and 1 or direct_unit_count
                direct.research_unit_energy = direct_unit_energy == nil and 60 or direct_unit_energy
                continuation.research_unit_count = continuation_unit_count == nil and 1 or continuation_unit_count
                continuation.research_unit_energy = continuation_unit_energy == nil and 60 or continuation_unit_energy
              end
              force.technologies[direct.name], force.technologies[continuation.name] = direct, continuation
               force.add_research = function(value) current_research = value; return true end
              force.get_spawn_position = function() return {x=0, y=0} end

              callbacks, global = {}, {}
              local messages, saves = {}, {}
              script = {
                on_init=function(callback) callbacks.init=callback end,
                on_load=function(callback) callbacks.load=callback end,
                on_event=function(event, callback) callbacks[event]=callback end,
              }
              defines = {inventory={lab_input=1}, events={on_research_finished=2, on_tick=3}}
              game = {
                active_mods={["more-infinite-research"]="5.0"}, forces={player=force}, surfaces={[1]=surface},
                tick=0, server_save=function(name) saves[#saves + 1] = name end,
              }
              log=function(value) messages[#messages + 1] = value end
              assert(loadfile(control_path, "t", _ENV))()
              callbacks.init()

              local direct_input = global.mir5_historical_native.direct_lab.get_inventory(defines.inventory.lab_input)
              if id == "f017" or (id == "f018" and science_policy == "all") then
                local function only_powered(expected)
                  local powered = {}
                  for _, lab in ipairs(created) do
                    if lab == expected then
                      assert(lab.energy == 100000000, "fixture active lab energy differs")
                    else
                      assert(lab.energy == 0, "fixture inactive lab retained energy")
                    end
                    if lab.energy > 0 then powered[#powered + 1] = lab end
                  end
                  assert(#powered == 1 and powered[1] == expected, "fixture lab power budget differs")
                end
                local state = global.mir5_historical_native
                only_powered(state.direct_lab)
                callbacks[defines.events.on_tick]()
                assert(state.phase == "direct" and force.current_research == direct)
                only_powered(state.direct_lab)
                direct.researched, force.manual_mining_speed_modifier, force.current_research = true, actual_effect, nil
                callbacks[defines.events.on_research_finished]({research=direct})
                assert(state.phase == "direct-consumption-pending")
                assert(state.direct_lab.energy == 0 and state.continuation_lab.energy == 0)
                callbacks[defines.events.on_tick]()
                assert(state.phase == "direct-consumption-pending")
                assert(state.direct_next_tick_counts == nil and force.current_research == nil
                  and state.direct_lab.energy == 0 and state.continuation_lab.energy == 0)
                for _, pack in ipairs(package.loaded.target.direct_science) do
                  if pack ~= missing_direct_pack then direct_input.consume(pack, 1) end
                end
                game.tick = 1
                callbacks[defines.events.on_tick]()
                assert(state.phase == "continuation" and force.current_research == continuation)
                only_powered(state.continuation_lab)
                assert(state.direct_lab.energy == 0)

                local continuation_input = state.continuation_lab.get_inventory(defines.inventory.lab_input)
                callbacks[defines.events.on_tick]()
                assert(state.phase == "continuation" and force.current_research == continuation)
                only_powered(state.continuation_lab)
                continuation.researched, force.current_research = true, nil
                if id == "f018" then
                  gun_speed["laser-turret"] = actual_continuation_effect or 0.01
                else
                  force.stack_inserter_capacity_bonus = actual_continuation_effect or 1
                end
                callbacks[defines.events.on_research_finished]({research=continuation})
                assert(state.phase == "continuation-consumption-pending")
                assert(state.direct_lab.energy == 0 and state.continuation_lab.energy == 0)
                callbacks[defines.events.on_tick]()
                assert(state.phase == "continuation-consumption-pending")
                assert(state.continuation_next_tick_counts == nil and force.current_research == nil
                  and state.direct_lab.energy == 0 and state.continuation_lab.energy == 0)
                for _, pack in ipairs(package.loaded.target.continuation_science) do
                  if pack ~= missing_continuation_pack then continuation_input.consume(pack, 1) end
                end
                game.tick = 2
                callbacks[defines.events.on_tick]()
                assert(state.phase == "complete" and state.saved == true and saves[1] == "mir5-native-complete")
                assert(state.direct_lab.energy == 0 and state.continuation_lab.energy == 0)
                if restored_lab == "direct" then
                  direct_input.insert{name="military-science-pack", count=1}
                elseif restored_lab == "continuation" then
                  continuation_input.insert{name="automation-science-pack", count=1}
                end
                callbacks.load()
                game.tick = 3
                callbacks[defines.events.on_tick]()
                return {phase=state.phase, saved=state.saved == true, modifier=force.manual_mining_speed_modifier,
                  stack_bonus=force.stack_inserter_capacity_bonus,
                  continuation_effect=id == "f018" and gun_speed["laser-turret"] or force.stack_inserter_capacity_bonus,
                  direct_event=state.direct_event_counts["military-science-pack"],
                  direct_next=state.direct_next_tick_counts["military-science-pack"],
                  continuation_event=state.continuation_event_counts["automation-science-pack"],
                  continuation_next=state.continuation_next_tick_counts["automation-science-pack"],
                  direct_unit_marker=messages[1], continuation_unit_marker=messages[2],
                  saves=#saves, final_marker=messages[#messages]}
              end

              for _, pack in ipairs(package.loaded.target.direct_science) do direct_input.consume(pack, 1) end
              direct.researched, force.manual_mining_speed_modifier, force.current_research = true, actual_effect, nil
              callbacks[defines.events.on_research_finished]({research=direct})

              if id == "f013" then
                game.tick = 1
                callbacks[defines.events.on_tick]()
                return {phase=global.mir5_historical_native.phase, saved=global.mir5_historical_native.saved == true,
                  modifier=force.manual_mining_speed_modifier, energy=continuation.research_unit_energy}
              end

              game.tick = 1
              callbacks[defines.events.on_tick]()
              assert(force.current_research == continuation)
              local continuation_input = global.mir5_historical_native.continuation_lab.get_inventory(defines.inventory.lab_input)
              for _, pack in ipairs(package.loaded.target.continuation_science) do continuation_input.consume(pack, 1) end
              continuation.researched = true
              if id == "f018" then
                gun_speed["laser-turret"] = actual_continuation_effect or 0.01
              else
                force.stack_inserter_capacity_bonus = actual_continuation_effect or 1
              end
              force.current_research = nil
              callbacks[defines.events.on_research_finished]({research=continuation})
              game.tick = 2
              callbacks[defines.events.on_tick]()
              return {phase=global.mir5_historical_native.phase, saved=global.mir5_historical_native.saved == true,
                modifier=force.manual_mining_speed_modifier, energy=continuation.research_unit_energy}
            end)
            return ok, value
          end
        ''')

        old = self.lua.eval("exercise_direct_completion")("f013", 0.05, 0.05)
        self.assertTrue(old[0])
        self.assertEqual(
            (old[1]["phase"], old[1]["saved"], old[1]["modifier"], old[1]["energy"]),
            ("complete", True, 0.05, 3600),
        )

        later = self.lua.eval("exercise_direct_completion")("f015", 0.10, 0.10)
        self.assertTrue(later[0])
        self.assertEqual(
            (later[1]["phase"], later[1]["saved"], later[1]["modifier"], later[1]["energy"]),
            ("complete", True, 0.10, 3600),
        )

        f018 = self.lua.eval("exercise_direct_completion")("f018", 0.10, 0.10)
        self.assertTrue(f018[0])
        self.assertEqual(
            (f018[1]["phase"], f018[1]["saved"], f018[1]["modifier"], f018[1]["energy"]),
            ("complete", True, 0.10, 60),
        )

        wrong_f018_continuation_effect = self.lua.eval("exercise_direct_completion")(
            "f018", 0.10, 0.10, None, None, None, 0.005
        )
        self.assertFalse(wrong_f018_continuation_effect[0])
        self.assertIn("generated native effect", wrong_f018_continuation_effect[1])

        wrong_old = self.lua.eval("exercise_direct_completion")("f013", 0.05, 0.10)
        self.assertFalse(wrong_old[0])
        self.assertIn("mining bonus", wrong_old[1])

        all_science = self.lua.eval("exercise_direct_completion")("f017", 0.10, 0.10)
        self.assertTrue(all_science[0])
        self.assertEqual(
            (all_science[1]["phase"], all_science[1]["saved"], all_science[1]["modifier"],
             all_science[1]["stack_bonus"], all_science[1]["direct_event"], all_science[1]["direct_next"],
             all_science[1]["continuation_event"], all_science[1]["continuation_next"], all_science[1]["saves"]),
            ("complete", True, 0.10, 1, 32, 31, 32, 31, 1),
        )
        self.assertIn('"stage":"reload"', all_science[1]["final_marker"])
        self.assertIn("direct_unit count=1,energy=60", all_science[1]["direct_unit_marker"])
        self.assertIn("continuation_unit count=1,energy=60", all_science[1]["continuation_unit_marker"])

        f018_all_science = self.lua.eval("exercise_direct_completion")(
            "f018", 0.10, 0.10, None, None, None, None, None, None, None, None, "all"
        )
        self.assertTrue(f018_all_science[0])
        self.assertEqual(
            (f018_all_science[1]["phase"], f018_all_science[1]["saved"], f018_all_science[1]["modifier"],
             f018_all_science[1]["continuation_effect"], f018_all_science[1]["direct_event"],
             f018_all_science[1]["direct_next"], f018_all_science[1]["continuation_event"],
             f018_all_science[1]["continuation_next"], f018_all_science[1]["saves"]),
            ("complete", True, 0.10, 0.01, 32, 31, 32, 31, 1),
        )
        self.assertIn('"stage":"reload"', f018_all_science[1]["final_marker"])
        self.assertIn("direct_unit count=1,energy=60", f018_all_science[1]["direct_unit_marker"])
        self.assertIn("continuation_unit count=1,energy=60", f018_all_science[1]["continuation_unit_marker"])

        missing_f018_all_direct = self.lua.eval("exercise_direct_completion")(
            "f018", 0.10, 0.10, "space-science-pack", None, None, None, None, None, None, None, "all"
        )
        self.assertFalse(missing_f018_all_direct[0])
        self.assertIn("real direct lab did not consume space-science-pack", missing_f018_all_direct[1])

        missing_f018_all_continuation = self.lua.eval("exercise_direct_completion")(
            "f018", 0.10, 0.10, None, "production-science-pack", None, None, None, None, None, None, "all"
        )
        self.assertFalse(missing_f018_all_continuation[0])
        self.assertIn("real continuation lab did not consume production-science-pack", missing_f018_all_continuation[1])

        wrong_f018_all_continuation_effect = self.lua.eval("exercise_direct_completion")(
            "f018", 0.10, 0.10, None, None, None, 0.005, None, None, None, None, "all"
        )
        self.assertFalse(wrong_f018_all_continuation_effect[0])
        self.assertIn("generated native effect", wrong_f018_all_continuation_effect[1])

        missing_all_science = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, "military-science-pack"
        )
        self.assertFalse(missing_all_science[0])
        self.assertIn("real direct lab did not consume military-science-pack", missing_all_science[1])

        missing_continuation_all_science = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, None, "automation-science-pack"
        )
        self.assertFalse(missing_continuation_all_science[0])
        self.assertIn("real continuation lab did not consume automation-science-pack", missing_continuation_all_science[1])

        wrong_all_science_effect = self.lua.eval("exercise_direct_completion")("f017", 0.10, 0.05)
        self.assertFalse(wrong_all_science_effect[0])
        self.assertIn("mining bonus", wrong_all_science_effect[1])

        wrong_all_science_continuation_effect = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, None, None, None, 0.5
        )
        self.assertFalse(wrong_all_science_continuation_effect[0])
        self.assertIn("generated native effect", wrong_all_science_continuation_effect[1])

        restored_direct_after_snapshot = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, None, None, "direct"
        )
        self.assertFalse(restored_direct_after_snapshot[0])
        self.assertIn("real direct lab did not consume military-science-pack", restored_direct_after_snapshot[1])

        restored_continuation_after_snapshot = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, None, None, "continuation"
        )
        self.assertFalse(restored_continuation_after_snapshot[0])
        self.assertIn("real continuation lab did not consume automation-science-pack",
                      restored_continuation_after_snapshot[1])

        zero_direct_unit = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, None, None, None, None, 0
        )
        self.assertFalse(zero_direct_unit[0])
        self.assertIn("real direct lab research unit differs", zero_direct_unit[1])

        malformed_continuation_unit = self.lua.eval("exercise_direct_completion")(
            "f017", 0.10, 0.10, None, None, None, None, 1, 60, 1, "60"
        )
        self.assertFalse(malformed_continuation_unit[0])
        self.assertIn("real continuation lab research unit differs", malformed_continuation_unit[1])

    def test_settings_only_accelerate_direct_and_gate_continuation_on_its_actual_surface(self):
        self.lua.globals().fixture_root = FIXTURE.as_posix()
        self.lua.globals().settings_updates = (FIXTURE / "settings-updates.lua").as_posix()
        self.lua.execute(r'''
          package.path = fixture_root .. "/?.lua"
          function install_fixture_target(id, science_policy)
            package.loaded["target"] = nil
            package.loaded["target-literal"] = nil
            package.preload["target-literal"] = function()
              local target = {id=id, science_policy=science_policy,
                direct="recipe-prod-research_character_mining_speed-1"}
              if id == "f018" then target.continuation_settings_family = "laser-shooting-speed" end
              return target
            end
          end
          function setting_defaults(id, with_continuation, science_policy)
            install_fixture_target(id, science_policy)
            local direct = "research_character_mining_speed"
            local base = id == "f018" and "laser-shooting-speed" or "inserter-capacity-bonus"
            data = {raw = {
              ["bool-setting"] = {["ips-enable-" .. direct] = {default_value = false}},
              ["string-setting"] = { ["mir-science-pack-ingredient-policy"] = {
                setting_type="startup", allowed_values={"configured", "all"}, default_value="configured"
              }},
              ["int-setting"] = {
                ["ips-cost-base-" .. direct] = {default_value = 8000},
                ["ips-cost-linear-increment-" .. direct] = {default_value = 0},
                ["ips-max-level-" .. direct] = {default_value = 0},
                ["ips-research-time-" .. direct] = {default_value = 60},
              },
              ["double-setting"] = {
                ["ips-cost-growth-" .. direct] = {default_value = 2},
                ["ips-effect-per-level-" .. direct] = {default_value = 5},
              },
            }}
            if with_continuation then
              data.raw["bool-setting"]["mir-enable-" .. base] = {default_value = false}
              data.raw["int-setting"]["mir-cost-base-" .. base] = {default_value = 200}
              data.raw["int-setting"]["mir-cost-linear-increment-" .. base] = {default_value = 0}
              data.raw["int-setting"]["mir-max-level-" .. base] = {default_value = 0}
              data.raw["int-setting"]["mir-research-time-" .. base] = {default_value = 60}
              data.raw["double-setting"]["mir-cost-growth-" .. base] = {default_value = 3.333333333333}
              data.raw["int-setting"]["mir-effect-per-level-" .. base] = {default_value = 4}
            end
            assert(loadfile(settings_updates, "t", _ENV))()
            local out = {
              direct = {
                data.raw["bool-setting"]["ips-enable-" .. direct].default_value,
                data.raw["int-setting"]["ips-cost-base-" .. direct].default_value,
                data.raw["int-setting"]["ips-cost-linear-increment-" .. direct].default_value,
                data.raw["double-setting"]["ips-cost-growth-" .. direct].default_value,
                data.raw["int-setting"]["ips-max-level-" .. direct].default_value,
                data.raw["int-setting"]["ips-research-time-" .. direct].default_value,
                data.raw["double-setting"]["ips-effect-per-level-" .. direct].default_value,
              },
              continuation = data.raw["bool-setting"]["mir-enable-" .. base]
                and {
                  data.raw["bool-setting"]["mir-enable-" .. base].default_value,
                  data.raw["int-setting"]["mir-cost-base-" .. base].default_value,
                  data.raw["int-setting"]["mir-cost-linear-increment-" .. base].default_value,
                  data.raw["double-setting"]["mir-cost-growth-" .. base].default_value,
                  data.raw["int-setting"]["mir-max-level-" .. base].default_value,
                  data.raw["int-setting"]["mir-research-time-" .. base].default_value,
                  data.raw["int-setting"]["mir-effect-per-level-" .. base].default_value,
                } or false,
              science_policy = data.raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value,
            }
            return out
          end
          function setting_policy_error(id, science_policy)
            local ok, message = pcall(function() setting_defaults(id, true, science_policy) end)
            return ok, message
          end
        ''')
        for target, with_continuation, expected_direct in (
            ("f013", False, (False, 8000, 0, 2, 0, 60, 5)),
            ("f014", False, (False, 8000, 0, 2, 0, 60, 5)),
            ("f015", True, (True, 1, 0, 1, 1, 1, 10)),
        ):
            with self.subTest(target=target):
                row = self.lua.eval("setting_defaults")(target, with_continuation)
                self.assertEqual(tuple(row["direct"][index] for index in range(1, 8)), expected_direct)
                if with_continuation:
                    self.assertEqual(
                        tuple(row["continuation"][index] for index in range(1, 8)),
                        (True, 1, 0, 1, 8, 1, 1),
                    )
                else:
                    self.assertFalse(row["continuation"])

        for target in ("f017", "f018", "f100", "f110"):
            with self.subTest(target=target, policy="all"):
                row = self.lua.eval("setting_defaults")(target, True, "all")
                self.assertEqual(row["science_policy"], "all")
        f018 = self.lua.eval("setting_defaults")("f018", True)
        self.assertEqual(tuple(f018["direct"][index] for index in range(1, 8)), (True, 1, 0, 1, 1, 1, 10))
        self.assertEqual(tuple(f018["continuation"][index] for index in range(1, 8)), (True, 1, 0, 1, 8, 1, 1))
        self.assertEqual(self.lua.eval("setting_defaults")("f017", True)["science_policy"], "configured")
        rejected = self.lua.eval("setting_policy_error")("f015", "all")
        self.assertFalse(rejected[0])
        self.assertIn("historical all science target differs", rejected[1])

    def test_f013_f014_final_stage_accelerates_only_a_validated_direct_probe(self):
        self.lua.globals().fixture_root = FIXTURE.as_posix()
        self.lua.globals().final_fixes = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          package.path = fixture_root .. "/?.lua"
          function install_fixture_target(id)
            package.loaded["target"] = nil
            package.loaded["target-literal"] = nil
            package.preload["target-literal"] = function() return {
              id=id, direct="recipe-prod-research_character_mining_speed-1"
            } end
          end
          function direct_probe(count)
            return {
              type="technology", name="recipe-prod-research_character_mining_speed-1",
              level=1, upgrade=true, max_level="infinite",
              unit={count=count, time=60, ingredients={{"alien-science-pack", 1}}},
              effects={{type="character-mining-speed", modifier=0.05}},
            }
          end
          function accelerate_old(id, count)
            install_fixture_target(id)
            local direct = direct_probe(count)
            local continuation = {unit={count=914489, time=60}}
            data = {raw={technology={
              ["recipe-prod-research_character_mining_speed-1"] = direct,
              ["inserter-capacity-bonus-8"] = continuation,
            }}}
            local ok, message = pcall(function() assert(loadfile(final_fixes, "t", _ENV))() end)
            return ok, message, direct.unit.count, direct.unit.time, continuation.unit.count, continuation.unit.time
          end
        ''')
        for target in ("f013", "f014"):
            with self.subTest(target=target):
                result = self.lua.eval("accelerate_old")(target, 8000)
                self.assertTrue(result[0])
                self.assertEqual(result[2:], (1, 1, 914489, 60))

        invalid = self.lua.eval("accelerate_old")("f013", 7999)
        self.assertFalse(invalid[0])
        self.assertIn("cost or time differs", invalid[1])

        untouched = self.lua.eval("accelerate_old")("f015", 8000)
        self.assertTrue(untouched[0])
        self.assertEqual(untouched[2:], (8000, 60, 914489, 60))

    def test_all_science_final_stage_preflights_the_actual_initial_red_surface(self):
        self.lua.globals().fixture_root = FIXTURE.as_posix()
        self.lua.globals().final_fixes = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          package.path = fixture_root .. "/?.lua"
          local direct_science = {
            "military-science-pack", "utility-science-pack", "automation-science-pack",
            "logistic-science-pack", "chemical-science-pack", "production-science-pack",
            "space-science-pack"
          }
          local continuation_science = {
            "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
            "production-science-pack", "utility-science-pack", "military-science-pack",
            "space-science-pack"
          }
          local f018_continuation_science = {
            "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
            "military-science-pack", "utility-science-pack", "production-science-pack",
            "space-science-pack"
          }
          function install_all_fixture_target(id)
            package.loaded["target"] = nil
            package.loaded["target-literal"] = nil
            package.preload["target-literal"] = function()
              return {
                id=id, science_policy="all", direct="recipe-prod-research_character_mining_speed-1",
                direct_science=direct_science,
                continuation=id == "f018" and "laser-turret-speed-8" or "inserter-capacity-bonus-8",
                continuation_science=id == "f018" and f018_continuation_science or continuation_science
              }
            end
          end
          local function ingredients(names)
            local out = {}
            for _, name in ipairs(names) do out[#out + 1] = {name, 1} end
            return out
          end
          function all_science_preflight(id, mutation)
            install_all_fixture_target(id)
            local continuation_name = id == "f018" and "laser-turret-speed-8" or "inserter-capacity-bonus-8"
            local selected_continuation_science = id == "f018" and f018_continuation_science or continuation_science
            local red = {result="automation-science-pack"}
            local direct = {unit={ingredients=ingredients(direct_science)}, prerequisites={}}
            local continuation = {unit={ingredients=ingredients(selected_continuation_science)}, prerequisites={}}
            local technology = {
              ["recipe-prod-research_character_mining_speed-1"] = direct,
              [continuation_name] = continuation,
            }
            if mutation == "disabled-red" then red.enabled = false end
            if mutation == "red-owner" then technology["automation-science-pack"] = {} end
            if mutation == "wrong-ingredient" then direct.unit.ingredients[3] = {"wrong-pack", 1} end
            if mutation == "missing-ingredient" then table.remove(continuation.unit.ingredients) end
            if mutation == "red-prerequisite" then continuation.prerequisites = {"automation-science-pack"} end
            data = {raw={recipe={ ["automation-science-pack"] = red }, technology=technology}}
            local ok, message = pcall(function() assert(loadfile(final_fixes, "t", _ENV))() end)
            return ok, message
          end
        ''')
        for target in ("f017", "f018", "f100", "f110"):
            with self.subTest(target=target):
                result = self.lua.eval("all_science_preflight")(target, "")
                self.assertTrue(result[0])
        for mutation, message in (
            ("disabled-red", "historical initial red recipe differs"),
            ("red-owner", "historical initial red owner differs"),
            ("wrong-ingredient", "historical all science ingredient differs"),
            ("missing-ingredient", "historical all science ingredient count differs"),
            ("red-prerequisite", "historical initial red prerequisite differs"),
        ):
            with self.subTest(mutation=mutation):
                result = self.lua.eval("all_science_preflight")("f018", mutation)
                self.assertFalse(result[0])
                self.assertIn(message, result[1])

    def test_runner_keeps_historical_server_reloads_separate_from_the_modern_benchmark_vector(self):
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn("[string]$HistoricalTarget=''", source)
        self.assertIn("Get-HistoricalFixtureTarget", source)
        self.assertIn("Assert-HistoricalFixtureArchive", source)
        self.assertIn("ConvertTo-HistoricalFixtureTargetLiteral", source)
        self.assertIn("target-literal.lua", source)
        self.assertIn("if($historical){", source)
        self.assertIn("'check-updates=false','enable-new-mods=false'", source)
        self.assertIn("@('--start-server',$complete)", source)
        self.assertIn("@('--benchmark',$complete,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')", source)
        self.assertIn("$historicalFixture.factorio_version -notin @('0.13','0.14')", source)
        self.assertIn("cold reload changed completed save bytes", source)
        self.assertIn('\"stage\":\"reload\"', source)
        self.assertNotIn("New-MIR4HistoricalArchiveStage", source)
        self.assertIn("if($historical -and ($historicalFixture.target -in @('f013','f014','f015','f016')))", source)
        self.assertIn("$activationArguments.PrePinMIROwnedArchiveNames=@('more-infinite-research')", source)
        self.assertNotIn("if($historicalTransition -and ($historicalFixture.target -in @('f013','f014','f015','f016')))", source)

    def test_historical_server_settings_are_private_unpaused_and_use_supported_bind_flags(self):
        script = r'''
          $ErrorActionPreference='Stop'
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse differs'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','New-HistoricalFixtureServerSettings')){
            $node=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
            if(@($node).Count -ne 1){throw 'function missing'}
            Invoke-Expression $node[0].Extent.Text
          }
          foreach($version in @('0.13','0.14','0.15','0.16','0.17','0.18','1.0','1.1')){
            $engine=Join-Path $env:MIR_TEST_TEMP $version
            [IO.Directory]::CreateDirectory($engine)|Out-Null
            # Exact relevant shapes of the historical engine-owned examples.
            $example=if($version -ceq '0.13'){
              @{name='public';description='example';visibility='public';verify_user_identity=$true;max_players='0'}
            }else{
              @{name='public';description='example';visibility=@{public=$true;lan=$true};require_user_verification=$true;auto_pause=$true;max_players=0}
            }
            $source=Join-Path $engine 'server-settings.example.json'
            $example|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $source
            $before=Get-FixtureSha $source
            $result=New-HistoricalFixtureServerSettings (Join-Path $engine 'private.json') $engine $version
            $value=Get-Content -LiteralPath $result.path -Raw|ConvertFrom-Json -AsHashtable
            if($value.auto_pause -or $result.auto_pause){throw 'fixture paused without players'}
            foreach($field in @('username','password','token')){if($value[$field] -cne ''){throw 'credential field retained'}}
            if($version -ceq '0.13'){
              if($value.visibility -cne 'hidden' -or $value.verify_user_identity -or $result.arguments.Count -ne 3 -or
                $result.arguments[2] -cne '--no-auto-pause'){throw 'F013 server contract differs'}
            }else{
              if($value.visibility.public -or $value.visibility.lan -or $value.require_user_verification){throw 'server advertised'}
              if(($result.arguments -join '|') -cnotmatch '[|]--bind[|]127[.]0[.]0[.]1$'){throw 'loopback bind absent'}
            }
            if($result.arguments[0] -cne '--server-settings' -or $result.arguments[1] -cne $result.path){throw 'explicit settings absent'}
            if((Get-FixtureSha $source) -cne $before -or (Get-FixtureSha $result.path) -cne $result.sha256){throw 'server settings custody differs'}
          }
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-historical-private-server-") as work:
            env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_TEMP=work)
            result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                                    capture_output=True, text=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_historical_save_completion_requires_a_closed_native_archive(self):
        script = r'''
          $ErrorActionPreference='Stop'
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile($env:MIR_TEST_RUNNER,[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'runner parse differs'}
          $nodes=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -ceq 'Test-HistoricalFixtureSaveComplete'},$true))
          if($nodes.Count -ne 1){throw 'save completion helper missing'}
          Invoke-Expression $nodes[0].Extent.Text
          $saveComplete=${function:Test-HistoricalFixtureSaveComplete}
          $completion={param($path) & $saveComplete $path}.GetNewClosure()
          foreach($name in @('old','later')){
            if(-not (& $completion (Join-Path $env:MIR_TEST_TEMP ($name+'.zip')))){throw 'valid native save rejected'}
          }
          foreach($name in @('missing','corrupt','wrong','empty')){
            if(Test-HistoricalFixtureSaveComplete (Join-Path $env:MIR_TEST_TEMP ($name+'.zip'))){throw 'invalid native save accepted'}
          }
          $path=Join-Path $env:MIR_TEST_TEMP 'old.zip'
          $writer=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
          try{if(Test-HistoricalFixtureSaveComplete $path){throw 'open writer accepted'}}finally{$writer.Dispose()}
        '''
        with tempfile.TemporaryDirectory(prefix="mir5-historical-save-") as work:
            folder = Path(work)
            for name, member, contents in (
                ("old", "old/level-init.dat", b"native bytes"),
                ("later", "later/level.dat", b"native bytes"),
                ("wrong", "other/level.dat", b"native bytes"),
                ("empty", "empty/level.dat", b""),
            ):
                with zipfile.ZipFile(folder / (name + ".zip"), "w") as archive:
                    archive.writestr(member, contents)
            (folder / "corrupt.zip").write_bytes(b"incomplete native archive")
            env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_TEMP=work)
            result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-Command", script],
                                    capture_output=True, text=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actual_archive_guard_accepts_six_members_and_rejects_merged_dependencies_or_missing_member(self):
        functions = r'''
          $ErrorActionPreference='Stop'
          Set-StrictMode -Version Latest
          $tokens=$null;$errors=$null
          $ast=[Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PWD 'tools/Invoke-NativeFixture.ps1'),[ref]$tokens,[ref]$errors)
          if($errors.Count){throw 'parse failed'}
          foreach($name in @('Assert-Fixture','Get-FixtureSha','Get-HistoricalFixtureTarget',
            'ConvertTo-HistoricalFixtureTargetLiteral','Assert-HistoricalFixtureArchive')){
            $node=@($ast.FindAll({param($n) $n -is
              [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($node.Count -ne 1){throw 'helper missing'}
            Invoke-Expression $node[0].Extent.Text
          }
          $source=Join-Path $PWD 'tests/fixtures/historical-native'
          $selected=Get-HistoricalFixtureTarget -Target f013 -MetadataPath (Join-Path $source 'metadata.json')
        '''
        literal = subprocess.run(
            ["pwsh", "-NoProfile", "-Command", functions +
             "ConvertTo-HistoricalFixtureTargetLiteral $selected"],
            cwd=ROOT, text=True, capture_output=True, check=True,
        ).stdout.strip() + "\n"
        info = {"name": self.metadata["name"], "version": self.metadata["version"],
                "title": "MIR historical native fixture", "author": "MIR maintainers",
                "factorio_version": "0.13",
                "dependencies": ["base >= 0.13.20", "more-infinite-research = 5.0.01300"]}
        members = {name: (FIXTURE / name).read_bytes() for name in
                   ("control.lua", "settings-updates.lua", "data-final-fixes.lua", "target.lua")}
        members["target-literal.lua"] = literal.encode("utf-8")
        members["info.json"] = json.dumps(info).encode("utf-8")
        temporary_root = ROOT / "build/tmp"
        temporary_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mir5-historical-archive-guard-", dir=temporary_root) as folder:
            folder = Path(folder).resolve()
            self.assertTrue(folder.is_relative_to(temporary_root.resolve()))
            archive_root = self.metadata["name"] + "_" + self.metadata["version"] + "/"
            labels = ["good", "merged", "missing"] + [
                field + "-" + defect for field in ("title", "author")
                for defect in ("absent", "blank", "array")]
            for label in labels:
                rows = dict(members)
                if label == "merged":
                    bad = dict(info, dependencies=[" ".join(info["dependencies"])])
                    rows["info.json"] = json.dumps(bad).encode("utf-8")
                if label == "missing":
                    del rows["data-final-fixes.lua"]
                if "-" in label:
                    field, defect = label.split("-", 1)
                    bad = dict(info)
                    if defect == "absent":
                        del bad[field]
                    else:
                        bad[field] = "  " if defect == "blank" else ["invalid"]
                    rows["info.json"] = json.dumps(bad).encode("utf-8")
                with zipfile.ZipFile(folder / (label + ".zip"), "w") as archive:
                    for name, content in rows.items():
                        archive.writestr(archive_root + name, content)
            check = r'''
              Assert-HistoricalFixtureArchive -Archive (Join-Path $env:MIR5_GUARD_ROOT 'good.zip') -SourceDirectory $source -Fixture $selected
              foreach($case in @('merged','missing','title-absent','title-blank','title-array','author-absent','author-blank','author-array')){
                $refused=$false
                try{Assert-HistoricalFixtureArchive -Archive (Join-Path $env:MIR5_GUARD_ROOT ($case+'.zip')) -SourceDirectory $source -Fixture $selected}
                catch{
                  $message=$_.Exception.Message
                  if(($case -eq 'merged' -and $message -notmatch 'dependencies differ') -or
                    ($case -eq 'missing' -and $message -notmatch 'membership differs') -or
                    ($case -match '^(title|author)-' -and $message -notmatch ('info '+$Matches[1]+' must be a nonempty string'))){throw}
                  $refused=$true
                }
                if(-not $refused){throw ('invalid archive accepted: '+$case)}
              }
            '''
            subprocess.run(["pwsh", "-NoProfile", "-Command", functions + check],
                           cwd=ROOT, text=True, capture_output=True, check=True,
                           env=dict(os.environ, MIR5_GUARD_ROOT=str(folder)))

    def test_fixture_uses_real_engine_callbacks_and_no_synthetic_research_or_event(self):
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("surface.create_entity{name=\"lab\"", source)
        self.assertIn("defines.inventory.lab_input", source)
        self.assertNotIn("game.active_mods.base", source)
        self.assertIn('local target = require("target")', source)
        self.assertIn("force.current_research = name", source)
        self.assertIn("defines.events.on_research_finished", source)
        self.assertIn("game.server_save(\"mir5-native-complete\")", source)
        self.assertIn("script.on_load", source)
        self.assertIn('state.phase = "continuation-pending"', source)
        self.assertIn('state.phase = "direct-consumption-pending"', source)
        self.assertIn('state.phase = "continuation-consumption-pending"', source)
        self.assertIn("state.direct_event_tick = game.tick", source)
        self.assertIn("state.continuation_event_tick = game.tick", source)
        self.assertIn("if game.tick <= state.direct_event_tick then return end", source)
        self.assertIn("if game.tick <= state.continuation_event_tick then return end", source)
        self.assertIn('report_lab_pack_counts("direct_lab", "event", target.direct_science', source)
        self.assertIn('report_lab_pack_counts("direct_lab", "next_tick", target.direct_science', source)
        self.assertIn('report_lab_pack_counts("continuation_lab", "event", target.continuation_science', source)
        self.assertIn('report_lab_pack_counts("continuation_lab", "next_tick", target.continuation_science', source)
        self.assertNotIn("state.direct_next_tick_counts or", source)
        self.assertNotIn("state.continuation_next_tick_counts or", source)
        self.assertIn("lab.energy = 0", source)
        self.assertIn("power_direct_lab(global[KEY])", source)
        self.assertIn("freeze_labs(state)", source)
        self.assertIn('assert_lab_research_unit("direct", direct)', source)
        self.assertIn('assert_lab_research_unit("continuation", continuation)', source)
        self.assertNotIn("lab.active", source)
        self.assertNotIn("energize(", source)
        self.assertIn('if state.phase == "continuation-pending" then', source)
        self.assertIn('create_lab(surface, position, force, target.direct_science)', source)
        self.assertIn('target.continuation_science)', source)
        completed_handler = source.split("script.on_event(defines.events.on_research_finished", 1)[1].split(
            "script.on_load", 1
        )[0]
        self.assertNotIn("start_research(game.forces.player, target.continuation)", completed_handler)
        all_science_completion = completed_handler.split('if target.science_policy == "all" then', 1)[1].split(
            "end\n    assert_direct(state)", 1
        )[0]
        self.assertNotIn("assert_direct(state)", all_science_completion)
        self.assertIn("return", all_science_completion)
        self.assertNotIn("raise_event", source)
        self.assertNotIn("remote.call", source)

    def test_f013_f014_data_final_fixture_source_uses_the_stamped_target_before_data_raw(self):
        source = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertIn('local target = require("target")', source)
        self.assertIn('target.id ~= "f013" and target.id ~= "f014"', source)
        self.assertIn("unit.count = 1", source)
        self.assertIn("unit.time = 1", source)
        self.assertNotIn('data.raw.technology["inserter-capacity-bonus-8"]', source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(HistoricalNativeFixtureControls)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
