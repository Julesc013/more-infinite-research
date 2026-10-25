-- Disposable native queue-bound passive-repair fixture for the explicitly
-- selected F200 or F210 profile.  It observes physical walls only; it never
-- reads or writes MIR's saved runtime state.
local KEY = "mir5_repair_stress"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-repair-stress"
local FRIENDLY = "mir5-repair-stress-friendly"
local FOREIGN = "mir5-repair-stress-foreign"

local TOTAL = 1000
local CAPACITY = 256
local OVERFLOW = TOTAL - CAPACITY
local BUDGET = 8
local QUIET_TICKS = 600
local SERVICE_TICKS = 60
local REPAIR_AMOUNT = 1
-- The native hit itself is the witness: each selected target must report an
-- exact one-point electric health reduction before repair observation starts.
local DAMAGE_AMOUNT = 1
local DAMAGE_TYPE = "electric"
local REACTIVATE_COUNT = 8

local loaded_snapshot, reload_logged = nil, false

local function fail(message) error("[mir5-repair-stress] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= 0.000001
end
local function valid(value) return value ~= nil and value.valid ~= false end

local function mode()
  local active = script.active_mods
  local f200 = active.base == "2.0.77" and active["space-age"] == nil
  local f210 = active.base == "2.1.23" and active["elevated-rails"] == "2.1.23"
    and active.quality == "2.1.23" and active.recycler == "2.1.23"
    and active["space-age"] == "2.1.23"
  if not f200 and not f210 then
    fail("fixture requires exact F200 Base 2.0.77 or F210 2.1.23 official closure")
  end
  local mir, fixture = active["more-infinite-research"], active[FIXTURE]
  if f200 and mir == "4.7.20002" and fixture == "0.1.0" then return "published-4.7.20002", "repair-stress" end
  if f200 and mir == "5.0.20000" and fixture == "0.2.0" then return "mir5-5.0.20000", "repair-stress" end
  if f210 and mir == "4.7.21002" and fixture == "0.1.0" then return "f210-published-4.7.21002", "repair-stress-f210" end
  if f210 and mir == "5.0.21000" and fixture == "0.2.0" then return "f210-mir5-5.0.21000", "repair-stress-f210" end
  fail("fixture requires target-matched published or MIR5 identity")
end

local function health(entity, label)
  if not valid(entity) or type(entity.health) ~= "number" or type(entity.max_health) ~= "number"
      or entity.max_health <= 0 then
    fail(label .. " native entity health is absent")
  end
  return entity.health, entity.max_health
end

local function damage_one(entity, label)
  local before, maximum = health(entity, label)
  local applied = entity.damage(DAMAGE_AMOUNT, game.forces.enemy, DAMAGE_TYPE)
  local after = health(entity, label)
  if not close(applied, REPAIR_AMOUNT) or not close(after, before - REPAIR_AMOUNT)
      or after <= 0 or after >= maximum then
    fail(label .. " native one-point electric damage did not apply exactly one health")
  end
  return after, maximum
end

local function damage_sentinel(entity, label)
  local before, maximum = health(entity, label)
  local applied = entity.damage(DAMAGE_AMOUNT, game.forces.enemy, DAMAGE_TYPE)
  local after = health(entity, label)
  if type(applied) ~= "number" or applied <= 0 or not close(after, before - applied)
      or after <= 0 or after >= maximum then
    fail(label .. " native electric damage witness is absent")
  end
  return after, maximum
end

local function create(surface, name, position, force, label)
  local entity = surface.create_entity{name = name, position = position, force = force}
  if not valid(entity) or entity.type == nil then fail(label .. " native entity could not be created") end
  return entity
end

local function first_service_tick(damage_tick)
  -- The subscription is globally aligned to the 60-tick clock.  A re-damage
  -- can happen between services, so its first eligible service is the first
  -- aligned tick at or after the quiet deadline, not damage_tick + 600.
  local quiet_until = damage_tick + QUIET_TICKS
  return math.ceil(quiet_until / SERVICE_TICKS) * SERVICE_TICKS
end

local function service_tick(damage_tick, observed_tick, label)
  local first = first_service_tick(damage_tick)
  if observed_tick < first then fail(label .. " repaired before the quiet period") end
  if (observed_tick - first) % SERVICE_TICKS == 0 then return observed_tick end
  -- Factorio can dispatch the fixture's on_tick observer before the 60-tick
  -- subscription; the next tick sees that same service write.
  if observed_tick > first and (observed_tick - 1 - first) % SERVICE_TICKS == 0 then return observed_tick - 1 end
  fail(label .. " repair did not occur on the 60-tick native service cadence")
end

local function record_changes(record, damage_tick, observed_tick, changed, label)
  if changed == 0 then return end
  if changed > BUDGET then fail(label .. " observed repair batch exceeded eight entities") end
  local service = service_tick(damage_tick, observed_tick, label)
  if record.last_service_tick ~= nil then
    if service - record.last_service_tick ~= SERVICE_TICKS then
      fail(label .. " native repair service cadence changed")
    end
  elseif service < damage_tick + QUIET_TICKS then
    fail(label .. " first native repair service was early")
  end
  record.first_observed_tick = record.first_observed_tick or observed_tick
  record.first_service_tick = record.first_service_tick or service
  record.last_service_tick = service
  record.services = record.services + 1
  record.changed = record.changed + changed
  record.maximum_batch = math.max(record.maximum_batch, changed)
end

local function observe_range(state, first, last, record, damage_tick, label)
  local all_full, changed = true, 0
  for index = first, last do
    local entry = state.eligible[index]
    local current, maximum = health(entry.entity, label .. " " .. tostring(index))
    if current < entry.observed_health - 0.000001 then fail(label .. " wall lost health after fixture damage") end
    if current > entry.observed_health + 0.000001 then
      if not close(current - entry.observed_health, REPAIR_AMOUNT) then
        fail(label .. " service changed more than one health on a wall")
      end
      changed = changed + 1
    end
    entry.observed_health = current
    if not close(current, maximum) then all_full = false end
  end
  record_changes(record, damage_tick, game.tick, changed, label)
  return all_full
end

local function assert_unchanged(entry, label)
  local current = health(entry.entity, label)
  if not close(current, entry.damaged_health) then fail(label .. " changed without a new native damage event") end
end

local function assert_overflow_and_sentinels(state)
  for index = CAPACITY + 1, TOTAL do
    assert_unchanged(state.eligible[index], "eligible overflow wall " .. tostring(index))
  end
  for index, entry in ipairs(state.foreign_walls) do
    assert_unchanged(entry, "nonfriendly wall sentinel " .. tostring(index))
  end
  assert_unchanged(state.nonwall, "non-wall sentinel")
end

local function assert_record(record, expected, label)
  if record.changed ~= expected or record.maximum_batch ~= BUDGET
      or record.services ~= expected / BUDGET or record.first_service_tick == nil
      or record.first_observed_tick == nil then
    fail(label .. " native queue service witness differs")
  end
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage, case = state.case, status = "passed",
    qualification = "native-runner-readback-required",
    witnesses = {
      mode = state.mode,
      total_eligible_walls = TOTAL,
      first_capacity_walls = CAPACITY,
      eligible_overflow_walls = OVERFLOW,
      first_capacity_player_walls = state.player_primary,
      first_capacity_reciprocal_friend_walls = state.friendly_primary,
      quiet_ticks = QUIET_TICKS,
      service_ticks = SERVICE_TICKS,
      repair_amount = REPAIR_AMOUNT,
      maximum_observed_repairs_per_service = state.initial_record.maximum_batch,
      initial_first_repair_observed_tick = state.initial_record.first_observed_tick,
      initial_first_repair_service_tick = state.initial_record.first_service_tick,
      reactivation_first_repair_observed_tick = state.reactivation_record.first_observed_tick,
      reactivation_first_repair_service_tick = state.reactivation_record.first_service_tick,
      reactivation_count = REACTIVATE_COUNT,
      overflow_unchanged = true,
      nonfriendly_unchanged = true,
      nonwall_unchanged = true,
      native_damage_api = "LuaEntity.damage",
      native_damage_type = DAMAGE_TYPE,
      on_load_read_only = stage == "reload",
      performance_qualified = false,
      runtime_elapsed_qualified = false,
      scope = state.case == "repair-stress-f210"
        and "disposable-f210-passive-repair-queue-bound-only"
        or "disposable-f200-passive-repair-queue-bound-only"
    }
  }))
