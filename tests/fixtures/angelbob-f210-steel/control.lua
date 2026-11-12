local facts = require("__mir-fixture-mir5-angelbob-f210-steel__/fixture_facts")
local KEY, loaded, reload_reported = "mir5_angelbob_f210_steel", false, false

local function fail(message, fields)
  if helpers and helpers.table_to_json and log then
    log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json({
      case="angelbob-f210-steel", status="failed", error=message, fields=fields,
    }))
  end
  error("[mir5-angelbob-f210-steel] " .. message)
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function assert_closure()
  facts.assert_exact_mods(script.active_mods, fail)
end

local function assert_vector(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  local seen = {}
  for _, row in ipairs(actual) do
    if type(row) ~= "table" or type(row.name) ~= "string" or row.amount ~= 1 or seen[row.name] then
      fail(label .. " member differs")
    end
    seen[row.name] = true
  end
  for _, name in ipairs(expected) do if not seen[name] then fail(label .. " is absent: " .. name) end end
end

local function assert_named_effects(value)
  local effects, counts = value.prototype and value.prototype.effects, {}
  if type(effects) ~= "table" then fail("native steel effects are absent") end
  for _, effect in ipairs(effects) do
    if type(effect) == "table" and effect.type == "change-recipe-productivity" then
      for _, recipe in ipairs(facts.named_recipes) do
        if effect.recipe == recipe then
          counts[recipe] = (counts[recipe] or 0) + 1
          if not facts.close(effect.change, facts.effect_change) then fail("native steel change differs: " .. recipe) end
        end
      end
    end
  end
  for _, recipe in ipairs(facts.named_recipes) do
    if counts[recipe] ~= 1 then fail("native steel named effect count differs: " .. recipe) end
  end
end

local function finite_nonnegative(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value >= 0
end

local function assert_lab_modifiers(force, phase)
  if force.laboratory_speed_modifier ~= 0 or force.laboratory_productivity_bonus ~= 0 then
    fail(phase .. " fixture requires unmodified force laboratory modifiers")
  end
end

local function baseline_bonuses(force)
  local baselines = {}
  for _, recipe in ipairs(facts.named_recipes) do
    local value = force.recipes and force.recipes[recipe]
    if value == nil or not finite_nonnegative(value.productivity_bonus) then
      fail("native productivity baseline differs: " .. recipe)
    end
    baselines[recipe] = value.productivity_bonus
  end
  return baselines
end

local function assert_owner(force, phase, require_first_level_count)
  local owner = technology(force, facts.owner)
  if owner.prototype == nil or owner.prototype.level ~= 1 or owner.prototype.max_level ~= 4294967295
      or owner.prototype.research_unit_count_formula ~= "1.5^L*1000" or owner.research_unit_energy ~= facts.research_unit_energy then
    fail(phase .. " native steel ordinary cost differs")
  end
  if require_first_level_count and owner.research_unit_count ~= facts.first_level_count then fail(phase .. " native steel first-level count differs") end
  assert_vector(owner.research_unit_ingredients, facts.ingredients, phase .. " native steel ingredients")
  assert_named_effects(owner)
  return owner
end

local function create_lab(force)
  local lab = game.surfaces[1].create_entity{name=facts.fast_lab, position={0, 0}, force=force}
  if lab == nil or lab.valid == false or lab.prototype == nil or lab.prototype.name ~= facts.fast_lab
      or lab.quality == nil or lab.quality.name ~= "normal" or type(lab.prototype.get_researching_speed) ~= "function"
      or not facts.close(lab.prototype.get_researching_speed("normal"), facts.fast_lab_speed) then
    fail("fixture fast laboratory differs")
  end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("fixture laboratory input is absent") end
  return lab, inventory
end

local function supply(state)
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("fixture laboratory input is absent") end
  for _, name in ipairs(facts.ingredients) do
    if inventory.get_item_count(name) <= facts.refill_below then
      local inserted = inventory.insert{name=name, count=facts.refill_amount}
      if inserted ~= facts.refill_amount then fail("fixture laboratory rejected science: " .. name) end
      state.supplied[name] = state.supplied[name] + inserted
    end
  end
  return inventory
end

local function assert_paid(state, phase)
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail(phase .. " fixture laboratory input is absent") end
  local paid, remaining = {}, {}
  for _, name in ipairs(facts.ingredients) do
    remaining[name] = inventory.get_item_count(name)
    paid[name] = state.supplied[name] - remaining[name]
    if paid[name] ~= facts.first_level_count then
      fail(phase .. " actual native science payment differs: " .. name, {paid=paid, remaining=remaining, supplied=state.supplied})
    end
  end
  return paid, remaining
end

local function assert_complete(state, phase)
  local force = game.forces.player
  local owner = assert_owner(force, phase, false)
  if state.finished ~= 1 or owner.level ~= 2 or owner.researched ~= false or force.current_research ~= nil then
    fail(phase .. " requires exactly one real native steel completion")
  end
  local bonuses, deltas = {}, {}
  for _, recipe in ipairs(facts.named_recipes) do
    local value = force.recipes and force.recipes[recipe]
    local baseline = state.baselines and state.baselines[recipe]
    if value == nil or not finite_nonnegative(baseline) or not finite_nonnegative(value.productivity_bonus)
        or not facts.close(value.productivity_bonus, baseline + facts.effect_change) then
      fail(phase .. " native productivity bonus differs: " .. recipe)
    end
    bonuses[recipe] = value.productivity_bonus
    deltas[recipe] = value.productivity_bonus - baseline
  end
  local paid, remaining = assert_paid(state, phase)
  return {level=owner.level, bonuses=bonuses, deltas=deltas, paid=paid, remaining=remaining}
end

local function marker(stage, state)
  local frame = assert_complete(state, stage)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="angelbob-f210-steel", stage=stage, status="passed",
    witnesses={actual_steel_laboratory_completions=state.finished, event_by_script=false,
      named_steel_recipes=facts.named_recipes, named_effect_count_each=1,
      named_productivity_baselines=state.baselines, named_productivity_deltas=frame.deltas,
      named_productivity_bonuses=frame.bonuses, ordinary_first_level_count=facts.first_level_count,
      ordinary_research_unit_energy=facts.research_unit_energy, ordinary_science_vector=facts.ingredients,
      actual_paid_science=frame.paid, remaining_science=frame.remaining,
      settled_after_finished_tick=state.finish_tick + facts.settle_ticks, on_load_read_only=stage == "reload",
      broader_eligible_steel_recipes_unconstrained=true, prototype_baseline_capture_required=true,
      physical_output_qualified=false, migration_qualification=false, release_qualification=false},
  }))
