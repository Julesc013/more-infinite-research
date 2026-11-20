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
local SOURCE_MIR, CURRENT_MIR, UINT32_MAX = "4.7.20002", "5.0.20018", 4294967295
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
local pending_setup

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
  local total = 0
  for index = 1, #input do
    local stack = input[index]
    local readable = stack.valid_for_read
    check(type(readable) == "boolean", label .. " native science read flag differs: " .. item)
    if readable and stack.name == item then
      local quality = stack.quality
      check(quality and quality.name == "normal", label .. " native science quality differs: " .. item)
      check(stack.type == "tool" and stack.is_tool == true, label .. " native science stack type differs: " .. item)
      check(type(stack.count) == "number" and stack.count >= 1 and stack.count % 1 == 0,
        label .. " native science count differs: " .. item)
      local maximum, durability = prototype.get_durability(quality), stack.durability
      check(close(maximum, 1) and type(durability) == "number" and durability > 0 and durability <= maximum,
        label .. " native science durability differs: " .. item)
      total = total + stack.count - 1 + durability / maximum
    end
  end
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
local function assert_cap12_settings()
  for _, expected in ipairs(SETTINGS) do
    local value = expected.name == "mir-max-level-worker-robots-storage" and 12 or expected.value
    local row = settings.startup and settings.startup[expected.name]
    check(type(row) == "table" and row.valid ~= false and type(row.value) == type(value),
      "cap12 startup setting differs: " .. expected.name)
    check(row.value == value, "cap12 startup setting value differs: " .. expected.name)
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
local function setup_value(read)
  local ok, value = pcall(read)
  if not ok then return "unavailable:" .. tostring(value):gsub("[\r\n]", " "):sub(1, 96) end
  return value == nil and "nil" or tostring(value)
end
local function setup_box(box)
  local left, right = box.left_top or box[1], box.right_bottom or box[2]
  return table.concat({left.x or left[1], left.y or left[2], right.x or right[1], right.y or right[2]}, ",")
end
local function observe_setup(stage, lab, power, pole)
  local rows = {}
  for _, row in ipairs({{role="power", entity=power, x=0, y=0}, {role="lab", entity=lab, x=8.5, y=0.5},
      {role="pole", entity=pole, x=0, y=6}}) do
    local entity = row.entity
    if entity == nil or entity.valid == false then
      rows[#rows + 1] = row.role .. " requested=" .. row.x .. "," .. row.y
        .. " status=" .. (entity == nil and "absent" or "invalid")
        .. " actual=unavailable grid=unavailable collision=unavailable selection=unavailable network=unavailable connected=unavailable"
    else rows[#rows + 1] = table.concat({row.role, "requested=" .. row.x .. "," .. row.y,
      "actual=" .. setup_value(function() return entity.position.x .. "," .. entity.position.y end),
      "valid=" .. setup_value(function() return entity.valid end),
      "grid=" .. setup_value(function() return entity.prototype.tile_width .. "," .. entity.prototype.tile_height end),
      "collision=" .. setup_value(function() return setup_box(entity.prototype.collision_box) end),
      "selection=" .. setup_value(function() return setup_box(entity.prototype.selection_box) end),
      "network=" .. setup_value(function() return entity.electric_network_id end),
      "connected=" .. setup_value(function() return entity.is_connected_to_electric_network() end)}, " ") end
  end
  log("[MIR_SE_CARGO_SETUP] stage=" .. stage .. " tick=" .. game.tick .. " " .. table.concat(rows, " | "))
