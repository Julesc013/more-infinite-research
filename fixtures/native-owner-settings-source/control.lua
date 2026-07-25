local interface_name = "mir-native-owner-reset-safety"
local snapshot = {configuration_change_seen = false}

local function player()
  return game.get_player(1)
end

local function token_count()
  local value = player()
  return value and value.get_item_count("mir-reset-safety-token") or 0
end

remote.add_interface(interface_name, {
  seal_initial_inventory = function()
    snapshot.player_inventory_available = player() ~= nil
    snapshot.initial_token_count = token_count()
    storage.mir_reset_safety_initial_token_count = snapshot.initial_token_count
    storage.mir_reset_safety_player_inventory_available = snapshot.player_inventory_available
    return snapshot.initial_token_count
  end,
  configuration_snapshot = function()
    return {
      configuration_change_seen = snapshot.configuration_change_seen,
      player_inventory_available = snapshot.player_inventory_available,
      initial_token_count = snapshot.initial_token_count,
      token_count_before_mir = snapshot.token_count_before_mir,
      recipe_enabled_after_override = snapshot.recipe_enabled_after_override
    }
  end
})

script.on_init(function()
  local technology = game.forces.player.technologies["mir-external-give-item-technology"]
  if not technology then error("MIR reset-safety fixture technology is absent") end
  technology.researched = true
  snapshot.player_inventory_available = player() ~= nil
  snapshot.initial_token_count = token_count()
  storage.mir_reset_safety_initial_token_count = snapshot.initial_token_count
  storage.mir_reset_safety_player_inventory_available = snapshot.player_inventory_available
end)

script.on_configuration_changed(function()
  local force = game.forces.player
  local recipe = force.recipes["mir-reset-safety-recipe"]
  if not recipe then error("MIR reset-safety fixture recipe is absent") end
  snapshot.initial_token_count = storage.mir_reset_safety_initial_token_count
  snapshot.player_inventory_available = storage.mir_reset_safety_player_inventory_available == true
  snapshot.configuration_change_seen = true
  snapshot.token_count_before_mir = token_count()
  if snapshot.player_inventory_available and snapshot.token_count_before_mir ~= snapshot.initial_token_count then
    error("MIR reset-safety fixture external give-item effect was reapplied during configuration change")
  end
  recipe.enabled = false
  snapshot.recipe_enabled_after_override = recipe.enabled
  log("[mir-fixture] external configuration-change state prepared before MIR")
end)
