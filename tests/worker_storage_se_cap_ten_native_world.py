"""Strict Lua52-style world for the SE worker-storage cargo fixture.

This is a narrow host control world.  It models only the documented runtime
members consumed by the fixture and fails unknown reads/writes; it is not a
Factorio emulator or a substitute for the later five-process native case.
"""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "worker-storage-se-cap-ten-native"
TARGET = "worker-robots-storage-4"
PREDECESSOR = "worker-robots-storage-3"
TAIL = "mir-fixture-worker-storage-se-cap-ten-tail"
LAB = "se-space-science-lab"
POWER = "mir-fixture-worker-storage-se-cap-ten-power"
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
    """Read the fixture's literal setup declaration without evaluating Lua."""
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


def _lua_rows(declaration: dict[str, list[str]]) -> str:
    parts = []
    for name, parents in declaration.items():
        children = ",".join(f'"{parent}"' for parent in parents)
        parts.append(f'["{name}"]={{{children}}}')
    return "{" + ",".join(parts) + "}"


WORLD = r'''
local TARGET, PREDECESSOR, TAIL = "worker-robots-storage-4", "worker-robots-storage-3", "mir-fixture-worker-storage-se-cap-ten-tail"
local LAB, POWER = "se-space-science-lab", "mir-fixture-worker-storage-se-cap-ten-power"
local SCIENCE = {"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack","se-rocket-science-pack","se-material-science-pack-1","space-science-pack"}
local function copy(v) if type(v)~="table" then return v end local out={} for k,x in pairs(v) do out[k]=copy(x) end return out end
local function strict(values, reads, writes, label)
  return setmetatable({}, {__index=function(_, key) if reads[key] then return values[key] end error(label .. " unsupported read " .. tostring(key)) end,
    __newindex=function(_, key, value) if writes[key] then values[key]=value;return end error(label .. " unsupported write " .. tostring(key)) end})
end
local function tech(name, parents)
  local values={name=name,valid=true,level=1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
    prerequisites={},prototype={max_level=1,effects={}},research_unit_count=1,research_unit_energy=60,research_unit_ingredients={}}
  local writes={researched=true,enabled=true,visible_when_disabled=true,saved_progress=true}
  local row=strict(values,{name=true,valid=true,level=true,researched=true,enabled=true,visible_when_disabled=true,saved_progress=true,
    prerequisites=true,prototype=true,research_unit_count=true,research_unit_count_formula=true,research_unit_energy=true,research_unit_ingredients=true,force=true},writes,"LuaTechnology")
  return row, values
end
local function inventory()
  local counts={}
  local value={valid=true,get_item_count=function(name)return counts[name] or 0 end,
    insert=function(stack) assert(type(stack)=="table" and type(stack.name)=="string" and type(stack.count)=="number");if CARGO_FLAGS and CARGO_FLAGS.blocked_feed then return 0 end;counts[stack.name]=(counts[stack.name] or 0)+stack.count;return stack.count end}
  return strict(value,{valid=true,get_item_count=true,insert=true}, {},"LuaInventory"), counts
end
local function make_force(declaration)
  local technologies, backing={},{}
  for name, parents in pairs(declaration) do
    local row, values=tech(name, parents); technologies[name],backing[name]=row,values
  end
  local target, target_values=tech(TARGET, {PREDECESSOR}); technologies[TARGET],backing[TARGET]=target,target_values
  target_values.level=4;target_values.prototype.max_level=4294967295;target_values.prototype.effects={{type="worker-robot-storage",modifier=1}}
  target_values.research_unit_count_formula="675*1.5^(L-4)";target_values.research_unit_count=675;target_values.research_unit_energy=3600
  for index,name in ipairs(SCIENCE) do target_values.research_unit_ingredients[index]={name=name,amount=1} end
  local tail, tail_values=tech(TAIL, {});technologies[TAIL],backing[TAIL]=tail,tail_values
  for name, parents in pairs(declaration) do
    for _, parent in ipairs(parents) do backing[name].prerequisites[parent]=technologies[parent] end
  end
  target_values.prerequisites[PREDECESSOR]=technologies[PREDECESSOR]
  local values={name="player",index=1,valid=true,technologies=technologies,_queue={},_current=nil,_progress=0,
    laboratory_speed_modifier=0,worker_robots_storage_bonus=0}
  local force
  values.add_research=function(row)
    if type(row)=="string" then row=technologies[row] end
    if row~=target or values._current~=nil or backing[TARGET].level>=11 then return false end
    values._queue={row};values._current=row;values._progress=0;return true
  end
  force=setmetatable({}, {__index=function(_,key)
      if key=="research_queue" then return values._queue end
      if key=="current_research" then return values._current end
      if key=="research_progress" then return values._progress end
      if key=="add_research" then return values.add_research end
      if values[key]~=nil then return values[key] end
      error("LuaForce unsupported read "..tostring(key))
    end,__newindex=function(_,key,value)
      if key=="research_queue" then
        local queue={};for index,row in ipairs(value or {}) do queue[index]=row end
        values._queue=queue;values._current=queue[1];values._progress=0;return
      end
      if key=="research_progress" then assert(values._current~=nil,"progress without current");values._progress=value;return end
      if key=="laboratory_speed_modifier" then values[key]=value;return end
      error("LuaForce unsupported write "..tostring(key))
    end})
  for _, row in pairs(technologies) do backing[row.name].force=force end
  return force,backing,values
end
function cargo_world(declaration)
  callbacks,logs,interfaces,storage={}, {}, {}, {}
  local player, backing, force_values=make_force(declaration)
  local lab, power, lab_input, lab_counts; local flags={missing_power=false,blocked_feed=false}; local saves={}
  local surface={valid=true,create_entity=function(spec)
    assert(spec.force==player)
    if spec.name==POWER then if flags.missing_power then return nil end;power={valid=true,name=POWER,force=player};return power end
    assert(spec.name==LAB); lab_input,lab_counts=inventory(); lab={valid=true,name=LAB,unit_number=91,force=player,energy=0,electric_buffer_size=1000000,active=true,
      prototype={get_researching_speed=function()return 10 end},get_inventory=function(index)assert(index==1);return lab_input end};return lab
  end}
  local active=copy(CARGO_CLOSURE);active["more-infinite-research"]="4.7.20002";active["mir-fixture-mir5-worker-storage-se-cap-ten-native"]="0.1.0"
  local startup={};for name,value in pairs(CARGO_SETTINGS) do startup[name]={valid=true,value=value,default_value=0} end
  game={tick=0,forces={player=player,[1]=player},surfaces={[1]=surface},server_save=function(name)saves[#saves+1]=name end}
  script={active_mods=active,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,on_configuration_changed=function(fn)callbacks.configuration=fn end,on_event=function(id,fn)callbacks[id]=fn end}
  remote={add_interface=function(name, value)interfaces[name]=value end}
  settings={startup=startup};defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}}
  local env={game=game,script=script,remote=remote,settings=settings,defines=defines,storage=storage,log=function(text)logs[#logs+1]=text end}
  env._G=env;setmetatable(env,{__index=function(_,key)return _G[key]end})
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-worker-storage-se-cap-ten-native__/prerequisites",name)
    local rows,by_name={},{}
    for name, parents in pairs(declaration) do local row={name=name,parents=parents};rows[#rows+1]=row;by_name[name]=row end
    table.sort(rows,function(a,b)return a.name<b.name end)
    -- Preserve declaration order, not lexical order.
    rows={};for name, parents in ipairs(CARGO_DECLARATION_ORDER) do local row={name=parents[1],parents=parents[2]};rows[#rows+1]=row;by_name[row.name]=row end
    return {rows=rows,by_name=by_name}
  end
  CARGO_ENV=env;CARGO_CALLBACKS=callbacks;CARGO_LOGS=logs;CARGO_INTERFACES=interfaces;CARGO_FORCE_VALUES=force_values;CARGO_TECHNOLOGIES=force_values.technologies;CARGO_TECH_BACKING=backing;CARGO_FLAGS=flags;CARGO_SAVES=saves;CARGO_LAB_COUNTS=function()return copy(lab_counts or {})end
  return env
end
function cargo_load(path)
  local fn,message=loadfile(path,"t",CARGO_ENV);assert(fn,message);fn()
  assert(CARGO_CALLBACKS.init);CARGO_CALLBACKS.init()
end
function cargo_begin() return CARGO_INTERFACES["mir-fixture-mir5-worker-storage-se-cap-ten-native"].begin() end
function cargo_tick(count) for _=1,count do game.tick=game.tick+1;CARGO_CALLBACKS[1]() end end
function cargo_partial(progress) CARGO_FORCE_VALUES._progress=progress end
function cargo_complete(by_script,cursor)
  local target=CARGO_TECHNOLOGIES[TARGET];local target_values
  local level=target.level+1
  CARGO_SET_TARGET_LEVEL(level)
  CARGO_FORCE_VALUES.worker_robots_storage_bonus=level-4
  CARGO_FORCE_VALUES._progress=0
  if level==11 then CARGO_FORCE_VALUES._queue={};CARGO_FORCE_VALUES._current=nil end
  local event={research=target,by_script=by_script,tick=game.tick}
  if cursor~=nil then CARGO_SET_TARGET_LEVEL(cursor) end
  CARGO_CALLBACKS[2](event)
  if cursor~=nil then CARGO_SET_TARGET_LEVEL(level) end
end
function cargo_candidate(mir, mutate)
  script.active_mods["more-infinite-research"]=mir or "5.0.20018"
  if mutate then mutate(CARGO_TECHNOLOGIES[TARGET],CARGO_FORCE_VALUES) end
  CARGO_CALLBACKS.configuration({mod_startup_settings_changed=false,mod_changes={["more-infinite-research"]={old_version="4.7.20002",new_version=script.active_mods["more-infinite-research"]}}})
end
function cargo_cold()
  CARGO_CALLBACKS.load();game.tick=game.tick+1;CARGO_CALLBACKS[1]()
end
function cargo_logs()return CARGO_LOGS end
function cargo_counts()return CARGO_LAB_COUNTS() end
function cargo_saves()return CARGO_SAVES end
function cargo_phase()return storage["mir5_worker_storage_se_cap_ten_native"].phase end
function cargo_unsupported_force_write()game.forces.player.unapproved=true end
function cargo_missing_power()CARGO_FLAGS.missing_power=true end
function cargo_block_feed()CARGO_FLAGS.blocked_feed=true end
function cargo_setting(name,value) settings.startup[name].value=value end
function cargo_science(names)
  local values=CARGO_TECH_BACKING[TARGET];values.research_unit_ingredients={}
  for index,name in ipairs(names) do values.research_unit_ingredients[index]={name=name,amount=1} end
end
function cargo_lab_speed(value)
  local old=CARGO_ENV.game.surfaces[1].create_entity
  -- The host represents the documented prototype method through this flag.
  CARGO_FLAGS.lab_speed=value
  CARGO_ENV.game.surfaces[1].create_entity=function(spec)
    local entity=old(spec)
    if entity and entity.name==LAB then entity.prototype.get_researching_speed=function()return value end end
    return entity
  end
end
function cargo_drop_queue() CARGO_FORCE_VALUES._queue={};CARGO_FORCE_VALUES._current=nil end
function cargo_mutate_closed() CARGO_FORCE_VALUES.worker_robots_storage_bonus=999 end
'''


