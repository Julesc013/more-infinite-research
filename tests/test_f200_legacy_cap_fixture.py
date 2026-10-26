"""Host controls for the private F200 positive old-cap continuity fixture.

The controls execute fixture data/control code with a bounded native-shaped
mock.  They do not run Factorio or qualify the published-to-MIR5 save.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/f200-legacy-cap"
ORACLE = ROOT / "spec/inventory/modern-f200-470.json"
F210_ORACLE = ROOT / "spec/inventory/modern-f210-470.json"
PUBLISHED_PROFILE = ROOT / "tests/profiles/f200-legacy-cap-published-4.7-2077.json"
MIR5_PROFILE = ROOT / "tests/profiles/f200-legacy-cap-mir5-2077.json"
PUBLISHED_RELAXED_PROFILE = ROOT / "tests/profiles/f200-legacy-cap-published-relaxed-control-4.7-2077.json"
CROSS_SOURCE_PROFILE = ROOT / "tests/profiles/f200-legacy-cap-cross-f200-published-4.7.3-2077.json"
PUBLISHED_CONTROL_INFO = FIXTURE / "published-control-info.json"
F200_CROSS = FIXTURE / "f200/cross-to-f210"
F210_CROSS = FIXTURE / "f210/cross-from-f200"
F210_DISABLED = FIXTURE / "f210/disabled-after-f200"
F210_REENABLED = FIXTURE / "f210/reenabled-after-f200"
NAME = "mir-fixture-mir5-f200-legacy-cap"
GEAR = "recipe-prod-research_gears-1"
SCIENCE = ("automation-science-pack", "logistic-science-pack",
           "chemical-science-pack", "production-science-pack")


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (list, tuple)):
        return lua.table_from([lua_value(lua, item) for item in value])
    return value


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("cyclic Lua fixture value")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        result = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        result = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return result


class F200LegacyCapFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
        row = next(item["row"] for item in oracle["profiles"][0]["published_output"]["data"]["additions"]
                   if item["name"] == GEAR)
        cls.oracle_row = deepcopy(row)
        f210_oracle = json.loads(F210_ORACLE.read_text(encoding="utf-8"))
        f210_row = next(item["row"] for item in f210_oracle["profiles"][0]["published_output"]["data"]["additions"]
                        if item["name"] == GEAR)
        cls.f210_oracle_row = deepcopy(f210_row)
        # The fixture selects the historical 1% setting before data-final.
        cls.oracle_row["effects"][0]["change"] = .01
        cls.f210_oracle_row["effects"][0]["change"] = .01

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function legacy_cap_data(path, data_alias, base, mir, fixture, row, companions)
            local raw={technology={[row.name]=row},["double-setting"]={},["int-setting"]={}}
            raw["double-setting"]["ips-effect-per-level-research_gears"]={default_value=10}
            raw["int-setting"]["ips-max-level-research_gears"]={default_value=0}
            local mods={base=base,["more-infinite-research"]=mir,["mir-fixture-mir5-f200-legacy-cap"]=fixture}
            for name,value in pairs(companions or {}) do mods[name]=value end
            local env={mods=mods,data={raw=raw}}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-f200-legacy-cap__/fixture_data_final" and data_alias)
              return assert(loadfile(data_alias,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),row=row,raw=raw}
          end

          function legacy_cap_settings(path)
            local raw={["bool-setting"]={ ["ips-enable-research_gears"]={default_value=true}},["double-setting"]={ ["ips-effect-per-level-research_gears"]={default_value=10}},
              ["int-setting"]={ ["ips-max-level-research_gears"]={default_value=0}}}
            local env={data={raw=raw}}
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),enabled=raw["bool-setting"]["ips-enable-research_gears"].default_value,effect=raw["double-setting"]["ips-effect-per-level-research_gears"].default_value,
              cap=raw["int-setting"]["ips-max-level-research_gears"].default_value}
          end

          function legacy_cap_parse(path, base, mir, fixture, control_alias)
            local callbacks,reads={events={}},{}
            local env={script={active_mods={base=base,["more-infinite-research"]=mir,["mir-fixture-mir5-f200-legacy-cap"]=fixture},
              on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,
              on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-f200-legacy-cap__/fixture_control" and control_alias)
              return assert(loadfile(control_alias,"t",env))()
            end
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings"then reads[key]=(reads[key]or 0)+1 end
              return _G[key]
            end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end

          function legacy_cap_flow(source_path, destination_path, opponent, options)
            options=options or {}
            local callbacks,markers,diagnostics,saves,marker_cases={events={}},0,0,0,{}
            local GEAR="recipe-prod-research_gears-1"
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local function inventory()
              local value={items={},slots={},slot_by_name={}}
              local function stack(name)
                local current=value.slot_by_name[name]
                if current==nil then
                  current={valid_for_read=true,name=name,count=0,quality={name="normal"},durability=1}
                  value.slot_by_name[name]=current;value.slots[#value.slots+1]=current
                end
                return current
              end
              function value.insert(row)
                local current=stack(row.name);current.count=current.count+row.count;current.valid_for_read=current.count>0
                value.items[row.name]=current.count;return row.count
              end
              function value.get_item_count(name)
                local current=value.slot_by_name[name];return current and current.count or 0
              end
              function value.consume(name,amount)
                local current=stack(name);assert(current.count>=1 and current.durability>0)
                if amount==1 then
                  assert(math.abs(current.durability-1)<.000001)
                  current.count=current.count-1;current.valid_for_read=current.count>0
                else
                  assert(amount>0 and amount<1 and math.abs(current.durability-1)<.000001)
                  current.durability=current.durability-amount
                end
                value.items[name]=current.count
              end
              return setmetatable(value,{__len=function(current)return #current.slots end,
                __index=function(current,key)
                  if type(key)=="number" then return current.slots[key] end
                  return rawget(current,key)
                end})
            end
            local item_prototypes={}
            for _,name in ipairs(science) do
              item_prototypes[name]={get_durability=function(quality)
                assert(quality and quality.name=="normal");return 1
              end}
            end
            local input=inventory();local modules=setmetatable({},{__len=function()return 0 end})
            local lab={valid=true,energy=0,quality={name="normal"},prototype={get_researching_speed=function(quality)
              assert(quality and quality.name=="normal");return 1
            end}}
            function lab.get_inventory(index)assert(index==1);return input end
            function lab.get_module_inventory()return modules end
            local function tech(name, force)
              return {name=name,valid=true,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
                prototype={max_level=4294967295,visible_when_disabled=false},prerequisites={},research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},{name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1}}}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={['iron-gear-wheel']={productivity_bonus=0}},research_queue={},research_progress=0,
                laboratory_speed_modifier=0,laboratory_productivity_bonus=0}
              value.technologies[GEAR]=tech(GEAR,value);value.technologies["braking-force-1"]=tech("braking-force-1",value)
              function value.enable_all_prototypes()end
              function value.reset_technology_effects() value.recipes['iron-gear-wheel'].productivity_bonus=0 end
              function value.add_research(research)
                if type(research)=="string"then research=value.technologies[research]end
                if research==nil or value.current_research~=nil then return false end
                local transferred=research.saved_progress or 0
                if opponent=="lost-investment" and value.name=="player" and transferred>0 then transferred=.26 end
                value.current_research=research;value.research_queue={research};value.research_progress=transferred;research.saved_progress=0;return true
              end
              return value
            end
            local player,foreign=force("player",1),nil
            local game={tick=0,speed=1,forces={player=player,[1]=player},surfaces={}}
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
            function game.create_force(name)foreign=force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign end
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local function startup(cap, enabled)
              return {startup={
                ["ips-enable-research_gears"]={value=enabled ~= false},
                ["ips-max-level-research_gears"]={value=cap},["ips-effect-per-level-research_gears"]={value=1},
                ["mir-settings-profile-import"]={value=""},
              }}
            end
            local function rejected(message)
              local state=storage.mir5_f200_legacy_cap or {}
              return {ok=false,message=message,queue_entries=#player.research_queue,
                destination_labs=state.destination_lab_completions or 0,
                disabled_intermediate_observed=state.disabled_stage_observed == true,
                disabled_destination_labs=state.disabled_stage_destination_lab_completions or 0}
            end
            local function load_control(path,base,mir,version,settings_values,control_alias)
              local c={events={}}
              local env={script={active_mods={base=base,["more-infinite-research"]=mir,["mir-fixture-mir5-f200-legacy-cap"]=version},
                on_init=function(f)c.init=f end,on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,
                on_event=function(e,f)c.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
                game=game,storage=storage,settings=settings_values,prototypes={item=item_prototypes},helpers={table_to_json=function(row)
                  if row.status=="passed" then
                    assert(row.stage=="initial" or row.stage=="reload");marker_cases[#marker_cases+1]=row.case
                  else
                    assert(row.stage=="finish-before-assertion");assert(type(row.research_start_tick)=="number")
                    assert(type(row.research_finished_tick)=="number");assert(type(row.raw_elapsed_ticks)=="number")
                    assert(type(row.processing_ticks)=="number");assert(type(row.expected_processing_ticks)=="number")
                    assert(type(row.science_units_observed)=="table")
                  end
                  return "{}"
                end},log=function(row)
                  if row:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ") then markers=markers+1
                  else assert(row:match("^%[MIR5_NATIVE_FIXTURE%] DIAGNOSTIC "));diagnostics=diagnostics+1 end
                end}
              env.require=function(name)
                assert(name=="__mir-fixture-mir5-f200-legacy-cap__/fixture_control" and control_alias)
                return assert(loadfile(control_alias,"t",env))()
              end
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
              return ok and c or nil,tostring(result)
            end
            local function invoke(control, kind, event)
              local callback=kind=="tick" and control.events[1] or (kind=="finished" and control.events[2] or control[kind])
              if type(callback)~="function"then return false,"missing "..kind.." callback"end
              local ok,result=pcall(callback,event);return ok,tostring(result)
            end
            local function tick(control)
              game.tick=game.tick+1;return invoke(control,"tick")
            end
            local function complete_player(control, level, bonus, consumed_units)
              player.current_research=nil;player.research_queue={};player.research_progress=0;player.technologies[GEAR].level=level
              player.technologies[GEAR].researched=false;player.recipes['iron-gear-wheel'].productivity_bonus=bonus
              for _,science_name in ipairs(science)do input.consume(science_name,consumed_units or 1) end
              return invoke(control,"finished",{research=player.technologies[GEAR]})
            end
            local source_mir=options.source_mir or "4.7.20002"
            local source_fixture=options.source_fixture or "0.1.0"
            local source_base=options.source_base or "2.0.77"
            local destination_mir=options.destination_mir or "5.0.20000"
            local destination_fixture=options.destination_fixture or "0.2.0"
            local destination_base=options.destination_base or "2.0.77"
            local source,message=load_control(source_path,source_base,source_mir,source_fixture,startup(2),options.source_control_alias);if not source then return {ok=false,message=message}end
            -- The independently observed published on_init owns visibility
            -- before the dependent fixture's init, even below the cap.
            player.technologies[GEAR].visible_when_disabled=true
            player.technologies[GEAR].prototype.visible_when_disabled=true
            local ok,result=invoke(source,"init");if not ok then return {ok=false,message=result}end
            ok,result=complete_player(source,2,.01,1);if not ok then return {ok=false,message=result}end
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            ok,result=complete_player(source,3,.02,1);if not ok then return {ok=false,message=result}end
            player.technologies[GEAR].enabled=false;player.technologies[GEAR].visible_when_disabled=true
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            local state=storage.mir5_f200_legacy_cap
            if options.omit_source_case then state.source_case=nil end
            -- Two cold-source reload markers; on_load itself must only rebuild local witnesses.
            for _=1,2 do ok,result=invoke(source,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(source);if not ok then return {ok=false,message=result}end end
            if opponent=="stale-enable" then player.technologies[GEAR].enabled=false
            elseif opponent=="native-level" then player.technologies[GEAR].level=2
            elseif opponent=="foreign-queue" then foreign.research_progress=.41
            elseif opponent=="saved-progress" then player.technologies[GEAR].saved_progress=.26
            elseif opponent=="lab-count" then state.actual_lab_completions=1 end
            local three_stage=options.disabled_path~=nil or options.reenabled_path~=nil
            if three_stage and (options.disabled_path==nil or options.reenabled_path==nil) then
              return rejected("three-stage flow requires both F210 successors")
            end
            if three_stage and opponent~="skip-intermediate" then
              local disabled,message=load_control(options.disabled_path,options.disabled_base or "2.1.23",
                options.disabled_mir or "5.0.21000",options.disabled_fixture or "0.6.0",startup(40,opponent=="wrong-disabled-setting"),options.disabled_control_alias)
              if not disabled then return rejected(message) end
              ok,result=invoke(disabled,"load");if not ok then return rejected(result) end
              ok,result=invoke(disabled,"changed");if not ok then return rejected(result) end
              ok,result=tick(disabled);if not ok then return rejected(result) end
              for reload=1,2 do
                ok,result=invoke(disabled,"load");if not ok then return rejected(result) end
                if opponent=="disabled-reload-drift" and reload==1 then player.technologies[GEAR].saved_progress=.26 end
                ok,result=tick(disabled);if not ok then return rejected(result) end
              end
            end
            -- This is the candidate lifecycle result under test, not a fixture write.
            if opponent~="stale-enable" and opponent~="old-disabled-right" then
              player.technologies[GEAR].enabled=true;player.technologies[GEAR].visible_when_disabled=true
            end
            if three_stage then
              destination_path=options.reenabled_path
              destination_base=options.reenabled_base or "2.1.23"
              destination_mir=options.reenabled_mir or "5.0.21000"
              destination_fixture=options.reenabled_fixture or "0.7.0"
              options.destination_control_alias=options.reenabled_control_alias
            end
            local destination,message=load_control(destination_path,destination_base,destination_mir,destination_fixture,startup(40,opponent~="wrong-reenabled-setting"),options.destination_control_alias);if not destination then return {ok=false,message=message}end
            -- Native upgrade loads the old fixture state before configuration_changed.
            ok,result=invoke(destination,"load");if not ok then return rejected(result) end
            ok,result=invoke(destination,"changed");if not ok then return rejected(result) end
            local consumed_units=state.destination_science_accounting.consumed_units
            local processing_ticks=state.destination_science_accounting.remaining_ticks
            if opponent=="wrong-tick-span" then processing_ticks=processing_ticks-1 end
            if opponent=="raw-elapsed-offset" then game.tick=game.tick+1 end
            for _=1,processing_ticks do ok,result=tick(destination);if not ok then return rejected(result) end end
            if opponent=="consumption-overshoot" then consumed_units=consumed_units+1/60 end
            ok,result=complete_player(destination,4,.03,consumed_units);if not ok then return rejected(result) end
            if opponent=="duplicate-lab"then state.destination_lab_completions=2 end
            ok,result=tick(destination);if not ok then return rejected(result) end
            for _=1,2 do ok,result=invoke(destination,"load");if not ok then return rejected(result) end;ok,result=tick(destination);if not ok then return rejected(result) end end
            return {ok=true,message="",phase=state.phase,source_labs=state.actual_lab_completions,destination_labs=state.destination_lab_completions,
              player_level=player.technologies[GEAR].level,bonus=player.recipes['iron-gear-wheel'].productivity_bonus,
              player_enabled=player.technologies[GEAR].enabled,player_visible=player.technologies[GEAR].visible_when_disabled,
              science_before=state.destination_science_units_before[science[1]],science_after=state.destination_science_units_after[science[1]],
              consumed_units=state.destination_science_accounting.consumed_units,remaining_ticks=state.destination_science_accounting.remaining_ticks,
              processing_ticks=state.destination_processing_ticks,elapsed_ticks=state.destination_elapsed_ticks,current_progress=state.destination_science_accounting.progress,foreign_progress=foreign.research_progress,foreign_enabled=foreign.technologies[GEAR].enabled,
              source_mir=source_mir,destination_mir=destination_mir,source_base=source_base,destination_base=destination_base,
              source_case=state.source_case,marker_cases=marker_cases,markers=markers,diagnostics=diagnostics,saves=saves,
              disabled_intermediate_observed=state.disabled_stage_observed == true,
              disabled_destination_labs=state.disabled_stage_destination_lab_completions or 0}
          end
        ''')

    def row(self):
        return lua_value(self.lua, deepcopy(self.oracle_row))

    def f210_row(self):
        return lua_value(self.lua, deepcopy(self.f210_oracle_row))

    def data_result(self, path, base, mir, fixture, row, data_alias=None, companions=None):
        return self.lua.eval("legacy_cap_data")(str(path), str(data_alias) if data_alias else None,
                                                 base, mir, fixture, row,
                                                 lua_value(self.lua, companions or {}))

    def settings_result(self, path):
        return self.lua.eval("legacy_cap_settings")(str(path))

    def parse_result(self, path, base, mir, fixture, control_alias=None):
        return self.lua.eval("legacy_cap_parse")(str(path), base, mir, fixture,
                                                  str(control_alias) if control_alias else None)

    def flow_result(self, source_path, destination_path, opponent="", options=None):
        return self.lua.eval("legacy_cap_flow")(str(source_path), str(destination_path), opponent,
                                                 lua_value(self.lua, options or {}))

    def test_profiles_use_base_f200_observer_and_explicit_fixture_versions(self):
        for path, mir, version in ((PUBLISHED_PROFILE, "4.7.20002", "0.1.0"),
                                   (MIR5_PROFILE, "5.0.20000", "0.2.0"),
                                   (PUBLISHED_RELAXED_PROFILE, "4.7.20002", "0.3.0")):
            with self.subTest(profile=path.name):
                profile = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(("f200", "2.0.77"), (profile["target"], profile["engine"]["version"]))
                self.assertEqual(["base", "mir-fixture-mir5-active-mods-observer", "more-infinite-research", NAME],
                                 [item["name"] for item in profile["mods"]])
                self.assertEqual(mir, profile["mods"][2]["version"])
                self.assertEqual(version, profile["mods"][3]["version"])
                self.assertNotIn("space-age", [item["name"] for item in profile["mods"]])
                info_path = FIXTURE / "published/info.json" if version == "0.1.0" else (PUBLISHED_CONTROL_INFO if version == "0.3.0" else FIXTURE / "mir5/info.json")
                info = json.loads(info_path.read_text())
                self.assertEqual((NAME, version, "2.0"), (info["name"], info["version"], info["factorio_version"]))
                if version == "0.3.0":
                    self.assertEqual("F3943EB4D69CCDAC41BD9F922AD03A5C78F34F22D8E7FA5A88A7A658AB1010B7",
                                     profile["archive_sha256"]["more-infinite-research_4.7.20002.zip"])

    def test_cross_engine_source_profile_and_thin_stage_wrappers_pin_only_the_published_input(self):
        profile = json.loads(CROSS_SOURCE_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual((1, "mir5-f200-f210-positive-cap-cross-source", "f200", "2.0", "Defaults"),
                         (profile["schema"], profile["kind"], profile["target"], profile["factorio_line"], profile["settings_mode"]))
        self.assertEqual({"version": "2.0.77", "sha256": "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"},
                         profile["engine"])
        self.assertEqual({"base": "2.0.77", "mir-fixture-mir5-active-mods-observer": "0.1.0",
                          "more-infinite-research": "4.7.20003", NAME: "0.4.0"},
                         {row["name"]: row["version"] for row in profile["mods"]})
        self.assertEqual({
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip": "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87",
            "more-infinite-research_4.7.20003.zip": "FBBA844DD04011A12BB6DA885745B0733AD37FAB181EAAD9EE4346B9B0D32647",
        }, profile["archive_sha256"])
        self.assertIn("Input binding only; no native pass.", profile["scope"])

        source_info = json.loads(F200_CROSS.joinpath("info.json").read_text(encoding="utf-8"))
        successor_info = json.loads(F210_CROSS.joinpath("info.json").read_text(encoding="utf-8"))
        disabled_info = json.loads(F210_DISABLED.joinpath("info.json").read_text(encoding="utf-8"))
        reenabled_info = json.loads(F210_REENABLED.joinpath("info.json").read_text(encoding="utf-8"))
        self.assertEqual((NAME, "0.4.0", "2.0"), (source_info["name"], source_info["version"], source_info["factorio_version"]))
        self.assertEqual(["base = 2.0.77", "more-infinite-research = 4.7.20003"], source_info["dependencies"])
        self.assertEqual((NAME, "0.5.0", "2.1"), (successor_info["name"], successor_info["version"], successor_info["factorio_version"]))
        self.assertEqual("base = 2.1.23", successor_info["dependencies"][0])
        self.assertEqual("more-infinite-research = 5.0.21000", successor_info["dependencies"][-1])
        self.assertEqual({"? elevated-rails = 2.1.23", "? quality = 2.1.23", "? recycler = 2.1.23", "? space-age = 2.1.23"},
                         set(successor_info["dependencies"][1:-1]))
        for stage, version in ((F210_DISABLED, "0.6.0"), (F210_REENABLED, "0.7.0")):
            with self.subTest(stage=stage.name):
                info = disabled_info if stage == F210_DISABLED else reenabled_info
                self.assertEqual((NAME, version, "2.1"), (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(successor_info["dependencies"], info["dependencies"])
        for stage in (F200_CROSS, F210_CROSS, F210_DISABLED, F210_REENABLED):
            self.assertEqual('require("__mir-fixture-mir5-f200-legacy-cap__/fixture_control")\n',
                             stage.joinpath("control.lua").read_text(encoding="utf-8"))
            self.assertEqual('require("__mir-fixture-mir5-f200-legacy-cap__/fixture_data_final")\n',
                             stage.joinpath("data-final-fixes.lua").read_text(encoding="utf-8"))
        self.assertEqual((True, 1, 2), tuple(self.settings_result(F200_CROSS / "settings-updates.lua")[field]
                                             for field in ("ok", "effect", "cap")))
        self.assertEqual((True, 1, 40), tuple(self.settings_result(F210_CROSS / "settings-updates.lua")[field]
                                              for field in ("ok", "effect", "cap")))
        for stage, enabled in ((F210_DISABLED, False), (F210_REENABLED, True)):
            self.assertEqual((True, enabled, 1, 40), tuple(self.settings_result(stage / "settings-updates.lua")[field]
                                                           for field in ("ok", "enabled", "effect", "cap")))

    def test_cross_engine_stage_guards_preflight_independent_f200_and_f210_gear_rows(self):
        source_row = self.row()
        source_row["visible_when_disabled"] = True
        source = self.data_result(F200_CROSS / "data-final-fixes.lua", "2.0.77", "4.7.20003", "0.4.0", source_row,
                                  data_alias=FIXTURE / "published/data-final-fixes.lua")
        self.assertTrue(source["ok"], source["message"])
        self.assertEqual((None, "1", 1), (source["row"]["unit"]["count"], source["row"]["unit"]["count_formula"], source["row"]["unit"]["time"]))

        successor_row = self.f210_row()
        successor = self.data_result(F210_CROSS / "data-final-fixes.lua", "2.1.23", "5.0.21000", "0.5.0", successor_row,
                                     data_alias=FIXTURE / "mir5/data-final-fixes.lua")
        self.assertTrue(successor["ok"], successor["message"])
        self.assertEqual((None, "1", 1), (successor["row"]["unit"]["count"], successor["row"]["unit"]["count_formula"], successor["row"]["unit"]["time"]))
        self.assertEqual(.01, successor["row"]["effects"][1]["change"])

        bad_effect = self.f210_row()
        bad_effect["effects"][1]["change"] = .02
        rejected = self.data_result(F210_CROSS / "data-final-fixes.lua", "2.1.23", "5.0.21000", "0.5.0", bad_effect,
                                    data_alias=FIXTURE / "mir5/data-final-fixes.lua")
        self.assertFalse(rejected["ok"])
        self.assertIn("1% fixture-selected effect changed", rejected["message"])
        self.assertEqual(("8000*2^(L-1)", 60), (rejected["row"]["unit"]["count_formula"], rejected["row"]["unit"]["time"]))

        companion = self.data_result(F210_CROSS / "data-final-fixes.lua", "2.1.23", "5.0.21000", "0.5.0", self.f210_row(),
                                     data_alias=FIXTURE / "mir5/data-final-fixes.lua", companions={"quality": "2.1.23"})
        self.assertFalse(companion["ok"])
        self.assertIn("F210 Base successor carries Space Age companion", companion["message"])
        self.assertEqual(("8000*2^(L-1)", 60), (companion["row"]["unit"]["count_formula"], companion["row"]["unit"]["time"]))

        for stage, version in ((F210_DISABLED, "0.6.0"), (F210_REENABLED, "0.7.0")):
            with self.subTest(stage=stage.name):
                result = self.data_result(stage / "data-final-fixes.lua", "2.1.23", "5.0.21000", version,
                                          self.f210_row(), data_alias=FIXTURE / "mir5/data-final-fixes.lua")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((None, "1", 1),
                                 (result["row"]["unit"]["count"], result["row"]["unit"]["count_formula"],
                                  result["row"]["unit"]["time"]))

    def test_independent_base_oracle_preflight_precedes_the_only_count_time_mutation(self):
        for directory, mir, fixture in (("published", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
            with self.subTest(directory=directory):
                row = self.row()
                if directory == "published":
                    row["visible_when_disabled"] = True
                result = self.data_result(FIXTURE / directory / "data-final-fixes.lua", "2.0.77", mir, fixture, row)
                self.assertTrue(result["ok"], result["message"])
                unit = result["row"]["unit"]
                self.assertIsNone(unit["count"])
                self.assertEqual(("1", 1), (unit["count_formula"], unit["time"]))
                self.assertEqual(.01, result["row"]["effects"][1]["change"])
        bad = self.row()
        bad["visible_when_disabled"] = True
        bad["effects"][1]["change"] = .02
        result = self.data_result(FIXTURE / "published" / "data-final-fixes.lua", "2.0.77", "4.7.20002", "0.1.0", bad)
        self.assertFalse(result["ok"])
        self.assertIn("1% fixture-selected effect changed", result["message"])
        self.assertIsNone(result["row"]["unit"]["count"])
        self.assertEqual("8000*2^(L-1)", result["row"]["unit"]["count_formula"])
        self.assertEqual(60, result["row"]["unit"]["time"])
        wrong_published = self.row()
        result = self.data_result(FIXTURE / "published" / "data-final-fixes.lua", "2.0.77", "4.7.20002", "0.1.0", wrong_published)
        self.assertFalse(result["ok"])
        self.assertIn("cap presentation changed", result["message"])
        wrong_mir5 = self.row()
        wrong_mir5["visible_when_disabled"] = True
        result = self.data_result(FIXTURE / "mir5" / "data-final-fixes.lua", "2.0.77", "5.0.20000", "0.2.0", wrong_mir5)
        self.assertFalse(result["ok"])
        self.assertIn("fresh presentation changed", result["message"])

    def test_published_relaxation_uses_the_published_visibility_preflight_and_canonical_successor_control(self):
        published = (FIXTURE / "published/data-final-fixes.lua").read_text(encoding="utf-8")
        mir5 = (FIXTURE / "mir5/data-final-fixes.lua").read_text(encoding="utf-8")
        control = (FIXTURE / "mir5/control.lua").read_text(encoding="utf-8")
        self.assertIn("technology.visible_when_disabled == true", published)
        self.assertIn("cap presentation changed", published)
        self.assertIn("technology.visible_when_disabled == nil", mir5)
        self.assertIn("PUBLISHED_RELAXED_CASE", control)
        self.assertIn('mir == "4.7.20002" and fixture == "0.3.0"', control)

    def test_controls_parse_without_game_or_storage_access_and_never_write_source_player_presentation(self):
        for directory, mir, version in (("published", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
            with self.subTest(directory=directory):
                result = self.parse_result(FIXTURE / directory / "control.lua", "2.0.77", mir, version)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, plain(result["reads"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
        source = (FIXTURE / "published" / "control.lua").read_text(encoding="utf-8")
        self.assertIsNone(re.search(r"(?<![A-Za-z0-9_])gear\.enabled\s*=", source))
        self.assertIsNone(re.search(r"(?<![A-Za-z0-9_])gear\.visible_when_disabled\s*=", source))
        self.assertIn("technology(game.forces.player, GEAR).saved_progress = 0.27", source)
        self.assertIn("state.milestone = \"actual2labs\"", source)
        self.assertIn("await-second-queue", source)
        self.assertNotIn("research_queue_enabled", source)
        for directory in ("published", "mir5"):
            control = (FIXTURE / directory / "control.lua").read_text(encoding="utf-8")
            body = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
            self.assertNotIn("game.", body, f"{directory} on_load touched LuaGameScript")
            self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=", f"{directory} on_load wrote fixture storage")

    def test_cross_engine_wrappers_bind_retained_callbacks_and_preserved_cap_witness(self):
        source = self.parse_result(F200_CROSS / "control.lua", "2.0.77", "4.7.20003", "0.4.0",
                                   FIXTURE / "published/control.lua")
        successor = self.parse_result(F210_CROSS / "control.lua", "2.1.23", "5.0.21000", "0.5.0",
                                      FIXTURE / "mir5/control.lua")
        for stage, result in (("source", source), ("successor", successor)):
            with self.subTest(stage=stage):
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, plain(result["reads"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])

        options = {
            "source_base": "2.0.77", "source_mir": "4.7.20003", "source_fixture": "0.4.0",
            "destination_base": "2.1.23", "destination_mir": "5.0.21000", "destination_fixture": "0.5.0",
            "source_control_alias": str(FIXTURE / "published/control.lua"),
            "destination_control_alias": str(FIXTURE / "mir5/control.lua"),
        }
        result = self.flow_result(F200_CROSS / "control.lua", F210_CROSS / "control.lua", "", options)
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(("2.0.77", "4.7.20003", "2.1.23", "5.0.21000"),
                         (result["source_base"], result["source_mir"], result["destination_base"], result["destination_mir"]))
        self.assertEqual(("completed", 2, 1, 4, .03),
                         (result["phase"], result["source_labs"], result["destination_labs"], result["player_level"], result["bonus"]))
        self.assertTrue(result["player_enabled"])
        self.assertTrue(result["player_visible"])
        self.assertEqual((.42, False, 2), (result["foreign_progress"], result["foreign_enabled"], result["saves"]))
        self.assertEqual((44, 44, 44), (result["remaining_ticks"], result["processing_ticks"], result["elapsed_ticks"]))
        self.assertEqual(["f200-f210-positive-legacy-cap-source"] * 3 + ["f200-f210-positive-legacy-cap"] * 3,
                         plain(result["marker_cases"]))

        missing_case = self.flow_result(F200_CROSS / "control.lua", F210_CROSS / "control.lua", "",
                                        {**options, "omit_source_case": True})
        self.assertFalse(missing_case["ok"])
        self.assertIn("source case witness is absent or malformed", missing_case["message"])

        for opponent, phrase in {
            "stale-enable": "MIR5 F210 cross-engine restored player native gear state differs",
            "foreign-queue": "foreign queue or progress changed",
            "saved-progress": "MIR5 F210 cross-engine restored player saved progress differs",
        }.items():
            with self.subTest(opponent=opponent):
                rejected = self.flow_result(F200_CROSS / "control.lua", F210_CROSS / "control.lua", opponent, options)
                self.assertFalse(rejected["ok"])
                self.assertIn(phrase, rejected["message"])

    def test_cross_engine_disabled_intermediate_requires_the_observed_stage_before_reenabling_only_owned_gear(self):
        options = {
            "source_base": "2.0.77", "source_mir": "4.7.20003", "source_fixture": "0.4.0",
            "source_control_alias": str(FIXTURE / "published/control.lua"),
            "disabled_path": str(F210_DISABLED / "control.lua"), "disabled_base": "2.1.23", "disabled_mir": "5.0.21000",
            "disabled_fixture": "0.6.0", "disabled_control_alias": str(FIXTURE / "mir5/control.lua"),
            "reenabled_path": str(F210_REENABLED / "control.lua"), "reenabled_base": "2.1.23", "reenabled_mir": "5.0.21000",
            "reenabled_fixture": "0.7.0", "reenabled_control_alias": str(FIXTURE / "mir5/control.lua"),
        }
        for stage, version in ((F210_DISABLED, "0.6.0"), (F210_REENABLED, "0.7.0")):
            with self.subTest(parse=stage.name):
                parsed = self.parse_result(stage / "control.lua", "2.1.23", "5.0.21000", version,
                                           FIXTURE / "mir5/control.lua")
                self.assertTrue(parsed["ok"], parsed["message"])
                self.assertEqual({}, plain(parsed["reads"]))

        result = self.flow_result(F200_CROSS / "control.lua", F210_REENABLED / "control.lua", "", options)
        self.assertTrue(result["ok"], result["message"])
        self.assertTrue(result["disabled_intermediate_observed"])
        self.assertEqual(0, result["disabled_destination_labs"])
        self.assertEqual(("completed", 2, 1, 4, .03),
                         (result["phase"], result["source_labs"], result["destination_labs"],
                          result["player_level"], result["bonus"]))
        self.assertTrue(result["player_enabled"])
        self.assertTrue(result["player_visible"])
        self.assertEqual((.27, .42, False),
                         (result["current_progress"], result["foreign_progress"], result["foreign_enabled"]))
        self.assertEqual((9, 1, 3), (result["markers"], result["diagnostics"], result["saves"]))
        self.assertEqual(
            ["f200-f210-positive-legacy-cap-source"] * 3
            + ["f200-f210-positive-legacy-cap-disabled"] * 3
            + ["f200-f210-positive-legacy-cap-reenabled"] * 3,
            plain(result["marker_cases"]),
        )

        opponents = {
            "old-disabled-right": ("MIR5 F210 re-enabled cross-engine restored player native gear state differs", True),
            "skip-intermediate": ("required disabled intermediate witness is absent or malformed", False),
            "foreign-queue": ("foreign queue or progress changed", False),
            "saved-progress": ("MIR5 F210 disabled intermediate player saved progress differs", False),
            "disabled-reload-drift": ("disabled intermediate player saved progress differs", True),
            "wrong-disabled-setting": ("disabled intermediate did not retain the disabled owned family setting", False),
            "wrong-reenabled-setting": ("re-enabled successor did not retain the owned family setting", True),
        }
        for opponent, (phrase, observed) in opponents.items():
            with self.subTest(opponent=opponent):
                rejected = self.flow_result(F200_CROSS / "control.lua", F210_REENABLED / "control.lua", opponent, options)
                self.assertFalse(rejected["ok"])
                self.assertIn(phrase, rejected["message"])
                self.assertEqual(observed, rejected["disabled_intermediate_observed"])
                self.assertEqual((0, 0), (rejected["queue_entries"], rejected["destination_labs"]))

    def test_published_completed_v010_source_save_uses_only_the_exact_old_case_fallback_on_cold_reload(self):
        result = self.flow_result(FIXTURE / "published" / "control.lua", FIXTURE / "mir5" / "control.lua", "",
                                  {"omit_source_case": True})
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNone(result["source_case"])
        self.assertEqual(["f200-positive-legacy-cap"] * 6, plain(result["marker_cases"]))
        self.assertEqual((2, 1, 2), (result["source_labs"], result["destination_labs"], result["saves"]))

    def test_two_real_source_labs_restore_positive_cap_then_one_real_successor_lab_and_reload(self):
        result = self.flow_result(FIXTURE / "published" / "control.lua", FIXTURE / "mir5" / "control.lua")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual("completed", result["phase"])
        self.assertEqual((2, 1), (result["source_labs"], result["destination_labs"]))
        self.assertEqual((4, .03), (result["player_level"], result["bonus"]))
        self.assertTrue(result["player_enabled"])
        self.assertTrue(result["player_visible"])
        self.assertAlmostEqual(22, result["science_before"], places=6)
        self.assertAlmostEqual(22 - 44 / 60, result["science_after"], places=6)
        self.assertAlmostEqual(44 / 60, result["consumed_units"], places=6)
        self.assertEqual(44, result["remaining_ticks"])
        self.assertEqual(44, result["processing_ticks"])
        self.assertEqual(44, result["elapsed_ticks"])
        self.assertAlmostEqual(.27, result["current_progress"], places=6)
        self.assertEqual(.42, result["foreign_progress"])
        self.assertFalse(result["foreign_enabled"])
        self.assertEqual((6, 1, 2), (result["markers"], result["diagnostics"], result["saves"]))

    def test_exact_processing_ticks_accept_a_distinct_raw_event_elapsed(self):
        result = self.flow_result(FIXTURE / "published" / "control.lua", FIXTURE / "mir5" / "control.lua",
                                  "raw-elapsed-offset")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((44, 44, 45),
                         (result["remaining_ticks"], result["processing_ticks"], result["elapsed_ticks"]))
        self.assertEqual(1, result["diagnostics"])

    def test_published_relaxation_uses_the_same_tick_accounting_without_claiming_mir5_runtime(self):
        result = self.flow_result(FIXTURE / "published" / "control.lua", FIXTURE / "mir5" / "control.lua", "",
                                  {"destination_mir": "4.7.20002", "destination_fixture": "0.3.0"})
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((2, 1, 44), (result["source_labs"], result["destination_labs"], result["remaining_ticks"]))
        self.assertAlmostEqual(44 / 60, result["consumed_units"], places=6)

    def test_source_and_successor_continuity_opponents_fail(self):
        opponents = {
            "stale-enable": "MIR5 restored player native gear state differs",
            "native-level": "MIR5 restored player native gear state differs",
            "foreign-queue": "foreign queue or progress changed",
            "saved-progress": "MIR5 restored player saved progress differs",
            "lab-count": "published positive-cap source witness is absent",
            "duplicate-lab": "successor did not finish exactly one further lab level",
            "lost-investment": "successor saved research investment did not become current research",
            "wrong-tick-span": "successor real lab processing ticks differ",
            "consumption-overshoot": "successor real lab consumption differs for automation-science-pack: observed_units=",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = self.flow_result(FIXTURE / "published" / "control.lua", FIXTURE / "mir5" / "control.lua", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                if opponent == "consumption-overshoot":
                    self.assertIn("expected_units=21.266", result["message"])
                    self.assertIn("consumed_units=0.733", result["message"])
                    self.assertIn("remaining_ticks=44", result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(F200LegacyCapFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
