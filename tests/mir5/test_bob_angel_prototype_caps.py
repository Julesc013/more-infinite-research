'''Host controls for the private F200 Bob/Angel prototype-cap fixtures.'''
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/bob-angel-continuity"
ORACLE = ROOT / "spec/mir5/inventory/bob-angel-f200-472.json"
BASE_PROFILE = ROOT / "tests/mir5/profiles/bob-angel-f200-2077.json"
NAME = "mir-fixture-mir5-bob-angel-continuity"
CASES = {
    "cap125": ("prototype-cap125", "0.5.0", "percent-125", 1.25),
    "cap400": ("prototype-cap400", "0.6.0", "percent-400", 4),
}
FAMILIES = {
    "research_material_aluminium": ("angels-plate-aluminium", "angels-plate-aluminium-2"),
    "research_material_copper_tungsten": ("bob-copper-tungsten-alloy",),
    "research_material_gold": ("angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"),
    "research_material_tin": ("angels-plate-tin", "angels-plate-tin-2"),
    "research_material_titanium": ("angels-plate-titanium", "angels-plate-titanium-2"),
}


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
        raise AssertionError("cyclic fixture value")
    seen.add(id(value))
    keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        out = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        out = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value))
    return out


class BobAngelPrototypeCapsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        additions = json.loads(ORACLE.read_text(encoding="utf-8"))["profiles"][0]["published_output"]["data"]["additions"]
        cls.rows = [deepcopy(item["row"]) for item in additions
                    if item.get("name", "").startswith("recipe-prod-research_material_")]
        if len(cls.rows) != 10:
            raise AssertionError("independent BA oracle must have ten rows")
        for row in cls.rows:
            if row["name"].endswith("-4"):
                if row["max_level"] != 150:
                    raise AssertionError("published tail changed")
                row["max_level"] = "infinite"

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
          function cap_settings(path)
            local data={raw={["double-setting"]={},["int-setting"]={},["string-setting"]={},["bool-setting"]={}}}
            local families={"research_material_aluminium","research_material_copper_tungsten","research_material_gold","research_material_tin","research_material_titanium"}
            for _,family in ipairs(families)do
              data.raw["double-setting"]["ips-effect-per-level-"..family]={setting_type="startup",default_value=2}
              data.raw["int-setting"]["ips-max-level-"..family]={setting_type="startup",minimum_value=0,default_value=0}
            end
            data.raw["string-setting"]["mir-settings-profile-import"]={setting_type="startup",default_value=""}
            data.raw["string-setting"]["mir-prototype-productivity-cap"]={setting_type="startup",default_value="engine-default"}
            data.raw["bool-setting"]["mir-productivity-cap-self-recycling-only"]={setting_type="startup",default_value=false}
            local env={data=data};env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local c,m=loadfile(path,"t",env);assert(c,m);local ok,result=pcall(c)
            return {ok=ok,message=tostring(result),raw=data.raw}
          end
          function cap_data(path, rows, cap, bad)
            local recipes={}
            local names={"angels-plate-aluminium","angels-plate-aluminium-2","bob-copper-tungsten-alloy","angels-plate-gold","angels-plate-gold-2","angels-wire-gold-2","angels-plate-tin","angels-plate-tin-2","angels-plate-titanium","angels-plate-titanium-2"}
            for _,name in ipairs(names)do recipes[name]={maximum_productivity=cap}end
            if bad then recipes[bad].maximum_productivity=3 end
            local env={mods={base="2.0.77",["more-infinite-research"]="5.0.20000"},data={raw={technology=rows,recipe=recipes}}}
            env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
            local c,m=loadfile(path,"t",env);assert(c,m);local ok,result=pcall(c)
            return {ok=ok,message=tostring(result),rows=rows}
          end
          function parse_cap_control(path, version)
            local callbacks, reads={events={}},{}
            local env={script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-bob-angel-continuity"]=version},
              on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
            env._G=env;setmetatable(env,{__index=function(_,key)if key=="game"or key=="storage"or key=="prototypes"then reads[key]=(reads[key]or 0)+1 end;return _G[key]end})
            local c,m=loadfile(path,"t",env);assert(c,m);local ok,result=pcall(c)
            return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
          end
          function cap_fixture_flow(path125,path400,opponent)
            local F={
              {"research_material_aluminium",{"angels-plate-aluminium","angels-plate-aluminium-2"}},
              {"research_material_copper_tungsten",{"bob-copper-tungsten-alloy"}},
              {"research_material_gold",{"angels-plate-gold","angels-plate-gold-2","angels-wire-gold-2"}},
              {"research_material_tin",{"angels-plate-tin","angels-plate-tin-2"}},
              {"research_material_titanium",{"angels-plate-titanium","angels-plate-titanium-2"}},
            }
            local effect=.019999999552965164
            local prototypes={recipe={}}
            for _,family in ipairs(F)do for _,name in ipairs(family[2])do prototypes.recipe[name]={maximum_productivity=1.25}end end
            local function force(name,index)
              local value={name=name,index=index,valid=true,technologies={},recipes={},research_queue={},research_progress=0}
              function value.enable_all_prototypes()end
              function value.get_spawn_position(_)return {0,0}end
              function value.add_research(tech)
                if type(tech)=="string"then tech=value.technologies[tech]end
                if not tech or value.current_research then return false end
                value.research_queue={tech};value.current_research=tech;return true
              end
              for _,family in ipairs(F)do
                local key,recipes=family[1],family[2]
                for _,recipe in ipairs(recipes)do value.recipes[recipe]={productivity_bonus=0}end
                for _,stage in ipairs({{key.."-1",1,3},{key.."-4",4,4294967295}})do
                  local effects={};for i,recipe in ipairs(recipes)do effects[i]={type="change-recipe-productivity",recipe=recipe,change=effect}end
                  value.technologies["recipe-prod-"..stage[1]]={name="recipe-prod-"..stage[1],level=stage[2],researched=false,enabled=true,visible_when_disabled=false,force=value,
                    prototype={max_level=stage[3],effects=effects},prerequisites={{name="external",research_recursive=function()end}}}
                end
              end
              value.technologies["mir5-ba-continuity-queue-probe"]={name="mir5-ba-continuity-queue-probe",level=1,researched=false,enabled=true,visible_when_disabled=false,force=value,prototype={max_level=1,effects={}},prerequisites={{name="external",research_recursive=function()end}}}
              function value.reset_technology_effects()
                for _,technology in pairs(value.technologies)do
                  technology.enabled,technology.visible_when_disabled=true,false
                end
                for _,recipe in pairs(value.recipes)do recipe.productivity_bonus=0 end
                for _,family in ipairs(F)do
                  local early=value.technologies["recipe-prod-"..family[1].."-1"];local tail=value.technologies["recipe-prod-"..family[1].."-4"]
                  local e=early.researched and early.level or early.level-1;local t=tail.level-4
                  for _,entry in ipairs(early.prototype.effects)do value.recipes[entry.recipe].productivity_bonus=value.recipes[entry.recipe].productivity_bonus+e*entry.change end
                  for _,entry in ipairs(tail.prototype.effects)do value.recipes[entry.recipe].productivity_bonus=value.recipes[entry.recipe].productivity_bonus+t*entry.change end
                end
              end
              setmetatable(value,{__newindex=function(object,key,item)
                if key=="research_queue_enabled"then error("removed F200 LuaForce property")end
                rawset(object,key,item)
              end})
              return value
            end
            local player,foreign,saves,markers=force("player",1),nil,0,0
            local inventory={items={}};function inventory.insert(row)inventory.items[row.name]=(inventory.items[row.name]or 0)+row.count;return row.count end;function inventory.get_item_count(name)return inventory.items[name]or 0 end
            local lab={valid=true,energy=0};function lab.get_inventory(index)assert(index==1);return inventory end
            local game={tick=0,forces={player=player,[1]=player},surfaces={}}
            function game.create_force(name)foreign=force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign end
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab"and row.force==player);return lab end}
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local function startup(cap,recycling)
              local rows={["mir-prototype-productivity-cap"]={value=cap},["mir-productivity-cap-self-recycling-only"]={value=recycling},["mir-settings-profile-import"]={value=""}}
              for _,family in ipairs(F)do rows["ips-effect-per-level-"..family[1]]={value=2};rows["ips-max-level-"..family[1]]={value=0}end
              return rows
            end
            local function load_control(path,version,cap,recycling)
              local callbacks={events={}}
              local env={script={active_mods={base="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-bob-angel-continuity"]=version},
                  on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},
                defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage=storage,prototypes=prototypes,settings={startup=startup(cap,recycling)},
                helpers={table_to_json=function(row)assert(row.status=="passed");return "{}"end},log=function(row)assert(row:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
              env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
              local c,m=loadfile(path,"t",env);assert(c,m);local ok,result=pcall(c);return ok and callbacks or nil,tostring(result)
            end
            local function callback(callbacks,kind,event)
              local f=kind=="tick"and callbacks.events[1]or(kind=="finished"and callbacks.events[2]or callbacks[kind])
              if type(f)~="function"then return false,"callback missing"end
              local ok,result=pcall(f,event);return ok,tostring(result)
            end
            local function complete(callbacks,disable)
              local state=storage.mir5_bob_angel_continuity
              for _,name in ipairs(state.plan)do
                local tech=player.current_research;assert(tech and tech.name==name and #player.research_queue==1)
                tech.level=tech.level+1;tech.researched=false
                for _,entry in ipairs(tech.prototype.effects)do player.recipes[entry.recipe].productivity_bonus=player.recipes[entry.recipe].productivity_bonus+entry.change end
                local packs=tech.name:match("_tin") and {"automation-science-pack","utility-science-pack"}
                  or {"automation-science-pack","logistic-science-pack","utility-science-pack"}
                for _,pack in ipairs(packs)do inventory.items[pack]=inventory.items[pack]-1 end
                if disable then tech.enabled,tech.visible_when_disabled=false,true end
                local ok,message=callback(callbacks,"finished",{research=tech});if not ok then return false,message end
                player.current_research=nil;player.research_queue={}
                ok,message=callback(callbacks,"tick");if not ok then return false,message end
              end
              return true,""
            end
            local one,message=load_control(path125,"0.5.0","percent-125",false);if not one then return {ok=false,message=message}end
            local ok,message=callback(one,"init");if not ok then return {ok=false,message=message}end
            ok,message=complete(one,opponent~="skip125");if not ok then return {ok=false,message=message}end
            local state=storage.mir5_bob_angel_continuity;local saved={phase=state.phase,completed=state.completed,events=state.events,queue_count=state.queue_count}
            ok,message=callback(one,"load");if not ok then return {ok=false,message=message}end
            local read_only=state.phase==saved.phase and state.completed==saved.completed and state.events==saved.events and state.queue_count==saved.queue_count
            ok,message=callback(one,"tick");if not ok then return {ok=false,message=message}end
            if opponent=="foreign"then foreign.research_progress=.41 end
            for _,family in ipairs(F)do for _,name in ipairs(family[2])do prototypes.recipe[name]={maximum_productivity=4}end end
            if opponent~="skip400"then for _,family in ipairs(F)do local tail=player.technologies["recipe-prod-"..family[1].."-4"];tail.enabled,tail.visible_when_disabled=true,false end end
            local two,message=load_control(path400,"0.6.0","percent-400",false);if not two then return {ok=false,message=message}end
            ok,message=callback(two,"changed");if not ok then return {ok=false,message=message}end
            ok,message=complete(two,false);if not ok then return {ok=false,message=message}end
            state=storage.mir5_bob_angel_continuity;saved={phase=state.phase,completed=state.completed,events=state.events,queue_count=state.queue_count}
            ok,message=callback(two,"load");if not ok then return {ok=false,message=message}end
            read_only=read_only and state.phase==saved.phase and state.completed==saved.completed and state.events==saved.events and state.queue_count==saved.queue_count
            ok,message=callback(two,"tick");if not ok then return {ok=false,message=message}end
            local tail=player.technologies["recipe-prod-research_material_aluminium-4"]
            return {ok=true,message="",phase=state.phase,completed=state.completed,events=state.events,queue_count=state.queue_count,tail=tail.level,enabled=tail.enabled,visible=tail.visible_when_disabled,bonus=player.recipes["angels-plate-aluminium"].productivity_bonus,foreign=foreign.technologies["recipe-prod-research_material_aluminium-4"].enabled,progress=foreign.research_progress,markers=markers,saves=saves,read_only=read_only}
          end
        ''')

    def table_rows(self):
        return self.lua.table_from({row["name"]: lua_value(self.lua, deepcopy(row)) for row in self.rows})

    def test_profiles_and_fixture_identities_are_normal_f200_mir5_inputs(self):
        base = json.loads(BASE_PROFILE.read_text(encoding="utf-8"))
        for key, (directory, version, setting, _) in CASES.items():
            with self.subTest(case=key):
                profile = json.loads((ROOT / f"tests/mir5/profiles/bob-angel-prototype-{key}-f200.json").read_text(encoding="utf-8"))
                self.assertEqual(profile["target"], "f200")
                self.assertEqual(profile["engine"], base["engine"])
                self.assertEqual(profile["archive_sha256"], base["archive_sha256"])
                self.assertEqual(profile["mods"][:len(base["mods"])], base["mods"])
                self.assertEqual(profile["mods"][-2], {"name": "more-infinite-research", "version": "5.0.20000", "enabled": True})
                self.assertEqual(profile["mods"][-1], {"name": NAME, "version": version, "enabled": True})
                self.assertNotIn("space-age", [entry["name"] for entry in profile["mods"]])
                self.assertNotIn("bobtech", [entry["name"] for entry in profile["mods"]])
                info = json.loads((FIXTURE / directory / "info.json").read_text(encoding="utf-8"))
                self.assertEqual((info["name"], info["version"], info["factorio_version"]), (NAME, version, "2.0"))
                self.assertEqual(info["dependencies"], ["base >= 2.0.77", "more-infinite-research = 5.0.20000"])

    def test_settings_and_atomic_data_preflight_pin_all_ten_native_recipe_caps(self):
        for key, (directory, version, setting, cap) in CASES.items():
            with self.subTest(case=key):
                values = self.lua.eval("cap_settings")(str((FIXTURE / directory / "settings-updates.lua")))
                self.assertTrue(values["ok"], values["message"])
                self.assertEqual(setting, values["raw"]["string-setting"]["mir-prototype-productivity-cap"]["default_value"])
                for family in FAMILIES:
                    self.assertEqual(2, values["raw"]["double-setting"][f"ips-effect-per-level-{family}"]["default_value"])
                    self.assertEqual(0, values["raw"]["int-setting"][f"ips-max-level-{family}"]["default_value"])
                good = self.lua.eval("cap_data")(str((FIXTURE / directory / "data-final-fixes.lua")), self.table_rows(), cap, None)
                self.assertTrue(good["ok"], good["message"])
                for expected in self.rows:
                    actual = plain(good["rows"][expected["name"]])
                    self.assertEqual(("1", 1), (actual["unit"]["count_formula"], actual["unit"]["time"]))
                    actual["unit"]["count_formula"], actual["unit"]["time"] = expected["unit"]["count_formula"], expected["unit"]["time"]
                    self.assertEqual(actual, expected)
                bad = self.lua.eval("cap_data")(str((FIXTURE / directory / "data-final-fixes.lua")), self.table_rows(), cap, "angels-plate-titanium-2")
                self.assertFalse(bad["ok"])
                self.assertIn("named recipe productivity cap changed", bad["message"])
                unit = bad["rows"]["recipe-prod-research_material_aluminium-1"]["unit"]
                self.assertEqual(("200*2^(L-1)", 30), (unit["count_formula"], unit["time"]))

    def test_controls_defer_native_reads_until_game_callbacks(self):
        for key, (directory, version, _, _) in CASES.items():
            with self.subTest(case=key):
                result = self.lua.eval("parse_cap_control")(str(FIXTURE / directory / "control.lua"), version)
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["reads"]["game"])
                self.assertIsNone(result["reads"]["storage"])
                self.assertIsNone(result["reads"]["prototypes"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                source = (FIXTURE / directory / "control.lua").read_text(encoding="utf-8")
                self.assertIn("prototypes.recipe[name]", source)
                self.assertNotIn("research_queue_enabled = true", source)
                self.assertIn("native_recipe_bonus_is_observed_separately_from_prototype_cap", source)
                self.assertIn("game.server_save(SAVE)", source)
                self.assertNotIn("require(", source)

    def test_cap125_to_cap400_real_tail_flow_rejects_missing_cap_or_foreign_transitions(self):
        flow = self.lua.eval("cap_fixture_flow")
        normal = flow(str(FIXTURE / "prototype-cap125/control.lua"), str(FIXTURE / "prototype-cap400/control.lua"), "")
        self.assertTrue(normal["ok"], normal["message"])
        self.assertEqual(("prototype-cap400-saved", 5, 5, 5), (normal["phase"], normal["completed"], normal["events"], normal["queue_count"]))
        self.assertEqual(65, normal["tail"])
        self.assertTrue(normal["enabled"])
        self.assertFalse(normal["visible"])
        self.assertFalse(normal["foreign"])
        self.assertAlmostEqual(.42, normal["progress"])
        self.assertTrue(normal["read_only"])
        self.assertEqual((4, 2), (normal["markers"], normal["saves"]))
        self.assertGreaterEqual(normal["bonus"], 1.25)
        self.assertLessEqual(normal["bonus"], 1.28)
        for opponent, prefix in (("skip125", "[mir5-bob-angel-prototype-cap125]"), ("skip400", "[mir5-bob-angel-prototype-cap400]"), ("foreign", "[mir5-bob-angel-prototype-cap400]")):
            with self.subTest(opponent=opponent):
                failed = flow(str(FIXTURE / "prototype-cap125/control.lua"), str(FIXTURE / "prototype-cap400/control.lua"), opponent)
                self.assertFalse(failed["ok"])
                self.assertIn(prefix, failed["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelPrototypeCapsTests))
    sys.exit(0 if result.wasSuccessful() else 1)
