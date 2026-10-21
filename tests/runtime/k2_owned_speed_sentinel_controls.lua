-- Focused host controls for the test-only owned speed sentinel. They model only
-- its Factorio API boundary; a native run must still prove real callback order.
local checks = 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end

local function close(left, right)
  return type(left) == "number" and math.abs(left - right) < 0.000001
end

local function reject(callback, needle)
  local ok, reason = pcall(callback)
  check(not ok and tostring(reason):find(needle, 1, true) ~= nil,
    "expected rejection " .. needle .. ": " .. tostring(reason))
end

local function new_environment(source_speed)
  local callbacks, logs = {}, {}
  local force = {index = 17, character_running_speed_modifier = source_speed}
  local env = setmetatable({
    storage = {},
    game = {forces = {alpha = force}},
    script = {active_mods = {base = "2.1.22", ["more-infinite-research"] = "4.6.21000"},
    on_configuration_changed = function(callback) callbacks.configuration = callback end},
    remote = {interfaces = {}},
    log = function(message) logs[#logs + 1] = message end
  }, {__index = _G})
  local remote_methods = {}
  env.remote.add_interface = function(name, methods)
    check(env.remote.interfaces[name] == nil, "interface must be registered once")
    local exposed = {}
    for method, callback in pairs(methods) do
      assert(type(callback) == "function", "registered remote method must be callable")
      exposed[method] = true -- Factorio's LuaRemote.interfaces contract.
    end
    env.remote.interfaces[name] = exposed
    remote_methods[name] = methods
  end
  env.remote.call = function(name, method, ...)
    local methods = remote_methods[name]
    assert(methods and type(methods[method]) == "function", "unknown remote call")
    return methods[method](...)
  end
  assert(load(MIR47_OWNED_SPEED_SENTINEL_SOURCE, "owned-speed-sentinel", "t", env))()
    check(type(callbacks.configuration) == "function", "configuration callback is registered")
  check(env.remote.interfaces["aaa-mir47-owned-speed-sentinel"].capture == true
    and env.remote.interfaces["aaa-mir47-owned-speed-sentinel"].snapshot == true,
    "host remote.interfaces matches Factorio boolean method map")
  return {env = env, force = force, callbacks = callbacks, logs = logs}
end

local function capture_and_seal(fixture)
  local record = fixture.env.remote.call("aaa-mir47-owned-speed-sentinel", "capture", "alpha")
  check(close(record.delta, 0.125), "the stored owned delta is exact")
  check(close(fixture.force.character_running_speed_modifier, 0.175), "source capture applies only the owned delta")
  local state = fixture.env.remote.call("aaa-mir47-owned-speed-sentinel", "seal_source", {"alpha"})
  check(state.phase == "captured" and state.records.alpha.force_index == 17, "source state is sealed to exact force identity")
end

local fixture = new_environment(0.05)
capture_and_seal(fixture)
fixture.env.script.active_mods["more-infinite-research"] = "4.7.21000"
fixture.force.character_running_speed_modifier = 0.05 -- observed post-prototype-migration baseline
fixture.callbacks.configuration()
local restored = fixture.env.remote.call("aaa-mir47-owned-speed-sentinel", "snapshot")
check(restored.phase == "restored" and restored.configuration_changed_events == 1, "target restoration is recorded")
check(close(restored.records.alpha.before_target, 0.05) and close(restored.records.alpha.restored_total, 0.175), "target record binds baseline and owned result")
check(close(fixture.force.character_running_speed_modifier, 0.175), "target adds the stored delta without assigning an aggregate")
fixture.callbacks.configuration()
check(close(fixture.force.character_running_speed_modifier, 0.175), "repeat configuration callback is idempotent")
check(fixture.env.remote.call("aaa-mir47-owned-speed-sentinel", "snapshot").configuration_changed_events == 2, "repeat callback is retained as observation only")

-- A later MIR-like reset cannot be silently covered up by replaying the owned
-- delta. The companion rejects it and leaves the unexpected state visible.
fixture.force.character_running_speed_modifier = 0.05
reject(function() fixture.callbacks.configuration() end, "owned contribution changed after restoration")
check(close(fixture.force.character_running_speed_modifier, 0.05), "late reset is not silently repaired or double-counted")

local duplicate = new_environment(0.05)
duplicate.env.remote.call("aaa-mir47-owned-speed-sentinel", "capture", "alpha")
reject(function() duplicate.env.remote.call("aaa-mir47-owned-speed-sentinel", "capture", "alpha") end, "already captured")
reject(function() duplicate.env.remote.call("aaa-mir47-owned-speed-sentinel", "seal_source", {"alpha", "alpha"}) end, "not unique")

local retained = new_environment(0.05)
capture_and_seal(retained)
retained.env.script.active_mods["more-infinite-research"] = "4.7.21000"
-- If the engine did not reset the contribution, adding it again would be a
-- bug. Refuse rather than infer which total a third party intended.
reject(function() retained.callbacks.configuration() end, "refusing to add it twice")
check(close(retained.force.character_running_speed_modifier, 0.175), "already-retained aggregate is not overwritten")

local unknown = new_environment(0.05)
capture_and_seal(unknown)
unknown.env.script.active_mods["more-infinite-research"] = "4.7.21000"
unknown.force.character_running_speed_modifier = 0.08
reject(function() unknown.callbacks.configuration() end, "refusing to invent prior state")
check(close(unknown.force.character_running_speed_modifier, 0.08), "unknown target aggregate remains untouched")

local wrong_target = new_environment(0.05)
capture_and_seal(wrong_target)
wrong_target.env.script.active_mods["more-infinite-research"] = "4.7.21001"
wrong_target.force.character_running_speed_modifier = 0.05
reject(function() wrong_target.callbacks.configuration() end, "target MIR identity differs")
check(close(wrong_target.force.character_running_speed_modifier, 0.05), "wrong target never receives the owned delta")

-- This is a host-dispatch model, not a claim about Factorio callback ordering.
-- It proves the companion restores before a later callback and then refuses a
-- destructive later write on the next reconciliation instead of masking it.
local ordered = new_environment(0.05)
capture_and_seal(ordered)
ordered.env.script.active_mods["more-infinite-research"] = "4.7.21000"
ordered.force.character_running_speed_modifier = 0.05
local order = {}
order[#order + 1] = "owned-sentinel"
ordered.callbacks.configuration()
order[#order + 1] = "later-mir"
check(table.concat(order, ",") == "owned-sentinel,later-mir" and close(ordered.force.character_running_speed_modifier, 0.175), "host dispatch shows the sentinel's required before-MIR position")
ordered.force.character_running_speed_modifier = 0.05
reject(function() ordered.callbacks.configuration() end, "owned contribution changed after restoration")

return checks
