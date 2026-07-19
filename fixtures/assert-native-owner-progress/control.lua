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
  if not remote.interfaces["mir-native-owner-reset-safety"] then
    fail("reset-safety source interface is absent during initialization")
  end
  remote.call("mir-native-owner-reset-safety", "seal_initial_inventory")
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
  if not remote.interfaces["mir-native-owner-reset-safety"] then
    fail("reset-safety source interface is absent")
  end
  local reset_snapshot = remote.call("mir-native-owner-reset-safety", "configuration_snapshot")
  local player = game.get_player(1)
  local token_count = player and player.get_item_count("mir-reset-safety-token") or 0
  local reset_recipe = force.recipes["mir-reset-safety-recipe"]
  if not reset_snapshot.configuration_change_seen then
    fail("reset-safety source did not observe configuration change before MIR")
  end
  if reset_snapshot.player_inventory_available
    and reset_snapshot.token_count_before_mir ~= reset_snapshot.initial_token_count then
    fail("external give-item inventory changed before MIR configuration handling")
  end
  if reset_snapshot.player_inventory_available and token_count ~= reset_snapshot.token_count_before_mir then
    fail("MIR duplicated an external give-item effect during configuration change")
  end
  if reset_snapshot.recipe_enabled_after_override ~= false or not reset_recipe or reset_recipe.enabled ~= false then
    fail("MIR lost another mod's configuration-change recipe state")
  end
  log("[mir-fixture] native-owner force-state preservation proof complete"
    .. " player_inventory_asserted=" .. tostring(reset_snapshot.player_inventory_available))
  log("[mir-fixture] native-owner progress configuration-change proof complete")
end)
