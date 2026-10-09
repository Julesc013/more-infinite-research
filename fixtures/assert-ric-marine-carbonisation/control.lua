local technology_name = "recipe-prod-research_material_ric_coke-1"
local recipe_name = "ric-carbonise-marine-biomass"
local reload_pending = false

local function fail(message)
  error("MIR RIC Marine carbonisation: " .. message)
end

local function check(force, expected, stage)
  local technology = force.technologies[technology_name]
  local recipe = force.recipes[recipe_name]
  if not technology or not recipe then fail(stage .. " technology or recipe absent") end
  if technology.level ~= 2 or math.abs(recipe.productivity_bonus - expected) > 0.0001 then
    fail(stage .. " level or force recipe bonus changed")
  end
  log("[MIR42_RIC_MARINE_RUNTIME] " .. stage .. " level=2 bonus=" .. tostring(recipe.productivity_bonus))
end

script.on_init(function()
  if settings.startup["ric-world-mode"].value ~= "marine" then return end
  local force = game.create_force("mir-ric-marine-carbonisation-check")
  local recipe = assert(force.recipes[recipe_name], "RIC carbonisation recipe missing")
  local before = recipe.productivity_bonus
  local technology = assert(force.technologies[technology_name], "MIR carbonisation technology missing")
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
  if technology.level ~= 1 or not force.add_research(technology)
      or not force.current_research or force.current_research.name ~= technology_name then
    fail("could not offer the first carbonisation research level")
  end
  force.research_queue = nil
  force.cancel_current_research()
  technology.researched = true
  local expected = before + 0.02
  check(force, expected, "CREATE PASS")
  storage.mir_ric_marine_carbonisation = {force = force.name, bonus = expected}
end)

script.on_load(function()
  reload_pending = true
end)

script.on_event(defines.events.on_tick, function()
  if not reload_pending then return end
  reload_pending = false
  if settings.startup["ric-world-mode"].value ~= "marine" then return end
  local saved = storage.mir_ric_marine_carbonisation
  if not saved then fail("saved force assertion is absent") end
  local force = game.forces[saved.force]
  if not force then fail("saved force is absent") end
  check(force, saved.bonus, "RELOAD PASS")
end)
