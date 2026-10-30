-- One F200 Defaults-mode combined Space Age/BobTech steel witness.  The
-- fixture owns only its disposable world state.  It never writes an MIR
-- technology, a force recipe enablement, or a recipe prototype.
local KEY = "mir5_bob_angel_f200_combined_gameplay"
local SAVE = "mir5-native-complete"
local CASE = "bob-angel-f200-combined-gameplay"
local MIR = "more-infinite-research"
local FIXTURE = "mir-fixture-mir5-bob-angel-f200-combined-gameplay"
local TARGET = "recipe-prod-research_steel-1"
local ROUTE = "angels-plate-steel-2"
local OWNER = "angels-steel-smelting-2"
local ROLL = "angels-roll-steel"
local PLATE = "steel-plate"
local LAB_COUNT = 100
local BATCH = 100
local PLATES_PER_CRAFT = 4
local NATIVE_BONUS = .1
local EXPECTED_OUTPUT = 440
local RESEARCH_UNITS = 8000
local RESEARCH_UNIT_TIME_SECONDS = 60
local RESEARCH_UNIT_ENERGY = RESEARCH_UNIT_TIME_SECONDS * 60
local SCIENCE_PER_LAB = 40
local EXPECTED_SCIENCE_CONSUMPTION = 4000
local DEADLINE = 288000
local ENERGY = 1000000000
local UINT32_MAX = 4294967295
local loaded, reported, marker = nil, false, nil

local REQUIRED = {
  base="2.0.77", ["elevated-rails"]="2.0.77", quality="2.0.77", ["space-age"]="2.0.77",
  ["angelsaddons-mobility"]="2.0.1", ["angelsaddons-mobility-graphics-crawler"]="2.0.0",
  ["angelsaddons-mobility-graphics-petro"]="2.0.0", ["angelsaddons-mobility-graphics-smelting"]="2.0.0",
  ["angelsaddons-storage"]="2.0.1", angelsbioprocessing="2.0.3", angelsbioprocessinggraphics="2.0.0",
  angelsinfiniteores="2.0.3", angelspetrochem="2.0.3", angelspetrochemgraphics="2.0.1",
  angelsrefining="2.0.4", angelsrefininggraphics="2.0.0", angelssmelting="2.0.5",
  angelssmeltinggraphics="2.0.0", bobassembly="2.1.0", bobelectronics="2.1.1", bobenemies="2.1.0",
  bobequipment="2.1.0", bobgreenhouse="2.1.0", bobinserters="2.0.3", boblibrary="2.1.0",
  boblogistics="2.1.1", bobmining="2.1.0", bobmodules="2.1.0", bobores="2.1.2", bobplates="2.1.1",
  bobpower="2.1.0", bobrevamp="2.1.1", bobtech="2.1.0", bobvehicleequipment="2.1.1",
  bobwarfare="2.1.0", ["mir-fixture-mir5-active-mods-observer"]="0.1.0",
  [MIR]="5.0.20000", [FIXTURE]="0.1.0",
}
local SCIENCE = {"automation-science-pack", "logistic-science-pack"}
local UPSTREAM = {"automation-science-pack", "logistic-science-pack", OWNER}
local loaded_marker = false

local function fail(message) error("[mir5-bob-angel-f200-combined-gameplay] " .. message) end
local function close(left, right) return type(left) == "number" and math.abs(left-right) <= .0000001 end

