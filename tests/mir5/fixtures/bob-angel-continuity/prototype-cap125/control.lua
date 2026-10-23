-- Native F200 recipe-cap boundary fixture. It observes normal MIR cap
-- reconciliation and actual lab research; it never edits a completed level.
local KEY = "mir5_bob_angel_continuity"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-prototype-cap125"
local PROBE = "mir5-ba-continuity-queue-probe"
local UINT32_MAX = 4294967295
local CAP = 1.25
local EFFECT = 0.02
local START_NEXT_LEVEL = 63
local FINISHED_NEXT_LEVEL = 64
local START_BONUS = 1.24
local RAW_COMPLETED_BONUS = 1.26
local INITIAL_PACKS = 16
local DEADLINE_TICKS = 18000
local loaded, reload_logged = nil, false

local FAMILIES = {
  {key="research_material_aluminium", early="recipe-prod-research_material_aluminium-1", tail="recipe-prod-research_material_aluminium-4", recipes={"angels-plate-aluminium", "angels-plate-aluminium-2"}},
  {key="research_material_copper_tungsten", early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}},
  {key="research_material_gold", early="recipe-prod-research_material_gold-1", tail="recipe-prod-research_material_gold-4", recipes={"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"}},
  {key="research_material_tin", early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"angels-plate-tin", "angels-plate-tin-2"}},
  {key="research_material_titanium", early="recipe-prod-research_material_titanium-1", tail="recipe-prod-research_material_titanium-4", recipes={"angels-plate-titanium", "angels-plate-titanium-2"}},
}
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "utility-science-pack"}
local CONSUMPTION = {["automation-science-pack"]=5, ["logistic-science-pack"]=4, ["utility-science-pack"]=5}

local function fail(message) error("[mir5-bob-angel-prototype-cap125] " .. message) end
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
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible_when_disabled=value.visible_when_disabled, max_level=value.prototype.max_level}
end
local function same_status(left, right)
  return left and right and left.level == right.level and left.researched == right.researched
    and left.enabled == right.enabled and left.visible_when_disabled == right.visible_when_disabled
    and left.max_level == right.max_level
end

local function check_closure()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "5.0.20000"
      or script.active_mods["mir-fixture-mir5-bob-angel-continuity"] ~= "0.5.0"
      or script.active_mods["space-age"] ~= nil or script.active_mods.bobtech ~= nil then
    fail("unexpected F200 Bob/Angel 125-percent closure")
  end
end
local function check_settings()
  local cap = settings.startup["mir-prototype-productivity-cap"]
  local imported = settings.startup["mir-settings-profile-import"]
  if not cap or cap.value ~= "percent-125" or not imported or imported.value ~= "" then
    fail("fixture startup prototype-cap settings differ")
  end
  for _, family in ipairs(FAMILIES) do
    local effect = settings.startup["ips-effect-per-level-" .. family.key]
    local max = settings.startup["ips-max-level-" .. family.key]
    if not effect or effect.value ~= 2 or not max or max.value ~= 0 then
      fail("fixture material settings differ for " .. family.key)
    end
  end
end
local function check_effects(value, family, label)
  local effects = value.prototype.effects
  if type(effects) ~= "table" or #effects ~= #family.recipes then fail(label .. " effect count changed") end
  for index, recipe in ipairs(family.recipes) do
    local effect = effects[index]
    if not effect or effect.type ~= "change-recipe-productivity" or effect.recipe ~= recipe
        or not close(effect.change, EFFECT) then
      fail(label .. " effect changed for " .. recipe)
    end
  end
end
local function check_native_caps(family)
  for _, name in ipairs(family.recipes) do
    local recipe = prototypes.recipe[name]
    if not recipe or not close(recipe.maximum_productivity, CAP) then
      fail("named native recipe cap differs for " .. name)
    end
  end
end
local function check_rows(force, expected_tail, player, label)
  for _, family in ipairs(FAMILIES) do
    local early, tail = technology(force, family.early), technology(force, family.tail)
    if early.prototype.max_level ~= 3 or tail.prototype.max_level ~= UINT32_MAX then
      fail(label .. " material progression boundary differs")
    end
    check_effects(early, family, label .. " early")
    check_effects(tail, family, label .. " tail")
    check_native_caps(family)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= expected_tail or tail.researched ~= false then
      fail(label .. " material levels differ for " .. family.key)
    end
    if player then
      if expected_tail == FINISHED_NEXT_LEVEL then
        if early.enabled ~= true or early.visible_when_disabled ~= false
            or tail.enabled ~= false or tail.visible_when_disabled ~= true then
          fail(label .. " MIR-owned tail cap state differs for " .. family.key)
        end
      elseif early.enabled ~= true or early.visible_when_disabled ~= false
          or tail.enabled ~= true or tail.visible_when_disabled ~= false then
        fail(label .. " player pre-completion state differs for " .. family.key)
      end
    elseif early.enabled ~= false or tail.enabled ~= false
        or early.visible_when_disabled ~= false or tail.visible_when_disabled ~= false then
      fail(label .. " foreign disabled state differs for " .. family.key)
    end
  end
