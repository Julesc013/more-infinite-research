-- One F200 catalogue-state upgrade scenario.  Lists come from the adjacent
-- recovered F200 oracle copy; the control never discovers technology families.
local KEY = "mir5_full_catalogue_upgrade"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-full-catalogue-upgrade"
local SOURCE = false
local MIR = "5.0.20000"
local GEAR = "recipe-prod-research_gears-1"
local PROBE = "braking-force-1"
local DEADLINE = 36000
local UINT32_MAX = 4294967295
local loaded, reload_logged = nil, false
local PLAN = require("__mir-fixture-mir5-full-catalogue-upgrade__/catalogue")

local function fail(message) error("[mir5-full-catalogue-upgrade] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end
local function profile()
  local space = script.active_mods["space-age"] ~= nil
  if space then
    if script.active_mods["space-age"] ~= "2.0.77" or script.active_mods["elevated-rails"] ~= "2.0.77"
        or script.active_mods.quality ~= "2.0.77" then fail("Space Age closure differs") end
    return PLAN.space_age, "space-age"
  end
  if script.active_mods["elevated-rails"] ~= nil or script.active_mods.quality ~= nil then
    fail("Base closure carries Space Age companions")
  end
  return PLAN.base, "base"
end
local function check_closure()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= MIR
      or script.active_mods[FIXTURE] ~= (SOURCE and "0.1.0" or "0.2.0") then
    fail("fixture stage closure differs")
  end
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function copy_table(value)
  local out = {}
  for key, item in pairs(value) do out[key] = item end
  return out
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    queue=queue, progress=force.research_progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs") end
  end
  return actual
end
local function state_rows(plan)
  local out = {}
  for _, row in ipairs(plan.state) do out[#out + 1] = row.name end
  for _, name in ipairs(plan.native_owners) do out[#out + 1] = name end
  return out
end
local function seed_levels(force, plan, label)
  for _, name in ipairs(state_rows(plan)) do
    local value = technology(force, name)
    if value.prototype.max_level ~= UINT32_MAX then fail(label .. " maximum changed: " .. name) end
    -- This is an explicit saved-state seed.  The only real lab completions are
    -- the source and successor gear levels below.
    value.level = value.prototype.level + 1
    if value.researched then fail(label .. " seeded infinite row became researched: " .. name) end
  end
  for _, name in ipairs(plan.scripted) do
    -- Scripted runtime effects have their own qualification.  Only presence is
    -- checked here; no scripted row is level-seeded or claimed as a lab result.
    technology(force, name)
  end
  force.reset_technology_effects()
end
local function snapshot(force, plan)
  local out = {technologies={}, recipes={}, fields={}, guns={}}
  for _, name in ipairs(state_rows(plan)) do
    local value = technology(force, name)
    out.technologies[name] = {level=value.level, researched=value.researched, enabled=value.enabled,
      visible=value.visible_when_disabled, saved=value.saved_progress, maximum=value.prototype.max_level}
  end
  for _, recipe in ipairs(plan.recipes) do
    local value = force.recipes[recipe]
    if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then
      fail("recipe productivity fact is absent: " .. recipe)
    end
    out.recipes[recipe] = value.productivity_bonus
  end
  for _, field in ipairs(PLAN.force_fields) do
    local value = force[field]
    if type(value) ~= "number" then fail("native force effect field is absent: " .. field) end
    out.fields[field] = value
  end
  for _, category in ipairs(plan.guns) do
    local value = force.get_gun_speed_modifier(category)
    if type(value) ~= "number" then fail("native gun-speed fact is absent: " .. category) end
    out.guns[category] = value
  end
  return out
end
local function assert_same_snapshot(force, plan, expected, label)
  local actual = snapshot(force, plan)
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    if now == nil or now.level ~= before.level or now.researched ~= before.researched
        or now.enabled ~= before.enabled or now.visible ~= before.visible or now.maximum ~= before.maximum
        or not close(now.saved, before.saved) then fail(label .. " technology state changed: " .. name) end
  end
  for name, before in pairs(expected.recipes) do if not close(actual.recipes[name], before) then fail(label .. " recipe bonus changed: " .. name) end end
  for name, before in pairs(expected.fields) do if not close(actual.fields[name], before) then fail(label .. " native force effect changed: " .. name) end end
  for name, before in pairs(expected.guns) do if not close(actual.guns[name], before) then fail(label .. " native gun effect changed: " .. name) end end
  return actual
end
local function assert_successor_snapshot(force, plan, expected, label)
  local actual = snapshot(force, plan)
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    local wanted = name == GEAR and before.level + 1 or before.level
    if now == nil or now.level ~= wanted or now.researched ~= before.researched
        or now.enabled ~= before.enabled or now.visible ~= before.visible or now.maximum ~= before.maximum
        or not close(now.saved, name == GEAR and 0 or before.saved) then fail(label .. " technology state changed: " .. name) end
  end
  for name, before in pairs(expected.recipes) do
    local extra = (name == "iron-gear-wheel" or name == "casting-iron-gear-wheel") and .1 or 0
    if not close(actual.recipes[name], before + extra) then fail(label .. " recipe bonus changed: " .. name) end
  end
  for name, before in pairs(expected.fields) do if not close(actual.fields[name], before) then fail(label .. " native force effect changed: " .. name) end end
  for name, before in pairs(expected.guns) do if not close(actual.guns[name], before) then fail(label .. " native gun effect changed: " .. name) end end
  return actual
end
local function assert_credits(force, plan, label)
  for _, name in ipairs(plan.credits) do
    local value = technology(force, name)
    if value.level ~= 1 or value.researched or value.enabled ~= false or value.visible_when_disabled ~= false
        or value.prototype.hidden ~= true or value.prototype.max_level ~= UINT32_MAX then
      fail(label .. " hidden zero-credit carrier differs: " .. name)
    end
  end
end
local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("real lab is absent") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real lab input is absent") end
  return value, inventory
end
local function fill(state, value)
  local entity, inventory = lab(state)
  inventory.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if inventory.insert{name=ingredient.name, count=64} ~= 64 then fail("could not insert science: " .. ingredient.name) end
  end
  entity.active, entity.energy = true, 1000000000
end
local function freeze(state)
  local entity, inventory = lab(state)
  entity.active, entity.energy = false, 0
  inventory.clear()
end
local function marker(stage, state, plan, profile_name)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="full-catalogue-upgrade", stage=stage, status="passed", profile=profile_name,
    qualification="native-runner-readback-required", witnesses={
      public_rows=#plan.public, level_backed_rows=#plan.state, native_owner_rows=#plan.native_owners,
      scripted_rows_not_seeded=#plan.scripted, zero_credit_rows=#plan.credits,
      source_gear_lab=state.source_labs, successor_gear_lab=state.successor_labs,
      queued_progress=.42, paused_progress=.27, save_name=SAVE, on_load_read_only=stage == "reload",
    },
  }))
