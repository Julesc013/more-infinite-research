-- Private F210 BobTech plus Angel Smelting laboratory witness. It seeds only
-- the fixed direct non-MIR prerequisites, earns eleven named MIR levels in a
-- real lab, and observes the saved state on two cold reloads. It never walks
-- a technology graph, assigns MIR research state or levels, or repairs state
-- from on_load.
local KEY = "mir5_bob_tech_gameplay"
local SAVE = "mir5-native-complete"
local INITIAL_PACKS = 32
local DEADLINE_TICKS = 72000
local LAB_ENERGY = 100000000
local UINT32_MAX = 4294967295
local EFFECT = .02
local loaded, reported = nil, false

local REQUIRED = {
  base="2.1.23", ["elevated-rails"]="2.1.23", quality="2.1.23", recycler="2.1.23", ["space-age"]="2.1.23",
  boblibrary="3.0.1", bobores="3.0.0", bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
  angelsrefining="2.1.2", angelsrefininggraphics="2.1.0", angelspetrochem="2.1.3",
  angelspetrochemgraphics="2.1.0", angelssmelting="2.1.1", angelssmeltinggraphics="2.1.1",
  ["mir-fixture-mir5-active-mods-observer"]="0.1.0", ["more-infinite-research"]="5.0.21000",
  ["mir-fixture-mir5-bob-tech-gameplay"]="0.1.0",
}
local FAMILIES = {
  {key="research_material_tin", early="recipe-prod-research_material_tin-1", tail=nil,
    recipes={"angels-plate-tin","angels-plate-tin-2"}},
  {key="research_material_gunmetal", early="recipe-prod-research_material_gunmetal-1",
    tail="recipe-prod-research_material_gunmetal-4", recipes={"angels-plate-gunmetal"}},
  {key="research_material_invar", early="recipe-prod-research_material_invar-1",
    tail="recipe-prod-research_material_invar-4", recipes={"angels-plate-invar"}},
}
local EXTERNAL_PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "space-science-pack",
  "angels-tin-smelting-1", "angels-tin-casting-2", "angels-gunmetal-smelting-1", "angels-invar-smelting-1",
}
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "space-science-pack"}
local CONSUMPTION = {["automation-science-pack"]=11, ["logistic-science-pack"]=8, ["space-science-pack"]=2}

local function fail(message) error("[mir5-bob-tech-gameplay] " .. message) end
local function near(actual, expected) return type(actual) == "number" and math.abs(actual - expected) <= .0000001 end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value or value.valid == false or value.name ~= name or not value.prototype then
    fail("named technology is absent: " .. tostring(name))
  end
  return value
end

local function check_closure()
  local count = 0
  for name, version in pairs(REQUIRED) do
    if script.active_mods[name] ~= version then fail("unexpected BobTech plus Angel closure member: " .. name) end
    count = count + 1
  end
  local actual_count = 0
  for _ in pairs(script.active_mods) do actual_count = actual_count + 1 end
  if actual_count ~= count then fail("unexpected F210 BobTech plus Angel closure") end
end

local function assert_effects(value, family)
  local effects = value.prototype.effects
  if type(effects) ~= "table" or #effects ~= #family.recipes then fail(value.name .. " native recipe effects changed") end
  for index, recipe in ipairs(family.recipes) do
    local effect = effects[index]
    if not effect or effect.type ~= "change-recipe-productivity" or effect.recipe ~= recipe
        or not near(effect.change, EFFECT) then
      fail(value.name .. " native recipe effect changed")
    end
  end
end

local function assert_stage(force, family, name, continuation)
  local value = technology(force, name)
  local maximum = continuation and UINT32_MAX or 3
  if value.prototype.max_level ~= maximum then fail(name .. " finite/continuation boundary changed") end
  assert_effects(value, family)
  if value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
    fail(name .. " fixture count or time differs")
  end
  return value
end

local function assert_initial(force)
  for _, family in ipairs(FAMILIES) do
    local early = assert_stage(force, family, family.early, false)
    if early.level ~= 1 or early.researched or early.enabled ~= true then
      fail(family.key .. " early stage did not begin at level one")
    end
    if family.tail then
      local tail = assert_stage(force, family, family.tail, true)
      if tail.level ~= 4 or tail.researched then fail(family.key .. " tail did not begin at level four") end
    end
  end
end

