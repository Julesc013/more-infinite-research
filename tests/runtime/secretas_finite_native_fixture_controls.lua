-- Oracle controls for the Secretas finite-continuation native fixture.  The
-- mocked award transition only verifies the fixture callbacks; it is not
-- Factorio execution or a substitute for the selected F210 native scenario.
-- The caller supplies the exact fixture control.lua bytes in
-- MIR_SECRETAS_FINITE_CONTROL_SOURCE.

local checks = 0

local function check(value, label)
  assert(value, label)
  checks = checks + 1
end

local function world(overrides)
  overrides = overrides or {}
  local env = setmetatable({}, {__index = _G})
  local callbacks, saves, logs = {}, {}, {}
  env.storage = {}
  env.defines = {events = {on_tick = 1}}
  env.log = function(message) logs[#logs + 1] = message end
  env.script = {
    active_mods = {
      base = overrides.base or "2.1.21",
      ["space-age"] = overrides.space_age or "2.1.21",
      secretas = overrides.secretas or "1.0.37",
      ["pretty-frozeta"] = overrides.frozeta or "1.0.1",
      ["more-infinite-research"] = overrides.mir or "4.2.21002"
    },
    on_init = function(callback) callbacks.init = callback end,
    on_load = function(callback) callbacks.load = callback end,
    on_event = function(_, callback) callbacks.tick = callback end
  }

  local seven = {name = "worker-robots-storage-7", level = 1, researched = false,
    enabled = true, prerequisites = {}, prototype = {max_level = 1, effects = {
      {type = "worker-robot-storage", modifier = 1}
    }}}
  local eight = {name = "worker-robots-storage-8", level = 1, researched = false,
    enabled = true, prerequisites = {seven}, prototype = {max_level = 1, effects = {
      {type = "worker-robot-storage", modifier = 1}
    }}}
  local continuation = {name = "worker-robots-storage-9", level = 9,
    researched = false, enabled = true, prerequisites = {eight}, prototype = {
      max_level = 4294967295, effects = {{type = "worker-robot-storage", modifier = 1}}
    }, research_unit_ingredients = {
      {name = "automation-science-pack", amount = 1},
      {name = "logistic-science-pack", amount = 1},
      {name = "chemical-science-pack", amount = 1},
      {name = "production-science-pack", amount = 1},
      {name = "utility-science-pack", amount = 1},
      {name = "space-science-pack", amount = 1},
      {name = "metallurgic-science-pack", amount = 1},
      {name = "electromagnetic-science-pack", amount = 1},
      {name = "agricultural-science-pack", amount = 1},
      {name = "cryogenic-science-pack", amount = 1},
      {name = "golden-science-pack", amount = 1},
      {name = "promethium-science-pack", amount = 1}
    }}
  seven.research_recursive = function() seven.researched = true end
  eight.research_recursive = function()
    seven.research_recursive()
    eight.researched = true
  end

  -- `worker_robots_storage_bonus` deliberately uses the installed F210
  -- LuaForce spelling. There is no singular alias in this oracle.
  local force = {technologies = {
    [seven.name] = seven, [eight.name] = eight, [continuation.name] = continuation
  }, worker_robots_storage_bonus = 0, research_progress = 0, research_queue = {}}
  force.cancel_current_research = function()
    force.current_research = nil
    force.research_queue = {}
    force.research_progress = 0
  end
  force.add_research = function(technology)
    if not technology.enabled or force.current_research then return false end
    force.current_research = technology
    force.research_queue = {technology}
    force.research_progress = 0
    return true
  end
  env.game = {forces = {player = force}, server_save = function(name) saves[#saves + 1] = name end}
  assert(load(MIR_SECRETAS_FINITE_CONTROL_SOURCE, "secretas-finite-native-fixture", "t", env))()
  return env, callbacks, force, seven, eight, continuation, saves, logs
end

local function award_current(force)
  local technology = force.current_research
  check(technology and technology.name == "worker-robots-storage-9", "fixture queues MIR level nine")
  check(force.research_progress == 1, "fixture requests one complete level")
  technology.level = technology.level + 1 -- Engine award simulation; never used as native evidence.
  force.worker_robots_storage_bonus = force.worker_robots_storage_bonus + technology.prototype.effects[1].modifier
  force.current_research = nil
  force.research_queue = {}
  force.research_progress = 0
end

local function reach_saved_state()
  local env, callbacks, force, seven, eight, continuation, saves, logs = world()
  callbacks.init()
  check(seven.researched and eight.researched, "fixture preserves and completes the finite Secretas chain")
  check(continuation.level == 9 and continuation.prototype.max_level == 4294967295,
    "fixture starts from MIR level nine")
  award_current(force)
  callbacks.tick{tick = 1}
  check(continuation.level == 10 and force.worker_robots_storage_bonus == 1,
    "fixture observes one awarded cargo increment")
  check(force.current_research == continuation and #force.research_queue == 1
      and force.research_progress == 0.42, "fixture preserves queued next level and progress")
  check(#saves == 1 and saves[1] == "mir-secretas-finite-continuation", "fixture requests one source save")
  return env, callbacks, force, seven, eight, continuation, saves, logs
end

do
  local _, callbacks, _, _, _, _, _, logs = reach_saved_state()
  callbacks.load()
  callbacks.tick{tick = 2}
  check(logs[#logs]:find("stage=reload", 1, true) ~= nil, "fixture observes the saved state only after load")
end

for _, mutation in ipairs({
  {"lost finite level seven", function(_, _, seven) seven.researched = false end},
  {"lost finite level eight", function(_, _, _, eight) eight.researched = false end},
  {"lost awarded cargo bonus", function(_, force) force.worker_robots_storage_bonus = 0 end},
  {"changed queue", function(_, force) force.research_queue = {} end},
  {"changed progress", function(_, force) force.research_progress = 0.41 end},
  {"lost promethium science", function(_, _, _, _, continuation)
    continuation.research_unit_ingredients = {{name = "golden-science-pack", amount = 1}}
  end}
}) do
  local env, callbacks, force, seven, eight, continuation = reach_saved_state()
  mutation[2](env, force, seven, eight, continuation)
  callbacks.load()
  check(not pcall(callbacks.tick, {tick = 3}), "fixture rejects " .. mutation[1])
end

for _, overrides in ipairs({
  {mir = "4.2.21001"},
  {base = "2.1.20"},
  {secretas = "1.0.36"},
  {frozeta = "1.0.0"}
}) do
  local _, callbacks = world(overrides)
  check(not pcall(callbacks.init), "fixture rejects wrong exact source input")
end

print("MIR-SECRETAS-FINITE-NATIVE-FIXTURE-CONTROLS-PASS " .. checks)
