-- Successor-only observer for the immutable published Base/MIR source saved
-- endpoint.  It never repairs or owns MIR research state.
local FIXTURE = "mir-fixture-published-base-added-successor"
local KEY = "mir_published_base_added_successor"
local PREFIX = "[MIR_PUBLISHED_BASE_ADDED_SUCCESSOR] "
local SAVE = "mir473-base-added-successor"
local SOURCE = require("expected-source")
local SOURCE_SHA = "BCDED2247121D9F0268D1F4F0DF16EB5C89E6BECD4DE66E04EBDB23ECFE2FD98"
local SOURCE_SAVE_SHA = "4354251431E4A495DACF6DA44207A5ECAE2F1D5A29FFD2A990415ACC98CD2413"
local SOURCE_MIR = "4.7.20003"
local TARGET = {["5.0.20016"] = true, ["5.0.20018"] = true}
local HOLD = 2
local SPEED_ACCELERATION = 115199
local STEEL_LEVEL_THREE_COUNT = 32000
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}
local PLAYER, FOREIGN = "player", "mir473-base-paid-foreign"
local MAINS = {
  {family="research_low_density_structure", name="recipe-prod-research_low_density_structure-1", recipe="low-density-structure", alias="mir-fixture-added-low-density-structure"},
  {family="research_plastic", name="recipe-prod-research_plastic-1", recipe="plastic-bar", alias="mir-fixture-added-plastic-bar"},
  {family="research_processing_unit", name="recipe-prod-research_processing_unit-1", recipe="processing-unit", alias="mir-fixture-added-processing-unit"},
  {family="research_rocket_fuel", name="recipe-prod-research_rocket_fuel-1", recipe="rocket-fuel", alias="mir-fixture-added-rocket-fuel"},
  {family="research_steel", name="recipe-prod-research_steel-1", recipe="steel-plate", alias="mir-fixture-added-steel-plate"},
}
local STEEL = MAINS[5]
local carriers = {}
for _, row in ipairs(MAINS) do
  for _, recipe in ipairs({row.recipe, row.alias}) do
    carriers["mir-native-credit-" .. row.family .. "-" .. recipe .. "-positive"] = true
    carriers["mir-native-credit-" .. row.family .. "-" .. recipe .. "-negative"] = true
  end
end

local cold_pending = false

local function fail(message) error("[mir-published-base-added-successor] " .. message, 2) end
local function require_ok(value, message) if not value then fail(message) end return value end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.000001
end
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, item in pairs(value) do out[key] = copy(item) end; return out
end
local function equal(actual, expected, path)
  if type(actual) ~= type(expected) then fail(path .. " type differs") end
  if type(actual) == "table" then
    for key, item in pairs(expected) do equal(actual[key], item, path .. "." .. tostring(key)) end
    for key in pairs(actual) do if expected[key] == nil then fail(path .. " has unexpected field " .. tostring(key)) end end
  elseif type(actual) == "number" then
    local floating_native = path:find("saved_progress", 1, true) or path:find("progress", 1, true) or path:find("recipe_bonuses", 1, true)
    if expected == 0 then
      if actual ~= 0 then fail(path .. " differs") end
    elseif floating_native then
      if not close(actual, expected) then fail(path .. " differs") end
    elseif actual ~= expected then fail(path .. " differs") end
  elseif actual ~= expected then fail(path .. " differs") end
end
local function active() return TARGET[script.active_mods["more-infinite-research"]] == true end
local function technology(force, name)
  local row = force.technologies[name]
  require_ok(row and row.valid ~= false and row.name == name, "technology absent: " .. name)
  return row
end
local function recipe(force, name)
  local row = force.recipes[name]
  require_ok(row and row.valid ~= false and type(row.productivity_bonus) == "number", "recipe absent: " .. name)
  return row
end
local function queue(force)
  local out = {}
  for index, row in ipairs(force.research_queue) do
    require_ok(row and row.valid ~= false and type(row.name) == "string", "research queue row differs")
    out[index] = row.name
  end
  return {current = force.current_research and force.current_research.name or false, names = out, progress = force.research_progress}
