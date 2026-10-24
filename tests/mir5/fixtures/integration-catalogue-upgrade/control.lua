-- One saved-game assertion for the exact F200 integration captures.  The public
-- row list is adjacent fixture data recovered from published 4.7.2 output;
-- this control never scans arbitrary technologies or recipes.
local KEY = "mir5_integration_catalogue_upgrade"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-integration-catalogue-upgrade"
local DEADLINE = 36000
local UINT32_MAX = 4294967295
local PLAN = require("__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue")
local loaded, reload_logged = false, false

local function fail(message) error("[mir5-integration-catalogue-upgrade] " .. message) end
local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= .000001
end
local function source_stage()
  local mir, fixture = script.active_mods["more-infinite-research"], script.active_mods[FIXTURE]
  if mir == "4.7.20002" and fixture == "0.1.0" then return true end
  if mir == "5.0.20000" and fixture == "0.2.0" then return false end
  fail("fixture stage closure differs")
end
local SOURCE = source_stage()

local function profile()
  local active = script.active_mods
  if active.base ~= "2.0.77" then fail("fixture engine closure differs") end
  if active.bobwarfare ~= nil then
    if active.bobwarfare ~= "2.1.0" or active.boblibrary ~= "2.1.0"
        or active.pycoalprocessing ~= nil or active.pyalienlife ~= nil or active.pyhightech ~= nil then
      fail("Bob Warfare profile closure differs")
    end
    return PLAN.profiles["armor-bobwarfare"], "armor-bobwarfare"
  end
  if active.pyhightech ~= nil or active.pyalienlife ~= nil then
    if active.pycoalprocessing ~= "3.0.44" or active.pyalienlife ~= "3.0.67" or active.pyhightech ~= "3.0.19"
        or active.bobwarfare ~= nil then fail("Py AlienLife/HighTech profile closure differs") end
    return PLAN.profiles["py-alienlife-hightech"], "py-alienlife-hightech"
  end
  if active.pycoalprocessing ~= nil then
    if active.pycoalprocessing ~= "3.0.44" or active.bobwarfare ~= nil then fail("Py Coal profile closure differs") end
    return PLAN.profiles["py-coal"], "py-coal"
  end
  fail("fixture has no admitted integration profile")
end

local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function prerequisites(value)
  for _, prerequisite in pairs(value.prerequisites) do prerequisite.research_recursive() end
