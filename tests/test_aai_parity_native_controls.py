"""Independent data-stage and lifecycle controls for the AAI parity fixture."""

from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import argparse
import json
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "aai-parity-native"
BASE_SCIENCE = [
    ["automation-science-pack", 1],
    ["logistic-science-pack", 1],
    ["chemical-science-pack", 1],
    ["production-science-pack", 1],
]
AAI = {
    "fuel-processing": (["automation-science-pack"], 10, 10),
    "sand-processing": (["automation-science-pack"], 10, 10),
    "electricity": (["fuel-processing"], 50, 10),
    "electronics": (["electricity"], 30, 15),
    "glass-processing": (["sand-processing"], 40, 10),
    "electric-lab": (["electronics", "glass-processing"], 100, 10),
}


def lua(runtime, value):
    if isinstance(value, dict):
        table = runtime.table()
        for key, item in value.items():
            table[key] = lua(runtime, item)
        return table
    if isinstance(value, list):
        table = runtime.table()
        for index, item in enumerate(value, 1):
            table[index] = lua(runtime, item)
        return table
    return value


def py(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [py(value[key]) for key in range(1, max(keys) + 1)]
        return {key: py(value[key]) for key in keys}
    return value


def raw_fixture():
    technologies = {
        "burner-mechanics": {
            "research_trigger": {"type": "craft-item", "item": "iron-plate", "count": 10},
            "effects": [{"type": "unlock-recipe", "recipe": "burner-lab"}],
        },
        "automation-science-pack": {
            "research_trigger": {"type": "craft-item", "item": "burner-lab"},
            "prerequisites": ["burner-mechanics"],
        },
        "recipe-prod-research_electric_engine-1": {
            "max_level": "infinite",
            "prerequisites": [row[0] for row in BASE_SCIENCE],
            "unit": {"count_formula": "8000*2^(L-1)", "time": 60, "ingredients": deepcopy(BASE_SCIENCE)},
            "effects": [{"type": "change-recipe-productivity", "recipe": "electric-engine-unit", "change": 0.1}],
        },
    }
    for name, (prerequisites, count, time) in AAI.items():
        technologies[name] = {
            "prerequisites": prerequisites,
            "unit": {"count": count, "time": time, "ingredients": [["automation-science-pack", 1]]},
        }
    return {
        "technology": technologies,
        "recipe": {
            "burner-lab": {
                "categories": ["crafting"],
                "enabled": False,
                "energy_required": 0.5,
                "ingredients": [
                    {"type": "item", "name": "motor", "amount": 10},
                    {"type": "item", "name": "copper-plate", "amount": 10},
                    {"type": "item", "name": "stone-brick", "amount": 5},
                ],
                "results": [{"type": "item", "name": "burner-lab", "amount": 1}],
            },
            "iron-plate": {
                "categories": ["smelting"],
                "energy_required": 3.2,
                "ingredients": [{"type": "item", "name": "iron-ore", "amount": 1}],
                "results": [{"type": "item", "name": "iron-plate", "amount": 1}],
            },
            "electric-engine-unit": {
                "energy_required": 10,
                "ingredients": [
                    {"type": "fluid", "name": "lubricant", "amount": 40},
                    {"type": "item", "name": "steel-plate", "amount": 2},
                    {"type": "item", "name": "electronic-circuit", "amount": 4},
                    {"type": "item", "name": "electric-motor", "amount": 2},
                ],
                "results": [{"type": "item", "name": "electric-engine-unit", "amount": 1}],
            },
        },
        "item": {
            "automation-science-pack": {"stack_size": 200},
        },
        "unrelated": {"preserved": True},
    }


class AaiParityNativeControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(LUA_RUNTIME_DIR.resolve(strict=True)))
        from lupa.lua52 import LuaRuntime

        cls.LuaRuntime = LuaRuntime

    def setUp(self):
        self.lua = self.LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.execute(
            r'''
            function run_data(stage, raw, mods)
              local env = {data={raw=raw}, mods=mods}
              env.require = function(name)
                if name == "__mir-fixture-mir5-aai-parity-native__/fixture_data_final" then
                  return assert(loadfile(fixture .. "/shared/data-final-fixes.lua", "t", env))()
                end
                if name == "__mir-fixture-mir5-aai-parity-native__/catalogue" then
                  return assert(loadfile(fixture .. "/shared/catalogue.lua", "t", env))()
                end
                if name == "__mir-fixture-mir5-aai-parity-native__/published-4.7/catalogue" then
                  return assert(loadfile(fixture .. "/published-4.7/catalogue.lua", "t", env))()
                end
                if name == "__mir-fixture-mir5-aai-parity-native__/mir5/catalogue" then
                  return assert(loadfile(fixture .. "/mir5/catalogue.lua", "t", env))()
                end
                error("unexpected fixture module: " .. tostring(name))
              end
              env._G = env
              setmetatable(env, {__index=_G})
              local ok, message = pcall(function()
                return assert(loadfile(fixture .. "/" .. stage .. "/data-final-fixes.lua", "t", env))()
              end)
              return {ok=ok, message=tostring(message), raw=raw}
            end
            function parse_control(stage, mods)
              local callbacks, forbidden = {events={}}, {}
              local env = {
                script={active_mods=mods,on_init=function(fn) callbacks.init=fn end,on_load=function(fn) callbacks.load=fn end,
                  on_configuration_changed=function(fn) callbacks.configuration=fn end,on_event=function(event,fn) callbacks.events[event]=fn end},
                defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1, fuel=2, crafter_input=3, crafter_output=4}},
                mods=mods,
              }
              env.require = function(name)
                if name == "__mir-fixture-mir5-aai-parity-native__/fixture_control" then
                  return assert(loadfile(fixture .. "/shared/control.lua", "t", env))()
                end
                if name == "__mir-fixture-mir5-aai-parity-native__/catalogue" then
                  return assert(loadfile(fixture .. "/shared/catalogue.lua", "t", env))()
                end
                if name == "__mir-fixture-mir5-aai-parity-native__/published-4.7/catalogue" then
                  return assert(loadfile(fixture .. "/published-4.7/catalogue.lua", "t", env))()
                end
                if name == "__mir-fixture-mir5-aai-parity-native__/mir5/catalogue" then
                  return assert(loadfile(fixture .. "/mir5/catalogue.lua", "t", env))()
                end
                error("unexpected fixture module: " .. tostring(name))
              end
              env._G = env
              setmetatable(env, {__index=function(_, key)
                if key == "game" or key == "storage" then forbidden[key]=true; return nil end
                return _G[key]
              end})
              local ok, message = pcall(function() assert(loadfile(fixture .. "/" .. stage .. "/control.lua", "t", env))() end)
              return {ok=ok, message=tostring(message), callbacks=callbacks, forbidden=forbidden}
            end
            function run_same_closure_protocol()
              local markers, saves = 0, 0
              local storage, callbacks = {}, {events={}}
              local function inventory(stack_capacity)
                local counts = {}
                return {
                  insert=function(stack)
                    local existing=counts[stack.name] or 0
                    local accepted=math.min(stack.count, (stack_capacity or math.huge)-existing)
                    counts[stack.name]=existing+accepted
                    return accepted
                  end,
                  get_item_count=function(name) return counts[name] or 0 end,
                  get_contents=function() return counts end,
                  counts=counts,
                }
              end
              local function strict_entity(fields, on_energy)
                return setmetatable(fields, {
                  __index=function(target, key)
                    if key=="energy" then return 0 end
                    local result=rawget(target,key)
                    if result==nil then error("unknown LuaEntity field read: "..key) end
                    return result
                  end,
                  __newindex=function(target,key,value)
                    if key=="energy" then
                      if on_energy then on_energy(target,value) end
                      return
                    end
                    error("unknown LuaEntity field write: "..key)
                  end,
                })
              end
              local function force(index)
                local queued,current={},nil
                local value=setmetatable({index=index, technologies={}, recipes={}, research_progress=0},{
                  __index=function(target,key)
                    if key=="research_queue" then return queued end
                    if key=="current_research" then return current end
                    local result=rawget(target,key)
                    if result==nil then error("unknown LuaForce field read: "..key) end
                    return result
                  end,
                  __newindex=function(target,key,value)
                    if key=="research_queue" then queued=value or {};current=queued[1]
                    elseif key=="current_research" then current=value
                    elseif key=="add_research" then rawset(target,key,value)
                    else error("unknown LuaForce field write: "..key) end
                  end,
                })
                local function technology(name, researched, level)
                  local row={valid=true,name=name,force=value,researched=researched or false,level=level or 1,enabled=true}
                  value.technologies[name]=row
                  return row
                end
                technology("burner-mechanics",false); technology("automation-science-pack",false)
                for _,name in ipairs({"fuel-processing","sand-processing","electricity","electronics","glass-processing","electric-lab"}) do technology(name,false) end
                for _,name in ipairs({"logistic-science-pack","chemical-science-pack","production-science-pack"}) do technology(name,false) end
                technology("recipe-prod-research_electric_engine-1",false,1)
                value.recipes["burner-lab"]={valid=true,name="burner-lab",enabled=false}
                value.recipes["lab"]={valid=true,name="lab",enabled=false}
                value.recipes["electric-engine-unit"]={valid=true,name="electric-engine-unit",productivity_bonus=0}
                value.add_research=function(row) value.research_queue={row}; return true end
                return value
              end
              local player=force(1)
              local surface={}
              local electric_lab_creations, bootstrap_crafts, physical_crafts=0,{},0
              function surface.find_entities_filtered() return {} end
              function surface.create_entity(spec)
                if spec.name=="burner-lab" or spec.name=="lab" then
                  if spec.name=="lab" then
                    electric_lab_creations=electric_lab_creations+1
                    assert(electric_lab_creations==1,"successor tried to place a lab over the source lab")
                  end
                  local input,fuel=inventory(200),inventory()
                  return strict_entity({valid=true,active=true,get_inventory=function(slot) assert(slot==1);return input end,get_fuel_inventory=function()return fuel end})
                end
                if spec.name=="stone-furnace" then
                  local input,output,fuel=inventory(),inventory(),inventory()
                  local entity={valid=true}
                  entity.get_inventory=function(slot) if slot==3 then return input elseif slot==4 then return output end error("unexpected furnace slot") end
                  entity.get_fuel_inventory=function()return fuel end
                  return strict_entity(entity,function(_,value)
                      if input.get_item_count("iron-ore")==10 and output.get_item_count("iron-plate")==0 then
                        input.counts["iron-ore"]=0;output.counts["iron-plate"]=10;bootstrap_crafts.iron=10
                        player.technologies["burner-mechanics"].researched=true;player.recipes["burner-lab"].enabled=true
                      end
                    end)
                end
                if spec.name=="burner-assembling-machine" then
                  local input,output,fuel=inventory(),inventory(),inventory()
                  local entity={valid=true}
                  entity.get_inventory=function(slot) if slot==3 then return input elseif slot==4 then return output end error("unexpected burner assembler slot") end
                  entity.get_fuel_inventory=function()return fuel end
                  entity.set_recipe=function(name) assert(name=="burner-lab");return {} end
                  entity.get_recipe=function() return {name="burner-lab"} end
                  return strict_entity(entity,function(_,value)
                      if input.get_item_count("motor")==10 and input.get_item_count("copper-plate")==10
                          and input.get_item_count("stone-brick")==5 and output.get_item_count("burner-lab")==0 then
                        input.counts["motor"],input.counts["copper-plate"],input.counts["stone-brick"]=0,0,0
                        output.counts["burner-lab"]=1;bootstrap_crafts.burner_lab=1
                        player.technologies["automation-science-pack"].researched=true
                      end
                    end)
                end
                assert(spec.name=="assembling-machine-2")
                local input,output=inventory(),inventory()
                local fluids={}
                local entity={valid=true,status="assembling"}
                entity.get_inventory=function(slot) if slot==3 then return input elseif slot==4 then return output end error("unexpected assembler slot") end
                entity.get_module_inventory=function() return nil end
                entity.set_recipe=function(name) assert(name=="electric-engine-unit");return {} end
                entity.get_recipe=function() return {name="electric-engine-unit"} end
                entity.get_fluid_count=function(name) return fluids[name] or 0 end
                entity.get_fluid_contents=function() return fluids end
                entity.get_fluid_capacity=function(index) assert(index==1);return 160 end
                entity.insert_fluid=function(stack)
                  assert(stack.name=="lubricant" and type(stack.amount)=="number" and stack.amount>0,"unexpected LuaEntity.insert_fluid input")
                  local admitted=math.min(stack.amount,160-(fluids[stack.name] or 0))
                  fluids[stack.name]=(fluids[stack.name] or 0)+admitted
                  return admitted
                end
                local pending, delay, batch_crafts=0,0,0
                return strict_entity(entity,function(_,value)
                  if batch_crafts==10 and pending==0 and input.get_item_count("steel-plate")>=20 then batch_crafts=0 end
                  if input.get_item_count("steel-plate")>=2 and input.get_item_count("electronic-circuit")>=4
                      and input.get_item_count("electric-motor")>=2 and (fluids["lubricant"] or 0)>=40 then
                    input.counts["steel-plate"]=input.counts["steel-plate"]-2
                    input.counts["electronic-circuit"]=input.counts["electronic-circuit"]-4
                    input.counts["electric-motor"]=input.counts["electric-motor"]-2
                    fluids["lubricant"]=fluids["lubricant"]-40
                    if fluids["lubricant"]==0 then fluids["lubricant"]=nil end
                    batch_crafts,physical_crafts=batch_crafts+1,physical_crafts+1
                    local amount=player.recipes["electric-engine-unit"].productivity_bonus==0 and 10 or 11
                    if batch_crafts<10 then output.counts["electric-engine-unit"]=(output.counts["electric-engine-unit"] or 0)+1
                    else pending,delay=amount-(batch_crafts-1),1 end
                  elseif pending>0 then
                    if delay>0 then delay=delay-1 else
                      output.counts["electric-engine-unit"]=output.counts["electric-engine-unit"]+pending
                      pending=0
                    end
                  end
                end)
              end
              local game={tick=0,forces={player=player,[1]=player},surfaces={[1]=surface}}
              function game.create_force()
                local paused=force(2);game.forces[2]=paused;return paused
              end
              function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
              local function environment(stage, active, target_callbacks)
                local env={
                  script={active_mods=active,on_init=function(fn)target_callbacks.init=fn end,on_load=function(fn)target_callbacks.load=fn end,
                    on_configuration_changed=function(fn)target_callbacks.configuration=fn end,on_event=function(event,fn)target_callbacks.events[event]=fn end},
                  defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1,fuel=2,crafter_input=3,crafter_output=4}},
                  game=game,storage=storage,mods=active,helpers={table_to_json=function()return "{}" end},log=function(value)
                    if value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ") then markers=markers+1
                    else assert(value:match("^%[MIR5_AAI_FLUID%] ")) end
                  end,
                }
                env.require=function(name)
                  if name=="__mir-fixture-mir5-aai-parity-native__/fixture_control" then return assert(loadfile(fixture.."/shared/control.lua","t",env))() end
                  if name=="__mir-fixture-mir5-aai-parity-native__/catalogue" then return assert(loadfile(fixture.."/shared/catalogue.lua","t",env))() end
                  if name=="__mir-fixture-mir5-aai-parity-native__/published-4.7/catalogue" then return assert(loadfile(fixture.."/published-4.7/catalogue.lua","t",env))() end
                  if name=="__mir-fixture-mir5-aai-parity-native__/mir5/catalogue" then return assert(loadfile(fixture.."/mir5/catalogue.lua","t",env))() end
                  error("unexpected module: "..tostring(name))
                end
                env._G=env;setmetatable(env,{__index=_G})
                local ok,message=pcall(function()assert(loadfile(fixture.."/"..stage.."/control.lua","t",env))()end)
                assert(ok,message)
              end
              local published={base="2.1.23",["aai-industry"]="0.7.5",["more-infinite-research"]="4.7.21003",["mir-fixture-mir5-aai-parity-native"]="0.1.0"}
              environment("published-4.7",published,callbacks)
              assert(pcall(callbacks.init))
              assert(pcall(callbacks.events[2]))
              assert(storage.mir5_aai_parity_native.phase=="bootstrap-burner-lab")
              assert(player.technologies["burner-mechanics"].researched==true and player.recipes["burner-lab"].enabled==true)
              assert(pcall(callbacks.events[2]))
              assert(storage.mir5_aai_parity_native.phase=="aai-progression")
              assert(player.technologies["automation-science-pack"].researched==true)
              assert(bootstrap_crafts.iron==10 and bootstrap_crafts.burner_lab==1)
              assert(pcall(callbacks.events[2]))
              for _,name in ipairs({"fuel-processing","sand-processing","electricity","electronics","glass-processing","electric-lab"}) do
                assert(player.current_research and player.current_research.name==name)
                player.technologies[name].researched=true;player.current_research=nil;player.research_queue={}
                assert(pcall(callbacks.events[1],{by_script=false,research=player.technologies[name]}))
                if name=="electric-lab" then player.recipes.lab.enabled=true end
                assert(pcall(callbacks.events[2]))
              end
              assert(pcall(callbacks.events[2]))
              assert(storage.mir5_aai_parity_native.phase=="physical-before",
                "empty inputs were mistaken for the last completed craft")
              assert(player.current_research==nil)
              for _=1,16 do
                assert(pcall(callbacks.events[2]))
                if player.current_research then break end
              end
              assert(player.current_research and player.current_research.name=="recipe-prod-research_electric_engine-1")
              assert(physical_crafts==10)
              local owner=player.technologies["recipe-prod-research_electric_engine-1"]
              owner.level=2;player.recipes["electric-engine-unit"].productivity_bonus=.1;player.current_research=nil;player.research_queue={}
              assert(pcall(callbacks.events[1],{by_script=false,research=owner}))
              for _=1,16 do
                assert(pcall(callbacks.events[2]))
                if storage.mir5_aai_parity_native.phase=="source-complete" then break end
              end
              local state=storage.mir5_aai_parity_native
              assert(state.phase=="source-complete" and physical_crafts==20)
              assert(state.production.fluid_target==400 and state.production.fluid_provided==400)
              assert(state.burner_lab.active==false and state.electric_lab.active==false,
                "published queued progress was left under a powered active lab")
              local source={phase=state.phase,aai=state.aai_finished,mir=state.mir_labs,before=state.before_output,after=state.after_output,queue=player.research_progress,saves=saves,markers=markers}
              local successor={events={}}
              local current={base="2.1.23",["aai-industry"]="0.7.5",["more-infinite-research"]="5.0.21000",["mir-fixture-mir5-aai-parity-native"]="0.2.0"}
              environment("mir5",current,successor)
              assert(pcall(successor.configuration))
              owner.level=3;player.recipes["electric-engine-unit"].productivity_bonus=.2;player.current_research=nil;player.research_queue={}
              assert(pcall(successor.events[1],{by_script=false,research=owner}))
              assert(pcall(successor.events[2]));assert(pcall(successor.load));assert(pcall(successor.events[2]))
              return {source=source,phase=state.phase,successor_labs=state.successor_labs,saves=saves,markers=markers,
                bootstrap_iron=bootstrap_crafts.iron,bootstrap_burner_lab=bootstrap_crafts.burner_lab}
            end
            '''
        )

    @staticmethod
    def mods(stage, space=False):
        data = {
            "base": "2.1.23",
            "aai-industry": "0.7.5",
            "more-infinite-research": "4.7.21003" if stage == "published-4.7" else "5.0.21000",
            "mir-fixture-mir5-aai-parity-native": "0.1.0" if stage == "published-4.7" else "0.2.0",
        }
        if space:
            data.update({name: "2.1.23" for name in ("elevated-rails", "quality", "recycler", "space-age")})
        return data

    def test_stage_infos_are_exact_and_only_define_same_closure_stages(self):
        for stage, fixture_version, mir_version in (("published-4.7", "0.1.0", "4.7.21003"), ("mir5", "0.2.0", "5.0.21000")):
            info = json.loads((FIXTURE / stage / "info.json").read_text(encoding="utf-8"))
            with self.subTest(stage=stage):
                self.assertEqual(("mir-fixture-mir5-aai-parity-native", fixture_version, "2.1"),
                                 (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual("MIR maintainers", info["author"])
                self.assertIn("aai-industry = 0.7.5", info["dependencies"])
                self.assertIn(f"more-infinite-research = {mir_version}", info["dependencies"])
                self.assertIn("? space-age = 2.1.23", info["dependencies"])
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        self.assertIn("does not claim a Base-to-Space-Age migration", readme)
        self.assertIn("two cold reloads", readme)

    def test_data_guard_accelerates_only_validated_aai_and_mir_workloads(self):
        for stage in ("published-4.7", "mir5"):
            for space in (False, True):
                raw_python = raw_fixture()
                if space:
                    raw_python["technology"]["recipe-prod-research_electric_engine-1"]["prerequisites"].append("electromagnetic-science-pack")
                    raw_python["technology"]["recipe-prod-research_electric_engine-1"]["unit"]["ingredients"].append(["electromagnetic-science-pack", 1])
                raw = lua(self.lua, raw_python)
                result = self.lua.eval("run_data")(stage, raw, lua(self.lua, self.mods(stage, space)))
                with self.subTest(stage=stage, space=space):
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])
                    for name in AAI:
                        self.assertEqual((1, 1), (actual["technology"][name]["unit"]["count"], actual["technology"][name]["unit"]["time"]))
                    owner = actual["technology"]["recipe-prod-research_electric_engine-1"]["unit"]
                    self.assertEqual((1, None, 1), (owner["count"], owner.get("count_formula"), owner["time"]))
                    self.assertTrue(actual["unrelated"]["preserved"])

    def test_data_guard_refuses_drift_without_partial_acceleration(self):
        opponents = {
            "aai-count": lambda raw: raw["technology"]["electronics"]["unit"].__setitem__("count", 31),
            "mir-effect": lambda raw: raw["technology"]["recipe-prod-research_electric_engine-1"]["effects"][0].__setitem__("change", 0.2),
            "recipe-fluid": lambda raw: raw["recipe"]["electric-engine-unit"]["ingredients"][0].__setitem__("amount", 39),
            "burner-trigger": lambda raw: raw["technology"]["burner-mechanics"]["research_trigger"].__setitem__("count", 9),
            "automation-trigger": lambda raw: raw["technology"]["automation-science-pack"]["research_trigger"].__setitem__("item", "iron-plate"),
            "burner-recipe": lambda raw: raw["recipe"]["burner-lab"]["ingredients"][0].__setitem__("amount", 9),
            "burner-recipe-category": lambda raw: raw["recipe"]["burner-lab"]["categories"].__setitem__(0, "smelting"),
            "iron-plate-recipe": lambda raw: raw["recipe"]["iron-plate"].__setitem__("energy_required", 4),
            "automation-stack-size": lambda raw: raw["item"]["automation-science-pack"].__setitem__("stack_size", 199),
            "wrong-closure": lambda raw: raw,
        }
        for name, mutate in opponents.items():
            with self.subTest(opponent=name):
                value = raw_fixture()
                mutate(value)
                before = deepcopy(value)
                mods = self.mods("published-4.7")
                if name == "wrong-closure":
                    mods["aai-industry"] = "0.7.4"
                result = self.lua.eval("run_data")("published-4.7", lua(self.lua, value), lua(self.lua, mods))
                self.assertFalse(result["ok"])
                actual = py(result["raw"])
                for technology in AAI:
                    self.assertEqual(before["technology"][technology]["unit"], actual["technology"][technology]["unit"])
                unit = actual["technology"]["recipe-prod-research_electric_engine-1"]["unit"]
                self.assertEqual((None, "8000*2^(L-1)", 60), (unit.get("count"), unit["count_formula"], unit["time"]))

    def test_control_registers_real_stage_callbacks_without_runtime_parse_reads(self):
        for stage in ("published-4.7", "mir5"):
            result = self.lua.eval("parse_control")(stage, lua(self.lua, self.mods(stage)))
            with self.subTest(stage=stage):
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                if stage == "published-4.7":
                    self.assertIsNotNone(result["callbacks"]["init"])
                else:
                    self.assertIsNotNone(result["callbacks"]["configuration"])

    def test_runtime_contract_keeps_aai_and_mir_lab_claims_distinct_from_setup(self):
        source = (FIXTURE / "shared" / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local AAI_PLAN = {"fuel-processing", "sand-processing", "electricity", "electronics", "glass-processing", "electric-lab"}', source)
        self.assertIn('event.by_script ~= false', source)
        self.assertIn('source_setup_external_science_prerequisites=true', source)
        self.assertIn('phase="bootstrap-iron"', source)
        self.assertIn('craft-item trigger did not complete after native iron production', source)
        self.assertIn('craft-item trigger did not complete after native burner-lab production', source)
        self.assertIn('local AAI_PACKS = 32', source)
        self.assertIn('entity.insert_fluid{name="lubricant", amount=remaining}', source)
        self.assertIn('production.fluid_provided = production.fluid_provided + inserted', source)
        self.assertIn('physical lubricant contents remain after production', source)
        self.assertIn('entity.get_fluid_count("lubricant")', source)
        self.assertIn('entity.get_fluid_contents()', source)
        self.assertIn('entity.get_fluid_capacity(1)', source)
        self.assertNotIn('fluidbox', source)
        self.assertIn('defines.inventory.crafter_input', source)
        self.assertIn('defines.inventory.crafter_output', source)
        self.assertNotIn('assembling_machine_input', source)
        self.assertNotIn('assembling_machine_output', source)
        self.assertIn('state.aai_finished ~= #AAI_PLAN', source)
        self.assertIn('physical_before_output=state.before_output', source)
        self.assertIn('physical_after_output=state.after_output', source)
        self.assertNotIn('enable_all_prototypes', source)
        self.assertNotIn('technology(force, AAI_PLAN[state.aai_next]).researched = true', source)
        self.assertIn('game.server_save(SAVE)', source)
        self.assertIn('on_load_read_only=stage == "reload"', source)

    def test_runtime_protocol_uses_native_events_for_the_aai_chain_and_mir_levels(self):
        result = py(self.lua.eval("run_same_closure_protocol")())
        self.assertEqual(("source-complete", 6, 1, 10, 11, 0.42, 1, 1),
                         (result["source"]["phase"], result["source"]["aai"], result["source"]["mir"],
                          result["source"]["before"], result["source"]["after"], result["source"]["queue"],
                          result["source"]["saves"], result["source"]["markers"]))
        self.assertEqual(("successor-complete", 1, 2, 3),
                         (result["phase"], result["successor_labs"], result["saves"], result["markers"]))
        self.assertEqual((10, 1), (result["bootstrap_iron"], result["bootstrap_burner_lab"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    arguments = parser.parse_args()
    LUA_RUNTIME_DIR = arguments.lua_runtime_dir
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AaiParityNativeControls)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
