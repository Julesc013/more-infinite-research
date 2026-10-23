local fixture_name = "mir-fixture-mir5-owned-gear-upgrade"
local storage_key = "mir5_owned_gear_upgrade"
local gear_technology_name = "recipe-prod-research_gears-1"
local gear_recipe_name = "iron-gear-wheel"
local foreign_force_name = "mir5-owned-gear-upgrade-foreign"
local save_name = "mir5-native-complete"
local UINT32_MAX = 4294967295
local sciences = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack"
}

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-owned-gear-upgrade] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function technology_for(force)
  local technology = force and force.technologies[gear_technology_name]
  if technology == nil then fail("gear technology is absent for " .. tostring(force and force.name)) end
  return technology
end

local function status_for(force)
  local technology = technology_for(force)
  local recipe = force.recipes[gear_recipe_name]
  if recipe == nil then fail("gear recipe is absent for " .. tostring(force.name)) end
  return {
    level = technology.level,
    researched = technology.researched,
    enabled = technology.enabled,
    visible_when_disabled = technology.visible_when_disabled,
    max_level = technology.prototype.max_level,
    productivity_bonus = recipe.productivity_bonus
  }
end

local function copy_status(value)
  return {
    level = value.level,
    researched = value.researched,
    enabled = value.enabled,
    visible_when_disabled = value.visible_when_disabled,
    max_level = value.max_level,
    productivity_bonus = value.productivity_bonus
  }
end