end
assert_lab = function(lab, power, pole, force)
  check(lab and lab.valid ~= false and lab.name == LAB and lab.force == force, "native SE lab differs")
  check(lab.prototype and lab.prototype.get_researching_speed and lab.prototype.get_researching_speed() == 10, "native SE lab speed differs")
  check(power and power.valid ~= false and power.name == POWER and power.force == force and positioned(power, 0, 0),
    "fixture external power differs")
  check(pole and pole.valid ~= false and pole.name == POLE and pole.force == force and positioned(pole, 0, 6),
    "fixture substation differs")
  check(positioned(lab, 8.5, 0.5), "native SE lab position differs: expected=8.5,0.5 observed="
    .. tostring(lab.position and lab.position.x) .. "," .. tostring(lab.position and lab.position.y))
  check(lab.prototype.tile_width == 7 and lab.prototype.tile_height == 7
    and power.prototype.tile_width == 2 and power.prototype.tile_height == 2
    and pole.prototype.tile_width == 2 and pole.prototype.tile_height == 2, "fixture native tile grid differs")
  local network = lab.electric_network_id
  check(network ~= nil and power.electric_network_id == network and pole.electric_network_id == network,
    "fixture electric network differs: lab=" .. tostring(network) .. " power=" .. tostring(power.electric_network_id)
      .. " pole=" .. tostring(pole.electric_network_id))
  check(type(lab.is_connected_to_electric_network) == "function"
    and type(power.is_connected_to_electric_network) == "function"
    and lab.is_connected_to_electric_network()
    and power.is_connected_to_electric_network(), "fixture electric network differs")
  local input = lab.get_inventory(defines.inventory.lab_input)
  check(input ~= nil and input.valid == true, "native SE lab input differs")
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
  -- The native seven-tile lab uses a tile-center anchor with normal snapping.
  local lab = surface.create_entity{name = LAB, position = {8.5, 0.5}, force = force}
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
-- This is a bounded diagnostic for the one opaque transferred-frame refusal.
-- It only consumes the fixture's already-constructed plain frame values; it
-- neither traverses Factorio objects nor changes state, research, or queues.
local FRAME_DIFF_MAX, FRAME_DIFF_DEPTH, FRAME_DIFF_VISITS, FRAME_DIFF_KEYS = 24, 6, 128, 64
local source_reload_observed = false
-- This is intentionally a finite, read-only contributor snapshot.  The
-- packet-side temporary diagnostic calls it at selected callback boundaries;
-- ordinary fixture play never calls it and it has no research authority.
local CONTRIBUTION_PREFIX = "[MIR_SE_FORCE_CONTRIBUTIONS]"
local CONTRIBUTION_FORCE_LIMIT, CONTRIBUTION_REGISTRY_KEY_LIMIT = 16, 64
local CONTRIBUTION_EFFECT_LIMIT, CONTRIBUTION_NAME_LIMIT = 16, 160
local CONTRIBUTION_PHASES = {
  ["source-reload"] = true,
  ["mir-config-entry"] = true,
  ["mir-worker-applied"] = true,
  ["mir-config-exit"] = true,
  ["candidate-transfer"] = true,
  ["cap12-configuration"] = true,
  ["candidate-closed"] = true,
  ["cold-read"] = true
}
local CONTRIBUTION_TECHNOLOGIES = {
  "worker-robots-storage-1", "worker-robots-storage-2", "worker-robots-storage-3", "worker-robots-storage-4",
  "mir-worker-storage-default-4", "mir-worker-storage-head-4", "mir-worker-storage-published517-4"
}
local function contribution_finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function contribution_number(value)
  return contribution_finite(value) and string.format("%.17g", value) or "unavailable"
end
local function contribution_boolean(value)
  return type(value) == "boolean" and tostring(value) or "unavailable"
end
local function contribution_name(value)
  if type(value) ~= "string" then return "<unavailable>", true end
  if #value > CONTRIBUTION_NAME_LIMIT then return value:sub(1, CONTRIBUTION_NAME_LIMIT) .. "...", true end
  return value, false
end
local function contribution_read(object, field)
  local ok, value = pcall(function() return object[field] end)
  if not ok then return nil, false end
  return value, true
