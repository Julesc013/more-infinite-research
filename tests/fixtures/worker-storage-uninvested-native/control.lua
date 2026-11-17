-- Disposable observer for the empty published11 worker-storage route.  The
-- source role is loaded only with published4.7; it is absent while published11
-- performs its own real configuration callback and is newly added to candidate17.
local M = {}

local MIR = "more-infinite-research"
local FIXTURE = "mir-worker-storage-uninvested-native"
local KEY = "mir_worker_storage_uninvested_native"
local FOREIGN = "mir-worker-uninvested-native-foreign"
local LAB = "mir-worker-uninvested-native-lab"
local CANONICAL = "worker-robots-storage-4"
local DEFAULT = "mir-worker-storage-default-4"
local HEAD = "mir-worker-storage-head-4"
local CURRENT = "automation"
local QUEUED = "logistics"
local DISABLED = "worker-robots-speed-4"
local SCIENCE = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}
local ORDINARY_PREREQUISITES = {"worker-robots-storage-2", "worker-robots-storage-3", "automation-science-pack",
  "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack"}
local TUPLES = {
  ["2.0.77"] = {old="4.7.20002", published="5.0.20011", negative="5.0.20016", candidate="5.0.20017"},
  ["2.1.23"] = {old="4.7.21002", published="5.0.21011", negative="5.0.21016", candidate="5.0.21017"},
}
local loaded = false
local SOURCE_FOREIGN = {current=CURRENT, queue={CURRENT, QUEUED}, progress=.42,
  queued_saved=.27, disabled_enabled=false, disabled_visible=true, worker_speed_modifier=.75,
  setup_rows={"steam-power", "electronics", "automation-science-pack", CURRENT, QUEUED, DISABLED}}
local FLOAT_TOLERANCE = 1e-7

local function fail(reason) error("[worker-storage-uninvested-native] " .. reason, 2) end
local function check(value, reason) if not value then fail(reason) end end

local function near(actual, expected, reason)
  check(type(actual) == "number" and type(expected) == "number"
    and math.abs(actual - expected) <= FLOAT_TOLERANCE, reason)
end

local function number_text(value, reason)
  check(type(value) == "number", reason)
  return string.format("%.17g", value)
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function same(left, right, path)
  path = path or "$"
  check(type(left) == type(right), path .. " type differs")
  if type(left) ~= "table" then check(left == right, path .. " differs"); return end
  for key, value in pairs(left) do same(value, right[key], path .. "/" .. tostring(key)) end
  for key in pairs(right) do check(left[key] ~= nil, path .. "/" .. tostring(key) .. " unexpected") end
end

local function tuple(role)
  local active = script.active_mods
  local selected = TUPLES[active.base]
  check(selected ~= nil and active[FIXTURE] == "0.13.0", "exact Base/fixture tuple")
  local expected = role == "source" and selected.old or selected.candidate
  check(active[MIR] == expected, "exact MIR tuple")
  local count = 0
  for name in pairs(active) do
    check(name == "base" or name == MIR or name == FIXTURE, "unexpected active mod")
    count = count + 1
  end
  check(count == 3, "exact active mod selection")
  return selected
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  check(value and value.valid ~= false and value.name == name, "missing technology " .. name)
  return value
end

local function row(force, name)
  local value = technology(force, name)
  return {name=name, level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, saved=value.saved_progress, count=value.research_unit_count}
end

local function optional_row(force, name)
  local value = force.technologies[name]
  if value == nil then return false end
  return row(force, name)
end

local function queue(force)
  local out = {}
  for index, item in ipairs(force.research_queue or {}) do out[index] = item.name end
  return out
end

local function worker_frame(force)
  return {name=force.name, index=force.index, bonus=force.worker_robots_storage_bonus,
    current=force.current_research and force.current_research.name or false,
    progress=force.research_progress, queue=queue(force), canonical=row(force, CANONICAL),
    ordinary=optional_row(force, DEFAULT), head=optional_row(force, HEAD)}
end

