local KEY = "mir5_migration_origin_f200_110_source"
local FIXTURE = "mir-fixture-mir5-migration-origin-f200-110-source"
local SAVE = "mir5-native-complete"
local DEADLINE = 18000
local PACKS = 32
local UINT32_MAX = 4294967295
local CATALOGUE = require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
local loaded, reload_reported = false, false

local function fail(message) error("[mir5-migration-origin-f200-110-source] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end

local function check_closure()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "1.1.0"
      or script.active_mods[FIXTURE] ~= "0.1.0" then
    fail("source runtime closure differs")
  end
  for name, default_value in pairs(CATALOGUE.settings) do
    if settings.startup[name] == nil or settings.startup[name].value ~= default_value then
      fail("source runtime default differs: " .. name)
    end
  end
end

local function state()
  if type(storage) ~= "table" or type(storage[KEY]) ~= "table" then fail("source fixture state is absent") end
  return storage[KEY]
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("source technology is absent: " .. tostring(name)) end
  return value
end

local function expected_science(name)
  local row = CATALOGUE.rows[name]
  if row == nil then fail("source catalogue row is absent: " .. tostring(name)) end
  return CATALOGUE.science[row.science].ingredients
end

local function source_roster(force)
  local rows, seen = {}, {}
  for name, value in pairs(force.technologies) do
    if name:sub(1, #CATALOGUE.technology_prefix) == CATALOGUE.technology_prefix then
      if CATALOGUE.rows[name] == nil or name:sub(-#CATALOGUE.technology_suffix) ~= CATALOGUE.technology_suffix
          or value == nil or value.valid == false or value.prototype.level ~= 1
          or value.prototype.max_level ~= UINT32_MAX then
        fail("source runtime roster identity differs: " .. tostring(name))
      end
      rows[#rows + 1], seen[name] = name, true
    end
  end
  for name in pairs(CATALOGUE.rows) do if not seen[name] then fail("source runtime row is absent: " .. name) end end
  table.sort(rows)
  if #rows ~= 31 then fail("source runtime roster count differs") end
  if force.technologies["recipe-prod-research_inventory_capacity-1"] ~= nil then
    fail("disabled inventory stream is present at runtime")
  end
  return rows
end

local function prerequisites(value, seen)
  seen = seen or {}
  if seen[value.name] then return end
  seen[value.name] = true
  for _, prerequisite in pairs(value.prerequisites or {}) do
    prerequisites(prerequisite, seen)
    prerequisite.enabled = true
    prerequisite.researched = true
  end
end

local function effect_signature(value)
  if value.type == "change-recipe-productivity" then
    return value.type .. "|" .. tostring(value.recipe) .. "|" .. string.format("%.17g", value.change)
  end
  if value.type == "worker-robot-battery" then
    return value.type .. "|" .. string.format("%.17g", value.modifier)
  end
  return tostring(value.type) .. "|unexpected"
end

local function effects_signature(value)
  local rows = {}
  for _, effect in pairs(value.prototype.effects or {}) do rows[#rows + 1] = effect_signature(effect) end
  table.sort(rows)
  return table.concat(rows, ",")
end

local function per_level(value)
  local result = {}
  for _, effect in pairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" then result[effect.recipe] = (result[effect.recipe] or 0) + effect.change end
  end
  return result
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queue, progress=force.research_progress}
end

local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do if actual.queue[index] ~= name then fail(label .. " queue identity differs") end end
  return actual
end

local function assert_idle(force, label)
  local actual = queue_snapshot(force)
  if actual.current ~= false or #actual.queue ~= 0 then fail(label .. " queue is not idle") end
end

local function snapshot(force, rows)
  local out = {technologies={}, effects={}, recipes={}, fields={}}
  local recipes = {}
  for _, name in ipairs(rows) do
    local value = technology(force, name)
    out.technologies[name] = {level=value.level, researched=value.researched, enabled=value.enabled,
      visible=value.visible_when_disabled, saved=value.saved_progress, maximum=value.prototype.max_level}
    out.effects[name] = effects_signature(value)
    for recipe in pairs(per_level(value)) do recipes[recipe] = true end
  end
  for recipe in pairs(recipes) do
    local value = force.recipes[recipe]
    if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then fail("source recipe fact is absent: " .. recipe) end
    out.recipes[recipe] = value.productivity_bonus
  end
  if type(force.manual_mining_speed_modifier) ~= "number" or type(force.worker_robots_battery_modifier) ~= "number" then
    fail("source force contribution is absent")
  end
  out.fields.manual_mining_speed_modifier = force.manual_mining_speed_modifier
  out.fields.worker_robots_battery_modifier = force.worker_robots_battery_modifier
  return out
end

local function assert_same_snapshot(force, rows, expected, label)
  local actual = snapshot(force, rows)
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    if now == nil or now.level ~= before.level or now.researched ~= before.researched or now.enabled ~= before.enabled
        or now.visible ~= before.visible or now.maximum ~= before.maximum or not close(now.saved, before.saved) then
      fail(label .. " technology state changed: " .. name)
    end
    if actual.effects[name] ~= expected.effects[name] then fail(label .. " technology effects changed: " .. name) end
  end
  for recipe, before in pairs(expected.recipes) do if not close(actual.recipes[recipe], before) then fail(label .. " recipe contribution changed: " .. recipe) end end
  for field, before in pairs(expected.fields) do if not close(actual.fields[field], before) then fail(label .. " force contribution changed: " .. field) end end
  return actual
end

local function seed_rows(force, rows, label, preserve)
  force.enable_all_prototypes()
  for _, name in ipairs(rows) do
    local value = technology(force, name)
    if value.prototype.max_level ~= UINT32_MAX then fail(label .. " source row is not infinite: " .. name) end
    if name ~= preserve then
      value.level = value.prototype.level + 1
      if value.researched then fail(label .. " level seed unexpectedly researched: " .. name) end
    end
  end
  force.reset_technology_effects()
  if not close(force.manual_mining_speed_modifier, 0) then fail(label .. " native manual-mining baseline differs") end
  if not close(force.worker_robots_battery_modifier, .1) then fail(label .. " robot battery contribution differs") end
end

local function lab(state_value)
  local entity = state_value.lab
  if entity == nil or entity.valid == false then fail("real source lab is absent") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real source lab input is absent") end
  return entity, inventory
end

local function fill_lab(state_value, value)
  local entity, inventory = lab(state_value)
  inventory.clear()
  local expected, actual = expected_science(CATALOGUE.direct), {}
  state_value.initial_packs = {}
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string" or ingredient.amount ~= 1
        or expected[ingredient.name] ~= 1 or actual[ingredient.name] ~= nil then fail("source runtime science differs") end
    actual[ingredient.name] = 1
    if inventory.insert{name=ingredient.name, count=PACKS} ~= PACKS then fail("real source lab rejected " .. ingredient.name) end
    state_value.initial_packs[ingredient.name] = PACKS
  end
  for name in pairs(expected) do if actual[name] ~= 1 then fail("source runtime science is incomplete: " .. name) end end
  entity.energy = 1000000000
end

local function freeze_lab(state_value)
  local entity, inventory = lab(state_value)
  entity.energy = 0
  inventory.clear()
end

local function assert_consumed(state_value)
  local _, inventory = lab(state_value)
  for name, before in pairs(state_value.initial_packs or {}) do if inventory.get_item_count(name) >= before then fail("real source lab did not consume " .. name) end end
end

local function establish_foreign_state(rows)
  local foreign = game.create_force("mir5-migration-origin-f200-110-foreign")
  seed_rows(foreign, rows, "foreign", CATALOGUE.direct)
  local direct, probe = technology(foreign, CATALOGUE.direct), technology(foreign, "recipe-prod-research_plastic-1")
  prerequisites(direct)
  prerequisites(probe)
  direct.saved_progress, probe.saved_progress = .42, 0
  foreign.research_queue = {direct, probe}
  foreign.research_progress = .42
  return foreign.index, snapshot(foreign, rows),
    assert_queue(foreign, {current=CATALOGUE.direct, queue={CATALOGUE.direct, probe.name}, progress=.42}, "foreign")
end

local function establish_detached_state(rows)
  local detached = game.create_force("mir5-migration-origin-f200-110-detached")
  seed_rows(detached, rows, "detached", CATALOGUE.direct)
  technology(detached, CATALOGUE.direct).saved_progress = .27
  if not close(technology(detached, CATALOGUE.direct).saved_progress, .27) then fail("detached source progress differs") end
  assert_idle(detached, "detached")
  return detached.index, snapshot(detached, rows)
end

local function marker(stage, state_value)
  local player = game.forces.player
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"migration-origin-f200-110-source\","
    .. "\"stage\":\"" .. stage .. "\","
    .. "\"status\":\"passed\","
    .. "\"origin_tag\":\"1.1.0\","
    .. "\"source_roster_rows\":31,"
    .. "\"player_seeded_rows\":30,"
    .. "\"source_direct_lab_completions\":" .. tostring(state_value.source_labs or 0) .. ","
    .. "\"foreign_queue_progress\":0.42,"
    .. "\"detached_progress\":0.27,"
    .. "\"source_direct_level\":" .. tostring(technology(player, CATALOGUE.direct).level) .. ","
    .. "\"source_gear_productivity\":" .. tostring(player.recipes["iron-gear-wheel"].productivity_bonus) .. ","
    .. "\"source_robot_battery\":" .. tostring(player.worker_robots_battery_modifier) .. ","
    .. "\"inventory_stream_absent\":true,"
    .. "\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end

local function init()
  check_closure()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  local player = game.forces.player
  local rows = source_roster(player)
  game.speed = 16
  seed_rows(player, rows, "source player", CATALOGUE.direct)
  local direct = technology(player, CATALOGUE.direct)
  prerequisites(direct)
  direct.enabled = true
  if direct.researched or direct.level ~= 1 then fail("source gear technology is not fresh") end
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if entity == nil or entity.valid == false then fail("could not create real source lab") end
  local state_value = {phase="await-source-lab", roster=rows, lab=entity, source_labs=0, deadline=game.tick + DEADLINE}
  storage[KEY] = state_value
  fill_lab(state_value, direct)
  if player.add_research(direct) ~= true or player.current_research == nil or player.current_research.name ~= CATALOGUE.direct then
    fail("could not queue real source lab")
  end
end

local function assert_completed_state(state_value, label)
  assert_same_snapshot(game.forces.player, state_value.roster, state_value.player_snapshot, label .. " player")
  local foreign = game.forces[state_value.foreign_index]
  if foreign == nil or foreign.valid == false then fail(label .. " foreign force is absent") end
  assert_same_snapshot(foreign, state_value.roster, state_value.foreign_snapshot, label .. " foreign")
  assert_queue(foreign, state_value.foreign_queue, label .. " foreign")
  local detached = game.forces[state_value.detached_index]
  if detached == nil or detached.valid == false then fail(label .. " detached force is absent") end
  assert_same_snapshot(detached, state_value.roster, state_value.detached_snapshot, label .. " detached")
  if not close(technology(detached, CATALOGUE.direct).saved_progress, .27) then fail(label .. " detached progress changed") end
  assert_idle(detached, label .. " detached")
end

local function tick()
  local state_value = state()
  if state_value.phase == "completed" then
    if loaded and not reload_reported then
      assert_completed_state(state_value, "source cold reload")
      marker("reload", state_value)
      reload_reported = true
    end
    return
  end
  if game.tick > state_value.deadline then fail("real source lab did not finish") end
  lab(state_value).energy = 1000000000
  if state_value.source_labs ~= 1 then return end
  assert_consumed(state_value)
  local player, direct = game.forces.player, technology(game.forces.player, CATALOGUE.direct)
  if direct.level ~= 2 or direct.researched ~= false then fail("source lab result differs") end
  if not close(player.recipes["iron-gear-wheel"].productivity_bonus, .1) then fail("actual source gear productivity differs") end
  if not close(player.worker_robots_battery_modifier, .1) then fail("actual source robot battery differs") end
  freeze_lab(state_value)
  state_value.player_snapshot = snapshot(player, state_value.roster)
  state_value.foreign_index, state_value.foreign_snapshot, state_value.foreign_queue = establish_foreign_state(state_value.roster)
  state_value.detached_index, state_value.detached_snapshot = establish_detached_state(state_value.roster)
  state_value.phase = "completed"
  marker("initial", state_value)
  game.server_save(SAVE)
end

script.on_init(init)
script.on_load(function()
  local value = storage and storage[KEY]
  loaded = type(value) == "table" and value.phase == "completed"
  reload_reported = false
end)
script.on_event(defines.events.on_research_finished, function(event)
  local value = storage and storage[KEY]
  if type(value) ~= "table" or value.phase ~= "await-source-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= CATALOGUE.direct then return end
  value.source_labs = value.source_labs + 1
  if value.source_labs ~= 1 then fail("source lab completed more than once") end
end)
script.on_event(defines.events.on_tick, tick)
