local KEY = "mir5_native_scripted_effects"
local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE = "recipe-prod-research_spoilage_preservation-1"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "military-science-pack",
  "chemical-science-pack", "production-science-pack", "utility-science-pack",
  "space-science-pack", "metallurgic-science-pack", "agricultural-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack"
}
local GROWTH_TICKS = 18000
local EXTERNAL_SPOILAGE_BASELINE = 2
local EFFECT_PERCENT = 1
local SPOILAGE_ITEM_TICKS = 600
local INITIAL_SCIENCE_PACK_COUNT = 16
-- The data-stage prototype declares this immutable one-hour base timer. A
-- stack's absolute spoil deadline is scaled by the current global modifier.
local AGRICULTURAL_SCIENCE_PACK_PROTOTYPE_TICKS = 216000
local COMPLETED_RESEARCH_COUNT = 5
local AGRICULTURAL_SCIENCE_PACK_MINIMUM_CONSUMED = COMPLETED_RESEARCH_COUNT + 1
local AGRICULTURAL_SCIENCE_PACK_MAXIMUM_CONSUMED = COMPLETED_RESEARCH_COUNT * 2
local DEADLINE_TICKS = 18000
local loaded, reported

local function fail(message)
  error("[mir5-scripted-effects-native] " .. message)
end

local function close(actual, expected, tolerance)
  return type(actual) == "number" and math.abs(actual - expected) <= (tolerance or 0.0000001)
end

local function technology(force, name)
  local value = force.technologies[name]
  if not value then fail("missing generated technology " .. name) end
  return value
end

local function start_research(force, name)
  local value = technology(force, name)
  if value.enabled ~= true then fail("could not start disabled research " .. name) end
  if force.current_research ~= nil then fail("attempted to overlap native research") end
  if not force.add_research(value) then fail("could not start real lab research " .. name) end
end

local function assert_capped(force, name, completed)
  local value = technology(force, name)
  if value.level ~= completed + 1 or value.researched or value.enabled
      or not value.visible_when_disabled then
    fail(name .. " did not stop at its configured finite cap")
  end
end

local function assert_no_pending_research(force)
  if force.current_research ~= nil then fail("completed scripted research remained active") end
  for _, queued in ipairs(force.research_queue) do
    if queued.name == AGRICULTURE or queued.name == SPOILAGE then
      fail("completed scripted research remained queued")
    end
  end
end

local function named_stack(inventory, name)
  for slot = 1, #inventory do
    local stack = inventory[slot]
    if stack and stack.valid_for_read and stack.name == name then return stack end
  end
end

