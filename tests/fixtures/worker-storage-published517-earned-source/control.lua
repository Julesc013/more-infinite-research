-- Runtime members were audited against official 2.0.77 runtime-api JSON
-- 594B4EC98CC5FBEE322D7380DB49A388AB38B0D69C06F00EAD877CFFBB37F578.
-- This is a source-only actor. Prerequisite grants are fixture setup; every
-- ordinary worker completion below must be native and by_script == false.
local fixture = require("__mir-fixture-mir5-worker-storage-published517-earned-source__/prerequisites")
local KEY = "mir5_worker_storage_published517_earned_source"
local FIXTURE = "mir-fixture-mir5-worker-storage-published517-earned-source"
local RESEARCH_FORCE = "mir5-worker-storage-published517-earned-source"
local TARGET = "mir-worker-storage-default-4"
local PREDECESSOR = "worker-robots-storage-3"
local TAIL = "mir-fixture-published517-earned-source-tail"
local LAB, POWER, POLE = "se-space-science-lab", "mir-fixture-published517-earned-source-power", "substation"
local SOURCE_MIR, UINT32_MAX = "5.0.20017", 4294967295
local SOURCE_SAVE, FEED_REQUEST, SPEED_STIMULUS = "mir5-published517-earned-source", 200, 115199
local SOURCE_QUEUE_ROWS = 5
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack",
  "utility-science-pack"
}
local RUNTIME_PREREQUISITES = {"utility-science-pack", PREDECESSOR}
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
local cold_pending, cold_phase, pending_setup = false, nil, nil
local force_vectors, vector_text, vector_count

local function bounded_refusal(message)
  if type(message) ~= "string" then return "invalid-refusal-message" end
  if #message > 160 then return string.sub(message, 1, 160) .. ":truncated" end
  return message
end
local function fail(message)
  log("[MIR_PUBLISHED517_EARNED_SOURCE] stage=refusal|message=" .. bounded_refusal(message))
  error("[mir5-worker-storage-published517-earned-source] " .. message)
