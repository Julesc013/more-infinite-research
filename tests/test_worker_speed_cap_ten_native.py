"""Pinned host controls for the reduced F200/SE worker-speed tail-ten actor.

They exercise fixture setup and the real pure cap reconciler with native-shaped
doubles. They neither start Factorio nor qualify native gameplay.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-speed-cap-ten-native"
SOURCE = FIXTURE / "source"
OLD_NEGATIVE = FIXTURE / "cap10"
SUCCESSOR = FIXTURE / "successor16"
LUA_ROOT = ROOT / "source"
WORKER = "worker-robots-speed-10"
PREDECESSOR = "worker-robots-speed-9"
DEEP_SCIENCE = "se-deep-space-science-pack-1"
ELECTRICITY = "electricity"
UNRELATED = "mir-fixture-unrelated-disabled"
CAP = "mir-max-level-worker-robots-speed"
PACKS = (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "utility-science-pack", "space-science-pack", "se-rocket-science-pack",
    "se-energy-science-pack-4", "se-deep-space-science-pack-1",
)


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
  successor16={fixture="0.6.0",mir="5.0.20016",cap=10}
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
  for _,n in ipairs({WORKER,PROBE,AUTOMATION,PREDECESSOR,DEEP,ELECTRICITY,UNRELATED})do f.technologies[n]=tech(n,f,wrong_energy)end
  f.technologies[UNRELATED].enabled,f.technologies[UNRELATED].researched=false,false
  function f.enable_all_prototypes()error("broad prototype enablement is forbidden by this fixture")end
  function f.reset_technology_effects()f.worker_robots_speed_modifier=(f.technologies[WORKER].level-1)*.65 end
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
    defines={events={on_tick=1,on_research_finished=2,on_research_started=3},inventory={lab_input=1}},
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
  ok,result=call(successor.changed);if not ok then return{ok=false,message=result,markers=markers,files=files,saves=saves,labs=labs}end
  local owner=player.technologies[WORKER]
  if opponent=="await-eleven"then owner.level=11;ok,result=call(successor.events[3],{research=owner,tick=0});return{ok=ok,message=result}end
  game.tick=1;ok,result=call(successor.events[1]);if not ok then return{ok=false,message=result}end
  if opponent=="scripted-finish"then owner.level=11;ok,result=call(successor.events[2],{research=owner,by_script=true,tick=1});return{ok=ok,message=result}end
  if opponent=="preincrement-finish"then owner.level=10;ok,result=call(successor.events[2],{research=owner,by_script=false,tick=1});return{ok=ok,message=result}end
  player.research_queue={};owner.level=11;ok,result=call(successor.events[2],{research=owner,by_script=false,tick=1});if not ok then return{ok=false,message=result}end
  player.worker_robots_speed_modifier=state.player_bonus_before+.65;for n in pairs(state.lab_feed)do game.lab.input.items[n]=50 end;caps.reconcile(player,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})
  if opponent=="after-eleven"then ok,result=call(successor.events[3],{research=owner,tick=1});return{ok=ok,message=result}end
  for _=1,3 do game.tick=game.tick+1;ok,result=call(successor.events[1]);if not ok then return{ok=false,message=result}end end
  for _=1,2 do local cold,cmsg=load_stage(successor_path,common,"successor16",game,storage,settings(10),markers,logs,files);if not cold then return{ok=false,message=cmsg}end;ok,result=call(cold.load);if not ok then return{ok=false,message=result}end;game.tick=game.tick+1;ok,result=call(cold.events[1]);if not ok then return{ok=false,message=result}end end
  return{ok=true,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage[KEY],player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}
end
''')

    def data_result(self, stage: str, opponent: str = ""):
        directory = {"source15": SOURCE, "old-negative15": OLD_NEGATIVE, "successor16": SUCCESSOR}[stage]
        return self.lua.eval("data_case")(str(directory / "settings-updates.lua"), str(directory / "data-final-fixes.lua"),
                                          str(FIXTURE / "fixture_settings.lua"), str(FIXTURE / "fixture_data_final.lua"), stage, opponent)

    def flow_result(self, mode: str = "successor", opponent: str = ""):
        return self.lua.eval("flow")(str(SOURCE / "control.lua"), str(OLD_NEGATIVE / "control.lua"), str(SUCCESSOR / "control.lua"),
                                     str(FIXTURE / "fixture_control.lua"), mode, opponent)

    def test_metadata_declares_three_explicit_f200_se_stages(self):
        for directory, version, mir in ((SOURCE, "0.4.0", "5.0.20015"), (OLD_NEGATIVE, "0.5.0", "5.0.20015"),
                                        (SUCCESSOR, "0.6.0", "5.0.20016")):
            with self.subTest(stage=directory.name):
                info = json.loads((directory / "info.json").read_text(encoding="utf-8"))
                self.assertEqual(("mir-fixture-mir5-worker-speed-cap-ten", version, "2.0"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(["base = 2.0.77", "space-exploration = 0.7.57", f"more-infinite-research = {mir}"], info["dependencies"])

    def test_data_preflight_retains_actual_tail_ten_contract_and_only_adds_fixture_lab(self):
        for stage, cap in (("source15", 0), ("old-negative15", 10), ("successor16", 10)):
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

    def test_published15_old_negative_records_public_adverse_before_expected_failure(self):
        result = self.flow_result("old-negative")
        self.assertFalse(result["ok"]); self.assertIn("MIR_EXPECTED_OLD15_CAP_NOT_ENFORCED", result["message"]); self.assertEqual((0, 0), (result["saves"], result["labs"]))
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "old-negative"], [row["phase"] for row in markers])
        adverse = markers[1]
        self.assertEqual(("5.0.20015", "5.0.20015"), (adverse["pre_work"]["source_mir"], adverse["pre_work"]["active_mir"]))
        self.assertEqual((10, True, 2, .27), (adverse["player"]["level"], adverse["player"]["enabled"], len(adverse["player"]["queue"]["queue"]), adverse["player"]["queue"]["progress"]))
        self.assertEqual((11, False, "automation", .42), (adverse["foreign"]["level"], adverse["foreign"]["enabled"], adverse["foreign"]["queue"]["current"], adverse["foreign"]["queue"]["progress"]))
        self.assertEqual((13, True, False), (adverse["earned_above_cap"]["level"], adverse["earned_above_cap"]["enabled"], adverse["earned_above_cap"]["queue"]["current"]))
        self.assertFalse(adverse["lab"]["present"]); self.assertEqual(0, adverse["ordinary_native_completion_count"])
        self.assertTrue(all(result[force]["technologies"][UNRELATED]["enabled"] is False
                            for force in ("player", "foreign", "earned")))
        self.assertNotIn("cap_owner", {key: adverse[key] for key in adverse})
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/old-negative.json"], [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])

    def test_successor_cap_keeps_one_ordinary_tail_ten_completion_then_two_cold_reads(self):
        result = self.flow_result(); self.assertTrue(result["ok"], result["message"]); self.assertEqual((1, 1), (result["saves"], result["labs"]))
        markers = [result["markers"][i] for i in range(1, len(result["markers"]) + 1)]
        self.assertEqual(["source", "pre-work", "complete", "cold", "cold"], [row["phase"] for row in markers])
        self.assertEqual(("5.0.20015", "5.0.20016"), (markers[0]["mir_version"], markers[1]["mir_version"]))
        complete = markers[2]
        self.assertEqual((1, 0), (complete["ordinary_native_completion_count"], complete["level_eleven_start_count"]))
        self.assertEqual((WORKER, False, 10, 11), (complete["ordinary_events"][1]["name"], complete["ordinary_events"][1]["by_script"],
                                                    complete["ordinary_events"][1]["completed_level"], complete["ordinary_events"][1]["event_post_increment_level"]))
        self.assertEqual((WORKER, False), (complete["ordinary"][1]["name"], complete["ordinary"][1]["by_script"]))
        self.assertEqual((2, 1, 0), (len(markers[0]["player"]["queue"]["queue"]), len(markers[1]["player"]["queue"]["queue"]), len(complete["player"]["queue"]["queue"])))
        self.assertEqual(3600, complete["player"]["research_unit_energy"])
        self.assertEqual(set(PACKS), set(complete["post_completion"]["lab"]["input_by_name"].keys()))
        self.assertTrue(all(complete["post_completion"]["lab"]["input_by_name"][name] > 0 for name in PACKS))
        post_input = complete["post_completion"]["lab"]["input_by_name"]
        end_input = complete["post_completion"]["end_lab"]["input_by_name"]
        self.assertEqual({name: post_input[name] for name in PACKS}, {name: end_input[name] for name in PACKS})
        self.assertEqual((False, 2), (complete["level_eleven_queue_attempt"]["accepted"], complete["post_completion_hold_ticks"]))
        self.assertEqual(["worker-speed-cap-ten/source.json", "worker-speed-cap-ten/pre-work.json", "worker-speed-cap-ten/complete.json", "worker-speed-cap-ten/cold.json", "worker-speed-cap-ten/cold.json"], [result["files"][i]["path"] for i in range(1, len(result["files"]) + 1)])

    def test_source_and_successor_controls_refuse_adverse_states(self):
        source_tick = self.flow_result("successor", "source-tick"); self.assertFalse(source_tick["ok"]); self.assertIn("source create-only stage received an actor tick", source_tick["message"])
        admin = self.flow_result("successor", "source-admin"); self.assertTrue(admin["ok"]); self.assertEqual("scripted-prerequisite", admin["state"]["scripted_administrative_events"][1]["setup_class"])
        electricity_admin = self.flow_result("successor", "source-admin-electricity")
        self.assertTrue(electricity_admin["ok"])
        self.assertEqual(ELECTRICITY, electricity_admin["state"]["scripted_administrative_events"][1]["name"])
        preinit = self.flow_result("successor", "preinit-unrelated"); self.assertTrue(preinit["ok"]); self.assertIsNone(preinit["state"])
        for opponent, phrase in {"source-worker": "source stage observed non-administrative research completion", "missing-electricity": "foreign automation electricity prerequisite is absent", "missing-predecessor": "player worker prerequisite is not researched: worker-robots-speed-9", "missing-deep": "player worker prerequisite is not researched: se-deep-space-science-pack-1", "skip-caps": "cap-ten did not retain only current level-ten work", "partial-drift": "cap-ten did not retain only current level-ten work", "foreign-reenabled": "foreign disabled sentinel differs", "scripted-finish": "scripted or non-level-ten completion cannot satisfy ordinary cap-ten work", "preincrement-finish": "scripted or non-level-ten completion cannot satisfy ordinary cap-ten work", "await-eleven": "level eleven research started", "after-eleven": "level eleven research started", "wrong-runtime-energy": "worker research-unit contract differs"}.items():
            with self.subTest(opponent=opponent):
                result = self.flow_result("successor", opponent); self.assertFalse(result["ok"]); self.assertIn(phrase, result["message"])
        control = (FIXTURE / "fixture_control.lua").read_text(encoding="utf-8")
        on_load = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
        self.assertNotIn("game", on_load); self.assertNotIn("storage", on_load)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args(); sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(WorkerSpeedCapTenNativeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
