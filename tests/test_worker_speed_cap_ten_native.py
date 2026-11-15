"""Pinned host controls for the reduced F200/SE worker-speed tail-ten actor.

They exercise fixture setup and the real pure cap reconciler with native-shaped
doubles. They neither start Factorio nor qualify native gameplay.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-speed-cap-ten-native"
SOURCE = FIXTURE / "source"
OLD_NEGATIVE = FIXTURE / "cap10"
SUCCESSOR = FIXTURE / "successor16"
CURRENT_OLD_NEGATIVE = FIXTURE / "current-old15"
CURRENT_SUCCESSOR = FIXTURE / "current-successor16"
LUA_ROOT = ROOT / "source"
WORKER = "worker-robots-speed-10"
PREDECESSOR = "worker-robots-speed-9"
DEEP_SCIENCE = "se-deep-space-science-pack-1"
AUTOMATION_SCIENCE = "automation-science-pack"
AUTOMATION = "automation"
ELECTRICITY = "electricity"
UNRELATED = "mir-fixture-unrelated-disabled"
CURRENT_SENTINEL = "stone-wall"
CAP = "mir-max-level-worker-robots-speed"
PACKS = (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "utility-science-pack", "space-science-pack", "se-rocket-science-pack",
    "se-energy-science-pack-4", "se-deep-space-science-pack-1",
)
ACTIVE_MODS = (
    "aai-containers@0.3.2", "aai-industry@0.6.16", "aai-signal-transmission@0.5.3",
    "alien-biomes-graphics@0.7.1", "alien-biomes@0.7.4", "base@2.0.77",
    "informatron@0.4.0", "jetpack@0.4.17",
    "mir-fixture-mir5-worker-speed-cap-ten@0.5.0", "more-infinite-research@5.0.20015",
    "robot_attrition@0.6.6", "shield-projector@0.2.2",
    "space-exploration-graphics-2@0.7.2", "space-exploration-graphics-3@0.7.2",
    "space-exploration-graphics-4@0.7.2", "space-exploration-graphics-5@0.7.3",
    "space-exploration-graphics@0.7.5", "space-exploration-menu-simulations@0.7.4",
    "space-exploration-postprocess@0.7.5", "space-exploration@0.7.57",
)
ACTIVE_MODS_OBSERVER = "mir-fixture-mir5-worker-speed-cap-ten"


class WorkerSpeedCapTenNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(f'package.path = "{LUA_ROOT.as_posix()}/?.lua;" .. package.path')
        self.lua.execute(r'''
local caps = require("runtime.caps")
local KEY = "mir5_worker_speed_cap_ten"
local WORKER, PREDECESSOR = "worker-robots-speed-10", "worker-robots-speed-9"
local DEEP, PROBE, AUTOMATION, ELECTRICITY = "se-deep-space-science-pack-1", "automation", "automation-science-pack", "electricity"
local UNRELATED = "mir-fixture-unrelated-disabled"
local FIXTURE = "mir-fixture-mir5-worker-speed-cap-ten"
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "utility-science-pack", "space-science-pack", "se-rocket-science-pack",
  "se-energy-science-pack-4", "se-deep-space-science-pack-1"}
local closure = {
  base="2.0.77", ["space-exploration"]="0.7.57", ["aai-containers"]="0.3.2", ["aai-industry"]="0.6.16",
  ["alien-biomes"]="0.7.4", ["alien-biomes-graphics"]="0.7.1", jetpack="0.4.17", robot_attrition="0.6.6",
  ["shield-projector"]="0.2.2", ["space-exploration-graphics"]="0.7.5", ["space-exploration-graphics-2"]="0.7.2",
  ["space-exploration-graphics-3"]="0.7.2", ["space-exploration-graphics-4"]="0.7.2",
  ["space-exploration-graphics-5"]="0.7.3", ["space-exploration-menu-simulations"]="0.7.4",
  ["space-exploration-postprocess"]="0.7.5", informatron="0.4.0", ["aai-signal-transmission"]="0.5.3"
}
local stages = {
  source15={fixture="0.4.0",mir="5.0.20015",cap=0},
  ["old-negative15"]={fixture="0.5.0",mir="5.0.20015",cap=10},
  successor16={fixture="0.6.0",mir="5.0.20016",cap=10},
  ["current-old15"]={fixture="0.7.0",mir="5.0.20015",cap=10},
  ["current-successor16"]={fixture="0.8.0",mir="5.0.20016",cap=10}
}
local function copy(v) if type(v)~="table" then return v end local o={} for k,x in pairs(v)do o[k]=copy(x)end return o end
local function packs() local r={} for _,n in ipairs(PACKS)do r[#r+1]={n,1}end return r end
local function runtime_packs() local r={} for _,n in ipairs(PACKS)do r[#r+1]={name=n,amount=1}end return r end

function data_case(settings_wrapper,data_wrapper,settings_common,data_common,stage,opponent)
  local expected=assert(stages[stage]);local cap=expected.cap;if opponent=="wrong-cap"then cap=cap==0 and 10 or 0 end
  local unit={count_formula=opponent=="wrong-formula" and "2^(L-6)*1000" or "0.2*(2^(L-6)*1000)",time=60,ingredients=packs()}
  local worker={name=WORKER,max_level="infinite",prerequisites={PREDECESSOR,DEEP},unit=unit,
    effects={{type="worker-robot-speed",modifier=opponent=="wrong-effect" and .6 or .65}}}
  local raw={technology={[WORKER]=worker},lab={lab={name="lab",inputs={"automation-science-pack"}}},
    ["int-setting"]={["mir-max-level-worker-robots-speed"]={default_value=0,minimum_value=0}}}
  local rows, logs = {}, {}
  local env={mods=copy(closure),data={raw=raw,extend=function(_,v)for _,x in ipairs(v)do rows[#rows+1]=x end end},
    settings={startup={["mir-max-level-worker-robots-speed"]={value=cap}}},log=function(row)logs[#logs+1]=row end}
  env.mods[FIXTURE],env.mods["more-infinite-research"]=expected.fixture,expected.mir
  local tables={}for k,v in pairs(table)do tables[k]=v end;tables.deepcopy=copy;env.table=tables
  env.require=function(n)if n=="__mir-fixture-mir5-worker-speed-cap-ten__/fixture_settings"then return assert(loadfile(settings_common,"t",env))()end
    assert(n=="__mir-fixture-mir5-worker-speed-cap-ten__/fixture_data_final");return assert(loadfile(data_common,"t",env))()end
  env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end})
  local ok,msg=pcall(assert(loadfile(settings_wrapper,"t",env)));if not ok then return{ok=false,message=tostring(msg),raw=raw,rows=rows,logs=logs,mods=env.mods}end
  ok,msg=pcall(assert(loadfile(data_wrapper,"t",env)));return{ok=ok,message=tostring(msg),raw=raw,rows=rows,logs=logs,mods=env.mods}
end

local function tech(name,force,wrong_energy)
  local t={name=name,valid=true,force=force,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
    prototype={max_level=4294967295,effects=name==WORKER and {{type="worker-robot-speed",modifier=.65}} or {}},
    prerequisites={},research_unit_count=3200,research_unit_energy=wrong_energy and 60 or 3600,research_unit_ingredients=runtime_packs()}
  if name==WORKER then t.prerequisites[PREDECESSOR]={name=PREDECESSOR};t.prerequisites[DEEP]={name=DEEP}end;return t
end
local function force(name,index,wrong_energy)
  local f={name=name,index=index,valid=true,technologies={},_queue={},current_research=nil,research_progress=0,worker_robots_speed_modifier=0}
  for _,n in ipairs({WORKER,PROBE,AUTOMATION,PREDECESSOR,DEEP,ELECTRICITY,UNRELATED,"stone-wall"})do f.technologies[n]=tech(n,f,wrong_energy)end
  f.technologies[UNRELATED].enabled,f.technologies[UNRELATED].researched=false,false
  f.technologies["stone-wall"].enabled,f.technologies["stone-wall"].researched=false,false
  function f.enable_all_prototypes()error("broad prototype enablement is forbidden by this fixture")end
  function f.reset_technology_effects()
    f.worker_robots_speed_modifier=f._reset_bonus or (f.technologies[WORKER].level-1)*.65
    if f._external_reset then f._external_reset(f) end
    if f._reset_dispatch then f._reset_dispatch(f) end
  end
  function f.add_research(r)
    if type(r)=="string"then r=f.technologies[r]end;if not r or r.enabled~=true or f.current_research then return false end
    if r.name==WORKER and(f.technologies[PREDECESSOR].researched~=true or f.technologies[DEEP].researched~=true)then return false end
    if r.name==PROBE and (f.technologies[AUTOMATION].researched~=true or f.technologies[ELECTRICITY].researched~=true) then return false end;f.research_queue={r};return true
  end
  return setmetatable(f,{__index=function(s,k)if k=="research_queue"then return rawget(s,"_queue")end end,
    __newindex=function(s,k,v)if k~="research_queue"then rawset(s,k,v)return end;rawset(s,"_queue",v);rawset(s,"current_research",v[1]);rawset(s,"research_progress",v[1]and 0 or 0)end})
end
local function inventory()
  local x={items={},capacity=200};function x.insert(r)local n=math.min(r.count,math.max(0,x.capacity-(x.items[r.name]or 0)));x.items[r.name]=(x.items[r.name]or 0)+n;return n end
  function x.get_item_count(n)return x.items[n]or 0 end;return x
end
local function load_stage(path,common,stage,game,storage,settings,markers,logs,files)
  local e,s,active = {events={}},assert(stages[stage]),copy(closure);active[FIXTURE],active["more-infinite-research"]=s.fixture,s.mir
  local env={game=game,storage=storage,settings=settings,script={active_mods=active,on_init=function(f)e.init=f end,
      on_configuration_changed=function(f)e.changed=f end,on_load=function(f)e.load=f end,on_event=function(k,f)e.events[k]=f end},
    defines={events={on_tick=1,on_research_finished=2,on_research_started=3,on_technology_effects_reset=4},inventory={lab_input=1}},
    helpers={table_to_json=function(row)markers[#markers+1]=row;return '{"fixture":"host"}'end,
      write_file=function(p,b,a)files[#files+1]={path=p,body=b,append=a}end},log=function(x)logs[#logs+1]=x end}
  env.require=function(n)assert(n=="__mir-fixture-mir5-worker-speed-cap-ten__/fixture_control");return assert(loadfile(common,"t",env))()end
  env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end});local ok,msg=pcall(assert(loadfile(path,"t",env)));return ok and e or nil,tostring(msg)
end
local function call(f,e)if type(f)~="function"then return false,"missing callback"end;local ok,msg=pcall(f,e);return ok,tostring(msg)end

function flow(source_path,old_path,successor_path,common,mode,opponent)
  local wrong=opponent=="wrong-runtime-energy";local player=force("player",1,wrong);local game={tick=0,forces={player=player,[1]=player},surfaces={}}
  function game.create_force(n)local x=force(n,#game.forces+1,wrong);game.forces[n],game.forces[x.index]=x,x;return x end
  local saves,labs=0,0;game.surfaces[1]={create_entity=function(row)labs=labs+1;local x={valid=true,disabled_by_script=false,unit_number=labs,input=inventory()};function x.get_inventory(i)assert(i==1)return x.input end;game.lab=x;return x end}
  function game.server_save(n)assert(n=="mir5-worker-speed-cap-ten-complete");saves=saves+1 end
  local storage,markers,logs,files={mir_caps={}}, {},{},{};local function settings(cap)return{startup={["mir-max-level-worker-robots-speed"]={value=cap},["mir-settings-profile-import"]={value=""}}}end
  local source,msg=load_stage(source_path,common,"source15",game,storage,settings(0),markers,logs,files);if not source then return{ok=false,message=msg}end
  local ok,result
  if opponent=="preinit-unrelated"then ok,result=call(source.events[2],{research={name="se-always-researched",force=player},by_script=true,tick=0});return{ok=ok,message=result,state=storage[KEY],markers=markers}end
  ok,result=call(source.init);if not ok then return{ok=false,message=result}end
  if opponent=="source-tick"then ok,result=call(source.events[1]);return{ok=ok,message=result}end
  if opponent=="source-worker"then ok,result=call(source.events[2],{research=player.technologies[WORKER],by_script=false,tick=0});return{ok=ok,message=result,state=storage[KEY]}end
  if opponent=="source-admin"or opponent=="source-admin-electricity"then
    local prerequisite=opponent=="source-admin" and PREDECESSOR or ELECTRICITY
    ok,result=call(source.events[2],{research=player.technologies[prerequisite],by_script=true,tick=0});return{ok=ok,message=result,state=storage[KEY]}
  end
  local state=storage[KEY];if not state then return{ok=false,message="source state absent"}end
  if opponent=="missing-electricity"then
    local foreign=game.forces[state.foreign_index];foreign.technologies[ELECTRICITY].researched=false
    local accepted=foreign.add_research(foreign.technologies[PROBE])
    return{ok=accepted==true,message=accepted and "foreign automation unexpectedly queued" or "foreign automation electricity prerequisite is absent"}
  end
  if mode=="old-negative"then local old,oldmsg=load_stage(old_path,common,"old-negative15",game,storage,settings(10),markers,logs,files);if not old then return{ok=false,message=oldmsg}end
    ok,result=call(old.changed);return{ok=ok,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}end
  if opponent=="missing-predecessor"then player.technologies[PREDECESSOR].researched=false end;if opponent=="missing-deep"then player.technologies[DEEP].researched=false end
  if opponent~="skip-caps"then for _,f in ipairs({player,game.forces[state.foreign_index],game.forces[state.earned_index]})do caps.reconcile(f,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})end end
  if opponent=="partial-drift"then player.research_progress=.26 end;if opponent=="foreign-reenabled"then game.forces[state.foreign_index].technologies[WORKER].enabled=true end
  local successor,smsg=load_stage(successor_path,common,"successor16",game,storage,settings(10),markers,logs,files);if not successor then return{ok=false,message=smsg}end
  ok,result=call(successor.changed);if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs}end
  local owner=player.technologies[WORKER]
  if opponent=="await-eleven"then owner.level=11;ok,result=call(successor.events[3],{research=owner,tick=0});return{ok=ok,message=result}end
  game.tick=1;ok,result=call(successor.events[1]);if not ok then return{ok=false,message=result}end
  if opponent=="scripted-finish"then ok,result=call(successor.events[2],{research=owner,by_script=true,tick=1});return{ok=ok,message=result}end
  player.research_queue={};owner.level=10;ok,result=call(successor.events[2],{research=owner,by_script=false,tick=1});if not ok then return{ok=false,message=result}end
  owner.level=11;player.worker_robots_speed_modifier=state.player_bonus_before+.65;for n in pairs(state.lab_feed)do game.lab.input.items[n]=50 end;caps.reconcile(player,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})
  if opponent=="after-eleven"then ok,result=call(successor.events[3],{research=owner,tick=1});return{ok=ok,message=result}end
  for _=1,3 do game.tick=game.tick+1;ok,result=call(successor.events[1]);if not ok then return{ok=false,message=result}end end
  for _=1,2 do local cold,cmsg=load_stage(successor_path,common,"successor16",game,storage,settings(10),markers,logs,files);if not cold then return{ok=false,message=cmsg}end;ok,result=call(cold.load);if not ok then return{ok=false,message=result}end;game.tick=game.tick+1;ok,result=call(cold.events[1]);if not ok then return{ok=false,message=result}end end
  return{ok=true,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage[KEY],player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}
end

function current_state_flow(old_path,successor_path,common,mode,opponent)
  local player,foreign,earned=force("player",1,false),force("mir5-worker-speed-cap-ten-foreign",2,false),force("mir5-worker-speed-cap-ten-earned",3,false)
  local game={tick=0,forces={player=player,[1]=player,[foreign.name]=foreign,[foreign.index]=foreign,[earned.name]=earned,[earned.index]=earned},surfaces={}}
  local saves,labs=0,0;game.surfaces[1]={create_entity=function(row)labs=labs+1;local x={valid=true,disabled_by_script=false,unit_number=labs,input=inventory()};function x.get_inventory(i)assert(i==1)return x.input end;game.lab=x;return x end}
  function game.server_save(n)assert(n=="mir5-worker-speed-cap-current-state-complete");saves=saves+1 end
  local storage,markers,logs,files={mir_caps={}}, {},{},{};local function settings()return{startup={["mir-max-level-worker-robots-speed"]={value=10},["mir-settings-profile-import"]={value=""}}}end
  local stage=mode=="old" and "current-old15" or "current-successor16";local path=mode=="old" and old_path or successor_path
  local actor,message=load_stage(path,common,stage,game,storage,settings(),markers,logs,files);if not actor then return{ok=false,message=message}end
  local function install_reset(force)
    force._external_reset=function(value)
      if mode=="candidate" and opponent~="candidate-no-cap" then caps.reconcile(value,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})end
    end
    force._reset_dispatch=function(value)
      if opponent=="missing-reset-event" then return end
      local callback=actor.events[4];if callback then callback({force=value})end
    end
  end
  install_reset(player)
  install_reset(foreign);install_reset(earned)
  function game.create_force()error("current-state role must use the three named input forces")end
  if opponent=="missing-prerequisite"then player.technologies[PREDECESSOR]=nil end
  if opponent=="sentinel-enabled"then player.technologies["stone-wall"].enabled=true end
  local ok,result=call(actor.changed)
  if mode=="old"then return{ok=ok,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage.mir5_worker_speed_cap_current_state,player=player,foreign=foreign,earned=earned}end
  if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage.mir5_worker_speed_cap_current_state,player=player,foreign=foreign,earned=earned}end
  local state=storage.mir5_worker_speed_cap_current_state;local owner=player.technologies[WORKER]
  if opponent=="fourth-reset"then player.reset_technology_effects();ok,result=call(actor.events[1]);return{ok=ok,message=result,state=state,markers=markers}end
  if opponent=="await-eleven"then owner.level=11;ok,result=call(actor.events[3],{research=owner,tick=0});return{ok=ok,message=result,state=state}end
  if opponent=="post-boundary-admin-write"then player.technologies[PREDECESSOR].researched=false end
  if opponent=="post-boundary-sentinel-write"then player.technologies["stone-wall"].enabled=true end
  game.tick=1;ok,result=call(actor.events[1]);if not ok then return{ok=false,message=result,state=state}end
  if opponent=="scripted-finish"then ok,result=call(actor.events[2],{research=owner,by_script=true,tick=1});return{ok=ok,message=result,state=state}end
  player.research_queue={};owner.level=10;ok,result=call(actor.events[2],{research=owner,by_script=false,tick=1});if not ok then return{ok=false,message=result,state=state}end
  owner.level=11;player.worker_robots_speed_modifier=state.current_player_bonus_before+.65;for n in pairs(state.lab_feed)do game.lab.input.items[n]=50 end;caps.reconcile(player,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})
  if opponent=="after-eleven"then ok,result=call(actor.events[3],{research=owner,tick=1});return{ok=ok,message=result,state=state}end
  for _=1,3 do game.tick=game.tick+1;ok,result=call(actor.events[1]);if not ok then return{ok=false,message=result,state=state}end end
  for _=1,2 do local cold,cmsg=load_stage(successor_path,common,"current-successor16",game,storage,settings(),markers,logs,files);if not cold then return{ok=false,message=cmsg}end;ok,result=call(cold.load);if not ok then return{ok=false,message=result}end;game.tick=game.tick+1;ok,result=call(cold.events[1]);if not ok then return{ok=false,message=result}end end
  return{ok=true,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}
end
''')

    def data_result(self, stage: str, opponent: str = ""):
        directory = {"source15": SOURCE, "old-negative15": OLD_NEGATIVE, "successor16": SUCCESSOR,
                     "current-old15": CURRENT_OLD_NEGATIVE, "current-successor16": CURRENT_SUCCESSOR}[stage]
        return self.lua.eval("data_case")(str(directory / "settings-updates.lua"), str(directory / "data-final-fixes.lua"),
                                          str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"), stage, opponent)

    def flow_result(self, mode: str = "successor", opponent: str = ""):
        return self.lua.eval("flow")(str(SOURCE / "control.lua"), str(OLD_NEGATIVE / "control.lua"), str(SUCCESSOR / "control.lua"),
                                     str(FIXTURE / "fixture_control.lua"), mode, opponent)

    def current_state_result(self, mode: str = "candidate", opponent: str = ""):
        return self.lua.eval("current_state_flow")(str(CURRENT_OLD_NEGATIVE / "control.lua"),
                                                   str(CURRENT_SUCCESSOR / "control.lua"),
                                                   str(FIXTURE / "fixture_control.lua"), mode, opponent)

    def test_metadata_declares_three_explicit_f200_se_stages(self):
        for directory, version, mir in ((SOURCE, "0.4.0", "5.0.20015"), (OLD_NEGATIVE, "0.5.0", "5.0.20015"),
                                        (SUCCESSOR, "0.6.0", "5.0.20016"),
                                        (CURRENT_OLD_NEGATIVE, "0.7.0", "5.0.20015"),
                                        (CURRENT_SUCCESSOR, "0.8.0", "5.0.20016")):
            with self.subTest(stage=directory.name):
                info = json.loads((directory / "info.json").read_text(encoding="utf-8"))
                self.assertEqual(("mir-fixture-mir5-worker-speed-cap-ten", version, "2.0"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(["base = 2.0.77", "space-exploration = 0.7.57", f"more-infinite-research = {mir}"], info["dependencies"])

    def test_data_preflight_retains_actual_tail_ten_contract_and_only_adds_fixture_lab(self):
        for stage, cap in (("source15", 0), ("old-negative15", 10), ("successor16", 10),
                           ("current-old15", 10), ("current-successor16", 10)):
            with self.subTest(stage=stage):
                result = self.data_result(stage)
                self.assertTrue(result["ok"], result["message"])
                worker = result["raw"]["technology"][WORKER]
                self.assertEqual(("infinite", "worker-robot-speed", .65), (worker["max_level"], worker["effects"][1]["type"], worker["effects"][1]["modifier"]))
                self.assertEqual(("0.2*(2^(L-6)*1000)", 60, PACKS), (worker["unit"]["count_formula"], worker["unit"]["time"], tuple(worker["unit"]["ingredients"][i][1] for i in range(1, 9))))
                self.assertEqual((PREDECESSOR, DEEP_SCIENCE), tuple(worker["prerequisites"][i] for i in range(1, 3)))
                self.assertEqual(PACKS, tuple(result["rows"][1]["inputs"][i] for i in range(1, 9)))
                self.assertEqual(cap, result["raw"]["int-setting"][CAP]["default_value"])
                self.assertEqual(1, len(result["logs"]))
                observed = result["logs"][1]
                self.assertTrue(observed.startswith("[MIR_ACTIVE_MODS] "))
                reported = observed.removeprefix("[MIR_ACTIVE_MODS] ").split("|")
                expected_mods = sorted(f"{name}@{version}" for name, version in result["mods"].items())
                self.assertEqual(expected_mods, reported)
                self.assertEqual(20, len(reported))
        for opponent, phrase in (("wrong-cap", "worker-speed cap startup differs"), ("wrong-effect", "SE worker-speed effect differs"), ("wrong-formula", "SE worker-speed research unit differs")):
            with self.subTest(opponent=opponent):
                result = self.data_result("successor16", opponent); self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])

    @staticmethod
    def _current_markers(result):
        return {row["phase"]: row for row in (result["markers"][index]
                for index in range(1, len(result["markers"]) + 1))}

    @staticmethod
    def _current_frame_signature(frame):
        worker = frame["worker"]
        queue = worker["queue"]
        flags = frame["prerequisite_flags"]
        return (
            frame["force_index"], frame["force_name"], worker["level"], worker["researched"], worker["enabled"],
            worker["visible"], worker["saved_progress"], worker["bonus"], worker["per_level_speed_effect"],
            worker["research_unit_count"], worker["research_unit_energy"], queue["current"],
            tuple(queue["queue"][index] for index in range(1, len(queue["queue"]) + 1)), queue["progress"],
            tuple((name, flags[name]["researched"], flags[name]["enabled"], flags[name]["visible"],
                   flags[name]["level"], flags[name]["valid"])
                  for name in (PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION)),
            frame["unrelated_sentinel"]["name"], frame["unrelated_sentinel"]["researched"],
            frame["unrelated_sentinel"]["enabled"], frame["unrelated_sentinel"]["visible"],
            frame["unrelated_sentinel"]["level"], frame["unrelated_sentinel"]["valid"],
        )

    def test_current_state_reset_roles_keep_the_declared_three_force_boundary(self):
        old = self.current_state_result("old")
        self.assertFalse(old["ok"])
        self.assertIn("MIR_EXPECTED_CURRENT_OLD15_RESET_NOT_ENFORCED", old["message"])
        self.assertEqual((0, 0), (old["saves"], old["labs"]))
        old_markers = self._current_markers(old)
        self.assertEqual({"current-provider", "current-pre-reset", "current-post-reset"}, set(old_markers))
        provider, old_pre, old_post = (old_markers[phase] for phase in
                                       ("current-provider", "current-pre-reset", "current-post-reset"))
        self.assertEqual(("post-provider-normalization-before-fixture-admin", "controller-bound-A0-base-input-only",
                          "not-read-no-continuation-precondition"),
                         (provider["snapshot_role"], provider["source_base"]["identity"],
                          provider["source_base"]["fixture_source_phase"]))
        self.assertEqual("published15-reset-event-not-enforced", old_post["outcome"])
        self.assertEqual(3, old_post["reset_call_count"])
        self.assertEqual({"player", "foreign", "earned_above_cap"},
                         {old_post["reset_rows"][index]["force_role"]
                          for index in range(1, len(old_post["reset_rows"]) + 1)})
        self.assertTrue(all(old_post["reset_rows"][index]["native_event_delivered"] is True
                            for index in range(1, len(old_post["reset_rows"]) + 1)))

        for frame_name in ("player", "foreign", "earned_above_cap"):
            frame = provider[frame_name]
            self.assertIsInstance(frame["force_index"], int)
            self.assertIsInstance(frame["force_name"], str)
            self.assertFalse(frame["unrelated_sentinel"]["enabled"])
            self.assertIsNone(frame["unrelated_sentinel"]["queue"])
            self.assertEqual({PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION},
                             set(frame["prerequisite_flags"].keys()))

        player_intent = old_pre["admin_intent"]["player"]
        foreign_intent = old_pre["admin_intent"]["foreign"]
        self.assertEqual((10, False, True, (WORKER, WORKER), .27),
                         (player_intent["worker"]["level"], player_intent["worker"]["researched"],
                          player_intent["worker"]["enabled"], tuple(player_intent["worker"]["queue"][index]
                                                                        for index in range(1, len(player_intent["worker"]["queue"]) + 1)),
                          player_intent["worker"]["progress"]))
        self.assertEqual((11, True, (AUTOMATION,), .42),
                         (foreign_intent["worker"]["level"], foreign_intent["worker"]["enabled"],
                          tuple(foreign_intent["queue"][index] for index in range(1, len(foreign_intent["queue"]) + 1)),
                          foreign_intent["progress"]))
        self.assertEqual((CURRENT_SENTINEL, False), (old_pre["admin_intent"]["unrelated_sentinel"]["name"],
                                                      old_pre["admin_intent"]["unrelated_sentinel"]["enabled"]))
        self.assertEqual((10, True, 2, .27), (old_pre["player"]["worker"]["level"],
                                               old_pre["player"]["worker"]["enabled"],
                                               len(old_pre["player"]["worker"]["queue"]["queue"]),
                                               old_pre["player"]["worker"]["queue"]["progress"]))
        self.assertEqual((11, True, AUTOMATION, .42), (old_pre["foreign"]["worker"]["level"],
                                                        old_pre["foreign"]["worker"]["enabled"],
                                                        old_pre["foreign"]["worker"]["queue"]["current"],
                                                        old_pre["foreign"]["worker"]["queue"]["progress"]))
        self.assertEqual((13, True, False), (old_pre["earned_above_cap"]["worker"]["level"],
                                              old_pre["earned_above_cap"]["worker"]["enabled"],
                                              old_pre["earned_above_cap"]["worker"]["queue"]["current"]))

        candidate = self.current_state_result()
        self.assertTrue(candidate["ok"], candidate["message"])
        self.assertEqual((1, 1), (candidate["saves"], candidate["labs"]))
        candidate_markers = self._current_markers(candidate)
        self.assertEqual({"current-provider", "current-pre-reset", "current-post-reset", "current-pre-work",
                          "current-complete", "current-cold"}, set(candidate_markers))
        candidate_pre, candidate_post, pre_work = (candidate_markers[phase] for phase in
                                                    ("current-pre-reset", "current-post-reset", "current-pre-work"))
        for role in ("player", "foreign", "earned_above_cap"):
            self.assertEqual(self._current_frame_signature(old_pre[role]), self._current_frame_signature(candidate_pre[role]))
        self.assertEqual("candidate16-reset-event-enforced", candidate_post["outcome"])
        self.assertEqual((10, 1, .27), (candidate_post["player"]["worker"]["level"],
                                        len(candidate_post["player"]["worker"]["queue"]["queue"]),
                                        candidate_post["player"]["worker"]["queue"]["progress"]))
        self.assertEqual((False, AUTOMATION, .42), (candidate_post["foreign"]["worker"]["enabled"],
                                                     candidate_post["foreign"]["worker"]["queue"]["current"],
                                                     candidate_post["foreign"]["worker"]["queue"]["progress"]))
        self.assertEqual((13, False), (candidate_post["earned_above_cap"]["worker"]["level"],
                                       candidate_post["earned_above_cap"]["worker"]["enabled"]))
        self.assertIsInstance(pre_work["post_reset_player_bonus"], (int, float))
        complete, cold = candidate_markers["current-complete"], candidate_markers["current-cold"]
        self.assertEqual((1, 0, 2), (complete["ordinary_native_completion_count"],
                                     complete["level_eleven_start_count"], complete["post_completion_hold_ticks"]))
        self.assertAlmostEqual(complete["post_reset_player_bonus"] + .65,
                               complete["post_completion"]["player"]["bonus"])
        self.assertEqual(set(PACKS), set(complete["lab"]["input_by_name"].keys()))
        self.assertTrue(all(complete["lab"]["input_by_name"][name] > 0 for name in PACKS))
        self.assertEqual((True, 2), (cold["on_load_read_only"], cold["post_completion_hold_ticks"]))
        self.assertEqual(["worker-speed-cap-ten/current-provider.json", "worker-speed-cap-ten/current-pre-reset.json",
                          "worker-speed-cap-ten/current-post-reset.json", "worker-speed-cap-ten/current-pre-work.json",
                          "worker-speed-cap-ten/current-complete.json", "worker-speed-cap-ten/current-cold.json",
                          "worker-speed-cap-ten/current-cold.json"],
                         [candidate["files"][index]["path"] for index in range(1, len(candidate["files"]) + 1)])

    def test_current_state_controls_refuse_missing_or_extra_reset_and_boundary_mutation(self):
        for opponent, phrase in {
            "missing-prerequisite": "technology is absent: worker-robots-speed-9",
            "sentinel-enabled": "current provider player unrelated sentinel is enabled",
            "missing-reset-event": "native reset event was not delivered synchronously",
            "candidate-no-cap": "candidate player reset state differs",
            "fourth-reset": "observed reset outside the declared three-force boundary",
            "post-boundary-admin-write": "post-reset public state changed before ordinary lab work",
            "post-boundary-sentinel-write": "current pre-work player unrelated sentinel is enabled",
            "await-eleven": "level eleven research started",
            "after-eleven": "level eleven research started",
            "scripted-finish": "scripted or non-level-ten current-state completion cannot satisfy ordinary cap-ten work",
        }.items():
            with self.subTest(opponent=opponent):
                result = self.current_state_result("candidate", opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
        source = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        current = source.split("local function begin_current_state", 1)[1].split("function M.apply", 1)[0]
        for forbidden in ("game.create_force", "add_research", "worker_robots_speed_modifier =", "storage[KEY]",
                          "remote.", "script.raise_event", "enable_all_prototypes", "research_recursive"):
            self.assertNotIn(forbidden, current)
        self.assertIn('local roles = {"player", "foreign", "earned_above_cap"}', source)
        self.assertIn("state.reset_call_count ~= 3", source)

    def test_library_observer_accepts_only_the_wrapper_report_of_the_full_active_tuple(self):
        """Bind the producer's wrapper call site to the real selection reader."""
        tuple_text = "|".join(ACTIVE_MODS)
        fixture_log = lambda script, rows=tuple_text, loading="": (
            f"{loading}1.860 Script @__{ACTIVE_MODS_OBSERVER}__/{script}:3: [MIR_ACTIVE_MODS] {rows}\n"
        )
        with tempfile.TemporaryDirectory(prefix="mir5-cap-ten-active-mods-") as work:
            temporary = Path(work)
            selection = temporary / "selected.json"
            selection.write_text(json.dumps([
                {"name": row.partition("@")[0], "version": row.partition("@")[2]}
                for row in ACTIVE_MODS
            ]), encoding="utf-8")
            logs = {
                "accepted": fixture_log("data-final-fixes.lua"),
                "shared": fixture_log("fixture_data_final.lua"),
                "contradictory": fixture_log("data-final-fixes.lua", loading="1.859 Loading mod base 2.0.78 (data.lua)\n"),
                "missing_asset": fixture_log("data-final-fixes.lua", rows="|".join(
                    row for row in ACTIVE_MODS if row != "space-exploration-graphics-5@0.7.3")),
            }
            paths = {}
            for name, contents in logs.items():
                path = temporary / f"{name}.log"
                path.write_text(contents, encoding="utf-8", newline="\n")
                paths[name] = str(path)
            script = r'''
              $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
              . $env:MIR_TEST_LIBRARY_ACTIVATION
              $activation=[pscustomobject]@{selected=@(Get-Content -LiteralPath $env:MIR_TEST_SELECTION -Raw|ConvertFrom-Json)}
              $observer=$env:MIR_TEST_OBSERVER
              Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $env:MIR_TEST_ACCEPTED -ActiveModsObserver $observer|Out-Null
              function Assert-ObserverRefusal([string]$Path,[string]$Expected){
                $refused=$false
                try{Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $Path -ActiveModsObserver $observer|Out-Null}catch{
                  if(-not $_.Exception.Message.Contains($Expected)){throw ('unexpected observer refusal: '+$_.Exception.Message)}
                  $refused=$true
                }
                if(-not $refused){throw ('observer opponent accepted: '+$Path)}
              }
              Assert-ObserverRefusal $env:MIR_TEST_SHARED '[mir-library-loaded-observation]'
              Assert-ObserverRefusal $env:MIR_TEST_CONTRADICTORY '[mir-library-loaded-selection] Duplicate or contradictory native identity.'
              Assert-ObserverRefusal $env:MIR_TEST_MISSING_ASSET '[mir-library-loaded-selection] Actual mod names/versions differ from the profile.'
            '''
            environment = dict(os.environ, MIR_TEST_LIBRARY_ACTIVATION=str(ROOT / "tools/lib/compatibility/LibraryActivation.ps1"),
                               MIR_TEST_SELECTION=str(selection), MIR_TEST_OBSERVER=ACTIVE_MODS_OBSERVER,
                               MIR_TEST_ACCEPTED=paths["accepted"], MIR_TEST_SHARED=paths["shared"],
                               MIR_TEST_CONTRADICTORY=paths["contradictory"], MIR_TEST_MISSING_ASSET=paths["missing_asset"])
            result = subprocess.run(["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
                                    cwd=ROOT, env=environment, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        shared = (FIXTURE / "fixture_data_final.lua").read_text(encoding="utf-8")
        self.assertNotIn('log("[MIR_ACTIVE_MODS] ', shared)
        for stage in (SOURCE, OLD_NEGATIVE, SUCCESSOR):
            wrapper = (stage / "data-final-fixes.lua").read_text(encoding="utf-8")
            self.assertIn('log("[MIR_ACTIVE_MODS] " .. tuple)', wrapper)

    def test_published15_old_negative_records_public_adverse_before_expected_failure(self):
        result = self.flow_result("old-negative")
        self.assertFalse(result["ok"]); self.assertIn("MIR_EXPECTED_OLD15_CAP_NOT_ENFORCED", result["message"]); self.assertEqual((0, 0), (result["saves"], result["labs"]))
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "preconditions", "old-negative"], [row["phase"] for row in markers])
        preconditions, adverse = markers[1], markers[2]
        self.assertEqual(("pre-assert-configuration", "source-seeded", "5.0.20015"),
                         (preconditions["source_snapshot_role"], preconditions["source_state"]["phase"], preconditions["source_state"]["source_mir"]))
        self.assertEqual(20, preconditions["active_mod_count"])
        self.assertEqual(("5.0.20015", "5.0.20015"), (adverse["pre_work"]["source_mir"], adverse["pre_work"]["active_mir"]))
        self.assertEqual((10, True, 2, .27), (adverse["player"]["level"], adverse["player"]["enabled"], len(adverse["player"]["queue"]["queue"]), adverse["player"]["queue"]["progress"]))
        self.assertEqual((11, False, "automation", .42), (adverse["foreign"]["level"], adverse["foreign"]["enabled"], adverse["foreign"]["queue"]["current"], adverse["foreign"]["queue"]["progress"]))
        self.assertEqual((13, True, False), (adverse["earned_above_cap"]["level"], adverse["earned_above_cap"]["enabled"], adverse["earned_above_cap"]["queue"]["current"]))
        self.assertFalse(adverse["lab"]["present"]); self.assertEqual(0, adverse["ordinary_native_completion_count"])
        self.assertTrue(all(result[force]["technologies"][UNRELATED]["enabled"] is False
                            for force in ("player", "foreign", "earned")))
        self.assertNotIn("cap_owner", {key: adverse[key] for key in adverse})
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/preconditions.json", "worker-speed-cap-ten/old-negative.json"], [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])

    def test_successor_cap_keeps_one_ordinary_tail_ten_completion_then_two_cold_reads(self):
        result = self.flow_result(); self.assertTrue(result["ok"], result["message"]); self.assertEqual((1, 1), (result["saves"], result["labs"]))
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "preconditions", "pre-work", "complete", "cold", "cold"], [row["phase"] for row in markers])
        self.assertEqual(("5.0.20015", "5.0.20016"), (markers[0]["mir_version"], markers[2]["mir_version"]))
        complete = markers[3]
        self.assertEqual((1, 0), (complete["ordinary_native_completion_count"], complete["level_eleven_start_count"]))
        self.assertEqual((WORKER, False), (complete["ordinary_events"][1]["name"], complete["ordinary_events"][1]["by_script"]))
        self.assertEqual((WORKER, False), (complete["ordinary"][1]["name"], complete["ordinary"][1]["by_script"]))
        self.assertEqual((2, 1, 0), (len(markers[0]["player"]["queue"]["queue"]), len(markers[2]["player"]["queue"]["queue"]), len(complete["player"]["queue"]["queue"])))
        self.assertEqual(3600, complete["player"]["research_unit_energy"])
        self.assertEqual(set(PACKS), set(complete["post_completion"]["lab"]["input_by_name"].keys()))
        self.assertTrue(all(complete["post_completion"]["lab"]["input_by_name"][name] > 0 for name in PACKS))
        post_input = complete["post_completion"]["lab"]["input_by_name"]
        end_input = complete["post_completion"]["end_lab"]["input_by_name"]
        self.assertEqual({name: post_input[name] for name in PACKS}, {name: end_input[name] for name in PACKS})
        self.assertEqual((False, 2), (complete["level_eleven_queue_attempt"]["accepted"], complete["post_completion_hold_ticks"]))
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/preconditions.json", "worker-speed-cap-ten/pre-work.json", "worker-speed-cap-ten/complete.json", "worker-speed-cap-ten/cold.json", "worker-speed-cap-ten/cold.json"], [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])

    def test_source_and_successor_controls_refuse_adverse_states(self):
        source_tick = self.flow_result("successor", "source-tick"); self.assertFalse(source_tick["ok"]); self.assertIn("source create-only stage received an actor tick", source_tick["message"])
        admin = self.flow_result("successor", "source-admin"); self.assertTrue(admin["ok"]); self.assertEqual("scripted-prerequisite", admin["state"]["scripted_administrative_events"][1]["setup_class"])
        electricity_admin = self.flow_result("successor", "source-admin-electricity")
        self.assertTrue(electricity_admin["ok"])
        self.assertEqual(ELECTRICITY, electricity_admin["state"]["scripted_administrative_events"][1]["name"])
        preinit = self.flow_result("successor", "preinit-unrelated"); self.assertTrue(preinit["ok"]); self.assertIsNone(preinit["state"])
        for opponent, phrase in {"source-worker": "source stage observed non-administrative research completion", "missing-electricity": "foreign automation electricity prerequisite is absent", "missing-predecessor": "player worker prerequisite is not researched: worker-robots-speed-9", "missing-deep": "player worker prerequisite is not researched: se-deep-space-science-pack-1", "skip-caps": "cap-ten did not retain only current level-ten work", "partial-drift": "cap-ten did not retain only current level-ten work", "foreign-reenabled": "foreign disabled sentinel differs", "scripted-finish": "scripted or non-level-ten completion cannot satisfy ordinary cap-ten work", "await-eleven": "level eleven research started", "after-eleven": "level eleven research started", "wrong-runtime-energy": "worker research-unit contract differs"}.items():
            with self.subTest(opponent=opponent):
                result = self.flow_result("successor", opponent); self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])
        control = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        on_load = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
        self.assertNotIn("game", on_load); self.assertNotIn("storage", on_load)

    def test_precondition_observer_precedes_the_known_missing_predecessor_assertion(self):
        result = self.flow_result("successor", "missing-predecessor")
        self.assertFalse(result["ok"])
        self.assertIn("player worker prerequisite is not researched: worker-robots-speed-9", result["message"])
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "preconditions"], [row["phase"] for row in markers])
        preconditions = markers[1]
        self.assertEqual(("pre-assert-configuration", "source-seeded", "5.0.20015"),
                         (preconditions["source_snapshot_role"], preconditions["source_state"]["phase"], preconditions["source_state"]["source_mir"]))
        self.assertEqual(False, preconditions["prerequisite_flags"]["player"][PREDECESSOR]["researched"])
        self.assertEqual(True, preconditions["prerequisite_flags"]["foreign"][PREDECESSOR]["researched"])
        self.assertEqual(True, preconditions["prerequisite_flags"]["earned_above_cap"][PREDECESSOR]["researched"])
        self.assertEqual(20, preconditions["active_mod_count"])
        self.assertEqual("0.7.57", preconditions["mods"]["space-exploration"])
        self.assertEqual("0.6.0", preconditions["mods"]["mir-fixture-mir5-worker-speed-cap-ten"])
        self.assertEqual("5.0.20016", preconditions["mods"]["more-infinite-research"])
        expected_researched = {
            "player": {PREDECESSOR: False, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: False, ELECTRICITY: False, AUTOMATION: False},
            "foreign": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: True, ELECTRICITY: True, AUTOMATION: False},
            "earned_above_cap": {PREDECESSOR: True, DEEP_SCIENCE: True, AUTOMATION_SCIENCE: False, ELECTRICITY: False, AUTOMATION: False},
        }
        for force_name in ("player", "foreign", "earned_above_cap"):
            flags = preconditions["prerequisite_flags"][force_name]
            self.assertEqual({PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION}, set(flags.keys()))
            for technology_name in (PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, AUTOMATION):
                value = flags[technology_name]
                self.assertEqual((expected_researched[force_name][technology_name], True, 1, True),
                                 (value["researched"], value["enabled"], value["level"], value["valid"]),
                                 f"{force_name}/{technology_name}")
        self.assertEqual((10, 11, 13), (preconditions["worker_frames"]["player"]["level"],
                                        preconditions["worker_frames"]["foreign"]["level"],
                                        preconditions["worker_frames"]["earned_above_cap"]["level"]))
        self.assertEqual(2, len(result["logs"]))
        self.assertTrue(result["logs"][2].startswith("[MIR_WORKER_SPEED_CAP_TEN phase=preconditions] "))
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/preconditions.json"],
                         [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args(); sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WorkerSpeedCapTenNativeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
