local technology_name = "mir-upgrade-reset-sentinel-technology"
local recipe_name = "mir-upgrade-reset-sentinel-recipe"
local custom_crafting_speed_modifier = 7.25

script.on_init(function()
  local force = game.forces.player
  local technology = force.technologies[technology_name]
  local recipe = force.recipes[recipe_name]
  if not technology or not recipe then error("MIR upgrade reset probe prototypes are missing") end
  technology.researched = true
  recipe.enabled = false
  storage.mir_upgrade_reset_probe = {
    configuration_changed = false
  }
end)

script.on_configuration_changed(function()
  local force = game.forces.player
  local recipe = force.recipes[recipe_name]
  if not recipe then error("MIR upgrade reset probe recipe is missing after configuration change") end
  storage.mir_upgrade_reset_probe = storage.mir_upgrade_reset_probe or {}
  storage.mir_upgrade_reset_probe.configuration_changed = true
  recipe.enabled = false
  force.manual_crafting_speed_modifier = custom_crafting_speed_modifier
end)

remote.add_interface("mir_upgrade_reset_probe", {
  snapshot = function()
    local state = storage.mir_upgrade_reset_probe or {}
    local recipe = game.forces.player.recipes[recipe_name]
    return {
      configuration_changed = state.configuration_changed == true,
      current_recipe_enabled = recipe and recipe.enabled,
      expected_crafting_speed_modifier = custom_crafting_speed_modifier,
      current_crafting_speed_modifier = game.forces.player.manual_crafting_speed_modifier
    }
  end
})