end
local function recipe_bonuses(force, lower, upper, label)
  local first = nil
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      local value = recipe and recipe.productivity_bonus
      if not value or value < lower - 0.000001 or value > upper + 0.000001 then
        fail(label .. " recipe productivity differs for " .. name)
      end
      if first ~= nil and not close(value, first) then fail(label .. " recipe bonuses diverged") end
      first = value
    end
  end
  return first
end
local function snapshot(force, bonus)
  local technologies, bonuses = {}, {}
  for _, family in ipairs(FAMILIES) do
    technologies[family.early] = status(technology(force, family.early))
    technologies[family.tail] = status(technology(force, family.tail))
    for _, name in ipairs(family.recipes) do bonuses[name] = force.recipes[name].productivity_bonus end
  end
  return {technologies=technologies, bonuses=bonuses, queue=queue_names(force),
    current=force.current_research and force.current_research.name or false,
    progress=force.research_progress or 0, expected_bonus=bonus}
end
local function assert_snapshot(force, expected, label)
  for name, saved in pairs(expected.technologies) do
    if not same_status(status(technology(force, name)), saved) then fail(label .. " state changed for " .. name) end
  end
  for name, saved in pairs(expected.bonuses) do
    if not close(force.recipes[name].productivity_bonus, saved) then fail(label .. " bonus changed for " .. name) end
  end
  local queue = queue_names(force)
  if #queue ~= #expected.queue or (force.current_research and force.current_research.name or false) ~= expected.current
      or not close(force.research_progress or 0, expected.progress) then
    fail(label .. " queue or progress changed")
  end
  for index, name in ipairs(expected.queue) do if queue[index] ~= name then fail(label .. " queue identity changed") end end
end
local function seed_external_prerequisites(force)
  local selected = {}
  for _, family in ipairs(FAMILIES) do selected[family.early], selected[family.tail] = true, true end
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs({family.early, family.tail}) do
      for _, prerequisite in pairs(technology(force, name).prerequisites) do
        if not selected[prerequisite.name] then prerequisite.research_recursive() end
      end
    end
  end
end
local function seed_material_boundary(force, player)
  for _, family in ipairs(FAMILIES) do
    local early, tail = technology(force, family.early), technology(force, family.tail)
    early.level, early.researched = 3, true
    tail.level, tail.researched = START_NEXT_LEVEL, false
  end
  force.reset_technology_effects()
  -- Effect reset may restore native enablement. The disposable foreign
  -- writer establishes its disable only after every seeding/reset operation.
  for _, family in ipairs(FAMILIES) do
    local early, tail = technology(force, family.early), technology(force, family.tail)
    early.enabled, early.visible_when_disabled = player, false
    tail.enabled, tail.visible_when_disabled = player, false
  end
  check_rows(force, START_NEXT_LEVEL, player, player and "player seed" or "foreign seed")
  local bonus = recipe_bonuses(force, START_BONUS, START_BONUS, player and "player seed" or "foreign seed")
  return bonus
end
local function seed_foreign(force)
  force.enable_all_prototypes()
  seed_external_prerequisites(force)
  local bonus = seed_material_boundary(force, false)
  for _, prerequisite in pairs(technology(force, PROBE).prerequisites) do prerequisite.research_recursive() end
  if force.add_research(PROBE) ~= true then fail("could not queue foreign probe research") end
  force.research_progress = 0.42
  local result = snapshot(force, bonus)
  if result.current ~= PROBE or #result.queue ~= 1 or not close(result.progress, 0.42) then
    fail("foreign queue/progress seed differs")
  end
  return result
