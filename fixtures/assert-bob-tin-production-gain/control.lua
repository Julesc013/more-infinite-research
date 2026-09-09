local technology_name = "recipe-prod-research_material_tin-1"
local recipe_name = "bob-tin-plate"
local raw_direct_cap = 2
local imported_cap = 3
local input_ore = 100
local expected_outputs = {[0] = 100, [1] = 102, [2] = 104, [3] = 106}
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local function fail(message)
  error("[mir-bob-tin-production-gain] " .. message)
end

local function assert_cap_transport()
  local profile = settings.startup["mir-settings-profile-import"]
  local cap = settings.startup["ips-max-level-research_material_tin"]
  if not profile or type(profile.value) ~= "string" or not cap or cap.value ~= raw_direct_cap then fail("raw direct cap transport differs") end
  local decoded, decode_error = profile_codec.decode(profile.value)
  if not decoded or not decoded.settings or decoded.settings["ips-max-level-research_material_tin"] ~= imported_cap then fail("MIRSET1 cap transport differs: " .. tostring(decode_error)) end
  local raw = startup_settings.raw("ips-max-level-research_material_tin")
  local effective = startup_settings.get("ips-max-level-research_material_tin")
  if raw ~= raw_direct_cap then fail("raw resolver does not retain direct cap two") end
  if effective ~= imported_cap then fail("effective resolver does not apply imported cap three") end
  return {raw_direct = raw, mirset1_imported = decoded.settings["ips-max-level-research_material_tin"], effective = effective}
end

local function prepare_technology(force, completed_level)
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology then fail("Tin technology is absent for level " .. completed_level) end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for level = 1, completed_level do
    if technology.level ~= level or not force.add_research(technology) or not force.current_research or force.current_research.name ~= technology_name then
      fail("could not offer exact Tin level " .. level)
    end
    force.research_queue = nil
    force.cancel_current_research()
    technology.researched = true
  end
  if technology.level ~= completed_level + 1 then fail("completed Tin level differs " .. completed_level) end
  return technology
end

local function assert_no_level_four()
  local force = game.create_force("mir-bob-tin-production-gain-cap")
  local technology = prepare_technology(force, imported_cap)
  local accepted = force.add_research(technology)
  local no_level_four = not technology.researched and not technology.enabled and not accepted
  if not no_level_four then fail("effective Tin cap admitted level four") end
  return no_level_four
end

local function summarize_runtime_observation(cases, caps, no_level_four)
  local levels = {}
  local input_exhausted = true
  local output_drained = true
  local observed_input = nil
  for index, case in ipairs(cases) do
    if case.level ~= index - 1 then fail("runtime case order is not deterministic") end
    if not observed_input then observed_input = case.input_inserted elseif observed_input ~= case.input_inserted then fail("runtime input observations differ") end
    levels[#levels + 1] = case.level .. ":" .. case.drained .. ":" .. (case.drained - case.input_inserted)
    input_exhausted = input_exhausted and case.input_exhausted
    output_drained = output_drained and case.drain_events > 0
  end
  return "raw=" .. caps.raw_direct .. " imported=" .. caps.mirset1_imported .. " effective=" .. caps.effective .. " no-level-4=" .. tostring(no_level_four) .. " input-ore=" .. observed_input .. " levels=" .. table.concat(levels, ",") .. " input-exhausted=" .. tostring(input_exhausted) .. " output-drained=" .. tostring(output_drained)
end

local function create_case(level)
  local force = game.create_force("mir-bob-tin-production-gain-" .. level)
  local technology = prepare_technology(force, level)
  local furnace = game.surfaces[1].create_entity{name = "stone-furnace", position = {level * 4, 0}, force = force}
  if not furnace then fail("could not create stone-furnace Tin witness at level " .. level) end
  local input = furnace.get_inventory(defines.inventory.crafter_input)
  local fuel = furnace.get_inventory(defines.inventory.fuel)
  if not input or not fuel then fail("Tin furnace inventory is absent at level " .. level) end
  local inserted_input = input.insert{name = "bob-tin-ore", count = input_ore}
  local inserted_fuel = fuel.insert{name = "solid-fuel", count = 50}
  if inserted_input ~= input_ore or inserted_fuel ~= 50 then fail("could not establish exact Tin production inputs at level " .. level) end
  return {level = level, force = force, technology = technology, furnace = furnace, input_inserted = inserted_input, drained = 0, drain_events = 0, input_exhausted = false, done = false}
end

local function drain_case(case)
  local output = case.furnace.get_inventory(defines.inventory.crafter_output)
  local input = case.furnace.get_inventory(defines.inventory.crafter_input)
  if not output or not input then fail("Tin furnace inventory is absent at level " .. case.level) end
  local count = output.get_item_count("bob-tin-plate")
  if count > 0 then
    local removed = output.remove{name = "bob-tin-plate", count = count}
    if removed ~= count then fail("Tin output drain failed at level " .. case.level) end
    case.drained = case.drained + removed
    case.drain_events = case.drain_events + 1
  end
  if input.get_item_count("bob-tin-ore") == 0 then case.input_exhausted = true end
  if case.input_exhausted and case.furnace.crafting_progress == 0 and output.get_item_count("bob-tin-plate") == 0 then
    local expected = expected_outputs[case.level]
    if case.drained ~= expected then fail("exact Tin output differs at completed level " .. case.level .. ": " .. case.drained .. " expected " .. expected) end
    if case.drain_events == 0 then fail("Tin output capacity was not actively drained at level " .. case.level) end
    case.done = true
  end
end

script.on_init(function()
  if not script.active_mods.boblibrary or not script.active_mods.bobores or not script.active_mods.bobplates or script.active_mods.angelssmelting or script.active_mods.angelsrefining or script.active_mods.angelspetrochem then fail("fixture requires exact Bob-only closure") end
  local caps = assert_cap_transport()
  local no_level_four = assert_no_level_four()
  storage.mir_bob_tin_production_gain = {cases = {create_case(0), create_case(1), create_case(2), create_case(3)}, caps = caps, no_level_four = no_level_four, passed = false}
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_bob_tin_production_gain
  if not state or state.passed then return end
  for _, case in ipairs(state.cases) do if not case.done then drain_case(case) end end
  local complete = true
  for _, case in ipairs(state.cases) do if not case.done then complete = false end end
  if complete then
    state.passed = true
    log("[mir-bob-tin-production-gain] RUNTIME PASS " .. summarize_runtime_observation(state.cases, state.caps, state.no_level_four))
  elseif event.tick >= 30000 then
    fail("Tin production did not finish before bounded runtime deadline")
  end
end)
