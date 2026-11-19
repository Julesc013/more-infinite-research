"""Plain Lua52 world for the published Base paid-source scenario controls."""

from __future__ import annotations

from pathlib import Path


FIXTURE = Path(__file__).parent / "fixtures" / "published-base-paid-source"
FOREIGN = "mir473-base-paid-foreign"
SCIENCE = [
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
]
MAINS = [
    ("recipe-prod-research_low_density_structure-1", "low-density-structure"),
    ("recipe-prod-research_plastic-1", "plastic-bar"),
    ("recipe-prod-research_processing_unit-1", "processing-unit"),
    ("recipe-prod-research_rocket_fuel-1", "rocket-fuel"),
    ("recipe-prod-research_steel-1", "steel-plate"),
]
ROWS = {
    "electronics": [], "steam-power": [],
    "automation-science-pack": ["steam-power", "electronics"],
    "logistic-science-pack": ["automation-science-pack"],
    "automation": ["automation-science-pack"], "steel-processing": ["automation-science-pack"],
    "automation-2": ["automation", "steel-processing", "logistic-science-pack"],
    "engine": ["steel-processing", "logistic-science-pack"], "fluid-handling": ["automation-2", "engine"],
    "oil-gathering": ["fluid-handling"], "oil-processing": ["oil-gathering"], "plastics": ["oil-processing"],
    "advanced-circuit": ["plastics"], "sulfur-processing": ["oil-processing"],
    "chemical-science-pack": ["advanced-circuit", "sulfur-processing"],
    "advanced-material-processing": ["steel-processing", "logistic-science-pack"],
    "advanced-material-processing-2": ["advanced-material-processing", "chemical-science-pack"],
    "modules": ["advanced-circuit"], "productivity-module": ["modules"],
    "logistics": ["automation-science-pack"], "logistics-2": ["logistics", "logistic-science-pack"],
    "railway": ["logistics-2", "engine"],
    "production-science-pack": ["productivity-module", "advanced-material-processing-2", "railway"],
}