end
local function effect_signature(value)
  local kind = type(value)
  if kind == "string" then return "s:" .. value end
  if kind == "number" then return "n:" .. string.format("%.17g", value) end
  if kind == "boolean" then return value and "b:true" or "b:false" end
  if kind ~= "table" then return kind .. ":" .. tostring(value) end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  local rows = {}
  for _, key in ipairs(keys) do rows[#rows + 1] = effect_signature(key) .. "=" .. effect_signature(value[key]) end
  return "{" .. table.concat(rows, ",") .. "}"
end
local function per_level(value)
  local result = {recipes={}, guns={}}
  for _, effect in pairs(value.prototype.effects or {}) do
    if effect.type == "change-recipe-productivity" then
      result.recipes[effect.recipe] = (result.recipes[effect.recipe] or 0) + effect.change
    elseif effect.type == "gun-speed" then
      result.guns[effect.ammo_category] = (result.guns[effect.ammo_category] or 0) + effect.modifier
    end
  end
  return result
end
local function add_delta(into, next)
  for recipe, value in pairs(next.recipes) do into.recipes[recipe] = (into.recipes[recipe] or 0) + value end
  for category, value in pairs(next.guns) do into.guns[category] = (into.guns[category] or 0) + value end
end
local function state_rows(plan)
  return plan.public
end
local function seed_levels(force, plan, label)
  local finite = plan.finite
  for _, name in ipairs(state_rows(plan)) do
    local value = technology(force, name)
    if finite ~= nil and name == finite.early then
      if value.prototype.max_level ~= finite.early_level then fail(label .. " finite early maximum differs") end
      value.level, value.researched = finite.early_level, true
    elseif finite ~= nil and name == finite.tail then
      if value.prototype.max_level ~= 50000000 then fail(label .. " finite tail maximum differs") end
      value.level, value.researched = finite.tail_level, false
    else
      if value.prototype.max_level ~= UINT32_MAX then fail(label .. " unexpected finite public row: " .. name) end
      value.level = value.prototype.level + 1
      if value.researched then fail(label .. " seeded infinite row became researched: " .. name) end
    end
  end
  force.reset_technology_effects()
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queue, progress=force.research_progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do if actual.queue[index] ~= name then fail(label .. " queue identity differs") end end
end
local function snapshot(force, plan)
  local out = {technologies={}, effects={}, recipes={}, guns={}, fields={}}
  local all_recipes, all_guns = {}, {}
  for _, name in ipairs(state_rows(plan)) do
    local value = technology(force, name)
    out.technologies[name] = {level=value.level, researched=value.researched, enabled=value.enabled,
      visible=value.visible_when_disabled, saved=value.saved_progress, maximum=value.prototype.max_level}
    out.effects[name] = effect_signature(value.prototype.effects or {})
    local delta = per_level(value)
    for recipe in pairs(delta.recipes) do all_recipes[recipe] = true end
    for category in pairs(delta.guns) do all_guns[category] = true end
  end
  for recipe in pairs(all_recipes) do
    local value = force.recipes[recipe]
    if value == nil or value.valid == false or type(value.productivity_bonus) ~= "number" then fail("recipe productivity fact is absent: " .. recipe) end
    out.recipes[recipe] = value.productivity_bonus
  end
  for category in pairs(all_guns) do
    local value = force.get_gun_speed_modifier(category)
    if type(value) ~= "number" then fail("native gun-speed fact is absent: " .. category) end
    out.guns[category] = value
  end
  for _, field in ipairs(PLAN.force_fields) do
    local value = force[field]
    if type(value) ~= "number" then fail("native force effect field is absent: " .. field) end
    out.fields[field] = value
  end
  return out
end
local function assert_same_snapshot(force, plan, expected, label)
  local actual = snapshot(force, plan)
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    if now == nil or now.level ~= before.level or now.researched ~= before.researched or now.enabled ~= before.enabled
        or now.visible ~= before.visible or now.maximum ~= before.maximum or not close(now.saved, before.saved) then
      fail(label .. " technology state changed: " .. name)
    end
    if actual.effects[name] ~= expected.effects[name] then fail(label .. " technology effects changed: " .. name) end
  end
  for recipe, before in pairs(expected.recipes) do if not close(actual.recipes[recipe], before) then fail(label .. " recipe bonus changed: " .. recipe) end end
  for category, before in pairs(expected.guns) do if not close(actual.guns[category], before) then fail(label .. " gun effect changed: " .. category) end end
  for field, before in pairs(expected.fields) do if not close(actual.fields[field], before) then fail(label .. " native force effect changed: " .. field) end end
  return actual
end
local function assert_advanced(force, plan, expected, delta, label)
  local actual = snapshot(force, plan)
  local advanced = {[plan.primary]=true, [plan.continuation]=true}
  for name, before in pairs(expected.technologies) do
    local now = actual.technologies[name]
    local wanted_level = before.level + (advanced[name] and 1 or 0)
    local wanted_saved = name == plan.primary and 0 or before.saved
    if now == nil or now.level ~= wanted_level or now.researched ~= before.researched or now.enabled ~= before.enabled
        or now.visible ~= before.visible or now.maximum ~= before.maximum or not close(now.saved, wanted_saved) then
      fail(label .. " technology state changed: " .. name)
    end
    if actual.effects[name] ~= expected.effects[name] then fail(label .. " technology effects changed: " .. name) end
  end
  for recipe, before in pairs(expected.recipes) do
    if not close(actual.recipes[recipe], before + (delta.recipes[recipe] or 0)) then fail(label .. " recipe bonus changed: " .. recipe) end
  end
  for category, before in pairs(expected.guns) do
    if not close(actual.guns[category], before + (delta.guns[category] or 0)) then fail(label .. " gun effect changed: " .. category) end
  end
  for field, before in pairs(expected.fields) do if not close(actual.fields[field], before) then fail(label .. " native force effect changed: " .. field) end end
end
local function lab(state)
  local entity = state.lab
  if entity == nil or entity.valid == false then fail("real lab is absent") end
  local inventory = entity.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("real lab input is absent") end
  return entity, inventory
end
local function fill(state, value)
  local entity, inventory = lab(state)
  inventory.clear()
  for _, ingredient in ipairs(value.research_unit_ingredients) do
    if inventory.insert{name=ingredient.name, count=128} ~= 128 then fail("could not insert science: " .. ingredient.name) end
  end
  entity.active, entity.energy = true, 1000000000
end
local function freeze(state)
  local entity, inventory = lab(state)
  entity.active, entity.energy = false, 0
  inventory.clear()
end
local function marker(stage, state, plan, profile_name)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case="integration-catalogue-upgrade", stage=stage, status="passed", profile=profile_name,
    qualification="native-runner-readback-required", witnesses={
      public_rows=#plan.public, source_labs=state.source_labs, successor_labs=state.successor_labs,
      primary=plan.primary, continuation=plan.continuation, queued_progress=.42, paused_progress=.27,
      finite_log=plan.finite ~= nil, foreign_disablement_checked=true, save_name=SAVE,
      on_load_read_only=stage == "reload",
    },
  }))
