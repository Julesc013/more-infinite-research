local C = require("__mir-fixture-mir5-migration-origin-f200-120-source__/catalogue")
local KEY, FIXTURE, UINT32_MAX = C.storage_key, C.fixture, 4294967295
local loaded, reload_reported = false, false

local function fail(message) error("[mir5-migration-origin-f200-120-successor] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end
local function count(value)
  local result = 0
  for _ in pairs(value or {}) do result = result + 1 end
  return result
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end

-- Runtime technology effects use exact IEEE float32 values on native Factorio
-- while the independently pinned Base source uses authored decimals.  These
-- aliases are finite spellings, not a tolerance or a rounding rule.
local SCALARS = {
  {.1, 0.10000000149011612}, {.2, 0.20000000298023224}, {.3, 0.30000001192092896},
  {.4, 0.40000000596046448}, {.5, .5}, {.7, 0.69999998807907104},
  {.8, 0.800000011920929}, {.9, 0.8999999761581421},
  {1.3, 1.2999999523162842}, {1.5, 1.5},
}
local function scalar(value)
  for _, aliases in ipairs(SCALARS) do
    if value == aliases[1] or value == aliases[2] then return aliases[1] end
  end
  fail("unsupported exact gun-speed scalar: " .. tostring(value))
end
local function gun_signature(effects)
  local rows = {}
  for _, effect in ipairs(effects or {}) do
    if type(effect) ~= "table" or effect.type ~= "gun-speed" or type(effect.ammo_category) ~= "string"
        or type(effect.modifier) ~= "number" then
      return "invalid"
    end
    rows[#rows + 1] = effect.type .. "|" .. effect.ammo_category .. "|" .. string.format("%.17g", scalar(effect.modifier))
  end
  table.sort(rows)
  return table.concat(rows, ",")
end
local function expected_gun_signature(effects) return gun_signature(effects) end
local function assert_gun_vector(value, expected, label)
  local actual, wanted = gun_signature(value.prototype.effects), expected_gun_signature(expected.effects)
  if actual ~= wanted then fail(label .. " gun vector differs actual=" .. actual .. " expected=" .. wanted) end
  if value.level ~= expected.level or value.prototype.level ~= expected.level or value.prototype.max_level ~= expected.maximum then
    fail(label .. " runtime level/max differs")
  end
end
local function queue_snapshot(force)
  local queue = {}
  for index, row in ipairs(force.research_queue or {}) do queue[index] = row.name end
  return {current = force.current_research and force.current_research.name or false, queue = queue, progress = force.research_progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue identity differs") end
  end
end
local function row_text(row)
  if type(row) ~= "table" then return tostring(row) end
  return "level=" .. tostring(row.level) .. " researched=" .. tostring(row.researched)
    .. " enabled=" .. tostring(row.enabled) .. " visible=" .. tostring(row.visible)
    .. " maximum=" .. tostring(row.maximum) .. " saved=" .. tostring(row.saved)
end
local function runtime_row_text(value)
  if value == nil then return "nil" end
  return "level=" .. tostring(value.level) .. " researched=" .. tostring(value.researched)
    .. " enabled=" .. tostring(value.enabled) .. " visible=" .. tostring(value.visible_when_disabled)
    .. " maximum=" .. tostring(value.prototype and value.prototype.max_level) .. " saved=" .. tostring(value.saved_progress)
end
local function target()
  for name, expected in pairs(C.targets) do
    if script.active_mods.base == expected.base and script.active_mods["more-infinite-research"] == expected.mir
        and script.active_mods[FIXTURE] == expected.fixture
        and script.active_mods["mir-fixture-mir5-active-mods-observer"] == "0.1.0" then
      return name, expected
    end
  end
  fail("successor runtime target closure differs")
end
local function source_seeded(label, name)
  for _, expected in ipairs(C.source_finite_seed_sets[label]) do if expected == name then return true end end
  return false
end
local function source_state()
  local value = storage and storage[KEY]
  if type(value) ~= "table" or value.phase ~= "completed" or value.source_labs ~= C.source_labs
      or type(value.roster) ~= "table" or type(value.weapons) ~= "table"
      or type(value.player_snapshot) ~= "table" or type(value.foreign_snapshot) ~= "table"
      or type(value.detached_snapshot) ~= "table" or type(value.foreign_queue) ~= "table" then
    fail("protected MIR 1.2 source state is absent or incomplete")
  end
  if #value.roster ~= C.source_rows or #value.weapons ~= C.source_weapons then fail("protected source roster count differs") end
  return value
end
local function assert_snapshot(snapshot, label, direct_level, direct_saved)
  if type(snapshot) ~= "table" or type(snapshot.technologies) ~= "table" or type(snapshot.weapons) ~= "table"
      or type(snapshot.recipes) ~= "table" or type(snapshot.fields) ~= "table" or type(snapshot.gun_speed) ~= "table" then
    fail(label .. " source snapshot is malformed")
  end
  if count(snapshot.technologies) ~= C.source_rows or count(snapshot.weapons) ~= C.source_weapons then
    fail(label .. " source snapshot roster count differs")
  end
  local combined = snapshot.technologies[C.source_combined]
  if type(combined) ~= "table" or combined.level ~= direct_level or combined.researched ~= false
      or combined.enabled ~= true or combined.visible ~= false or combined.maximum ~= UINT32_MAX
      or not close(combined.saved, direct_saved) or combined.effects ~= C.source_combined_signature then
    fail(label .. " saved combined rocket/cannon state differs: " .. row_text(combined))
  end
  for name, expected in pairs(C.source_runtime) do
    local row = snapshot.weapons[name]
    if type(row) ~= "table" or row.level ~= expected.level or row.maximum ~= expected.maximum
        or row.researched ~= source_seeded(label, name) or row.enabled ~= true or row.visible ~= false
        or not close(row.saved, 0) or row.effects ~= expected_gun_signature(expected.effects) then
      fail(label .. " saved finite owner differs: " .. name .. " " .. row_text(row))
    end
  end
  local totals = C.source_gun_totals[label]
  for category, expected in pairs(totals) do
    if not close(snapshot.gun_speed[category], expected) then
      fail(label .. " saved source gun total differs: " .. category)
    end
  end
  if not close(snapshot.recipes[C.gear_recipe], .1) then fail(label .. " saved gear contribution differs") end
  if not close(snapshot.fields.worker_robots_battery_modifier, .1) then fail(label .. " saved worker-battery contribution differs") end
end
local function assert_source(value)
  assert_snapshot(value.player_snapshot, "player", 2, 0)
  -- Active queue progress belongs to LuaForce.  The foreign saved-progress
  -- field is preserved as a separate source value and must not proxy .42.
  local foreign_saved = value.foreign_snapshot.technologies[C.source_combined]
  if type(foreign_saved) ~= "table" or type(foreign_saved.saved) ~= "number" or foreign_saved.saved < 0 or foreign_saved.saved >= 1 then
    fail("foreign saved source combined progress differs")
  end
  assert_snapshot(value.foreign_snapshot, "foreign", 1, foreign_saved.saved)
  assert_snapshot(value.detached_snapshot, "detached", 1, .27)
  if value.foreign_queue.current ~= C.direct or #value.foreign_queue.queue ~= 2
      or value.foreign_queue.queue[1] ~= C.direct or value.foreign_queue.queue[2] ~= "recipe-prod-research_plastic-1"
      or not close(value.foreign_queue.progress, .42) then
    fail("protected foreign source queue differs")
  end
end
local function finite_total(snapshot, vectors)
  local totals = {bullet = 0, ["shotgun-shell"] = 0, rocket = 0, ["cannon-shell"] = 0, electric = 0, flamethrower = 0}
  for name, expected in pairs(vectors) do
    local row = snapshot.weapons[name]
    if row and row.researched then
      for _, effect in ipairs(expected.effects) do totals[effect.ammo_category] = (totals[effect.ammo_category] or 0) + effect.modifier end
    end
  end
  return totals
end
local function expected_guns(snapshot)
  local old, current = finite_total(snapshot, C.source_runtime), finite_total(snapshot, C.current_runtime)
  local out = {}
  for category, saved in pairs(snapshot.gun_speed) do out[category] = saved - (old[category] or 0) + (current[category] or 0) end
  return out
end
local function assert_current_weapons(force, snapshot, label)
  for name, expected in pairs(C.current_runtime) do
    local value, source = technology(force, name), snapshot.weapons[name]
    assert_gun_vector(value, expected, label .. " current finite owner " .. name)
    if value.researched ~= source.researched or value.enabled ~= source.enabled
        or value.visible_when_disabled ~= source.visible or not close(value.saved_progress, source.saved) then
      fail(label .. " current finite owner state differs: " .. name
        .. " source{" .. row_text(source) .. "} actual{" .. runtime_row_text(value) .. "}")
    end
  end
end
local function assert_split(force, snapshot, label)
  local rocket, cannon = technology(force, C.source_combined), technology(force, C.cannon)
  local saved = snapshot.technologies[C.source_combined]
  if rocket.level ~= saved.level or rocket.researched ~= saved.researched or rocket.enabled ~= saved.enabled
      or rocket.visible_when_disabled ~= saved.visible or rocket.prototype.max_level ~= saved.maximum
      or not close(rocket.saved_progress, saved.saved) then
    fail(label .. " retained rocket public state differs: " .. runtime_row_text(rocket))
  end
  if gun_signature(rocket.prototype.effects) ~= expected_gun_signature(C.split_effects.rocket) then
    fail(label .. " current rocket split effect differs")
  end
  if cannon.level ~= 1 or cannon.researched ~= false or cannon.enabled ~= true or cannon.visible_when_disabled ~= false
      or cannon.prototype.max_level ~= UINT32_MAX or not close(cannon.saved_progress, 0)
      or gun_signature(cannon.prototype.effects) ~= expected_gun_signature(C.split_effects.cannon) then
    fail(label .. " current cannon split state differs: " .. runtime_row_text(cannon))
  end
end
local function assert_force(force, snapshot, label, gear_extra)
  if force == nil or force.valid == false then fail(label .. " force is absent") end
  for name, source in pairs(snapshot.technologies) do
    local actual = technology(force, name)
    local level = source.level + ((name == C.direct and gear_extra ~= 0) and 1 or 0)
    if actual.level ~= level or actual.researched ~= source.researched or actual.enabled ~= source.enabled
        or actual.visible_when_disabled ~= source.visible or actual.prototype.max_level ~= source.maximum
        or not close(actual.saved_progress, source.saved) then
      fail(label .. " retained source technology differs: " .. name
        .. " source{" .. row_text(source) .. "} actual{" .. runtime_row_text(actual) .. "}")
    end
  end
  assert_split(force, snapshot, label)
  assert_current_weapons(force, snapshot, label)
  for recipe, expected in pairs(snapshot.recipes) do
    local actual, wanted = force.recipes[recipe], expected
    if recipe == C.gear_recipe then wanted = wanted + gear_extra end
    if actual == nil or actual.valid == false or not close(actual.productivity_bonus, wanted) then
      fail(label .. " retained source recipe contribution differs: " .. recipe)
    end
  end
  if not close(force.worker_robots_battery_modifier, snapshot.fields.worker_robots_battery_modifier) then
    fail(label .. " retained worker-battery contribution differs")
  end
  local expected = expected_guns(snapshot)
  for category, wanted in pairs(expected) do
    local actual = force.get_gun_speed_modifier(category)
    if not close(actual, wanted) then
      fail(label .. " preserved gun contribution differs: " .. category
        .. " expected=" .. tostring(wanted) .. " actual=" .. tostring(actual))
    end
  end
end
local function assert_other_source_forces(value)
  local foreign = game.forces[value.foreign_index]
  assert_force(foreign, value.foreign_snapshot, "foreign", 0)
  assert_queue(foreign, value.foreign_queue, "foreign")
  local detached = game.forces[value.detached_index]
  assert_force(detached, value.detached_snapshot, "detached", 0)
  local idle = queue_snapshot(detached)
  if idle.current ~= false or #idle.queue ~= 0 then fail("detached source queue changed") end
end
local function assert_source_before(value)
  assert_source(value)
  assert_force(game.forces.player, value.player_snapshot, "player", 0)
  assert_other_source_forces(value)
end
local function direct_delta(value)
  local matches = 0
  for _, effect in ipairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == C.gear_recipe and effect.change == C.expected_gear_delta then matches = matches + 1 end
  end
  if matches ~= 1 then fail("candidate gear effect differs") end
  return C.expected_gear_delta
end
local function new_lab()
  local lab = game.surfaces[1].create_entity{name = "lab", position = {8, 0}, force = game.forces.player}
  if lab == nil or lab.valid == false then fail("could not create candidate gear lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("candidate lab input is absent") end
  return lab, inventory
end
local function fill_lab(successor, direct)
  local inventory, packs = successor.lab.get_inventory(defines.inventory.lab_input), {}
  inventory.clear()
  for _, ingredient in ipairs(direct.research_unit_ingredients or {}) do
    if type(ingredient) ~= "table" or type(ingredient.name) ~= "string" or type(ingredient.amount) ~= "number"
        or ingredient.amount <= 0 or packs[ingredient.name] ~= nil then fail("candidate runtime science differs") end
    if inventory.insert{name = ingredient.name, count = C.lab_packs} ~= C.lab_packs then fail("candidate lab rejected science: " .. ingredient.name) end
    packs[ingredient.name] = C.lab_packs
  end
  if next(packs) == nil then fail("candidate runtime science is absent") end
  successor.packs = packs
  successor.lab.energy = 1000000000
end
local function freeze_lab(successor)
  local inventory = successor.lab and successor.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("candidate lab input is absent") end
  for name, before in pairs(successor.packs or {}) do if inventory.get_item_count(name) >= before then fail("candidate lab did not consume " .. name) end end
  successor.lab.energy = 0
  successor.lab, successor.packs = nil, nil
end
local function marker(stage, target_name, value, successor)
  local player = game.forces.player
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"migration-origin-1.2.0-" .. target_name .. "-successor\","
    .. "\"stage\":\"" .. stage .. "\",\"status\":\"passed\",\"source_origin\":\"1.2.0\","
    .. "\"source_rows\":34,\"source_actual_labs\":" .. tostring(value.source_labs) .. ","
    .. "\"candidate_actual_labs\":" .. tostring(successor.candidate_actual_labs) .. ","
    .. "\"source_rocket_gun\":" .. tostring(value.player_snapshot.gun_speed.rocket) .. ","
    .. "\"candidate_rocket_gun\":" .. tostring(player.get_gun_speed_modifier("rocket")) .. ","
    .. "\"source_cannon_gun\":" .. tostring(value.player_snapshot.gun_speed["cannon-shell"]) .. ","
    .. "\"candidate_cannon_gun\":" .. tostring(player.get_gun_speed_modifier("cannon-shell")) .. ","
    .. "\"foreign_queue_progress\":0.42,\"detached_progress\":0.27,\"on_load_read_only\":" .. tostring(stage == "reload") .. "}")
end
local function begin()
  local target_name = target()
  local value = source_state()
  assert_source_before(value)
  value.successors = value.successors or {}
  if value.successors[target_name] ~= nil then fail("target successor already began") end
  local direct = technology(game.forces.player, C.direct)
  local successor = {phase = "await-candidate-lab", deadline = game.tick + C.deadline_ticks,
    candidate_actual_labs = 0, before_bonus = game.forces.player.recipes[C.gear_recipe].productivity_bonus,
    candidate_delta = direct_delta(direct)}
  value.successors[target_name] = successor
  successor.lab = new_lab()
  fill_lab(successor, direct)
  if game.forces.player.add_research(direct) ~= true or game.forces.player.current_research ~= direct then
    fail("could not queue one actual candidate gear lab")
  end
end
local function complete(target_name, value, successor)
  assert_source(value)
  assert_other_source_forces(value)
  local direct = technology(game.forces.player, C.direct)
  local source = value.player_snapshot.technologies[C.direct]
  if successor.candidate_actual_labs ~= 1 or direct.level ~= source.level + 1 or direct.researched ~= false
      or not close(game.forces.player.recipes[C.gear_recipe].productivity_bonus, successor.before_bonus + successor.candidate_delta) then
    fail("actual candidate gear lab result differs")
  end
  assert_force(game.forces.player, value.player_snapshot, "player after candidate lab", successor.candidate_delta)
  if game.forces.player.current_research ~= nil or #game.forces.player.research_queue ~= 0 then fail("candidate player queue survived completion") end
end
local function reset_after_completion(target_name, value, successor)
  local player = game.forces.player
  if type(player.reset_technology_effects) ~= "function" then fail("candidate force cannot reset technology effects") end
  player.reset_technology_effects()
  complete(target_name, value, successor)
end

script.on_configuration_changed(begin)
script.on_load(function()
  local value = storage and storage[KEY]
  loaded, reload_reported = type(value) == "table" and type(value.successors) == "table", false
end)
script.on_event(defines.events.on_research_finished, function(event)
  local value = storage and storage[KEY]
  if type(value) ~= "table" or type(value.successors) ~= "table" or event.research == nil
      or event.research.force ~= game.forces.player or event.research.name ~= C.direct then return end
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
  local target_name = target()
  local value = source_state()
  local successor = value.successors and value.successors[target_name]
  if type(successor) ~= "table" then fail("target successor state is absent") end
  if successor.phase == "completed" then
    if loaded and not reload_reported then complete(target_name, value, successor); marker("reload", target_name, value, successor); reload_reported = true end
    return
  end
  if successor.phase ~= "await-candidate-lab" and successor.phase ~= "await-observation" then fail("candidate successor phase is invalid") end
  if game.tick > successor.deadline then fail("candidate gear lab did not complete") end
  if successor.phase == "await-candidate-lab" then
    if successor.lab == nil or successor.lab.valid == false then fail("candidate gear lab became invalid") end
    successor.lab.energy = 1000000000
    return
  end
  complete(target_name, value, successor)
  reset_after_completion(target_name, value, successor)
  successor.phase = "completed"
  marker("initial", target_name, value, successor)
  game.server_save(C.save)
end)
