"""Independent native-shaped controls for protected published F100 witnesses.

These tests exercise fixture transactions, not Factorio or release acceptance.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/published-f100-forward"


class PublishedF100ForwardControls(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function forward_flow(control_path, source_plan, target_plan, definitions, opponent, bridge_plan)
  local function clone(value)
    if type(value)~="table"then return value end
    local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out
  end
  local plan=assert(loadfile(source_plan))()
  local current=plan
  local markers,saves={},0
  local force_list={}
  local packs={"military-science-pack","utility-science-pack"}
  local function inventory(count)
    local inv={values={}}
    for _,n in ipairs(packs)do inv.values[n]=count end
    function inv.get_item_count(n)return inv.values[n]or 0 end
    function inv.insert(r)inv.values[r.name]=(inv.values[r.name]or 0)+r.count;return r.count end
    return inv
  end
  local source_input=inventory(31)
  local source_lab={valid=true,active=false,energy=0,get_inventory=function()return source_input end}
  local labs={}
  local function make_force(name)
    local f={name=name,valid=true,technologies={},research_queue_enabled=true,research_queue={},
      research_progress=0,manual_mining_speed_modifier=0,laboratory_speed_modifier=0,laboratory_productivity_bonus=0,
      inserter_stack_size_bonus=0,stack_inserter_capacity_bonus=0,bulk_inserter_capacity_bonus=0,bonus=0}
    for n,definition in pairs(definitions)do
      local proto=clone(definition)
      local t={name=n,valid=true,force=f,level=proto.level,researched=false,enabled=true,
        visible_when_disabled=false,prototype=proto,prerequisites={},saved_progress=0}
      f.technologies[n]=t
    end
    f.technologies["braking-force-1"]={name="braking-force-1",valid=true,force=f,researched=false,enabled=true,prerequisites={}}
    function f.get_saved_technology_progress(t)return t.saved_progress~=0 and t.saved_progress or nil end
    function f.set_saved_technology_progress(t,v)t.saved_progress=v end
    function f.add_research(t)f.research_queue[#f.research_queue+1]=t;f.current_research=f.research_queue[1];return true end
    function f.get_gun_speed_modifier(ammo)assert(ammo==current.ammo);return f.bonus end
    function f.get_spawn_position()return{x=0,y=0}end
    function f.reset_technology_effects()
      f.bonus=0
      for i=1,7 do if f.technologies[current.laser_prefix..i].researched then f.bonus=f.bonus+({.1,.2,.3,.3,.4,.4,.5})[i]end end
      f.inserter_stack_size_bonus=f.technologies["inserter-capacity-bonus-8"].level==9 and 2 or 0
      f.stack_inserter_capacity_bonus=f.inserter_stack_size_bonus*2
    end
    force_list[name]=f;return f
  end
  local player=make_force("player")
  local direct="recipe-prod-research_character_mining_speed-1"
  player.technologies[direct].level=2;player.manual_mining_speed_modifier=.05
  player.research_queue={player.technologies[direct],player.technologies["braking-force-1"]}
  player.current_research=player.research_queue[1];player.research_progress=.42
  local original={origin="published",phase="published-ready",source_direct_finished=1,before_mining=0,
    source_lab=source_lab,source_lab_initial={[packs[1]]=32,[packs[2]]=32},saved=true}
  local bucket={mir5_historical_transition=original}
  local game={tick=100,forces=force_list,surfaces={{}}}
  function game.create_force(n)return make_force(n)end
  game.surfaces[1].create_entity=function(spec)
    assert(spec.name=="lab");local inv=inventory(0)
    local lab={valid=true,active=true,energy=0,get_inventory=function()return inv end}
    labs[#labs+1]=lab;return lab
  end
  function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
  local function load_stage(stage_path, readonly)
    current=assert(loadfile(stage_path))()
    local callbacks={}
    local env={game=game,settings={startup={}},defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}},
      script={active_mods={base=current.base,["more-infinite-research"]=current.mir,["mir-fixture-mir5-historical-transition"]=current.fixture}},
      require=function(n)assert(n=="stage");return current end,
      log=function(s)markers[#markers+1]=s end}
    env._G=env
    if current.target=="f210"then env.storage=bucket else env.global=bucket end
    setmetatable(env,{__index=_G})
    for _,k in ipairs({"on_init","on_load","on_configuration_changed"})do env.script[k]=function(fn)callbacks[k]=fn end end
    function env.script.on_event(event,fn)callbacks[event]=fn end
    assert(loadfile(control_path,"t",env))()
    if readonly then
      local saved_game=env.game;env.game=setmetatable({},{__index=function()error("game accessed during on_load")end,__newindex=function()error("game written during on_load")end})
      callbacks.on_load();env.game=saved_game
    end
    return callbacks,env
  end
  if opponent=="source-mining"then player.manual_mining_speed_modifier=0 end
  if opponent=="source-queue"then player.research_progress=.41 end
  if opponent=="source-lab"then source_lab.active=true end
  if opponent=="source-science"then source_input.values[packs[1]]=32 end
  if opponent=="source-extra-laser"then player.technologies["laser-turret-speed-8"]={}end
  if opponent=="source-inserter-effect"then player.technologies["inserter-capacity-bonus-8"].prototype.effects[2].modifier=3 end
  local callbacks=load_stage(source_plan,true)
  if opponent=="fresh-world"then callbacks.on_init()end
  callbacks.on_configuration_changed();callbacks[1]();callbacks[1]()
  assert(saves==1 and #markers==1 and #labs==0,"source enhancement must save once without a new lab")
  local source_snapshot=clone(original.forward)
  callbacks=load_stage(source_plan,true);callbacks[1]();callbacks[1]()
  assert(saves==1 and #markers==2,"source cold reload must be read-only and report once")
  local function move_engine(stage_path)
    local destination=assert(loadfile(stage_path))()
    local old_prefix=current.laser_prefix
    for _,f in pairs(force_list)do
      for i=1,7 do
        local value=f.technologies[old_prefix..i];f.technologies[old_prefix..i]=nil
        value.name=destination.laser_prefix..i;f.technologies[value.name]=value
        value.prototype.effects[1].ammo_category=destination.ammo
      end
      if destination.target=="f210"then
        f.bulk_inserter_capacity_bonus=f.stack_inserter_capacity_bonus
        for _,t in pairs(f.technologies)do
          for _,e in pairs((t.prototype or{}).effects or{})do
            if e.type=="stack-inserter-capacity-bonus"then e.type="bulk-inserter-capacity-bonus"end
          end
        end
      end
    end
    return load_stage(stage_path,true)
  end
  if bridge_plan~=""then
    callbacks=move_engine(bridge_plan);callbacks.on_configuration_changed();callbacks[1]();callbacks[1]()
    assert(#labs==0 and #markers==3 and saves==2,"published bridge must not create research or a false cold marker")
  end
  callbacks=move_engine(target_plan)
  if opponent=="destination-level"then player.technologies[direct].level=1 end
  if opponent=="destination-cap"then player.technologies[direct].prototype.max_level=12 end
  if opponent=="destination-effect"then player.technologies[current.laser_prefix..7].prototype.effects[1].modifier=.4 end
  if opponent=="destination-laser"then player.bonus=0 end
  if opponent=="destination-inserter"then player.inserter_stack_size_bonus=1 end
  if opponent=="destination-foreign"then force_list["mir-published-f100-foreign"].technologies[direct].enabled=true end
  if opponent=="destination-paused"then force_list["mir-published-f100-suspended"].technologies[direct].saved_progress=.26 end
  if opponent=="destination-queue"then player.research_progress=.41 end
  callbacks.on_configuration_changed();assert(#labs==1 and original.forward.phase=="successor-lab")
  callbacks[1]();assert(labs[1].energy>0)
  player.technologies[direct].level=3;player.manual_mining_speed_modifier=.1
  local inv=labs[1].get_inventory();for _,n in ipairs(packs)do inv.values[n]=31 end
  callbacks[2]({research=player.technologies[direct]})
  table.remove(player.research_queue,1);player.current_research=player.research_queue[1];player.research_progress=0
  callbacks[1]();callbacks[1]()
  local expected_saves=bridge_plan==""and 2 or 3
  assert(saves==expected_saves and original.forward.successor_labs==1)
  if opponent=="completed-effect"then player.bonus=0 end
  for i=1,2 do
    callbacks=load_stage(target_plan,true)
    callbacks.on_configuration_changed() -- A completed reload still checks all state.
    callbacks[1]();callbacks[1]()
  end
  assert(saves==expected_saves and #labs==1 and original.source_direct_finished==1)
  return #markers,saves,#labs,original.forward.seeded_finite_lasers,source_snapshot.player[direct].level
end
''')
        direct = json.loads((ROOT / "tests/fixtures/historical-direct-native-oracle.json").read_bytes())
        continuation = json.loads((ROOT / "tests/fixtures/historical-continuation-native-oracle.json").read_bytes())
        definitions = {}
        for oracle in (direct, continuation):
            capture = next(row for row in oracle["captures"] if row["target"] == "f100")
            for row in capture["technologies"]:
                effects = list(row["definition"]["effects"].values())
                level = int(row["id"].rsplit("-", 1)[1])
                definitions[row["id"]] = {"level": level, "max_level": row["definition"]["max_level"], "effects": effects}
        for i, modifier in enumerate((.1, .2, .3, .3, .4, .4, .5), 1):
            definitions[f"laser-turret-speed-{i}"] = {"level": i, "max_level": i, "effects": [
                {"type": "gun-speed", "ammo_category": "laser-turret", "modifier": modifier}]}
        self.definitions = self.to_lua(definitions)

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k: self.to_lua(v) for k, v in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(v) for v in value])
        return value

    def flow(self, target="f110", opponent="", bridge=False):
        return self.lua.globals().forward_flow(str(FIXTURE / "shared/control.lua"),
            str(FIXTURE / "source/stage.lua"), str(FIXTURE / target / "stage.lua"), self.definitions,
            opponent, str(FIXTURE / "bridge/stage.lua") if bridge else "")

    def test_both_exact_destinations_preserve_source_and_two_completed_reload_checks(self):
        for target in ("f110", "f210"):
            with self.subTest(target=target):
                self.setUp()
                self.assertEqual(self.flow(target), (5, 2, 1, 7, 2))

    def test_optional_published_engine_bridge_preserves_state_without_new_research(self):
        self.assertEqual(self.flow("f210", bridge=True), (6, 3, 1, 7, 2))

    def test_source_faults_refuse_before_an_enhanced_save_or_new_lab(self):
        for opponent in ("fresh-world", "source-mining", "source-queue", "source-lab", "source-science",
                         "source-extra-laser", "source-inserter-effect"):
            with self.subTest(opponent=opponent):
                self.setUp()
                with self.assertRaises(Exception):
                    self.flow(opponent=opponent)

    def test_destination_faults_and_completed_configuration_drift_remain_failures(self):
        for target in ("f110", "f210"):
            for opponent in ("destination-level", "destination-cap", "destination-effect", "destination-laser",
                             "destination-inserter", "destination-foreign", "destination-paused", "destination-queue", "completed-effect"):
                with self.subTest(target=target, opponent=opponent):
                    self.setUp()
                    with self.assertRaises(Exception):
                        self.flow(target, opponent)

    def test_stages_preserve_mod_identity_and_never_change_startup_settings(self):
        expected = {"source": ("1.0", "0.2.0", "4.7.10003"), "bridge": ("1.1", "0.3.0", "4.7.11003"),
                    "f110": ("1.1", "0.4.0", "5.0.11000"), "f210": ("2.1", "0.5.0", "5.0.21000")}
        for directory, (line, version, mir) in expected.items():
            path = FIXTURE / directory
            info = json.loads((path / "info.json").read_bytes())
            self.assertEqual(info["name"], "mir-fixture-mir5-historical-transition")
            self.assertEqual((info["factorio_version"], info["version"]), (line, version))
            self.assertIn("more-infinite-research = " + mir, info["dependencies"])
            self.assertNotIn("data", (path / "settings-updates.lua").read_text())

    def test_data_preflight_refuses_changed_meaning_before_acceleration(self):
        self.lua.execute(r'''
          function preflight(path,stage_path,row,opponent)
            local plan=assert(loadfile(stage_path))()
            local env={mods={base=plan.base,["more-infinite-research"]=plan.mir},
              data={raw={technology={["recipe-prod-research_character_mining_speed-1"]=row}}},
              require=function(n)assert(n=="stage");return plan end}
            env._G=env;setmetatable(env,{__index=_G})
            if opponent=="engine"then env.mods.base="2.0.1"end
            if opponent=="mir"then env.mods["more-infinite-research"]="4.7.11002"end
            local ok,message=pcall(assert(loadfile(path,"t",env)))
            return ok,tostring(message)
          end
        ''')
        for directory in ("source", "bridge", "f110", "f210"):
            row = {"level": 1, "max_level": "infinite", "upgrade": True,
                   "effects": [{"type": "character-mining-speed", "modifier": .05}],
                   "unit": {"count_formula": "1*(8000*2^(L-1))" if directory in ("f110", "f210") else "8000*2^(L-1)",
                            "time": 60, "ingredients": [["military-science-pack", 1], ["utility-science-pack", 1]]}}
            for opponent in ("", "engine", "mir", "effect", "cost", "cap", "science"):
                with self.subTest(stage=directory, opponent=opponent):
                    changed = deepcopy(row)
                    if opponent == "effect":
                        changed["effects"][0]["modifier"] = .1
                    elif opponent == "cost":
                        changed["unit"]["time"] = 120
                    elif opponent == "cap":
                        changed["max_level"] = 12
                    elif opponent == "science":
                        changed["unit"]["ingredients"][1][0] = "automation-science-pack"
                    native = self.to_lua(changed)
                    ok, _ = self.lua.globals().preflight(str(FIXTURE / "shared/data-final-fixes.lua"),
                        str(FIXTURE / directory / "stage.lua"), native, opponent)
                    self.assertEqual(ok, not opponent)
                    if opponent:
                        self.assertEqual(native["unit"]["count_formula"], changed["unit"]["count_formula"])
                        self.assertIsNone(native["unit"]["count"])
                    else:
                        self.assertIsNone(native["unit"]["count_formula"])
                        self.assertEqual((native["unit"]["count"], native["unit"]["time"]), (1, 1))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", required=True)
    args, rest = parser.parse_known_args()
    sys.path.insert(0, args.lua_runtime_dir)
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
