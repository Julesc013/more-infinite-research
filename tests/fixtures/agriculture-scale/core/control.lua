local KEY = "mir5_agriculture_scale"
local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local PAIRED = "mir-fixture-mir5-agriculture-scale-paired"
local CANDIDATE = "mir-fixture-mir5-agriculture-scale-arm-candidate"
local DEFAULTS = "mir-fixture-mir5-agriculture-scale-arm-candidate-defaults"
local PUBLISHED = "mir-fixture-mir5-agriculture-scale-arm-published"
local ACTIVE = "mir-fixture-mir5-agriculture-scale-active"
local CANDIDATE_SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "metallurgic-science-pack", "promethium-science-pack"
}
-- This list is bound to the independent published 4.7.21002 capture
-- (95B1A1FC…67B536C / 27FBC90D…7888072), never inferred from MIR 5.
local PUBLISHED_SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack"
}
local ARMS = {
  ["candidate-mir5"] = {name = "candidate-mir5", version = "5.0.21000", science = CANDIDATE_SCIENCE},
  ["candidate-defaults-mir5"] = {name = "candidate-defaults-mir5", version = "5.0.21000", science = PUBLISHED_SCIENCE},
  ["published-4.7.21002"] = {name = "published-4.7.21002", version = "4.7.21002", science = PUBLISHED_SCIENCE}
}
local TIERS = { [1] = true, [32] = true, [128] = true }
local SELECTOR_FOR_TIER = {
  [1] = "mir-fixture-mir5-agriculture-scale-tier-1",
  [32] = "mir-fixture-mir5-agriculture-scale-tier-32",
  [128] = "mir-fixture-mir5-agriculture-scale-tier-128"
}
local GROWTH_TICKS = 18000
local SPOIL_TICKS = 216000
local AGRICULTURE_LEVELS = 2
local EFFECT_PERCENT = 1
local INITIAL_SCIENCE_PACKS = 16
local SPOIL_STACKS_PER_FORCE = 2
local GRID_SPACING = 16
local DEADLINE_TICKS = 18000
local SAVE = "mir5-native-complete"
local ACTIVE_SAVE = "mir5-native-active"

local loaded, reported, active_seed_pending

local function fail(message, fields)
  if fields then
    fields.case, fields.status, fields.error = "agriculture-scale", "failed", message
    log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json(fields))
  end
  error("[mir5-agriculture-scale] " .. message)
end

local function tier()
  local value = settings.startup["mir5-agriculture-scale-tier"]
  value = value and value.value
  if not TIERS[value] then fail("fixture did not select an authored agriculture scale tier") end
  return value
end

local function selected_arm(value)
  local paired = script.active_mods[PAIRED] == "0.1.0"
  local active = script.active_mods[ACTIVE]
  if active ~= nil and active ~= "0.1.0" then
    fail("active agriculture selector version differs")
  end
  local candidate = script.active_mods[CANDIDATE] == "0.1.0"
  local defaults = script.active_mods[DEFAULTS] == "0.1.0"
  local published = script.active_mods[PUBLISHED] == "0.1.0"
  if paired then
    if (candidate and 1 or 0) + (defaults and 1 or 0) + (published and 1 or 0) ~= 1 then
      fail("paired agriculture fixture requires exactly one arm selector")
    end
    local selectors = 0
    for _, selected in ipairs({1, 32, 128}) do
      local name = "mir-fixture-mir5-agriculture-scale-matched-tier-" .. selected
      if script.active_mods[name] ~= nil then
        if script.active_mods[name] ~= "0.1.0" or value ~= selected then
          fail("agriculture matched tier selector differs")
        end
        selectors = selectors + 1
      end
    end
    if selectors > 1 then fail("agriculture matched fixture requires one tier selector") end
    if active ~= nil and selectors ~= 1 then
      fail("active agriculture fixture requires exactly one matched tier selector")
    end
    if selectors == 0 then
      if value ~= 1 then fail("paired agriculture fixture requires the fixed single-tower tier") end
      if defaults then fail("agriculture Defaults arm requires a matched tier selector") end
    elseif candidate then
      fail("agriculture matched tiers require Defaults or published arm")
    end
    for _, name in pairs(SELECTOR_FOR_TIER) do
      if script.active_mods[name] ~= nil then fail("paired agriculture fixture cannot combine a scale tier selector") end
    end
    return ARMS[candidate and "candidate-mir5" or defaults and "candidate-defaults-mir5"
      or "published-4.7.21002"], true, active ~= nil
  end
  if candidate or defaults or published or active ~= nil then
    fail("agriculture arm selector requires the paired selector")
  end
  for _, selected in ipairs({1, 32, 128}) do
    if script.active_mods["mir-fixture-mir5-agriculture-scale-matched-tier-" .. selected] ~= nil then
      fail("agriculture matched tier selector requires a paired arm")
    end
  end
  local expected = SELECTOR_FOR_TIER[value]
  if script.active_mods[expected] ~= "0.1.0" then fail("selected agriculture scale tier lacks its selector") end
  for other, name in pairs(SELECTOR_FOR_TIER) do
    if other ~= value and script.active_mods[name] ~= nil then fail("multiple agriculture scale selectors are active") end
  end
  return ARMS["candidate-mir5"], false, false
