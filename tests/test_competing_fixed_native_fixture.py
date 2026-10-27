# Host controls for the prepared F200 Space Age fixed-provider save chain.
# These controls use a native-shaped mock only; no Factorio process or native
# transition is run here.
from copy import deepcopy
import argparse
import sys
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/competing-fixed-gameplay"
FACTS = ROOT / "tests/fixtures/competing-fixed-f200-sa-captured-facts.json"
PROFILES = tuple(ROOT / "tests/profiles" / name for name in (
    "competing-fixed-published-4.7-f200-sa-2077.json",
    "competing-fixed-mir5-prefer-mir-f200-sa-2077.json",
    "competing-fixed-mir5-prefer-foreign-f200-sa-2077.json",
    "competing-fixed-mir5-prefer-mir-again-f200-sa-2077.json",
    "competing-fixed-mir5-prefer-foreign-providers-removed-f200-sa-2077.json",
    "competing-fixed-mir5-prefer-foreign-providers-readded-f200-sa-2077.json",
))
FIXTURE_NAME = "mir-fixture-mir5-competing-fixed-gameplay"
SUCCESSOR_ROLES = {
    "mir5-prefer-mir": "successor-prefer-mir",
    "mir5-prefer-foreign": "successor-prefer-foreign",
    "mir5-prefer-mir-again": "successor-prefer-mir-again",
    "mir5-prefer-foreign-providers-removed": "successor-prefer-foreign-providers-removed",
    "mir5-prefer-foreign-providers-readded": "successor-prefer-foreign-providers-readded",
}


def fixture_role(stage):
    return SUCCESSOR_ROLES.get(stage, stage)
FOREIGN_DATA = FIXTURE / "foreign-data.lua"
FULL_BIOFLUX_DATA = FIXTURE / "full-bioflux-data.lua"
ALL = ("basic-plate-productivity", "electric-circuit-productivity", "advanced-circuit-productivity",
       "automation-science-productivity-4", "logistic-science-productivity-4", "military-science-productivity-4",
       "chemical-science-productivity-4", "production-science-productivity-4", "utility-science-productivity-4",
       "space-science-productivity-4", "metallurgic-science-productivity-4", "electromagnetic-science-productivity-4",
       "agricultural-science-productivity-4", "cryogenic-science-productivity-4", "promethium-science-productivity-4",
       "bioflux-productivity", "fish-breeding-productivity")
EXPECTED = {
    "plates": {"basic-plate-productivity": (("advanced-material-processing",), ("copper-plate", "iron-plate"), "2500+2500*(L-1)", 30, (("automation-science-pack", 1), ("logistic-science-pack", 1)))},
    "science-packs": {"automation-science-productivity-4": (("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack", "productivity-module-3", "promethium-science-pack", "automation-science-productivity-3"), ("automation-science-pack",), "100000*(L - 3)", 60, (("automation-science-pack", 2), ("logistic-science-pack", 1), ("chemical-science-pack", 1), ("production-science-pack", 1), ("utility-science-pack", 1), ("space-science-pack", 1), ("promethium-science-pack", 1)))},
    "bioflux": {"bioflux-productivity": (("bioflux", "production-science-pack"), ("bioflux",), "2^L*600", 60, (("automation-science-pack", 1), ("logistic-science-pack", 1), ("chemical-science-pack", 1), ("production-science-pack", 1), ("agricultural-science-pack", 1)))},
    "fish": {"fish-breeding-productivity": (("fish-breeding",), ("fish-breeding",), "1.5^L*1000-500", 60, (("space-science-pack", 1), ("agricultural-science-pack", 1)))},
}

def lua_value(lua, value):
    if isinstance(value, dict): return lua.table_from({key: lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, (tuple, list)): return lua.table_from([lua_value(lua, item) for item in value])
    return value

def plain(value, seen=None):
    if not hasattr(value, "items"): return value
    seen = set() if seen is None else seen
    if id(value) in seen: raise AssertionError("cyclic Lua fixture value")
    seen.add(id(value)); keys = list(value.keys())
    if keys and all(isinstance(key, int) and key > 0 for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        output = [plain(value[index], seen) for index in range(1, len(keys) + 1)]
    else: output = {key: plain(item, seen) for key, item in value.items()}
    seen.remove(id(value)); return output

class CompetingFixedNativeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS.read_text(encoding="utf-8"))
        cls.providers = {item["key"]: item for item in cls.facts["providers"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
local function fixture_require(env, foreign_path, bioflux_path)
  local loaded = {}
  return function(name)
    local path = name == "foreign-data" and foreign_path
      or name == "full-bioflux-data" and bioflux_path
    if path == nil then error("unexpected fixture module: " .. tostring(name)) end
    if loaded[name] then return true end
    loaded[name] = true
    local chunk, message = loadfile(path, "t", env)
    assert(chunk, message)
    local result = chunk()
    return result == nil and true or result
  end
end
function fixed_data(path, foreign_data_path, rows)
  local raw={technology=rows,["bool-setting"]={["mir-prefer-this-mod-for-competing-techs"]={default_value=true}}}
  local env={mods={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="4.7.20002",["plates-n-circuit-productivity"]="0.0.2",Science_packs_productivity="0.0.1",["bioflux-productivity"]="0.1.0",["fish-productivity"]="1.0.0"},data={raw=raw}}
  env.require=fixture_require(env, foreign_data_path, nil);env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local update=path:gsub("data%-final%-fixes%.lua$","settings-updates.lua")
  local chunk,message=loadfile(update,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result),raw=raw} end
  chunk,message=loadfile(path,"t",env);assert(chunk,message);ok,result=pcall(chunk);return {ok=ok,message=tostring(result),raw=raw}
end
function fixed_mir_data(path, foreign_data_path, bioflux_data_path, fixture, preference, mir_rows, foreign_rows, providers_present)
  local raw={technology=foreign_rows,["bool-setting"]={["mir-prefer-this-mod-for-competing-techs"]={default_value=preference}}}
  for name,row in pairs(mir_rows) do raw.technology[name]=row end
  local mods={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-competing-fixed-gameplay"]=fixture}
  if providers_present~=false then mods["plates-n-circuit-productivity"]="0.0.2";mods.Science_packs_productivity="0.0.1";mods["bioflux-productivity"]="0.1.0";mods["fish-productivity"]="1.0.0" end
  local env={mods=mods,data={raw=raw}}
  env.require=fixture_require(env, foreign_data_path, bioflux_data_path);env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local update=path:gsub("data%-final%-fixes%.lua$","settings-updates.lua")
  local chunk,message=loadfile(update,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result),raw=raw}end
  chunk,message=loadfile(path,"t",env);assert(chunk,message);ok,result=pcall(chunk);return {ok=ok,message=tostring(result),raw=raw}
end
function fixed_setting(path, mir, providers_present)
  local raw={["bool-setting"]={["mir-prefer-this-mod-for-competing-techs"]={default_value=false}}}
  local mods={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]=mir}
  if providers_present~=false then mods["plates-n-circuit-productivity"]="0.0.2";mods.Science_packs_productivity="0.0.1";mods["bioflux-productivity"]="0.1.0";mods["fish-productivity"]="1.0.0" end
  local env={mods=mods,data={raw=raw}}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),value=raw["bool-setting"]["mir-prefer-this-mod-for-competing-techs"].default_value}
