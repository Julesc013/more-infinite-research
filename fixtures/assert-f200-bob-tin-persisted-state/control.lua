local technology_name = "recipe-prod-research_material_tin-1"
local recipe_name = "bob-tin-plate"
local setting_name = "ips-max-level-research_material_tin"
local raw_direct_cap = 2
local imported_cap = 3
local completed_levels = 2
local fractional_progress = 0.42
local profile_codec = require("__more-infinite-research__/prototypes/mir/settings/profile_codec")
local startup_settings = require("__more-infinite-research__/prototypes/mir/runtime/startup_settings")

local loaded_generation = nil
local terminal_logged = false

local function fail(message)
  error("[mir-f200-bob-tin-persisted-state] " .. message)
end

local function json_string(value)
  return "\"" .. tostring(value):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
end

local function json_array(values)
  local parts = {}
  for _, value in ipairs(values) do table.insert(parts, json_string(value)) end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function json_observation(stage, state, observed)
  return "{" ..
    "\"stage\":" .. json_string(stage) ..
    ",\"generation\":" .. state.generation ..
    ",\"predecessor_generation\":" .. state.predecessor_generation ..
    ",\"completed_levels\":" .. state.completed_levels ..
    ",\"current_research_technology_level\":" .. observed.current_research_technology_level ..
    ",\"current_research\":" .. json_string(observed.current_research) ..
    ",\"queue\":" .. json_array(observed.queue) ..
    ",\"fractional_progress\":" .. string.format("%.2f", observed.fractional_progress) ..
    ",\"observed_effect_change\":" .. string.format("%.2f", observed.effect_change) ..
    ",\"observed_effect_value_field\":" .. json_string(observed.effect_value_field) ..
    ",\"derived_earned_modifier\":" .. string.format("%.2f", state.completed_levels * observed.effect_change) ..
    ",\"raw_direct_max_level\":" .. observed.raw_direct ..
    ",\"mirset1_imported_max_level\":" .. observed.imported ..
    ",\"effective_max_level\":" .. observed.effective ..
    "}"
end

