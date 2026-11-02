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
  local source = version=="0.1.0"
  if not source and version~="0.2.0" then fail("fixture version differs") end
  local expected = {base="2.0.77",["elevated-rails"]="2.0.77",quality="2.0.77",
    ["space-age"]="2.0.77",["space-is-fake"]="1.0.60",["cr-commons"]="1.0.27",
    [C.fixture]=version,["more-infinite-research"]=source and C.source or C.successor,
    ["mir-fixture-mir5-active-mods-observer"]="0.1.0"}
  for name, value in pairs(expected) do
    if script.active_mods[name]~=value then fail("exact closure differs: " .. name) end
  end
  for name in pairs(script.active_mods) do if expected[name]==nil then fail("unexpected mod: " .. name) end end
  return source
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
      or state.source_mir~=C.source then fail("published source witness absent") end
  same(snapshot(game.forces.player),state.player,"player")
  local foreign=game.forces[state.foreign_index]
  same(snapshot(foreign),state.foreign,"foreign force")
  zero_manufacturing(foreign)
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
      local before=state.player.technologies[id(row)]
      if type(value)~="table" or reason~=nil then fail("native API query absent: " .. id(row)) end
      for _, field in ipairs({"level","researched","enabled","saved_progress"}) do
        same(value[field],before[field],"API " .. id(row) .. "." .. field)
      end
    end
    same(snapshot(game.forces.player),state.player,"after read-only API")
  end
end
local function marker(phase,state,source)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({case=C.case,stage=phase,status="passed",
    witnesses={source_mir=C.source,successor_mir=C.successor,role=source and "published" or "successor",
      source_kind=state.kind,source_actual_labs=0,successor_actual_labs=0,
      source_snapshot=state.player,foreign_snapshot=state.foreign,fresh_index=state.fresh_index,
      five_hidden_rows=true,exact_effect_counts={3,2,1,3,2},processing_unit_scrap=false,
      actual_gui_input=false,hidden_library_enqueue_not_exercised=true,on_load_read_only=phase=="reload"}}))
end
local function prepare_source()
  if not stage() then fail("protected published source save required") end
  if storage[KEY]~=nil or game.forces[FOREIGN_FORCE] or game.forces[FRESH_FORCE] then fail("source fixture collision") end
  local force=game.forces.player
  assert_rows(force)
  for _, row in ipairs(C.rows) do
    for _, prerequisite in pairs(technology(force,id(row)).prerequisites) do prerequisite.research_recursive() end
  end
  local native=technology(force,C.foreign)
  for _, prerequisite in pairs(native.prerequisites) do prerequisite.research_recursive() end
  for index,row in ipairs(C.rows) do
    local value=technology(force,id(row));value.researched=false;value.level=index+1
    value.enabled=index~=3;value.saved_progress=index/10
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
  local player=snapshot(force)
  if #player.queue~=2 or player.queue[1]~=C.foreign or player.queue[2]~=id(C.rows[2])
      or player.current~=C.foreign or not close(player.progress,.42) then fail("source queue seed differs") end
  for index,row in ipairs(C.rows) do
    for _, name in ipairs(row.recipes) do
      if player.bonuses[name]<index*.1-.000001 then fail("source native bonus was not earned: " .. name) end
    end
  end
  local foreign=game.create_force(FOREIGN_FORCE)
  local foreign_native=technology(foreign,C.foreign)
  foreign_native.researched=false;foreign_native.level=5;foreign_native.enabled=false;foreign_native.saved_progress=.27
  foreign.reset_technology_effects();zero_manufacturing(foreign)
  storage[KEY]={kind="explicit-published-native-fixture-seed-not-lab-earned",source_mir=C.source,
    phase="source-pending",player=player,foreign_index=foreign.index,foreign=snapshot(foreign)}
end
script.on_init(prepare_source)
script.on_configuration_changed(function()
  if stage() then fail("unexpected source configuration change") end
  local state=storage[KEY]
  if type(state)~="table" or state.phase~="source-complete" then fail("protected completed source required") end
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
  local source=stage();local state=storage[KEY]
  if type(state)~="table" then fail("fixture state absent") end
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