local function assert_status(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled
      or actual.visible_when_disabled ~= expected.visible_when_disabled
      or actual.max_level ~= expected.max_level
      or not close(actual.productivity_bonus, expected.productivity_bonus) then
    fail(label .. " differs")
  end
end

local function prepare_prerequisites(technology)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
end

local function assert_native_unit_shape(technology)
  if technology.research_unit_count ~= 1 or not close(technology.prototype.research_unit_energy, 60) then
    fail("fixture defaults did not produce a native one-unit, one-second gear level")
  end
  local expected, seen = {}, {}
  for _, name in ipairs(sciences) do expected[name] = true end
  for _, ingredient in ipairs(technology.prototype.research_unit_ingredients) do
    if expected[ingredient.name] ~= true or ingredient.amount ~= 1 or seen[ingredient.name] then
      fail("published gear science unit differs from the owned-lab fixture")
    end
    seen[ingredient.name] = true
  end
  for _, name in ipairs(sciences) do
    if seen[name] ~= true then fail("published gear science unit is missing " .. name) end
  end
end

local function ensure_powered_lab(state)
  local lab = state.lab
  if lab == nil or lab.valid == false then fail("real lab disappeared") end
  -- This is the documented LuaEntity electric buffer. Research remains driven
  -- by the engine consuming the lab input inventory; no technology setter is used.
  lab.energy = 100000000
  if lab.energy <= 0 then fail("real lab has no stored power") end
  state.lab_energy_seen = true
  return lab
end

local function fill_lab(lab)
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real lab has no science input inventory") end
  for _, name in ipairs(sciences) do
    local inserted = inventory.insert{name = name, count = 16}
    if inserted ~= 16 then fail("could not insert native science " .. name) end
  end
  return inventory
end

local function assert_source_witness(state)
  local original = state.original_player
  local foreign = state.original_foreign
  if state.seeded_mir_version ~= "4.7.21000" or type(original) ~= "table"
      or original.level ~= 1 or original.researched ~= false
      or original.enabled ~= true or original.visible_when_disabled ~= false
      or not close(original.productivity_bonus, 0)
      or type(foreign) ~= "table" or foreign.enabled ~= false
      or foreign.visible_when_disabled ~= false then
    fail("pre-lab ownership witness is absent or malformed")
  end
end

local function assert_published_cap(state)
  assert_source_witness(state)
  if state.finished_levels ~= 2 then fail("lab did not finish exactly two gear levels") end
  local expected_player = {
    level = 3, researched = false, enabled = false,
    visible_when_disabled = true, max_level = UINT32_MAX, productivity_bonus = 0.2
  }
  local player = status_for(game.forces.player)
  assert_status(player, expected_player, "published player cap state")
  local foreign_force = game.forces[state.foreign_force_index]
  if foreign_force == nil or foreign_force.valid == false or foreign_force.name ~= foreign_force_name then
    fail("foreign force witness is absent")
  end
  local expected_foreign = {
    level = 1, researched = false, enabled = false,
    visible_when_disabled = false, max_level = UINT32_MAX, productivity_bonus = 0
  }
  local foreign = status_for(foreign_force)
  assert_status(foreign, expected_foreign, "foreign disabled state")

  if game.forces.player.current_research ~= nil then fail("above-cap player research survived") end
  for _, queued in ipairs(game.forces.player.research_queue) do
    if queued.name == gear_technology_name then fail("above-cap gear queue entry survived") end
  end
  local inventory = ensure_powered_lab(state).get_inventory(defines.inventory.lab_input)
  local consumed = {}
  for _, name in ipairs(sciences) do
    local amount = 16 - inventory.get_item_count(name)
    if amount ~= 2 then fail("lab science consumption differs for " .. name) end
    consumed[name] = amount
  end
  state.science_units_consumed = consumed
  return player, foreign
end

local function marker(stage, state)
  local post_cap = state.post_cap
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "owned-gear-upgrade",
    status = "passed",
    witnesses = {
      source_mir_version = state.seeded_mir_version,
      fixture_version = script.active_mods[fixture_name],
      lab_completed_levels = state.finished_levels,
      no_gear_researched_setter = true,
      original_player_enabled = state.original_player.enabled,
      original_player_visible_when_disabled = state.original_player.visible_when_disabled,
      post_cap_player_enabled = post_cap.player.enabled,
      post_cap_player_visible_when_disabled = post_cap.player.visible_when_disabled,
      next_level = post_cap.player.level,
      productivity_bonus = post_cap.player.productivity_bonus,
      science_units_consumed = state.science_units_consumed,
      lab_energy_seen = state.lab_energy_seen,
      foreign_enabled = post_cap.foreign.enabled,
      foreign_visible_when_disabled = post_cap.foreign.visible_when_disabled,
      on_load_read_only = stage == "reload",
      qualification = "native-runner-readback-required"
    }
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23"
      or script.active_mods["more-infinite-research"] ~= "4.7.21000"
      or script.active_mods[fixture_name] ~= "0.1.0" then
    fail("seed requires published MIR 4.7.21000 and fixture 0.1.0")
  end
  if storage[storage_key] ~= nil then fail("fixture storage already exists") end
  game.speed = 16

  local force = game.forces.player
  force.enable_all_prototypes()
  local gear = technology_for(force)
  -- Establish an explicit foreign-authored presentation baseline before the
  -- published controller acquires cap rights at actual lab completion.
  gear.enabled = true
  gear.visible_when_disabled = false
  local original_player = status_for(force)
  if original_player.level ~= 1 or original_player.researched
      or original_player.enabled ~= true or original_player.visible_when_disabled ~= false
      or original_player.max_level ~= UINT32_MAX or not close(original_player.productivity_bonus, 0) then
    fail("fresh player gear state does not establish owned-restoration baseline")
  end
  assert_native_unit_shape(gear)
  prepare_prerequisites(gear)

  local foreign = game.create_force(foreign_force_name)
  foreign.enable_all_prototypes()
  local foreign_gear = technology_for(foreign)
  foreign_gear.enabled = false
  foreign_gear.visible_when_disabled = false
  local original_foreign = status_for(foreign)
  if original_foreign.enabled ~= false or original_foreign.visible_when_disabled ~= false then
    fail("foreign force did not start disabled and hidden")
  end

  local lab = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = force}
  if lab == nil or lab.valid == false then fail("could not create real lab") end
  local inventory = fill_lab(lab)
  storage[storage_key] = {
    phase = "await-lab-completion",
    seeded_mir_version = script.active_mods["more-infinite-research"],
    original_player = original_player,
    original_foreign = original_foreign,
    foreign_force_index = foreign.index,
    lab = lab,
    lab_energy_seen = false,
    finished_levels = 0,
    deadline_tick = game.tick + 18000
  }
  local state = storage[storage_key]
  ensure_powered_lab(state)
  if force.add_research(gear) ~= true then fail("could not queue native gear research") end
  -- Three queue entries intentionally leave a third level available for the
  -- published controller to cancel after the second real lab completion.
  force.research_queue = {gear, gear, gear}
  if force.current_research == nil or force.current_research.name ~= gear_technology_name
      or inventory.get_item_count(sciences[1]) ~= 16 then
    fail("native gear research did not enter a fully supplied real lab")
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[storage_key]
  if state == nil or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= gear_technology_name then
    return
  end
  state.finished_levels = state.finished_levels + 1
  if state.finished_levels > 2 then fail("lab completed gear beyond the configured cap") end
end)

script.on_load(function()
  local state = storage[storage_key]
  if type(state) == "table" and state.phase == "completed" and type(state.post_cap) == "table" then
    -- Read only: later ticks perform native-object checks after a cold load.
    loaded_snapshot = {
      original_player = copy_status(state.original_player),
      original_foreign = copy_status(state.original_foreign),
      post_player = copy_status(state.post_cap.player),
      post_foreign = copy_status(state.post_cap.foreign),
      finished_levels = state.finished_levels,
      foreign_force_index = state.foreign_force_index
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if type(state) ~= "table" then fail("fixture storage is absent") end
  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      if state.finished_levels ~= loaded_snapshot.finished_levels
          or state.foreign_force_index ~= loaded_snapshot.foreign_force_index then
        fail("cold load lost durable source witnesses")
      end
      local player, foreign = assert_published_cap(state)
      assert_status(player, loaded_snapshot.post_player, "cold-loaded player cap")
      assert_status(foreign, loaded_snapshot.post_foreign, "cold-loaded foreign state")
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("two real lab gear completions did not reach cap") end
  ensure_powered_lab(state)
  if state.finished_levels < 2 then return end

  local player, foreign = assert_published_cap(state)
  state.post_cap = {player = copy_status(player), foreign = copy_status(foreign)}
  state.phase = "completed"
  marker("initial", state)
  game.server_save(save_name)
end)
