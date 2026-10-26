local KEY = "mir5_f200_legacy_cap"
local MIR5_CASE = "f200-positive-legacy-cap"
local PUBLISHED_RELAXED_CASE = "published-relaxed-control"
local CROSS_ENGINE_CASE = "f200-f210-positive-legacy-cap"
local CROSS_ENGINE_DISABLED_CASE = "f200-f210-positive-legacy-cap-disabled"
local CROSS_ENGINE_REENABLED_CASE = "f200-f210-positive-legacy-cap-reenabled"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-f200-legacy-cap"
local GEAR = "recipe-prod-research_gears-1"
local RECIPE = "iron-gear-wheel"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-f200-legacy-cap-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}
local UINT32_MAX = 4294967295
local LAB_ENERGY = 100000000
local DESTINATION_PACKS = 8
local DEADLINE = 18000

local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-f200-legacy-cap-successor] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function status(force)
  local value = technology(force, GEAR)
  local recipe = force.recipes[RECIPE]
  if recipe == nil then fail("gear recipe is absent for " .. tostring(force.name)) end
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = recipe.productivity_bonus, saved_progress = value.saved_progress}
end

local function copy_status(value)
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible, maximum = value.maximum, bonus = value.bonus,
    saved_progress = value.saved_progress}
end

local function assert_status(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible ~= expected.visible
      or actual.maximum ~= expected.maximum or not close(actual.bonus, expected.bonus) then
    fail(label .. " native gear state differs")
  end
  if expected.saved_progress ~= nil and not close(actual.saved_progress, expected.saved_progress) then
    fail(label .. " saved progress differs")
  end
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end

local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue or {}) do queue[index] = name end
  return {current = value.current, queue = queue, progress = value.progress}
end

local function assert_foreign(force, expected)
  if force == nil or force.valid == false or force.name ~= FOREIGN then fail("foreign force witness is absent") end
  assert_status(status(force), {level = 1, researched = false, enabled = false, visible = false,
    maximum = UINT32_MAX, bonus = 0}, "foreign gear")
  local current = queue_snapshot(force)
  if current.current ~= PROBE or #current.queue ~= 1 or current.queue[1] ~= PROBE
      or not close(current.progress, 0.42) then fail("foreign queue or progress changed") end
  if type(expected) ~= "table" or expected.current ~= current.current or #expected.queue ~= #current.queue
      or expected.queue[1] ~= current.queue[1] or not close(expected.progress, current.progress) then
    fail("foreign source queue witness differs")
  end
  return current
end

local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("source player lab is absent") end
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("source player lab has no power") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("source player lab inventory is absent") end
  return inventory
end

local function science_units(inventory, item, label)
  local total, stacks = 0, 0
  local prototype = prototypes.item[item]
  if prototype == nil or type(prototype.get_durability) ~= "function" then
    fail(label .. " native science item prototype is absent: " .. item)
  end
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == item then
      local quality = stack.quality
      if quality == nil or quality.name ~= "normal" then
        fail(label .. " native science quality changed for " .. item)
      end
      local maximum = prototype.get_durability(quality)
      local durability = stack.durability
      if not close(maximum, 1) or type(durability) ~= "number"
          or durability <= 0 or durability > maximum or type(stack.count) ~= "number" or stack.count < 1 then
        fail(label .. " native science durability changed for " .. item)
      end
      total = total + stack.count - 1 + durability / maximum
      stacks = stacks + 1
    end
  end
  if stacks == 0 then fail(label .. " native science stack is absent for " .. item) end
  return total
end

local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not retain one-unit one-second native research")
  end
end

local function destination_mode()
  local base = script.active_mods.base
  local mir, fixture = script.active_mods["more-infinite-research"], script.active_mods[FIXTURE]
  if base == "2.0.77" and mir == "5.0.20000" and fixture == "0.2.0" then
    return {case = MIR5_CASE, label = "MIR5", source_mir = "4.7.20002", source_fixture = "0.1.0"}
  end
  if base == "2.0.77" and mir == "4.7.20002" and fixture == "0.3.0" then
    return {case = PUBLISHED_RELAXED_CASE, label = "published relaxed", source_mir = "4.7.20002", source_fixture = "0.1.0"}
  end
  if base == "2.1.23" and mir == "5.0.21000" and fixture == "0.5.0" then
    return {case = CROSS_ENGINE_CASE, label = "MIR5 F210 cross-engine", source_mir = "4.7.20003", source_fixture = "0.4.0"}
  end
  if base == "2.1.23" and mir == "5.0.21000" and fixture == "0.6.0" then
    return {case = CROSS_ENGINE_DISABLED_CASE, label = "MIR5 F210 disabled intermediate",
      source_mir = "4.7.20003", source_fixture = "0.4.0", disabled_intermediate = true}
  end
  if base == "2.1.23" and mir == "5.0.21000" and fixture == "0.7.0" then
    return {case = CROSS_ENGINE_REENABLED_CASE, label = "MIR5 F210 re-enabled cross-engine",
      source_mir = "4.7.20003", source_fixture = "0.4.0", reenabled = true}
  end
  fail("successor requires the exact F200 MIR5/published fixture or F210 5.0.21000 cross-engine stage")
