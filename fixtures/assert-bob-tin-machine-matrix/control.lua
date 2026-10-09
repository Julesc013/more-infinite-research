local technology_name = "recipe-prod-research_material_tin-1"
local recipe_name = "bob-tin-plate"
local raw_direct_cap = 2
local imported_cap = 3
local input_ore = 100
local expected_outputs = {[0] = 100, [1] = 102, [2] = 104, [3] = 106}
local expected_machines = {
  {name = "bob-electric-mixing-furnace", entity_type = "assembling-machine", place_item = "bob-electric-mixing-furnace", energy_type = "electric", crafting_categories = {"bob-mixing-furnace", "smelting"}},
  {name = "bob-steel-mixing-furnace", entity_type = "assembling-machine", place_item = "bob-steel-mixing-furnace", energy_type = "burner", crafting_categories = {"bob-mixing-furnace", "smelting"}},
  {name = "bob-stone-mixing-furnace", entity_type = "assembling-machine", place_item = "bob-stone-mixing-furnace", energy_type = "burner", crafting_categories = {"bob-mixing-furnace", "smelting"}},
  {name = "electric-furnace", entity_type = "furnace", place_item = "electric-furnace", energy_type = "electric", crafting_categories = {"smelting"}},
  {name = "steel-furnace", entity_type = "furnace", place_item = "steel-furnace", energy_type = "burner", crafting_categories = {"smelting"}},
  {name = "stone-furnace", entity_type = "furnace", place_item = "stone-furnace", energy_type = "burner", crafting_categories = {"smelting"}},
}
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local function fail(message) error("[mir-bob-tin-machine-matrix] " .. message) end
local function assert_exact(actual, expected, message) if actual ~= expected then fail(message .. ": observed " .. tostring(actual) .. " expected " .. tostring(expected)) end end
local function sorted_copy(values) local copy = {}; for _, value in ipairs(values or {}) do copy[#copy + 1] = value end; table.sort(copy); return copy end
local function equal_list(actual, expected) actual = sorted_copy(actual); expected = sorted_copy(expected); if #actual ~= #expected then return false end; for index, value in ipairs(actual) do if value ~= expected[index] then return false end end; return true end
local function json_string(value) return '"' .. value .. '"' end
local function json_categories(values) local output = {}; for _, value in ipairs(values) do output[#output + 1] = json_string(value) end; return "[" .. table.concat(output, ",") .. "]" end
local function json_levels(levels) local output = {}; for _, level in ipairs(levels) do output[#output + 1] = '{"completed_level":' .. level.completed_level .. ',"input_ore":' .. level.input_ore .. ',"input_exhausted":' .. tostring(level.input_exhausted) .. ',"output":' .. level.output .. ',"bonus":' .. level.bonus .. ',"output_drain_observed":' .. tostring(level.output_drain_observed) .. '}' end; return "[" .. table.concat(output, ",") .. "]" end
local function json_machine(machine) return '{"name":' .. json_string(machine.name) .. ',"entity_type":' .. json_string(machine.entity_type) .. ',"place_item":' .. json_string(machine.place_item) .. ',"energy_type":' .. json_string(machine.energy_type) .. ',"crafting_categories":' .. json_categories(machine.crafting_categories) .. ',"levels":' .. json_levels(machine.levels) .. '}' end
local function json_machines(machines) local output = {}; for _, machine in ipairs(machines) do output[#output + 1] = json_machine(machine) end; return "[" .. table.concat(output, ",") .. "]" end

local function assert_cap_transport()
  local profile = settings.startup["mir-settings-profile-import"]
  local direct = settings.startup["ips-max-level-research_material_tin"]
  if not profile or type(profile.value) ~= "string" or not direct then fail("startup cap settings absent") end
  assert_exact(direct.value, raw_direct_cap, "raw direct cap")
  local decoded, decode_error = profile_codec.decode(profile.value)
  if not decoded or not decoded.settings then fail("MIRSET1 profile decode failed: " .. tostring(decode_error)) end
  assert_exact(decoded.settings["ips-max-level-research_material_tin"], imported_cap, "MIRSET1 imported cap")
  local raw = startup_settings.raw("ips-max-level-research_material_tin")
  local effective = startup_settings.get("ips-max-level-research_material_tin")
  assert_exact(raw, raw_direct_cap, "startup raw resolver cap")
  assert_exact(effective, imported_cap, "startup effective resolver cap")
  return {raw_direct = raw, mirset1_imported = decoded.settings["ips-max-level-research_material_tin"], effective = effective}
end

local function prepare_technology(force, completed_level)
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology then fail("Tin technology is absent") end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for level = 1, completed_level do
    if technology.level ~= level or not force.add_research(technology) or not force.current_research or force.current_research.name ~= technology_name then fail("could not offer exact Tin level " .. level) end
    force.research_queue = nil
    force.cancel_current_research()
    technology.researched = true
  end
  assert_exact(technology.level, completed_level + 1, "completed Tin level")
  return technology
end

local function assert_no_level_four()
  local force = game.create_force("mir-bob-tin-machine-matrix-cap")
  local technology = prepare_technology(force, imported_cap)
  local accepted = force.add_research(technology)
  local no_level_four = not technology.researched and not technology.enabled and not accepted
  if not no_level_four then fail("effective Tin cap admitted level four") end
  return no_level_four
end

local function assert_machine_shape(entity, expected)
  assert_exact(entity.type, expected.entity_type, "runtime entity type " .. expected.name)
  local runtime_categories = {}
  for key, value in pairs(entity.prototype.crafting_categories or {}) do
    if type(key) == "string" then runtime_categories[#runtime_categories + 1] = key
    elseif type(value) == "string" then runtime_categories[#runtime_categories + 1] = value
    end
  end
  for _, expected_category in ipairs(expected.crafting_categories) do
    local found = false
    for _, runtime_category in ipairs(runtime_categories) do if runtime_category == expected_category then found = true end end
    if not found then fail("runtime crafting categories omit " .. expected_category .. " for " .. expected.name .. ": " .. table.concat(sorted_copy(runtime_categories), ",")) end
  end
end

local function create_case(machine_spec, completed_level, position_index)
  local force = game.create_force("mir-bob-tin-machine-matrix-" .. machine_spec.name .. "-" .. completed_level)
  local technology = prepare_technology(force, completed_level)
  local entity = game.surfaces[1].create_entity{name = machine_spec.name, position = {position_index * 4, completed_level * 5}, force = force}
  if not entity then fail("could not create machine " .. machine_spec.name) end
  assert_machine_shape(entity, machine_spec)
  if entity.type == "assembling-machine" and not entity.set_recipe(recipe_name) then fail("machine cannot set exact Tin recipe " .. machine_spec.name) end
  local input = entity.get_inventory(defines.inventory.crafter_input)
  local output = entity.get_inventory(defines.inventory.crafter_output)
  if not input or not output then fail("crafting inventories absent for " .. machine_spec.name) end
  local inserted_input = input.insert{name = "bob-tin-ore", count = input_ore}
  assert_exact(inserted_input, input_ore, "exact Tin ore input " .. machine_spec.name)
  if machine_spec.energy_type == "burner" then
    local fuel = entity.get_inventory(defines.inventory.fuel)
    if not fuel or fuel.insert{name = "solid-fuel", count = 50} ~= 50 then fail("burner fuel setup differs for " .. machine_spec.name) end
  elseif machine_spec.energy_type == "electric" then
    local ok = pcall(function() entity.energy = 1000000000 end)
    if not ok or not entity.energy or entity.energy <= 0 then fail("electric buffer setup differs for " .. machine_spec.name) end
  else
    fail("unsupported runtime energy type " .. tostring(machine_spec.energy_type))
  end
  return {machine_spec = machine_spec, completed_level = completed_level, entity = entity, input_inserted = inserted_input, drained = 0, drain_events = 0, input_exhausted = false, done = false}
end

local function maintain_and_drain(case)
  if case.machine_spec.energy_type == "electric" then
    local ok = pcall(function() case.entity.energy = 1000000000 end)
    if not ok or not case.entity.energy or case.entity.energy <= 0 then fail("electric buffer differs during runtime for " .. case.machine_spec.name) end
  end
  local input = case.entity.get_inventory(defines.inventory.crafter_input)
  local output = case.entity.get_inventory(defines.inventory.crafter_output)
  if not input or not output then fail("crafting inventories disappeared for " .. case.machine_spec.name) end
  local available = output.get_item_count("bob-tin-plate")
  if available > 0 then
    local removed = output.remove{name = "bob-tin-plate", count = available}
    assert_exact(removed, available, "output drain " .. case.machine_spec.name)
    case.drained = case.drained + removed
    case.drain_events = case.drain_events + 1
  end
  if input.get_item_count("bob-tin-ore") == 0 then case.input_exhausted = true end
  if case.input_exhausted and case.entity.crafting_progress == 0 and output.get_item_count("bob-tin-plate") == 0 then
    assert_exact(case.drained, expected_outputs[case.completed_level], "exact Tin output " .. case.machine_spec.name .. " level " .. case.completed_level)
    if case.drain_events == 0 then fail("output inventory was not drained for " .. case.machine_spec.name) end
    case.done = true
  end
end

local function summarize_machine(machine_spec, cases)
  local levels = {}
  for _, case in ipairs(cases) do
    if case.completed_level ~= #levels then fail("non-deterministic case order for " .. machine_spec.name) end
    levels[#levels + 1] = {completed_level = case.completed_level, input_ore = case.input_inserted, input_exhausted = case.input_exhausted, output = case.drained, bonus = case.drained - case.input_inserted, output_drain_observed = case.drain_events > 0}
  end
  return {name = machine_spec.name, entity_type = machine_spec.entity_type, place_item = machine_spec.place_item, energy_type = machine_spec.energy_type, crafting_categories = machine_spec.crafting_categories, levels = levels}
end

script.on_init(function()
  if not script.active_mods.boblibrary or not script.active_mods.bobores or not script.active_mods.bobplates or script.active_mods.angelssmelting or script.active_mods.angelsrefining or script.active_mods.angelspetrochem then fail("fixture requires exact Bob-only closure") end
  local state = {caps = assert_cap_transport(), no_level_four = assert_no_level_four(), cases = {}, passed = false}
  for machine_index, machine_spec in ipairs(expected_machines) do
    for completed_level = 0, imported_cap do state.cases[#state.cases + 1] = create_case(machine_spec, completed_level, machine_index) end
  end
  storage.mir_bob_tin_machine_matrix = state
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_bob_tin_machine_matrix
  if not state or state.passed then return end
  local complete = true
  for _, case in ipairs(state.cases) do if not case.done then maintain_and_drain(case) end; complete = complete and case.done end
  if complete then
    local machines, offset = {}, 1
    for _, machine_spec in ipairs(expected_machines) do
      local cases = {state.cases[offset], state.cases[offset + 1], state.cases[offset + 2], state.cases[offset + 3]}
      offset = offset + 4
      machines[#machines + 1] = summarize_machine(machine_spec, cases)
    end
    state.passed = true
    log("[mir-bob-tin-machine-matrix] RUNTIME JSON {\"raw_direct\":" .. state.caps.raw_direct .. ",\"mirset1_imported\":" .. state.caps.mirset1_imported .. ",\"effective\":" .. state.caps.effective .. ",\"no_level_4\":" .. tostring(state.no_level_four) .. ",\"input_ore_per_machine_per_level\":" .. input_ore .. ",\"machines\":" .. json_machines(machines) .. "}")
  elseif event.tick >= 30000 then
    fail("Tin machine matrix did not finish before bounded runtime deadline")
  end
end)
