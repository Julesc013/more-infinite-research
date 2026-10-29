local KEY = "mir5_legacy_boolean_cap"
local CASE = "legacy-boolean-cap-published-400"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-legacy-boolean-cap"
local GEAR = "recipe-prod-research_gears-1"
local RECIPE = "iron-gear-wheel"
local PROBE = "braking-force-1"
local FOREIGN = "mir5-legacy-boolean-cap-foreign"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack",
}
local UINT32_MAX = 4294967295
local INITIAL_PACKS = 8
local LAB_ENERGY = 100000000
local DEADLINE = 18000

local loaded, reload_logged = nil, false

local function fail(message) error("[mir5-legacy-boolean-cap-source] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function status(force)
  local value = technology(force, GEAR)
  local recipe = force.recipes[RECIPE]
  if recipe == nil then fail("gear recipe is absent") end
  return {
    level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    bonus = recipe.productivity_bonus, saved_progress = value.saved_progress,
  }
end

local function copy_status(value)
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible, maximum = value.maximum, bonus = value.bonus,
    saved_progress = value.saved_progress}
end

local function assert_status(actual, expected, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible ~= expected.visible
      or actual.maximum ~= expected.maximum or not close(actual.bonus, expected.bonus) then
    fail(label .. " native gear state differs")
  end
  if expected.saved_progress ~= nil and not close(actual.saved_progress, expected.saved_progress) then
    fail(label .. " saved progress differs")
  end
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end

local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue or {}) do queue[index] = name end
  return {current = value.current, queue = queue, progress = value.progress}
end

local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites or {}) do prerequisite.research_recursive() end
end

local function read_lab(state)
  local value = state.lab
  if value == nil or value.valid == false then fail("player lab is absent") end
  local inventory = value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("player lab inventory is absent") end
  return value, inventory
end

local function recharge_lab(state)
  local value, inventory = read_lab(state)
  value.energy = LAB_ENERGY
  if value.energy <= 0 then fail("player lab has no power") end
  return inventory
end

local function freeze_lab(state)
  local value = read_lab(state)
  value.energy = 0
  if value.energy ~= 0 then fail("player lab did not freeze after the final source completion") end
end

local function assert_acceleration(value)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not reduce only gear count and time")
  end
  for _, name in ipairs(SCIENCE) do
    local found = false
    for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
      if ingredient.name == name and ingredient.amount == 1 then found = true end
    end
    if not found then fail("native gear science is absent: " .. name) end
  end
end

local function assert_foreign(force, expected)
  if force == nil or force.valid == false or force.name ~= FOREIGN then fail("foreign witness is absent") end
  assert_status(status(force), {level = 1, researched = false, enabled = false, visible = false,
    maximum = UINT32_MAX, bonus = 0}, "foreign gear")
  local actual = queue_snapshot(force)
  if actual.current ~= PROBE or #actual.queue ~= 1 or actual.queue[1] ~= PROBE
      or not close(actual.progress, 0.42) then
    fail("foreign queue or progress differs")
  end
  if expected and (expected.current ~= actual.current or #expected.queue ~= #actual.queue
      or expected.queue[1] ~= actual.queue[1] or not close(expected.progress, actual.progress)) then
    fail("foreign source queue differs")
  end
  return actual
end

local function assert_completed(state)
  if state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs" then
    fail("source did not retain exactly two real gear completions")
  end
  local player = status(game.forces.player)
  assert_status(player, {level = 3, researched = false, enabled = false, visible = true,
    maximum = UINT32_MAX, bonus = .20, saved_progress = .27}, "published capped player")
  if game.forces.player.current_research ~= nil or #(game.forces.player.research_queue or {}) ~= 0 then
    fail("capped player gear queue survived")
  end
  local _, inventory = read_lab(state)
  for _, name in ipairs(SCIENCE) do
    if inventory.get_item_count(name) ~= INITIAL_PACKS - 2 then
      fail("real lab consumption differs for " .. name)
    end
  end
  assert_foreign(game.forces[state.foreign_force_index], state.foreign_queue)
  return player