end
local function begin_task(state, force, plan, index)
  local name = index == 1 and plan.primary or plan.continuation
  local value = technology(force, name)
  fill(state, value)
  local current = force.current_research
  if current ~= nil and current.name ~= name then fail("current research differs before actual lab: " .. name) end
  if current == nil and force.add_research(value) ~= true then fail("could not queue actual lab research: " .. name) end
  state.active_task = name
end
local function finish_source(state, plan, profile_name)
  freeze(state)
  local player = game.forces.player
  local primary = technology(player, plan.primary)
  primary.saved_progress = .42
  player.research_queue = {primary}
  player.research_progress = .42
  state.player_queue = queue_snapshot(player)
  assert_queue(player, state.player_queue, "source current work")
  state.source_snapshot = snapshot(player, plan)
  state.phase = "source-complete"
  marker("initial", state, plan, profile_name)
  game.server_save(SAVE)
end
local function source_init()
  local plan, profile_name = profile()
  if storage[KEY] ~= nil then fail("source fixture state already exists") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  seed_levels(player, plan, "source player")
  prerequisites(technology(player, plan.primary)); prerequisites(technology(player, plan.continuation))
  local paused = game.create_force("mir5-integration-catalogue-upgrade-paused")
  paused.enable_all_prototypes(); seed_levels(paused, plan, "source paused")
  technology(paused, plan.primary).saved_progress = .27
  if not close(technology(paused, plan.primary).saved_progress, .27) or paused.current_research ~= nil or #(paused.research_queue or {}) ~= 0 then
    fail("paused saved work seed differs")
  end
  local foreign = game.create_force("mir5-integration-catalogue-upgrade-foreign")
  foreign.enable_all_prototypes(); seed_levels(foreign, plan, "foreign")
  local foreign_primary = technology(foreign, plan.primary)
  foreign_primary.enabled, foreign_primary.visible_when_disabled = false, false
  local entity = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if entity == nil or entity.valid == false then fail("could not create a real integration lab") end
  local state = {phase="await-source-labs", profile=profile_name, lab=entity, paused_index=paused.index, foreign_index=foreign.index,
    source_labs=0, successor_labs=0, task_index=1, deadline=game.tick + DEADLINE,
    paused_snapshot=snapshot(paused, plan), foreign_snapshot=snapshot(foreign, plan),
    delta={recipes={}, guns={}}}
  add_delta(state.delta, per_level(technology(player, plan.primary)))
  add_delta(state.delta, per_level(technology(player, plan.continuation)))
  storage[KEY] = state
  begin_task(state, player, plan, 1)
end
local function source_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture state is absent") end
  local plan, profile_name = profile()
  if state.phase == "source-complete" then
    if loaded and not reload_logged then
      assert_same_snapshot(game.forces.player, plan, state.source_snapshot, "source cold reload")
      local paused, foreign = game.forces[state.paused_index], game.forces[state.foreign_index]
      if paused == nil or foreign == nil then fail("source cold reload lost auxiliary force") end
      assert_same_snapshot(paused, plan, state.paused_snapshot, "source paused cold reload")
      assert_same_snapshot(foreign, plan, state.foreign_snapshot, "source foreign cold reload")
      marker("reload", state, plan, profile_name); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("source integration labs did not finish") end
  if state.phase == "await-source-labs" then
    local entity = lab(state); entity.energy = 1000000000
    if state.active_task ~= nil then return end
    if state.task_index <= 2 then
      begin_task(state, game.forces.player, plan, state.task_index)
    else
      finish_source(state, plan, profile_name)
    end
  end
