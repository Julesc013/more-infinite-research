-- Native order must be observed independently. No MIR dependency: this
-- explicitly delegated fixture owner must act before MIR configuration.
local FOREIGN = "mir5-k2se-imersite-carrier-foreign"
local EARLY = "mir-k2-imersite-staged-state-1"
local TAIL = "mir-k2-imersite-continuation-state-4"
local function fail(message) error("[mir-k2se-early-owner] " .. message) end

script.on_configuration_changed(function()
  if script.active_mods["a-mir-fixture-k2se-foreign-owner"] ~= "0.1.0"
      or script.active_mods["mir-fixture-mir5-k2se-imersite-carrier-retention"] ~= "0.3.0"
      or storage.report ~= nil then fail("unexpected or repeated fixture-owner configuration") end
  local entry = remote.call("mir-k2se-fixture-seed", "preflight")
  local force = game.forces[FOREIGN]
  if type(entry) ~= "table" or entry.schema ~= 1 or entry.tick ~= game.tick
      or not force or entry.foreign_index ~= force.index or entry.foreign_name ~= FOREIGN
      or entry.source_mir ~= "4.7.21003" or entry.source_fixture ~= "0.1.0"
      or entry.seed_kind ~= "native-saved-state-not-lab-earned"
      or type(entry.early_enabled) ~= "boolean" or entry.early_enabled ~= entry.tail_enabled then
    fail("source owner preflight differs")
  end
  local early, tail = force.technologies[EARLY], force.technologies[TAIL]
  if early.enabled ~= entry.early_enabled or tail.enabled ~= entry.tail_enabled then
    fail("foreign flags changed since read-only preflight")
  end
  if entry.early_enabled then early.enabled, tail.enabled = false, false end
  storage.report = {schema=1, tick=game.tick, foreign_index=force.index, foreign_name=force.name,
    source_mir=entry.source_mir, source_fixture=entry.source_fixture, owner_version="0.1.0",
    initial_enabled=entry.early_enabled, reasserted=entry.early_enabled, enabled_after_owner=false}
  log("[MIR_K2SE_EARLY_OWNER] " .. helpers.table_to_json(storage.report))
end)

remote.add_interface("mir-k2se-foreign-owner", {get=function()
  if storage.report == nil then return nil end
  local copy = {}
  for key, value in pairs(storage.report) do copy[key] = value end
  return copy
end})