end

local function state_arm(state)
  local arm = ARMS[state.arm]
  if not arm then fail("fixture state has no recognized agriculture arm") end
  return arm
end

local function technology(force)
  local value = force.technologies[AGRICULTURE]
  if not value then fail("missing MIR agricultural growth technology") end
  return value
end

local function assert_startup_contract(arm)
  if script.active_mods.base ~= "2.1.23" or script.active_mods["space-age"] ~= "2.1.23"
      or script.active_mods["more-infinite-research"] ~= arm.version then
    fail("unexpected engine, Space Age, or MIR package")
  end
  if arm.name == "published-4.7.21002" then return end
  local expected = {
    ["mir-science-pack-ingredient-policy"] = arm.name == "candidate-defaults-mir5" and "configured" or "all-official",
    ["ips-require-space-gate"] = arm.name ~= "candidate-defaults-mir5",
    ["ips-enable-research_agricultural_growth_speed"] = true,
    ["ips-cost-base-research_agricultural_growth_speed"] = 40000,
    ["ips-cost-linear-increment-research_agricultural_growth_speed"] = 0,
    ["ips-cost-growth-research_agricultural_growth_speed"] = 1.5,
    ["ips-max-level-research_agricultural_growth_speed"] = 0,
    ["ips-research-time-research_agricultural_growth_speed"] = 90,
    ["ips-effect-per-level-research_agricultural_growth_speed"] = EFFECT_PERCENT
  }
  for name, wanted in pairs(expected) do
    local actual = settings.startup[name]
    if not actual or actual.value ~= wanted then
      fail("fixture startup contract differs for " .. name)
    end
  end
end

local function start_research(force)
  local value = technology(force)
  if force.current_research ~= nil or not force.add_research(value) then
    fail("could not start the next real agricultural research")
  end
end

local function assert_foreign(state)
  local force = game.forces[state.foreign_force_index]
  if not force or force.name ~= "mir5-agriculture-scale-foreign" then
    fail("zero-research foreign force is absent")
  end
  local value = technology(force)
  if value.level ~= 1 or value.researched then
    fail("foreign force received agricultural research")
  end
  return force
end

local function grid_dimensions(count)
  local columns = math.ceil(math.sqrt(count))
  return columns, math.ceil(count / columns)
end

local function grid_position(state, kind, index)
  local columns = state.grid_columns
  local origin_x = kind == "player" and 64 or 64 + (columns + 4) * GRID_SPACING
  local column = (index - 1) % columns
  local row = math.floor((index - 1) / columns)
  return {x = origin_x + column * GRID_SPACING, y = 64 + row * GRID_SPACING}
end

