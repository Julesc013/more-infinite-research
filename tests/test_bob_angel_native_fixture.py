"""Host controls for the private F200 Bob/Angel continuity fixture.

These checks execute fixture data/control code with a bounded mock. They never
launch Factorio or qualify the native source/save/lab scenarios.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/bob-angel-continuity"
ORACLE = ROOT / "spec/inventory/bob-angel-f200-472.json"
BASE_PROFILE = ROOT / "tests/profiles/bob-angel-f200-2077.json"
PROFILE_PATHS = {
    "published": ROOT / "tests/profiles/bob-angel-continuity-published-4.7-f200.json",
    "published_reset": ROOT / "tests/profiles/bob-angel-published-reset-control-f200.json",
    "mir5": ROOT / "tests/profiles/bob-angel-continuity-f200.json",
    "effect3": ROOT / "tests/profiles/bob-angel-continuity-effect3-cap2-f200.json",
    "effect1": ROOT / "tests/profiles/bob-angel-continuity-effect1-cap40-f200.json",
}
FIXTURE_NAME = "mir-fixture-mir5-bob-angel-continuity"
DEFAULT_CAP = ROOT / "tests/fixtures/bob-angel-default-cap"
DEFAULT_CAP_PROFILE = ROOT / "tests/profiles/bob-angel-default-cap-f200-2077.json"
DEFAULT_CAP_NAME = "mir-fixture-mir5-bob-angel-default-cap"


def plain(value, seen=None):
    if not hasattr(value, "items"):
        return value
    seen = set() if seen is None else seen
    if id(value) in seen:
        raise AssertionError("fixture table is cyclic")
    seen.add(id(value))
    entries = list(value.items())
    keys = [key for key, _ in entries]
    if keys and all(isinstance(key, int) and key >= 1 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        out = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else:
        out = {key: plain(item, seen) for key, item in entries}
    seen.remove(id(value))
    return out


def lua_value(lua, value):
    if isinstance(value, dict):
        result = lua.table()
        for key, item in value.items():
            result[key] = lua_value(lua, item)
        return result
    if isinstance(value, (list, tuple)):
        result = lua.table()
        for index, item in enumerate(value, 1):
            result[index] = lua_value(lua, item)
        return result
    return value


class BobAngelNativeFixtureTests(unittest.TestCase):
    def default_cap_cases(self):
        return self.lua.execute("return assert(loadfile(...))()", (DEFAULT_CAP / "cases.lua").as_posix())

    def default_cap_raw(self):
        facts = json.loads((ROOT / "tests/fixtures/bob-angel-f200-captured-facts.json").read_bytes())
        recipes = {route["recipe"]: {"enabled": False, "allow_productivity": True,
                   "ingredients": deepcopy(route["ingredients"]), "results": deepcopy(route["results"])}
                   for family in facts["selected_families"] for route in family["routes"]}
        recipes["unrelated-recipe"] = {"maximum_productivity": 2, "keep": "foreign"}
        return lua_value(self.lua, {"recipe": recipes, "technology": {
            row["name"]: deepcopy(row) for row in self.candidate_rows}})

    def run_default_cap_data(self, phase, raw, *, wrong_version=False):
        self.lua.execute(r'''
          function run_default_cap_data(path, raw, cases, wrong_version)
            local mods={base="2.0.77",["more-infinite-research"]="5.0.20000",
              ["mir-fixture-mir5-bob-angel-default-cap"]="0.1.0"}
            if wrong_version then mods["more-infinite-research"]="4.7.20003" end
            local env={mods=mods,data={raw=raw,extend=function()error("fixture published prototypes")end}}
            env.require=function(name)
              assert(name=="__mir-fixture-mir5-bob-angel-default-cap__/cases");return cases
            end
            setmetatable(env,{__index=_G})
            local ok,message=pcall(function()assert(loadfile(path,"t",env))()end)
            return {ok=ok,message=tostring(message)}
          end
        ''')
        return self.lua.globals().run_default_cap_data(
            (DEFAULT_CAP / phase).as_posix(), raw, self.default_cap_cases(), wrong_version)

    def test_default_cap_startup_selection_preserves_exact_upstream_inputs(self):
        profile = json.loads(DEFAULT_CAP_PROFILE.read_bytes())
        base = json.loads(BASE_PROFILE.read_bytes())
        info = json.loads((DEFAULT_CAP / "info.json").read_bytes())
        self.assertEqual(profile["engine"], base["engine"])
        self.assertEqual(profile["engine"]["version"], "2.0.77")
        self.assertEqual(profile["archive_sha256"], base["archive_sha256"])
        self.assertEqual(profile["mods"], base["mods"] + [
            {"name": "more-infinite-research", "version": "5.0.20000", "enabled": True},
            {"name": DEFAULT_CAP_NAME, "version": "0.1.0", "enabled": True}])
        self.assertEqual(info["name"], DEFAULT_CAP_NAME)
        self.assertEqual(info["version"], "0.1.0")
        self.assertEqual(info["dependencies"], ["base = 2.0.77", "more-infinite-research = 5.0.20000"])
        self.assertEqual(profile["fixture"]["root"], DEFAULT_CAP.relative_to(ROOT).as_posix())
        self.assertEqual(set(profile["fixture"]["included_members"]),
                         {p.relative_to(DEFAULT_CAP).as_posix() for p in DEFAULT_CAP.rglob("*") if p.is_file()})
        facts = json.loads((ROOT / "tests/fixtures/bob-angel-f200-captured-facts.json").read_bytes())
        self.assertEqual(plain(self.default_cap_cases()), [
            {"key": family["key"], "recipes": [r["recipe"] for r in family["routes"]]}
            for family in facts["selected_families"]])
        self.assertEqual(profile["case"], "bob-angel-default-cap")
        self.assertEqual(profile["consumer_markers"], ["MIR5_F200_DEFAULT_CAP"])

    def test_default_cap_input_checks_the_complete_preimage_before_writing(self):
        raw = self.default_cap_raw()
        expected = plain(raw)
        for recipe in expected["recipe"].values():
            if recipe.get("keep") != "foreign":
                recipe["maximum_productivity"] = 3
        result = self.run_default_cap_data("data-updates.lua", raw)
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(plain(raw), expected)
        for opponent in ("missing-last", "cap-last", "version"):
            with self.subTest(opponent=opponent):
                raw = self.default_cap_raw()
                if opponent == "missing-last": raw["recipe"]["angels-plate-titanium-2"] = None
                if opponent == "cap-last": raw["recipe"]["angels-plate-titanium-2"]["maximum_productivity"] = 2
                before = plain(raw)
                result = self.run_default_cap_data("data-updates.lua", raw, wrong_version=opponent == "version")
                self.assertFalse(result["ok"])
                self.assertEqual(plain(raw), before)

    def test_default_cap_final_observer_rejects_missing_rows_or_changed_effects_without_writes(self):
        for opponent in (None, "cap", "missing-tail", "effect", "maximum", "version"):
            with self.subTest(opponent=opponent):
                raw = self.default_cap_raw()
                self.assertTrue(self.run_default_cap_data("data-updates.lua", raw)["ok"])
                tail = "recipe-prod-research_material_titanium-4"
                if opponent == "cap": raw["recipe"]["angels-plate-titanium-2"]["maximum_productivity"] = 2
                if opponent == "missing-tail": raw["technology"][tail] = None
                if opponent == "effect": raw["technology"][tail]["effects"][1]["change"] = .03
                if opponent == "maximum": raw["technology"][tail]["max_level"] = 150
                before = plain(raw)
                result = self.run_default_cap_data("data-final-fixes.lua", raw, wrong_version=opponent == "version")
                self.assertEqual(result["ok"], opponent is None, result["message"])
                self.assertEqual(plain(raw), before)

    def test_default_cap_init_is_read_only_and_rejects_native_state_drift(self):
        self.lua.execute(r'''
          function run_default_cap_init(path, cases, force, wrong_version)
            local function readonly(value)
              if type(value)~="table" then return value end
              return setmetatable({}, {
                __index=function(_,key)return readonly(value[key])end,
                __len=function()return #value end,
                __newindex=function()error("native state write")end,
                __pairs=function()error("whole native collection scan")end,
              })
            end
            local active={base="2.0.77",["more-infinite-research"]="5.0.20000",
              ["mir-fixture-mir5-bob-angel-default-cap"]="0.1.0"}
            if wrong_version then active.base="2.0.78" end
            local callback,payload,line,initialized
            local script={active_mods=readonly(active)}
            script.on_init=function(value)assert(callback==nil);callback=value end
            setmetatable(script,{__index=function()error("unexpected event registration")end})
            local env={script=script,helpers={table_to_json=function(value)payload=value;return "<fixture>"end},
              log=function(value)assert(line==nil);line=value end}
            env.require=function(name)
              assert(not initialized,"late fixture import")
              assert(name=="__mir-fixture-mir5-bob-angel-default-cap__/cases");return cases
            end
            setmetatable(env,{__index=function(_,key)
              if key=="storage" or key=="global" then error("saved-state access") end
              if key=="game" then error("parse-time game access") end
              return _G[key]
            end})
            local parsed,message=pcall(function()assert(loadfile(path,"t",env))()end)
            if not parsed then return {ok=false,phase="parse",message=tostring(message)} end
            assert(type(callback)=="function")
            env.game={forces={player=readonly(force)}};initialized=true
            local ok,message=pcall(callback)
            return {ok=ok,phase="init",message=tostring(message),payload=payload,line=line}
          end
        ''')
        facts = json.loads((ROOT / "tests/fixtures/bob-angel-f200-captured-facts.json").read_bytes())
        for opponent in (None, "version", "force", "missing-row", "level", "researched", "enabled",
                         "maximum", "effect", "target", "bonus"):
            with self.subTest(opponent=opponent):
                force = {"valid": True, "technologies": {}, "recipes": {}}
                for family in facts["selected_families"]:
                    for recipe in family["routes"]:
                        force["recipes"][recipe["recipe"]] = {"valid": True, "productivity_bonus": 0}
                for row in self.candidate_rows:
                    level = 4 if row["name"].endswith("-4") else 1
                    effects = deepcopy(row["effects"])
                    for effect in effects:
                        effect["change"] = 0.019999999552965164
                    force["technologies"][row["name"]] = {
                        "name": row["name"], "valid": True, "level": level, "researched": False, "enabled": True,
                        "prototype": {"max_level": 4294967295 if level == 4 else 3, "effects": effects}}
                tail = "recipe-prod-research_material_titanium-4"
                if opponent == "missing-row": del force["technologies"][tail]
                if opponent == "level": force["technologies"][tail]["level"] = 5
                if opponent == "researched": force["technologies"][tail]["researched"] = True
                if opponent == "enabled": force["technologies"][tail]["enabled"] = False
                if opponent == "maximum": force["technologies"][tail]["prototype"]["max_level"] = 150
                if opponent == "effect": force["technologies"][tail]["prototype"]["effects"][0]["change"] = .03
                if opponent == "target": force["technologies"][tail]["prototype"]["effects"][0]["recipe"] = "foreign"
                if opponent == "bonus": force["recipes"]["angels-plate-titanium-2"]["productivity_bonus"] = .02
                result = self.lua.globals().run_default_cap_init(
                    (DEFAULT_CAP / "control.lua").as_posix(), self.default_cap_cases(),
                    None if opponent == "force" else lua_value(self.lua, force), opponent == "version")
                self.assertEqual(result["phase"], "init", result["message"])
                self.assertEqual(result["ok"], opponent is None, result["message"])
                if opponent is None:
                    self.assertEqual(result["line"], "[MIR5_F200_DEFAULT_CAP] RESULT <fixture>")
                    self.assertEqual(plain(result["payload"]), {
                        "case": "bob-angel-default-cap", "stage": "init", "status": "passed",
                        "qualification": "representative-native-default-cap-startup-only",
                        "families": 5, "technologies": 10, "recipes": 10, "fresh_recipe_productivity_bonus": 0})
                else:
                    self.assertIsNone(result["payload"])

    @classmethod
    def setUpClass(cls):
        source = json.loads(ORACLE.read_text(encoding="utf-8"))
        additions = source["profiles"][0]["published_output"]["data"]["additions"]
        cls.published_rows = [deepcopy(item["row"]) for item in additions
                              if item.get("name", "").startswith("recipe-prod-research_material_")]
        if len(cls.published_rows) != 10:
            raise AssertionError("independent 4.7.2 Bob/Angel oracle does not contain ten material rows")
        cls.candidate_rows = deepcopy(cls.published_rows)
        for row in cls.candidate_rows:
            if row["name"].endswith("-4"):
                if row["max_level"] != 150:
                    raise AssertionError("finite predecessor oracle changed")
                row["max_level"] = "infinite"
            elif row["max_level"] != 3:
                raise AssertionError("finite early oracle changed")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().data_fixes = (FIXTURE / "mir5/data-final-fixes.lua").as_posix()
        self.lua.globals().mir5_control = (FIXTURE / "mir5/control.lua").as_posix()
        self.lua.globals().published_control_path = (FIXTURE / "published-4.7/control.lua").as_posix()
        self.lua.globals().published_reset_control_path = (FIXTURE / "published-config-control/control.lua").as_posix()
        self.lua.globals().mir5_control_path = (FIXTURE / "mir5/control.lua").as_posix()
        self.lua.globals().effect3_control_path = (FIXTURE / "effect3-cap2/control.lua").as_posix()
        self.lua.globals().effect1_control_path = (FIXTURE / "effect1-cap40/control.lua").as_posix()
        self.lua.execute(r'''
          function run_ba_data(path, rows, bad)
            local environment = {mods={base="2.0.77",["more-infinite-research"]="5.0.20000"},data={raw={technology=rows}}}
            environment._G=environment; setmetatable(environment,{__index=function(_,key)return _G[key] end})
            if bad then environment.data.raw.technology[bad].effects[1].change=.01 end
            local chunk,message=loadfile(path,"t",environment); assert(chunk,message)
            local ok,result=pcall(chunk)
            return {ok=ok,message=tostring(result),rows=environment.data.raw.technology}
          end

          function run_ba_fresh(path, opponent)
            -- Factorio exposes this native float32 representation at runtime.
            -- Data-stage fixture preflight below deliberately remains exact 0.02.
            local runtime_effect=0.019999999552965164
            local families={
              {early="recipe-prod-research_material_aluminium-1",tail="recipe-prod-research_material_aluminium-4",recipes={"angels-plate-aluminium","angels-plate-aluminium-2"}},
              {early="recipe-prod-research_material_copper_tungsten-1",tail="recipe-prod-research_material_copper_tungsten-4",recipes={"bob-copper-tungsten-alloy"}},
              {early="recipe-prod-research_material_gold-1",tail="recipe-prod-research_material_gold-4",recipes={"angels-plate-gold","angels-plate-gold-2","angels-wire-gold-2"}},
              {early="recipe-prod-research_material_tin-1",tail="recipe-prod-research_material_tin-4",recipes={"angels-plate-tin","angels-plate-tin-2"}},
              {early="recipe-prod-research_material_titanium-1",tail="recipe-prod-research_material_titanium-4",recipes={"angels-plate-titanium","angels-plate-titanium-2"}},
            }
            local function new_force(name,index)
              local force={name=name,index=index,valid=true,technologies={},recipes={},research_queue={},research_progress=0}
              function force.enable_all_prototypes() end
              function force.get_spawn_position(_) return {0,0} end
              function force.add_research(value)
                if type(value)=="string" then value=force.technologies[value] end
                if not value or force.current_research then return false end
                for _,family in ipairs(families) do
                  if value.name==family.tail and force.technologies[family.early].researched~=true then return false end
                end
                force.research_queue={value};force.current_research=value;return true
              end
              for _,family in ipairs(families) do
                for _,recipe in ipairs(family.recipes) do force.recipes[recipe]={productivity_bonus=0} end
                for _,stage in ipairs({{family.early,1,3},{family.tail,4,4294967295}}) do
                  local effects={};for i,recipe in ipairs(family.recipes) do effects[i]={type="change-recipe-productivity",recipe=recipe,change=runtime_effect} end
                  force.technologies[stage[1]]={name=stage[1],level=stage[2],researched=false,enabled=true,visible_when_disabled=false,force=force,
                    research_unit_count=1,research_unit_energy=60,prototype={max_level=stage[3],effects=effects,research_unit_energy=60},
                    prerequisites={{name="external-a",research_recursive=function()end},{name="external-b",research_recursive=function()end}}}
                end
              end
              force.technologies["mir5-ba-continuity-queue-probe"]={name="mir5-ba-continuity-queue-probe",level=1,researched=false,enabled=true,prototype={max_level=1,effects={}},prerequisites={}}
              function force.reset_technology_effects()
                for _,recipe in pairs(force.recipes) do recipe.productivity_bonus=0 end
                for _,family in ipairs(families) do
                  local early,tail=force.technologies[family.early],force.technologies[family.tail]
                  local early_count=early.researched and early.level or early.level-1
                  local tail_count=tail.level-4
                  for _,effect in ipairs(early.prototype.effects) do force.recipes[effect.recipe].productivity_bonus=force.recipes[effect.recipe].productivity_bonus+early_count*effect.change end
                  for _,effect in ipairs(tail.prototype.effects) do force.recipes[effect.recipe].productivity_bonus=force.recipes[effect.recipe].productivity_bonus+tail_count*effect.change end
                end
              end
              return force
            end
            local player,foreign,saves,markers=new_force("player",1),nil,0,0
            local inventory={items={}}
            function inventory.insert(row) inventory.items[row.name]=(inventory.items[row.name] or 0)+row.count;return row.count end
            function inventory.get_item_count(name)return inventory.items[name] or 0 end
            local lab={valid=true,energy=0};function lab.get_inventory(index)assert(index==1);return inventory end
            local game={tick=0,forces={player=player,[1]=player},surfaces={}}
            function game.create_force(name)foreign=new_force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign end
            game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
            function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
            local callbacks,storage={events={}},{}
            local mods={base="2.0.77",angelsbioprocessing="2.0.3",angelsbioprocessinggraphics="2.0.0",angelspetrochem="2.0.3",angelspetrochemgraphics="2.0.1",angelsrefining="2.0.4",angelsrefininggraphics="2.0.0",angelssmelting="2.0.5",angelssmeltinggraphics="2.0.0",bobelectronics="2.1.1",boblibrary="2.1.0",bobores="2.1.2",bobplates="2.1.1",bobrevamp="2.1.1",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-bob-angel-continuity"]="0.2.0"}
            local environment={script={active_mods=mods,on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage=storage,helpers={table_to_json=function(value)assert(value.status=="passed");return "{}" end},log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
            environment._G=environment;setmetatable(environment,{__index=function(_,key)return _G[key] end})
            local chunk,message=loadfile(path,"t",environment);assert(chunk,message)
            local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)} end
            if opponent=="effect-drift" then
              player.technologies["recipe-prod-research_material_aluminium-1"].prototype.effects[1].change=.01
            end
            ok,result=pcall(callbacks.init);if not ok then return {ok=false,message=tostring(result)} end
            local state=storage.mir5_bob_angel_continuity
            for i,name in ipairs(state.plan) do
              local tech=player.technologies[name]
              assert(player.current_research==tech and #player.research_queue==1,"fixture bypassed native sequential admission")
              if tech.prototype.max_level==3 then
                if tech.level<3 then tech.level=tech.level+1;tech.researched=false else tech.researched=true end
              else tech.level=tech.level+1;tech.researched=false end
              for _,effect in ipairs(tech.prototype.effects) do player.recipes[effect.recipe].productivity_bonus=player.recipes[effect.recipe].productivity_bonus+effect.change end
              local packs=name:match("%-4$") and (name:match("_tin") and {"automation-science-pack","utility-science-pack"} or {"automation-science-pack","logistic-science-pack","utility-science-pack"}) or (name:match("_tin") and {"automation-science-pack"} or {"automation-science-pack","logistic-science-pack"})
              for _,pack in ipairs(packs) do inventory.items[pack]=inventory.items[pack]-1 end
              local event_tech=(opponent=="out-of-order" and i==1) and player.technologies[state.plan[4]] or tech
              ok,result=pcall(callbacks.events[2],{research=event_tech});if not ok then return {ok=false,message=tostring(result)} end
              table.remove(player.research_queue,1);player.current_research=player.research_queue[1]
              if i<#state.plan then
                ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)} end
              end
            end
            if opponent=="lost-bonus" then player.recipes["angels-plate-aluminium"].productivity_bonus=player.recipes["angels-plate-aluminium"].productivity_bonus-.02
            elseif opponent=="not-advanced" then local t=player.technologies[state.plan[1]];t.level=2;t.researched=false
            elseif opponent=="foreign-queue" then foreign.research_progress=.41 end
            ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)} end
            local phase=state.phase;ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result)} end
            if phase~=state.phase then return {ok=false,message="on_load changed fixture state"} end
            ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)} end
            return {ok=true,markers=markers,saves=saves,completed=state.completed,events=state.events,phase=state.phase,tail=player.technologies["recipe-prod-research_material_aluminium-4"].level,bonus=player.recipes["angels-plate-aluminium"].productivity_bonus,foreign_progress=foreign.research_progress,runtime_effect=runtime_effect}
          end

        ''')

        self.lua.execute(r'''
          function run_ba_transition(source_path, destination_path, cap2_path, cap40_path, opponent)
            local f={
              {e="recipe-prod-research_material_aluminium-1",t="recipe-prod-research_material_aluminium-4",r={"angels-plate-aluminium","angels-plate-aluminium-2"}},
              {e="recipe-prod-research_material_copper_tungsten-1",t="recipe-prod-research_material_copper_tungsten-4",r={"bob-copper-tungsten-alloy"}},
              {e="recipe-prod-research_material_gold-1",t="recipe-prod-research_material_gold-4",r={"angels-plate-gold","angels-plate-gold-2","angels-wire-gold-2"}},
              {e="recipe-prod-research_material_tin-1",t="recipe-prod-research_material_tin-4",r={"angels-plate-tin","angels-plate-tin-2"}},
              {e="recipe-prod-research_material_titanium-1",t="recipe-prod-research_material_titanium-4",r={"angels-plate-titanium","angels-plate-titanium-2"}},
            }
            local function force(name,index)
              local x={name=name,index=index,valid=true,technologies={},recipes={},research_queue={},research_progress=0}
              function x.enable_all_prototypes()end
              function x.add_research(v)if type(v)=="string"then v=x.technologies[v]end;if not v or x.current_research then return false end;x.research_queue={v};x.current_research=v;return true end
              for _,a in ipairs(f)do
                for _,n in ipairs(a.r)do x.recipes[n]={productivity_bonus=0}end
                for _,v in ipairs({{a.e,1,3},{a.t,4,150}})do
                  local q={};for i,n in ipairs(a.r)do q[i]={type="change-recipe-productivity",recipe=n,change=0.019999999552965164}end
                  x.technologies[v[1]]={name=v[1],level=v[2],researched=false,enabled=true,visible_when_disabled=false,force=x,prototype={max_level=v[3],effects=q},prerequisites={}}
                end
              end
              x.technologies["mir5-ba-continuity-queue-probe"]={name="mir5-ba-continuity-queue-probe",level=1,researched=false,enabled=true,prototype={max_level=1,effects={}},prerequisites={{research_recursive=function()end}}}
              function x.reset_technology_effects()
                for _,v in pairs(x.recipes)do v.productivity_bonus=0 end
                for _,a in ipairs(f)do
                  local e,t=x.technologies[a.e],x.technologies[a.t];local ec=e.researched and e.level or e.level-1;local tc=t.researched and t.level-3 or t.level-4
                  for _,z in ipairs(e.prototype.effects)do x.recipes[z.recipe].productivity_bonus=x.recipes[z.recipe].productivity_bonus+ec*z.change end
                  for _,z in ipairs(t.prototype.effects)do x.recipes[z.recipe].productivity_bonus=x.recipes[z.recipe].productivity_bonus+tc*z.change end
                end
                if opponent=="prewrite-disabled" and x.index==2 then x.technologies[f[1].e].enabled=false end
              end
              return x
            end
            local player,foreign,saves,markers=force("player",1),nil,0,0
            local game={tick=0,forces={player=player,[1]=player}}
            function game.create_force(n)foreign=force(n,2);game.forces[n]=foreign;game.forces[2]=foreign;return foreign end
            function game.server_save(n)assert(n=="mir5-native-complete");saves=saves+1 end
            local storage={}
            local base={base="2.0.77",angelsbioprocessing="2.0.3",angelsbioprocessinggraphics="2.0.0",angelspetrochem="2.0.3",angelspetrochemgraphics="2.0.1",angelsrefining="2.0.4",angelsrefininggraphics="2.0.0",angelssmelting="2.0.5",angelssmeltinggraphics="2.0.0",bobelectronics="2.1.1",boblibrary="2.1.0",bobores="2.1.2",bobplates="2.1.1",bobrevamp="2.1.1"}
            local function load(path,mir,ver,startup)
              local c={events={}};local mods={};for n,v in pairs(base)do mods[n]=v end;mods["more-infinite-research"],mods["mir-fixture-mir5-bob-angel-continuity"]=mir,ver
              local env={script={active_mods=mods,on_init=function(g)c.init=g end,on_load=function(g)c.load=g end,on_configuration_changed=function(g)c.changed=g end,on_event=function(e,g)c.events[e]=g end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage=storage,settings={startup=startup or {}},helpers={table_to_json=function(v)assert(v.status=="passed");return "{}"end},log=function(v)assert(v:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
              env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end});local h,m=loadfile(path,"t",env);assert(h,m);local ok,v=pcall(h);return ok and c or nil,tostring(v)
            end
            local function call(c,field)
              local h=field=="tick" and c.events[1] or c[field]
              if type(h)~="function" then return false,"missing callback "..field end
              local ok,v=pcall(h);return ok,tostring(v)
            end
            local function shift(effect,cap)
              for _,x in ipairs({player,foreign})do
                for _,a in ipairs(f)do
                  local e,t=x.technologies[a.e],x.technologies[a.t];e.level,e.researched,e.prototype.max_level=3,true,3;t.level,t.researched,t.prototype.max_level=151,false,4294967295
                  local native_effect=effect==.03 and 0.029999999329447746 or (effect==.01 and 0.009999999776482582 or effect)
                  for _,q in ipairs({e,t})do for _,z in ipairs(q.prototype.effects)do z.change=native_effect end end
                  -- Exact published native control proves the upstream reset enables both forces.
                  e.enabled,e.visible_when_disabled=(cap>=3),(cap<3)
                  t.enabled,t.visible_when_disabled=false,true
                end
                x.reset_technology_effects()
              end
            end
            local c,m=load(source_path,"4.7.20002","0.1.0");if not c then return {ok=false,message=m}end
            local ok,v=call(c,"init");if not ok then return {ok=false,message=v}end
            local seeded=storage.mir5_bob_angel_continuity
            if type(seeded.foreign_pre_external)~="table" or type(seeded.foreign)~="table" then return {ok=false,message="source did not save foreign external transition"}end
            for _,a in ipairs(f)do for _,n in ipairs({a.e,a.t})do
              local before,after=seeded.foreign_pre_external.technologies[n],seeded.foreign.technologies[n]
              if not before or not after or before.enabled~=true or before.visible_when_disabled~=false or after.enabled~=false or after.visible_when_disabled~=false then return {ok=false,message="source foreign external transition differs for "..n}end
            end end
            if #seeded.foreign_pre_external.queue~=#seeded.foreign.queue or seeded.foreign_pre_external.current~=seeded.foreign.current or seeded.foreign_pre_external.progress~=seeded.foreign.progress then return {ok=false,message="source foreign external transition changed queue or progress"}end
            ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end;ok,v=call(c,"load");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end
            shift(.02,150);if opponent=="lost-boundary"then player.technologies[f[1].t].level=150 elseif opponent=="foreign-upgrade-state"then foreign.technologies[f[1].e].enabled=false end
            c,m=load(destination_path,"5.0.20000","0.2.0");if not c then return {ok=false,message=m}end;ok,v=call(c,"changed");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end;ok,v=call(c,"load");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end
            shift(.03,2);if opponent=="foreign-queue"then foreign.research_progress=.41 end
            local s3={["mir-settings-profile-import"]={value=""}};for _,a in ipairs(f)do local k=a.e:match("recipe%-prod%-(research_material_.+)%-1");s3["ips-effect-per-level-"..k]={value=3};s3["ips-max-level-"..k]={value=2}end
            c,m=load(cap2_path,"5.0.20000","0.3.0",s3);if not c then return {ok=false,message=m}end;ok,v=call(c,"changed");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end;ok,v=call(c,"load");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end
            shift(.01,40);local s1={["mir-settings-profile-import"]={value=""}};for _,a in ipairs(f)do local k=a.e:match("recipe%-prod%-(research_material_.+)%-1");s1["ips-effect-per-level-"..k]={value=1};s1["ips-max-level-"..k]={value=40}end
            c,m=load(cap40_path,"5.0.20000","0.4.0",s1);if not c then return {ok=false,message=m}end;ok,v=call(c,"changed");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end;ok,v=call(c,"load");if not ok then return {ok=false,message=v}end;ok,v=call(c,"tick");if not ok then return {ok=false,message=v}end
            return {ok=true,message="",phase=storage.mir5_bob_angel_continuity.phase,markers=markers,saves=saves,tail=player.technologies[f[1].t].level,bonus=player.recipes[f[1].r[1]].productivity_bonus,enabled=player.technologies[f[1].t].enabled}
          end

          function run_ba_published_reset_control(path, opponent)
            local families={
              {early="recipe-prod-research_material_aluminium-1",tail="recipe-prod-research_material_aluminium-4",recipes={"angels-plate-aluminium","angels-plate-aluminium-2"}},
              {early="recipe-prod-research_material_copper_tungsten-1",tail="recipe-prod-research_material_copper_tungsten-4",recipes={"bob-copper-tungsten-alloy"}},
              {early="recipe-prod-research_material_gold-1",tail="recipe-prod-research_material_gold-4",recipes={"angels-plate-gold","angels-plate-gold-2","angels-wire-gold-2"}},
              {early="recipe-prod-research_material_tin-1",tail="recipe-prod-research_material_tin-4",recipes={"angels-plate-tin","angels-plate-tin-2"}},
              {early="recipe-prod-research_material_titanium-1",tail="recipe-prod-research_material_titanium-4",recipes={"angels-plate-titanium","angels-plate-titanium-2"}},
            }
            local function readonly(values, label)
              return setmetatable({}, {
                __index=function(_, key) return values[key] end,
                __newindex=function(_, key) error("fixture observer wrote " .. label .. "." .. tostring(key)) end,
              })
            end
            local function new_force(name, index, enabled)
              local force={name=name,index=index,valid=true,technologies={},recipes={},research_queue={},research_progress=0}
              local technology_values, recipe_values={},{}
              for _,family in ipairs(families) do
                for _,recipe in ipairs(family.recipes) do
                  recipe_values[recipe]={productivity_bonus=3}
                  force.recipes[recipe]=readonly(recipe_values[recipe], "recipe." .. recipe)
                end
                for _,entry in ipairs({{family.early,3},{family.tail,150}}) do
                  local effects={}
                  for effect_index,recipe in ipairs(family.recipes) do
                    effects[effect_index]={type="change-recipe-productivity",recipe=recipe,change=0.019999999552965164}
                  end
                  technology_values[entry[1]]={
                    name=entry[1], level=entry[2], researched=true, enabled=enabled, visible_when_disabled=false,
                    prototype={max_level=entry[1]==family.early and 3 or 150,effects=effects},
                  }
                  force.technologies[entry[1]]=readonly(technology_values[entry[1]], "technology." .. entry[1])
                end
              end
              local probe_values={name="mir5-ba-continuity-queue-probe",level=1,researched=false,enabled=true,visible_when_disabled=false,prototype={max_level=1,effects={}}}
              local probe=readonly(probe_values, "technology.mir5-ba-continuity-queue-probe")
              force.technologies[probe_values.name]=probe
              force.research_queue={probe}
              force.current_research=probe
              force.research_progress=.42
              return force,technology_values,recipe_values
            end
            local function stored_status(value)
              return {level=value.level,researched=value.researched,enabled=value.enabled,
                visible_when_disabled=value.visible_when_disabled,max_level=value.prototype.max_level}
            end
            local function snapshot(force)
              local technologies,bonuses={},{}
              for _,family in ipairs(families) do
                technologies[family.early]=stored_status(force.technologies[family.early])
                technologies[family.tail]=stored_status(force.technologies[family.tail])
                for _,recipe in ipairs(family.recipes) do bonuses[recipe]=force.recipes[recipe].productivity_bonus end
              end
              return {technologies=technologies,bonuses=bonuses,queue={force.research_queue[1].name},
                current=force.current_research.name,progress=force.research_progress}
            end
            local function same_snapshot(left, right)
              for _,family in ipairs(families) do
                for _,name in ipairs({family.early,family.tail}) do
                  local a,b=left.technologies[name],right.technologies[name]
                  if not a or not b or a.level~=b.level or a.researched~=b.researched or a.enabled~=b.enabled
                      or a.visible_when_disabled~=b.visible_when_disabled or a.max_level~=b.max_level then return false end
                end
                for _,recipe in ipairs(family.recipes) do if left.bonuses[recipe]~=right.bonuses[recipe] then return false end end
              end
              return #left.queue==#right.queue and left.queue[1]==right.queue[1]
                and left.current==right.current and left.progress==right.progress
            end

            local player,player_values,player_recipes=new_force("player",1,true)
            local foreign,foreign_values,foreign_recipes=new_force("foreign",2,false)
            local game={forces={player=player,[1]=player,foreign=foreign,[2]=foreign}}
            local saves,markers=0,0
            function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
            local storage={mir5_bob_angel_continuity={
              phase="published-boundary-saved",source_mir="4.7.20002",player=snapshot(player),
              foreign=snapshot(foreign),foreign_index=2,
            }}
            if opponent=="source-state-loss" then
              storage.mir5_bob_angel_continuity.foreign.technologies[families[1].early].enabled=true
            end
            if opponent=="wrong-source-phase" then
              storage.mir5_bob_angel_continuity.phase="published-boundary-seeded"
            end
            local callbacks={events={}}
            local mods={base="2.0.77",angelsbioprocessing="2.0.3",angelsbioprocessinggraphics="2.0.0",angelspetrochem="2.0.3",angelspetrochemgraphics="2.0.1",angelsrefining="2.0.4",angelsrefininggraphics="2.0.0",angelssmelting="2.0.5",angelssmeltinggraphics="2.0.0",bobelectronics="2.1.1",boblibrary="2.1.0",bobores="2.1.2",bobplates="2.1.1",bobrevamp="2.1.1",["more-infinite-research"]="4.7.20002",["mir-fixture-mir5-bob-angel-continuity"]="0.1.1"}
            local environment={
              script={active_mods=mods,on_init=function(f)callbacks.init=f end,on_load=function(f)callbacks.load=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_event=function(e,f)callbacks.events[e]=f end},
              defines={events={on_tick=1}},game=game,storage=storage,
              helpers={table_to_json=function(value)assert(value.case=="bob-angel-continuity-published-reset-control" and value.status=="passed");return "{}" end},
              log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end,
            }
            environment._G=environment;setmetatable(environment,{__index=function(_,key)return _G[key]end})
            local chunk,message=loadfile(path,"t",environment);assert(chunk,message)
            local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)} end
            local init_ok,init_message=pcall(callbacks.init)
            if init_ok or not tostring(init_message):find("must start from its 0.1.0 predecessor save",1,true) then
              return {ok=false,message="reset-control accepted a fresh initialization"}
            end

            -- This is the independent upstream Angels configuration callback.
            -- It is intentionally outside the fixture observer and occurs first.
            if opponent~="missing-reset" then
              for _,values in pairs({player_values,foreign_values}) do
                for _,family in ipairs(families) do
                  values[family.early].enabled,values[family.early].visible_when_disabled=true,false
                  values[family.tail].enabled,values[family.tail].visible_when_disabled=true,false
                end
              end
            end
            if opponent=="effect-loss" then foreign_recipes[families[1].recipes[1]].productivity_bonus=2.98 end
            if opponent=="queue-loss" then foreign.research_progress=.41 end
            if opponent=="state-loss" then foreign_values[families[1].tail].level=149 end
            local before_observer=snapshot(foreign)
            local event={mod_changes={["mir-fixture-mir5-bob-angel-continuity"]={old_version="0.1.0",new_version="0.1.1"}}}
            if opponent=="wrong-transition" then event.mod_changes["mir-fixture-mir5-bob-angel-continuity"].old_version="0.0.9" end
            ok,result=pcall(callbacks.changed,event);if not ok then return {ok=false,message=tostring(result)} end
            if not same_snapshot(before_observer,snapshot(foreign)) then return {ok=false,message="reset-control observer mutated foreign native state"} end
            ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)} end
            ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result)} end
            ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)} end
            ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result)} end
            ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)} end
            return {ok=true,message="",phase=storage.mir5_bob_angel_continuity.phase,markers=markers,saves=saves,
              player=snapshot(player),foreign=snapshot(foreign)}
          end
        ''')

    def test_profiles_pin_source_destination_and_relaxation_archives(self):
        base = json.loads(BASE_PROFILE.read_text(encoding="utf-8"))
        expected = {"published": ("4.7.20002", "0.1.0"), "published_reset": ("4.7.20002", "0.1.1"), "mir5": ("5.0.20000", "0.2.0"), "effect3": ("5.0.20000", "0.3.0"), "effect1": ("5.0.20000", "0.4.0")}
        directories = {"published": "published-4.7", "published_reset": "published-config-control", "mir5": "mir5", "effect3": "effect3-cap2", "effect1": "effect1-cap40"}
        for key,path in PROFILE_PATHS.items():
            profile=json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(profile["target"],"f200")
            self.assertEqual(profile["engine"],base["engine"])
            self.assertEqual(profile["archive_sha256"],base["archive_sha256"])
            self.assertEqual(profile["mods"][:len(base["mods"])],base["mods"])
            self.assertNotIn("space-age",[item["name"] for item in profile["mods"]])
            self.assertNotIn("bobtech",[item["name"] for item in profile["mods"]])
            self.assertEqual(profile["mods"][-2],{"name":"more-infinite-research","version":expected[key][0],"enabled":True})
            self.assertEqual(profile["mods"][-1],{"name":FIXTURE_NAME,"version":expected[key][1],"enabled":True})
            info=json.loads((FIXTURE/directories[key]/"info.json").read_text(encoding="utf-8"))
            self.assertEqual((info["name"],info["version"]),(FIXTURE_NAME,expected[key][1]))
            self.assertEqual(info["dependencies"][-1],f"more-infinite-research = {expected[key][0]}")
            if key == "published_reset":
                self.assertEqual(info["dependencies"],[
                    "base >= 2.0.77",
                    "angelsrefining = 2.0.4",
                    "bobplates = 2.1.1",
                    "more-infinite-research = 4.7.20002",
                ])

    def test_default_preflight_is_atomic_and_accelerates_only_count_time(self):
        input_rows={row["name"]:lua_value(self.lua,deepcopy(row)) for row in self.candidate_rows}
        self.lua.globals().rows=lua_value(self.lua,input_rows)
        result=self.lua.eval("run_ba_data(data_fixes,rows)")
        self.assertTrue(result["ok"],result["message"])
        for expected in self.candidate_rows:
            actual=plain(result["rows"][expected["name"]])
            self.assertEqual((actual["unit"]["count_formula"],actual["unit"]["time"]),("1",1))
            actual["unit"]["count_formula"],actual["unit"]["time"]=expected["unit"]["count_formula"],expected["unit"]["time"]
            self.assertEqual(actual,expected)
        bad_rows={row["name"]:lua_value(self.lua,deepcopy(row)) for row in self.candidate_rows}
        self.lua.globals().bad_rows=lua_value(self.lua,bad_rows)
        self.lua.globals().bad_name="recipe-prod-research_material_titanium-4"
        failed=self.lua.eval("run_ba_data(data_fixes,bad_rows,bad_name)")
        self.assertFalse(failed["ok"])
        self.assertIn("effect changed",failed["message"])
        first=failed["rows"]["recipe-prod-research_material_aluminium-1"]["unit"]
        self.assertEqual((first["count_formula"],first["time"]),("200*2^(L-1)",30))

    def test_fresh_lab_control_requires_twenty_ordered_events_and_preserves_foreign_queue(self):
        for opponent in (None,"lost-bonus","not-advanced","foreign-queue","out-of-order","effect-drift"):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent=opponent
                result=self.lua.eval("run_ba_fresh(mir5_control,opponent)")
                if opponent is None:
                    self.assertTrue(result["ok"],result["message"])
                    self.assertEqual((result["completed"],result["events"],result["phase"]),(20,20,"fresh-lab-complete"))
                    self.assertEqual((result["markers"],result["saves"]),(2,1))
                    self.assertEqual(result["runtime_effect"],0.019999999552965164)
                    self.assertEqual(result["tail"],5)
                    self.assertAlmostEqual(result["bonus"],.08)
                    self.assertAlmostEqual(result["foreign_progress"],.42)
                else:
                    self.assertFalse(result["ok"])
                    self.assertIn("[mir5-bob-angel-continuity]",result["message"])
                    if opponent == "effect-drift":
                        self.assertIn("default material effect differs",result["message"])


    def test_published_boundary_upgrade_and_saved_cap_transitions_execute(self):
        for opponent in (None, "lost-boundary", "foreign-queue", "prewrite-disabled", "foreign-upgrade-state"):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent=opponent
                result=self.lua.eval("run_ba_transition(published_control_path,mir5_control_path,effect3_control_path,effect1_control_path,opponent)")
                if opponent is None:
                    self.assertTrue(result["ok"],result["message"])
                    self.assertEqual((result["phase"],result["tail"]),("effect1-cap40-saved",151))
                    self.assertAlmostEqual(result["bonus"],1.5)
                    self.assertFalse(result["enabled"])
                    self.assertEqual((result["markers"],result["saves"]),(8,4))
                else:
                    self.assertFalse(result["ok"])
                    self.assertIn("[mir5-bob-angel-continuity",result["message"])
                    if opponent == "prewrite-disabled":
                        self.assertIn("[mir5-bob-angel-continuity-source]",result["message"])
                        self.assertIn("foreign external pre-write state differs",result["message"])
                    elif opponent == "foreign-upgrade-state":
                        self.assertIn("actual=early={level=3,researched=true,enabled=false,visible_when_disabled=false,max_level=3}",result["message"])
                        self.assertIn("tail={level=151,researched=false,enabled=false,visible_when_disabled=true,max_level=4294967295}",result["message"])
                        self.assertIn("MIR_private_ownership=unavailable_to_external_fixture",result["message"])

    def test_published_reset_control_observes_upstream_reenable_without_mutating_native_state(self):
        expected_errors = {
            "missing-reset": "upstream angelsrefining did not re-enable",
            "effect-loss": "native recipe effect changed",
            "queue-loss": "queue or progress changed",
            "state-loss": "published earned boundary differs",
            "source-state-loss": "published foreign external-disable source state differs",
            "wrong-source-phase": "requires the published 0.1.0 boundary save",
            "wrong-transition": "requires the published 0.1.0 to 0.1.1 fixture update",
        }
        for opponent in (None, *expected_errors):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent = opponent
                result = self.lua.eval("run_ba_published_reset_control(published_reset_control_path,opponent)")
                if opponent is not None:
                    self.assertFalse(result["ok"])
                    self.assertIn("[mir5-bob-angel-published-reset-control]", result["message"])
                    self.assertIn(expected_errors[opponent], result["message"])
                    continue

                self.assertTrue(result["ok"], result["message"])
                self.assertEqual((result["phase"], result["markers"], result["saves"]),
                                 ("published-reset-control-saved", 3, 1))
                for label in ("player", "foreign"):
                    snapshot = plain(result[label])
                    self.assertEqual(snapshot["queue"], ["mir5-ba-continuity-queue-probe"])
                    self.assertEqual(snapshot["current"], "mir5-ba-continuity-queue-probe")
                    self.assertAlmostEqual(snapshot["progress"], 0.42)
                    for name, status in snapshot["technologies"].items():
                        expected_level = 3 if name.endswith("-1") else 150
                        self.assertEqual(
                            (status["level"], status["researched"], status["enabled"], status["visible_when_disabled"]),
                            (expected_level, True, True, False),
                        )
                    for bonus in snapshot["bonuses"].values():
                        self.assertAlmostEqual(bonus, 3)

    def test_relaxed_setting_values_and_saved_boundary_markers_are_explicit(self):
        for directory,effect,cap,useful in (("effect3-cap2",3,2,100),("effect1-cap40",1,40,300)):
            with self.subTest(directory=directory):
                self.lua.globals().settings_path=(FIXTURE/directory/"settings-updates.lua").as_posix()
                self.lua.execute(r'''
                  local families={"research_material_aluminium","research_material_copper_tungsten","research_material_gold","research_material_tin","research_material_titanium"}
                  data={raw={["double-setting"]={},["int-setting"]={},["string-setting"]={}}}
                  for _,family in ipairs(families) do
                    data.raw["double-setting"]["ips-effect-per-level-"..family]={setting_type="startup",default_value=2}
                    data.raw["int-setting"]["ips-max-level-"..family]={setting_type="startup",minimum_value=0,default_value=0}
                  end
                  data.raw["string-setting"]["mir-settings-profile-import"]={setting_type="startup",default_value=""}
                  assert(dofile(settings_path)==nil)
                ''')
                for _,entry in self.lua.globals().data["raw"]["double-setting"].items(): self.assertEqual(entry["default_value"],effect)
                for _,entry in self.lua.globals().data["raw"]["int-setting"].items(): self.assertEqual(entry["default_value"],cap)
                self.assertEqual((300+effect-1)//effect,useful)
                self.assertEqual(min(cap,useful),cap)
        source=(FIXTURE/"published-4.7/control.lua").read_text(encoding="utf-8")
        mir5=(FIXTURE/"mir5/control.lua").read_text(encoding="utf-8")
        self.assertIn("historical_lab_completed_levels=0",source)
        self.assertIn("no_fabricated_150_completion_claim=true",source)
        self.assertIn("assert_external_prewrite",source)
        self.assertIn("assert_external_disable_transition",source)
        self.assertIn("foreign_pre_external",source)
        self.assertIn("PRESERVED_TAIL_NEXT_LEVEL = 151",mir5)
        self.assertIn("real_lab_completed_levels=state.completed",mir5)
        self.assertIn("foreign_upgrade_diagnostic",mir5)
        self.assertNotIn("storage.mir_caps",mir5)
        published_reset=(FIXTURE/"published-config-control/control.lua").read_text(encoding="utf-8")
        self.assertIn("published-boundary-saved",published_reset)
        self.assertIn("all_ten_native_material_technologies_reenabled=true",published_reset)
        self.assertIn("requires the published 0.1.0 to 0.1.1 fixture update",published_reset)
        self.assertIn("upstream angelsrefining did not re-enable",published_reset)
        for field in ("level", "researched", "enabled", "visible_when_disabled", "productivity_bonus"):
            self.assertNotIn(f".{field} =",published_reset)
        for path in FIXTURE.rglob("*.lua"):
            self.lua.globals().lua_path=path.as_posix()
            self.lua.execute("local chunk,message=loadfile(lua_path);assert(chunk,message)")


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir",type=Path,required=True)
    args=parser.parse_args()
    sys.path.insert(0,str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelNativeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