-- Factorio exposes forces both by name and by numeric index.  Snapshot each
-- valid force once by its stable native index so an empty-origin admission
-- cannot overlook an invested third force merely because it is not the
-- player or the fixture's named foreign force.
local function applicable_forces()
  local by_index, indices = {}, {}
  for _, force in pairs(game.forces) do
    if force ~= nil and force.valid ~= false then
      local index = force.index
      check(type(index) == "number" and index > 0 and index % 1 == 0, "valid force index")
      if by_index[index] == nil then
        by_index[index] = force
        indices[#indices + 1] = index
      end
    end
  end
  table.sort(indices)
  local forces = {}
  for _, index in ipairs(indices) do forces[#forces + 1] = by_index[index] end
  return forces
end

local function worker_frames(forces)
  forces = forces or applicable_forces()
  local frames = {}
  for _, force in ipairs(forces) do frames[tostring(force.index)] = worker_frame(force) end
  return frames
end

local function unrelated_frame(force)
  local rows = {}
  for _, name in ipairs(SOURCE_FOREIGN.setup_rows) do rows[name] = row(force, name) end
  return {current=force.current_research and force.current_research.name or false,
    progress=force.research_progress, queue=queue(force), automation=row(force, CURRENT),
    logistics=row(force, QUEUED), disabled=row(force, DISABLED), rows=rows,
    bonus=force.worker_robots_speed_modifier}
end

local function assert_source_foreign(force)
  local actual = unrelated_frame(force)
  check(actual.current == SOURCE_FOREIGN.current, "foreign current differs")
  near(actual.progress, SOURCE_FOREIGN.progress, "foreign current progress differs")
  check(#actual.queue == #SOURCE_FOREIGN.queue, "foreign queue length differs")
  for index, name in ipairs(SOURCE_FOREIGN.queue) do check(actual.queue[index] == name, "foreign queue differs") end
  near(actual.logistics.saved, SOURCE_FOREIGN.queued_saved, "foreign suspended progress differs")
  check(actual.disabled.enabled == SOURCE_FOREIGN.disabled_enabled and actual.disabled.visible == SOURCE_FOREIGN.disabled_visible,
    "foreign disabled flag differs")
  check(actual.bonus == SOURCE_FOREIGN.worker_speed_modifier, "foreign native bonus differs")
  for _, name in ipairs(SOURCE_FOREIGN.setup_rows) do
    local observed = actual.rows[name]
    check(observed ~= nil, "foreign setup row is absent: " .. name)
    if name == "steam-power" or name == "electronics" or name == "automation-science-pack" then
      check(observed.researched == true and observed.level == 1, "foreign prerequisite differs: " .. name)
    elseif name == CURRENT or name == QUEUED then
      check(observed.researched == false and observed.level == 1 and observed.enabled == true,
        "foreign unfinished work differs: " .. name)
    elseif name == DISABLED then
      check(observed.researched == false and observed.level == 4 and observed.enabled == false
        and observed.visible == true, "foreign disabled sentinel differs")
    end
  end
  return actual
end

local function same_source_row(expected, actual, saved_near, path)
  check(type(expected) == "table" and type(actual) == "table", path .. " row type differs")
  for key, value in pairs(expected) do
    if key == "saved" and saved_near then near(actual[key], value, path .. "/saved differs")
    else same(value, actual[key], path .. "/" .. tostring(key)) end
  end
  for key in pairs(actual) do check(expected[key] ~= nil, path .. "/" .. tostring(key) .. " unexpected") end
end

-- Only the public research fractions can differ by the engine's recorded
-- floating representation.  Identity, levels, flags, counts and bonuses stay
-- exact; this is intentionally not a numeric-tolerant deep comparison.
local function same_source_foreign(expected, actual, path)
  path = path or "$/foreign"
  check(type(expected) == "table" and type(actual) == "table", path .. " type differs")
  same(expected.current, actual.current, path .. "/current")
  near(actual.progress, expected.progress, path .. "/progress differs")
  same(expected.queue, actual.queue, path .. "/queue")
  same_source_row(expected.automation, actual.automation, false, path .. "/automation")
  same_source_row(expected.logistics, actual.logistics, true, path .. "/logistics")
  same_source_row(expected.disabled, actual.disabled, false, path .. "/disabled")
  same(expected.bonus, actual.bonus, path .. "/bonus")
  check(type(expected.rows) == "table" and type(actual.rows) == "table", path .. "/rows type differs")
  for name, row in pairs(expected.rows) do
    same_source_row(row, actual.rows[name], name == QUEUED, path .. "/rows/" .. name)
  end
  for name in pairs(actual.rows) do check(expected.rows[name] ~= nil, path .. "/rows/" .. name .. " unexpected") end
end

local function optional_boolean(read)
  local ok, value = pcall(read)
  if ok and type(value) == "boolean" then return {supported=true, value=value} end
  return {supported=false, value=false}
end

local function emit_unaccepted_source_setup(foreign)
  local actual = unrelated_frame(foreign)
  local body = {schema=1, role="published11-uninvested-worker-storage", stage="source-unaccepted-after-final-setup",
    accepted=false, source_role=true, current=actual.current, expected_current=SOURCE_FOREIGN.current,
    progress=actual.progress, progress_text=number_text(actual.progress, "source progress type"),
    expected_progress=SOURCE_FOREIGN.progress, expected_progress_text=number_text(SOURCE_FOREIGN.progress, "expected progress type"),
    logistics_saved=actual.logistics.saved, logistics_saved_text=number_text(actual.logistics.saved, "source saved type"),
    expected_logistics_saved=SOURCE_FOREIGN.queued_saved,
    expected_logistics_saved_text=number_text(SOURCE_FOREIGN.queued_saved, "expected saved type"),
    foreign=copy(actual), research_queue_enabled={supported=false, value=false,
      reason="not-declared-2.0.77-runtime-api"},
    research_enabled=optional_boolean(function() return foreign.research_enabled end)}
  local text = helpers.table_to_json(body)
  log("MIR_WORKER_UNINVESTED_NATIVE_UNACCEPTED " .. text)
  helpers.write_file("worker-storage-uninvested-native/source-unaccepted-after-final-setup.json", text .. "\n", false)
end

local function assert_empty_worker(force, candidate)
  local frame = worker_frame(force)
  check(frame.canonical.level == 4 and frame.canonical.researched == false and frame.canonical.saved == 0,
    "canonical worker C4 is invested")
  check(frame.current ~= CANONICAL, "canonical worker C4 is current")
  for _, name in ipairs(frame.queue) do check(name ~= CANONICAL, "canonical worker C4 is queued") end
  if candidate then
    check(frame.ordinary ~= false and frame.head ~= false, "candidate default identities absent")
    check(frame.ordinary.level == 4 and frame.ordinary.researched == false and frame.ordinary.saved == 0,
      "candidate ordinary C4 is invested")
    check(frame.current ~= DEFAULT, "candidate ordinary C4 is current before work")
    for _, name in ipairs(frame.queue) do check(name ~= DEFAULT, "candidate ordinary C4 is queued before work") end
    check(frame.head.level == 4 and frame.head.researched == false and frame.head.saved == 0,
      "candidate head C4 is invested")
    check(frame.current ~= HEAD, "candidate head C4 is current before work")
    for _, name in ipairs(frame.queue) do check(name ~= HEAD, "candidate head C4 is queued before work") end
  else
    check(frame.ordinary == false and frame.head == false, "published4.7 source contains candidate identities")
  end
  return frame
end

local function assert_all_empty_worker(candidate)
  local forces = applicable_forces()
  for _, force in ipairs(forces) do assert_empty_worker(force, candidate) end
  return worker_frames(forces)
end

local function lab_frame(state)
  local lab = state.lab
  if lab == nil then return {present=false} end
  check(lab.valid ~= false, "fixture lab invalid")
  local inventory, amounts = lab.get_inventory(defines.inventory.lab_input), {}
  for _, pack in ipairs(SCIENCE) do amounts[pack] = inventory.get_item_count(pack) end
  return {present=true, unit=lab.unit_number, disabled=lab.disabled_by_script,
    speed=lab.prototype.get_researching_speed("normal"), inventory=amounts,
    modules_empty=lab.get_inventory(defines.inventory.lab_modules).is_empty()}
end

local function event_rows(event)
  check(type(event) == "table" and type(event.mod_startup_settings_changed) == "boolean"
    and type(event.mod_changes) == "table", "configuration event shape")
  local rows = {}
  for name, change in pairs(event.mod_changes) do
    check(type(name) == "string" and type(change) == "table", "configuration change shape")
    local old, new = change.old_version, change.new_version
    check((old == nil or type(old) == "string") and (new == nil or type(new) == "string"), "configuration version shape")
    rows[#rows + 1] = {name=name, old_version_present=old ~= nil, old_version=old,
      new_version_present=new ~= nil, new_version=new}
  end
  table.sort(rows, function(left, right) return left.name < right.name end)
  return rows
end

local function emit(stage, extra)
  local state = storage[KEY]
  local frames = {player=worker_frame(game.forces.player)}
  local foreign = game.forces[FOREIGN]
  if foreign ~= nil then
    check(foreign.valid ~= false, "foreign force unavailable")
    frames.foreign = worker_frame(foreign)
  end
  local body = {schema=1, role="published11-uninvested-worker-storage", stage=stage, tick=game.tick,
    fixture_version=script.active_mods[FIXTURE], mir_version=script.active_mods[MIR], mods=copy(script.active_mods),
    frames=frames, worker_frames=worker_frames(), pre_config=state and state.pre_config or false,
    source_foreign=state and state.source_foreign and copy(state.source_foreign) or false,
    candidate_event=state and state.candidate_event or false, lab=state and lab_frame(state) or {present=false}, extra=extra}
  local text = helpers.table_to_json(body)
  log("MIR_WORKER_UNINVESTED_NATIVE " .. text)
  helpers.write_file("worker-storage-uninvested-native/" .. stage .. ".json", text .. "\n", false)
end

local function source_setup()
  local selected = tuple("source")
  check(storage[KEY] == nil, "source fixture already initialized")
  local player = game.forces.player
  local foreign = game.forces[FOREIGN] or game.create_force(FOREIGN)
  assert_all_empty_worker(false)
  -- These are real Base technologies and a real Base native modifier.  They
  -- deliberately do not touch the worker-storage C4 continuation.
  for _, name in ipairs({"steam-power", "electronics", "automation-science-pack"}) do
    technology(foreign, name).researched = true
  end
  technology(foreign, CURRENT).enabled = true
  technology(foreign, QUEUED).enabled = true
  technology(foreign, CURRENT).researched = false
  technology(foreign, QUEUED).researched = false
  foreign.research_queue = {CURRENT, QUEUED}
  foreign.research_progress = .42
  technology(foreign, QUEUED).saved_progress = .27
  technology(foreign, DISABLED).researched = false
  technology(foreign, DISABLED).enabled = false
  technology(foreign, DISABLED).visible_when_disabled = true
  foreign.worker_robots_speed_modifier = SOURCE_FOREIGN.worker_speed_modifier
  -- This intentionally precedes acceptance/storage.  It preserves the exact
  -- engine-facing post-setter frame when the later source assertion refuses.
  emit_unaccepted_source_setup(foreign)
  local unrelated = assert_source_foreign(foreign)
  local workers = assert_all_empty_worker(false)
  storage[KEY] = {schema=1, phase="source-ready", source_base=script.active_mods.base,
    source_mir=selected.old, foreign_index=foreign.index, source_foreign=unrelated, source_workers=workers}
  emit("source-ready", {source_role=true, worker_storage_written=false})
end

local function candidate_event(event)
  local selected = tuple("candidate")
  local state = storage[KEY]
  check(type(state) == "table" and state.schema == 1 and state.phase == "candidate-awaiting-config"
    and state.source_base == script.active_mods.base, "candidate observer state")
  local rows = event_rows(event)
  local changes = event.mod_changes
  local mir, fixture = changes[MIR], changes[FIXTURE]
  check(mir and mir.old_version == selected.published and mir.new_version == selected.candidate,
    "exact published11 candidate event")
  check(fixture and fixture.old_version == nil and fixture.new_version == "0.13.0", "fixture must be newly added after published11")
  for _, item in ipairs(rows) do check(item.name == MIR or item.name == FIXTURE, "unexpected candidate configuration change") end
  local foreign = game.forces[FOREIGN]
  check(foreign and foreign.valid ~= false, "source foreign force absent")
  -- This is the first fixture callback after MIR17's configuration handler.
  -- It reads public native state only; candidate worker writes begin on a later tick.
  local workers = assert_all_empty_worker(true)
  assert_source_foreign(foreign)
  same_source_foreign(state.pre_config.foreign_unrelated, unrelated_frame(foreign), "$/pre-config-foreign")
  same(state.pre_config.worker_frames, workers, "$/pre-config-worker-frames")
  state.candidate_event = {startup_settings_changed=event.mod_startup_settings_changed,
    trigger=event.mod_startup_settings_changed and "startup-settings-plus-fixture-addition" or "fixture-addition", mod_changes=rows}
  state.phase = "candidate-admitted"
  emit("candidate-admitted", {worker_storage_written=false})
end

local function start_ordinary()
  local state = storage[KEY]
  check(state.phase == "candidate-admitted", "ordinary start phase")
  local player = game.forces.player
  local ordinary = technology(player, DEFAULT)
  local expected = {}
  for _, name in ipairs(ORDINARY_PREREQUISITES) do expected[name] = true end
  for key, prerequisite in pairs(ordinary.prerequisites) do
    local name = type(key) == "string" and key or prerequisite.name
    check(expected[name] == true, "ordinary prerequisite differs: " .. tostring(name))
    expected[name] = nil
  end
  check(next(expected) == nil, "ordinary prerequisite set differs")
  -- The bounded authored prerequisite list is validated above.  Complete only
  -- those exact public rows: recursive research would silently traverse an
  -- unobserved Base graph and obscure the source/candidate boundary.
  for _, name in ipairs(ORDINARY_PREREQUISITES) do technology(player, name).researched = true end
  check(ordinary.research_unit_count == 675, "ordinary default exact science cost")
  local foreign = game.forces[FOREIGN]
  assert_all_empty_worker(true)
  assert_source_foreign(foreign)
  same_source_foreign(state.pre_config.foreign_unrelated, unrelated_frame(foreign), "$/ordinary-foreign")
  local surface = game.surfaces[1]
  local lab = surface.create_entity{name=LAB, position={0, 0}, force=player}
  check(lab and lab.valid ~= false and lab.prototype.get_researching_speed("normal") == 3600, "owned ordinary lab")
  state.lab, state.inserted = lab, {}
  player.research_queue = {DEFAULT}
  local input = lab.get_inventory(defines.inventory.lab_input)
  for _, pack in ipairs(SCIENCE) do
    local count = input.insert{name=pack, count=200}
    check(count > 0, "ordinary lab feed " .. pack)
    state.inserted[pack] = count
  end
  state.before_work = {player=worker_frame(player), foreign=worker_frame(foreign), worker_frames=worker_frames(),
    foreign_unrelated=unrelated_frame(foreign)}
  state.phase = "ordinary-active"
  emit("ordinary-started", {scripted_queue_after_admission=true})
end

local function supply_ordinary_science(state)
  local input = state.lab.get_inventory(defines.inventory.lab_input)
  for _, pack in ipairs(SCIENCE) do
    if input.get_item_count(pack) < 64 then
      local count = input.insert{name=pack, count=200}
      check(count > 0, "ordinary lab refill " .. pack)
      state.inserted[pack] = state.inserted[pack] + count
    end
  end
end

local function save_after_ordinary()
  local state, player = storage[KEY], game.forces.player
  check(state.phase == "ordinary-finished", "ordinary save phase")
  local foreign = game.forces[FOREIGN]
  check(state.lab.valid ~= false, "ordinary lab missing")
  state.lab.disabled_by_script = true
  assert_source_foreign(foreign)
  same_source_foreign(state.pre_config.foreign_unrelated, unrelated_frame(foreign), "$/saved-foreign")
  local ordinary = row(player, DEFAULT)
  check(ordinary.level == 5 and ordinary.researched == false and player.worker_robots_storage_bonus == state.before_work.player.bonus + 1,
    "ordinary default C4 effect")
  state.closed, state.closed_lab, state.phase = {player=worker_frame(player), foreign=worker_frame(foreign), worker_frames=worker_frames(),
    foreign_unrelated=unrelated_frame(foreign)}, lab_frame(state), "ordinary-saved"
  emit("ordinary-saved", {ordinary_native_completion_count=1})
  check(game.is_multiplayer(), "server save requires owned server")
  game.server_save("worker-storage-uninvested-native")
end

local function cold()
  local state = storage[KEY]
  check(state and state.phase == "ordinary-saved" and state.closed ~= nil, "cold requires closed candidate save")
  local foreign = game.forces[FOREIGN]
  local actual = {player=worker_frame(game.forces.player), foreign=worker_frame(foreign), worker_frames=worker_frames(),
    foreign_unrelated=unrelated_frame(foreign)}
  same(state.closed, actual, "$/cold")
  same(state.closed_lab, lab_frame(state), "$/cold-lab")
  emit("cold", {on_load_read_only=true})
end

function M.on_configuration_changed(event)
  local selected = TUPLES[script.active_mods.base]
  if selected and script.active_mods[MIR] == selected.candidate then
    candidate_event(event)
  end
end

function M.on_tick()
  local selected = TUPLES[script.active_mods.base]
  if selected == nil then fail("unsupported Base version") end
  if script.active_mods[MIR] == selected.old then
    if storage[KEY] == nil then source_setup() end
    return
  end
  if script.active_mods[MIR] ~= selected.candidate then return end
  local state = storage[KEY]
  if loaded then loaded = false; if state and state.phase == "ordinary-saved" then cold() end; return end
  if state and state.phase == "candidate-admitted" then start_ordinary()
  elseif state and state.phase == "ordinary-active" then supply_ordinary_science(state)
  elseif state and state.phase == "ordinary-finished" then save_after_ordinary() end
end

function M.on_finished(event)
  local state = storage[KEY]
  if state == nil or state.phase ~= "ordinary-active" then return end
  check(event.by_script == false and event.research and event.research.name == DEFAULT
    and event.research.force == game.forces.player, "exact ordinary default C4 completion")
  local foreign = game.forces[FOREIGN]
  emit("ordinary-callback-observed", {name=event.research.name, by_script=event.by_script, force=event.research.force.name})
  assert_source_foreign(foreign)
  same_source_foreign(state.pre_config.foreign_unrelated, unrelated_frame(foreign), "$/completion-foreign")
  state.ordinary = {{name=DEFAULT, tick=event.tick, by_script=false}}
  state.phase = "ordinary-finished"
end

script.on_init(function()
  local selected = TUPLES[script.active_mods.base]
  check(selected ~= nil, "unsupported Base version")
  if script.active_mods[MIR] == selected.old then source_setup()
  elseif script.active_mods[MIR] == selected.negative then
    -- The same archive can witness the old16 added-mod refusal.  It must not
    -- pre-empt MIR's own missing-route validation or manufacture a source.
    return
  elseif script.active_mods[MIR] == selected.candidate then
    -- The p4.7 actor was removed for published11, so it cannot retain a
    -- private source marker here.  This is a public, read-only pre-config
    -- observation; the owner separately binds the p4.7 marker and p11 query.
    check(storage[KEY] == nil, "candidate fixture must not retain source actor storage")
    local foreign = game.forces[FOREIGN]
    check(foreign and foreign.valid ~= false, "candidate source foreign force absent")
    local workers = assert_all_empty_worker(true)
    assert_source_foreign(foreign)
    storage[KEY] = {schema=1, phase="candidate-awaiting-config", source_base=script.active_mods.base,
      pre_config={player=worker_frame(game.forces.player), foreign=worker_frame(foreign), worker_frames=workers,
        foreign_unrelated=unrelated_frame(foreign)}}
    emit("candidate-pre-configuration", {public_read_only=true})
  end
end)
script.on_load(function() loaded = true end)
script.on_configuration_changed(M.on_configuration_changed)
script.on_event(defines.events.on_tick, M.on_tick)
script.on_event(defines.events.on_research_finished, M.on_finished)
remote.add_interface("mir-worker-storage-uninvested-native", {observe=function() emit("manual-observe", {}) end})
return M