end
function fixed_parse(path, mir, fixture, providers_present)
  local callbacks,reads={events={}},{ }
  local mods={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]=mir,["mir-fixture-mir5-competing-fixed-gameplay"]=fixture}
  if providers_present~=false then mods["plates-n-circuit-productivity"]="0.0.2";mods.Science_packs_productivity="0.0.1";mods["bioflux-productivity"]="0.1.0";mods["fish-productivity"]="1.0.0" end
  local env={script={active_mods=mods,on_init=function(f)callbacks.init=f end,on_configuration_changed=function(f)callbacks.changed=f end,on_load=function(f)callbacks.load=f end,on_event=function(e,f)callbacks.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}}
  env._G=env;setmetatable(env,{__index=function(_,key)if key=="game" or key=="storage" or key=="settings" then reads[key]=(reads[key]or 0)+1 end;return _G[key]end})
  local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk);return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end
''')
        self.lua.execute(r'''
function fixed_successor(path, fixture, stage, opponent)
  local ids={"basic-plate-productivity","electric-circuit-productivity","advanced-circuit-productivity","automation-science-productivity-4","logistic-science-productivity-4","military-science-productivity-4","chemical-science-productivity-4","production-science-productivity-4","utility-science-productivity-4","space-science-productivity-4","metallurgic-science-productivity-4","electromagnetic-science-productivity-4","agricultural-science-productivity-4","cryogenic-science-productivity-4","promethium-science-productivity-4","bioflux-productivity","fish-breeding-productivity"}
  local breeding="recipe-prod-research_breeding-1"
  local full_bioflux="recipe-prod-research_bioflux-1"
  local function inventory() local value={}; function value.get_item_count(_) return 0 end; function value.insert(stack) return stack.count end; function value.clear() end; return value end
  local lab={valid=true,disabled_by_script=true,energy=0}; function lab.get_inventory(_) return inventory() end
  local function queue(force, entries)
    rawset(force,"_queue",entries or {}); local current=entries and entries[1] or nil; rawset(force,"current_research",current)
    if current then rawset(force,"research_progress",current.saved_progress or 0); current.saved_progress=0 else rawset(force,"research_progress",0) end
  end
  local function research(force, id, level)
    return {name=id,valid=true,force=force,level=level or 1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
      prototype={max_level=4294967295},prerequisites={},research_unit_count=1,research_unit_energy=60,
      research_unit_ingredients={{name="automation-science-pack",amount=1}}}
  end
  local function force(name,index)
    local value={name=name,index=index,valid=true,technologies={},recipes={},_queue={},research_progress=0}
    setmetatable(value,{__index=function(item,key) if key=="research_queue" then return rawget(item,"_queue") end end,
      __newindex=function(item,key,row) if key=="research_queue" then queue(item,row) else rawset(item,key,row) end end})
    for _,recipe in ipairs({"automation-science-pack","copper-plate","iron-plate","bioflux","fish-breeding","biter-egg","pentapod-egg"}) do value.recipes[recipe]={productivity_bonus=0} end
    for _,id in ipairs(ids) do value.technologies[id]=research(value,id,id:match("%-4$") and 4 or 1) end
    value.technologies[breeding]=research(value,breeding,1)
    value.technologies["braking-force-1"]=research(value,"braking-force-1",1)
    return value
  end
  local player,foreign,detached=force("player",1),force("mir5-competing-fixed-foreign",2),force("mir5-competing-fixed-detached",3)
  -- Captured published false-preference input omits this MIR row.  Materializing
  -- the MIR5 true successor introduces it only after that predecessor witness.
  if opponent=="old-predecessor-has-full" then player.technologies[full_bioflux]=research(player,full_bioflux,1) end
  if player.technologies[full_bioflux]~=nil or foreign.technologies[full_bioflux]~=nil then
    return {ok=false,message="published false-preference predecessor unexpectedly contains fully covered MIR bioflux"}
  end
  if opponent=="missing-mir5-introduction" then
    return {ok=false,message="MIR5 true data did not introduce fully covered MIR bioflux"}
  end
  local function introduce_mir5_full_row(value)
    value.technologies[full_bioflux]=research(value,full_bioflux,1)
  end
  introduce_mir5_full_row(player); introduce_mir5_full_row(foreign); introduce_mir5_full_row(detached)
  for _,id in ipairs({"automation-science-productivity-4","basic-plate-productivity","bioflux-productivity","fish-breeding-productivity"}) do player.technologies[id].level=player.technologies[id].level+1 end
  for _,recipe in ipairs({"automation-science-pack","copper-plate","iron-plate","bioflux","fish-breeding"}) do player.recipes[recipe].productivity_bonus=.1 end
  local electric,probe=player.technologies["electric-circuit-productivity"],player.technologies["braking-force-1"]
  probe.saved_progress=.42; player.research_queue={electric,probe}; player.research_progress=.27
  for _,id in ipairs(ids) do foreign.technologies[id].enabled=false; foreign.technologies[id].visible_when_disabled=true end
  local foreign_probe=foreign.technologies["braking-force-1"]; foreign.research_queue={foreign_probe}; foreign.research_progress=.42
  detached.technologies["basic-plate-productivity"].saved_progress=.27
  local successor_has_full = stage~="true"
  if successor_has_full then foreign.technologies[full_bioflux].enabled=false; foreign.technologies[full_bioflux].visible_when_disabled=false end
  local state={source_mir="4.7.20002",fixture_version="0.1.0",actual_lab_completions=4,milestone="four-native-fixed-provider-labs",prerequisite_seeding="completed-before-native-labs",player_effects={['automation-science-pack']=.1,['copper-plate']=.1,['iron-plate']=.1,bioflux=.1,['fish-breeding']=.1},foreign_force_index=2,detached_force_index=3,foreign_queue={current="braking-force-1",queue={"braking-force-1"},progress=.42},foreign_current_saved_progress=0,player_queue={current="electric-circuit-productivity",queue={"electric-circuit-productivity","braking-force-1"},progress=.27},probe_inactive_saved_progress=.42,lab=lab,full_mir_bioflux_introduced=successor_has_full,foreign_full_mir_bioflux_initialized=successor_has_full}
  if stage=="true" then
    for _,id in ipairs(ids) do if id~="electric-circuit-productivity" then player.technologies[id].enabled=false; player.technologies[id].visible_when_disabled=true end end
    state.phase="source-completed"
  elseif stage=="false" then
    player.technologies[full_bioflux].level=2; player.technologies[full_bioflux].enabled=false
    player.technologies[breeding].level=2; player.recipes["bioflux"].productivity_bonus=.2; player.recipes["fish-breeding"].productivity_bonus=.2; player.recipes["biter-egg"].productivity_bonus=.1; player.recipes["pentapod-egg"].productivity_bonus=.1
    for _,id in ipairs(ids) do player.technologies[id].enabled=true; player.technologies[id].visible_when_disabled=false end
    state.phase="prefer-mir-breeding-completed"; state.full_mir_actual_lab_completions=1; state.true_bioflux_effects={bioflux=.2}; state.true_breeding_effects={['fish-breeding']=.2,['biter-egg']=.1,['pentapod-egg']=.1}
  else
    -- The successor lifecycle has a recorded false-stage disablement right and
    -- restores only that exact full-row presentation before this observer runs.
    player.technologies[full_bioflux].level=2; player.technologies[full_bioflux].enabled=true
    player.technologies[breeding].level=3; player.recipes["bioflux"].productivity_bonus=.2; player.recipes["fish-breeding"].productivity_bonus=.2; player.recipes["biter-egg"].productivity_bonus=.2; player.recipes["pentapod-egg"].productivity_bonus=.2
    for _,id in ipairs(ids) do if id~="electric-circuit-productivity" then player.technologies[id].enabled=false; player.technologies[id].visible_when_disabled=true end end
    state.phase="prefer-foreign-breeding-completed"; state.full_mir_actual_lab_completions=1; state.true_bioflux_effects={bioflux=.2}; state.true_breeding_effects={['fish-breeding']=.2,['biter-egg']=.1,['pentapod-egg']=.1}; state.false_breeding_effects={['fish-breeding']=.2,['biter-egg']=.2,['pentapod-egg']=.2}
  end
  if opponent=="detached-disabled" then detached.technologies["basic-plate-productivity"].enabled=false
  elseif opponent=="lost-current" then player.research_progress=.26
  elseif opponent=="foreign-reenabled" then foreign.technologies["bioflux-productivity"].enabled=true
  elseif opponent=="lost-earned-provider" then player.recipes["automation-science-pack"].productivity_bonus=player.recipes["automation-science-pack"].productivity_bonus-.01
  elseif opponent=="lost-earned-fish" then player.recipes["fish-breeding"].productivity_bonus=player.recipes["fish-breeding"].productivity_bonus-.01
  elseif opponent=="lost-earned-full" then player.recipes["bioflux"].productivity_bonus=player.recipes["bioflux"].productivity_bonus-.01
  elseif opponent=="lost-full-lab" then state.full_mir_actual_lab_completions=0
  elseif opponent=="full-reenabled-on-false" then player.technologies[full_bioflux].enabled=true
  elseif opponent=="full-still-disabled-again" then player.technologies[full_bioflux].enabled=false end
  local saves,markers=0,0; local game={tick=1,forces={player=player,[1]=player,[2]=foreign,[3]=detached,["mir5-competing-fixed-foreign"]=foreign,["mir5-competing-fixed-detached"]=detached}}
  function game.server_save(name) assert(name=="mir5-native-complete"); saves=saves+1 end
  local c={events={}}; local fixture_version=stage=="true" and "0.2.0" or (stage=="false" and "0.3.0" or "0.4.0")
  if fixture~=fixture_version then return {ok=false,message="fixture version does not match transition stage"} end
  local preference=stage~="false"
  local env={script={active_mods={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="5.0.20000",["plates-n-circuit-productivity"]="0.0.2",Science_packs_productivity="0.0.1",["bioflux-productivity"]="0.1.0",["fish-productivity"]="1.0.0",["mir-fixture-mir5-competing-fixed-gameplay"]=fixture_version},on_init=function(f)c.init=f end,on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,on_event=function(e,f)c.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage={mir5_competing_fixed_gameplay=state},settings={startup={["mir-prefer-this-mod-for-competing-techs"]={value=preference}}},helpers={table_to_json=function(v) if v[1] then assert(#v==3 and v[1].name==breeding) else assert(v.status=="passed" and (v.stage=="initial" or v.stage=="reload")) end; return "{}" end},log=function(v) if v:match("^%[MIR5_NATIVE_FIXTURE%] CREDIT_TRANSITION ") then return end; assert(v:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")); markers=markers+1 end}
  env._G=env; setmetatable(env,{__index=function(_,key)return _G[key]end}); local chunk,message=loadfile(path,"t",env); assert(chunk,message); local ok,result=pcall(chunk); if not ok then return {ok=false,message=tostring(result)} end
  c.load(); ok,result=pcall(c.changed); if not ok then return {ok=false,message=tostring(result)} end
  if opponent=="foreign-full-reenabled" then foreign.technologies[full_bioflux].enabled=true end
  local function complete(name, recipes)
    local value=player.current_research
    if value==nil or value.name~=name then return false,"fixture did not queue "..name end
    value.level=value.level+1
    for _,recipe in ipairs(recipes) do player.recipes[recipe].productivity_bonus=player.recipes[recipe].productivity_bonus+.1 end
    player.research_queue={electric,probe}
    local event_ok,event_result=pcall(c.events[2],{research=value}); if not event_ok then return false,tostring(event_result) end
    event_ok,event_result=pcall(c.events[1]); if not event_ok then return false,tostring(event_result) end
    return true,""
  end
  if stage=="true" then
    local done,message=complete(full_bioflux,{"bioflux"}); if not done then return {ok=false,message=message} end
    done,message=complete(breeding,{"biter-egg","fish-breeding","pentapod-egg"}); if not done then return {ok=false,message=message} end
  elseif stage=="false" then
    local done,message=complete(breeding,{"biter-egg","pentapod-egg"}); if not done then return {ok=false,message=message} end
  end
  ok,result=pcall(c.events[1]); if not ok then return {ok=false,message=tostring(result)} end
  for _=1,2 do ok,result=pcall(c.load); if not ok then return {ok=false,message=tostring(result)} end; ok,result=pcall(c.events[1]); if not ok then return {ok=false,message=tostring(result)} end end
  return {ok=true,message="",phase=state.phase,markers=markers,saves=saves,breed_level=player.technologies[breeding].level,fish=player.recipes["fish-breeding"].productivity_bonus,biter=player.recipes["biter-egg"].productivity_bonus,pentapod=player.recipes["pentapod-egg"].productivity_bonus,full_labs=state.full_mir_actual_lab_completions,full_level=player.technologies[full_bioflux].level,full_enabled=player.technologies[full_bioflux].enabled,full_bonus=player.recipes["bioflux"].productivity_bonus,progress=player.research_progress}
end

function fixed_provider_removal_readdition(path, opponent)
  local ids={"basic-plate-productivity","electric-circuit-productivity","advanced-circuit-productivity","automation-science-productivity-4","logistic-science-productivity-4","military-science-productivity-4","chemical-science-productivity-4","production-science-productivity-4","utility-science-productivity-4","space-science-productivity-4","metallurgic-science-productivity-4","electromagnetic-science-productivity-4","agricultural-science-productivity-4","cryogenic-science-productivity-4","promethium-science-productivity-4","bioflux-productivity","fish-breeding-productivity"}
  local breeding,full_bioflux="recipe-prod-research_breeding-1","recipe-prod-research_bioflux-1"
  local function inventory() local value={}; function value.get_item_count(_) return 0 end; function value.insert(stack) return stack.count end; function value.clear() end; return value end
  local lab={valid=true,disabled_by_script=true,energy=0}; function lab.get_inventory(_) return inventory() end
  local function queue(force, entries)
    rawset(force,"_queue",entries or {}); local current=entries and entries[1] or nil; rawset(force,"current_research",current)
    if current then rawset(force,"research_progress",current.saved_progress or 0); current.saved_progress=0 else rawset(force,"research_progress",0) end
  end
  local function research(force, id, level)
    return {name=id,valid=true,force=force,level=level or 1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
      prototype={max_level=4294967295},prerequisites={},research_unit_count=1,research_unit_energy=60,
      research_unit_ingredients={{name="automation-science-pack",amount=1}}}
  end
  local function force(name,index)
    local value={name=name,index=index,valid=true,technologies={},recipes={},_queue={},research_progress=0}
    setmetatable(value,{__index=function(item,key) if key=="research_queue" then return rawget(item,"_queue") end end,
      __newindex=function(item,key,row) if key=="research_queue" then queue(item,row) else rawset(item,key,row) end end})
    for _,recipe in ipairs({"automation-science-pack","copper-plate","iron-plate","bioflux","fish-breeding","biter-egg","pentapod-egg"}) do value.recipes[recipe]={productivity_bonus=0} end
    value.technologies[breeding]=research(value,breeding,1); value.technologies[full_bioflux]=research(value,full_bioflux,1)
    value.technologies["braking-force-1"]=research(value,"braking-force-1",1)
    return value
  end
  local player,foreign,detached=force("player",1),force("mir5-competing-fixed-foreign",2),force("mir5-competing-fixed-detached",3)
  local orphan_electric=research(player,"electric-circuit-productivity",1)
  local probe=player.technologies["braking-force-1"]
  probe.saved_progress=.42; player.research_queue={orphan_electric,probe}; player.research_progress=.27
  player.technologies[full_bioflux].level=2; player.technologies[breeding].level=3
  player.recipes.bioflux.productivity_bonus=.1; player.recipes["fish-breeding"].productivity_bonus=.1; player.recipes["biter-egg"].productivity_bonus=.2; player.recipes["pentapod-egg"].productivity_bonus=.2
  local foreign_probe=foreign.technologies["braking-force-1"]; foreign_probe.saved_progress=.42; foreign.research_queue={foreign_probe}; foreign.research_progress=.42
  foreign.technologies[full_bioflux].enabled=false
  local state={phase="prefer-mir-again-completed",source_mir="4.7.20002",fixture_version="0.1.0",actual_lab_completions=4,milestone="four-native-fixed-provider-labs",prerequisite_seeding="completed-before-native-labs",foreign_force_index=2,detached_force_index=3,foreign_queue={current="braking-force-1",queue={"braking-force-1"},progress=.42},foreign_current_saved_progress=0,player_queue={current="electric-circuit-productivity",queue={"electric-circuit-productivity","braking-force-1"},progress=.27},lab=lab,full_mir_bioflux_introduced=true,foreign_full_mir_bioflux_initialized=true,full_mir_actual_lab_completions=1,true_bioflux_effects={bioflux=.2},true_breeding_effects={["fish-breeding"]=.2,["biter-egg"]=.1,["pentapod-egg"]=.1},false_breeding_effects={["fish-breeding"]=.2,["biter-egg"]=.2,["pentapod-egg"]=.2}}
  local saves,markers=0,0; local game={tick=1,forces={player=player,[1]=player,[2]=foreign,[3]=detached,["mir5-competing-fixed-foreign"]=foreign,["mir5-competing-fixed-detached"]=detached}}
  function game.server_save(name) assert(name=="mir5-native-complete"); saves=saves+1 end
  local c={events={}}; local active={base="2.0.77",["space-age"]="2.0.77",["more-infinite-research"]="5.0.20000",["mir-fixture-mir5-competing-fixed-gameplay"]="0.5.0"}
  local setting={value=false}
  local env={script={active_mods=active,on_init=function(f)c.init=f end,on_configuration_changed=function(f)c.changed=f end,on_load=function(f)c.load=f end,on_event=function(e,f)c.events[e]=f end},defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},game=game,storage={mir5_competing_fixed_gameplay=state},settings={startup={['mir-prefer-this-mod-for-competing-techs']=setting}},helpers={table_to_json=function(v) assert(v.status=="passed" and (v.stage=="initial" or v.stage=="reload")); return "{}" end},log=function(v) assert(v:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")); markers=markers+1 end}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end});local chunk,message=loadfile(path,"t",env);assert(chunk,message);local ok,result=pcall(chunk);if not ok then return {ok=false,message=tostring(result)} end
  if opponent=="removed-provider-still-present" then active["fish-productivity"]="1.0.0"
  elseif opponent=="lost-provider-absent-queue" then player.research_progress=.26
  elseif opponent=="lost-provider-absent-fish" then player.recipes["fish-breeding"].productivity_bonus=.09 end
  c.load();ok,result=pcall(c.changed);if not ok then return {ok=false,message=tostring(result)} end
  local function tick() local tick_ok,tick_result=pcall(c.events[1]);if not tick_ok then return false,tostring(tick_result) end;return true,"" end
  local function reloads()
    for _=1,2 do local load_ok,load_result=pcall(c.load);if not load_ok then return false,tostring(load_result) end;local tick_ok,tick_result=tick();if not tick_ok then return false,tick_result end end
    return true,""
  end
  local value=player.current_research
  if value==nil or value.name~=full_bioflux then return {ok=false,message="provider-absent fixture did not queue MIR bioflux"} end
  value.level=value.level+1; player.recipes.bioflux.productivity_bonus=player.recipes.bioflux.productivity_bonus+.1; player.research_queue={orphan_electric,probe}
  ok,result=pcall(c.events[2],{research=value});if not ok then return {ok=false,message=tostring(result)} end
  ok,result=tick();if not ok then return {ok=false,message=result} end
  ok,result=reloads();if not ok then return {ok=false,message=result} end
  for _,id in ipairs(ids) do
    local first=id:match("%-4$") and 4 or 1
    player.technologies[id]=player.technologies[id] or research(player,id,first)
    foreign.technologies[id]=research(foreign,id,first);foreign.technologies[id].enabled=false;foreign.technologies[id].visible_when_disabled=true
    detached.technologies[id]=research(detached,id,first)
  end
  player.technologies["electric-circuit-productivity"]=orphan_electric
  player.technologies[full_bioflux].enabled=false
  player.recipes["fish-breeding"].productivity_bonus=.2
  active["mir-fixture-mir5-competing-fixed-gameplay"]="0.6.0";active["plates-n-circuit-productivity"]="0.0.2";active.Science_packs_productivity="0.0.1";active["bioflux-productivity"]="0.1.0";active["fish-productivity"]="1.0.0"
  if opponent=="readded-foreign-enabled" then foreign.technologies["bioflux-productivity"].enabled=true end
  if opponent=="readded-bioflux-lost" then player.recipes.bioflux.productivity_bonus=.19 end
  c.load();ok,result=pcall(c.changed);if not ok then return {ok=false,message=tostring(result)} end
  ok,result=tick();if not ok then return {ok=false,message=result} end
  ok,result=reloads();if not ok then return {ok=false,message=result} end
  return {ok=true,message="",phase=state.phase,markers=markers,saves=saves,full_labs=state.full_mir_actual_lab_completions,full_level=player.technologies[full_bioflux].level,full_enabled=player.technologies[full_bioflux].enabled,bioflux=player.recipes.bioflux.productivity_bonus,fish=player.recipes["fish-breeding"].productivity_bonus,biter=player.recipes["biter-egg"].productivity_bonus,pentapod=player.recipes["pentapod-egg"].productivity_bonus,progress=player.research_progress}
end
''')

    def selected_rows(self):
        rows = {}
        for key, expected in EXPECTED.items():
            inventory = self.providers[key]["arms"]["upstream"]["provider_rows"]
            for name in expected: rows[name] = deepcopy(inventory[name])
        return rows

    def selected_mir_rows(self):
        return {
            "recipe-prod-research_bioflux-1": deepcopy(
                self.providers["bioflux"]["arms"]["published"]["mir_rows"]["recipe-prod-research_bioflux-1"]),
            "recipe-prod-research_breeding-1": deepcopy(
                self.providers["fish"]["arms"]["published"]["mir_rows"]["recipe-prod-research_breeding-1"]),
        }

    def test_profiles_define_one_complete_four_provider_chain(self):
        versions = (("4.7.20002", "0.1.0", True), ("5.0.20000", "0.2.0", True),
                    ("5.0.20000", "0.3.0", True), ("5.0.20000", "0.4.0", True),
                    ("5.0.20000", "0.5.0", False), ("5.0.20000", "0.6.0", True))
        for path, (mir, fixture, providers_present) in zip(PROFILES, versions):
            profile = json.loads(path.read_text(encoding="utf-8")); mods = {item["name"]: item["version"] for item in profile["mods"]}
            self.assertEqual(("f200", "2.0", "2.0.77"), (profile["target"], profile["factorio_line"], profile["engine"]["version"]))
            self.assertEqual((mir, fixture), (mods["more-infinite-research"], mods[FIXTURE_NAME]))
            if providers_present:
                self.assertEqual({"0.0.2", "0.0.1", "0.1.0", "1.0.0"}, {mods["plates-n-circuit-productivity"], mods["Science_packs_productivity"], mods["bioflux-productivity"], mods["fish-productivity"]})
                self.assertEqual(5, len(profile["archive_sha256"]))
            else:
                self.assertTrue({"plates-n-circuit-productivity", "Science_packs_productivity", "bioflux-productivity", "fish-productivity"}.isdisjoint(mods))
                self.assertEqual({"mir-fixture-mir5-active-mods-observer_0.1.0.zip"}, set(profile["archive_sha256"]))
        stages = ("published", "mir5-prefer-mir", "mir5-prefer-foreign", "mir5-prefer-mir-again",
                  "mir5-prefer-foreign-providers-removed", "mir5-prefer-foreign-providers-readded")
        for stage, (_, fixture, _) in zip(stages, versions):
            info = json.loads((FIXTURE / fixture_role(stage) / "info.json").read_text(encoding="utf-8"))
            self.assertEqual((FIXTURE_NAME, fixture, "2.0"), (info["name"], info["version"], info["factorio_version"]))
        for stage, mir, expected, providers_present in (("published", "4.7.20002", False, True),
                                                         ("mir5-prefer-mir", "5.0.20000", True, True),
                                                         ("mir5-prefer-foreign", "5.0.20000", False, True),
                                                         ("mir5-prefer-mir-again", "5.0.20000", True, True),
                                                         ("mir5-prefer-foreign-providers-removed", "5.0.20000", False, False),
                                                         ("mir5-prefer-foreign-providers-readded", "5.0.20000", False, True)):
            setting = self.lua.eval("fixed_setting")(str(FIXTURE / fixture_role(stage) / "settings-updates.lua"), mir, providers_present)
            self.assertTrue(setting["ok"], setting["message"])
            self.assertEqual(expected, setting["value"])

    def test_independent_facts_bind_the_exact_rows_and_complete_mir_coverage(self):
        self.assertEqual((1, 40009033780), (self.facts["schema"], self.facts["run"]))
        replacements = {"plates": {"recipe-prod-research_copper-1", "recipe-prod-research_iron-1", "recipe-prod-research_electronic_circuit-1", "recipe-prod-research_advanced_circuit-1"}, "science-packs": {"recipe-prod-research_science_pack_productivity-1"}, "bioflux": {"recipe-prod-research_bioflux-1"}, "fish": {"recipe-prod-research_breeding-1"}}
        for key, expected in EXPECTED.items():
            arms = self.providers[key]["arms"]; upstream, published, foreign = arms["upstream"], arms["published"], arms["foreign"]
            self.assertEqual(63, published["mir_row_count"]); self.assertIn("complete native MIR rows", published["mir_rows_scope"]); self.assertEqual(replacements[key], set(published["mir_rows"]))
            for name, (prereqs, recipes, formula, time, ingredients) in expected.items():
                row = upstream["provider_rows"][name]
                self.assertEqual(("infinite", list(prereqs), formula, time, [list(item) for item in ingredients]), (row["max_level"], row["prerequisites"], row["unit"]["count_formula"], row["unit"]["time"], row["unit"]["ingredients"]))
                self.assertNotIn("level", row); self.assertEqual(list(recipes), [effect["recipe"] for effect in row["effects"]]); self.assertIsNone(published["provider_rows"][name]); self.assertEqual(row, foreign["provider_rows"][name])
        # The false-preference foreign arms are evidence of an overlap-policy
        # difference, not authorization to claim every future MIR effect here.
        self.assertEqual({"plates": 61, "science-packs": 62, "bioflux": 62, "fish": 63},
                         {key: self.providers[key]["arms"]["foreign"]["mir_row_count"] for key in self.providers})
        self.assertEqual({}, self.providers["plates"]["arms"]["foreign"]["mir_rows"])
        self.assertEqual({}, self.providers["science-packs"]["arms"]["foreign"]["mir_rows"])
        self.assertEqual({}, self.providers["bioflux"]["arms"]["foreign"]["mir_rows"])
        self.assertNotIn("recipe-prod-research_bioflux-1", self.providers["bioflux"]["arms"]["foreign"]["ids"])
        full_bioflux = self.providers["bioflux"]["arms"]["published"]["mir_rows"]["recipe-prod-research_bioflux-1"]
        self.assertEqual(("recipe-prod-research_bioflux-1", 1, "8000*2^(L-1)", 60),
                         (full_bioflux["name"], full_bioflux["level"], full_bioflux["unit"]["count_formula"], full_bioflux["unit"]["time"]))
        self.assertEqual(["automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                          "production-science-pack", "agricultural-science-pack"], full_bioflux["prerequisites"])
        self.assertEqual(["bioflux"], [effect["recipe"] for effect in full_bioflux["effects"]])
        self.assertIsNone(self.providers["bioflux"]["foreign_remaining_mir_rows"]["recipe-prod-research_bioflux-1"])
        remaining = self.providers["fish"]["foreign_remaining_mir_rows"]["recipe-prod-research_breeding-1"]
        full = self.providers["fish"]["arms"]["published"]["mir_rows"]["recipe-prod-research_breeding-1"]
        self.assertEqual(("recipe-prod-research_breeding-1", 1, "8000*2^(L-1)", 60),
                         (remaining["name"], remaining["level"], remaining["unit"]["count_formula"], remaining["unit"]["time"]))
        self.assertEqual(["biter-egg", "fish-breeding", "pentapod-egg"], [effect["recipe"] for effect in full["effects"]])
        self.assertEqual(["biter-egg", "pentapod-egg"], [effect["recipe"] for effect in remaining["effects"]])

    def test_published_preflight_precedes_only_disposable_count_time_mutation(self):
        result = self.lua.eval("fixed_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), str(FOREIGN_DATA), lua_value(self.lua, self.selected_rows()))
        self.assertTrue(result["ok"], result["message"]); rows = plain(result["raw"])["technology"]
        for name, expected in self.selected_rows().items():
            self.assertEqual((None, "1", 1), (rows[name]["unit"].get("count"), rows[name]["unit"]["count_formula"], rows[name]["unit"]["time"]))
            self.assertEqual(expected["effects"], rows[name]["effects"]); self.assertEqual(expected["prerequisites"], rows[name]["prerequisites"])
        bad = self.selected_rows(); bad["bioflux-productivity"]["effects"][0]["change"] = .2
        result = self.lua.eval("fixed_data")(str(FIXTURE / "published" / "data-final-fixes.lua"), str(FOREIGN_DATA), lua_value(self.lua, bad))
        self.assertFalse(result["ok"]); self.assertIn("bioflux-productivity effects changed", result["message"])

    def test_named_mir_preflight_distinguishes_partial_and_fully_covered_rows(self):
        full = deepcopy(self.providers["fish"]["arms"]["published"]["mir_rows"]["recipe-prod-research_breeding-1"])
        bioflux = deepcopy(self.providers["bioflux"]["arms"]["published"]["mir_rows"]["recipe-prod-research_bioflux-1"])
        false = deepcopy(self.providers["fish"]["foreign_remaining_mir_rows"]["recipe-prod-research_breeding-1"])
        cases = (("mir5-prefer-mir", "0.2.0", True, True, full, ["biter-egg", "fish-breeding", "pentapod-egg"], None, (None, "1", 1)),
                 ("mir5-prefer-foreign", "0.3.0", False, True, false, ["biter-egg", "pentapod-egg"], False, (None, "8000*2^(L-1)", 60)),
                 ("mir5-prefer-mir-again", "0.4.0", True, True, full, ["biter-egg", "fish-breeding", "pentapod-egg"], None, (None, "8000*2^(L-1)", 60)),
                 ("mir5-prefer-foreign-providers-removed", "0.5.0", False, False, full, ["biter-egg", "fish-breeding", "pentapod-egg"], None, (None, "1", 1)),
                 ("mir5-prefer-foreign-providers-readded", "0.6.0", False, True, false, ["biter-egg", "pentapod-egg"], False, (None, "8000*2^(L-1)", 60)))
        for stage, fixture, preference, providers_present, row, effects, expected_enabled, bioflux_cost in cases:
            mir_rows = self.selected_mir_rows()
            bioflux_row = mir_rows["recipe-prod-research_bioflux-1"]
            if expected_enabled is False:
                bioflux_row["enabled"] = False
            mir_rows["recipe-prod-research_breeding-1"] = row
            foreign_rows = self.selected_rows() if providers_present else {}
            result = self.lua.eval("fixed_mir_data")(str(FIXTURE / fixture_role(stage) / "data-final-fixes.lua"), str(FOREIGN_DATA), str(FULL_BIOFLUX_DATA), fixture, preference, lua_value(self.lua, mir_rows), lua_value(self.lua, foreign_rows), providers_present)
            self.assertTrue(result["ok"], result["message"])
            technologies = plain(result["raw"])["technology"]
            actual = technologies["recipe-prod-research_breeding-1"]
            expected_breeding_cost = (None, "8000*2^(L-1)", 60) if stage in ("mir5-prefer-mir-again", "mir5-prefer-foreign-providers-removed") else (None, "1", 1)
            self.assertEqual(expected_breeding_cost, (actual["unit"].get("count"), actual["unit"]["count_formula"], actual["unit"]["time"]))
            self.assertEqual(effects, [effect["recipe"] for effect in actual["effects"]])
            full_actual = technologies["recipe-prod-research_bioflux-1"]
            self.assertEqual(expected_enabled, full_actual.get("enabled"))
            self.assertEqual(bioflux_cost, (full_actual["unit"].get("count"), full_actual["unit"]["count_formula"], full_actual["unit"]["time"]))
            self.assertEqual(bioflux["effects"], full_actual["effects"])
            if providers_present:
                foreign_costs = {(foreign["unit"].get("count"), foreign["unit"]["count_formula"], foreign["unit"]["time"])
                                 for name, foreign in technologies.items() if name in self.selected_rows()}
                self.assertEqual({(None, "1", 1)}, foreign_costs)
        bad = deepcopy(false); bad["effects"].append({"type": "change-recipe-productivity", "recipe": "fish-breeding", "change": .1})
        result = self.lua.eval("fixed_mir_data")(str(FIXTURE / fixture_role("mir5-prefer-foreign") / "data-final-fixes.lua"), str(FOREIGN_DATA), str(FULL_BIOFLUX_DATA), "0.3.0", False, lua_value(self.lua, {"recipe-prod-research_breeding-1": bad, "recipe-prod-research_bioflux-1": bioflux}), lua_value(self.lua, self.selected_rows()))
        self.assertFalse(result["ok"])
        self.assertIn("captured released MIR breeding effects count changed", result["message"])
        bad_bioflux = deepcopy(bioflux); bad_bioflux["enabled"] = True
        result = self.lua.eval("fixed_mir_data")(str(FIXTURE / fixture_role("mir5-prefer-foreign") / "data-final-fixes.lua"), str(FOREIGN_DATA), str(FULL_BIOFLUX_DATA), "0.3.0", False, lua_value(self.lua, {"recipe-prod-research_breeding-1": false, "recipe-prod-research_bioflux-1": bad_bioflux}), lua_value(self.lua, self.selected_rows()))
        self.assertFalse(result["ok"])
        self.assertIn("captured released MIR bioflux identity changed", result["message"])
        foreign = self.selected_rows(); foreign["bioflux-productivity"]["effects"][0]["change"] = .2
        result = self.lua.eval("fixed_mir_data")(str(FIXTURE / fixture_role("mir5-prefer-foreign") / "data-final-fixes.lua"), str(FOREIGN_DATA), str(FULL_BIOFLUX_DATA), "0.3.0", False, lua_value(self.lua, {"recipe-prod-research_breeding-1": false, "recipe-prod-research_bioflux-1": bioflux}), lua_value(self.lua, foreign))
        self.assertFalse(result["ok"])
        self.assertIn("bioflux-productivity effects changed", result["message"])

    def test_controls_keep_parse_and_on_load_read_only(self):
        for stage, mir, fixture, providers_present in (("published", "4.7.20002", "0.1.0", True), ("mir5-prefer-mir", "5.0.20000", "0.2.0", True), ("mir5-prefer-foreign", "5.0.20000", "0.3.0", True), ("mir5-prefer-mir-again", "5.0.20000", "0.4.0", True), ("mir5-prefer-foreign-providers-removed", "5.0.20000", "0.5.0", False), ("mir5-prefer-foreign-providers-readded", "5.0.20000", "0.6.0", True)):
            result = self.lua.eval("fixed_parse")(str(FIXTURE / "control.lua"), mir, fixture, providers_present)
            self.assertTrue(result["ok"], result["message"]); self.assertEqual({}, plain(result["reads"])); self.assertIsNotNone(result["callbacks"]["load"]); self.assertIsNotNone(result["callbacks"]["events"][1])
            body = (FIXTURE / "control.lua").read_text(encoding="utf-8").split("script.on_load(function()", 1)[1].split("script.on_configuration_changed", 1)[0]
            self.assertNotIn("game.", body); self.assertNotIn("research_queue_enabled", body); self.assertNotRegex(body, r"storage\s*\[.*?\]\s*=")
        source=(FIXTURE / "control.lua").read_text(encoding="utf-8")
        for witness in ('name="biolab"', "four-native-fixed-provider-labs", "recipe-prod-research_bioflux-1", "electric-circuit-productivity", "detached_basic.saved_progress = 0.27"):
            self.assertIn(witness, source)

    def test_successor_observations_retain_full_and_partial_effects_and_reject_state_loss(self):
        run = self.lua.eval("fixed_successor")
        preferred = run(str(FIXTURE / "control.lua"), "0.2.0", "true", "")
        self.assertTrue(preferred["ok"], preferred["message"])
        self.assertEqual(("prefer-mir-breeding-completed", 3, 1, 2, .2, .1, .1, 1, 2, True, .2, .27),
                         (preferred["phase"], preferred["markers"], preferred["saves"], preferred["breed_level"],
                           preferred["fish"], preferred["biter"], preferred["pentapod"], preferred["full_labs"], preferred["full_level"],
                           preferred["full_enabled"], preferred["full_bonus"], preferred["progress"]))
        released = run(str(FIXTURE / "control.lua"), "0.3.0", "false", "")
        self.assertTrue(released["ok"], released["message"])
        self.assertEqual(("prefer-foreign-breeding-completed", 3, 1, 3, .2, .2, .2, 1, 2, False, .2, .27),
                         (released["phase"], released["markers"], released["saves"], released["breed_level"],
                           released["fish"], released["biter"], released["pentapod"], released["full_labs"], released["full_level"],
                           released["full_enabled"], released["full_bonus"], released["progress"]))
        re_preferred = run(str(FIXTURE / "control.lua"), "0.4.0", "again", "")
        self.assertTrue(re_preferred["ok"], re_preferred["message"])
        self.assertEqual(("prefer-mir-again-completed", 3, 1, 3, .2, .2, .2, 1, 2, True, .2, .27),
                         (re_preferred["phase"], re_preferred["markers"], re_preferred["saves"], re_preferred["breed_level"],
                           re_preferred["fish"], re_preferred["biter"], re_preferred["pentapod"], re_preferred["full_labs"], re_preferred["full_level"],
                           re_preferred["full_enabled"], re_preferred["full_bonus"], re_preferred["progress"]))
        for stage, fixture, mode, opponent, expected in (
            ("mir5-prefer-mir", "0.2.0", "true", "old-predecessor-has-full", "published false-preference predecessor unexpectedly contains fully covered MIR bioflux"),
            ("mir5-prefer-mir", "0.2.0", "true", "missing-mir5-introduction", "MIR5 true data did not introduce fully covered MIR bioflux"),
            ("mir5-prefer-mir", "0.2.0", "true", "detached-disabled", "detached partial initial state differs"),
            ("mir5-prefer-mir", "0.2.0", "true", "lost-current", "preferred player queue/progress differs"),
            ("mir5-prefer-mir", "0.2.0", "true", "foreign-reenabled", "foreign presentation changed"),
            ("mir5-prefer-mir", "0.2.0", "true", "foreign-full-reenabled", "foreign fully covered MIR bioflux state differs"),
            ("mir5-prefer-mir", "0.2.0", "true", "lost-earned-provider", "preferred earned productivity changed: automation-science-pack"),
            ("mir5-prefer-mir", "0.2.0", "true", "lost-earned-full", "preferred earned productivity changed: bioflux"),
            ("mir5-prefer-foreign", "0.3.0", "false", "full-reenabled-on-false", "false transition fully covered MIR bioflux state differs"),
            ("mir5-prefer-foreign", "0.3.0", "false", "lost-earned-fish", "false transition earned productivity changed: fish-breeding"),
            ("mir5-prefer-foreign", "0.3.0", "false", "lost-earned-full", "false transition earned productivity changed: bioflux"),
            ("mir5-prefer-foreign", "0.3.0", "false", "lost-full-lab", "false transition fully covered MIR bioflux actual lab witness differs"),
            ("mir5-prefer-mir-again", "0.4.0", "again", "full-still-disabled-again", "re-preferred fully covered MIR bioflux state differs"),
            ("mir5-prefer-mir-again", "0.4.0", "again", "lost-earned-fish", "re-preference transition earned productivity changed: fish-breeding"),
            ("mir5-prefer-mir-again", "0.4.0", "again", "lost-earned-full", "re-preference transition earned productivity changed: bioflux"),
        ):
            result = run(str(FIXTURE / "control.lua"), fixture, mode, opponent)
            self.assertFalse(result["ok"])
            self.assertIn(expected, result["message"])

    def test_provider_removal_and_readdition_preserve_only_observed_mir5_state(self):
        run = self.lua.eval("fixed_provider_removal_readdition")
        result = run(str(FIXTURE / "control.lua"), "")
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual(("providers-readded-foreign-completed", 6, 2, 2, 3, False, .2, .2, .2, .2, .27),
                         (result["phase"], result["markers"], result["saves"], result["full_labs"], result["full_level"],
                          result["full_enabled"], result["bioflux"], result["fish"], result["biter"], result["pentapod"], result["progress"]))
        for opponent, expected in (
            ("removed-provider-still-present", "provider-absent successor unexpectedly retains a fixed provider"),
            ("lost-provider-absent-queue", "provider removal player queue/progress differs"),
            ("lost-provider-absent-fish", "provider removal pre-lab breeding productivity changed: fish-breeding"),
            ("readded-foreign-enabled", "foreign presentation changed: bioflux-productivity"),
            ("readded-bioflux-lost", "readded foreign retained bioflux productivity changed: bioflux"),
        ):
            result = run(str(FIXTURE / "control.lua"), opponent)
            self.assertFalse(result["ok"])
            self.assertIn(expected, result["message"])

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args, extra = parser.parse_known_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    unittest.main(argv=[sys.argv[0], *extra])
