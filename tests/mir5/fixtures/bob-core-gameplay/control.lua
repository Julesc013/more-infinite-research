-- Private F210 Bob-core laboratory witness. Every selected stage is earned in
-- a real lab: three finite levels and one continuation level per family. The
-- only seeded technologies are the named external prerequisites below; this
-- fixture never assigns levels, research state, productivity, queues, or a
-- foreign force state for a selected MIR material row.
local KEY = "mir5_bob_core_gameplay"
local SAVE = "mir5-native-complete"
local INITIAL_PACKS = 64
local DEADLINE_TICKS = 72000
local LAB_ENERGY = 100000000
local UINT32_MAX = 4294967295
local EFFECT = 0.02
local loaded, reported

local REQUIRED = {
  base="2.1.23", ["space-age"]="2.1.23", boblibrary="3.0.1", bobores="3.0.0",
  bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
}

local FAMILIES = {
  {key="research_material_tin", early="recipe-prod-research_material_tin-1", tail="recipe-prod-research_material_tin-4", recipes={"bob-tin-plate"}},
  {key="research_material_lead", early="recipe-prod-research_material_lead-1", tail="recipe-prod-research_material_lead-4", recipes={"bob-lead-plate"}},
  {key="research_material_bronze", early="recipe-prod-research_material_bronze-1", tail="recipe-prod-research_material_bronze-4", recipes={"bob-bronze-alloy"}},
  {key="research_material_gunmetal", early="recipe-prod-research_material_gunmetal-1", tail="recipe-prod-research_material_gunmetal-4", recipes={"bob-gunmetal-alloy"}},
  {key="research_material_invar", early="recipe-prod-research_material_invar-1", tail="recipe-prod-research_material_invar-4", recipes={"bob-invar-alloy"}},
  {key="research_material_nitinol", early="recipe-prod-research_material_nitinol-1", tail="recipe-prod-research_material_nitinol-4", recipes={"bob-nitinol-alloy"}},
  {key="research_material_copper_tungsten", early="recipe-prod-research_material_copper_tungsten-1", tail="recipe-prod-research_material_copper_tungsten-4", recipes={"bob-copper-tungsten-alloy"}},
}

-- These are the direct, independently captured non-MIR prerequisites. There
-- is no prerequisite walk, so the witness cannot silently earn a selected row.
local EXTERNAL_PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "space-science-pack", "metallurgic-science-pack",
  "bob-alloy-processing", "bob-zinc-processing", "bob-invar-processing",
  "bob-nitinol-processing", "bob-tungsten-processing",
}
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "space-science-pack", "metallurgic-science-pack",
}
local CONSUMPTION = {
  ["automation-science-pack"]=28, ["logistic-science-pack"]=20,
  ["chemical-science-pack"]=16, ["production-science-pack"]=8,
  ["space-science-pack"]=10, ["metallurgic-science-pack"]=4,
}

local function fail(message)
  error("[mir5-bob-core-gameplay] " .. message)
end

local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if not value or value.valid == false then fail("named technology is absent: " .. name) end
  return value
end

local function check_closure()
  for name, version in pairs(REQUIRED) do
    if script.active_mods[name] ~= version then fail("unexpected Bob-core closure member: " .. name) end
  end
  if script.active_mods["more-infinite-research"] ~= "5.0.21000"
      or script.active_mods["mir-fixture-mir5-bob-core-gameplay"] ~= "0.1.0"
      or script.active_mods.angelssmelting ~= nil or script.active_mods.angelsrefining ~= nil then
    fail("unexpected F210 Bob-core gameplay closure")
  end
end

local function assert_effects(value, family)
  local effects = value.prototype and value.prototype.effects
  if type(effects) ~= "table" or #effects ~= #family.recipes then
    fail(value.name .. " native recipe effects changed")
  end
  for index, recipe in ipairs(family.recipes) do
    local effect = effects[index]
    if not effect or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or not near(effect.change, EFFECT) then
      fail(value.name .. " native recipe effect changed")
    end
  end
end

local function assert_prototypes(force, family)
  local early, tail = technology(force, family.early), technology(force, family.tail)
  if not early.prototype or early.prototype.max_level ~= 3
      or not tail.prototype or tail.prototype.max_level ~= UINT32_MAX then
    fail(family.key .. " native finite/tail boundary changed")
  end
  assert_effects(early, family)
  assert_effects(tail, family)
  return early, tail
end

local function assert_acceleration(force)
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototypes(force, family)
    for _, value in ipairs({early, tail}) do
      if value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
        fail(value.name .. " fixture cost or time differs")
      end
    end
  end
end

local function assert_initial(force)
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototypes(force, family)
    if early.level ~= 1 or early.researched or early.enabled ~= true
        or tail.level ~= 4 or tail.researched then
      fail(family.key .. " did not begin at the native early-one/tail-four boundary")
    end
  end
