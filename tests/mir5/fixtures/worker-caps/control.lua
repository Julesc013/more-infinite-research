local NAME = "worker-robots-speed-7"
local KEY = "mir5_native_worker_caps"
local PACKS = {"production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"}
if not script.active_mods["Krastorio2-spaced-out"] then
  PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"}
end
local MODIFIER = script.active_mods["Krastorio2-spaced-out"] and 0.6 or 0.65
local loaded, reported

local function fail(message)
  error("[mir5-worker-caps] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < 0.0000001
end

local function owner(force)
  local value = force.technologies[NAME]
  if not value or value.prototype.max_level ~= 4294967295 then fail("native infinite tail is absent") end
  local effects = value.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "worker-robot-speed" or effects[1].modifier ~= MODIFIER then
    fail("native worker effect was replaced")
  end
  return value
end

local function assert_complete(state)
  local force = game.forces.player
  local technology = owner(force)
  if state.finished ~= 2 or technology.level ~= 9 or technology.researched
      or technology.enabled or not technology.visible_when_disabled then
    fail("two lab completions did not stop at the absolute cap of eight")
  end
  if not close(force.worker_robots_speed_modifier, state.before_bonus + 2 * MODIFIER) then
    fail("native worker bonus or independent offset was lost/duplicated")
  end
  if force.current_research ~= nil then fail("above-cap research remained active") end
  for _, queued in ipairs(force.research_queue) do
    if queued.name == NAME then fail("above-cap research remained queued") end
  end
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.name ~= "mir5-worker-caps-foreign" then fail("foreign force disappeared") end
  local foreign_technology = owner(foreign)
  if foreign_technology.enabled or foreign_technology.visible_when_disabled
      or foreign_technology.level ~= 7 or not close(foreign.worker_robots_speed_modifier, 0) then
    fail("foreign disabled owner or unrelated force bonus changed")
  end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(PACKS) do
    if 16 - inventory.get_item_count(name) ~= 2 then fail("science consumption differs for " .. name) end
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "worker-caps", stage = stage, status = "passed",
    witnesses = {
      profile = MODIFIER == 0.6 and "k2so" or "space-age",
      native_owner = NAME, native_effect_modifier = MODIFIER,
      cap = 8, next_level = 9, lab_completed_levels = state.finished,
      each_required_science_pack_consumed = 2,
      science_pack_names = PACKS,
      before_bonus_with_independent_offset = state.before_bonus,
      after_bonus = game.forces.player.worker_robots_speed_modifier,
      independent_offset = 0.123,
      cap_disabled_owned_player = true, foreign_disable_preserved = true,
      foreign_force_bonus_unchanged = true,
      fixture_accelerates_cost_and_time = true,
      on_load_read_only = stage == "reload",
      gameplay_scope = "disposable-native-worker-cap-only"
    }
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("unexpected target or player package")
  end
  if settings.startup["mir-max-level-worker-robots-speed"].value ~= 8
      or settings.startup["mir-settings-profile-import"].value ~= "" then fail("unexpected startup controls") end
  game.speed = 16
  local force = game.forces.player
  force.enable_all_prototypes()
  local technology = owner(force)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  if technology.level ~= 7 or technology.researched then fail("fixture did not start at native level seven") end
  technology.enabled, technology.visible_when_disabled = true, false
  force.worker_robots_speed_modifier = force.worker_robots_speed_modifier + 0.123
  local before_bonus = force.worker_robots_speed_modifier
  local foreign = game.create_force("mir5-worker-caps-foreign")
  local foreign_technology = owner(foreign)
  foreign_technology.enabled, foreign_technology.visible_when_disabled = false, false
  local lab = force.get_spawn_position(game.surfaces[1])
  lab = game.surfaces[1].create_entity{name = "lab", position = lab, force = force}
  if not lab or not lab.valid then fail("could not create real lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(PACKS) do
    if inventory.insert{name = name, count = 16} ~= 16 then fail("lab rejected " .. name) end
  end
  storage[KEY] = {phase = "researching", finished = 0, before_bonus = before_bonus,
    foreign_index = foreign.index, lab = lab, deadline = game.tick + 18000}
  lab.energy = 100000000
  if not force.add_research(technology) then fail("could not start native research") end
  force.research_queue = {technology, technology, technology}
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if state and event.research and event.research.name == NAME and event.research.force == game.forces.player then
    state.finished = state.finished + 1
    if state.finished > 2 then fail("worker research exceeded its cap") end
  end
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = state and state.phase == "complete" and {finished = state.finished, before_bonus = state.before_bonus} or nil
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      if state.finished ~= loaded.finished or state.before_bonus ~= loaded.before_bonus then fail("load changed saved witness") end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real lab did not reach the native worker cap") end
  state.lab.energy = 100000000
  if state.finished ~= 2 then return end
  assert_complete(state)
  state.phase = "complete"
  marker("initial", state)
  game.server_save("mir5-native-complete")
end)