local function exact_names(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do
    if actual[index] ~= name then fail(label .. " differs at " .. tostring(index)) end
  end
end

local function entry_name(value) return type(value) == "table" and (value.name or value[1]) or nil end
local function entry_amount(value) return type(value) == "table" and (value.amount or value[2]) or nil end

local function zero_optional(value)
  return value == nil or (type(value) == "number" and value == 0)
end
local function exact_rows(actual, expected, label, kind)
  kind = kind or "ingredient"
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, wanted in ipairs(expected) do
    local got = actual[index]
    if type(got) ~= "table" then fail(label .. " differs at " .. tostring(index)) end
    local type_ok = got.type == wanted.type or (kind == "research" and got.type == nil and wanted.type == "item")
    local probability_ok = (kind == "product" and got.probability == 1) or (kind ~= "product" and got.probability == nil)
    local defaults_ok
    if kind == "product" then
      defaults_ok = zero_optional(got.extra_count_fraction) and zero_optional(got.ignored_by_productivity)
        and zero_optional(got.ignored_by_stats) and zero_optional(got.percent_spoiled)
    elseif kind == "ingredient" then
      defaults_ok = zero_optional(got.ignored_by_stats) and got.extra_count_fraction == nil
        and got.ignored_by_productivity == nil and got.percent_spoiled == nil
    else
      defaults_ok = got.ignored_by_stats == nil and got.extra_count_fraction == nil
        and got.ignored_by_productivity == nil and got.percent_spoiled == nil
    end
    if entry_name(got) ~= wanted.name or entry_amount(got) ~= wanted.amount or not type_ok
        or not probability_ok or not defaults_ok or got.amount_min ~= nil or got.amount_max ~= nil
        or got.independent_probability ~= nil then
      fail(label .. " differs at " .. tostring(index))
    end
  end
end

local function check_closure()
  local count = 0
  for name, version in pairs(script.active_mods) do
    if REQUIRED[name] ~= version then fail("unexpected closure member: " .. tostring(name)) end
    count = count + 1
  end
  for name, version in pairs(REQUIRED) do
    if script.active_mods[name] ~= version then fail("closure member differs: " .. name) end
  end
  if count ~= 38 then fail("combined closure count differs") end
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. name) end
  return value
end

local function exact_prerequisites(value)
  local seen, count = {}, 0
  for _, prerequisite in pairs(value.prerequisites or {}) do
    if prerequisite == nil or type(prerequisite.name) ~= "string" or seen[prerequisite.name] then
      fail("steel prerequisite shape differs")
    end
    seen[prerequisite.name], count = true, count + 1
  end
  if count ~= 2 or not seen[SCIENCE[1]] or not seen[SCIENCE[2]] then fail("steel prerequisites differ") end
end

local function exact_effects(value)
  local effects, found, count = value.prototype and value.prototype.effects, {}, 0
  for _, effect in pairs(effects or {}) do
    if effect.type ~= "change-recipe-productivity" or (effect.recipe ~= "angels-plate-steel" and effect.recipe ~= ROUTE)
        or not close(effect.change, NATIVE_BONUS) or found[effect.recipe] then
      fail("steel productivity effects differ")
    end
    found[effect.recipe], count = true, count + 1
  end
  if count ~= 2 or not found["angels-plate-steel"] or not found[ROUTE] then fail("steel productivity effects differ") end
end

local function has_lab_input(inputs, name)
  local found = false
  for _, value in pairs(inputs or {}) do
    if type(value) ~= "string" then fail("native lab input type differs") end
    if value == name then found = true end
  end
  return found
end

local function scalar(value)
  local kind = type(value)
  if kind == "boolean" or kind == "number" or kind == "string" then return kind .. ":" .. tostring(value) end
  return kind
end

local function expected_research_unit_count(level)
  if level == 1 then return RESEARCH_UNITS end
  if level == 2 then return RESEARCH_UNITS * 2 end
  return nil
end

local function target_row_observation(value)
  local prototype = value.prototype
  local function field(name)
    local ok, result = pcall(function() return prototype[name] end)
    return name .. "=" .. (ok and scalar(result) or "<getter-error>")
  end
  return table.concat({
    "prototype_type=" .. type(prototype), field("max_level"), field("level"), field("upgrade"), field("order"),
    "current_level=" .. scalar(value.level), "current_research_unit_count=" .. scalar(value.research_unit_count),
    "current_research_unit_energy=" .. scalar(value.research_unit_energy),
  }, ";")
end

local function target(force)
  local value = technology(force, TARGET)
  local prototype = value.prototype
  local expected_count = expected_research_unit_count(value.level)
  if prototype == nil or prototype.max_level ~= UINT32_MAX or prototype.level ~= 1 or prototype.upgrade ~= true
      or prototype.order ~= "p[research_steel]" or expected_count == nil or value.research_unit_count ~= expected_count
      or not close(value.research_unit_energy, RESEARCH_UNIT_ENERGY) then
    fail("complete steel technology row differs: " .. target_row_observation(value))
  end
  exact_prerequisites(value)
  exact_rows(value.research_unit_ingredients, {
    {type="item", name=SCIENCE[1], amount=1}, {type="item", name=SCIENCE[2], amount=1},
  }, "steel research science", "research")
  exact_effects(value)
  return value
