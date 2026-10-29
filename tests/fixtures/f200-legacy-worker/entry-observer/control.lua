-- Private observation only. The native order diagnostic must establish that
-- this Base-only observer executes before MIR's configuration callback.
local WORKER = "worker-robots-speed-6"
local FOREIGN = "mir5-f200-legacy-worker-foreign"

local function read(force)
  local value = force and force.technologies[WORKER]
  if not value then return nil end
  return {index=force.index, name=force.name, level=value.level, researched=value.researched,
    enabled=value.enabled, visible=value.visible_when_disabled,
    bonus=force.worker_robots_speed_modifier, saved_progress=value.saved_progress}
end
local function copy(row)
  if row == nil then return nil end
  local out = {}
  for key, value in pairs(row) do out[key] = value end
  return out
end
script.on_configuration_changed(function()
  storage.entry = {schema=1, tick=game.tick, base=script.active_mods.base,
    mir=script.active_mods["more-infinite-research"],
    fixture=script.active_mods["mir-fixture-mir5-f200-legacy-worker"],
    observer=script.active_mods["a-mir-fixture-worker-entry"],
    player=read(game.forces.player), foreign=read(game.forces[FOREIGN])}
  log("[MIR_WORKER_NATIVE_ENTRY] " .. helpers.table_to_json(storage.entry))
end)
remote.add_interface("mir-fixture-worker-entry", {get=function()
  local entry = storage.entry
  if entry == nil then return nil end
  return {schema=entry.schema, tick=entry.tick, base=entry.base, mir=entry.mir,
    fixture=entry.fixture, observer=entry.observer, player=copy(entry.player), foreign=copy(entry.foreign)}
end})
