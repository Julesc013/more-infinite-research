"""Host controls for the exact MIR 1.0.0 source-save successor observer."""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-100-successor"
EARLY_OBSERVER = ROOT / "tests/fixtures/migration-origins/f200-100-early-entry-observer"
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

    def test_early_entry_observer_is_base_only_read_only_and_records_all_three_forces(self):
        info = json.loads((EARLY_OBSERVER / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(
            ("mir-fixture-mir5-migration-origin-f200-100-early-entry-observer", "0.1.0", "2.0"),
            (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual(["base = 2.0.77"], info["dependencies"])
        self.assertLess(info["name"], "more-infinite-research")

        path = (EARLY_OBSERVER / "control.lua").as_posix()
        self.lua.globals().early_entry_observer_path = path
        self.lua.execute(r'''
          function migration_early_entry_observer_run()
            local callbacks,logs={},{ }
            local player={valid=true,manual_mining_speed_modifier=.125}
            local foreign={valid=true,manual_mining_speed_modifier=.125}
            local detached={valid=true,manual_mining_speed_modifier=.125}
            local env={
              game={forces={player=player,
                ["mir5-migration-origin-f200-100-foreign"]=foreign,
                ["mir5-migration-origin-f200-100-detached"]=detached}},
              script={on_init=function(fn) callbacks.init=fn end,
                on_configuration_changed=function(fn) callbacks.configuration=fn end},
              log=function(message) logs[#logs+1]=message end}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="storage" then error("early observer must not access storage") end
              return _G[key]
            end})
            local ok,message=pcall(function()
              assert(loadfile(early_entry_observer_path,"t",env))()
              callbacks.init();callbacks.configuration({})
            end)
            return {ok=ok,message=tostring(message),logs=logs,
              values={player=player.manual_mining_speed_modifier,
                foreign=foreign.manual_mining_speed_modifier,
                detached=detached.manual_mining_speed_modifier}}
          end
        ''')
        result = py(self.lua.eval("migration_early_entry_observer_run")())
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual({"player": .125, "foreign": .125, "detached": .125}, result["values"])
        self.assertEqual(
            ['[MIR5_MIGRATION_ORIGIN_EARLY_OFFSET] {"event":"init","player":0.125,"foreign":0.125,"detached":0.125}',
             '[MIR5_MIGRATION_ORIGIN_EARLY_OFFSET] {"event":"configuration-changed","player":0.125,"foreign":0.125,"detached":0.125}'],
            result["logs"])

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
          function migration_successor_run_control(target_name,mutate,already_current,effect_case,reset_offsets_before_configuration,mutate_offset_after_configuration,preconfiguration_drift)
            local callbacks={events={}}
            local direct_name="recipe-prod-research_gears-1"
            local alternate_name="recipe-prod-research_plastic-1"
            local native_string, current_numeric_form=string, "source"
            local source_changes={[.1]="0.10000000149011612",[.05]="0.05000000074505806",
              [.02]="0.019999999552965164",[.01]="0.0099999997764825821"}
            local short_changes={[.1]="0.1",[.05]="0.05",[.02]="0.02",[.01]="0.01"}
            local function effect(recipe,change,kind,hidden)
              local row={type=kind or "change-recipe-productivity",recipe=recipe,change=change}
              if hidden~=nil then row.hidden=hidden end
              return row
            end
            local function source_record(recipe,change,kind)
              return {recipe=recipe,change=source_changes[change],kind=kind or "change-recipe-productivity"}
            end
            local function direct_source_records()
              if effect_case=="ordered" then return {source_record("iron-gear-wheel",.1),source_record("advanced-circuit",.1)} end
              if effect_case=="four-values" then return {source_record("iron-gear-wheel",.1),source_record("advanced-circuit",.05),
                source_record("processing-unit",.02),source_record("low-density-structure",.01)} end
              if effect_case=="ten-records" then return {source_record("iron-gear-wheel",.1),source_record("advanced-circuit",.05),
                source_record("processing-unit",.02),source_record("low-density-structure",.01),source_record("electric-engine-unit",.1),
                source_record("rocket-control-unit",.05),source_record("speed-module",.02),source_record("productivity-module",.01),
                source_record("utility-science-pack",.1),source_record("space-science-pack",.05)} end
              if effect_case=="missing-duplicate" then return {source_record("iron-gear-wheel",.1),source_record("iron-gear-wheel",.1)} end
              return {source_record("iron-gear-wheel",.1)}
            end
            local function direct_current_effects()
              if effect_case=="ordered" then return {effect("advanced-circuit",.1),effect("iron-gear-wheel",.1,false,false)} end
              if effect_case=="four-values" then return {effect("low-density-structure",.01,false,false),effect("processing-unit",.02),
                effect("advanced-circuit",.05,false,false),effect("iron-gear-wheel",.1)} end
              if effect_case=="ten-records" then return {effect("space-science-pack",.05),effect("utility-science-pack",.1,false,false),
                effect("productivity-module",.01),effect("speed-module",.02),effect("rocket-control-unit",.05),effect("electric-engine-unit",.1),
                effect("low-density-structure",.01),effect("processing-unit",.02),effect("advanced-circuit",.05,false,false),effect("iron-gear-wheel",.1)} end
              if effect_case=="wrong-recipe" then return {effect("steel-plate",.1)} end
              if effect_case=="wrong-type" then return {effect("iron-gear-wheel",.1,"unlock-recipe")} end
              if effect_case=="wrong-change" then return {effect("iron-gear-wheel",.05)} end
              if effect_case=="hidden-true" then return {effect("iron-gear-wheel",.1,false,true)} end
              if effect_case=="duplicate" then return {effect("iron-gear-wheel",.1),effect("iron-gear-wheel",.1)} end
              if effect_case=="missing-duplicate" then return {effect("iron-gear-wheel",.1)} end
              return {effect("iron-gear-wheel",.1)}
            end
            local function tech(name,level,saved)
              local effect_rows=name==direct_name and direct_current_effects() or {effect("plastic-bar",.1)}
              return {name=name,valid=true,level=level,researched=false,enabled=true,visible_when_disabled=false,
                saved_progress=saved or 0,prototype={max_level=4294967295,effects=effect_rows,
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
            local function effects(records)
              local indexed,rows={},{}
              for index,row in ipairs(records) do indexed[#indexed+1]={index=index,row=row} end
              table.sort(indexed,function(left,right) return tostring(left.index)<tostring(right.index) end)
              for _,value in ipairs(indexed) do
                local row=value.row
                rows[#rows+1]="n:"..value.index.."={s:change=n:"..row.change..",s:recipe=s:"..row.recipe..",s:type=s:"..row.kind.."}"
              end
              return "{"..table.concat(rows,",").."}"
            end
            local function snapshot(direct_saved)
              return {technologies={
                [direct_name]={level=2,researched=false,enabled=true,visible=false,saved=direct_saved,maximum=4294967295},
                [alternate_name]={level=2,researched=false,enabled=true,visible=false,saved=0,maximum=4294967295}},
                effects={[direct_name]=effects(direct_source_records()),[alternate_name]=effects({source_record("plastic-bar",.1)})},
                recipes={["iron-gear-wheel"]=.1,["plastic-bar"]=.1},fields={manual_mining_speed_modifier=.125}}
            end
            local expected, foreign_expected, detached_expected=snapshot(0), snapshot(.42), snapshot(.27)
            local state={phase="completed",roster={direct_name,alternate_name},alternate=alternate_name,source_labs=1,
              player_snapshot=expected,foreign_index=2,foreign_snapshot=foreign_expected,
              foreign_queue={current=direct_name,queue={direct_name,alternate_name},progress=.42},
              detached_index=3,detached_snapshot=detached_expected}
            local initial_source_effect_signature=state.player_snapshot.effects[direct_name]
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
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
              string=setmetatable({format=function(pattern,value)
                if pattern=="%.17g" and type(value)=="number" and source_changes[value]~=nil then
                  if current_numeric_form=="short" then return short_changes[value] end
                  return source_changes[value]
                end
                return native_string.format(pattern,value)
              end},{__index=native_string})
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
              callbacks={events={}};current_numeric_form=target=="f210" and "short" or "source";env.script.active_mods=mods_for(target)
              assert(loadfile(successor_runtime_path,"t",env))()
              if reset_offsets_before_configuration then
                player.manual_mining_speed_modifier=0
                foreign.manual_mining_speed_modifier=0
                detached.manual_mining_speed_modifier=0
              end
              if preconfiguration_drift=="player" then player.manual_mining_speed_modifier=.25 end
              if preconfiguration_drift=="foreign" then foreign.manual_mining_speed_modifier=.25 end
              if preconfiguration_drift=="detached" then detached.manual_mining_speed_modifier=.25 end
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
              if mutate_offset_after_configuration then player.manual_mining_speed_modifier=.25 end
              finish();local before_reload=stable(state);reload_target(target_name);env.reload_read_only=(before_reload==stable(state))
            end)
            return {ok=ok,message=tostring(message),state=state,gear=player.technologies[direct_name].level,
              bonus=player.recipes["iron-gear-wheel"].productivity_bonus,saved=env.saved,logs=env.logs,
              reload_read_only=env.reload_read_only,add_calls=player.add_calls,
              offsets={player=player.manual_mining_speed_modifier,foreign=foreign.manual_mining_speed_modifier,
                detached=detached.manual_mining_speed_modifier},
              source_effect_signature=state.player_snapshot.effects[direct_name],
              initial_source_effect_signature=initial_source_effect_signature}
          end
        ''')
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                accepted = py(self.lua.eval("migration_successor_run_control")(target, False))
                self.assertTrue(accepted["ok"], accepted["message"])
                self.assertEqual((3, .2, True), (accepted["gear"], accepted["bonus"], accepted["saved"]))
                self.assertEqual("completed", accepted["state"]["successors"][target]["phase"])
                self.assertEqual(1, accepted["state"]["successors"][target]["candidate_actual_labs"])
                self.assertEqual(3, len(accepted["logs"]))
                self.assertIn('"player_action":"retained","foreign_action":"retained","detached_action":"retained"', accepted["logs"][0])
                self.assertTrue(accepted["reload_read_only"])
                self.assertEqual(1, accepted["add_calls"])

        reapply = py(self.lua.eval("migration_successor_run_control")("f200", False, False, None, True))
        self.assertTrue(reapply["ok"], reapply["message"])
        reapply_markers = [line for line in reapply["logs"] if "MIR5_MIGRATION_ORIGIN_OFFSET_REAPPLY" in line]
        self.assertEqual(1, len(reapply_markers))
        self.assertIn('"player_before":0,"foreign_before":0,"detached_before":0', reapply_markers[0])
        self.assertIn('"player_action":"reapplied","foreign_action":"reapplied","detached_action":"reapplied"', reapply_markers[0])
        self.assertIn('"player_expected":0.125,"foreign_expected":0.125,"detached_expected":0.125', reapply_markers[0])
        self.assertTrue(reapply["reload_read_only"])

        for force_name in ("player", "foreign", "detached"):
            with self.subTest(preconfiguration_drift=force_name):
                rejected = py(self.lua.eval("migration_successor_run_control")(
                    "f200", False, False, None, False, False, force_name))
                self.assertFalse(rejected["ok"])
                self.assertIn(force_name + " source-owned pre-configuration offset differs", rejected["message"])
                self.assertEqual({}, rejected["state"].get("successors", {}))
                self.assertEqual(0, rejected["add_calls"])
                self.assertEqual(.25, rejected["offsets"][force_name])

        # The source snapshot remains raw/indexed.  Current F210 may expose
        # the same additive effects in a different order, with explicit
        # hidden=false and short decimals; the fixture may project only those
        # verified representation differences for its comparison.
        ordered = py(self.lua.eval("migration_successor_run_control")("f210", False, False, "ordered"))
        self.assertTrue(ordered["ok"], ordered["message"])
        self.assertEqual(
            "{n:1={s:change=n:0.10000000149011612,s:recipe=s:iron-gear-wheel,s:type=s:change-recipe-productivity},"
            "n:2={s:change=n:0.10000000149011612,s:recipe=s:advanced-circuit,s:type=s:change-recipe-productivity}}",
            ordered["source_effect_signature"])
        all_changes = py(self.lua.eval("migration_successor_run_control")("f210", False, False, "four-values"))
        self.assertTrue(all_changes["ok"], all_changes["message"])
        self.assertIn("0.05000000074505806", all_changes["source_effect_signature"])
        self.assertIn("0.019999999552965164", all_changes["source_effect_signature"])
        self.assertIn("0.0099999997764825821", all_changes["source_effect_signature"])
        ten_records = py(self.lua.eval("migration_successor_run_control")("f210", False, False, "ten-records"))
        self.assertTrue(ten_records["ok"], ten_records["message"])
        self.assertIn("n:1=", ten_records["source_effect_signature"])
        self.assertLess(ten_records["source_effect_signature"].index("n:10="),
                        ten_records["source_effect_signature"].index("n:2="))

        for effect_case in ("wrong-recipe", "wrong-type", "wrong-change", "hidden-true", "duplicate", "missing-duplicate"):
            with self.subTest(effect_case=effect_case):
                rejected = py(self.lua.eval("migration_successor_run_control")("f210", False, False, effect_case))
                self.assertFalse(rejected["ok"])
                self.assertIn("effect", rejected["message"])
                # Failure must neither rewrite the saved source signature nor
                # create a candidate lab/continuation record.
                self.assertEqual(rejected["initial_source_effect_signature"],
                                 rejected["source_effect_signature"])
                self.assertEqual("completed", rejected["state"]["phase"])
                self.assertNotIn("f210", rejected["state"].get("successors", {}))

        already_current = py(self.lua.eval("migration_successor_run_control")("f200", False, True))
        self.assertTrue(already_current["ok"], already_current["message"])
        self.assertEqual(0, already_current["add_calls"])

        rejected = py(self.lua.eval("migration_successor_run_control")("f200", True, False))
        self.assertFalse(rejected["ok"])
        self.assertIn("source row changed before candidate work", rejected["message"])
        self.assertEqual(2, rejected["gear"])

        offset_rejected = py(self.lua.eval("migration_successor_run_control")("f200", False, False, None, False, True))
        self.assertFalse(offset_rejected["ok"])
        self.assertIn("player unrelated scripted offset changed expected=0.125 actual=0.25", offset_rejected["message"])
        self.assertEqual("completed", offset_rejected["state"]["phase"])
        self.assertEqual("await-observation", offset_rejected["state"]["successors"]["f200"]["phase"])

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
        self.assertEqual("838803FD017705EFE204EAA00413E5512AC90C3C4CF8F10E8B4F201FA693CE91",
                         f200_profile["archive_sha256"][f"{NAME}_0.2.0.zip"])
        self.assertEqual("58F04FB9D417F2726835F4A6740490DE3C1841665DAC81C2BA3DFA94050D9457",
                         f210_profile["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
        self.assertEqual("F8B38209DA632C8B2EFA049C8F69CDB3E3EC01F6BEE0C5D03BAFF03C27989C54",
                         f210_profile["source_save"]["sha256"])
        self.assertEqual("ProtectedOriginalF200SourceSave", f210_profile["settings_mode"])
        self.assertNotIn("required_completed_f200_stage", f210_profile["source_save"])
        self.assertEqual("514C9B2C2F3F564814C2EA621C3BCFD6837FEB4BC89B6B98FC84127CBF167ABF",
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
