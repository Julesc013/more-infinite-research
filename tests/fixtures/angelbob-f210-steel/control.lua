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

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function assert_lab_modifiers(force, phase)
  if force.laboratory_speed_modifier ~= 0 or force.laboratory_productivity_bonus ~= 0 then
    fail(phase .. " fixture requires unmodified force laboratory modifiers")
  end
end

local function baseline_bonuses(force)
  local baselines = {}
  for recipe, value in pairs(force.recipes) do
    if value == nil or not finite(value.productivity_bonus) then
      fail("native productivity baseline differs: " .. recipe)
    end
    baselines[recipe] = value.productivity_bonus
  end
  for _, recipe in ipairs(facts.named_recipes) do
    if not finite_nonnegative(baselines[recipe]) then fail("native productivity baseline differs: " .. recipe) end
  end
  return baselines
end

local function owner_deltas(force, owner)
  local deltas, counts = {}, {}
  for _, effect in ipairs(owner.prototype.effects) do
    if effect.type == "change-recipe-productivity" then
      local recipe, change = effect.recipe, effect.change
      if type(recipe) ~= "string" or force.recipes[recipe] == nil or type(change) ~= "number"
          or change ~= change or change == math.huge or change == -math.huge then
        fail("native owner productivity effect differs: " .. tostring(recipe))
      end
      deltas[recipe] = (deltas[recipe] or 0) + change
      counts[recipe] = (counts[recipe] or 0) + 1
    end
  end
  return deltas, counts
end

