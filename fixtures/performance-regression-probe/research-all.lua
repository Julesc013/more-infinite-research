-- Used only by the MIR-owned research-all observation fixture. The ordinary
-- compiler-phase probe does not import this file or mutate runtime research.
local completions = 0
script.on_event(defines.events.on_research_finished, function(event)
  if event.research.force == game.forces.player then completions = completions + 1 end
end)
script.on_init(function() storage.research_all_observations = {} end)
script.on_nth_tick(1, function()
  local rows = storage.research_all_observations
  local phase = #rows == 0 and "first" or "repeat"
  assert(#rows < 2, "research-all observation already completed")
  local force = game.forces.player
  local technologies = 0
  for _ in pairs(force.technologies) do technologies = technologies + 1 end
  assert(technologies > 0 and #game.connected_players == 0, "expected private headless research state")
  completions = 0
  local timer = helpers.create_profiler()
  force.research_all_technologies()
  timer.stop()
  assert(completions > 0, "research-all did not raise completion events")
  -- Lua deliberately cannot read nondeterministic profiler durations. Keep the
  -- engine-rendered measurement in the log and join it outside the game.
  log({"", "[mir-research-all] ", phase, "=", timer})
  rows[#rows + 1] = {phase = phase, completion_events = completions, technologies = technologies}
  if #rows == 2 then
    script.on_nth_tick(1, nil)
    helpers.write_file("research-all.json", helpers.table_to_json{
      schema = 1, status = "observed", engine = helpers.game_version,
      mir_version = script.active_mods["more-infinite-research"], connected_players = #game.connected_players,
      observations = rows
    }, false)
  end
end)