local function plan()
  local out = {}
  for _, family in ipairs(FAMILIES) do
    for _ = 1, 3 do out[#out+1] = family.early end
    if family.tail then out[#out+1] = family.tail end
  end
  return out
end

local function expected_bonus(family)
  return family.key == "research_material_tin" and .06 or .08
end

local function assert_bonus(force)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or recipe.valid == false or not near(recipe.productivity_bonus, expected_bonus(family)) then
        fail("native recipe productivity differs for " .. name)
      end
    end
  end
end

local function assert_consumption(state)
  if not state.lab or state.lab.valid == false then fail("real BobTech plus Angel lab is absent") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real BobTech plus Angel lab input is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.get_item_count(name) ~= INITIAL_PACKS - CONSUMPTION[name] then
      fail("real lab science consumption differs for " .. name)
    end
  end
end

local function assert_complete(state)
  local force = game.forces.player
  if state.finished ~= 11 or state.events ~= 11 or state.next ~= 12
      or force.current_research ~= nil or #(force.research_queue or {}) ~= 0 then
    fail("real lab did not complete all eleven selected research levels")
  end
  for _, family in ipairs(FAMILIES) do
    local early = assert_stage(force, family, family.early, false)
    if early.level ~= 3 or early.researched ~= true then fail(family.key .. " finite progression differs") end
    if family.tail then
      local tail = assert_stage(force, family, family.tail, true)
      if tail.level ~= 5 or tail.researched then fail(family.key .. " continuation progression differs") end
    end
  end
  assert_bonus(force)
  assert_consumption(state)
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="bob-tech-gameplay", stage=stage, status="passed",
    witnesses={
      profile="f210-bobtech-angel-smelting", selected_families=3, named_technologies=5,
      actual_lab_completions=state.finished, finite_levels_completed_by_lab=9,
      continuation_levels_completed_by_lab=2, science_consumed=CONSUMPTION,
      native_recipe_productivity={tin=.06,gunmetal=.08,invar=.08},
      native_effect_per_completed_level=EFFECT, fixture_accelerates_count_and_time=true,
      ordinary_tuning_qualified=false, source_shape_preflight_required=true,
      on_load_read_only=stage == "reload", foreign_force_witness_not_claimed=true,
    },
  }))
end

local function start_next(state)
  if state.next > #state.plan or game.forces.player.current_research ~= nil then return end
  if state.finished ~= state.next - 1 then fail("next research did not wait for preceding completion") end
  local value = technology(game.forces.player, state.plan[state.next])
  if value.enabled ~= true or game.forces.player.add_research(value) ~= true then
    fail("could not start real BobTech plus Angel research: " .. value.name)
  end
  state.next = state.next + 1
end

script.on_init(function()
  check_closure()
  if storage[KEY] ~= nil then fail("fresh BobTech plus Angel fixture found existing state") end
  local force = game.forces.player
  for _, name in ipairs(EXTERNAL_PREREQUISITES) do technology(force, name).researched = true end
  assert_initial(force)
  for _, family in ipairs(FAMILIES) do
    for _, name in ipairs(family.recipes) do
      local recipe = force.recipes[name]
      if not recipe or not near(recipe.productivity_bonus, 0) then fail("initial native recipe bonus differs") end
    end
  end
  local surface = game.surfaces[1]
  local lab = surface.create_entity{name="lab", position=force.get_spawn_position(surface), force=force}
  if not lab or lab.valid == false then fail("could not create real BobTech plus Angel lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real BobTech plus Angel lab input is absent") end
  for _, name in ipairs(SCIENCE) do
    if inventory.insert{name=name,count=INITIAL_PACKS} ~= INITIAL_PACKS then fail("lab rejected " .. name) end
  end
  lab.energy, game.speed = LAB_ENERGY, 16
  storage[KEY] = {phase="researching",plan=plan(),next=1,finished=0,events=0,lab=lab,deadline=game.tick+DEADLINE_TICKS}
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if not state or state.phase ~= "researching" or event.by_script ~= false
      or not event.research or event.research.force ~= game.forces.player then return end
  local expected = state.plan[state.finished + 1]
  if not expected or event.research.name ~= expected then fail("unexpected native material completion") end
  state.finished, state.events = state.finished + 1, state.events + 1
  if state.finished > #state.plan then fail("native completion exceeded bounded plan") end
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "complete" then loaded = {finished=state.finished,events=state.events,next=state.next} else loaded = nil end
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if not state then fail("BobTech plus Angel gameplay state is absent") end
  if state.phase == "complete" then
    if loaded and not reported then
      if loaded.finished ~= state.finished or loaded.events ~= state.events or loaded.next ~= state.next then
        fail("on_load changed the saved BobTech plus Angel witness")
      end
      assert_complete(state)
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real BobTech plus Angel labs exceeded deadline") end
  if not state.lab or state.lab.valid == false then fail("real BobTech plus Angel lab was removed") end
  state.lab.energy = LAB_ENERGY
  if state.finished == #state.plan then
    assert_complete(state)
    state.phase = "complete"
    marker("initial", state)
    game.server_save(SAVE)
    return
  end
  start_next(state)
end)
