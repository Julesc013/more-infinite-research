local plan = require("stage")
local KEY, CASE = "mir_f100_f110_laser", "f100-f110-laser-transition"
local FIXTURE, SAVE = "mir-fixture-f100-f110-laser", "mir5-native-complete"
local PROBE = "braking-force-1"
local SUSPENDED, FOREIGN = "mir-laser-suspended", "mir-laser-foreign"
local PACKS = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack",
  "military-science-pack", "utility-science-pack"}
local loaded, reported = false, false

local function fail(message) error("[mir-f100-f110-laser] " .. message) end
local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-7 end
local function technology(force, name)
  local value = force and force.technologies[name]
  if not value or value.valid == false then fail("technology absent: " .. name) end
  return value
end
local function closure()
  local mods = script.active_mods
  if mods.base ~= plan.base or mods["more-infinite-research"] ~= plan.mir
      or mods[FIXTURE] ~= plan.fixture then fail("exact engine/MIR/fixture tuple differs") end
  if settings.startup["mir-max-level-laser-shooting-speed"].value ~= 12
      or settings.startup["mir-effect-per-level-laser-shooting-speed"].value ~= 1
      or settings.startup["mir-research-time-laser-shooting-speed"].value ~= 1 then
    fail("laser fixture settings differ")
  end
end
local function native(force)
  local value = technology(force, plan.laser)
  if force.technologies[plan.old_or_new_absent] ~= nil then fail("old/new identity survived unexpectedly") end
  local effects = value.prototype.effects
  if value.prototype.max_level ~= 12 or #effects ~= 1 or effects[1].type ~= "gun-speed"
      or effects[1].ammo_category ~= plan.ammo or not close(effects[1].modifier, .01)
      or value.research_unit_count ~= 1 or value.research_unit_energy ~= 60 then
    fail("native laser definition differs")
  end
  return value
end
local function unlock(value)
  local pending, seen, count = {value}, {}, 0
  while #pending > 0 do
    local current = table.remove(pending)
    if not seen[current.name] then
      seen[current.name], count = true, count + 1
      if count > 256 then fail("Base prerequisite fixture exceeded its finite bound") end
      for _, prerequisite in pairs(current.prerequisites) do
        prerequisite.enabled, prerequisite.researched = true, true
        pending[#pending + 1] = prerequisite
      end
    end
  end
end
local function queue(force, current, second, progress, label)
  local values = force.research_queue
  local length = second and 2 or 1
  if force.research_queue_enabled ~= true or not force.current_research
      or force.current_research.name ~= current or #values ~= length
      or values[1].name ~= current or (second and values[2].name ~= second)
      or not close(force.research_progress, progress) then fail(label .. " queue/progress differs") end
end
local function science_units(inventory, name)
  local units, found = 0, false
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read and stack.name == name then
      local durability = stack.durability
      if type(durability) ~= "number" or durability <= 0 or durability > 1
          or stack.count < 1 or stack.count % 1 ~= 0 then fail("science tool stack differs") end
      units, found = units + stack.count - 1 + durability, true
    end
  end
  if not found then fail("science stack absent: " .. name) end
  return units
end
local function inventory(state)
  local lab = state.lab
  if not lab or lab.valid == false then fail("retained native lab absent") end
  return lab.get_inventory(defines.inventory.lab_input)
end
local function assert_science(state, expected)
  local input = inventory(state)
  for _, name in ipairs(PACKS) do
    if not close(science_units(input, name), expected) then fail("native lab science consumption differs: " .. name) end
  end
end
local function assert_other_forces(state)
  local suspended, foreign = game.forces[SUSPENDED], game.forces[FOREIGN]
  local detached, unrelated = native(suspended), native(foreign)
  if detached.level ~= 8 or detached.researched or not detached.enabled
      or not close(suspended.get_saved_technology_progress(detached), .27)
      or suspended.current_research ~= nil then fail("suspended renamed laser investment differs") end
  if unrelated.level ~= 8 or unrelated.researched or unrelated.enabled or unrelated.visible_when_disabled then
    fail("foreign renamed laser disablement differs")
  end
  if not close(suspended.get_gun_speed_modifier(plan.ammo), state.suspended_bonus)
      or not close(foreign.get_gun_speed_modifier(plan.ammo), state.foreign_bonus) then
    fail("unrelated native force effects differ")
  end
  queue(foreign, PROBE, nil, .42, "foreign")
end
local function assert_player(state, completed)
  local force = game.forces.player
  local value = native(force)
  local expected_level = completed and 10 or 9
  local expected_bonus = state.before_bonus + (completed and .02 or .01)
  if value.level ~= expected_level or value.researched or not value.enabled
      or value.visible_when_disabled ~= state.player_visible
      or not close(force.get_gun_speed_modifier(plan.ammo), expected_bonus)
      or not close(force.manual_mining_speed_modifier, state.mining_bonus) then
    fail("earned renamed laser state/effect differs")
  end
  if completed then queue(force, PROBE, nil, 0, "successor")
  else queue(force, plan.laser, PROBE, .42, "source investment") end
  assert_other_forces(state)
end
local function marker(stage, state)
  log('[MIR5_NATIVE_FIXTURE] RESULT {"case":"' .. CASE .. '","stage":"' .. stage
    .. '","role":"' .. plan.role .. '","status":"passed","source_labs":' .. tostring(state.source_labs)
    .. ',"successor_labs":' .. tostring(state.successor_labs) .. ',"laser":"' .. plan.laser
    .. '","level":' .. tostring(technology(game.forces.player, plan.laser).level)
    .. ',"gun_speed_modifier":' .. tostring(game.forces.player.get_gun_speed_modifier(plan.ammo))
    .. ',"source_gun_speed_baseline":' .. tostring(state.before_bonus)
    .. ',"suspended_progress":0.27,"foreign_progress":0.42,"foreign_disabled":true'
    .. ',"science_consumed_units":' .. tostring(plan.role == "source" and 1 or state.successor_units)
    .. ',"on_load_read_only":' .. tostring(stage == "reload") .. '}')
end
local function freeze(state)
  state.lab.active, state.lab.energy = false, 0
  if state.lab.active or state.lab.energy ~= 0 then fail("native lab did not freeze") end
end
local function source_init()
  closure()
  if global[KEY] ~= nil then fail("source fixture state already exists") end
  game.speed = 16
  local force = game.forces.player
  force.enable_all_prototypes(); force.research_queue_enabled = true
  local value = native(force); unlock(value)
  if value.level ~= 8 or value.researched then fail("source laser is not fresh") end
  local lab = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=force}
  if not lab or not lab.valid then fail("native lab creation failed") end
  local state = {phase="source-lab", source_labs=0, successor_labs=0, lab=lab,
    before_bonus=force.get_gun_speed_modifier(plan.ammo), mining_bonus=force.manual_mining_speed_modifier,
    player_visible=value.visible_when_disabled,
    deadline=game.tick + 18000, origin="f100-5.0.10000-laser"}
  global[KEY] = state
  local input = inventory(state)
  for _, name in ipairs(PACKS) do if input.insert{name=name,count=32} ~= 32 then fail("science insertion failed") end end
  if force.add_research(value) ~= true then fail("source laser research did not start") end
