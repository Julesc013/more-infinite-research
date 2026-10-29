-- Private native continuity fixture for the F200 Space Age fixed-provider contract.
-- It is deliberately one composed scenario: no provider-specific campaigns or
-- fixture-owned MIR state. Native execution is required for qualification.
local KEY = "mir5_competing_fixed_gameplay"
local CASE = "f200-competing-fixed-gameplay"
local FIXTURE = "mir-fixture-mir5-competing-fixed-gameplay"
local SAVE = "mir5-native-complete"
local UINT32_MAX = 4294967295
local PROBE = "braking-force-1"
local FOREIGN = "mir5-competing-fixed-foreign"
local DETACHED = "mir5-competing-fixed-detached"
local DEADLINE = 60 * 60 * 10

local TARGETS = {
  {id="automation-science-productivity-4", first=4, recipes={"automation-science-pack"}},
  {id="basic-plate-productivity", first=1, recipes={"copper-plate", "iron-plate"}},
  {id="bioflux-productivity", first=1, recipes={"bioflux"}},
  {id="fish-breeding-productivity", first=1, recipes={"fish-breeding"}},
}
-- This is the one captured remaining-MIR row exercised after the foreign
-- source levels.  It has all three effects while preferred, then only eggs
-- when the exact false-preference data-stage filter is active.
local MIR_BREEDING = "recipe-prod-research_breeding-1"
local MIR_BREEDING_FULL = {"biter-egg", "fish-breeding", "pentapod-egg"}
local MIR_BREEDING_FALSE = {"biter-egg", "pentapod-egg"}
-- This exact row is completely covered by the foreign bioflux provider.  In
-- contrast to breeding, false preference retains its completed effect vector
-- and disables its future levels.
local MIR_BIOFLUX = "recipe-prod-research_bioflux-1"
local MIR_BIOFLUX_EFFECTS = {"bioflux"}
local ALL = {
  "basic-plate-productivity", "electric-circuit-productivity", "advanced-circuit-productivity",
  "automation-science-productivity-4", "logistic-science-productivity-4", "military-science-productivity-4",
  "chemical-science-productivity-4", "production-science-productivity-4", "utility-science-productivity-4",
  "space-science-productivity-4", "metallurgic-science-productivity-4", "electromagnetic-science-productivity-4",
  "agricultural-science-productivity-4", "cryogenic-science-productivity-4", "promethium-science-productivity-4",
  "bioflux-productivity", "fish-breeding-productivity",
}
local loaded_snapshot, reload_logged, pending_save = nil, false, false

local function fail(message) error("[mir5-competing-fixed-gameplay] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= 0.000001
end
local function tech(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function require_mode(mir, fixture, preference, label, providers_present)
  local active = script.active_mods
  if active.base ~= "2.0.77" or active["space-age"] ~= "2.0.77"
      or active["more-infinite-research"] ~= mir or active[FIXTURE] ~= fixture then
    fail(label .. " fixture closure differs")
  end
  local providers = active["plates-n-circuit-productivity"] ~= nil
    or active.Science_packs_productivity ~= nil or active["bioflux-productivity"] ~= nil
    or active["fish-productivity"] ~= nil
  if providers_present == false then
    if providers then fail(label .. " unexpectedly retains a fixed provider") end
  elseif active["plates-n-circuit-productivity"] ~= "0.0.2"
      or active.Science_packs_productivity ~= "0.0.1"
      or active["bioflux-productivity"] ~= "0.1.0" or active["fish-productivity"] ~= "1.0.0" then
    fail(label .. " fixture provider closure differs")
  end
  local setting = settings.startup["mir-prefer-this-mod-for-competing-techs"]
  if setting == nil or setting.value ~= preference then fail(label .. " preference setting differs") end
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function status(force, name)
  local value = tech(force, name)
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, maximum=value.prototype.max_level,
    saved_progress=value.saved_progress}
end
local function assert_status(force, name, expected, label)
  local actual = status(force, name)
  local function display(value)
    return "level:" .. tostring(value.level) .. ",researched:" .. tostring(value.researched)
      .. ",enabled:" .. tostring(value.enabled) .. ",visible:" .. tostring(value.visible)
      .. ",maximum:" .. tostring(value.maximum) .. ",saved_progress:" .. tostring(value.saved_progress)
  end
  if actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible ~= expected.visible
      or actual.maximum ~= expected.maximum or not close(actual.saved_progress, expected.saved_progress) then
    fail(label .. " state differs: " .. name .. " expected=" .. display(expected) .. " actual=" .. display(actual))
  end
  return actual
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queue,
    progress=force.research_progress}
