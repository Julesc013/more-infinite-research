-- Base 2.0.77 / published MIR 4.7.20003 source scenario.
-- This actor owns only its scenario storage and source-world construction.

local KEY = "mir_published473_base_paid_source"
local PREFIX = "[MIR_PUBLISHED473_BASE_PAID_SOURCE] "
local SAVE_NAME = "mir473-base-paid-source"
local OUTPUT_DIRECTORY = "published-base-paid-source"
local BASE, MIR = "2.0.77", "4.7.20003"
local UINT32_MAX, HOLD_ELAPSED_TICKS, FEED_REQUEST, SPEED_ACCELERATION = 4294967295, 2, 200, 115199
local FOREIGN = "mir473-base-paid-foreign"
local LAB_POSITION = { 0, 0 }
local SCIENCE = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" }
local MAINS = {
  { name = "recipe-prod-research_low_density_structure-1", recipe = "low-density-structure" },
  { name = "recipe-prod-research_plastic-1", recipe = "plastic-bar" },
  { name = "recipe-prod-research_processing_unit-1", recipe = "processing-unit" },
  { name = "recipe-prod-research_rocket_fuel-1", recipe = "rocket-fuel" },
  { name = "recipe-prod-research_steel-1", recipe = "steel-plate" }
}
local PREREQUISITES = {
  { "electronics", {} }, { "steam-power", {} },
  { "automation-science-pack", { "steam-power", "electronics" } }, { "logistic-science-pack", { "automation-science-pack" } },
  { "automation", { "automation-science-pack" } }, { "steel-processing", { "automation-science-pack" } },
  { "automation-2", { "automation", "steel-processing", "logistic-science-pack" } }, { "engine", { "steel-processing", "logistic-science-pack" } },
  { "fluid-handling", { "automation-2", "engine" } }, { "oil-gathering", { "fluid-handling" } }, { "oil-processing", { "oil-gathering" } },
  { "plastics", { "oil-processing" } }, { "advanced-circuit", { "plastics" } }, { "sulfur-processing", { "oil-processing" } },
  { "chemical-science-pack", { "advanced-circuit", "sulfur-processing" } }, { "advanced-material-processing", { "steel-processing", "logistic-science-pack" } },
  { "advanced-material-processing-2", { "advanced-material-processing", "chemical-science-pack" } }, { "modules", { "advanced-circuit" } },
  { "productivity-module", { "modules" } }, { "logistics", { "automation-science-pack" } },
  { "logistics-2", { "logistics", "logistic-science-pack" } }, { "railway", { "logistics-2", "engine" } },
  { "production-science-pack", { "productivity-module", "advanced-material-processing-2", "railway" } }
}
local MAIN_PARENTS = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" }
local GEAR, BRAKING = "recipe-prod-research_gears-1", "braking-force-1"
local cold_pending = false

