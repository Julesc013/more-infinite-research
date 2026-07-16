local technology_name = "low-density-structure-productivity"
local expected_progress = 0.42
local epsilon = 0.000001

local setting_values = {
  ["ips-enable-research_low_density_structure"] = true,
  ["ips-cost-base-research_low_density_structure"] = 2000,
  ["ips-cost-growth-research_low_density_structure"] = 2,
  ["ips-max-level-research_low_density_structure"] = 0,
  ["ips-research-time-research_low_density_structure"] = 60,
  ["ips-effect-per-level-research_low_density_structure"] = 10
}

local function fail(message)
  error("MIR 2.4.5 to 2.5.0 native-owner upgrade validation failed: " .. message)
end

local function assert_close(label, actual, expected)
  if math.abs((actual or 0) - expected) > epsilon then
    fail(label .. " was " .. tostring(actual) .. ", expected " .. tostring(expected))
  end
end

local function technology()
  local value = game.forces.player.technologies[technology_name]
  if not value then fail("missing low-density-structure productivity technology") end
  return value
end

local function assert_settings()
  for name, expected in pairs(setting_values) do
    local setting = settings.startup[name]
    if not setting then fail("missing startup setting " .. name) end
    if setting.value ~= expected then
      fail(name .. " was " .. tostring(setting.value) .. ", expected " .. tostring(expected))
    end
  end
end

script.on_init(function()
  if script.active_mods["more-infinite-research"] ~= "2.4.5" then
    fail("initial save did not use MIR 2.4.5")
  end
  assert_settings()
  local force = game.forces.player
  local tech = technology()
  force.research_all_technologies()
  tech.level = 5
  if not force.add_research(tech) then fail("could not queue native-owner research") end
  force.research_progress = expected_progress
  storage.mir_upgrade_fixture_2_5_0 = {
    technology_level = tech.level,
    research_progress = force.research_progress
  }
  log("[mir-fixture] 2.4.5 upgrade source proof complete")
end)

script.on_configuration_changed(function()
  if script.active_mods["more-infinite-research"] ~= "2.5.0" then
    fail("upgraded save did not use MIR 2.5.0")
  end
  assert_settings()
  local state = storage.mir_upgrade_fixture_2_5_0
  if not state then fail("fixture storage did not survive upgrade") end
  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then
    fail("native-owner technology level did not survive upgrade")
  end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("current native-owner research did not survive upgrade")
  end
  assert_close("native-owner research progress", force.research_progress, state.research_progress)
  log("[mir-fixture] 2.4.5 to 2.5.0 upgrade proof complete")
end)