end
local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue or {}) do queue[index] = name end
  return {current=value.current, queue=queue, progress=value.progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue changed at " .. tostring(index)) end
  end
  return actual
end
local function recipes(targets)
  local values, seen = {}, {}
  for _, target in ipairs(targets) do
    for _, name in ipairs(target.recipes) do
      if not seen[name] then values[#values + 1], seen[name] = name, true end
    end
  end
  return values
end
local EFFECT_RECIPES = recipes(TARGETS)
local function effects(force)
  local values = {}
  for _, recipe in ipairs(EFFECT_RECIPES) do
    local value = force.recipes[recipe]
    if value == nil then fail("recipe is absent: " .. recipe) end
    values[recipe] = value.productivity_bonus
  end
  return values
end
local function selected_effects(force, names)
  local values = {}
  for _, recipe in ipairs(names) do
    local value = force.recipes[recipe]
    if value == nil then fail("recipe is absent: " .. recipe) end
    values[recipe] = value.productivity_bonus
  end
  return values
end
local function assert_selected_effects(force, expected, names, label)
  local actual = selected_effects(force, names)
  for _, recipe in ipairs(names) do
    if not close(actual[recipe], expected[recipe]) then fail(label .. " productivity changed: " .. recipe) end
  end
end
local function advanced_effects(start, names)
  local values = {}
  for recipe, amount in pairs(start) do values[recipe] = amount end
  for _, recipe in ipairs(names) do values[recipe] = start[recipe] + 0.1 end
  return values
end
local function assert_effects(force, expected, label)
  local actual = effects(force)
  for _, recipe in ipairs(EFFECT_RECIPES) do
    if not close(actual[recipe], expected[recipe]) then
      fail(label .. " productivity changed: " .. recipe .. " expected=" .. tostring(expected[recipe])
        .. " actual=" .. tostring(actual[recipe]))
    end
  end
end
local function copy_effects(value)
  local out = {}
  for recipe, amount in pairs(value) do out[recipe] = amount end
  return out
end
local function expected_effects(start)
  local out = copy_effects(start)
  for _, target in ipairs(TARGETS) do
    for _, recipe in ipairs(target.recipes) do out[recipe] = out[recipe] + 0.1 end
  end
  return out
end
local function assert_accelerated(value, label)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail(label .. " did not retain one-unit one-second research")
  end
end
local function assert_breeding(value, level, label, accelerated)
  if value.level ~= level or value.researched ~= false or value.enabled ~= true
      or value.visible_when_disabled ~= false or value.prototype.max_level ~= UINT32_MAX
      or not close(value.saved_progress, 0) then
    fail(label .. " remaining MIR breeding state differs")
  end
  if accelerated then assert_accelerated(value, label .. " remaining MIR breeding") end
end
local function assert_full_bioflux(value, level, enabled, visible, accelerated, label)
  if value.level ~= level or value.researched ~= false or value.enabled ~= enabled
      or value.visible_when_disabled ~= visible or value.prototype.max_level ~= UINT32_MAX
      or not close(value.saved_progress, 0) then
    fail(label .. " fully covered MIR bioflux state differs")
  end
  if accelerated then assert_accelerated(value, label .. " fully covered MIR bioflux") end
end
local function assert_full_bioflux_completion(state, label)
  if state.full_mir_actual_lab_completions ~= 1 then
    fail(label .. " fully covered MIR bioflux actual lab witness differs")
  end
end
local function fill(lab, value)
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("lab input is absent") end
  input.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    local inserted = input.insert{name=ingredient.name, count=100}
    if inserted ~= 100 then fail("lab did not receive science: " .. ingredient.name) end
  end
  lab.energy = 1000000000
  lab.disabled_by_script = false
end
local function freeze(state)
  local lab = state.lab
  if lab == nil or lab.valid == false then fail("source lab is absent") end
  lab.disabled_by_script, lab.energy = true, 0
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("source lab input is absent") end
  input.clear()
end
local function assert_frozen(state, providers_present)
  local lab = state.lab
  if lab == nil or lab.valid == false or lab.disabled_by_script ~= true or lab.energy ~= 0 then fail("source lab was not frozen") end
  local input = lab.get_inventory(defines.inventory.lab_input)
  if input == nil then fail("source lab input is absent") end
  if providers_present ~= false then
    for _, target in ipairs(TARGETS) do
      for _, ingredient in ipairs(tech(game.forces.player, target.id).research_unit_ingredients) do
        if input.get_item_count(ingredient.name) ~= 0 then fail("source lab retained science: " .. ingredient.name) end
      end
    end
  end
end
local function assert_all(force, enabled, visible, label, except)
  for _, name in ipairs(ALL) do
    if except == nil or except[name] == nil then
      local value = tech(force, name)
      if value.enabled ~= enabled or value.visible_when_disabled ~= visible then
        fail(label .. " presentation changed: " .. name)
      end
    end
  end
end
local function assert_foreign(state)
  local foreign = game.forces[state.foreign_force_index]
  if foreign == nil or foreign.valid == false or foreign.name ~= FOREIGN then fail("foreign force is absent") end
  assert_all(foreign, false, true, "foreign")
  if state.foreign_full_mir_bioflux_initialized == true then
    -- This matching main MIR row was disabled before MIR5's false-to-true
    -- transition. It must not acquire the player force's restoration right.
    assert_status(foreign, MIR_BIOFLUX, {level=1, researched=false, enabled=false, visible=false,
      maximum=UINT32_MAX, saved_progress=0}, "foreign fully covered MIR bioflux")
  elseif state.foreign_full_mir_bioflux_initialized == false then
    if foreign.technologies[MIR_BIOFLUX] ~= nil then
      fail("published foreign fully covered MIR bioflux unexpectedly exists")
    end
  else
    fail("foreign fully covered MIR bioflux initialization witness is absent")
  end
  assert_queue(foreign, state.foreign_queue, "foreign")
  if not close(tech(foreign, PROBE).saved_progress, state.foreign_current_saved_progress) then
    fail("foreign current raw progress changed")
  end
end
local function assert_detached(state)
  local detached = game.forces[state.detached_force_index]
  if detached == nil or detached.valid == false or detached.name ~= DETACHED then fail("detached force is absent") end
  assert_status(detached, "basic-plate-productivity", {level=1, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, saved_progress=0.27}, "detached partial initial")
  if detached.current_research ~= nil or #(detached.research_queue or {}) ~= 0 or not close(detached.research_progress, 0) then
    fail("detached partial initial gained a queue")
  end
end
local function assert_provider_rows_absent(force, label)
  for _, name in ipairs(ALL) do
    if force.technologies[name] ~= nil then fail(label .. " retained removed provider row: " .. name) end
  end
end
local function assert_foreign_without_providers(state)
  local foreign = game.forces[state.foreign_force_index]
  if foreign == nil or foreign.valid == false or foreign.name ~= FOREIGN then fail("foreign force is absent") end
  assert_provider_rows_absent(foreign, "foreign")
  assert_status(foreign, MIR_BIOFLUX, {level=1, researched=false, enabled=false, visible=false,
    maximum=UINT32_MAX, saved_progress=0}, "foreign fully covered MIR bioflux after provider removal")
  assert_queue(foreign, state.foreign_queue, "foreign after provider removal")
  if not close(tech(foreign, PROBE).saved_progress, state.foreign_current_saved_progress) then
    fail("foreign current raw progress changed after provider removal")
  end
end
local function assert_detached_without_providers(state)
  local detached = game.forces[state.detached_force_index]
  if detached == nil or detached.valid == false or detached.name ~= DETACHED then fail("detached force is absent") end
  assert_provider_rows_absent(detached, "detached")
  if detached.current_research ~= nil or #(detached.research_queue or {}) ~= 0 or not close(detached.research_progress, 0) then
    fail("detached provider removal changed its empty queue")
  end
end
local function assert_source_witness(state)
  if type(state) ~= "table" or state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0"
      or state.actual_lab_completions ~= #TARGETS or state.milestone ~= "four-native-fixed-provider-labs"
      or state.prerequisite_seeding ~= "completed-before-native-labs" then
    fail("published source witness differs")
  end
end
local function assert_source(state)
  assert_source_witness(state)
  local player = game.forces.player
  if state.full_mir_bioflux_introduced ~= false or player.technologies[MIR_BIOFLUX] ~= nil then
    fail("published player fully covered MIR bioflux unexpectedly exists")
  end
  for _, target in ipairs(TARGETS) do
    assert_status(player, target.id, {level=target.first + 1, researched=false, enabled=true, visible=false,
      maximum=UINT32_MAX, saved_progress=0}, "published earned")
  end
  assert_effects(player, state.player_effects, "published earned")
  assert_status(player, "advanced-circuit-productivity", {level=1, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, saved_progress=0}, "published untouched initial")
  assert_queue(player, state.player_queue, "published player")
  if not close(tech(player, "electric-circuit-productivity").saved_progress, 0)
      or not close(tech(player, PROBE).saved_progress, state.probe_inactive_saved_progress) then
    fail("published current/inactive progress witnesses differ")
  end
  assert_frozen(state)
  assert_foreign(state)
  assert_detached(state)
end
local function selected_source_effects(state, ...)
  local expected = copy_effects(state.player_effects)
  for _, selected in ipairs({...}) do
    for recipe, amount in pairs(selected or {}) do
      if expected[recipe] ~= nil then expected[recipe] = amount end
    end
  end
  return expected
end
local function assert_earned_source(state, label, expected_effects)
  local player = game.forces.player
  for _, target in ipairs(TARGETS) do
    local value = tech(player, target.id)
    if value.level ~= target.first + 1 or value.researched ~= false then
      fail(label .. " earned level changed: " .. target.id)
    end
  end
  assert_effects(player, expected_effects or state.player_effects, label .. " earned")
end
local function assert_preferred(state, expected_effects)
  assert_source_witness(state)
  assert_frozen(state)
  assert_foreign(state)
  assert_detached(state)
  assert_earned_source(state, "preferred", expected_effects)
  local player = game.forces.player
  assert_all(player, false, true, "preferred player", { ["electric-circuit-productivity"] = true })
  assert_status(player, "electric-circuit-productivity", {level=1, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, saved_progress=0}, "preferred queued initial")
  assert_queue(player, state.player_queue, "preferred player")
end
local function assert_released(state, expected_effects)
  assert_source_witness(state)
  assert_frozen(state)
  assert_foreign(state)
  assert_detached(state)
  assert_earned_source(state, "released", expected_effects)
  local player = game.forces.player
  assert_all(player, true, false, "released player")
  assert_queue(player, state.player_queue, "released player")
end
local function assert_true_breeding(state)
  assert_preferred(state, selected_source_effects(state, state.true_bioflux_effects, state.true_breeding_effects))
  local player = game.forces.player
  assert_full_bioflux_completion(state, "preferred")
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 2, true, false, true, "preferred")
  assert_selected_effects(player, state.true_bioflux_effects, MIR_BIOFLUX_EFFECTS, "preferred bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 2, "preferred", true)
  assert_selected_effects(player, state.true_breeding_effects, MIR_BREEDING_FULL, "preferred breeding")
end
local function assert_false_breeding(state)
  assert_released(state, selected_source_effects(state, state.true_bioflux_effects, state.true_breeding_effects))
  local player = game.forces.player
  assert_full_bioflux_completion(state, "released")
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 2, false, false, false, "released")
  assert_selected_effects(player, state.true_bioflux_effects, MIR_BIOFLUX_EFFECTS, "released bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 3, "released", true)
  assert_selected_effects(player, state.false_breeding_effects, MIR_BREEDING_FULL, "released breeding")
end
local function assert_breeding_earned_after_false(state)
  assert_source_witness(state)
  assert_frozen(state)
  assert_foreign(state)
  assert_detached(state)
  local player = game.forces.player
  assert_full_bioflux_completion(state, "re-preference transition")
  assert_earned_source(state, "re-preference transition", selected_source_effects(state, state.true_bioflux_effects, state.true_breeding_effects))
  assert_selected_effects(player, state.true_bioflux_effects, MIR_BIOFLUX_EFFECTS,
    "re-preference transition retained released bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 3, "re-preference transition", false)
  assert_selected_effects(player, state.false_breeding_effects, MIR_BREEDING_FULL,
    "re-preference transition retained released breeding")
  assert_queue(player, state.player_queue, "re-preference transition player")
end
local function assert_repreferred_breeding(state)
  assert_preferred(state, selected_source_effects(state, state.true_bioflux_effects, state.true_breeding_effects))
  local player = game.forces.player
  assert_full_bioflux_completion(state, "re-preferred")
  -- This enablement is the runtime's recorded disablement right from the false
  -- stage.  A pre-disabled foreign row must never receive this transition.
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 2, true, false, false, "re-preferred")
  assert_selected_effects(player, state.true_bioflux_effects, MIR_BIOFLUX_EFFECTS, "re-preferred bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 3, "re-preferred", false)
  assert_selected_effects(player, state.false_breeding_effects, MIR_BREEDING_FULL, "re-preferred breeding")
end
local function assert_provider_absent_before_lab(state)
  assert_source_witness(state)
  assert_frozen(state, false)
  local player = game.forces.player
  assert_provider_rows_absent(player, "player")
  assert_queue(player, state.player_queue, "provider removal player")
  assert_foreign_without_providers(state)
  assert_detached_without_providers(state)
  assert_full_bioflux_completion(state, "provider removal")
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 2, true, false, true, "provider removal pre-lab")
  assert_selected_effects(player, {bioflux=0.1}, MIR_BIOFLUX_EFFECTS, "provider removal pre-lab bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 3, "provider removal pre-lab", false)
  assert_selected_effects(player, { ["fish-breeding"]=0.1, ["biter-egg"]=0.2, ["pentapod-egg"]=0.2 },
    MIR_BREEDING_FULL, "provider removal pre-lab breeding")
end
local function assert_provider_absent_completed(state)
  assert_source_witness(state)
  assert_frozen(state, false)
  local player = game.forces.player
  assert_provider_rows_absent(player, "player")
  assert_queue(player, state.player_queue, "provider removal player")
  assert_foreign_without_providers(state)
  assert_detached_without_providers(state)
  if state.full_mir_actual_lab_completions ~= 2 then
    fail("provider removal fully covered MIR bioflux actual lab witness differs")
  end
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 3, true, false, true, "provider removal completed")
  assert_selected_effects(player, state.provider_absent_bioflux_effects, MIR_BIOFLUX_EFFECTS,
    "provider removal completed bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 3, "provider removal completed", false)
  assert_selected_effects(player, { ["fish-breeding"]=0.1, ["biter-egg"]=0.2, ["pentapod-egg"]=0.2 },
    MIR_BREEDING_FULL, "provider removal completed breeding")
end
local function assert_readded_foreign(state)
  assert_source_witness(state)
  assert_frozen(state)
  assert_foreign(state)
  local player = game.forces.player
  assert_all(player, true, false, "readded foreign player")
  assert_queue(player, state.player_queue, "readded foreign player")
  if state.full_mir_actual_lab_completions ~= 2 then
    fail("readded foreign fully covered MIR bioflux actual lab witness differs")
  end
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 3, false, false, false, "readded foreign")
  assert_selected_effects(player, state.provider_absent_bioflux_effects, MIR_BIOFLUX_EFFECTS,
    "readded foreign retained bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 3, "readded foreign", true)
  assert_selected_effects(player, state.false_breeding_effects, MIR_BREEDING_FULL,
    "readded foreign retained breeding")
end
local function assert_breeding_earned_before_false(state)
  assert_source_witness(state)
  assert_frozen(state)
  assert_foreign(state)
  assert_detached(state)
  local player = game.forces.player
  local credit = {}
  for _, name in ipairs({MIR_BREEDING,
      "mir-native-credit-research_breeding-fish-breeding-positive",
      "mir-native-credit-research_breeding-fish-breeding-negative"}) do
    local value = player.technologies[name]
    local prototype = value and value.prototype
    credit[#credit + 1] = {name=name, present=value ~= nil,
      level=value and value.level, researched=value and value.researched,
      prototype_name=prototype and prototype.name, prototype_level=prototype and prototype.level,
      prototype_maximum=prototype and prototype.max_level, hidden=prototype and prototype.hidden,
      prototype_enabled=prototype and prototype.enabled,
      prototype_visible=prototype and prototype.visible_when_disabled,
      effects=prototype and prototype.effects}
  end
  log("[MIR5_NATIVE_FIXTURE] CREDIT_TRANSITION " .. helpers.table_to_json(credit))
  assert_full_bioflux_completion(state, "false transition")
  assert_earned_source(state, "false transition", selected_source_effects(state, state.true_bioflux_effects, state.true_breeding_effects))
  assert_full_bioflux(tech(player, MIR_BIOFLUX), 2, false, false, false, "false transition")
  assert_selected_effects(player, state.true_bioflux_effects, MIR_BIOFLUX_EFFECTS,
    "false transition retained preferred bioflux")
  assert_breeding(tech(player, MIR_BREEDING), 2, "false transition", true)
  assert_selected_effects(player, state.true_breeding_effects, MIR_BREEDING_FULL,
    "false transition retained preferred breeding")
  assert_queue(player, state.player_queue, "false transition player")
end
local function prepend_research(state, name, label)
  local player = game.forces.player
  local queued = player.current_research
  local queue = player.research_queue or {}
  local probe = queue[2]
  assert_queue(player, state.player_queue, label .. " before remaining MIR research")
  if queued == nil or queued.name ~= "electric-circuit-productivity" or probe == nil or probe.name ~= PROBE then
    fail(label .. " queued partial research identity differs")
  end
  queued.saved_progress = player.research_progress
  player.research_queue = {tech(player, name), queued, probe}
  assert_queue(player, {current=name, queue={name, "electric-circuit-productivity", PROBE}, progress=0},
    label .. " remaining MIR queue")
  if not close(queued.saved_progress, 0.27) or not close(probe.saved_progress, 0.42) then
    fail(label .. " did not retain queued partial work")
  end
  fill(state.lab, tech(player, name))
end
local function marker(stage, state)
  local player = game.forces.player
  local providers_present = script.active_mods["plates-n-circuit-productivity"] ~= nil
  local function optional_level(force, name)
    local value = force.technologies[name]
    return value and value.level or "absent"
  end
  local function optional_saved_progress(force, name)
    local value = force.technologies[name]
    return value and value.saved_progress or "absent"
  end
  local function optional_disabled(force, name)
    local value = force.technologies[name]
    if value == nil then return "absent" end
    return value.enabled == false
  end
  local full = {status="absent-published-predecessor"}
  local foreign_full = {status="absent-published-predecessor"}
  if state.full_mir_bioflux_introduced == true then
    local value = tech(player, MIR_BIOFLUX)
    full = {status="present", actual_lab_completions=state.full_mir_actual_lab_completions,
      next_level=value.level, enabled=value.enabled, productivity_bonus=player.recipes["bioflux"].productivity_bonus}
  end
  if state.foreign_full_mir_bioflux_initialized == true then
    foreign_full = {status="present-pre-disabled",
      enabled=tech(game.forces[state.foreign_force_index], MIR_BIOFLUX).enabled}
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage=stage, case=CASE, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir=state.source_mir, destination_mir=script.active_mods["more-infinite-research"],
      actual_lab_completions=state.actual_lab_completions, milestone=state.milestone,
      fully_covered_mir_bioflux=full,
      fixed_providers_present=providers_present,
      science_tail_next_level=optional_level(player, "automation-science-productivity-4"),
      plate_next_level=optional_level(player, "basic-plate-productivity"),
      bioflux_next_level=optional_level(player, "bioflux-productivity"),
      fish_next_level=optional_level(player, "fish-breeding-productivity"),
      remaining_mir_breeding_next_level=tech(player, MIR_BREEDING).level,
      remaining_mir_biter_egg_bonus=player.recipes["biter-egg"].productivity_bonus,
      remaining_mir_pentapod_egg_bonus=player.recipes["pentapod-egg"].productivity_bonus,
      remaining_mir_fish_bonus=player.recipes["fish-breeding"].productivity_bonus,
      queued_initial_current=queue_snapshot(player).current, current_progress=queue_snapshot(player).progress,
      detached_initial_saved_progress=optional_saved_progress(game.forces[state.detached_force_index], "basic-plate-productivity"),
      foreign_still_disabled=optional_disabled(game.forces[state.foreign_force_index], "basic-plate-productivity"),
      foreign_full_mir_bioflux=foreign_full,
      false_preference_future_effect_coverage=(state.phase == "prefer-foreign-breeding-completed"
          or state.phase == "providers-readded-foreign-completed")
        and "prepared-breeding-row-native-readback-required" or "not-applicable",
      lab_frozen=true, on_load_read_only=stage == "reload"},
  }))
