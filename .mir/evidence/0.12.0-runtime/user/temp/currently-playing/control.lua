require "defines"

normal_attack_sent_event = script.generate_event_name()
landing_attack_sent_event = script.generate_event_name()
remote.add_interface("freeplay",
{
  set_attack_data = function(data)
    global.attack_data = data
  end,

  get_attack_data = function()
    return global.attack_data
  end,

  get_normal_attack_sent_event = function()
    return normal_attack_sent_event
  end,
})

init_attack_data = function()
  global.attack_data = {
    -- whether all attacks are enabled
    enabled = true,
    -- this script is allowed to change the attack values attack_count and until_next_attack
    change_values = true,
    -- what distracts the creepers during the attack
    distraction = defines.distraction.byenemy,
    -- number of units in the next attack
    attack_count = 5,
    -- time to the next attack
    until_next_attack = 60 * 60 * 60,
  }
end

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  player.insert{name="iron-plate", count=8}
  player.insert{name="pistol", count=1}
  player.insert{name="basic-bullet-magazine", count=10}
  player.insert{name="burner-mining-drill", count = 1}
  player.insert{name="stone-furnace", count = 1}
  if (#game.players <= 1) then
    game.show_message_dialog{text = {"msg-intro"}}
  end
  player.force.chart(player.surface, {{player.position.x - 200, player.position.y - 200}, {player.position.x + 200, player.position.y + 200}})
end)

script.on_init(function()
  init_attack_data()
end)

-- for backwards compatibility
script.on_configuration_changed(function(data)
  if global.attack_data == nil then
    init_attack_data()
    if global.attack_count ~= nil then global.attack_data.attack_count = global.attack_count end
    if global.until_next_attacknormal ~= nil then global.attack_data.until_next_attack = global.until_next_attacknormal end
  end
  if global.attack_data.distraction == nil then global.attack_data.distraction = defines.distraction.byenemy end
  
end)

script.on_event(defines.events.on_rocket_launched, function(event)
  local force = event.rocket.force
  if event.rocket.get_item_count("satellite") > 0 then
    if global.satellite_sent == nil then
      global.satellite_sent = {}
    end
    if global.satellite_sent[force.name] == nil then
      game.set_game_state{game_finished=true, player_won=true, can_continue=true}
      global.satellite_sent[force.name] = 1
    else
      global.satellite_sent[force.name] = global.satellite_sent[force.name] + 1
    end
    for index, player in pairs(force.players) do
      if player.gui.left.rocket_score == nil then
        local frame = player.gui.left.add{name = "rocket_score", type = "frame", direction = "horizontal", caption={"score"}}
        frame.add{name="rocket_count_label", type = "label", caption={"", {"rockets-sent"}, ""}}
        frame.add{name="rocket_count", type = "label", caption="1"}
      else
        player.gui.left.rocket_score.rocket_count.caption = tostring(global.satellite_sent[force.name])
      end
    end
  else
    if (#game.players <= 1) then
      game.show_message_dialog{text = {"gui-rocket-silo.rocket-launched-without-satellite"}}
    else
      for index, player in pairs(force.players) do
        player.print({"gui-rocket-silo.rocket-launched-without-satellite"})
      end
    end
  end
end)