end
local function check(value, message) if not value then fail(message) end end
local function finite(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end
local function close(left, right) return finite(left) and finite(right) and math.abs(left - right) <= 0.0000001 end
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, row in pairs(value) do out[key] = copy(row) end; return out
end
local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not same(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end
local function fixture_active() return script.active_mods[FIXTURE] == "0.1.0" end
local function source_active() return fixture_active() and script.active_mods["more-infinite-research"] == SOURCE_MIR end
local function technology(force, name)
  local row = force and force.technologies and force.technologies[name]
  check(row and row.valid ~= false and row.name == name, "technology differs: " .. name)
  return row
end
local function queue_names(force)
  local out = {}
  for index, row in ipairs(force.research_queue or {}) do out[index] = type(row) == "string" and row or row.name end
  return out
end
local function exact_names(left, right, label)
  check(#left == #right, label .. " count differs")
  for index, name in ipairs(right) do check(left[index] == name, label .. " differs") end
end
local function role_value(row)
  return table.concat({row.name, tostring(row.level), tostring(row.researched), tostring(row.enabled), tostring(row.visible_when_disabled)}, ":")
end
local function ordered_rows(values)
  local keys, rows = {}, {}
  for key in pairs(values) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do rows[#rows + 1] = tostring(key) .. ":" .. tostring(values[key]) end
  return table.concat(rows, ",")
end
local function science_rows(values)
  local rows = {}
  for _, name in ipairs(SCIENCE) do rows[#rows + 1] = name .. ":" .. string.format("%.17g", values[name]) end
  return table.concat(rows, ",")
end
local function assert_active_tuple()
  local expected = 0
  for name, version in pairs(CLOSURE) do
    check(script.active_mods[name] == version, "active source module differs: " .. name)
    expected = expected + 1
  end
  local count = 0
  for name in pairs(script.active_mods) do
    count = count + 1
    check(name == FIXTURE or name == "more-infinite-research" or CLOSURE[name] ~= nil, "unexpected active module: " .. name)
  end
  check(count == expected + 2, "active source module count differs")
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
local function observe_runtime_prerequisites(force, before_vectors)
  local row = technology(force, TARGET)
  local after_vectors = force_vectors()
  local vectors = "|before_force_count=" .. tostring(vector_count(before_vectors))
    .. "|before_vectors=" .. vector_text(before_vectors)
    .. "|after_force_count=" .. tostring(vector_count(after_vectors))
    .. "|after_vectors=" .. vector_text(after_vectors)
  local prerequisites = row.prerequisites
  if prerequisites == nil then
    log("[MIR_PUBLISHED517_EARNED_SOURCE] stage=runtime-pregrant|research_force=" .. force.name
      .. "|research_force_index=" .. tostring(force.index) .. "|target=" .. TARGET
      .. "|observed=unavailable|final_expected=utility-science-pack,worker-robots-storage-3"
      .. "|catalogue_declaration=worker-robots-storage-2,utility-science-pack,worker-robots-storage-3" .. vectors)
    fail("ordinary worker runtime prerequisite is unavailable")
  end
  local names, seen, count = {}, {}, 0
  for key, value in pairs(prerequisites) do
    local name = type(key) == "string" and key or value and value.name
    check(type(name) == "string" and name ~= "" and not seen[name], "ordinary worker runtime prerequisite is invalid")
    count = count + 1
    check(count <= 32, "ordinary worker runtime prerequisite exceeds bounded observation")
    seen[name], names[#names + 1] = true, name
  end
  table.sort(names)
  log("[MIR_PUBLISHED517_EARNED_SOURCE] stage=runtime-pregrant|research_force=" .. force.name
    .. "|research_force_index=" .. tostring(force.index) .. "|target=" .. TARGET
    .. "|observed_count=" .. tostring(#names) .. "|observed=" .. table.concat(names, ",")
    .. "|final_expected=utility-science-pack,worker-robots-storage-3"
    .. "|catalogue_declaration=worker-robots-storage-2,utility-science-pack,worker-robots-storage-3" .. vectors)
end
local function role_observed(value)
  if value == nil then return "unavailable:nil" end
  if type(value) == "boolean" then return "boolean:" .. tostring(value) end
  if type(value) == "number" then
    if finite(value) then return "number:" .. string.format("%.17g", value) end
    return "number:nonfinite"
  end
  return type(value)
end
local function observe_initial_role(row)
  local fields = {
    {name = "level", expected = 4},
    {name = "researched", expected = false},
    {name = "enabled", expected = true},
    {name = "visible", expected = true, key = "visible_when_disabled"}
  }
  local parts = {"[MIR_PUBLISHED517_EARNED_SOURCE] stage=runtime-initial-role", "target=" .. TARGET}
  for _, field in ipairs(fields) do
    local observed = row[field.key or field.name]
    parts[#parts + 1] = field.name .. "_observed=" .. role_observed(observed)
    parts[#parts + 1] = field.name .. "_expected=" .. role_observed(field.expected)
    parts[#parts + 1] = field.name .. "_matches=" .. tostring(observed == field.expected)
  end
  log(table.concat(parts, "|"))
end
local function assert_worker_contract(force)
  local row = technology(force, TARGET)
  check(row.prototype and row.prototype.max_level == UINT32_MAX, "ordinary worker maximum differs")
  exact_names(parent_names(row), RUNTIME_PREREQUISITES, "ordinary worker direct prerequisite")
  check(row.research_unit_count_formula == "675*1.5^(L-4)" and row.research_unit_energy == 3600, "ordinary worker unit differs")
  local seen, count = {}, 0
  for _, ingredient in pairs(row.research_unit_ingredients or {}) do
    check(type(ingredient) == "table" and type(ingredient.name) == "string" and ingredient.amount == 1 and not seen[ingredient.name],
      "ordinary worker science row differs")
    seen[ingredient.name], count = true, count + 1
  end
  check(count == #SCIENCE, "ordinary worker science count differs")
  for _, name in ipairs(SCIENCE) do check(seen[name], "ordinary worker science differs: " .. name) end
  local effects = row.prototype.effects
  check(type(effects) == "table" and #effects == 1 and effects[1].type == "worker-robot-storage" and close(effects[1].modifier, 1),
    "ordinary worker effect differs")
  observe_initial_role(row)
  check(row.level == 4 and row.researched == false and row.enabled == true and row.visible_when_disabled == true,
    "ordinary worker initial role differs")
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
  check(#fixture.rows == 101 and seen[PREDECESSOR] and seen["utility-science-pack"], "setup declaration count differs")
end

-- This is the complete six-component native vector needed for this source
-- slice. It records each existing force before creation, then proves that the
-- new dedicated force is the only member whose earned worker bonus changes.
force_vectors = function()
  local seen, out, count = {}, {}, 0
  for _, force in pairs(game.forces or {}) do
    check(force and force.valid ~= false and finite(force.index) and type(force.name) == "string", "force registry differs")
    if not seen[force.index] then
      seen[force.index] = true
      count = count + 1
      check(count <= 32, "force vector limit differs")
      local vector = {
        name = force.name,
        worker_robots_storage_bonus = force.worker_robots_storage_bonus,
        worker_robots_speed_modifier = force.worker_robots_speed_modifier,
        artillery_range_modifier = force.artillery_range_modifier,
        artillery_shell_gun_speed_modifier = force.get_gun_speed_modifier("artillery-shell"),
        laser_gun_speed_modifier = force.get_gun_speed_modifier("laser"),
        laser_ammo_damage_modifier = force.get_ammo_damage_modifier("laser")
      }
      for field, value in pairs(vector) do if field ~= "name" then check(finite(value), "force vector differs: " .. field) end end
      out[force.index] = vector
    end
  end
  check(next(out) ~= nil, "force vector is absent")
  return out
end
vector_text = function(vectors)
  local indexes, rows = {}, {}
  for index in pairs(vectors) do indexes[#indexes + 1] = index end
  table.sort(indexes)
  for _, index in ipairs(indexes) do
    local row = vectors[index]
    rows[#rows + 1] = string.format("%d:%q:%.17g:%.17g:%.17g:%.17g:%.17g:%.17g", index, row.name,
      row.worker_robots_storage_bonus, row.worker_robots_speed_modifier, row.artillery_range_modifier,
      row.artillery_shell_gun_speed_modifier, row.laser_gun_speed_modifier, row.laser_ammo_damage_modifier)
  end
  return table.concat(rows, ";")
end
vector_count = function(vectors)
  local count = 0
  for _ in pairs(vectors) do count = count + 1 end
  return count
end
local function assert_foreign_vectors(state, vectors, label)
  for index, expected in pairs(state.foreign_baseline) do
    check(same(vectors[index], expected), label .. " foreign force vector differs: " .. tostring(index))
  end
  for index in pairs(vectors) do
    check(index == state.research_force_index or state.foreign_baseline[index] ~= nil,
      label .. " foreign force membership differs: " .. tostring(index))
  end
end
local function assert_earned_vectors(state, label)
  local vectors = force_vectors()
  assert_foreign_vectors(state, vectors, label)
  local actual, expected = vectors[state.research_force_index], copy(state.research_baseline)
  check(actual ~= nil, label .. " dedicated force is absent")
  expected.worker_robots_storage_bonus = expected.worker_robots_storage_bonus + state.ordinary
  check(same(actual, expected), label .. " dedicated force vector differs")
  return vectors
end

local assert_lab
local function science_units(input, item, label)
  local prototype = prototypes.item[item]
  check(prototype and prototype.type == "tool" and type(prototype.get_durability) == "function",
    label .. " science prototype differs: " .. item)
  local total = 0
  for index = 1, #input do
    local stack = input[index]
    check(type(stack.valid_for_read) == "boolean", label .. " science read flag differs: " .. item)
    if stack.valid_for_read and stack.name == item then
      check(stack.quality and stack.quality.name == "normal", label .. " science quality differs: " .. item)
      check(stack.type == "tool" and stack.is_tool == true, label .. " science stack type differs: " .. item)
      check(type(stack.count) == "number" and stack.count >= 1 and stack.count % 1 == 0, label .. " science count differs: " .. item)
      local maximum, durability = prototype.get_durability(stack.quality), stack.durability
      check(close(maximum, 1) and finite(durability) and durability > 0 and durability <= maximum,
        label .. " science durability differs: " .. item)
      total = total + stack.count - 1 + durability / maximum
    end
  end
  return total
end
local function science_accounting(state)
  local input, remaining, debit = assert_lab(state.lab, state.power, state.pole, state.research_force), {}, {}
  for _, pack in ipairs(SCIENCE) do
    local issued = state.accepted[pack]
    remaining[pack] = science_units(input, pack, "native lab")
    check(finite(issued) and issued >= remaining[pack], "science accounting differs: " .. pack)
    debit[pack] = issued - remaining[pack]
  end
  return {issued = copy(state.accepted), remaining = remaining, debit = debit}
end
local function frame(state)
  local target = technology(state.research_force, TARGET)
  local progress = state.research_force.research_progress
  check(finite(progress), "research progress differs")
  return {
    research_force = {name = state.research_force_name, index = state.research_force_index},
    target = {name = target.name, level = target.level, researched = target.researched, enabled = target.enabled,
      visible = target.visible_when_disabled},
    current = state.research_force.current_research and state.research_force.current_research.name or false,
    progress = progress,
    queue = queue_names(state.research_force),
    vectors = force_vectors(),
    science = science_accounting(state)
  }
end
local function marker(phase, state, extra)
  local observed = frame(state)
  local fields = {
    "[MIR_SE_CARGO_NATIVE]", "mode=published517-source", "phase=" .. phase, "tick=" .. tostring(game.tick),
    "research_force=" .. observed.research_force.name, "research_force_index=" .. tostring(observed.research_force.index),
    "target=" .. observed.target.name, "level=" .. tostring(observed.target.level), "researched=" .. tostring(observed.target.researched),
    "enabled=" .. tostring(observed.target.enabled), "visible=" .. tostring(observed.target.visible),
    "current=" .. tostring(observed.current), "progress=" .. string.format("%.17g", observed.progress),
    "queue=" .. table.concat(observed.queue, ","), "ordinary=" .. tostring(state.ordinary),
    "force_count=" .. tostring(vector_count(observed.vectors)), "vectors_complete=true",
    "vectors=" .. vector_text(observed.vectors),
    "science_issued=" .. science_rows(observed.science.issued),
    "science_remaining=" .. science_rows(observed.science.remaining),
    "science_debit=" .. science_rows(observed.science.debit),
    "unit_count=" .. tostring(technology(state.research_force, TARGET).research_unit_count),
    "unit_time=" .. tostring(technology(state.research_force, TARGET).research_unit_energy)
  }
  if extra then for key, value in pairs(extra) do fields[#fields + 1] = key .. "=" .. tostring(value) end end
  log(table.concat(fields, "|"))
end
local function positioned(entity, x, y)
  return entity and entity.position and entity.position.x == x and entity.position.y == y
end
assert_lab = function(lab, power, pole, force)
  check(lab and lab.valid ~= false and lab.name == LAB and lab.force == force, "native SE lab differs")
  check(lab.prototype and lab.prototype.get_researching_speed and lab.prototype.get_researching_speed() == 10, "native SE lab speed differs")
  check(power and power.valid ~= false and power.name == POWER and power.force == force and positioned(power, 0, 0), "fixture power differs")
  check(pole and pole.valid ~= false and pole.name == POLE and pole.force == force and positioned(pole, 0, 6), "fixture pole differs")
  check(positioned(lab, 8.5, 0.5), "native SE lab position differs")
  check(lab.prototype.tile_width == 7 and lab.prototype.tile_height == 7 and power.prototype.tile_width == 2
    and power.prototype.tile_height == 2 and pole.prototype.tile_width == 2 and pole.prototype.tile_height == 2,
    "fixture grid differs")
  local network = lab.electric_network_id
  check(network ~= nil and power.electric_network_id == network and pole.electric_network_id == network, "fixture electric network differs")
  check(type(lab.is_connected_to_electric_network) == "function" and type(power.is_connected_to_electric_network) == "function"
    and lab.is_connected_to_electric_network() and power.is_connected_to_electric_network(), "fixture electric connection differs")
  local input = lab.get_inventory(defines.inventory.lab_input)
  check(input ~= nil and input.valid == true, "native SE lab input differs")
  return input
end
local function create_lab_and_power(force)
  local surface = game.surfaces[1]
  check(surface and surface.valid ~= false and type(surface.create_entity) == "function", "source surface differs")
  local power = surface.create_entity{name = POWER, position = {0, 0}, force = force}
  local lab = surface.create_entity{name = LAB, position = {8.5, 0.5}, force = force}
  local pole = surface.create_entity{name = POLE, position = {0, 6}, force = force}
  return lab, power, pole
end
local function feed(state)
  local input = assert_lab(state.lab, state.power, state.pole, state.research_force)
  for _, pack in ipairs(SCIENCE) do
    local present = input.get_item_count(pack)
    check(finite(present) and present >= 0, "science inventory differs: " .. pack)
    if present < 32 then
      local requested = FEED_REQUEST - present
      check(input.insert{name = pack, count = requested} == requested, "science feed differs: " .. pack)
      state.accepted[pack] = state.accepted[pack] + requested
    end
  end
end
local function start_research(state, lab, power, pole)
  state.lab, state.power, state.pole = lab, power, pole
  state.input = assert_lab(lab, power, pole, state.research_force)
  state.speed_before, state.accepted, state.ordinary = state.research_force.laboratory_speed_modifier, {}, 0
  for _, pack in ipairs(SCIENCE) do state.accepted[pack] = 0 end
  state.research_baseline = force_vectors()[state.research_force_index]
  check(state.research_baseline ~= nil, "research force baseline differs")
  state.research_force.laboratory_speed_modifier = state.speed_before + SPEED_STIMULUS
  check(state.research_force.laboratory_speed_modifier == state.speed_before + SPEED_STIMULUS, "laboratory speed stimulus differs")
  local target = technology(state.research_force, TARGET)
  check(state.research_force.add_research(target) == true, "could not begin ordinary worker research")
  local queue = {}
  for index = 1, SOURCE_QUEUE_ROWS do queue[index] = target end
  state.research_force.research_queue = queue
  state.phase = "source-working"
  feed(state)
  marker("source-begin", state, {setup_rows = #fixture.rows,
    source_archive = "B0BFA7418CFF77F249262C98864A386FA022C73E59B29EC30D028AE279A6AB27"})
end
local function stage_partial_queue(state)
  local target = technology(state.research_force, TARGET)
  state.research_force.research_queue = {target, target, technology(state.research_force, TAIL)}
  check(state.research_force.current_research == target and state.research_force.research_progress == 0, "source partial queue differs")
  state.phase = "source-await-partial"
  state.lab.disabled_by_script = false
  feed(state)
end
local function source_partial(state)
  local target = technology(state.research_force, TARGET)
  check(target.level == 9 and target.researched == false and target.enabled == true and target.visible_when_disabled == true,
    "source partial target role differs")
  check(state.research_force.current_research == target and state.research_force.research_progress > 0
    and state.research_force.research_progress < 1, "source partial progress differs")
  exact_names(queue_names(state.research_force), {TARGET, TARGET, TAIL}, "source partial queue")
  state.lab.disabled_by_script = true
  state.research_force.laboratory_speed_modifier = state.speed_before
  check(state.research_force.laboratory_speed_modifier == state.speed_before, "source laboratory speed restoration differs")
  assert_earned_vectors(state, "source partial")
  state.source_frame, state.phase = frame(state), "source-partial"
  for _, pack in ipairs(SCIENCE) do check(state.source_frame.science.debit[pack] > 0, "source science debit differs: " .. pack) end
  game.server_save(SOURCE_SAVE)
  marker("source-partial", state, {save = SOURCE_SAVE})
end
local function begin_source()
  check(source_active(), "published source identity differs")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "idle", "source begin phase differs")
  check(pending_setup == nil, "source setup already scheduled")
  assert_active_tuple(); assert_settings()
  state.foreign_baseline = force_vectors()
  check(game.forces[RESEARCH_FORCE] == nil, "dedicated research force already exists")
  local force = game.create_force(RESEARCH_FORCE)
  check(force and force.valid ~= false and force.name == RESEARCH_FORCE and finite(force.index), "dedicated research force differs")
  state.research_force, state.research_force_name, state.research_force_index = force, force.name, force.index
  observe_runtime_prerequisites(force, state.foreign_baseline)
  assert_setup_declaration(force); assert_worker_contract(force)
  for _, declared in ipairs(fixture.rows) do technology(force, declared.name).researched = true end
  assert_foreign_vectors(state, force_vectors(), "source setup")
  local lab, power, pole = create_lab_and_power(force)
  pending_setup = {tick = game.tick, lab = lab, power = power, pole = pole}
end

script.on_init(function()
  if source_active() then storage[KEY] = {phase = "idle"} end
end)
script.on_load(function()
  cold_pending = true
  local state = storage[KEY]
  cold_phase = type(state) == "table" and state.phase or nil
end)
remote.add_interface(FIXTURE, {begin = begin_source})
script.on_configuration_changed(function()
  if fixture_active() then fail("configuration changes are outside this published-source fixture") end
end)
script.on_event(defines.events.on_research_finished, function(event)
  if not source_active() then return end
  local state = storage[KEY]
  if type(state) ~= "table" or not event or not event.research or event.research.name ~= TARGET then return end
  check(state.phase == "source-working" and state.research_force ~= nil, "ordinary worker completion phase differs")
  check(event.research.force == state.research_force and event.research == technology(state.research_force, TARGET)
    and event.by_script == false, "ordinary worker completion differs")
  local target = technology(state.research_force, TARGET)
  local next_level = target.level + (target.researched and 1 or 0)
  check(next_level == state.ordinary + 5 and next_level <= 9, "ordinary worker completion level differs")
  state.ordinary = state.ordinary + 1
  assert_earned_vectors(state, "source ordinary")
  if next_level == 9 then
    state.lab.disabled_by_script = true
    state.phase = "source-await-queue"
  else
    feed(state)
  end
  marker("source-ordinary", state, {completed_level = next_level - 1, next_level = next_level, by_script = false})
end)
script.on_event(defines.events.on_tick, function(event)
  if not source_active() then return end
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  if pending_setup then
    if game.tick == pending_setup.tick then return end
    local setup = pending_setup
    pending_setup = nil
    check(event and event.tick == setup.tick + 1 and state.phase == "idle", "source setup update boundary differs")
    start_research(state, setup.lab, setup.power, setup.pole)
    return
  end
  if cold_pending then
    if cold_phase == "source-partial" then
      check(state.phase == "source-partial" and same(frame(state), state.source_frame), "cold source partial differs")
      assert_earned_vectors(state, "cold source partial")
      marker("source-cold-read", state, {cold_writes = 0})
      cold_pending, cold_phase = false, nil
      return
    end
    check(cold_phase == "idle" or cold_phase == "source-working", "unexpected cold source phase")
    cold_pending, cold_phase = false, nil
  end
  if state.phase == "source-working" then
    feed(state)
  elseif state.phase == "source-await-queue" then
    stage_partial_queue(state)
  elseif state.phase == "source-await-partial" then
    feed(state)
    if state.research_force.research_progress > 0 then source_partial(state) end
  elseif state.phase == "source-partial" then
    check(same(frame(state), state.source_frame), "saved source partial changed")
  elseif state.phase ~= "idle" then
    fail("source phase differs")
  end
end)