end

script.on_init(function()
  require_mode("4.7.20002", "0.1.0", false, "published source")
  if storage[KEY] ~= nil then fail("source fixture storage already exists") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  if player.technologies[MIR_BIOFLUX] ~= nil then
    fail("published player fully covered MIR bioflux unexpectedly exists")
  end
  for _, target in ipairs(TARGETS) do
    local value = tech(player, target.id)
    prerequisites(value)
    assert_accelerated(value, "published " .. target.id)
    assert_status(player, target.id, {level=target.first, researched=false, enabled=true, visible=false,
      maximum=UINT32_MAX, saved_progress=0}, "published pre-lab")
  end
  local queued = tech(player, "electric-circuit-productivity")
  local untouched = tech(player, "advanced-circuit-productivity")
  prerequisites(queued); prerequisites(untouched)
  if queued.researched or untouched.researched then fail("initial retirement rows were researched by prerequisites") end
  local probe = tech(player, PROBE)
  prerequisites(probe)
  if probe.researched then fail("unrelated braking probe was researched by prerequisites") end
  -- Completing the authored science prerequisites earns their finite native
  -- productivity bonuses. Measure the baseline after all player prerequisites;
  -- the four observed lab completions must each add exactly one further level.
  local starting_effects = effects(player)

  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  for _, name in ipairs(ALL) do
    local value = tech(foreign, name)
    prerequisites(value)
    value.enabled, value.visible_when_disabled = false, true
  end
  if foreign.technologies[MIR_BIOFLUX] ~= nil then
    fail("published foreign fully covered MIR bioflux unexpectedly exists")
  end
  local foreign_probe = tech(foreign, PROBE)
  prerequisites(foreign_probe)
  if foreign_probe.researched then fail("foreign braking probe was researched by prerequisites") end
  foreign_probe.saved_progress = 0.42
  if foreign.add_research(foreign_probe) ~= true then fail("could not queue foreign braking probe") end
  local foreign_queue = assert_queue(foreign, {current=PROBE, queue={PROBE}, progress=0.42}, "foreign setup")
  if not close(foreign_probe.saved_progress, 0) then fail("foreign current raw progress was retained") end

  local detached = game.create_force(DETACHED)
  detached.enable_all_prototypes()
  local detached_basic = tech(detached, "basic-plate-productivity")
  prerequisites(detached_basic)
  if detached_basic.researched then fail("detached initial was researched by prerequisites") end
  detached_basic.saved_progress = 0.27

  local lab = game.surfaces[1].create_entity{name="biolab", position={0, 0}, force=player}
  if lab == nil or lab.valid == false then fail("could not create real Space Age biolab") end
  local state = {phase="await-lab", source_mir=script.active_mods["more-infinite-research"],
    fixture_version=script.active_mods[FIXTURE], actual_lab_completions=0,
    prerequisite_seeding="completed-before-native-labs", player_start_effects=copy_effects(starting_effects),
    foreign_force_index=foreign.index, detached_force_index=detached.index, foreign_queue=foreign_queue,
    foreign_current_saved_progress=foreign_probe.saved_progress, lab=lab, deadline_tick=game.tick + DEADLINE,
    full_mir_bioflux_introduced=false, foreign_full_mir_bioflux_initialized=false}
  storage[KEY] = state
  fill(lab, tech(player, TARGETS[1].id))
  if player.add_research(tech(player, TARGETS[1].id)) ~= true then fail("could not queue first native fixed-provider research") end
  assert_queue(player, {current=TARGETS[1].id, queue={TARGETS[1].id}, progress=0}, "first native research")
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player then return end
  if (state.phase == "await-preferred-bioflux-lab" or state.phase == "await-provider-absent-bioflux-lab")
      and event.research.name == MIR_BIOFLUX then
    state.full_mir_actual_lab_completions = (state.full_mir_actual_lab_completions or 0) + 1
    state.phase = state.phase == "await-preferred-bioflux-lab"
      and "await-preferred-bioflux-restore" or "await-provider-absent-bioflux-restore"
    return
  end
  if (state.phase == "await-preferred-breeding-lab" or state.phase == "await-released-breeding-lab")
      and event.research.name == MIR_BREEDING then
    state.phase = state.phase == "await-preferred-breeding-lab"
      and "await-preferred-breeding-restore" or "await-released-breeding-restore"
    return
  end
  if state.phase ~= "await-lab" then return end
  local expected = TARGETS[state.actual_lab_completions + 1]
  if expected == nil or event.research.name ~= expected.id then return end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions == #TARGETS then state.phase = "await-freeze"
  else state.phase = "await-next" end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "source-completed" or state.phase == "prefer-mir-breeding-completed"
      or state.phase == "prefer-foreign-breeding-completed" or state.phase == "prefer-mir-again-completed"
      or state.phase == "providers-removed-bioflux-completed" or state.phase == "providers-readded-foreign-completed") then
    loaded_snapshot = {phase=state.phase, labs=state.actual_lab_completions, queue=copy_queue(state.player_queue)}
  else loaded_snapshot = nil end
  reload_logged, pending_save = false, false
