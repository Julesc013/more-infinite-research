local KEY = "mir5_migration_origin_f200_120_source"
local FIXTURE = "mir-fixture-mir5-migration-origin-f200-120-source"
local SAVE = "mir5-native-complete"
local DEADLINE, PACKS, UINT32_MAX = 18000, 32, 4294967295
local CATALOGUE = require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
local loaded, reload_reported = false, false

local function fail(message) error("[mir5-migration-origin-f200-120-source] " .. message) end
local function close(left, right) return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001 end

local function check_closure()
  if script.active_mods.base ~= "2.0.77" or script.active_mods["more-infinite-research"] ~= "1.2.0"
      or script.active_mods[FIXTURE] ~= "0.1.0" then fail("source runtime closure differs") end
  for name, expected in pairs(CATALOGUE.settings) do
    if settings.startup[name] == nil or settings.startup[name].value ~= expected.default_value then
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

local function signature(value)
  if value.type == "change-recipe-productivity" then return value.type .. "|" .. tostring(value.recipe) .. "|" .. string.format("%.17g", value.change) end
  if value.type == "worker-robot-battery" then return value.type .. "|" .. string.format("%.17g", value.modifier) end
  if value.type == "gun-speed" then return value.type .. "|" .. tostring(value.ammo_category) .. "|" .. string.format("%.17g", value.modifier) end
  return tostring(value.type) .. "|unexpected"
end

