local archetype = settings.startup["mir-upgrade-archetype"].value
local expected_progress = 0.42
local epsilon = 0.000001

local profiles = {
  ["base-default"] = {
    technology = "recipe-prod-research_iron-1",
    level = 3
  },
  ["space-age-native-owner"] = {
    technology = "low-density-structure-productivity",
    level = 5,
    requires_space_age = true,
    settings = {
      ["ips-enable-research_low_density_structure"] = true,
      ["ips-cost-base-research_low_density_structure"] = 1234,
      ["ips-cost-growth-research_low_density_structure"] = 1.7,
      ["ips-max-level-research_low_density_structure"] = 0,
      ["ips-research-time-research_low_density_structure"] = 77,
      ["ips-effect-per-level-research_low_density_structure"] = 13
    }
  },
  ["automatic-family-creation"] = {
    technology = "mir-auto-prod-manufacturing-assembling-machine-1",
    level = 3,
    target_recipe = "mir-upgrade-auto-assembler-recipe",
    settings = {
      ["mir-automatic-productivity-action"] = "apply",
      ["mir-automatic-create-research"] = true,
      ["mir-automatic-require-reviewed-data"] = false,
      ["ips-enable-research_auto_assembling_machine"] = true
    }
  },
  ["base-continuations"] = {
    technology = "inserter-capacity-bonus-8",
    level = 8,
    settings = {
      ["mir-enable-inserter-capacity-bonus"] = true
    }
  },
  ["mod-set-configuration-change"] = {
    technology = "recipe-prod-research_iron-1",
    level = 3,
    target_recipe = "mir-upgrade-removed-iron-plate",
    source_only_mod = "mir-fixture-upgrade-modset-source"
  }
}

local profile = profiles[archetype]
if not profile then error("unknown MIR upgrade archetype " .. tostring(archetype)) end

local function fail(message)
  error("MIR 3.1.9 to 3.2.0 " .. archetype .. " upgrade validation failed: " .. message)
end

local function assert_close(label, actual, expected)
  if math.abs((actual or 0) - expected) > epsilon then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected))
  end
end

local function technology()
  local value = game.forces.player.technologies[profile.technology]
  if not value then fail("missing technology " .. profile.technology) end
  return value
end

local function assert_settings()
  for name, expected in pairs(profile.settings or {}) do
    local setting = settings.startup[name]
    log("[mir-fixture] startup setting check archetype=" .. archetype
      .. " name=" .. name
      .. " present=" .. tostring(setting ~= nil)
      .. " value=" .. tostring(setting and setting.value))
    if not setting then fail("missing startup setting " .. name) end
    if setting.value ~= expected then
      fail(name .. " was " .. tostring(setting.value) .. ", expected " .. tostring(expected))
    end
  end
end

local function has_recipe_effect(technology_value, recipe_name)
  for _, effect in pairs((technology_value.prototype and technology_value.prototype.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function assert_source_profile(technology_value)
  if profile.requires_space_age and not script.active_mods["space-age"] then
    fail("Space Age was not active for its upgrade archetype")
  end
  if archetype == "base-default" and script.active_mods["space-age"] then
    fail("Space Age was unexpectedly active for the base/default archetype")
  end
  if profile.target_recipe then
    log("[mir-fixture] source target check archetype=" .. archetype
      .. " recipe=" .. profile.target_recipe
      .. " recipe_exists=" .. tostring(prototypes.recipe[profile.target_recipe] ~= nil)
      .. " effect_exists=" .. tostring(has_recipe_effect(technology_value, profile.target_recipe)))
    if not prototypes.recipe[profile.target_recipe] then
      fail("missing source recipe " .. profile.target_recipe)
    end
    if not has_recipe_effect(technology_value, profile.target_recipe) then
      fail("technology did not target source recipe " .. profile.target_recipe)
    end
  end
  if profile.source_only_mod and not script.active_mods[profile.source_only_mod] then
    fail("source-only compatibility mod was not active")
  end
end

local function assert_upgraded_profile(technology_value)
  if archetype == "automatic-family-creation" then
    if not prototypes.recipe[profile.target_recipe] then
      fail("automatic-family recipe disappeared during upgrade")
    end
    if not has_recipe_effect(technology_value, profile.target_recipe) then
      fail("automatic-family recipe effect disappeared during upgrade")
    end
  elseif archetype == "mod-set-configuration-change" then
    if script.active_mods[profile.source_only_mod] then
      fail("source-only compatibility mod remained active after removal")
    end
    if prototypes.recipe[profile.target_recipe] then
      fail("removed compatibility recipe remained after configuration change")
    end
    if has_recipe_effect(technology_value, profile.target_recipe) then
      fail("dangling removed-recipe target survived sanitation")
    end
  end
end

script.on_init(function()
  log("[mir-fixture] upgrade source initialization started archetype=" .. archetype)
  if script.active_mods["more-infinite-research"] ~= "3.1.9" then
    fail("initial save did not use MIR 3.1.9")
  end
  assert_settings()
  local force = game.forces.player
  local tech = technology()
  log("[mir-fixture] upgrade source technology resolved archetype=" .. archetype .. " technology=" .. profile.technology)
  assert_source_profile(tech)
  log("[mir-fixture] upgrade source profile asserted archetype=" .. archetype)
  force.research_all_technologies()
  log("[mir-fixture] upgrade source research initialized archetype=" .. archetype)
  tech.level = profile.level
  if not force.add_research(tech) then fail("could not queue " .. profile.technology) end
  force.research_progress = expected_progress
  storage.mir_upgrade_fixture = {
    archetype = archetype,
    technology = profile.technology,
    technology_level = tech.level,
    research_progress = force.research_progress,
    source_target_present = profile.target_recipe and has_recipe_effect(tech, profile.target_recipe) or nil
  }
  log("[mir-fixture] 3.1.9 upgrade source proof complete archetype=" .. archetype)
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "3.2.0" then
    fail("upgraded save did not use MIR 3.2.0")
  end
  assert_settings()
  local state = storage.mir_upgrade_fixture
  if not state then fail("fixture storage did not survive upgrade") end
  if state.archetype ~= archetype then fail("fixture archetype changed across upgrade") end
  if state.technology ~= profile.technology then fail("fixture technology identity changed across upgrade") end
  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then
    fail("technology level did not survive upgrade")
  end
  if not force.current_research or force.current_research.name ~= profile.technology then
    fail("current research did not survive upgrade")
  end
  assert_close("research progress", force.research_progress, state.research_progress)
  assert_upgraded_profile(tech)
  log("[mir-fixture] 3.1.9 to 3.2.0 upgrade proof complete archetype=" .. archetype)
end)