end)

script.on_configuration_changed(function()
  -- Loading the predecessor runs on_load before this configuration change.
  -- That saved phase is an input witness, not a cold reload of the successor.
  loaded_snapshot, reload_logged = nil, false
  local state = storage[KEY]
  if script.active_mods["more-infinite-research"] == "5.0.20000" and script.active_mods[FIXTURE] == "0.2.0" then
    require_mode("5.0.20000", "0.2.0", true, "preferred successor")
    if type(state) ~= "table" or state.full_mir_bioflux_introduced ~= false
        or state.foreign_full_mir_bioflux_initialized ~= false then
      fail("preferred successor full MIR bioflux predecessor witness differs")
    end
    local foreign_full = tech(game.forces[state.foreign_force_index], MIR_BIOFLUX)
    if foreign_full.researched or foreign_full.level ~= 1 or foreign_full.enabled ~= true
        or foreign_full.visible_when_disabled ~= false then
      fail("preferred successor full MIR bioflux introduction differs")
    end
    foreign_full.enabled, foreign_full.visible_when_disabled = false, false
    state.full_mir_bioflux_introduced, state.foreign_full_mir_bioflux_initialized = true, true
    assert_preferred(state)
    local bioflux = tech(game.forces.player, MIR_BIOFLUX)
    prerequisites(bioflux)
    assert_full_bioflux(bioflux, 1, true, false, true, "preferred pre-lab")
    state.true_bioflux_before = selected_effects(game.forces.player, MIR_BIOFLUX_EFFECTS)
    state.phase = "await-preferred-bioflux-lab"
    state.deadline_tick = game.tick + DEADLINE
    prepend_research(state, MIR_BIOFLUX, "preferred fully covered bioflux")
  elseif script.active_mods["more-infinite-research"] == "5.0.20000" and script.active_mods[FIXTURE] == "0.3.0" then
    require_mode("5.0.20000", "0.3.0", false, "released successor")
    if type(state) ~= "table" or state.phase ~= "prefer-mir-breeding-completed" then fail("released successor source witness differs") end
    assert_breeding_earned_before_false(state)
    assert_released(state, selected_source_effects(state, state.true_bioflux_effects, state.true_breeding_effects))
    state.phase = "await-released-breeding-lab"
    state.deadline_tick = game.tick + DEADLINE
    prepend_research(state, MIR_BREEDING, "released")
  elseif script.active_mods["more-infinite-research"] == "5.0.20000" and script.active_mods[FIXTURE] == "0.4.0" then
    require_mode("5.0.20000", "0.4.0", true, "re-preferred successor")
    if type(state) ~= "table" or state.phase ~= "prefer-foreign-breeding-completed" then fail("re-preferred source witness differs") end
    assert_breeding_earned_after_false(state)
    state.phase = "prefer-mir-again-completed"
    pending_save = true
  elseif script.active_mods["more-infinite-research"] == "5.0.20000" and script.active_mods[FIXTURE] == "0.5.0" then
    require_mode("5.0.20000", "0.5.0", false, "provider-absent successor", false)
    if type(state) ~= "table" or state.phase ~= "prefer-mir-again-completed" then
      fail("provider-absent successor source witness differs")
    end
    assert_provider_absent_before_lab(state)
    local bioflux = tech(game.forces.player, MIR_BIOFLUX)
    prerequisites(bioflux)
    assert_full_bioflux(bioflux, 2, true, false, true, "provider removal pre-lab")
    state.provider_absent_bioflux_before = selected_effects(game.forces.player, MIR_BIOFLUX_EFFECTS)
    state.phase = "await-provider-absent-bioflux-lab"
    state.deadline_tick = game.tick + DEADLINE
    prepend_research(state, MIR_BIOFLUX, "provider removal fully covered bioflux")
  elseif script.active_mods["more-infinite-research"] == "5.0.20000" and script.active_mods[FIXTURE] == "0.6.0" then
    require_mode("5.0.20000", "0.6.0", false, "provider-readded foreign successor")
    if type(state) ~= "table" or state.phase ~= "providers-removed-bioflux-completed" then
      fail("provider-readded foreign source witness differs")
    end
    assert_readded_foreign(state)
    state.phase = "providers-readded-foreign-completed"
    pending_save = true
  end
end)

