local KEY = "mir5_f200_legacy_worker"
local MIR5_CASE = "f200-positive-legacy-worker"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-f200-legacy-worker"
local WORKER = "worker-robots-speed-6"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-f200-legacy-worker-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "space-science-pack",
}
local UINT32_MAX = 4294967295
local MODIFIER = 0.65
local LAB_ENERGY = 100000000
local DESTINATION_PACKS = 8
local DEADLINE = 18000

local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-f200-legacy-worker-successor] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number"
    and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function status(force)
  local value = technology(force, WORKER)
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = force.worker_robots_speed_modifier, saved_progress = value.saved_progress}
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
    fail(label .. " native worker state differs")
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

local function assert_foreign(force, expected, baseline)
  if force == nil or force.valid == false or force.name ~= FOREIGN then fail("foreign force witness is absent") end
  assert_status(status(force), {level = 6, researched = false, enabled = false, visible = false,
    maximum = UINT32_MAX, bonus = baseline, saved_progress = 0}, "foreign native worker")
  local current = queue_snapshot(force)
  if current.current ~= PROBE or #current.queue ~= 1 or current.queue[1] ~= PROBE
      or not close(current.progress, 0.42) then fail("foreign worker queue or progress changed") end
  if type(expected) ~= "table" or expected.current ~= current.current or #expected.queue ~= #current.queue
      or expected.queue[1] ~= current.queue[1] or not close(expected.progress, current.progress) then
    fail("foreign native worker source queue witness differs")
  end
  return current
end

local function lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("source player native worker lab is absent") end
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("source player native worker lab has no power") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("source player native worker lab inventory is absent") end
  return inventory
end

local function assert_native_owner(value)
  if value.name ~= WORKER or value.prototype.max_level ~= UINT32_MAX
      or value.prototype.visible_when_disabled ~= false
      or value.level < 8 or value.researched then
    fail("F200 native worker tail is absent or regressed")
  end
  local effects = value.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "worker-robot-speed"
      or not close(effects[1].modifier, MODIFIER) then
    fail("F200 native worker effect differs")
  end
end

local function science_units(inventory, item, label)
  local total, stacks = 0, 0
  local prototype = prototypes.item[item]
  local science_type = script.active_mods.base == "2.1.23" and "item" or "tool"
  if prototype == nil then
    fail(label .. " native science item prototype is absent: " .. item)
  end
  if prototype.type ~= science_type then fail(label .. " native science prototype type changed for " .. item) end
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == item then
      local quality = stack.quality
      if quality == nil or quality.name ~= "normal" then
        fail(label .. " native science quality changed for " .. item)
      end
      if stack.type ~= science_type or stack.is_tool ~= (science_type == "tool") then
        fail(label .. " native science stack type changed for " .. item)
      end
      if type(stack.count) ~= "number" or stack.count < 1 or stack.count % 1 ~= 0 then
        fail(label .. " native science count changed for " .. item)
      end
      if science_type == "tool" then
        if type(prototype.get_durability) ~= "function" then fail(label .. " native tool durability API is absent: " .. item) end
        local maximum = prototype.get_durability(quality)
        local durability = stack.durability
        if not close(maximum, 1) or type(durability) ~= "number"
            or durability <= 0 or durability > maximum then
          fail(label .. " native science durability changed for " .. item)
        end
        total = total + stack.count - 1 + durability / maximum
      else
        -- Ordinary F210 items spend a whole item for a partial one-unit lab
        -- completion. Never read either tool-only durability API on this arm.
        total = total + stack.count
      end
      stacks = stacks + 1
    end
  end
  if stacks == 0 then fail(label .. " native science stack is absent for " .. item) end
  return total
end

