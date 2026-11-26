-- Control entry point for the private preparation mod built by build_worker_storage_preparation.py.
local checkpoint = require("research.worker_storage_checkpoint")
local original = require("profile")
local MIR = "more-infinite-research"

remote.add_interface(checkpoint.preparation_mod, {checkpoint=function() return storage[checkpoint.key] end})
local version = script.active_mods[MIR]
local legacy = version == checkpoint.legacy_mir
if not legacy and not (type(version) == "string" and version:match("^5%.0%.200%d%d$")) then return end
local function watch_addon_preparation()
  local saved = storage[checkpoint.key]
  script.on_event(defines.events.on_tick, saved and saved.purpose == "addon-change" and function(event)
    if event.tick - saved.tick <= 1 then return end
    storage[checkpoint.key] = nil
    script.on_event(defines.events.on_tick, nil)
  end or nil)
end
if legacy then
  script.on_configuration_changed(function(event)
    if event.mod_startup_settings_changed then storage.mir_preparation_configuration_changed = true end
    for name, change in pairs(event.mod_changes) do
      if name ~= checkpoint.preparation_mod and change.old_version ~= change.new_version then
        storage.mir_preparation_configuration_changed = true
      end
    end
  end)
else
  script.on_load(watch_addon_preparation)
  script.on_configuration_changed(watch_addon_preparation)
end
local operation, identity = legacy and "prepare" or "prepare-addon-change", legacy and checkpoint.canonical_worker or checkpoint.ordinary_worker
local help = "Administrator or server. Usage: /mir-prepare-legacy-worker <" .. operation .. "|cancel>."
commands.add_command("mir-prepare-legacy-worker", help, function(command)
  local player = command.player_index and game.get_player(command.player_index)
  local function say(message)
    if player then player.print(message) else log("[MIR worker preparation] " .. message) end
  end
  if command.player_index and not (player and player.admin) then say(help); return end
  local saved = storage[checkpoint.key]
  if command.parameter == "cancel" and saved and saved.mir == version then
    game.tick_paused, storage[checkpoint.key] = saved.was_paused, nil
    if not legacy then watch_addon_preparation() end
    say("Cancelled the worker preparation.")
  elseif command.parameter == operation then
    if storage.mir_preparation_configuration_changed or not checkpoint.matches_preparation_selection(script.active_mods, original) then
      say("The old mod selection or startup settings changed. Return to the verified original copy.")
      return
    end
    local ok, state = pcall(checkpoint.capture, function(_, technology) return technology.saved_progress end, identity)
    if not ok then say(state); return end
    local formula = prototypes.technology[identity].research_unit_count_formula
    if type(formula) ~= "string" or formula == "" or #formula > 1024 then
      say("The original infinite worker research formula is unavailable.")
      return
    end
    state.formula, state.source_mods = formula, original
    if not legacy then
      local holder = prototypes.technology["mir-worker-storage-prepared-paid-4"]
      if not holder or holder.research_unit_count_formula ~= formula then
        say("The worker preparation archive must include the previous research price.")
        return
      end
      state.purpose, state.source_mods = "addon-change", {}
      for name, active_version in pairs(script.active_mods) do state.source_mods[name] = active_version end
    end
    if saved and saved.mir == version then state.was_paused = saved.was_paused end
    game.tick_paused, storage[checkpoint.key] = true, state
    if not legacy then watch_addon_preparation() end
    say("Worker research recorded. Save this paused copy under a new name and exit.")
  else
    say(help)
  end
end)
