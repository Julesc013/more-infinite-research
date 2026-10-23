"""Host controls for the seven exact-engine historical predecessor transition fixture.

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

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/historical-transition"
RUNNER = ROOT / "tools/mir5/Invoke-NativeFixture.ps1"
DIRECT_ORACLE = ROOT / "tests/mir5/fixtures/historical-direct-native-oracle.json"


class HistoricalTransitionFixtureControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metadata = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        cls.direct_oracle = json.loads(DIRECT_ORACLE.read_text(encoding="utf-8"))

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def test_all_seven_profiles_pin_published_and_mir5_versions_without_extra_mods(self):
        # Accepted public 4.7.2 archive checksums from dist/MIR-4.7.2-SHA256SUMS.txt.
        expected = {
            "f013": ("0.13.20", "4.7.01302", "5.0.01300", "69D02F628F1278B5D161B61E39DB4E3D1A5978E31D01638E2AE23E28594637C8", "preservation-only", False),
            "f014": ("0.14.23", "4.7.01402", "5.0.01400", "D34B6281A3815CD52AD91CABD1E1669650F2A2A761D9109DEDC07268D78D2CDE", "preservation-only", False),
            "f015": ("0.15.40", "4.7.01502", "5.0.01500", "758AA85BF41A10188DEA914AC456F672BAC7D3430E646CBDB6D761BE5ECC7B8A", "lab", False),
            "f016": ("0.16.51", "4.7.01602", "5.0.01600", "00053C78EE854EB8AE0CB5318F7A41E3C81E62F29FEB6E6DCE317635743520DB", "lab", False),
            "f017": ("0.17.79", "4.7.01702", "5.0.01700", "3FB8750565526816C1C33B3ADD6B82165B5AA6D026D47CD242251455FE5CFE32", "lab", True),
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
                for role, version in (("published", published), ("mir5", mir5)):
                    profile = json.loads((ROOT / f"tests/mir5/profiles/historical-transition-{role}-{target}.json")
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
        self.assertIn("('4.7.'+$edition+'02')", source)
        self.assertIn("historical fixtures require a fresh full run", source)
        self.assertIn("historical-transition", source)
        self.assertIn("transition_stage", source)
        self.assertIn("$historicalTransition -and ($historicalFixture.target -in @('f013','f014','f015','f016'))", source)
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
          $earlyLiteral=ConvertTo-HistoricalTransitionFixtureTargetLiteral $early
          if($earlyLiteral -notmatch 'successor_mode="preservation-only"' -or $earlyLiteral -match 'partial_progress'){throw 'early literal invented a successor state'}
        '''
        env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_METADATA=str(FIXTURE / "metadata.json"))
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", functions], cwd=ROOT,
                                text=True, capture_output=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        broken = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        del broken["targets"]["f017"]["queue_probe"]
        stale = json.loads((FIXTURE / "metadata.json").read_text(encoding="utf-8"))
        stale["targets"]["f017"]["published_mir_version"] = "4.7.01700"
        with tempfile.TemporaryDirectory(prefix="mir5-historical-transition-bad-") as work:
            root = Path(work)
            broken_path, stale_path = root / "broken.json", root / "stale.json"
            broken_path.write_text(json.dumps(broken), encoding="utf-8")
            stale_path.write_text(json.dumps(stale), encoding="utf-8")
            rejection = functions + r'''
              $queueRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_BROKEN -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'queue probe'){$queueRefused=$true}else{throw} }
              if(-not $queueRefused){throw 'missing queue probe accepted'}
              $staleRefused=$false
              try { Get-HistoricalTransitionFixtureTarget -Target f017 -MetadataPath $env:MIR_TEST_STALE -Stage published | Out-Null }
              catch { if($_.Exception.Message -match 'MIR versions differ'){$staleRefused=$true}else{throw} }
              if(-not $staleRefused){throw 'stale 4.7.0 predecessor accepted'}
            '''
            env["MIR_TEST_BROKEN"] = str(broken_path)
            env["MIR_TEST_STALE"] = str(stale_path)
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
            check = r'''
              Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_GOOD -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $fixture
              $refused=$false
              try { Assert-HistoricalTransitionFixtureArchive -Archive $env:MIR_TEST_WRONG -SourceDirectory $env:MIR_TEST_SOURCE -Fixture $fixture }
              catch { if($_.Exception.Message -match 'dependencies differ'){$refused=$true}else{throw} }
              if(-not $refused){throw 'wrong stage dependency accepted'}
            '''
            env = dict(os.environ, MIR_TEST_RUNNER=str(RUNNER), MIR_TEST_METADATA=str(FIXTURE / "metadata.json"),
                       MIR_TEST_GOOD=str(good), MIR_TEST_WRONG=str(wrong), MIR_TEST_SOURCE=str(FIXTURE))
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", functions + check], cwd=ROOT,
                                    text=True, capture_output=True, env=env, check=False)
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
            local before=global.mir5_historical_transition.phase;callbacks.load();assert(global.mir5_historical_transition.phase == before);callbacks.events[defines.events.on_tick]()
            callbacks={events={}};install_target("mir5",queue,old_lab);assert(loadfile(control,"t",_ENV))();callbacks.configuration({})
            if queue or old_lab then
              assert(global.mir5_historical_transition.phase == "mir5-successor" and force.current_research == direct)
              direct.level=3;force.manual_mining_speed_modifier=2*fixture_target.direct_effect
              if queue then force.research_queue={braking} else force.current_research=nil end
              callbacks.events[defines.events.on_research_finished]({research=direct})
              if queue then assert(force.current_research == braking and #force.research_queue == 1) else assert(force.current_research == nil) end
            else assert(global.mir5_historical_transition.phase == "mir5-complete" and direct.researched and force.current_research == nil) end
            callbacks.events[defines.events.on_tick]();assert(saves[#saves] == "mir5-native-complete")
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
                if queue:
                    self.assertIn('"research_queue_enabled":true', witness)

        self.lua.execute(r'''
          callbacks={events={}};install_target("mir5",true);mock_world(true);global={}
          assert(loadfile(control,"t",_ENV))()
          local ok,message=pcall(function()callbacks.configuration({})end)
          assert(not ok and tostring(message):find("lacks the published fixture state",1,true))
        ''')

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

        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.globals().data_final = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          package.path=fixture .. "/?.lua"
          function data_final_row(id, stage, expected_effect, actual_effect, expected_science, actual_science, count, count_formula)
            package.loaded.target=nil;package.loaded["target-literal"]=nil
            package.preload["target-literal"]=function()return {id=id,stage=stage,mir_version="4.7." .. id:sub(2) .. "02",
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