local function expected_science_consumption(force, value, lab_entity, saved_progress)
  if force.current_research ~= value or #force.research_queue ~= 1 then
    fail("successor native worker research is not singly current")
  end
  local progress = force.research_progress
  if not close(progress, saved_progress) then
    fail("successor native worker saved investment did not become current research")
  end
  local quality = lab_entity.quality
  if quality == nil or quality.name ~= "normal" then fail("successor native worker lab quality is not normal") end
  local prototype = lab_entity.prototype
  if prototype == nil or type(prototype.get_researching_speed) ~= "function" then
    fail("successor native worker lab researching speed is absent")
  end
  local researching_speed = prototype.get_researching_speed(quality)
  local laboratory_speed, productivity = force.laboratory_speed_modifier, force.laboratory_productivity_bonus
  if not close(researching_speed, 1) or not close(laboratory_speed, 0) or not close(productivity, 0) then
    fail("successor native worker lab speed or productivity fixture input changed")
  end
  local modules = lab_entity.get_module_inventory and lab_entity.get_module_inventory()
  if modules ~= nil then
    for index = 1, #modules do
      if modules[index].valid_for_read then fail("successor native worker lab has a module") end
    end
  end
  local energy = value.research_unit_energy
  local work_per_tick = researching_speed * (1 + laboratory_speed)
  local remaining_work = (1 - progress) * energy
  if type(energy) ~= "number" or energy <= 0 or work_per_tick <= 0 or remaining_work <= 0 then
    fail("successor native worker research timing differs")
  end
  local ticks = math.ceil(remaining_work / work_per_tick)
  local consumed_units = ticks * work_per_tick / energy
  if ticks <= 0 or consumed_units <= 0 or consumed_units > 1 then fail("successor native worker science timing differs") end
  return {progress = progress, energy = energy, researching_speed = researching_speed,
    laboratory_speed = laboratory_speed, remaining_work = remaining_work, remaining_ticks = ticks,
    consumed_units = consumed_units,
    science_type = script.active_mods.base == "2.1.23" and "item" or "tool",
    inventory_consumed_units = script.active_mods.base == "2.1.23" and 1 or consumed_units}
end

local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not retain one-unit one-second native worker research")
  end
  for _, item in ipairs(SCIENCE) do
    local found = false
    for _, ingredient in ipairs(value.research_unit_ingredients) do
      if ingredient.name == item and ingredient.amount == 1 then found = true end
    end
    if not found then fail("native worker science is absent: " .. item) end
  end
end

local function assert_source_witness(state)
  if state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0"
      or state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs"
      or type(state.foreign_queue) ~= "table" or type(state.player_with_independent) ~= "number"
      or type(state.foreign_baseline) ~= "number" or type(state.player_cap) ~= "table"
      or not close(state.player_cap.saved_progress, 0.27) then
    fail("published native-worker source witness is absent or malformed")
  end
end

local function assert_restored(state, independently_observed_bonus, expected_enabled)
  assert_source_witness(state)
  if expected_enabled == nil then expected_enabled = true end
  local player = status(game.forces.player)
  -- The source controller captured the positive-cap presentation value after
  -- its data-stage patch. MIR5 restores that owned force presentation even
  -- though the successor prototype itself keeps the Base default.
  assert_status(player, {level = 8, researched = false, enabled = expected_enabled, visible = true,
    maximum = UINT32_MAX, bonus = independently_observed_bonus or state.player_with_independent + 2 * MODIFIER,
    saved_progress = 0.27}, "MIR5 restored native worker")
  assert_native_owner(technology(game.forces.player, WORKER))
  assert_acceleration(technology(game.forces.player, WORKER))
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue, state.foreign_baseline)
  return player
end

local function assert_held_inventory(state)
  local held = state.finite_hold_witness
  if type(held) ~= "table" or type(held.science_units) ~= "table"
      or state.lab == nil or state.lab.valid == false then fail("finite hold inventory witness is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("finite hold lab inventory is absent") end
  for _, item in ipairs(SCIENCE) do
    if not close(science_units(inventory, item, "finite hold"), held.science_units[item]) then
      fail("finite hold changed science units for " .. item)
    end
  end
end

local function assert_held(state)
  local held, offset = state.finite_hold_witness, state.fixture_owned_offset
  if state.phase ~= "finite-held" or state.destination_lab_completions ~= 0
      or type(held) ~= "table" or held.schema ~= 1 or held.maximum ~= 7
      or held.level ~= 8 or held.enabled ~= false or held.visible ~= true
      or not close(held.bonus, 3.823) or not close(held.saved_progress, .27)
      or type(offset) ~= "table" or offset.stage ~= "hold" or not close(offset.restored_total, 3.823) then
    fail("finite hold witness changed")
  end
  local player = assert_restored(state, nil, false)
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("finite hold unexpectedly queued player research")
  end
  assert_held_inventory(state)
  return player
end

local function assert_completed(state)
  if state.destination_lab_completions ~= 1 then fail("successor did not finish exactly one further native worker lab level") end
  local player = status(game.forces.player)
  assert_status(player, {level = 9, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = state.player_with_independent + 3 * MODIFIER},
    "MIR5 post-lab native worker")
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("successor native worker research queue survived completion")
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue, state.foreign_baseline)
  local inventory = lab(state)
  local expected_units = state.destination_science_units_before
  local accounting = state.destination_science_accounting
  if type(expected_units) ~= "table" or type(accounting) ~= "table" then
    fail("successor native science accounting witness is absent")
  end
  state.destination_science_units_after = state.destination_science_units_after or {}
  for _, item in ipairs(SCIENCE) do
    local inventory_spent = accounting.inventory_consumed_units or accounting.consumed_units
    local expected = expected_units[item] - inventory_spent
    local observed = science_units(inventory, item, "successor post-lab")
    if not close(observed, expected) then
      fail("successor real native worker lab consumption differs for " .. item
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
    stage = stage, case = MIR5_CASE, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      source_mir = state.source_mir, destination_mir = script.active_mods["more-infinite-research"],
      source_actual_lab_completions = state.actual_lab_completions,
      destination_actual_lab_completions = state.destination_lab_completions,
      native_owner = WORKER, native_effect_modifier = MODIFIER,
      milestone = state.milestone, next_level = player.level,
      worker_speed_modifier = player.bonus, independent_modifier_baseline = state.player_with_independent,
      player_enabled = player.enabled, player_visible_when_disabled = player.visible,
      foreign_queue_progress = state.foreign_queue.progress,
      science_consumed_units = state.destination_science_accounting.consumed_units,
      science_inventory_consumed_units = state.destination_science_accounting.inventory_consumed_units
        or state.destination_science_accounting.consumed_units,
      science_type = state.destination_science_accounting.science_type or "tool",
      science_remaining_ticks = state.destination_science_accounting.remaining_ticks,
      science_processing_ticks = state.destination_processing_ticks,
      science_elapsed_ticks = state.destination_elapsed_ticks,
      science_units_after = state.destination_science_units_after,
      fixture_owned_offset = state.fixture_owned_offset,
      finite_hold_witness = state.finite_hold_witness,
      on_load_read_only = stage == "reload",
    },
  }))
