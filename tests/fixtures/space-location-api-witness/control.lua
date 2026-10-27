-- This disposable fixture observes Factorio's 2.1 LuaForce space-location
-- methods.  It owns only its direct lock/unlock calls and the small saved
-- witness state below; it neither earns research nor changes MIR state.
local CASE = "space-location-api-witness"
local STORAGE_KEY = "mir5_space_location_api_witness"
local PRIMARY_LOCATION = "vulcanus"
local UNRESEARCHED_LOCATION = "gleba"
local SPACE_TECHNOLOGY = "planet-discovery-vulcanus"
local UNRESEARCHED_TECHNOLOGY = "planet-discovery-gleba"
local SENTINEL_FORCE = "mir5-space-location-api-witness-sentinel"
local SENTINEL_TECHNOLOGY = "automation"
local SAVE_NAME = "mir5-native-complete"

local reload_pending = false

local function fail(message)
  error("[mir5-space-location-api-witness] " .. message)
end

local function player_force()
  local force = game.forces.player
  if force == nil or force.valid == false then fail("player force is absent") end
  return force
end

local function technology(force, name)
  local value = force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. name) end
  return value
end

local function assert_custom_table(value, label)
  if value == nil or value.object_name ~= "LuaCustomTable" then
    fail(label .. " is not a LuaCustomTable")
  end
end

local function assert_space_effect(force)
  assert_custom_table(force.technologies, "force technologies")
  local value = technology(force, SPACE_TECHNOLOGY)
  if value.researched ~= false then fail("space-location technology must remain unresearched") end
  local prototype = value.prototype
  if prototype == nil or prototype.object_name ~= "LuaTechnologyPrototype" then
    fail("space-location technology prototype shape differs")
  end
  local effects = prototype.effects
  assert_custom_table(effects, "space-location technology effects")
  if #effects ~= 2 then fail("space-location technology effect count differs") end
  local location_effect = effects[1]
  local travel_effect = effects[2]
  if location_effect == nil or location_effect.type ~= "unlock-space-location"
      or location_effect.space_location ~= PRIMARY_LOCATION then
    fail("space-location technology unlock effect differs")
  end
  if travel_effect == nil or travel_effect.type ~= "unlock-travel-to-space-platforms"
      or travel_effect.modifier ~= true then
    fail("space-location technology travel effect differs")
  end
  return {
    technology = value.name,
    researched = value.researched,
    prototype_object_name = prototype.object_name,
    force_technologies_object_name = force.technologies.object_name,
    effects_object_name = effects.object_name,
    effect_count = #effects,
    effect_type = location_effect.type,
    effect_space_location = location_effect.space_location,
    travel_effect_type = travel_effect.type,
    travel_effect_modifier = travel_effect.modifier
  }
end

local function establish_sentinel()
  local force = game.forces[SENTINEL_FORCE]
  if force == nil then force = game.create_force(SENTINEL_FORCE) end
  if force == nil or force.valid == false then fail("sentinel force is absent") end
  force.enable_all_prototypes()
  local probe = technology(force, SENTINEL_TECHNOLOGY)
  if probe.researched ~= false then probe.researched = false end
  force.research_queue_enabled = true
  force.research_queue = {probe}
  if force.current_research ~= probe or #force.research_queue ~= 1
      or force.research_queue[1] ~= probe then
    fail("sentinel research queue was not established")
  end
  return force
end

local function assert_sentinel(force)
  local probe = technology(force, SENTINEL_TECHNOLOGY)
  if force.research_queue_enabled ~= true or force.current_research ~= probe
      or #force.research_queue ~= 1 or force.research_queue[1] ~= probe then
    fail("unrelated sentinel force or queue changed")
  end
end

local function run_initial()
  local force = player_force()
  local sentinel = establish_sentinel()
  local effect = assert_space_effect(force)
  local unresearched = technology(force, UNRESEARCHED_TECHNOLOGY)
  if unresearched.researched ~= false then fail("unresearched location technology is researched") end

  force.lock_space_location(PRIMARY_LOCATION)
  local locked = force.is_space_location_unlocked(PRIMARY_LOCATION)
  if locked ~= false then fail("fixture-owned lock did not report false") end
  force.unlock_space_location(PRIMARY_LOCATION)
  local unlocked = force.is_space_location_unlocked(PRIMARY_LOCATION)
  if unlocked ~= true then fail("fixture-owned unlock did not report true") end
  force.unlock_space_location(PRIMARY_LOCATION)
  local duplicate_unlocked = force.is_space_location_unlocked(PRIMARY_LOCATION)
  if duplicate_unlocked ~= true then fail("duplicate fixture-owned unlock changed state") end

  force.lock_space_location(UNRESEARCHED_LOCATION)
  local unresearched_locked = force.is_space_location_unlocked(UNRESEARCHED_LOCATION)
  if unresearched_locked ~= false then fail("unresearched location is not locked") end
  if technology(force, SPACE_TECHNOLOGY).researched ~= false then
    fail("fixture-owned location calls changed research state")
  end
  assert_sentinel(sentinel)

  storage[STORAGE_KEY] = {
    primary_location = PRIMARY_LOCATION,
    unresearched_location = UNRESEARCHED_LOCATION,
    sentinel_force = sentinel.name,
    sentinel_technology = SENTINEL_TECHNOLOGY,
    effect = effect,
    locked = locked,
    unlocked = unlocked,
    duplicate_unlocked = duplicate_unlocked,
    unresearched_location_unlocked = unresearched_locked
  }
end

local function assert_saved_witness()
  local state = storage[STORAGE_KEY]
  if state == nil then fail("saved witness state is absent") end
  local force = player_force()
  local sentinel = game.forces[state.sentinel_force]
  if sentinel == nil or sentinel.valid == false then fail("saved sentinel force is absent") end
  if force.is_space_location_unlocked(state.primary_location) ~= true
      or force.is_space_location_unlocked(state.unresearched_location) ~= false then
    fail("saved space-location state differs")
  end
  assert_sentinel(sentinel)
  local effect = assert_space_effect(force)
  if effect.effect_space_location ~= state.effect.effect_space_location
      or effect.effect_count ~= state.effect.effect_count then
    fail("saved prototype effect witness differs")
  end
  return state
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE,
    stage = stage,
    status = "passed",
    witnesses = {
      fixture_owned_lock_then_unlock = true,
      primary_location = state.primary_location,
      locked_after_lock = state.locked,
      unlocked_after_unlock = state.unlocked,
      duplicate_unlock_unchanged = state.duplicate_unlocked,
      unresearched_location = state.unresearched_location,
      unresearched_location_unlocked = state.unresearched_location_unlocked,
      sentinel_force = state.sentinel_force,
      sentinel_queue_technology = state.sentinel_technology,
      effect = state.effect,
      researched_earned = false,
      gameplay_claim = false
    }
  }))
end

script.on_init(function()
  run_initial()
  local state = assert_saved_witness()
  marker("initial", state)
  game.server_save(SAVE_NAME)
end)

script.on_load(function()
  reload_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not reload_pending then return end
  local state = assert_saved_witness()
  marker("reload", state)
  reload_pending = false
end)
