local KEY = "mir5_f110_f200_transition"
local FIXTURE = "mir-fixture-mir5-f110-f200-transition"
local SAVE = "mir5-native-complete"
local DEADLINE = 18000
local PACKS = 32
local SOURCE = "source"
local SUCCESSOR = "successor"
local loaded, reload_reported = false, false
local plan = require("__mir-fixture-mir5-f110-f200-transition__/catalogue")

local function fail(message)
  error("[mir5-f110-f200-transition] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end

local function store()
  -- F110 retains `global`; F200 migrates it into `storage`. Resolve only in a
  -- callback, and never create either table while loading or on_load.
  local modern = rawget(_G, "storage")
  if type(modern) == "table" then return modern end
  local legacy = rawget(_G, "global")
  if type(legacy) == "table" then return legacy end
  fail("runtime state store is absent")
end

local function read_state()
  return store()[KEY]
end

local function write_state(value)
  store()[KEY] = value
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("missing required technology " .. tostring(name)) end
  return value
end

local function saved_progress(force, value)
  if plan.stage == SOURCE then
    return force.get_saved_technology_progress(value)
  end
  return value.saved_progress
end

local function set_saved_progress(force, value, progress)
  if plan.stage == SOURCE then
    force.set_saved_technology_progress(value, progress)
  else
    value.saved_progress = progress
  end
end

local function same_saved_progress(actual, expected)
  -- F110 represents no saved progress as nil via the force getter. F200's
  -- retained technology property can represent that same absence as nil or 0.
  if expected == nil and plan.stage == SUCCESSOR then return actual == nil or close(actual, 0) end
  if actual == nil or expected == nil then return actual == expected end
  return close(actual, expected)
end

local function current_name(force)
  local value = force.current_research
  return value and value.name or nil
end

local function queue_enabled(force)
  -- F110 exposes the queue opt-in. F200's native queue is always available
  -- and has no research_queue_enabled member to inspect.
  if plan.stage == SOURCE then return force.research_queue_enabled end
  return true
end

local function effect_vector(value)
  local effects = value.prototype and value.prototype.effects
  if type(effects) ~= "table" then fail("retained technology effects are absent: " .. value.name) end
  local out = {}
  for _, effect in pairs(effects) do
    if type(effect) ~= "table" or type(effect.type) ~= "string" or type(effect.modifier) ~= "number" then
      fail("retained technology effect shape differs: " .. value.name)
    end
    local type_name = effect.type
    -- This is the only F110/F200 effect-token translation in the retained
    -- catalogue. The values remain independently observed as 2/4 below.
    if plan.stage == SUCCESSOR and value.name == plan.continuation
        and type_name == "bulk-inserter-capacity-bonus" then
      type_name = "stack-inserter-capacity-bonus"
    end
    local row = {type=type_name, modifier=effect.modifier}
    if effect.ammo_category ~= nil then
      if type(effect.ammo_category) ~= "string" then fail("retained ammo category differs: " .. value.name) end
      row.ammo_category = effect.ammo_category
    end
    out[#out + 1] = row
  end
  table.sort(out, function(left, right)
    local left_key = left.type .. "\0" .. tostring(left.ammo_category or "") .. "\0" .. tostring(left.modifier)
    local right_key = right.type .. "\0" .. tostring(right.ammo_category or "") .. "\0" .. tostring(right.modifier)
    return left_key < right_key
  end)
  return out
end

local function same_effects(actual, expected)
  if type(actual) ~= "table" or type(expected) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local observed = actual[index]
    if type(observed) ~= "table" or observed.type ~= wanted.type
        or observed.ammo_category ~= wanted.ammo_category or not close(observed.modifier, wanted.modifier) then
      return false
    end
  end
  return true
end

local function check_closure()
  local mods = script.active_mods
  if plan.stage == SOURCE then
    if mods.base ~= "1.1.110" or mods["more-infinite-research"] ~= "4.7.11003"
        or mods[FIXTURE] ~= "0.1.0" then
      fail("published F110 source closure differs")
    end
  elseif plan.stage == SUCCESSOR then
    if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "5.0.20000"
        or mods[FIXTURE] ~= "0.2.0" then
      fail("MIR5 F200 successor closure differs")
    end
  else
    fail("catalogue stage differs")
  end
end

local function assert_rows()
  if type(plan.rows) ~= "table" or #plan.rows ~= 17 then fail("retained catalogue row count differs") end
  local seen = {}
  for _, name in ipairs(plan.rows) do
    if type(name) ~= "string" or seen[name] then fail("retained catalogue identities differ") end
    seen[name] = true
  end
  if not seen[plan.direct] or not seen[plan.continuation] or type(plan.probe) ~= "string" then
    fail("retained catalogue anchors differ")
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

local function status(force, name)
  local value = technology(force, name)
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, saved=saved_progress(force, value),
    maximum=value.prototype and value.prototype.max_level, effects=effect_vector(value)}
end

local function snapshot(force)
  local out = {}
  for _, name in ipairs(plan.rows) do out[name] = status(force, name) end
  return out
end

local function same_status(actual, expected, label)
  if type(actual) ~= "table" or type(expected) ~= "table"
      or actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible ~= expected.visible
      or actual.maximum ~= expected.maximum or not same_saved_progress(actual.saved, expected.saved)
      or not same_effects(actual.effects, expected.effects) then
    fail(label .. " retained technology state differs")
  end
end

local function assert_snapshot(force, expected, label, successor)
  if type(expected) ~= "table" then fail(label .. " snapshot is absent") end
  for _, name in ipairs(plan.rows) do
    local wanted, actual = expected[name], status(force, name)
    if successor and name == plan.direct then
      if type(wanted) ~= "table" or actual.level ~= wanted.level + 1
          or actual.researched ~= wanted.researched or actual.enabled ~= wanted.enabled
          or actual.visible ~= wanted.visible or actual.maximum ~= wanted.maximum
          or not same_saved_progress(actual.saved, nil) or not same_effects(actual.effects, wanted.effects) then
        fail(label .. " successor direct state differs")
      end
    else
      same_status(actual, wanted, label .. " " .. name)
    end
  end
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=current_name(force), queue=queue, progress=force.research_progress,
    enabled=queue_enabled(force)}
