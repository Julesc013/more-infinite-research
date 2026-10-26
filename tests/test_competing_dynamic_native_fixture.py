"""Host controls for the F200 Space Age dynamic-provider continuity fixtures.

The controls execute staged data checks and a deliberately small native-shaped
mock.  They do not start Factorio and therefore do not qualify the save chain.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/competing-dynamic-gameplay"
FACTS = ROOT / "tests/fixtures/competing-dynamic-f200-sa-captured-facts.json"
NATIVE_INITIAL_FACTS = ROOT / "tests/fixtures/competing-dynamic-f200-sa-native-initial-levels.json"
NAME = "mir-fixture-mir5-competing-dynamic-gameplay"
OBSERVER = "mir-fixture-mir5-active-mods-observer"
UINT32_MAX = 4294967295
ENGINE_SHA = "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"
ARCHIVES = {
    "ce": ("crafting-efficiency-2", "0.2.20", "crafting-efficiency-2_0.2.20.zip", "2ED4373DEB180E910D72EDE30C8FC1F71BFFCB5401F6092E87E365631D9A2AB1"),
    "pr": ("ProductivityResearch", "1.3.2", "ProductivityResearch_1.3.2.zip", "4E1B609B6AB731E1C3A019B6C23250878B4188D3F3179B701BC977B306D10874"),
}
STAGES = (
    ("published-4.7", "published", "4.7.20002", "0.1.0", False),
    ("mir5-prefer-mir", "mir5-prefer-mir", "5.0.20000", "0.2.0", True),
    ("mir5-prefer-foreign", "mir5-prefer-foreign", "5.0.20000", "0.3.0", False),
)
PROFILES = tuple(
    ROOT / "tests/profiles" / f"competing-dynamic-gameplay-{provider}-{label}-f200-sa-2077.json"
    for provider in ("ce", "pr") for label, _, _, _, _ in STAGES
)
TARGETS = {
    "ce": {
        "target": "ce-iron-gear-wheel-19", "predecessor": "ce-iron-gear-wheel-14",
        "initial_level": 19,
        "prerequisites": ["ce-iron-gear-wheel-14", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"],
        "recipe": "iron-gear-wheel",
        "science": ["automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"],
    },
    "pr": {
        "target": "sem-prfe_iron-gear-wheel-productivity-1", "predecessor": False, "prerequisites": [],
        "initial_level": 1,
        "recipe": "iron-gear-wheel", "science": ["automation-science-pack"],
    },
}
SOURCE_ROWS = {
    "ce": {
        "type": "technology", "name": "ce-iron-gear-wheel-19", "upgrade": True,
        "localised_name": ["technology-name.technology-productivity", "Iron gear wheel productivity"],
        "effects": [
            {"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": 0.1},
            {"type": "change-recipe-productivity", "recipe": "casting-iron-gear-wheel", "change": 0.1},
        ],
        "max_level": "infinite", "icon": "__base__/graphics/icons/iron-gear-wheel.png",
        "unit": {"count_formula": "1200 * 1.5 * l", "ingredients": [[name, 1] for name in TARGETS["ce"]["science"]], "time": 45},
        "prerequisites": ["ce-iron-gear-wheel-14", *TARGETS["ce"]["science"]],
    },
    "pr": {
        "type": "technology", "name": "sem-prfe_iron-gear-wheel-productivity-1", "upgrade": True,
        "hidden": True, "hidden_in_factoriopedia": True,
        "effects": [
            {"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": 0.1},
            {"type": "change-recipe-productivity", "recipe": "casting-iron-gear-wheel", "change": 0.1},
        ],
        "max_level": "infinite",
        "icons": [
            {"icon": "__base__/graphics/icons/iron-gear-wheel.png"},
            {"icon": "__core__/graphics/icons/technology/effect-constant/effect-constant-recipe-productivity.png", "icon_size": 64},
        ],
        "localised_name": ["technology-name.sem-prfe_productivity", "Iron gear wheel productivity"],
        "unit": {"count_formula": "1.25^(L-1)*1000", "ingredients": [["automation-science-pack", 1]], "time": 15},
    },
}


def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (tuple, list)):
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


class CompetingDynamicNativeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS.read_text(encoding="utf-8"))
        cls.providers = {entry["key"]: entry for entry in cls.facts["providers"]}
        native = json.loads(NATIVE_INITIAL_FACTS.read_text(encoding="utf-8"))
        cls.native_initial_levels = {
            entry["provider_key"]: {row["id"]: row["technology_level"] for row in entry["levels"]}
            for entry in native["observations"]
        }

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function dynamic_fixture_data(path, helper, provider, mir, row)
  local mods={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]=mir}
  if provider=="ce" then mods["crafting-efficiency-2"]="0.2.20" else mods.ProductivityResearch="1.3.2" end
  local raw={technology={[row.name]=row},["bool-setting"]={["mir-prefer-this-mod-for-competing-techs"]={default_value=false}}}
  local env={mods=mods,data={raw=raw}};env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  package.loaded["data-final-common"]=nil
  package.preload["data-final-common"]=function()
    local common,message=loadfile(helper,"t",env);assert(common,message);return common()
  end
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  package.preload["data-final-common"]=nil;package.loaded["data-final-common"]=nil
  return {ok=ok,message=tostring(result),raw=raw,row=row}
end
function dynamic_fixture_parse(path, provider, mir, fixture)
  local callbacks,reads={events={}},{ }
  local active={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]=mir,["mir-fixture-mir5-competing-dynamic-gameplay"]=fixture}
  if provider=="ce" then active["crafting-efficiency-2"]="0.2.20" else active.ProductivityResearch="1.3.2" end
  local env={script={active_mods=active,on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
  env._G=env;setmetatable(env,{__index=function(_,key)if key=="game" or key=="storage" or key=="settings" then reads[key]=(reads[key]or 0)+1 end;return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end
function dynamic_on_load(path, provider, phase)
  local callbacks={events={}}
  local active={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-competing-dynamic-gameplay"]="0.2.0"}
  if provider=="ce" then active["crafting-efficiency-2"]="0.2.20" else active.ProductivityResearch="1.3.2" end
  local completed_level=provider=="ce"and 20 or 2
  local state={provider=provider,phase=phase,actual_lab_completions=1,player_snapshot={level=completed_level,researched=false,enabled=false,visible=true,maximum=4294967295,saved_progress=.27,bonus=.1},player_queue={current="braking-force-1",queue={"braking-force-1"},progress=.42}}
  local store={mir5_competing_dynamic_gameplay=state};setmetatable(store,{__newindex=function()error("on_load wrote fixture storage")end})
  local env={script={active_mods=active,on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},storage=store}
  env._G=env;setmetatable(env,{__index=function(_,key)if key=="game" then error("on_load read LuaGameScript")end;return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)}end
  ok,result=pcall(callbacks.load);return {ok=ok,message=tostring(result)}
end
function dynamic_source_flow(path, provider, target_name, predecessor_name, target_prerequisites, recipe_name, science, ids, initial_levels, opponent)
  local callbacks,markers,saves={events={}},0,0
  local predecessor_calls=0
  local function inventory()
    local value={items={}}
    function value.insert(row)value.items[row.name]=(value.items[row.name]or 0)+row.count;return row.count end
    function value.get_item_count(name)return value.items[name]or 0 end
    function value.clear()value.items={}end
    return value
  end
  local input=inventory();local lab={valid=true,disabled_by_script=false,energy=0}
  setmetatable(lab,{__index=function(entity,key)if key=="active"then return entity.aggregate_inactive~=true and entity.disabled_by_script~=true end end,__newindex=function(entity,key,value)if key=="active"then error("LuaEntity.active is read-only")end;rawset(entity,key,value)end})
  function lab.get_inventory(index)assert(index==1);return input end
  local function make_force(name,index)
    local force={name=name,index=index,valid=true,technologies={},recipes={[recipe_name]={productivity_bonus=0}},research_progress=0,_queue={}}
    setmetatable(force,{__index=function(value,key)if key=="research_queue"then return rawget(value,"_queue")end end,__newindex=function(value,key,row)
      if key=="research_queue" then
        local queue=row or {};for _,technology in ipairs(queue)do for _,prerequisite in pairs(technology.prerequisites)do assert(prerequisite.researched==true,"research queue accepted prerequisite-unready native work")end end
        rawset(value,"_queue",queue);local current=row and row[1] or nil;rawset(value,"current_research",current)
        if current then rawset(value,"research_progress",current.saved_progress or 0);current.saved_progress=0 else rawset(value,"research_progress",0)end
      else rawset(value,key,row)end
    end})
    local function technology(name)
      local initial=initial_levels[name] or 1
      return {name=name,valid=true,force=force,level=initial,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
        prototype={max_level=4294967295,level=initial},prerequisites={},research_unit_count=1,research_unit_energy=60,research_unit_ingredients={}}
    end
    for _,id in ipairs(ids) do force.technologies[id]=technology(id) end
    local target=force.technologies[target_name];for _,item in ipairs(science)do target.research_unit_ingredients[#target.research_unit_ingredients+1]={name=item,amount=1}end
    if opponent=="missing-predecessor" then target.prerequisites={}
    else for _,required in ipairs(target_prerequisites) do local prerequisite={name=required,researched=false};prerequisite.research_recursive=function()prerequisite.researched=true;predecessor_calls=predecessor_calls+1 end;target.prerequisites[required]=prerequisite end end
    if opponent=="added-prerequisite" then target.prerequisites.unexpected={name="unexpected",research_recursive=function()end}end
    force.technologies["braking-force-1"]=technology("braking-force-1")
    for _,required in ipairs({"railway","chemical-science-pack"}) do local prerequisite={name=required,researched=false};prerequisite.research_recursive=function()prerequisite.researched=true;predecessor_calls=predecessor_calls+1 end;force.technologies["braking-force-1"].prerequisites[required]=prerequisite end
    function force.enable_all_prototypes()for _,item in pairs(force.technologies)do item.enabled=true;item.visible_when_disabled=false end end
    function force.add_research(value)
      if type(value)=="string"then value=force.technologies[value]end
      if value==nil or force.current_research~=nil then return false end
      force.research_queue={value};return true
    end
    return force
  end
  local player=make_force("player",1)
  if opponent=="probe-researched" then player.technologies["braking-force-1"].researched=true end
  local foreign,detached=nil,nil
  local game={tick=0,speed=1,forces={player=player,[1]=player},surfaces={}}
  game.surfaces[1]={create_entity=function(row)assert(row.name=="lab" and row.force==player);return lab end}
  function game.create_force(name)
    local index=name=="mir5-competing-dynamic-foreign"and 2 or 3;local value=make_force(name,index);game.forces[name]=value;game.forces[index]=value
    if index==2 then foreign=value else detached=value end;return value
  end
  function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
  local active={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="4.7.20002",["mir-fixture-mir5-competing-dynamic-gameplay"]="0.1.0"}
  if provider=="ce"then active["crafting-efficiency-2"]="0.2.20"else active.ProductivityResearch="1.3.2"end
  local diagnostics={};local storage={};local env={script={active_mods=active,on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage=storage,settings={startup={["mir-prefer-this-mod-for-competing-techs"]={value=false}}},helpers={table_to_json=function(value)if value.status=="passed"then assert(value.stage=="initial"or value.stage=="reload") else assert(value.provider and value.target and value.levels)end;return "{}"end},log=function(value)if value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")then markers=markers+1 elseif value:match("^%[MIR5_DYNAMIC_INITIAL_LEVELS%] ")then diagnostics[#diagnostics+1]=value else error("unexpected fixture log")end end}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)}end
  if opponent=="aggregate-inactive"then lab.aggregate_inactive=true end
  ok,result=pcall(callbacks.init);if not ok then return {ok=false,message=tostring(result)}end
  local target=player.technologies[target_name]
  local expected_level=target.prototype.level+1
  player.research_queue={};target.level=opponent=="wrong-level"and expected_level+1 or expected_level;player.recipes[recipe_name].productivity_bonus=opponent=="wrong-effect"and .09 or .1
  ok,result=pcall(callbacks.events[2],{research=target});if not ok then return {ok=false,message=tostring(result)}end
  game.tick=game.tick+1;ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)}end
  for _=1,2 do ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result)}end;game.tick=game.tick+1;ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)}end end
  local state=storage.mir5_competing_dynamic_gameplay
  return {ok=true,message="",phase=state.phase,labs=state.actual_lab_completions,level=target.level,bonus=player.recipes[recipe_name].productivity_bonus,target_saved=target.saved_progress,current=player.current_research and player.current_research.name or false,current_progress=player.research_progress,probe_saved=player.technologies["braking-force-1"].saved_progress,foreign_disabled=foreign.technologies[target_name].enabled==false,detached_saved=detached.technologies[target_name].saved_progress,lab_disabled_by_script=lab.disabled_by_script,lab_energy=lab.energy,markers=markers,saves=saves,predecessor_calls=predecessor_calls,initial_levels=state.initial_levels,diagnostics=diagnostics}
end
function dynamic_successor_flow(path, provider, target_name, recipe_name, science, ids, initial_levels, fixture, preference, opponent)
  local callbacks,markers,saves={events={}},0,0
  local function inventory()local value={items={}};function value.get_item_count(name)return value.items[name]or 0 end;function value.clear()value.items={}end;return value end
  local input=inventory();local lab={valid=true,disabled_by_script=true,energy=0};function lab.get_inventory(index)assert(index==1);return input end
  local function force(name,index)
    local value={name=name,index=index,valid=true,technologies={},recipes={[recipe_name]={productivity_bonus=.1}},research_progress=0,_queue={}}
    setmetatable(value,{__index=function(item,key)if key=="research_queue"then return rawget(item,"_queue")end end,__newindex=function(item,key,row)if key=="research_queue"then rawset(item,"_queue",row or {});local current=row and row[1]or nil;rawset(item,"current_research",current);if current then rawset(item,"research_progress",current.saved_progress or 0);current.saved_progress=0 else rawset(item,"research_progress",0)end else rawset(item,key,row)end end})
    for _,id in ipairs(ids)do local initial=initial_levels[id]or 1;value.technologies[id]={name=id,valid=true,force=value,level=initial,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295,level=initial}}end
    value.technologies[target_name].level=value.technologies[target_name].prototype.level+1;value.technologies["braking-force-1"]={name="braking-force-1",valid=true,force=value,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,prototype={max_level=4294967295,level=1}}
    return value
  end
  local player,foreign,detached=force("player",1),force("mir5-competing-dynamic-foreign",2),force("mir5-competing-dynamic-detached",3)
  for _,id in ipairs(ids)do foreign.technologies[id].enabled=false;foreign.technologies[id].visible_when_disabled=true end
  local foreign_probe=foreign.technologies["braking-force-1"];foreign_probe.saved_progress=.42;foreign.research_queue={foreign_probe}
  detached.technologies[target_name].saved_progress=.27
  local target,probe=player.technologies[target_name],player.technologies["braking-force-1"]
  target.saved_progress=.27;probe.saved_progress=.42;player.research_queue={probe}
  if preference then for _,id in ipairs(ids)do player.technologies[id].enabled=false;player.technologies[id].visible_when_disabled=true end else for _,id in ipairs(ids)do player.technologies[id].enabled=true;player.technologies[id].visible_when_disabled=false end end
  if opponent=="lost-current"then target.saved_progress=.26 elseif opponent=="foreign-reenabled"then foreign.technologies[target_name].enabled=true elseif opponent=="detached-disabled"then detached.technologies[target_name].enabled=false elseif opponent=="duplicate-effect"then player.recipes[recipe_name].productivity_bonus=.2 end
  local phase=preference and "source-completed" or "prefer-mir-completed"
  local predecessor=provider=="ce" and "ce-iron-gear-wheel-14" or false
  local snapshot={level=player.technologies[target_name].prototype.level+1,researched=false,enabled=player.technologies[target_name].enabled,visible=player.technologies[target_name].visible_when_disabled,maximum=4294967295,saved_progress=.27,bonus=.1}
  local state={provider=provider,source_mir="4.7.20002",fixture_version="0.1.0",predecessor=predecessor,prerequisite_seeding="captured-direct-prerequisites",phase=phase,actual_lab_completions=1,milestone="one-native-dynamic-lab",player_start_bonus=0,player_bonus=.1,current_target_progress=.27,target_initial={technology_level=target.prototype.level,prototype_level=target.prototype.level},foreign_force_index=2,detached_force_index=3,foreign_queue={current="braking-force-1",queue={"braking-force-1"},progress=.42},player_queue={current=target_name,queue={target_name,"braking-force-1"},progress=.27},player_snapshot=snapshot,lab=lab}
  local game={tick=1,forces={player=player,[1]=player,[2]=foreign,[3]=detached,["mir5-competing-dynamic-foreign"]=foreign,["mir5-competing-dynamic-detached"]=detached}}
  function game.server_save(name)assert(name=="mir5-native-complete");saves=saves+1 end
  local active={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-competing-dynamic-gameplay"]=fixture}
  if provider=="ce"then active["crafting-efficiency-2"]="0.2.20"else active.ProductivityResearch="1.3.2"end
  local env={script={active_mods=active,on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage={mir5_competing_dynamic_gameplay=state},settings={startup={["mir-prefer-this-mod-for-competing-techs"]={value=preference}}},helpers={table_to_json=function(value)assert(value.status=="passed"and(value.stage=="initial"or value.stage=="reload"));return "{}"end},log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)}end
  ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result)}end
  ok,result=pcall(callbacks.changed);if not ok then return {ok=false,message=tostring(result)}end
  ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)}end
  ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)}end
  for _=1,2 do ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result)}end;ok,result=pcall(callbacks.events[1]);if not ok then return {ok=false,message=tostring(result)}end end
  return {ok=true,message="",phase=state.phase,markers=markers,saves=saves,target_enabled=target.enabled,target_visible=target.visible_when_disabled,target_saved=target.saved_progress,current=player.current_research and player.current_research.name or false,current_progress=player.research_progress,bonus=player.recipes[recipe_name].productivity_bonus,foreign_enabled=foreign.technologies[target_name].enabled,detached_enabled=detached.technologies[target_name].enabled}
end
''')

    def provider_ids(self, provider):
        return [row["id"] for row in self.providers[provider]["bindings"]]

    def test_profiles_and_facts_bind_two_exact_independent_provider_chains(self):
        self.assertEqual((1, 40018079589, 71), (self.facts["schema"], self.facts["run"], self.facts["binding_count"]))
        self.assertEqual({"crafting-efficiency", "productivity-research", "prfe", "prfe-fg"}, set(self.providers))
        self.assertEqual((28, 43, 0, 0), tuple(len(self.providers[key]["bindings"]) for key in ("crafting-efficiency", "productivity-research", "prfe", "prfe-fg")))
        self.assertTrue(self.providers["crafting-efficiency"]["default_preference_admission"])
        self.assertTrue(self.providers["productivity-research"]["default_preference_admission"])
        self.assertEqual((ARCHIVES["ce"][0], ARCHIVES["ce"][1], ARCHIVES["ce"][2], ARCHIVES["ce"][3]),
                         (self.providers["crafting-efficiency"]["name"], self.providers["crafting-efficiency"]["version"], self.providers["crafting-efficiency"]["archive"], self.providers["crafting-efficiency"]["archive_sha256"]))
        self.assertEqual((ARCHIVES["pr"][0], ARCHIVES["pr"][1], ARCHIVES["pr"][2], ARCHIVES["pr"][3]),
                         (self.providers["productivity-research"]["name"], self.providers["productivity-research"]["version"], self.providers["productivity-research"]["archive"], self.providers["productivity-research"]["archive_sha256"]))
        for profile in PROFILES:
            data = json.loads(profile.read_text(encoding="utf-8"))
            mods = {row["name"]: row["version"] for row in data["mods"]}
            provider = "ce" if "-ce-" in profile.name else "pr"
            name, version, archive, digest = ARCHIVES[provider]
            stage = next(item for item in STAGES if f"-{item[0]}-" in profile.name)
            self.assertEqual(("f200", "2.0", "2.0.77", ENGINE_SHA), (data["target"], data["factorio_line"], data["engine"]["version"], data["engine"]["sha256"]))
            self.assertEqual(["base", "elevated-rails", "quality", "space-age", name, OBSERVER, "more-infinite-research", NAME],
                             [row["name"] for row in data["mods"]])
            self.assertEqual((name, version), (next(row["name"] for row in data["mods"] if row["name"] == name), mods[name]))
            self.assertEqual((stage[2], stage[3]), (mods["more-infinite-research"], mods[NAME]))
            self.assertEqual(digest, data["archive_sha256"][archive])
            self.assertEqual("723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87", data["archive_sha256"][f"{OBSERVER}_0.1.0.zip"])
            self.assertNotIn(ARCHIVES["pr" if provider == "ce" else "ce"][0], mods)
            info = json.loads((FIXTURE / provider / stage[1] / "info.json").read_text(encoding="utf-8"))
            self.assertEqual((NAME, stage[3], "2.0"), (info["name"], info["version"], info["factorio_version"]))
            dependencies = set(info["dependencies"])
            self.assertIn(f"{name} = {version}", dependencies)
            self.assertIn(f"more-infinite-research = {stage[2]}", dependencies)
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        blocks = {
            "ce": control.split("ce = {", 1)[1].split("  },\n  pr = {", 1)[0],
            "pr": control.split("pr = {", 1)[1].split("  },\n}", 1)[0],
        }
        for provider, fact_key in (("ce", "crafting-efficiency"), ("pr", "productivity-research")):
            literal_ids = re.findall(r'"([^\"]+)"', blocks[provider].split("ids = {", 1)[1])
            self.assertEqual(self.provider_ids(fact_key), literal_ids)
        native_literals = {
            name: int(level)
            for name, level in re.findall(r'\["([^\"]+)"\]\s*=\s*(\d+),',
                                          control.split("local CE_INITIAL_LEVELS = {", 1)[1].split("}\n\nlocal PROVIDERS", 1)[0])
        }
        self.assertEqual(self.native_initial_levels["crafting-efficiency"], native_literals)
        self.assertEqual(19, native_literals[TARGETS["ce"]["target"]])

    def test_captured_source_rows_preflight_before_only_count_time_acceleration(self):
        run = self.lua.eval("dynamic_fixture_data")
        for provider in ("ce", "pr"):
            helper = FIXTURE / provider / "data-final-common.lua"
            for _, stage, mir, _, _ in STAGES:
                with self.subTest(provider=provider, stage=stage):
                    before = deepcopy(SOURCE_ROWS[provider])
                    result = run(str(FIXTURE / provider / stage / "data-final-fixes.lua"), str(helper), provider, mir,
                                 lua_value(self.lua, before))
                    self.assertTrue(result["ok"], result["message"])
                    actual = plain(result["row"])
                    self.assertEqual((None, "1", 1), (actual["unit"].get("count"), actual["unit"]["count_formula"], actual["unit"]["time"]))
                    expected = deepcopy(before); expected["unit"] = deepcopy(expected["unit"]); expected["unit"].update({"count_formula": "1", "time": 1})
                    self.assertEqual(expected, actual)
                    self.assertEqual('return require("data-final-common")\n',
                                     (FIXTURE / provider / stage / "data-final-fixes.lua").read_text(encoding="utf-8"))
        bad = deepcopy(SOURCE_ROWS["ce"]); bad["effects"][0]["change"] = .2
        result = run(str(FIXTURE / "ce/published/data-final-fixes.lua"), str(FIXTURE / "ce/data-final-common.lua"), "ce", "4.7.20002",
                     lua_value(self.lua, bad))
        self.assertFalse(result["ok"])
        self.assertIn("CE effect changed", result["message"])
        self.assertEqual(("1200 * 1.5 * l", 45), (plain(result["row"])["unit"]["count_formula"], plain(result["row"])["unit"]["time"]))
        bad = deepcopy(SOURCE_ROWS["pr"]); bad["prerequisites"] = ["unexpected"]
        result = run(str(FIXTURE / "pr/published/data-final-fixes.lua"), str(FIXTURE / "pr/data-final-common.lua"), "pr", "4.7.20002",
                     lua_value(self.lua, bad))
        self.assertFalse(result["ok"])
        self.assertIn("empty prerequisites", result["message"])
        bad = deepcopy(SOURCE_ROWS["ce"])
        result = run(str(FIXTURE / "ce/mir5-prefer-mir/data-final-fixes.lua"), str(FIXTURE / "ce/data-final-common.lua"), "ce", "5.0.20001",
                     lua_value(self.lua, bad))
        self.assertFalse(result["ok"])
        self.assertIn("unexpected CE fixture closure", result["message"])

    def test_shared_control_parses_without_runtime_access_and_on_load_only_reads_snapshots(self):
        parse = self.lua.eval("dynamic_fixture_parse")
        load = self.lua.eval("dynamic_on_load")
        for provider in ("ce", "pr"):
            for _, _, mir, fixture, _ in STAGES:
                with self.subTest(provider=provider, fixture=fixture):
                    result = parse(str(FIXTURE / "control.lua"), provider, mir, fixture)
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual({}, plain(result["reads"]))
                    self.assertIsNotNone(result["callbacks"]["load"])
                    self.assertIsNotNone(result["callbacks"]["events"][1])
                    self.assertTrue(load(str(FIXTURE / "control.lua"), provider, "source-completed")["ok"])
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        body = control.split("script.on_load(function()", 1)[1].split("script.on_event(defines.events.on_tick", 1)[0]
        self.assertNotIn("game.", body)
        self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=")
        self.assertNotIn("research_queue_enabled", control)
        self.assertIn("source lab was not frozen before successor preference", control)

    def test_source_uses_one_real_representative_lab_then_freezes_and_saves_current_work(self):
        run = self.lua.eval("dynamic_source_flow")
        for provider, fact_key in (("ce", "crafting-efficiency"), ("pr", "productivity-research")):
            target = TARGETS[provider]
            with self.subTest(provider=provider):
                result = run(str(FIXTURE / "control.lua"), provider, target["target"], target["predecessor"], lua_value(self.lua, target["prerequisites"]), target["recipe"], lua_value(self.lua, target["science"]), lua_value(self.lua, self.provider_ids(fact_key)), lua_value(self.lua, self.native_initial_levels[fact_key]), "")
                self.assertTrue(result["ok"], result["message"])
                self.assertEqual(("source-completed", 1, target["initial_level"] + 1, .1, 0, target["target"], .27, .42, .27, True, 0, 3, 1),
                                 (result["phase"], result["labs"], result["level"], result["bonus"], result["target_saved"], result["current"], result["current_progress"], result["probe_saved"], result["detached_saved"], result["lab_disabled_by_script"], result["lab_energy"], result["markers"], result["saves"]))
                self.assertTrue(result["foreign_disabled"])
                self.assertEqual(18 if provider == "ce" else 4, result["predecessor_calls"])
                self.assertEqual(
                    [{"id": name, "technology_level": self.native_initial_levels[fact_key][name], "prototype_level": self.native_initial_levels[fact_key][name]}
                     for name in self.provider_ids(fact_key)],
                    plain(result["initial_levels"]),
                )
                self.assertEqual(1, len(plain(result["diagnostics"])))
        ce = TARGETS["ce"]
        pr = TARGETS["pr"]
        opponents = (
            ("ce", ce, "missing-predecessor", "captured target direct prerequisite count changed"),
            ("pr", pr, "added-prerequisite", "captured target direct prerequisite count changed"),
            ("ce", ce, "probe-researched", "unrelated probe was researched"),
            ("pr", pr, "wrong-effect", "native target completion/effect differs"),
            ("ce", ce, "aggregate-inactive", "lab cannot consume native science"),
        )
        for provider, target, opponent, phrase in opponents:
            with self.subTest(provider=provider, opponent=opponent):
                fact_key = "crafting-efficiency" if provider == "ce" else "productivity-research"
                result = run(str(FIXTURE / "control.lua"), provider, target["target"], target["predecessor"], lua_value(self.lua, target["prerequisites"]), target["recipe"], lua_value(self.lua, target["science"]), lua_value(self.lua, self.provider_ids(fact_key)), lua_value(self.lua, self.native_initial_levels[fact_key]), opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
        result = run(str(FIXTURE / "control.lua"), "ce", ce["target"], ce["predecessor"],
                     lua_value(self.lua, ce["prerequisites"]), ce["recipe"], lua_value(self.lua, ce["science"]),
                     lua_value(self.lua, self.provider_ids("crafting-efficiency")), lua_value(self.lua, self.native_initial_levels["crafting-efficiency"]), "wrong-level")
        self.assertFalse(result["ok"])
        self.assertIn("expected_level=20 actual_level=21", result["message"])
        self.assertIn("prototype_level=19", result["message"])
        self.assertIn("baseline_bonus=0", result["message"])
        self.assertIn("actual_bonus=0.1", result["message"])
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertLess(control.index("capture_initial_levels(player, config)"),
                        control.index("verify_and_seed_prerequisites(target, config.prerequisites"))

    def test_preference_chain_preserves_paused_current_foreign_and_earned_output_without_duplication(self):
        run = self.lua.eval("dynamic_successor_flow")
        for provider, fact_key in (("ce", "crafting-efficiency"), ("pr", "productivity-research")):
            target = TARGETS[provider]
            for fixture, preference, phase, enabled, visible in (("0.2.0", True, "prefer-mir-completed", False, True), ("0.3.0", False, "prefer-foreign-completed", True, False)):
                with self.subTest(provider=provider, fixture=fixture):
                    result = run(str(FIXTURE / "control.lua"), provider, target["target"], target["recipe"], lua_value(self.lua, target["science"]), lua_value(self.lua, self.provider_ids(fact_key)), lua_value(self.lua, self.native_initial_levels[fact_key]), fixture, preference, "")
                    self.assertTrue(result["ok"], result["message"])
                    self.assertEqual((phase, 3, 1, enabled, visible, .27, "braking-force-1", .42, .1, False, True),
                                     (result["phase"], result["markers"], result["saves"], result["target_enabled"], result["target_visible"], result["target_saved"], result["current"], result["current_progress"], result["bonus"], result["foreign_enabled"], result["detached_enabled"]))
        target = TARGETS["ce"]
        for opponent, phrase in (
            ("lost-current", "target bonus/progress differs"),
            ("foreign-reenabled", "foreign enabled differs"),
            ("detached-disabled", "detached partial target differs"),
            ("duplicate-effect", "target bonus/progress differs"),
        ):
            result = run(str(FIXTURE / "control.lua"), "ce", target["target"], target["recipe"], lua_value(self.lua, target["science"]), lua_value(self.lua, self.provider_ids("crafting-efficiency")), lua_value(self.lua, self.native_initial_levels["crafting-efficiency"]), "0.2.0", True, opponent)
            self.assertFalse(result["ok"])
            self.assertIn(phrase, result["message"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args, extra = parser.parse_known_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *extra])
