"""Independent controls for the prepared direct MIR 1.1.0 successors."""
import argparse
from collections import Counter
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-110-successor"
SOURCE_FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-110-source"
F200_PROFILE = ROOT / "tests/profiles/migration-origins-1.1.0-successor-f200-2077.json"
F210_PROFILE = ROOT / "tests/profiles/migration-origins-1.1.0-successor-f210-2123.json"
DIRECT = "recipe-prod-research_gears-1"
ROBOT = "recipe-prod-research_robot_battery-1"
MODULES = "recipe-prod-research_modules-1"
RETIRED_SUCCESSOR_NAME = "mir-fixture-mir5-migration-origin-f200-110-successor"

# Pinned from the archived 1.1.0 config and F200 Base recipe output set; this
# test does not take its expected identities from the successor catalogue.
SOURCE_ROWS = {
    "recipe-prod-research_plastic-1", "recipe-prod-research_sulfur-1", "recipe-prod-research_batteries-1",
    "recipe-prod-research_explosives-1", DIRECT, "recipe-prod-research_iron_sticks-1",
    "recipe-prod-research_copper_cable-1", "recipe-prod-research_electronic_circuit-1",
    "recipe-prod-research_advanced_circuit-1", "recipe-prod-research_processing_unit-1",
    "recipe-prod-research_low_density_structure-1", "recipe-prod-research_rocket_fuel-1",
    "recipe-prod-research_copper-1", "recipe-prod-research_iron-1", "recipe-prod-research_engine-1",
    "recipe-prod-research_electric_engine-1", "recipe-prod-research_flying_robot_frame-1",
    MODULES, "recipe-prod-research_belts-1", "recipe-prod-research_inserters-1",
    "recipe-prod-research_bullets-1", "recipe-prod-research_rockets-1", ROBOT,
    "recipe-prod-research_science_pack_productivity-1", "recipe-prod-research_walls-1",
    "recipe-prod-research_grenades-1", "recipe-prod-research_rails-1",
    "recipe-prod-research_electric_energy-1", "recipe-prod-research_concrete-1",
    "recipe-prod-research_furnace-1", "recipe-prod-research_mining_drill-1",
}


