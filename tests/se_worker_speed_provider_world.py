"""Plain Lua host world for the SE worker-speed provider fixture controls."""

from __future__ import annotations

from pathlib import Path
import re


FIXTURE = Path(__file__).parent / "fixtures" / "se-worker-speed-provider-admitted"
WORKER = "worker-robots-speed-10"
PREDECESSOR = "worker-robots-speed-9"
DEEP = "se-deep-space-science-pack-1"


def _rows() -> dict[str, list[str]]:
    source = (FIXTURE / "prerequisites.lua").read_text(encoding="utf-8")
    match = re.search(r"ROW_TEXT = \[\[\n(.*?)\n\]\]", source, re.DOTALL)
    if match is None:
        raise AssertionError("fixed prerequisite declaration is absent")
    rows: dict[str, list[str]] = {}
    for line in match.group(1).splitlines():
        name, parents = line.split("=", 1)
        if not name or name in rows:
            raise AssertionError("fixed prerequisite declaration is malformed")
        rows[name] = [] if not parents else parents.split("|")
    if len(rows) != 196:
        raise AssertionError("fixed prerequisite count differs")
    return rows


def _lua_rows(rows: dict[str, list[str]]) -> str:
    parts = []
    for name, parents in rows.items():
        encoded = ",".join(f'"{parent}"' for parent in parents)
        parts.append(f'["{name}"]={{{encoded}}}')
    return "{" + ",".join(parts) + "}"