end
local function contribution_effects(row)
  local prototype, available = contribution_read(row, "prototype")
  if not available or prototype == nil then return "effects=unavailable", false, true end
  local effects, effects_available = contribution_read(prototype, "effects")
  if not effects_available or type(effects) ~= "table" then return "effects=unavailable", false, true end
  local count_available, count = pcall(function() return #effects end)
  if not count_available or type(count) ~= "number" or count < 0 or count % 1 ~= 0 then return "effects=unavailable", false, true end
  if count > CONTRIBUTION_EFFECT_LIMIT then return "effects=truncated", true, false end
  local fields = {"type", "modifier", "recipe", "change"}
  local rows, truncated, unavailable = {"effects_count=" .. string.format("%.17g", count)}, false, false
  for index = 1, count do
    local effect, effect_available = contribution_read(effects, index)
    if not effect_available or type(effect) ~= "table" then return "effects=unavailable", false, true end
    for _, field in ipairs(fields) do
      local value, value_available = contribution_read(effect, field)
      local encoded
      if not value_available then encoded = "unavailable"; unavailable = true
      elseif value == nil then encoded = "missing"
      elseif type(value) == "string" then
        local name, value_truncated = contribution_name(value)
        encoded = string.format("%q", name); truncated = truncated or value_truncated
      elseif type(value) == "number" then
        encoded = contribution_number(value); unavailable = unavailable or not contribution_finite(value)
      elseif type(value) == "boolean" then encoded = tostring(value)
      else encoded = "unavailable"; unavailable = true end
      rows[#rows + 1] = "effect_" .. tostring(index) .. "_" .. field .. "=" .. encoded
    end
  end
  return table.concat(rows, " "), truncated, unavailable
end
local function contribution_technology(force, phase, force_index, force_name)
  local truncated, unavailable = false, false
  for _, name in ipairs(CONTRIBUTION_TECHNOLOGIES) do
    local technologies, technologies_available = contribution_read(force, "technologies")
    local row, row_available = nil, technologies_available
    if row_available then row, row_available = contribution_read(technologies, name) end
    local prefix = CONTRIBUTION_PREFIX .. " phase=" .. phase .. " force_index=" .. contribution_number(force_index)
      .. " force_name=" .. string.format("%q", force_name) .. " kind=technology technology=" .. string.format("%q", name)
    if not row_available then
      log(prefix .. " state=unavailable"); unavailable = true
    elseif row == nil then
      log(prefix .. " state=absent")
    else
      local valid, valid_available = contribution_read(row, "valid")
      local level, level_available = contribution_read(row, "level")
      local researched, researched_available = contribution_read(row, "researched")
      local enabled, enabled_available = contribution_read(row, "enabled")
      local visible, visible_available = contribution_read(row, "visible_when_disabled")
      if not valid_available or valid ~= true or not level_available or not researched_available or not enabled_available or not visible_available then
        log(prefix .. " state=unavailable"); unavailable = true
      else
        local effects, effects_truncated, effects_unavailable = contribution_effects(row)
        log(prefix .. " state=present level=" .. contribution_number(level)
          .. " researched=" .. contribution_boolean(researched) .. " enabled=" .. contribution_boolean(enabled)
          .. " visible=" .. contribution_boolean(visible) .. " " .. effects)
        unavailable = unavailable or not contribution_finite(level) or type(researched) ~= "boolean"
          or type(enabled) ~= "boolean" or type(visible) ~= "boolean" or effects_unavailable
        truncated = truncated or effects_truncated
      end
    end
  end
  return truncated, unavailable
end
local function contribution_force_rows()
  local registry, registry_available = contribution_read(game, "forces")
  if not registry_available or registry == nil then return nil, false, true end
  local rows, seen, keys = {}, {}, 0
  local iterated, complete, truncated, unavailable = pcall(function()
    for _, force in pairs(registry) do
      keys = keys + 1
      if keys > CONTRIBUTION_REGISTRY_KEY_LIMIT then return false, true, false end
      local index, index_available = contribution_read(force, "index")
      if not index_available or not contribution_finite(index) then return false, false, true end
      if not seen[index] then
        seen[index] = true
        local name, name_available = contribution_read(force, "name")
        local valid, valid_available = contribution_read(force, "valid")
        if not name_available or type(name) ~= "string" or not valid_available or valid ~= true then return false, false, true end
        rows[#rows + 1] = {force = force, index = index, name = name}
        if #rows > CONTRIBUTION_FORCE_LIMIT then return false, true, false end
      end
    end
    return true, false, false
  end)
  if not iterated then return nil, false, true end
  if not complete then return nil, truncated, unavailable end
  table.sort(rows, function(left, right)
    if left.index ~= right.index then return left.index < right.index end
    return left.name < right.name
  end)
  return rows, false, false
end
local function observe_force_contributions(phase)
  check(type(phase) == "string" and CONTRIBUTION_PHASES[phase] == true, "contribution observation phase differs")
  local rows, truncated, unavailable = contribution_force_rows()
  if rows then
    for _, row in ipairs(rows) do
      local force_name, name_truncated = contribution_name(row.name)
      truncated = truncated or name_truncated
      local values = {}
      local fields = {
        {"worker_robots_storage_bonus", function() return row.force.worker_robots_storage_bonus end},
        {"worker_robots_speed_modifier", function() return row.force.worker_robots_speed_modifier end},
        {"artillery_range_modifier", function() return row.force.artillery_range_modifier end},
        {"artillery_shell_gun_speed_modifier", function() return row.force.get_gun_speed_modifier("artillery-shell") end},
        {"laser_gun_speed_modifier", function() return row.force.get_gun_speed_modifier("laser") end},
        {"laser_ammo_damage_modifier", function() return row.force.get_ammo_damage_modifier("laser") end}
      }
      for _, field in ipairs(fields) do
        local ok, value = pcall(field[2])
        values[#values + 1] = field[1] .. "=" .. (ok and contribution_number(value) or "unavailable")
        unavailable = unavailable or not ok or not contribution_finite(value)
      end
      log(CONTRIBUTION_PREFIX .. " phase=" .. phase .. " force_index=" .. contribution_number(row.index)
        .. " force_name=" .. string.format("%q", force_name) .. " kind=force name_truncated=" .. tostring(name_truncated)
        .. " " .. table.concat(values, " "))
      local technology_truncated, technology_unavailable = contribution_technology(row.force, phase, row.index, force_name)
      truncated = truncated or technology_truncated
      unavailable = unavailable or technology_unavailable
    end
  end
  log(CONTRIBUTION_PREFIX .. " summary phase=" .. phase .. " forces=" .. tostring(rows and #rows or 0)
    .. " truncated=" .. tostring(truncated) .. " unavailable=" .. tostring(unavailable))
  return rows ~= nil
end
local function frame_key(key)
  if type(key) == "number" then return string.format("#%.17g", key) end
  if type(key) == "string" then return "$" .. key end
  return "?" .. type(key)
end
local function frame_path_key(key)
  if type(key) == "number" then return "[" .. string.format("%.17g", key) .. "]" end
  if type(key) == "string" then return "." .. key end
  return ".<" .. type(key) .. ">"
end
local function frame_value(value, present)
  if not present then return "missing", "<missing>" end
  local kind = type(value)
  if kind == "number" then return kind, string.format("%.17g", value) end
  if kind == "string" then
    local bounded = #value > 160 and value:sub(1, 160) .. "..." or value
    return kind, string.format("%q", bounded)
  end
  if kind == "boolean" or kind == "nil" then return kind, tostring(value) end
  return kind, "<" .. kind .. ">"
end
local function frame_diagnostics(expected, observed, origin)
  local rows, visits, truncated = {}, 0, false
  local function add(path, expected_value, expected_present, observed_value, observed_present)
    if #rows >= FRAME_DIFF_MAX then truncated = true; return false end
    local expected_kind, expected_text = frame_value(expected_value, expected_present)
    local observed_kind, observed_text = frame_value(observed_value, observed_present)
    rows[#rows + 1] = {path = path, expected_kind = expected_kind, expected_text = expected_text,
      observed_kind = observed_kind, observed_text = observed_text}
    return true
  end
  local function add_table_limit(path, expected_value, observed_value)
    truncated = true
    local row = {path = path, expected_kind = type(expected_value), expected_text = "<key-limit-exceeded>",
      observed_kind = type(observed_value), observed_text = "<key-limit-exceeded>"}
    -- Retain an explicit table-level diagnostic even when earlier leaf rows
    -- used the output allowance; the omitted fields must not depend on pair order.
    if #rows >= FRAME_DIFF_MAX then rows[#rows] = row else rows[#rows + 1] = row end
  end
  local function bounded_keys(expected_value, observed_value)
    local keys, seen, count = {}, {}, 0
    local function collect(value)
      for key in pairs(value) do
        if not seen[key] then
          count = count + 1
          if count > FRAME_DIFF_KEYS then return false end
          seen[key], keys[#keys + 1] = true, key
        end
      end
      return true
    end
    if not collect(expected_value) or not collect(observed_value) then return nil end
    table.sort(keys, function(left, right) return frame_key(left) < frame_key(right) end)
    return keys
  end
  local function walk(path, expected_value, expected_present, observed_value, observed_present, depth)
    if #rows >= FRAME_DIFF_MAX then truncated = true; return end
    visits = visits + 1
    if visits > FRAME_DIFF_VISITS then truncated = true; return end
    local expected_kind = expected_present and type(expected_value) or "missing"
    local observed_kind = observed_present and type(observed_value) or "missing"
    if expected_kind ~= observed_kind then add(path, expected_value, expected_present, observed_value, observed_present); return end
    if expected_kind ~= "table" then
      if not expected_present or expected_value ~= observed_value then add(path, expected_value, expected_present, observed_value, observed_present) end
      return
    end
    if depth >= FRAME_DIFF_DEPTH then truncated = true; return end
    local keys = bounded_keys(expected_value, observed_value)
    if not keys then add_table_limit(path, expected_value, observed_value); return end
    for _, key in ipairs(keys) do
      walk(path .. frame_path_key(key), expected_value[key], expected_value[key] ~= nil,
        observed_value[key], observed_value[key] ~= nil, depth + 1)
      if #rows >= FRAME_DIFF_MAX then truncated = true; return end
    end
  end
  walk("frame", expected, true, observed, true, 0)
  for _, row in ipairs(rows) do
    log("[MIR_SE_CARGO_FRAME_DIFF] path=" .. row.path .. " expected(" .. row.expected_kind .. ")=" .. row.expected_text
      .. " observed(" .. row.observed_kind .. ")=" .. row.observed_text .. " origin=" .. origin)
  end
  log("[MIR_SE_CARGO_FRAME_DIFF] summary path=frame origin=" .. origin .. " count=" .. tostring(#rows)
    .. " truncated=" .. tostring(truncated))
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
  local observed = frame(state)
  observe_force_contributions("candidate-transfer")
  if not same(observed, expected) then frame_diagnostics(expected, observed, "candidate-transfer") end
  check(same(observed, expected), "candidate changed source frame before observation")
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
local function start_source_research(state, player, lab, power, pole)
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
local function begin_source()
  check(script.active_mods["more-infinite-research"] == SOURCE_MIR, "source MIR identity differs")
  local state = storage[KEY]
  check(type(state) == "table" and state.phase == "idle", "source begin phase differs")
  check(pending_setup == nil, "source setup already scheduled")
  local player = game.forces.player
  check(player and player.valid ~= false, "player force differs")
  assert_active_tuple(); assert_settings(); assert_setup_declaration(player); assert_worker_contract(player, SOURCE)
  for _, declared in ipairs(fixture.rows) do
    local row = technology(player, declared.name)
    row.researched = true
  end
  local lab, power, pole = create_lab_and_power(player)
  observe_setup("created", lab, power, pole)
  -- Hand the completed creation batch back to one native update before
  -- judging electrical publication. No queue, feed or speed stimulus yet.
  pending_setup = {tick=game.tick, player=player, lab=lab, power=power, pole=pole}
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
local function cap12_mir_change_values(event)
  local change = event.mod_changes["more-infinite-research"]
  if change == nil then return "missing", "missing", "missing", true end
  if type(change) ~= "table" then return "unavailable", "unavailable", "unavailable", false end
  local function value(field)
    local row = change[field]
    if row == nil then return "missing", true end
    if type(row) ~= "string" or #row > 160 then return "unavailable", false end
    return string.format("%q", row), true
  end
  local old_version, old_valid = value("old_version")
  local new_version, new_valid = value("new_version")
  return "present", old_version, new_version, old_valid and new_valid
end
local function cap12_contract_value(value)
  local kind, text = frame_value(value, true)
  return kind .. ":" .. text
end
local function cap12_contract_scalar(row, field)
  local available, value = pcall(function() return row[field] end)
  if not available then return "unavailable", false, nil end
  return cap12_contract_value(value), true, value
end
local function observe_cap12_configuration(event, state)
  check(script.active_mods["more-infinite-research"] == CURRENT_MIR, "cap12 MIR identity differs")
  check(state.phase == "closed" and state.worker == CANDIDATE and type(state.closed) == "table"
    and state.closed.worker == CANDIDATE, "cap12 configuration state differs")
  check(state.ordinary == 5 and state.candidate_events == 2, "cap12 saved completion count differs")
  check(state.configuration_startup_settings_changed == false, "cap12 saved configuration flag differs")
  assert_active_tuple(); assert_cap12_settings()
  local change_state, old_version, new_version, change_valid = cap12_mir_change_values(event)
  local observed = frame(state)
  local target = technology(state.player, CANDIDATE)
  local prototype_available, prototype = pcall(function() return target.prototype end)
  local maximum_text, maximum_available, maximum = "unavailable", false, nil
  if prototype_available then
    maximum_text, maximum_available, maximum = cap12_contract_scalar(prototype, "max_level")
  end
  local count_text, count_available, count = cap12_contract_scalar(target, "research_unit_count")
  local time_text, time_available, time = cap12_contract_scalar(target, "research_unit_energy")
  local formula_text, formula_available, formula = cap12_contract_scalar(target, "research_unit_count_formula")
  log(table.concat({
    "[MIR_SE_CARGO_CAP12_CONFIGURATION]", "event_startup_settings_changed=" .. tostring(event.mod_startup_settings_changed),
    "saved_configuration_startup_settings_changed=" .. tostring(state.configuration_startup_settings_changed),
    "configured_cap=12", "mir_change=" .. change_state, "mir_old=" .. old_version, "mir_new=" .. new_version, "worker=" .. observed.worker,
    "level=" .. tostring(observed.target.level), "enabled=" .. tostring(observed.target.enabled),
    "current=" .. tostring(observed.current), "progress=" .. tostring(observed.progress),
    "queue=" .. table.concat(observed.queue, ","), "science_issued=" .. science_values(observed.science.issued),
    "science_remaining=" .. science_values(observed.science.remaining), "science_debit=" .. science_values(observed.science.debit),
    "bonus=" .. cap12_contract_value(observed.bonus), "maximum=" .. maximum_text,
    "unit_count=" .. count_text, "unit_time=" .. time_text, "unit_formula=" .. formula_text
  }, "|"))
  check(change_valid, "cap12 MIR change differs")
  check(prototype_available and maximum_available and count_available and time_available and formula_available,
    "cap12 current contract unavailable")
  check(type(maximum) == "number" and type(count) == "number" and type(time) == "number" and type(formula) == "string",
    "cap12 current contract differs")
  observe_force_contributions("cap12-configuration")
  frame_diagnostics(state.closed, observed, "cap12-configuration")
end
local function configuration(event)
  check(event and type(event.mod_startup_settings_changed) == "boolean" and type(event.mod_changes) == "table", "configuration event differs")
  local state = storage[KEY]
  if not source_reload_observed and script.active_mods["more-infinite-research"] == SOURCE_MIR
    and type(state) == "table" and state.phase == "source-partial" then
    source_reload_observed = true
    observe_force_contributions("source-reload")
    frame_diagnostics(state.source_frame, frame(state), "source-reload")
  end
  if type(state) == "table" and state.worker == CANDIDATE then
    observe_cap12_configuration(event, state)
    return
  end
  local change = event.mod_changes["more-infinite-research"]
  check(change and change.old_version == SOURCE_MIR and type(change.new_version) == "string" and change.new_version ~= SOURCE_MIR, "source-to-candidate identity differs")
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
  observe_force_contributions("candidate-closed")
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
remote.add_interface(FIXTURE, {begin = begin_source, observe_force_contributions = observe_force_contributions})
script.on_configuration_changed(function(event)
  if active() then configuration(event) end
end)
script.on_event(defines.events.on_research_finished, function(event)
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  check(event and event.research and type(event.research.name) == "string", "research completion event differs")
  if event.research.name ~= SOURCE and event.research.name ~= CANDIDATE then return end
  local player = state.player or game.forces.player
  check(player and event.research.force, "research completion force differs")
  if event.research.force ~= player then return end
  -- MIR's configuration handoff can emit scripted notifications before this
  -- observer's configuration callback validates the complete transferred frame.
  if state.phase == "source-partial" and event.by_script == true then return end
  if state.worker and event.research.name ~= state.worker then
    if event.by_script == true then return end
    fail("ordinary worker role differs")
  end
  if event and event.by_script == true then fail("scripted worker completion differs") end
  check(state.phase == "source-working" or state.phase == "candidate-working", "worker completion phase differs")
  local target = technology(state.player, state.worker)
  check(event and event.research == target and event.by_script == false and event.research.force == state.player, "worker completion differs")
  check(event.research.level == target.level, "worker event cursor differs")
  local next_level = target.level + (target.researched and 1 or 0)
  if state.phase == "source-working" then
    check(next_level == state.ordinary + 5 and next_level <= 9,
      "source ordinary completion level differs: level=" .. tostring(target.level) .. " researched=" .. tostring(target.researched)
        .. " next=" .. tostring(next_level) .. " expected=" .. tostring(state.ordinary + 5))
    state.ordinary = state.ordinary + 1
    assert_earned_bonuses(state, state.ordinary, 0, "source ordinary")
    if next_level == 9 then
      state.lab.disabled_by_script = true
      state.phase = "source-await-queue"
    else feed(state) end
  elseif state.phase == "candidate-working" then
    check(next_level == state.candidate_events + 10 and next_level <= 11, "candidate ordinary completion level differs")
    state.candidate_events = state.candidate_events + 1
    assert_earned_bonuses(state, state.ordinary, state.candidate_events, "candidate ordinary")
    if next_level == 11 then
      state.lab.disabled_by_script = true
      state.phase = "candidate-await-cap"
    else feed(state) end
  else fail("worker completion phase differs") end
end)
script.on_event(defines.events.on_tick, function(event)
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  if pending_setup then
    if game.tick == pending_setup.tick then return end
    local setup = pending_setup
    pending_setup = nil
    observe_setup("next-update", setup.lab, setup.power, setup.pole)
    check(event and event.tick == setup.tick + 1 and game.tick == event.tick and state.phase == "idle",
      "source setup update boundary differs")
    start_source_research(state, setup.player, setup.lab, setup.power, setup.pole)
    return
  end
  if cold_pending then
    if not source_reload_observed and cold_phase == "source-partial"
      and script.active_mods["more-infinite-research"] == SOURCE_MIR and state.phase == "source-partial" then
      source_reload_observed = true
      observe_force_contributions("source-reload")
      frame_diagnostics(state.source_frame, frame(state), "source-reload")
    end
    if cold_phase == "closed" then
      check(state.phase == "closed" and same(frame(state), state.closed), "cold process changed candidate endpoint")
      observe_force_contributions("cold-read")
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
