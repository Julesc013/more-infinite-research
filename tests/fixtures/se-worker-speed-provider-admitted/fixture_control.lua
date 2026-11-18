local M = {}

local fixture = require("__mir-fixture-se-worker-speed-provider-admitted__/prerequisites")
local FIXTURE, MIR = "mir-fixture-se-worker-speed-provider-admitted", "more-infinite-research"
local KEY = "mir5_se_worker_speed_provider_admitted"
local WORKER, PREDECESSOR, DEEP = "worker-robots-speed-10", "worker-robots-speed-9", "se-deep-space-science-pack-1"
local CURRENT, QUEUED = "mir-fixture-se-worker-speed-provider-unrelated", "mir-fixture-se-worker-speed-provider-queued"
local FOREIGN, EARNED = "mir5-se-worker-speed-provider-foreign", "mir5-se-worker-speed-provider-earned"
local LAB = "mir-fixture-se-worker-speed-provider-lab"
local CAP = "mir-max-level-worker-robots-speed"
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack",
  "space-science-pack", "se-rocket-science-pack", "se-energy-science-pack-4", "se-deep-space-science-pack-1"}
local STAGES = {
  source = {fixture = "0.1.0", mir = "5.0.20015", cap = 0},
  admission = {fixture = "0.2.0", mir = "5.0.20015", cap = 0},
  old = {fixture = "0.3.0", mir = "5.0.20015", cap = 10},
  candidate = {fixture = "0.4.0", mir = "5.0.20018", cap = 10},
}
local CLOSURE = {
  base = "2.0.77", ["space-exploration"] = "0.7.57", ["aai-containers"] = "0.3.2",
  ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4", ["alien-biomes-graphics"] = "0.7.1",
  jetpack = "0.4.17", robot_attrition = "0.6.6", ["shield-projector"] = "0.2.2",
  ["space-exploration-graphics"] = "0.7.5", ["space-exploration-graphics-2"] = "0.7.2",
  ["space-exploration-graphics-3"] = "0.7.2", ["space-exploration-graphics-4"] = "0.7.2",
  ["space-exploration-graphics-5"] = "0.7.3", ["space-exploration-menu-simulations"] = "0.7.4",
  ["space-exploration-postprocess"] = "0.7.5", informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3",
}
local stage, cold_pending, cold_emitted