end
local function source_finish(state)
  local force = game.forces.player
  if state.source_labs ~= 1 or native(force).level ~= 9
      or not close(force.get_gun_speed_modifier(plan.ammo), state.before_bonus + .01) then
    fail("source real lab did not earn one laser level/effect")
  end
  freeze(state); assert_science(state, 31)
  local value, probe = native(force), technology(force, PROBE)
  unlock(probe); probe.enabled = true
  force.research_queue = {value, probe}; force.research_progress = .42
  local suspended = game.create_force(SUSPENDED)
  suspended.enable_all_prototypes(); local detached = native(suspended); unlock(detached)
  suspended.set_saved_technology_progress(detached, .27)
  state.suspended_bonus = suspended.get_gun_speed_modifier(plan.ammo)
  local foreign = game.create_force(FOREIGN)
  foreign.enable_all_prototypes(); foreign.research_queue_enabled = true
  local unrelated, foreign_probe = native(foreign), technology(foreign, PROBE)
  unlock(unrelated); unlock(foreign_probe)
  unrelated.enabled, unrelated.visible_when_disabled = false, false
  if foreign.add_research(foreign_probe) ~= true then fail("foreign probe did not start") end
  foreign.research_progress = .42; state.foreign_bonus = foreign.get_gun_speed_modifier(plan.ammo)
  state.phase = "source-complete"
  assert_player(state, false); marker("initial", state); game.server_save(SAVE)
end
local function successor_config()
  closure()
  local state = global[KEY]
  if type(state) ~= "table" or state.origin ~= "f100-5.0.10000-laser"
      or state.phase ~= "source-complete" or state.source_labs ~= 1 or state.successor_labs ~= 0 then
    fail("successor lacks the exact completed source witness")
  end
  assert_player(state, false); assert_science(state, 31) -- Before fixture writes.
  local force = game.forces.player
  if not close(force.laboratory_speed_modifier, 0) or not close(force.laboratory_productivity_bonus, 0) then
    fail("successor native lab speed/productivity differs")
  end
  state.successor_units = math.ceil((1 - force.research_progress) * 60) / 60
  if not close(state.successor_units, 35 / 60) then fail("partial research timing expectation differs") end
  state.phase, state.deadline = "successor-lab", game.tick + 18000
  loaded, reported = false, false
  state.lab.active, state.lab.energy = true, 100000000
end
if plan.role == "source" then script.on_init(source_init)
elseif plan.role == "successor" then script.on_configuration_changed(successor_config)
else fail("fixture role differs") end
script.on_event(defines.events.on_research_finished, function(event)
  local state = global[KEY]
  if not state or not event.research or event.research.force ~= game.forces.player
      or event.research.name ~= plan.laser then return end
  if state.phase == "source-lab" then
    state.source_labs = state.source_labs + 1
    if state.source_labs ~= 1 then fail("duplicate source laser completion") end
    state.phase = "source-observe"
  elseif state.phase == "successor-lab" then
    state.successor_labs = state.successor_labs + 1
    if state.successor_labs ~= 1 then fail("duplicate successor laser completion") end
    state.phase = "successor-observe"
  end
end)
script.on_load(function()
  local state = global[KEY]
  loaded = type(state) == "table" and state.phase == plan.role .. "-complete"
  reported = false
end)
script.on_event(defines.events.on_tick, function()
  local state = global[KEY]
  if type(state) ~= "table" then fail("fixture state absent") end
  if state.phase == "source-complete" or state.phase == "successor-complete" then
    assert_player(state, state.phase == "successor-complete")
    assert_science(state, state.phase == "successor-complete" and 31 - state.successor_units or 31)
    if loaded and not reported then marker("reload", state); reported = true end
    return
  end
  if game.tick > state.deadline then fail("native laser lab deadline exceeded") end
  state.lab.energy = 100000000
  if state.phase == "source-observe" then source_finish(state)
  elseif state.phase == "successor-observe" then
    freeze(state)
    if state.successor_labs ~= 1 then fail("successor lab count differs") end
    assert_player(state, true); assert_science(state, 31 - state.successor_units)
    state.phase = "successor-complete"; marker("initial", state); game.server_save(SAVE)
  end
end)
