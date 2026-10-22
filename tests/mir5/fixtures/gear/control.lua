local technology_name = "recipe-prod-research_gears-1"
local recipe_name = "iron-gear-wheel"
local save_name = "mir5-gear-native-complete"
local loaded_generation = nil
local reload_logged = false

local function fail(message)
  error("[mir5-gear-native] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000000001
end

local function describe_effects(effects)
  local rows = {}
  for index, row in ipairs(effects or {}) do
    rows[#rows + 1] = "#" .. index
      .. ":type=" .. tostring(row.type)
      .. ",recipe=" .. tostring(row.recipe)
      .. ",change=" .. tostring(row.change)
      .. ",modifier=" .. tostring(row.modifier)
  end
  return table.concat(rows, "|")
end

local function profile_for(technology)
  local change = nil
  local count = 0
  for _, row in ipairs(technology.prototype.effects or {}) do
    if row.type == "change-recipe-productivity" and row.recipe == recipe_name then
      change = row.change
      count = count + 1
    end
  end
  if count ~= 1 then fail("runtime gear productivity owner cardinality differs") end
  local time = technology.prototype.research_unit_energy
  local version = script.active_mods["mir-fixture-mir5-gear-native"]
  log("[MIR5_GEAR_RUNTIME_PROFILE] fixture_version=" .. tostring(version)
    .. ";research_unit_energy=" .. tostring(time)
    .. ";matching_effect_count=" .. tostring(count)
    .. ";matching_change=" .. tostring(change)
    .. ";effects=" .. describe_effects(technology.prototype.effects))
  if version == "0.1.0" and close(change, 0.10) and close(time, 3600) then
    return {name = "default", change = 0.10, level_one_count = 8000, physical_output = 110}
  end
  if version == "0.2.0" and close(change, 0.20) and close(time, 1800) then
    return {name = "tuned", change = 0.20, level_one_count = 100, physical_output = 120}
  end
  fail("runtime gear setting profile is neither default nor approved tuned")
end

local function json(state, stage)
  return "{\"stage\":\"" .. stage
    .. "\",\"profile\":\"" .. state.profile.name
    .. "\",\"technology\":\"" .. technology_name
    .. "\",\"completed_level\":" .. state.completed_level
    .. ",\"next_level\":" .. state.next_level
    .. ",\"effect_change\":" .. string.format("%.2f", state.profile.change)
    .. ",\"level_one_count\":" .. state.level_one_count
    .. ",\"level_two_count\":" .. state.level_two_count
    .. ",\"level_three_count\":" .. state.level_three_count
    .. ",\"baseline_output\":" .. state.baseline_output
    .. ",\"researched_output\":" .. state.researched_output
    .. "}"
end

local function assert_reloaded(state)
  local force = game.forces.player
  local technology = force and force.technologies[technology_name]
  if not technology or technology.level ~= state.next_level or technology.researched then
    fail("saved infinite technology level differs")
  end
  if not close(force.recipes[recipe_name].productivity_bonus, state.profile.change) then
    fail("saved recipe productivity bonus differs")
  end
  if state.baseline_output ~= 100 or state.researched_output ~= state.profile.physical_output then
    fail("saved physical crafting witness differs")
  end
end

local function observe_native_counts(profile)
  local observer = game.forces["mir5-gear-count-observer"] or game.create_force("mir5-gear-count-observer")
  observer.enable_all_prototypes()
  local technology = observer.technologies[technology_name]
  if not technology then fail("count observer has no gear technology") end
  local counts = {}
  for level = 1, 3 do
    technology.level = level
    counts[level] = technology.research_unit_count
  end
  if counts[1] ~= profile.level_one_count or counts[2] <= counts[1] or counts[3] <= counts[2] then
    fail("native research count progression differs")
  end
  return counts
end

local function machine_for(force)
  local surface = game.surfaces[1]
  local entity = surface.create_entity{name = "assembling-machine-3", position = {0, 0}, force = force}
  if not entity or not entity.valid then fail("could not create native gear assembler") end
  if not entity.set_recipe(recipe_name) then fail("could not select native gear recipe") end
  return entity
end

local function begin_crafting(state, phase)
  local entity = state.machine
  if not entity or not entity.valid then fail("native gear assembler disappeared") end
  entity.energy = 1000000000
  local input = entity.get_inventory(defines.inventory.crafter_input)
  local output = entity.get_inventory(defines.inventory.crafter_output)
  if not input or not output or not output.is_empty() or not input.is_empty() then
    fail("native gear assembler inventories were not clean")
  end
  local inserted = input.insert{name = "iron-plate", count = 200}
  if inserted ~= 200 then fail("could not supply 200 iron plates; inserted " .. tostring(inserted)) end
  state.phase = phase
  state.phase_output = 0
end

local function drain_crafting(state)
  local entity = state.machine
  if not entity or not entity.valid then fail("native gear assembler disappeared during crafting") end
  entity.energy = 1000000000
  local input = entity.get_inventory(defines.inventory.crafter_input)
  local output = entity.get_inventory(defines.inventory.crafter_output)
  local count = output.get_item_count(recipe_name)
  if count > 0 then
    if output.remove{name = recipe_name, count = count} ~= count then fail("could not drain native gear output") end
    state.phase_output = state.phase_output + count
  end
  if input.get_item_count("iron-plate") ~= 0 or entity.crafting_progress ~= 0 then return false end
  return true
end

local function complete_research(state)
  local force = game.forces.player
  local technology = force.technologies[technology_name]
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  technology.researched = true
  if technology.level ~= 2 or technology.researched then fail("could not complete native level one gear research") end
  if not close(force.recipes[recipe_name].productivity_bonus, state.profile.change) then
    fail("research completion did not apply native productivity")
  end
  state.completed_level = 1
  state.next_level = technology.level
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("fixture loaded with an unexpected private MIR 5 or Factorio closure")
  end
  local force = game.forces.player
  force.enable_all_prototypes()
  local technology = force.technologies[technology_name]
  if not technology or technology.level ~= 1 or technology.researched then fail("fresh gear technology state differs") end
  local profile = profile_for(technology)
  local prototype_count = technology.prototype.research_unit_count
  local force_count = technology.research_unit_count
  log("[MIR5_GEAR_RUNTIME_COUNT] level=" .. tostring(technology.level)
    .. ";force_research_unit_count=" .. tostring(force_count)
    .. ";prototype_research_unit_count=" .. tostring(prototype_count)
    .. ";force_formula=" .. tostring(technology.research_unit_count_formula)
    .. ";prototype_formula=" .. tostring(technology.prototype.research_unit_count_formula))
  if force_count ~= profile.level_one_count then
    fail("native level-one research count differs")
  end
  if not close(force.recipes[recipe_name].productivity_bonus, 0) then fail("unresearched gear recipe has productivity") end
  local counts = observe_native_counts(profile)
  storage.mir5_gear_native = {
    profile = profile,
    machine = machine_for(force),
    phase = "",
    phase_output = 0,
    baseline_output = 0,
    researched_output = 0,
    completed_level = 0,
    next_level = 1,
    level_one_count = force_count,
    level_two_count = counts[2],
    level_three_count = counts[3],
    deadline_tick = game.tick + 18000
  }
  begin_crafting(storage.mir5_gear_native, "baseline")
end)

script.on_load(function()
  local state = storage.mir5_gear_native
  loaded_generation = state and state.saved and state.completed_level or nil
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir5_gear_native
  if not state then fail("fixture state is absent") end
  if loaded_generation ~= nil then
    assert_reloaded(state)
    if not reload_logged then
      reload_logged = true
      log("[MIR5_GEAR_NATIVE] RESULT " .. json(state, "reload"))
    end
    return
  end
  if game.tick > state.deadline_tick then fail("native gear crafting did not finish within 18000 ticks") end
  if not drain_crafting(state) then return end
  if state.phase == "baseline" then
    if state.phase_output ~= 100 then fail("100 baseline crafts did not produce exactly 100 gears") end
    state.baseline_output = state.phase_output
    complete_research(state)
    begin_crafting(state, "researched")
  elseif state.phase == "researched" then
    if state.phase_output ~= state.profile.physical_output then
      fail("researched native gear crafts did not produce expected productivity output")
    end
    state.researched_output = state.phase_output
    assert_reloaded(state)
    log("[MIR5_GEAR_NATIVE] RESULT " .. json(state, "initial"))
    state.saved = true
    state.phase = "saved"
    game.server_save(save_name)
  elseif state.phase ~= "saved" then
    fail("unknown fixture phase " .. tostring(state.phase))
  end
end)
