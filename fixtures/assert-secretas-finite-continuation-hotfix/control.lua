-- Native assertion fixture for the reported Secretas finite worker-storage
-- continuation. It requires one exact F210 dependency tuple and the uncapped
-- MIR candidate selected by its caller. Caps and competing infinite owners
-- remain covered by the planner's source controls, not by this gameplay probe.

local MIR_VERSION = "4.2.21002"
local SECRETAS_VERSION = "1.0.37"
local FROZETA_VERSION = "1.0.1"
local FINITE_SEVEN = "worker-robots-storage-7"
local FINITE_EIGHT = "worker-robots-storage-8"
local CONTINUATION = "worker-robots-storage-9"
local PROGRESS = 0.42
local EPSILON = 0.000001

local loaded = false
local reload_checked = false

local function fail(message)
  error("MIR Secretas finite continuation validation failed: " .. message)
end

local function require_input(name, expected)
  if script.active_mods[name] ~= expected then
    fail("wrong input " .. name .. ": expected " .. expected .. ", got " .. tostring(script.active_mods[name]))
  end
end

local function profile(version)
  require_input("base", "2.1.21")
  require_input("space-age", "2.1.21")
  require_input("secretas", SECRETAS_VERSION)
  require_input("pretty-frozeta", FROZETA_VERSION)
  require_input("more-infinite-research", version)
end

local function contains(rows, name)
  for _, row in pairs(rows or {}) do
    if row.name == name then return true end
  end
  return false
end

