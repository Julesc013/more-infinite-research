local CASE = "k2-base-continuations"
local KEY = "mir5_k2_base_continuations"
local SAVE = "mir5-native-complete"
local DEADLINE_TICKS = 36000
local INITIAL_PACKS = 32
local LAB_ENERGY = 100000000
local UINT32_MAX = 4294967295

-- These named rows are intentionally the same independent F200 K2 Base facts
-- checked in data-final-fixes.lua.  This runtime fixture has no family scan.
local PLAN = {
  {
    name = "braking-force-8", level = 8,
    prerequisites = {"braking-force-6", "braking-force-7", "automation-science-pack",
      "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack"},
    effects = {{type = "train-braking-force-bonus", modifier = 0.15}},
  },
  {
    name = "inserter-capacity-bonus-8", level = 8,
    prerequisites = {"inserter-capacity-bonus-6", "utility-science-pack", "inserter-capacity-bonus-7",
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack"},
    effects = {
      {type = "inserter-stack-size-bonus", modifier = 2},
      {type = "bulk-inserter-capacity-bonus", modifier = 4},
    },
  },
  {
    name = "laser-shooting-speed-8", level = 8,
    prerequisites = {"laser-shooting-speed-6", "laser-shooting-speed-7", "automation-science-pack",
      "logistic-science-pack", "chemical-science-pack", "military-science-pack", "utility-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "military-science-pack", "utility-science-pack"},
    effects = {
      {type = "gun-speed", ammo_category = "laser", modifier = 0.1},
      {type = "gun-speed", ammo_category = "kr-impulse-rifle", modifier = 0.1},
    },
  },
  {
    name = "research-speed-7", level = 7,
    prerequisites = {"research-speed-5", "utility-science-pack", "research-speed-6", "automation-science-pack",
      "logistic-science-pack", "chemical-science-pack", "production-science-pack", "military-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack", "military-science-pack"},
    effects = {{type = "laboratory-speed", modifier = 0.6}},
  },
  {
    name = "weapon-shooting-speed-7", level = 7,
    prerequisites = {"weapon-shooting-speed-5", "utility-science-pack", "weapon-shooting-speed-6",
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "military-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "military-science-pack", "utility-science-pack"},
    effects = {
      {type = "gun-speed", ammo_category = "bullet", modifier = 0.15},
      {type = "gun-speed", ammo_category = "shotgun-shell", modifier = 0.15},
      {type = "gun-speed", ammo_category = "kr-pistol", modifier = 0.15},
      {type = "gun-speed", ammo_category = "kr-anti-materiel-rifle-ammo", modifier = 0.15},
      {type = "gun-speed", ammo_category = "kr-railgun-shell", modifier = 0.2},
      {type = "gun-speed", ammo_category = "kr-turret-missile", modifier = 0.2},
      {type = "gun-speed", ammo_category = "kr-heavy-rocket", modifier = 0.2},
    },
  },
  {
    name = "worker-robots-storage-4", level = 4,
    prerequisites = {"worker-robots-storage-2", "utility-science-pack", "worker-robots-storage-3",
      "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack"},
    effects = {{type = "worker-robot-storage", modifier = 1}},
  },
  {
    name = "recipe-prod-research_gears-1", level = 1,
    prerequisites = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    effects = {
      {type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.1},
      {type = "change-recipe-productivity", recipe = "kr-iron-gear-wheel-from-enriched-iron", change = 0.1},
      {type = "change-recipe-productivity", recipe = "kr-iron-gear-wheel-from-iron-ore", change = 0.1},
    },
  },
}

local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack", "military-science-pack",
}
local CONSUMPTION = {
  ["automation-science-pack"] = 7, ["logistic-science-pack"] = 7, ["chemical-science-pack"] = 7,
  ["production-science-pack"] = 5, ["utility-science-pack"] = 6, ["military-science-pack"] = 3,
}
local GEAR_RECIPES = {
  "iron-gear-wheel", "kr-iron-gear-wheel-from-enriched-iron", "kr-iron-gear-wheel-from-iron-ore",
}

local loaded, reported

local function fail(message) error("[mir5-k2-base-continuations] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function exact_effects(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " effect cardinality changed") end
  for index, wanted in ipairs(expected) do
    local effect = actual[index]
    if type(effect) ~= "table" or effect.type ~= wanted.type then fail(label .. " effect type changed") end
    for key, value in pairs(wanted) do
      -- Native numeric effect fields can be single precision. The data-stage
      -- defaults above remain exact; use the existing native witness tolerance.
      local same = type(value) == "number" and close(effect[key], value) or effect[key] == value
      if not same then fail(label .. " effect changed at " .. tostring(index) .. "." .. key
        .. ": actual=" .. tostring(effect[key]) .. " expected=" .. tostring(value)) end
    end
  end
end

local function exact_prerequisites(actual, expected, label)
  local expected_names, count = {}, 0
  for _, name in ipairs(expected) do expected_names[name], count = true, count + 1 end
  local actual_count = 0
  for name, value in pairs(actual or {}) do
    if not expected_names[name] or not value or value.name ~= name then fail(label .. " native prerequisite changed") end
    actual_count = actual_count + 1
  end
  if actual_count ~= count then fail(label .. " native prerequisite cardinality changed") end
end

local function technology(force, expected)
  local value = force and force.technologies[expected.name]
  if not value or value.valid == false then fail("missing technology " .. expected.name) end
  local prototype = value.prototype
  if not prototype or prototype.level ~= expected.level or prototype.max_level ~= UINT32_MAX or prototype.upgrade ~= true then
    fail(expected.name .. " native continuation identity changed")
  end
  exact_prerequisites(prototype.prerequisites, expected.prerequisites, expected.name)
  exact_effects(prototype.effects, expected.effects, expected.name)
  return value
end

local function player_start(force)
  for _, expected in ipairs(PLAN) do
    local value = technology(force, expected)
    if value.level ~= expected.level or value.researched or value.enabled ~= true then
      fail(expected.name .. " did not begin as an enabled unresearched level")
    end
    if value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
      fail(expected.name .. " fixture acceleration is not the exact disposable unit")
    end
  end
end

local function bonus_snapshot(force)
  local values = {
    braking = force.train_braking_force_bonus,
    inserter = force.inserter_stack_size_bonus,
    bulk_inserter = force.bulk_inserter_capacity_bonus,
    laboratory = force.laboratory_speed_modifier,
    storage = force.worker_robots_storage_bonus,
    guns = {}, recipes = {},
  }
  for _, category in ipairs({"laser", "kr-impulse-rifle", "bullet", "shotgun-shell", "kr-pistol",
      "kr-anti-materiel-rifle-ammo", "kr-railgun-shell", "kr-turret-missile", "kr-heavy-rocket"}) do
    values.guns[category] = force.get_gun_speed_modifier(category)
  end
  for _, recipe in ipairs(GEAR_RECIPES) do
    local value = force.recipes[recipe]
    if not value then fail("missing gear recipe " .. recipe) end
    values.recipes[recipe] = value.productivity_bonus
  end
  return values
end

local function assert_bonus_delta(force, baseline, label)
  local current = bonus_snapshot(force)
  local scalar_deltas = {
    braking = 0.15, inserter = 2, bulk_inserter = 4, laboratory = 0.6, storage = 1,
  }
  for field, delta in pairs(scalar_deltas) do
    if not close(current[field], baseline[field] + delta) then fail(label .. " native effect changed for " .. field) end
  end
  local gun_deltas = {
    laser = 0.1, ["kr-impulse-rifle"] = 0.1, bullet = 0.15, ["shotgun-shell"] = 0.15,
    ["kr-pistol"] = 0.15, ["kr-anti-materiel-rifle-ammo"] = 0.15, ["kr-railgun-shell"] = 0.2,
    ["kr-turret-missile"] = 0.2, ["kr-heavy-rocket"] = 0.2,
  }
  for category, delta in pairs(gun_deltas) do
    if not close(current.guns[category], baseline.guns[category] + delta) then
      fail(label .. " native gun-speed effect changed for " .. category)
    end
  end
  for _, recipe in ipairs(GEAR_RECIPES) do
    if not close(current.recipes[recipe], baseline.recipes[recipe] + 0.1) then
      fail(label .. " native gear productivity changed for " .. recipe)
    end
  end
end

local function assert_foreign(state)
  local force = game.forces[state.foreign_name]
  if not force or force.valid == false then fail("foreign force is absent") end
  for _, expected in ipairs(PLAN) do
    local value = technology(force, expected)
    if value.level ~= expected.level or value.researched or value.enabled or value.visible_when_disabled then
      fail("foreign disabled state changed for " .. expected.name)
    end
  end
  local current = bonus_snapshot(force)
  local baseline = state.foreign_baseline
  for _, field in ipairs({"braking", "inserter", "bulk_inserter", "laboratory", "storage"}) do
    if not close(current[field], baseline[field]) then fail("foreign bonus changed for " .. field) end
  end
  for category, value in pairs(baseline.guns) do
    if not close(current.guns[category], value) then fail("foreign gun bonus changed for " .. category) end
  end
  for recipe, value in pairs(baseline.recipes) do
    if not close(current.recipes[recipe], value) then fail("foreign recipe bonus changed for " .. recipe) end
  end
end

local function assert_science_consumption(state)
  if not state.lab or state.lab.valid == false then fail("real K2 advanced lab is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real K2 advanced lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    local remaining = inventory.get_item_count(science)
    local expected = INITIAL_PACKS - CONSUMPTION[science]
    if remaining ~= expected then
      fail("science consumption changed for " .. science .. ": actual=" .. tostring(remaining)
        .. " expected=" .. tostring(expected))
    end
  end
end

local function assert_complete(state)
  if state.finished ~= #PLAN or state.events ~= #PLAN or state.queue_count ~= #PLAN then
    fail("seven-step native research queue did not complete exactly once per row")
  end
  local force = game.forces.player
  if force.current_research ~= nil or #force.research_queue ~= 0 then fail("completed research remained queued") end
  for _, expected in ipairs(PLAN) do
    local value = technology(force, expected)
    if value.level ~= expected.level + 1 or value.researched ~= false then
      fail(expected.name .. " did not retain its one completed native level")
    end
  end
  assert_bonus_delta(force, state.player_baseline, "player")
  assert_science_consumption(state)
  assert_foreign(state)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage, status = "passed",
    witnesses = {
      profile = "f200-k2-base", technology_ids = {
        PLAN[1].name, PLAN[2].name, PLAN[3].name, PLAN[4].name, PLAN[5].name, PLAN[6].name, PLAN[7].name,
      },
      one_lab = "kr-advanced-lab", queued_native_researches = state.queue_count,
      research_finished_events = state.events, completed_levels = state.finished,
      science_consumed = CONSUMPTION, foreign_force_preserved = true,
      native_gear_effect_change = game.forces.player.technologies[PLAN[7].name].prototype.effects[1].change,
      fixture_accelerates_count_formula_and_time = true,
      default_rows_preflighted_before_mutation = true, on_load_read_only = stage == "reload",
      gameplay_scope = "disposable-f200-k2-base-continuations-and-gears",
    },
  }))
end

local function seed_prerequisites(force)
  local seen = {}
  for _, expected in ipairs(PLAN) do
    for _, name in ipairs(expected.prerequisites) do
      if not seen[name] then
        local prerequisite = force.technologies[name]
        if not prerequisite then fail("named native prerequisite is absent: " .. name) end
        prerequisite.researched = true
        seen[name] = true
      end
    end
  end
end

script.on_init(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods.Krastorio2 ~= "2.0.19"
      or script.active_mods.Krastorio2Assets ~= "2.0.5" or script.active_mods["more-infinite-research"] ~= "5.0.20000"
      or script.active_mods["space-age"] ~= nil or script.active_mods["Krastorio2-spaced-out"] ~= nil
      or script.active_mods["k2so-assets"] ~= nil then
    fail("fixture loaded with an unexpected F200 K2 Base closure")
  end

  game.speed = 16
  local force = game.forces.player
  seed_prerequisites(force)
  player_start(force)
  local player_baseline = bonus_snapshot(force)

  local foreign_name = "mir5-k2-base-continuations-foreign"
  local foreign = game.create_force(foreign_name)
  for _, expected in ipairs(PLAN) do
    local value = technology(foreign, expected)
    if value.researched then fail("foreign technology unexpectedly begins researched") end
    value.enabled, value.visible_when_disabled = false, false
  end
  local foreign_baseline = bonus_snapshot(foreign)

  local surface = game.surfaces[1]
  local lab = surface.create_entity{
    name = "kr-advanced-lab", position = force.get_spawn_position(surface), force = force,
  }
  if not lab or lab.valid == false then fail("could not create a real K2 advanced lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real K2 advanced lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.insert{name = science, count = INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("K2 advanced lab did not accept " .. science)
    end
  end
  lab.energy = LAB_ENERGY

  -- All named prerequisites are seeded before the force bonus baseline.  Add
  -- the fixed seven entries once: the lab, not this control script, completes
  -- every research and raises the seven native completion events.
  -- F200 queues are always available. Do not write the removed 1.1
  -- research_queue_enabled property; exact add/queue readback below is proof.
  for _, expected in ipairs(PLAN) do
    local value = technology(force, expected)
    if not force.add_research(value) then fail("could not queue native research " .. expected.name) end
  end
  if #force.research_queue ~= #PLAN then fail("native research queue did not retain seven entries") end

  storage[KEY] = {
    phase = "researching", finished = 0, events = 0, queue_count = #force.research_queue,
    deadline = game.tick + DEADLINE_TICKS, lab = lab, player_baseline = player_baseline,
    foreign_name = foreign_name, foreign_baseline = foreign_baseline,
  }
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research or event.research.force ~= game.forces.player then return end
  local expected = PLAN[state.finished + 1]
  if not expected or event.research.name ~= expected.name then fail("unexpected native research completion") end
  state.finished, state.events = state.finished + 1, state.events + 1
  if state.finished > #PLAN then fail("native research queue completed an unexpected eighth row") end
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "complete" then
    -- This callback only rebuilds process-local witnesses. It intentionally
    -- does not access game or write persistent fixture state.
    loaded = {finished = state.finished, events = state.events, queue_count = state.queue_count}
  else
    loaded = nil
  end
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      if state.finished ~= loaded.finished or state.events ~= loaded.events or state.queue_count ~= loaded.queue_count then
        fail("on_load changed the saved continuation witness")
      end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real K2 Base lab queue did not finish before deadline") end
  if not state.lab or state.lab.valid == false then fail("real K2 advanced lab was removed") end
  state.lab.energy = LAB_ENERGY
  if state.finished == #PLAN then
    assert_complete(state)
    state.phase = "complete"
    marker("initial", state)
    game.server_save(SAVE)
  end
end)