local function consumption_summary(consumed)
  local rows = {}
  for _, name in ipairs(SCIENCE) do
    rows[#rows + 1] = name .. "=" .. tostring(consumed[name])
  end
  return table.concat(rows, ",")
end

local function assert_lab_consumption(state)
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end

  local observed = {completion_tick = game.tick, consumed = {}}
  for _, name in ipairs(SCIENCE) do
    observed.consumed[name] = INITIAL_SCIENCE_PACK_COUNT - inventory.get_item_count(name)
  end

  for _, name in ipairs(SCIENCE) do
    if name ~= "agricultural-science-pack" and observed.consumed[name] ~= COMPLETED_RESEARCH_COUNT then
      fail("science consumption differs for " .. name
        .. ": actual=" .. tostring(observed.consumed[name])
        .. " expected=" .. tostring(COMPLETED_RESEARCH_COUNT)
        .. " completion_tick=" .. tostring(game.tick)
        .. " all_consumed=" .. consumption_summary(observed.consumed))
    end
  end

  local agriculture_stack = named_stack(inventory, "agricultural-science-pack")
  if not agriculture_stack or type(agriculture_stack.spoil_tick) ~= "number" then
    fail("agricultural science input is absent after completed research: completion_tick=" .. tostring(game.tick)
      .. " consumed=" .. consumption_summary(observed.consumed))
  end
  observed.agricultural_science_lab_fill_tick = state.agricultural_science_lab_fill_tick
  observed.agricultural_science_initial_spoil_tick = state.agricultural_science_initial_spoil_tick
  observed.agricultural_science_initial_runtime_ticks = state.agricultural_science_initial_runtime_ticks
  observed.agricultural_science_remaining_ticks = agriculture_stack.spoil_tick - game.tick
  observed.agricultural_science_remaining_input = inventory.get_item_count("agricultural-science-pack")
  observed.agricultural_science_completion_spoil_tick = agriculture_stack.spoil_tick
  observed.agricultural_science_completion_modifier = game.difficulty_settings.spoil_time_modifier

  local consumed = observed.consumed["agricultural-science-pack"]
  if consumed < AGRICULTURAL_SCIENCE_PACK_MINIMUM_CONSUMED
      or consumed > AGRICULTURAL_SCIENCE_PACK_MAXIMUM_CONSUMED then
    fail("fresh agricultural science consumption is outside the native bounded witness: actual="
      .. tostring(consumed)
      .. " expected=" .. tostring(AGRICULTURAL_SCIENCE_PACK_MINIMUM_CONSUMED)
      .. ".." .. tostring(AGRICULTURAL_SCIENCE_PACK_MAXIMUM_CONSUMED)
      .. " initial_spoil_tick=" .. tostring(state.agricultural_science_initial_spoil_tick)
      .. " remaining_ticks=" .. tostring(observed.agricultural_science_remaining_ticks)
      .. " completion_tick=" .. tostring(game.tick)
      .. " all_consumed=" .. consumption_summary(observed.consumed))
  end

  if not state.lab_observation then
    -- The five research points draw one durability each. The ordinary lab has
    -- the native 100% drain rate. The completed event must follow insertion,
    -- so each agricultural pack is no longer fully fresh and five whole packs
    -- cannot supply five full durability points. A pack still above half
    -- freshness can require at most two physical packs per point.
    if observed.completion_tick <= state.agricultural_science_lab_fill_tick then
      fail("agricultural science completed without elapsed freshness time: fill_tick="
        .. tostring(state.agricultural_science_lab_fill_tick)
        .. " completion_tick=" .. tostring(observed.completion_tick))
    end
    if observed.agricultural_science_remaining_ticks
        <= state.agricultural_science_initial_runtime_ticks / 2 then
      fail("agricultural science was not still fresher than one half at completion: remaining_ticks="
        .. tostring(observed.agricultural_science_remaining_ticks)
        .. " initial_runtime_ticks=" .. tostring(state.agricultural_science_initial_runtime_ticks)
        .. " completion_tick=" .. tostring(game.tick))
    end
    state.lab_observation = observed
  else
    for _, name in ipairs(SCIENCE) do
      if state.lab_observation.consumed[name] ~= observed.consumed[name] then
        fail("lab input changed after research completed for " .. name
          .. ": initial=" .. tostring(state.lab_observation.consumed[name])
          .. " current=" .. tostring(observed.consumed[name])
          .. " completion_tick=" .. tostring(game.tick))
      end
    end
  end
end

local function assert_foreign_unresearched(state)
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.name ~= "mir5-scripted-effects-foreign" then
    fail("zero-research foreign force is absent")
  end
  for _, name in ipairs({AGRICULTURE, SPOILAGE}) do
    local value = technology(foreign, name)
    if value.level ~= 1 or value.researched then
      fail("foreign force was given scripted research " .. name)
    end
  end
  return foreign
end

local function assert_plants(state)
  local player_plant, foreign_plant = state.player_plant, state.foreign_plant
  if not player_plant or not player_plant.valid or not foreign_plant or not foreign_plant.valid then
    fail("native planted seed witness is absent")
  end
  if player_plant.name ~= "yumako-tree" or foreign_plant.name ~= "yumako-tree" then
    fail("tower planted an unexpected native plant")
  end
  if player_plant.prototype.growth_ticks ~= GROWTH_TICKS
      or foreign_plant.prototype.growth_ticks ~= GROWTH_TICKS then
    fail("native yumako growth tick contract changed")
  end
  if player_plant.tick_grown ~= state.player_tick_grown
      or foreign_plant.tick_grown ~= state.foreign_tick_grown then
    fail("plant tick_grown changed after the tower-planted event")
  end
  if state.player_remaining ~= math.floor(GROWTH_TICKS / (1.01 ^ 2))
      or state.foreign_remaining ~= GROWTH_TICKS then
    fail("stored agricultural growth witness is malformed")
  end
end

local function assert_spoilage(state)
  local expected_modifier = EXTERNAL_SPOILAGE_BASELINE * (1.01 ^ 3)
  if not close(game.difficulty_settings.spoil_time_modifier, expected_modifier) then
    fail("global spoil time modifier did not retain baseline two and three completed levels")
  end
  if not close(state.spoil_modifier, expected_modifier) then
    fail("stored global spoilage modifier differs")
  end
  local expected_ticks = SPOILAGE_ITEM_TICKS * expected_modifier
  if math.abs(state.player_spoil_interval - expected_ticks) > 1
      or math.abs(state.foreign_spoil_interval - expected_ticks) > 1
      or math.abs(state.player_spoil_interval - state.foreign_spoil_interval) > 1 then
    fail("native spoil clock intervals do not share the scaled global modifier")
  end
  for _, row in ipairs({
    {chest = state.player_chest, tick = state.player_spoil_tick, label = "player"},
    {chest = state.foreign_chest, tick = state.foreign_spoil_tick, label = "foreign"}
  }) do
    local inventory = row.chest and row.chest.valid and row.chest.get_inventory(defines.inventory.chest)
    local stack = inventory and inventory[1]
    if not stack or not stack.valid_for_read or stack.name ~= "yumako" or stack.spoil_tick ~= row.tick then
      fail(row.label .. " native spoil clock did not preserve its observed tick")
    end
  end
end

local function assert_complete(state)
  local force = game.forces.player
  if state.agriculture_finished ~= 2 or state.spoilage_finished ~= 3 then
    fail("real labs did not complete the requested scripted levels")
  end
  assert_capped(force, AGRICULTURE, 2)
  assert_capped(force, SPOILAGE, 3)
  assert_no_pending_research(force)
  assert_lab_consumption(state)
  assert_foreign_unresearched(state)
  assert_plants(state)
  assert_spoilage(state)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "scripted-effects-native", stage = stage, status = "passed",
    witnesses = {
      profile = "space-age-f210",
      completed_research = {
        agricultural_growth_speed = state.agriculture_finished,
        spoilage_preservation = state.spoilage_finished
      },
      required_science_pack_names = SCIENCE,
      nonspoiling_required_science_pack_consumed_each = COMPLETED_RESEARCH_COUNT,
      agricultural_science_pack_freshness_witness = {
        prototype_spoil_ticks = AGRICULTURAL_SCIENCE_PACK_PROTOTYPE_TICKS,
        initial_runtime_modifier = EXTERNAL_SPOILAGE_BASELINE,
        initial_input_count = INITIAL_SCIENCE_PACK_COUNT,
        physical_consumption_minimum = AGRICULTURAL_SCIENCE_PACK_MINIMUM_CONSUMED,
        physical_consumption_maximum = AGRICULTURAL_SCIENCE_PACK_MAXIMUM_CONSUMED,
        observed = state.lab_observation
      },
      all_official_policy = true,
      named_space_gate = true,
      cap_disabled_after_completed_levels = {
        agricultural_growth_speed = 2,
        spoilage_preservation = 3
      },
      tower_surface = "nauvis",
      tower_pressure = state.surface_pressure,
      tower_seed = "yumako-seed",
      plant = "yumako-tree",
      native_growth_ticks = GROWTH_TICKS,
      trained_remaining_ticks = state.player_remaining,
      trained_expected_remaining_ticks = math.floor(GROWTH_TICKS / (1.01 ^ 2)),
      foreign_zero_research_remaining_ticks = state.foreign_remaining,
      tower_planted_events_observed_after_mir_callback = state.planted_events,
      external_spoilage_baseline = EXTERNAL_SPOILAGE_BASELINE,
      global_spoil_time_modifier = state.spoil_modifier,
      player_spoil_interval = state.player_spoil_interval,
      foreign_spoil_interval = state.foreign_spoil_interval,
      fixture_yumako_spoil_ticks = SPOILAGE_ITEM_TICKS,
      equal_native_spoil_clock_tolerance_ticks = 1,
      native_spoil_ticks_persisted = stage == "reload",
      on_load_read_only = stage == "reload",
      ordinary_tuning_qualified = false,
      recurring_native_effect_maintenance_qualified = false,
      gameplay_scope = "disposable-native-scripted-effects-only"
    }
  }))
