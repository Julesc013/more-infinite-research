script.on_init(function()
  local force = game.forces.player
  local technology = assert(force.technologies['recipe-prod-research_character_crafting_speed-1'])
  local before = force.manual_crafting_speed_modifier
  technology.researched = true
  local after = force.manual_crafting_speed_modifier
  assert(after > before, 'Completing MIR crafting research did not increase manual crafting speed')
  log('[mir-fixture] MIR-HISTORICAL-HANDCRAFTING-REWARD-PASS before=' .. before .. ' after=' .. after)
end)
