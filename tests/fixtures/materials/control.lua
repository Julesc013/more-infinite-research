local KEY = "mir5_native_materials"
local SAVE = "mir5-native-complete"
local INITIAL_PACKS = 32
local DEADLINE_TICKS = 36000
local LAB_ENERGY = 100000000

local MATERIALS = {
  {
    name = "recipe-prod-research_material_rare_metals-1",
    recipes = {"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"},
  },
  {
    name = "recipe-prod-research_material_silicon-1",
    recipes = {"kr-silicon"},
  },
  {
    name = "recipe-prod-research_material_glass-1",
    recipes = {"kr-glass"},
  },
}

local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
}

local PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "kr-rare-metal-processing", "kr-enriched-ores", "kr-silicon-processing", "kr-stone-processing",
}

local PLAN = {
  MATERIALS[1], MATERIALS[1], MATERIALS[1],
  MATERIALS[2], MATERIALS[2], MATERIALS[2],
  MATERIALS[3], MATERIALS[3], MATERIALS[3],
}

local EXPECTED_CONSUMPTION = {
  ["automation-science-pack"] = 9,
  ["logistic-science-pack"] = 9,
  ["chemical-science-pack"] = 6,
}

local loaded, reported

local function fail(message)
  error("[mir5-materials] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function technology(force, material)
  local value = force and force.technologies[material.name]
  if not value then fail("missing material technology " .. material.name) end
  local prototype = value.prototype
  if not prototype or prototype.max_level ~= 3 then
    fail(material.name .. " native finite maximum changed")
  end
  if type(prototype.effects) ~= "table" or #prototype.effects ~= #material.recipes then
    fail(material.name .. " native recipe effects changed")
  end
  for index, recipe in ipairs(material.recipes) do
    local effect = prototype.effects[index]
    if not effect or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or not close(effect.change, 0.02) then
      fail(material.name .. " native recipe effect changed")
    end
  end
  return value
end

local function assert_productivity(force, expected, label)
  for _, material in ipairs(MATERIALS) do
    for _, recipe in ipairs(material.recipes) do
      local value = force.recipes[recipe]
      if not value or not close(value.productivity_bonus, expected) then
        fail(label .. " productivity bonus changed for " .. recipe)
      end
    end
  end
end

local function assert_no_lab_productivity(force, label)
  if not close(force.laboratory_productivity_bonus, 0) then
    fail(label .. " has native laboratory productivity")
  end
end

local function assert_player_start(force)
  assert_no_lab_productivity(force, "player")
  assert_productivity(force, 0, "player initial")
  for _, material in ipairs(MATERIALS) do
    local value = technology(force, material)
    if value.level ~= 1 or value.researched or value.enabled ~= true then
      fail(material.name .. " did not begin as an unresearched enabled finite technology")
    end
  end
end

local function assert_foreign(state)
  local force = game.forces[state.foreign_index]
  if not force or force.valid == false or force.name ~= "mir5-materials-foreign" then
    fail("foreign force is absent")
  end
  assert_no_lab_productivity(force, "foreign force")
  assert_productivity(force, 0, "foreign force")
  for _, material in ipairs(MATERIALS) do
    local value = technology(force, material)
    if value.level ~= 1 or value.researched or value.enabled or value.visible_when_disabled then
      fail("foreign material state changed for " .. material.name)
    end
  end
end

local function assert_lab_consumption(state)
  if not state.lab or not state.lab.valid then fail("real lab input witness is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    local remaining = inventory.get_item_count(science)
    local expected = INITIAL_PACKS - EXPECTED_CONSUMPTION[science]
    if remaining ~= expected then
      fail("science consumption changed for " .. science .. ": actual=" .. tostring(remaining)
        .. " expected=" .. tostring(expected))
    end
  end
end

local function assert_complete(state)
  if state.finished ~= #PLAN or state.next ~= #PLAN + 1 then
    fail("real labs did not complete all nine material stages")
  end
  local force = game.forces.player
  assert_no_lab_productivity(force, "player")
  for _, material in ipairs(MATERIALS) do
    local value = technology(force, material)
    if value.level ~= 3 or value.researched ~= true then
      fail(material.name .. " did not retain its three earned finite stages")
    end
  end
  assert_productivity(force, 0.06, "player")
  if force.current_research ~= nil then fail("completed material research remained active") end
  for _, queued in ipairs(force.research_queue) do
    for _, material in ipairs(MATERIALS) do
      if queued.name == material.name then fail("completed material research remained queued") end
    end
  end
  assert_lab_consumption(state)
  assert_foreign(state)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "materials", stage = stage, status = "passed",
    witnesses = {
      profile = "k2so",
      technology_ids = {
        MATERIALS[1].name, MATERIALS[2].name, MATERIALS[3].name,
      },
      finite_levels_per_family = 3,
      actual_lab_completions = state.finished,
      native_recipe_productivity_per_recipe = 0.06,
      native_effect_per_completed_level = 0.02,
      science_consumed = {
        automation = EXPECTED_CONSUMPTION["automation-science-pack"],
        logistic = EXPECTED_CONSUMPTION["logistic-science-pack"],
        chemical = EXPECTED_CONSUMPTION["chemical-science-pack"],
      },
      native_laboratory_productivity = 0,
      foreign_force_preserved = true,
      fixture_accelerates_count_formula_and_time = true,
      ordinary_tuning_qualified = false,
      physical_productivity_observed = false,
      on_load_read_only = stage == "reload",
      gameplay_scope = "disposable-native-k2so-materials-only",
    },
  }))
