-- Private F200 Space Age experiment for the engine's native technology-effect
-- accounting.  It manipulates only its two fixture-owned carriers and reads
-- the aggregate recipe bonus; it never writes recipe.productivity_bonus.
local KEY = "mir5_native_credit_control"
local CASE = "f200-space-age-native-credit-control"
local FIXTURE = "mir-fixture-mir5-native-credit-control"
local SAVE = "mir5-native-complete"
local MAIN = "recipe-prod-research_breeding-1"
local POSITIVE = "mir5-native-credit-control-fish-positive"
local NEGATIVE = "mir5-native-credit-control-fish-negative"
local FISH = "fish-breeding"
local EGG = "biter-egg"
local DEADLINE = 60 * 60 * 10

local loaded = false

local function fail(message)
  error("[mir5-native-credit-control] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then
    fail("technology is absent: " .. tostring(name))
  end
  return value
end

local function bonus(force, recipe)
  local value = force.recipes and force.recipes[recipe]
  if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then
    fail("recipe productivity fact is absent: " .. tostring(recipe))
  end
  return value.productivity_bonus
end

local function marker(stage, state, detail)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE,
    stage = stage,
    status = "passed",
    qualification = "native-mechanism-control-only",
    witnesses = {
      main_next_level = technology(game.forces.player, MAIN).level,
      positive_next_level = technology(game.forces.player, POSITIVE).level,
      negative_next_level = technology(game.forces.player, NEGATIVE).level,
      fish_bonus = bonus(game.forces.player, FISH),
      egg_bonus = bonus(game.forces.player, EGG),
      detail = detail
    }
  }))
end

local function carrier_status(force, name)
  local value = technology(force, name)
  return {
    level = value.level,
    researched = value.researched,
    enabled = value.enabled,
    visible_when_disabled = value.visible_when_disabled,
    hidden = value.prototype.hidden,
    maximum = value.prototype.max_level
  }
end

local function assert_carrier(force, name, expected_level, label)
  local value = carrier_status(force, name)
  if value.level ~= expected_level or value.researched ~= false
      or value.enabled ~= false or value.visible_when_disabled ~= false
      or value.hidden ~= true or value.maximum ~= 4294967295 then
    fail(label .. " carrier state differs: " .. helpers.table_to_json(value))
  end
end

local function assert_bonus(force, fish, egg, label)
  local actual_fish, actual_egg = bonus(force, FISH), bonus(force, EGG)
  if not close(actual_fish, fish) or not close(actual_egg, egg) then
    fail(label .. " aggregate differs: fish=" .. tostring(actual_fish)
      .. " egg=" .. tostring(actual_egg) .. " expected_fish=" .. tostring(fish)
      .. " expected_egg=" .. tostring(egg))
  end
end

local function research_prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end

local function fill(lab, value)
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("lab input is absent") end
  inventory.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    local inserted = inventory.insert{name = ingredient.name, count = 100}
    if inserted ~= 100 then fail("lab could not receive science: " .. ingredient.name) end
  end
  lab.energy, lab.active = 1000000000, true
end

local function freeze(lab)
  if lab == nil or lab.valid == false then fail("native lab is absent") end
  lab.active, lab.energy = false, 0
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("lab input is absent while freezing") end
  inventory.clear()
end

local function bonus_snapshot(force)
  return {fish_bonus = bonus(force, FISH), egg_bonus = bonus(force, EGG)}
end

local function set_level_with_diagnostic(force, name, level, label)
  local value = technology(force, name)
  local before = {carrier = carrier_status(force, name), bonuses = bonus_snapshot(force)}
  local ok, err = pcall(function()
    value.level = level
    -- Factorio enables a technology after an explicit level write. These
    -- fixture-owned credit holders must remain hidden and unresearchable.
    value.enabled = false
  end)
  local after_set = {carrier = carrier_status(force, name), bonuses = bonus_snapshot(force)}
  log("[MIR5_NATIVE_FIXTURE] NATIVE_CARRIER_LEVEL " .. helpers.table_to_json({
    case = CASE, label = label, carrier = name, requested_level = level,
    accepted = ok, error = ok and nil or tostring(err), before = before, after_set = after_set,
    effects_changed_before_reset = ok and (not close(before.bonuses.fish_bonus, after_set.bonuses.fish_bonus)
      or not close(before.bonuses.egg_bonus, after_set.bonuses.egg_bonus)) or false
  }))
  if not ok then fail(label .. " native carrier level write failed: " .. tostring(err)) end
  local reset_ok, reset_err = pcall(function() force.reset_technology_effects() end)
  local after_reset = bonus_snapshot(force)
  log("[MIR5_NATIVE_FIXTURE] NATIVE_CARRIER_RESET " .. helpers.table_to_json({
    case = CASE, label = label, accepted = reset_ok, error = reset_ok and nil or tostring(reset_err),
    before_reset = after_set.bonuses, after_reset = after_reset
  }))
  if not reset_ok then fail(label .. " reset_technology_effects failed: " .. tostring(reset_err)) end
  return {before = before, after_set = after_set, after_reset = after_reset}
