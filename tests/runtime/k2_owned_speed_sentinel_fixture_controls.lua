-- Execute the complete K2 upgrade fixture's source phase with a Factorio-shaped
-- LuaRemote boundary. This is intentionally not an engine migration model: it
-- catches lexical ordering and API-shape errors before a native slot is used.
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end

local function reject(callback, needle)
  local ok, reason = pcall(callback)
  check(not ok and tostring(reason):find(needle, 1, true) ~= nil,
    "expected rejection " .. needle .. ": " .. tostring(reason))
end

local infinite = 4294967295
local powder, crystal = "kr-imersite-powder", "kr-imersite-crystal"
local legacy, native = "recipe-prod-research_material_imersite-1", "kr-imersite-productivity"
local effect = function(recipe, change)
  return {type = "change-recipe-productivity", recipe = recipe, change = change}
end

local force_effect_fields = {
  "artillery_range_modifier", "beacon_distribution_modifier", "belt_stack_size_bonus",
  "bulk_inserter_capacity_bonus", "character_build_distance_bonus", "character_health_bonus",
  "character_inventory_slots_bonus", "character_item_drop_distance_bonus", "character_item_pickup_distance_bonus",
  "character_loot_pickup_distance_bonus", "character_reach_distance_bonus", "character_resource_reach_distance_bonus",
  "character_running_speed_modifier", "following_robots_lifetime_modifier", "inserter_stack_size_bonus",
  "laboratory_productivity_bonus", "laboratory_speed_modifier", "manual_crafting_speed_modifier",
  "manual_mining_speed_modifier", "train_braking_force_bonus", "worker_robots_battery_modifier",
  "worker_robots_speed_modifier", "worker_robots_storage_bonus"
}

local function new_technology(name, max_level, effects)
  return {
    name = name, level = 1, researched = false, enabled = true, visible_when_disabled = true,
    saved_progress = 0, prerequisites = {},
    prototype = {order = name, hidden = false, hidden_in_factoriopedia = false,
      max_level = max_level, prerequisites = {}, effects = effects},
    research_unit_ingredients = {{name = "automation-science-pack", amount = 1}},
    research_unit_count = 1, research_unit_count_formula = nil, research_unit_energy = 1
  }
end

local function new_force(name, index)
  local source = {
    name = name, index = index, current_research = nil, research_queue = {}, research_progress = 0,
    technologies = {
      [legacy] = new_technology(legacy, infinite, {effect(powder, 0.02)}),
      [native] = new_technology(native, 1, {effect(crystal, 0.10)})
    },
    recipes = {[powder] = {productivity_bonus = 0}, [crystal] = {productivity_bonus = 0.10}}
  }
  for _, field in ipairs(force_effect_fields) do source[field] = 0 end
  source.character_running_speed_modifier = 0.05
  source.research_all_technologies = function() end
  source.cancel_current_research = function()
    source.current_research = nil
    source.research_queue = {}
    source.research_progress = 0
  end
  source.reset_technology_effects = function()
    local technology = source.technologies[legacy]
    local completed = technology.researched and technology.level or math.max(0, technology.level - 1)
    source.recipes[powder].productivity_bonus = completed * 0.02
    source.recipes[crystal].productivity_bonus = 0.10
  end
  source.add_research = function(technology)
    source.current_research = technology
    return true
  end
  return source
end

local continuation = "recipe-prod-research_material_imersite-4"
local holder, continuation_holder = "mir-k2-imersite-staged-state-1", "mir-k2-imersite-continuation-state-4"

local function active_mods(mir_version)
  return {
    base = "2.1.22", Krastorio2 = "2.1.4", ["Krastorio2-spaced-out"] = "2.0.19",
    ["more-infinite-research"] = mir_version,
    ["mir-fixture-assert-k2-imersite-460-to-470-upgrade"] = "0.1.4700",
    ["aaa-mir47-owned-speed-sentinel"] = "0.1.4700"
  }
end