end

local function route(force, expected_bonus)
  local prototype = prototypes.recipe[ROUTE]
  if prototype == nil or prototype.name ~= ROUTE or not close(prototype.energy, .5)
      or prototype.category ~= "advanced-crafting" then
    fail("steel physical route identity differs")
  end
  exact_names(prototype.additional_categories, {}, "steel physical additional category")
  exact_rows(prototype.ingredients, {{type="item", name=ROLL, amount=1}}, "steel physical input")
  exact_rows(prototype.products, {{type="item", name=PLATE, amount=4}}, "steel physical output", "product")
  local value = force.recipes[ROUTE]
  if value == nil or value.valid == false or value.enabled ~= true
      or not close(value.productivity_bonus, expected_bonus) then
    fail("steel force route differs")
  end
  return value
end

local function assert_upstream(force)
  for _, name in ipairs(UPSTREAM) do
    local value = technology(force, name)
    if value.researched ~= true then fail("named upstream prerequisite was not retained: " .. name) end
  end
  route(force, 0)
end

local function assert_fresh_upstream(force)
  for _, name in ipairs(UPSTREAM) do
    if technology(force, name).researched ~= false then fail("named upstream prerequisite was pre-researched: " .. name) end
  end
  local value = force.recipes[ROUTE]
  if value == nil or value.valid == false or value.enabled ~= false then fail("fresh steel route differs") end
end

local function lab_inventory(value)
  local inventory = value and value.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("native biolab input is absent") end
  return inventory
end

local function create_labs(force)
  local surface = game.surfaces[1]
  if surface == nil or type(surface.get_property) ~= "function" or not close(surface.get_property("pressure"), 1000) then
    fail("native biolab pressure surface differs")
  end
  local labs = {}
  for index=1,LAB_COUNT do
    local value = surface.create_entity{name="biolab", position={((index-1)%10)*7, math.floor((index-1)/10)*7}, force=force}
    local conditions = value and value.prototype and value.prototype.surface_conditions
    if value == nil or value.valid == false or value.prototype == nil or value.prototype.name ~= "biolab"
        or value.quality == nil or value.quality.name ~= "normal"
        or type(value.prototype.get_researching_speed) ~= "function"
        or not close(value.prototype.get_researching_speed(value.quality.name), 2)
        or value.prototype.science_pack_drain_rate_percent ~= 50
        or value.prototype.module_inventory_size ~= 4 or value.prototype.allowed_module_categories == nil
        or value.prototype.allowed_module_categories["quality"] ~= true
        or type(conditions) ~= "table" or #conditions ~= 1 or conditions[1].property ~= "pressure"
        or conditions[1].min ~= 1000 or conditions[1].max ~= 1000
        or not has_lab_input(value.prototype.lab_inputs, SCIENCE[1])
        or not has_lab_input(value.prototype.lab_inputs, SCIENCE[2]) then
      fail("native biolab differs")
    end
    local modules = value.get_inventory(defines.inventory.lab_modules)
    if modules ~= nil and not modules.is_empty() then fail("native biolab unexpectedly has modules") end
    local inventory = lab_inventory(value)
    for _, name in ipairs(SCIENCE) do
      if inventory.insert{name=name,count=SCIENCE_PER_LAB} ~= SCIENCE_PER_LAB then
        fail("native biolab rejected science: " .. name)
      end
    end
    value.energy = ENERGY
    labs[index] = value
  end
  return labs
end

local function science_remaining(state, name)
  local total = 0
  for _, value in ipairs(state.labs) do total = total + lab_inventory(value).get_item_count(name) end
  return total
end

local function assert_science_consumption(state)
  for _, name in ipairs(SCIENCE) do
    local remaining = science_remaining(state, name)
    if remaining ~= 0 or LAB_COUNT * SCIENCE_PER_LAB - remaining ~= EXPECTED_SCIENCE_CONSUMPTION then
      fail("native biolab science consumption differs: " .. name)
    end
  end
end