end

local function plan()
  local out = {}
  for _, family in ipairs(FAMILIES) do
    out[#out + 1] = family.early
    out[#out + 1] = family.early
    out[#out + 1] = family.early
    out[#out + 1] = family.tail
  end
  return out
end

local function assert_bonus(force, expected)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not near(recipe.productivity_bonus, expected) then
        fail("native recipe productivity differs for " .. name)
      end
    end
  end
end

local function assert_consumption(state)
  local lab = state.lab
  if not lab or lab.valid == false then fail("real Bob-core lab is absent") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real Bob-core lab input inventory is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.get_item_count(name) ~= INITIAL_PACKS - CONSUMPTION[name] then
      fail("real lab science consumption differs for " .. name)
    end
  end
end

local function assert_complete(state)
  local force = game.forces.player
  if state.finished ~= #state.plan or state.events ~= #state.plan or state.next ~= #state.plan + 1
      or force.current_research ~= nil or #(force.research_queue or {}) ~= 0 then
    fail("real lab did not complete all twenty-eight selected research levels")
  end
  for _, family in ipairs(FAMILIES) do
    local early, tail = assert_prototypes(force, family)
    if early.level ~= 3 or early.researched ~= true or tail.level ~= 5 or tail.researched ~= false then
      fail("real lab did not retain the earned finite-three/tail-four boundary for " .. family.key)
    end
  end
  assert_bonus(force, 0.08)
  assert_consumption(state)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="bob-core-gameplay", stage=stage, status="passed",
    witnesses={
      profile="f210-bob-core-no-angel", selected_families=7,
      named_technologies=14, actual_lab_completions=state.finished,
      finite_levels_completed_by_lab=21, continuation_levels_completed_by_lab=7,
      science_consumed=CONSUMPTION, native_recipe_productivity_per_route=0.08,
      native_effect_per_completed_level=EFFECT, fixture_accelerates_count_and_time=true,
      ordinary_tuning_qualified=false, candidate_full_catalogue_comparison_required=true,
      on_load_read_only=stage == "reload", foreign_force_witness_not_claimed=true,
    },
  }))
end

local function start_next_research(state)
  if state.next > #state.plan then return end
  local force = game.forces.player
  if force.current_research ~= nil then return end
  if state.finished ~= state.next - 1 then fail("next research did not wait for the preceding completion") end
  local value = technology(force, state.plan[state.next])
  if value.enabled ~= true then fail("next native material research is not enabled: " .. value.name) end
  if force.add_research(value) ~= true then fail("could not start real material research: " .. value.name) end
  state.next = state.next + 1
end

script.on_init(function()
  check_closure()
  if storage[KEY] ~= nil then fail("fresh gameplay fixture found existing state") end
  local force = game.forces.player
  for _, name in ipairs(EXTERNAL_PREREQUISITES) do technology(force, name).researched = true end
  assert_initial(force)
  assert_acceleration(force)
  assert_bonus(force, 0)

  local surface = game.surfaces[1]
  local lab = surface.create_entity{name="lab", position=force.get_spawn_position(surface), force=force}
  if not lab or lab.valid == false then fail("could not create real Bob-core lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real Bob-core lab input inventory is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name=name, count=INITIAL_PACKS} ~= INITIAL_PACKS then
      fail("real Bob-core lab rejected " .. name)
    end
  end
  lab.energy = LAB_ENERGY
  game.speed = 16
  storage[KEY] = {
    phase="researching", plan=plan(), next=1, finished=0, events=0,
    lab=lab, deadline=game.tick + DEADLINE_TICKS,
  }
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or not event.research
      or event.research.force ~= game.forces.player then return end
  local expected = state.plan[state.finished + 1]
  if not expected or event.research.name ~= expected then fail("unexpected native material completion") end
  state.finished, state.events = state.finished + 1, state.events + 1
  if state.finished > #state.plan then fail("native material completion exceeded the plan") end
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "complete" then
    -- Saved state is only observed after cold load; nothing is repaired here.
    loaded = {finished=state.finished, events=state.events, next=state.next}
  else
    loaded = nil
  end
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("gameplay fixture state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      if loaded.finished ~= state.finished or loaded.events ~= state.events or loaded.next ~= state.next then
        fail("on_load changed the saved Bob-core witness")
      end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real Bob-core labs exceeded deadline") end
  if not state.lab or state.lab.valid == false then fail("real Bob-core lab was removed") end
  state.lab.energy = LAB_ENERGY
  if state.finished == #state.plan then
    assert_complete(state)
    state.phase = "complete"
    marker("initial", state)
    game.server_save(SAVE)
    return
  end
  start_next_research(state)
end)