local function new_environment(prior)
  local callbacks, logs, writes = {configuration = {}}, {}, {}
  local storage, game, settings, remote, private_interfaces, saves
  if prior then
    storage, game, settings = prior.env.storage, prior.env.game, prior.env.settings
    remote, private_interfaces, saves = prior.env.remote, prior.private_interfaces, prior.saves
  else
    local forces, next_force_index = {player = new_force("player", 1)}, 2
    storage, game = {}, {forces = forces}
    settings = {startup = {["ips-max-level-research_material_imersite"] = {value = 0}}}
    remote, private_interfaces, saves = {interfaces = {}}, {}, {}
    game.create_force = function(name)
      check(forces[name] == nil, "fixture creates each force once")
      local force = new_force(name, next_force_index)
      next_force_index = next_force_index + 1
      forces[name] = force
      return force
    end
    game.server_save = function(name)
      saves[#saves + 1] = name
    end
    remote.add_interface = function(name, methods)
      check(remote.interfaces[name] == nil, "companion interface is registered once")
      local exposed = {}
      for method, callback in pairs(methods) do
        check(type(callback) == "function", "companion method is callable privately")
        exposed[method] = true -- LuaRemote.interfaces reports booleans, not methods.
      end
      remote.interfaces[name] = exposed
      private_interfaces[name] = methods
    end
    remote.call = function(name, method, ...)
      local methods = private_interfaces[name]
      assert(methods and type(methods[method]) == "function", "private remote dispatcher rejects unknown method")
      return methods[method](...)
    end
  end
  local mir_version = prior and prior.env.script.active_mods["more-infinite-research"] or "4.6.21000"
  local env = setmetatable({
    storage = storage,
    game = game,
    settings = settings,
    helpers = {
      table_to_json = function(_) return "host-fixture-json" end,
      write_file = function(path, value) writes[path] = value end
    },
    script = {
      active_mods = active_mods(mir_version),
      on_init = function(callback) callbacks.init = callback end,
      on_configuration_changed = function(callback) callbacks.configuration[#callbacks.configuration + 1] = callback end,
      on_load = function(callback) callbacks.load = callback end,
      on_event = function(event, callback)
        check(event == 1, "fixture registers only the on_tick event")
        callbacks.tick = callback
      end
    },
    defines = {events = {on_tick = 1}},
    remote = remote,
    log = function(message) logs[#logs + 1] = message end
  }, {__index = _G})
  return {
    env = env, callbacks = callbacks, logs = logs, writes = writes, saves = saves,
    private_interfaces = private_interfaces
  }
end

local function load_full_fixture(fixture)
  -- Keep the entire real fixture chunk, so export_state closes over the real
  -- local owned_sentinel_call binding. Extracting a helper would miss lexical
  -- ordering and LuaRemote-shape faults.
  local chunk = assert(load(MIR47_K2_FULL_FIXTURE_SOURCE .. "\nreturn export_state", "k2-full-fixture", "t", fixture.env))
  return chunk()
end

local function run_configuration_callbacks(fixture)
  check(#fixture.callbacks.configuration == 2,
    "source and target fixture registration exposes the companion and fixture configuration callbacks")
  for _, callback in ipairs(fixture.callbacks.configuration) do callback({}) end
end

local function add_holder(name, minimum_level, source)
  local technology = new_technology(name, infinite, {effect(powder, 0.02)})
  technology.enabled, technology.visible_when_disabled = false, false
  technology.level, technology.researched, technology.saved_progress = minimum_level, false, 0
  technology.prototype.hidden, technology.prototype.hidden_in_factoriopedia = true, true
  technology.research_unit_ingredients = source.research_unit_ingredients
  technology.research_unit_count = source.research_unit_count
  technology.research_unit_count_formula = source.research_unit_count_formula
  technology.research_unit_energy = source.research_unit_energy
  return technology
end

-- This is deliberately a narrow candidate-state adapter for the real fixture
-- lifecycle. It does not model Factorio's prototype migration; native coverage
-- remains responsible for it. It makes the existing full state oracle prove
-- that callback ordering cannot label an unsaved upgrade tick as a reload.
local function apply_candidate_state(fixture)
  fixture.env.script.active_mods["more-infinite-research"] = "4.7.21000"
  for _, force in pairs(fixture.env.game.forces) do
    local source = force.technologies[legacy]
    local completed = source.level - 1
    source.prototype.max_level = 3
    local next = new_technology(continuation, infinite, {effect(powder, 0.02)})
    next.level = 4
    next.prerequisites = {{name = legacy}}
    force.technologies[continuation] = next
    force.technologies[holder] = add_holder(holder, 1, source)
    force.technologies[continuation_holder] = add_holder(continuation_holder, 4, source)
    if completed >= 3 then
      source.level, source.researched = 3, true
      next.level, next.researched = completed + 1, false
      force.research_queue, force.current_research = {next}, next
    end
  end
  -- The native observation established that prototype migration removes the
  -- fixture's owned contribution before configuration callbacks. Recreate only
  -- that owned-input condition so the companion callback restores it.
  for _, name in ipairs({"mir-k2-migration-zero", "mir-k2-migration-low", "player", "mir-k2-migration-high"}) do
    fixture.env.game.forces[name].character_running_speed_modifier = 0.05
  end
end

local function count_log(logs, needle)
  local matches = 0
  for _, message in ipairs(logs) do
    if message:find(needle, 1, true) then matches = matches + 1 end
  end
  return matches
end

local fixture = new_environment()
assert(load(MIR47_OWNED_SPEED_SENTINEL_SOURCE, "owned-speed-sentinel", "t", fixture.env))()
local export_state = load_full_fixture(fixture)
check(type(export_state) == "function", "complete fixture returns its lexical exporter")
check(type(fixture.callbacks.init) == "function", "complete fixture registered source init")
check(type(fixture.callbacks.load) == "function" and type(fixture.callbacks.tick) == "function",
  "complete fixture registered separate load and tick lifecycle callbacks")
check(fixture.env.remote.interfaces["aaa-mir47-owned-speed-sentinel"].capture == true
  and fixture.env.remote.interfaces["aaa-mir47-owned-speed-sentinel"].snapshot == true,
  "host LuaRemote.interfaces uses Factorio boolean method markers")
fixture.callbacks.init()
check(fixture.writes["mir-upgrade-full-state-source.json"] == "host-fixture-json",
  "real source initialization exported a full-state record through the companion")
local snapshot = fixture.env.remote.call("aaa-mir47-owned-speed-sentinel", "snapshot")
check(snapshot.phase == "captured" and snapshot.records["mir-k2-migration-zero"] ~= nil
  and snapshot.records.player ~= nil and snapshot.records["mir-k2-migration-high"] ~= nil,
  "real source fixture captured each exact seeded force")
for _, name in ipairs({"mir-k2-migration-zero", "mir-k2-migration-low", "player", "mir-k2-migration-high"}) do
  check(math.abs(fixture.env.game.forces[name].character_running_speed_modifier - 0.175) < 0.000001,
    "real source fixture receives exactly one owned speed contribution for " .. name)
end
export_state("host-source-export")
check(fixture.writes["mir-upgrade-full-state-host-source-export.json"] == "host-fixture-json",
  "returned lexical exporter uses the same bound companion call")

-- Factorio invokes on_load for the predecessor save before the target
-- configuration callback. This must not make the upgrade process eligible to
-- emit a reload result.
fixture.callbacks.load()
apply_candidate_state(fixture)
run_configuration_callbacks(fixture)
check(fixture.env.storage.mir_k2_460_to_470.phase == "upgrade-verified",
  "configuration verification leaves an explicit pre-save lifecycle state")
check(#fixture.saves == 0 and fixture.writes["mir-upgrade-full-state-reload.json"] == nil,
  "configuration callback neither requests a server save nor records a reload")
fixture.callbacks.tick()
check(#fixture.saves == 1 and fixture.saves[1] == "mir-4721000-upgraded",
  "first post-configuration tick requests exactly the named upgraded-save")
check(fixture.env.storage.mir_k2_460_to_470.phase == "save-pending",
  "save request persists the cold-reload admission state before server save")
check(fixture.writes["mir-upgrade-full-state-reload.json"] == nil
    and count_log(fixture.logs, "upgraded save reload proof complete") == 0,
  "the unsaved upgrade process cannot label its first tick as a reload")
fixture.callbacks.tick()
check(#fixture.saves == 1 and fixture.writes["mir-upgrade-full-state-reload.json"] == nil,
  "repeated upgrade ticks cannot request another save or create a reload record")

-- A fresh control chunk represents the actual cold process after the saved
-- target state is loaded. Each cold process verifies the persisted state once;
-- neither can request another upgrade save.
local cold_one = new_environment(fixture)
load_full_fixture(cold_one)
cold_one.callbacks.load()
cold_one.callbacks.tick()
check(cold_one.writes["mir-upgrade-full-state-reload.json"] == "host-fixture-json"
    and count_log(cold_one.logs, "upgraded save reload proof complete") == 1,
  "first cold on_load process emits the reload acceptance record")
check(#fixture.saves == 1, "first cold reload does not request another upgrade save")
cold_one.callbacks.tick()
check(count_log(cold_one.logs, "upgraded save reload proof complete") == 1,
  "one cold process cannot emit duplicate reload acceptance records")

local cold_two = new_environment(fixture)
load_full_fixture(cold_two)
cold_two.callbacks.load()
cold_two.callbacks.tick()
check(cold_two.writes["mir-upgrade-full-state-reload.json"] == "host-fixture-json"
    and count_log(cold_two.logs, "upgraded save reload proof complete") == 1,
  "second cold on_load process independently verifies the same saved target state")
check(#fixture.saves == 1, "two cold reloads still retain the single upgrade-save request")

-- A callable value in LuaRemote.interfaces is not the Factorio contract. The
-- fixture must reject a missing public marker even while private dispatch can
-- still invoke the method; this prevents host mocks from masking that mismatch.
fixture.env.remote.interfaces["aaa-mir47-owned-speed-sentinel"].snapshot = false
reject(function() export_state("host-bad-interface") end, "interface or method is unavailable")

return checks