local function freeze_labs(state)
  for _, value in ipairs(state.labs) do
    if value == nil or value.valid == false then fail("native biolab disappeared") end
    value.energy = 0
  end
end

local function assert_labs_frozen(state)
  for _, value in ipairs(state.labs) do
    if value == nil or value.valid == false or value.energy ~= 0 then fail("native biolab final state differs") end
  end
end

local function queue(force, value)
  if force.current_research ~= nil or force.add_research(value) ~= true or force.current_research ~= value then
    fail("could not queue real steel research")
  end
  local count = 0
  for _, queued in pairs(force.research_queue or {}) do
    if queued ~= value then fail("steel research queue differs") end
    count = count + 1
  end
  if count ~= 1 then fail("steel research queue differs") end
end

local function assert_research_complete(state)
  local force, value = game.forces.player, target(game.forces.player)
  if state.actual_labs ~= 1 or value.level ~= 2 or value.researched ~= false
      or force.current_research ~= nil or #(force.research_queue or {}) ~= 0 then
    fail("native steel infinite research did not advance once")
  end
  route(force, NATIVE_BONUS)
  assert_science_consumption(state)
  freeze_labs(state)
end

local function setup_physical(state)
  local force, surface = game.forces.player, game.surfaces[1]
  local machine = surface.create_entity{name="assembling-machine-1", position={0, 84}, force=force}
  if machine == nil or machine.valid == false or machine.prototype == nil or machine.prototype.name ~= "assembling-machine-1"
      or machine.quality == nil or machine.quality.name ~= "normal"
      or type(machine.prototype.get_crafting_speed) ~= "function"
      or not close(machine.prototype.get_crafting_speed(machine.quality.name), .5)
      or machine.prototype.crafting_categories["advanced-crafting"] ~= true then
    fail("unchanged assembling-machine-1 differs")
  end
  local modules = machine.get_inventory(defines.inventory.crafter_modules)
  if modules ~= nil and not modules.is_empty() then fail("unchanged assembling-machine-1 has modules") end
  local input, output = machine.get_inventory(defines.inventory.crafter_input), machine.get_inventory(defines.inventory.crafter_output)
  if input == nil or output == nil or not input.is_empty() or not output.is_empty() or machine.crafting_progress ~= 0
      or not close(machine.bonus_progress, 0) then
    fail("unchanged assembling-machine-1 initial state differs")
  end
  machine.set_recipe(ROUTE)
  local selected = machine.get_recipe()
  if selected == nil or selected.name ~= ROUTE then fail("could not select real steel route") end
  if input.insert{name=ROLL,count=BATCH} ~= BATCH then fail("real steel machine rejected roll batch") end
  state.machine, state.phase, state.physical_output = machine, "physical", 0
end

local function tick_physical(state)
  local machine = state.machine
  if machine == nil or machine.valid == false then fail("real steel machine disappeared") end
  route(game.forces.player, NATIVE_BONUS)
  local input, output = machine.get_inventory(defines.inventory.crafter_input), machine.get_inventory(defines.inventory.crafter_output)
  if input == nil or output == nil then fail("real steel machine inventories disappeared") end
  machine.energy = ENERGY
  local made = output.get_item_count(PLATE)
  if made > 0 then
    if output.remove{name=PLATE,count=made} ~= made then fail("could not drain real steel output") end
    state.physical_output = state.physical_output + made
  end
  if input.get_item_count(ROLL) ~= 0 or machine.crafting_progress ~= 0 then return end
  if state.physical_output ~= EXPECTED_OUTPUT or not close(machine.bonus_progress, 0)
      or not close(machine.productivity_bonus, NATIVE_BONUS) or not output.is_empty() then
    fail("real steel physical output or native bonus differs")
  end
  state.phase = "complete"
  state.saved_actual_labs = state.actual_labs
  state.saved_physical_output = state.physical_output
  state.saved_target_level = target(game.forces.player).level
  marker("initial", state)
  game.server_save(SAVE)
end

