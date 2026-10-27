"""Host controls for the exact MIR 1.0.0 source-save successor observer."""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-100-successor"
F200_PROFILE = ROOT / "tests/profiles/migration-origins-1.0.0-successor-f200-2077.json"
F210_PROFILE = ROOT / "tests/profiles/migration-origins-1.0.0-successor-f210-2123.json"
NAME = "mir-fixture-mir5-migration-origin-f200-100-source"
DIRECT = "recipe-prod-research_gears-1"


def py(value):
    if hasattr(value, "items"):
        items = list(value.items())
        keys = [key for key, _ in items]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in items}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class MigrationOriginSuccessorControls(unittest.TestCase):
    def candidate_raw(self):
        return {"technology": {
            DIRECT: {"type": "technology", "name": DIRECT, "level": 1, "upgrade": True,
                     "max_level": "infinite", "enabled": True,
                     "unit": {"count_formula": "9000*2^(L-1)", "time": 60,
                              "ingredients": [["automation-science-pack", 1]]},
                     "effects": [{"type": "change-recipe-productivity",
                                  "recipe": "iron-gear-wheel", "change": .10}]},
        }, "sentinel": {"unchanged": 23}}

    def run_data(self, raw, mods):
        path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().successor_data_path = path
        self.lua.execute(r'''
          function migration_successor_run_data(raw, mods)
            local catalogue={fixture="mir-fixture-mir5-migration-origin-f200-100-source",
              direct="recipe-prod-research_gears-1",gear_recipe="iron-gear-wheel",
              targets={f200={base="2.0.77",mir="5.0.20000",fixture="0.2.0"},
                       f210={base="2.1.23",mir="5.0.21000",fixture="0.3.0"}},expected_gear_delta=.10}
            local env={data={raw=raw},mods=mods}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue");return catalogue end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(successor_data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_successor_run_data")(
            lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def test_data_guard_admits_only_the_two_exact_current_targets_and_only_accelerates_direct_cost(self):
        f200 = {"base": "2.0.77", "more-infinite-research": "5.0.20000", NAME: "0.2.0",
                "mir-fixture-mir5-active-mods-observer": "0.1.0"}
        f210 = {"base": "2.1.23", "more-infinite-research": "5.0.21000", NAME: "0.3.0",
                "mir-fixture-mir5-active-mods-observer": "0.1.0"}
        for label, mods in (("f200", f200), ("f210", f210)):
            with self.subTest(label=label):
                accepted = self.run_data(self.candidate_raw(), mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                direct = accepted["raw"]["technology"][DIRECT]["unit"]
                self.assertEqual((1, None, 1), (direct.get("count"), direct.get("count_formula"), direct["time"]))
                self.assertEqual(23, accepted["raw"]["sentinel"]["unchanged"])

        variants = []
        wrong_engine = dict(f200); wrong_engine["base"] = "2.1.23"; variants.append(("engine", self.candidate_raw(), wrong_engine))
        missing_observer = dict(f200); missing_observer.pop("mir-fixture-mir5-active-mods-observer"); variants.append(("observer", self.candidate_raw(), missing_observer))
        wrong_effect = self.candidate_raw(); wrong_effect["technology"][DIRECT]["effects"][0]["change"] = .01; variants.append(("effect", wrong_effect, f200))
        wrong_level = self.candidate_raw(); wrong_level["technology"][DIRECT]["level"] = 2; variants.append(("level", wrong_level, f200))
        missing_science = self.candidate_raw(); missing_science["technology"][DIRECT]["unit"]["ingredients"] = []; variants.append(("science", missing_science, f200))
        wrong_f210_fixture = dict(f210); wrong_f210_fixture[NAME] = "0.2.0"; variants.append(("metadata", self.candidate_raw(), wrong_f210_fixture))
        for label, raw, mods in variants:
            with self.subTest(label=label):
                before = copy.deepcopy(raw)
                rejected = self.run_data(raw, mods)
                self.assertFalse(rejected["ok"])
                # Lua represents an empty input table as a mapping on the
                # Python boundary, so compare the mutation boundary rather
                # than its transport shape.
                self.assertEqual(before["technology"][DIRECT]["unit"].get("count"),
                                 rejected["raw"]["technology"][DIRECT]["unit"].get("count"))
                self.assertEqual(before["technology"][DIRECT]["unit"].get("count_formula"),
                                 rejected["raw"]["technology"][DIRECT]["unit"].get("count_formula"))
                self.assertEqual(before["technology"][DIRECT]["unit"]["time"],
                                 rejected["raw"]["technology"][DIRECT]["unit"]["time"])

    def test_control_registers_configuration_lifecycle_without_work_at_parse_time(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().successor_control_path = path
        self.lua.execute(r'''
          function migration_successor_parse_control()
            local callbacks,forbidden={events={}},{ }
            local catalogue={storage_key="mir5_migration_origin_f200_100_source",
              fixture="mir-fixture-mir5-migration-origin-f200-100-source",direct="recipe-prod-research_gears-1",
              gear_recipe="iron-gear-wheel",breeding_setting="ips-enable-research_breeding",source_fixture_version="0.1.0",
              targets={f200={base="2.0.77",mir="5.0.20000",fixture="0.2.0"},f210={base="2.1.23",mir="5.0.21000",fixture="0.3.0"}},
              save="mir5-native-complete",deadline_ticks=18000,lab_packs=16,expected_gear_delta=.10}
            local env={script={active_mods={},on_configuration_changed=function(fn) callbacks.configuration=fn end,
              on_load=function(fn) callbacks.load=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue");return catalogue end
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local ok,message=pcall(function() assert(loadfile(successor_control_path,"t",env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        result = py(self.lua.eval("migration_successor_parse_control")())
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNotNone(result["callbacks"]["configuration"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertEqual(2, len(result["callbacks"]["events"]))
        self.assertEqual({}, result["forbidden"])

    def test_successor_settings_stage_supplies_only_the_explicit_false_startup_input(self):
        path = (FIXTURE / "settings-updates.lua").as_posix()
        self.lua.globals().successor_settings_path = path
        self.lua.execute(r'''
          function migration_successor_run_settings(raw, mods)
            local catalogue={fixture="mir-fixture-mir5-migration-origin-f200-100-source",
              breeding_setting="ips-enable-research_breeding",
              targets={f200={base="2.0.77",mir="5.0.20000",fixture="0.2.0"},
                       f210={base="2.1.23",mir="5.0.21000",fixture="0.3.0"}}}
            local env={data={raw=raw},mods=mods}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue");return catalogue end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(successor_settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        f200 = {"base": "2.0.77", "more-infinite-research": "5.0.20000", NAME: "0.2.0",
                "mir-fixture-mir5-active-mods-observer": "0.1.0"}
        f210 = {"base": "2.1.23", "more-infinite-research": "5.0.21000", NAME: "0.3.0",
                "mir-fixture-mir5-active-mods-observer": "0.1.0"}
        for label, mods in (("f200", f200), ("f210", f210)):
            with self.subTest(label=label):
                raw = {"bool-setting": {"ips-enable-research_breeding": {
                    "setting_type": "startup", "default_value": True}}, "sentinel": {"same": 7}}
                accepted = py(self.lua.eval("migration_successor_run_settings")(lua(self.lua, raw), lua(self.lua, mods)))
                self.assertTrue(accepted["ok"], accepted["message"])
                self.assertFalse(accepted["raw"]["bool-setting"]["ips-enable-research_breeding"]["default_value"])
                self.assertEqual(7, accepted["raw"]["sentinel"]["same"])
        wrong_default = {"bool-setting": {"ips-enable-research_breeding": {
            "setting_type": "startup", "default_value": False}}}
        rejected = py(self.lua.eval("migration_successor_run_settings")(lua(self.lua, wrong_default), lua(self.lua, f200)))
        self.assertFalse(rejected["ok"])
        self.assertFalse(rejected["raw"]["bool-setting"]["ips-enable-research_breeding"]["default_value"])

    def test_control_preserves_the_actual_source_baseline_then_records_separate_f200_and_f210_labs(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().successor_runtime_path = path
        self.lua.execute(r'''
          function migration_successor_run_control(target_name,mutate,already_current)
            local callbacks={events={}}
            local direct_name="recipe-prod-research_gears-1"
            local alternate_name="recipe-prod-research_plastic-1"
            local function tech(name,level,saved)
              return {name=name,valid=true,level=level,researched=false,enabled=true,visible_when_disabled=false,
                saved_progress=saved or 0,prototype={max_level=4294967295,effects={{type="change-recipe-productivity",
                recipe=name==direct_name and "iron-gear-wheel" or "plastic-bar",change=.1}},
                research_unit_ingredients={{name="automation-science-pack",amount=1}}},
                research_unit_ingredients={{name="automation-science-pack",amount=1}}}
            end
            local function force(name,gear_level,gear_bonus)
              local direct, alternate=tech(direct_name,gear_level,0), tech(alternate_name,2,0)
              local value={name=name,valid=true,technologies={[direct_name]=direct,[alternate_name]=alternate},
                recipes={["iron-gear-wheel"]={valid=true,productivity_bonus=gear_bonus},["plastic-bar"]={valid=true,productivity_bonus=.1}},
                manual_mining_speed_modifier=.125,research_queue={},research_progress=0,current_research=nil}
              direct.force=value;alternate.force=value
              value.add_calls=0
              value.add_research=function(research) value.add_calls=value.add_calls+1;value.current_research=research;value.research_queue={research};value.research_progress=0;return true end
              return value
            end
            local player, foreign, detached=force("player",2,.1), force("foreign",2,.1), force("detached",2,.1)
            if already_current then player.current_research=player.technologies[direct_name];player.research_queue={player.technologies[direct_name]} end
            foreign.research_queue={foreign.technologies[direct_name],foreign.technologies[alternate_name]}
            foreign.current_research=foreign.technologies[direct_name];foreign.research_progress=.42
            foreign.technologies[direct_name].saved_progress=.42
            detached.technologies[direct_name].saved_progress=.27
            if mutate then player.technologies[alternate_name].level=3 end
            local function effects(change,recipe)
              return "{n:1={s:change=n:"..string.format("%.17g",change)..",s:recipe=s:"..recipe..",s:type=s:change-recipe-productivity}}"
            end
            local function snapshot(direct_saved)
              return {technologies={
                [direct_name]={level=2,researched=false,enabled=true,visible=false,saved=direct_saved,maximum=4294967295},
                [alternate_name]={level=2,researched=false,enabled=true,visible=false,saved=0,maximum=4294967295}},
                effects={[direct_name]=effects(.1,"iron-gear-wheel"),[alternate_name]=effects(.1,"plastic-bar")},
                recipes={["iron-gear-wheel"]=.1,["plastic-bar"]=.1},fields={manual_mining_speed_modifier=.125}}
            end
            local expected, foreign_expected, detached_expected=snapshot(0), snapshot(.42), snapshot(.27)
            local state={phase="completed",roster={direct_name,alternate_name},alternate=alternate_name,source_labs=1,
              player_snapshot=expected,foreign_index=2,foreign_snapshot=foreign_expected,
              foreign_queue={current=direct_name,queue={direct_name,alternate_name},progress=.42},
              detached_index=3,detached_snapshot=detached_expected}
            local inventory={items={}}
            function inventory.clear() inventory.items={} end
            function inventory.insert(row) inventory.items[row.name]=(inventory.items[row.name] or 0)+row.count;return row.count end
            local entity={valid=true,energy=0,get_inventory=function() return inventory end}
            local env
            env={
              storage={mir5_migration_origin_f200_100_source=state},
              settings={startup={["ips-enable-research_breeding"]={value=false}}},
              game={forces={player=player,[2]=foreign,[3]=detached},surfaces={[1]={create_entity=function() return entity end}},tick=0,speed=1,
                server_save=function(_) env.saved=true end},
              helpers={table_to_json=function(_) return "{}" end}, log=function(message) env.logs[#env.logs+1]=message end, logs={},
              script={active_mods={},on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_load=function(fn) callbacks.load=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
            }
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue");return {
              storage_key="mir5_migration_origin_f200_100_source",fixture="mir-fixture-mir5-migration-origin-f200-100-source",
              direct=direct_name,gear_recipe="iron-gear-wheel",breeding_setting="ips-enable-research_breeding",
              targets={f200={base="2.0.77",mir="5.0.20000",fixture="0.2.0"},f210={base="2.1.23",mir="5.0.21000",fixture="0.3.0"}},
              save="mir5-native-complete",deadline_ticks=18000,lab_packs=16,expected_gear_delta=.1} end
            env._G=env;setmetatable(env,{__index=_G})
            local function mods_for(target)
              if target=="f200" then return {base="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-active-mods-observer"]="0.1.0",
                ["mir-fixture-mir5-migration-origin-f200-100-source"]="0.2.0"} end
              return {base="2.1.23",["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-active-mods-observer"]="0.1.0",
                ["mir-fixture-mir5-migration-origin-f200-100-source"]="0.3.0"}
            end
            local function load_target(target)
              callbacks={events={}};env.script.active_mods=mods_for(target)
              assert(loadfile(successor_runtime_path,"t",env))()
              callbacks.configuration()
            end
            local function reload_target(target)
              callbacks={events={}};env.script.active_mods=mods_for(target)
              assert(loadfile(successor_runtime_path,"t",env))()
              callbacks.load();env.game.tick=2;callbacks.events[2]()
            end
            local function stable(value)
              if type(value)~="table" then return tostring(value) end
              local keys={};for key in pairs(value) do keys[#keys+1]=key end
              table.sort(keys,function(left,right)return tostring(left)<tostring(right) end)
              local rows={};for _,key in ipairs(keys) do rows[#rows+1]=tostring(key).."="..stable(value[key]) end
              return "{"..table.concat(rows,",").."}"
            end
            local function finish()
              local direct=player.technologies[direct_name]
              direct.level=direct.level+1;player.recipes["iron-gear-wheel"].productivity_bonus=player.recipes["iron-gear-wheel"].productivity_bonus+.1
              player.current_research=nil;player.research_queue={};callbacks.events[1]({research=direct});env.game.tick=1;callbacks.events[2]()
            end
            local ok,message=pcall(function()
              load_target(target_name)
              finish();local before_reload=stable(state);reload_target(target_name);env.reload_read_only=(before_reload==stable(state))
            end)
            return {ok=ok,message=tostring(message),state=state,gear=player.technologies[direct_name].level,
              bonus=player.recipes["iron-gear-wheel"].productivity_bonus,saved=env.saved,logs=env.logs,
              reload_read_only=env.reload_read_only,add_calls=player.add_calls}
          end
        ''')
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                accepted = py(self.lua.eval("migration_successor_run_control")(target, False))
                self.assertTrue(accepted["ok"], accepted["message"])
                self.assertEqual((3, .2, True), (accepted["gear"], accepted["bonus"], accepted["saved"]))
                self.assertEqual("completed", accepted["state"]["successors"][target]["phase"])
                self.assertEqual(1, accepted["state"]["successors"][target]["candidate_actual_labs"])
                self.assertEqual(2, len(accepted["logs"]))
                self.assertTrue(accepted["reload_read_only"])
                self.assertEqual(1, accepted["add_calls"])

        already_current = py(self.lua.eval("migration_successor_run_control")("f200", False, True))
        self.assertTrue(already_current["ok"], already_current["message"])
        self.assertEqual(0, already_current["add_calls"])

        rejected = py(self.lua.eval("migration_successor_run_control")("f200", True, False))
        self.assertFalse(rejected["ok"])
        self.assertIn("source row changed before candidate work", rejected["message"])
        self.assertEqual(2, rejected["gear"])

    def test_fixture_identity_profiles_and_storage_preservation_contract_are_exact(self):
        f200_info = json.loads((FIXTURE / "info-f200.json").read_text(encoding="utf-8"))
        f210_info = json.loads((FIXTURE / "info-f210.json").read_text(encoding="utf-8"))
        f200_profile, f210_profile = json.loads(F200_PROFILE.read_text()), json.loads(F210_PROFILE.read_text())
        self.assertEqual((NAME, "0.2.0", "2.0"), (f200_info["name"], f200_info["version"], f200_info["factorio_version"]))
        self.assertEqual((NAME, "0.3.0", "2.1"), (f210_info["name"], f210_info["version"], f210_info["factorio_version"]))
        self.assertEqual(("f200", "2.0.77", "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"),
                         (f200_profile["target"], f200_profile["engine"]["version"], f200_profile["engine"]["sha256"]))
        self.assertEqual(("f210", "2.1.23", "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"),
                         (f210_profile["target"], f210_profile["engine"]["version"], f210_profile["engine"]["sha256"]))
        self.assertEqual("F8B38209DA632C8B2EFA049C8F69CDB3E3EC01F6BEE0C5D03BAFF03C27989C54",
                         f200_profile["source_save"]["sha256"])
        self.assertEqual({"name": "ips-enable-research_breeding", "value": False,
                          "delivery": "fixture-settings-updates-default-for-successor-load-only",
                          "persistence_claim": False}, f200_profile["fixture_startup_setting"])
        self.assertEqual("BD1B88D7DE85489207F71C1B080FD61617FAEF9655370BF0332A51579308ECE3",
                         f200_profile["archive_sha256"]["more-infinite-research_5.0.20000.zip"])
        self.assertEqual("8B55E1CE22873EB20B0D270071A082CCC71C45530B1AAAD94800CD720AAE8FBE",
                         f200_profile["archive_sha256"][f"{NAME}_0.2.0.zip"])
        self.assertEqual("58F04FB9D417F2726835F4A6740490DE3C1841665DAC81C2BA3DFA94050D9457",
                         f210_profile["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
        self.assertEqual("F8B38209DA632C8B2EFA049C8F69CDB3E3EC01F6BEE0C5D03BAFF03C27989C54",
                         f210_profile["source_save"]["sha256"])
        self.assertEqual("ProtectedOriginalF200SourceSave", f210_profile["settings_mode"])
        self.assertNotIn("required_completed_f200_stage", f210_profile["source_save"])
        self.assertEqual("16609472F17EF4F4A4644A353D0696F0A9DAC66235107F7C8D58C1FA8E2CF1CC",
                         f210_profile["archive_sha256"][f"{NAME}_0.3.0.zip"])
        self.assertEqual({"README.md", "catalogue.lua", "control.lua", "data-final-fixes.lua", "info-f200.json", "info-f210.json", "settings-updates.lua"},
                         {path.name for path in FIXTURE.iterdir() if path.is_file()})
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('storage[KEY]', control)
        self.assertIn('assert_direct_before', control)
        self.assertIn('missing historical technology', control)
        self.assertIn('original MIR1 source', control)
        self.assertIn('freeze_lab(successor)', control)
        self.assertIn('candidate_actual_labs', control)
        self.assertNotIn('force.reset_technology_effects', control)
        self.assertNotIn('.level =', control)
        self.assertIn("loaded directly by the MIR5 F210 target",
                      (FIXTURE / "info-f210.json").read_text(encoding="utf-8"))
        self.assertNotIn('.researched =', control)
        self.assertIn('on_load_read_only', control)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    MigrationOriginSuccessorControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginSuccessorControls))
    sys.exit(0 if result.wasSuccessful() else 1)
