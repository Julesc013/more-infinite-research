"""Small Lua52 host world for the published-5.0.20017 source-only fixture."""

from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-storage-published517-earned-source"
TARGET = "mir-worker-storage-default-4"
PREDECESSOR = "worker-robots-storage-3"
TAIL = "mir-fixture-published517-earned-source-tail"
SCIENCE = ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack")
SETTINGS = {
    "mir-enable-worker-robots-storage": True, "mir-max-level-worker-robots-storage": 10,
    "mir-cost-base-worker-robots-storage": 200, "mir-cost-linear-increment-worker-robots-storage": 0,
    "mir-cost-growth-worker-robots-storage": 1.5, "mir-research-time-worker-robots-storage": 60,
    "mir-effect-per-level-worker-robots-storage": 1,
}
CLOSURE = {
    "base": "2.0.77", "space-exploration": "0.7.57", "aai-containers": "0.3.2", "aai-industry": "0.6.16",
    "alien-biomes": "0.7.4", "alien-biomes-graphics": "0.7.1", "jetpack": "0.4.17", "robot_attrition": "0.6.6",
    "shield-projector": "0.2.2", "space-exploration-graphics": "0.7.5", "space-exploration-graphics-2": "0.7.2",
    "space-exploration-graphics-3": "0.7.2", "space-exploration-graphics-4": "0.7.2",
    "space-exploration-graphics-5": "0.7.3", "space-exploration-menu-simulations": "0.7.4",
    "space-exploration-postprocess": "0.7.5", "informatron": "0.4.0", "aai-signal-transmission": "0.5.3",
}


def rows() -> dict[str, list[str]]:
    source = (FIXTURE / "prerequisites.lua").read_text(encoding="utf-8")
    match = re.search(r"ROW_TEXT = \[\[\n(.*?)\n\]\]", source, re.DOTALL)
    if match is None:
        raise AssertionError("literal fixed prerequisite declaration is absent")
    parsed: dict[str, list[str]] = {}
    for line in match.group(1).splitlines():
        name, parents = line.split("=", 1)
        if not name or name in parsed:
            raise AssertionError("fixed prerequisite declaration is malformed")
        parsed[name] = [] if not parents else parents.split("|")
    if len(parsed) != 101:
        raise AssertionError("fixed prerequisite declaration count differs")
    return parsed