end

local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if type(expected) ~= "table" or actual.current ~= expected.current or actual.enabled ~= true
      or not close(actual.progress, expected.progress) or #actual.queue ~= #expected.queue then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs") end
  end
  return actual
end

local function create_lab(force, position)
  local entity = game.surfaces[1].create_entity{name="lab", position=position, force=force}
  if entity == nil or entity.valid == false then fail("could not create real mining lab") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real mining lab input is absent") end
  return entity
end

local function fill_lab(state, value)
  local entity = state.lab
  if entity == nil or entity.valid == false then fail("real mining lab is absent") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real mining lab input is absent") end
  inventory.clear()
  local ingredients = value.research_unit_ingredients
  if type(ingredients) ~= "table" or #ingredients == 0 then fail("mining lab research ingredients are absent") end
  state.lab_initial = {}
  for _, ingredient in ipairs(ingredients) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string" then
      fail("mining lab ingredient differs")
    end
    if inventory.insert{name=ingredient.name, count=PACKS} ~= PACKS then
      fail("real mining lab rejected " .. ingredient.name)
    end
    state.lab_initial[ingredient.name] = inventory.get_item_count(ingredient.name)
  end
  entity.energy = 100000000
end

local function freeze_lab(state)
  local entity = state.lab
  if entity == nil or entity.valid == false then fail("real mining lab disappeared") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real mining lab input disappeared") end
  entity.energy = 0
  inventory.clear()
end

local function assert_capacity_source(force)
  if not close(force.inserter_stack_size_bonus, 2)
      or not close(force.stack_inserter_capacity_bonus, 4) then
    fail("published F110 stack inserter effects differ")
  end
end

local function assert_capacity_successor(force)
  if not close(force.inserter_stack_size_bonus, 2)
      or not close(force.bulk_inserter_capacity_bonus, 4) then
    fail("F200 bulk inserter effects differ")
  end
end

local function seed_remaining(force)
  local seeded = 0
  for _, name in ipairs(plan.rows) do
    if name ~= plan.direct then
      local value = technology(force, name)
      value.enabled = true
      value.level = value.prototype.level + 1
      if value.researched then fail("saved catalogue seed became researched: " .. name) end
      seeded = seeded + 1
    end
  end
  if seeded ~= 16 then fail("saved catalogue seed count differs") end
  force.reset_technology_effects()
  return seeded
end

