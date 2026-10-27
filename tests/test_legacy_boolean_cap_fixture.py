"""Independent controls for the published F200 policy-v1 boolean-cap fixture.

These controls prepare native inputs only.  They do not model Factorio's old
controller, a save migration, or a laboratory result.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/legacy-boolean-cap"
SOURCE = FIXTURE / "published"
F200 = FIXTURE / "f200/successor"
F210 = FIXTURE / "f210/successor"
SUCCESSOR_BODY = FIXTURE / "fixture_control.lua"
SOURCE_PROFILE = ROOT / "tests/profiles/legacy-boolean-cap-published-400-f200-2077.json"
F200_PROFILE = ROOT / "tests/profiles/legacy-boolean-cap-current-f200-2077.json"
F210_PROFILE = ROOT / "tests/profiles/legacy-boolean-cap-current-f210-2123.json"
PREPARED_INPUT_RECEIPT = ROOT / "spec/evidence/legacy-boolean-cap-a575-prepared-inputs-9ef64ff41.json"
ARCHIVE_SHA256 = "5C0E299D78C4EE545958448DAE48D87BE5FE1B959875D4CB93A264D95D3DB0AE"
POLICY_SHA256 = "687E2EB214C7097C1691562ECE206AA69FDE24194164A8EF33F48AF14405C0EA"
GEAR = "recipe-prod-research_gears-1"
SCIENCE = [
    ["automation-science-pack", 1], ["logistic-science-pack", 1],
    ["chemical-science-pack", 1], ["production-science-pack", 1],
]
NAME = "mir-fixture-mir5-legacy-boolean-cap"
_package_spec = importlib.util.spec_from_file_location("legacy_boolean_cap_package", ROOT / "tools/package.py")
PACKAGE = importlib.util.module_from_spec(_package_spec)
_package_spec.loader.exec_module(PACKAGE)


def py(value):
    if hasattr(value, "items"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in value.items()}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


def raw_git_bytes(revision, path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)


class LegacyBooleanCapFixtureTests(unittest.TestCase):
    def row(self):
        return {
            "type": "technology", "name": GEAR, "upgrade": True, "max_level": "infinite",
            "enabled": True,
            "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                     "ingredients": copy.deepcopy(SCIENCE)},
            "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .10}],
        }

    def raw(self, tool_science=False):
        raw = {"technology": {GEAR: self.row()}, "sentinel": {"unchanged": 17}}
        if tool_science:
            raw["tool"] = {
                name: {"type": "tool", "name": name, "durability": 1}
                for name, _ in SCIENCE
            }
        return raw

    def run_data(self, path, raw, mods):
        self.lua.globals().fixture_data_path = path.as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def run_settings(self, path, mods):
        self.lua.globals().fixture_settings_path = path.as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_settings(mods)
            local cap={default_value=0,minimum_value=0,maximum_value=2147483647}
            local effect={default_value=10}
            local env={mods=mods,data={raw={ ["int-setting"]={ ["ips-max-level-research_gears"]=cap },
              ["double-setting"]={ ["ips-effect-per-level-research_gears"]=effect }}}}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),cap=cap,effect=effect}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_settings")(lua(self.lua, mods)))

    def parse_control(self, path, mods):
        self.lua.globals().fixture_control_path = path.as_posix()
        self.lua.globals().fixture_successor_body_path = SUCCESSOR_BODY.as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_parse(mods)
            local callbacks,forbidden={events={}},{}
            local env={script={active_mods=mods,on_init=function(fn) callbacks.init=fn end,
              on_load=function(fn) callbacks.load=fn end,on_configuration_changed=function(fn) callbacks.configuration=fn end,
              on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local modules={}
            env.require=function(name)
              if name~="__mir-fixture-mir5-legacy-boolean-cap__/fixture_control" then
                error("unexpected fixture module: "..tostring(name))
              end
              if modules[name]==nil then
                local chunk,message=loadfile(fixture_successor_body_path,"t",env);assert(chunk,message)
                modules[name]=chunk()
              end
              return modules[name]
            end
            local ok,message=pcall(function() assert(loadfile(fixture_control_path,"t",env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_parse")(lua(self.lua, mods)))

    def source_flow(self, keep_enabled=False):
        self.lua.globals().fixture_source_control_path = (SOURCE / "control.lua").as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_source_flow(keep_enabled)
            local callbacks,markers,saves={events={}},{},0
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local function inventory()
              local value={counts={}}
              function value.insert(request) value.counts[request.name]=(value.counts[request.name] or 0)+request.count;return request.count end
              function value.get_item_count(name) return value.counts[name] or 0 end
              return value
            end
            local function technology(name,force)
              return {name=name,force=force,valid=true,level=1,researched=false,enabled=true,visible_when_disabled=true,
                saved_progress=0,prerequisites={},prototype={max_level=4294967295},research_unit_count=1,research_unit_energy=60,
                research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},
                  {name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1}}}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={["iron-gear-wheel"]={productivity_bonus=0}},
                research_queue={},research_progress=0}
              local gear=technology("recipe-prod-research_gears-1",value)
              value.technologies[gear.name]=gear
              value.technologies["braking-force-1"]=technology("braking-force-1",value)
              function value.enable_all_prototypes() end
              function value.reset_technology_effects() end
              function value.add_research(research)
                if research==nil or value.current_research~=nil then return false end
                value.current_research=research;value.research_queue={research};value.research_progress=research.saved_progress or 0;return true
              end
              return value
            end
            local player=force("player",1)
            local game={tick=0,forces={player=player,[1]=player},surfaces={[1]={}}}
            game.surfaces[1].create_entity=function(request)
              local result={valid=true,force=request.force,contents=inventory(),energy_writes=0}
              local native_energy=0
              setmetatable(result,{__index=function(_,key)
                if key=="energy" then return native_energy end
                return rawget(result,key)
              end,__newindex=function(_,key,value)
                if key=="energy" then native_energy=value;result.energy_writes=result.energy_writes+1
                else rawset(result,key,value) end
              end})
              function result.get_inventory(kind) return result.contents end
              return result
            end
            function game.create_force(name)
              local result=force(name,2);game.forces[name]=result;game.forces[2]=result;return result
            end
            function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local env={game=game,storage=storage,settings={startup={
              ["ips-max-level-research_gears"]={value=2},["ips-effect-per-level-research_gears"]={value=10}}},
              helpers={table_to_json=function(row)markers[#markers+1]=row;return "{}" end},
              log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))end,
              script={active_mods={base="2.0.77",["more-infinite-research"]="4.0.20000",
                  ["mir-fixture-mir5-legacy-boolean-cap"]="0.1.0"},
                on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
                on_event=function(event,fn)callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=_G})
            local chunk,message=loadfile(fixture_source_control_path,"t",env);assert(chunk,message);chunk()
            local function invoke(callback,argument) local ok,message=pcall(callback,argument);return ok,tostring(message) end
            local function tick() game.tick=game.tick+1;return invoke(callbacks.events[2]) end
            local ok,message=invoke(callbacks.init);if not ok then return {ok=false,message=message} end
            local state=storage.mir5_legacy_boolean_cap;local gear=player.technologies["recipe-prod-research_gears-1"]
            -- These two assignments and inventory decrements model exactly the native
            -- laboratory completions asserted by the fixture; the fixture remains the
            -- only code that observes and records the capped state.
            player.current_research=nil;player.research_queue={};gear.level=2;player.recipes["iron-gear-wheel"].productivity_bonus=.10
            for _,name in ipairs(science) do state.lab.contents.counts[name]=state.lab.contents.counts[name]-1 end
            ok,message=invoke(callbacks.events[1],{research=gear});if not ok then return {ok=false,message=message} end
            local after_first_energy,after_first_writes=state.lab.energy,state.lab.energy_writes
            ok,message=tick();if not ok then return {ok=false,message=message} end
            player.current_research=nil;player.research_queue={};gear.level=3;player.recipes["iron-gear-wheel"].productivity_bonus=.20
            if not keep_enabled then gear.enabled=false end
            for _,name in ipairs(science) do state.lab.contents.counts[name]=state.lab.contents.counts[name]-1 end
            ok,message=invoke(callbacks.events[1],{research=gear});if not ok then return {ok=false,message=message} end
            local after_second_energy,after_second_writes=state.lab.energy,state.lab.energy_writes
            if keep_enabled then game.tick=state.deadline_tick+1 else game.tick=game.tick+1 end
            ok,message=invoke(callbacks.events[2]);if not ok then return {ok=false,message=message} end
            local before_reload={phase=state.phase,labs=state.actual_lab_completions,milestone=state.milestone,
              cap=state.player_cap and state.player_cap.level,energy=state.lab.energy,energy_writes=state.lab.energy_writes}
            for _=1,2 do
              ok,message=invoke(callbacks.load);if not ok then return {ok=false,message=message} end
              ok,message=tick();if not ok then return {ok=false,message=message} end
            end
            return {ok=true,saves=saves,markers=markers,state={actual_lab_completions=storage.mir5_legacy_boolean_cap.actual_lab_completions,
                milestone=storage.mir5_legacy_boolean_cap.milestone,player_cap=storage.mir5_legacy_boolean_cap.player_cap},
              player={level=gear.level,enabled=gear.enabled,visible=gear.visible_when_disabled,
                progress=gear.saved_progress,bonus=player.recipes["iron-gear-wheel"].productivity_bonus},
              lab={after_first_energy=after_first_energy,after_first_writes=after_first_writes,
                after_second_energy=after_second_energy,after_second_writes=after_second_writes,
                reload_energy=state.lab.energy,reload_energy_writes=state.lab.energy_writes,
                reload_storage_unchanged=before_reload.phase==state.phase and before_reload.labs==state.actual_lab_completions
                  and before_reload.milestone==state.milestone and before_reload.cap==state.player_cap.level
                  and before_reload.energy==state.lab.energy and before_reload.energy_writes==state.lab.energy_writes},
              foreign={level=game.forces[2].technologies["recipe-prod-research_gears-1"].level,
                enabled=game.forces[2].technologies["recipe-prod-research_gears-1"].enabled,
                visible_when_disabled=game.forces[2].technologies["recipe-prod-research_gears-1"].visible_when_disabled}}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_source_flow")(keep_enabled))

    def successor_flow(self, target_name, science_consumption="expected"):
        self.lua.globals().fixture_successor_body_path = SUCCESSOR_BODY.as_posix()
        self.lua.globals().fixture_successor_wrapper_path = ((F200 if target_name == "f200" else F210) / "control.lua").as_posix()
        self.lua.execute(r'''
          function legacy_boolean_cap_successor_flow(target_name,science_consumption)
            local callbacks,markers,saves={events={}},{},0
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
            local function inventory()
              local value={counts={},by_name={},slots={},slot_count=0}
              local function stack_for(name)
                local stack=value.by_name[name]
                if stack==nil then
                  value.slot_count=value.slot_count+1
                  stack={valid_for_read=true,name=name,type=target_name=="f200" and "tool" or "item",count=0,durability=1}
                  value.by_name[name]=stack;value.slots[value.slot_count]=stack
                end
                return stack
              end
              function value.insert(request)
                local stack=stack_for(request.name)
                value.counts[request.name]=(value.counts[request.name] or 0)+request.count
                stack.count=stack.count+request.count
                return request.count
              end
              function value.get_item_count(name) return value.counts[name] or 0 end
              return setmetatable(value,{__len=function(self) return self.slot_count end,
                __index=function(self,key)
                  if type(key)=="number" then return self.slots[key] end
                  return rawget(self,key)
                end})
            end
            local function lab(force)
              local value={valid=true,force=force,contents=inventory(),energy_writes=0}
              local native_energy=0
              setmetatable(value,{__index=function(_,key)
                if key=="energy" then return native_energy end
                return rawget(value,key)
              end,__newindex=function(_,key,next)
                if key=="energy" then native_energy=next;value.energy_writes=value.energy_writes+1
                else rawset(value,key,next) end
              end})
              function value.get_inventory(kind) return value.contents end
              return value
            end
            local function technology(name,force)
              return {name=name,force=force,valid=true,level=1,researched=false,enabled=true,visible_when_disabled=true,
                saved_progress=0,prerequisites={},prototype={max_level=4294967295},research_unit_count=1,research_unit_energy=60}
            end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={ ["iron-gear-wheel"]={productivity_bonus=0}},
                research_queue={},research_progress=0}
              local gear=technology("recipe-prod-research_gears-1",value)
              value.technologies[gear.name]=gear
              value.technologies["braking-force-1"]=technology("braking-force-1",value)
              function value.add_research(research)
                if research==nil or value.current_research~=nil then return false end
                value.current_research=research;value.research_queue={research};value.research_progress=research.saved_progress or 0;return true
              end
              return value
            end
            local player,foreign=force("player",1),force("mir5-legacy-boolean-cap-foreign",2)
            foreign.technologies["recipe-prod-research_gears-1"].enabled=false
            foreign.technologies["recipe-prod-research_gears-1"].visible_when_disabled=false
            foreign.current_research=foreign.technologies["braking-force-1"]
            foreign.research_queue={foreign.current_research};foreign.research_progress=.42
            local gear=player.technologies["recipe-prod-research_gears-1"]
            gear.level=3;gear.saved_progress=.27;player.recipes["iron-gear-wheel"].productivity_bonus=.20
            local source_lab=lab(player)
            for _,name in ipairs(science) do source_lab.contents.insert{name=name,count=14} end
            local state={phase="completed",source_mir="4.0.20000",actual_lab_completions=2,milestone="actual2labs",
              player_cap={level=3,researched=false,enabled=true,visible=true,maximum=4294967295,bonus=.20,saved_progress=.27},
              foreign_force_index=foreign.index,foreign_queue={current="braking-force-1",queue={"braking-force-1"},progress=.42},lab=source_lab}
            local game={tick=0,forces={player=player,[1]=player,[2]=foreign,[foreign.name]=foreign}}
            function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
            local expected=target_name=="f200" and {base="2.0.77",mir="5.0.20000",fixture="0.2.0"}
              or {base="2.1.23",mir="5.0.21000",fixture="0.3.0"}
            local storage={mir5_legacy_boolean_cap=state}
            local env={game=game,storage=storage,settings={startup={
              ["ips-max-level-research_gears"]={value=0},["ips-effect-per-level-research_gears"]={value=10}}},
              helpers={table_to_json=function(row)markers[#markers+1]=row;return "{}" end},
              log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "))end,
              script={active_mods={base=expected.base,["more-infinite-research"]=expected.mir,
                ["mir-fixture-mir5-legacy-boolean-cap"]=expected.fixture},
                on_load=function(fn)callbacks.load=fn end,on_configuration_changed=function(fn)callbacks.configuration=fn end,
                on_event=function(event,fn)callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=_G})
            local module
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-legacy-boolean-cap__/fixture_control")
              if module==nil then local chunk,message=loadfile(fixture_successor_body_path,"t",env);assert(chunk,message);module=chunk() end
              return module
            end
            local chunk,message=loadfile(fixture_successor_wrapper_path,"t",env);assert(chunk,message);chunk()
            local function invoke(callback,argument) local ok,message=pcall(callback,argument);return ok,tostring(message) end
            local function tick() game.tick=game.tick+1;return invoke(callbacks.events[2]) end
            local ok,message=invoke(callbacks.configuration);if not ok then return {ok=false,message=message} end
            local after_configuration_energy,after_configuration_writes=state.lab.energy,state.lab.energy_writes
            ok,message=invoke(callbacks.events[1],{research=foreign.technologies["recipe-prod-research_gears-1"]});if not ok then return {ok=false,message=message} end
            local after_foreign_energy,after_foreign_labs=state.lab.energy,state.destination_lab_completions
            player.current_research=nil;player.research_queue={};gear.level=4;player.recipes["iron-gear-wheel"].productivity_bonus=.30
            for _,name in ipairs(science) do
              local stack=state.lab.contents.by_name[name]
              if target_name=="f200" then
                if science_consumption=="expected" then stack.durability=.27
                elseif science_consumption=="none" then stack.durability=1
                elseif science_consumption=="excess" then stack.durability=.1
                elseif science_consumption=="malformed-type" then stack.type="item"
                elseif science_consumption=="malformed-durability" then stack.durability=0
                else error("unknown science consumption model: "..tostring(science_consumption)) end
              else
                state.lab.contents.counts[name]=state.lab.contents.counts[name]-1
                stack.count=stack.count-1
              end
            end
            ok,message=invoke(callbacks.events[1],{research=gear});if not ok then return {ok=false,message=message} end
            local after_finish_energy,after_finish_writes=state.lab.energy,state.lab.energy_writes
            local after_finish_counts={};for _,name in ipairs(science) do after_finish_counts[name]=state.lab.contents.counts[name] end
            local after_finish_tools={};for _,name in ipairs(science) do
              local stack=state.lab.contents.by_name[name]
              after_finish_tools[name]={count=stack.count,durability=stack.durability,type=stack.type}
            end
            ok,message=tick();if not ok then return {ok=false,message=message} end
            local before_reload={phase=state.phase,labs=state.destination_lab_completions,player=state.successor_player and state.successor_player.level,
              energy=state.lab.energy,writes=state.lab.energy_writes,counts={}}
            for _,name in ipairs(science) do before_reload.counts[name]=state.lab.contents.counts[name] end
            for _=1,2 do
              ok,message=invoke(callbacks.load);if not ok then return {ok=false,message=message} end
              ok,message=tick();if not ok then return {ok=false,message=message} end
            end
            local storage_unchanged=before_reload.phase==state.phase and before_reload.labs==state.destination_lab_completions
              and before_reload.player==state.successor_player.level and before_reload.energy==state.lab.energy
              and before_reload.writes==state.lab.energy_writes
            for _,name in ipairs(science) do storage_unchanged=storage_unchanged and before_reload.counts[name]==state.lab.contents.counts[name] end
            return {ok=true,saves=saves,markers=markers,lab={configuration_energy=after_configuration_energy,
              configuration_writes=after_configuration_writes,foreign_energy=after_foreign_energy,foreign_labs=after_foreign_labs,
              after_finish_energy=after_finish_energy,after_finish_writes=after_finish_writes,after_finish_counts=after_finish_counts,
              after_finish_tools=after_finish_tools,
              reload_energy=state.lab.energy,reload_energy_writes=state.lab.energy_writes,reload_storage_unchanged=storage_unchanged},
              state={phase=state.phase,labs=state.destination_lab_completions,player=state.successor_player,
                tool_remaining=state.destination_science_remaining}}
          end
        ''')
        return py(self.lua.eval("legacy_boolean_cap_successor_flow")(target_name, science_consumption))

    def test_data_preflights_pin_the_independent_published_and_successor_row_before_acceleration(self):
        stages = (
            (SOURCE / "data-final-fixes.lua", {"base": "2.0.77", "more-infinite-research": "4.0.20000",
                                                 "mir-fixture-mir5-legacy-boolean-cap": "0.1.0"}, False),
            (F200 / "data-final-fixes.lua", {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}, True),
            (F210 / "data-final-fixes.lua", {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.3.0"}, False),
        )
        for path, mods, tool_science in stages:
            with self.subTest(path=path):
                raw = self.raw(tool_science)
                accepted = self.run_data(path, raw, mods)
                self.assertTrue(accepted["ok"], accepted["message"])
                unit = accepted["raw"]["technology"][GEAR]["unit"]
                self.assertEqual((1, None, 1), (unit["count"], unit.get("count_formula"), unit["time"]))
                self.assertEqual(SCIENCE, unit["ingredients"])
                self.assertEqual(17, accepted["raw"]["sentinel"]["unchanged"])

                for label, mutate in (
                    ("formula", lambda row: row["unit"].update({"count_formula": "8001*2^(L-1)"})),
                    ("science", lambda row: row["unit"]["ingredients"].__setitem__(0, ["foreign-science-pack", 1])),
                    ("effect", lambda row: row["effects"][0].update({"change": .01})),
                ):
                    candidate = self.raw(tool_science)
                    mutate(candidate["technology"][GEAR])
                    before = copy.deepcopy(candidate)
                    rejected = self.run_data(path, candidate, mods)
                    self.assertFalse(rejected["ok"], (label, rejected["message"]))
                    self.assertEqual(before, rejected["raw"])

        f200_mods = {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                     "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}
        for label, mutate in (
            ("missing-tool", lambda raw: raw.pop("tool")),
            ("plain-item", lambda raw: raw["tool"][SCIENCE[0][0]].update({"type": "item"})),
            ("wrong-durability", lambda raw: raw["tool"][SCIENCE[0][0]].update({"durability": .5})),
        ):
            with self.subTest(tool_guard=label):
                candidate = self.raw(True)
                mutate(candidate)
                before = copy.deepcopy(candidate)
                rejected = self.run_data(F200 / "data-final-fixes.lua", candidate, f200_mods)
                self.assertFalse(rejected["ok"], rejected["message"])
                self.assertEqual(before, rejected["raw"])

    def test_settings_stages_select_only_the_historical_source_cap(self):
        source_mods = {"base": "2.0.77", "more-infinite-research": "4.0.20000",
                       "mir-fixture-mir5-legacy-boolean-cap": "0.1.0"}
        source = self.run_settings(SOURCE / "settings-updates.lua", source_mods)
        self.assertTrue(source["ok"], source["message"])
        self.assertEqual((2, 10), (source["cap"]["default_value"], source["effect"]["default_value"]))
        for path, mods in (
            (F200 / "settings-updates.lua", {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}),
            (F210 / "settings-updates.lua", {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                                               "mir-fixture-mir5-legacy-boolean-cap": "0.3.0"}),
        ):
            with self.subTest(path=path):
                result = self.run_settings(path, mods)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((0, 10), (result["cap"]["default_value"], result["effect"]["default_value"]))

    def test_controls_register_only_the_required_source_or_successor_callbacks(self):
        source = self.parse_control(SOURCE / "control.lua", {"base": "2.0.77", "more-infinite-research": "4.0.20000",
                                                                "mir-fixture-mir5-legacy-boolean-cap": "0.1.0"})
        self.assertTrue(source["ok"], source["message"])
        self.assertIsNotNone(source["callbacks"]["init"])
        self.assertIsNotNone(source["callbacks"]["load"])
        self.assertIsNone(source["callbacks"].get("configuration"))
        self.assertEqual({}, source["forbidden"])
        for path, mods in (
            (F200 / "control.lua", {"base": "2.0.77", "more-infinite-research": "5.0.20000",
                                      "mir-fixture-mir5-legacy-boolean-cap": "0.2.0"}),
            (F210 / "control.lua", {"base": "2.1.23", "more-infinite-research": "5.0.21000",
                                      "mir-fixture-mir5-legacy-boolean-cap": "0.3.0"}),
        ):
            with self.subTest(path=path):
                result = self.parse_control(path, mods)
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNotNone(result["callbacks"]["configuration"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertEqual({}, result["forbidden"])

    def test_published_archive_provenance_and_prepared_profiles_bind_the_reviewed_candidate_packages(self):
        metadata = json.loads((ROOT / "spec/evidence/historical-boolean-cap-archive-metadata.json").read_text(encoding="utf-8"))
        observed = next(row for row in metadata["observations"] if row["info_json"]["version"] == "4.0.20000")
        self.assertEqual((1067014, ARCHIVE_SHA256, POLICY_SHA256,
                          "09eb",
                          "67c3f06c0af3de8193548e1716e7aba8d5380135"),
                         (observed["archive"]["observed_bytes"], observed["archive"]["observed_sha256"],
                          observed["maximum_level_control"]["raw_sha256"],
                          observed["maximum_level_control"]["matched_git_body"],
                          observed["maximum_level_control"]["tag_source_git_blob"]))
        source = json.loads(SOURCE_PROFILE.read_text(encoding="utf-8"))
        self.assertEqual({"more-infinite-research_4.0.20000.zip": ARCHIVE_SHA256,
                          "mir-fixture-mir5-legacy-boolean-cap_0.1.0.zip":
                              "A33E86829C63B995228E79CEA7421E669A4D2C5F7F76BDAF8F2D7F2B742F4C3D"},
                         source["archive_sha256"])
        self.assertEqual(("4.0.0", "09eb6ece484c8e3c1bcdafaea31451ce84a27108"),
                         (source["origin_tag"], source["origin_archive_body"]))
        for profile_path, target, mir, fixture, archive, digest, size, fixture_digest in (
            (F200_PROFILE, "f200", "5.0.20000", "0.2.0", "more-infinite-research_5.0.20000.zip",
             "8DB28D2DE45F26033B5F54E176902A3138A903AF0F4B48EAB6B9971466021B4F", 680963,
             "0504A2AC4BA0BC6985EF5AFB24AC72CA9B62DF9B02090663AA1AA5A9DC5B0EED"),
            (F210_PROFILE, "f210", "5.0.21000", "0.3.0", "more-infinite-research_5.0.21000.zip",
             "7CE6A4DF78019F6B98237E638A1C927C5FDB538D4A1442EE22D846DD962DDCDC", 681347,
             "D1BDF52D254F6C1DE051117293D9F731295BFC8E3C1909DFFA8F2DA15413F876"),
        ):
            profile = json.loads(profile_path.read_text(encoding="utf-8"))
            with self.subTest(profile=profile_path.name):
                self.assertEqual({archive: digest, f"mir-fixture-mir5-legacy-boolean-cap_{fixture}.zip": fixture_digest},
                                 profile["archive_sha256"])
                self.assertEqual(("a575a4198807b6aea9e26963e3d9970fc5c068ae",
                                  "398c79c687d2bc662c976355ced1436201c43f11", size),
                                 (profile["candidate_binding"]["source_commit"],
                                  profile["candidate_binding"]["player_tree"],
                                  profile["candidate_binding"]["bytes"]))
                self.assertEqual((target, mir, fixture),
                                 (profile["target"], next(row["version"] for row in profile["mods"]
                                                           if row["name"] == "more-infinite-research"),
                                  next(row["version"] for row in profile["mods"]
                                       if row["name"] == "mir-fixture-mir5-legacy-boolean-cap")))

    def test_source_proves_native_transition_without_cross_mod_storage_access_and_successors_remain_distinct(self):
        source = (SOURCE / "control.lua").read_text(encoding="utf-8")
        self.assertNotIn("storage.mir", source)
        self.assertNotIn("maximum_level_control", source)
        self.assertIn("player.enabled == false and player.visible == true", source)
        self.assertIn("foreign_gear.enabled = false", source)
        self.assertIn("foreign_gear.visible_when_disabled = false", source)
        self.assertIn("actual_lab_completions ~= 2", source)
        self.assertIn("game.server_save(SAVE)", source)
        self.assertIn('marker("reload", state)', source)
        body = SUCCESSOR_BODY.read_text(encoding="utf-8")
        self.assertIn("F200 restored player", body)
        self.assertIn("F210 direct restored player", body)
        self.assertIn("direct successor carries Space Age companions", body)
        self.assertIn("foreign gear", body)
        self.assertIn("destination_lab_completions ~= 1", body)
        self.assertIn("game.server_save(SAVE)", body)
        self.assertIn('marker("reload", state)', body)
        self.assertIn("return {apply = apply}", body)
        self.assertEqual('require("__mir-fixture-mir5-legacy-boolean-cap__/fixture_control").apply("f200")\n',
                         (F200 / "control.lua").read_text(encoding="utf-8"))
        self.assertEqual('require("__mir-fixture-mir5-legacy-boolean-cap__/fixture_control").apply("f210")\n',
                         (F210 / "control.lua").read_text(encoding="utf-8"))

    def test_owned_fixture_projections_bind_the_shared_successor_body_and_exact_archive_members(self):
        receipt = json.loads(PREPARED_INPUT_RECEIPT.read_text(encoding="utf-8"))
        fixtures_by_stage = {fixture["stage"]: fixture for fixture in receipt["fixture_archives"]}
        stages = (
            ("published-source", "0.1.0", SOURCE_PROFILE),
            ("f200-successor", "0.2.0", F200_PROFILE),
            ("f210-direct-successor", "0.3.0", F210_PROFILE),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for stage, version, profile_path in stages:
                with self.subTest(version=version):
                    fixture = fixtures_by_stage[stage]
                    self.assertEqual(version, fixture["version"])
                    expected = {member["path"]: (member["sha256"], member["bytes"])
                                for member in fixture["members"]}
                    projection = root / version
                    projection.mkdir()
                    for member in fixture["members"]:
                        raw = raw_git_bytes(receipt["fixture_source_commit"], member["source_path"])
                        self.assertEqual((member["sha256"], member["bytes"]),
                                         (hashlib.sha256(raw).hexdigest().upper(), len(raw)))
                        destination = projection / member["path"]
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_bytes(raw)
                    archive = root / f"{NAME}_{version}.zip"
                    record = PACKAGE.build(projection, archive)
                    observed = {row["path"]: (row["sha256"].upper(), row["bytes"]) for row in record["members"]}
                    self.assertIsNone(record["source_commit"])
                    self.assertEqual(expected, observed)
                    self.assertEqual(record["sha256"].upper(), hashlib.sha256(archive.read_bytes()).hexdigest().upper())
                    self.assertEqual(record["sha256"].upper(),
                                     json.loads(profile_path.read_text(encoding="utf-8"))["archive_sha256"]
                                     [f"{NAME}_{version}.zip"])
                    with zipfile.ZipFile(archive) as package:
                        self.assertEqual({f"{NAME}_{version}/{name}" for name in expected},
                                         {entry.filename for entry in package.infolist() if not entry.is_dir()})

            # A checkout that rewrites even one raw member to CRLF cannot
            # satisfy the frozen archive receipt.  This is the old projection
            # failure, expressed without depending on the runner's Git EOL
            # setting.
            source_fixture = fixtures_by_stage["published-source"]
            altered = root / "crlf"
            altered.mkdir()
            for member in source_fixture["members"]:
                raw = raw_git_bytes(receipt["fixture_source_commit"], member["source_path"])
                if member["path"] == "control.lua":
                    raw = raw.replace(b"\n", b"\r\n")
                (altered / member["path"]).write_bytes(raw)
            crlf_archive = altered / f"{NAME}_0.1.0.zip"
            crlf_record = PACKAGE.build(altered, crlf_archive)
            crlf_members = {row["path"]: (row["sha256"].upper(), row["bytes"])
                            for row in crlf_record["members"]}
            expected_source_members = {member["path"]: (member["sha256"], member["bytes"])
                                       for member in source_fixture["members"]}
            self.assertNotEqual(expected_source_members, crlf_members)

    def test_prepared_input_receipt_binds_only_the_owned_projections_and_current_candidate(self):
        receipt = json.loads(PREPARED_INPUT_RECEIPT.read_text(encoding="utf-8"))
        self.assertEqual(("MIR5LegacyBooleanCapPreparedInputsV1",
                          "exact-fixtures-built-not-native-qualified", False, False, False, False),
                         (receipt["kind"], receipt["status"], receipt["native_execution"],
                          receipt["library_mutation"], receipt["laboratory_completion"],
                          receipt["release_qualification"]))
        self.assertEqual(("9ef64ff41e0c7140467df044dfe20837f1fa5a40",
                          "efbe89b4f48542c04af298ecc9fd6b92119bd5ae"),
                         (receipt["fixture_source_commit"], receipt["fixture_source_tree"]))
        profile_by_path = {row["path"]: row for row in receipt["profiles"]}
        for path in (SOURCE_PROFILE, F200_PROFILE, F210_PROFILE):
            with self.subTest(profile=path.name):
                expected = profile_by_path[str(path.relative_to(ROOT)).replace("\\", "/")]
                self.assertEqual((expected["bytes"], expected["sha256"]),
                                 (path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest().upper()))
        expected_versions = {"published-source": "0.1.0", "f200-successor": "0.2.0",
                             "f210-direct-successor": "0.3.0"}
        for fixture in receipt["fixture_archives"]:
            with self.subTest(stage=fixture["stage"]):
                self.assertEqual(expected_versions[fixture["stage"]], fixture["version"])
                self.assertEqual("build/qualification/legacy-boolean-cap-a575-prepared-inputs-r01",
                                 fixture["archive"].rsplit("/", 1)[0])
                expected_members = {row["path"]: (row["sha256"], row["bytes"])
                                    for row in fixture["members"]}
                actual_members = {}
                for row in fixture["members"]:
                    raw = raw_git_bytes(receipt["fixture_source_commit"], row["source_path"])
                    actual_members[row["path"]] = (hashlib.sha256(raw).hexdigest().upper(), len(raw))
                self.assertEqual(expected_members, actual_members)
                if fixture["stage"] != "published-source":
                    self.assertIn("fixture_control.lua", expected_members)
        candidate = receipt["inputs"]["current_candidate"]
        self.assertEqual(("a575a4198807b6aea9e26963e3d9970fc5c068ae",
                          "398c79c687d2bc662c976355ced1436201c43f11"),
                         (candidate["source_commit"], candidate["player_tree"]))
        self.assertEqual(("8DB28D2DE45F26033B5F54E176902A3138A903AF0F4B48EAB6B9971466021B4F", 680963),
                         (candidate["f200"]["sha256"], candidate["f200"]["bytes"]))
        self.assertEqual(("7CE6A4DF78019F6B98237E638A1C927C5FDB538D4A1442EE22D846DD962DDCDC", 681347),
                         (candidate["f210"]["sha256"], candidate["f210"]["bytes"]))

    def test_native_shaped_source_model_requires_the_observed_cap_disablement_before_the_protected_save(self):
        passed = self.source_flow()
        self.assertTrue(passed["ok"], passed.get("message"))
        self.assertEqual(1, passed["saves"])
        self.assertEqual(["initial", "reload", "reload"], [row["stage"] for row in passed["markers"]])
        self.assertEqual((3, False, True, .27, .20),
                         (passed["player"]["level"], passed["player"]["enabled"], passed["player"]["visible"],
                          passed["player"]["progress"], passed["player"]["bonus"]))
        self.assertEqual((1, False, False),
                         (passed["foreign"]["level"], passed["foreign"]["enabled"],
                          passed["foreign"]["visible_when_disabled"]))
        self.assertEqual((2, "actual2labs", .27),
                         (passed["state"]["actual_lab_completions"], passed["state"]["milestone"],
                          passed["state"]["player_cap"]["saved_progress"]))
        self.assertGreater(passed["lab"]["after_first_energy"], 0)
        self.assertEqual(0, passed["lab"]["after_second_energy"])
        self.assertGreater(passed["lab"]["after_second_writes"], passed["lab"]["after_first_writes"])
        self.assertEqual(0, passed["lab"]["reload_energy"])
        self.assertTrue(passed["lab"]["reload_storage_unchanged"])

        refused = self.source_flow(keep_enabled=True)
        self.assertFalse(refused["ok"])
        self.assertIn("source labs did not complete", refused["message"])

    def test_successor_freezes_the_live_lab_once_and_cold_reloads_are_native_and_storage_read_only(self):
        for target in ("f200", "f210"):
            with self.subTest(target=target):
                passed = self.successor_flow(target)
                self.assertTrue(passed["ok"], passed.get("message"))
                self.assertEqual(1, passed["saves"])
                self.assertEqual(["initial", "reload", "reload"], [row["stage"] for row in passed["markers"]])
                self.assertGreater(passed["lab"]["configuration_energy"], 0)
                self.assertEqual((passed["lab"]["configuration_energy"], 0),
                                 (passed["lab"]["foreign_energy"], passed["lab"]["foreign_labs"]))
                self.assertEqual(0, passed["lab"]["after_finish_energy"])
                self.assertGreater(passed["lab"]["after_finish_writes"], passed["lab"]["configuration_writes"])
                expected_count = 22 if target == "f200" else 21
                self.assertEqual({name: expected_count for name, _ in SCIENCE}, passed["lab"]["after_finish_counts"])
                if target == "f200":
                    self.assertAlmostEqual(.73, passed["state"]["tool_remaining"])
                    self.assertEqual({name: {"count": 22, "durability": .27, "type": "tool"}
                                      for name, _ in SCIENCE}, passed["lab"]["after_finish_tools"])
                self.assertEqual(0, passed["lab"]["reload_energy"])
                self.assertTrue(passed["lab"]["reload_storage_unchanged"])
                self.assertEqual(("completed", 1, 4),
                                 (passed["state"]["phase"], passed["state"]["labs"], passed["state"]["player"]["level"]))

    def test_f200_tool_science_observation_requires_exact_remaining_unit_consumption(self):
        passed = self.successor_flow("f200")
        self.assertTrue(passed["ok"], passed.get("message"))
        self.assertAlmostEqual(.73, passed["state"]["tool_remaining"])
        for name, _ in SCIENCE:
            with self.subTest(name=name):
                stack = passed["lab"]["after_finish_tools"][name]
                self.assertEqual((22, "tool"), (stack["count"], stack["type"]))
                self.assertAlmostEqual(.27, stack["durability"])

        for model, expected in (
            ("none", "F200 successor tool science consumption differs"),
            ("excess", "F200 successor tool science consumption differs"),
            ("malformed-type", "F200 science stack is not a tool"),
            ("malformed-durability", "F200 science tool durability is invalid"),
        ):
            with self.subTest(model=model):
                refused = self.successor_flow("f200", model)
                self.assertFalse(refused["ok"])
                self.assertIn(expected, refused["message"])
                if model == "none":
                    for field in ("before-units=", "after-units=", "expected-delta=", "actual-delta=",
                                  "observed-lab-progress="):
                        self.assertIn(field, refused["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    LegacyBooleanCapFixtureTests.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyBooleanCapFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
