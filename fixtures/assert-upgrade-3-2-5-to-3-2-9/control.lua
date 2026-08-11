local archetype = settings.startup["mir-upgrade-archetype"].value
local expected_progress = 0.42
local epsilon = 0.000001

local profiles = {
  ["base-default"] = {technology = "recipe-prod-research_iron-1", level = 3},
  ["space-age-native-owner"] = {technology = "low-density-structure-productivity", level = 5, requires_space_age = true},
  ["automatic-family-creation"] = {
    technology = "mir-auto-prod-manufacturing-assembling-machine-1", level = 3,
    target_recipe = "mir-upgrade-auto-assembler-recipe"
  },
  ["base-continuations"] = {technology = "inserter-capacity-bonus-8", level = 8},
  ["mod-set-configuration-change"] = {
    technology = "recipe-prod-research_iron-1", level = 3,
    target_recipe = "mir-upgrade-removed-iron-plate",
    source_only_mod = "mir-fixture-upgrade-modset-source"
  }
}

local profile = profiles[archetype]
if not profile then error("unknown MIR upgrade archetype " .. tostring(archetype)) end

local function fail(message)
  error("MIR 3.2.5 to 3.2.9 " .. archetype .. " upgrade validation failed: " .. message)
end

local function technology()
  local value = game.forces.player.technologies[profile.technology]
  if not value then fail("missing technology " .. profile.technology) end
  return value
end

local function science_names(technology_value)
  local out = {}
  for _, ingredient in pairs(technology_value.research_unit_ingredients or {}) do
    table.insert(out, ingredient.name)
  end
  table.sort(out)
  return out
end

local function same_names(left, right)
  if #left ~= #right then return false end
  for index, value in ipairs(left) do if value ~= right[index] then return false end end
  return true
end

local function has_recipe_effect(technology_value, recipe_name)
  for _, effect in pairs((technology_value.prototype and technology_value.prototype.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then return true end
  end
  return false
end

script.on_init(function()
  if script.active_mods["more-infinite-research"] ~= "3.2.5" then fail("source save did not use MIR 3.2.5") end
  if profile.requires_space_age and not script.active_mods["space-age"] then fail("Space Age was not active") end
  if archetype == "base-default" and script.active_mods["space-age"] then fail("Space Age was unexpectedly active") end
  if profile.source_only_mod and not script.active_mods[profile.source_only_mod] then fail("source-only mod was not active") end

  local force = game.forces.player
  local tech = technology()
  if profile.target_recipe and not has_recipe_effect(tech, profile.target_recipe) then
    fail("technology did not target source recipe " .. profile.target_recipe)
  end
  force.research_all_technologies()
  tech.level = profile.level
  if not force.add_research(tech) then fail("could not queue " .. profile.technology) end
  force.research_progress = expected_progress
  if not tech.research_unit_count or tech.research_unit_count <= 0 then fail("source research cost is unavailable") end
  storage.mir_upgrade_fixture = {
    archetype = archetype,
    technology = profile.technology,
    technology_level = tech.level,
    research_progress = force.research_progress,
    research_unit_count = tech.research_unit_count,
    science = science_names(tech),
    source_version = "3.2.5"
  }
  log("[mir-fixture] 3.2.5 upgrade source proof complete archetype=" .. archetype)
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "3.2.9" then fail("upgraded save did not use MIR 3.2.9") end
  local state = storage.mir_upgrade_fixture
  if not state or state.source_version ~= "3.2.5" then fail("fixture storage did not survive upgrade") end
  if state.archetype ~= archetype or state.technology ~= profile.technology then fail("stable identity changed") end

  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then fail("technology level did not survive") end
  if not force.current_research or force.current_research.name ~= profile.technology then fail("current research did not survive") end
  local current_count = tech.research_unit_count
  if not current_count or current_count <= 0 then fail("upgraded research cost is unavailable") end
  local expected = math.max(0, math.min(1, state.research_progress * state.research_unit_count / current_count))
  if math.abs((force.research_progress or 0) - expected) > epsilon then fail("completed research work changed") end
  if not same_names(state.science, science_names(tech)) then fail("science ingredients changed outside the exact K2 envelope") end

  if archetype == "automatic-family-creation" and not has_recipe_effect(tech, profile.target_recipe) then
    fail("automatic-family recipe effect disappeared")
  elseif archetype == "mod-set-configuration-change" then
    if script.active_mods[profile.source_only_mod] then fail("source-only mod remained active") end
    if prototypes.recipe[profile.target_recipe] or has_recipe_effect(tech, profile.target_recipe) then
      fail("removed recipe or dangling effect survived sanitation")
    end
  end

  state.upgrade_complete = true
  log("[mir-fixture] 3.2.5 to 3.2.9 upgrade proof complete archetype=" .. archetype)
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir_upgrade_fixture
  if state and state.upgrade_complete and not state.server_save_requested then
    state.server_save_requested = true
    game.server_save("mir-329-upgraded")
    log("[mir-fixture] governed upgraded save requested")
  end
end)

script.on_load(function()
  if storage.mir_upgrade_fixture and storage.mir_upgrade_fixture.upgrade_complete then
    log("[mir-fixture] 3.2.9 upgraded save reload proof complete archetype=" .. archetype)
  end
end)
