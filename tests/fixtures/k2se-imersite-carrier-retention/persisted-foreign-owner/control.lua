-- Exact private source89023 owns this named force and the two deliberately
-- seeded locks. This is not a reader for arbitrary player/foreign provenance.
local successor = require("successor-control")
local KEY = "mir5_k2se_imersite_carrier_retention"
local FIXTURE = "mir-fixture-mir5-k2se-imersite-carrier-retention"
local OWNER = "a-mir-fixture-k2se-foreign-owner"
local FOREIGN = "mir5-k2se-imersite-carrier-foreign"
local EARLY = "mir-k2-imersite-staged-state-1"
local TAIL = "mir-k2-imersite-continuation-state-4"

local function fail(message) error("[mir-k2se-fixture-owner] " .. message) end
local function source_contract()
  local active, state = script.active_mods, storage[KEY]
  if active.base ~= "2.1.23" or active.Krastorio2 ~= "2.1.4"
      or active["space-exploration"] ~= "0.7.63" or active["Krastorio2-spaced-out"] ~= nil
      or active["more-infinite-research"] ~= "5.0.21000"
      or active[FIXTURE] ~= "0.3.0" or active[OWNER] ~= "0.1.0"
      or type(state) ~= "table" or state.phase ~= "source-complete"
      or state.source_mir ~= "4.7.21003" or state.fixture_version ~= "0.1.0"
      or state.foreign_force ~= FOREIGN or state.seed_kind ~= "native-saved-state-not-lab-earned"
      or state.actual_lab_completions ~= 0 or state.k2so_runtime_bridge_exercised ~= false
      or state.fixture_foreign_owner ~= nil then
    fail("exact original fixture source/closure differs")
  end
  return state
end

remote.add_interface("mir-k2se-fixture-seed", {preflight=function()
  source_contract()
  local foreign = game.forces[FOREIGN]
  local early = foreign and foreign.technologies[EARLY]
  local tail = foreign and foreign.technologies[TAIL]
  if not early or not tail or type(early.enabled) ~= "boolean"
      or type(tail.enabled) ~= "boolean" or early.enabled ~= tail.enabled then
    fail("unexpected native foreign flag combination")
  end
  -- Complete original level/effect/settings/work/player/foreign checks are
  -- read-only here. Only the two observed enabled flags may be native-reset.
  successor.assert_retained("fixture owner before any write", early.enabled)
  return {schema=1, tick=game.tick, foreign_index=foreign.index, foreign_name=foreign.name,
    source_mir="4.7.21003", source_fixture="0.1.0", seed_kind="native-saved-state-not-lab-earned",
    early_enabled=early.enabled, tail_enabled=tail.enabled}
end})

script.on_configuration_changed(function(event)
  source_contract()
  local report = remote.call("mir-k2se-foreign-owner", "get")
  local foreign = game.forces[FOREIGN]
  if type(report) ~= "table" or report.schema ~= 1 or report.tick ~= game.tick
      or report.foreign_name ~= FOREIGN or report.foreign_index ~= foreign.index
      or report.owner_version ~= "0.1.0" or report.source_mir ~= "4.7.21003"
      or report.source_fixture ~= "0.1.0" or type(report.reasserted) ~= "boolean"
      or type(report.initial_enabled) ~= "boolean" or report.reasserted ~= report.initial_enabled
      or report.enabled_after_owner ~= false then
    fail("fresh before-MIR fixture-owner witness differs")
  end
  -- These original strict false assertions run AFTER MIR configuration and
  -- before this successor changes phase or stores its detached witness.
  successor.assert_retained("after MIR before successor fixture write")
  successor.configuration_changed(event, "0.3.0")
  local copy = {}
  for key, value in pairs(report) do copy[key] = value end
  storage[KEY].fixture_foreign_owner = copy
end)