local function require_ok(value, message) if not value then error("[mir-published473-paid-source] " .. message, 0) end end
local function copy(value) if type(value) ~= "table" then return value end local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out end
local function near(left, right) return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001 end
local function integer(value) return type(value) == "number" and value == math.floor(value) end
local function same(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for k, v in pairs(left) do if not same(v, right[k]) then return false end end
  for k in pairs(right) do if left[k] == nil then return false end end
  return true
end
local function active_source()
  local count = 0; for _ in pairs(script.active_mods) do count = count + 1 end
  return count == 2 and script.active_mods.base == BASE and script.active_mods["more-infinite-research"] == MIR
end
local function exact_set(rows, expected, label)
  require_ok(rows ~= nil, label .. " rows are absent")
  local actual, count = {}, 0
  for _, row in pairs(rows) do
    local name = row and row.name or nil
    require_ok(type(name) == "string" and actual[name] == nil, label .. " contains malformed or duplicate row")
    actual[name] = true; count = count + 1
  end
  require_ok(count == #expected, label .. " count differs")
  for _, name in ipairs(expected) do require_ok(actual[name] == true, label .. " differs: " .. name) end
end
local function queue_frame(force)
  local queue = force.research_queue
  require_ok(queue ~= nil, "force research queue is absent")
  local names = {}
  for _, technology in ipairs(queue) do
    require_ok(technology and type(technology.name) == "string", "force research queue contains malformed technology")
    names[#names + 1] = technology.name
  end
  return { current = force.current_research and force.current_research.name or false, names = names, progress = force.research_progress }
end
local function scalar(force)
  if not force then return "force=absent" end
  local queue = force.research_queue
  local current = force.current_research
  local progress = force.research_progress
  local first = force.technologies and force.technologies[MAINS[1].name] or nil
  local bonus = force.recipes and force.recipes[MAINS[1].recipe] and force.recipes[MAINS[1].recipe].productivity_bonus or nil
  return "force=" .. tostring(force.name) .. " index=" .. tostring(force.index) .. " level=" .. tostring(first and first.level) ..
    " current=" .. tostring(current and current.name) .. " progress=" .. tostring(progress) .. " queue=" .. tostring(queue and #queue) .. " bonus=" .. tostring(bonus)
end
local function tech_state(technology)
  return { level = technology.level, researched = technology.researched, enabled = technology.enabled,
    visible = technology.visible_when_disabled, saved_progress = technology.saved_progress }
end
local function science_unit(technology)
  local rows, ingredients = technology.research_unit_ingredients, {}
  require_ok(rows ~= nil, "technology science ingredients are absent")
  for _, ingredient in pairs(rows) do
    require_ok(ingredient and type(ingredient.name) == "string" and type(ingredient.amount) == "number", "technology science ingredient is malformed")
    ingredients[ingredient.name] = ingredient.amount
  end
  return { count = technology.research_unit_count, energy_ticks = technology.research_unit_energy, ingredients = ingredients }
end
local function assert_main(technology, main, label)
  require_ok(technology and technology.valid ~= false and technology.name == main.name, label .. " main is unavailable")
  local prototype = technology.prototype
  require_ok(prototype and prototype.max_level == UINT32_MAX, label .. " main is not runtime-infinite")
  require_ok(technology.research_unit_count == 8000 and technology.research_unit_energy == 3600, label .. " main unit differs")
  exact_set(technology.research_unit_ingredients, SCIENCE, label .. " main science")
  for _, ingredient in pairs(technology.research_unit_ingredients) do require_ok(ingredient.amount == 1, label .. " main science amount differs") end
  exact_set(technology.prerequisites, MAIN_PARENTS, label .. " main direct parents")
  require_ok(prototype.effects ~= nil, label .. " main effects are absent")
  local count, observed = 0, false
  for _, effect in pairs(prototype.effects) do count = count + 1; observed = effect and effect.type == "change-recipe-productivity" and effect.recipe == main.recipe and near(effect.change, .1) end
  require_ok(count == 1 and observed, label .. " main effect differs")
end
local function assert_finite(technology, name, parents, label)
  require_ok(technology and technology.valid ~= false and technology.name == name, label .. " finite technology is absent: " .. name)
  local prototype = technology.prototype; require_ok(prototype, label .. " finite technology prototype is absent: " .. name)
  local level, prototype_level, maximum = technology.level, prototype.level, prototype.max_level
  local single_native_stage = integer(level) and level >= 1 and integer(prototype_level) and integer(maximum) and maximum == level and maximum < UINT32_MAX and
    ((prototype_level == level) or (prototype_level == 0 and level == 1 and maximum == 1))
  require_ok(single_native_stage,
    label .. " finite technology is not a single finite native ordinal: " .. name)
  require_ok(technology.researched == false and technology.saved_progress == 0, label .. " finite technology is not fresh: " .. name)
  exact_set(technology.prerequisites, parents, label .. " direct parents: " .. name)
  return { name = name, technology_level = level, prototype_level = prototype_level, prototype_max_level = maximum,
    researched = technology.researched, saved_progress = technology.saved_progress }
end
local function assert_preflight(force, label)
  require_ok(force and force.valid ~= false, label .. " force is invalid")
  local facts = scalar(force)
  for _, main in ipairs(MAINS) do
    local technology = force.technologies[main.name]; assert_main(technology, main, label)
    require_ok(technology.level == 1 and technology.researched == false and technology.saved_progress == 0, label .. " main is not a fresh level one: " .. main.name .. " [" .. facts .. "]")
  end
  local finite = {}
  for _, row in ipairs(PREREQUISITES) do finite[row[1]] = assert_finite(force.technologies[row[1]], row[1], row[2], label) end
  assert_finite(force.technologies[BRAKING], BRAKING, { "railway", "chemical-science-pack" }, label)
  assert_main(force.technologies[GEAR], { name = GEAR, recipe = "iron-gear-wheel" }, label .. " gear")
  return finite
end
local function grant_finite(force, label)
  for _, row in ipairs(PREREQUISITES) do
    local technology = force.technologies[row[1]]; technology.researched = true
    require_ok(technology.researched == true, label .. " administrative prerequisite grant differs: " .. row[1])
  end
end
local function completed_rows(force)
  local rows = {}; for _, row in ipairs(PREREQUISITES) do rows[row[1]] = tech_state(force.technologies[row[1]]) end; return rows
end
local function force_frame(force)
  local mains, recipes = {}, {}
  for _, main in ipairs(MAINS) do
    local technology = force.technologies[main.name]; mains[main.name] = { state = tech_state(technology), unit = science_unit(technology) }
    recipes[main.recipe] = force.recipes[main.recipe].productivity_bonus
  end
  return { name = force.name, index = force.index, finite = completed_rows(force), mains = mains,
    braking = tech_state(force.technologies[BRAKING]), gear = tech_state(force.technologies[GEAR]),
    queue = queue_frame(force), recipe_bonuses = recipes }
end
local function force_registry()
  local rows, seen = {}, {}
  for _, force in pairs(game.forces) do
    require_ok(force and force.valid ~= false and type(force.name) == "string" and type(force.index) == "number", "force registry contains invalid row")
    if seen[force.index] == nil then
      seen[force.index] = force; rows[#rows + 1] = { name = force.name, index = force.index }
    else
      require_ok(seen[force.index] == force, "force registry aliases distinct forces at index " .. force.index)
    end
  end
  table.sort(rows, function(left, right) return left.index < right.index end); return rows
end
local function lab_inventory(state)
  require_ok(state.lab and state.lab.valid ~= false, "owned source lab is invalid")
  local inventory = state.lab.get_inventory(defines.inventory.lab_input); require_ok(inventory, "owned source lab input inventory is absent"); return inventory
end
local function lab_frame(state)
  local inventory, input = lab_inventory(state), {}; for _, name in ipairs(SCIENCE) do input[name] = inventory.get_item_count(name) end
  local position, force, surface = state.lab.position, state.lab.force, state.lab.surface
  require_ok(position and type(position.x) == "number" and type(position.y) == "number", "owned source lab position is unavailable")
  require_ok(force and force.valid ~= false and type(force.name) == "string" and type(force.index) == "number", "owned source lab force is unavailable")
  require_ok(surface and type(surface.index) == "number", "owned source lab surface is unavailable")
  return { name = state.lab.name, unit_number = state.lab.unit_number, disabled_by_script = state.lab.disabled_by_script,
    input = input,
    position = { x = position.x, y = position.y }, force_name = force.name, force_index = force.index, surface_index = surface.index,
    laboratory_speed_modifier = state.player.laboratory_speed_modifier }
end
local function science_frame(state)
  local inventory, remaining, consumed = lab_inventory(state), {}, {}
  for _, name in ipairs(SCIENCE) do remaining[name] = inventory.get_item_count(name); consumed[name] = state.science.accepted[name] - remaining[name] end
  return { accepted = copy(state.science.accepted), consumed = consumed, remaining = remaining }
end
local function endpoint_frame(state)
  return { force_registry = force_registry(), observed_force_count = 2,
    observed_forces = { player = { name = state.player.name, index = state.player.index }, foreign = { name = state.foreign.name, index = state.foreign.index } },
    player = force_frame(state.player), foreign = force_frame(state.foreign), science = science_frame(state), lab = lab_frame(state),
    events = copy(state.events), ordinary_completed = copy(state.ordinary_completed), administrative = copy(state.administrative) }
end
local function assert_endpoint(state)
  local facts = "player{" .. scalar(state.player) .. "} foreign{" .. scalar(state.foreign) .. "}"
  require_ok(state.player.laboratory_speed_modifier == state.original_laboratory_speed_modifier, "temporary laboratory speed modifier was not restored")
  require_ok(state.lab.disabled_by_script == true, "source lab is not disabled at endpoint")
  for _, main in ipairs(MAINS) do
    local technology = state.player.technologies[main.name]
    require_ok(technology.level == 2 and technology.researched == false, "player ordinary endpoint differs: " .. main.name .. " [" .. facts .. "]")
    require_ok(near(state.player.recipes[main.recipe].productivity_bonus, .1), "player native recipe effect differs: " .. main.recipe .. " [" .. facts .. "]")
    require_ok(state.ordinary_completed[main.name] == 1, "ordinary completion count differs: " .. main.name)
  end
  local plastic = state.player.technologies[MAINS[2].name]; require_ok(near(plastic.saved_progress, .27), "detached plastic saved progress differs [" .. facts .. "]")
  local steel, player_queue = state.player.technologies[MAINS[5].name], queue_frame(state.player)
  require_ok(player_queue.current == steel.name and player_queue.progress == 0 and #player_queue.names == 2 and player_queue.names[1] == steel.name and player_queue.names[2] == steel.name, "player duplicate steel queue differs [" .. facts .. "]")
  local foreign_queue = queue_frame(state.foreign)
  require_ok(foreign_queue.current == BRAKING and near(foreign_queue.progress, .42) and #foreign_queue.names == 3 and foreign_queue.names[1] == BRAKING and foreign_queue.names[2] == GEAR and foreign_queue.names[3] == GEAR, "foreign current or repeated gear queue differs [" .. facts .. "]")
  for _, force in ipairs({ state.player, state.foreign }) do for _, row in ipairs(PREREQUISITES) do require_ok(force.technologies[row[1]].researched == true, "completed finite prerequisite differs: " .. force.name .. ":" .. row[1]) end end
  local science = science_frame(state)
  for _, name in ipairs(SCIENCE) do
    require_ok(science.consumed[name] == 40000, "ordinary science consumption differs: " .. name)
    require_ok(science.accepted[name] >= science.consumed[name] and science.accepted[name] <= science.consumed[name] + FEED_REQUEST, "ordinary science accepted range differs: " .. name)
  end
  if state.endpoint then require_ok(same(endpoint_frame(state), state.endpoint), "immutable source endpoint changed [" .. facts .. "]") end
end
local function marker(state, phase, write_name)
  local body = { kind = "MIRPublished473BasePaidSourceV1", schema = 1, role = "source", phase = phase, tick = game.tick,
    saved_tick = state.saved_tick, mods = copy(script.active_mods), endpoint = endpoint_frame(state) }
  local encoded = helpers.table_to_json(body); log(PREFIX .. encoded)
  if write_name then helpers.write_file(OUTPUT_DIRECTORY .. "/" .. write_name, encoded, false) end
end
local function preflight_marker(player, finite)
  local body = { kind = "MIRPublished473BasePaidSourcePreflightV1", schema = 1, role = "source", phase = "source-preflight", tick = game.tick,
    mods = copy(script.active_mods), force_registry = force_registry(), player = { name = player.name, index = player.index }, finite = finite }
  local encoded = helpers.table_to_json(body); log(PREFIX .. encoded); helpers.write_file(OUTPUT_DIRECTORY .. "/preflight.json", encoded, false)
end
local function set_queue(force, rows, progress, label)
  force.research_queue = rows
  local queue = queue_frame(force); require_ok(queue.current == rows[1].name and #queue.names == #rows, label .. " queue setter differs")
  for index, technology in ipairs(rows) do require_ok(queue.names[index] == technology.name, label .. " queue order differs") end
  if progress ~= nil then require_ok(force.current_research ~= nil, label .. " lacks current research before progress"); force.research_progress = progress; require_ok(near(force.research_progress, progress), label .. " progress differs") end
end
local function refill(state)
  require_ok(type(state.lab.energy) == "number" and type(state.lab.electric_buffer_size) == "number", "source lab energy fields are unavailable")
  state.lab.energy = state.lab.electric_buffer_size
  local inventory = lab_inventory(state)
  for _, name in ipairs(SCIENCE) do
    local present = inventory.get_item_count(name); require_ok(type(present) == "number" and present >= 0, "source lab inventory count differs: " .. name)
    local request = math.max(0, FEED_REQUEST - present)
    if request > 0 then
      local accepted = inventory.insert({ name = name, count = request })
      require_ok(type(accepted) == "number" and accepted == math.floor(accepted) and accepted >= 0 and accepted <= request, "source lab insert return differs: " .. name)
      state.science.accepted[name] = state.science.accepted[name] + accepted
      require_ok(state.science.accepted[name] <= 40000 + FEED_REQUEST, "source lab feed bound differs: " .. name)
    end
  end
end
local function begin_ordinary(state)
  local main = MAINS[state.main_index]; require_ok(main, "ordinary main selection is absent")
  local technology = state.player.technologies[main.name]
  require_ok(technology.level == 1 and technology.researched == false and technology.saved_progress == 0, "ordinary main start differs: " .. main.name)
  set_queue(state.player, { technology }, nil, "ordinary " .. main.name); state.lab.disabled_by_script = false; state.current_main = main.name; state.phase = "ordinary"
end
local function prepare_endpoint(state)
  state.lab.disabled_by_script = true; state.player.laboratory_speed_modifier = state.original_laboratory_speed_modifier
  require_ok(state.player.laboratory_speed_modifier == state.original_laboratory_speed_modifier, "temporary laboratory speed modifier restoration differs")
  local plastic = state.player.technologies[MAINS[2].name]; require_ok(plastic.level == 2 and plastic.researched == false, "plastic source level differs"); plastic.saved_progress = .27
  set_queue(state.player, { state.player.technologies[MAINS[5].name], state.player.technologies[MAINS[5].name] }, nil, "player retained steel")
  set_queue(state.foreign, { state.foreign.technologies[BRAKING], state.foreign.technologies[GEAR], state.foreign.technologies[GEAR] }, .42, "foreign retained braking")
  assert_endpoint(state); state.endpoint = endpoint_frame(state); state.hold_start_tick = game.tick; state.hold_observations = 0; state.phase = "holding"; marker(state, "source-pre-hold")
end

script.on_init(function()
  if not active_source() then return end
  require_ok(storage[KEY] == nil, "source scenario storage already exists")
  local player = game.forces.player; require_ok(player and player.valid ~= false, "player force is absent")
  require_ok(game.forces[FOREIGN] == nil, "named foreign force already exists")
  local player_finite = assert_preflight(player, "player")
  preflight_marker(player, player_finite)
  local foreign = game.create_force(FOREIGN); assert_preflight(foreign, "foreign")
  grant_finite(player, "player"); grant_finite(foreign, "foreign")
  local surface = game.surfaces[1]; require_ok(surface and type(surface.create_entity) == "function", "source surface is absent")
  local lab = surface.create_entity({ name = "lab", position = LAB_POSITION, force = player }); require_ok(lab and lab.valid ~= false, "could not create source Base lab"); lab.disabled_by_script = true
  require_ok(type(player.laboratory_speed_modifier) == "number", "laboratory speed modifier is unavailable")
  local state = { phase = "ordinary-start", player = player, foreign = foreign, lab = lab, main_index = 1, ordinary_completed = {}, events = {}, science = { accepted = {} },
    administrative = { label = "explicit-finite-prerequisite-grants", rows = #PREREQUISITES, forces = { player.name, foreign.name } }, original_laboratory_speed_modifier = player.laboratory_speed_modifier }
  for _, main in ipairs(MAINS) do state.ordinary_completed[main.name] = 0 end
  for _, name in ipairs(SCIENCE) do state.science.accepted[name] = 0 end
  player.laboratory_speed_modifier = state.original_laboratory_speed_modifier + SPEED_ACCELERATION
  require_ok(player.laboratory_speed_modifier == state.original_laboratory_speed_modifier + SPEED_ACCELERATION, "temporary laboratory speed modifier differs")
  storage[KEY] = state
end)
script.on_configuration_changed(function() if not active_source() then return end end)
script.on_load(function() cold_pending = true end)
script.on_event(defines.events.on_research_finished, function(event)
  if not active_source() then return end
  local state = storage[KEY]
  if not state or not event.research or event.research.force ~= state.player then return end
  require_ok(state.phase == "ordinary" and event.research.name == state.current_main and event.by_script == false, "ordinary research event differs")
  require_ok(event.research.level == 2 and event.research.researched == false, "ordinary research event was not post-increment level two")
  state.ordinary_completed[event.research.name] = state.ordinary_completed[event.research.name] + 1
  require_ok(state.ordinary_completed[event.research.name] == 1, "ordinary research completion count differs")
  state.events[#state.events + 1] = { name = event.research.name, level = event.research.level, by_script = event.by_script, tick = game.tick }
  state.lab.disabled_by_script = true; state.main_index = state.main_index + 1; state.phase = state.main_index <= #MAINS and "ordinary-start" or "finalizing"
end)
script.on_event(defines.events.on_tick, function()
  if not active_source() then return end
  local state = storage[KEY]; if not state then return end
  if cold_pending then
    require_ok(state.phase == "saved" and game.tick == state.saved_tick + 1, "cold source tick differs")
    assert_endpoint(state); marker(state, "source-cold", "cold.json"); cold_pending = false; return
  end
  if state.phase == "ordinary-start" then begin_ordinary(state); refill(state)
  elseif state.phase == "ordinary" then refill(state)
  elseif state.phase == "finalizing" then prepare_endpoint(state)
  elseif state.phase == "holding" then
    assert_endpoint(state); state.hold_observations = state.hold_observations + 1
    if game.tick - state.hold_start_tick >= HOLD_ELAPSED_TICKS then state.saved_tick = game.tick; state.phase = "saved"; marker(state, "source-saved", "source.json"); game.server_save(SAVE_NAME) end
  elseif state.phase == "saved" then assert_endpoint(state)
  else require_ok(false, "unknown source phase: " .. tostring(state.phase)) end
end)
