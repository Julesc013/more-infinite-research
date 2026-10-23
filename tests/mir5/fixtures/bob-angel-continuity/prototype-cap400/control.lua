-- Native F200 recipe-cap relaxation fixture. It begins with the completed
-- 125-percent save, checks MIR restored only its owned cap disablement, then
-- completes one additional real level for every named material continuation.
local KEY = "mir5_bob_angel_continuity"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-prototype-cap400"
local PROBE = "mir5-ba-continuity-queue-probe"
local UINT32_MAX = 4294967295
local CAP = 4
local EFFECT = 0.02
local RESTORED_NEXT_LEVEL = 64
local FINISHED_NEXT_LEVEL = 65
local MIN_SOURCE_PLAYER_BONUS = 1.25
local RAW_COMPLETED_BONUS = 1.28
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

local function fail(message) error("[mir5-bob-angel-prototype-cap400] " .. message) end
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
      or script.active_mods["mir-fixture-mir5-bob-angel-continuity"] ~= "0.6.0"
      or script.active_mods["space-age"] ~= nil or script.active_mods.bobtech ~= nil then
    fail("unexpected F200 Bob/Angel 400-percent closure")
  end
end
local function check_settings()
  local cap = settings.startup["mir-prototype-productivity-cap"]
  local scope = settings.startup["mir-productivity-cap-self-recycling-only"]
  local imported = settings.startup["mir-settings-profile-import"]
  if not cap or cap.value ~= "percent-400" or not scope or scope.value ~= false
      or not imported or imported.value ~= "" then
    fail("fixture startup prototype-cap relaxation settings differ")
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
      if early.enabled ~= true or early.visible_when_disabled ~= false
          or tail.enabled ~= true or tail.visible_when_disabled ~= false then
        fail(label .. " MIR-owned state was not restored for " .. family.key)
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
local function snapshot(force)
  local technologies, bonuses = {}, {}
  for _, family in ipairs(FAMILIES) do
    technologies[family.early] = status(technology(force, family.early))
    technologies[family.tail] = status(technology(force, family.tail))
    for _, name in ipairs(family.recipes) do bonuses[name] = force.recipes[name].productivity_bonus end
  end
  return {technologies=technologies, bonuses=bonuses, queue=queue_names(force),
    current=force.current_research and force.current_research.name or false, progress=force.research_progress or 0}
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
      default_rows_preflighted_before_mutation=true, native_cap_percent=400,
      self_recycling_scope=false, prototype_maximum_productivity=CAP,
      effect_percent=2, useful_level_headroom=200,
      inherited_cap125_tail_next_level=RESTORED_NEXT_LEVEL,
      restored_only_mir_owned_player_tail=true, retained_foreign_disabled_state=true,
      lab_completed_tail_levels=state.completed, tail_next_level_after_lab=FINISHED_NEXT_LEVEL,
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
    fail("actual relaxed-cap lab completions differ")
  end
  local player = game.forces.player
  if player.current_research ~= nil or #player.research_queue ~= 0 then fail("player queue was not exhausted") end
  check_rows(player, FINISHED_NEXT_LEVEL, true, "player complete")
  state.player_bonus = recipe_bonuses(player, MIN_SOURCE_PLAYER_BONUS, RAW_COMPLETED_BONUS, "player complete")
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab inventory is absent") end
  for _, science in ipairs(SCIENCE) do
    if inventory.get_item_count(science) ~= state.before_science[science] - CONSUMPTION[science] then
      fail("real lab science consumption differs for " .. science)
    end
  end
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.valid == false then fail("foreign force is absent") end
  check_rows(foreign, RESTORED_NEXT_LEVEL - 1, false, "foreign")
  assert_snapshot(foreign, state.foreign, "foreign")
end

script.on_init(function() fail("prototype-cap400 fixture must start from the cap125 save") end)
script.on_configuration_changed(function()
  check_closure(); check_settings()
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "prototype-cap125-saved" or state.completed ~= 5
      or state.events ~= 5 or state.queue_count ~= 5 then
    fail("required cap125 completed-save witness is absent")
  end
  local player = game.forces.player
  local foreign = game.forces[state.foreign_index]
  if not foreign or foreign.valid == false then fail("cap125 foreign force is absent") end
  -- MIR's configuration handler runs before this dependent fixture. It may
  -- restore the player tail it disabled at 125%; it must not re-enable the
  -- independently disabled foreign identities.
  check_rows(player, RESTORED_NEXT_LEVEL, true, "restored player")
  local restored_bonus = recipe_bonuses(player, MIN_SOURCE_PLAYER_BONUS, 1.26, "restored player")
  if not close(restored_bonus, state.player_bonus) then
    fail("cap125 player recipe productivity observation changed")
  end
  check_rows(foreign, RESTORED_NEXT_LEVEL - 1, false, "foreign")
  assert_snapshot(foreign, state.foreign, "foreign")
  if not state.lab or state.lab.valid == false then fail("cap125 lab is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("cap125 lab input inventory is absent") end
  local before = {}
  for _, science in ipairs(SCIENCE) do
    before[science] = inventory.get_item_count(science)
    if inventory.insert{name=science, count=16} ~= 16 then fail("cap125 lab rejected " .. science) end
    before[science] = inventory.get_item_count(science)
  end
  if player.current_research ~= nil or #player.research_queue ~= 0 then fail("cap125 player queue was not empty") end
  local sequence = plan()
  if player.add_research(technology(player, sequence[1])) ~= true then fail("could not start relaxed-cap research") end
  if not player.current_research or player.current_research.name ~= sequence[1] or #player.research_queue ~= 1 then
    fail("native queue did not accept first relaxed-cap research")
  end
  state.phase, state.plan, state.completed, state.events, state.queue_count = "prototype-cap400-running", sequence, 0, 0, 1
  state.deadline, state.before_science = game.tick + DEADLINE_TICKS, before
  state.lab.energy = 100000000
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and state.phase == "prototype-cap400-saved"
    and {completed=state.completed, events=state.events, queue_count=state.queue_count} or nil
  reload_logged = false
end)
script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "prototype-cap400-running" or not event.research
      or event.research.force ~= game.forces.player then return end
  local expected = state.plan[state.completed + 1]
  if event.research.name ~= expected then fail("actual lab completed an unexpected relaxed-cap row") end
  state.completed, state.events = state.completed + 1, state.events + 1
  if state.completed > #state.plan then fail("actual lab completed duplicate relaxed-cap research") end
end)
script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("prototype-cap400 state is absent") end
  if state.phase == "prototype-cap400-running" then
    if game.tick > state.deadline then fail("actual relaxed-cap lab did not complete") end
    state.lab.energy = 100000000
    if state.completed == #state.plan then
      assert_complete(state)
      state.phase = "prototype-cap400-saved"
      marker("initial", state)
      game.server_save(SAVE)
    elseif game.forces.player.current_research == nil then
      local name = state.plan[state.completed + 1]
      local force = game.forces.player
      if #force.research_queue ~= 0 or force.add_research(technology(force, name)) ~= true
          or not force.current_research or force.current_research.name ~= name or #force.research_queue ~= 1 then
        fail("native queue refused the next relaxed-cap lab research")
      end
      state.queue_count = state.queue_count + 1
    end
  elseif state.phase == "prototype-cap400-saved" and loaded and not reload_logged then
    if loaded.completed ~= state.completed or loaded.events ~= state.events or loaded.queue_count ~= state.queue_count then
      fail("on_load changed relaxed-cap state")
    end
    assert_complete(state)
    marker("reload", state)
    reload_logged = true
  end
end)
