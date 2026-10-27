-- Disposable F210 native-owner cap-order fixture. It never imports or calls
-- MIR internals: native reset/configuration events drive the player runtime.
local M = {}

local KEY = "mir5_native_owner_cap_order"
local SAVE = "mir5-native-complete"
local CASE = "native-owner-cap-order"
local FIXTURE = "mir-fixture-mir5-native-owner-cap-order"
local OWNER = "steel-plate-productivity"
local PROBE = "automation"
local RECIPES = {"steel-plate", "casting-steel"}
local UINT32_MAX = 4294967295
local CLOSURE = {"base", "elevated-rails", "quality", "recycler", "space-age"}
local STAGES = {
  canonical = {version = "0.1.0", cap = 1, effects = {"steel-plate", "casting-steel"}, prior = nil},
  permuted = {version = "0.2.0", cap = 1, effects = {"casting-steel", "steel-plate"}, prior = "canonical-complete"},
  relaxed = {version = "0.3.0", cap = 0, effects = {"steel-plate", "casting-steel"}, prior = "permuted-complete"},
}

local reload_requested, reload_logged = false, false

local function fail(message) error("[mir5-native-owner-cap-order] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.0000001
end

local function stage_info(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown control stage") end
  return expected
end

local function check_closure(expected)
  for _, name in ipairs(CLOSURE) do
    if script.active_mods[name] ~= "2.1.23" then fail("F210 Space Age closure differs: " .. name) end
  end
  if script.active_mods["more-infinite-research"] ~= "5.0.21000"
      or script.active_mods[FIXTURE] ~= expected.version then
    fail("fixture stage closure differs")
  end
  local startup = settings.startup
  local cap = startup and startup["ips-max-level-research_steel"]
  local imported = startup and startup["mir-settings-profile-import"]
  if cap == nil or cap.value ~= expected.cap or imported == nil or imported.value ~= "" then
    fail("fixture startup settings differ")
  end
end

local function technology(force)
  local value = force and force.technologies and force.technologies[OWNER]
  if value == nil or value.valid == false or value.name ~= OWNER then fail("steel native owner is absent") end
  return value
end

local function check_effects(value, expected, label)
  local effects = value.prototype and value.prototype.effects
  if type(effects) ~= "table" or #effects ~= #expected then fail(label .. " effect count differs") end
  for index, recipe in ipairs(expected) do
    local effect = effects[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or not close(effect.change, 0.1) then
      fail(label .. " effect differs at " .. tostring(index))
    end
  end
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end

local function same_queue(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or left.current ~= right.current
      or #left.queue ~= #right.queue or not close(left.progress, right.progress) then return false end
  for index, name in ipairs(left.queue) do if right.queue[index] ~= name then return false end end
  return true
end

local function recipe_bonuses(force)
  local result = {}
  for _, name in ipairs(RECIPES) do
    local recipe = force.recipes and force.recipes[name]
    if recipe == nil or type(recipe.productivity_bonus) ~= "number" then fail("native recipe productivity is absent: " .. name) end
    result[name] = recipe.productivity_bonus
  end
  return result
end

local function same_bonuses(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  for _, name in ipairs(RECIPES) do if not close(left[name], right[name]) then return false end end
  return true
end

local function snapshot(force)
  local value = technology(force)
  return {
    level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, maximum = value.prototype.max_level,
    saved_progress = value.saved_progress, bonuses = recipe_bonuses(force), queue = queue_snapshot(force),
  }
end

local function assert_owner(force, expected, stage, label)
  local value = technology(force)
  check_effects(value, expected.effects, label)
  if value.level ~= 2 or value.researched ~= false or value.prototype.max_level ~= UINT32_MAX then
    fail(label .. " level or native maximum differs")
  end
  if stage == "relaxed" then
    if value.enabled ~= true or value.visible_when_disabled ~= false then fail(label .. " owned cap was not restored") end
  elseif value.enabled ~= false or value.visible_when_disabled ~= true then
    fail(label .. " owned cap is absent")
  end
  local state = snapshot(force)
  for _, name in ipairs(RECIPES) do
    if not close(state.bonuses[name], 0.1) then fail(label .. " native recipe bonus differs") end
  end
  return state
end

local function assert_foreign(force, expected, stage, label)
  local value = technology(force)
  check_effects(value, expected.effects, label)
  if value.level ~= 2 or value.researched ~= false or value.enabled ~= false
      or value.prototype.max_level ~= UINT32_MAX then fail(label .. " foreign native state differs") end
  if stage == "relaxed" then
    if value.visible_when_disabled ~= false then fail(label .. " foreign visibility was not restored") end
  elseif value.visible_when_disabled ~= true then
    fail(label .. " foreign visibility cap witness is absent")
  end
  local queue = queue_snapshot(force)
  if queue.current ~= PROBE or #queue.queue ~= 1 or queue.queue[1] ~= PROBE or not close(queue.progress, 0.42) then
    fail(label .. " foreign current research or progress differs")
  end
  local state = snapshot(force)
  for _, name in ipairs(RECIPES) do
    if not close(state.bonuses[name], 0.1) then fail(label .. " foreign native recipe bonus differs") end
  end
  return state
end

local function assert_player_snapshot(actual, expected, stage, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.maximum ~= expected.maximum or not close(actual.saved_progress, expected.saved_progress)
      or not same_bonuses(actual.bonuses, expected.bonuses) or not same_queue(actual.queue, expected.queue) then
    fail(label .. " player saved state differs")
  end
  if stage == "relaxed" then
    if actual.enabled ~= true or actual.visible ~= false then fail(label .. " player cap restoration differs") end
  elseif actual.enabled ~= false or actual.visible ~= true then
    fail(label .. " player cap state differs")
  end
end

local function assert_foreign_snapshot(actual, expected, stage, label)
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.maximum ~= expected.maximum or not same_bonuses(actual.bonuses, expected.bonuses)
      or not same_queue(actual.queue, expected.queue) then fail(label .. " foreign saved state differs") end
  if actual.enabled ~= false then fail(label .. " foreign disablement changed") end
  if stage == "relaxed" then
    if actual.visible ~= false then fail(label .. " foreign visibility restoration differs") end
  elseif actual.visible ~= true then
    fail(label .. " foreign cap visibility differs")
  end
end

local function marker(stage, state, expected)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage, status = "passed", qualification = "native-runner-readback-required",
    witnesses = {
      fixture_stage = script.active_mods[FIXTURE], cap = expected.cap, effect_order = expected.effects,
      actual_lab_completions = 0, native_state_seeded = true,
      player_level = state.player.level, player_saved_progress = state.player.saved_progress,
      player_enabled = state.player.enabled, foreign_enabled = state.foreign.enabled,
      foreign_queue_progress = state.foreign.queue.progress, on_load_read_only = stage == "reload",
    },
  }))
end

local function save_initial(state, expected)
  marker("initial", state, expected)
  game.server_save(SAVE)
end

local function mark_reload(state, expected)
  marker("reload", state, expected)
end

local function setup_foreign(expected)
  local foreign = game.create_force("mir5-native-owner-cap-order-foreign")
  foreign.enable_all_prototypes()
  local owner = technology(foreign)
  -- LuaTechnology.level re-enables a technology. Keep the intentional
  -- foreign disablement after the level seed in separate writes.
  owner.level = 2
  owner.enabled = false
  owner.visible_when_disabled = false
  local probe = foreign.technologies[PROBE]
  if probe == nil then fail("foreign queue probe is absent") end
  if foreign.add_research(probe) ~= true then fail("could not queue foreign probe") end
  foreign.research_progress = 0.42
  -- This is a documented engine event, not a call into MIR. It lets the
  -- runtime observe a pre-disabled foreign owner and its unrelated queue.
  foreign.reset_technology_effects()
  return foreign
end

function M.apply(stage)
  local expected = stage_info(stage)
  script.on_init(function()
    if stage ~= "canonical" then fail("only canonical stage may initialize a fresh save") end
    check_closure(expected)
    if storage[KEY] ~= nil then fail("fixture state already exists") end
    local player = game.forces.player
    player.enable_all_prototypes()
    local owner = technology(player)
    -- Set the level first: assigning it re-enables a LuaTechnology.
    owner.level = 2
    owner.enabled = true
    owner.visible_when_disabled = false
    -- `on_technology_effects_reset` is the actual engine boundary. The
    -- fixture neither imports nor invokes any MIR lifecycle handler.
    player.reset_technology_effects()
    owner.saved_progress = 0.27
    local player_state = assert_owner(player, expected, stage, "canonical player")
    local foreign = setup_foreign(expected)
    local foreign_state = assert_foreign(foreign, expected, stage, "canonical foreign")
    -- The create-only seed is not a server save. Keep this state pending
    -- until the first actual server tick can emit INITIAL and save it.
    local state = {phase = "canonical-prepared", player = player_state, foreign = foreign_state,
      foreign_index = foreign.index, stage = stage}
    storage[KEY] = state
  end)

  script.on_configuration_changed(function()
    if stage == "canonical" then fail("canonical stage does not accept a successor configuration") end
    check_closure(expected)
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= expected.prior or type(state.player) ~= "table"
        or type(state.foreign) ~= "table" then fail("required prior cap-order state is absent") end
    local player = assert_owner(game.forces.player, expected, stage, stage .. " player")
    local foreign = game.forces[state.foreign_index]
    local foreign_state = assert_foreign(foreign, expected, stage, stage .. " foreign")
    assert_player_snapshot(player, state.player, stage, stage .. " player")
    assert_foreign_snapshot(foreign_state, state.foreign, stage, stage .. " foreign")
    -- A configuration create step likewise cannot produce the stage's
    -- server-backed initial result.
    state.player, state.foreign, state.phase, state.stage = player, foreign_state, stage .. "-prepared", stage
  end)

  script.on_load(function()
    -- `on_load` intentionally touches neither game nor storage. The next
    -- tick performs all native and saved-state readback after cold reload.
    reload_requested = true
    reload_logged = false
  end)

  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if type(state) ~= "table" or state.stage ~= stage then
      fail("cold reload changed fixture phase")
    end
    if state.phase == stage .. "-prepared" then
      -- This is the first tick of the real server leg. Complete the seed only
      -- after every live state assertion has passed, then create the input
      -- consumed by the two read-only cold reloads.
      check_closure(expected)
      local player = assert_owner(game.forces.player, expected, stage, "initial server player")
      local foreign = assert_foreign(game.forces[state.foreign_index], expected, stage, "initial server foreign")
      assert_player_snapshot(player, state.player, stage, "initial server player")
      assert_foreign_snapshot(foreign, state.foreign, stage, "initial server foreign")
      state.player, state.foreign, state.phase = player, foreign, stage .. "-complete"
      save_initial(state, expected)
      reload_requested, reload_logged = false, true
      return
    end
    if state.phase ~= stage .. "-complete" then fail("cold reload changed fixture phase") end
    if not reload_requested or reload_logged then return end
    check_closure(expected)
    local player = assert_owner(game.forces.player, expected, stage, "cold reload player")
    local foreign = assert_foreign(game.forces[state.foreign_index], expected, stage, "cold reload foreign")
    assert_player_snapshot(player, state.player, stage, "cold reload player")
    assert_foreign_snapshot(foreign, state.foreign, stage, "cold reload foreign")
    mark_reload(state, expected)
    reload_logged = true
  end)
end

return M