end

local function assert_completed(state, label)
  local player = game.forces.player
  if state.phase ~= "completed" then fail(label .. " phase differs") end
  if technology(player, MAIN).level ~= 2 or technology(player, MAIN).researched ~= false then
    fail(label .. " main research state differs")
  end
  assert_carrier(player, POSITIVE, 2, label .. " positive")
  assert_carrier(player, NEGATIVE, 2, label .. " negative")
  assert_bonus(player, 0.1, 0.1, label)
end

script.on_init(function()
  local active = script.active_mods
  if active.base ~= "2.0.77" or active["elevated-rails"] ~= "2.0.77"
      or active.quality ~= "2.0.77" or active["space-age"] ~= "2.0.77"
      or active["more-infinite-research"] ~= "5.0.20000" or active[FIXTURE] ~= "0.1.0" then
    fail("unexpected F200 Space Age mechanism-control closure")
  end
  if storage[KEY] ~= nil then fail("fixture state already exists") end

  game.speed = 16
  local player = game.forces.player
  local main = technology(player, MAIN)
  research_prerequisites(main)
  assert_carrier(player, POSITIVE, 1, "initial positive")
  assert_carrier(player, NEGATIVE, 1, "initial negative")
  assert_bonus(player, 0, 0, "initial")
  if main.level ~= 1 or main.researched ~= false then fail("main research is not a fresh infinite level") end

  local lab = game.surfaces[1].create_entity{name = "biolab", position = {0, 0}, force = player}
  if lab == nil or lab.valid == false then fail("could not create the native Space Age biolab") end
  fill(lab, main)
  if player.add_research(main) ~= true then fail("could not queue native MIR breeding research") end
  storage[KEY] = {phase = "await-main-lab", lab = lab, deadline_tick = game.tick + DEADLINE}
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-main-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= MAIN then
    return
  end
  local player = game.forces.player
  freeze(state.lab)
  if technology(player, MAIN).level ~= 2 or technology(player, MAIN).researched ~= false then
    fail("one native main lab completion did not advance exactly one infinite level")
  end
  assert_bonus(player, 0.1, 0.1, "earned main research")

  state.positive_credit = set_level_with_diagnostic(player, POSITIVE, 2, "positive-credit")
  assert_carrier(player, POSITIVE, 2, "positive-credit")
  assert_carrier(player, NEGATIVE, 1, "positive-credit")
  assert_bonus(player, 0.2, 0.1, "positive native credit")

  state.negative_credit = set_level_with_diagnostic(player, NEGATIVE, 2, "negative-credit")
  assert_carrier(player, POSITIVE, 2, "negative-credit")
  assert_carrier(player, NEGATIVE, 2, "negative-credit")
  assert_bonus(player, 0.1, 0.1, "negative native credit reversal")

  local reset_ok, reset_err = pcall(function() player.reset_technology_effects() end)
  if not reset_ok then fail("repeat reset_technology_effects failed: " .. tostring(reset_err)) end
  assert_bonus(player, 0.1, 0.1, "repeat reset consistency")

  state.phase = "completed"
  marker("initial", state, "main-plus-positive-minus-negative")
  game.server_save(SAVE)
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "completed"
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if loaded then
    assert_completed(state, "cold reload")
    marker("reload", state, "native-carrier-credit-survived-cold-load")
    loaded = false
    return
  end
  if state.phase == "completed" then return end
  if state.phase == "await-main-lab" then
    if state.lab == nil or state.lab.valid == false then fail("native lab disappeared while awaiting main research") end
    state.lab.energy = 1000000000
  end
  if game.tick > state.deadline_tick then fail("native main lab did not complete before bounded deadline") end
end)