end

local function hold_configuration(fixture_version)
  local active = script.active_mods
  local f200 = fixture_version == "0.5.0" and active.base == "2.0.77"
    and active["more-infinite-research"] == "5.0.20000"
  local f210 = fixture_version == "0.7.0" and active.base == "2.1.23"
    and active["more-infinite-research"] == "5.0.21000"
  if not (f200 or f210) or active[FIXTURE] ~= fixture_version or active["space-age"] ~= nil
      or active["a-mir-fixture-worker-entry"] ~= "0.1.0"
      or settings.startup["mir-max-level-worker-robots-speed"].value ~= 7
      or settings.startup["mir-settings-profile-import"].value ~= "" then fail("finite hold tuple differs") end
  local state = storage[KEY]
  local player = assert_restored(state, nil, false)
  if state.phase ~= "completed" or state.destination_lab_completions ~= nil
      or type(state.fixture_owned_offset) ~= "table" or state.fixture_owned_offset.stage ~= "hold" then
    fail("finite hold requires the original source after its explicit owned contribution")
  end
  local units, inventory = {}, lab(state)
  for _, item in ipairs(SCIENCE) do units[item] = science_units(inventory, item, "first finite hold") end
  state.finite_hold_witness = {schema=1, maximum=7, level=player.level, enabled=player.enabled,
    visible=player.visible, bonus=player.bonus, saved_progress=player.saved_progress, science_units=units}
  state.destination_lab_completions = 0
  state.destination_science_accounting = {consumed_units=0, inventory_consumed_units=0, remaining_ticks=0,
    science_type=active.base == "2.1.23" and "item" or "tool"}
  state.destination_science_units_after = units
  state.destination_processing_ticks, state.destination_elapsed_ticks = 0, 0
  state.phase = "finite-held"
  state.held_player = copy_status(assert_held(state))
  loaded_snapshot, reload_logged = nil, false
end

local function finish_diagnostic(state, accounting)
  local observed = {}
  local inventory = lab(state)
  for _, item in ipairs(SCIENCE) do
    observed[item] = science_units(inventory, item, "successor native worker finish")
  end
  log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json({
    stage = "finish-before-assertion", case = MIR5_CASE,
    research_start_tick = state.destination_research_start_tick,
    research_finished_tick = game.tick,
    raw_elapsed_ticks = game.tick - state.destination_research_start_tick,
    processing_ticks = state.destination_processing_ticks,
    expected_processing_ticks = type(accounting) == "table" and accounting.remaining_ticks or false,
    science_units_observed = observed,
  }))
end

