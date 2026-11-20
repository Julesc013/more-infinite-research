-- Runtime members were audited against official 2.0.77 runtime-api JSON
-- 594B4EC98CC5FBEE322D7380DB49A388AB38B0D69C06F00EAD877CFFBB37F578.
-- Genuine SE cargo worker-storage actor.  The explicit prerequisite grants
-- below are setup only; all worker rows are advanced by native lab work and
-- observed through on_research_finished with by_script == false.
local fixture = require("__mir-fixture-mir5-worker-storage-se-cap-ten-native__/prerequisites")
local KEY = "mir5_worker_storage_se_cap_ten_native"
local FIXTURE = "mir-fixture-mir5-worker-storage-se-cap-ten-native"
local POWER = "mir-fixture-worker-storage-se-cap-ten-power"
local POLE = "substation"
local TAIL = "mir-fixture-worker-storage-se-cap-ten-tail"
local SOURCE, CANDIDATE, HEAD = "worker-robots-storage-4", "mir-worker-storage-default-4", "mir-worker-storage-head-4"
local PREDECESSOR, LAB = "worker-robots-storage-3", "se-space-science-lab"
local SOURCE_MIR, UINT32_MAX = "4.7.20002", 4294967295
local SPEED_STIMULUS, FEED_REQUEST = 115199, 200
-- Five native rows cover ordinary levels 4 through 8.  After the fifth
-- completion has selected no successor, the next tick (while the lab is
-- paused) installs only the retained level-nine/tail work needed for the
-- source partial and candidate hand-off.  This does not assume an unbounded
-- native research queue.
local SOURCE_QUEUE_ROWS = 5
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
local cold_pending, cold_phase = false, nil

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
local function queue_names(player)
  local queue = {}
  for index, row in ipairs(player.research_queue or {}) do queue[index] = type(row) == "string" and row or row.name end
  return queue
