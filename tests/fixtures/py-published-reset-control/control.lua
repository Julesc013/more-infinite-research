-- A published-4.7-only configuration-boundary observer.  Its paired actor
-- migration has already restored the exact foreign disabled flag before this
-- callback can run.  This fixture only reads the retained snapshot and saves
-- a runner completion boundary; it never writes technologies, forces, recipes,
-- effects, research, queues, or actor storage.
local KEY = "mir5_integration_catalogue_upgrade"
local ACTOR_KEY = "mir5_integration_foreign_owner"
local FIXTURE = "mir-fixture-mir5-integration-catalogue-upgrade"
local ACTOR_MOD = "mir-fixture-mir5-integration-foreign-owner"
local SAVE = "mir5-native-complete"
local loaded, configured, initial_saved, reload_logged = false, false, false, false

local profiles = {
  ["py-coal"] = {
    primary = "recipe-prod-research_material_py_log-4",
    mods = {
      base = "2.0.77",
      [FIXTURE] = "0.2.0",
      [ACTOR_MOD] = "0.2.0",
      ["mir-fixture-mir5-active-mods-observer"] = "0.1.0",
      ["more-infinite-research"] = "4.7.20002",
      pycoalprocessinggraphics = "3.0.9",
      pypostprocessing = "3.0.42",
      pycoalprocessing = "3.0.44",
    },
  },
  ["py-alienlife-hightech"] = {
    primary = "recipe-prod-research_breeding-1",
    mods = {
      base = "2.0.77",
      [FIXTURE] = "0.2.0",
      [ACTOR_MOD] = "0.2.0",
      ["mir-fixture-mir5-active-mods-observer"] = "0.1.0",
      ["more-infinite-research"] = "4.7.20002",
      pycoalprocessinggraphics = "3.0.9",
      pypostprocessing = "3.0.42",
      pycoalprocessing = "3.0.44",
      pyfusionenergygraphics = "3.0.4",
      pyfusionenergy = "3.0.17",
      pyindustrygraphics = "3.0.3",
      pyindustry = "3.0.21",
      pypetroleumhandlinggraphics = "3.0.5",
      pypetroleumhandling = "3.0.23",
      pyraworesgraphics = "3.0.4",
      pyrawores = "3.0.25",
      pyalienlifegraphics = "3.0.12",
      pyalienlifegraphics2 = "3.0.3",
      pyalienlifegraphics3 = "3.0.4",
      pyalienlife = "3.0.67",
      pyhightechgraphics = "3.0.3",
      pyhightech = "3.0.19",
    },
  },
}

local function fail(message)
  error("[mir5-py-published-reset-control] " .. message)
end

local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end

local function exactly(actual, expected)
  for name, version in pairs(expected) do
    if actual[name] ~= version then return false end
  end
  for name in pairs(actual) do
    if expected[name] == nil then return false end
  end
  return true
end

local function profile()
  local found, selected = 0, nil
  for name, candidate in pairs(profiles) do
    if exactly(script.active_mods, candidate.mods) then found, selected = found + 1, name end
  end
  if found ~= 1 then fail("runtime closure is not one retained Py profile") end
  return selected, profiles[selected]
end

local function technology(force, name, label)
  local value = force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name or value.prototype == nil then
    fail(label .. " technology is absent: " .. name)
  end
  return value
end

local function snapshot_row(technology)
  return {
    level = technology.level,
    researched = technology.researched,
    enabled = technology.enabled,
    visible = technology.visible_when_disabled,
    saved = technology.saved_progress,
    maximum = technology.prototype.max_level,
  }
end

local function assert_row(actual, expected, name, primary)
  if type(expected) ~= "table" or type(expected.level) ~= "number" or type(expected.researched) ~= "boolean"
      or type(expected.enabled) ~= "boolean" or type(expected.visible) ~= "boolean"
      or type(expected.saved) ~= "number" then
    fail("saved foreign row is malformed: " .. name)
  end
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.visible ~= expected.visible or not close(actual.saved, expected.saved)
      or actual.maximum ~= expected.maximum then
    fail("post-callback foreign row changed outside enabled state: " .. name)
  end
  local expected_enabled = name == primary and true or expected.enabled
  if actual.enabled ~= expected_enabled then
    fail("post-callback foreign enabled state differs: " .. name)
  end