end
local function source_init()
  check_closure()
  local plan, profile_name = profile()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  seed_levels(player, plan, "source player")
  local gear = technology(player, GEAR)
  prerequisites(gear)
  local paused = game.create_force("mir5-full-catalogue-upgrade-paused")
  paused.enable_all_prototypes(); seed_levels(paused, plan, "source paused")
  local paused_gear = technology(paused, GEAR)
  paused_gear.saved_progress = .27
  if not close(paused_gear.saved_progress, .27) or paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0 then
    fail("paused saved work seed differs")
  end
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if entity == nil or entity.valid == false then fail("could not create a real gear lab") end
  local state = {phase="await-source-lab", plan=profile_name, lab=entity, paused_index=paused.index, paused_snapshot=snapshot(paused, plan),
    source_labs=0, successor_labs=0, deadline=game.tick + DEADLINE}
  storage[KEY] = state
  fill(state, gear)
  if player.add_research(gear) ~= true then fail("could not queue source gear lab") end
end
local function source_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture state is absent") end
  local plan, profile_name = profile()
  if state.phase == "completed" then
    if loaded and not reload_logged then
      assert_same_snapshot(game.forces.player, plan, state.source_snapshot, "source cold reload")
      local paused = game.forces[state.paused_index]
      if paused == nil or not close(technology(paused, GEAR).saved_progress, .27) then fail("source cold reload lost paused work") end
      assert_same_snapshot(paused, plan, state.paused_snapshot, "source paused cold reload")
      marker("reload", state, plan, profile_name); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("source gear lab did not finish") end
  if state.phase == "await-source-lab" then
    local _, inventory = lab(state); state.lab.energy = 1000000000
    if state.source_labs ~= 1 then return end
    freeze(state)
    local player, gear, probe = game.forces.player, technology(game.forces.player, GEAR), technology(game.forces.player, PROBE)
    prerequisites(probe)
    if probe.researched then fail("unrelated queue probe was researched") end
    gear.saved_progress, probe.saved_progress = .42, 0
    player.research_queue = {gear, probe}; player.research_progress = .42
    state.player_queue = assert_queue(player, {current=GEAR, queue={GEAR, PROBE}, progress=.42}, "source queued work")
    state.source_snapshot = snapshot(player, plan)
    state.phase = "completed"
    marker("initial", state, plan, profile_name); game.server_save(SAVE)
  end
