-- A fixed Base predecessor -> published11 preparation -> candidate15 chain.
-- Only this test mod's own state is read; MIR's private records stay opaque.
local P = {}
local KEY, FIXTURE = "worker_prepared_default_native_fixture", "mir-worker-storage-default-native"
local MAIN, OWNER, PRIVATE, HEAD = "worker-robots-storage-4", "mir-worker-storage-default-4",
  "mir-worker-storage-preservation-4", "mir-worker-storage-head-4"
local CURRENT, QUEUED, DETACHED = "mir-worker-default-native-current", "mir-worker-default-native-queued", "mir-worker-default-native-detached"
local LAB = "mir-worker-default-native-lab"
local ROLES = {"player", "mir-worker-default-queued", "mir-worker-default-detached", "mir-worker-default-unpaid"}
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}
local PREREQUISITES = {"worker-robots-storage-2", "worker-robots-storage-3", "automation-science-pack",
  "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}
local VERSIONS = {
  ["2.0.77"]={origin="4.7.20002", inherited="5.0.20011", successor="5.0.20015"},
  ["2.1.23"]={origin="4.7.21002", inherited="5.0.21011", successor="5.0.21015"},
  ["2.1.24"]={origin="4.7.21002", inherited="5.0.21011", successor="5.0.21015"},
}
local function check(value, reason) if not value then error("[worker-prepared-native] "..reason, 2) end end
local function copy(value)
  if type(value)~="table" then return value end
  local out={} for key,item in pairs(value)do out[key]=copy(item)end return out
end
local function price(level)return math.floor(675*1.5^(level-4))end
local function row(name, level, enabled, visible, saved)
  return {name=name,level=level,researched=false,enabled=enabled,visible=visible,saved=saved or 0,
    count=name==HEAD and 1 or price(level)}
end
function P.expected_inherited(before)
  local out=copy(before)
  for _,force in ipairs(out)do
    check(force.rows[PRIVATE]==nil and force.rows[OWNER]==nil and force.rows[HEAD]==nil,"origin must predate private/ordinary holders")
    force.rows[PRIVATE]=row(PRIVATE,4,false,false,0)
  end
  return out
end
function P.expected_prepared(before)
  local out=copy(before)
  for _,force in ipairs(out)do
    local source=force.rows[MAIN];check(source and not source.researched,"advanced native source required")
    local pending=source.saved>0 or force.current==MAIN and force.progress>0
    for _,id in ipairs(force.queue)do if id==MAIN then pending=true end end
    force.rows[PRIVATE]=row(PRIVATE,source.level,pending and source.enabled or false,source.visible,source.saved)
    source.level,source.researched,source.saved,source.count=4,false,0,675
    if force.current==MAIN then force.current=PRIVATE end
    for index,id in ipairs(force.queue)do if id==MAIN then force.queue[index]=PRIVATE end end
  end
  return out
end
function P.expected_completion(before,frame_ordinal,force_index)
  local out=copy(before);local force=out[frame_ordinal];local owner=force.rows[OWNER]
  check(force.index==force_index,"protected frame/force identity")
  check(force.current==OWNER and force.queue[1]==OWNER and not owner.researched,"ordinary current must be queued")
  owner.level,owner.saved,owner.count=owner.level+1,0,price(owner.level+1)
  force.rows[MAIN]=row(MAIN,5,false,true,0);force.rows[HEAD]=row(HEAD,5,false,false,0)
  force.bonus=force.bonus+1;table.remove(force.queue,1)
  force.current,force.progress=force.queue[1],0
  return out
end
function P.expected_bonus_after(before,force_index)
  local out=copy(before);local key=tostring(force_index)
  check(type(out[key])=="number","protected live force bonus required")
  out[key]=out[key]+1
  return out
end
function P.tuple(engine,version)
  local values=VERSIONS[engine];check(values,"exact supported engine")
  for _,stage in ipairs({"origin","inherited","successor"})do if values[stage]==version then return stage end end
  check(false,"exact predecessor/11/candidate15 version")
end
function P.event_transition(event,engine,old,new)
  local change=event.mod_changes and event.mod_changes["more-infinite-research"]
  check(change and change.old_version==old and change.new_version==new
    and type(event.mod_startup_settings_changed)=="boolean","exact historical version/settings event")
  for name,item in pairs(event.mod_changes)do
    local patch=name=="base"and engine=="2.1.24"and item.old_version=="2.1.23"and item.new_version=="2.1.24"
      and old=="5.0.21011"and new=="5.0.21015"
    check(name=="more-infinite-research"or item.old_version==item.new_version or patch,"unchanged other mods or exact declared engine patch hop")
  end
end
function P.bind(shared)
  local loaded=false
  local function selected()
    local setting=settings and settings.startup and settings.startup["worker-default-native-scenario"]
    check(setting and setting.value=="prepared-default","prepared actor requires prepared-default startup setting")
  end
  local function state()
    selected();local s=storage[KEY]
    check(not s or s.fixture_scenario=="prepared-default","prepared actor refuses legacy fixture state")
    return s
  end
  local function closure(stage)
    selected()
    local active=script.active_mods
    check(P.tuple(active.base,active["more-infinite-research"])==stage,"exact stage")
    check(active[FIXTURE]=="0.1.0" and game.speed==1 and game.difficulty_settings.technology_price_multiplier==1,"fixture/map/clock")
    local count=0
    for name in pairs(active)do check(name=="base"or name==FIXTURE or name=="more-infinite-research","three-mod Base closure");count=count+1 end
    check(count==3,"exact three mods")
  end
  local function contract(id, modifier)
    local p=prototypes.technology[id]
    check(p and p.name==id and p.level==4 and p.max_level==4294967295 and #p.effects==1
      and p.effects[1].type=="worker-robot-storage" and p.effects[1].modifier==modifier,"native contract "..id)
    check(prototypes.get_history("technology",id).created=="more-infinite-research","MIR custody "..id)
    if id==HEAD then
      check(p.hidden and p.enabled==false and p.visible_when_disabled==false and p.research_unit_count==1
        and p.research_unit_count_formula==nil and p.research_unit_energy==60 and p.ignore_tech_cost_multiplier
        and next(p.prerequisites)==nil and next(p.research_unit_ingredients)==nil,"head debit contract")
    else
      check(p.research_unit_count_formula=="675*1.5^(L-4)" and p.research_unit_energy==3600
        and not p.ignore_tech_cost_multiplier and #p.research_unit_ingredients==5,"full native worker price/science")
      check(p.hidden==(id==PRIVATE) and p.enabled==(id~=PRIVATE) and p.visible_when_disabled==false,
        "exact native prototype flags "..id)
      local actual,expected={},copy(PREREQUISITES)
      for key,item in pairs(p.prerequisites)do
        actual[#actual+1]=type(key)=="string"and key or type(item)=="string"and item or item.name
      end
      table.sort(actual);table.sort(expected);shared.same(expected,actual)
      for index,item in ipairs(p.research_unit_ingredients)do check(item.name==SCIENCE[index]and item.amount==1,"exact native science")end
    end
  end
  local function contracts(stage)
    contract(MAIN,1)
    if stage~="origin"then contract(PRIVATE,1)else check(prototypes.technology[PRIVATE]==nil,"old origin has no private holder")end
    if stage=="successor"then contract(OWNER,1);contract(HEAD,-1)
    else check(prototypes.technology[OWNER]==nil and prototypes.technology[HEAD]==nil,"old origin has no ordinary/debit holders")end
  end
  local function bonuses()
    local out={}for _,force in pairs(game.forces)do
      check(force.valid~=false and type(force.index)=="number","live force identity")
      out[tostring(force.index)]=force.worker_robots_storage_bonus
    end return out
  end
  local function labs()
    local out={}
    for role,lab in pairs(state().labs)do
      check(lab and lab.valid and lab.name==LAB and lab.force and lab.force.name==role
        and lab.prototype.get_researching_speed("normal")==3600,"owned native lab")
      check(lab.get_inventory(defines.inventory.lab_modules).is_empty(),"no lab modules")
      local amounts={}local input=lab.get_inventory(defines.inventory.lab_input)
      for _,pack in ipairs(SCIENCE)do amounts[pack]=input.get_item_count(pack)end
      out[role]={name=lab.name,unit=lab.unit_number,force={name=lab.force.name,index=lab.force.index},
        disabled=lab.disabled_by_script,inventory=amounts}
    end
    return out
  end
  local function stopped_labs(s,expected,reason)
    local actual=labs()
    for role,item in pairs(actual)do check(item.disabled==true,"stopped native lab differs "..role.."/"..reason)end
    if expected then shared.same(expected,actual)end
    return actual
  end
  local function emit(phase,extra)
    local s=state();local body={phase=phase,tick=game.tick,mods=script.active_mods,frames=shared.frames(),
      all_force_bonuses=bonuses(),labs=s and labs(),ordinary=s and s.ordinary,administrative=s and s.administrative,
      inserted=s and s.inserted,extra=extra}
    local text=helpers.table_to_json(body)
    helpers.write_file("worker-prepared-native/"..phase..".json",text.."\n",false)
    log("[MIR_WORKER_PREPARED_NATIVE phase="..phase.."]")
  end
  local function save(phase)
    local s=state();local stopped=stopped_labs(s,s.stopped_labs,phase.." save")
    if phase=="successor-saved"then shared.same(s.expected_bonuses,bonuses())end
    s.phase,s.closed,s.closed_labs,s.closed_bonuses=phase,shared.frames(),stopped,bonuses();s.stopped_labs=copy(stopped)
    emit(phase);check(game.is_multiplayer(),"owned server save")
    game.server_save("worker-prepared-"..phase)
  end
  local function setup()
    closure("origin");contracts("origin")
    local s={fixture_scenario="prepared-default",phase="setup",setting_up=true,labs={},inserted={},ordinary={},administrative={}};storage[KEY]=s
    for index,name in ipairs(ROLES)do
      local force=game.forces[name]or game.create_force(name);local main=force.technologies[MAIN]
      for _,prerequisite in pairs(main.prerequisites)do prerequisite.research_recursive()end
      check(main.level==4 and not main.researched and main.enabled and main.research_unit_count==675,"pristine historical unpaid4")
      if index<=3 then main.level=({8,7,6})[index]end
      if index==1 then force.research_queue={MAIN,MAIN,QUEUED};force.research_progress=.42
      elseif index==2 then force.research_queue={CURRENT,MAIN,QUEUED};force.research_progress=.125;main.saved_progress=.27
      elseif index==3 then force.research_queue={CURRENT};force.research_progress=.19;main.saved_progress=.23
      else force.research_queue={MAIN};force.research_progress=.37 end
      force.technologies[DETACHED].saved_progress=.27
      check(force.worker_robots_storage_bonus==3+main.level-4,"labelled historical scripted baseline")
      check(force.laboratory_speed_modifier==0 and force.laboratory_productivity_bonus==0,"unmodified native lab bonus")
    end
    local surface=game.surfaces[1];local tiles={}
    for x=-2,10 do for y=-2,2 do tiles[#tiles+1]={name="stone-path",position={x,y}}end end;surface.set_tiles(tiles)
    for index,name in ipairs({ROLES[1],ROLES[4]})do
      local lab=surface.create_entity{name=LAB,position={(index-1)*8,0},force=game.forces[name]}
      check(lab and lab.valid,"test lab creation");lab.disabled_by_script=true;s.labs[name]=lab;s.inserted[name]={}
    end
    s.setting_up=false;s.phase="origin-ready"
    emit("setup",{scripted_prerequisites=true,scripted_earned_levels=true,scripted_partial_work=true})
  end
  local function configure(event)
    local s=state();if not s then return end
    local version=script.active_mods["more-infinite-research"];local values=VERSIONS[script.active_mods.base]
    if s.phase=="origin-saved"then
      closure("inherited");contracts("inherited");P.event_transition(event,script.active_mods.base,values.origin,values.inherited)
      shared.same(P.expected_inherited(s.closed),shared.frames());shared.same(s.closed_bonuses,bonuses());shared.same(s.closed_labs,labs())
      s.phase="inherited-ready"
    elseif s.phase=="prepared-saved"then
      closure("successor");contracts("successor");P.event_transition(event,script.active_mods.base,values.inherited,values.successor)
      s.expected=shared.expected_upgrade(s.before_preparation)
      shared.same(s.expected,shared.frames());shared.same(s.closed_bonuses,bonuses());shared.same(s.closed_labs,labs())
      s.expected_bonuses=copy(s.closed_bonuses)
      s.phase="successor-ready"
    else check(false,"unexpected historical configuration phase/version "..tostring(version))end
    emit("configuration-observed",{event=event})
  end
  local function prepared()
    local s=state();check(s and s.phase=="inherited-saved","public prepare observation requires inherited save")
    closure("inherited");contracts("inherited")
    shared.same(P.expected_prepared(s.closed),shared.frames());shared.same(s.closed_bonuses,bonuses());shared.same(s.closed_labs,labs())
    s.before_preparation=copy(s.closed);s.phase="prepared-ready"
    emit("public-preparation-verified")
  end
  local function begin(mode)
    check(mode=="prepared","controller must call actual public recovery command before this observation")
    prepared()
  end
  local function start_work(index)
    local s=state();local role=index==1 and ROLES[1]or ROLES[4]
    local force=game.forces[role];check(force and force.valid,"live work force")
    local frame_ordinal=index==1 and 1 or 4
    local frame=shared.frames()[frame_ordinal]
    check(frame.index==force.index,"work frame/force index differs")
    s.stopped_labs=stopped_labs(s,s.stopped_labs or s.closed_labs,"before ordinary start")
    shared.same(s.expected_bonuses,bonuses())
    s.work,s.role,s.frame_ordinal,s.force_index=index,role,frame_ordinal,force.index
    check(frame.current==OWNER and frame.queue[1]==OWNER,"transferred native current research")
    check(frame.rows[OWNER].level==(index==1 and 8 or 4),"literal incoming worker level")
    check(math.ceil(frame.rows[OWNER].count*(1-frame.progress))==(index==1 and 1982 or 426),"independent remaining science oracle")
    s.labs[s.role].disabled_by_script=false;s.phase="research"
  end
  local function finish(event)
    local s=state();if not s then return end
    if event.by_script==true then
      check(s.setting_up or event.research.name==MAIN or event.research.name==OWNER or event.research.name==HEAD or event.research.name==PRIVATE,"labelled administrative callback")
      check(#s.administrative<512,"bounded administrative callbacks")
      s.administrative[#s.administrative+1]={name=event.research.name,force=event.research.force.name,tick=event.tick,by_script=true};return
    end
    check(s.phase=="research"and event.by_script==false and event.research.name==OWNER and event.research.force.name==s.role,"exact ordinary native completion")
    check(event.research.force.index==s.force_index,"ordinary completion force index differs")
    local frames=shared.frames();check(frames[s.frame_ordinal].index==s.force_index,"callback frame/force index differs")
    shared.assert_callback_safe(frames[s.frame_ordinal])
    s.callback_bonuses=P.expected_bonus_after(s.expected_bonuses,s.force_index)
    shared.same(s.callback_bonuses,bonuses())
    local before=labs()
    for role,item in pairs(before)do
      if role==s.role then check(item.disabled==false,"ordinary lab unexpectedly stopped")
      else shared.same(s.stopped_labs[role],item)end
    end
    s.ordinary[#s.ordinary+1]={name=OWNER,force=s.role,tick=event.tick,by_script=false}
    s.labs[s.role].disabled_by_script=true;s.stopped_labs=stopped_labs(s,nil,"ordinary completion intentional stop")
    s.phase="finish-ready";emit("ordinary-callback-"..tostring(#s.ordinary),{name=event.research.name,force=event.research.force.name,by_script=event.by_script})
  end
  local function cold()
    local s=state();local stage=s.phase=="origin-saved"and"origin"or s.phase=="successor-saved"and"successor"or"inherited"
    closure(stage);contracts(stage)
    shared.same(s.closed,shared.frames());stopped_labs(s,s.closed_labs,"cold");shared.same(s.closed_bonuses,bonuses())
    if stage=="successor"then shared.same(s.expected_bonuses,bonuses())end
    check(#s.ordinary==(stage=="successor"and 2 or 0),"cold cannot add completions")
    emit("cold")
  end
  local function tick()
    local s=state()
    if not s then loaded=false;setup();return end
    if loaded then loaded=false;if s.phase:match("%-saved$")then cold();return end end
    if s.phase=="origin-ready"then save("origin-saved")
    elseif s.phase=="inherited-ready"then save("inherited-saved")
    elseif s.phase=="prepared-ready"then save("prepared-saved")
    elseif s.phase=="successor-ready"then shared.same(s.expected,shared.frames());start_work(1);emit("upgrade-verified")
    elseif s.phase=="research"then
      local input=s.labs[s.role].get_inventory(defines.inventory.lab_input)
      for _,pack in ipairs(SCIENCE)do if input.get_item_count(pack)<64 then
        local n=input.insert{name=pack,count=200};check(n>0,"real native science supply")
        s.inserted[s.role][pack]=(s.inserted[s.role][pack]or 0)+n
      end end
    elseif s.phase=="finish-ready"then
      check(s.callback_bonuses,"ordinary callback bonus map missing")
      s.expected=P.expected_completion(s.expected,s.frame_ordinal,s.force_index);shared.same(s.expected,shared.frames())
      shared.same(s.callback_bonuses,bonuses());s.expected_bonuses=s.callback_bonuses;s.callback_bonuses=nil
      local inventory=labs()[s.role].inventory
      for _,pack in ipairs(SCIENCE)do check(s.inserted[s.role][pack]-inventory[pack]==(s.work==1 and 1982 or 426),"exact ordinary science depletion")end
      emit("ordinary-settled-"..s.work)
      if s.work==1 then start_work(2)else
        check(#s.ordinary==2,"two ordinary successor completions");shared.same(s.expected_bonuses,bonuses());save("successor-saved")
      end
    end
  end
  return {begin=begin,on_configuration_changed=configure,on_tick=tick,on_finished=finish,on_load=function()loaded=true end}
end
return P
