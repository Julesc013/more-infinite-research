script.on_init(function()
  local technology = game.forces.player.technologies["processing-unit-productivity"]
  if not technology or technology.prototype.max_level ~= 9 then
    error("late native-owner maximum-level fixture mutation did not survive finalization")
  end
  log("[mir-fixture] late native-owner maximum-level mutation observed final=9")
end)