end
local function successor_config()
  check_closure()
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "completed" or type(state.source_snapshot) ~= "table" or type(state.paused_snapshot) ~= "table" then
    fail("successor lacks the complete published source witness")
  end
  local plan, profile_name = profile()
  if state.plan ~= profile_name then fail("successor changed F200 profile") end
  local player = game.forces.player
  assert_same_snapshot(player, plan, state.source_snapshot, "pre-successor")
  assert_credits(player, plan, "pre-successor")
  assert_queue(player, state.player_queue, "pre-successor")
  local paused = game.forces[state.paused_index]
  if paused == nil or paused.valid == false or not close(technology(paused, GEAR).saved_progress, .27)
      or paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0 then fail("successor changed paused work") end
  assert_same_snapshot(paused, plan, state.paused_snapshot, "pre-successor paused")
  state.phase, state.deadline = "await-successor-lab", game.tick + DEADLINE
  fill(state, technology(player, GEAR))
end
local function successor_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor fixture state is absent") end
  local plan, profile_name = profile()
  if state.phase == "successor-completed" then
    if loaded and not reload_logged then
      assert_successor_snapshot(game.forces.player, plan, state.source_snapshot, "successor cold reload")
      assert_credits(game.forces.player, plan, "successor cold reload")
      local paused = game.forces[state.paused_index]
      if paused == nil then fail("successor cold reload lost paused force") end
      assert_same_snapshot(paused, plan, state.paused_snapshot, "successor paused cold reload")
      marker("reload", state, plan, profile_name); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("successor gear lab did not finish") end
  if state.phase == "await-successor-lab" then
    local entity = lab(state); entity.energy = 1000000000
  elseif state.phase == "await-successor-observation" then
    freeze(state)
    assert_successor_snapshot(game.forces.player, plan, state.source_snapshot, "successor lab")
    assert_credits(game.forces.player, plan, "successor lab")
    local paused = game.forces[state.paused_index]
    if paused == nil or not close(technology(paused, GEAR).saved_progress, .27) then fail("successor lost paused progress") end
    assert_same_snapshot(paused, plan, state.paused_snapshot, "successor paused lab")
    state.phase = "successor-completed"
    marker("initial", state, plan, profile_name); game.server_save(SAVE)
  end
end

if SOURCE then
  script.on_init(source_init)
else
  script.on_configuration_changed(function() successor_config() end)
end
script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= GEAR then return end
  if SOURCE and state.phase == "await-source-lab" then state.source_labs = state.source_labs + 1
  elseif not SOURCE and state.phase == "await-successor-lab" then
    state.successor_labs = state.successor_labs + 1; state.phase = "await-successor-observation"
  end
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and (state.phase == "completed" or state.phase == "successor-completed")
  reload_logged = false
end)
script.on_event(defines.events.on_tick, function()
  if SOURCE then source_tick() else successor_tick() end
end)
