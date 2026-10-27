local KEY = "mir5_migration_origin_f200_100_source"
local FIXTURE = "mir-fixture-mir5-migration-origin-f200-100-source"
local DIRECT = "recipe-prod-research_gears-1"
local SAVE = "mir5-native-complete"
local DEADLINE = 18000
local PACKS = 32
local loaded, reload_reported = false, false

local function fail(message)
  error("[mir5-migration-origin-f200-100-source] " .. message)
end

local function state()
  if type(storage) ~= "table" then fail("runtime storage is absent") end
  local value = storage[KEY]
  if type(value) ~= "table" then fail("source fixture state is absent") end
  return value
end

local function technology(force)
  local value = force and force.technologies[DIRECT]
  if value == nil or value.valid == false then fail("source gear technology is absent at runtime") end
  return value
end

local function check_closure()
  local mods = script.active_mods
  if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.0.0"
      or mods[FIXTURE] ~= "0.1.0" then
    fail("source runtime closure differs")
  end
end

local function unlock(value, seen)
  seen = seen or {}
  if seen[value.name] then return end
  seen[value.name] = true
  for _, prerequisite in pairs(value.prerequisites or {}) do
    unlock(prerequisite, seen)
    prerequisite.enabled = true
    prerequisite.researched = true
  end
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
  state_value.initial_packs = {}
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string"
        or ingredient.amount ~= 1 then
      fail("source runtime science differs")
    end
    if inventory.insert{name=ingredient.name, count=PACKS} ~= PACKS then
      fail("real source lab rejected " .. ingredient.name)
    end
    state_value.initial_packs[ingredient.name] = PACKS
  end
  if next(state_value.initial_packs) == nil then fail("source runtime science is absent") end
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
    if inventory.get_item_count(name) >= before then
      fail("real source lab did not consume " .. name)
    end
  end
end

local function marker(stage, state_value)
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"migration-origin-f200-100-source\","
    .. "\"stage\":\"" .. stage .. "\","
    .. "\"status\":\"passed\","
    .. "\"origin_tag\":\"1.0.0\","
    .. "\"source_direct_lab_completions\":" .. tostring(state_value.source_labs or 0) .. ","
    .. "\"source_direct_level\":" .. tostring(technology(game.forces.player).level) .. ","
    .. "\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end

local function init()
  check_closure()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  game.speed = 16
  local force = game.forces.player
  local direct = technology(force)
  unlock(direct)
  direct.enabled = true
  if direct.researched then fail("source direct technology was already researched") end
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=force}
  if entity == nil or entity.valid == false then fail("could not create real source lab") end
  local state_value = {phase="await-source-lab", lab=entity, source_labs=0, deadline=game.tick + DEADLINE}
  storage[KEY] = state_value
  fill_lab(state_value, direct)
  if force.add_research(direct) ~= true then fail("could not queue real source lab") end
end

local function tick()
  local state_value = state()
  if state_value.phase == "completed" then
    if loaded and not reload_reported then
      local direct = technology(game.forces.player)
      if direct.level ~= 2 or state_value.source_labs ~= 1 then fail("source cold reload state differs") end
      marker("reload", state_value)
      reload_reported = true
    end
    return
  end
  if game.tick > state_value.deadline then fail("real source lab did not finish") end
  local entity = lab(state_value)
  entity.energy = 1000000000
  if state_value.source_labs ~= 1 then return end
  assert_consumed(state_value)
  local direct = technology(game.forces.player)
  if direct.level ~= 2 or direct.researched ~= false then fail("source lab result differs") end
  freeze_lab(state_value)
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
      or event.research.force ~= game.forces.player or event.research.name ~= DIRECT then
    return
  end
  value.source_labs = value.source_labs + 1
end)
script.on_event(defines.events.on_tick, tick)