local function assert_complete(state)
  assert_research_complete(state)
  assert_labs_frozen(state)
  if state.phase ~= "complete" or state.physical_output ~= EXPECTED_OUTPUT or state.machine == nil
      or state.machine.valid == false then
    fail("completed steel witness differs")
  end
  local input, output = state.machine.get_inventory(defines.inventory.crafter_input), state.machine.get_inventory(defines.inventory.crafter_output)
  if input == nil or output == nil or not input.is_empty() or not output.is_empty()
      or state.machine.crafting_progress ~= 0 or not close(state.machine.bonus_progress, 0) then
    fail("completed steel physical state differs")
  end
  route(game.forces.player, NATIVE_BONUS)
end

marker = function(stage, state)
  local value = target(game.forces.player)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={
      profile="f200-space-age-bobtech-combined-defaults", target=TARGET,
      actual_native_lab_completions=state.actual_labs, level_before=1, level_after=value.level,
      biolab_count=LAB_COUNT, biolab_science_pack_drain_rate_percent=50,
      science_consumed={ [SCIENCE[1]]=EXPECTED_SCIENCE_CONSUMPTION, [SCIENCE[2]]=EXPECTED_SCIENCE_CONSUMPTION },
      physical_recipe=ROUTE, physical_roll_batch=BATCH, physical_steel_plate_output=state.physical_output,
      native_recipe_productivity=NATIVE_BONUS, native_bonus_progress=state.machine.bonus_progress,
      on_load_read_only=stage == "reload", library_stage="pending-fresh-en-de-library-observations",
      library_input_simulation=false,
    },
  }))
end

remote.add_interface("mir5-bob-angel-f200-combined-gameplay", {
  report=function()
    local state = storage[KEY]
    return {
      kind="MIR5BobAngelF200CombinedGameplayReportV1", case=CASE,
      phase=state and state.phase or "absent", saved=state and state.phase == "complete" or false,
      library_stage={status="pending-fresh-en-de-library-observations", method="public-owned-library-window-actor",
        required_roles={"MIR5English", "MIR5Deutsch"}, fresh_screenshots=true, fresh_query=true,
        role_and_native_state_readback=true, input_simulation=false, base_or_space_age_claim=false},
    }
  end,
})

script.on_init(function()
  check_closure()
  if storage[KEY] ~= nil then fail("fixture state already exists") end
  local force, value = game.forces.player, target(game.forces.player)
  if value.level ~= 1 or value.researched ~= false or value.enabled ~= true then fail("fresh steel technology state differs") end
  assert_fresh_upstream(force)
  for _, name in ipairs(UPSTREAM) do technology(force, name).researched = true end
  assert_upstream(force)
  local state = {phase="researching", actual_labs=0, labs=create_labs(force), deadline=game.tick+DEADLINE}
  storage[KEY] = state
  game.speed = 16
  queue(force, value)
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "researching" or event.by_script ~= false
      or event.research == nil or event.research.force ~= game.forces.player or event.research.name ~= TARGET then
    return
  end
  state.actual_labs = state.actual_labs + 1
  if state.actual_labs ~= 1 then fail("steel fixture received duplicate native completion") end
  state.phase = "research-observed"
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "complete" then
    if type(state.saved_actual_labs) ~= "number" or type(state.saved_physical_output) ~= "number"
        or type(state.saved_target_level) ~= "number" then
      fail("cold reload storage witness differs")
    end
    loaded = {actual_labs=state.saved_actual_labs, output=state.saved_physical_output, level=state.saved_target_level}
  else
    loaded = nil
  end
  reported, loaded_marker = false, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("steel fixture state is absent") end
  if state.phase == "complete" then
    if loaded ~= nil and not reported then
      if loaded.actual_labs ~= state.actual_labs or loaded.output ~= state.physical_output
          or loaded.level ~= state.saved_target_level then
        fail("cold reload changed steel witness")
      end
      assert_complete(state)
      if target(game.forces.player).level ~= loaded.level then fail("cold reload native steel level differs") end
      marker("reload", state)
      reported = true
    end
    return
  end
  if game.tick > state.deadline then fail("real steel research or physical route exceeded fixture deadline") end
  if state.phase == "researching" then
    for _, value in ipairs(state.labs) do
      if value == nil or value.valid == false then fail("native biolab disappeared") end
      value.energy = ENERGY
    end
  elseif state.phase == "research-observed" then
    assert_research_complete(state)
    setup_physical(state)
  elseif state.phase == "physical" then
    tick_physical(state)
  else
    fail("steel fixture phase differs")
  end
end)
