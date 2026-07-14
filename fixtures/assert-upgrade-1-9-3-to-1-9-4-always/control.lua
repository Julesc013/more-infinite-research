local from_version = "1.9.3"
local to_version = "1.9.4"
local expected_mode = "always"
local technology_name = "recipe-prod-research_lab_productivity-1"
local expected_progress = 0.42
local epsilon = 0.000001

local function fail(message)
  error("MIR 1.9.3 to 1.9.4 always-retention validation failed: " .. message)
end

local function active_version()
  return script.active_mods["more-infinite-research"]
end

local function technology()
  local value = game.forces.player.technologies[technology_name]
  if not value then fail("missing stable lab-productivity technology") end
  return value
end

local function assert_setting()
  local setting = settings.startup["mir-adjust-vanilla-weapon-speed-techs"]
  if not setting then fail("missing weapon overlap setting") end
  if setting.value ~= expected_mode then
    fail("weapon overlap mode was " .. tostring(setting.value) .. ", expected " .. expected_mode)
  end
end

script.on_init(function()
  if active_version() ~= from_version then fail("source save used " .. tostring(active_version())) end
  assert_setting()
  local force = game.forces.player
  force.research_all_technologies()
  local tech = technology()
  tech.level = 5
  if not force.add_research(tech) then fail("could not queue lab-productivity research") end
  force.research_progress = expected_progress
  global.mir = global.mir or {}
  global.mir.target_upgrade_fixture = {
    mode = expected_mode,
    technology_level = tech.level,
    research_progress = force.research_progress,
    runtime_marker = "factorio-1.1-global-state"
  }
  log("[mir-fixture] 1.9.3 upgrade source proof complete")
end)

script.on_configuration_changed(function()
  if active_version() ~= to_version then fail("upgraded save used " .. tostring(active_version())) end
  assert_setting()
  local state = global.mir and global.mir.target_upgrade_fixture
  if not state or state.runtime_marker ~= "factorio-1.1-global-state" then
    fail("global runtime state did not survive upgrade")
  end
  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then fail("technology level did not survive upgrade") end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("current research did not survive upgrade")
  end
  if math.abs((force.research_progress or 0) - state.research_progress) > epsilon then
    fail("fractional research progress did not survive upgrade")
  end
  log("[mir-fixture] 1.9.3 to 1.9.4 upgrade proof complete")
end)
