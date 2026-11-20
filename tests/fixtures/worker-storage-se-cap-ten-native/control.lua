-- Runtime members were audited against official 2.0.77 runtime-api JSON
-- 594B4EC98CC5FBEE322D7380DB49A388AB38B0D69C06F00EAD877CFFBB37F578.
-- Genuine SE cargo worker-storage actor.  The explicit prerequisite grants
-- below are setup only; all worker rows are advanced by native lab work and
-- observed through on_research_finished with by_script == false.
local fixture = require("__mir-fixture-mir5-worker-storage-se-cap-ten-native__/prerequisites")
local KEY = "mir5_worker_storage_se_cap_ten_native"
local FIXTURE = "mir-fixture-mir5-worker-storage-se-cap-ten-native"
local POWER = "mir-fixture-worker-storage-se-cap-ten-power"
local TAIL = "mir-fixture-worker-storage-se-cap-ten-tail"
local TARGET, PREDECESSOR, LAB = "worker-robots-storage-4", "worker-robots-storage-3", "se-space-science-lab"
local SOURCE_MIR, UINT32_MAX = "4.7.20002", 4294967295
local SPEED_STIMULUS, FEED_REQUEST = 115199, 200
local SOURCE_SAVE, CANDIDATE_SAVE = "mir5-se-worker-storage-cap10-source", "mir5-se-worker-storage-cap10-candidate"
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "se-rocket-science-pack", "se-material-science-pack-1", "space-science-pack"
}
local SETTINGS = {
  {name = "mir-enable-worker-robots-storage", value = true},
  {name = "mir-max-level-worker-robots-storage", value = 10},
  {name = "mir-cost-base-worker-robots-storage", value = 200},
  {name = "mir-cost-linear-increment-worker-robots-storage", value = 0},
  {name = "mir-cost-growth-worker-robots-storage", value = 1.5},
  {name = "mir-research-time-worker-robots-storage", value = 60},
  {name = "mir-effect-per-level-worker-robots-storage", value = 1}
}
local CLOSURE = {
  base = "2.0.77", ["space-exploration"] = "0.7.57", ["aai-containers"] = "0.3.2",
  ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4", ["alien-biomes-graphics"] = "0.7.1",
  jetpack = "0.4.17", robot_attrition = "0.6.6", ["shield-projector"] = "0.2.2",
  ["space-exploration-graphics"] = "0.7.5", ["space-exploration-graphics-2"] = "0.7.2",
  ["space-exploration-graphics-3"] = "0.7.2", ["space-exploration-graphics-4"] = "0.7.2",
  ["space-exploration-graphics-5"] = "0.7.3", ["space-exploration-menu-simulations"] = "0.7.4",
  ["space-exploration-postprocess"] = "0.7.5", informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3"
}
local cold_pending = false

local function fail(message) error("[mir5-worker-storage-se-cap-ten-native] " .. message) end
local function check(value, message) if not value then fail(message) end end
local function close(left, right) return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.0000001 end
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, row in pairs(value) do out[key] = copy(row) end; return out
end
local function active() return script.active_mods[FIXTURE] == "0.1.0" and script.active_mods["more-infinite-research"] ~= nil end
local function technology(force, name)
  local row = force and force.technologies and force.technologies[name]
  check(row and row.valid ~= false and row.name == name, "technology differs: " .. name)
  return row
