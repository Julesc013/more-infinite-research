-- Disposable native fixture for the narrow 3.2.x Vulcanus discovery repair.
-- It has no MIR-private API or storage access: the successor only observes
-- the ordinary configuration result before it starts its one current lab.
local M = {}

local KEY = "mir5_discovery_recovery_fixture"
local FIXTURE = "mir-fixture-discovery-recovery"
local OBSERVER = "mir-fixture-mir5-active-mods-observer"
local CASE = "discovery-recovery"
local SAVE = "mir5-native-complete"
local IRON = "recipe-prod-research_iron-1"
local GEAR = "recipe-prod-research_gears-1"
local DISCOVERY = "planet-discovery-vulcanus"
local LOCATION = "vulcanus"
local PACKS = 32
local DEADLINE = 18000
local EPSILON = .000001

local loaded, reload_reported = false, false

local function fail(message) error("[mir-fixture-discovery-recovery] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= EPSILON
end

local function source_version()
  local version = script.active_mods["more-infinite-research"]
  local fixture = script.active_mods[FIXTURE]
  if (version == "3.2.0" and fixture == "0.1.0") or (version == "3.2.1" and fixture == "0.1.1") then
    return version
  end
  return nil
end

local function check_closure(stage)
  local expected = {
    base = "2.1.23", ["space-age"] = "2.1.23", quality = "2.1.23",
    ["elevated-rails"] = "2.1.23", recycler = "2.1.23", [OBSERVER] = "0.1.0",
  }
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then fail("runtime closure differs: " .. name) end
  end
  if stage == "source" then
    if source_version() == nil then fail("source MIR/fixture pair differs") end
  elseif script.active_mods["more-infinite-research"] ~= "5.0.21000" or script.active_mods[FIXTURE] ~= "0.2.0" then
    fail("MIR5 successor/fixture pair differs")
  end
  expected["more-infinite-research"], expected[FIXTURE] = script.active_mods["more-infinite-research"], script.active_mods[FIXTURE]
  for name in pairs(script.active_mods) do
    if expected[name] == nil then fail("unexpected active mod in fixture closure: " .. tostring(name)) end
  end
end

local function assert_source_defaults()
  local expected = {
    ["ips-enable-research_iron"] = true,
    ["ips-cost-base-research_iron"] = 8000,
    ["ips-cost-growth-research_iron"] = 2,
    ["ips-max-level-research_iron"] = 0,
    ["ips-research-time-research_iron"] = 60,
    ["ips-effect-per-level-research_iron"] = 10,
    ["ips-require-space-gate"] = false,
    ["mir-science-pack-ingredient-policy"] = "configured",
    ["mir-lab-incompatibility-policy"] = "reduce",
  }
  for name, expected_value in pairs(expected) do
    local setting = settings.startup and settings.startup[name]
    if setting == nil or setting.value ~= expected_value then
      fail("historical source default differs: " .. name)
    end
  end
end

local function technology(force, name, label)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail(label .. " technology is absent: " .. name) end
  return value
end

local function iron_effects(value, label)
  local expected, seen = {['iron-plate'] = true, ['casting-iron'] = true}, {}
  for _, effect in pairs((value.prototype and value.prototype.effects) or {}) do
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or expected[effect.recipe] ~= true or effect.change ~= .1 or seen[effect.recipe] then
      fail(label .. " Space Age iron effect differs")
    end
    seen[effect.recipe] = true
  end
  for recipe in pairs(expected) do
    if seen[recipe] ~= true then fail(label .. " Space Age iron effect differs") end
  end
  return .1
end

local function gear_effects(value, label)
  local expected = {"casting-iron-gear-wheel", "iron-gear-wheel"}
  local effects = value.prototype and value.prototype.effects
  local count = 0
  for index, effect in ipairs(effects or {}) do
    count = count + 1
    local recipe = expected[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or effect.change ~= .1 then
      fail(label .. " gear effect differs")
    end
  end
  if count ~= #expected then fail(label .. " gear effect differs") end
  return .1
end

local function saved_progress(value, label)
  local progress = value.saved_progress
  if type(progress) ~= "number" or progress ~= progress or progress < 0 or progress >= 1 then
    fail(label .. " saved technology progress is outside [0,1)")
  end
  return progress
end

local function location_unlocked(force, label)
  if force == nil or type(force.is_space_location_unlocked) ~= "function" then
    fail(label .. " native discovery query is absent")
  end
  local value = force.is_space_location_unlocked(LOCATION)
  if type(value) ~= "boolean" then fail(label .. " native discovery query is not boolean") end
  return value
end

local function collect_direct_prerequisites(value, label)
  local result, seen = {}, {}
  for _, prerequisite in pairs(value.prerequisites or {}) do
    if prerequisite == nil or prerequisite.valid == false or type(prerequisite.name) ~= "string"
        or seen[prerequisite.name] then
      fail(label .. " direct prerequisite differs")
    end
    seen[prerequisite.name] = true
    result[#result + 1] = prerequisite
  end
  table.sort(result, function(left, right) return left.name < right.name end)
  return result
end

local function seed_direct_prerequisites(values)
  local names = {}
  for _, value in ipairs(values) do
    value.enabled, value.researched = true, true
    names[#names + 1] = value.name
  end
  return names
end

local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end

local function queue_ids(values)
  local out = {}
  for index, value in ipairs(values or {}) do out[index] = tostring(value) end
  return table.concat(out, ",")
end

local function queue_diagnostic(expected, actual, vulcanus_unlocked)
  return " expected-current=" .. tostring(expected.current)
    .. " actual-current=" .. tostring(actual.current)
    .. " expected-queue-ids=" .. queue_ids(expected.queue)
    .. " actual-queue-ids=" .. queue_ids(actual.queue)
    .. " expected-queue-length=" .. tostring(#(expected.queue or {}))
    .. " actual-queue-length=" .. tostring(#(actual.queue or {}))
    .. " expected-progress=" .. tostring(expected.progress)
    .. " actual-progress=" .. tostring(actual.progress)
    .. " vulcanus-unlocked=" .. tostring(vulcanus_unlocked)
end

local function assert_queue(force, expected, label, vulcanus_unlocked)
  local actual = queue_snapshot(force)
  local diagnostic = queue_diagnostic(expected, actual, vulcanus_unlocked)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs;" .. diagnostic)
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs;" .. diagnostic) end
  end
  return actual
end

local function pause_fixture_iron_queue(force, expected)
  if type(expected) ~= "table" or expected.current ~= IRON or #(expected.queue or {}) ~= 1
      or expected.queue[1] ~= IRON or not close(expected.progress, .42) then
    fail("protected player iron queue is not fixture-owned")
  end
  -- LuaForce.research_queue accepts a complete TechnologyID array.  Its exact
  -- 2.1.23 contract says an empty array cancels only the current queue; never
  -- use cancel_current_research(), which can also remove dependent entries.
  force.research_queue = {}
  local paused = queue_snapshot(force)
  if paused.current ~= false or #paused.queue ~= 0 then fail("could not pause fixture-owned player iron queue") end
end

local function restore_fixture_iron_queue(force, expected)
  -- Restore the captured TechnologyID names first, then the documented
  -- read/write progress field, and read them back because invalid entries are
  -- silently dropped by LuaForce.research_queue.
  force.research_queue = expected.queue
  force.research_progress = expected.progress
  assert_queue(force, expected, "restored player iron", location_unlocked(force, "restored player"))
end

local function research_unit(value, label)
  local packs, seen = {}, {}
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    local name, amount = ingredient.name or ingredient[1], ingredient.amount or ingredient[2]
    if type(name) ~= "string" or type(amount) ~= "number" or amount <= 0 or seen[name] then
      fail(label .. " emitted science differs")
    end
    seen[name] = true
    packs[#packs + 1] = {name = name, amount = amount}
  end
  if #packs == 0 then fail(label .. " emitted science is absent") end
  return packs
end

local function new_lab(force, label)
  local entity = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = force}
  if entity == nil or entity.valid == false then fail(label .. " lab is absent") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail(label .. " lab input is absent") end
  return entity, inventory
end

local function fill_lab(entity, inventory, value, label)
  inventory.clear()
  local packs = research_unit(value, label)
  local supplied = {}
  for _, ingredient in ipairs(packs) do
    if inventory.insert{name = ingredient.name, count = PACKS} ~= PACKS then
      fail(label .. " lab rejected science: " .. ingredient.name)
    end
    supplied[ingredient.name] = PACKS
  end
  entity.energy = 1000000000
  return supplied
end

local function freeze_lab(entity)
  local inventory = entity and entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("completed fixture lab input is absent") end
  inventory.clear()
  entity.energy = 0
end

local function assert_consumed(entity, supplied, label)
  local inventory = entity and entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail(label .. " lab input is absent") end
  for name, before in pairs(supplied or {}) do
    if inventory.get_item_count(name) >= before then fail(label .. " lab did not consume " .. name) end
  end
end

local function snapshot(force, label)
  local iron = technology(force, IRON, label)
  local discovery = technology(force, DISCOVERY, label)
  local recipe = force.recipes and force.recipes["iron-plate"]
  if recipe == nil or recipe.valid == false or type(recipe.productivity_bonus) ~= "number" then
    fail(label .. " iron-plate productivity is absent")
  end
  return {
    iron = {level = iron.level, researched = iron.researched, enabled = iron.enabled,
      saved_progress = saved_progress(iron, label), effect = iron_effects(iron, label),
      bonus = recipe.productivity_bonus},
    discovery = {researched = discovery.researched, unlocked = location_unlocked(force, label)},
    queue = queue_snapshot(force),
  }
end

local function gear_snapshot(force, label)
  local gear = technology(force, GEAR, label)
  local recipe = force.recipes and force.recipes["iron-gear-wheel"]
  if recipe == nil or recipe.valid == false or type(recipe.productivity_bonus) ~= "number" then
    fail(label .. " iron-gear-wheel productivity is absent")
  end
  if type(gear.level) ~= "number" or gear.level < 1 or gear.level % 1 ~= 0 then
    fail(label .. " gear level is invalid")
  end
  return {level = gear.level, bonus = recipe.productivity_bonus, effect = gear_effects(gear, label)}
end

local function assert_gear_advance(before, after, label)
  if type(before) ~= "table" or type(after) ~= "table" or after.level ~= before.level + 1
      or not close(after.effect, before.effect) or not close(after.bonus, before.bonus + before.effect) then
    fail(label .. " gear lab result differs")
  end
end

local function assert_same_gear(actual, expected, label)
  if type(actual) ~= "table" or type(expected) ~= "table" or actual.level ~= expected.level
      or not close(actual.bonus, expected.bonus) or not close(actual.effect, expected.effect) then
    fail(label .. " saved gear state differs")
  end
end

local function assert_source_snapshot(force, expected, label, foreign, repaired)
  if type(expected) ~= "table" or type(expected.iron) ~= "table" or type(expected.discovery) ~= "table"
      or type(expected.queue) ~= "table" then fail(label .. " protected source state is malformed") end
  local actual = snapshot(force, label)
  local iron = actual.iron
  if iron.level ~= expected.iron.level or iron.researched ~= expected.iron.researched
      or iron.enabled ~= expected.iron.enabled or not close(iron.saved_progress, expected.iron.saved_progress)
      or not close(iron.effect, expected.iron.effect) or not close(iron.bonus, expected.iron.bonus) then
    fail(label .. " protected iron state differs")
  end
  assert_queue(force, expected.queue, label .. " protected", actual.discovery.unlocked)
  if iron.level ~= 3 or iron.researched ~= false or not close(iron.effect, .1) or not close(iron.bonus, .2) then
    fail(label .. " earned iron state differs")
  end
  if foreign then
    if actual.discovery.researched ~= false or actual.discovery.unlocked ~= false then
      fail(label .. " unresearched foreign Vulcanus state differs")
    end
    assert_queue(force, {current = IRON, queue = {IRON}, progress = .27}, label, actual.discovery.unlocked)
  else
    local expected_unlocked = repaired and true or expected.discovery.unlocked
    if actual.discovery.researched ~= true then
      fail(label .. " player Vulcanus discovery state differs")
    end
    if actual.discovery.unlocked ~= expected_unlocked then
      if repaired then fail("MIR discovery repair did not restore researched Vulcanus") end
      fail(label .. " player Vulcanus discovery state differs")
    end
    assert_queue(force, {current = IRON, queue = {IRON}, progress = .42}, label, actual.discovery.unlocked)
  end
  return actual
end

local function assert_same(actual, expected, label)
  if actual.iron.level ~= expected.iron.level or actual.iron.researched ~= expected.iron.researched
      or actual.iron.enabled ~= expected.iron.enabled or not close(actual.iron.saved_progress, expected.iron.saved_progress)
      or not close(actual.iron.effect, expected.iron.effect) or not close(actual.iron.bonus, expected.iron.bonus)
      or actual.discovery.researched ~= expected.discovery.researched or actual.discovery.unlocked ~= expected.discovery.unlocked then
    fail(label .. " saved state differs")
  end
  -- Compare the actual queue separately so table identity never becomes an API assumption.
  if actual.queue.current ~= expected.queue.current or #actual.queue.queue ~= #expected.queue.queue
      or not close(actual.queue.progress, expected.queue.progress) then fail(label .. " saved queue differs") end
  for index, name in ipairs(expected.queue.queue) do
    if actual.queue.queue[index] ~= name then fail(label .. " saved queue identity differs") end
  end
end

local function marker(stage, state, successor)
  local player = snapshot(game.forces.player, "fixture marker player")
  local gear = successor and gear_snapshot(game.forces.player, "fixture marker gear") or false
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = CASE, stage = stage, status = "passed", qualification = "native-runner-readback-required",
    fixture_role = successor and "successor" or "source", source_version = state.source_version,
    source_actual_labs = state.source_actual_labs,
    successor_actual_labs = successor and successor.actual_labs or 0,
    source_scripted_iron_level = state.player.iron.level,
    source_scripted_iron_plate_bonus = state.player.iron.bonus,
    player_iron_queue_current = player.queue.current,
    player_iron_queue_progress = player.queue.progress,
    successor_gear_level_before = successor and successor.gear_before.level or false,
    successor_gear_bonus_before = successor and successor.gear_before.bonus or false,
    successor_gear_level_after = successor and gear.level or false,
    successor_gear_bonus_after = successor and gear.bonus or false,
    successor_gear_native_effect = successor and gear.effect or false,
    foreign_iron_progress = state.foreign.queue.progress,
    source_discovery_lab_researched = state.player.discovery.researched,
    source_vulcanus_native_locked_after_discovery = not state.player.discovery.unlocked,
    player_vulcanus_unlocked = player.discovery.unlocked,
    foreign_vulcanus_unresearched_locked = not state.foreign.discovery.researched and not state.foreign.discovery.unlocked,
    on_load_read_only = stage == "reload",
  }))
end

local function source_preflight()
  check_closure("source")
  assert_source_defaults()
  local player = game.forces.player
  local discovery = technology(player, DISCOVERY, "source player")
  local iron = technology(player, IRON, "source player")
  if discovery.researched then fail("source Vulcanus discovery is already researched") end
  if location_unlocked(player, "source player") then fail("source Vulcanus is unexpectedly unlocked") end
  if iron.researched or iron.level ~= 1 then fail("source iron technology is not fresh") end
  iron_effects(iron, "source player")
  research_unit(discovery, "source Vulcanus discovery")
  research_unit(iron, "source iron")
  location_unlocked(player, "source player")
  return player, discovery, iron, collect_direct_prerequisites(discovery, "source discovery"),
    collect_direct_prerequisites(iron, "source iron")
end

local function seed_foreign()
  local foreign = game.create_force("mir5-discovery-recovery-foreign")
  if foreign == nil or foreign.valid == false then fail("foreign force is absent") end
  local discovery = technology(foreign, DISCOVERY, "foreign")
  local iron = technology(foreign, IRON, "foreign")
  local prerequisites = collect_direct_prerequisites(iron, "foreign iron")
  seed_direct_prerequisites(prerequisites)
  discovery.researched = false
  iron.researched = false
  iron.level = 3
  foreign.reset_technology_effects()
  if not close((foreign.recipes["iron-plate"] or {}).productivity_bonus, .2) then fail("foreign iron bonus differs") end
  if location_unlocked(foreign, "foreign") then fail("foreign Vulcanus did not remain locked") end
  if foreign.add_research(iron) ~= true then fail("could not queue foreign iron") end
  foreign.research_progress = .27
  return foreign
end

local function source_init()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  -- Complete all semantic reads, including both direct prerequisite vectors,
  -- before a seed, lab, queue, storage, or save write is possible.
  local player, discovery, iron, discovery_prerequisites, iron_prerequisites = source_preflight()
  local discovery_labels = seed_direct_prerequisites(discovery_prerequisites)
  local iron_labels = seed_direct_prerequisites(iron_prerequisites)
  local lab, inventory = new_lab(player, "source discovery")
  local state = {phase = "await-source-discovery", source_version = source_version(), source_actual_labs = 0,
    discovery_prerequisites = discovery_labels, iron_prerequisites = iron_labels, lab = lab,
    source_packs = fill_lab(lab, inventory, discovery, "source discovery"), deadline = game.tick + DEADLINE}
  storage[KEY] = state
  if player.add_research(discovery) ~= true or player.current_research == nil or player.current_research.name ~= DISCOVERY then
    fail("could not queue one actual source Vulcanus discovery lab")
  end
end

local function complete_source(state)
  local player = game.forces.player
  local discovery = technology(player, DISCOVERY, "source player")
  local expected_unlocked = state.source_version == "3.2.1"
  if state.source_actual_labs ~= 1 or discovery.researched ~= true
      or location_unlocked(player, "source player") ~= expected_unlocked then
    fail("actual source Vulcanus discovery result differs")
  end
  assert_consumed(state.lab, state.source_packs, "source discovery")
  freeze_lab(state.lab)
  local iron = technology(player, IRON, "source player")
  iron.researched = false
  iron.level = 3
  player.reset_technology_effects()
  if not close((player.recipes["iron-plate"] or {}).productivity_bonus, .2) then fail("source iron bonus differs") end
  if player.add_research(iron) ~= true then fail("could not queue source iron") end
  player.research_progress = .42
  local foreign = seed_foreign()
  state.player = snapshot(player, "source player")
  state.foreign_index, state.foreign = foreign.index, snapshot(foreign, "foreign")
  assert_source_snapshot(player, state.player, "source player", false)
  assert_source_snapshot(foreign, state.foreign, "foreign", true)
  state.phase = "source-complete"
  -- An initial server load may already have armed this local callback before
  -- the first source lab completes.  Only a later cold load may report a
  -- reload observation for the completed save.
  loaded, reload_reported = false, false
  marker("initial", state)
  game.server_save(SAVE)
end

local function successor_begin()
  check_closure("successor")
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "source-complete"
      or (state.source_version ~= "3.2.0" and state.source_version ~= "3.2.1") then
    fail("protected 3.2.x source state is absent")
  end
  local player = game.forces.player
  local foreign = game.forces[state.foreign_index]
  -- This preflight intentionally runs before successor storage/lab writes.
  local requires_repair = state.source_version == "3.2.0"
  local player_before = assert_source_snapshot(player, state.player, "successor player", false, requires_repair)
  if player_before.discovery.unlocked ~= true then
    if requires_repair then fail("MIR discovery repair did not restore researched Vulcanus") end
    fail("3.2.1 source Vulcanus discovery was not retained by successor")
  end
  local foreign_before = assert_source_snapshot(foreign, state.foreign, "successor foreign", true)
  local iron = technology(player, IRON, "successor player")
  iron_effects(iron, "successor player")
  local gear = technology(player, GEAR, "successor player")
  local gear_before = gear_snapshot(player, "successor player")
  research_unit(gear, "successor gear")
  local gear_prerequisites = collect_direct_prerequisites(gear, "successor gear")
  -- The protected source state has now been fully read and compared.  The
  -- temporary queue pause is a fixture-owned operation only: it lets the
  -- unqueued gear family perform the one successor lab without changing the
  -- saved iron research unit or claiming that the product paused it.
  pause_fixture_iron_queue(player, player_before.queue)
  local gear_labels = seed_direct_prerequisites(gear_prerequisites)
  if player.add_research(gear) ~= true or player.current_research == nil or player.current_research.name ~= GEAR then
    restore_fixture_iron_queue(player, player_before.queue)
    fail("could not queue one actual successor gear lab")
  end
  local lab, inventory = new_lab(player, "successor gear")
  local successor = {phase = "await-successor-gear", actual_labs = 0, lab = lab,
    packs = fill_lab(lab, inventory, gear, "successor gear"), deadline = game.tick + DEADLINE,
    player_before = player_before, foreign_before = foreign_before, gear_before = gear_before,
    gear_prerequisites = gear_labels, iron_queue = player_before.queue}
  state.successor = successor
end

local function complete_successor(state)
  local successor = state.successor
  local player = game.forces.player
  local discovery = technology(player, DISCOVERY, "successor player")
  if discovery.researched ~= true or not location_unlocked(player, "successor player") then
    fail("successor Vulcanus discovery was not retained after candidate lab")
  end
  if successor.actual_labs ~= 1 then fail("actual successor gear lab count differs") end
  assert_gear_advance(successor.gear_before, gear_snapshot(player, "actual successor gear"), "actual successor gear")
  restore_fixture_iron_queue(player, successor.iron_queue)
  assert_source_snapshot(player, state.player, "successor restored player", false,
    state.source_version == "3.2.0")
  local foreign = game.forces[state.foreign_index]
  assert_source_snapshot(foreign, state.foreign, "successor foreign", true)
  successor.player_after = snapshot(player, "successor player")
  successor.gear_after = gear_snapshot(player, "successor player")
  successor.foreign_after = snapshot(foreign, "successor foreign")
  successor.phase = "successor-complete"
  -- See the matching source completion boundary above: a completed save is
  -- not a cold reload merely because the server continues ticking.
  loaded, reload_reported = false, false
  marker("initial", state, successor)
  game.server_save(SAVE)
end

function M.apply(stage)
  if stage ~= "source" and stage ~= "successor" then fail("unknown fixture control stage") end
  if stage == "source" then script.on_init(source_init) else script.on_configuration_changed(successor_begin) end
  script.on_load(function()
    -- on_load never reads game or durable fixture state; observation happens on
    -- a normal tick after the native save has finished loading.
    loaded, reload_reported = true, false
  end)
  script.on_event(defines.events.on_research_finished, function(event)
    local state = storage and storage[KEY]
    if type(state) ~= "table" or event.by_script ~= false or event.research == nil
        or event.research.force ~= game.forces.player then return end
    if state.phase == "await-source-discovery" and event.research.name == DISCOVERY then
      state.source_actual_labs = state.source_actual_labs + 1
      if state.source_actual_labs ~= 1 then fail("source discovery lab completed more than once") end
    elseif type(state.successor) == "table" and state.successor.phase == "await-successor-gear" and event.research.name == GEAR then
      assert_consumed(state.successor.lab, state.successor.packs, "successor gear")
      state.successor.actual_labs = state.successor.actual_labs + 1
      if state.successor.actual_labs ~= 1 then fail("successor gear lab completed more than once") end
      freeze_lab(state.successor.lab)
      state.successor.phase = "await-successor-observation"
    end
  end)
  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if type(state) ~= "table" then fail("fixture state is absent") end
    if stage == "source" then
      if state.phase == "await-source-discovery" then
        if game.tick > state.deadline then fail("source discovery lab did not finish") end
        if state.lab == nil or state.lab.valid == false then fail("source discovery lab became invalid") end
        state.lab.energy = 1000000000
        if state.source_actual_labs == 1 then complete_source(state) end
      elseif state.phase == "source-complete" and loaded and not reload_reported then
        assert_source_snapshot(game.forces.player, state.player, "source cold reload player", false)
        assert_source_snapshot(game.forces[state.foreign_index], state.foreign, "source cold reload foreign", true)
        marker("reload", state)
        reload_reported = true
      elseif state.phase ~= "source-complete" then fail("source fixture phase differs") end
      return
    end
    local successor = state.successor
    if type(successor) ~= "table" then fail("successor state is absent") end
    if successor.phase == "await-successor-gear" then
      if game.tick > successor.deadline then fail("successor gear lab did not finish") end
      if successor.lab == nil or successor.lab.valid == false then fail("successor gear lab became invalid") end
      successor.lab.energy = 1000000000
    elseif successor.phase == "await-successor-observation" then
      complete_successor(state)
    elseif successor.phase == "successor-complete" and loaded and not reload_reported then
      local foreign = game.forces[state.foreign_index]
      assert_source_snapshot(foreign, state.foreign, "successor cold reload foreign", true)
      if successor.player_after == nil or successor.foreign_after == nil then fail("successor saved observation is absent") end
      local player_after = snapshot(game.forces.player, "successor cold reload player")
      if player_after.discovery.researched ~= true or player_after.discovery.unlocked ~= true then
        fail("successor cold reload lost Vulcanus discovery")
      end
      assert_same(player_after, successor.player_after, "successor cold reload player")
      assert_same_gear(gear_snapshot(game.forces.player, "successor cold reload gear"), successor.gear_after,
        "successor cold reload gear")
      assert_same(snapshot(foreign, "successor cold reload foreign"), successor.foreign_after, "successor cold reload foreign")
      marker("reload", state, successor)
      reload_reported = true
    elseif successor.phase ~= "successor-complete" then fail("successor fixture phase differs") end
  end)
end

return M