end

local function expected_science_consumption(force, value, lab_entity, saved_progress)
  if force.current_research ~= value or #force.research_queue ~= 1 then
    fail("successor research is not singly current")
  end
  local progress = force.research_progress
  if not close(progress, saved_progress) then
    fail("successor saved research investment did not become current research")
  end
  local quality = lab_entity.quality
  if quality == nil or quality.name ~= "normal" then fail("successor lab quality is not normal") end
  local prototype = lab_entity.prototype
  if prototype == nil or type(prototype.get_researching_speed) ~= "function" then
    fail("successor lab researching speed is absent")
  end
  local researching_speed = prototype.get_researching_speed(quality)
  local laboratory_speed, productivity = force.laboratory_speed_modifier, force.laboratory_productivity_bonus
  if not close(researching_speed, 1) or not close(laboratory_speed, 0) or not close(productivity, 0) then
    fail("successor lab speed or productivity fixture input changed")
  end
  local modules = lab_entity.get_module_inventory and lab_entity.get_module_inventory()
  if modules ~= nil then
    for index = 1, #modules do
      if modules[index].valid_for_read then fail("successor lab has a module") end
    end
  end
  local energy = value.research_unit_energy
  local work_per_tick = researching_speed * (1 + laboratory_speed)
  local remaining_work = (1 - progress) * energy
  if type(energy) ~= "number" or energy <= 0 or work_per_tick <= 0 or remaining_work <= 0 then
    fail("successor native research timing differs")
  end
  local ticks = math.ceil(remaining_work / work_per_tick)
  local consumed_units = ticks * work_per_tick / energy
  if ticks <= 0 or consumed_units <= 0 or consumed_units > 1 then fail("successor native science timing differs") end
  return {progress = progress, energy = energy, researching_speed = researching_speed,
    laboratory_speed = laboratory_speed, remaining_work = remaining_work, remaining_ticks = ticks,
    consumed_units = consumed_units}
end

local function assert_source_witness(state, mode)
  if state.source_mir ~= mode.source_mir or state.fixture_version ~= mode.source_fixture
      or state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs"
      or type(state.foreign_queue) ~= "table" or type(state.player_cap) ~= "table"
      or not close(state.player_cap.saved_progress, 0.27) then
    fail("published positive-cap source witness is absent or malformed")
  end
end

local function assert_restored(state, mode)
  assert_source_witness(state, mode)
  local label = mode.label
  local player = status(game.forces.player)
  -- Preserve the actual value captured by the published controller after its
  -- data-final presentation patch, rather than inventing a false predecessor.
  assert_status(player, {level = 3, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = 0.02, saved_progress = 0.27}, label .. " restored player")
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  assert_acceleration(technology(game.forces.player, GEAR))
  return player
end

local function assert_disabled_intermediate(state, mode)
  assert_source_witness(state, mode)
  local player = status(game.forces.player)
  assert_status(player, {level = 3, researched = false, enabled = false, visible = true,
    maximum = UINT32_MAX, bonus = 0.02, saved_progress = 0.27}, mode.label .. " player")
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("disabled intermediate queued successor research")
  end
  if state.destination_lab_completions ~= nil or state.destination_science_accounting ~= nil then
    fail("disabled intermediate retained successor lab work")
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  assert_acceleration(technology(game.forces.player, GEAR))
  return player
end

local function assert_disabled_stage_witness(state, mode)
  assert_source_witness(state, mode)
  if state.phase ~= "disabled-intermediate-completed"
      or state.disabled_stage_case ~= CROSS_ENGINE_DISABLED_CASE
      or state.disabled_stage_fixture ~= "0.6.0"
      or state.disabled_stage_observed ~= true
      or type(state.disabled_stage_player) ~= "table"
      or type(state.disabled_stage_foreign) ~= "table"
      or state.disabled_stage_destination_lab_completions ~= 0
      or state.disabled_stage_queue_entries ~= 0 then
    fail("required disabled intermediate witness is absent or malformed")
  end
  assert_status(state.disabled_stage_player, {level = 3, researched = false, enabled = false, visible = true,
    maximum = UINT32_MAX, bonus = 0.02, saved_progress = 0.27}, "disabled intermediate saved player")
  if state.disabled_stage_foreign.current ~= state.foreign_queue.current
      or #state.disabled_stage_foreign.queue ~= #state.foreign_queue.queue
      or state.disabled_stage_foreign.queue[1] ~= state.foreign_queue.queue[1]
      or not close(state.disabled_stage_foreign.progress, state.foreign_queue.progress) then
    fail("disabled intermediate foreign witness differs")
  end