end
local function ordered_numbers(values)
  local keys, rows = {}, {}
  for key in pairs(values) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do rows[#rows + 1] = tostring(key) .. ":" .. tostring(values[key]) end
  return table.concat(rows, ",")
end
local function science_values(values)
  local rows = {}
  for _, pack in ipairs(SCIENCE) do rows[#rows + 1] = pack .. ":" .. tostring(values[pack]) end
  return table.concat(rows, ",")
end
local function force_bonuses()
  local seen, out = {}, {}
  for _, force in pairs(game.forces or {}) do
    if force and force.valid ~= false and not seen[force.index] then
      local bonus = force.worker_robots_storage_bonus
      check(type(bonus) == "number" and bonus == bonus and bonus ~= math.huge and bonus ~= -math.huge,
        "force worker bonus differs")
      seen[force.index], out[force.index] = true, bonus
    end
  end
  check(next(out) ~= nil, "force worker bonus set differs")
  return out
end
local function assert_earned_bonuses(state, source_events, candidate_events, label)
  local baseline, observed = state.force_bonus_baseline, force_bonuses()
  check(type(baseline) == "table" and type(state.player.index) == "number", label .. " worker bonus baseline differs")
  for index, expected in pairs(baseline) do
    local actual = observed[index]
    check(actual ~= nil, label .. " worker bonus force differs")
    if index == state.player.index then
      check(close(actual, expected + source_events + candidate_events), label .. " earned worker bonus differs")
    else
      check(close(actual, expected), label .. " foreign worker bonus differs")
    end
  end
  for index in pairs(observed) do check(baseline[index] ~= nil, label .. " worker bonus membership differs") end
  return observed
end
local function science_units(input, item, label)
  local prototype = prototypes.item[item]
  check(prototype and prototype.type == "tool" and type(prototype.get_durability) == "function",
    label .. " native science prototype differs: " .. item)
  local total, stacks = 0, 0
  for index = 1, #input do
    local stack = input[index]
    if stack.valid_for_read and stack.name == item then
      local quality = stack.quality
      check(quality and quality.name == "normal", label .. " native science quality differs: " .. item)
      check(stack.type == "tool" and stack.is_tool == true, label .. " native science stack type differs: " .. item)
      check(type(stack.count) == "number" and stack.count >= 1 and stack.count % 1 == 0,
        label .. " native science count differs: " .. item)
      local maximum, durability = prototype.get_durability(quality), stack.durability
      check(close(maximum, 1) and type(durability) == "number" and durability > 0 and durability <= maximum,
        label .. " native science durability differs: " .. item)
      total, stacks = total + stack.count - 1 + durability / maximum, stacks + 1
    end
  end
  check(stacks > 0, label .. " native science stack is absent: " .. item)
  return total
end
local assert_lab
local function science_accounting(state)
  local input, remaining, debit = assert_lab(state.lab, state.power, state.pole, state.player), {}, {}
  for _, pack in ipairs(SCIENCE) do
    local issued = state.accepted[pack]
    remaining[pack] = science_units(input, pack, "native lab")
    check(type(issued) == "number" and issued >= remaining[pack], "science accounting differs: " .. pack)
    debit[pack] = issued - remaining[pack]
  end
  return {issued = copy(state.accepted), remaining = remaining, debit = debit}
end
local function frame(state)
  local target = technology(state.player, state.worker)
  local difficulty = game.difficulty_settings
  check(difficulty and type(difficulty.technology_price_multiplier) == "number"
    and difficulty.technology_price_multiplier == difficulty.technology_price_multiplier
    and difficulty.technology_price_multiplier ~= math.huge and difficulty.technology_price_multiplier ~= -math.huge,
    "technology price context differs")
  check(type(state.player.laboratory_productivity_bonus) == "number"
    and state.player.laboratory_productivity_bonus == state.player.laboratory_productivity_bonus
    and state.player.laboratory_productivity_bonus ~= math.huge and state.player.laboratory_productivity_bonus ~= -math.huge,
    "laboratory productivity context differs")
  return {
    worker = state.worker,
    target = {name = target.name, level = target.level, researched = target.researched,
      enabled = target.enabled, visible = target.visible_when_disabled},
    current = state.player.current_research and state.player.current_research.name or false,
    progress = state.player.research_progress, queue = queue_names(state.player),
    bonus = state.player.worker_robots_storage_bonus, force_bonuses = force_bonuses(),
    science = science_accounting(state),
    lab = {name = state.lab.name, unit_number = state.lab.unit_number, disabled_by_script = state.lab.disabled_by_script == true,
      energy = state.lab.energy, laboratory_speed_modifier = state.player.laboratory_speed_modifier,
      laboratory_productivity_bonus = state.player.laboratory_productivity_bonus,
      technology_price_multiplier = difficulty.technology_price_multiplier}
  }
end
local function marker(phase, state, extra)
  local observed = frame(state)
  local fields = {
    "[MIR_SE_CARGO_NATIVE]", "phase=" .. phase, "tick=" .. tostring(game.tick), "worker=" .. observed.worker,
    "level=" .. tostring(observed.target.level), "current=" .. tostring(observed.current),
    "progress=" .. tostring(observed.progress), "queue=" .. table.concat(observed.queue, ","),
    "ordinary=" .. tostring(state.ordinary), "bonus=" .. tostring(observed.bonus),
    "force_bonuses=" .. ordered_numbers(observed.force_bonuses),
    "laboratory_productivity_bonus=" .. tostring(observed.lab.laboratory_productivity_bonus),
    "technology_price_multiplier=" .. tostring(observed.lab.technology_price_multiplier),
    "science_issued=" .. science_values(observed.science.issued),
    "science_remaining=" .. science_values(observed.science.remaining),
    "science_debit=" .. science_values(observed.science.debit),
    "unit_count=" .. tostring(technology(state.player, state.worker).research_unit_count),
    "unit_time=" .. tostring(technology(state.player, state.worker).research_unit_energy),
    "settings_file_values=true"
  }
  if state.force_bonus_baseline then
    fields[#fields + 1] = "expected_worker_bonus=" .. tostring(
      state.force_bonus_baseline[state.player.index] + state.ordinary + (state.candidate_events or 0))
  end
  if state.configuration_startup_settings_changed ~= nil then
    fields[#fields + 1] = "configuration_startup_settings_changed=" .. tostring(state.configuration_startup_settings_changed)
  end
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
local function role_value(row)
  return table.concat({row.name, tostring(row.level), tostring(row.researched), tostring(row.enabled), tostring(row.visible_when_disabled)}, ":")
end
local function assert_worker_contract(force, name)
  local target = technology(force, name)
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
local function positioned(entity, x, y)
  local position = entity and entity.position
  return position and position.x == x and position.y == y
end
assert_lab = function(lab, power, pole, force)
  check(lab and lab.valid ~= false and lab.name == LAB and lab.force == force, "native SE lab differs")
  check(lab.prototype and lab.prototype.get_researching_speed and lab.prototype.get_researching_speed() == 10, "native SE lab speed differs")
  check(power and power.valid ~= false and power.name == POWER and power.force == force and positioned(power, 0, 0),
    "fixture external power differs")
  check(pole and pole.valid ~= false and pole.name == POLE and pole.force == force and positioned(pole, 0, 6),
    "fixture substation differs")
  check(positioned(lab, 8, 0), "native SE lab position differs")
  local network = lab.electric_network_id
  check(network ~= nil and power.electric_network_id == network and pole.electric_network_id == network,
    "fixture electric network differs: lab=" .. tostring(network) .. " power=" .. tostring(power.electric_network_id)
      .. " pole=" .. tostring(pole.electric_network_id))
  check(type(lab.is_connected_to_electric_network) == "function"
    and type(power.is_connected_to_electric_network) == "function"
    and lab.is_connected_to_electric_network()
    and power.is_connected_to_electric_network(), "fixture electric network differs")
  local input = lab.get_inventory(defines.inventory.lab_input)
  check(input ~= nil, "native SE lab input differs")
  return input
end
local function feed(state)
  local input = assert_lab(state.lab, state.power, state.pole, state.player)
  for _, pack in ipairs(SCIENCE) do
    local present = input.get_item_count(pack)
    if present < 32 then
      local requested = FEED_REQUEST - present
      check(input.insert{name = pack, count = requested} == requested, "native science feed differs: " .. pack)
      state.accepted[pack] = state.accepted[pack] + requested
    end
  end
end
local function create_lab_and_power(force)
  local surface = game.surfaces[1]
  check(surface and surface.valid ~= false and type(surface.create_entity) == "function", "source surface differs")
  local power = surface.create_entity{name = POWER, position = {0, 0}, force = force}
  local lab = surface.create_entity{name = LAB, position = {8, 0}, force = force}
  local pole = surface.create_entity{name = POLE, position = {0, 6}, force = force}
  return lab, power, pole
end
local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not same(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end
local function mapped_source_name(name) return name == SOURCE and CANDIDATE or name end
local function expected_candidate_frame(source)
  local expected = copy(source)
  expected.worker, expected.target.name = CANDIDATE, CANDIDATE
  expected.current = mapped_source_name(expected.current)
  for index, name in ipairs(expected.queue) do expected.queue[index] = mapped_source_name(name) end
  return expected
end
local function assert_candidate_transfer(state)
  local expected = expected_candidate_frame(state.source_frame)
  check(same(frame(state), expected), "candidate changed source frame before observation")
  local canonical, gate = technology(state.player, SOURCE), technology(state.player, HEAD)
  check(canonical.level == 5 and canonical.researched == false and canonical.enabled == false
    and canonical.visible_when_disabled == state.source_canonical.visible, "candidate canonical handoff differs")
  check(gate.level == 5 and gate.researched == false and gate.enabled == false
    and gate.visible_when_disabled == false, "candidate head debit differs")
end
local function assert_tail_current(state, label)
  check(state.player.current_research and state.player.current_research.name == TAIL, label .. " tail current differs")
  exact_names(queue_names(state.player), {TAIL}, label .. " tail queue")
end
local function begin_source()
  check(script.active_mods["more-infinite-research"] == SOURCE_MIR, "source MIR identity differs")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "idle", "source begin phase differs")
  local player = game.forces.player
  check(player and player.valid ~= false, "player force differs")
  assert_active_tuple(); assert_settings(); assert_setup_declaration(player); assert_worker_contract(player, SOURCE)
  for _, declared in ipairs(fixture.rows) do
    local row = technology(player, declared.name)
    row.researched = true
  end
  local lab, power, pole = create_lab_and_power(player)
  state.player, state.lab, state.power, state.pole, state.input = player, lab, power, pole, assert_lab(lab, power, pole, player)
  state.speed_before, state.accepted, state.ordinary, state.worker = player.laboratory_speed_modifier, {}, 0, SOURCE
  state.force_bonus_baseline = force_bonuses()
  for _, pack in ipairs(SCIENCE) do state.accepted[pack] = 0 end
  player.laboratory_speed_modifier = state.speed_before + SPEED_STIMULUS
  check(player.laboratory_speed_modifier == state.speed_before + SPEED_STIMULUS, "laboratory speed stimulus differs")
  local target = technology(player, SOURCE)
  check(player.add_research(target) == true, "could not begin ordinary worker research")
  -- Queue shape is established before any worker units are consumed.  The
  -- earned partial below is native progress on this current entry, never a
  -- fixture replacement of progress after the fact.
  local queue = {}
  for index = 1, SOURCE_QUEUE_ROWS do queue[index] = target end
  player.research_queue = queue
  state.phase = "source-working"; feed(state); marker("source-begin", state, {setup_rows = #fixture.rows, lab_speed = 10, queue_rows = SOURCE_QUEUE_ROWS})
end
local function source_partial(state)
  local target = technology(state.player, SOURCE)
  check(target.level == 9 and state.player.current_research == target and state.player.research_progress > 0 and state.player.research_progress < 1, "source partial differs")
  exact_names(queue_names(state.player), {SOURCE, SOURCE, TAIL}, "source partial queue")
  state.lab.disabled_by_script = true
  state.player.laboratory_speed_modifier = state.speed_before
  check(state.player.laboratory_speed_modifier == state.speed_before, "source laboratory speed restoration differs")
  state.source_frame, state.source_canonical, state.source_role, state.phase = frame(state),
    {level = target.level, researched = target.researched, enabled = target.enabled, visible = target.visible_when_disabled},
    role_value(target), "source-partial"
  for _, pack in ipairs(SCIENCE) do check(state.source_frame.science.debit[pack] > 0, "source native science debit differs: " .. pack) end
  assert_earned_bonuses(state, state.ordinary, 0, "source partial")
  game.server_save(SOURCE_SAVE)
  marker("source-partial", state, {partial = state.source_frame.progress, save = SOURCE_SAVE, source_role = state.source_role})
end
local function stage_source_partial_queue(state)
  local target = technology(state.player, SOURCE)
  check(target.level == 9 and state.player.current_research == nil, "source queue staging differs")
  state.player.research_queue = {target, target, technology(state.player, TAIL)}
  exact_names(queue_names(state.player), {SOURCE, SOURCE, TAIL}, "source staged queue")
  state.lab.disabled_by_script = false
  state.phase = "source-await-partial"
  feed(state)
  marker("source-queue-staged", state, {queue_rows = 3})
end
local function configuration(event)
  check(event and type(event.mod_startup_settings_changed) == "boolean" and type(event.mod_changes) == "table", "configuration event differs")
  local change = event.mod_changes["more-infinite-research"]
  check(change and change.old_version == SOURCE_MIR and type(change.new_version) == "string" and change.new_version ~= SOURCE_MIR, "source-to-candidate identity differs")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "source-partial", "candidate source state differs")
  assert_active_tuple(); assert_settings(); state.worker = CANDIDATE; assert_worker_contract(state.player, CANDIDATE)
  -- This comparison intentionally occurs before candidate feeding or queueing.
  assert_candidate_transfer(state)
  assert_earned_bonuses(state, state.ordinary, 0, "candidate transfer")
  state.configuration_startup_settings_changed = event.mod_startup_settings_changed
  state.phase = "candidate-working"; state.candidate_events = 0
  state.lab.disabled_by_script = false
  state.player.laboratory_speed_modifier = state.speed_before + SPEED_STIMULUS
  feed(state); marker("candidate-pre-work", state, {
    source_partial = state.source_frame.progress,
    source_role = state.source_role,
    canonical_role = role_value(technology(state.player, SOURCE)),
    private_role = role_value(technology(state.player, CANDIDATE)),
    head_role = role_value(technology(state.player, HEAD))
  })
end
local function close_candidate(state)
  local before = science_accounting(state)
  local target = technology(state.player, CANDIDATE)
  check(target.level == 11 and target.enabled == false, "candidate cap disabled state differs")
  assert_earned_bonuses(state, state.ordinary, state.candidate_events, "candidate cap")
  assert_tail_current(state, "candidate cap")
  check(state.player.add_research(target) == false, "cap level eleven unexpectedly queued")
  local after = science_accounting(state)
  check(same(before, after), "cap level eleven consumed science")
  assert_tail_current(state, "candidate cap")
  state.player.laboratory_speed_modifier = state.speed_before
  for _, pack in ipairs(SCIENCE) do check(after.debit[pack] > state.source_frame.science.debit[pack], "candidate native science debit differs: " .. pack) end
  state.closed, state.phase = frame(state), "closed"
  game.server_save(CANDIDATE_SAVE)
  marker("candidate-closed", state, {cap_attempt = "refused", candidate_events = state.candidate_events, save = CANDIDATE_SAVE})
end

script.on_init(function()
  if active() then storage[KEY] = {phase = "idle"} end
end)
script.on_load(function()
  cold_pending = true
  local state = storage[KEY]
  cold_phase = type(state) == "table" and state.phase or nil
end)
remote.add_interface(FIXTURE, {begin = begin_source})
script.on_configuration_changed(function(event)
  if active() then configuration(event) end
end)
script.on_event(defines.events.on_research_finished, function(event)
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  check(event and event.research and type(event.research.name) == "string", "research completion event differs")
  if event.research.name ~= SOURCE and event.research.name ~= CANDIDATE then return end
  if event and event.by_script == true then fail("scripted worker completion differs") end
  local target = technology(state.player, state.worker)
  check(event and event.research == target and event.by_script == false and event.research.force == state.player, "worker completion differs")
  check(event.research.level == target.level, "worker event cursor differs")
  if state.phase == "source-working" then
    check(target.level == state.ordinary + 5 and target.level <= 9,
      "source ordinary completion level differs: observed=" .. tostring(target.level) .. " expected=" .. tostring(state.ordinary + 5))
    state.ordinary = state.ordinary + 1
    assert_earned_bonuses(state, state.ordinary, 0, "source ordinary")
    if target.level == 9 then
      state.lab.disabled_by_script = true
      state.phase = "source-await-queue"
    else feed(state) end
  elseif state.phase == "candidate-working" then
    check(target.level == state.candidate_events + 10 and target.level <= 11, "candidate ordinary completion level differs")
    state.candidate_events = state.candidate_events + 1
    assert_earned_bonuses(state, state.ordinary, state.candidate_events, "candidate ordinary")
    if target.level == 11 then
      state.lab.disabled_by_script = true
      state.phase = "candidate-await-cap"
    else feed(state) end
  else fail("worker completion phase differs") end
end)
script.on_event(defines.events.on_tick, function()
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  if cold_pending then
    if cold_phase == "closed" then
      check(state.phase == "closed" and same(frame(state), state.closed), "cold process changed candidate endpoint")
      marker("cold-read", state, {cold_writes = 0}); cold_pending, cold_phase = false, nil; return
    elseif cold_phase == "idle" then
      check(state.phase == "idle" or state.phase == "source-working", "cold load phase differs")
    elseif cold_phase == "source-partial" then
      check(state.phase == "candidate-working", "cold load phase differs")
    else
      fail("cold load phase differs")
    end
    cold_pending, cold_phase = false, nil
  end
  if state.phase == "source-working" or state.phase == "candidate-working" then feed(state)
  elseif state.phase == "source-await-queue" then stage_source_partial_queue(state)
  elseif state.phase == "source-await-partial" then
    feed(state)
    if state.player.research_progress > 0 then source_partial(state) end
  elseif state.phase == "candidate-await-cap" then close_candidate(state)
  elseif state.phase == "closed" then check(same(frame(state), state.closed), "closed endpoint changed") end
end)