end

local function complete_witness(state)
  assert_record(state.initial_record, CAPACITY, "initial 256-wall")
  assert_record(state.reactivation_record, REACTIVATE_COUNT, "reactivated")
  assert_overflow_and_sentinels(state)
  for index = 1, REACTIVATE_COUNT do
    local current, maximum = health(state.eligible[index].entity, "reactivated wall " .. tostring(index))
    if not close(current, maximum) then fail("reactivated wall did not heal") end
  end
end

local function redamage_drained_queue(state)
  state.reactivation_tick = game.tick
  state.reactivation_record = {changed = 0, services = 0, maximum_batch = 0}
  for index = 1, REACTIVATE_COUNT do
    local entry = state.eligible[index]
    local current, maximum = health(entry.entity, "reactivation source wall " .. tostring(index))
    if not close(current, maximum) then fail("initial queue had not drained before reactivation") end
    local damaged = damage_one(entry.entity, "reactivated wall " .. tostring(index))
    entry.observed_health = damaged
  end
  state.phase = "await-reactivation"
  state.deadline_tick = game.tick + QUIET_TICKS + SERVICE_TICKS * 4
end

script.on_init(function()
  local selected, selected_case = mode()
  if settings.startup["mir-enable-passive-repair"] == nil
      or settings.startup["mir-enable-passive-repair"].value ~= true then
    fail("passive-repair runtime setting is not enabled")
  end
  if storage[KEY] ~= nil then fail("fixture storage already exists") end

  local player, enemy = game.forces.player, game.forces.enemy
  if not valid(player) or not valid(enemy) then fail("native player or enemy force is absent") end
  local friendly = game.create_force(FRIENDLY)
  local foreign = game.create_force(FOREIGN)
  if not valid(friendly) or not valid(foreign) then fail("native fixture forces could not be created") end
  friendly.set_friend(player, true)
  player.set_friend(friendly, true)
  if friendly.get_friend(player) ~= true or player.get_friend(friendly) ~= true
      or foreign.get_friend(player) == true or player.get_friend(foreign) == true then
    fail("native reciprocal friendship setup differs")
  end

  local surface = game.surfaces[1]
  if not valid(surface) then fail("native surface is absent") end
  local eligible, player_primary, friendly_primary = {}, 0, 0
  for index = 1, TOTAL do
    local owner = index % 2 == 0 and friendly or player
    local entity = create(surface, "stone-wall", {x = 20 + (index - 1) % 40 * 2, y = 20 + math.floor((index - 1) / 40) * 2},
      owner, "eligible wall " .. tostring(index))
    local damaged_health, maximum = damage_one(entity, "eligible wall " .. tostring(index))
    eligible[index] = {entity = entity, damaged_health = damaged_health, observed_health = damaged_health, maximum = maximum}
    if index <= CAPACITY then
      if owner == player then player_primary = player_primary + 1 else friendly_primary = friendly_primary + 1 end
    end
  end
  if player_primary ~= CAPACITY / 2 or friendly_primary ~= CAPACITY / 2 then
    fail("first queue capacity did not include equal player and reciprocal-friendly walls")
  end

  local foreign_walls = {}
  for index = 1, 2 do
    local entity = create(surface, "stone-wall", {x = 104 + index * 2, y = 20}, foreign,
      "nonfriendly wall sentinel " .. tostring(index))
    local damaged_health, maximum = damage_one(entity, "nonfriendly wall sentinel " .. tostring(index))
    foreign_walls[index] = {entity = entity, damaged_health = damaged_health, maximum = maximum}
  end
  local nonwall_entity = create(surface, "wooden-chest", {x = 114, y = 24}, player, "non-wall sentinel")
  local nonwall_health, nonwall_maximum = damage_sentinel(nonwall_entity, "non-wall sentinel")

  storage[KEY] = {
    phase = "await-initial", mode = selected, case = selected_case, eligible = eligible, foreign_walls = foreign_walls,
    nonwall = {entity = nonwall_entity, damaged_health = nonwall_health, maximum = nonwall_maximum},
    player_primary = player_primary, friendly_primary = friendly_primary, damage_tick = game.tick,
    initial_record = {changed = 0, services = 0, maximum_batch = 0},
    deadline_tick = game.tick + QUIET_TICKS + SERVICE_TICKS * (CAPACITY / BUDGET + 4)
  }
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and state.phase == "completed" then
    -- This callback reads fixture-owned scalar facts only.  Native entities
    -- and durable storage are checked on the first game-available tick.
    loaded_snapshot = {
      mode = state.mode, case = state.case, initial_changed = state.initial_record and state.initial_record.changed,
      reactivation_changed = state.reactivation_record and state.reactivation_record.changed,
      initial_service = state.initial_record and state.initial_record.first_service_tick,
      reactivation_service = state.reactivation_record and state.reactivation_record.first_service_tick
    }
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("fixture state is absent") end
  if state.phase ~= "completed" and game.tick > state.deadline_tick then
    fail("native passive-repair queue did not settle before its bounded deadline")
  end

  if state.phase == "await-initial" then
    if observe_range(state, 1, CAPACITY, state.initial_record, state.damage_tick, "initial queue") then
      assert_record(state.initial_record, CAPACITY, "initial 256-wall")
      assert_overflow_and_sentinels(state)
      redamage_drained_queue(state)
    end
    return
  end

  if state.phase == "await-reactivation" then
    if observe_range(state, 1, REACTIVATE_COUNT, state.reactivation_record, state.reactivation_tick, "reactivated queue") then
      complete_witness(state)
      state.phase = "completed"
      marker("initial", state)
      game.server_save(SAVE)
    end
    return
  end

  if state.phase == "completed" then
    if loaded_snapshot and not reload_logged then
      if loaded_snapshot.mode ~= state.mode or loaded_snapshot.case ~= state.case or loaded_snapshot.initial_changed ~= state.initial_record.changed
          or loaded_snapshot.reactivation_changed ~= state.reactivation_record.changed
          or loaded_snapshot.initial_service ~= state.initial_record.first_service_tick
          or loaded_snapshot.reactivation_service ~= state.reactivation_record.first_service_tick then
        fail("on_load changed a saved scalar witness")
      end
      complete_witness(state)
      marker("reload", state)
      reload_logged = true
    end
    return
  end

  fail("unknown fixture phase " .. tostring(state.phase))
end)
