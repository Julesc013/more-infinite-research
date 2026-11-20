"""Strict Lua52-style world for the SE worker-storage cargo fixture.

The world represents only documented members consumed by the fixture. Engine
completion and the published C4→private recovery transfer are host operations;
the fixture cannot write technology levels or research progress.
"""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-storage-se-cap-ten-native"
SOURCE = TARGET = "worker-robots-storage-4"
CANDIDATE = "mir-worker-storage-default-4"
HEAD = "mir-worker-storage-head-4"
PREDECESSOR = "worker-robots-storage-3"
TAIL = "mir-fixture-worker-storage-se-cap-ten-tail"
LAB = "se-space-science-lab"
POWER = "mir-fixture-worker-storage-se-cap-ten-power"
POLE = "substation"
SCIENCE = (
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
    "se-rocket-science-pack", "se-material-science-pack-1", "space-science-pack",
)
SETTINGS = {
    "mir-enable-worker-robots-storage": True,
    "mir-max-level-worker-robots-storage": 10,
    "mir-cost-base-worker-robots-storage": 200,
    "mir-cost-linear-increment-worker-robots-storage": 0,
    "mir-cost-growth-worker-robots-storage": 1.5,
    "mir-research-time-worker-robots-storage": 60,
    "mir-effect-per-level-worker-robots-storage": 1,
}
CLOSURE = {
    "base": "2.0.77", "space-exploration": "0.7.57", "aai-containers": "0.3.2",
    "aai-industry": "0.6.16", "alien-biomes": "0.7.4", "alien-biomes-graphics": "0.7.1",
    "jetpack": "0.4.17", "robot_attrition": "0.6.6", "shield-projector": "0.2.2",
    "space-exploration-graphics": "0.7.5", "space-exploration-graphics-2": "0.7.2",
    "space-exploration-graphics-3": "0.7.2", "space-exploration-graphics-4": "0.7.2",
    "space-exploration-graphics-5": "0.7.3", "space-exploration-menu-simulations": "0.7.4",
    "space-exploration-postprocess": "0.7.5", "informatron": "0.4.0", "aai-signal-transmission": "0.5.3",
}


def rows() -> dict[str, list[str]]:
    """Read the literal prerequisite declaration without evaluating Lua."""
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
    if len(parsed) != 98:
        raise AssertionError("fixed prerequisite declaration count differs")
    return parsed