end

local function set_yumako_soil(surface, center)
  local tiles = {}
  for x = center.x - 5, center.x + 5 do
    for y = center.y - 5, center.y + 5 do
      tiles[#tiles + 1] = {name = "natural-yumako-soil", position = {x = x, y = y}}
    end
  end
  surface.set_tiles(tiles)
  if surface.get_tile(center).name ~= "natural-yumako-soil" then
    fail("could not prepare natural yumako soil")
  end
end

local function create_tower(surface, center, force)
  local tower = surface.create_entity{name = "agricultural-tower", position = center, force = force}
  if not tower or not tower.valid then fail("could not create native agricultural tower") end
  tower.energy = 100000000
  return tower
end

local function insert_native_seed(tower)
  local inventory = tower.get_inventory(defines.inventory.agricultural_tower_input)
  if not inventory or inventory.insert{name = "yumako-seed", count = 1} ~= 1 then
    fail("could not insert native yumako seed into agricultural tower")
  end
end

local function create_spoilage_chest(surface, position, force)
  local chest = surface.create_entity{name = "wooden-chest", position = position, force = force}
  if not chest or not chest.valid then fail("could not create native spoilage chest") end
  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory or inventory.insert{name = "yumako", count = 1} ~= 1 then
    fail("could not insert native yumako into spoilage chest")
  end
  local stack = inventory[1]
  if not stack.valid_for_read or stack.name ~= "yumako" or type(stack.spoil_tick) ~= "number"
      or stack.spoil_tick <= game.tick then
    fail("native yumako stack did not expose a future spoil tick")
  end
  return chest, stack.spoil_tick - game.tick, stack.spoil_tick
end

local function begin_native_plants(state)
  local surface, player = game.surfaces.nauvis, game.forces.player
  local foreign = assert_foreign_unresearched(state)
  if not surface or surface.get_property("pressure") ~= 1000 then
    fail("Nauvis does not meet the native agricultural tower pressure contract")
  end
  local player_center, foreign_center = {x = 64, y = 0}, {x = -64, y = 0}
  set_yumako_soil(surface, player_center)
  set_yumako_soil(surface, foreign_center)
  state.surface_pressure = surface.get_property("pressure")
  -- Keep both owned tower identities and the planting phase visible before a
  -- seed reaches a native inventory. This also keeps the witness sound if an
  -- engine ever chooses to dispatch its native event synchronously.
  state.phase = "planting"
  state.player_tower = create_tower(surface, player_center, player)
  state.foreign_tower = create_tower(surface, foreign_center, foreign)
  state.player_tower_position, state.foreign_tower_position = player_center, foreign_center
  insert_native_seed(state.player_tower)
  insert_native_seed(state.foreign_tower)
end

local function begin_spoilage_clocks(state)
  local surface, player = game.surfaces.nauvis, game.forces.player
  local foreign = assert_foreign_unresearched(state)
  state.spoil_insert_tick = game.tick
  state.player_chest, state.player_spoil_interval, state.player_spoil_tick =
    create_spoilage_chest(surface, {x = 64, y = 12}, player)
  state.foreign_chest, state.foreign_spoil_interval, state.foreign_spoil_tick =
    create_spoilage_chest(surface, {x = -64, y = 12}, foreign)
  state.spoil_modifier = game.difficulty_settings.spoil_time_modifier
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["space-age"] ~= "2.1.23"
      or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("unexpected engine, Space Age, or player package")
  end
  if settings.startup["mir-science-pack-ingredient-policy"].value ~= "all-official"
      or settings.startup["ips-require-space-gate"].value ~= true then
    fail("fixture did not select all-official science and the named space gate")
  end
  for family, maximum in pairs({
    research_agricultural_growth_speed = 2,
    research_spoilage_preservation = 3
  }) do
    if settings.startup["ips-cost-base-" .. family].value ~= 1
        or settings.startup["ips-cost-linear-increment-" .. family].value ~= 0
        or settings.startup["ips-cost-growth-" .. family].value ~= 1
        or settings.startup["ips-max-level-" .. family].value ~= maximum
        or settings.startup["ips-research-time-" .. family].value ~= 1
        or settings.startup["ips-effect-per-level-" .. family].value ~= EFFECT_PERCENT then
      fail("unexpected accelerated scripted-effect settings for " .. family)
    end
  end

  game.speed = 16
  local surface = assert(game.surfaces.nauvis)
  surface.request_to_generate_chunks({x = 64, y = 0}, 1)
  surface.request_to_generate_chunks({x = -64, y = 0}, 1)
  surface.force_generate_chunk_requests()

  local force = game.forces.player
  force.enable_all_prototypes()
  for _, name in ipairs({AGRICULTURE, SPOILAGE}) do
    local value = technology(force, name)
    for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
    if value.level ~= 1 or value.researched then fail("fixture did not start at level one for " .. name) end
    value.enabled, value.visible_when_disabled = true, false
  end

  -- This write is independent of MIR and precedes every scripted spoilage
  -- completion. The later global result must retain it as baseline two.
  game.difficulty_settings.spoil_time_modifier = EXTERNAL_SPOILAGE_BASELINE

  local foreign = game.create_force("mir5-scripted-effects-foreign")
  foreign.enable_all_prototypes()

  local lab_position = force.get_spawn_position(surface)
  local lab = surface.create_entity{name = "lab", position = lab_position, force = force}
  if not lab or not lab.valid then fail("could not create real Space Age lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name = name, count = INITIAL_SCIENCE_PACK_COUNT} ~= INITIAL_SCIENCE_PACK_COUNT then
      fail("lab rejected " .. name)
    end
  end
  local agriculture_stack = named_stack(inventory, "agricultural-science-pack")
  local agricultural_science_initial_runtime_ticks =
    AGRICULTURAL_SCIENCE_PACK_PROTOTYPE_TICKS * EXTERNAL_SPOILAGE_BASELINE
  if not agriculture_stack or type(agriculture_stack.spoil_tick) ~= "number"
      or agriculture_stack.spoil_tick - game.tick ~= agricultural_science_initial_runtime_ticks then
    fail("new agricultural science input did not retain its native scaled spoil contract: actual="
      .. tostring(agriculture_stack and agriculture_stack.spoil_tick - game.tick)
      .. " expected=" .. tostring(agricultural_science_initial_runtime_ticks)
      .. " modifier=" .. tostring(game.difficulty_settings.spoil_time_modifier))
  end
  lab.energy = 100000000

  storage[KEY] = {
    phase = "researching",
    agriculture_finished = 0,
    spoilage_finished = 0,
    foreign_index = foreign.index,
    lab = lab,
    agricultural_science_lab_fill_tick = game.tick,
    agricultural_science_initial_spoil_tick = agriculture_stack.spoil_tick,
    agricultural_science_initial_runtime_ticks = agricultural_science_initial_runtime_ticks,
    deadline = game.tick + DEADLINE_TICKS
  }
  start_research(force, AGRICULTURE)
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research
      or event.research.force ~= game.forces.player then
    return
  end
  if event.research.name == AGRICULTURE then
    state.agriculture_finished = state.agriculture_finished + 1
    if state.agriculture_finished > 2 then fail("agriculture completed above the configured cap") end
    state.next_research = state.agriculture_finished < 2 and AGRICULTURE or SPOILAGE
  elseif event.research.name == SPOILAGE then
    state.spoilage_finished = state.spoilage_finished + 1
    if state.spoilage_finished > 3 then fail("spoilage completed above the configured cap") end
    if state.spoilage_finished < 3 then
      state.next_research = SPOILAGE
    else
      state.next_research = nil
      begin_native_plants(state)
    end
  end
end)

-- This callback observes the native event emitted by the two actual towers.
-- The fixture never invokes MIR internals or raises a synthetic tower event.
script.on_event(defines.events.on_tower_planted_seed, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "planting" or not event.tower or not event.plant then return end

  local kind
  if event.tower.valid and state.player_tower and event.tower.unit_number == state.player_tower.unit_number then
    kind = "player"
  elseif event.tower.valid and state.foreign_tower and event.tower.unit_number == state.foreign_tower.unit_number then
    kind = "foreign"
  else
    return
  end
  if event.plant.name ~= "yumako-tree" or event.plant.prototype.growth_ticks ~= GROWTH_TICKS then
    fail("native tower event did not carry the expected yumako plant")
  end
  local remaining = event.plant.tick_grown - event.tick
  if kind == "player" then
    local expected = math.floor(GROWTH_TICKS / (1.01 ^ 2))
    if state.player_plant or remaining ~= expected then
      fail("trained plant did not retain the MIR event-adjusted growth tick")
    end
    state.player_plant, state.player_tick_grown, state.player_remaining = event.plant, event.plant.tick_grown, remaining
  else
    if state.foreign_plant or remaining ~= GROWTH_TICKS then
      fail("zero-research foreign plant was unexpectedly accelerated")
    end
    state.foreign_plant, state.foreign_tick_grown, state.foreign_remaining = event.plant, event.plant.tick_grown, remaining
  end
  state.planted_events = (state.planted_events or 0) + 1
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.phase == "complete" and {
    agriculture_finished = state.agriculture_finished,
    spoilage_finished = state.spoilage_finished,
    player_tick_grown = state.player_tick_grown,
    foreign_tick_grown = state.foreign_tick_grown,
    player_spoil_interval = state.player_spoil_interval,
    foreign_spoil_interval = state.foreign_spoil_interval,
    player_spoil_tick = state.player_spoil_tick,
    foreign_spoil_tick = state.foreign_spoil_tick,
    spoil_modifier = state.spoil_modifier
  } or nil
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end

  if state.phase == "complete" then
    if loaded and not reported then
      if state.agriculture_finished ~= loaded.agriculture_finished
          or state.spoilage_finished ~= loaded.spoilage_finished
          or state.player_tick_grown ~= loaded.player_tick_grown
          or state.foreign_tick_grown ~= loaded.foreign_tick_grown
          or state.player_spoil_interval ~= loaded.player_spoil_interval
          or state.foreign_spoil_interval ~= loaded.foreign_spoil_interval
          or state.player_spoil_tick ~= loaded.player_spoil_tick
          or state.foreign_spoil_tick ~= loaded.foreign_spoil_tick
          or not close(state.spoil_modifier, loaded.spoil_modifier) then
        fail("on_load changed a durable scripted-effect witness")
      end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end

  if game.tick > state.deadline then fail("real labs or agricultural towers did not finish before deadline") end
  if state.lab and state.lab.valid then state.lab.energy = 100000000 end

  if state.phase == "researching" then
    if state.next_research and game.forces.player.current_research == nil then
      local next_research = state.next_research
      state.next_research = nil
      start_research(game.forces.player, next_research)
    end
    return
  end

  if state.phase == "planting" then
    if state.player_tower and state.player_tower.valid then state.player_tower.energy = 100000000 end
    if state.foreign_tower and state.foreign_tower.valid then state.foreign_tower.energy = 100000000 end
    if state.player_plant and state.foreign_plant then
      begin_spoilage_clocks(state)
      assert_complete(state)
      state.phase = "complete"
      marker("initial", state)
      game.server_save("mir5-native-complete")
    end
    return
  end

  fail("unknown fixture phase " .. tostring(state.phase))
end)