end
local function plan()
  local rows = {}
  for _, family in ipairs(FAMILIES) do rows[#rows + 1] = family.tail end
  return rows
end
local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed",
    witnesses={
      fixture_version=script.active_mods["mir-fixture-mir5-bob-angel-continuity"],
      default_rows_preflighted_before_mutation=true, native_cap_percent=125,
      prototype_maximum_productivity=CAP, effect_percent=2, useful_level_headroom=63,
      seeded_boundary_levels=true, seeded_tail_next_level=START_NEXT_LEVEL,
      seeded_earned_effect_bonus=START_BONUS, lab_completed_tail_levels=state.completed,
      tail_next_level_after_lab=FINISHED_NEXT_LEVEL, player_owned_tail_disabled=true,
      native_recipe_productivity_bonus=state.player_bonus,
      raw_completed_bonus_formula=RAW_COMPLETED_BONUS,
      native_recipe_bonus_is_observed_separately_from_prototype_cap=true,
      foreign_disabled_effect_and_queue_preserved=true,
      sequential_native_queue_entries=state.queue_count, on_load_read_only=stage == "reload",
      qualification="native-runner-readback-required",
    },
  }))
end
local function assert_complete(state)
  if state.completed ~= #state.plan or state.events ~= #state.plan or state.queue_count ~= #state.plan then
    fail("actual cap-boundary lab completions differ")
  end
  local player = game.forces.player
  if player.current_research ~= nil or #player.research_queue ~= 0 then fail("player queue was not exhausted") end
  check_rows(player, FINISHED_NEXT_LEVEL, true, "player complete")
  local bonus = recipe_bonuses(player, CAP, RAW_COMPLETED_BONUS, "player complete")
  state.player_bonus = bonus
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.get_item_count(science) ~= INITIAL_PACKS - CONSUMPTION[science] then
      fail("real lab science consumption differs for " .. science)
    end
  end
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.valid == false then fail("foreign force is absent") end
  check_rows(foreign, START_NEXT_LEVEL, false, "foreign")
  assert_snapshot(foreign, state.foreign, "foreign")
end

script.on_init(function()
  check_closure(); check_settings()
  if storage[KEY] ~= nil then fail("prototype-cap125 fixture found prior state") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  seed_external_prerequisites(player)
  seed_material_boundary(player, true)
  local foreign = game.create_force("mir5-bob-angel-prototype-cap125-foreign")
  local foreign_state = seed_foreign(foreign)
  local lab = game.surfaces[1].create_entity{name="lab", position=player.get_spawn_position(game.surfaces[1]), force=player}
  if not lab or lab.valid == false then fail("could not create real lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.insert{name=science, count=INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("real lab rejected " .. science)
    end
  end
  lab.energy = 100000000
  local sequence = plan()
  if player.add_research(technology(player, sequence[1])) ~= true then fail("could not start cap-boundary research") end
  if not player.current_research or player.current_research.name ~= sequence[1] or #player.research_queue ~= 1 then
    fail("native queue did not accept first cap-boundary research")
  end
  storage[KEY] = {phase="prototype-cap125-running", plan=sequence, completed=0, events=0, queue_count=1,
    deadline=game.tick + DEADLINE_TICKS, lab=lab, foreign_index=foreign.index, foreign=foreign_state}
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "prototype-cap125-saved"
    and {completed=state.completed, events=state.events, queue_count=state.queue_count} or nil
  reload_logged = false
end)
script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "prototype-cap125-running" or not event.research
      or event.research.force ~= game.forces.player then return end
  local expected = state.plan[state.completed + 1]
  if event.research.name ~= expected then fail("actual lab completed an unexpected cap-boundary row") end
  state.completed, state.events = state.completed + 1, state.events + 1
  if state.completed > #state.plan then fail("actual lab completed duplicate cap-boundary research") end
end)
script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("prototype-cap125 state is absent") end
  if state.phase == "prototype-cap125-running" then
    if game.tick > state.deadline then fail("actual cap-boundary lab did not complete") end
    state.lab.energy = 100000000
    if state.completed == #state.plan then
      assert_complete(state)
      state.phase = "prototype-cap125-saved"
      marker("initial", state)
      game.server_save(SAVE)
    elseif game.forces.player.current_research == nil then
      local name = state.plan[state.completed + 1]
      local force = game.forces.player
      if #force.research_queue ~= 0 or force.add_research(technology(force, name)) ~= true
          or not force.current_research or force.current_research.name ~= name or #force.research_queue ~= 1 then
        fail("native queue refused the next cap-boundary lab research")
      end
      state.queue_count = state.queue_count + 1
    end
  elseif state.phase == "prototype-cap125-saved" and loaded and not reload_logged then
    if loaded.completed ~= state.completed or loaded.events ~= state.events or loaded.queue_count ~= state.queue_count then
      fail("on_load changed cap-boundary state")
    end
    assert_complete(state)
    marker("reload", state)
    reload_logged = true
  end
end)
