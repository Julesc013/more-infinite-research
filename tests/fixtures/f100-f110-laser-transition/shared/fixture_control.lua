local M = {}

local KEY = "mir5_f100_f110_laser_transition"
local FIXTURE = "mir-fixture-mir5-f100-f110-laser-transition"
local CASE = "f100-f110-laser-transition"
local SAVE = "mir5-native-complete"
local LAB_PACKS = 32
local DEADLINE = 18000
local PREREQUISITES = {
  "chemical-science-pack", "laser-turret-speed-6", "laser-turret-speed-7",
  "logistic-science-pack", "military-science-pack", "utility-science-pack",
}

local function fail(message)
  error("[mir5-f100-f110-laser-transition] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= .000001
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false then fail("required technology is absent: " .. tostring(name)) end
  return value
end

local function current_name(force)
  local value = force.current_research
  return value and value.name or nil
end

local function state()
  local value = global and global[KEY]
  if type(value) ~= "table" then fail("fixture state is absent") end
  return value
end

local function write_state(value)
  global[KEY] = value
end

local function saved_progress(force, value)
  return force.get_saved_technology_progress(value)
end

local function set_saved_progress(force, value, progress)
  force.set_saved_technology_progress(value, progress)
end

local function assert_effect(value, ammo, label)
  local effects = value.prototype and value.prototype.effects
  local found, count = nil, 0
  for _, effect in pairs(effects or {}) do
    count = count + 1
    if type(effect) == "table" and effect.type == "gun-speed"
        and effect.ammo_category == ammo and close(effect.modifier, .75) then
      found = effect
    end
  end
  if count ~= 1 or found == nil then fail(label .. " laser effect differs") end
end

local function assert_shape(force, spec, label)
  local value = technology(force, spec.direct)
  local prototype = value.prototype
  if prototype == nil or prototype.name ~= spec.direct or prototype.level ~= 8
      or prototype.upgrade ~= true or prototype.max_level ~= spec.maximum then
    fail(label .. " laser identity or cap differs")
  end
  assert_effect(value, spec.ammo, label)
  local ingredients = value.research_unit_ingredients
  if type(ingredients) ~= "table" or #ingredients ~= 5 then
    fail(label .. " laser science vector differs")
  end
  return value
end

local function seed_prerequisites(force)
  for _, name in ipairs(PREREQUISITES) do
    local value = technology(force, name)
    value.enabled = true
    value.researched = true
  end
end

local function seed_braking_probe_prerequisites(force)
  -- F100 Base binds braking-force-1 to these two direct prerequisites.  This
  -- is deliberately a finite fixture seed, not a recursive prerequisite walk.
  for _, name in ipairs({"railway", "chemical-science-pack"}) do
    local value = technology(force, name)
    value.enabled = true
    value.researched = true
  end
end

local function queue_snapshot(force)
  local queue = force.research_queue or {}
  local names = {}
  for index, value in ipairs(queue) do names[index] = value.name end
  return {current=current_name(force), queue=names, progress=force.research_progress,
    enabled=force.research_queue_enabled}
end

local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if type(expected) ~= "table" or actual.current ~= expected.current
      or actual.enabled ~= true or not close(actual.progress, expected.progress)
      or #actual.queue ~= #expected.queue then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs") end
  end
end

local function create_lab(force, position)
  local entity = game.surfaces[1].create_entity{name="lab", position=position, force=force}
  if entity == nil or entity.valid == false then fail("could not create real laser lab") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real laser lab input is absent") end
  return entity
end

local function science_units(inventory, item, label, science_type)
  if science_type ~= "tool" then fail(label .. " science type differs") end
  local prototype = game.item_prototypes and game.item_prototypes[item]
  if prototype == nil or type(prototype.durability) ~= "number" or prototype.durability <= 0 then
    fail(label .. " native science tool prototype differs: " .. item)
  end
  local total, stacks = 0, 0
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == item then
      if stack.is_tool ~= true or type(stack.count) ~= "number" or stack.count < 1
          or stack.count % 1 ~= 0 or type(stack.durability) ~= "number"
          or stack.durability <= 0 or stack.durability > prototype.durability then
        fail(label .. " native science tool stack differs: " .. item)
      end
      total = total + stack.count - 1 + stack.durability / prototype.durability
      stacks = stacks + 1
    end
  end
  if stacks == 0 then fail(label .. " native science tool stack is absent: " .. item) end
  return total
end

local function fill_lab(state_value, field, value, spec)
  local entity = state_value[field]
  if entity == nil or entity.valid == false then fail("real laser lab is absent") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real laser lab input disappeared") end
  inventory.clear()
  local supplied = {}
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string" then
      fail("laser lab ingredient differs")
    end
    if inventory.insert{name=ingredient.name, count=LAB_PACKS} ~= LAB_PACKS then
      fail("real laser lab rejected " .. ingredient.name)
    end
    supplied[ingredient.name] = science_units(inventory, ingredient.name, field .. " fixture seed", spec.science_type)
  end
  if next(supplied) == nil then fail("laser lab has no supplied science") end
  state_value[field .. "_supplied"] = supplied
  entity.energy = 100000000
end

local function assert_consumed(state_value, field, spec)
  local entity = state_value[field]
  local inventory = entity and entity.get_inventory(defines.inventory.lab_input)
  local supplied = state_value[field .. "_supplied"]
  if entity == nil or entity.valid == false or inventory == nil or type(supplied) ~= "table" then
    fail("laser lab consumption witness is absent")
  end
  for name, units in pairs(supplied) do
    if type(units) ~= "number" or units - science_units(inventory, name, field .. " post-lab", spec.science_type) < 1 then
      fail("real laser lab did not consume " .. tostring(name))
    end
  end
end

local function freeze_lab(state_value, field)
  local entity = state_value[field]
  if entity == nil or entity.valid == false then fail("real laser lab disappeared") end
  entity.energy = 0
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real laser lab input disappeared") end
  inventory.clear()
end

local function energize_lab(state_value, field)
  local entity = state_value[field]
  if entity == nil or entity.valid == false then fail("real laser lab disappeared") end
  entity.energy = 100000000
end

local function seed_control(spec)
  local control = game.create_force("mir5-f100-f110-laser-control")
  if control == nil or control.valid == false then fail("could not create baseline control force") end
  control.enable_all_prototypes()
  local direct = assert_shape(control, spec, "control")
  seed_prerequisites(control)
  direct.enabled = true
  if direct.researched then fail("baseline control laser was already researched") end
  return control
end

local function seed_detached(spec)
  local detached = game.create_force("mir5-f100-f110-laser-detached")
  if detached == nil or detached.valid == false then fail("could not create detached laser force") end
  detached.enable_all_prototypes()
  local direct = assert_shape(detached, spec, "detached")
  seed_prerequisites(detached)
  direct.enabled = true
  if direct.researched or current_name(detached) ~= nil or #(detached.research_queue or {}) ~= 0 then
    fail("detached laser seed differs")
  end
  set_saved_progress(detached, direct, .27)
  if not close(saved_progress(detached, direct), .27) then fail("detached laser progress differs") end
  return detached
end

local function seed_foreign(spec)
  local foreign = game.create_force("mir5-f100-f110-laser-foreign")
  if foreign == nil or foreign.valid == false then fail("could not create foreign laser force") end
  foreign.enable_all_prototypes()
  local direct = assert_shape(foreign, spec, "foreign")
  direct.enabled = false
  if direct.enabled ~= false or direct.researched then fail("foreign laser disablement differs") end
  return foreign
end

local function assert_detached(state_value, spec, label)
  local force = game.forces[state_value.detached_index]
  if force == nil or force.valid == false then fail(label .. " detached force is absent") end
  local direct = assert_shape(force, spec, label .. " detached")
  if direct.researched or direct.enabled ~= true or not close(saved_progress(force, direct), .27)
      or current_name(force) ~= nil or #(force.research_queue or {}) ~= 0 then
    fail(label .. " detached work differs")
  end
end

local function assert_foreign(state_value, spec, label)
  local force = game.forces[state_value.foreign_index]
  if force == nil or force.valid == false then fail(label .. " foreign force is absent") end
  local direct = assert_shape(force, spec, label .. " foreign")
  if direct.enabled ~= false or direct.researched then fail(label .. " foreign disablement differs") end
end

local function baseline_delta(player, control, ammo)
  return player.get_gun_speed_modifier(ammo) - control.get_gun_speed_modifier(ammo)
end

local function assert_baseline(state_value, spec, expected, label)
  local player, control = game.forces.player, game.forces[state_value.control_index]
  if control == nil or control.valid == false then fail(label .. " control force is absent") end
  assert_shape(control, spec, label .. " control")
  if not close(baseline_delta(player, control, spec.ammo), expected) then
    fail(label .. " earned laser modifier differs")
  end
end

local function marker(stage, state_value, spec)
  local player = game.forces.player
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"" .. CASE .. "\","
    .. "\"stage\":\"" .. stage .. "\","
    .. "\"status\":\"passed\","
    .. "\"scope\":\"mir5-forward-laser-intent\","
    .. "\"direct\":\"" .. spec.direct .. "\","
    .. "\"ammo_category\":\"" .. spec.ammo .. "\","
    .. "\"source_laser_lab_completions\":" .. tostring(state_value.source_laser_labs or 0) .. ","
    .. "\"successor_laser_lab_completions\":" .. tostring(state_value.successor_laser_labs or 0) .. ","
    .. "\"laser_level\":" .. tostring(technology(player, spec.direct).level) .. ","
    .. "\"laser_delta\":" .. tostring(baseline_delta(player, game.forces[state_value.control_index], spec.ammo)) .. ","
    .. "\"queued_progress\":0.42,"
    .. "\"detached_progress\":0.27,"
    .. "\"foreign_enabled\":false,"
    .. "\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end

local function assert_closure(spec)
  local mods = script.active_mods
  if type(mods) ~= "table" or mods.base ~= spec.base or mods["more-infinite-research"] ~= spec.mir
      or mods[FIXTURE] ~= spec.fixture then
    fail(spec.stage .. " closure differs")
  end
end

local function source_initialize(spec)
  assert_closure(spec)
  if global[KEY] ~= nil then fail("source state already exists") end
  local player = game.forces.player
  player.enable_all_prototypes()
  local direct = assert_shape(player, spec, "source")
  seed_prerequisites(player)
  direct.enabled = true
  if direct.researched then fail("source laser was already researched") end
  player.research_queue_enabled = true
  if player.research_queue_enabled ~= true then fail("source research queue is unavailable") end
  local control = seed_control(spec)
  local before = baseline_delta(player, control, spec.ammo)
  if not close(before, 0) then fail("source baseline force differs") end
  local source_state = {
    origin = "mir5-f100-forward-laser-intent", phase = "source-lab",
    source_laser_labs = 0, successor_laser_labs = 0, control_index = control.index,
    source_lab = create_lab(player, {0, 0}), deadline = game.tick + DEADLINE,
  }
  write_state(source_state)
  fill_lab(source_state, "source_lab", direct, spec)
  if player.add_research(direct) ~= true or current_name(player) ~= spec.direct then
    fail("could not start real source laser research")
  end
end

local function source_finish(state_value, spec)
  local player, direct = game.forces.player, assert_shape(game.forces.player, spec, "source")
  assert_consumed(state_value, "source_lab", spec)
  if direct.researched ~= true or direct.level ~= 8 then fail("source finite laser completion differs") end
  assert_baseline(state_value, spec, .75, "source")
  freeze_lab(state_value, "source_lab")
  local probe = technology(player, "braking-force-1")
  seed_braking_probe_prerequisites(player)
  probe.enabled = true
  if probe.researched then fail("source queue probe was already researched") end
  if player.add_research(probe) ~= true or current_name(player) ~= probe.name then
    fail("could not queue source preservation probe")
  end
  player.research_progress = .42
  state_value.player_queue = {current=probe.name, queue={probe.name}, progress=.42}
  assert_queue(player, state_value.player_queue, "source")
  local detached = seed_detached(spec)
  local foreign = seed_foreign(spec)
  state_value.detached_index, state_value.foreign_index = detached.index, foreign.index
  state_value.phase = "source-complete"
end

local function assert_source_complete(state_value, spec, label)
  if state_value.origin ~= "mir5-f100-forward-laser-intent" or state_value.phase ~= "source-complete"
      or state_value.source_laser_labs ~= 1 or state_value.successor_laser_labs ~= 0 then
    fail(label .. " source witness differs")
  end
  local player, direct = game.forces.player, assert_shape(game.forces.player, spec, label)
  if direct.researched ~= true or direct.level ~= 8 then fail(label .. " source earned level differs") end
  assert_baseline(state_value, spec, .75, label)
  assert_queue(player, state_value.player_queue, label)
  assert_detached(state_value, spec, label)
  assert_foreign(state_value, spec, label)
end

local function successor_initialize(state_value, spec)
  assert_closure(spec)
  if state_value.origin ~= "mir5-f100-forward-laser-intent" or state_value.phase ~= "source-complete"
      or state_value.source_laser_labs ~= 1 then
    fail("successor lacks complete current MIR5 F100 source state")
  end
  local player, direct = game.forces.player, assert_shape(game.forces.player, spec, "successor")
  -- The exact JSON migration has already changed the source identity before
  -- this callback. A finite completed level eight becomes the next available
  -- canonical level; the fixture never writes that earned state itself.
  if direct.researched ~= false or direct.level ~= 9 then
    fail("successor canonical earned laser state differs")
  end
  assert_baseline(state_value, spec, .75, "successor")
  assert_queue(player, state_value.player_queue, "successor")
  assert_detached(state_value, spec, "successor")
  assert_foreign(state_value, spec, "successor")
  -- This is a new F110 process/result, distinct from the protected F100
  -- source save marker.  It must issue its own completion save before its
  -- two successor cold-read-only reloads.
  state_value.saved = false
  state_value.phase = "successor-lab"
  local queued = technology(player, state_value.player_queue.current)
  player.research_queue = {direct}
  if current_name(player) ~= spec.direct or not close(saved_progress(player, queued), state_value.player_queue.progress) then
    fail("could not preserve queued braking work while starting successor laser research")
  end
  state_value.successor_lab = create_lab(player, {4, 0})
  fill_lab(state_value, "successor_lab", direct, spec)
  state_value.deadline = game.tick + DEADLINE
end

local function successor_finish(state_value, spec)
  local player, direct = game.forces.player, assert_shape(game.forces.player, spec, "successor")
  assert_consumed(state_value, "successor_lab", spec)
  if direct.researched ~= false or direct.level ~= 10 then
    fail("successor laser level differs")
  end
  assert_baseline(state_value, spec, 1.5, "successor")
  freeze_lab(state_value, "successor_lab")
  local probe = technology(player, state_value.player_queue.current)
  if not close(saved_progress(player, probe), state_value.player_queue.progress) then
    fail("successor laser completion lost queued braking work")
  end
  player.research_queue = {probe}
  assert_queue(player, state_value.player_queue, "successor")
  assert_detached(state_value, spec, "successor")
  assert_foreign(state_value, spec, "successor")
  state_value.phase = "successor-complete"
end

function M.apply(spec)
  if type(spec) ~= "table" or (spec.stage ~= "source" and spec.stage ~= "successor")
      or type(spec.direct) ~= "string" or type(spec.ammo) ~= "string"
      or type(spec.maximum) ~= "number" or spec.science_type ~= "tool" then
    fail("fixture control specification differs")
  end
  local loaded, reload_reported = false, false

  script.on_init(function()
    if spec.stage ~= "source" then fail("successor requires a protected source save") end
    source_initialize(spec)
  end)

  script.on_configuration_changed(function()
    if spec.stage ~= "successor" then fail("unexpected source configuration") end
    local state_value = state()
    if state_value.phase ~= "source-complete" then fail("unexpected completed successor configuration") end
    successor_initialize(state_value, spec)
  end)

  script.on_event(defines.events.on_research_finished, function(event)
    local state_value = state()
    if event == nil or event.research == nil or event.research.force ~= game.forces.player then return end
    if spec.stage == "source" and state_value.phase == "source-lab" and event.research.name == spec.direct then
    if event.by_script ~= false then fail("source laser completion was not a real lab") end
      state_value.source_laser_labs = state_value.source_laser_labs + 1
      if state_value.source_laser_labs ~= 1 then fail("source laser completed more than once") end
      source_finish(state_value, spec)
    elseif spec.stage == "successor" and state_value.phase == "successor-lab" and event.research.name == spec.direct then
    if event.by_script ~= false then fail("successor laser completion was not a real lab") end
      state_value.successor_laser_labs = state_value.successor_laser_labs + 1
      if state_value.successor_laser_labs ~= 1 then fail("successor laser completed more than once") end
      successor_finish(state_value, spec)
    end
  end)

  script.on_load(function()
    -- on_load deliberately touches no game or persisted fixture state.
    loaded, reload_reported = true, false
  end)

  script.on_event(defines.events.on_tick, function()
    local state_value = state()
    if state_value.phase == "source-lab" then
      energize_lab(state_value, "source_lab")
      if game.tick > state_value.deadline then fail("source real laser lab missed deadline") end
      return
    end
    if state_value.phase == "successor-lab" then
      energize_lab(state_value, "successor_lab")
      if game.tick > state_value.deadline then fail("successor real laser lab missed deadline") end
      return
    end
    if spec.stage == "source" and state_value.phase == "source-complete" then
      assert_source_complete(state_value, spec, "source")
    elseif spec.stage == "successor" and state_value.phase == "successor-complete" then
      local direct = assert_shape(game.forces.player, spec, "successor")
      if direct.level ~= 10 then fail("successor completed level differs") end
      assert_baseline(state_value, spec, 1.5, "successor")
      assert_queue(game.forces.player, state_value.player_queue, "successor")
      assert_detached(state_value, spec, "successor")
      assert_foreign(state_value, spec, "successor")
    else
      fail("fixture phase differs")
    end
    if not state_value.saved then
      state_value.saved = true
      loaded, reload_reported = false, false
      marker("initial", state_value, spec)
      game.server_save(SAVE)
      return
    end
    if loaded and not reload_reported then
      marker("reload", state_value, spec)
      reload_reported = true
    end
  end)
end

return M
