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

local function new_environment()
  local callbacks, logs, writes, private_interfaces = {}, {}, {}, {}
  local forces, next_force_index = {player = new_force("player", 1)}, 2
  local env = setmetatable({
    storage = {},
    game = {forces = forces},
    settings = {startup = {["ips-max-level-research_material_imersite"] = {value = 0}}},
    helpers = {
      table_to_json = function(_) return "host-fixture-json" end,
      write_file = function(path, value) writes[path] = value end
    },
    script = {
      active_mods = {
        base = "2.1.22", Krastorio2 = "2.1.4", ["Krastorio2-spaced-out"] = "2.0.19",
        ["more-infinite-research"] = "4.6.21000",
        ["mir-fixture-assert-k2-imersite-460-to-470-upgrade"] = "0.1.4700",
        ["aaa-mir47-owned-speed-sentinel"] = "0.1.4700"
      },
      on_init = function(callback) callbacks.init = callback end,
      on_configuration_changed = function(callback) callbacks.configuration = callback end,
      on_load = function(callback) callbacks.load = callback end,
      on_event = function(event, callback)
        check(event == 1, "fixture registers only the on_tick event")
        callbacks.tick = callback
      end
    },
    defines = {events = {on_tick = 1}},
    remote = {interfaces = {}},
    log = function(message) logs[#logs + 1] = message end
  }, {__index = _G})
  env.game.create_force = function(name)
    check(forces[name] == nil, "fixture creates each force once")
    local force = new_force(name, next_force_index)
    next_force_index = next_force_index + 1
    forces[name] = force
    return force
  end
  env.game.server_save = function() end
  env.remote.add_interface = function(name, methods)
    check(env.remote.interfaces[name] == nil, "companion interface is registered once")
    local exposed = {}
    for method, callback in pairs(methods) do
      check(type(callback) == "function", "companion method is callable privately")
      exposed[method] = true -- LuaRemote.interfaces reports booleans, not methods.
    end
    env.remote.interfaces[name] = exposed
    private_interfaces[name] = methods
  end
  env.remote.call = function(name, method, ...)
    local methods = private_interfaces[name]
    assert(methods and type(methods[method]) == "function", "private remote dispatcher rejects unknown method")
    return methods[method](...)
  end
  return {env = env, callbacks = callbacks, logs = logs, writes = writes, private_interfaces = private_interfaces}
end

local fixture = new_environment()
assert(load(MIR47_OWNED_SPEED_SENTINEL_SOURCE, "owned-speed-sentinel", "t", fixture.env))()
-- Keep the entire real fixture chunk, so export_state closes over the real
-- local owned_sentinel_call binding. Extracting a helper would miss the old
-- lexical forward-reference defect.
local full_chunk = assert(load(MIR47_K2_FULL_FIXTURE_SOURCE .. "\nreturn export_state", "k2-full-fixture", "t", fixture.env))
local export_state = full_chunk()
check(type(export_state) == "function", "complete fixture returns its lexical exporter")
check(type(fixture.callbacks.init) == "function", "complete fixture registered source init")
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

-- A callable value in LuaRemote.interfaces is not the Factorio contract. The
-- fixture must reject a missing public marker even while private dispatch can
-- still invoke the method; this prevents host mocks from masking that mismatch.
fixture.env.remote.interfaces["aaa-mir47-owned-speed-sentinel"].snapshot = false
reject(function() export_state("host-bad-interface") end, "interface or method is unavailable")

return checks