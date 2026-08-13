local archetype = settings.startup["mir-upgrade-archetype"].value
local expected_progress = 0.42
local epsilon = 0.000001

local shared_settings = {
  ["ips-cost-base-research_gears"] = 4321,
  ["ips-cost-growth-research_gears"] = 1.25,
  ["mir-cost-base-worker-robots-storage"] = 2345,
  ["mir-cost-growth-worker-robots-storage"] = 1.1
}

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
    source_realized_cost = 914488,
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
  error("MIR 3.2.3 to 3.2.9 " .. archetype .. " upgrade validation failed: " .. message)
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

local function assert_setting(name, expected)
  local setting = settings.startup[name]
  if not setting then fail("missing startup setting " .. name) end
  if setting.value ~= expected then
    fail(name .. " was " .. tostring(setting.value) .. ", expected " .. tostring(expected))
  end
end

local function assert_settings(upgraded)
  for name, expected in pairs(shared_settings) do assert_setting(name, expected) end
  for name, expected in pairs(profile.settings or {}) do assert_setting(name, expected) end
  local stream_increment = settings.startup["ips-cost-linear-increment-research_gears"]
  local continuation_increment = settings.startup["mir-cost-linear-increment-worker-robots-storage"]
  if upgraded then
    if not stream_increment or stream_increment.value ~= 0 then
      fail("stream linear increment was not introduced at neutral default")
    end
    if not continuation_increment or continuation_increment.value ~= 0 then
      fail("continuation linear increment was not introduced at neutral default")
    end
  elseif stream_increment or continuation_increment then
    fail("linear increment settings existed in the 3.2.3 source save")
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
  if script.active_mods["more-infinite-research"] ~= "3.2.3" then
    fail("source save did not use MIR 3.2.3")
  end
  assert_settings(false)
  local force = game.forces.player
  local tech = technology()
  assert_source_profile(tech)
  force.research_all_technologies()
  tech.level = profile.level
  if not force.add_research(tech) then fail("could not queue " .. profile.technology) end
  force.research_progress = expected_progress
  local research_unit_count = tech.research_unit_count
  if not research_unit_count or research_unit_count <= 0 then
    fail("source realized research-unit count is unavailable")
  end
  if profile.source_realized_cost and research_unit_count ~= profile.source_realized_cost then
    fail("source realized research-unit count was " .. tostring(research_unit_count)
      .. ", expected " .. tostring(profile.source_realized_cost))
  end
  storage.mir_upgrade_fixture = {
    archetype = archetype,
    technology = profile.technology,
    technology_level = tech.level,
    research_progress = force.research_progress,
    research_unit_count = research_unit_count,
    source_version = "3.2.3"
  }
  log("[mir-fixture] 3.2.3 upgrade source proof complete archetype=" .. archetype
    .. " progress=" .. tostring(force.research_progress)
    .. " realized-cost=" .. tostring(research_unit_count))
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "3.2.9" then
    fail("upgraded save did not use MIR 3.2.9")
  end
  assert_settings(true)
  local state = storage.mir_upgrade_fixture
  if not state then fail("fixture storage did not survive upgrade") end
  if state.archetype ~= archetype then fail("fixture archetype changed across upgrade") end
  if state.source_version ~= "3.2.3" then fail("source-version authority did not survive upgrade") end
  if state.technology ~= profile.technology then fail("technology identity changed across upgrade") end
  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then fail("technology level did not survive") end
  if not force.current_research or force.current_research.name ~= profile.technology then
    fail("current research did not survive")
  end
  if not state.research_unit_count or state.research_unit_count <= 0 then
    fail("source realized research-unit count evidence is unavailable")
  end
  local current_research_unit_count = tech.research_unit_count
  if not current_research_unit_count or current_research_unit_count <= 0 then
    fail("upgraded realized research-unit count is unavailable")
  end
  local expected_upgraded_progress = math.max(0, math.min(1,
    state.research_progress * state.research_unit_count / current_research_unit_count))
  assert_close("completed research-unit work", force.research_progress, expected_upgraded_progress)
  if archetype == "base-continuations" and current_research_unit_count ~= state.research_unit_count then
    fail("neutral 3.2.9 base-continuation controls changed the 3.2.3 realized cost from "
      .. tostring(state.research_unit_count) .. " to " .. tostring(current_research_unit_count))
  end
  assert_upgraded_profile(tech)
  state.upgrade_complete = true
  log("[mir-fixture] 3.2.3 to 3.2.9 upgrade proof complete archetype=" .. archetype
    .. " progress=" .. tostring(force.research_progress)
    .. " source-realized-cost=" .. tostring(state.research_unit_count)
    .. " upgraded-realized-cost=" .. tostring(current_research_unit_count))
end)

script.on_event(defines.events.on_tick, function(event)
  local state = storage.mir_upgrade_fixture
  if state and state.upgrade_complete and not state.server_save_requested then
    state.server_save_requested = true
    game.server_save("mir-325-upgraded")
    log("[mir-fixture] governed upgraded save requested tick=" .. event.tick)
  end
end)

script.on_load(function()
  if storage.mir_upgrade_fixture and storage.mir_upgrade_fixture.upgrade_complete then
    log("[mir-fixture] 3.2.9 upgraded save reload proof complete archetype=" .. archetype)
  end
end)