WORLD = r'''
local SOURCE,CANDIDATE,HEAD="worker-robots-storage-4","mir-worker-storage-default-4","mir-worker-storage-head-4"
local PREDECESSOR,TAIL="worker-robots-storage-3","mir-fixture-worker-storage-se-cap-ten-tail"
local LAB,POWER,POLE="se-space-science-lab","mir-fixture-worker-storage-se-cap-ten-power","substation"
local SCIENCE={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","se-rocket-science-pack","se-material-science-pack-1","space-science-pack"}
local function copy(v) if type(v)~="table" then return v end local o={} for k,x in pairs(v) do o[k]=copy(x) end return o end
local function strict(values,reads,writes,label)
  return setmetatable({}, {__index=function(_,k) if reads[k] then return values[k] end error(label.." unsupported read "..tostring(k)) end,
    __newindex=function(_,k,v) if writes[k] then values[k]=v;return end error(label.." unsupported write "..tostring(k)) end})
end
local function new_tech(name)
  local v={name=name,valid=true,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,prerequisites={},prototype={max_level=1,effects={}},research_unit_count=1,research_unit_energy=60,research_unit_ingredients={}}
  local r={name=true,valid=true,level=true,researched=true,enabled=true,visible_when_disabled=true,saved_progress=true,prerequisites=true,prototype=true,research_unit_count=true,research_unit_count_formula=true,research_unit_energy=true,research_unit_ingredients=true,force=true}
  return strict(v,r,{researched=true,enabled=true,visible_when_disabled=true,saved_progress=true},"LuaTechnology"),v
end
local function new_inventory()
  local counts,slots,by_name={},{},{}
  local function add(name,count)
    local raw=by_name[name]
    if raw==nil then
      raw={valid_for_read=true,name=name,quality={name="normal"},type="tool",is_tool=true,count=0,durability=1}
      by_name[name]=raw
      slots[#slots+1]=strict(raw,{valid_for_read=true,name=true,quality=true,type=true,is_tool=true,count=true,durability=true},{},"LuaItemStack")
    end
    raw.count=raw.count+count;raw.durability=CARGO_FLAGS.bad_durability and 2 or raw.durability;counts[name]=raw.count
  end
  local function spend_one()
    for _,name in ipairs(SCIENCE) do
      local raw=by_name[name]
      assert(raw and raw.count>0,"native lab science missing "..name)
      raw.count=raw.count-1;counts[name]=raw.count
    end
  end
  local function set_partial(progress)
    for _,name in ipairs(SCIENCE) do
      local raw=by_name[name]
      assert(raw and raw.count>0,"native lab science missing "..name)
      raw.durability=1-progress
    end
  end
  local values={valid=true,get_item_count=function(name)return counts[name] or 0 end,insert=function(spec)
    assert(type(spec)=="table" and type(spec.name)=="string" and type(spec.count)=="number")
    if CARGO_FLAGS.blocked_feed then return 0 end;add(spec.name,spec.count);return spec.count end}
  local inventory=setmetatable({}, {__index=function(_,key)
    if type(key)=="number" then return slots[key] end
    if values[key]~=nil then return values[key] end
    error("LuaInventory unsupported read "..tostring(key)) end,
    __newindex=function(_,key)error("LuaInventory unsupported write "..tostring(key)) end,
    __len=function()return #slots end})
  return inventory,counts,spend_one,set_partial
end
local function worker_contract(v,all)
  v.prototype.max_level=4294967295;v.prototype.effects={{type="worker-robot-storage",modifier=1}}
  v.research_unit_count_formula="675*1.5^(L-4)";v.research_unit_count=675;v.research_unit_energy=3600
  for i,n in ipairs(SCIENCE) do v.research_unit_ingredients[i]={name=n,amount=1} end
  v.prerequisites[PREDECESSOR]=all[PREDECESSOR]
end
local function new_force(declaration)
  local all,backing={},{}
  for name in pairs(declaration) do all[name],backing[name]=new_tech(name) end
  for _,name in ipairs({SOURCE,CANDIDATE,HEAD,TAIL}) do all[name],backing[name]=new_tech(name) end
  for name,parents in pairs(declaration) do for _,parent in ipairs(parents) do backing[name].prerequisites[parent]=all[parent] end end
  worker_contract(backing[SOURCE],all);worker_contract(backing[CANDIDATE],all);backing[SOURCE].level=4
  local values={name="player",index=1,valid=true,technologies=all,_queue={},_current=nil,_progress=0,_queue_enabled=true,laboratory_speed_modifier=0,laboratory_productivity_bonus=0,worker_robots_storage_bonus=0}
  local force
  values.add_research=function(row)
    if type(row)=="string" then row=all[row] end
    if row~=all[SOURCE] and row~=all[CANDIDATE] then return false end
    if backing[row.name].enabled~=true then return false end
    if values._current~=nil then
      if values._queue_enabled~=true then return false end
      values._queue[#values._queue+1]=row;return true
    end
    values._queue={row};values._current=row;values._progress=0;return true
  end
  local readable={name=true,index=true,valid=true,technologies=true,laboratory_speed_modifier=true,laboratory_productivity_bonus=true,worker_robots_storage_bonus=true}
  force=setmetatable({}, {__index=function(_,key)
    if key=="research_queue" then return values._queue end
    if key=="current_research" then return values._current end
    if key=="research_progress" then return values._progress end
    if key=="add_research" then return values.add_research end
    if readable[key] then return values[key] end
    error("LuaForce unsupported read "..tostring(key)) end,
    __newindex=function(_,key,value)
      if key=="research_queue" then local q={};for i,row in ipairs(value or {}) do q[i]=row end;values._queue=q;values._current=q[1];values._progress=0;return end
      if key=="research_progress" then assert(values._current~=nil,"progress without current");values._progress=value;return end
      if key=="laboratory_speed_modifier" or key=="laboratory_productivity_bonus" then values[key]=value;return end
      error("LuaForce unsupported write "..tostring(key)) end})
  for _,row in pairs(all) do backing[row.name].force=force end
  return force,backing,values
end
local function transfer(force,backing,values)
  local source,private,head=backing[SOURCE],backing[CANDIDATE],backing[HEAD]
  private.level=source.level;private.researched=source.researched;private.enabled=source.enabled;private.visible_when_disabled=source.visible_when_disabled;private.saved_progress=source.saved_progress
  source.level=5;source.researched=false;source.enabled=false
  head.level=5;head.researched=false;head.enabled=false;head.visible_when_disabled=false
  for i,row in ipairs(values._queue) do if row==force.technologies[SOURCE] then values._queue[i]=force.technologies[CANDIDATE] end end
  values._current=values._queue[1]
end
function cargo_world(declaration)
  callbacks,logs,interfaces,storage={}, {}, {}, {}
  local player,backing,values=new_force(declaration)
  local lab,power,pole,input,counts,spend_science,set_partial_science;local flags={missing_power=false,missing_pole=false,disconnected_network=false,wrong_network=false,blocked_feed=false,bad_durability=false};local saves={};local entity_specs={}
  local foreign_values={valid=true,index=2,worker_robots_storage_bonus=0}
  local foreign=strict(foreign_values,{valid=true,index=true,worker_robots_storage_bonus=true},{worker_robots_storage_bonus=true},"LuaForce")
  local positions={[POWER]={0,0},[LAB]={8,0},[POLE]={0,6}}
  local function network_entity(name,x,y,network)
    local values={valid=true,name=name,force=player,position={x=x,y=y},electric_network_id=network}
    values.is_connected_to_electric_network=function()return name ~= POLE and not flags.disconnected_network end
    return strict(values,{valid=true,name=true,force=true,position=true,electric_network_id=true,is_connected_to_electric_network=true},{},"LuaEntity")
  end
  local surface={valid=true,create_entity=function(spec)
    assert(spec.force==player);local expected=positions[spec.name];assert(expected,"unexpected fixture entity "..tostring(spec.name));local position=spec.position or {};local x,y=position.x or position[1],position.y or position[2];assert(x==expected[1] and y==expected[2],"fixture entity position differs");entity_specs[#entity_specs+1]={name=spec.name,x=x,y=y}
    if spec.name==POWER then if flags.missing_power then return nil end;power=network_entity(POWER,x,y,1);return power end
    if spec.name==POLE then if flags.missing_pole then return nil end;pole=network_entity(POLE,x,y,flags.wrong_network and 2 or 1);return pole end
    input,counts,spend_science,set_partial_science=new_inventory();local values={valid=true,name=LAB,unit_number=91,force=player,position={x=x,y=y},electric_network_id=1,energy=0,electric_buffer_size=1000000,disabled_by_script=false,prototype={get_researching_speed=function()return flags.lab_speed or 10 end}};values.is_connected_to_electric_network=function()return not flags.disconnected_network end;values.get_inventory=function(i)assert(i==1);return input end;lab=strict(values,{valid=true,name=true,unit_number=true,force=true,position=true,electric_network_id=true,energy=true,electric_buffer_size=true,disabled_by_script=true,prototype=true,is_connected_to_electric_network=true,get_inventory=true},{disabled_by_script=true},"LuaEntity");return lab end}
  local active=copy(CARGO_CLOSURE);active["more-infinite-research"]="4.7.20002";active["mir-fixture-mir5-worker-storage-se-cap-ten-native"]="0.1.0"
  local startup={};for n,v in pairs(CARGO_SETTINGS) do startup[n]={valid=true,value=v,default_value=0} end
  game={tick=0,difficulty_settings={technology_price_multiplier=1},forces={player=player,[1]=player,foreign=foreign,[2]=foreign},surfaces={[1]=surface},server_save=function(n)saves[#saves+1]=n end}
  script={active_mods=active,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,on_configuration_changed=function(fn)callbacks.configuration=fn end,on_event=function(id,fn)callbacks[id]=fn end}
  remote={add_interface=function(n,v)interfaces[n]=v end};settings={startup=startup};defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}
  local item_prototypes={};for _,name in ipairs(SCIENCE) do item_prototypes[name]={type="tool",get_durability=function(quality)assert(quality and quality.name=="normal");return 1 end} end
  local env={game=game,script=script,remote=remote,settings=settings,defines=defines,storage=storage,prototypes={item=item_prototypes},log=function(t)logs[#logs+1]=t end};env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end})
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-worker-storage-se-cap-ten-native__/prerequisites",name);local rs,by_name={},{}
    for _,entry in ipairs(CARGO_DECLARATION_ORDER) do local row={name=entry[1],parents=entry[2]};rs[#rs+1]=row;by_name[row.name]=row end
    return {rows=rs,by_name=by_name} end
  CARGO_ENV=env;CARGO_CALLBACKS=callbacks;CARGO_LOGS=logs;CARGO_INTERFACES=interfaces;CARGO_FORCE_VALUES=values;CARGO_TECHNOLOGIES=values.technologies;CARGO_TECH_BACKING=backing;CARGO_FLAGS=flags;CARGO_SAVES=saves;CARGO_LAB_COUNTS=function()return copy(counts or {})end;CARGO_ENTITIES=function()return copy(entity_specs)end;CARGO_FOREIGN_VALUES=foreign_values
  CARGO_TRANSFER=function()transfer(player,backing,values)end;CARGO_CONSUME=function()assert(spend_science);spend_science()end;CARGO_PARTIAL=function(progress)assert(set_partial_science);set_partial_science(progress)end
  return env
end
function cargo_load(path)local fn,msg=loadfile(path,"t",CARGO_ENV);assert(fn,msg);fn();assert(CARGO_CALLBACKS.init);CARGO_CALLBACKS.init()end
function cargo_begin()return CARGO_INTERFACES["mir-fixture-mir5-worker-storage-se-cap-ten-native"].begin()end
function cargo_tick(n)for _=1,n do game.tick=game.tick+1;CARGO_CALLBACKS[1]()end end
function cargo_partial(p)CARGO_FORCE_VALUES._progress=p;CARGO_PARTIAL(p) end
function cargo_complete(by_script,cursor,reward)
  local target=CARGO_FORCE_VALUES._current;assert(target,"completion without current");local values=CARGO_TECH_BACKING[target.name];local level=values.level+1;values.level=level;CARGO_FORCE_VALUES.worker_robots_storage_bonus=reward==nil and level-4 or reward;if target.name==CANDIDATE and level==11 then values.enabled=false end;CARGO_CONSUME();table.remove(CARGO_FORCE_VALUES._queue,1);CARGO_FORCE_VALUES._current=CARGO_FORCE_VALUES._queue[1];CARGO_FORCE_VALUES._progress=0
  local event={research=target,by_script=by_script,tick=game.tick};if cursor~=nil then values.level=cursor end;CARGO_CALLBACKS[2](event);if cursor~=nil then values.level=level end end
function cargo_candidate(mir,mutate,startup_changed)
  script.active_mods["more-infinite-research"]=mir or "5.0.20018";CARGO_TRANSFER();if mutate then mutate(CARGO_TECHNOLOGIES[CANDIDATE],CARGO_TECHNOLOGIES[SOURCE],CARGO_TECHNOLOGIES[HEAD],CARGO_FORCE_VALUES) end
  local changed=false;if startup_changed~=nil then changed=startup_changed end
  CARGO_CALLBACKS.configuration({mod_startup_settings_changed=changed,mod_changes={["more-infinite-research"]={old_version="4.7.20002",new_version=script.active_mods["more-infinite-research"]}}}) end
function cargo_on_load()CARGO_CALLBACKS.load()end
function cargo_cold()CARGO_CALLBACKS.load();game.tick=game.tick+1;CARGO_CALLBACKS[1]()end
function cargo_logs()return CARGO_LOGS end;function cargo_counts()return CARGO_LAB_COUNTS()end;function cargo_saves()return CARGO_SAVES end;function cargo_phase()return storage["mir5_worker_storage_se_cap_ten_native"].phase end
function cargo_set_phase(phase)storage["mir5_worker_storage_se_cap_ten_native"].phase=phase end
function cargo_unsupported_force_write()game.forces.player.unapproved=true end;function cargo_missing_power()CARGO_FLAGS.missing_power=true end;function cargo_missing_pole()CARGO_FLAGS.missing_pole=true end;function cargo_disconnected_electric_network()CARGO_FLAGS.disconnected_network=true end;function cargo_wrong_electric_network()CARGO_FLAGS.wrong_network=true end;function cargo_block_feed()CARGO_FLAGS.blocked_feed=true end;function cargo_setting(n,v)settings.startup[n].value=v end
function cargo_science(names)
  for _,worker in ipairs({SOURCE,CANDIDATE}) do
    local v=CARGO_TECH_BACKING[worker];v.research_unit_ingredients={};for i,n in ipairs(names) do v.research_unit_ingredients[i]={name=n,amount=1} end
  end
end
function cargo_lab_speed(v)CARGO_FLAGS.lab_speed=v end;function cargo_drop_queue()CARGO_FORCE_VALUES._queue={};CARGO_FORCE_VALUES._current=nil end;function cargo_mutate_closed()CARGO_FORCE_VALUES.worker_robots_storage_bonus=999 end;function cargo_mutate_bonus(v)CARGO_FORCE_VALUES.worker_robots_storage_bonus=v end;function cargo_bad_science_durability()CARGO_FLAGS.bad_durability=true end
function cargo_wrong_gate()CARGO_TECH_BACKING[HEAD].enabled=true end;function cargo_add_late_force()CARGO_FOREIGN_VALUES.worker_robots_storage_bonus=5 end
function cargo_reenable_cap()CARGO_TECH_BACKING[CANDIDATE].enabled=true end
function cargo_reenable_cap_and_queue()CARGO_TECH_BACKING[CANDIDATE].enabled=true;return CARGO_FORCE_VALUES.add_research(CARGO_TECHNOLOGIES[CANDIDATE]) end
function cargo_queue_names()local o={};for i,row in ipairs(CARGO_FORCE_VALUES._queue) do o[i]=row.name end;return o end;function cargo_current_name()return CARGO_FORCE_VALUES._current and CARGO_FORCE_VALUES._current.name or false end;function cargo_entities()return CARGO_ENTITIES()end
'''


def install(lua) -> None:
    declaration = rows()
    mapping = "{" + ",".join(
        f'[{name!r}]={{{",".join(repr(parent) for parent in parents)}}}'
        for name, parents in declaration.items()
    ) + "}"
    ordered = "{" + ",".join(
        "{%r,{%s}}" % (name, ",".join(repr(parent) for parent in parents))
        for name, parents in declaration.items()
    ) + "}"
    closure = "{" + ",".join(f'[{name!r}]={version!r}' for name, version in CLOSURE.items()) + "}"
    settings = "{" + ",".join(
        f'[{name!r}]={str(value).lower() if isinstance(value, bool) else value}' for name, value in SETTINGS.items()
    ) + "}"
    lua.execute(f"CARGO_DECLARATION={mapping};CARGO_DECLARATION_ORDER={ordered};CARGO_CLOSURE={closure};CARGO_SETTINGS={settings}")
    lua.execute(WORLD)
    lua.globals().cargo_world(lua.globals().CARGO_DECLARATION)


def load(lua) -> None:
    lua.globals().cargo_load((FIXTURE / "control.lua").as_posix())