end

local function assert_completed(state, label)
  if state.destination_lab_completions ~= 1 then fail("successor did not finish exactly one further lab level") end
  local player = status(game.forces.player)
  assert_status(player, {level = 4, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = 0.03}, label .. " post-lab player")
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("successor gear research queue survived native completion")
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  local inventory = lab(state)
  local expected_units = state.destination_science_units_before
  local accounting = state.destination_science_accounting
  if type(expected_units) ~= "table" or type(accounting) ~= "table" then
    fail("successor native science accounting witness is absent")
  end
  state.destination_science_units_after = state.destination_science_units_after or {}
  for _, item in ipairs(SCIENCE) do
    local expected = expected_units[item] - accounting.consumed_units
    local observed = science_units(inventory, item, "successor post-lab")
    if not close(observed, expected) then
      fail("successor real lab consumption differs for " .. item
        .. ": observed_units=" .. tostring(observed) .. " expected_units=" .. tostring(expected)
        .. " consumed_units=" .. tostring(accounting.consumed_units)
        .. " remaining_ticks=" .. tostring(accounting.remaining_ticks))
    end
    local prior = state.destination_science_units_after[item]
    if prior ~= nil and not close(prior, observed) then
      fail("successor cold reload changed native science units for " .. item)
    end
    state.destination_science_units_after[item] = observed
  end
  return player
end

local function marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = state.destination_case, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir, destination_mir = script.active_mods["more-infinite-research"],
      source_actual_lab_completions = state.actual_lab_completions,
      destination_actual_lab_completions = state.destination_lab_completions,
      milestone = state.milestone, next_level = player.level, productivity_bonus = player.bonus,
      player_enabled = player.enabled, player_visible_when_disabled = player.visible,
      foreign_queue_progress = state.foreign_queue.progress,
      science_consumed_units = state.destination_science_accounting.consumed_units,
      science_remaining_ticks = state.destination_science_accounting.remaining_ticks,
      science_processing_ticks = state.destination_processing_ticks,
      science_elapsed_ticks = state.destination_elapsed_ticks,
      science_units_after = state.destination_science_units_after,
      on_load_read_only = stage == "reload",
    },
  }))
end

local function disabled_marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = state.disabled_stage_case, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir, destination_mir = script.active_mods["more-infinite-research"],
      source_actual_lab_completions = state.actual_lab_completions,
      destination_actual_lab_completions = state.disabled_stage_destination_lab_completions,
      disabled_intermediate_observed = state.disabled_stage_observed,
      next_level = player.level, productivity_bonus = player.bonus,
      player_enabled = player.enabled, player_visible_when_disabled = player.visible,
      saved_progress = player.saved_progress, foreign_queue_progress = state.foreign_queue.progress,
      foreign_disabled = status(game.forces[state.foreign_force_index]).enabled == false,
      on_load_read_only = stage == "reload",
    },
  }))
end

local function finish_diagnostic(state, accounting)
  local observed = {}
  local inventory = lab(state)
  for _, item in ipairs(SCIENCE) do
    observed[item] = science_units(inventory, item, "successor finish")
  end
  log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json({
    stage = "finish-before-assertion", case = state.destination_case,
    research_start_tick = state.destination_research_start_tick,
    research_finished_tick = game.tick,
    raw_elapsed_ticks = game.tick - state.destination_research_start_tick,
    processing_ticks = state.destination_processing_ticks,
    expected_processing_ticks = type(accounting) == "table" and accounting.remaining_ticks or false,
    science_units_observed = observed,
  }))
end

