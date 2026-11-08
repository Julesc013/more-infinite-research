-- Disposable native state fixture, not a lab/GUI/performance acceptance case.
-- Seed only published source creation; successor and cold checks never reseed
-- research, reset effects, replace a queue or repair a captured expectation.
local C = require("contract")
local KEY, SAVE = "mir5_sif_retained_manufacturing", "mir5-native-complete"
local FOREIGN_FORCE, FRESH_FORCE = "mir5-sif-retained-foreign", "mir5-sif-retained-fresh"
local loaded, reported = false, false
local function fail(message) error("[mir5-sif-retained] " .. message) end
local function id(row) return "recipe-prod-research_" .. row.key .. "-1" end
local function close(a, b)
  return type(a)=="number" and type(b)=="number" and a==a and b==b and math.abs(a-b)<=.000001
end
local function same(a, b, path)
  if type(a) ~= type(b) then fail(path .. " type differs") end
  if type(a)=="number" then if not close(a,b) then fail(path .. " differs") end
  elseif type(a)=="table" then
    for key, value in pairs(a) do same(value,b[key],path .. "." .. tostring(key)) end
    for key in pairs(b) do if a[key]==nil then fail(path .. " unexpected " .. tostring(key)) end end
  elseif a~=b then fail(path .. " differs") end
