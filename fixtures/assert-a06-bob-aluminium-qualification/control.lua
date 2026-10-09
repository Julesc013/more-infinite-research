local technology_name = "recipe-prod-research_material_aluminium-1"
local recipe_name = "bob-aluminium-plate"
local setting_name = "ips-max-level-research_material_aluminium"
local raw_direct_cap, imported_cap = 2, 3
local input_alumina, input_carbon = 100, 50
local expected_outputs = {[0] = 100, [1] = 102, [2] = 104, [3] = 106}
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")
local loaded_generation, terminal_logged = nil, false

local function fail(message) error("[mir-a06-bob-aluminium-qualification] " .. message) end
local function bool(value) return value and "true" or "false" end

local function cap_state()
  local profile, direct = settings.startup["mir-settings-profile-import"], settings.startup[setting_name]
  if not profile or not direct or direct.value ~= raw_direct_cap then fail("raw direct cap transport differs") end
  local decoded, decode_error = profile_codec.decode(profile.value)
  local imported = decoded and decoded.settings and decoded.settings[setting_name]
  if imported ~= imported_cap then fail("MIRSET1 cap differs: " .. tostring(decode_error)) end
  local raw, effective = startup_settings.raw(setting_name), startup_settings.get(setting_name)
  if raw ~= raw_direct_cap or effective ~= imported_cap then fail("cap resolver differs") end
  return {raw = raw, imported = imported, effective = effective}
end

local function runtime_effect(technology)
  local count, change = 0, nil
  for _, effect in ipairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then count = count + 1; change = effect.change end
  end
  if count ~= 1 or change ~= 0.02 then fail("runtime productivity owner differs") end
  return change
end

local function prepare_technology(force, completed_level)
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology then fail("Aluminium technology absent") end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for level = 1, completed_level do
    if technology.level ~= level or not force.add_research(technology) or not force.current_research or force.current_research.name ~= technology_name then fail("could not offer exact Aluminium level " .. level) end
    force.research_queue = nil
    force.cancel_current_research()
    technology.researched = true
  end
  if technology.level ~= completed_level + 1 then fail("completed Aluminium level differs") end
  return technology
end

local function no_level_four()
  local force = game.create_force("mir-a06-bob-aluminium-cap")
  local technology = prepare_technology(force, imported_cap)
  local accepted = force.add_research(technology)
  local result = not technology.researched and not technology.enabled and not accepted
  if not result then fail("effective Aluminium cap admitted level four") end
  return result
end

local function create_production_case(level)
  local force = game.create_force("mir-a06-bob-aluminium-production-" .. level)
  prepare_technology(force, level)
  local entity = game.surfaces[1].create_entity{name = "bob-electrolyser", position = {level * 5, 0}, force = force}
  if not entity or entity.type ~= "assembling-machine" or not entity.set_recipe(recipe_name) then fail("bob-electrolyser cannot execute Aluminium recipe at level " .. level) end
  local input, output = entity.get_inventory(defines.inventory.crafter_input), entity.get_inventory(defines.inventory.crafter_output)
  if not input or not output then fail("electrolyser crafting inventories absent") end
  if input.insert{name = "bob-alumina", count = input_alumina} ~= input_alumina or input.insert{name = "carbon", count = input_carbon} ~= input_carbon then fail("exact Aluminium inputs could not be established") end
  local ok = pcall(function() entity.energy = 1000000000 end)
  if not ok or not entity.energy or entity.energy <= 0 then fail("electrolyser electric buffer is unavailable") end
  return {level = level, entity = entity, drained = 0, drain_events = 0, done = false}
end

local function maintain_production(case)
  local ok = pcall(function() case.entity.energy = 1000000000 end)
  if not ok or not case.entity.energy or case.entity.energy <= 0 then fail("electrolyser electric buffer disappeared") end
  local input, output = case.entity.get_inventory(defines.inventory.crafter_input), case.entity.get_inventory(defines.inventory.crafter_output)
  if not input or not output then fail("electrolyser crafting inventories disappeared") end
  local available = output.get_item_count(recipe_name)
  if available > 0 then
    local removed = output.remove{name = recipe_name, count = available}
    if removed ~= available then fail("Aluminium output drain differs") end
    case.drained = case.drained + removed
    case.drain_events = case.drain_events + 1
  end
  local exhausted = input.get_item_count("bob-alumina") == 0 and input.get_item_count("carbon") == 0
  if exhausted and case.entity.crafting_progress == 0 and output.get_item_count(recipe_name) == 0 then
    if case.drained ~= expected_outputs[case.level] or case.drain_events == 0 then fail("exact Aluminium output differs at level " .. case.level .. ": " .. case.drained) end
    case.done = true
  end