local function runtime_effect_observation(technology)
  local owners, change, field = 0, nil, nil
  for _, effect in ipairs(technology.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owners = owners + 1
      if effect.change ~= nil then
        change, field = tonumber(effect.change), "change"
      elseif effect.modifier ~= nil then
        change, field = tonumber(effect.modifier), "modifier"
      else
        fail("runtime Tin productivity effect has no change or modifier value")
      end
    end
  end
  if owners ~= 1 or type(change) ~= "number" or change ~= change or math.abs(change - 0.02) > 0.000000001 or field ~= "change" then
    fail("runtime Tin anchor effect differs owners=" .. tostring(owners) .. " field=" .. tostring(field) .. " value=" .. tostring(change))
  end
  return {change = change, value_field = field}
end

local function cap_observation()
  local profile = settings.startup["mir-settings-profile-import"]
  local direct = settings.startup[setting_name]
  if not profile or type(profile.value) ~= "string" or not direct or direct.value ~= raw_direct_cap then
    fail("raw direct cap transport differs")
  end
  local decoded, decode_error = profile_codec.decode(profile.value)
  local imported = decoded and decoded.settings and decoded.settings[setting_name]
  if imported ~= imported_cap then fail("MIRSET1 imported cap differs " .. tostring(decode_error)) end
  local raw = startup_settings.raw(setting_name)
  local effective = startup_settings.get(setting_name)
  if raw ~= raw_direct_cap or effective ~= imported_cap then fail("runtime cap resolver differs") end
  return {raw_direct = raw, imported = imported, effective = effective}
end

local function queue_names(force)
  local names = {}
  for _, entry in ipairs(force.research_queue or {}) do table.insert(names, entry.name) end
  return names
end

local function assert_exact_research_state(state)
  local force = game.forces.player
  local technology = force and force.technologies[technology_name]
  if not technology then fail("player force Tin technology is absent") end
  if technology.level ~= state.current_research_technology_level or technology.researched then fail("Tin completed/current level differs") end
  if not force.current_research or force.current_research.name ~= technology_name then fail("Tin current research differs") end
  if math.abs((force.research_progress or -1) - state.fractional_progress) > 0.0001 then fail("Tin fractional progress differs") end
  local queue = queue_names(force)
  if #queue ~= 1 or queue[1] ~= technology_name then fail("Tin research queue differs") end
  local caps = cap_observation()
  local effect = runtime_effect_observation(technology)
  return {
    current_research_technology_level = technology.level,
    current_research = force.current_research.name,
    queue = queue,
    fractional_progress = force.research_progress,
    effect_change = effect.change,
    effect_value_field = effect.value_field,
    raw_direct = caps.raw_direct,
    imported = caps.imported,
    effective = caps.effective,
  }
end

local function initialize_current_candidate_state()
  for _, official in ipairs({"base", "elevated-rails", "quality", "space-age"}) do
    if not script.active_mods[official] then fail("required official F200 mod is absent " .. official) end
  end
  if script.active_mods.recycler then
    fail("F200 2.0.77 official closure must not include recycler")
  end
  if not script.active_mods.boblibrary or not script.active_mods.bobores or not script.active_mods.bobplates then fail("fixture requires exact Bob closure") end
  if script.active_mods["angelssmelting"] or script.active_mods["angelsrefining"] or script.active_mods["angelspetrochem"] then fail("fixture refuses Angel modules") end
  local force = game.forces.player
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology then fail("published Tin anchor is absent for player force") end
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  for level = 1, completed_levels do
    if technology.level ~= level or not force.add_research(technology) or not force.current_research or force.current_research.name ~= technology_name then
      fail("could not establish exact Tin completed level " .. level)
    end
    force.research_queue = nil
    force.cancel_current_research()
    technology.researched = true
  end
  if technology.level ~= completed_levels + 1 then fail("Tin current technology level is not three after two completed levels") end
  if not force.add_research(technology) or not force.current_research or force.current_research.name ~= technology_name then
    fail("could not establish Tin level three fractional current research")
  end
  force.research_queue = {technology}
  force.research_progress = fractional_progress
  local state = {generation = 0, predecessor_generation = -1, completed_levels = completed_levels, current_research_technology_level = technology.level, fractional_progress = fractional_progress}
  storage.mir_f200_bob_tin_persisted_state = state
  log("[mir-f200-bob-tin-persisted-state] INITIAL JSON " .. json_observation("initial", state, assert_exact_research_state(state)))
end

local function save_successor(state, generation, predecessor_generation, save_name)
  local observed = assert_exact_research_state(state)
  state.generation = generation
  state.predecessor_generation = predecessor_generation
  log("[mir-f200-bob-tin-persisted-state] CYCLE JSON " .. json_observation("cycle", state, observed))
  game.server_save(save_name)
end

script.on_init(initialize_current_candidate_state)

script.on_load(function()
  local state = storage.mir_f200_bob_tin_persisted_state
  loaded_generation = state and state.generation or nil
  terminal_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir_f200_bob_tin_persisted_state
  if not state then fail("fixture state is absent") end
  if loaded_generation == nil or state.generation ~= loaded_generation then return end
  if loaded_generation == 0 then
    save_successor(state, 1, 0, "mir-f200-bob-tin-persisted-cycle-1")
  elseif loaded_generation == 1 then
    save_successor(state, 2, 1, "mir-f200-bob-tin-persisted-cycle-2")
  elseif loaded_generation == 2 then
    if not terminal_logged then
      terminal_logged = true
      log("[mir-f200-bob-tin-persisted-state] TERMINAL JSON " .. json_observation("terminal", state, assert_exact_research_state(state)))
    end
  else
    fail("fixture generation is outside two serialized cycles")
  end
end)