local function ingredient_names(technology)
  local names = {}
  for _, ingredient in pairs(technology.research_unit_ingredients or {}) do
    names[#names + 1] = ingredient.name
  end
  table.sort(names)
  return names
end

local function has_ingredient(technology, name)
  for _, ingredient in pairs(technology.research_unit_ingredients or {}) do
    if ingredient.name == name then return true end
  end
  return false
end

local function storage_effect(technology)
  local matches = {}
  for _, effect in pairs(technology.prototype.effects or {}) do
    if effect.type == "worker-robot-storage" then matches[#matches + 1] = effect end
  end
  if #matches ~= 1 or type(matches[1].modifier) ~= "number" or matches[1].modifier <= 0 then
    fail("continuation lacks one useful worker robot storage effect")
  end
  return matches[1].modifier
end

local function technologies()
  local force = game.forces.player
  local seven = force.technologies[FINITE_SEVEN]
  local eight = force.technologies[FINITE_EIGHT]
  local continuation = force.technologies[CONTINUATION]
  if not seven or not eight or not continuation then fail("required finite chain or continuation is absent") end
  if seven.prototype.max_level == 4294967295 or eight.prototype.max_level == 4294967295 then
    fail("Secretas finite upstream levels became infinite")
  end
  if continuation.prototype.max_level ~= 4294967295 then fail("MIR level nine is not infinite") end
  if not contains(eight.prerequisites, FINITE_SEVEN) then fail("Secretas level eight lost level seven prerequisite") end
  if not contains(continuation.prerequisites, FINITE_EIGHT) then
    fail("MIR level nine does not follow Secretas level eight")
  end
  if not has_ingredient(continuation, "golden-science-pack")
      or not has_ingredient(continuation, "promethium-science-pack") then
    fail("MIR level nine lost Secretas level-eight science")
  end
  return force, seven, eight, continuation
end

local function queue(technology, level, progress)
  local force = game.forces.player
  if technology.level ~= level then fail("queued continuation level changed") end
  if not force.current_research or force.current_research.name ~= CONTINUATION then
    fail("continuation is no longer current research")
  end
  local rows = force.research_queue or {}
  if #rows ~= 1 or rows[1].name ~= CONTINUATION then fail("continuation queue changed") end
  if math.abs(force.research_progress - progress) > EPSILON then fail("continuation progress changed") end
end

local function verify_saved(stage)
  profile(MIR_VERSION)
  local state = storage.mir_secretas_finite_continuation
  if not state or not state.saved then fail("fixture state is absent") end
  local force, seven, eight, continuation = technologies()
  if not seven.researched or not eight.researched then fail("Secretas earned finite levels changed") end
  if seven.level ~= state.seven_level or eight.level ~= state.eight_level then
    fail("Secretas finite levels changed")
  end
  if continuation.level ~= state.continuation_level then fail("earned MIR continuation level changed") end
  if math.abs(force.worker_robots_storage_bonus - state.worker_robots_storage_bonus) > EPSILON then
    fail("awarded worker robot storage bonus changed")
  end
  if not has_ingredient(continuation, "golden-science-pack")
      or not has_ingredient(continuation, "promethium-science-pack") then
    fail("saved continuation science changed")
  end
  queue(continuation, state.continuation_level, state.progress)
  log("[mir-fixture] Secretas finite continuation verified stage=" .. stage
    .. ";level=" .. continuation.level .. ";bonus=" .. force.worker_robots_storage_bonus
    .. ";science=" .. table.concat(ingredient_names(continuation), ","))
end

script.on_init(function()
  profile(MIR_VERSION)
  local force, seven, eight, continuation = technologies()

  -- Complete the actual prerequisite graph rather than enabling every
  -- prototype.  The generated continuation may include a science-production
  -- gate in addition to Secretas level eight.
  for _, prerequisite in pairs(continuation.prerequisites) do
    prerequisite.research_recursive()
  end
  -- Keep the two reported upstream finite technologies explicit in the
  -- witness. Their flags apply their real finite effects before level nine is
  -- offered; they do not manufacture a replacement technology.
  seven.researched = true
  eight.researched = true
  if not seven.researched or not eight.researched or not continuation.enabled then
    fail("Secretas finite prerequisites did not enable MIR continuation")
  end

  local before = force.worker_robots_storage_bonus
  local modifier = storage_effect(continuation)
  local initial_level = continuation.level
  if initial_level ~= 9 then fail("MIR continuation did not begin at level nine") end
  if force.current_research then force.cancel_current_research() end
  force.research_queue = nil
  if not force.add_research(continuation) then fail("could not queue MIR level nine") end
  force.research_progress = 1
  storage.mir_secretas_finite_continuation = {
    phase = "awaiting-award",
    seven_level = seven.level,
    eight_level = eight.level,
    initial_continuation_level = initial_level,
    worker_robots_storage_bonus_before = before,
    worker_robot_storage_modifier = modifier
  }
  log("[mir-fixture] Secretas finite continuation source proof queued level=" .. initial_level)
end)

script.on_load(function()
  loaded = true
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir_secretas_finite_continuation
  if not state then return end
  if state.phase == "awaiting-award" then
    local force, seven, eight, continuation = technologies()
    if continuation.level == state.initial_continuation_level then return end
    if continuation.level ~= state.initial_continuation_level + 1 then fail("MIR continuation awarded an unexpected level") end
    local expected_bonus = state.worker_robots_storage_bonus_before + state.worker_robot_storage_modifier
    if math.abs(force.worker_robots_storage_bonus - expected_bonus) > EPSILON then
      fail("MIR continuation did not award the expected worker robot storage increment")
    end
    if force.current_research then force.cancel_current_research() end
    force.research_queue = nil
    if not force.add_research(continuation) then fail("could not queue next MIR continuation level") end
    force.research_progress = PROGRESS
    state.phase = "queued"
    state.saved = true
    state.seven_level = seven.level
    state.eight_level = eight.level
    state.continuation_level = continuation.level
    state.worker_robots_storage_bonus = force.worker_robots_storage_bonus
    state.progress = PROGRESS
    queue(continuation, state.continuation_level, state.progress)
    verify_saved("source")
    game.server_save("mir-secretas-finite-continuation")
    return
  end
  if state.phase == "queued" and loaded and not reload_checked then
    verify_saved("reload")
    reload_checked = true
  end
end)
