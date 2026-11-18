"""Construct the host worlds used by worker-speed fixture controls.

Expected frames remain in the test cases. The builder installs the world and
returns its execution closures without importing a TestCase or Lua factory.
"""
from pathlib import Path


_WORLD = r'''
local caps = require("runtime.caps")
local KEY = "mir5_worker_speed_cap_ten"
local WORKER, PREDECESSOR = "worker-robots-speed-10", "worker-robots-speed-9"
local DEEP, PROBE, AUTOMATION, ELECTRICITY = "se-deep-space-science-pack-1", "automation", "automation-science-pack", "electricity"
local UNRELATED = "mir-fixture-unrelated-disabled"
local FIXTURE = "mir-fixture-mir5-worker-speed-cap-ten"
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "utility-science-pack", "space-science-pack", "se-rocket-science-pack",
  "se-energy-science-pack-4", "se-deep-space-science-pack-1"}
local closure = {
  base="2.0.77", ["space-exploration"]="0.7.57", ["aai-containers"]="0.3.2", ["aai-industry"]="0.6.16",
  ["alien-biomes"]="0.7.4", ["alien-biomes-graphics"]="0.7.1", jetpack="0.4.17", robot_attrition="0.6.6",
  ["shield-projector"]="0.2.2", ["space-exploration-graphics"]="0.7.5", ["space-exploration-graphics-2"]="0.7.2",
  ["space-exploration-graphics-3"]="0.7.2", ["space-exploration-graphics-4"]="0.7.2",
  ["space-exploration-graphics-5"]="0.7.3", ["space-exploration-menu-simulations"]="0.7.4",
  ["space-exploration-postprocess"]="0.7.5", informatron="0.4.0", ["aai-signal-transmission"]="0.5.3"
}
local stages = {
  source15={fixture="0.4.0",mir="5.0.20015",cap=0},
  ["old-negative15"]={fixture="0.5.0",mir="5.0.20015",cap=10},
  successor16={fixture="0.6.0",mir="5.0.20016",cap=10},
  ["current-old15"]={fixture="0.7.0",mir="5.0.20015",cap=10},
  ["current-successor16"]={fixture="0.8.0",mir="5.0.20016",cap=10},
  ["current-observe16"]={fixture="0.9.0",mir="5.0.20016",cap=10},
  ["current-successor17"]={fixture="0.12.0",mir="5.0.20017",cap=10},
  ["source-producer15"]={fixture="0.13.0",mir="5.0.20015",cap=0}
}
local function copy(v) if type(v)~="table" then return v end local o={} for k,x in pairs(v)do o[k]=copy(x)end return o end
local function packs() local r={} for _,n in ipairs(PACKS)do r[#r+1]={n,1}end return r end
local function runtime_packs() local r={} for _,n in ipairs(PACKS)do r[#r+1]={name=n,amount=1}end return r end

function data_case(settings_wrapper,data_wrapper,settings_common,data_common,stage,opponent)
  local expected=assert(stages[stage]);local cap=expected.cap;if opponent=="wrong-cap"then cap=cap==0 and 10 or 0 end
  local unit={count_formula=opponent=="wrong-formula" and "2^(L-6)*1000" or "0.2*(2^(L-6)*1000)",time=60,ingredients=packs()}
  local worker={name=WORKER,max_level="infinite",prerequisites={PREDECESSOR,DEEP},unit=unit,
    effects={{type="worker-robot-speed",modifier=opponent=="wrong-effect" and .6 or .65}}}
  local raw={technology={[WORKER]=worker},lab={lab={name="lab",inputs={"automation-science-pack"}}},
    ["int-setting"]={["mir-max-level-worker-robots-speed"]={default_value=0,minimum_value=0}}}
  local rows, logs = {}, {}
  local env={mods=copy(closure),data={raw=raw,extend=function(_,v)for _,x in ipairs(v)do rows[#rows+1]=x end end},
    settings={startup={["mir-max-level-worker-robots-speed"]={value=cap}}},log=function(row)logs[#logs+1]=row end}
  env.mods[FIXTURE],env.mods["more-infinite-research"]=expected.fixture,expected.mir
  if opponent=="stale-mir17"then env.mods["more-infinite-research"]="5.0.20016"end
  local tables={}for k,v in pairs(table)do tables[k]=v end;tables.deepcopy=copy;env.table=tables
  env.require=function(n)if n=="__mir-fixture-mir5-worker-speed-cap-ten__/fixture_settings"then return assert(loadfile(settings_common,"t",env))()end
    assert(n=="__mir-fixture-mir5-worker-speed-cap-ten__/fixture_data_final");return assert(loadfile(data_common,"t",env))()end
  env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end})
  local ok,msg=pcall(assert(loadfile(settings_wrapper,"t",env)));if not ok then return{ok=false,message=tostring(msg),raw=raw,rows=rows,logs=logs,mods=env.mods}end
  ok,msg=pcall(assert(loadfile(data_wrapper,"t",env)));return{ok=ok,message=tostring(msg),raw=raw,rows=rows,logs=logs,mods=env.mods}
end

local function tech(name,force,wrong_energy)
  local t={name=name,valid=true,force=force,level=name==PREDECESSOR and 9 or 1,researched=false,enabled=true,visible_when_disabled=false,saved_progress=0,
    prototype={max_level=4294967295,effects=name==WORKER and {{type="worker-robot-speed",modifier=.65}} or {}},
    prerequisites={},research_unit_count=3200,research_unit_energy=wrong_energy and 60 or 3600,research_unit_ingredients=runtime_packs()}
  if name==WORKER then t.prerequisites[PREDECESSOR]={name=PREDECESSOR};t.prerequisites[DEEP]={name=DEEP}end;return t
end
local function force(name,index,wrong_energy)
  local f={name=name,index=index,valid=true,technologies={},_queue={},current_research=nil,research_progress=0,worker_robots_speed_modifier=0}
  for _,n in ipairs({WORKER,PROBE,AUTOMATION,PREDECESSOR,DEEP,ELECTRICITY,UNRELATED,"stone-wall"})do f.technologies[n]=tech(n,f,wrong_energy)end
  f.technologies[UNRELATED].enabled,f.technologies[UNRELATED].researched=false,false
  f.technologies["stone-wall"].enabled,f.technologies["stone-wall"].researched=false,false
  function f.enable_all_prototypes()error("broad prototype enablement is forbidden by this fixture")end
  function f.reset_technology_effects()
    f.worker_robots_speed_modifier=f._reset_bonus or (f.technologies[WORKER].level-1)*.65
    if f._external_reset then f._external_reset(f) end
    if f._reset_dispatch then f._reset_dispatch(f) end
  end
  function f.add_research(r)
    if type(r)=="string"then r=f.technologies[r]end;if not r or r.enabled~=true or f.current_research then return false end
    if r.name==WORKER and(f.technologies[PREDECESSOR].researched~=true or f.technologies[DEEP].researched~=true)then return false end
    if r.name==PROBE and (f.technologies[AUTOMATION].researched~=true or f.technologies[ELECTRICITY].researched~=true) then return false end;f.research_queue={r};return true
  end
  return setmetatable(f,{__index=function(s,k)if k=="research_queue"then return rawget(s,"_queue")end end,
    __newindex=function(s,k,v)if k~="research_queue"then rawset(s,k,v)return end;rawset(s,"_queue",v);rawset(s,"current_research",v[1]);rawset(s,"research_progress",v[1]and 0 or 0)end})
end
local function inventory()
  local x={items={},capacity=200};function x.insert(r)local n=math.min(r.count,math.max(0,x.capacity-(x.items[r.name]or 0)));x.items[r.name]=(x.items[r.name]or 0)+n;return n end
  function x.get_item_count(n)return x.items[n]or 0 end;return x
end
local function load_stage(path,common,stage,game,storage,settings,markers,logs,files)
  local e,s,active = {events={}},assert(stages[stage]),copy(closure);active[FIXTURE],active["more-infinite-research"]=s.fixture,s.mir
  local env={game=game,storage=storage,settings=settings,script={active_mods=active,on_init=function(f)e.init=f end,
      on_configuration_changed=function(f)e.changed=f end,on_load=function(f)e.load=f end,on_event=function(k,f)e.events[k]=f end},
    defines={events={on_tick=1,on_research_finished=2,on_research_started=3,on_technology_effects_reset=4,on_research_cancelled=5,on_research_reversed=6},inventory={lab_input=1}},
    helpers={table_to_json=function(row)markers[#markers+1]=row;return '{"fixture":"host"}'end,
      write_file=function(p,b,a)files[#files+1]={path=p,body=b,append=a}end},log=function(x)logs[#logs+1]=x end}
  env.require=function(n)assert(n=="__mir-fixture-mir5-worker-speed-cap-ten__/fixture_control");return assert(loadfile(common,"t",env))()end
  env._G=env;setmetatable(env,{__index=function(_,k)return _G[k]end});local ok,msg=pcall(assert(loadfile(path,"t",env)));return ok and e or nil,tostring(msg)
end
local function call(f,e)if type(f)~="function"then return false,"missing callback"end;local ok,msg=pcall(f,e);return ok,tostring(msg)end
-- Factorio advances an infinite technology before the ordinary completion event.
-- Both flows share this engine sequence; effect/science/queue oracles stay local.
local function finish_infinite_level(technology,completed_level,callback,tick)
  assert(technology.level==completed_level,"ordinary research must finish its current level")
  technology.level=completed_level+1
  return call(callback,{research=technology,by_script=false,tick=tick})
end

function flow(source_path,old_path,successor_path,common,mode,opponent)
  local wrong=opponent=="wrong-runtime-energy";local player=force("player",1,wrong);local game={tick=0,forces={player=player,[1]=player},surfaces={}}
  function game.create_force(n)local x=force(n,#game.forces+1,wrong);game.forces[n],game.forces[x.index]=x,x;return x end
  local saves,labs=0,0;game.surfaces[1]={create_entity=function(row)labs=labs+1;local x={valid=true,disabled_by_script=false,unit_number=labs,input=inventory()};function x.get_inventory(i)assert(i==1)return x.input end;game.lab=x;return x end}
  function game.server_save(n)assert(n=="mir5-worker-speed-cap-ten-complete");saves=saves+1 end
  local storage,markers,logs,files={mir_caps={}}, {},{},{};local function settings(cap)return{startup={["mir-max-level-worker-robots-speed"]={value=cap},["mir-settings-profile-import"]={value=""}}}end
  local source,msg=load_stage(source_path,common,"source15",game,storage,settings(0),markers,logs,files);if not source then return{ok=false,message=msg}end
  local ok,result
  if opponent=="preinit-unrelated"then ok,result=call(source.events[2],{research={name="se-always-researched",force=player},by_script=true,tick=0});return{ok=ok,message=result,state=storage[KEY],markers=markers}end
  ok,result=call(source.init);if not ok then return{ok=false,message=result}end
  if opponent=="source-tick"then ok,result=call(source.events[1]);return{ok=ok,message=result}end
  if opponent=="source-worker"then ok,result=call(source.events[2],{research=player.technologies[WORKER],by_script=false,tick=0});return{ok=ok,message=result,state=storage[KEY]}end
  if opponent=="source-admin"or opponent=="source-admin-electricity"then
    local prerequisite=opponent=="source-admin" and PREDECESSOR or ELECTRICITY
    ok,result=call(source.events[2],{research=player.technologies[prerequisite],by_script=true,tick=0});return{ok=ok,message=result,state=storage[KEY]}
  end
  local state=storage[KEY];if not state then return{ok=false,message="source state absent"}end
  if opponent=="missing-electricity"then
    local foreign=game.forces[state.foreign_index];foreign.technologies[ELECTRICITY].researched=false
    local accepted=foreign.add_research(foreign.technologies[PROBE])
    return{ok=accepted==true,message=accepted and "foreign automation unexpectedly queued" or "foreign automation electricity prerequisite is absent"}
  end
  if mode=="old-negative"then local old,oldmsg=load_stage(old_path,common,"old-negative15",game,storage,settings(10),markers,logs,files);if not old then return{ok=false,message=oldmsg}end
    ok,result=call(old.changed);return{ok=ok,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}end
  if opponent=="missing-predecessor"then player.technologies[PREDECESSOR].researched=false end;if opponent=="missing-deep"then player.technologies[DEEP].researched=false end
  if opponent~="skip-caps"then for _,f in ipairs({player,game.forces[state.foreign_index],game.forces[state.earned_index]})do caps.reconcile(f,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})end end
  if opponent=="partial-drift"then player.research_progress=.26 end;if opponent=="foreign-reenabled"then game.forces[state.foreign_index].technologies[WORKER].enabled=true end
  local successor,smsg=load_stage(successor_path,common,"successor16",game,storage,settings(10),markers,logs,files);if not successor then return{ok=false,message=smsg}end
  ok,result=call(successor.changed);if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs}end
  local owner=player.technologies[WORKER]
  if opponent=="await-eleven"then owner.level=11;ok,result=call(successor.events[3],{research=owner,tick=0});return{ok=ok,message=result}end
  game.tick=1;ok,result=call(successor.events[1]);if not ok then return{ok=false,message=result}end
  if opponent=="scripted-finish"then owner.level=11;ok,result=call(successor.events[2],{research=owner,by_script=true,tick=1});return{ok=ok,message=result}end
  if opponent=="preincrement-finish"then owner.level=10;ok,result=call(successor.events[2],{research=owner,by_script=false,tick=1});return{ok=ok,message=result}end
  player.research_queue={};ok,result=finish_infinite_level(owner,10,successor.events[2],1);if not ok then return{ok=false,message=result}end
  player.worker_robots_speed_modifier=state.player_bonus_before+.65;for n in pairs(state.lab_feed)do game.lab.input.items[n]=50 end;caps.reconcile(player,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})
  if opponent=="after-eleven"then ok,result=call(successor.events[3],{research=owner,tick=1});return{ok=ok,message=result}end
  for _=1,3 do game.tick=game.tick+1;ok,result=call(successor.events[1]);if not ok then return{ok=false,message=result}end end
  for _=1,2 do local cold,cmsg=load_stage(successor_path,common,"successor16",game,storage,settings(10),markers,logs,files);if not cold then return{ok=false,message=cmsg}end;ok,result=call(cold.load);if not ok then return{ok=false,message=result}end;game.tick=game.tick+1;ok,result=call(cold.events[1]);if not ok then return{ok=false,message=result}end end
  return{ok=true,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage[KEY],player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}
end

function current_state_flow(old_path,successor_path,successor17_path,observe_path,common,mode,opponent)
  local player,foreign,earned=force("player",1,false),force("mir5-worker-speed-cap-ten-foreign",2,false),force("mir5-worker-speed-cap-ten-earned",3,false)
  for _,value in ipairs({player,foreign,earned})do value.technologies["stone-wall"].enabled=true end
  local game={tick=0,forces={player=player,[1]=player,[foreign.name]=foreign,[foreign.index]=foreign,[earned.name]=earned,[earned.index]=earned},surfaces={}}
  local saves,labs=0,0;game.surfaces[1]={create_entity=function(row)labs=labs+1;local x={valid=true,disabled_by_script=false,unit_number=labs,input=inventory()};function x.get_inventory(i)assert(i==1)return x.input end;game.lab=x;return x end}
  function game.server_save(n)assert(n=="mir5-worker-speed-cap-current-state-complete");saves=saves+1 end
  local storage,markers,logs,files={mir_caps={}}, {},{},{};local function settings()return{startup={["mir-max-level-worker-robots-speed"]={value=10},["mir-settings-profile-import"]={value=""}}}end
  local stage,path
  if mode=="old"then stage,path="current-old15",old_path
  elseif mode=="observe"then stage,path="current-observe16",observe_path
  elseif mode=="candidate17"then stage,path="current-successor17",successor17_path
  else stage,path="current-successor16",successor_path end
  local actor,message=load_stage(path,common,stage,game,storage,settings(),markers,logs,files);if not actor then return{ok=false,message=message}end
  local function install_reset(force)
    force._external_reset=function(value)
      if (mode=="candidate" or mode=="candidate17") and opponent~="candidate-no-cap" then caps.reconcile(value,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})end
    end
    force._reset_dispatch=function(value)
      if opponent=="missing-reset-event" then return end
      local callback=actor.events[4];if callback then callback({force=value})end
    end
  end
  install_reset(player)
  install_reset(foreign);install_reset(earned)
  function game.create_force()error("current-state role must use the three named input forces")end
  if opponent=="missing-prerequisite"then player.technologies[PREDECESSOR]=nil end
  local ok,result=call(actor.changed)
  if mode=="old"then return{ok=ok,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage.mir5_worker_speed_cap_current_state,player=player,foreign=foreign,earned=earned}end
  if mode=="observe"then
    local state=storage.mir5_worker_speed_cap_current_observe
    if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,player=player,foreign=foreign,earned=earned}end
    local owner=player.technologies[WORKER]
    if opponent=="observe-event-overflow"then
      for _=1,129 do ok,result=call(actor.events[3],{research=owner,by_script=false,tick=0});if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state}end end
    else
      for _,row in ipairs({
        {3,{research=owner,by_script=false,tick=0}}, {5,{research=owner,by_script=true,tick=0}},
        {2,{research=owner,by_script=false,tick=0}}, {6,{research=owner,by_script=false,tick=0}},
        {4,{force=foreign,tick=0}},
      })do ok,result=call(actor.events[row[1]],row[2]);if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state}end end
    end
    game.tick=1;ok,result=call(actor.events[1]);return{ok=ok,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,player=player,foreign=foreign,earned=earned}
  end
  if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage.mir5_worker_speed_cap_current_state,player=player,foreign=foreign,earned=earned}end
  local state=storage.mir5_worker_speed_cap_current_state;local owner=player.technologies[WORKER]
  if opponent=="fourth-reset"then player.reset_technology_effects();ok,result=call(actor.events[1]);return{ok=ok,message=result,state=state,markers=markers}end
  if opponent=="await-eleven"then owner.level=11;ok,result=call(actor.events[3],{research=owner,tick=0});return{ok=ok,message=result,state=state}end
  if opponent=="post-boundary-admin-write"then player.technologies[PREDECESSOR].researched=false end
  if opponent=="post-boundary-sentinel-write"then player.technologies["stone-wall"].enabled=true end
  if opponent=="post-boundary-bonus-drift"then player.worker_robots_speed_modifier=player.worker_robots_speed_modifier+.1 end
  game.tick=1;ok,result=call(actor.events[1]);if not ok then return{ok=false,message=result,state=state}end
  if opponent=="scripted-finish"then owner.level=11;ok,result=call(actor.events[2],{research=owner,by_script=true,tick=1});return{ok=ok,message=result,state=state}end
  if opponent=="preincrement-finish"then owner.level=10;ok,result=call(actor.events[2],{research=owner,by_script=false,tick=1});return{ok=ok,message=result,state=state}end
  player.research_queue={};ok,result=finish_infinite_level(owner,10,actor.events[2],1);if not ok then return{ok=false,message=result,state=state}end
  if opponent=="missing-ordinary-event"then state.ordinary_events={} end
  player.worker_robots_speed_modifier=state.current_player_bonus_before+.65;for n in pairs(state.lab_feed)do game.lab.input.items[n]=50 end;caps.reconcile(player,{[WORKER]=10},storage.mir_caps,{[WORKER]=true})
  if opponent=="after-eleven"then ok,result=call(actor.events[3],{research=owner,tick=1});return{ok=ok,message=result,state=state}end
  for _=1,3 do game.tick=game.tick+1;ok,result=call(actor.events[1]);if not ok then return{ok=false,message=result,state=state}end end
  for _=1,2 do local cold,cmsg=load_stage(path,common,stage,game,storage,settings(),markers,logs,files);if not cold then return{ok=false,message=cmsg}end;ok,result=call(cold.load);if not ok then return{ok=false,message=result}end;game.tick=game.tick+1;ok,result=call(cold.events[1]);if not ok then return{ok=false,message=result}end end
  return{ok=true,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,player=player,foreign=game.forces[state.foreign_index],earned=game.forces[state.earned_index]}
end

function source_producer_flow(path,common,cold)
  local player=force("player",1,false);player._reset_bonus=.65
  -- The exact published15/SE native trace restores the enabled gate during
  -- reset_technology_effects (including its callbacks). Model that observed
  -- profile outcome here; the producer must seed its intended gates last.
  local function source_reset_gate(value) value.technologies[WORKER].enabled=true end
  player._external_reset=source_reset_gate
  local game={tick=0,forces={player=player,[1]=player},surfaces={}}
  function game.create_force(name)
    local value=force(name,#game.forces+1,false)
    value._reset_bonus=name=="mir5-worker-speed-cap-ten-foreign" and 1.3 or 2.6
    value._external_reset=source_reset_gate
    game.forces[name],game.forces[value.index]=value,value
    return value
  end
  local saves,labs=0,0
  function game.server_save() saves=saves+1 end
  local storage,markers,logs,files={mir_caps={}}, {},{},{}
  local function settings()return{startup={
    ["mir-max-level-worker-robots-speed"]={value=0},["mir-settings-profile-import"]={value=""}}}end
  local actor,message=load_stage(path,common,"source-producer15",game,storage,settings(),markers,logs,files)
  if not actor then return{ok=false,message=message}end
  local ok,result=call(actor.init)
  if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage[KEY]}end
  if cold then
    local observed,observed_message=load_stage(path,common,"source-producer15",game,storage,settings(),markers,logs,files)
    if not observed then return{ok=false,message=observed_message,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage[KEY]}end
    ok,result=call(observed.load);if not ok then return{ok=false,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=storage[KEY]}end
    game.tick=game.tick+1;ok,result=call(observed.events[1])
  end
  local state=storage[KEY]
  return{ok=ok,message=result,markers=markers,logs=logs,files=files,saves=saves,labs=labs,state=state,
    player=player,foreign=game.forces[state and state.foreign_index],earned=game.forces[state and state.earned_index]}
end
'''


def build_worker_speed_world(lua, lua_root: Path):
    lua.execute(f'package.path = "{lua_root.as_posix()}/?.lua;" .. package.path')
    lua.execute(_WORLD)
    return {
        "data_case": lua.eval("data_case"),
        "flow": lua.eval("flow"),
        "current_state_flow": lua.eval("current_state_flow"),
        "source_producer_flow": lua.eval("source_producer_flow"),
    }