end

local function assert_snapshot(force, expected, primary)
  if type(expected) ~= "table" or type(expected.technologies) ~= "table"
      or type(expected.recipes) ~= "table" or type(expected.guns) ~= "table" or type(expected.fields) ~= "table" then
    fail("published source foreign snapshot is incomplete")
  end
  local technology_count = 0
  for name, before in pairs(expected.technologies) do
    assert_row(snapshot_row(technology(force, name, "foreign")), before, name, primary)
    technology_count = technology_count + 1
  end
  for name, before in pairs(expected.recipes) do
    local recipe = force.recipes[name]
    if recipe == nil or recipe.valid == false or recipe.enabled ~= before then
      fail("post-callback foreign recipe changed: " .. name)
    end
  end
  for category, before in pairs(expected.guns) do
    if not close(force.get_gun_speed_modifier(category), before) then
      fail("post-callback foreign gun effect changed: " .. category)
    end
  end
  for field, before in pairs(expected.fields) do
    if not close(force[field], before) then
      fail("post-callback foreign force effect changed: " .. field)
    end
  end
  return technology_count
end

local function observe()
  local profile_name, selected = profile()
  local state = storage[KEY]
  local actor = storage[ACTOR_KEY]
  if type(state) ~= "table" or state.phase ~= "source-complete" or state.profile ~= profile_name
      or type(state.foreign_index) ~= "number" then
    fail("published source witness is absent or belongs to another profile")
  end
  if type(actor) ~= "table" or actor.disabled ~= true or actor.force_index ~= state.foreign_index
      or actor.technology ~= selected.primary then
    fail("foreign-owner migration witness differs")
  end
  local force = game.forces[state.foreign_index]
  if force == nil or force.valid == false or force.name ~= "mir5-integration-catalogue-upgrade-foreign" then
    fail("published foreign force is absent")
  end
  local expected_primary = state.foreign_snapshot and state.foreign_snapshot.technologies
      and state.foreign_snapshot.technologies[selected.primary] or nil
  if type(expected_primary) ~= "table" or expected_primary.enabled ~= false or expected_primary.visible ~= false then
    fail("published primary disabled/visibility witness differs")
  end
  local rows = assert_snapshot(force, state.foreign_snapshot, selected.primary)
  local actual = snapshot_row(technology(force, selected.primary, "foreign primary"))
  return {
    profile = profile_name,
    force = state.foreign_index,
    primary = selected.primary,
    source_enabled = expected_primary.enabled,
    migration_actor_disabled = actor.disabled,
    post_configuration_enabled = actual.enabled,
    visibility = actual.visible,
    checked_technology_rows = rows,
  }
end

local function marker(stage, witness)
  local payload = {
    case = "py-published-reset-control",
    stage = stage,
    status = "passed",
    qualification = "published-only-configuration-observation-no-mir5-gameplay-or-save-qualification",
    witnesses = witness,
  }
  log("[MIR5_PY_PUBLISHED_RESET_CONTROL] " .. helpers.table_to_json(payload))
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json(payload))
end

script.on_configuration_changed(function()
  configured = true
  local witness = observe()
  log("[MIR5_PY_PUBLISHED_RESET_CONTROL] CONFIGURATION " .. helpers.table_to_json(witness))
end)

script.on_load(function()
  loaded, reload_logged = true, false
end)

script.on_event(defines.events.on_tick, function()
  if configured and not initial_saved then
    marker("initial", observe())
    initial_saved = true
    game.server_save(SAVE)
    return
  end
  if loaded and not reload_logged then
    marker("reload", observe())
    reload_logged = true
  end
end)