local function seed_suspended(force)
  force.enable_all_prototypes()
  for _, name in ipairs(plan.rows) do
    local value = technology(force, name)
    value.enabled = true
    value.level = value.prototype.level + 1
  end
  local direct = technology(force, plan.direct)
  set_saved_progress(force, direct, .27)
  if not close(saved_progress(force, direct), .27) or current_name(force) ~= nil
      or #(force.research_queue or {}) ~= 0 then
    fail("suspended source state differs")
  end
  force.reset_technology_effects()
  return snapshot(force)
end

local function seed_foreign()
  local foreign = game.create_force("mir5-f110-f200-transition-foreign")
  foreign.enable_all_prototypes()
  local direct = technology(foreign, plan.direct)
  direct.enabled = false
  if direct.enabled ~= false then fail("foreign disabled state differs") end
  return foreign.index, status(foreign, plan.direct)
end

local function assert_foreign(state)
  local foreign = game.forces[state.foreign_index]
  if foreign == nil or foreign.valid == false then fail("foreign force is absent") end
  same_status(status(foreign, plan.direct), state.foreign_direct, "foreign disabled")
end

local function assert_suspended(state, label)
  local paused = game.forces[state.suspended_index]
  if paused == nil or paused.valid == false then fail(label .. " suspended force is absent") end
  assert_snapshot(paused, state.suspended_snapshot, label .. " suspended", false)
  if not close(saved_progress(paused, technology(paused, plan.direct)), .27)
      or current_name(paused) ~= nil or #(paused.research_queue or {}) ~= 0 then
    fail(label .. " suspended work differs")
  end
end

local function marker(stage, state)
  local capacity = plan.stage == SOURCE and "stack_inserter_capacity_bonus" or "bulk_inserter_capacity_bonus"
  local capacity_value = plan.stage == SOURCE and game.forces.player.stack_inserter_capacity_bonus
    or game.forces.player.bulk_inserter_capacity_bonus
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"f110-f200-transition\","
    .. "\"stage\":\"" .. stage .. "\","
    .. "\"status\":\"passed\","
    .. "\"source_direct_lab_completions\":" .. tostring(state.source_direct_labs or 0) .. ","
    .. "\"successor_direct_lab_completions\":" .. tostring(state.successor_direct_labs or 0) .. ","
    .. "\"seeded_catalogue_rows\":" .. tostring(state.seeded_catalogue_rows or 0) .. ","
    .. "\"retained_catalogue_rows\":17,"
    .. "\"queued_progress\":0.42,\"suspended_progress\":0.27,"
    .. "\"foreign_disabled\":true,"
    .. "\"inserter_stack_size_bonus\":" .. tostring(game.forces.player.inserter_stack_size_bonus) .. ","
    .. "\"" .. capacity .. "\":" .. tostring(capacity_value) .. ","
    .. "\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end

local function source_init()
  check_closure(); assert_rows()
  if read_state() ~= nil then fail("source state already exists") end
  local force = game.forces.player
  force.enable_all_prototypes(); force.research_queue_enabled = true
  local direct = technology(force, plan.direct)
  unlock(direct); direct.enabled = true
  if direct.researched or direct.level ~= 1 then fail("source mining target is not fresh") end
  local state = {phase="await-source-lab", origin="published-f110-4.7.11003", lab=create_lab(force, {0, 0}),
    before_mining=force.manual_mining_speed_modifier, source_direct_labs=0, successor_direct_labs=0,
    deadline=game.tick + DEADLINE}
  write_state(state)
  fill_lab(state, direct)
  if force.add_research(direct) ~= true or current_name(force) ~= plan.direct then
    fail("could not queue source mining lab")
  end
end

local function finish_source(state)
  local force = game.forces.player
  freeze_lab(state)
  if technology(force, plan.direct).level ~= 2
      or not close(force.manual_mining_speed_modifier, state.before_mining + .05) then
    fail("source direct mining completion differs")
  end
  state.seeded_catalogue_rows = seed_remaining(force)
  assert_capacity_source(force)
  local direct, probe = technology(force, plan.direct), technology(force, plan.probe)
  unlock(probe); probe.enabled = true; force.research_queue_enabled = true
  force.research_queue = {direct, probe}; force.research_progress = .42
  state.player_queue = assert_queue(force, {current=plan.direct, queue={plan.direct, plan.probe}, progress=.42}, "source")
  state.player_snapshot = snapshot(force)
  local suspended = game.create_force("mir5-f110-f200-transition-suspended")
  state.suspended_index, state.suspended_snapshot = suspended.index, seed_suspended(suspended)
  state.foreign_index, state.foreign_direct = seed_foreign()
  state.phase = "source-complete"
  marker("initial", state); game.server_save(SAVE)
