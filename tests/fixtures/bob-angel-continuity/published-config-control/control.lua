-- Published 4.7.2 source-control observer for the F200 Bob/Angel continuity
-- save. This fixture observes the upstream configuration reset; it does not
-- write technology levels, enabled/visibility state, recipe bonuses, or queue
-- state.
local KEY = "mir5_bob_angel_continuity"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-continuity-published-reset-control"
local FIXTURE = "mir-fixture-mir5-bob-angel-continuity"
local PROBE = "mir5-ba-continuity-queue-probe"
local LEVEL = 150
local BONUS = 3
local loaded, reload_logged = nil, false

local FAMILIES = {
  {early="recipe-prod-research_material_aluminium-1", tail="recipe-prod-research_material_aluminium-4", recipes={"angels-plate-aluminium", "angels-plate-aluminium-2"}},
  {early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}},
  {early="recipe-prod-research_material_gold-1", tail="recipe-prod-research_material_gold-4", recipes={"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"}},
  {early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"angels-plate-tin", "angels-plate-tin-2"}},
  {early="recipe-prod-research_material_titanium-1", tail="recipe-prod-research_material_titanium-4", recipes={"angels-plate-titanium", "angels-plate-titanium-2"}},
}

local function fail(message) error("[mir5-bob-angel-published-reset-control] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value then fail("named technology is absent: " .. tostring(name)) end
  return value
end
local function queue_names(force)
  local names = {}
  for index, value in ipairs(force.research_queue or {}) do names[index] = value.name end
  return names
end
local function status(value)
  return {
    level=value.level,
    researched=value.researched,
    enabled=value.enabled,
    visible_when_disabled=value.visible_when_disabled,
    max_level=value.prototype.max_level,
  }
end

local function check_closure()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "4.7.20002"
      or script.active_mods[FIXTURE] ~= "0.1.1" or script.active_mods.angelsrefining ~= "2.0.4"
      or script.active_mods.bobplates ~= "2.1.1"
      or script.active_mods["space-age"] ~= nil or script.active_mods.bobtech ~= nil then
    fail("unexpected published F200 Bob/Angel reset-control closure")
  end
end

local function check_source_state(state)
  if type(state) ~= "table" or type(state.player) ~= "table" or type(state.foreign) ~= "table" then
    fail("requires the published 0.1.0 boundary save")
  end
  if state.source_mir ~= "4.7.20002" then
    fail("published source boundary identity differs: source_mir=" .. tostring(state.source_mir))
  end
  if state.phase ~= "published-boundary-saved" and state.phase ~= "published-reset-control-await-save"
      and state.phase ~= "published-reset-control-saved" then
    fail("published reset-control phase is invalid: " .. tostring(state.phase))
  end
  if type(state.foreign_index) ~= "number" then fail("published foreign boundary force is absent") end
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs({family.early, family.tail}) do
      local source = state.foreign.technologies and state.foreign.technologies[name]
      if type(source) ~= "table" or source.enabled ~= false or source.visible_when_disabled ~= false then
        fail("published foreign external-disable source state differs for " .. name)
      end
    end
  end
  if state.foreign.current ~= PROBE or type(state.foreign.queue) ~= "table"
      or state.foreign.queue[1] ~= PROBE or not close(state.foreign.progress, 0.42) then
    fail("published foreign queue source state differs")
  end
end

local function check_rows(force, label)
  for _, family in ipairs(FAMILIES) do
    local early, tail = technology(force, family.early), technology(force, family.tail)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= LEVEL or tail.researched ~= true then
      fail(label .. " published earned boundary differs for " .. family.early)
    end
    if early.enabled ~= true or early.visible_when_disabled ~= false
        or tail.enabled ~= true or tail.visible_when_disabled ~= false then
      fail(label .. " upstream angelsrefining did not re-enable " .. family.early)
    end
  end
end

local function check_bonuses(force, label)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not close(recipe.productivity_bonus, BONUS) then
        fail(label .. " native recipe effect changed for " .. name)
      end
    end
  end
end

local function check_queue(force, label)
  local queue = queue_names(force)
  if #queue ~= 1 or queue[1] ~= PROBE or not force.current_research or force.current_research.name ~= PROBE
      or not close(force.research_progress, 0.42) then
    fail(label .. " queue or progress changed")
  end
end

local function observe(state)
  check_closure()
  check_source_state(state)
  local player = game.forces.player
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.valid == false then fail("published foreign boundary force is absent") end
  check_rows(player, "player")
  check_bonuses(player, "player")
  check_rows(foreign, "foreign")
  check_bonuses(foreign, "foreign")
  check_queue(foreign, "foreign")
end

local function check_transition(event)
  local change = event and event.mod_changes and event.mod_changes[FIXTURE]
  if type(change) ~= "table" or change.old_version ~= "0.1.0" or change.new_version ~= "0.1.1" then
    fail("requires the published 0.1.0 to 0.1.1 fixture update")
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE,
    stage=stage,
    status="passed",
    witnesses={
      source_mir=state.source_mir,
      source_fixture_version="0.1.0",
      upstream_reset_observed=true,
      all_ten_native_material_technologies_reenabled=true,
      earned_early_level=3,
      earned_tail_level=LEVEL,
      native_recipe_bonus=BONUS,
      foreign_queue_probe=PROBE,
      foreign_queue_progress=0.42,
      on_load_read_only=stage == "reload",
      qualification="native-runner-readback-required",
    },
  }))
end

script.on_init(function()
  fail("published reset-control fixture must start from its 0.1.0 predecessor save")
end)

script.on_configuration_changed(function(event)
  local state = storage[KEY]
  check_transition(event)
  if type(state) ~= "table" or state.phase ~= "published-boundary-saved" then
    fail("requires the published 0.1.0 boundary save")
  end
  observe(state)
  state.phase = "published-reset-control-await-save"
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "published-reset-control-saved"
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("published reset-control state is absent") end
  if state.phase == "published-reset-control-await-save" then
    observe(state)
    state.phase = "published-reset-control-saved"
    marker("initial", state)
    game.server_save(SAVE)
  elseif state.phase == "published-reset-control-saved" and loaded and not reload_logged then
    observe(state)
    marker("reload", state)
    reload_logged = true
  end
end)