-- Qualified F210 plain-item value: inventory plus the lab's stored durability.
local function science_value(lab, pack)
  local input = lab.get_inventory(defines.inventory.lab_input)
  local prototype = prototypes.item[pack]
  local maximum = prototype and prototype.science_capacity
  if input == nil or prototype == nil or prototype.type ~= "item" or not finite_nonnegative(maximum)
      or maximum == 0 then fail("plain science capacity differs: " .. pack) end
  local out = {mode="item", maximum=maximum, count=input.get_item_count(pack), slots={}, inventory_units=0}
  for index=1, #input do
    local stack = input[index]
    if stack.valid_for_read and stack.name == pack then
      if stack.quality == nil or stack.quality.name ~= "normal" then fail("science quality differs: " .. pack) end
      out.inventory_units = out.inventory_units + stack.count
      out.slots[#out.slots+1] = {slot=index, count=stack.count, quality=stack.quality.name, units=stack.count}
    end
  end
  if out.inventory_units ~= out.count then fail("science inventory count differs: " .. pack) end
  local stored = lab.get_stored_durability(pack)
  local quality = stored.quality
  local quality_name = quality and (type(quality) == "string" and quality or quality.name) or false
  if not finite_nonnegative(stored.durability) or quality_name ~= false and quality_name ~= "normal" then
    fail("stored science durability or quality differs: " .. pack)
  end
  out.stored_quality, out.stored_durability = quality_name, stored.durability
  out.stored_units = stored.durability / maximum
  out.units = out.inventory_units + out.stored_units
  return out
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
    local before = science_value(state.lab, name)
    if before.count == 0 then
      local inserted = inventory.insert{name=name, count=facts.refill_amount}
      if inserted ~= facts.refill_amount then fail("fixture laboratory rejected science: " .. name) end
      local after = science_value(state.lab, name)
      if after.count ~= facts.refill_amount or math.abs(after.units - before.units - inserted) > .00000001
          or after.stored_durability ~= before.stored_durability then fail("science refill merged partial value: " .. name) end
      state.supplied[name] = state.supplied[name] + inserted
      state.supply_events[#state.supply_events+1] = {pack=name, count_before=before.count, count_after=after.count,
        inserted=inserted, units_before=before.units, units_after=after.units,
        stored_before=before.stored_durability, stored_after=after.stored_durability}
    end
  end
  return inventory
end

local function assert_paid(state, phase)
  local inventory = state.lab and state.lab.valid and state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail(phase .. " fixture laboratory input is absent") end
  local paid, remaining, science = {}, {}, {}
  for _, name in ipairs(facts.ingredients) do
    science[name] = science_value(state.lab, name)
    remaining[name] = science[name].units
    paid[name] = state.supplied[name] - remaining[name]
    if math.abs(paid[name] - facts.first_level_count) > facts.science_tolerance then
      fail(phase .. " actual native science payment differs: " .. name, {paid=paid, remaining=remaining, supplied=state.supplied})
    end
  end
  return paid, remaining, science
end

local function assert_complete(state, phase)
  local force = game.forces.player
  local owner = assert_owner(force, phase, false)
  if state.finished ~= 1 or owner.level ~= 2 or owner.researched ~= false or force.current_research ~= nil then
    fail(phase .. " requires exactly one real native steel completion")
  end
  local effects, effect_counts = owner_deltas(force, owner)
  for recipe, delta in pairs(state.owner_deltas) do
    if not facts.close(effects[recipe], delta) or effect_counts[recipe] ~= state.owner_effect_counts[recipe] then
      fail(phase .. " owner productivity delta map differs: " .. recipe)
    end
  end
  for recipe in pairs(effects) do if state.owner_deltas[recipe] == nil then fail(phase .. " owner delta added: " .. recipe) end end
  local bonuses, deltas, all_bonuses, all_deltas, recipe_count = {}, {}, {}, {}, 0
  for recipe, value in pairs(force.recipes) do
    local baseline = state.baselines and state.baselines[recipe]
    local delta = state.owner_deltas[recipe] or 0
    if value == nil or not finite(baseline) or not finite(value.productivity_bonus)
        or not facts.close(value.productivity_bonus, baseline + delta) then
      fail(phase .. " native productivity bonus differs: " .. recipe)
    end
    recipe_count = recipe_count + 1
    all_bonuses[recipe], all_deltas[recipe] = value.productivity_bonus, value.productivity_bonus - baseline
  end
  for recipe in pairs(state.baselines) do if force.recipes[recipe] == nil then fail(phase .. " original recipe absent: " .. recipe) end end
  for _, recipe in ipairs(facts.named_recipes) do bonuses[recipe], deltas[recipe] = all_bonuses[recipe], all_deltas[recipe] end
  local paid, remaining, science = assert_paid(state, phase)
  return {level=owner.level, bonuses=bonuses, deltas=deltas, all_bonuses=all_bonuses, all_deltas=all_deltas,
    recipe_count=recipe_count, paid=paid, remaining=remaining, science=science}
end

local function marker(stage, state)
  local frame = assert_complete(state, stage)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="angelbob-f210-steel", stage=stage, status="passed",
    witnesses={actual_steel_laboratory_completions=state.finished, event_by_script=false,
      named_steel_recipes=facts.named_recipes, named_effect_count_each=1,
      named_productivity_baselines=state.named_baselines, named_productivity_deltas=frame.deltas,
      named_productivity_bonuses=frame.bonuses, ordinary_first_level_count=facts.first_level_count,
      recipe_productivity_baselines=state.baselines, owner_recipe_productivity_deltas=state.owner_deltas,
      owner_recipe_productivity_effect_counts=state.owner_effect_counts, recipe_productivity_count=frame.recipe_count,
      recipe_productivity_bonuses=frame.all_bonuses, recipe_productivity_deltas=frame.all_deltas,
      ordinary_research_unit_energy=facts.research_unit_energy, ordinary_science_vector=facts.ingredients,
      actual_paid_science=frame.paid, remaining_science=frame.remaining, science_value=frame.science,
      initial_science_value=state.initial_science, supply_events=state.supply_events,
      science_abs_tolerance=facts.science_tolerance, scripted_finite_prerequisite_setup=true,
      settled_after_finished_tick=state.finish_tick + facts.settle_ticks, on_load_read_only=stage == "reload",
      broader_eligible_steel_recipes_unconstrained=false, all_recipe_productivity_verified=true,
      prototype_baseline_capture_required=true,
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
  local deltas, effect_counts = owner_deltas(force, owner)
  local named_baselines = {}
  for _, recipe in ipairs(facts.named_recipes) do named_baselines[recipe] = baselines[recipe] end
  local lab, inventory = create_lab(force)
  local supplied, initial_science = {}, {}
  for _, name in ipairs(facts.ingredients) do
    if science_value(lab, name).units ~= 0 then fail("new fixture lab already contains science: " .. name) end
    local inserted = inventory.insert{name=name, count=facts.initial_stack}
    if inserted ~= facts.initial_stack then fail("fixture laboratory rejected initial science: " .. name) end
    supplied[name] = inserted
    initial_science[name] = science_value(lab, name)
  end
  storage[KEY] = {phase="starting", lab=lab, supplied=supplied, baselines=baselines, named_baselines=named_baselines,
    owner_deltas=deltas, owner_effect_counts=effect_counts, initial_science=initial_science, supply_events={}, finished=0, started=false,
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