end
local function successor_config()
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "source-complete" or type(state.source_snapshot) ~= "table"
      or type(state.paused_snapshot) ~= "table" or type(state.foreign_snapshot) ~= "table" then
    fail("successor lacks the complete published source witness")
  end
  local plan, profile_name = profile()
  if state.profile ~= profile_name then fail("successor changed integration profile") end
  local player = game.forces.player
  assert_same_snapshot(player, plan, state.source_snapshot, "pre-successor")
  assert_queue(player, state.player_queue, "pre-successor")
  local paused, foreign = game.forces[state.paused_index], game.forces[state.foreign_index]
  if paused == nil or foreign == nil then fail("successor lost auxiliary force") end
  assert_same_snapshot(paused, plan, state.paused_snapshot, "pre-successor paused")
  assert_same_snapshot(foreign, plan, state.foreign_snapshot, "pre-successor foreign")
  state.phase, state.task_index, state.active_task, state.deadline = "await-successor-labs", 1, plan.primary, game.tick + DEADLINE
  fill(state, technology(player, plan.primary))
end
local function finish_successor(state, plan, profile_name)
  freeze(state)
  assert_advanced(game.forces.player, plan, state.source_snapshot, state.delta, "successor labs")
  local paused, foreign = game.forces[state.paused_index], game.forces[state.foreign_index]
  if paused == nil or foreign == nil then fail("successor lost auxiliary force") end
  assert_same_snapshot(paused, plan, state.paused_snapshot, "successor paused labs")
  assert_same_snapshot(foreign, plan, state.foreign_snapshot, "successor foreign labs")
  state.phase = "successor-complete"
  marker("initial", state, plan, profile_name)
  game.server_save(SAVE)
end
local function successor_tick()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("successor fixture state is absent") end
  local plan, profile_name = profile()
  if state.phase == "successor-complete" then
    if loaded and not reload_logged then
      assert_advanced(game.forces.player, plan, state.source_snapshot, state.delta, "successor cold reload")
      local paused, foreign = game.forces[state.paused_index], game.forces[state.foreign_index]
      if paused == nil or foreign == nil then fail("successor cold reload lost auxiliary force") end
      assert_same_snapshot(paused, plan, state.paused_snapshot, "successor paused cold reload")
      assert_same_snapshot(foreign, plan, state.foreign_snapshot, "successor foreign cold reload")
      marker("reload", state, plan, profile_name); reload_logged = true
    end
    return
  end
  if game.tick > state.deadline then fail("successor integration labs did not finish") end
  if state.phase == "await-successor-labs" then
    local entity = lab(state); entity.energy = 1000000000
    if state.active_task ~= nil then return end
    if state.task_index <= 2 then
      begin_task(state, game.forces.player, plan, state.task_index)
    else
      finish_successor(state, plan, profile_name)
    end
  end
end

if SOURCE then script.on_init(source_init) else script.on_configuration_changed(successor_config) end
script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or event.research == nil or event.research.force ~= game.forces.player then return end
  if state.active_task == nil or event.research.name ~= state.active_task then fail("unexpected research completion") end
  if SOURCE and state.phase == "await-source-labs" then state.source_labs = state.source_labs + 1
  elseif not SOURCE and state.phase == "await-successor-labs" then state.successor_labs = state.successor_labs + 1
  else fail("research completion occurred outside fixture lab phase") end
  state.task_index, state.active_task = state.task_index + 1, nil
end)
script.on_load(function()
  local state = storage[KEY]
  loaded = type(state) == "table" and (state.phase == "source-complete" or state.phase == "successor-complete")
  reload_logged = false
end)
script.on_event(defines.events.on_tick, function() if SOURCE then source_tick() else successor_tick() end end)