local function fail(message) error("[se-worker-speed-provider] " .. message) end
local function check(value, message) if not value then fail(message) end end
local function close(left, right) return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.0000001 end
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, item in pairs(left) do if not same(item, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function active_tuple()
  local rows = {}; for name, version in pairs(script.active_mods) do rows[#rows + 1] = name .. "@" .. version end
  table.sort(rows); return table.concat(rows, "|")
end

local function assert_active(expected_stage)
  local expected = STAGES[expected_stage]
  check(expected ~= nil, "unknown fixture stage")
  local count = 0
  for name, version in pairs(CLOSURE) do check(script.active_mods[name] == version, "SE tuple differs: " .. name); count = count + 1 end
  for name in pairs(script.active_mods) do
    check(name == FIXTURE or name == MIR or CLOSURE[name] ~= nil, "unexpected active mod: " .. name)
  end
  check(script.active_mods[FIXTURE] == expected.fixture and script.active_mods[MIR] == expected.mir, "fixture or MIR stage differs")
  check((function() local n=0; for _ in pairs(script.active_mods) do n=n+1 end; return n end)() == count + 2, "active mod count differs")
  local setting = settings.startup and settings.startup[CAP]
  check(type(setting) == "table" and setting.value == expected.cap, "worker-speed cap differs")
  return expected
end

local function technology(force, name)
  check(force and force.valid ~= false and type(force.technologies) == "table", "force technologies unavailable")
  local row = force.technologies[name]
  check(row and row.valid ~= false and row.name == name, "technology is absent: " .. name)
  return row
end

local function parent_names(row)
  local names, seen = {}, {}
  for key, value in pairs(row.prerequisites or {}) do
    local name = type(key) == "string" and key or (type(value) == "table" and value.name)
    check(type(name) == "string" and name ~= "" and not seen[name], "technology parent shape differs")
    seen[name], names[#names + 1] = true, name
  end
  table.sort(names); return names
end

local function expected_parents(row)
  local names = copy(row.parents); table.sort(names); return names
end

local function assert_fixed_contract(force, label)
  for _, declared in ipairs(fixture.rows) do
    local row = technology(force, declared.name)
    check(row.prototype ~= nil and row.prototype.max_level ~= "infinite", label .. " finite row differs: " .. declared.name)
    check(same(parent_names(row), expected_parents(declared)), label .. " direct parents differ: " .. declared.name)
  end
  for name, modifier in pairs(fixture.expected_worker_effects) do
    local row = technology(force, name)
    local effects = row.prototype and row.prototype.effects
    check(type(effects) == "table" and #effects == 1 and effects[1].type == "worker-robot-speed"
      and close(effects[1].modifier, modifier), label .. " worker-speed effect differs: " .. name)
  end
  local target = technology(force, WORKER)
  check(target.prototype and target.prototype.max_level == "infinite", label .. " worker target is not infinite")
  check(same(parent_names(target), {DEEP, PREDECESSOR}), label .. " worker target direct parents differ")
end

local function assert_declared_order(label)
  local seen = {}
  for _, declared in ipairs(fixture.rows) do
    check(not seen[declared.name], label .. " duplicate declared row: " .. declared.name)
    for _, parent in ipairs(declared.parents) do
      if fixture.by_name[parent] ~= nil then
        check(seen[parent] == true, label .. " declared order differs: " .. declared.name)
      end
    end
    seen[declared.name] = true
  end
end

local function completed_rows(force, label)
  local rows, order = {}, {}
  for _, declared in ipairs(fixture.rows) do
    local value = technology(force, declared.name)
    check(value.researched == true and value.saved_progress == 0, label .. " completed prerequisite differs: " .. declared.name)
    rows[declared.name] = {level = value.level, researched = value.researched, enabled = value.enabled,
      visible = value.visible_when_disabled, saved = value.saved_progress}
    order[#order + 1] = declared.name
  end
  return rows, order
end

local function queue_names(force)
  local names = {}
  for _, value in ipairs(force.research_queue or {}) do
    local name = type(value) == "string" and value or value.name
    check(type(name) == "string", "research queue row differs")
    names[#names + 1] = name
  end
  return names
end

local function worker_row(force, label)
  local worker = technology(force, WORKER)
  check(worker.saved_progress == 0, label .. " worker saved progress differs")
  local current = force.current_research
  return {name = force.name, index = force.index, bonus = force.worker_robots_speed_modifier,
    current = current and current.name or false, progress = force.research_progress, queue = queue_names(force),
    worker = {level = worker.level, researched = worker.researched, enabled = worker.enabled,
      visible = worker.visible_when_disabled, saved = worker.saved_progress}}
end

local function assert_worker_frame(actual, expected, label)
  check(actual.name == expected.name and actual.index == expected.index and close(actual.bonus, expected.bonus), label .. " force identity or bonus differs")
  check(actual.current == expected.current and close(actual.progress, expected.progress) and same(actual.queue, expected.queue), label .. " current or queue differs")
  check(same(actual.worker, expected.worker) and actual.worker.saved == 0, label .. " worker row differs")
end

local function force_by_index(index, label)
  local value = game.forces[index]
  check(value and value.valid ~= false and value.index == index, label .. " force is absent")
  return value
end

local function source_forces(state)
  return game.forces.player, force_by_index(state.foreign_index, "foreign"), force_by_index(state.earned_index, "earned")
end

local function source_snapshot(state, label)
  local player, foreign, earned = source_forces(state)
  local completed = {}
  for role, force in pairs({player = player, foreign = foreign, earned = earned}) do
    assert_fixed_contract(force, label .. " " .. role)
    local rows, order = completed_rows(force, label .. " " .. role)
    completed[role] = {rows = rows, order = order}
  end
  return {player = worker_row(player, label .. " player"), foreign = worker_row(foreign, label .. " foreign"),
    earned = worker_row(earned, label .. " earned"), completed = completed}
end

local function assert_snapshot(state, expected, label)
  local actual = source_snapshot(state, label)
  assert_worker_frame(actual.player, expected.player, label .. " player")
  assert_worker_frame(actual.foreign, expected.foreign, label .. " foreign")
  assert_worker_frame(actual.earned, expected.earned, label .. " earned")
  check(same(actual.completed, expected.completed), label .. " completed-row state differs")
  return actual
end

local function emit(phase, state, extra)
  local body = {schema = 1, role = stage, phase = phase, tick = game.tick, fixture_version = script.active_mods[FIXTURE],
    mir_version = script.active_mods[MIR], cap = settings.startup[CAP].value, active_mods = copy(script.active_mods),
    active_mod_tuple = active_tuple(), source_provenance = state and copy(state.provenance) or false,
    source = state and state.source and copy(state.source) or false,
    admission = state and state.admission and copy(state.admission) or false,
    candidate = state and state.candidate and copy(state.candidate) or false, extra = extra or {}}
  local text = helpers.table_to_json(body)
  log("[MIR_SE_WORKER_SPEED_PROVIDER phase=" .. phase .. "] " .. text)
  helpers.write_file("se-worker-speed-provider/" .. phase .. ".json", text .. "\n", false)
end

local function set_target(force, level, enabled)
  local target = technology(force, WORKER)
  target.researched, target.level = false, level
  force.reset_technology_effects()
  target.enabled, target.visible_when_disabled, target.saved_progress = enabled, false, 0
end

local function grant_declared_rows(force, label)
  assert_fixed_contract(force, label)
  for _, declared in ipairs(fixture.rows) do technology(force, declared.name).researched = true end
  local _, order = completed_rows(force, label)
  check(#order == 196, "fixed prerequisite row count differs")
end

local function assert_source_expected(snapshot, label)
  local player, foreign, earned = snapshot.player, snapshot.foreign, snapshot.earned
  check(player.worker.level == 10 and player.worker.researched == false and player.worker.enabled == true
    and player.worker.visible == false and player.current == WORKER and close(player.progress, .27)
    and same(player.queue, {WORKER, WORKER}) and close(player.bonus, 5.0), label .. " player source frame differs")
  check(foreign.worker.level == 11 and foreign.worker.researched == false and foreign.worker.enabled == false
    and foreign.worker.visible == false and foreign.current == CURRENT and close(foreign.progress, .42)
    and same(foreign.queue, {CURRENT, QUEUED}) and close(foreign.bonus, 5.65), label .. " foreign source frame differs")
  check(earned.worker.level == 13 and earned.worker.researched == false and earned.worker.enabled == true
    and earned.worker.visible == false and earned.current == false and close(earned.progress, 0)
    and #earned.queue == 0 and close(earned.bonus, 6.95), label .. " earned source frame differs")
end

local function begin_source()
  assert_active("source")
  check(storage[KEY] == nil, "source fixture storage already exists")
  assert_declared_order("source")
  local player = game.forces.player
  check(player and player.valid ~= false, "player force is absent")
  local foreign, earned = game.create_force(FOREIGN), game.create_force(EARNED)
  for _, row in ipairs({{force = player, level = 10, enabled = true, role = "player"},
    {force = foreign, level = 11, enabled = false, role = "foreign"}, {force = earned, level = 13, enabled = true, role = "earned"}}) do
    grant_declared_rows(row.force, "source " .. row.role)
    set_target(row.force, row.level, row.enabled)
  end
  player.research_queue, player.research_progress = {technology(player, WORKER), technology(player, WORKER)}, .27
  technology(foreign, CURRENT).researched, technology(foreign, QUEUED).researched = false, false
  technology(foreign, CURRENT).enabled, technology(foreign, QUEUED).enabled = true, true
  foreign.research_queue, foreign.research_progress = {technology(foreign, CURRENT), technology(foreign, QUEUED)}, .42
  earned.research_queue, earned.research_progress = {}, 0
  local state = {schema = 1, phase = "source-ready", provenance = {role = "source", source_mir = script.active_mods[MIR],
    fixture_version = script.active_mods[FIXTURE], ordered_prerequisite_count = #fixture.rows}, foreign_index = foreign.index, earned_index = earned.index}
  storage[KEY] = state
  state.source = source_snapshot(state, "source")
  assert_source_expected(state.source, "source")
  emit("source", state, {completed_rows_observed = true, native_execution = false})
end

local function assert_source_provenance(state, label)
  check(type(state) == "table" and state.schema == 1 and type(state.provenance) == "table"
    and state.provenance.role == "source" and state.provenance.source_mir == "5.0.20015" and state.provenance.ordered_prerequisite_count == 196,
    label .. " source provenance differs")
  check(type(state.source) == "table", label .. " source observation is absent")
end

local function assert_ready_source(state, label)
  assert_source_provenance(state, label)
  local actual = assert_snapshot(state, state.source, label)
  assert_source_expected(actual, label)
  return actual
end

local function admission_event(event)
  check(type(event) == "table" and event.mod_startup_settings_changed == false and type(event.mod_changes) == "table", "admission event differs")
  local change = event.mod_changes[FIXTURE]
  check(change and change.old_version == "0.1.0" and change.new_version == "0.2.0" and event.mod_changes[MIR] == nil,
    "admission fixture change differs")
  for name in pairs(event.mod_changes) do check(name == FIXTURE, "unexpected admission mod change") end
end

local function candidate_event(event)
  check(type(event) == "table" and event.mod_startup_settings_changed == true and type(event.mod_changes) == "table", "candidate event differs")
  local fixture_change, mir_change = event.mod_changes[FIXTURE], event.mod_changes[MIR]
  check(fixture_change and fixture_change.old_version == "0.2.0" and fixture_change.new_version == "0.4.0", "candidate fixture change differs")
  check(mir_change and mir_change.old_version == "5.0.20015" and mir_change.new_version == "5.0.20018", "candidate MIR change differs")
  for name in pairs(event.mod_changes) do check(name == FIXTURE or name == MIR, "unexpected candidate mod change") end
end

local function assert_candidate_normalized(state, label)
  local current = source_snapshot(state, label)
  -- Candidate MIR is allowed to remove only the duplicated future queue row;
  -- all source flags, finite prerequisite rows, worker levels and force work remain bound.
  check(same(current.completed, state.source.completed), label .. " completed prerequisite rows differ")
  check(same(current.foreign, state.source.foreign) and same(current.earned, state.source.earned),
    label .. " foreign or earned source frame differs")
  check(current.player.current == WORKER and close(current.player.progress, .27) and same(current.player.queue, {WORKER})
    and current.player.worker.level == 10 and current.player.worker.researched == false and current.player.worker.saved == 0
    and close(current.player.bonus, 5.0), label .. " candidate player cap frame differs")
  return current
end

local function begin_admission(event)
  assert_active("admission"); admission_event(event)
  local state = storage[KEY]; local actual = assert_ready_source(state, "admission")
  state.admission = {phase = "holding", before = actual, ticks = 0, config_observed = true}
  state.phase = "admission-holding"
  emit("admission-pre-hold", state, {native_repair = false})
end

local function begin_old(event)
  assert_active("old")
  local state = storage[KEY]; assert_ready_source(state, "old opponent")
  check(type(state.admission) == "table" and state.admission.phase == "saved" and state.admission.ticks == 2,
    "old opponent requires admitted source")
  check(type(event) == "table" and event.mod_startup_settings_changed == true and type(event.mod_changes) == "table", "old event differs")
  local change = event.mod_changes[FIXTURE]
  check(change and change.old_version == "0.2.0" and change.new_version == "0.3.0" and event.mod_changes[MIR] == nil, "old fixture change differs")
  emit("old-opponent", state, {accepted = false, native_repair = false})
  fail("MIR_EXPECTED_SE_WORKER_SPEED_PROVIDER_OLD15_OPPONENT")
end

local function begin_candidate(event)
  assert_active("candidate"); candidate_event(event)
  local state = storage[KEY]
  check(type(state) == "table" and type(state.admission) == "table" and state.admission.phase == "saved"
    and state.admission.config_observed == true and state.admission.ticks == 2
    and same(state.admission.before, state.source) and same(state.admission.after, state.source), "admitted source is absent")
  assert_source_provenance(state, "candidate source")
  local actual = assert_candidate_normalized(state, "candidate configuration")
  state.candidate = {phase = "awaiting-work", pre_work = actual, ordinary_events = {}, level_eleven_starts = 0}
  state.phase = "candidate-awaiting-work"
  emit("candidate-pre-work", state, {lab_created = false})
end

local function create_lab(state)
  local lab = game.surfaces[1].create_entity({name = LAB, position = {0, 0}, force = game.forces.player})
  check(lab and lab.valid ~= false, "candidate lab is absent")
  lab.disabled_by_script = false
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  check(inventory ~= nil, "candidate lab input is absent")
  state.candidate.lab, state.candidate.inserted = lab, {}
  for _, name in ipairs(SCIENCE) do
    local count = inventory.insert({name = name, count = 200})
    check(type(count) == "number" and count > 0, "candidate science feed differs: " .. name)
    state.candidate.inserted[name] = count
  end
end

local function assert_no_level_eleven(state, label)
  local player = game.forces.player
  local worker = technology(player, WORKER)
  check(state.candidate.level_eleven_starts == 0 and worker.level == 11 and worker.researched == false
    and worker.enabled == false and player.current_research == nil and #queue_names(player) == 0 and player.research_progress == 0,
    label .. " level eleven started or queued")
end

local function assert_science(state, label)
  local inventory = state.candidate.lab and state.candidate.lab.get_inventory(defines.inventory.lab_input)
  check(inventory ~= nil, label .. " lab input is absent")
  for name, inserted in pairs(state.candidate.inserted) do
    local remaining = inventory.get_item_count(name)
    check(remaining > 0 and remaining < inserted, label .. " science consumption differs: " .. name)
  end
end

local function close_candidate(state)
  local player, foreign, earned = source_forces(state)
  assert_no_level_eleven(state, "candidate complete")
  local current = source_snapshot(state, "candidate complete")
  check(same(current.foreign, state.candidate.pre_work.foreign) and same(current.earned, state.candidate.pre_work.earned),
    "candidate changed foreign or earned frame")
  assert_science(state, "candidate complete")
  state.candidate.closed = {player = current.player, foreign = current.foreign, earned = current.earned,
    completed = current.completed, ordinary_events = copy(state.candidate.ordinary_events), lab = {disabled = state.candidate.lab.disabled_by_script}}
  state.candidate.lab.disabled_by_script = true
  state.candidate.phase, state.phase = "saved", "candidate-saved"
  emit("candidate-complete", state, {ordinary_completion_count = #state.candidate.ordinary_events})
  check(game.is_multiplayer(), "candidate save requires server")
  game.server_save("se-worker-speed-provider-candidate")
end

local function candidate_cold()
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "candidate-saved" and type(state.candidate) == "table" and type(state.candidate.closed) == "table",
    "candidate cold state is absent")
  local current = source_snapshot(state, "candidate cold")
  check(same(current.player, state.candidate.closed.player) and same(current.foreign, state.candidate.closed.foreign)
    and same(current.earned, state.candidate.closed.earned) and same(current.completed, state.candidate.closed.completed),
    "candidate cold public state differs")
  local lab = state.candidate.lab
  check(lab and lab.valid ~= false and lab.disabled_by_script == true, "candidate cold lab differs")
  emit("candidate-cold", state, {on_load_read_only = true})
end

function M.apply(value)
  check(STAGES[value] ~= nil, "unknown control stage"); stage, cold_pending, cold_emitted = value, false, false
  script.on_init(function()
    if stage == "source" then begin_source()
    elseif stage == "candidate" then check(storage[KEY] ~= nil, "candidate requires admitted source state") end
  end)
  script.on_configuration_changed(function(event)
    if stage == "admission" then begin_admission(event)
    elseif stage == "old" then begin_old(event)
    elseif stage == "candidate" then begin_candidate(event)
    else fail("source stage does not accept configuration") end
  end)
  script.on_load(function() if stage == "admission" or stage == "candidate" then cold_pending = true end end)
  script.on_event(defines.events.on_research_started, function(event)
    if stage ~= "candidate" then return end
    local state = storage[KEY]
    if type(state) ~= "table" or type(state.candidate) ~= "table" then return end
    if event.research and event.research.force == game.forces.player and event.research.name == WORKER and event.research.level > 10 then
      state.candidate.level_eleven_starts = state.candidate.level_eleven_starts + 1
      fail("candidate level eleven research started")
    end
  end)
  script.on_event(defines.events.on_research_finished, function(event)
    if stage ~= "candidate" then return end
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= "candidate-working" then return end
    local worker = technology(game.forces.player, WORKER)
    check(event.research == worker and event.by_script == false and worker.level == 11, "candidate ordinary completion differs")
    state.candidate.ordinary_events[#state.candidate.ordinary_events + 1] = {name = WORKER, by_script = false,
      completed_level = 10, event_post_increment_level = worker.level, tick = event.tick}
    check(#state.candidate.ordinary_events == 1, "candidate repeated ordinary completion")
    state.phase, state.candidate.phase, state.candidate.hold_ticks = "candidate-holding", "holding", 0
  end)
  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if cold_pending and not cold_emitted then
      if stage == "admission" then
        check(type(state) == "table" and type(state.admission) == "table" and state.admission.phase == "saved", "admission cold state is absent")
        local actual = assert_ready_source(state, "admission cold")
        check(same(actual, state.admission.after), "admission cold frame differs")
        emit("admission-cold", state, {on_load_read_only = true}); cold_emitted = true; return
      elseif stage == "candidate" then candidate_cold(); cold_emitted = true; return end
    end
    if stage == "admission" and type(state) == "table" and state.phase == "admission-holding" then
      local actual = assert_ready_source(state, "admission hold")
      check(same(actual, state.admission.before), "admission changed public state")
      state.admission.ticks = state.admission.ticks + 1
      if state.admission.ticks >= 2 then
        state.admission.after, state.admission.phase, state.phase = actual, "saved", "admission-saved"
        emit("admission-saved", state, {hold_ticks = 2, native_repair = false})
        check(game.is_multiplayer(), "admission save requires server")
        game.server_save("se-worker-speed-provider-admission")
      end
      return
    end
    if stage ~= "candidate" or type(state) ~= "table" then return end
    if state.phase == "candidate-awaiting-work" then
      assert_candidate_normalized(state, "candidate before lab")
      create_lab(state); state.phase, state.candidate.phase = "candidate-working", "working"
    elseif state.phase == "candidate-holding" then
      assert_no_level_eleven(state, "candidate hold")
      state.candidate.hold_ticks = state.candidate.hold_ticks + 1
      if state.candidate.hold_ticks >= 2 then close_candidate(state) end
    end
  end)
end

return M
