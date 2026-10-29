-- This fixture owns the +0.123 it recorded in its original source storage.
-- MIR never reads this ledger. Reconcile only after the independent entry
-- observer and all original native/foreign assertions pass without writes.
local M = {}
local AMOUNT, MODIFIER = .123, .65
local FIXTURE = "mir-fixture-mir5-f200-legacy-worker"
local function fail(message) error("[mir-worker-fixture-offset-owner] " .. message) end
local function close(a, b)
  return type(a) == "number" and type(b) == "number" and a == a and b == b and math.abs(a - b) < 1e-9
end

function M.reconcile(state, entry, world, mods, startup, assert_restored, stage, assert_held_inventory)
  local holding, relaxing = stage == "hold", stage == "relax"
  if stage ~= nil and not holding and not relaxing then fail("unknown finite fixture stage") end
  if type(state) ~= "table" or state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0"
      or state.actual_lab_completions ~= 2 or state.milestone ~= "actual2labs"
      or type(state.player_cap) ~= "table" or type(state.player_baseline) ~= "number"
      or type(state.player_with_independent) ~= "number" or not state.lab or state.lab.valid == false then
    fail("requires the original two-lab source")
  end
  if relaxing then
    local held, offset = state.finite_hold_witness, state.fixture_owned_offset
    if state.phase ~= "finite-held" or state.destination_lab_completions ~= 0
        or type(held) ~= "table" or held.schema ~= 1 or held.maximum ~= 7 or held.level ~= 8
        or held.enabled ~= false or held.visible ~= true or not close(held.bonus, 3.823)
        or not close(held.saved_progress, .27) or type(held.science_units) ~= "table"
        or type(offset) ~= "table" or offset.schema ~= 1 or offset.stage ~= "hold"
        or not close(offset.amount, AMOUNT) or not close(offset.restored_total, 3.823)
        or not close(offset.source_total, 3.823) or type(offset.native_entry_tick) ~= "number"
        or not ((close(offset.native_entry_total, 3.7) and close(offset.reapplied, AMOUNT))
          or (close(offset.native_entry_total, 3.823) and close(offset.reapplied, 0))) then
      fail("requires the exact completed finite hold and owned contribution proof")
    end
  elseif state.phase ~= "completed" or state.destination_lab_completions ~= nil
      or state.fixture_owned_offset ~= nil or state.finite_hold_witness ~= nil then
    fail("requires the original source and no prior fixture-owner reconciliation")
  end
  -- Runtime settings expose native read-only facades, not necessarily plain
  -- Lua tables. Check the named API values without misclassifying that facade.
  local maximum = startup and startup["mir-max-level-worker-robots-speed"]
  local profile = startup and startup["mir-settings-profile-import"]
  log("[MIR5_NATIVE_FIXTURE] DIAGNOSTIC " .. helpers.table_to_json({stage="fixture-owner-preflight",
    startup_type=type(startup), maximum_type=type(maximum), profile_type=type(profile),
    maximum=maximum and maximum.value or false, profile_import_empty=profile and profile.value == "" or false}))
  local f200_role = holding and "0.5.0" or (relaxing and "0.6.0" or "0.3.0")
  local f210_role = holding and "0.7.0" or (relaxing and "0.8.0" or "0.4.0")
  local f200 = mods.base == "2.0.77" and mods["more-infinite-research"] == "5.0.20000" and mods[FIXTURE] == f200_role
  local f210 = mods.base == "2.1.23" and mods["more-infinite-research"] == "5.0.21000" and mods[FIXTURE] == f210_role
  if not maximum or not profile or not (f200 or f210) or mods["space-age"] ~= nil
      or mods["a-mir-fixture-worker-entry"] ~= "0.1.0"
      or maximum.value ~= (holding and 7 or 40) or profile.value ~= "" then fail("exact fixture-owner closure/settings differ") end
  local expected = state.player_with_independent + 2 * MODIFIER
  if not close(state.player_baseline, 2.4) or not close(state.foreign_baseline, 2.4)
      or not close(state.player_with_independent - state.player_baseline, AMOUNT)
      or not close(state.player_cap.bonus, expected) then fail("persisted fixture contribution differs") end
  if type(entry) ~= "table" or entry.schema ~= 1 or entry.tick ~= world.tick
      or entry.base ~= mods.base or entry.mir ~= mods["more-infinite-research"]
      or entry.fixture ~= mods[FIXTURE] or entry.observer ~= mods["a-mir-fixture-worker-entry"]
      or type(entry.player) ~= "table" or type(entry.foreign) ~= "table" then
    fail("independent native entry observation is absent or stale")
  end
  local player, foreign = world.forces.player, world.forces[state.foreign_force_index]
  if not player or not foreign or entry.player.index ~= player.index or entry.player.name ~= player.name
      or entry.foreign.index ~= foreign.index or entry.foreign.name ~= foreign.name
      or foreign.name ~= "mir5-f200-legacy-worker-foreign" or entry.player.level ~= 8
      or entry.player.researched ~= false or not close(entry.player.saved_progress, .27)
      or entry.foreign.level ~= 6 or entry.foreign.researched ~= false
      or entry.foreign.enabled ~= false or entry.foreign.visible ~= false
      or not close(entry.foreign.bonus, state.foreign_baseline) then fail("native entry identity/state differs") end
  if not close(player.worker_robots_speed_modifier, entry.player.bonus)
      or not close(foreign.worker_robots_speed_modifier, entry.foreign.bonus) then
    fail("aggregate changed between independent entry and fixture owner")
  end
  local amount
  if close(entry.player.bonus, expected) then amount = 0
  elseif close(entry.player.bonus, expected - AMOUNT) then amount = AMOUNT
  else fail("native entry contains an unknown aggregate difference") end
  -- Reuse every original read-only native-owner, earned level, work, foreign
  -- queue and effect assertion against the independently observed aggregate.
  assert_restored(state, entry.player.bonus, not holding)
  if relaxing then
    -- A held-save witness does not authorize changing science inventory. The
    -- stage's caller checks all six held counts before this owned write too.
    if type(assert_held_inventory) ~= "function" then fail("held inventory preflight is absent") end
    assert_held_inventory(state)
  end
  if amount ~= 0 then player.worker_robots_speed_modifier = player.worker_robots_speed_modifier + amount end
  if not close(player.worker_robots_speed_modifier, expected) then fail("fixture-owned contribution did not restore") end
  state.fixture_owned_offset = {schema=1, amount=AMOUNT, reapplied=amount,
    native_entry_total=entry.player.bonus, restored_total=player.worker_robots_speed_modifier,
    native_entry_tick=entry.tick, source_total=state.player_cap.bonus, stage=stage}
  return state.fixture_owned_offset
end
return M