WORLD = r'''
local TARGET,PREDECESSOR,TAIL="mir-worker-storage-default-4","worker-robots-storage-3","mir-fixture-published517-earned-source-tail"
local FORCE_NAME="mir5-worker-storage-published517-earned-source"
local POWER,LAB,POLE="mir-fixture-published517-earned-source-power","se-space-science-lab","substation"
local SCIENCE={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","utility-science-pack"}
local function copy(v) if type(v)~="table" then return v end local o={} for k,x in pairs(v)do o[k]=copy(x)end return o end
local function other_force(name,index,bonus)
 local v={name=name,index=index,valid=true,technologies={},worker_robots_storage_bonus=bonus or 0,worker_robots_speed_modifier=0,artillery_range_modifier=0}
 v.get_gun_speed_modifier=function(category)assert(category=="artillery-shell" or category=="laser");return 0 end
 v.get_ammo_damage_modifier=function(category)assert(category=="laser");return 0 end;return v
end
local function build_force(name,index,declaration)
 local values=other_force(name,index,0);values.laboratory_speed_modifier=0;values._queue={};values._current=nil;values._progress=0;local techs,backing={},{};local force
 local function tech(name)
  local v={name=name,object_name="LuaTechnology",valid=true,level=1,researched=false,enabled=true,visible_when_disabled=false,prerequisites={},prototype={max_level=1,effects={}},research_unit_count=1,research_unit_energy=60,research_unit_ingredients={}}
  local o=setmetatable({}, {__index=v,__newindex=function(_,k,x)
   if k=="researched" and x==true and v.researched~=true and (name=="worker-robots-storage-1" or name=="worker-robots-storage-2" or name=="worker-robots-storage-3") then values.worker_robots_storage_bonus=values.worker_robots_storage_bonus+1 end;v[k]=x end})
  techs[name],backing[name]=o,v
 end
 for name in pairs(declaration)do tech(name)end;tech(TARGET);tech(TAIL)
 for name,parents in pairs(declaration)do for _,parent in ipairs(parents)do backing[name].prerequisites[parent]=techs[parent]end end
 local target=backing[TARGET];target.level=4;target.visible_when_disabled=false;target.prototype.max_level=4294967295;target.prototype.effects={{type="worker-robot-storage",modifier=1}};target.research_unit_count_formula="675*1.5^(L-4)";target.research_unit_count=675;target.research_unit_energy=3600
 for field,value in pairs(P517_INITIAL_ROLE_OVERRIDES or {})do if value==P517_INITIAL_ROLE_NIL then target[field]=nil else target[field]=value end end
 for i,name in ipairs(SCIENCE)do target.research_unit_ingredients[i]={name=name,amount=1}end;if P517_OMIT_TARGET_PREREQUISITE~="utility-science-pack" then target.prerequisites["utility-science-pack"]=techs["utility-science-pack"] end;if P517_OMIT_TARGET_PREREQUISITE~=PREDECESSOR then target.prerequisites[PREDECESSOR]=techs[PREDECESSOR] end;if P517_EXTRA_TARGET_PREREQUISITE=="worker-robots-storage-2" then target.prerequisites["worker-robots-storage-2"]=techs["worker-robots-storage-2"] end;backing[TAIL].prerequisites["automation-science-pack"]=techs["automation-science-pack"];values.technologies=techs
 values.add_research=function(row)if type(row)=="string" then row=techs[row]end;if row~=techs[TARGET] or backing[TARGET].enabled~=true then return false end;if values._current then values._queue[#values._queue+1]=row;return true end;values._queue={row};values._current=row;values._progress=0;return true end
 force=setmetatable({}, {__index=function(_,key)if key=="research_queue" then return values._queue end;if key=="current_research" then return values._current end;if key=="research_progress" then return values._progress end;return values[key]end,__newindex=function(_,key,value)
  if key=="research_queue" then local q={};for i,row in ipairs(value or {})do q[i]=row end;if P517_DROP_TAIL_ON_PARTIAL_ASSIGNMENT==true and #q==3 and q[3] and q[3].name==TAIL then table.remove(q,3)end;values._queue=q;values._current=q[1];values._progress=0;return end;if key=="research_progress" then values._progress=value;return end;if key=="laboratory_speed_modifier" then values.laboratory_speed_modifier=value;return end;error("LuaForce unsupported write "..tostring(key))end})
 for _,v in pairs(backing)do v.force=force end;return force,values
end
local function new_inventory()
 local rows,by_name={},{};local input={valid=true};input.get_item_count=function(name)local row=by_name[name];return row and row.count or 0 end
 input.insert=function(spec)local row=by_name[spec.name];if not row then row={valid_for_read=true,name=spec.name,quality={name="normal"},type="tool",is_tool=true,count=0,durability=1};by_name[spec.name]=row;rows[#rows+1]=row;input[#input+1]=row end;row.valid_for_read=true;row.count=row.count+spec.count;row.durability=1;return spec.count end
 local function consume()for _,name in ipairs(SCIENCE)do local row=by_name[name];assert(row and row.count>0,"science missing "..name);row.count=row.count-1;if row.count==0 then row.valid_for_read=false;row.durability=0 end end end
 local function partial(progress)for _,name in ipairs(SCIENCE)do local row=by_name[name];assert(row and row.count>0,"science missing "..name);row.durability=1-progress end end
 return input,consume,partial
end
function p517_world(declaration)
 P517_INITIAL_ROLE_NIL={};P517_INITIAL_ROLE_OVERRIDES=nil;P517_DROP_TAIL_ON_PARTIAL_ASSIGNMENT=false
 callbacks,logs,interfaces,storage={}, {}, {}, {};local player=other_force("player",1,0);local enemy=other_force("enemy",2,0);local neutral=other_force("neutral",3,0);local se=other_force("se-system",4,3);local forces={player=player,[1]=player,enemy=enemy,[2]=enemy,neutral=neutral,[3]=neutral,["se-system"]=se,[4]=se};local next_index=5;local lab,power,pole,input,consume,partial;local saves={}
 local surface={valid=true,create_entity=function(spec)local p=spec.position;local x,y=p[1] or p.x,p[2] or p.y;if spec.name==POWER then power={valid=true,name=POWER,force=spec.force,position={x=x,y=y},electric_network_id=1,prototype={tile_width=2,tile_height=2}};power.is_connected_to_electric_network=function()return true end;return power end;if spec.name==POLE then pole={valid=true,name=POLE,force=spec.force,position={x=x,y=y},electric_network_id=1,prototype={tile_width=2,tile_height=2}};return pole end;assert(spec.name==LAB);input,consume,partial=new_inventory();lab={valid=true,name=LAB,force=spec.force,position={x=x,y=y},electric_network_id=1,disabled_by_script=false,prototype={tile_width=7,tile_height=7,get_researching_speed=function()return 10 end}};lab.is_connected_to_electric_network=function()return true end;lab.get_inventory=function(i)assert(i==1);return input end;return lab end}
 local active=copy(P517_CLOSURE);active["more-infinite-research"]="5.0.20017";active["mir-fixture-mir5-worker-storage-published517-earned-source"]="0.1.0";local startup={};for name,value in pairs(P517_SETTINGS)do startup[name]={valid=true,value=value}end
 game={tick=0,forces=forces,surfaces={[1]=surface},create_force=function(name)assert(forces[name]==nil);local force,values=build_force(name,next_index,declaration);P517_FORCE_VALUES=values;next_index=next_index+1;forces[name]=force;forces[force.index]=force;return force end,server_save=function(name)saves[#saves+1]=name end}
 script={active_mods=active,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,on_configuration_changed=function(fn)callbacks.configuration=fn end,on_event=function(id,fn)callbacks[id]=fn end};remote={add_interface=function(name,value)interfaces[name]=value end};settings={startup=startup};defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}};local items={};for _,name in ipairs(SCIENCE)do items[name]={type="tool",get_durability=function(quality)assert(quality and quality.name=="normal");return 1 end}end
 local env={game=game,script=script,remote=remote,settings=settings,defines=defines,storage=storage,prototypes={item=items},log=function(line)logs[#logs+1]=line end};env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end});env.require=function(name)assert(name=="__mir-fixture-mir5-worker-storage-published517-earned-source__/prerequisites",name);local rows,by_name={},{};for _,entry in ipairs(P517_ORDER)do local row={name=entry[1],parents=entry[2]};rows[#rows+1]=row;by_name[row.name]=row end;return {rows=rows,by_name=by_name}end
 P517_ENV=env;P517_CALLBACKS=callbacks;P517_INTERFACES=interfaces;P517_LOGS=logs;P517_SAVES=saves;P517_COMPLETE=function(by_script)local force=forces[FORCE_NAME];assert(force and force.current_research);local target=force.current_research;target.level=target.level+1;P517_FORCE_VALUES.worker_robots_storage_bonus=P517_FORCE_VALUES.worker_robots_storage_bonus+1;consume();table.remove(force.research_queue,1);force.research_queue=force.research_queue;callbacks[2]({research=target,by_script=by_script})end;P517_PARTIAL=function(progress)local force=forces[FORCE_NAME];force.research_progress=progress;partial(progress)end
end
function p517_load(path)local fn,message=loadfile(path,"t",P517_ENV);assert(fn,message);fn();P517_CALLBACKS.init()end
function p517_begin()return P517_INTERFACES["mir-fixture-mir5-worker-storage-published517-earned-source"].begin()end
function p517_tick(count)for _=1,count do game.tick=game.tick+1;P517_CALLBACKS[1]({tick=game.tick})end end
function p517_complete(by_script)return P517_COMPLETE(by_script)end;function p517_partial(progress)return P517_PARTIAL(progress)end;function p517_cold()P517_CALLBACKS.load();p517_tick(1)end;function p517_configuration()return P517_CALLBACKS.configuration({mod_changes={}})end
function p517_phase()local state=storage["mir5_worker_storage_published517_earned_source"];return state and state.phase end;function p517_logs()return P517_LOGS end;function p517_saves()return P517_SAVES end;function p517_state()return storage["mir5_worker_storage_published517_earned_source"]end;function p517_force()return game.forces[FORCE_NAME]end;function p517_setting(name,value)settings.startup[name].value=value end
function p517_override_initial_role(field,value)P517_INITIAL_ROLE_OVERRIDES={[field]=value}end;function p517_omit_initial_role(field)P517_INITIAL_ROLE_OVERRIDES={[field]=P517_INITIAL_ROLE_NIL}end
function p517_drop_tail_on_partial_assignment()P517_DROP_TAIL_ON_PARTIAL_ASSIGNMENT=true end
function p517_add_foreign(count)for index=1,count do local force=other_force("overflow-"..tostring(index),100+index,0);game.forces[force.name]=force;game.forces[force.index]=force end end
'''


def install(lua) -> None:
    declaration = rows()
    order = "{" + ",".join("{%r,{%s}}" % (name, ",".join(repr(parent) for parent in parents)) for name, parents in declaration.items()) + "}"
    mapping = "{" + ",".join(f"[{name!r}]={{{','.join(repr(parent) for parent in parents)}}}" for name, parents in declaration.items()) + "}"
    closure = "{" + ",".join(f"[{name!r}]={version!r}" for name, version in CLOSURE.items()) + "}"
    settings = "{" + ",".join(f"[{name!r}]={str(value).lower() if isinstance(value, bool) else value}" for name, value in SETTINGS.items()) + "}"
    lua.execute(f"P517_ORDER={order};P517_DECLARATION={mapping};P517_CLOSURE={closure};P517_SETTINGS={settings}")
    lua.execute(WORLD)
    lua.globals().p517_world(lua.globals().P517_DECLARATION)


def load(lua) -> None:
    lua.globals().p517_load((FIXTURE / "control.lua").as_posix())