end

script.on_init(function()
  assert_closure()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local force = game.forces.player
  assert_lab_modifiers(force, "before prerequisite seed")
  local prerequisite = technology(force, facts.prerequisites[1])
  prerequisite.enabled, prerequisite.researched = true, true
  assert_lab_modifiers(force, "after prerequisite seed")
  local owner = assert_owner(force, "initial", true)
  if owner.enabled ~= true or owner.researched ~= false or owner.level ~= 1 then fail("fresh native steel owner differs") end
  local baselines = baseline_bonuses(force)
  local lab, inventory = create_lab(force)
  local supplied = {}
  for _, name in ipairs(facts.ingredients) do
    local inserted = inventory.insert{name=name, count=facts.initial_stack}
    if inserted ~= facts.initial_stack then fail("fixture laboratory rejected initial science: " .. name) end
    supplied[name] = inserted
  end
  storage[KEY] = {phase="starting", lab=lab, supplied=supplied, baselines=baselines, finished=0, started=false,
    deadline=game.tick + facts.deadline_ticks}
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if state == nil or state.phase ~= "researching" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= facts.owner then return end
  if event.by_script ~= false then fail("scripted steel completion cannot satisfy this fixture") end
  if state.finished ~= 0 then fail("additional steel completion is not admitted") end
  state.finished, state.finish_tick, state.phase = 1, game.tick, "settling"
  if state.lab == nil or state.lab.valid == false then fail("fixture laboratory is absent at completion") end
  state.lab.disabled_by_script = true
end)

script.on_load(function()
  loaded = storage[KEY] and storage[KEY].phase == "complete" or false
  reload_reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if state == nil then fail("fixture state is absent") end
  assert_closure()
  if state.phase == "complete" then
    if loaded and not reload_reported then marker("reload", state); reload_reported = true end
    return
  end
  if game.tick > state.deadline then fail("steel laboratory deadline expired") end
  if state.phase == "starting" then
    state.phase, state.started = "researching", true
    if game.forces.player.add_research(assert_owner(game.forces.player, "start", true)) ~= true then
      fail("could not start native steel research")
    end
  end
  if state.phase == "researching" then
    supply(state)
    return
  end
  if state.phase == "settling" then
    if game.tick < state.finish_tick + facts.settle_ticks then return end
    assert_complete(state, "initial")
    state.phase = "complete"
    marker("initial", state)
    game.server_save(facts.save)
    return
  end
  fail("fixture phase differs")
end)