local function effects_signature(value)
  local rows = {}
  for _, effect in pairs(value.prototype.effects or {}) do rows[#rows + 1] = signature(effect) end
  table.sort(rows)
  return table.concat(rows, ",")
end

local function expected_signature(effects)
  local rows = {}
  for _, effect in ipairs(effects or {}) do rows[#rows + 1] = signature(effect) end
  table.sort(rows)
  return table.concat(rows, ",")
end

local function source_rows(force)
  local rows, seen = {}, {}
  for name, value in pairs(force.technologies) do
    if name:sub(1, #CATALOGUE.technology_prefix) == CATALOGUE.technology_prefix then
      local expected = CATALOGUE.rows[name]
      if expected == nil or name:sub(-#CATALOGUE.technology_suffix) ~= CATALOGUE.technology_suffix
          or value == nil or value.valid == false or value.prototype.level ~= expected.level
          or value.prototype.max_level ~= UINT32_MAX then fail("source runtime roster identity differs: " .. tostring(name)) end
      if effects_signature(value) ~= expected_signature(expected.effects) then fail("source runtime effects differ: " .. name) end
      rows[#rows + 1], seen[name] = name, true
    end
  end
  for name in pairs(CATALOGUE.rows) do if not seen[name] then fail("source runtime row is absent: " .. name) end end
  table.sort(rows)
  if #rows ~= 34 then fail("source runtime roster count differs") end
  return rows
end

local function weapon_rows(force)
  local rows = {}
  for name, expected in pairs(CATALOGUE.weapons) do
    local value = technology(force, name)
    local runtime = CATALOGUE.weapon_runtime[name]
    if runtime == nil or value.level ~= runtime.level or value.prototype.level ~= runtime.level
        or value.prototype.max_level ~= runtime.max_level then
      fail("finite weapon runtime level differs: " .. name)
    end
    if effects_signature(value) ~= expected_signature(expected.effects) then fail("finite weapon effects differ: " .. name) end
    rows[#rows + 1] = name
  end
  table.sort(rows)
  if #rows ~= 7 then fail("finite weapon roster count differs") end
  return rows
end

local function prerequisites(value, seen)
  seen = seen or {}
  if seen[value.name] then return end
  seen[value.name] = true
  for _, prerequisite in pairs(value.prerequisites or {}) do
    prerequisites(prerequisite, seen)
    prerequisite.enabled, prerequisite.researched = true, true
  end
end

local function per_level(value)
  local recipes = {}
  for _, effect in pairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" then recipes[effect.recipe] = (recipes[effect.recipe] or 0) + effect.change end
  end
  return recipes
end

local function technology_snapshot(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled, visible=value.visible_when_disabled,
    saved=value.saved_progress, maximum=value.prototype.max_level, effects=effects_signature(value)}
end

local function snapshot(force, rows, weapons)
  local out, recipes = {technologies={}, weapons={}, recipes={}, fields={}}, {}
  for _, name in ipairs(rows) do
    local value = technology(force, name)
    out.technologies[name] = technology_snapshot(value)
    for recipe in pairs(per_level(value)) do recipes[recipe] = true end
  end
  for _, name in ipairs(weapons) do out.weapons[name] = technology_snapshot(technology(force, name)) end
  for recipe in pairs(recipes) do
    local value = force.recipes[recipe]
    if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then fail("source recipe fact is absent: " .. recipe) end
    out.recipes[recipe] = value.productivity_bonus
  end
  if type(force.worker_robots_battery_modifier) ~= "number" then fail("source robot battery fact is absent") end
  out.fields.worker_robots_battery_modifier = force.worker_robots_battery_modifier
  out.gun_speed = {}
  for _, category in ipairs(CATALOGUE.gun_categories) do out.gun_speed[category] = force.get_gun_speed_modifier(category) end
  out.gun_speed.bullet = force.get_gun_speed_modifier("bullet")
  out.gun_speed["shotgun-shell"] = force.get_gun_speed_modifier("shotgun-shell")
  return out
end

local function assert_same_snapshot(force, rows, weapons, expected, label)
  local actual = snapshot(force, rows, weapons)
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    if now == nil or now.level ~= before.level or now.researched ~= before.researched or now.enabled ~= before.enabled
        or now.visible ~= before.visible or now.maximum ~= before.maximum or not close(now.saved, before.saved)
        or now.effects ~= before.effects then fail(label .. " technology state changed: " .. name) end
  end
  for name, before in pairs(expected.weapons) do
    local now = actual.weapons[name]
    if now == nil or now.level ~= before.level or now.researched ~= before.researched or now.enabled ~= before.enabled
        or now.visible ~= before.visible or now.maximum ~= before.maximum or not close(now.saved, before.saved)
        or now.effects ~= before.effects then fail(label .. " finite weapon state changed: " .. name) end
  end
  for recipe, before in pairs(expected.recipes) do if not close(actual.recipes[recipe], before) then fail(label .. " recipe contribution changed: " .. recipe) end end
  for field, before in pairs(expected.fields) do if not close(actual.fields[field], before) then fail(label .. " force contribution changed: " .. field) end end
  for category, before in pairs(expected.gun_speed) do if not close(actual.gun_speed[category], before) then fail(label .. " gun speed changed: " .. category) end end
  return actual
end

local function seed_rows(force, rows, weapons, label, preserve, finite_seeds, finite_speed)
  force.enable_all_prototypes()
  for _, name in ipairs(rows) do
    local value = technology(force, name)
    if value.prototype.max_level ~= UINT32_MAX then fail(label .. " source row is not infinite: " .. name) end
    if name ~= preserve then
      value.level = value.prototype.level + 1
      if value.researched then fail(label .. " source row level seed unexpectedly researched: " .. name) end
    end
  end
  local seeded = {}
  for _, name in ipairs(finite_seeds) do
    local owner = technology(force, name)
    prerequisites(owner)
    owner.enabled, owner.researched, seeded[name] = true, true, true
  end
  for _, name in ipairs(weapons) do
    local value = technology(force, name)
    local runtime = CATALOGUE.weapon_runtime[name]
    if runtime == nil or value.level ~= runtime.level or value.prototype.level ~= runtime.level
        or value.prototype.max_level ~= runtime.max_level then
      fail(label .. " finite weapon owner initial level differs: " .. name)
    end
    if seeded[name] then
      if value.researched ~= true then fail(label .. " finite weapon owner seed differs") end
    elseif value.researched ~= false then fail(label .. " finite weapon owner unexpectedly researched: " .. name) end
  end
  force.reset_technology_effects()
  for category, expected in pairs(CATALOGUE.direct_gun_speed) do
    if not close(force.get_gun_speed_modifier(category), expected) then fail(label .. " source gun speed differs: " .. category) end
  end
  for category, expected in pairs(finite_speed) do
    if not close(force.get_gun_speed_modifier(category), expected) then fail(label .. " finite weapon contribution differs: " .. category) end
  end
  if not close(force.worker_robots_battery_modifier, .1) then fail(label .. " robot battery contribution differs") end
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queue, progress=force.research_progress}
end

local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then fail(label .. " queue/progress differs") end
  for index, name in ipairs(expected.queue) do if actual.queue[index] ~= name then fail(label .. " queue identity differs") end end
end

local function lab(state_value)
  local entity = state_value.lab
  if entity == nil or entity.valid == false then fail("real source lab is absent") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real source lab input is absent") end
  return entity, inventory
end

local function fill_lab(state_value, technology_value)
  local entity, inventory = lab(state_value)
  inventory.clear()
  local expected, actual = CATALOGUE.rows[CATALOGUE.direct].unit.ingredients, {}
  state_value.initial_packs = {}
  for _, ingredient in ipairs(technology_value.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or ingredient.amount ~= 1 then fail("source runtime science differs") end
    local name = ingredient.name
    if actual[name] ~= nil then fail("source runtime science differs") end
    actual[name] = 1
    if inventory.insert{name=name, count=PACKS} ~= PACKS then fail("real source lab rejected " .. name) end
    state_value.initial_packs[name] = PACKS
  end
  if #expected ~= #technology_value.research_unit_ingredients then fail("source runtime science differs") end
  for _, ingredient in ipairs(expected) do if actual[ingredient[1]] ~= ingredient[2] then fail("source runtime science is incomplete") end end
  entity.energy = 1000000000
end

local function freeze_lab(state_value)
  local entity, inventory = lab(state_value)
  entity.energy = 0
  inventory.clear()
end

local function assert_consumed(state_value)
  local _, inventory = lab(state_value)
  for name, before in pairs(state_value.initial_packs or {}) do
    if inventory.get_item_count(name) >= before then fail("real source lab did not consume " .. name) end
  end
end

local function establish_foreign(rows, weapons)
  local foreign = game.create_force("mir5-migration-origin-f200-120-foreign")
  seed_rows(foreign, rows, weapons, "foreign", CATALOGUE.direct,
    CATALOGUE.finite_weapon_seed_sets.foreign, CATALOGUE.finite_owner_gun_speed.foreign)
  local direct, probe = technology(foreign, CATALOGUE.direct), technology(foreign, "recipe-prod-research_plastic-1")
  prerequisites(direct); prerequisites(probe)
  direct.saved_progress, probe.saved_progress = .42, 0
  foreign.research_queue, foreign.research_progress = {direct, probe}, .42
  return foreign.index, snapshot(foreign, rows, weapons), {current=CATALOGUE.direct, queue={CATALOGUE.direct, probe.name}, progress=.42}
end

local function establish_detached(rows, weapons)
  local detached = game.create_force("mir5-migration-origin-f200-120-detached")
  seed_rows(detached, rows, weapons, "detached", CATALOGUE.direct,
    CATALOGUE.finite_weapon_seed_sets.detached, CATALOGUE.finite_owner_gun_speed.detached)
  technology(detached, CATALOGUE.direct).saved_progress = .27
  return detached.index, snapshot(detached, rows, weapons)
end

local function marker(stage, value)
  local player = game.forces.player
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"migration-origin-f200-120-source\","
    .. "\"stage\":\"" .. stage .. "\",\"status\":\"passed\",\"origin_tag\":\"1.2.0\","
    .. "\"source_roster_rows\":34,\"player_scripted_row_seeds\":33,\"player_finite_weapon_owner_seeds\":6,\"foreign_finite_weapon_owner_seeds\":1,"
    .. "\"source_direct_lab_completions\":" .. tostring(value.source_labs or 0) .. ","
    .. "\"foreign_queue_progress\":0.42,\"detached_progress\":0.27,"
    .. "\"source_gear_productivity\":" .. tostring(player.recipes["iron-gear-wheel"].productivity_bonus) .. ","
    .. "\"source_rocket_gun_speed\":" .. tostring(player.get_gun_speed_modifier("rocket")) .. ","
    .. "\"source_cannon_gun_speed\":" .. tostring(player.get_gun_speed_modifier("cannon-shell")) .. ","
    .. "\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end

local function init()
  check_closure()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  local player = game.forces.player
  local rows, weapons = source_rows(player), weapon_rows(player)
  game.speed = 16
  seed_rows(player, rows, weapons, "source player", CATALOGUE.direct,
    CATALOGUE.finite_weapon_seed_sets.player, CATALOGUE.finite_owner_gun_speed.player)
  local direct = technology(player, CATALOGUE.direct)
  prerequisites(direct)
  direct.enabled = true
  if direct.researched or direct.level ~= 1 then fail("source gear technology is not fresh") end
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if entity == nil or entity.valid == false then fail("could not create real source lab") end
  local value = {phase="await-source-lab", roster=rows, weapons=weapons, lab=entity, source_labs=0, deadline=game.tick + DEADLINE}
  storage[KEY] = value
  fill_lab(value, direct)
  if player.add_research(direct) ~= true or player.current_research == nil or player.current_research.name ~= CATALOGUE.direct then
    fail("could not queue real source lab")
  end
end

local function assert_completed(value, label)
  assert_same_snapshot(game.forces.player, value.roster, value.weapons, value.player_snapshot, label .. " player")
  local foreign = game.forces[value.foreign_index]
  if foreign == nil or foreign.valid == false then fail(label .. " foreign force is absent") end
  assert_same_snapshot(foreign, value.roster, value.weapons, value.foreign_snapshot, label .. " foreign")
  assert_queue(foreign, value.foreign_queue, label .. " foreign")
  local detached = game.forces[value.detached_index]
  if detached == nil or detached.valid == false then fail(label .. " detached force is absent") end
  assert_same_snapshot(detached, value.roster, value.weapons, value.detached_snapshot, label .. " detached")
  if not close(technology(detached, CATALOGUE.direct).saved_progress, .27) then fail(label .. " detached progress changed") end
end

local function tick()
  local value = state()
  if value.phase == "completed" then
    if loaded and not reload_reported then assert_completed(value, "source cold reload"); marker("reload", value); reload_reported = true end
    return
  end
  if game.tick > value.deadline then fail("real source lab did not finish") end
  lab(value).energy = 1000000000
  if value.source_labs ~= 1 then return end
  local player, direct = game.forces.player, technology(game.forces.player, CATALOGUE.direct)
  if direct.level ~= 2 or direct.researched ~= false then fail("source lab result differs") end
  assert_consumed(value)
  if not close(player.recipes["iron-gear-wheel"].productivity_bonus, .1) then fail("actual source gear productivity differs") end
  freeze_lab(value)
  value.player_snapshot = snapshot(player, value.roster, value.weapons)
  value.foreign_index, value.foreign_snapshot, value.foreign_queue = establish_foreign(value.roster, value.weapons)
  value.detached_index, value.detached_snapshot = establish_detached(value.roster, value.weapons)
  value.phase = "completed"
  marker("initial", value)
  game.server_save(SAVE)
end

script.on_init(init)
script.on_load(function()
  local value = storage and storage[KEY]
  loaded, reload_reported = type(value) == "table" and value.phase == "completed", false
end)
script.on_event(defines.events.on_research_finished, function(event)
  local value = storage and storage[KEY]
  if type(value) ~= "table" or value.phase ~= "await-source-lab" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= CATALOGUE.direct then return end
  value.source_labs = value.source_labs + 1
  if value.source_labs ~= 1 then fail("source lab completed more than once") end
end)
script.on_event(defines.events.on_tick, tick)