end
local function marker(phase, state, extra)
  local target = technology(state.player, TARGET)
  local queue = {}
  for index, row in ipairs(state.player.research_queue or {}) do queue[index] = type(row) == "string" and row or row.name end
  local fields = {
    "[MIR_SE_CARGO_NATIVE]", "phase=" .. phase, "tick=" .. tostring(game.tick), "level=" .. tostring(target.level),
    "current=" .. tostring(state.player.current_research and state.player.current_research.name or false),
    "progress=" .. tostring(state.player.research_progress), "queue=" .. table.concat(queue, ","),
    "ordinary=" .. tostring(state.ordinary), "settings_file_values=true"
  }
  if extra then for key, value in pairs(extra) do fields[#fields + 1] = key .. "=" .. tostring(value) end end
  log(table.concat(fields, "|"))
end
local function assert_active_tuple()
  local expected_count = 0
  for name, version in pairs(CLOSURE) do
    check(script.active_mods[name] == version, "active SE module differs: " .. name)
    expected_count = expected_count + 1
  end
  local count = 0
  for name in pairs(script.active_mods) do
    count = count + 1
    check(name == FIXTURE or name == "more-infinite-research" or CLOSURE[name] ~= nil, "unexpected active module: " .. name)
  end
  check(count == expected_count + 2, "active module count differs")
end
local function assert_settings()
  for _, expected in ipairs(SETTINGS) do
    local row = settings.startup and settings.startup[expected.name]
    check(type(row) == "table" and row.valid ~= false and type(row.value) == type(expected.value), "startup setting differs: " .. expected.name)
    check(row.value == expected.value, "startup setting value differs: " .. expected.name)
  end
end
local function parent_names(row)
  local out = {}
  for key, value in pairs(row.prerequisites or {}) do out[#out + 1] = type(key) == "string" and key or value.name end
  table.sort(out); return out
end
local function exact_names(left, right, label)
  check(#left == #right, label .. " count differs")
  for index, name in ipairs(right) do check(left[index] == name, label .. " differs") end
end
local function assert_worker_contract(force)
  local target = technology(force, TARGET)
  check(target.prototype and target.prototype.max_level == UINT32_MAX, "worker maximum differs")
  exact_names(parent_names(target), {PREDECESSOR}, "worker direct prerequisite")
  check(target.research_unit_count_formula == "675*1.5^(L-4)" and target.research_unit_energy == 3600, "worker unit formula or time differs")
  local seen, count = {}, 0
  for _, row in pairs(target.research_unit_ingredients or {}) do
    check(type(row) == "table" and type(row.name) == "string" and row.amount == 1 and not seen[row.name], "worker science row differs")
    seen[row.name], count = true, count + 1
  end
  check(count == #SCIENCE, "worker science count differs")
  for _, name in ipairs(SCIENCE) do check(seen[name], "worker science differs: " .. name) end
  local effects = target.prototype.effects
  check(type(effects) == "table" and #effects == 1 and effects[1].type == "worker-robot-storage" and close(effects[1].modifier, 1), "worker effect differs")
end
local function assert_setup_declaration(force)
  local seen = {}
  for _, declared in ipairs(fixture.rows) do
    check(not seen[declared.name], "duplicate setup declaration")
    for _, parent in ipairs(declared.parents) do if fixture.by_name[parent] then check(seen[parent], "setup declaration order differs") end end
    local row = technology(force, declared.name)
    check(row.prototype and row.prototype.max_level ~= UINT32_MAX, "setup finite row differs: " .. declared.name)
    local parents = copy(declared.parents); table.sort(parents)
    exact_names(parent_names(row), parents, "setup parents " .. declared.name)
    seen[declared.name] = true
  end
  check(#fixture.rows == 98 and seen[PREDECESSOR], "setup declaration count differs")
end
local function assert_lab(lab, power, force)
  check(lab and lab.valid ~= false and lab.name == LAB and lab.force == force, "native SE lab differs")
  check(lab.prototype and lab.prototype.get_researching_speed and lab.prototype.get_researching_speed() == 10, "native SE lab speed differs")
  check(power and power.valid ~= false and power.name == POWER and power.force == force, "fixture external power differs")
  local input = lab.get_inventory(defines.inventory.lab_input)
  check(input ~= nil, "native SE lab input differs")
  return input
end
local function input_counts(input)
  local out = {}; for _, pack in ipairs(SCIENCE) do out[pack] = input.get_item_count(pack) end; return out
end
local function feed(state)
  local input = assert_lab(state.lab, state.power, state.player)
  for _, pack in ipairs(SCIENCE) do
    local present = input.get_item_count(pack)
    if present < 32 then
      local requested = FEED_REQUEST - present
      check(input.insert{name = pack, count = requested} == requested, "native science feed differs: " .. pack)
      state.accepted[pack] = state.accepted[pack] + requested
    end
  end
  -- This documented entity buffer write complements the fixture-owned external
  -- producer; it does not alter the lab prototype or its researching speed.
  state.lab.energy = state.lab.electric_buffer_size
  check(state.lab.energy > 0 and state.lab.active ~= false, "native SE lab energy differs")
end
local function create_lab_and_power(force)
  local surface = game.surfaces[1]
  check(surface and surface.valid ~= false and type(surface.create_entity) == "function", "source surface differs")
  local power = surface.create_entity{name = POWER, position = {0, 0}, force = force}
  local lab = surface.create_entity{name = LAB, position = {3, 0}, force = force}
  return lab, power
end
local function frame(state)
  local target = technology(state.player, TARGET)
  return {
    level = target.level, enabled = target.enabled, visible = target.visible_when_disabled,
    current = state.player.current_research and state.player.current_research.name or false,
    progress = state.player.research_progress, queue = (function() local names = {}; for _, row in ipairs(state.player.research_queue or {}) do names[#names + 1] = row.name end; return names end)(),
    bonus = state.player.worker_robots_storage_bonus, science = input_counts(assert_lab(state.lab, state.power, state.player)),
    lab = {name = state.lab.name, unit_number = state.lab.unit_number, disabled_by_script = state.lab.disabled_by_script == true,
      energy = state.lab.energy, laboratory_speed_modifier = state.player.laboratory_speed_modifier}
  }
end
local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not same(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end
local function begin_source()
  check(script.active_mods["more-infinite-research"] == SOURCE_MIR, "source MIR identity differs")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "idle", "source begin phase differs")
  local player = game.forces.player
  check(player and player.valid ~= false, "player force differs")
  assert_active_tuple(); assert_settings(); assert_setup_declaration(player); assert_worker_contract(player)
  for _, declared in ipairs(fixture.rows) do
    local row = technology(player, declared.name)
    row.researched = true
  end
  local lab, power = create_lab_and_power(player)
  state.player, state.lab, state.power, state.input = player, lab, power, assert_lab(lab, power, player)
  state.speed_before, state.accepted, state.ordinary = player.laboratory_speed_modifier, {}, 0
  for _, pack in ipairs(SCIENCE) do state.accepted[pack] = 0 end
  player.laboratory_speed_modifier = state.speed_before + SPEED_STIMULUS
  check(player.laboratory_speed_modifier == state.speed_before + SPEED_STIMULUS, "laboratory speed stimulus differs")
  local target = technology(player, TARGET)
  check(player.add_research(target) == true, "could not begin ordinary worker research")
  -- Queue shape is established before any worker units are consumed.  The
  -- earned partial below is native progress on this current entry, never a
  -- fixture replacement of progress after the fact.
  player.research_queue = {target, target, technology(player, TAIL)}
  state.phase = "source-working"; feed(state); marker("source-begin", state, {setup_rows = #fixture.rows, lab_speed = 10})
end
local function source_partial(state)
  local target = technology(state.player, TARGET)
  check(target.level == 9 and state.player.current_research == target and state.player.research_progress > 0 and state.player.research_progress < 1, "source partial differs")
  state.lab.disabled_by_script = true
  state.player.laboratory_speed_modifier = state.speed_before
  check(state.player.laboratory_speed_modifier == state.speed_before, "source laboratory speed restoration differs")
  state.source_frame, state.phase = frame(state), "source-partial"
  game.server_save(SOURCE_SAVE)
  marker("source-partial", state, {partial = state.source_frame.progress, save = SOURCE_SAVE})
end
local function configuration(event)
  check(event and event.mod_startup_settings_changed == false and type(event.mod_changes) == "table", "configuration event differs")
  local change = event.mod_changes["more-infinite-research"]
  check(change and change.old_version == SOURCE_MIR and type(change.new_version) == "string" and change.new_version ~= SOURCE_MIR, "source-to-candidate identity differs")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "source-partial", "candidate source state differs")
  assert_active_tuple(); assert_settings(); assert_worker_contract(state.player)
  -- This comparison intentionally occurs before candidate feeding or queueing.
  check(same(frame(state), state.source_frame), "candidate changed source frame before observation")
  state.phase = "candidate-working"; state.candidate_events = 0
  state.lab.disabled_by_script = false
  state.player.laboratory_speed_modifier = state.speed_before + SPEED_STIMULUS
  feed(state); marker("candidate-pre-work", state, {source_partial = state.source_frame.progress})
end
local function close_candidate(state)
  local before = input_counts(assert_lab(state.lab, state.power, state.player))
  local target = technology(state.player, TARGET)
  check(state.player.add_research(target) == false, "cap level eleven unexpectedly queued")
  local after = input_counts(assert_lab(state.lab, state.power, state.player))
  check(same(before, after) and state.player.current_research == nil and #(state.player.research_queue or {}) == 0, "cap level eleven consumed or queued worker research")
  state.lab.disabled_by_script = true; state.player.laboratory_speed_modifier = state.speed_before
  state.closed, state.phase = frame(state), "closed"
  game.server_save(CANDIDATE_SAVE)
  marker("candidate-closed", state, {cap_attempt = "refused", candidate_events = state.candidate_events, save = CANDIDATE_SAVE})
end

script.on_init(function()
  if active() then storage[KEY] = {phase = "idle"} end
end)
script.on_load(function() cold_pending = true end)
remote.add_interface(FIXTURE, {begin = begin_source})
script.on_configuration_changed(function(event)
  if active() then configuration(event) end
end)
script.on_event(defines.events.on_research_finished, function(event)
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  local target = technology(state.player, TARGET)
  if event and event.by_script == true then fail("scripted worker completion differs") end
  check(event and event.research == target and event.by_script == false and event.research.force == state.player, "worker completion differs")
  check(event.research.level == target.level, "worker event cursor differs")
  if state.phase == "source-working" then
    check(target.level == state.ordinary + 5 and target.level <= 9, "source ordinary completion level differs")
    state.ordinary = state.ordinary + 1
    if target.level == 9 then state.phase = "source-await-partial" else feed(state) end
  elseif state.phase == "candidate-working" then
    check(target.level == 10 or target.level == 11, "candidate ordinary completion level differs")
    state.candidate_events = state.candidate_events + 1
    if target.level == 11 then close_candidate(state) else feed(state) end
  else fail("worker completion phase differs") end
end)
script.on_event(defines.events.on_tick, function()
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  if cold_pending then
    check(state.phase == "closed" and same(frame(state), state.closed), "cold process changed candidate endpoint")
    marker("cold-read", state, {cold_writes = 0}); cold_pending = false; return
  end
  if state.phase == "source-working" or state.phase == "candidate-working" then feed(state)
  elseif state.phase == "source-await-partial" then
    feed(state)
    if state.player.research_progress > 0 then source_partial(state) end
  elseif state.phase == "closed" then check(same(frame(state), state.closed), "closed endpoint changed") end
end)