end

local function source_tick()
  local state = read_state()
  if type(state) ~= "table" then fail("source state is absent") end
  if state.phase == "source-complete" then
    assert_snapshot(game.forces.player, state.player_snapshot, "source reload", false)
    assert_queue(game.forces.player, state.player_queue, "source reload")
    assert_capacity_source(game.forces.player); assert_suspended(state, "source reload"); assert_foreign(state)
    if loaded and not reload_reported then marker("reload", state); reload_reported = true end
    return
  end
  if game.tick > state.deadline then fail("source mining lab missed deadline") end
  if state.phase == "await-source-lab" and state.source_direct_labs == 1 then finish_source(state) end
end

local function successor_config()
  check_closure(); assert_rows()
  local state = read_state()
  if type(state) ~= "table" or state.origin ~= "published-f110-4.7.11003"
      or state.phase ~= "source-complete" or state.source_direct_labs ~= 1
      or state.seeded_catalogue_rows ~= 16 then
    fail("successor lacks complete published F110 source witness")
  end
  local force = game.forces.player
  assert_snapshot(force, state.player_snapshot, "pre-successor", false)
  assert_queue(force, state.player_queue, "pre-successor")
  assert_suspended(state, "pre-successor"); assert_foreign(state); assert_capacity_successor(force)
  state.lab = create_lab(force, {4, 0})
  state.phase, state.deadline = "await-successor-lab", game.tick + DEADLINE
  fill_lab(state, technology(force, plan.direct))
end

local function finish_successor(state)
  local force = game.forces.player
  freeze_lab(state)
  if state.successor_direct_labs ~= 1
      or not close(force.manual_mining_speed_modifier, state.before_mining + .10) then
    fail("successor direct mining completion differs")
  end
  assert_snapshot(force, state.player_snapshot, "successor", true)
  assert_capacity_successor(force); assert_suspended(state, "successor"); assert_foreign(state)
  local queue = queue_snapshot(force)
  if queue.current ~= plan.probe or #queue.queue ~= 1 or queue.queue[1] ~= plan.probe then
    fail("successor did not retain queued probe")
  end
  state.phase = "successor-complete"
  marker("initial", state); game.server_save(SAVE)
end

local function successor_tick()
  local state = read_state()
  if type(state) ~= "table" then fail("successor state is absent") end
  if state.phase == "successor-complete" then
    assert_snapshot(game.forces.player, state.player_snapshot, "successor reload", true)
    assert_capacity_successor(game.forces.player); assert_suspended(state, "successor reload"); assert_foreign(state)
    if loaded and not reload_reported then marker("reload", state); reload_reported = true end
    return
  end
  if game.tick > state.deadline then fail("successor mining lab missed deadline") end
  if state.phase == "await-successor-lab" and state.successor_direct_labs == 1 then finish_successor(state) end
end

if plan.stage == SOURCE then script.on_init(source_init)
elseif plan.stage == SUCCESSOR then script.on_configuration_changed(successor_config)
else fail("unknown stage") end

script.on_event(defines.events.on_research_finished, function(event)
  local state = read_state()
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player
      or event.research.name ~= plan.direct then return end
  if plan.stage == SOURCE and state.phase == "await-source-lab" then
    state.source_direct_labs = state.source_direct_labs + 1
    if state.source_direct_labs ~= 1 then fail("source mining lab completed more than once") end
  elseif plan.stage == SUCCESSOR and state.phase == "await-successor-lab" then
    state.successor_direct_labs = state.successor_direct_labs + 1
    if state.successor_direct_labs ~= 1 then fail("successor mining lab completed more than once") end
  end
end)

script.on_load(function()
  local state = read_state()
  loaded = type(state) == "table" and (state.phase == "source-complete" or state.phase == "successor-complete")
  reload_reported = false
end)

script.on_event(defines.events.on_tick, function()
  if plan.stage == SOURCE then source_tick() else successor_tick() end
end)