def py(value):
    if hasattr(value, "items"):
        pairs = list(value.items())
        keys = [key for key, _ in pairs]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in pairs}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class MigrationOriginF200110SuccessorControls(unittest.TestCase):
    def candidate_raw(self):
        return {"technology": {
            DIRECT: {"type": "technology", "name": DIRECT, "level": 1, "upgrade": True,
                     "max_level": "infinite", "enabled": True,
                     "unit": {"count_formula": "9000*1.2^(L-1)", "time": 120,
                              "ingredients": [["automation-science-pack", 1]]},
                     "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .10}]},
        }, "sentinel": {"unchanged": 43}}

    def run_data(self, raw, mods):
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        data_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.globals().data_path = data_path
        self.lua.execute(r'''
          function migration_origin_110_successor_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return assert(loadfile(catalogue_path,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_110_successor_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def test_catalogue_pins_all_31_old_rows_and_the_separate_worker_battery_fact(self):
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.execute("function migration_origin_110_successor_catalogue() return assert(loadfile(catalogue_path))() end")
        catalogue = py(self.lua.eval("migration_origin_110_successor_catalogue")())
        rows = catalogue["rows"]
        self.assertEqual(SOURCE_ROWS, set(rows))
        self.assertEqual(31, len(rows))
        self.assertEqual("mir-fixture-mir5-migration-origin-f200-110-source", catalogue["fixture"])
        self.assertEqual(("change-recipe-productivity", "iron-gear-wheel", .10),
                         (rows[DIRECT][0]["type"], rows[DIRECT][0]["recipe"], rows[DIRECT][0]["change"]))
        self.assertEqual(("worker-robot-battery", .10), (rows[ROBOT][0]["type"], rows[ROBOT][0]["modifier"]))
        self.assertEqual(75, sum(len(effects) for effects in rows.values()))
        self.assertEqual(
            Counter({
                ("change-recipe-productivity", "speed-module", .10): 1,
                ("change-recipe-productivity", "productivity-module", .10): 1,
                ("change-recipe-productivity", "efficiency-module", .10): 1,
                ("change-recipe-productivity", "speed-module", .01): 1,
                ("change-recipe-productivity", "productivity-module", .01): 1,
                ("change-recipe-productivity", "efficiency-module", .01): 1,
                ("change-recipe-productivity", "speed-module-2", .05): 1,
                ("change-recipe-productivity", "productivity-module-2", .05): 1,
                ("change-recipe-productivity", "efficiency-module-2", .05): 1,
                ("change-recipe-productivity", "speed-module-3", .02): 1,
                ("change-recipe-productivity", "productivity-module-3", .02): 1,
                ("change-recipe-productivity", "efficiency-module-3", .02): 1,
            }),
            Counter((effect["type"], effect.get("recipe"), effect.get("change")) for effect in rows[MODULES]),
        )
        self.assertEqual("0.009999999776482582", catalogue["source_change_tokens"][.01])
        self.assertNotIn("recipe-prod-research_inventory_capacity-1", rows)
        self.assertEqual(42, len(catalogue["settings"]))
        self.assertTrue(catalogue["settings"]["ips-enable-research_breeding"])
        self.assertFalse(catalogue["settings"]["ips-enable-research_inventory_capacity"])

    def test_successor_wrappers_retain_the_source_fixture_identity_and_only_change_the_targeted_wrapper_version(self):
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        f200 = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        f210 = json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8"))
        source_version = tuple(map(int, source["version"].split(".")))
        for wrapper, base, mir, version in (
            (f200, "2.0", "5.0.20000", "0.2.0"),
            (f210, "2.1", "5.0.21000", "0.3.0"),
        ):
            with self.subTest(version=version):
                self.assertEqual(source["name"], wrapper["name"])
                self.assertEqual(version, wrapper["version"])
                self.assertEqual(base, wrapper["factorio_version"])
                self.assertIn(f"more-infinite-research = {mir}", wrapper["dependencies"])
                self.assertNotEqual(RETIRED_SUCCESSOR_NAME, wrapper["name"])
                self.assertGreater(tuple(map(int, wrapper["version"].split("."))), source_version)

    def test_data_guard_admits_only_the_two_exact_candidate_targets_and_accelerates_only_direct_cost(self):
        f200 = {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                "mir-fixture-mir5-active-mods-observer": "0.1.0",
                "mir-fixture-mir5-migration-origin-f200-110-source": "0.2.0"}
        f210 = {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                "mir-fixture-mir5-active-mods-observer": "0.1.0",
                "mir-fixture-mir5-migration-origin-f200-110-source": "0.3.0"}
        for label, mods in (("f200", f200), ("f210", f210)):
            with self.subTest(label=label):
                accepted = self.run_data(self.candidate_raw(), mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                unit = accepted["raw"]["technology"][DIRECT]["unit"]
                self.assertEqual((1, None, 1), (unit.get("count"), unit.get("count_formula"), unit["time"]))
                self.assertEqual(43, accepted["raw"]["sentinel"]["unchanged"])
        variants = []
        wrong_target = dict(f200); wrong_target["base"] = "2.1.23"; variants.append(("target", self.candidate_raw(), wrong_target))
        missing_observer = dict(f200); missing_observer.pop("mir-fixture-mir5-active-mods-observer"); variants.append(("observer", self.candidate_raw(), missing_observer))
        wrong_effect = self.candidate_raw(); wrong_effect["technology"][DIRECT]["effects"][0]["change"] = .05; variants.append(("effect", wrong_effect, f200))
        empty_science = self.candidate_raw(); empty_science["technology"][DIRECT]["unit"]["ingredients"] = []; variants.append(("science", empty_science, f200))
        for label, raw, mods in variants:
            with self.subTest(label=label):
                before = copy.deepcopy(raw)
                rejected = self.run_data(raw, mods)
                self.assertFalse(rejected["ok"])
                # lupa represents an empty Lua vector as an empty mapping on
                # the way back to Python.  Check the actual mutation boundary
                # instead: rejection cannot alter the selected cost/time or
                # unrelated raw table, including the malformed empty science
                # vector that triggered this opponent.
                before_direct = before["technology"][DIRECT]
                after_direct = rejected["raw"]["technology"][DIRECT]
                self.assertEqual(before_direct["unit"].get("count"), after_direct["unit"].get("count"))
                self.assertEqual(before_direct["unit"].get("count_formula"), after_direct["unit"].get("count_formula"))
                self.assertEqual(before_direct["unit"].get("time"), after_direct["unit"].get("time"))
                self.assertEqual(before["sentinel"], rejected["raw"]["sentinel"])

    def test_control_registers_without_runtime_access_and_refuses_missing_source_before_candidate_writes(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().successor_control_path = path
        self.lua.execute(r'''
          function migration_origin_110_successor_control()
            local callbacks,forbidden={events={}},{ }
            local env={script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
                ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
                ["mir-fixture-mir5-migration-origin-f200-110-source"]="0.2.0"},
              on_configuration_changed=function(fn) callbacks.configuration=fn end,
              on_load=function(fn) callbacks.load=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},storage={}}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              return {storage_key="mir5_migration_origin_f200_110_source",fixture="mir-fixture-mir5-migration-origin-f200-110-source",
                direct="recipe-prod-research_gears-1",gear_recipe="iron-gear-wheel",save="mir5-native-complete",deadline_ticks=18000,lab_packs=32,expected_gear_delta=.1,
                source_change_tokens={[.1]="0.10000000149011612",[.05]="0.05000000074505806",[.02]="0.019999999552965164",[.2]="0.20000000298023224"},
                rows={["recipe-prod-research_gears-1"]={{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}}},settings={test=true},
                targets={f200={base="2.0.77",mir="5.0.20000",fixture="0.2.0"},f210={base="2.1.23",mir="5.0.21000",fixture="0.3.0"}}}
            end
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local ok_parse,message_parse=pcall(function() assert(loadfile(successor_control_path,"t",env))() end)
            local ok_config,message_config=pcall(function() callbacks.configuration({}) end)
            return {ok_parse=ok_parse,message_parse=tostring(message_parse),ok_config=ok_config,message_config=tostring(message_config),callbacks=callbacks,forbidden=forbidden,storage=env.storage}
          end
        ''')
        result = py(self.lua.eval("migration_origin_110_successor_control")())
        self.assertTrue(result["ok_parse"], result["message_parse"])
        self.assertIsNotNone(result["callbacks"]["configuration"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertEqual({}, result["forbidden"])
        self.assertFalse(result["ok_config"])
        self.assertIn("protected MIR 1.1 source state is absent", result["message_config"])
        self.assertEqual({}, result["storage"])

    def test_profiles_bind_the_one_passed_r05_source_and_pin_only_a575_inputs(self):
        f200, f210 = json.loads(F200_PROFILE.read_text()), json.loads(F210_PROFILE.read_text())
        for profile in (f200, f210):
            self.assertEqual("88FC8E9891040275E001930C3E6AA0A4A7A28C31D81DF30E3F08AEDD98E5019A",
                             profile["source_save"]["sha256"])
            self.assertEqual("4FBD622144E3B69E39C0530385AA70C92971208584CA32D4A10B1FCC1A978997",
                             profile["source_save"]["source_result_sha256"])
            self.assertEqual(("a575a4198807b6aea9e26963e3d9970fc5c068ae", "398c79c687d2bc662c976355ced1436201c43f11"),
                             (profile["candidate"]["source_commit"], profile["candidate"]["player_tree"]))
            self.assertEqual("d8e24b4a79b6064a373c03210c5ef6be0b013f79", profile["source_fixture_commit"])
            self.assertEqual("aae9bc947674cd059df60d9617a412a059970cc2", profile["successor_fixture_commit"])
            self.assertEqual("2fb64822b82569e3b50f0653e361fb7148f18b63", profile["origin_source_commit"])
        self.assertEqual("3DCB5676C3819CB2DF6F4177DC120A38B45FAC62D8BE795C8765E2D6A540D966",
                         f200["archive_sha256"]["mir-fixture-mir5-migration-origin-f200-110-source_0.2.0.zip"])
        self.assertEqual("E4BCB251C6D4D0FBAA5DD4E9F36E3B5969A6A7863A2C51E649CADBE6B99A315E",
                         f210["archive_sha256"]["mir-fixture-mir5-migration-origin-f200-110-source_0.3.0.zip"])
        self.assertEqual("8DB28D2DE45F26033B5F54E176902A3138A903AF0F4B48EAB6B9971466021B4F",
                         f200["archive_sha256"]["more-infinite-research_5.0.20000.zip"])
        self.assertEqual("7CE6A4DF78019F6B98237E638A1C927C5FDB538D4A1442EE22D846DD962DDCDC",
                         f210["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
        self.assertNotIn("space-age", {entry["name"] for entry in f210["mods"]})

    def test_control_keeps_only_the_saved_source_roster_as_earned_state(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("assert_snapshot(value.player_snapshot, names, \"player\", 2, 0)", control)
        self.assertIn("assert_snapshot(value.foreign_snapshot, names, \"foreign\", 1, .42)", control)
        self.assertIn("assert_snapshot(value.detached_snapshot, names, \"detached\", 1, .27)", control)
        self.assertIn("worker-robot-battery contribution", control)
        self.assertIn("event.by_script ~= false", control)
        self.assertLess(control.index("assert_source_before(state_value, names, false, 0)"), control.index("state_value.successors ="))
        self.assertNotIn("manual_mining_speed_modifier =", control)
        self.assertNotIn("pairs(game.forces.player.technologies)", control)

    def _install_lifecycle_model(self):
        """Install the source-storage-aware fixture lifecycle double."""
        catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().catalogue_path = catalogue_path
        self.lua.globals().successor_control_path = control_path
        self.lua.execute(r'''
          function migration_origin_110_successor_lifecycle(target, source_fixture_name, active_wrapper_name, catalogue_fixture_name)
            local callbacks={events={}}
            local env={storage={},logs={},created_labs=0,saved=false,
              script={active_mods={},on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_load=function(fn) callbacks.load=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            local catalogue
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
              if catalogue==nil then
                catalogue=assert(loadfile(catalogue_path,"t",env))()
                if catalogue_fixture_name~=nil then catalogue.fixture=catalogue_fixture_name end
              end
              return catalogue
            end
            env.log=function(message) env.logs[#env.logs+1]=message end
            env._G=env;setmetatable(env,{__index=_G})
            catalogue=env.require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
            local UINT32_MAX=4294967295
            local function close(left,right) return type(left)=="number" and type(right)=="number" and math.abs(left-right)<=.000001 end
            local function names()
              local result={};for name in pairs(catalogue.rows) do result[#result+1]=name end;table.sort(result);return result
            end
            local roster=names()
            local function source_effect_signature(name)
              local rows={}
              for _,effect in ipairs(catalogue.rows[name]) do
                if effect.type=="change-recipe-productivity" then
                  rows[#rows+1]=effect.type.."|"..effect.recipe.."|"..catalogue.source_change_tokens[effect.change]
                elseif effect.type=="worker-robot-battery" then
                  rows[#rows+1]=effect.type.."|"..catalogue.source_change_tokens[effect.modifier]
                end
              end
              table.sort(rows);return table.concat(rows,",")
            end
            local function recipe_values(direct_earned)
              local result={}
              for name,effects in pairs(catalogue.rows) do
                if name~=catalogue.direct or direct_earned then
                  for _,effect in ipairs(effects) do
                    if effect.type=="change-recipe-productivity" then
                      result[effect.recipe]=(result[effect.recipe] or 0)+effect.change
                    end
                  end
                end
              end
              return result
            end
            local function source_snapshot(direct_level,direct_progress)
              local technologies,effects={},{}
              for _,name in ipairs(roster) do
                technologies[name]={level=name==catalogue.direct and direct_level or 2,researched=false,
                  enabled=true,visible=false,saved=name==catalogue.direct and direct_progress or 0,maximum=UINT32_MAX}
                effects[name]=source_effect_signature(name)
              end
              return {technologies=technologies,effects=effects,recipes=recipe_values(direct_level>=2),
                fields={manual_mining_speed_modifier=0,worker_robots_battery_modifier=.1}}
            end
            local function make_force(label,direct_level,direct_progress)
              local snapshot=source_snapshot(direct_level,direct_progress)
              local force={name=label,valid=true,technologies={},recipes={},manual_mining_speed_modifier=0,
                worker_robots_battery_modifier=.1,research_queue={},research_progress=0,current_research=nil,add_calls=0}
              for _,name in ipairs(roster) do
                local saved=snapshot.technologies[name]
                local value={name=name,valid=true,level=saved.level,researched=false,enabled=true,visible_when_disabled=false,
                  saved_progress=saved.saved,prototype={max_level=UINT32_MAX,effects=catalogue.rows[name]},
                  research_unit_ingredients={{name="automation-science-pack",amount=1}}}
                value.force=force;force.technologies[name]=value
              end
              for recipe,value in pairs(snapshot.recipes) do force.recipes[recipe]={valid=true,productivity_bonus=value} end
              -- Native recipes exist independently of whether this force has
              -- earned a source productivity contribution for them.
              if force.recipes[catalogue.gear_recipe]==nil then
                force.recipes[catalogue.gear_recipe]={valid=true,productivity_bonus=0}
              end
              force.add_research=function(research)
                force.add_calls=force.add_calls+1;force.current_research=research;force.research_queue={research};force.research_progress=0;return true
              end
              return force,snapshot
            end
            local player,player_snapshot=make_force("player",2,0)
            local foreign,foreign_snapshot=make_force("foreign",1,.42)
            local detached,detached_snapshot=make_force("detached",1,.27)
            foreign.current_research=foreign.technologies[catalogue.direct]
            foreign.research_queue={foreign.technologies[catalogue.direct],foreign.technologies["recipe-prod-research_plastic-1"]}
            foreign.research_progress=.42
            local state={phase="completed",roster=roster,source_labs=1,player_snapshot=player_snapshot,
              foreign_index=2,foreign_snapshot=foreign_snapshot,
              foreign_queue={current=catalogue.direct,queue={catalogue.direct,"recipe-prod-research_plastic-1"},progress=.42},
              detached_index=3,detached_snapshot=detached_snapshot}
            -- Model Factorio's per-mod storage ownership: the protected
            -- state belongs to the source fixture identity, not every
            -- fixture whose source directory happens to contain this control.
            local storage_by_mod={[source_fixture_name]={[catalogue.storage_key]=state}}
            if storage_by_mod[active_wrapper_name]==nil then storage_by_mod[active_wrapper_name]={} end
            env.storage=storage_by_mod[active_wrapper_name]
            env.settings={startup={}}
            for name,value in pairs(catalogue.settings) do env.settings.startup[name]={value=value} end
            local inventory={items={}}
            inventory.clear=function() inventory.items={} end
            inventory.insert=function(row) inventory.items[row.name]=(inventory.items[row.name] or 0)+row.count;return row.count end
            inventory.get_item_count=function(name) return inventory.items[name] or 0 end
            local entity={valid=true,energy=0,get_inventory=function(_) return inventory end}
            env.game={forces={player=player,[2]=foreign,[3]=detached},tick=0,
              surfaces={[1]={create_entity=function(_) env.created_labs=env.created_labs+1;return entity end}},
              server_save=function(_) env.saved=true end}
            if target=="f200" then
              env.script.active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
                [active_wrapper_name]="0.2.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            else
              env.script.active_mods={base="2.1.23",["more-infinite-research"]="5.0.21000",
                [active_wrapper_name]="0.3.0",["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
            end
            local ok,message=pcall(function()
              assert(loadfile(successor_control_path,"t",env))()
              callbacks.configuration({})
              local direct=player.technologies[catalogue.direct]
              inventory.items["automation-science-pack"]=0
              direct.level=direct.level+1
              player.recipes[catalogue.gear_recipe].productivity_bonus=player.recipes[catalogue.gear_recipe].productivity_bonus+catalogue.expected_gear_delta
              player.current_research=nil;player.research_queue={};callbacks.events[1]({research=direct,by_script=false})
              env.game.tick=1;callbacks.events[2]()
              local saved_phase=state.successors[target].phase
              callbacks.load();env.game.tick=2;callbacks.events[2]()
              assert(saved_phase=="completed")
            end)
            return {ok=ok,message=tostring(message),state=state,
              saved=env.saved,created_labs=env.created_labs,logs=env.logs,
              foreign_gear=foreign.recipes[catalogue.gear_recipe].productivity_bonus,
              detached_gear=detached.recipes[catalogue.gear_recipe].productivity_bonus,
              player_gear=player.recipes[catalogue.gear_recipe].productivity_bonus,
              player_level=player.technologies[catalogue.direct].level,
              player_manual=player.manual_mining_speed_modifier,player_battery=player.worker_robots_battery_modifier,
              foreign_progress=foreign.research_progress,detached_progress=detached.technologies[catalogue.direct].saved_progress,
              player_add_calls=player.add_calls,source_state_changed=state.successors~=nil,
              active_state_changed=type(storage_by_mod[active_wrapper_name][catalogue.storage_key])=="table"
                and storage_by_mod[active_wrapper_name][catalogue.storage_key].successors~=nil}
          end
        ''')
    def test_control_preserves_the_independent_source_snapshot_through_one_real_candidate_lab_and_reload(self):
        """Exercise the real fixture lifecycle, including the non-earned direct row.

        The saved player owns the first direct gear contribution (level two),
        whereas the foreign and detached source witnesses keep that technology
        at level one.  Their gear bonus must therefore remain zero.  This is a
        source-state fact, not a convenience projection of the current MIR5
        catalogue.
        """
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        wrappers = {
            "f200": json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8")),
            "f210": json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8")),
        }
        for target, wrapper in wrappers.items():
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], wrapper["name"]))
                self.assertTrue(result["ok"], result["message"])
                self.assertTrue(result["saved"])
                self.assertEqual(1, result["created_labs"])
                self.assertEqual(1, result["player_add_calls"])
                self.assertEqual((3, .2), (result["player_level"], result["player_gear"]))
                self.assertEqual((0, 0), (result["foreign_gear"], result["detached_gear"]))
                self.assertEqual((0, .1), (result["player_manual"], result["player_battery"]))
                self.assertEqual((.42, .27), (result["foreign_progress"], result["detached_progress"]))
                self.assertEqual("completed", result["state"]["successors"][target]["phase"])
                self.assertEqual(1, result["state"]["successors"][target]["candidate_actual_labs"])
                self.assertEqual(2, len(result["logs"]))
                self.assertIn('"stage":"initial"', result["logs"][0])
                self.assertIn('"stage":"reload"', result["logs"][1])
                self.assertTrue(result["source_state_changed"])
                self.assertTrue(result["active_state_changed"])

    def test_renamed_successor_cannot_consume_the_protected_source_storage(self):
        self._install_lifecycle_model()
        source = json.loads((SOURCE_FIXTURE / "info.json").read_text(encoding="utf-8"))
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                result = py(self.lua.eval("migration_origin_110_successor_lifecycle")(
                    target, source["name"], RETIRED_SUCCESSOR_NAME, RETIRED_SUCCESSOR_NAME))
                self.assertFalse(result["ok"])
                self.assertIn("protected MIR 1.1 source state is absent", result["message"])
                self.assertNotIn("successor runtime target closure differs", result["message"])
                self.assertEqual(0, result["created_labs"])
                self.assertEqual(0, result["player_add_calls"])
                self.assertFalse(result["source_state_changed"])
                self.assertFalse(result["active_state_changed"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    MigrationOriginF200110SuccessorControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginF200110SuccessorControls))
    sys.exit(0 if result.wasSuccessful() else 1)