end

local function marker(stage, state)
  local player = status(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = CASE, status = "passed", qualification = "native-runner-readback-required",
    witnesses = {source_mir = state.source_mir, actual_lab_completions = state.actual_lab_completions,
      player_level = player.level, player_enabled = player.enabled,
      player_visible_when_disabled = player.visible, saved_progress = player.saved_progress,
      productivity_bonus = player.bonus, foreign_disabled = status(game.forces[state.foreign_force_index]).enabled == false,
      foreign_queue_progress = state.foreign_queue.progress, on_load_read_only = stage == "reload"},
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "4.0.20000"
      or script.active_mods[FIXTURE] ~= "0.1.0" then fail("source closure differs") end
  if storage[KEY] ~= nil then fail("source fixture storage already exists") end
  if settings.startup["ips-max-level-research_gears"].value ~= 2
      or settings.startup["ips-effect-per-level-research_gears"].value ~= 10 then
    fail("source fixture settings differ")
  end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  local gear = technology(player, GEAR)
  assert_acceleration(gear)
  assert_status(status(player), {level = 1, researched = false, enabled = true, visible = true,
    maximum = UINT32_MAX, bonus = 0, saved_progress = 0}, "published initial player")
  prerequisites(gear)

  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  local foreign_gear = technology(foreign, GEAR)
  prerequisites(foreign_gear)
  foreign.reset_technology_effects()
  foreign_gear.enabled = false
  foreign_gear.visible_when_disabled = false
  local probe = technology(foreign, PROBE)
  prerequisites(probe)
  if foreign.add_research(probe) ~= true then fail("could not queue foreign probe") end
  foreign.research_progress = .42

  local entity = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = player}
  if entity == nil or entity.valid == false then fail("could not create real player lab") end
  local state = {phase = "await-first-lab", source_mir = script.active_mods["more-infinite-research"],
    actual_lab_completions = 0, milestone = "unstarted", foreign_force_index = foreign.index,
    foreign_queue = assert_foreign(foreign), lab = entity, deadline_tick = game.tick + DEADLINE}
  storage[KEY] = state
  local inventory = recharge_lab(state)
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name = name, count = INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("could not insert native science " .. name)
    end
  end
  if player.add_research(gear) ~= true then fail("could not queue first native gear research") end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= GEAR then return end
  if state.phase ~= "await-first-lab" and state.phase ~= "await-second-lab" then
    fail("unexpected native gear completion phase")
  end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions == 1 then
    state.phase = "await-second-queue"
  elseif state.actual_lab_completions == 2 then
    state.phase = "await-published-cap"
    freeze_lab(state)
  else
    fail("source completed more than two gear levels")
  end
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "completed"
    and {player = copy_status(state.player_cap), foreign = copy_queue(state.foreign_queue)} or nil
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture storage is absent") end
  if state.phase == "completed" then
    if loaded and not reload_logged then
      assert_status(assert_completed(state), loaded.player, "source cold reload player")
      assert_foreign(game.forces[state.foreign_force_index], loaded.foreign)
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("source labs did not complete") end
  if state.phase == "await-first-lab" or state.phase == "await-second-lab" then
    recharge_lab(state)
  elseif state.phase == "await-second-queue" then
    if game.forces.player.current_research == nil then
      if game.forces.player.add_research(technology(game.forces.player, GEAR)) ~= true then
        fail("could not queue second native gear research")
      end
      state.phase = "await-second-lab"
    end
    recharge_lab(state)
  elseif state.phase == "await-published-cap" then
    local player = status(game.forces.player)
    if player.enabled == false and player.visible == true then
      technology(game.forces.player, GEAR).saved_progress = .27
      state.milestone = "actual2labs"
      state.phase = "completed"
      state.player_cap = copy_status(assert_completed(state))
      marker("initial", state)
      game.server_save(SAVE)
    end
  else
    fail("source fixture phase is invalid")
  end
end)
