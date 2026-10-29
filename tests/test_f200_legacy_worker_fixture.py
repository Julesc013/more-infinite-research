"""Host controls for the F200 source and F200/F210 native-worker successors.

These bounded mocks execute the fixture controls and immutable F200 row preflight.
They do not replace the required published-to-MIR5 native save qualification.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/f200-legacy-worker"
SUCCESSOR_ROLE = "successor"
PUBLISHED_PROFILE = ROOT / "tests/profiles/f200-legacy-worker-published-4.7-2077.json"
MIR5_PROFILE = ROOT / "tests/profiles/f200-legacy-worker-mir5-2077.json"
NAME = "mir-fixture-mir5-f200-legacy-worker"
WORKER = "worker-robots-speed-6"
SCIENCE = ("automation-science-pack", "logistic-science-pack", "chemical-science-pack",
           "production-science-pack", "utility-science-pack", "space-science-pack")
ROW = {
    "type": "technology", "name": WORKER, "upgrade": True, "max_level": "infinite",
    "prerequisites": ["worker-robots-speed-5", "space-science-pack"],
    "unit": {"count_formula": "2^(L-6)*1000", "time": 60,
             "ingredients": [[name, 1] for name in SCIENCE]},
    "effects": [{"type": "worker-robot-speed", "modifier": .65}],
}


def fixture_role(stage):
    return SUCCESSOR_ROLE if stage == "mir5" else stage


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


class F200LegacyWorkerFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function worker_data(path, mir, row, f210, fixture)
            local env={mods={base=f210 and "2.1.23" or "2.0.77",["more-infinite-research"]=mir,
              ["mir-fixture-mir5-f200-legacy-worker"]=fixture or (f210 and "0.4.0" or nil),
              ["a-mir-fixture-worker-entry"]=f210 and "0.1.0" or nil},data={raw={technology={[row.name]=row}}}}
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),row=row}
          end

          function worker_parse(path, mir, fixture, owner_root, base)
            local callbacks,reads={events={}},{ }
            local env={script={active_mods={base=base or "2.0.77",["more-infinite-research"]=mir,
              ["mir-fixture-mir5-f200-legacy-worker"]=fixture},on_init=function(f)callbacks.init=f end,
              on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,
              on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            if owner_root then
              env.require=function(name)
                local relative=name=="fixture_control" and "/../successor/control.lua"
                  or name=="offset-owner" and "/../persisted-offset-owner/offset-owner.lua"
                assert(relative);return assert(loadfile(owner_root..relative,"t",env))()
              end
            end
            env._G=env;setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then reads[key]=(reads[key]or 0)+1 end
              return _G[key]
            end})
            local chunk,message=loadfile(path,"t",env);assert(chunk,message)
            local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end

          function worker_flow(source_path, destination_path, opponent, owner_root, startup_facade, f210, finite)
            local callbacks,markers,diagnostics,saves={events={}},0,0,0
            local science_type,item_durability_reads="tool",0
            local held_role=f210 and "0.7.0"or"0.5.0"
            local relax_role=f210 and "0.8.0"or"0.6.0"
            local hold_result
            local WORKER="worker-robots-speed-6"
            local science={"automation-science-pack","logistic-science-pack","chemical-science-pack",
              "production-science-pack","utility-science-pack","space-science-pack"}
            local function inventory()
              local value={items={},slots={},slot_by_name={}}
              local function stack(name)
                local current=value.slot_by_name[name]
                if current==nil then
                  current=setmetatable({valid_for_read=true,name=name,count=0,quality={name="normal"},durability=1},
                    {__index=function(_,key)
                      if key=="type"then return science_type end
                      if key=="is_tool"then return science_type=="tool" end
                      if key=="durability"and science_type=="item"then
                        item_durability_reads=item_durability_reads+1;error("ordinary item durability read")
                      end
                    end})
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
                local current=stack(name);assert(current.count>=1)
                if science_type=="item"then
                  assert(amount>=0 and amount%1==0);current.count=current.count-amount
                  value.items[name]=current.count;return
                end
                assert(current.durability>0)
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
              item_prototypes[name]=setmetatable({},{__index=function(_,key)
                if key=="type"then return science_type end
                if key=="get_durability"then
                  if science_type=="item"then item_durability_reads=item_durability_reads+1;error("ordinary item durability API read")end
                  return function(quality)assert(quality and quality.name=="normal");return 1 end
                end
              end})
            end
            local input=inventory();local modules=setmetatable({},{__len=function()return 0 end})
            local lab={valid=true,energy=0,quality={name="normal"},prototype={get_researching_speed=function(quality)
              assert(quality and quality.name=="normal");return 1
            end}}
            function lab.get_inventory(index)assert(index==1);return input end
            function lab.get_module_inventory()return modules end
            local function prereq(name)return {name=name,research_recursive=function()end}end
            local function tech(name,force)
              local effect=name==WORKER and {{type="worker-robot-speed",modifier=.65}} or {}
              local prerequisites=name==WORKER and {['worker-robots-speed-5']=prereq('worker-robots-speed-5'),
                ['space-science-pack']=prereq('space-science-pack')} or {}
              local ingredients={};for _,science_name in ipairs(science)do ingredients[#ingredients+1]={name=science_name,amount=1}end
              return {name=name,valid=true,force=force,level=name==WORKER and 6 or 1,researched=false,
                enabled=true,visible_when_disabled=false,saved_progress=0,
                prototype={max_level=4294967295,effects=effect,visible_when_disabled=false},prerequisites=prerequisites,
                research_unit_count=1,research_unit_energy=60,research_unit_ingredients=ingredients}
            end
            local function force(name,index,modifier)
              local value={name=name,index=index,valid=true,technologies={},research_queue={},research_progress=0,
                worker_robots_speed_modifier=modifier,laboratory_speed_modifier=0,laboratory_productivity_bonus=0}
              value.technologies[WORKER]=tech(WORKER,value);value.technologies["braking-force-1"]=tech("braking-force-1",value)
              function value.enable_all_prototypes()end
              function value.add_research(research)
                if type(research)=="string"then research=value.technologies[research]end
                if research==nil or value.current_research~=nil then return false end
                local transferred=research.saved_progress or 0
                if opponent=="lost-investment" and value.name=="player" and transferred>0 then transferred=.26 end
                value.current_research=research;value.research_queue={research};value.research_progress=transferred;research.saved_progress=0;return true
              end
              return value
            end
            local player,foreign=force("player",1,owner_root and 2.4 or 1.25),nil
            local game={tick=0,speed=1,forces={player=player,[1]=player},surfaces={}}
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
            function game.create_force(name)
              foreign=force(name,2,owner_root and 2.4 or 2.5)
              -- Prototype presentation was patched globally by published F200 data final fixes.
              foreign.technologies[WORKER].prototype.visible_when_disabled=player.technologies[WORKER].prototype.visible_when_disabled
              game.forces[name]=foreign;game.forces[2]=foreign;return foreign
            end
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local function startup(cap)
              return {startup={["mir-max-level-worker-robots-speed"]={value=cap},["mir-settings-profile-import"]={value=""}}}
            end
            local entry
            local function load_control(path,mir,version,settings_values)
              if startup_facade and (version=="0.3.0"or version=="0.4.0")then settings_values.startup=startup_facade end
              local c={events={}}
              local env={script={active_mods={base=(version=="0.4.0"or version=="0.7.0"or version=="0.8.0")and"2.1.23"or"2.0.77",["more-infinite-research"]=mir,
                ["mir-fixture-mir5-f200-legacy-worker"]=version},on_init=function(f)c.init=f end,
                on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,
                on_event=function(e,f)c.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
                game=game,storage=storage,settings=settings_values,prototypes={item=item_prototypes},helpers={table_to_json=function(row)
                  if row.status=="passed" then assert(row.stage=="initial" or row.stage=="reload")
                  elseif row.stage=="fixture-owner-preflight"then
                    assert((row.maximum==40 or (finite and row.maximum==7)) and row.profile_import_empty==true)
                    assert(type(row.startup_type)=="string" and type(row.maximum_type)=="string")
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
              if owner_root then
                if version~="0.1.0"and version~="0.2.0"then env.script.active_mods["a-mir-fixture-worker-entry"]="0.1.0"end
                if version=="0.4.0"and opponent=="owner-wrong-mir"then env.script.active_mods["more-infinite-research"]="5.0.20000"end
                if version=="0.4.0"and opponent=="owner-wrong-engine"then env.script.active_mods.base="2.1.24"end
                env.remote={call=function(name,method)assert(name=="mir-fixture-worker-entry" and method=="get");return entry end}
                env.require=function(name)
                  local relative=name=="fixture_control" and "/../successor/control.lua" or name=="offset-owner" and "/../persisted-offset-owner/offset-owner.lua"
                  assert(relative,"unexpected private fixture import")
                  local import_root=finite and owner_root:gsub("/f%d+/first%-finite%-held$","/persisted-offset-owner")or owner_root
                  return assert(loadfile(import_root..relative,"t",env))()
                end
              end
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
              return ok and c or nil,tostring(result)
            end
            local function invoke(control,kind,event)
              local callback=kind=="tick" and control.events[1] or (kind=="finished" and control.events[2] or control[kind])
              if type(callback)~="function"then return false,"missing "..kind.." callback"end
              local ok,result=pcall(callback,event);return ok,tostring(result)
            end
            local function tick(control)game.tick=game.tick+1;return invoke(control,"tick")end
            local function complete(control,level,bonus,consumed_units)
              player.current_research=nil;player.research_queue={};player.research_progress=0;player.technologies[WORKER].level=level
              player.technologies[WORKER].researched=false;player.worker_robots_speed_modifier=bonus
              for _,science_name in ipairs(science)do input.consume(science_name,consumed_units or 1) end
              return invoke(control,"finished",{research=player.technologies[WORKER]})
            end
            local source,message=load_control(source_path,"4.7.20002","0.1.0",startup(7));if not source then return {ok=false,message=message}end
            -- Published MIR is a dependency, so its on_init cap presentation precedes fixture on_init.
            player.technologies[WORKER].prototype.visible_when_disabled=true
            player.technologies[WORKER].visible_when_disabled=true
            local ok,result=invoke(source,"init");if not ok then return {ok=false,message=result}end
            local state=storage.mir5_f200_legacy_worker
            ok,result=complete(source,7,state.player_with_independent+.65,1);if not ok then return {ok=false,message=result}end
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            ok,result=complete(source,8,state.player_with_independent+1.3,1);if not ok then return {ok=false,message=result}end
            -- Emulates the published cap controller, outside the fixture: the fixture only observes this player write.
            player.technologies[WORKER].enabled=true;player.technologies[WORKER].visible_when_disabled=true
            -- The second actual completion is followed by the published cap controller disabling it.
            player.technologies[WORKER].enabled=false;player.technologies[WORKER].visible_when_disabled=true
            ok,result=tick(source);if not ok then return {ok=false,message=result}end
            for _=1,2 do ok,result=invoke(source,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(source);if not ok then return {ok=false,message=result}end end
            if f210 then
              science_type="item"
              for _,stack in ipairs(input.slots)do rawset(stack,"durability",nil)end
            end
            local observed
            if owner_root then
              player.worker_robots_speed_modifier=state.player_cap.bonus-(opponent=="owner-retained" and 0 or .123)
              observed=function(f)
                local t=f.technologies[WORKER]
                return {index=f.index,name=f.name,level=t.level,researched=t.researched,enabled=t.enabled,
                  visible=t.visible_when_disabled,bonus=f.worker_robots_speed_modifier,saved_progress=t.saved_progress}
              end
              entry={schema=1,tick=game.tick,base=f210 and"2.1.23"or"2.0.77",mir=f210 and"5.0.21000"or"5.0.20000",fixture=finite and held_role or(f210 and"0.4.0"or"0.3.0"),observer="0.1.0",player=observed(player),foreign=observed(foreign)}
              if opponent=="owner-native-loss"then player.worker_robots_speed_modifier=player.worker_robots_speed_modifier-.01
              elseif opponent=="owner-stale"then entry.tick=entry.tick-1
              elseif opponent=="owner-unknown"then entry.player.bonus=entry.player.bonus-.01;player.worker_robots_speed_modifier=entry.player.bonus
              elseif opponent=="owner-unknown-ledger"then state.player_with_independent=state.player_with_independent+.001
              elseif opponent=="owner-missing-ledger"then state.player_with_independent=nil
              elseif opponent=="owner-repeated"then state.fixture_owned_offset={schema=1}
              elseif opponent=="owner-force"then entry.player.index=99
              elseif opponent=="owner-foreign-queue"then foreign.research_progress=.41
              elseif opponent=="owner-foreign-enable"then foreign.technologies[WORKER].enabled=true
              elseif opponent=="owner-effect"then player.technologies[WORKER].prototype.effects[1].modifier=.6 end
            end
            if opponent=="stale-enable"then player.technologies[WORKER].enabled=false
            elseif opponent=="native-level"then player.technologies[WORKER].level=7
            elseif opponent=="foreign-queue"then foreign.research_progress=.41
            elseif opponent=="saved-progress"then player.technologies[WORKER].saved_progress=.26
            elseif opponent=="speed-bonus"then player.worker_robots_speed_modifier=0
            elseif opponent=="lab-count"then state.actual_lab_completions=1 end
            -- The source state owns the published positive-cap presentation.
            -- The successor data-stage prototype independently returns to the
            -- Base default before its lifecycle restores the source value.
            if opponent~="stale-enable"then player.technologies[WORKER].enabled=not finite;player.technologies[WORKER].visible_when_disabled=true;player.technologies[WORKER].prototype.visible_when_disabled=false
            elseif finite then player.technologies[WORKER].enabled=true end
            local destination,message=load_control(destination_path,f210 and"5.0.21000"or"5.0.20000",finite and held_role or(f210 and"0.4.0"or(owner_root and"0.3.0"or"0.2.0")),startup(finite and 7 or 40));if not destination then return {ok=false,message=message}end
            -- Native upgrade loads the old fixture state before configuration_changed.
            ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end
            local before_owner=player.worker_robots_speed_modifier
            ok,result=invoke(destination,"changed");if not ok then return {ok=false,message=result,before_owner=before_owner,after_owner=player.worker_robots_speed_modifier}end
            if owner_root and opponent=="owner-duplicate-config"then
              local before_repeat=player.worker_robots_speed_modifier
              ok,result=invoke(destination,"changed")
              return {ok=ok,message=result,before_owner=before_repeat,after_owner=player.worker_robots_speed_modifier}
            end
            if finite then
              if opponent=="hold-duplicate-config"then
                before_owner=player.worker_robots_speed_modifier
                ok,result=invoke(destination,"changed")
                return {ok=ok,message=result,before_owner=before_owner,after_owner=player.worker_robots_speed_modifier}
              end
              ok,result=tick(destination);if not ok then return {ok=false,message=result}end
              if opponent=="hold-cold-enable"then player.technologies[WORKER].enabled=true end
              if opponent=="hold-cold-bonus"then player.worker_robots_speed_modifier=3.813 end
              if opponent=="hold-cold-science"then input.slots[1].count=input.slots[1].count+1 end
              for _=1,2 do
                before_owner=player.worker_robots_speed_modifier
                ok,result=invoke(destination,"load");if ok then ok,result=tick(destination)end
                if not ok then return {ok=false,message=result,before_owner=before_owner,after_owner=player.worker_robots_speed_modifier}end
              end
              hold_result={phase=state.phase,level=player.technologies[WORKER].level,
                enabled=player.technologies[WORKER].enabled,bonus=player.worker_robots_speed_modifier,
                source_labs=state.actual_lab_completions,destination_labs=state.destination_lab_completions,
                science=input.slots[1].count,saved_progress=player.technologies[WORKER].saved_progress,
                markers=markers,saves=saves}
              if opponent=="relax-missing-proof"then state.finite_hold_witness=nil end
              if opponent=="relax-bad-proof"then state.finite_hold_witness.maximum=8 end
              if opponent=="relax-bad-offset"then state.fixture_owned_offset.amount=.124 end
              if opponent=="relax-bad-phase"then state.phase="completed"end
              if opponent=="relax-held-science"then input.slots[1].count=input.slots[1].count+1 end
              -- Independent native reset and MIR cap relaxation; these writes
              -- are outside the fixture under test, as in the direct mock.
              player.worker_robots_speed_modifier=opponent=="owner-retained"and 3.823 or 3.7
              entry={schema=1,tick=game.tick,base=f210 and"2.1.23"or"2.0.77",
                mir=f210 and"5.0.21000"or"5.0.20000",fixture=relax_role,observer="0.1.0",
                player=observed(player),foreign=observed(foreign)}
              if opponent=="relax-stale-entry"then entry.tick=entry.tick-1 end
              if opponent=="relax-unknown-entry"then entry.player.bonus=3.69;player.worker_robots_speed_modifier=3.69 end
              player.technologies[WORKER].enabled=opponent~="relax-disabled"
              if opponent=="relax-foreign-enable"then foreign.technologies[WORKER].enabled=true end
              destination,message=load_control(destination_path:gsub("first%-finite%-held","first-finite-relaxed"),
                f210 and"5.0.21000"or"5.0.20000",relax_role,startup(40))
              if not destination then return {ok=false,message=message}end
              ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end
              before_owner=player.worker_robots_speed_modifier
              ok,result=invoke(destination,"changed")
              if not ok then return {ok=false,message=result,before_owner=before_owner,after_owner=player.worker_robots_speed_modifier}end
              if opponent=="relax-duplicate-config"then
                before_owner=player.worker_robots_speed_modifier
                ok,result=invoke(destination,"changed")
                return {ok=ok,message=result,before_owner=before_owner,after_owner=player.worker_robots_speed_modifier}
              end
            end
            local consumed_units=state.destination_science_accounting.consumed_units
            if f210 then consumed_units=1 end -- independent native item-inventory oracle
            local processing_ticks=state.destination_science_accounting.remaining_ticks
            if opponent=="wrong-tick-span" then processing_ticks=processing_ticks-1 end
            if opponent=="raw-elapsed-offset" then game.tick=game.tick+1 end
            for _=1,processing_ticks do ok,result=tick(destination);if not ok then return {ok=false,message=result}end end
            if opponent=="consumption-overshoot" then consumed_units=consumed_units+1/60 end
            if opponent=="item-no-debit"then consumed_units=0 end
            if opponent=="item-extra-debit"then consumed_units=2 end
            if opponent=="item-wrong-quality"then input.slots[1].quality.name="uncommon"end
            ok,result=complete(destination,9,state.player_with_independent+1.95,consumed_units);if not ok then return {ok=false,message=result}end
            if opponent=="duplicate-lab"then state.destination_lab_completions=2 end
            ok,result=tick(destination);if not ok then return {ok=false,message=result}end
            if owner_root and opponent=="owner-cold-drift"then player.worker_robots_speed_modifier=player.worker_robots_speed_modifier-.01 end
            for _=1,2 do ok,result=invoke(destination,"load");if not ok then return {ok=false,message=result}end;ok,result=tick(destination);if not ok then return {ok=false,message=result,after_reload_bonus=player.worker_robots_speed_modifier}end end
            return {ok=true,message="",phase=state.phase,source_labs=state.actual_lab_completions,destination_labs=state.destination_lab_completions,
              player_level=player.technologies[WORKER].level,bonus=player.worker_robots_speed_modifier,
              player_enabled=player.technologies[WORKER].enabled,player_visible=player.technologies[WORKER].visible_when_disabled,
              fixture_owned_offset=state.fixture_owned_offset,hold_result=hold_result,finite_hold_witness=state.finite_hold_witness,
              science_type=state.destination_science_accounting.science_type,
              inventory_consumed_units=state.destination_science_accounting.inventory_consumed_units,
              item_durability_reads=item_durability_reads,
              science_before=state.destination_science_units_before[science[1]],science_after=state.destination_science_units_after[science[1]],
              consumed_units=state.destination_science_accounting.consumed_units,remaining_ticks=state.destination_science_accounting.remaining_ticks,
              processing_ticks=state.destination_processing_ticks,elapsed_ticks=state.destination_elapsed_ticks,current_progress=state.destination_science_accounting.progress,foreign_progress=foreign.research_progress,foreign_enabled=foreign.technologies[WORKER].enabled,markers=markers,diagnostics=diagnostics,saves=saves}
          end
        ''')

    def row(self):
        return lua_value(self.lua, deepcopy(ROW))

    def f210_flow(self, opponent="", startup_facade=None):
        role = FIXTURE / "f210-owned-offset"
        return self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(role / "control.lua"),
                                            opponent, str(role), startup_facade, True)

    def finite_flow(self, f210, opponent=""):
        role = FIXTURE / ("f210" if f210 else "f200") / "first-finite-held"
        return self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(role / "control.lua"),
                                            opponent, role.as_posix(), None, f210, True)

    def test_first_finite_hold_preserves_earned_work_then_relaxes_before_one_new_lab(self):
        for f210 in (False, True):
            for opponent, reapplied in (("", .123), ("owner-retained", 0)):
                with self.subTest(f210=f210, opponent=opponent):
                    r = self.finite_flow(f210, opponent)
                    self.assertTrue(r["ok"], r["message"])
                    held = r["hold_result"]
                    self.assertEqual(("finite-held", 8, False, 2, 0, 14, 6, 2),
                                     (held["phase"], held["level"], held["enabled"], held["source_labs"],
                                      held["destination_labs"], held["science"], held["markers"], held["saves"]))
                    self.assertAlmostEqual(3.823, held["bonus"])
                    self.assertAlmostEqual(.27, held["saved_progress"])
                    self.assertEqual(("completed", 2, 1, 9, True, 9, 3),
                                     (r["phase"], r["source_labs"], r["destination_labs"], r["player_level"],
                                      r["player_enabled"], r["markers"], r["saves"]))
                    self.assertAlmostEqual(4.473, r["bonus"])
                    self.assertEqual(7, r["finite_hold_witness"]["maximum"])
                    self.assertEqual("relax", r["fixture_owned_offset"]["stage"])
                    self.assertAlmostEqual(reapplied, r["fixture_owned_offset"]["reapplied"])
                    self.assertAlmostEqual(21 if f210 else 22 - 44 / 60, r["science_after"])
                    self.assertEqual(0, r["item_durability_reads"])
                    self.assertFalse(r["foreign_enabled"])
                    self.assertAlmostEqual(.42, r["foreign_progress"])

    def test_finite_stages_refuse_missing_proof_foreign_or_cold_changes_before_owned_writes(self):
        for f210 in (False, True):
            for opponent in ("stale-enable", "saved-progress", "owner-native-loss", "owner-stale",
                             "owner-unknown", "owner-missing-ledger", "owner-foreign-enable",
                             "hold-duplicate-config", "hold-cold-enable", "hold-cold-bonus", "hold-cold-science",
                             "relax-missing-proof", "relax-bad-proof", "relax-bad-offset", "relax-bad-phase",
                             "relax-held-science", "relax-stale-entry", "relax-unknown-entry", "relax-disabled",
                             "relax-foreign-enable", "relax-duplicate-config"):
                with self.subTest(f210=f210, opponent=opponent):
                    r = self.finite_flow(f210, opponent)
                    self.assertFalse(r["ok"], opponent)
                    self.assertRegex(r["message"], r"\[(?:mir-worker-fixture-offset-owner|mir5-f200-legacy-worker-successor)\]")
                    self.assertEqual(r["before_owner"], r["after_owner"], r["message"])

    def test_finite_roles_pin_exact_engine_stage_and_register_without_native_reads(self):
        for target, base, mir, versions in (("f200", "2.0.77", "5.0.20000", ("0.5.0", "0.6.0")),
                                            ("f210", "2.1.23", "5.0.21000", ("0.7.0", "0.8.0"))):
            for stage, version in zip(("held", "relaxed"), versions):
                with self.subTest(target=target, stage=stage):
                    role = FIXTURE / target / ("first-finite-" + stage)
                    info = json.loads((role / "info.json").read_bytes())
                    self.assertEqual((NAME, version, base[:3]), (info["name"], info["version"], info["factorio_version"]))
                    self.assertEqual([f"base = {base}", f"more-infinite-research = {mir}",
                                      "a-mir-fixture-worker-entry = 0.1.0"], info["dependencies"])
                    parsed = self.lua.eval("worker_parse")(str(role / "control.lua"), mir, version,
                                                            str(FIXTURE / "persisted-offset-owner"), base)
                    self.assertTrue(parsed["ok"], parsed["message"])
                    self.assertEqual({}, plain(parsed["reads"]))
                    if target == "f210":
                        row = self.row()
                        data = self.lua.eval("worker_data")(str(FIXTURE / "successor/data-final-fixes.lua"),
                                                             mir, row, True, version)
                        self.assertTrue(data["ok"], data["message"])
                        self.assertEqual("1", row["unit"]["count_formula"])

    def test_f210_native_row_and_exact_role_metadata_keep_the_f200_source(self):
        role = FIXTURE / "f210-owned-offset"
        info = json.loads((role / "info.json").read_bytes())
        observer = json.loads((FIXTURE / "entry-observer/info-f210.json").read_bytes())
        self.assertEqual((NAME, "0.4.0", "2.1"), (info["name"], info["version"], info["factorio_version"]))
        self.assertIn("base = 2.1.23", info["dependencies"])
        self.assertIn("more-infinite-research = 5.0.21000", info["dependencies"])
        self.assertEqual(["base = 2.1.23"], observer["dependencies"])
        row = self.row()
        r = self.lua.eval("worker_data")(str(FIXTURE / "successor/data-final-fixes.lua"), "5.0.21000", row, True)
        self.assertTrue(r["ok"], r["message"])
        self.assertEqual(("1", 1), (row["unit"]["count_formula"], row["unit"]["time"]))
        bad = self.row()
        r = self.lua.eval("worker_data")(str(FIXTURE / "successor/data-final-fixes.lua"), "5.0.20000", bad, True)
        self.assertFalse(r["ok"])
        self.assertEqual("2^(L-6)*1000", bad["unit"]["count_formula"])
        parsed = self.lua.eval("worker_parse")(str(role / "control.lua"), "5.0.21000", "0.4.0", str(role), "2.1.23")
        self.assertTrue(parsed["ok"], parsed["message"])
        self.assertEqual({}, plain(parsed["reads"]))
        profile = json.loads((ROOT / "tests/profiles/f210-legacy-worker-owned-offset-2123.json").read_bytes())
        self.assertEqual(("f210", "2.1", "2.1.23"), (profile["target"], profile["factorio_line"], profile["engine"]["version"]))
        self.assertEqual("8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38", profile["engine"]["sha256"])
        self.assertEqual("38C84CCBC4BFDA62FCB078772C4690AB81228484744A36D9EA303F5A75B16447",
                         profile["archive_sha256"]["more-infinite-research_5.0.21000.zip"])
        self.assertNotIn("space-age", [row["name"] for row in profile["mods"]])
        self.assertEqual("0.4.0", next(row for row in profile["mods"] if row["name"] == NAME)["version"])

    def test_f210_spends_one_whole_item_without_reading_a_tool_durability_api(self):
        for opponent, reapplied in (("", .123), ("owner-retained", 0)):
            with self.subTest(opponent=opponent):
                r = self.f210_flow(opponent)
                self.assertTrue(r["ok"], r["message"])
                self.assertEqual((2, 1, 9, 6, 2), (r["source_labs"], r["destination_labs"], r["player_level"], r["markers"], r["saves"]))
                self.assertEqual(("item", 22, 21, 1, 0), (r["science_type"], r["science_before"], r["science_after"],
                                                        r["inventory_consumed_units"], r["item_durability_reads"]))
                self.assertAlmostEqual(44 / 60, r["consumed_units"])
                self.assertEqual(44, r["processing_ticks"])
                self.assertAlmostEqual(4.473, r["bonus"])
                self.assertAlmostEqual(reapplied, r["fixture_owned_offset"]["reapplied"])
                self.assertFalse(r["foreign_enabled"])
                self.assertAlmostEqual(.42, r["foreign_progress"])

    def test_f210_owner_refuses_wrong_tuples_unknown_or_foreign_state_before_aggregate_writes(self):
        for opponent in ("owner-wrong-mir", "owner-wrong-engine", "owner-native-loss", "owner-stale", "owner-unknown",
                         "owner-unknown-ledger", "owner-missing-ledger", "owner-repeated", "owner-force",
                         "owner-foreign-queue", "owner-foreign-enable", "owner-effect", "owner-duplicate-config",
                         "stale-enable", "native-level", "saved-progress"):
            with self.subTest(opponent=opponent):
                r = self.f210_flow(opponent)
                self.assertFalse(r["ok"])
                self.assertEqual(r["before_owner"], r["after_owner"])

    def test_f210_ordinary_item_accounting_and_read_only_reload_refuse_drift(self):
        for opponent, phrase in (("item-no-debit", "lab consumption differs"),
                                  ("item-extra-debit", "lab consumption differs"),
                                  ("item-wrong-quality", "native science quality changed"),
                                  ("wrong-tick-span", "processing ticks differ"),
                                  ("owner-cold-drift", "native worker state differs")):
            with self.subTest(opponent=opponent):
                r = self.f210_flow(opponent)
                self.assertFalse(r["ok"])
                self.assertIn(phrase, r["message"])

    def test_profiles_use_f200_base_observer_and_explicit_fixture_versions(self):
        for path, mir, version in ((PUBLISHED_PROFILE, "4.7.20002", "0.1.0"), (MIR5_PROFILE, "5.0.20000", "0.2.0")):
            with self.subTest(profile=path.name):
                profile = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(("f200", "2.0.77"), (profile["target"], profile["engine"]["version"]))
                self.assertEqual(["base", "mir-fixture-mir5-active-mods-observer", "more-infinite-research", NAME],
                                 [row["name"] for row in profile["mods"]])
                self.assertEqual((mir, version), (profile["mods"][2]["version"], profile["mods"][3]["version"]))
                self.assertNotIn("space-age", [row["name"] for row in profile["mods"]])
                info = json.loads((FIXTURE / ("published" if version == "0.1.0" else SUCCESSOR_ROLE) / "info.json").read_text())
                self.assertEqual((NAME, version, "2.0"), (info["name"], info["version"], info["factorio_version"]))

    def test_exact_base_native_row_preflight_precedes_only_disposable_count_time_mutation(self):
        for directory, mir in (("published", "4.7.20002"), ("mir5", "5.0.20000")):
            with self.subTest(directory=directory):
                row = self.row()
                if directory == "published":
                    row["visible_when_disabled"] = True
                result = self.lua.eval("worker_data")(str(FIXTURE / fixture_role(directory) / "data-final-fixes.lua"), mir, row)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((None, "1", 1), (result["row"]["unit"]["count"], result["row"]["unit"]["count_formula"], result["row"]["unit"]["time"]))
        bad = self.row(); bad["visible_when_disabled"] = True; bad["effects"][1]["modifier"] = .6
        result = self.lua.eval("worker_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), "4.7.20002", bad)
        self.assertFalse(result["ok"]); self.assertIn("published native worker effect changed", result["message"])
        self.assertEqual("2^(L-6)*1000", result["row"]["unit"]["count_formula"])
        bad_default = self.row(); bad_default["visible_when_disabled"] = False
        result = self.lua.eval("worker_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), "4.7.20002", bad_default)
        self.assertFalse(result["ok"]); self.assertIn("identity or progression changed", result["message"])

    def test_controls_parse_without_game_access_and_source_never_writes_player_presentation(self):
        for directory, mir, version in (("published", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
            with self.subTest(directory=directory):
                result = self.lua.eval("worker_parse")(str(FIXTURE / fixture_role(directory) / "control.lua"), mir, version)
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual({}, plain(result["reads"]))
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
        source = (FIXTURE / "published/control.lua").read_text(encoding="utf-8")
        self.assertNotIn("technology(game.forces.player, WORKER).enabled =", source)
        self.assertNotIn("technology(game.forces.player, WORKER).visible_when_disabled =", source)
        self.assertNotRegex(source, r"(?<!foreign_)native\.enabled\s*=")
        self.assertIn("technology(game.forces.player, WORKER).saved_progress = 0.27", source)
        self.assertIn('state.milestone = "actual2labs"', source)
        self.assertIn("published_controller_initial_visible_when_disabled", source)
        self.assertIn("await-second-queue", source)
        self.assertNotIn("research_queue_enabled", source)
        for directory in ("published", "mir5"):
            control = (FIXTURE / fixture_role(directory) / "control.lua").read_text(encoding="utf-8")
            body = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
            self.assertNotIn("game.", body, f"{directory} on_load touched LuaGameScript")
            self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=", f"{directory} on_load wrote fixture storage")

    def test_two_real_native_worker_labs_restore_source_right_then_one_successor_lab_and_reloads(self):
        result = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(FIXTURE / "successor/control.lua"), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(("completed", 2, 1, 9), (result["phase"], result["source_labs"], result["destination_labs"], result["player_level"]))
        self.assertAlmostEqual(3.323, result["bonus"], places=6)
        self.assertTrue(result["player_enabled"]); self.assertTrue(result["player_visible"])
        self.assertAlmostEqual(22, result["science_before"], places=6)
        self.assertAlmostEqual(22 - 44 / 60, result["science_after"], places=6)
        self.assertAlmostEqual(44 / 60, result["consumed_units"], places=6)
        self.assertEqual(44, result["remaining_ticks"])
        self.assertEqual(44, result["processing_ticks"])
        self.assertEqual(44, result["elapsed_ticks"])
        self.assertAlmostEqual(.27, result["current_progress"], places=6)
        self.assertEqual(.42, result["foreign_progress"]); self.assertFalse(result["foreign_enabled"])
        self.assertEqual((6, 1, 2), (result["markers"], result["diagnostics"], result["saves"]))

    def test_exact_processing_ticks_accept_a_distinct_raw_event_elapsed(self):
        result = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"),
                                               str(FIXTURE / "successor/control.lua"), "raw-elapsed-offset")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual((44, 44, 45),
                         (result["remaining_ticks"], result["processing_ticks"], result["elapsed_ticks"]))
        self.assertEqual(1, result["diagnostics"])

    def test_stale_state_native_bonus_foreign_queue_and_duplicate_completion_are_rejected(self):
        opponents = {
            "stale-enable": "MIR5 restored native worker native worker state differs",
            "native-level": "MIR5 restored native worker native worker state differs",
            "foreign-queue": "foreign worker queue or progress changed",
            "saved-progress": "MIR5 restored native worker saved progress differs",
            "speed-bonus": "MIR5 restored native worker native worker state differs",
            "lab-count": "published native-worker source witness is absent",
            "duplicate-lab": "successor did not finish exactly one further native worker lab level",
            "lost-investment": "successor native worker saved investment did not become current research",
            "wrong-tick-span": "successor real native worker lab processing ticks differ",
            "consumption-overshoot": "successor real native worker lab consumption differs for automation-science-pack: observed_units=",
        }
        for opponent, phrase in opponents.items():
            with self.subTest(opponent=opponent):
                result = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(FIXTURE / "successor/control.lua"), opponent)
                self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])
                if opponent == "consumption-overshoot":
                    self.assertIn("expected_units=21.266", result["message"])
                    self.assertIn("consumed_units=0.733", result["message"])
                    self.assertIn("remaining_ticks=44", result["message"])

    def test_persisted_fixture_owner_restores_only_its_own_known_offset(self):
        owner = FIXTURE / "persisted-offset-owner"
        for opponent, restored, entry_total in (("", .123, 3.7), ("owner-retained", 0, 3.823)):
            with self.subTest(opponent=opponent):
                r = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(owner / "control.lua"),
                                                 opponent, str(owner))
                self.assertTrue(r["ok"], r["message"])
                self.assertEqual((2, 1, 9, 6, 2), (r["source_labs"], r["destination_labs"], r["player_level"], r["markers"], r["saves"]))
                self.assertAlmostEqual(r["bonus"], 4.473)
                self.assertAlmostEqual(r["science_after"], 22 - 44 / 60)
                record = r["fixture_owned_offset"]
                self.assertAlmostEqual(record["amount"], .123)
                self.assertAlmostEqual(record["reapplied"], restored)
                self.assertAlmostEqual(record["native_entry_total"], entry_total)
                self.assertAlmostEqual(record["restored_total"], 3.823)
                self.assertAlmostEqual(record["source_total"], 3.823)
                self.assertFalse(r["foreign_enabled"])
                self.assertAlmostEqual(r["foreign_progress"], .42)

    def test_fixture_owner_refuses_unknown_stale_foreign_and_post_entry_changes_before_writes(self):
        owner = FIXTURE / "persisted-offset-owner"
        for opponent in ("owner-native-loss", "owner-stale", "owner-unknown", "owner-unknown-ledger", "owner-missing-ledger",
                         "owner-repeated", "owner-force", "owner-foreign-queue", "owner-foreign-enable", "owner-effect",
                         "owner-duplicate-config", "stale-enable", "native-level", "saved-progress"):
            with self.subTest(opponent=opponent):
                r = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(owner / "control.lua"),
                                                 opponent, str(owner))
                self.assertFalse(r["ok"])
                self.assertEqual(r["before_owner"], r["after_owner"], "rejected input changed the native aggregate")

    def test_fixture_owner_never_repairs_a_changed_bonus_on_cold_load(self):
        owner = FIXTURE / "persisted-offset-owner"
        r = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(owner / "control.lua"),
                                         "owner-cold-drift", str(owner))
        self.assertFalse(r["ok"])
        self.assertIn("native worker state differs", r["message"])
        self.assertAlmostEqual(r["after_reload_bonus"], 4.463)

    def test_fixture_owner_accepts_the_native_settings_userdata_facade(self):
        lua = self.lua

        class StartupFacade:
            def __getitem__(self, name):
                if name == "mir-max-level-worker-robots-speed":
                    return lua.table_from({"value": 40})
                if name == "mir-settings-profile-import":
                    return lua.table_from({"value": ""})
                raise KeyError(name)

        owner = FIXTURE / "persisted-offset-owner"
        r = self.lua.eval("worker_flow")(str(FIXTURE / "published/control.lua"), str(owner / "control.lua"),
                                         "", str(owner), StartupFacade())
        self.assertTrue(r["ok"], r["message"])
        self.assertAlmostEqual(r["bonus"], 4.473)

        f210 = self.f210_flow("", StartupFacade())
        self.assertTrue(f210["ok"], f210["message"])
        self.assertEqual(("item", 21, 0), (f210["science_type"], f210["science_after"], f210["item_durability_reads"]))

    def test_entry_observer_is_read_only_for_native_state_and_returns_detached_records(self):
        self.lua.execute(r'''
          function worker_entry_observer(path)
            local callbacks,interface,reads,logs={},nil,0,0
            local observed={level=8,researched=false,enabled=true,visible_when_disabled=true,saved_progress=.27}
            local player={index=1,name="player",worker_robots_speed_modifier=3.7,
              technologies={["worker-robots-speed-6"]=observed}}
            local foreign={index=4,name="mir5-f200-legacy-worker-foreign",worker_robots_speed_modifier=2.4,
              technologies={["worker-robots-speed-6"]={level=6,researched=false,enabled=false,visible_when_disabled=false,saved_progress=0}}}
            local state={}
            local env={storage=state,script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
                ["mir-fixture-mir5-f200-legacy-worker"]="0.3.0",["a-mir-fixture-worker-entry"]="0.1.0"},
                on_configuration_changed=function(f)callbacks.config=f end},
              remote={add_interface=function(name,methods)assert(name=="mir-fixture-worker-entry");interface=methods end},
              helpers={table_to_json=function(row)assert(row.player.bonus==3.7);return "{}"end},
              log=function(value)assert(value:match('^%[MIR_WORKER_NATIVE_ENTRY%] '));logs=logs+1 end}
            env._G=env;setmetatable(env,{__index=function(_,key)if key=="game"then reads=reads+1 end;return _G[key]end})
            assert(loadfile(path,"t",env))()
            assert(reads==0 and interface.get()==nil and state.entry==nil)
            env.game={tick=17,forces={player=player,["mir5-f200-legacy-worker-foreign"]=foreign}}
            callbacks.config()
            local row=interface.get();row.player.bonus=0;row.foreign.enabled=true
            assert(state.entry.player.bonus==3.7 and state.entry.foreign.enabled==false)
            assert(player.worker_robots_speed_modifier==3.7 and foreign.worker_robots_speed_modifier==2.4)
            assert(observed.enabled==true and foreign.technologies["worker-robots-speed-6"].enabled==false)
            return {logs=logs,reads=reads,tick=state.entry.tick}
          end
        ''')
        r = self.lua.eval("worker_entry_observer")(str(FIXTURE / "entry-observer/control.lua"))
        self.assertEqual((1, 0, 17), (r["logs"], r["reads"], r["tick"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(F200LegacyWorkerFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