script.on_configuration_changed(function()
  local mode = destination_mode()
  local startup = settings.startup
  if startup["ips-max-level-research_gears"].value ~= 40
      or startup["ips-effect-per-level-research_gears"].value ~= 1
      or startup["mir-settings-profile-import"].value ~= "" then
    fail("successor fixture settings are not the verified positive-cap relaxation")
  end
  if mode.disabled_intermediate and startup["ips-enable-research_gears"].value ~= false then
    fail("disabled intermediate did not retain the disabled owned family setting")
  end
  if mode.reenabled and startup["ips-enable-research_gears"].value ~= true then
    fail("re-enabled successor did not retain the owned family setting")
  end
  local state = storage[KEY]
  if mode.disabled_intermediate then
    local player = assert_disabled_intermediate(state, mode)
    state.disabled_stage_case = mode.case
    state.disabled_stage_fixture = script.active_mods[FIXTURE]
    state.disabled_stage_player = copy_status(player)
    state.disabled_stage_foreign = copy_queue(state.foreign_queue)
    state.disabled_stage_destination_lab_completions = 0
    state.disabled_stage_queue_entries = #game.forces.player.research_queue
    state.disabled_stage_observed = true
    state.phase = "disabled-intermediate-completed"
    disabled_marker("initial", state)
    game.server_save(SAVE)
    return
  end
  if mode.reenabled then assert_disabled_stage_witness(state, mode) end
  assert_restored(state, mode) -- required before this fixture queues any successor lab work.
  local inventory = lab(state)
  local before_units = {}
  for _, item in ipairs(SCIENCE) do
    local prior = science_units(inventory, item, "successor pre-insert")
    local inserted = inventory.insert{name = item, count = DESTINATION_PACKS}
    if inserted ~= DESTINATION_PACKS then fail("could not insert successor science " .. item) end
    local observed = science_units(inventory, item, "successor pre-lab")
    local expected = prior + DESTINATION_PACKS
    if not close(observed, expected) then
      fail("fixture-added normal-durability science changed for " .. item
        .. ": observed_units=" .. tostring(observed) .. " expected_units=" .. tostring(expected))
    end
    before_units[item] = observed
  end
  state.destination_science_units_before = before_units
  state.destination_science_units_after = nil
  state.destination_science_accounting = nil
  state.destination_case = mode.case
  state.destination_label = mode.label
  state.destination_lab_completions = 0
  state.phase = "await-successor-lab"
  state.deadline_tick = game.tick + DEADLINE
  if game.forces.player.add_research(technology(game.forces.player, GEAR)) ~= true then
    fail("could not queue successor native gear research")
  end
  if #game.forces.player.research_queue ~= 1 then fail("successor gear research was not queued singly") end
  state.destination_science_accounting = expected_science_consumption(game.forces.player,
    technology(game.forces.player, GEAR), state.lab, 0.27)
  state.destination_research_start_tick = game.tick
  state.destination_processing_ticks = 0
  state.destination_elapsed_ticks = nil
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-successor-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= GEAR then return end
  local accounting = state.destination_science_accounting
  local elapsed = game.tick - state.destination_research_start_tick
  finish_diagnostic(state, accounting)
  if type(accounting) ~= "table" or state.destination_processing_ticks ~= accounting.remaining_ticks then
    fail("successor real lab processing ticks differ")
  end
  state.destination_elapsed_ticks = elapsed
  state.destination_lab_completions = state.destination_lab_completions + 1
  if state.destination_lab_completions ~= 1 then fail("successor completed duplicate gear level") end
  state.phase = "await-successor-observation"
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" and type(state.successor_player) == "table" then
    -- Do not touch LuaGameScript or LuaForce from on_load.  This local witness
    -- is read from fixture-owned durable state and checked on the next tick.
    loaded_snapshot = {player = copy_status(state.successor_player), foreign = copy_queue(state.foreign_queue),
      source = state.actual_lab_completions, destination = state.destination_lab_completions}
  elseif type(state) == "table" and state.phase == "disabled-intermediate-completed"
      and type(state.disabled_stage_player) == "table" and type(state.disabled_stage_foreign) == "table" then
    loaded_snapshot = {disabled = true, player = copy_status(state.disabled_stage_player),
      foreign = copy_queue(state.disabled_stage_foreign), source = state.actual_lab_completions,
      destination = state.disabled_stage_destination_lab_completions}
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor fixture storage is absent") end
  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      local player = assert_completed(state, state.destination_label)
      assert_status(player, loaded_snapshot.player, "successor cold reload player")
      assert_foreign(game.forces[state.foreign_force_index], loaded_snapshot.foreign)
      if state.actual_lab_completions ~= loaded_snapshot.source
          or state.destination_lab_completions ~= loaded_snapshot.destination then
        fail("cold reload changed recorded lab completions")
      end
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if state.phase == "disabled-intermediate-completed" then
    if loaded_snapshot and loaded_snapshot.disabled and not reload_logged then
      local mode = destination_mode()
      if not mode.disabled_intermediate then fail("disabled intermediate loaded under the wrong successor stage") end
      local player = assert_disabled_intermediate(state, mode)
      assert_status(player, loaded_snapshot.player, "disabled intermediate cold reload player")
      assert_foreign(game.forces[state.foreign_force_index], loaded_snapshot.foreign)
      if state.actual_lab_completions ~= loaded_snapshot.source
          or state.disabled_stage_destination_lab_completions ~= loaded_snapshot.destination then
        fail("disabled intermediate cold reload changed lab completions")
      end
      disabled_marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("successor lab did not complete one gear level") end
  lab(state)
  if state.phase == "await-successor-lab" then
    state.destination_processing_ticks = state.destination_processing_ticks + 1
  end
  if state.phase == "await-successor-observation" then
    state.successor_player = copy_status(assert_completed(state, state.destination_label))
    state.phase = "completed"
    marker("initial", state)
    game.server_save(SAVE)
  end
end)
