"""Small independent Lua52 world for the retained Base paid-source successor."""

from __future__ import annotations

from pathlib import Path


FIXTURE = Path(__file__).parent / "fixtures" / "published-base-added-successor"
FOREIGN = "mir473-base-paid-foreign"
MAINS = (
    ("research_low_density_structure", "recipe-prod-research_low_density_structure-1", "low-density-structure", "mir-fixture-added-low-density-structure"),
    ("research_plastic", "recipe-prod-research_plastic-1", "plastic-bar", "mir-fixture-added-plastic-bar"),
    ("research_processing_unit", "recipe-prod-research_processing_unit-1", "processing-unit", "mir-fixture-added-processing-unit"),
    ("research_rocket_fuel", "recipe-prod-research_rocket_fuel-1", "rocket-fuel", "mir-fixture-added-rocket-fuel"),
    ("research_steel", "recipe-prod-research_steel-1", "steel-plate", "mir-fixture-added-steel-plate"),
)
FINITE = (
    "electronics", "steam-power", "automation-science-pack", "logistic-science-pack", "automation",
    "steel-processing", "automation-2", "engine", "fluid-handling", "oil-gathering", "oil-processing",
    "plastics", "advanced-circuit", "sulfur-processing", "chemical-science-pack", "advanced-material-processing",
    "advanced-material-processing-2", "modules", "productivity-module", "logistics", "logistics-2", "railway",
    "production-science-pack",
)
TIER_TWO = {"automation-2", "advanced-material-processing-2", "logistics-2"}