local function all_positions(state)
  local positions = {}
  for _, kind in ipairs({"player", "foreign"}) do
    for index = 1, state.tier do positions[#positions + 1] = grid_position(state, kind, index) end
  end
  return positions
end

local function prepare_native_ground(surface, state)
  local positions = all_positions(state)
  local minimum_x, maximum_x, minimum_y, maximum_y
  local tiles = {}
  for _, position in ipairs(positions) do
    minimum_x = minimum_x and math.min(minimum_x, position.x - 5) or position.x - 5
    maximum_x = maximum_x and math.max(maximum_x, position.x + 5) or position.x + 5
    minimum_y = minimum_y and math.min(minimum_y, position.y - 5) or position.y - 5
    maximum_y = maximum_y and math.max(maximum_y, position.y + 5) or position.y + 5
    for x = position.x - 5, position.x + 5 do
      for y = position.y - 5, position.y + 5 do
        tiles[#tiles + 1] = {name = "natural-yumako-soil", position = {x = x, y = y}}
      end
    end
  end
  local center = {x = (minimum_x + maximum_x) / 2, y = (minimum_y + maximum_y) / 2}
  local radius = math.ceil(math.max(maximum_x - center.x, maximum_y - center.y) / 32) + 1
  if radius > 8 then fail("authored agriculture scale grid exceeded its generation bound") end
  surface.request_to_generate_chunks(center, radius)
  surface.force_generate_chunk_requests()
  surface.set_tiles(tiles)
  state.generated_chunk_radius, state.native_soil_tiles = radius, #tiles
end

local function create_tower(surface, position, force)
  local tower = surface.create_entity{name = "agricultural-tower", position = position, force = force}
  if not tower or not tower.valid then fail("could not create native agricultural tower") end
  tower.energy = 100000000
  return tower
end

local function insert_seed(tower)
  local inventory = tower.get_inventory(defines.inventory.agricultural_tower_input)
  if not inventory or inventory.insert{name = "yumako-seed", count = 1} ~= 1 then
    fail("could not insert a native yumako seed")
  end
end

local function create_spoil_stack(surface, position, force)
  local chest = surface.create_entity{name = "wooden-chest", position = position, force = force}
  if not chest or not chest.valid then fail("could not create spoilage witness chest") end
  local inventory = chest.get_inventory(defines.inventory.chest)
  if not inventory or inventory.insert{name = "yumako", count = 1} ~= 1 then
    fail("could not insert native yumako spoilage witness")
  end
  local stack = inventory[1]
  local prototype_ticks = stack and stack.prototype and stack.prototype.get_spoil_ticks()
  if not stack or not stack.valid_for_read or stack.name ~= "yumako" or prototype_ticks ~= SPOIL_TICKS
      or type(stack.spoil_tick) ~= "number" or stack.spoil_tick <= game.tick then
    fail("native yumako stack did not retain the expected spoilage API contract")
  end
  return {chest = chest, spoil_tick = stack.spoil_tick, insert_tick = game.tick,
    prototype_spoil_ticks = prototype_ticks}
end

local function begin_spoilage(state)
  if game.difficulty_settings.spoil_time_modifier ~= 1 then
    fail("agriculture scale requires the native global spoilage baseline one")
  end
  local surface, player, foreign = game.surfaces.nauvis, game.forces.player, assert_foreign(state)
  state.spoilage_baseline = game.difficulty_settings.spoil_time_modifier
  state.spoil_stacks = {}
  for index = 1, SPOIL_STACKS_PER_FORCE do
    state.spoil_stacks[#state.spoil_stacks + 1] = create_spoil_stack(surface,
      {x = 32 + index * 8, y = 16}, player)
    state.spoil_stacks[#state.spoil_stacks + 1] = create_spoil_stack(surface,
      {x = 32 + index * 8, y = 32}, foreign)
  end
end

local function prepare_tower_burst(state)
  local surface, player, foreign = game.surfaces.nauvis, game.forces.player, assert_foreign(state)
  if not surface or surface.get_property("pressure") ~= 1000 then
    fail("Nauvis does not meet the native agricultural tower pressure contract")
  end
  prepare_native_ground(surface, state)
  state.player_towers, state.foreign_towers, state.plants = {}, {}, {player = {}, foreign = {}}
  state.tower_owner = {}
  for _, kind in ipairs({"player", "foreign"}) do
    local force, target = kind == "player" and player or foreign,
      kind == "player" and state.player_towers or state.foreign_towers
    for index = 1, state.tier do
      local tower = create_tower(surface, grid_position(state, kind, index), force)
      target[index] = tower
      state.tower_owner[tower.unit_number] = {kind = kind, index = index, force_index = force.index}
    end
  end
end

local function plant_prepared_towers(state)
  state.phase = "planting"
  local profiler = helpers.create_profiler()
  for _, towers in ipairs({state.player_towers, state.foreign_towers}) do
    for _, tower in ipairs(towers) do insert_seed(tower) end
  end
  profiler.stop()
  state.seed_insertion_profiler = tostring(profiler)
end

local function begin_tower_burst(state)
  prepare_tower_burst(state)
  plant_prepared_towers(state)
end

local function expected_remaining(kind)
  return kind == "player" and math.floor(GROWTH_TICKS / (1.01 ^ AGRICULTURE_LEVELS)) or GROWTH_TICKS
end

local function assert_lab_research(state)
  local player = game.forces.player
  local agriculture = technology(player)
  if state.research_finished ~= AGRICULTURE_LEVELS or agriculture.level ~= AGRICULTURE_LEVELS + 1
      or player.current_research ~= nil then
    fail("real lab did not complete exactly two agricultural research levels")
  end
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  local consumed = {}
  for _, name in ipairs(state_arm(state).science) do
    consumed[name] = INITIAL_SCIENCE_PACKS - inventory.get_item_count(name)
    if name ~= "agricultural-science-pack" and consumed[name] ~= AGRICULTURE_LEVELS then
      fail("real lab consumed an unexpected nominal input count for " .. name, {
        expected = AGRICULTURE_LEVELS, actual = consumed[name], input = name
      })
    end
  end
  local agricultural = consumed["agricultural-science-pack"]
  if agricultural < AGRICULTURE_LEVELS or agricultural > AGRICULTURE_LEVELS * 2 then
    fail("fresh agricultural science physical consumption differs", {
      expected_minimum = AGRICULTURE_LEVELS, expected_maximum = AGRICULTURE_LEVELS * 2,
      actual = agricultural
    })
  end
  if state.lab_consumption then
    for _, name in ipairs(state_arm(state).science) do
      if state.lab_consumption[name] ~= consumed[name] then
        fail("real lab input consumption changed after completion for " .. name)
      end
    end
  elseif state.phase == "complete" then
    fail("saved lab consumption witness is absent")
  else
    state.lab_consumption = consumed
  end
end
local function assert_plants(state)
  local expected_events = 2 * state.tier
  if state.planted_events ~= expected_events then
    fail("native planted event count differs", {expected = expected_events, actual = state.planted_events or 0})
  end
  for _, kind in ipairs({"player", "foreign"}) do
    local expected = expected_remaining(kind)
    local plants = state.plants and state.plants[kind]
    local towers = state[kind .. "_towers"]
    local force = kind == "player" and game.forces.player or assert_foreign(state)
    if not plants or not towers or #towers ~= state.tier then
      fail(kind .. " native plant witness cardinality differs")
    end
    for index = 1, state.tier do
      local tower = towers[index]
      if not tower or not tower.valid or tower.force.index ~= force.index then
        fail(kind .. " native tower witness differs at " .. index)
      end
      local row = plants[index]
      local plant = row and row.plant
      if not plant or not plant.valid or plant.name ~= "yumako-tree"
          or plant.prototype.growth_ticks ~= GROWTH_TICKS
          or plant.tick_grown ~= row.tick_grown or row.remaining ~= expected then
        fail(kind .. " native plant witness differs at " .. index)
      end
    end
  end
end

local function assert_spoilage(state)
  if game.difficulty_settings.spoil_time_modifier ~= state.spoilage_baseline
      or state.spoilage_baseline ~= 1 then
    fail("native global spoilage baseline changed")
  end
  if not state.spoil_stacks or #state.spoil_stacks ~= 2 * SPOIL_STACKS_PER_FORCE then
    fail("native spoilable stack witness cardinality differs")
  end
  for index, row in ipairs(state.spoil_stacks) do
    local inventory = row.chest and row.chest.valid and row.chest.get_inventory(defines.inventory.chest)
    local stack = inventory and inventory[1]
    if not stack or not stack.valid_for_read or stack.name ~= "yumako"
        or stack.prototype.get_spoil_ticks() ~= SPOIL_TICKS or stack.spoil_tick ~= row.spoil_tick
        or type(stack.spoil_percent) ~= "number" or stack.spoil_percent < 0 or stack.spoil_percent >= 1 then
      fail("native spoilable stack witness differs at " .. index)
    end
  end
end

local function assert_complete(state)
  assert_lab_research(state)
  assert_foreign(state)
  assert_plants(state)
  assert_spoilage(state)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "agriculture-scale",
    stage = stage,
    status = "passed",
    witnesses = {
      profile = "space-age-f210",
      tier = state.tier,
      real_lab_agriculture_completions = state.research_finished,
      -- Keep the original witness key for the existing scale controller. The
      -- paired descriptor makes clear that only the candidate arm is all-official.
      all_official_science = state_arm(state).science,
      science_contract = {arm = state.arm, packs = state_arm(state).science},
      defaults_prototype_contract = state.arm == "candidate-defaults-mir5"
        and "independently-matched-36CCE250-EE77416C" or "not-selected",
      nominal_nonperishable_science_consumed_each = AGRICULTURE_LEVELS,
      agricultural_science_physical_consumption = state.lab_consumption
        and state.lab_consumption["agricultural-science-pack"],
      native_towers = {player = state.tier, foreign_zero_research = state.tier},
      native_planting_events = {expected = 2 * state.tier, observed = state.planted_events},
      plant = "yumako-tree",
      native_growth_ticks = GROWTH_TICKS,
      trained_remaining_ticks = expected_remaining("player"),
      foreign_remaining_ticks = expected_remaining("foreign"),
      generated_chunk_radius = state.generated_chunk_radius,
      native_yumako_soil_tiles = state.native_soil_tiles,
      native_spoilable_stacks = #state.spoil_stacks,
      native_yumako_prototype_spoil_ticks = SPOIL_TICKS,
      native_spoilage_baseline = state.spoilage_baseline,
      seed_insertion_profiler = state.seed_insertion_profiler,
      profiler_timing_decision = "not-evaluated",
      published_4_7_contract = state.arm == "published-4.7.21002"
        and "independently-captured-95B1A1FC-27FBC90D"
        or (state.paired and "not-selected" or "unresolved"),
      cold_reload_witness = stage == "reload",
      on_load_read_only = stage == "reload",
      ordinary_tuning_qualified = false,
      gameplay_scope = "fixed-tier-native-agriculture-scale-only"
    }
  }))
