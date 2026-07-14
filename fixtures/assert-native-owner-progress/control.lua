local technology_name = "low-density-structure-productivity"
local expected_progress = 0.42
local epsilon = 0.000001

local function fail(message)
  error("MIR native-owner progress validation failed: " .. message)
end

local function technology()
  local value = game.forces.player.technologies[technology_name]
  if not value then fail("missing low-density-structure productivity technology") end
  return value
end

script.on_init(function()
  local force = game.forces.player
  local tech = technology()
  force.research_all_technologies()
  tech.level = 5
  if not force.add_research(tech) then fail("could not queue native-owner research") end
  force.research_progress = expected_progress
  storage.mir_native_owner_progress_fixture = {
    technology_level = tech.level,
    research_progress = force.research_progress
  }
  log("[mir-fixture] native-owner progress source proof complete")
end)

script.on_configuration_changed(function()
  local state = storage.mir_native_owner_progress_fixture
  if not state then fail("fixture storage did not survive configuration change") end
  local force = game.forces.player
  local tech = technology()
  if tech.level ~= state.technology_level then
    fail("native-owner technology level did not survive configuration change")
  end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("current native-owner research did not survive configuration change")
  end
  if math.abs((force.research_progress or 0) - state.research_progress) > epsilon then
    fail("native-owner research progress was " .. tostring(force.research_progress)
      .. ", expected " .. tostring(state.research_progress))
  end
  log("[mir-fixture] native-owner progress configuration-change proof complete")
end)