WORLD = r'''
local MAINS={{"research_low_density_structure","recipe-prod-research_low_density_structure-1","low-density-structure","mir-fixture-added-low-density-structure"},{"research_plastic","recipe-prod-research_plastic-1","plastic-bar","mir-fixture-added-plastic-bar"},{"research_processing_unit","recipe-prod-research_processing_unit-1","processing-unit","mir-fixture-added-processing-unit"},{"research_rocket_fuel","recipe-prod-research_rocket_fuel-1","rocket-fuel","mir-fixture-added-rocket-fuel"},{"research_steel","recipe-prod-research_steel-1","steel-plate","mir-fixture-added-steel-plate"}}
local FINITE=FINITE_ROWS
local TIER_TWO=TIER_TWO_ROWS
local PACKS={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
local function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
local function tech(name,level,maximum,effects)
  local values={name=name,valid=true,level=level,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
    prototype={level=level==2 and 2 or 0,max_level=maximum,effects=effects or {},research_unit_energy=3600},
    research_unit_ingredients={{name=PACKS[1],amount=1},{name=PACKS[2],amount=1},{name=PACKS[3],amount=1},{name=PACKS[4],amount=1}}}
  setmetatable(values,{__index=function(_,k)if k=="research_unit_count"then return maximum==4294967295 and 8000*2^(values.level-1) or 1 end end,
    __newindex=function(_,k,v)if observer_locked and (k=="level"or k=="researched"or k=="saved_progress"or k=="enabled"or k=="visible_when_disabled")then error("observer technology write")end;rawset(values,k,v)end})
  return values
end
local function make_force(name,index)
  local technologies,recipes={},{}
  for _,row in ipairs(FINITE)do local level=TIER_TWO[row]and 2 or 1;technologies[row]=tech(row,level,level);technologies[row].researched=true end
  for _,row in ipairs(MAINS)do local level=name=="player"and 2 or 1;technologies[row[2]]=tech(row[2],level,4294967295,{{type="change-recipe-productivity",recipe=row[3],change=.1}});recipes[row[3]]={valid=true,productivity_bonus=name=="player"and .1 or 0};recipes[row[4]]={valid=true,productivity_bonus=0}end
  technologies["braking-force-1"]=tech("braking-force-1",1,1)
  technologies["recipe-prod-research_gears-1"]=tech("recipe-prod-research_gears-1",1,4294967295)
  for _,row in pairs(technologies)do row.force=nil end
  local values={name=name,index=index,valid=true,technologies=technologies,recipes=recipes,queue={},current=nil,progress=0,laboratory_speed_modifier=0}
  local force={}
  setmetatable(force,{__index=function(_,k)if k=="research_queue"then return values.queue elseif k=="current_research"then return values.current elseif k=="research_progress"then return values.progress end;return values[k]end,
    __newindex=function(_,k,v)
      if k=="research_queue"or k=="research_progress"then error("observer research authority")end
      if k=="laboratory_speed_modifier"then values[k]=v;return end
      values[k]=v
    end})
  for _,row in pairs(technologies)do row.force=force end
  return force,values
end
local function inventory(initial)
  local values=copy(initial);local result={capacity=200}
  function result.insert(row)local accepted=math.min(row.count,result.capacity-(values[row.name]or 0));values[row.name]=(values[row.name]or 0)+accepted;return accepted end
  function result.get_item_count(name)return values[name]or 0 end
  function result.consume(name,n)assert((values[name]or 0)>=n,"science exhausted");values[name]=values[name]-n end
  return result
end
function added_world(expected)
  handlers,markers,logs,files,saves,storage={},{},{},{},{},{}
  local player,pv=make_force("player",1);local foreign,fv=make_force("mir473-base-paid-foreign",4)
  local enemy={name="enemy",index=2,valid=true};local neutral={name="neutral",index=3,valid=true}
  local input=inventory({["automation-science-pack"]=168,["logistic-science-pack"]=168,["chemical-science-pack"]=168,["production-science-pack"]=168})
  local surface={index=1};local lab={name="lab",valid=true,unit_number=19,disabled_by_script=true,energy=0,electric_buffer_size=1000000,force=player,surface=surface,position={x=.5,y=.5},
    get_inventory=function(kind)assert(kind==1);return input end}
  surface.find_entity=function(name,position)assert(name=="lab"and position.x==.5 and position.y==.5);return lab end
  game={tick=1252,forces={player=player,enemy=enemy,neutral=neutral,["mir473-base-paid-foreign"]=foreign,[1]=player,[2]=enemy,[3]=neutral,[4]=foreign},surfaces={[1]=surface},
    server_save=function(name)saves[#saves+1]={name=name,tick=game.tick}end}
  pv.queue={player.technologies["recipe-prod-research_steel-1"],player.technologies["recipe-prod-research_steel-1"]};pv.current=pv.queue[1];pv.progress=0
  fv.queue={foreign.technologies["braking-force-1"],foreign.technologies["recipe-prod-research_gears-1"],foreign.technologies["recipe-prod-research_gears-1"]};fv.current=fv.queue[1];fv.progress=.42
  player.technologies["recipe-prod-research_plastic-1"].saved_progress=.27
  expected_source=expected;world_lab=lab;world_input=input;world_values={player=pv,foreign=fv};observer_locked=true
end
function added_load(path,source_json)
  local active={base="2.0.77",["more-infinite-research"]="5.0.20018",["mir-fixture-published-base-added-successor"]="0.1.0"}
  local env={game=game,storage=storage,settings={startup={["mir-max-level-worker-robots-storage"]={valid=true,value=0}}},defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}},helpers={},script={active_mods=active},log=function(v)logs[#logs+1]=v end,
    pairs=pairs,ipairs=ipairs,type=type,error=error,math=math,table=table,tostring=tostring}
  env.helpers.json_to_table=function(text)assert(text==source_json,"actor source literal differs");return copy(expected_source)end
  env.helpers.table_to_json=function(row)markers[#markers+1]=copy(row);return "json"end
  env.helpers.write_file=function(path,text,append)files[#files+1]={path=path,text=text,append=append}end
  env.script.on_init=function(f)handlers.init=f end;env.script.on_load=function(f)handlers.load=f end;env.script.on_configuration_changed=function(f)handlers.config=f end;env.script.on_event=function(k,f)handlers[k]=f end
  env.require=function(name)assert(name=="expected-source");return source_json end;env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end});scenario_env=env
  assert(loadfile(path,"t",env))()
end
function added_call(which,event)local ok,msg=pcall(handlers[which],event);return ok,tostring(msg)end
function added_init_config(version,extra)
  scenario_env.script.active_mods["more-infinite-research"]=version or "5.0.20018"
  local ok,msg=added_call("init");if not ok then return ok,msg end
  local changes={["more-infinite-research"]={old_version="4.7.20003",new_version=version or "5.0.20018"},["mir-fixture-published-base-added-successor"]={old_version=nil,new_version="0.1.0"}}
  if extra then changes[extra]={old_version=nil,new_version="0.1.0"} end
  return added_call("config",{mod_startup_settings_changed=false,mod_changes=changes})
end
function added_engine(scripted)
  local p=game.forces.player;local current=p.current_research
  if not current or world_lab.disabled_by_script then return true,"" end
  local need=16000-(world_values.player.consumed or 0);local amount=need
  for _,pack in ipairs(PACKS)do amount=math.min(amount,world_input.get_item_count(pack))end
  if amount<=0 then return true,"" end
  for _,pack in ipairs(PACKS)do world_input.consume(pack,amount)end
  world_values.player.consumed=(world_values.player.consumed or 0)+amount
  if world_values.player.consumed<16000 then world_values.player.progress=world_values.player.consumed/16000;return true,"" end
  world_values.player.queue={current};world_values.player.current=current;world_values.player.progress=0;current.level=3
  p.recipes["steel-plate"].productivity_bonus=.2;p.recipes["mir-fixture-added-steel-plate"].productivity_bonus=.1
  return added_call(2,{research=current,by_script=scripted})
end
function added_tick(count,scripted)
  for _=1,count do game.tick=game.tick+1;local ok,msg=added_engine(scripted);if not ok then return ok,msg end;ok,msg=added_call(1);if not ok then return ok,msg end end
  return true,""
end
function added_until_saved()
  for _=1,300 do local ok,msg=added_tick(1,false);if not ok then return ok,msg end;if #saves>0 then return true,"" end end;return false,"no save"
end
function added_scripted(name)return added_call(2,{research=game.forces.player.technologies[name],by_script=true})end
function added_drift_foreign()world_values.foreign.progress=.5 end
function added_load_throwing()
  local old_game,old_storage=scenario_env.game,scenario_env.storage;scenario_env.game=setmetatable({},{__index=function()error("game read")end});scenario_env.storage=setmetatable({},{__index=function()error("storage read")end})
  local ok,msg=added_call("load");scenario_env.game,scenario_env.storage=old_game,old_storage;return ok,msg
end
'''


def _lua_set(values: set[str]) -> str:
    return "{" + ",".join(f'["{value}"]=true' for value in sorted(values)) + "}"


def _lua_list(values: tuple[str, ...]) -> str:
    return "{" + ",".join(f'"{value}"' for value in values) + "}"


def _lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: _lua_value(lua, item) for key, item in value.items()})
    if isinstance(value, list):
        return lua.table_from([_lua_value(lua, item) for item in value])
    return value


def install(lua, expected: dict, source_json: str) -> None:
    lua.execute(f"FINITE_ROWS={_lua_list(FINITE)}; TIER_TWO_ROWS={_lua_set(TIER_TWO)}")
    lua.execute(WORLD)
    lua.globals().added_world(_lua_value(lua, expected))
    lua.globals().added_actor = (FIXTURE / "control.lua").as_posix()
    lua.globals().added_source_json = source_json
    lua.execute("added_load(added_actor,added_source_json)")