end
local function force_registry()
  local seen, out = {}, {}
  for _, force in pairs(game.forces) do
    require_ok(force and force.valid ~= false and type(force.name) == "string" and type(force.index) == "number", "force registry row differs")
    local prior = seen[force.index]
    if prior then require_ok(prior.name == force.name, "force registry index aliases different names")
    else seen[force.index] = force; out[#out + 1] = {name = force.name, index = force.index} end
  end
  table.sort(out, function(left, right) return left.index < right.index end)
  return out
end
local function finite_frame(force, expected)
  local out = {}
  for name in pairs(expected) do
    local row = technology(force, name)
    out[name] = {level=row.level, researched=row.researched, enabled=row.enabled,
      visible=row.visible_when_disabled, saved_progress=row.saved_progress}
  end
  return out
end
local function ingredient_map(rows)
  local out = {}
  for _, row in ipairs(rows) do
    require_ok(type(row.name) == "string" and type(row.amount) == "number" and out[row.name] == nil, "science ingredient differs")
    out[row.name] = row.amount
  end
  return out
end
local function mains_frame(force, expected)
  local out = {}
  for name in pairs(expected) do
    local row = technology(force, name)
    out[name] = {state = {level=row.level, researched=row.researched, enabled=row.enabled,
      visible=row.visible_when_disabled, saved_progress=row.saved_progress},
      unit = {count=row.research_unit_count, energy_ticks=row.prototype.research_unit_energy,
        ingredients=ingredient_map(row.research_unit_ingredients)}}
  end
  return out
end
local function force_frame(force, expected)
  local bonuses = {}
  for recipe_name in pairs(expected.recipe_bonuses) do bonuses[recipe_name] = recipe(force, recipe_name).productivity_bonus end
  local braking, gear = technology(force, "braking-force-1"), technology(force, "recipe-prod-research_gears-1")
  return {name=force.name, index=force.index, finite=finite_frame(force, expected.finite), mains=mains_frame(force, expected.mains),
    braking={level=braking.level,researched=braking.researched,enabled=braking.enabled,visible=braking.visible_when_disabled,saved_progress=braking.saved_progress},
    gear={level=gear.level,researched=gear.researched,enabled=gear.enabled,visible=gear.visible_when_disabled,saved_progress=gear.saved_progress},
    queue=queue(force), recipe_bonuses=bonuses}
end
local function alias_bonus_frame(force)
  local out = {}
  for _, row in ipairs(MAINS) do out[row.alias] = recipe(force, row.alias).productivity_bonus end
  return out
end
local function aliases_frame(player, foreign)
  return {player=alias_bonus_frame(player),foreign=alias_bonus_frame(foreign)}
end
local function lab_frame(expected)
  local surface = game.surfaces[expected.surface_index]
  require_ok(surface and surface.valid ~= false and type(surface.find_entity) == "function", "source lab surface differs")
  local entity = surface.find_entity(expected.name, expected.position)
  require_ok(entity and entity.valid ~= false and entity.name == expected.name and entity.unit_number == expected.unit_number, "source lab identity differs")
  require_ok(entity.force and entity.force.name == expected.force_name and entity.force.index == expected.force_index, "source lab owner differs")
  local input = entity.get_inventory(defines.inventory.lab_input); require_ok(input, "source lab input differs")
  local counts = {}; for _, pack in ipairs(PACKS) do counts[pack] = input.get_item_count(pack) end
  return {name=entity.name,unit_number=entity.unit_number,disabled_by_script=entity.disabled_by_script == true,input=counts,
    position={x=entity.position.x,y=entity.position.y},force_name=entity.force.name,force_index=entity.force.index,
    surface_index=entity.surface.index,laboratory_speed_modifier=entity.force.laboratory_speed_modifier}, entity, input
end
local function source_endpoint()
  require_ok(helpers and type(helpers.json_to_table) == "function", "JSON parser is unavailable")
  local decoded = helpers.json_to_table(SOURCE)
  require_ok(type(decoded) == "table" and decoded.kind == "MIRPublished473BasePaidSourceV1" and decoded.schema == 1 and decoded.role == "source", "expected source JSON differs")
  return decoded.endpoint, decoded
end
local function source_projection(expected)
  local player, foreign = game.forces[PLAYER], game.forces[FOREIGN]
  require_ok(player and foreign and player.valid ~= false and foreign.valid ~= false, "observed source forces differ")
  local lab = lab_frame(expected.lab)
  return {force_registry=force_registry(),observed_force_count=2,observed_forces={player={name=player.name,index=player.index},foreign={name=foreign.name,index=foreign.index}},
    player=force_frame(player, expected.player), foreign=force_frame(foreign, expected.foreign), aliases=aliases_frame(player, foreign), lab=lab}
end
local function assert_aliases_zero(aliases)
  require_ok(type(aliases) == "table" and type(aliases.player) == "table" and type(aliases.foreign) == "table", "new alias observation differs")
  for _, role in ipairs({"player", "foreign"}) do
    for _, row in ipairs(MAINS) do require_ok(aliases[role][row.alias] == 0, "new alias inherited old paid bonus") end
  end
end
local function assert_initial()
  local expected, decoded = source_endpoint()
  require_ok(decoded.mods.base == "2.0.77" and decoded.mods["more-infinite-research"] == SOURCE_MIR and decoded.tick == 1252 and decoded.saved_tick == 1252, "frozen source identity differs")
  local actual = source_projection(expected)
  equal(actual.force_registry, expected.force_registry, "frozen public source registry")
  equal(actual.observed_force_count, expected.observed_force_count, "frozen public source observed force count")
  equal(actual.observed_forces, expected.observed_forces, "frozen public source observed forces")
  equal(actual.player, expected.player, "frozen public source player")
  equal(actual.foreign, expected.foreign, "frozen public source foreign")
  equal(actual.lab, expected.lab, "frozen public source lab")
  assert_aliases_zero(actual.aliases)
  return expected, actual
end
local function exact_mods()
  local expected = {base="2.0.77", ["more-infinite-research"]=script.active_mods["more-infinite-research"], [FIXTURE]=script.active_mods[FIXTURE]}
  require_ok(expected["more-infinite-research"] and TARGET[expected["more-infinite-research"]] and expected[FIXTURE] == "0.1.0", "exact active mod versions differ")
  local count = 0; for name, version in pairs(script.active_mods) do count = count + 1; require_ok(expected[name] == version, "unexpected active mod " .. tostring(name)) end
  require_ok(count == 3, "active mod count differs")
  return expected
end
local function startup_snapshot()
  local out = {}
  for name, setting in pairs(settings.startup) do
    require_ok(setting and setting.valid ~= false, "startup setting differs")
    out[name] = setting.value
  end
  return out
end
local function configuration(event)
  require_ok(event and event.mod_startup_settings_changed == false and type(event.mod_changes) == "table", "unchanged startup settings event differs")
  local changes, count = event.mod_changes, 0; for _ in pairs(changes) do count = count + 1 end
  local mir, fixture = changes["more-infinite-research"], changes[FIXTURE]
  require_ok(count == 2 and mir and mir.old_version == SOURCE_MIR and TARGET[mir.new_version] and fixture and fixture.old_version == nil and fixture.new_version == "0.1.0", "exact old-to-current addition event differs")
  return {startup_changed=event.mod_startup_settings_changed,mod_changes=copy(changes),mods=exact_mods(),startup=startup_snapshot()}
end
local function input_counts(input)
  local out = {}; for _, pack in ipairs(PACKS) do out[pack] = input.get_item_count(pack) end; return out
end
local function replenish(state)
  local input = state.input
  for _, pack in ipairs(PACKS) do
    local current = input.get_item_count(pack)
    if current <= 16 then
      local added = 200 - current
      require_ok(input.insert{name=pack,count=added} == added, "lab science insert differs")
      state.science.accepted[pack] = state.science.accepted[pack] + added
      state.topups[#state.topups + 1] = {tick=game.tick,pack=pack,count=added}
    end
  end
end
local function begin_work(state)
  local steel = technology(state.player, STEEL.name)
  require_ok(state.player.current_research == steel and close(state.player.research_progress, 0), "source steel queue differs before ordinary work")
  state.lab.energy = state.lab.electric_buffer_size
  state.player.laboratory_speed_modifier = state.source_lab.laboratory_speed_modifier + SPEED_ACCELERATION
  require_ok(state.player.laboratory_speed_modifier == state.source_lab.laboratory_speed_modifier + SPEED_ACCELERATION, "temporary laboratory speed differs")
  replenish(state); state.lab.disabled_by_script = false; state.phase = "working"
end
local function assert_settled(state)
  local expected = state.expected
  local player, foreign = state.player, state.foreign
  equal(force_registry(), expected.force_registry, "force registry")
  equal(finite_frame(player, expected.player.finite), expected.player.finite, "player finite")
  equal(finite_frame(foreign, expected.foreign.finite), expected.foreign.finite, "foreign finite")
  local player_mains, foreign_mains = mains_frame(player, expected.player.mains), mains_frame(foreign, expected.foreign.mains)
  for _, row in ipairs(MAINS) do
    if row.name == STEEL.name then
      local settled = copy(expected.player.mains[row.name])
      settled.state.level, settled.state.researched, settled.state.saved_progress = 3, false, 0
      settled.unit.count = STEEL_LEVEL_THREE_COUNT
      equal(player_mains[row.name], settled, "completed steel state")
    else equal(player_mains[row.name], expected.player.mains[row.name], "player main " .. row.name) end
    equal(foreign_mains[row.name], expected.foreign.mains[row.name], "foreign main " .. row.name)
  end
  local player_queue = queue(player); require_ok(player_queue.current == STEEL.name and #player_queue.names == 1 and player_queue.names[1] == STEEL.name and player_queue.progress == 0, "settled steel queue differs")
  equal(queue(foreign), expected.foreign.queue, "foreign queue")
  local aliases = aliases_frame(player, foreign)
  for _, row in ipairs(MAINS) do
    local player_bonus, foreign_bonus = recipe(player, row.recipe).productivity_bonus, recipe(foreign, row.recipe).productivity_bonus
    require_ok(foreign_bonus == 0 and aliases.foreign[row.alias] == 0, "foreign productivity differs")
    if row.name == STEEL.name then require_ok(close(player_bonus, .2) and close(aliases.player[row.alias],.1), "steel paid/new alias bonuses differ")
    else require_ok(close(player_bonus,.1) and aliases.player[row.alias] == 0, "uncompleted paid/new alias bonuses differ") end
  end
  local lab = lab_frame(expected.lab)
  require_ok(lab.disabled_by_script and lab.laboratory_speed_modifier == expected.lab.laboratory_speed_modifier, "settled lab control differs")
  for _, pack in ipairs(PACKS) do
    local spent = state.initial_input[pack] + state.science.accepted[pack] - lab.input[pack]
    require_ok(spent == 16000 and lab.input[pack] > 0, "ordinary science accounting differs")
  end
  return lab, aliases
end
local function plain_endpoint(state)
  local lab, aliases = assert_settled(state)
  local consumed = {}
  for _, pack in ipairs(PACKS) do
    consumed[pack] = state.initial_input[pack] + state.science.accepted[pack] - lab.input[pack]
  end
  return {force_registry=force_registry(),observed_forces={player=force_frame(state.player,state.expected.player),foreign=force_frame(state.foreign,state.expected.foreign)},aliases=aliases,
    lab=lab,science={accepted=copy(state.science.accepted),remaining=copy(lab.input),consumed=consumed},
    ordinary=copy(state.ordinary),topups=copy(state.topups),callback=copy(state.callback),scripted_carriers=copy(state.scripted_carriers)}
end
local function exact_equal(actual, expected, path)
  if type(actual) ~= type(expected) then fail(path .. " type differs") end
  if type(actual) == "table" then
    for key, item in pairs(expected) do exact_equal(actual[key], item, path .. "." .. tostring(key)) end
    for key in pairs(actual) do if expected[key] == nil then fail(path .. " has unexpected field " .. tostring(key)) end end
  elseif actual ~= expected then fail(path .. " differs") end
end
local function marker(state, phase, filename, closed)
  local endpoint
  if phase == "added-pre-work" then
    endpoint = copy(state.before)
  else
    endpoint = closed or plain_endpoint(state)
  end
  local body = {kind="MIRPublished473BaseAddedSuccessorV1",schema=1,role="added-successor",phase=phase,tick=game.tick,
    source_observation_sha256=SOURCE_SHA,source_save_sha256=SOURCE_SAVE_SHA,source_tick=state.source.tick,source_saved_tick=state.source.saved_tick,before=copy(state.before),source_history=copy(state.expected.science),endpoint=endpoint,
    callback=copy(state.callback),elapsed_ticks=state.hold_start and game.tick-state.hold_start or 0}
  local text = helpers.table_to_json(body)
  helpers.write_file("published-base-added-successor/" .. filename, text, false)
  log(PREFIX .. phase .. " " .. text)
end

script.on_init(function() storage[KEY] = {phase="initialized",scripted_carriers={}} end)
script.on_load(function() cold_pending = true end)
script.on_configuration_changed(function(event)
  if not active() then return end
  cold_pending = false
  local state = storage[KEY]; require_ok(type(state) == "table" and state.phase == "initialized", "fixture initialization differs")
  local callback = configuration(event)
  local expected, before = assert_initial()
  local lab, entity, input = lab_frame(expected.lab)
  state.phase, state.expected, state.before, state.source, state.callback = "pre-work", expected, before, helpers.json_to_table(SOURCE), callback
  state.player, state.foreign, state.lab, state.input, state.source_lab = game.forces[PLAYER], game.forces[FOREIGN], entity, input, lab
  state.initial_input, state.science, state.topups = input_counts(input), {accepted={}}, {}
  for _, pack in ipairs(PACKS) do state.science.accepted[pack] = 0 end
  state.ordinary = {name=STEEL.name,completed=0,by_script=false}; state.prework_tick = game.tick
  marker(state, "added-pre-work", "added-pre-work.json")
end)
script.on_event(defines.events.on_research_finished, function(event)
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  local research = event and event.research
  if event and event.by_script == true then
    local force = research and research.force
    local player, foreign = state.player or game.forces[PLAYER], state.foreign or game.forces[FOREIGN]
    require_ok(state.phase == "initialized" or state.phase == "pre-work" or state.phase == "working", "scripted carrier phase differs")
    require_ok(research and force and (force == player or force == foreign) and carriers[research.name] == true and technology(force, research.name) == research, "unexpected scripted research event")
    state.scripted_carriers[#state.scripted_carriers + 1] = {name=research.name,force_name=force.name,force_index=force.index,tick=game.tick,by_script=true}; return
  end
  require_ok(state.phase == "working" and research and research.force == state.player and research == technology(state.player, STEEL.name) and event.by_script == false, "ordinary research event differs")
  require_ok(research.level == 3 and research.researched == false, "ordinary event was not post-increment steel level three")
  state.ordinary.completed = state.ordinary.completed + 1; require_ok(state.ordinary.completed == 1, "ordinary completion count differs")
  state.ordinary.event = {name=research.name,level=research.level,force_name=research.force.name,force_index=research.force.index,tick=game.tick,by_script=event.by_script}
  state.lab.disabled_by_script = true
  state.player.laboratory_speed_modifier = state.source_lab.laboratory_speed_modifier
  state.phase, state.hold_start = "holding", game.tick
end)
script.on_event(defines.events.on_tick, function()
  if not active() then return end
  local state = storage[KEY]; if type(state) ~= "table" then return end
  if cold_pending then
    require_ok(state.phase == "saved" and game.tick == state.saved_tick + 1, "cold tick differs")
    local endpoint = plain_endpoint(state); exact_equal(endpoint, state.saved_endpoint, "cold saved endpoint"); marker(state, "added-cold", "added-cold.json", endpoint); cold_pending = false; return
  end
  if state.phase == "pre-work" then begin_work(state)
  elseif state.phase == "working" then state.lab.energy = state.lab.electric_buffer_size; replenish(state)
  elseif state.phase == "holding" then
    assert_settled(state)
    if game.tick - state.hold_start >= HOLD then
      state.saved_endpoint = plain_endpoint(state); state.saved_tick, state.phase = game.tick, "saved"; marker(state, "added-saved", "added-saved.json", state.saved_endpoint); game.server_save(SAVE)
    end
  elseif state.phase == "saved" then exact_equal(plain_endpoint(state), state.saved_endpoint, "saved endpoint")
  elseif state.phase ~= "initialized" then fail("unknown fixture phase") end
end)
