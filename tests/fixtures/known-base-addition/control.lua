-- Successor-only observer using the existing ordinary-lab/save/cold marker
-- protocol. Never seed a successor level, queue, bonus, cost or game speed.
local FIXTURE, KEY = "mir-fixture-mir5-known-base-addition", "mir5_known_base_addition"
local CASE, SAVE = "known-base-addition-f200-2077", "mir5-native-complete"
local GEAR, PLASTIC = "recipe-prod-research_gears-1", "recipe-prod-research_plastic-1"
local FORCES = {"player", "mir5-migration-origin-f200-110-foreign", "mir5-migration-origin-f200-110-detached"}
local FAMILIES = {
  {"low_density_structure","low-density-structure"}, {"plastic","plastic-bar"},
  {"processing_unit","processing-unit"}, {"rocket_fuel","rocket-fuel"}, {"steel","steel-plate"},
}
local loaded, reported = false, false
local function fail(message) error("[mir5-known-base-addition] " .. message) end
local function close(a,b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<=.000001 end
local function equal(a,b,path)
  if type(a)~=type(b) then fail(path.." type differs") end
  if type(a)=="table" then
    for key,value in pairs(a)do equal(value,b[key],path.."."..tostring(key))end
    for key in pairs(b)do if a[key]==nil then fail(path.." has an unexpected field")end end
  elseif type(a)=="number" then if not close(a,b)then fail(path.." differs")end
  elseif a~=b then fail(path.." differs")end
end
local function technology(force,name)
  local value=force.technologies[name]
  if not value or value.valid==false or value.name~=name then fail("technology absent: "..name)end
  return value
end
local function bonus(force,name)
  local value=force.recipes[name]
  if not value or value.valid==false or type(value.productivity_bonus)~="number" then fail("recipe absent: "..name)end
  return value.productivity_bonus
end
local function forces()
  local out={}
  for _,name in ipairs(FORCES)do
    local force=game.forces[name]
    if not force or force.valid==false or force.name~=name then fail("source force absent: "..name)end
    out[#out+1]=force
  end
  return out
end
local function snapshot(force)
  local out={rows={},bonuses={},queue={},current=force.current_research and force.current_research.name or false,
    progress=force.research_progress,mining=force.mining_drill_productivity_bonus,
    battery=force.worker_robots_battery_modifier,cannon=force.get_ammo_damage_modifier("cannon-shell")}
  local function row(name)
    local t=technology(force,name)
    out.rows[name]={level=t.level,researched=t.researched,enabled=t.enabled,saved=t.saved_progress,
      hidden=t.prototype.hidden==true,visible=t.visible_when_disabled}
  end
  row(GEAR)
  for _,family in ipairs(FAMILIES)do
    row("recipe-prod-research_"..family[1].."-1")
    out.bonuses[family[2]]=bonus(force,family[2])
  end
  for _,recipe in ipairs({"plastic-bar","low-density-structure"})do
    out.bonuses["mir-known-base-unpaid-"..recipe]=bonus(force,"mir-known-base-unpaid-"..recipe)
  end
  out.bonuses["iron-gear-wheel"]=bonus(force,"iron-gear-wheel")
  for _,t in ipairs(force.research_queue or {})do out.queue[#out.queue+1]=t.name end
  return out
end
local function snapshots()
  local out={};for _,force in ipairs(forces())do out[force.name]=snapshot(force)end;return out
end
local function carriers(force,recipe,family,positive,negative)
  for direction,level in pairs({positive=positive,negative=negative})do
    local t=technology(force,"mir-native-credit-research_"..family.."-"..recipe.."-"..direction)
    if t.level~=level or t.researched or t.enabled or not t.prototype.hidden or t.visible_when_disabled
      or t.prototype.max_level~=4294967295 or #t.prototype.effects~=1 then fail("signed carrier differs: "..t.name)end
    local effect=t.prototype.effects[1]
    if effect.type~="change-recipe-productivity" or effect.recipe~=recipe
      or not close(effect.change,direction=="positive" and .1 or -.1)then fail("signed effect differs: "..t.name)end
  end
end
local function check_carriers(completed)
  for index,force in ipairs(forces())do
    carriers(force,"plastic-bar","plastic",completed and index==2 and 3 or 2,1)
    carriers(force,"mir-known-base-unpaid-plastic-bar","plastic",1,1)
    carriers(force,"low-density-structure","low_density_structure",1,1)
    carriers(force,"mir-known-base-unpaid-low-density-structure","low_density_structure",1,2)
  end
end
local function entry(event)
  if game.speed~=1 or script.active_mods.base~="2.0.77"
    or script.active_mods["more-infinite-research"]~="5.0.20012"
    or script.active_mods[FIXTURE]~="0.1.0" then fail("exact successor inputs or ordinary speed differ")end
  local changes=event and event.mod_changes
  local mir=changes and changes["more-infinite-research"]
  if event.mod_startup_settings_changed~=false or not mir or mir.old_version~="5.0.20001"
    or mir.new_version~="5.0.20012" then fail("genuine unchanged-settings old Base event absent")end
  for name,version in pairs(script.active_mods)do
    if name~="base" and name~="more-infinite-research" then
      if name~=FIXTURE and name~="mir-fixture-mir5-active-mods-observer" then fail("unexpected successor mod")end
      local change=changes[name]
      if not change or change.old_version~=nil or change.new_version~=version then fail("old helper/provider was already present")end
    end
  end
  for name,change in pairs(changes)do
    if name~="more-infinite-research" then
      if not script.active_mods[name] or change.new_version~=script.active_mods[name]
        or name=="base" and change.old_version~="2.0.77"
        or name~="base" and change.old_version~=nil then fail("removed/changed old provider or engine")end
    end
  end
  local all=forces()
  for index,force in ipairs(all)do
    local s=snapshot(force)
    for _,family in ipairs(FAMILIES)do
      local row=s.rows["recipe-prod-research_"..family[1].."-1"]
      if family[1]~="steel" and (row.level~=2 or row.researched or not close(s.bonuses[family[2]],.1))then fail("old paid family differs")end
    end
    local plastic=s.rows[PLASTIC]
    if not plastic.hidden or plastic.enabled then fail("plastic retirement differs")end
    if s.rows["recipe-prod-research_low_density_structure-1"].hidden then fail("public LDS became private")end
    for _,recipe in ipairs({"plastic-bar","low-density-structure"})do
      if not close(s.bonuses["mir-known-base-unpaid-"..recipe],0)then fail("new recipe acquired old earnings")end
    end
    if not close(s.mining,0) or not close(s.battery,.1) or not close(s.cannon,0)then fail("unrelated old native effects differ")end
    if index==2 then
      equal(s.queue,{GEAR,PLASTIC},"source queue")
      if s.current~=GEAR or not close(s.progress,.42)then fail("current42% changed")end
    elseif s.current~=false or #s.queue~=0 then fail("idle source force acquired research")end
    if index==3 and not close(s.rows[GEAR].saved,.27)then fail("detached27% changed")end
  end
  check_carriers(false)
  return snapshots()
end
local function marker(stage,state)
  log("[MIR5_NATIVE_FIXTURE] RESULT "..helpers.table_to_json({case=CASE,stage=stage,status="passed",
    qualification="exact-protected-source-native-runtime-only",ordinary_completions=state.completions,
    initial=state.initial,final=state.final,on_load_read_only=stage=="reload"}))
end
local function fill(state,research)
  for _,lab in ipairs(state.labs)do
    if not lab.valid then fail("ordinary lab disappeared")end
    local input=lab.get_inventory(defines.inventory.lab_input);input.clear()
    for _,ingredient in ipairs(research.research_unit_ingredients)do
      if input.insert{name=ingredient.name,count=100}~=100 then fail("science stock failed")end
    end
    lab.energy,lab.disabled_by_script=1000000000,false
  end
  state.stocked=research.name
end
local function start_labs(state)
  local surface=game.create_surface("mir-known-base-addition-labs",{width=64,height=64})
  surface.request_to_generate_chunks({0,0},1);surface.force_generate_chunk_requests()
  local tiles={}
  for y=-16,16 do for x=-16,16 do tiles[#tiles+1]={name="grass-1",position={x,y}}end end
  surface.set_tiles(tiles)
  state.labs={}
  for y=0,7 do for x=0,7 do
    local lab=surface.create_entity{name="lab",position={x*4-14,y*4-14},force=forces()[2]}
    if not lab or not lab.valid then fail("ordinary lab creation failed")end
    state.labs[#state.labs+1]=lab
  end end
  fill(state,technology(forces()[2],GEAR));state.phase="labs"
end
script.on_init(function()
  if storage[KEY]~=nil then fail("fixture was already in the source")end
  storage[KEY]={phase="await-configuration"}
end)
script.on_configuration_changed(function(event)
  local state=storage[KEY]
  if not state or state.phase~="await-configuration" then fail("unexpected configuration stage")end
  state.initial=entry(event);state.completions={};state.phase="ready";state.deadline=game.tick+36000
end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[KEY];local research=event.research
  if not state or state.phase~="labs" or research.force~=forces()[2]then return end
  local expected=#state.completions==0 and GEAR or PLASTIC
  if event.by_script==true or research.name~=expected then fail("completion was not the declared ordinary queue")end
  for _,ingredient in ipairs(research.research_unit_ingredients)do
    local count=0
    for _,lab in ipairs(state.labs)do count=count+lab.get_inventory(defines.inventory.lab_input).get_item_count(ingredient.name)end
    if count>=#state.labs*100 then fail("ordinary completion consumed no "..ingredient.name)end
  end
  state.completions[#state.completions+1]={name=research.name,tick=game.tick}
  if research.name==PLASTIC then
    for _,lab in ipairs(state.labs)do lab.disabled_by_script=true;lab.get_inventory(defines.inventory.lab_input).clear()end
    state.completed_tick=game.tick;state.phase="settle"
  end
end)
script.on_load(function() loaded,reported=true,false end)
script.on_event(defines.events.on_tick,function()
  local state=storage[KEY]
  if not state then return end
  if loaded then
    if state.phase~="completed" then fail("cold save is incomplete")end
    check_carriers(true)
    equal(snapshots(),state.final,"cold state")
    if not reported then marker("reload",state);reported=true end
    return
  end
  if state.phase=="completed" then return end
  if state.phase=="await-configuration" then fail("a genuine predecessor configuration event is required")end
  if game.speed~=1 then fail("ordinary game speed changed")end
  if game.tick>state.deadline then fail("queued ordinary labs exceeded deadline")end
  if state.phase=="ready" then start_labs(state)end
  if state.phase=="labs" then
    local research=forces()[2].current_research
    if not research or research.name~=GEAR and research.name~=PLASTIC then fail("ordinary queued research disappeared")end
    if state.stocked~=research.name then fill(state,research)end
    for _,lab in ipairs(state.labs)do lab.energy=1000000000 end
  elseif state.phase=="settle" and game.tick>state.completed_tick then
    local final=snapshots();local expected_all=table.deepcopy(state.initial)
    local expected=expected_all[FORCES[2]]
    -- Only these two real native completions may change the protected snapshot.
    expected.rows[GEAR].level=expected.rows[GEAR].level+1;expected.rows[GEAR].saved=0
    expected.rows[PLASTIC].level=expected.rows[PLASTIC].level+1;expected.rows[PLASTIC].saved=0
    expected.bonuses["iron-gear-wheel"]=expected.bonuses["iron-gear-wheel"]+.1
    expected.bonuses["plastic-bar"]=expected.bonuses["plastic-bar"]+.1
    expected.current,expected.queue,expected.progress=false,{},0
    equal(final,expected_all,"post-lab state");check_carriers(true)
    state.final, state.phase=final,"completed"
    marker("initial",state);game.server_save(SAVE)
  end
end)
