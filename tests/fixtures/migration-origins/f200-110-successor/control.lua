local catalogue = require("__mir-fixture-mir5-migration-origin-f200-110-successor__/catalogue")
local KEY, FIXTURE = catalogue.storage_key, catalogue.fixture
local UINT32_MAX, loaded, reload_reported = 4294967295, false, false

local function fail(message) error("[mir5-migration-origin-f200-110-successor] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end
local function map_count(value)
  local count = 0
  for _ in pairs(value or {}) do count = count + 1 end
  return count
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("source technology is absent: " .. tostring(name)) end
  return value
end
local function source_names()
  local names = {}
  for name in pairs(catalogue.rows) do names[#names + 1] = name end
  table.sort(names)
  if #names ~= 31 or catalogue.rows["recipe-prod-research_inventory_capacity-1"] ~= nil then
    fail("published source roster definition differs")
  end
  return names
end
local function token(value)
  local result = catalogue.source_change_tokens[value]
  if result == nil then fail("published source effect scalar is unsupported") end
  return result
end
local function source_effect_signature(name)
  local rows = {}
  for _, effect in ipairs(catalogue.rows[name] or {}) do
    if effect.type == "change-recipe-productivity" then
      rows[#rows + 1] = effect.type .. "|" .. effect.recipe .. "|" .. token(effect.change)
    elseif effect.type == "worker-robot-battery" then
      rows[#rows + 1] = effect.type .. "|" .. token(effect.modifier)
    else
      fail("published source effect type is unsupported")
    end
  end
  table.sort(rows)
  return table.concat(rows, ",")
end
local function source_recipe_bonuses()
  local expected = {}
  for _, effects in pairs(catalogue.rows) do
    for _, effect in ipairs(effects) do
      if effect.type == "change-recipe-productivity" then
        expected[effect.recipe] = (expected[effect.recipe] or 0) + effect.change
      end
    end
  end
  return expected
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false, queue = queue, progress = force.research_progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do if actual.queue[index] ~= name then fail(label .. " queue identity differs") end end
end
local function assert_settings()
  if map_count(catalogue.settings) ~= 42 then fail("published source settings roster differs") end
  for name, expected in pairs(catalogue.settings) do
    local value = settings.startup[name]
    if value == nil or value.value ~= expected then fail("published source setting differs: " .. name) end
  end
end
local function assert_snapshot(snapshot, names, label, direct_level, direct_progress)
  if type(snapshot) ~= "table" or type(snapshot.technologies) ~= "table" or type(snapshot.effects) ~= "table"
      or type(snapshot.recipes) ~= "table" or type(snapshot.fields) ~= "table" then
    fail(label .. " saved source snapshot is malformed")
  end
  if map_count(snapshot.technologies) ~= #names or map_count(snapshot.effects) ~= #names then
    fail(label .. " saved source roster count differs")
  end
  for _, name in ipairs(names) do
    local row = snapshot.technologies[name]
    local expected_level = name == catalogue.direct and direct_level or 2
    local expected_progress = name == catalogue.direct and direct_progress or 0
    if type(row) ~= "table" or row.level ~= expected_level or row.researched ~= false or row.enabled ~= true
        or row.visible ~= false or row.maximum ~= UINT32_MAX or not close(row.saved, expected_progress) then
      fail(label .. " saved source technology differs: " .. name)
    end
    if snapshot.effects[name] ~= source_effect_signature(name) then
      fail(label .. " saved source effect multiset differs: " .. name)
    end
  end
  local recipes = source_recipe_bonuses()
  if map_count(snapshot.recipes) ~= map_count(recipes) then fail(label .. " saved recipe-bonus count differs") end
  for recipe, expected in pairs(recipes) do
    if not close(snapshot.recipes[recipe], expected) then fail(label .. " saved recipe bonus differs: " .. recipe) end
  end
  if not close(snapshot.fields.manual_mining_speed_modifier, 0) then
    fail(label .. " saved native manual-mining baseline differs")
  end
  if not close(snapshot.fields.worker_robots_battery_modifier, .1) then
    fail(label .. " saved worker-robot-battery contribution differs")
  end
end
local function assert_force(force, snapshot, names, label, ignore_direct, candidate_delta)
  if force == nil or force.valid == false then fail(label .. " force is absent") end
  for _, name in ipairs(names) do
    local expected, actual = snapshot.technologies[name], technology(force, name)
    if name ~= catalogue.direct or not ignore_direct then
      if actual.level ~= expected.level or actual.researched ~= expected.researched or actual.enabled ~= expected.enabled
          or actual.visible_when_disabled ~= expected.visible or actual.prototype.max_level ~= expected.maximum
          or not close(actual.saved_progress, expected.saved) then
        fail(label .. " retained source technology differs: " .. name)
      end
    end
  end
  for recipe, expected in pairs(snapshot.recipes) do
    local value = force.recipes[recipe]
    local wanted = expected
    if ignore_direct and recipe == catalogue.gear_recipe then wanted = wanted + candidate_delta end
    if value == nil or value.valid == false or not close(value.productivity_bonus, wanted) then
      fail(label .. " retained source recipe contribution differs: " .. recipe)
    end
  end
  if not close(force.manual_mining_speed_modifier, snapshot.fields.manual_mining_speed_modifier) then
    fail(label .. " native manual-mining baseline changed")
  end
  if not close(force.worker_robots_battery_modifier, snapshot.fields.worker_robots_battery_modifier) then
    fail(label .. " worker-robot-battery contribution changed")
  end
end
local function state()
  local value = storage and storage[KEY]
  if type(value) ~= "table" or value.phase ~= "completed" or type(value.roster) ~= "table" or value.source_labs ~= 1
      or type(value.player_snapshot) ~= "table" or type(value.foreign_snapshot) ~= "table"
      or type(value.detached_snapshot) ~= "table" or type(value.foreign_queue) ~= "table" then
    fail("protected MIR 1.1 source state is absent or incomplete")
  end
  local names = source_names()
  if #value.roster ~= #names then fail("protected source roster count differs") end
  for index, name in ipairs(names) do if value.roster[index] ~= name then fail("protected source roster differs: " .. name) end end
  assert_snapshot(value.player_snapshot, names, "player", 2, 0)
  assert_snapshot(value.foreign_snapshot, names, "foreign", 1, .42)
  assert_snapshot(value.detached_snapshot, names, "detached", 1, .27)
  if value.foreign_queue.current ~= catalogue.direct or #value.foreign_queue.queue ~= 2
      or value.foreign_queue.queue[1] ~= catalogue.direct or value.foreign_queue.queue[2] ~= "recipe-prod-research_plastic-1"
      or not close(value.foreign_queue.progress, .42) then
    fail("protected foreign source queue differs")
  end
  return value, names
end
local function exact_target()
  for name, expected in pairs(catalogue.targets) do
    if script.active_mods.base == expected.base and script.active_mods["more-infinite-research"] == expected.mir
        and script.active_mods[FIXTURE] == expected.fixture
        and script.active_mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
      return name
    end
  end
  fail("successor runtime target closure differs")
end
local function assert_source_before(state_value, names, ignore_direct, delta)
  assert_settings()
  assert_force(game.forces.player, state_value.player_snapshot, names, "player", ignore_direct, delta or 0)
  local foreign = game.forces[state_value.foreign_index]
  assert_force(foreign, state_value.foreign_snapshot, names, "foreign", false, 0)
  assert_queue(foreign, state_value.foreign_queue, "foreign")
  local detached = game.forces[state_value.detached_index]
  assert_force(detached, state_value.detached_snapshot, names, "detached", false, 0)
  local idle = queue_snapshot(detached)
  if idle.current ~= false or #idle.queue ~= 0 then fail("detached source queue changed") end
end
local function direct_delta(value)
  local matches = 0
  for _, effect in ipairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == catalogue.gear_recipe
        and effect.change == catalogue.expected_gear_delta then matches = matches + 1 end
  end
  if matches ~= 1 then fail("candidate direct gear effect differs") end
  return catalogue.expected_gear_delta
end
local function new_lab()
  local entity = game.surfaces[1].create_entity{name = "lab", position = {8, 0}, force = game.forces.player}
  if entity == nil or entity.valid == false then fail("could not create candidate gear lab") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("candidate gear lab input is absent") end
  return entity, inventory
end
local function fill_lab(successor, direct)
  local packs, inventory = {}, successor.lab.get_inventory(defines.inventory.lab_input)
  inventory.clear()
  for _, ingredient in ipairs(direct.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string" or type(ingredient.amount) ~= "number"
        or ingredient.amount <= 0 or packs[ingredient.name] ~= nil then fail("candidate runtime science differs") end
    if inventory.insert{name = ingredient.name, count = catalogue.lab_packs} ~= catalogue.lab_packs then
      fail("candidate lab rejected science: " .. ingredient.name)
    end
    packs[ingredient.name] = catalogue.lab_packs
  end
  if next(packs) == nil then fail("candidate runtime science is absent") end
  successor.packs = packs
  successor.lab.energy = 1000000000
end
local function assert_consumed(successor)
  local inventory = successor.lab and successor.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("candidate lab input is absent before completion") end
  for name, before in pairs(successor.packs or {}) do if inventory.get_item_count(name) >= before then fail("candidate lab did not consume " .. name) end end
end
local function freeze_lab(successor)
  assert_consumed(successor)
  successor.lab.energy = 0
  successor.lab = nil
  successor.packs = nil
end
local function marker(stage, target, state_value, successor)
  local player = game.forces.player
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"migration-origin-1.1.0-" .. target .. "-successor\","
    .. "\"stage\":\"" .. stage .. "\",\"status\":\"passed\","
    .. "\"source_origin\":\"1.1.0\",\"source_rows\":31,"
    .. "\"source_actual_labs\":" .. tostring(state_value.source_labs) .. ","
    .. "\"candidate_actual_labs\":" .. tostring(successor.candidate_actual_labs) .. ","
    .. "\"source_direct_level\":" .. tostring(state_value.player_snapshot.technologies[catalogue.direct].level) .. ","
    .. "\"candidate_direct_level\":" .. tostring(technology(player, catalogue.direct).level) .. ","
    .. "\"source_gear_bonus\":" .. tostring(state_value.player_snapshot.recipes[catalogue.gear_recipe]) .. ","
    .. "\"candidate_gear_bonus\":" .. tostring(player.recipes[catalogue.gear_recipe].productivity_bonus) .. ","
    .. "\"source_robot_battery\":" .. tostring(state_value.player_snapshot.fields.worker_robots_battery_modifier) .. ","
    .. "\"candidate_robot_battery\":" .. tostring(player.worker_robots_battery_modifier) .. ","
    .. "\"foreign_queue_progress\":0.42,\"detached_progress\":0.27,"
    .. "\"manual_mining_baseline\":0,\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end
local function begin()
  local target = exact_target()
  local state_value, names = state()
  -- Every retained source field is validated before this fixture creates a
  -- candidate lab or writes its successor record.
  assert_source_before(state_value, names, false, 0)
  if type(state_value.successors) == "table" and state_value.successors[target] ~= nil then
    fail("target successor already began")
  end
  local direct = technology(game.forces.player, catalogue.direct)
  if direct.level ~= state_value.player_snapshot.technologies[catalogue.direct].level then
    fail("source direct level differs before candidate work")
  end
  local successor = {phase = "await-candidate-lab", deadline = game.tick + catalogue.deadline_ticks,
    candidate_actual_labs = 0, before_bonus = game.forces.player.recipes[catalogue.gear_recipe].productivity_bonus,
    candidate_delta = direct_delta(direct), source_rows = #names, source_actual_labs = state_value.source_labs}
  state_value.successors = state_value.successors or {}
  state_value.successors[target] = successor
  successor.lab = new_lab()
  fill_lab(successor, direct)
  if game.forces.player.add_research(direct) ~= true or game.forces.player.current_research ~= direct then
    fail("could not queue one actual candidate gear lab")
  end
end
local function complete(target, state_value, successor)
  local names = source_names()
  assert_source_before(state_value, names, true, successor.candidate_delta)
  local direct = technology(game.forces.player, catalogue.direct)
  local before = state_value.player_snapshot.technologies[catalogue.direct]
  if successor.candidate_actual_labs ~= 1 or direct.level ~= before.level + 1 or direct.researched ~= false
      or not close(game.forces.player.recipes[catalogue.gear_recipe].productivity_bonus,
        successor.before_bonus + successor.candidate_delta) then
    fail("actual candidate gear lab result differs")
  end
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then
    fail("candidate player queue survived completion")
  end
end

script.on_configuration_changed(begin)
script.on_load(function()
  local value = storage and storage[KEY]
  loaded = type(value) == "table" and type(value.successors) == "table"
  reload_reported = false
end)
script.on_event(defines.events.on_research_finished, function(event)
  local value = storage and storage[KEY]
  if type(value) ~= "table" or type(value.successors) ~= "table" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= catalogue.direct then return end
  if event.by_script ~= false then fail("candidate gear lab completion is scripted") end
  for _, successor in pairs(value.successors) do
    if successor.phase == "await-candidate-lab" then
      successor.candidate_actual_labs = successor.candidate_actual_labs + 1
      if successor.candidate_actual_labs ~= 1 then fail("candidate gear lab completed more than once") end
      freeze_lab(successor)
      successor.phase = "await-observation"
    end
  end
end)
script.on_event(defines.events.on_tick, function()
  local target = exact_target()
  local state_value = state()
  local successor = state_value.successors and state_value.successors[target]
  if type(successor) ~= "table" then fail("target successor state is absent") end
  if successor.phase == "completed" then
    if loaded and not reload_reported then
      complete(target, state_value, successor)
      marker("reload", target, state_value, successor)
      reload_reported = true
    end
    return
  end
  if successor.phase ~= "await-candidate-lab" and successor.phase ~= "await-observation" then fail("candidate successor phase is invalid") end
  if game.tick > successor.deadline then fail("candidate gear lab did not complete") end
  if successor.phase == "await-candidate-lab" then
    if successor.lab == nil or successor.lab.valid == false then fail("candidate gear lab became invalid") end
    successor.lab.energy = 1000000000
  else
    complete(target, state_value, successor)
    successor.phase = "completed"
    marker("initial", target, state_value, successor)
    game.server_save(catalogue.save)
  end
end)