end

local function stable_state(force, caps)
  local technology = force.technologies[technology_name]
  if not technology or technology.level ~= 3 or technology.researched or not force.current_research or force.current_research.name ~= technology_name then fail("partially researched level-three state differs") end
  if math.abs((force.research_progress or -1) - 0.42) > 0.0001 then fail("fractional level-three progress differs") end
  local queue = force.research_queue or {}
  if #queue ~= 1 or queue[1].name ~= technology_name then fail("level-three research queue differs") end
  local effect = runtime_effect(technology)
  return "completed=2|current-level=3|current=" .. technology_name .. "|queue=" .. technology_name .. "|progress=0.42|effect=0.02|earned=0.04|raw=" .. caps.raw .. "|imported=" .. caps.imported .. "|effective=" .. caps.effective
end

local function log_state(stage, state)
  local caps = cap_state()
  local stable = stable_state(game.forces.player, caps)
  log("[mir-a06-bob-aluminium-qualification] STATE stage=" .. stage .. " generation=" .. state.generation .. " predecessor=" .. state.predecessor_generation .. " stable=" .. stable)
end

local function initialize_persisted_state()
  local force = game.forces.player
  local technology = prepare_technology(force, 2)
  if not force.add_research(technology) or not force.current_research or force.current_research.name ~= technology_name then fail("could not establish partially researched Aluminium level three") end
  force.research_queue = {technology}
  force.research_progress = 0.42
  storage.mir_a06_bob_aluminium = {generation = 0, predecessor_generation = -1, production = {caps = cap_state(), no_level_four = no_level_four(), cases = {create_production_case(0), create_production_case(1), create_production_case(2), create_production_case(3)}, passed = false}}
  log_state("initial", storage.mir_a06_bob_aluminium)
end

script.on_init(function()
  for _, name in ipairs({"base", "boblibrary", "bobores", "bobplates", "more-infinite-research"}) do if not script.active_mods[name] then fail("required Bob closure mod absent " .. name) end end
  for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do if script.active_mods[name] then fail("Bob-only fixture refuses " .. name) end end
  initialize_persisted_state()
end)

script.on_load(function()
  local state = storage.mir_a06_bob_aluminium
  loaded_generation = state and state.generation or nil
  terminal_logged = false
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_a06_bob_aluminium
  if not state then fail("qualification state is absent") end
  local production = state.production
  if not production.passed then
    local complete = true
    for _, case in ipairs(production.cases) do if not case.done then maintain_production(case) end; complete = complete and case.done end
    if complete then
      production.passed = true
      local levels = {}
      for _, case in ipairs(production.cases) do levels[#levels + 1] = case.level .. ":" .. case.drained .. ":" .. (case.drained - 100) end
      log("[mir-a06-bob-aluminium-qualification] PRODUCTION raw=" .. production.caps.raw .. " imported=" .. production.caps.imported .. " effective=" .. production.caps.effective .. " no-level-4=" .. bool(production.no_level_four) .. " input-alumina=100 input-carbon=50 levels=" .. table.concat(levels, ",") .. " inputs-exhausted=true output-drained=true")
    elseif event.tick >= 30000 then
      fail("Aluminium production did not finish before bounded runtime deadline")
    end
  end
  if loaded_generation == nil or state.generation ~= loaded_generation then return end
  if loaded_generation == 0 then
    state.generation, state.predecessor_generation = 1, 0
    log_state("cycle", state)
    game.server_save("mir-a06-bob-aluminium-cycle-1")
  elseif loaded_generation == 1 then
    state.generation, state.predecessor_generation = 2, 1
    log_state("cycle", state)
    game.server_save("mir-a06-bob-aluminium-cycle-2")
  elseif loaded_generation == 2 and not terminal_logged then
    terminal_logged = true
    log_state("terminal", state)
  elseif loaded_generation > 2 then
    fail("persisted generation is outside two reload cycles")
  end
end)