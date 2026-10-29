local catalogue = require("__mir-fixture-mir5-migration-origin-f200-110-source__/catalogue")
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
  if result ~= nil then return result end
  -- Current runtime recipe effects may expose the exact numeric value of a
  -- recorded native float32 token rather than the authored Lua decimal.  This
  -- is an exact finite alternate spelling, not a rounded comparison.
  for _, native in pairs(catalogue.source_change_tokens) do
    if value == tonumber(native) then return native end
  end
  fail("published source recipe-effect scalar is unsupported")
end
local function modifier_token(value)
  local result = catalogue.source_modifier_tokens[value]
  if result == nil then fail("published source modifier scalar is unsupported") end
  return result
end
local function source_effect_signature(name)
  local rows = {}
  for _, effect in ipairs(catalogue.rows[name] or {}) do
    if effect.type == "change-recipe-productivity" then
      rows[#rows + 1] = effect.type .. "|" .. effect.recipe .. "|" .. token(effect.change)
    elseif effect.type == "worker-robot-battery" then
      rows[#rows + 1] = effect.type .. "|" .. modifier_token(effect.modifier)
    else
      fail("published source effect type is unsupported")
    end
  end
  table.sort(rows)
  return table.concat(rows, ",")
end
local function source_recipe_bonuses(direct_earned)
  local expected = {}
  for name, effects in pairs(catalogue.rows) do
    for _, effect in ipairs(effects) do
      if effect.type == "change-recipe-productivity" then
        -- The published source fixture snapshots every native recipe touched
        -- by its selected rows.  Its foreign/detached direct gear row is
        -- unearned, so that key is a retained zero rather than absent state.
        if name == catalogue.direct and not direct_earned then
          expected[effect.recipe] = expected[effect.recipe] or 0
        else
          expected[effect.recipe] = (expected[effect.recipe] or 0) + effect.change
        end
      end
    end
  end
  return expected
end
local function recipe_effect_counts(effects, label)
  if type(effects) ~= "table" then fail(label .. " effects are absent") end
  local counts = {}
  for _, effect in ipairs(effects) do
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or type(effect.recipe) ~= "string" then
      fail(label .. " effect shape differs")
    end
    local key = effect.type .. "|" .. effect.recipe .. "|" .. token(effect.change)
    counts[key] = (counts[key] or 0) + 1
  end
  return counts
end
local function same_effect_counts(actual, expected)
  if map_count(actual) ~= map_count(expected) then return false end
  for key, count in pairs(expected) do if actual[key] ~= count then return false end end
  return true
end
local function assert_module_credit(force, snapshot, label, target)
  local contract = catalogue.module_credit
  if type(contract) ~= "table" or type(contract.public) ~= "table" or type(contract.holders) ~= "table"
      or #contract.public ~= 9 or #contract.holders ~= 3 then
    fail("candidate module-credit contract is malformed")
  end
  local saved = snapshot.technologies["recipe-prod-research_modules-1"]
  if type(saved) ~= "table" or type(saved.level) ~= "number" or saved.level < 1
      or type(saved.researched) ~= "boolean" then
    fail(label .. " saved module level is malformed")
  end
  local completed = saved.level - 1 + (saved.researched and 1 or 0)
  if completed < 1 then fail(label .. " saved module credit is absent") end
  local public = technology(force, "recipe-prod-research_modules-1")
  if public.prototype == nil or public.enabled ~= target.modules_enabled
      or public.prototype.enabled ~= target.modules_enabled
      or not same_effect_counts(recipe_effect_counts(public.prototype.effects, label .. " current public module"),
        recipe_effect_counts(contract.public, "candidate public module")) then
    fail(label .. " current public module effects differ")
  end
  for _, descriptor in ipairs(contract.holders) do
    local holder = force.technologies[descriptor.id]
    local prototype = holder and holder.prototype
    if holder == nil or holder.valid == false or holder.name ~= descriptor.id
        or holder.level ~= 1 + completed or holder.researched ~= false
        or holder.enabled ~= false or holder.visible_when_disabled ~= false
        or prototype == nil or prototype.name ~= descriptor.id or prototype.level ~= 1
        or prototype.max_level ~= UINT32_MAX or prototype.hidden ~= true
        or prototype.enabled ~= false or prototype.visible_when_disabled ~= false
        or holder.research_unit_count ~= 1 or holder.research_unit_energy ~= 60
        or type(holder.research_unit_ingredients) ~= "table" or #holder.research_unit_ingredients ~= 1
        or holder.research_unit_ingredients[1].name ~= "automation-science-pack"
        or holder.research_unit_ingredients[1].amount ~= 1
        or not same_effect_counts(recipe_effect_counts(prototype.effects, label .. " module credit holder"), {
          ["change-recipe-productivity|" .. descriptor.recipe .. "|" .. token(descriptor.change)] = 1,
        }) then
      fail(label .. " retained module credit differs: " .. tostring(descriptor.id))
    end
  end
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
local function assert_settings(target)
  if map_count(catalogue.settings) ~= 42 then fail("published source settings roster differs") end
  for name, expected in pairs(catalogue.settings) do
    local value = settings.startup[name]
    local candidate_expected = expected
    if name == "ips-enable-research_modules" then candidate_expected = target.modules_enabled end
    local actual = value and value.value
    if actual ~= candidate_expected then
      fail("candidate startup setting differs: " .. name
        .. " expected=" .. tostring(candidate_expected) .. " actual=" .. tostring(actual))
    end
  end
end
local function source_row_text(row)
  if type(row) ~= "table" then return "row=" .. tostring(row) end
  return "level=" .. tostring(row.level)
    .. " researched=" .. tostring(row.researched)
    .. " enabled=" .. tostring(row.enabled)
    .. " visible=" .. tostring(row.visible)
    .. " maximum=" .. tostring(row.maximum)
    .. " saved=" .. tostring(row.saved)
end
local function runtime_row_text(value)
  local kind = type(value)
  if kind ~= "table" and kind ~= "userdata" then return "technology=" .. tostring(value) end
  local prototype = value.prototype
  return "level=" .. tostring(value.level)
    .. " researched=" .. tostring(value.researched)
    .. " enabled=" .. tostring(value.enabled)
    .. " visible=" .. tostring(value.visible_when_disabled)
    .. " maximum=" .. tostring(prototype and prototype.max_level)
    .. " saved=" .. tostring(value.saved_progress)
end
local function saved_fraction(value)
  return type(value) == "number" and value == value and value >= 0 and value < 1
end
local function assert_snapshot(snapshot, names, label, direct_level, direct_saved)
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
    local expected_progress
    if name == catalogue.direct then
      expected_progress = direct_saved
    else
      expected_progress = 0
    end
    local progress_matches
    if name == catalogue.direct and expected_progress == nil then
      progress_matches = saved_fraction(row.saved)
    else
      progress_matches = close(row.saved, expected_progress)
    end
    if type(row) ~= "table" or row.level ~= expected_level or row.researched ~= false or row.enabled ~= true
        or row.visible ~= false or row.maximum ~= UINT32_MAX
        or not progress_matches then
      fail(label .. " saved source technology differs: " .. name .. " " .. source_row_text(row))
    end
    if snapshot.effects[name] ~= source_effect_signature(name) then
      fail(label .. " saved source effect multiset differs: " .. name)
    end
  end
  local recipes = source_recipe_bonuses(direct_level >= 2)
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
local function observe_module_bonuses(force, snapshot, label)
  if label ~= "player" then return end
  local observed = {}
  for _, recipe in ipairs({"speed-module", "productivity-module", "efficiency-module"}) do
    local source, candidate = snapshot.recipes[recipe], force.recipes[recipe]
    if type(source) ~= "number" or candidate == nil or candidate.valid == false
        or type(candidate.productivity_bonus) ~= "number" then
      fail("player module-bonus observation is absent: " .. recipe)
    end
    observed[recipe] = {source = source, candidate = candidate.productivity_bonus}
  end
  log("[MIR5_NATIVE_FIXTURE] OBSERVED {"
    .. "\"case\":\"migration-origin-1.1.0-module-bonus-pre-scalar\","
    .. "\"original_source_speed_module_bonus\":" .. tostring(observed["speed-module"].source) .. ","
    .. "\"original_source_productivity_module_bonus\":" .. tostring(observed["productivity-module"].source) .. ","
    .. "\"original_source_efficiency_module_bonus\":" .. tostring(observed["efficiency-module"].source) .. ","
    .. "\"current_candidate_speed_module_bonus\":" .. tostring(observed["speed-module"].candidate) .. ","
    .. "\"current_candidate_productivity_module_bonus\":" .. tostring(observed["productivity-module"].candidate) .. ","
    .. "\"current_candidate_efficiency_module_bonus\":" .. tostring(observed["efficiency-module"].candidate) .. "}")
end
local function assert_force(force, snapshot, names, label, ignore_direct, candidate_delta, target)
  if force == nil or force.valid == false then fail(label .. " force is absent") end
  for _, name in ipairs(names) do
    local expected, actual = snapshot.technologies[name], technology(force, name)
    if name ~= catalogue.direct or not ignore_direct then
      local expected_enabled = expected.enabled
      if name == "recipe-prod-research_modules-1" then
        expected_enabled = target.modules_enabled
      end
      if actual.level ~= expected.level or actual.researched ~= expected.researched or actual.enabled ~= expected_enabled
          or actual.visible_when_disabled ~= expected.visible or actual.prototype.max_level ~= expected.maximum
          or not close(actual.saved_progress, expected.saved) then
        fail(label .. " retained source technology differs: " .. name
          .. " source{" .. source_row_text(expected) .. "} actual{" .. runtime_row_text(actual) .. "}")
      end
    end
  end
  observe_module_bonuses(force, snapshot, label)
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
  -- An active native research queue has its own `research_progress`.  The
  -- saved technology field is a separate persisted fraction, so preserve its
  -- actual source value (validated as [0,1)) rather than proxying queue .42.
  assert_snapshot(value.foreign_snapshot, names, "foreign", 1, nil)
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
      return name, expected
    end
  end
  fail("successor runtime target closure differs")
end
local function assert_source_before(state_value, names, ignore_direct, delta, target)
  assert_settings(target)
  assert_force(game.forces.player, state_value.player_snapshot, names, "player", ignore_direct, delta or 0, target)
  assert_module_credit(game.forces.player, state_value.player_snapshot, "player", target)
  local foreign = game.forces[state_value.foreign_index]
  assert_force(foreign, state_value.foreign_snapshot, names, "foreign", false, 0, target)
  assert_module_credit(foreign, state_value.foreign_snapshot, "foreign", target)
  assert_queue(foreign, state_value.foreign_queue, "foreign")
  local detached = game.forces[state_value.detached_index]
  assert_force(detached, state_value.detached_snapshot, names, "detached", false, 0, target)
  assert_module_credit(detached, state_value.detached_snapshot, "detached", target)
  local idle = queue_snapshot(detached)
  if idle.current ~= false or #idle.queue ~= 0 then fail("detached source queue changed") end
end
local function direct_delta(value)
  local matches = 0
  local expected = token(catalogue.expected_gear_delta)
  for _, effect in ipairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == catalogue.gear_recipe
        and token(effect.change) == expected then matches = matches + 1 end
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
  local target, target_config = exact_target()
  local state_value, names = state()
  -- Every retained source field is validated before this fixture creates a
  -- candidate lab or writes its successor record.
  assert_source_before(state_value, names, false, 0, target_config)
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
local function complete(target, target_config, state_value, successor)
  local names = source_names()
  assert_source_before(state_value, names, true, successor.candidate_delta, target_config)
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
local function reset_after_candidate_lab(target, target_config, state_value, successor)
  local player = game.forces.player
  if type(player.reset_technology_effects) ~= "function" then
    fail("candidate force cannot reset technology effects")
  end
  player.reset_technology_effects()
  -- This reset belongs to the initial completion transaction.  Re-running the
  -- read-only completion checks prevents it from discarding source rights,
  -- candidate progress, or the foreign queue before the completed save.
  complete(target, target_config, state_value, successor)
end

script.on_configuration_changed(function()
  local target, target_config = exact_target()
  local state_value = state()
  if state_value.successors ~= nil and type(state_value.successors) ~= "table" then
    fail("saved successor map is malformed")
  end
  local successor = state_value.successors and state_value.successors[target]
  if successor == nil then return begin() end
  -- Adding an observation fixture to a protected completed successor is a
  -- configuration event, not another first upgrade. Recheck the entire
  -- original preservation contract without a new lab, reset, save or write.
  if type(successor) ~= "table" or successor.phase ~= "completed" then
    fail("configuration changed an incomplete or unknown successor")
  end
  if successor.candidate_delta ~= direct_delta(technology(game.forces.player, catalogue.direct)) then
    fail("completed successor direct effect differs")
  end
  complete(target, target_config, state_value, successor)
  log("[MIR5_MIGRATION_110_COMPLETED_CONFIGURATION] verified " .. target)
end)
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
  local target, target_config = exact_target()
  local state_value = state()
  local successor = state_value.successors and state_value.successors[target]
  if type(successor) ~= "table" then fail("target successor state is absent") end
  if successor.phase == "completed" then
    if loaded and not reload_reported then
      complete(target, target_config, state_value, successor)
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
    complete(target, target_config, state_value, successor)
    reset_after_candidate_lab(target, target_config, state_value, successor)
    successor.phase = "completed"
    marker("initial", target, state_value, successor)
    game.server_save(catalogue.save)
  end
end)
