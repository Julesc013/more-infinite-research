-- Published 4.7.2 source side for the F200 Bob/Angel continuity fixture.
-- Boundary levels are explicitly seeded through native API state and followed
-- by reset_technology_effects. They are not laboratory completions.
local KEY = "mir5_bob_angel_continuity"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-continuity-published-4.7"
local PROBE = "mir5-ba-continuity-queue-probe"
local LEVEL = 150
local EFFECT = 0.02
local TOTAL_BONUS = 3
local loaded, reload_logged = nil, false

local FAMILIES = {
  {early="recipe-prod-research_material_aluminium-1", tail="recipe-prod-research_material_aluminium-4", recipes={"angels-plate-aluminium", "angels-plate-aluminium-2"}},
  {early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}},
  {early="recipe-prod-research_material_gold-1", tail="recipe-prod-research_material_gold-4", recipes={"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"}},
  {early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"angels-plate-tin", "angels-plate-tin-2"}},
  {early="recipe-prod-research_material_titanium-1", tail="recipe-prod-research_material_titanium-4", recipes={"angels-plate-titanium", "angels-plate-titanium-2"}},
}

local function fail(message) error("[mir5-bob-angel-continuity-source] " .. message) end
local function close(left, right) return type(left) == "number" and math.abs(left - right) <= 0.000001 end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value then fail("named technology is absent: " .. tostring(name)) end
  return value
end
local function status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible_when_disabled=value.visible_when_disabled, max_level=value.prototype.max_level}
end
local function same(left, right)
  return type(left) == "table" and left.level == right.level and left.researched == right.researched
    and left.enabled == right.enabled and left.visible_when_disabled == right.visible_when_disabled
    and left.max_level == right.max_level
end
local function queue_names(force)
  local out = {}
  for index, value in ipairs(force.research_queue or {}) do out[index] = value.name end
  return out
end
local function progress(force)
  return type(force.research_progress) == "number" and force.research_progress or 0
end

local function assert_prototype(force, family)
  local early, tail = technology(force, family.early), technology(force, family.tail)
  if early.prototype.max_level ~= 3 or tail.prototype.max_level ~= LEVEL then
    fail("published finite material boundaries changed")
  end
  local effect = tail.prototype.effects and tail.prototype.effects[1]
  if not effect or effect.type ~= "change-recipe-productivity" or not close(effect.change, EFFECT) then
    fail("published material effect changed")
  end
  return early, tail
end

local function seed_boundary(force)
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototype(force, family)
    early.level, early.researched = 3, true
    tail.level, tail.researched = LEVEL, true
    if early.level ~= 3 or early.researched ~= true or tail.level ~= LEVEL or tail.researched ~= true then
      fail("native finite boundary seed did not retain its selected state")
    end
  end
  force.reset_technology_effects()
end

local function recipe_bonuses(force, expected)
  local out = {}
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not close(recipe.productivity_bonus, expected) then
        fail("native material recipe effect differs for " .. name)
      end
      out[name] = recipe.productivity_bonus
    end
  end
  return out
end

local function force_snapshot(force, bonus)
  local technologies = {}
  for _, family in ipairs(FAMILIES) do
    technologies[family.early] = status(technology(force, family.early))
    technologies[family.tail] = status(technology(force, family.tail))
  end
  return {technologies=technologies, bonuses=recipe_bonuses(force, bonus),
    queue=queue_names(force), current=force.current_research and force.current_research.name or false,
    progress=progress(force)}
end

local function assert_snapshot(force, expected, bonus, foreign)
  for name, saved in pairs(expected.technologies) do
    local current = status(technology(force, name))
    if not same(current, saved) then fail("saved material state changed for " .. name) end
  end
  local actual = recipe_bonuses(force, bonus)
  for name, value in pairs(expected.bonuses) do
    if not close(actual[name], value) then fail("saved recipe effect changed for " .. name) end
  end
  if #queue_names(force) ~= #expected.queue or (force.current_research and force.current_research.name or false) ~= expected.current
      or not close(progress(force), expected.progress) then
    fail((foreign and "foreign" or "player") .. " queue or progress changed")
  end
  for index, name in ipairs(expected.queue) do
    if force.research_queue[index].name ~= name then fail("saved queue identity changed") end
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed",
    witnesses={
      source_mir=state.source_mir, finite_tail_level=LEVEL, finite_tail_effect_percent=EFFECT * 100,
      seeded_boundary_levels=true, historical_lab_completed_levels=0,
      no_fabricated_150_completion_claim=true, native_recipe_bonus=TOTAL_BONUS,
      foreign_disabled=true, foreign_queue=state.foreign.current, foreign_progress=state.foreign.progress,
      on_load_read_only=stage == "reload", qualification="native-runner-readback-required",
    },
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "4.7.20002"
      or script.active_mods["mir-fixture-mir5-bob-angel-continuity"] ~= "0.1.0"
      or script.active_mods["space-age"] ~= nil or script.active_mods.bobtech ~= nil then
    fail("unexpected published F200 Bob/Angel closure")
  end
  if storage[KEY] ~= nil then fail("published boundary state already exists") end

  local player = game.forces.player
  player.enable_all_prototypes()
  seed_boundary(player)
  local player_state = force_snapshot(player, TOTAL_BONUS)

  local foreign = game.create_force("mir5-bob-angel-continuity-foreign")
  foreign.enable_all_prototypes()
  seed_boundary(foreign)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs({family.early, family.tail}) do
      local value = technology(foreign, name)
      value.enabled, value.visible_when_disabled = false, false
    end
  end
  for _, prerequisite in pairs(technology(foreign, PROBE).prerequisites) do prerequisite.research_recursive() end
  if foreign.add_research(PROBE) ~= true then fail("could not queue foreign probe research") end
  foreign.research_progress = 0.42
  local foreign_state = force_snapshot(foreign, TOTAL_BONUS)
  if foreign_state.current ~= PROBE or #foreign_state.queue ~= 1 or foreign_state.queue[1] ~= PROBE
      or not close(foreign_state.progress, 0.42) then
    fail("foreign queue boundary seed differs")
  end

  storage[KEY] = {phase="published-boundary-seeded", source_mir=script.active_mods["more-infinite-research"],
    player=player_state, foreign=foreign_state, foreign_index=foreign.index}
end)

script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "published-boundary-saved"
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("published boundary state is absent") end
  if state.phase == "published-boundary-seeded" or state.phase == "published-boundary-saved" then
    assert_snapshot(game.forces.player, state.player, TOTAL_BONUS, false)
    local foreign = game.forces[state.foreign_index]
    if not foreign or foreign.valid == false then fail("foreign boundary force is absent") end
    assert_snapshot(foreign, state.foreign, TOTAL_BONUS, true)
    if loaded then
      if not reload_logged then marker("reload", state); reload_logged = true end
    elseif state.phase == "published-boundary-seeded" then
      marker("initial", state)
      state.phase = "published-boundary-saved"
      game.server_save(SAVE)
    end
  end
end)