def install(lua) -> None:
    declaration = rows()
    mapping = "{" + ",".join(
        f'[\"{name}\"]={{{",".join(f"\"{parent}\"" for parent in parents)}}}'
        for name, parents in declaration.items()
    ) + "}"
    ordered = "{" + ",".join(
        "{\"%s\",{%s}}" % (name, ",".join(f'"{parent}"' for parent in parents))
        for name, parents in declaration.items()
    ) + "}"
    closure = "{" + ",".join(f'["{name}"]="{version}"' for name, version in CLOSURE.items()) + "}"
    settings = "{" + ",".join(
        f'["{name}"]={str(value).lower() if isinstance(value, bool) else value}' for name, value in SETTINGS.items()
    ) + "}"
    lua.execute(f"CARGO_DECLARATION={mapping};CARGO_DECLARATION_ORDER={ordered};CARGO_CLOSURE={closure};CARGO_SETTINGS={settings}")
    lua.execute(WORLD)
    # The strict wrapper deliberately hides level writes from fixture code;
    # this host-only closure models an engine completion before dispatch.
    lua.execute("""
      function CARGO_SET_TARGET_LEVEL(level)
        local row=CARGO_TECHNOLOGIES[\"worker-robots-storage-4\"]
        local values=getmetatable(row).__index
        -- The wrapper's backing fields are not public LuaTechnology members.
        -- Host installation owns this closure and accesses its captured value.
        CARGO_TARGET_BACKING.level=level
      end
    """)
    # Replace with a lexical setter captured by the world rather than making a
    # writable fixture field.  The assignment is passed through a dedicated
    # host-only global after cargo_world has initialized its technologies.
    lua.globals().cargo_world(lua.globals().CARGO_DECLARATION)
    # Derive the internal target backing table inside the world exactly once.
    lua.execute("CARGO_TARGET_BACKING=CARGO_TECH_BACKING[\"worker-robots-storage-4\"]")


def load(lua) -> None:
    lua.globals().cargo_load((FIXTURE / "control.lua").as_posix())