local function on_configuration_changed(_event, fixture_version)
  fixture_version = fixture_version or "0.2.0"
  local active = script.active_mods
  local f200 = (fixture_version == "0.2.0" or fixture_version == "0.3.0" or fixture_version == "0.6.0")
    and active.base == "2.0.77" and active["more-infinite-research"] == "5.0.20000"
  local f210 = (fixture_version == "0.4.0" or fixture_version == "0.8.0") and active.base == "2.1.23"
    and active["more-infinite-research"] == "5.0.21000" and active["a-mir-fixture-worker-entry"] == "0.1.0"
  if not (f200 or f210) or active[FIXTURE] ~= fixture_version or active["space-age"] ~= nil then
    fail("unsupported exact native-worker successor tuple")
  end
  if settings.startup["mir-max-level-worker-robots-speed"].value ~= 40
      or settings.startup["mir-settings-profile-import"].value ~= "" then
    fail("successor fixture settings are not the verified native-worker cap relaxation")
  end
  local state = storage[KEY]
  if (fixture_version == "0.6.0" or fixture_version == "0.8.0")
      and (state.phase ~= "finite-held" or type(state.fixture_owned_offset) ~= "table"
        or state.fixture_owned_offset.stage ~= "relax") then fail("finite relaxation requires its exact held save") end
  assert_restored(state) -- Required before this fixture queues any successor lab work.
  loaded_snapshot, reload_logged = nil, false
  local inventory = lab(state)
  local before_units = {}
  for _, item in ipairs(SCIENCE) do
    local prior = science_units(inventory, item, "successor pre-insert")
    local inserted = inventory.insert{name = item, count = DESTINATION_PACKS}
    if inserted ~= DESTINATION_PACKS then fail("could not insert successor worker science " .. item) end
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
  state.destination_lab_completions = 0
  state.phase = "await-successor-lab"
  state.deadline_tick = game.tick + DEADLINE
  if game.forces.player.add_research(technology(game.forces.player, WORKER)) ~= true then
    fail("could not queue successor native worker research")
  end
  if #game.forces.player.research_queue ~= 1 then fail("successor native worker research was not queued singly") end
  state.destination_science_accounting = expected_science_consumption(game.forces.player,
    technology(game.forces.player, WORKER), state.lab, 0.27)
  state.destination_research_start_tick = game.tick
  state.destination_processing_ticks = 0
  state.destination_elapsed_ticks = nil
end
script.on_configuration_changed(on_configuration_changed)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-successor-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= WORKER then return end
  local accounting = state.destination_science_accounting
  local elapsed = game.tick - state.destination_research_start_tick
  finish_diagnostic(state, accounting)
  if type(accounting) ~= "table" or state.destination_processing_ticks ~= accounting.remaining_ticks then
    fail("successor real native worker lab processing ticks differ")
  end
  state.destination_elapsed_ticks = elapsed
  state.destination_lab_completions = state.destination_lab_completions + 1
  if state.destination_lab_completions ~= 1 then fail("successor completed duplicate native worker level") end
  state.phase = "await-successor-observation"
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "finite-held" and type(state.held_player) == "table" then
    loaded_snapshot = {player=copy_status(state.held_player), foreign=copy_queue(state.foreign_queue),
      source=state.actual_lab_completions, destination=state.destination_lab_completions,
      foreign_baseline=state.foreign_baseline}
  elseif type(state) == "table" and state.phase == "completed" and type(state.successor_player) == "table" then
    loaded_snapshot = {player = copy_status(state.successor_player), foreign = copy_queue(state.foreign_queue),
      source = state.actual_lab_completions, destination = state.destination_lab_completions,
      foreign_baseline = state.foreign_baseline}
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor native worker fixture storage is absent") end
  if state.phase == "finite-held" then
    local player = assert_held(state)
    if loaded_snapshot and not reload_logged then
      assert_status(player, loaded_snapshot.player, "finite hold cold reload")
      if state.actual_lab_completions ~= loaded_snapshot.source
          or state.destination_lab_completions ~= loaded_snapshot.destination then fail("finite hold changed lab counts") end
      marker("reload", state)
      reload_logged = true
    elseif not loaded_snapshot and not reload_logged then
      marker("initial", state)
      game.server_save(SAVE)
      reload_logged = true
    end
    return
  end
  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      local player = assert_completed(state)
      assert_status(player, loaded_snapshot.player, "successor cold reload native worker")
      assert_foreign(game.forces[state.foreign_force_index], loaded_snapshot.foreign, loaded_snapshot.foreign_baseline)
      if state.actual_lab_completions ~= loaded_snapshot.source
          or state.destination_lab_completions ~= loaded_snapshot.destination then
        fail("cold reload changed recorded native worker lab completions")
      end
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("successor lab did not complete one native worker level") end
  lab(state)
  if state.phase == "await-successor-lab" then
    state.destination_processing_ticks = state.destination_processing_ticks + 1
  end
  if state.phase == "await-successor-observation" then
    state.successor_player = copy_status(assert_completed(state))
    state.phase = "completed"
    marker("initial", state)
    game.server_save(SAVE)
  end
end)

return {configuration_changed=on_configuration_changed, assert_restored=assert_restored,
  hold_configuration=hold_configuration, assert_held_inventory=assert_held_inventory}