end
local function stage()
  local version = script.active_mods[C.fixture]
  local role, mir
  if version=="0.1.0" then
    role,mir="published-source",C.source
  elseif version=="0.2.0" then
    role,mir="successor",C.successor
  elseif version=="0.4.0" then
    role,mir="entry-successor",C.successor
  elseif version==C.current_fixture then
    if script.active_mods["more-infinite-research"]==C.source then
      role,mir="current-source",C.source
    elseif script.active_mods["more-infinite-research"]==C.current_successor then
      role,mir="current-entry-successor",C.current_successor
    else
      fail("current fixture MIR version differs")
    end
  else
    fail("fixture version differs")
  end
  local expected = {base="2.0.77",["elevated-rails"]="2.0.77",quality="2.0.77",
    ["space-age"]="2.0.77",["space-is-fake"]="1.0.60",["cr-commons"]="1.0.27",
    [C.fixture]=version,["more-infinite-research"]=mir,
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
  for name, value in pairs(expected) do
    if script.active_mods[name]~=value then fail("exact closure differs: " .. name) end
  end
  for name in pairs(script.active_mods) do if expected[name]==nil then fail("unexpected mod: " .. name) end end
  return role
end
local function source_stage(role)
  return role=="published-source" or role=="current-source"
end
local function entry_boundary_mode(role)
  role=role or stage()
  return role=="entry-successor" or role=="current-entry-successor"
end
local function require_early_order(order)
  if type(order)~="string" then fail("entry boundary event order absent") end
  local names, seen, fixture_index, mir_index = {}, {}, nil, nil
  -- Exact2.0.77 returns the observed 'level -> mod -> mod' string. Refuse
  -- ambiguous/missing tokens rather than infer order from metadata or names.
  for name in (order .. " -> "):gmatch("(.-) %-> ") do
    if name=="" or seen[name] or (name~="level" and script.active_mods[name]==nil) then
      fail("entry boundary event order invalid")
    end
    names[#names+1],seen[name]=name,true
    if name==C.fixture then fixture_index=#names end
    if name=="more-infinite-research" then mir_index=#names end
  end
  if table.concat(names," -> ")~=order or not fixture_index or not mir_index or fixture_index>=mir_index then
    fail("entry boundary must precede MIR configuration")
  end
end
local function require_current_entry_event(event)
  if type(event)~="table" or event.mod_startup_settings_changed~=false then
    fail("current entry requires unchanged startup settings")
  end
  local changes=event.mod_changes
  local mir=type(changes)=="table" and changes["more-infinite-research"] or nil
  if type(mir)~="table" or mir.old_version~=C.source or mir.new_version~=C.current_successor then
    fail("current entry requires exact MIR transition")
  end
  for name,change in pairs(changes) do
    if name~="more-infinite-research" and (type(change)~="table" or change.old_version~=change.new_version) then
      fail("current entry requires MIR-only version change")
    end
  end
  return {mir_old_version=mir.old_version,mir_new_version=mir.new_version,
    mod_startup_settings_changed=event.mod_startup_settings_changed}
end
local function clone(value)
  if type(value)~="table" then return value end
  local out={};for key,item in pairs(value) do out[key]=clone(item) end;return out
end
local function expected_snapshots(state)
  if not entry_boundary_mode() then return state.player,state.foreign end
  local baseline=state.entry_boundary
  if type(baseline)~="table" or type(baseline.player_processing_enabled)~="boolean"
      or type(baseline.foreign_mining_enabled)~="boolean" then fail("fixed entry boundary absent") end
  require_early_order(baseline.event_order)
  local player,foreign=clone(state.player),clone(state.foreign)
  -- Only the two independently demonstrated fields use the fixed pre-MIR
  -- observation. Source witnesses and every other expectation stay unchanged.
  player.technologies[id(C.rows[3])].enabled=baseline.player_processing_enabled
  foreign.foreign.enabled=baseline.foreign_mining_enabled
  return player,foreign
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value or value.valid==false or value.name~=name then fail("missing technology " .. name) end
  return value
end
local function status(value)
  return {level=value.level,researched=value.researched,enabled=value.enabled,saved_progress=value.saved_progress}
end
local function assert_rows(force)
  for _, row in ipairs(C.rows) do
    local value = technology(force,id(row))
    if value.prototype.hidden~=true then fail("retained row is visible: " .. id(row)) end
    if value.prototype.max_level~=4294967295 and value.prototype.max_level~="infinite" then
      fail("retained row is not infinite: " .. id(row))
    end
    local expected, seen, count = {}, {}, 0
    for _, name in ipairs(row.recipes) do expected[name]=true end
    for _, effect in pairs(value.prototype.effects or {}) do
      count=count+1
      if effect.type~="change-recipe-productivity" or not expected[effect.recipe]
          or seen[effect.recipe] or not close(effect.change,.1) then fail("effect vector differs: " .. id(row)) end
      seen[effect.recipe]=true
    end
    if count~=#row.recipes then fail("effect count differs: " .. id(row)) end
    for name in pairs(expected) do if not seen[name] then fail("missing recipe effect: " .. name) end end
  end
end
local function snapshot(force)
  assert_rows(force)
  local out = {technologies={},bonuses={},queue={},current=force.current_research and force.current_research.name or false,
    progress=force.research_progress,
    mining=force.mining_drill_productivity_bonus,lab=force.laboratory_speed_modifier}
  for _, row in ipairs(C.rows) do
    out.technologies[id(row)]=status(technology(force,id(row)))
    for _, name in ipairs(row.recipes) do
      local recipe=force.recipes[name]
      if not recipe or type(recipe.productivity_bonus)~="number" then fail("missing native recipe bonus: " .. name) end
      out.bonuses[name]=recipe.productivity_bonus
    end
  end
  out.foreign=status(technology(force,C.foreign))
  for _, value in ipairs(force.research_queue or {}) do out.queue[#out.queue+1]=value.name end
  return out
end
-- Capture the same finite prototype fields that assert_rows independently
-- checks against the published contract. This is fixture-owned data only.
local function prototype_snapshot(force)
  assert_rows(force)
  local out={}
  for _,row in ipairs(C.rows) do
    local prototype=technology(force,id(row)).prototype
    local effects={}
    for _,effect in pairs(prototype.effects or {}) do
      effects[effect.recipe]={type=effect.type,recipe=effect.recipe,change=effect.change}
    end
    out[id(row)]={hidden=prototype.hidden,max_level=prototype.max_level,effects=effects}
  end
  return out
end
local function zero_manufacturing(force)
  assert_rows(force)
  for _, row in ipairs(C.rows) do
    local value=technology(force,id(row))
    if value.level~=1 or value.researched or not close(value.saved_progress,0) then fail("fresh paid state: " .. id(row)) end
    for _, name in ipairs(row.recipes) do
      if not force.recipes[name] or not close(force.recipes[name].productivity_bonus,0) then fail("fresh reward: " .. name) end
    end
  end
end
local function verify(state, successor)
  if type(state)~="table" or state.kind~="explicit-published-native-fixture-seed-not-lab-earned"
      or state.source_mir~=C.source or (state.source_fixture_version~=nil
        and state.source_fixture_version~=C.current_fixture) then fail("published source witness absent") end
  local expected_player,expected_foreign=expected_snapshots(state)
  same(snapshot(game.forces.player),expected_player,"player")
  local foreign=game.forces[state.foreign_index]
  same(snapshot(foreign),expected_foreign,"foreign force")
  zero_manufacturing(foreign)
  if entry_boundary_mode() then
    same(prototype_snapshot(game.forces.player),state.entry_boundary.player_prototypes,"player entry prototypes")
    same(prototype_snapshot(foreign),state.entry_boundary.foreign_prototypes,"foreign entry prototypes")
  end
  if successor then
    local fresh=game.forces[state.fresh_index]
    if not fresh or fresh.name~=FRESH_FORCE then fail("fresh successor force absent") end
    zero_manufacturing(fresh)
    if fresh.current_research or #(fresh.research_queue or {})~=0 then fail("fresh successor queue changed") end
    -- Current MIR5 exposes read-only native research queries, no enqueue API.
    -- Exercise the actual documented interface; it must report the captured
    -- states and leave the native queue/progress untouched.
    for _, row in ipairs(C.rows) do
      local value, reason=remote.call("more-infinite-research.api.v1","get_research",game.forces.player.index,id(row))
      local before=expected_player.technologies[id(row)]
      if type(value)~="table" or reason~=nil then fail("native API query absent: " .. id(row)) end
      for _, field in ipairs({"level","researched","enabled","saved_progress"}) do
        same(value[field],before[field],"API " .. id(row) .. "." .. field)
      end
    end
    same(snapshot(game.forces.player),expected_player,"after read-only API")
  end
end
local function entry_marker(phase,state)
  local version=script.active_mods[C.fixture]
  local witnesses={source_mir=C.source,successor_mir=C.successor,role="successor-entry-boundary-proposal",
    source_kind=state.kind,source_actual_labs=0,successor_actual_labs=0,
    source_snapshot=state.player,foreign_snapshot=state.foreign,entry_boundary=state.entry_boundary,
    accepted_current={player=snapshot(game.forces.player),foreign=snapshot(game.forces[state.foreign_index])},
    fresh_index=state.fresh_index,five_hidden_rows=true,exact_effect_counts={3,2,1,3,2},processing_unit_scrap=false,
    actual_gui_input=false,hidden_library_enqueue_not_exercised=true,on_load_read_only=phase=="reload",
    interpretation_review_required=true}
  if version=="0.5.0" then
    witnesses.successor_mir=C.current_successor
    witnesses.role="successor-current-entry-boundary-proposal"
    witnesses.fixture_version=version
    witnesses.source_fixture_version=state.source_fixture_version
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({case=C.case,stage=phase,status="passed",
    witnesses=witnesses}))
end
local function marker(phase,state,source)
  local current_source=source and state.source_fixture_version==C.current_fixture
  local witnesses={source_mir=C.source,successor_mir=current_source and C.current_successor or C.successor,
    role=current_source and "current-published-fixture-source" or source and "published" or "successor",
    source_kind=state.kind,source_actual_labs=0,successor_actual_labs=0,
    source_snapshot=state.player,foreign_snapshot=state.foreign,fresh_index=state.fresh_index,
    five_hidden_rows=true,exact_effect_counts={3,2,1,3,2},processing_unit_scrap=false,
    actual_gui_input=false,hidden_library_enqueue_not_exercised=true,on_load_read_only=phase=="reload"}
  if current_source then witnesses.source_fixture_version=state.source_fixture_version end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({case=C.case,stage=phase,status="passed",
    witnesses=witnesses}))
end
local function prepare_source(role)
  if not source_stage(role or stage()) then fail("protected published source save required") end
  local pending=storage[KEY]
  if role=="current-source" then
    if type(pending)~="table" or pending.kind~="current-fixture-source-awaiting-seed"
        or pending.source_mir~=C.source or pending.source_fixture_version~=C.current_fixture
        or pending.phase~="current-source-awaiting-seed" then fail("current source fixture collision") end
    -- Claim the fresh marker before mutating any source witness. A stopped
    -- partial source may fail closed; it never re-enters a seed/reseed path.
    pending.phase="current-source-seeding"
  elseif pending~=nil then fail("source fixture collision") end
  if game.forces[FOREIGN_FORCE] or game.forces[FRESH_FORCE] then fail("source fixture collision") end
  local force=game.forces.player
  assert_rows(force)
  for _, row in ipairs(C.rows) do
    for _, prerequisite in pairs(technology(force,id(row)).prerequisites) do prerequisite.research_recursive() end
  end
  local native=technology(force,C.foreign)
  for _, prerequisite in pairs(native.prerequisites) do prerequisite.research_recursive() end
  for index,row in ipairs(C.rows) do
    local value=technology(force,id(row));value.researched=false;value.level=index+1
    value.saved_progress=index/10
    if value.level~=index+1 or value.researched or not close(value.saved_progress,index/10) then fail("source seed failed") end
  end
  native.researched=false;native.level=4;native.enabled=true;native.saved_progress=.37
  force.reset_technology_effects()
  -- Exact2.0.77 has no LuaForce research_queue_enabled switch. Observe the
  -- supported queue/current/progress state and require both native additions.
  if #(force.research_queue or {})~=0 or force.current_research then fail("source queue was not empty") end
  if not force.add_research(C.foreign) or not force.add_research(id(C.rows[2])) then
    fail("published native API refused the required foreign/plastic queue; no fallback")
  end
  force.research_progress=.42
  -- Set intentional enablement after level/progress/effect/queue operations:
  -- published R03 showed earlier assignments normalized before capture.
  for index,row in ipairs(C.rows) do technology(force,id(row)).enabled=index~=3 end
  local player=snapshot(force)
  if player.technologies[id(C.rows[3])].enabled~=false then fail("disabled paid source was not retained") end
  if #player.queue~=2 or player.queue[1]~=C.foreign or player.queue[2]~=id(C.rows[2])
      or player.current~=C.foreign or not close(player.progress,.42) then fail("source queue seed differs") end
  for index,row in ipairs(C.rows) do
    for _, name in ipairs(row.recipes) do
      if player.bonuses[name]<index*.1-.000001 then fail("source native bonus was not earned: " .. name) end
    end
  end
  local foreign=game.create_force(FOREIGN_FORCE)
  local foreign_native=technology(foreign,C.foreign)
  foreign_native.researched=false;foreign_native.level=5;foreign_native.saved_progress=.27
  foreign.reset_technology_effects();foreign_native.enabled=false;zero_manufacturing(foreign)
  local foreign_snapshot=snapshot(foreign)
  if foreign_snapshot.foreign.enabled~=false then fail("disabled foreign source was not retained") end
  local captured={kind="explicit-published-native-fixture-seed-not-lab-earned",source_mir=C.source,
    phase="source-pending",player=player,foreign_index=foreign.index,foreign=foreign_snapshot}
  if role=="current-source" then captured.source_fixture_version=C.current_fixture end
  storage[KEY]=captured
end
script.on_init(function()
  local role=stage()
  if role=="current-source" then
    if storage[KEY]~=nil or game.forces[FOREIGN_FORCE] or game.forces[FRESH_FORCE] then fail("source fixture collision") end
    -- The normal runner creates, exits, then loads the save. Persist only a
    -- fixture-local pending marker now; the actual source seed is first tick,
    -- after published MIR initialization, and cannot be replayed once claimed.
    storage[KEY]={kind="current-fixture-source-awaiting-seed",source_mir=C.source,
      source_fixture_version=C.current_fixture,phase="current-source-awaiting-seed"}
    return
  end
  prepare_source(role)
end)
script.on_configuration_changed(function(event)
  local role=stage()
  local transition
  if role=="current-entry-successor" then transition=require_current_entry_event(event) end
  if source_stage(role) then fail("unexpected source configuration change") end
  local state=storage[KEY]
  if type(state)~="table" or state.phase~="source-complete" then fail("protected completed source required") end
  if role=="current-entry-successor" and state.source_fixture_version~=C.current_fixture then
    fail("current source fixture witness absent")
  end
  if entry_boundary_mode(role) then
    if state.entry_boundary~=nil then fail("entry boundary already captured") end
    local order=script.get_event_order();require_early_order(order)
    local player=snapshot(game.forces.player)
    local foreign_force=game.forces[state.foreign_index]
    local foreign=snapshot(foreign_force)
    local player_flag=player.technologies[id(C.rows[3])].enabled
    local foreign_flag=foreign.foreign.enabled
    if type(player_flag)~="boolean" or type(foreign_flag)~="boolean" then fail("entry boundary flags are not boolean") end
    local expected_player,expected_foreign=clone(state.player),clone(state.foreign)
    expected_player.technologies[id(C.rows[3])].enabled=player_flag
    expected_foreign.foreign.enabled=foreign_flag
    same(player,expected_player,"entry player vs source")
    same(foreign,expected_foreign,"entry foreign vs source")
    zero_manufacturing(foreign_force)
    local player_prototypes=prototype_snapshot(game.forces.player)
    local foreign_prototypes=prototype_snapshot(foreign_force)
    state.entry_boundary={player_processing_enabled=player_flag,foreign_mining_enabled=foreign_flag,event_order=order,
      player=player,foreign=foreign,player_prototypes=player_prototypes,foreign_prototypes=foreign_prototypes,
      flag_deltas={player_processing={source=state.player.technologies[id(C.rows[3])].enabled,entry=player_flag},
        foreign_mining={source=state.foreign.foreign.enabled,entry=foreign_flag}}}
    if transition then state.entry_boundary.transition=transition end
    state.phase="entry-boundary-pending"
    loaded,reported=false,false
    return -- No post-configuration verification, API, fresh force or save before MIR config.
  end
  -- Validate every preserved state before creating the independent fresh force.
  verify(state,false)
  if game.forces[FRESH_FORCE] then fail("fresh successor force collision") end
  local fresh=game.create_force(FRESH_FORCE);zero_manufacturing(fresh)
  state.fresh_index,state.phase=fresh.index,"successor-pending"
  loaded,reported=false,false
end)
script.on_load(function() loaded,reported=true,false end)
script.on_event(defines.events.on_tick,function()
  if reported then return end
  local role=stage()
  local initial=storage[KEY]
  if role=="current-source" and type(initial)=="table" and initial.phase=="current-source-awaiting-seed" then
    prepare_source(role)
    return
  end
  local source=source_stage(role);local state=initial
  if type(state)~="table" then fail("fixture state absent") end
  if entry_boundary_mode(role) and state.phase=="entry-boundary-pending" then
    -- First tick follows all configuration callbacks. Check preservation before
    -- the one intentional fresh-force creation, then the ordinary API/save path.
    verify(state,false)
    if game.forces[FRESH_FORCE] then fail("fresh successor force collision") end
    local fresh=game.create_force(FRESH_FORCE);zero_manufacturing(fresh)
    state.fresh_index=fresh.index
    verify(state,true)
    state.phase="entry-boundary-complete"
    entry_marker("initial",state);reported=true;game.server_save(SAVE)
    return
  elseif entry_boundary_mode(role) and loaded and state.phase=="entry-boundary-complete" then
    verify(state,true);entry_marker("reload",state);reported=true
    return
  end
  if state.phase=="source-pending" or state.phase=="successor-pending" then
    if source~=(state.phase=="source-pending") then fail("pending stage differs") end
    verify(state,not source)
    state.phase=source and "source-complete" or "successor-complete"
    marker("initial",state,source);reported=true;game.server_save(SAVE)
  elseif loaded and (state.phase=="source-complete" or state.phase=="successor-complete") then
    if source~=(state.phase=="source-complete") then fail("cold stage differs") end
    verify(state,not source);marker("reload",state,source);reported=true
  else fail("unexpected fixture phase") end
end)