WORLD = r'''
local FOREIGN="mir473-base-paid-foreign"
local SCIENCE={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
local MAINS={{"recipe-prod-research_low_density_structure-1","low-density-structure"},{"recipe-prod-research_plastic-1","plastic-bar"},{"recipe-prod-research_processing_unit-1","processing-unit"},{"recipe-prod-research_rocket_fuel-1","rocket-fuel"},{"recipe-prod-research_steel-1","steel-plate"}}
local GEAR,BRAKING="recipe-prod-research_gears-1","braking-force-1"
local TIER_TWO={ ["automation-2"]=true,["advanced-material-processing-2"]=true,["logistics-2"]=true }
local function copy(value)if type(value)~="table"then return value end local out={}for k,v in pairs(value)do out[k]=copy(v)end return out end
local function tech(name,maximum,effects,current_level,prototype_level)
  local row={name=name,valid=true,level=current_level or 1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
    prototype={level=prototype_level == nil and 0 or prototype_level,max_level=maximum or 1,effects=effects or{}},prerequisites={},research_unit_energy=3600,
    research_unit_ingredients={{name=SCIENCE[1],amount=1},{name=SCIENCE[2],amount=1},{name=SCIENCE[3],amount=1},{name=SCIENCE[4],amount=1}}}
  setmetatable(row,{__index=function(_,key)if key=="research_unit_count"then return row.prototype.max_level==4294967295 and 8000*2^(row.level-1)or 1 end end})
  return row
end
local function make_force(name,index,rows)
  local technologies,recipes={},{}
  for row_name in pairs(rows)do local level=TIER_TWO[row_name]and 2 or 1;local first=TIER_TWO[row_name]and 2 or 0;technologies[row_name]=tech(row_name,level,{},level,first)end
  for _,main in ipairs(MAINS)do technologies[main[1]]=tech(main[1],4294967295,{{type="change-recipe-productivity",recipe=main[2],change=.1}},1,0);recipes[main[2]]={productivity_bonus=0}end
  technologies[GEAR]=tech(GEAR,4294967295,{{type="change-recipe-productivity",recipe="iron-gear-wheel",change=.1}},1,0)
  technologies[BRAKING]=tech(BRAKING,1,{{type="train-braking-force-bonus",modifier=.1}},1,0)
  for row_name,parents in pairs(rows)do for _,parent in ipairs(parents)do technologies[row_name].prerequisites[parent]=technologies[parent]end end
  for _,main in ipairs(MAINS)do for _,parent in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"})do technologies[main[1]].prerequisites[parent]=technologies[parent]end end
  for _,parent in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"})do technologies[GEAR].prerequisites[parent]=technologies[parent]end
  technologies[BRAKING].prerequisites["railway"]=technologies["railway"];technologies[BRAKING].prerequisites["chemical-science-pack"]=technologies["chemical-science-pack"]
  local values={name=name,index=index,valid=true,technologies=technologies,recipes=recipes,queue={},current=nil,progress=0,laboratory_speed_modifier=0,remaining={}}
  local force={}
  setmetatable(force,{__index=function(_,key)
    if key=="research_queue"then return values.queue end;if key=="current_research"then return values.current end;if key=="research_progress"then return values.progress end
    return values[key]
  end,__newindex=function(_,key,value)
    if key=="research_queue"then
      local queue={};for index,item in ipairs(value)do assert(item and item.name,"invalid research queue row");queue[index]=item end
      values.queue=queue;values.current=queue[1];values.progress=0;return
    end
    if key=="research_progress"then assert(values.current~=nil,"No research in progress.");values.progress=value;return end
    values[key]=value
  end})
  function force._world_complete(technology)
    values.queue={};values.current=nil;values.progress=0;values.remaining[technology.name]=nil
  end
  for _,technology in pairs(technologies)do technology.force=force end
  return force
end
local function inventory()
  local values={};local result={capacity=200}
  function result.insert(row)local accepted=math.min(row.count,result.capacity-(values[row.name]or 0));values[row.name]=(values[row.name]or 0)+accepted;return accepted end
  function result.get_item_count(name)return values[name]or 0 end
  function result.decrement(name,count)assert((values[name]or 0)>=count,"world research input exhausted");values[name]=values[name]-count end
  return result
end
local function lab(force,surface,position)
  local input=inventory()
  return {valid=true,name="lab",unit_number=77,disabled_by_script=false,energy=0,electric_buffer_size=1000000,force=force,surface=surface,position={x=position.x or position[1],y=position.y or position[2]},
    get_inventory=function(kind)assert(kind==1);return input end,_input=input}
end
function paid_source_world(rows)
  handlers,markers,logs,files,saves,storage={},{},{},{},{},{}
  local player=make_force("player",1,rows);local enemy={name="enemy",index=2,valid=true};local neutral={name="neutral",index=3,valid=true};local next_index=4
  local surface={index=1}
  surface.create_entity=function(spec)assert(spec.name=="lab"and spec.force==player);game.lab=lab(spec.force,surface,spec.position);return game.lab end
  game={tick=0,forces={player=player,enemy=enemy,neutral=neutral,[1]=player,[2]=enemy,[3]=neutral},surfaces={[1]=surface},
    create_force=function(name)assert(game.forces[name]==nil);local value=make_force(name,next_index,rows);next_index=next_index+1;game.forces[name]=value;game.forces[value.index]=value;return value end,
    server_save=function(name)saves[#saves+1]={name=name,tick=game.tick}end}
  return player
end
function paid_source_load(path)
  local active={base="2.0.77",["more-infinite-research"]="4.7.20003"}
  local env={game=game,storage=storage,defines={inventory={lab_input=1},events={on_tick=1,on_research_finished=2}},helpers={},script={active_mods=active},log=function(value)logs[#logs+1]=value end,
    pairs=pairs,ipairs=ipairs,type=type,error=error,math=math,table=table,tostring=tostring}
  env.helpers.table_to_json=function(row)markers[#markers+1]=copy(row);return "json"end
  env.helpers.write_file=function(path,text,append)files[#files+1]={path=path,text=text,append=append}end
  env.script.on_init=function(fn)handlers.init=fn end;env.script.on_load=function(fn)handlers.load=fn end;env.script.on_configuration_changed=function(fn)handlers.configuration=fn end
  env.script.on_event=function(id,fn)handlers[id]=fn end
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end});scenario_env=env
  assert(loadfile(path,"t",env))();return env
end
function paid_source_call(name,event)local ok,message=pcall(handlers[name],event);return ok,tostring(message)end
function paid_source_engine(by_script)
  local player=game.forces.player;local current=player.current_research
  if not current or not game.lab or game.lab.disabled_by_script then return true,"" end
  local remaining=player.remaining[current.name]or 8000
  local amount=remaining
  for _,pack in ipairs(SCIENCE)do amount=math.min(amount,game.lab._input.get_item_count(pack))end
  if amount<=0 then return false,"world research input exhausted"end
  for _,pack in ipairs(SCIENCE)do game.lab._input.decrement(pack,amount)end
  remaining=remaining-amount;player.remaining[current.name]=remaining
  if remaining>0 then player.research_progress=(8000-remaining)/8000;return true,"" end
  player._world_complete(current);current.level=2;current.researched=false;player.recipes[current.prototype.effects[1].recipe].productivity_bonus=.1
  return paid_source_call(2,{research=current,by_script=by_script})
end
function paid_source_tick(count,by_script)
  for _=1,count do
    game.tick=game.tick+1;local ok,message=paid_source_engine(by_script);if not ok then return false,message end
    ok,message=paid_source_call(1);if not ok then return false,message end
  end
  return true,""
end
function paid_source_until_saved(limit)
  for _=1,limit do local ok,message=paid_source_tick(1,false);if not ok then return false,message end;if #saves>0 then return true,""end end
  return false,"save not reached"
end
function paid_source_set_mir(version)scenario_env.script.active_mods["more-infinite-research"]=version end
function paid_source_emit_stale()local technology=game.forces.player.technologies["recipe-prod-research_plastic-1"];return paid_source_call(2,{research=technology,by_script=false})end
function paid_source_drift_foreign_queue()game.forces[FOREIGN].research_queue={game.forces[FOREIGN].technologies[GEAR]}end
function paid_source_marker_is_plain(index)
  local seen={}
  local function walk(value)
    local kind=type(value)
    if kind=="nil"or kind=="boolean"or kind=="number"or kind=="string"then return true end
    if kind~="table"or seen[value]then return kind=="table"end
    seen[value]=true;for _,entry in pairs(value)do if not walk(entry)then return false end end;return true
  end
  return walk(markers[index])
end
function paid_source_load_with_throwing_globals()
  local original_game,original_storage=scenario_env.game,scenario_env.storage
  scenario_env.game=setmetatable({},{__index=function()error("on_load read game")end,__newindex=function()error("on_load write game")end})
  scenario_env.storage=setmetatable({},{__index=function()error("on_load read storage")end,__newindex=function()error("on_load write storage")end})
  local ok,message=paid_source_call("load")
  scenario_env.game,scenario_env.storage=original_game,original_storage
  return ok,message
end
'''


def _lua_rows(rows: dict[str, list[str]]) -> str:
    parts = []
    for name, parents in rows.items():
        values = ",".join(f'"{parent}"' for parent in parents)
        parts.append(f'["{name}"]={{{values}}}')
    return "{" + ",".join(parts) + "}"


def install(lua) -> None:
    lua.execute(f"PAID_SOURCE_ROWS={_lua_rows(ROWS)}")
    lua.execute(WORLD)
    lua.globals().paid_source_world(lua.globals().PAID_SOURCE_ROWS)


def load_actor(lua) -> None:
    lua.globals().paid_source_actor = (FIXTURE / "control.lua").as_posix()
    lua.execute("paid_source_load(paid_source_actor)")