WORLD = r'''
local WORKER, PREDECESSOR, DEEP = "worker-robots-speed-10", "worker-robots-speed-9", "se-deep-space-science-pack-1"
local FIXTURE = "mir-fixture-se-worker-speed-provider-admitted"
local CURRENT, QUEUED = "mir-fixture-se-worker-speed-provider-unrelated", "mir-fixture-se-worker-speed-provider-queued"
local SCIENCE={"automation-science-pack","logistic-science-pack","chemical-science-pack","utility-science-pack",
  "space-science-pack","se-rocket-science-pack","se-energy-science-pack-4","se-deep-space-science-pack-1"}
local WORKER_UNITS={[10]=3200,[11]=6400,[13]=25600}
local closure = {
  base="2.0.77", ["space-exploration"]="0.7.57", ["aai-containers"]="0.3.2", ["aai-industry"]="0.6.16",
  ["alien-biomes"]="0.7.4", ["alien-biomes-graphics"]="0.7.1", jetpack="0.4.17", robot_attrition="0.6.6",
  ["shield-projector"]="0.2.2", ["space-exploration-graphics"]="0.7.5", ["space-exploration-graphics-2"]="0.7.2",
  ["space-exploration-graphics-3"]="0.7.2", ["space-exploration-graphics-4"]="0.7.2",
  ["space-exploration-graphics-5"]="0.7.3", ["space-exploration-menu-simulations"]="0.7.4",
  ["space-exploration-postprocess"]="0.7.5", informatron="0.4.0", ["aai-signal-transmission"]="0.5.3"
}
local stages = {
  source={fixture="0.1.0",mir="5.0.20015",cap=0}, admission={fixture="0.2.0",mir="5.0.20015",cap=0},
  old={fixture="0.3.0",mir="5.0.20015",cap=10}, candidate={fixture="0.4.0",mir="5.0.20018",cap=10}
}
local function copy(v)if type(v)~="table"then return v end local o={}for k,x in pairs(v)do o[k]=copy(x)end return o end
local function tech(name, level, max_level, effects)
  return {name=name,valid=true,level=level or 1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
    prototype={max_level=max_level or 1,effects=effects or {}},prerequisites={}}
end
local function effect(name)
  local values={ ["worker-robots-speed-1"]=.35,["worker-robots-speed-2"]=.4,["worker-robots-speed-3"]=.45,
    ["worker-robots-speed-4"]=.55,["worker-robots-speed-5"]=.65,["worker-robots-speed-6"]=.65,
    ["worker-robots-speed-7"]=.65,["worker-robots-speed-8"]=.65,["worker-robots-speed-9"]=.65 }
  return values[name] and {{type="worker-robot-speed",modifier=values[name]}} or {}
end
local function make_force(name,index,rows)
  local technologies={}
  for technology_name in pairs(rows) do
    local level=tonumber(technology_name:match("worker%-robots%-speed%-(%d+)$")) or 1
    technologies[technology_name]=tech(technology_name,level,1,effect(technology_name))
  end
  technologies[WORKER]=tech(WORKER,10,4294967295,{{type="worker-robot-speed",modifier=.65}})
  technologies[WORKER].research_unit_count,technologies[WORKER].research_unit_energy=3200,3600
  technologies[WORKER].research_unit_ingredients={}
  for index,name in ipairs(SCIENCE)do technologies[WORKER].research_unit_ingredients[index]={name=name,amount=1}end
  technologies[CURRENT]=tech(CURRENT,1,1,{})
  technologies[QUEUED]=tech(QUEUED,1,1,{})
  for technology_name, parents in pairs(rows) do
    local target=technologies[technology_name]
    for _, parent in ipairs(parents) do target.prerequisites[parent]=technologies[parent] end
  end
  technologies[WORKER].prerequisites[PREDECESSOR]=technologies[PREDECESSOR]
  technologies[WORKER].prerequisites[DEEP]=technologies[DEEP]
  local values={name=name,index=index,valid=true,technologies=technologies,_queue={},research_progress=0,worker_robots_speed_modifier=0}
  local force={}
  function force.reset_technology_effects()
    local worker=technologies[WORKER]
    worker.research_unit_count=WORKER_UNITS[worker.level] or -1
    values.worker_robots_speed_modifier=5+math.max(0,worker.level-10)*.65
  end
  setmetatable(force,{__index=function(_,key)
      if key=="research_queue"then return values._queue end
      if key=="current_research"then return values._queue[1] end
      return values[key]
    end,__newindex=function(_,key,value)
      if key~="research_queue"then values[key]=value;return end
      local rows={};for index,item in ipairs(value)do
        local technology=type(item)=="string"and technologies[item]or item
        assert(technology and technology.name);rows[index]=technology
      end;values._queue=rows
    end})
  for _, technology in pairs(technologies) do technology.force=force end
  return force
end
local function inventory()
  local values,blocked={},false
  return {insert=function(item)
      if blocked then return 0 end
      local count=math.min(item.count,200-(values[item.name]or 0));values[item.name]=(values[item.name]or 0)+count;return count
    end,get_item_count=function(name)return values[name]or 0 end,
    decrement=function(name,count)values[name]=math.max(0,(values[name]or 0)-count)end,
    block_refills=function()blocked=true end}
end
local function lab()
  local input,modules=inventory(),{is_empty=function()return true end}
  return {valid=true,name="mir-fixture-se-worker-speed-provider-lab",disabled_by_script=false,unit_number=91,get_inventory=function(kind)return kind==1 and input or modules end,
    prototype={get_researching_speed=function()return 14400 end},_input=input}
end
function provider_world(rows)
  handlers, markers, logs, files, saves, storage = {},{},{},{},{},{}
  local player=make_force("player",1,rows);local forces={player=player,[1]=player};local next_index=2
  game={tick=0,forces=forces,surfaces={[1]={create_entity=function(spec)
      assert(spec.name=="mir-fixture-se-worker-speed-provider-lab" and spec.force==player);game.lab=lab();return game.lab end}},
    create_force=function(name)local value=make_force(name,next_index,rows);next_index=next_index+1;forces[name]=value;forces[value.index]=value;return value end,
    is_multiplayer=function()return true end,server_save=function(name)saves[#saves+1]=name end}
end
function provider_stage(wrapper, common, prerequisites, name)
  local selected=assert(stages[name]);local active=copy(closure);active[FIXTURE]=selected.fixture;active["more-infinite-research"]=selected.mir
  local function plain(value,path,seen)
    local kind=type(value)
    assert(kind=="nil" or kind=="boolean" or kind=="number" or kind=="string" or kind=="table","marker non-plain value at "..path)
    if kind~="table"then return end
    assert(value~=game.lab,"marker retains native lab at "..path)
    assert(not seen[value],"marker cycle at "..path);seen[value]=true
    for key,item in pairs(value)do
      local key_kind=type(key);assert(key_kind=="number" or key_kind=="string","marker non-plain key at "..path)
      plain(item,path.."."..tostring(key),seen)
    end
    seen[value]=nil
  end
  local env={game=game,storage=storage,settings={startup={["mir-max-level-worker-robots-speed"]={value=selected.cap}}},
    script={active_mods=active,on_init=function(fn)handlers.init=fn end,on_load=function(fn)handlers.load=fn end,
      on_configuration_changed=function(fn)handlers.configuration=fn end,on_event=function(id,fn)handlers[id]=fn end},
    defines={events={on_tick=1,on_research_started=2,on_research_finished=3},inventory={lab_input=1,lab_modules=2}},
    helpers={table_to_json=function(row)plain(row,"marker",{});markers[#markers+1]=copy(row);return "{}"end,
      write_file=function(path,text,append)files[#files+1]={path=path,text=text,append=append}end},log=function(value)logs[#logs+1]=value end}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  local fixed=assert(loadfile(prerequisites,"t",env))()
  env.require=function(module)
    if module=="__mir-fixture-se-worker-speed-provider-admitted__/fixture_control"then return assert(loadfile(common,"t",env))()end
    if module=="__mir-fixture-se-worker-speed-provider-admitted__/prerequisites"then return fixed end
    error("unexpected require: "..tostring(module))
  end
  provider_fixed=fixed
  local ok,message=pcall(assert(loadfile(wrapper,"t",env)));return ok,message,env
end
function provider_call(name,event)local ok,message=pcall(handlers[name],event);return ok,tostring(message)end
function provider_tick(count)for _=1,count do game.tick=game.tick+1;local ok,message=provider_call(1);if not ok then return false,message end end;return true,""end
function provider_candidate_normalize()
  local player=game.forces.player;player.research_queue={player.technologies[WORKER]};player.research_progress=.27
  player.technologies[WORKER].enabled=true;player.technologies[WORKER].visible_when_disabled=false
  local foreign=game.forces["mir5-se-worker-speed-provider-foreign"].technologies[WORKER]
  local earned=game.forces["mir5-se-worker-speed-provider-earned"].technologies[WORKER]
  foreign.enabled,foreign.visible_when_disabled=false,true;earned.enabled,earned.visible_when_disabled=false,true
end
function provider_research_tick(by_script)
  local player=game.forces.player;local worker=player.technologies[WORKER]
  local required=worker.research_unit_count
  if by_script then player._provider_remaining=0 else
    local remaining=player._provider_remaining
    if remaining==nil then remaining=required-(player.research_progress*required)end
    local available=remaining
    for _,ingredient in ipairs(worker.research_unit_ingredients)do available=math.min(available,game.lab._input.get_item_count(ingredient.name))end
    if available<=0 then return false,"world research input exhausted"end
    for _,ingredient in ipairs(worker.research_unit_ingredients)do game.lab._input.decrement(ingredient.name,available)end
    remaining=remaining-available;player._provider_remaining=remaining;player.research_progress=(required-remaining)/required
    if remaining>0 then return true,""end
  end
  player.research_queue={};player.research_progress=0;worker.level=11;worker.researched=false;worker.enabled=false;worker.visible_when_disabled=true;player.reset_technology_effects()
  return provider_call(3,{research=worker,by_script=by_script,tick=game.tick})
end
function provider_finish(by_script)
  if by_script then return provider_research_tick(true) end
  for _=1,64 do
    local ok,message=provider_research_tick(false);if not ok then return false,message end
    ok,message=provider_tick(1);if not ok then return false,message end
    if game.forces.player.technologies[WORKER].level==11 then return true,""end
  end
  return false,"world research completion did not occur"
end
function provider_disable_lab_refills()
  game.lab._input.block_refills()
end
function provider_start_eleven()
  local player=game.forces.player;local worker=player.technologies[WORKER];worker.level=11
  return provider_call(2,{research=worker,tick=game.tick})
end
'''


def install(lua) -> None:
    rows = _rows()
    lua.execute(f"PROVIDER_ROWS={_lua_rows(rows)}")
    lua.execute(WORLD)
    lua.globals().provider_world(lua.globals().PROVIDER_ROWS)


def load_stage(lua, stage: str) -> None:
    wrapper = (FIXTURE / stage / "control.lua").as_posix()
    common = (FIXTURE / "fixture_control.lua").as_posix()
    prerequisites = (FIXTURE / "prerequisites.lua").as_posix()
    ok, message, _ = lua.globals().provider_stage(wrapper, common, prerequisites, stage)
    if not ok:
        raise AssertionError(message)


def rows() -> dict[str, list[str]]:
    """Independent callers can inspect the portable static 196-row declaration."""
    return _rows()
