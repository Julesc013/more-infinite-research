local from_version = "1.3.0"
local to_version = "1.3.5"
local technology_name = "recipe-prod-research_rocket_shooting_speed-1"
local expected_progress = 0.42
local epsilon = 0.000001

local function fail(message)
  error("MIR 1.3.0 to 1.3.5 retention validation failed: " .. message)
end

local function active_version()
  return game.active_mods["more-infinite-research"]
end

local function technology()
  local value = game.forces.player.technologies[technology_name]
  if not value then fail("missing stable rocket-shooting-speed technology") end
  return value
end

script.on_init(function()
  if active_version() ~= from_version then fail("source save used " .. tostring(active_version())) end
  local force = game.forces.player
  force.research_all_technologies()
  local tech = technology()
  tech.researched = false
  force.current_research = technology_name
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("could not select rocket-shooting-speed research")
  end
  force.research_progress = expected_progress
  global.mir = global.mir or {}
  global.mir.target_upgrade_fixture = {
    technology_researched = tech.researched,
    research_progress = force.research_progress,
    runtime_marker = "factorio-0.13-global-state"
  }
  log("[mir-fixture] 1.3.0 upgrade source proof complete")
end)

script.on_configuration_changed(function()
  if active_version() ~= to_version then fail("upgraded save used " .. tostring(active_version())) end
  local state = global.mir and global.mir.target_upgrade_fixture
  if not state or state.runtime_marker ~= "factorio-0.13-global-state" then
    fail("global runtime state did not survive upgrade")
  end
  local force = game.forces.player
  local tech = technology()
  if tech.researched ~= state.technology_researched then fail("technology completion state did not survive upgrade") end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("current research did not survive upgrade")
  end
  if math.abs((force.research_progress or 0) - state.research_progress) > epsilon then
    fail("fractional research progress did not survive upgrade")
  end
  log("[mir-fixture] 1.3.0 to 1.3.5 upgrade proof complete")
end)