end

local function active_marker(stage, state)
  log("[MIR5_RUNTIME_ACTIVE] " .. helpers.table_to_json({
    kind = "agriculture-scale",
    stage = stage,
    status = stage == "complete" and "passed" or "pending",
    witnesses = {
      tier = state.tier,
      arm = state.arm,
      real_lab_agriculture_completions = state.research_finished,
      native_towers = {player = state.player_towers and #state.player_towers or 0,
        foreign_zero_research = state.foreign_towers and #state.foreign_towers or 0},
      native_planting_events = {expected = 2 * state.tier, observed = state.planted_events or 0},
      native_growth_ticks = GROWTH_TICKS,
      pending_physical_work = stage ~= "complete",
      planting_event_api = "on_tower_planted_seed",
      performance_qualified = false,
      runtime_elapsed_qualified = false
    }
  }))
end

local function loaded_snapshot(state)
  return {
    tier = state.tier,
    arm = state.arm,
    paired = state.paired,
    research_finished = state.research_finished,
    planted_events = state.planted_events,
    spoilage_baseline = state.spoilage_baseline,
    seed_insertion_profiler = state.seed_insertion_profiler
  }
end

local function assert_loaded(state)
  if not loaded then return end
  for key, expected in pairs(loaded) do
    if state[key] ~= expected then fail("on_load changed durable agriculture witness " .. key) end
  end
end

script.on_init(function()
  local value = tier()
  local arm, paired, active = selected_arm(value)
  assert_startup_contract(arm)
  game.speed = 16
  local surface = assert(game.surfaces.nauvis)
  local player = game.forces.player
  player.enable_all_prototypes()
  local agriculture = technology(player)
  for _, prerequisite in pairs(agriculture.prerequisites) do prerequisite.research_recursive() end
  if agriculture.level ~= 1 or agriculture.researched or not agriculture.enabled then
    fail("fixture did not start at the first agricultural research level")
  end

  local foreign = game.create_force("mir5-agriculture-scale-foreign")
  foreign.enable_all_prototypes()
  local foreign_agriculture = technology(foreign)
  if foreign_agriculture.level ~= 1 or foreign_agriculture.researched then
    fail("foreign fixture force did not start untrained")
  end

  local lab = surface.create_entity{name = "lab", position = player.get_spawn_position(surface), force = player}
  if not lab or not lab.valid then fail("could not create real Space Age lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  for _, name in ipairs(arm.science) do
    if inventory.insert{name = name, count = INITIAL_SCIENCE_PACKS} ~= INITIAL_SCIENCE_PACKS then
      fail("lab rejected " .. name)
    end
  end
  lab.energy = 100000000

  local columns = grid_dimensions(value)
  storage[KEY] = {
    phase = "researching",
    tier = value,
    arm = arm.name,
    paired = paired,
    active = active,
    grid_columns = columns,
    research_finished = 0,
    foreign_force_index = foreign.index,
    lab = lab,
    deadline = game.tick + DEADLINE_TICKS
  }
  start_research(player)
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research
      or event.research.force ~= game.forces.player or event.research.name ~= AGRICULTURE then
    return
  end
  state.research_finished = state.research_finished + 1
  if state.research_finished > AGRICULTURE_LEVELS then
    fail("agricultural research completed above the fixture boundary")
  end
  if state.research_finished < AGRICULTURE_LEVELS then
    state.next_research = true
  else
    if state.active then
      prepare_tower_burst(state)
      state.phase = "active-pending"
      active_marker("prepared", state)
      game.server_save(ACTIVE_SAVE)
    else
      begin_tower_burst(state)
    end
  end
end)

-- This is an observer of the engine event after MIR's own registered handler.
-- It neither calls MIR nor writes a native plant deadline.
script.on_event(defines.events.on_tower_planted_seed, function(event)
  local state = storage[KEY]
  if not state or not event.tower or not event.plant then return end
  local owner = event.tower.valid and state.tower_owner and state.tower_owner[event.tower.unit_number]
  if not owner then return end
  if state.phase ~= "planting" then fail("native tower event arrived outside planting state") end
  local seed_name = event.seed and event.seed.name
  -- ItemIDAndQualityIDPair reads its item identifier back as the native
  -- LuaItemPrototype on F210; preserve a string fallback for host doubles.
  if type(seed_name) ~= "string" then seed_name = seed_name and seed_name.name end
  -- MIR selects growth by the planting tower's force. The native plant's
  -- separate force is not an ownership precondition for that effect.
  if event.tower.force.index ~= owner.force_index
      or seed_name ~= "yumako-seed" or event.plant.name ~= "yumako-tree"
      or event.plant.prototype.growth_ticks ~= GROWTH_TICKS then
    fail("native tower event owner or plant contract differs")
  end
  local plants = state.plants[owner.kind]
  if plants[owner.index] then fail("native tower emitted a duplicate planting event") end
  local remaining = event.plant.tick_grown - event.tick
  local expected = expected_remaining(owner.kind)
  if remaining ~= expected then
    fail(owner.kind .. " native planted growth timing differs", {
      tier = state.tier, expected = expected, actual = remaining, index = owner.index
    })
  end
  plants[owner.index] = {plant = event.plant, tick_grown = event.plant.tick_grown, remaining = remaining}
  state.planted_events = (state.planted_events or 0) + 1
  if state.planted_events > 2 * state.tier then fail("native planted event count exceeded fixture boundary") end
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.phase == "complete" and loaded_snapshot(state) or nil
  active_seed_pending = state and state.phase == "active-pending" or false
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      assert_loaded(state)
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then
    fail("real lab or native towers did not satisfy the fixed-tier deadline", {
      tier = state.tier, phase = state.phase, events = state.planted_events or 0,
      expected_events = 2 * state.tier
    })
  end
  if state.phase == "researching" then
    if state.lab and state.lab.valid then state.lab.energy = 100000000 end
    if state.next_research and game.forces.player.current_research == nil then
      state.next_research = nil
      start_research(game.forces.player)
    end
    return
  end
  if state.phase == "active-pending" then
    if active_seed_pending then
      active_seed_pending = false
      assert_lab_research(state)
      assert_foreign(state)
      active_marker("start", state)
      plant_prepared_towers(state)
    end
    return
  end
  if state.phase == "planting" then
    for _, towers in ipairs({state.player_towers, state.foreign_towers}) do
      for _, tower in ipairs(towers) do
        if not tower.valid then fail("native tower was removed during planting") end
        tower.energy = 100000000
      end
    end
    if state.planted_events == 2 * state.tier then
      begin_spoilage(state)
      assert_complete(state)
      state.phase = "complete"
      if state.active then active_marker("complete", state) end
      marker("initial", state)
      game.server_save(SAVE)
    end
    return
  end
  fail("fixture entered an unknown state " .. tostring(state.phase))
end)
