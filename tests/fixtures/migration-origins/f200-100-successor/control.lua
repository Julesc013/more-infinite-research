local catalogue = require("__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue")
local KEY, FIXTURE = catalogue.storage_key, catalogue.fixture
local loaded, reload_reported = false, false

local function fail(message) error("[mir5-migration-origin-f200-100-successor] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("missing historical technology: " .. tostring(name)) end
  return value
end
local function signature(value)
  local kind = type(value)
  if kind == "string" then return "s:" .. value end
  if kind == "number" then return "n:" .. string.format("%.17g", value) end
  if kind == "boolean" then return value and "b:true" or "b:false" end
  if kind ~= "table" then return kind .. ":" .. tostring(value) end
  local keys, rows = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  for _, key in ipairs(keys) do rows[#rows + 1] = signature(key) .. "=" .. signature(value[key]) end
  return "{" .. table.concat(rows, ",") .. "}"
end
-- The protected MIR 1.0 snapshot is an immutable source signature.  The
-- current engines expose the same additive recipe-productivity effects with
-- only two observed representation differences: 2.1 may add hidden=false,
-- and its float presentation may use the short authored decimal.  Preserve
-- source bytes and project only the four published values for comparison.
local source_effect_changes = {
  ["0.10000000149011612"] = true,
  ["0.05000000074505806"] = true,
  ["0.019999999552965164"] = true,
  ["0.0099999997764825821"] = true,
}
local current_to_source_change = {
  ["0.1"] = "0.10000000149011612",
  ["0.05"] = "0.05000000074505806",
  ["0.02"] = "0.019999999552965164",
  ["0.01"] = "0.0099999997764825821",
  ["0.10000000149011612"] = "0.10000000149011612",
  ["0.05000000074505806"] = "0.05000000074505806",
  ["0.019999999552965164"] = "0.019999999552965164",
  ["0.0099999997764825821"] = "0.0099999997764825821",
}
local function canonical_effect_rows(rows)
  table.sort(rows)
  return "{" .. table.concat(rows, ",") .. "}"
end
local function canonical_saved_effects(raw, label)
  if type(raw) ~= "string" or raw:sub(1, 1) ~= "{" or raw:sub(-1) ~= "}" then
    fail(label .. " source effect signature is malformed")
  end
  local body, offset, ordinal, rows = raw:sub(2, -2), 1, 1, {}
  while offset <= #body do
    local start_at, end_at, index, record = body:find("n:(%d+)=(%b{})", offset)
    if start_at ~= offset or tonumber(index) ~= ordinal then
      fail(label .. " source effect signature is not a lossless indexed vector")
    end
    local change, recipe = record:match("^%{s:change=n:([^,{}]+),s:recipe=s:([^,{}]+),s:type=s:change%-recipe%-productivity%}$")
    if change == nil or recipe == nil or source_effect_changes[change] ~= true then
      fail(label .. " source effect record is not a published MIR1 productivity change")
    end
    rows[#rows + 1], ordinal = record, ordinal + 1
    offset = end_at + 1
    if offset <= #body then
      if body:sub(offset, offset) ~= "," then fail(label .. " source effect signature separator differs") end
      offset = offset + 1
    end
  end
  if #rows == 0 then fail(label .. " source effect signature is empty") end
  return canonical_effect_rows(rows)
end
local function canonical_current_effects(effects_value, label)
  if type(effects_value) ~= "table" then fail(label .. " current effect vector is malformed") end
  local rows = {}
  for index, effect in ipairs(effects_value) do
    if type(effect) ~= "table" then fail(label .. " current effect record is malformed") end
    if effect.hidden ~= nil and effect.hidden ~= false then
      fail(label .. " current effect hidden flag differs")
    end
    local projected = {}
    for key, value in pairs(effect) do
      if key ~= "hidden" or value ~= false then projected[key] = value end
    end
    local record = signature(projected)
    local change, recipe = record:match("^%{s:change=n:([^,{}]+),s:recipe=s:([^,{}]+),s:type=s:change%-recipe%-productivity%}$")
    local source_change = change and current_to_source_change[change] or nil
    if source_change == nil or recipe == nil then
      fail(label .. " current effect record differs at index " .. tostring(index))
    end
    rows[#rows + 1] = "{s:change=n:" .. source_change .. ",s:recipe=s:" .. recipe
      .. ",s:type=s:change-recipe-productivity}"
  end
  if #rows == 0 then fail(label .. " current effect vector is empty") end
  return canonical_effect_rows(rows)
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = queue, progress = force.research_progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if type(expected) ~= "table" or actual.current ~= expected.current or #actual.queue ~= #expected.queue
      or not close(actual.progress, expected.progress) then fail(label .. " queue/progress differs") end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs") end
  end
  return actual
end
local function effects(value)
  local result = {}
  for _, effect in pairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" then
      result[effect.recipe] = (result[effect.recipe] or 0) + effect.change
    end
  end
  return result
end
local function state()
  local value = storage and storage[KEY]
  if type(value) ~= "table" or value.phase ~= "completed" or type(value.roster) ~= "table"
      or type(value.player_snapshot) ~= "table" or type(value.foreign_snapshot) ~= "table"
      or type(value.detached_snapshot) ~= "table" then
    fail("protected historical source state is absent or incomplete")
  end
  return value
end
local function assert_force(force, expected, rows, label, ignored_technology, ignored_recipe)
  if force == nil or force.valid == false then fail(label .. " force is absent") end
  if type(expected.technologies) ~= "table" or type(expected.effects) ~= "table" or type(expected.recipes) ~= "table" then
    fail(label .. " source snapshot is malformed")
  end
  local observed_effects = {}
  for _, name in ipairs(rows) do
    local before = expected.technologies[name]
    if type(before) ~= "table" then fail(label .. " original row is missing: " .. name) end
    local now = technology(force, name)
    if name ~= ignored_technology and (now.level ~= before.level or now.researched ~= before.researched
        or now.enabled ~= before.enabled or now.visible_when_disabled ~= before.visible
        or now.prototype.max_level ~= before.maximum or not close(now.saved_progress, before.saved)) then
      fail(label .. " source row changed before candidate work: " .. name)
    end
    observed_effects[name] = signature(now.prototype.effects or {})
    if canonical_current_effects(now.prototype.effects or {}, label .. " current " .. name)
        ~= canonical_saved_effects(expected.effects[name], label .. " source " .. name) then
      fail(label .. " source effect vector changed: " .. name .. " expected=" .. tostring(expected.effects[name])
        .. " actual=" .. observed_effects[name])
    end
  end
  for recipe, before in pairs(expected.recipes) do
    local now = force.recipes[recipe]
    if recipe ~= ignored_recipe and (now == nil or now.valid == false or not close(now.productivity_bonus, before)) then
      fail(label .. " earned recipe contribution changed: " .. recipe)
    end
  end
  if type(force.manual_mining_speed_modifier) ~= "number"
      or not close(force.manual_mining_speed_modifier, expected.fields.manual_mining_speed_modifier) then
    fail(label .. " unrelated scripted offset changed")
  end
  return observed_effects
end
local function exact_target()
  for name, expected in pairs(catalogue.targets) do
    if script.active_mods.base == expected.base and script.active_mods["more-infinite-research"] == expected.mir
        and script.active_mods[FIXTURE] == expected.fixture
        and script.active_mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
      return name, expected
    end
  end
  fail("runtime target closure differs")
end
local function assert_supporting_state(state_value)
  if settings.startup[catalogue.breeding_setting] == nil
      or settings.startup[catalogue.breeding_setting].value ~= false then
    fail("effective false historical breeding setting was not retained")
  end
  local player_effects = assert_force(game.forces.player, state_value.player_snapshot, state_value.roster,
    "player", catalogue.direct, catalogue.gear_recipe)
  local foreign = game.forces[state_value.foreign_index]
  local foreign_effects = assert_force(foreign, state_value.foreign_snapshot, state_value.roster, "foreign")
  assert_queue(foreign, state_value.foreign_queue, "foreign")
  local detached = game.forces[state_value.detached_index]
  local detached_effects = assert_force(detached, state_value.detached_snapshot, state_value.roster, "detached")
  if not close(technology(detached, catalogue.direct).saved_progress, .27) then
    fail("detached historical progress changed")
  end
  local idle = queue_snapshot(detached)
  if idle.current ~= false or #idle.queue ~= 0 then fail("detached historical queue changed") end
  return {player = player_effects, foreign = foreign_effects, detached = detached_effects}
end
local function same_technology(actual, expected, label)
  if type(expected) ~= "table" or actual.level ~= expected.level or actual.researched ~= expected.researched
      or actual.enabled ~= expected.enabled or actual.visible_when_disabled ~= expected.visible
      or actual.prototype.max_level ~= expected.maximum or not close(actual.saved_progress, expected.saved) then
    fail(label .. " direct historical state differs")
  end
end
local function assert_direct_before(state_value)
  local direct = technology(game.forces.player, catalogue.direct)
  same_technology(direct, state_value.player_snapshot.technologies[catalogue.direct], "original MIR1 source")
  if not close(game.forces.player.recipes[catalogue.gear_recipe].productivity_bonus,
      state_value.player_snapshot.recipes[catalogue.gear_recipe]) then
    fail("original MIR1 source earned gear contribution differs")
  end
end
local function new_lab()
  local entity = game.surfaces[1].create_entity{name = "lab", position = {8, 0}, force = game.forces.player}
  if entity == nil or entity.valid == false then fail("could not create candidate gear lab") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("candidate gear lab input is absent") end
  return entity, inventory
end
local function fill_lab(entity, inventory, value)
  inventory.clear()
  local packs = {}
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string" or type(ingredient.amount) ~= "number"
        or ingredient.amount <= 0 then fail("candidate runtime science is malformed") end
    if packs[ingredient.name] ~= nil then fail("candidate runtime science duplicates a pack") end
    local inserted = inventory.insert{name = ingredient.name, count = catalogue.lab_packs}
    if inserted ~= catalogue.lab_packs then fail("candidate lab rejected science: " .. ingredient.name) end
    packs[ingredient.name] = catalogue.lab_packs
  end
  if next(packs) == nil then fail("candidate runtime science is absent") end
  entity.energy = 1000000000
  return packs
end
local function freeze_lab(successor)
  local entity = successor.lab
  if entity == nil or entity.valid == false then fail("candidate gear lab became invalid before completion freeze") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("candidate gear lab input is absent before completion freeze") end
  inventory.clear()
  entity.energy = 0
  successor.lab = nil
  successor.packs = nil
end
local function marker(stage, target_name, state_value, successor)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case = "migration-origin-1.0.0-" .. target_name .. "-successor", stage = stage, status = "passed",
    source_origin = "1.0.0", source_rows = successor.source_rows,
    source_actual_labs = successor.source_actual_labs, candidate_actual_labs = successor.candidate_actual_labs,
    source_direct_level = state_value.player_snapshot.technologies[catalogue.direct].level,
    candidate_direct_level = technology(game.forces.player, catalogue.direct).level,
    source_gear_bonus = state_value.player_snapshot.recipes[catalogue.gear_recipe],
    candidate_gear_bonus = game.forces.player.recipes[catalogue.gear_recipe].productivity_bonus,
    foreign_queue_progress = state_value.foreign_queue.progress, detached_progress = .27,
    effective_breeding_setting = settings.startup[catalogue.breeding_setting].value,
    on_load_read_only = stage == "reload",
  }))
end
local function begin()
  local target_name = exact_target()
  local state_value = state()
  local observed = assert_supporting_state(state_value)
  assert_direct_before(state_value)
  state_value.successors = state_value.successors or {}
  if state_value.successors[target_name] ~= nil then fail("target successor already began") end
  local successor = {}
  state_value.successors[target_name] = successor
  local direct = technology(game.forces.player, catalogue.direct)
  local before_bonus = game.forces.player.recipes[catalogue.gear_recipe].productivity_bonus
  local delta = effects(direct)[catalogue.gear_recipe]
  if not close(delta, catalogue.expected_gear_delta) then fail("candidate runtime gear contribution differs") end
  local entity, inventory = new_lab()
  successor.target = target_name
  successor.phase = "await-candidate-lab"
  successor.deadline = game.tick + catalogue.deadline_ticks
  successor.candidate_actual_labs = 0
  successor.before_bonus = before_bonus
  successor.candidate_delta = delta
  successor.before_effects = observed
  successor.source_effects = state_value.player_snapshot.effects
  successor.source_rows = #state_value.roster
  successor.source_actual_labs = state_value.source_labs
  successor.lab, successor.packs = entity, fill_lab(entity, inventory, direct)
  local current = game.forces.player.current_research
  if current == nil then
    if game.forces.player.add_research(direct) ~= true or game.forces.player.current_research ~= direct then
      fail("could not queue one actual candidate gear lab")
    end
  elseif current ~= direct then
    fail("source player has unrelated current research")
  end
end
local function complete(target_name, state_value, successor)
  assert_supporting_state(state_value)
  local direct = technology(game.forces.player, catalogue.direct)
  local before_level = state_value.player_snapshot.technologies[catalogue.direct].level
  if successor.candidate_actual_labs ~= 1 or direct.level ~= before_level + 1
      or direct.researched ~= false or not close(game.forces.player.recipes[catalogue.gear_recipe].productivity_bonus,
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
  if type(value) ~= "table" or type(value.successors) ~= "table" then return end
  for _, successor in pairs(value.successors) do
    if successor.phase == "await-candidate-lab" and event.research ~= nil and event.research.force == game.forces.player
        and event.research.name == catalogue.direct then
      successor.candidate_actual_labs = successor.candidate_actual_labs + 1
      if successor.candidate_actual_labs ~= 1 then fail("candidate gear lab completed more than once") end
      freeze_lab(successor)
      successor.phase = "await-observation"
    end
  end
end)
script.on_event(defines.events.on_tick, function()
  local target_name = exact_target()
  local state_value = state()
  local successor = state_value.successors and state_value.successors[target_name]
  if type(successor) ~= "table" then fail("target successor state is absent") end
  if successor.phase == "completed" then
    if loaded and not reload_reported then
      complete(target_name, state_value, successor)
      marker("reload", target_name, state_value, successor)
      reload_reported = true
    end
    return
  end
  if successor.phase ~= "await-candidate-lab" and successor.phase ~= "await-observation" then
    fail("target successor phase is invalid")
  end
  if game.tick > successor.deadline then fail("candidate gear lab did not complete") end
  if successor.phase == "await-candidate-lab" then
    if successor.lab == nil or successor.lab.valid == false then fail("candidate gear lab became invalid") end
    successor.lab.energy = 1000000000
  end
  if successor.phase == "await-observation" then
    complete(target_name, state_value, successor)
    successor.phase = "completed"
    marker("initial", target_name, state_value, successor)
    game.server_save(catalogue.save)
  end
end)