end

local function start_next_research(state)
  local force = game.forces.player
  if state.next > #PLAN then return end
  if force.current_research ~= nil then return end
  if state.finished ~= state.next - 1 then
    fail("next material stage did not wait for the preceding native completion")
  end
  local value = technology(force, PLAN[state.next])
  if value.enabled ~= true then fail("next material stage is not enabled: " .. value.name) end
  if not force.add_research(value) then fail("could not start real lab research: " .. value.name) end
  state.next = state.next + 1
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23"
      or script.active_mods["Krastorio2-spaced-out"] == nil
      or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("unexpected K2SO target or player package")
  end

  game.speed = 16
  local force = game.forces.player
  for _, name in ipairs(PREREQUISITES) do
    local prerequisite = force.technologies[name]
    if not prerequisite then fail("named prerequisite is absent: " .. name) end
    prerequisite.researched = true
  end
  assert_player_start(force)

  local foreign = game.create_force("mir5-materials-foreign")
  for _, material in ipairs(MATERIALS) do
    local value = technology(foreign, material)
    if value.level ~= 1 or value.researched then fail("foreign material did not begin at level one") end
    value.enabled, value.visible_when_disabled = false, false
  end
  assert_foreign({foreign_index = foreign.index})

  local surface = game.surfaces[1]
  local lab = surface.create_entity{
    name = "lab", position = force.get_spawn_position(surface), force = force,
  }
  if not lab or not lab.valid then fail("could not create real lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.insert{name = science, count = INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("real lab did not accept " .. science)
    end
  end
  lab.energy = LAB_ENERGY
  storage[KEY] = {
    phase = "researching", finished = 0, next = 1, foreign_index = foreign.index,
    lab = lab, deadline = game.tick + DEADLINE_TICKS,
  }
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research
      or event.research.force ~= game.forces.player then
    return
  end
  local expected = PLAN[state.finished + 1]
  if not expected or event.research.name ~= expected.name then
    fail("unexpected material research completion")
  end
  state.finished = state.finished + 1
  if state.finished > #PLAN then fail("material research completed above its finite stages") end
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "complete" then
    -- Only local witnesses and the per-process marker flag are rebuilt here.
    loaded = {finished = state.finished, next = state.next}
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
      if state.finished ~= loaded.finished or state.next ~= loaded.next then
        fail("on_load changed the saved material witness")
      end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real material labs did not finish before deadline") end
  if not state.lab or not state.lab.valid then fail("real material lab was removed") end
  state.lab.energy = LAB_ENERGY
  if state.finished == #PLAN then
    assert_complete(state)
    state.phase = "complete"
    marker("initial", state)
    game.server_save(SAVE)
    return
  end
  start_next_research(state)
end)