-- (Configuration stages above are intentionally ordered as true, false, true
-- again.  The first true stage performs the fully covered row before the
-- existing partial breeding row, so one shared queue carries both witnesses.)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if pending_save then
    if state.phase == "prefer-mir-again-completed" then assert_repreferred_breeding(state)
    elseif state.phase == "providers-readded-foreign-completed" then assert_readded_foreign(state)
    else fail("unexpected pending native save phase") end
    marker("initial", state)
    game.server_save(SAVE)
    pending_save = false
    return
  end
  if loaded_snapshot and not reload_logged then
    if loaded_snapshot.phase == "source-completed" then assert_source(state)
    elseif loaded_snapshot.phase == "prefer-mir-breeding-completed" then assert_true_breeding(state)
    elseif loaded_snapshot.phase == "prefer-foreign-breeding-completed" then assert_false_breeding(state)
    elseif loaded_snapshot.phase == "prefer-mir-again-completed" then assert_repreferred_breeding(state)
    elseif loaded_snapshot.phase == "providers-removed-bioflux-completed" then assert_provider_absent_completed(state)
    elseif loaded_snapshot.phase == "providers-readded-foreign-completed" then assert_readded_foreign(state)
    else fail("cold reload phase differs") end
    if loaded_snapshot.labs ~= state.actual_lab_completions then fail("cold reload changed native lab count") end
    assert_queue(game.forces.player, loaded_snapshot.queue, "cold reload player")
    marker("reload", state)
    reload_logged = true
    return
  end
  if state.phase == "source-completed" or state.phase == "prefer-mir-breeding-completed"
      or state.phase == "prefer-foreign-breeding-completed" or state.phase == "prefer-mir-again-completed"
      or state.phase == "providers-removed-bioflux-completed" or state.phase == "providers-readded-foreign-completed" then return end
  if game.tick > state.deadline_tick then fail("fixture did not complete its bounded native lab work") end
  local player = game.forces.player
  if state.phase == "await-next" then
    if player.current_research == nil and #(player.research_queue or {}) == 0 then
      local target = TARGETS[state.actual_lab_completions + 1]
      fill(state.lab, tech(player, target.id))
      if player.add_research(tech(player, target.id)) ~= true then fail("could not queue next native fixed-provider research") end
      state.phase = "await-lab"
    end
  elseif state.phase == "await-preferred-bioflux-restore" then
    if player.current_research and player.current_research.name == "electric-circuit-productivity" then
      -- The completed full row has returned the queued partial research.  Stop
      -- the lab before inspecting that hand-off, then refill it only for the
      -- following partial-coverage breeding lab.
      freeze(state)
      state.true_bioflux_effects = advanced_effects(state.true_bioflux_before, MIR_BIOFLUX_EFFECTS)
      assert_preferred(state, selected_source_effects(state, state.true_bioflux_effects))
      assert_full_bioflux(tech(player, MIR_BIOFLUX), 2, true, false, true, "preferred completed")
      assert_selected_effects(player, state.true_bioflux_effects, MIR_BIOFLUX_EFFECTS,
        "preferred completed bioflux")
      local breeding = tech(player, MIR_BREEDING)
      prerequisites(breeding)
      assert_breeding(breeding, 1, "preferred pre-lab", true)
      state.true_breeding_before = selected_effects(player, MIR_BREEDING_FULL)
      state.phase = "await-preferred-breeding-lab"
      prepend_research(state, MIR_BREEDING, "preferred partial breeding")
    end
  elseif state.phase == "await-preferred-breeding-restore" then
    if player.current_research and player.current_research.name == "electric-circuit-productivity" then
      freeze(state)
      state.true_breeding_effects = advanced_effects(state.true_breeding_before, MIR_BREEDING_FULL)
      state.phase = "prefer-mir-breeding-completed"
      assert_true_breeding(state)
      marker("initial", state)
      game.server_save(SAVE)
    end
  elseif state.phase == "await-released-breeding-restore" then
    if player.current_research and player.current_research.name == "electric-circuit-productivity" then
      freeze(state)
      state.false_breeding_effects = advanced_effects(state.true_breeding_effects, MIR_BREEDING_FALSE)
      state.phase = "prefer-foreign-breeding-completed"
      assert_false_breeding(state)
      marker("initial", state)
      game.server_save(SAVE)
    end
  elseif state.phase == "await-provider-absent-bioflux-restore" then
    if player.current_research and player.current_research.name == "electric-circuit-productivity" then
      freeze(state)
      state.provider_absent_bioflux_effects = advanced_effects(state.provider_absent_bioflux_before, MIR_BIOFLUX_EFFECTS)
      state.phase = "providers-removed-bioflux-completed"
      assert_provider_absent_completed(state)
      marker("initial", state)
      game.server_save(SAVE)
    end
  elseif state.phase == "await-freeze" then
    for _, target in ipairs(TARGETS) do
      assert_status(player, target.id, {level=target.first + 1, researched=false, enabled=true, visible=false,
        maximum=UINT32_MAX, saved_progress=0}, "native lab completion")
    end
    freeze(state)
    local queued, probe = tech(player, "electric-circuit-productivity"), tech(player, PROBE)
    queued.saved_progress, probe.saved_progress = 0.27, 0.42
    player.research_queue = {queued, probe}
    player.research_progress = 0.27
    state.player_queue = assert_queue(player, {current="electric-circuit-productivity", queue={"electric-circuit-productivity", PROBE}, progress=0.27}, "source seeded queue")
    state.probe_inactive_saved_progress = probe.saved_progress
    state.player_effects = expected_effects(state.player_start_effects)
    state.milestone = "four-native-fixed-provider-labs"
    state.phase = "source-completed"
    assert_source(state)
    marker("initial", state)
    game.server_save(SAVE)
  elseif state.phase == "await-lab" or state.phase == "await-preferred-bioflux-lab"
      or state.phase == "await-preferred-breeding-lab" or state.phase == "await-released-breeding-lab"
      or state.phase == "await-provider-absent-bioflux-lab" then
    state.lab.energy = 1000000000
  end
end)
