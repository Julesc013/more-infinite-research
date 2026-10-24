local target = require("target")
local KEY = "mir5_historical_native"
local LAB_PACK_COUNT = 32
local DEADLINE_TICKS = 18000
local loaded, reported

local function fail(message)
  error("[mir5-historical-native] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < 0.0000001
end

local function technology(force, name)
  local value = force.technologies[name]
  if not value then fail("missing expected technology " .. name) end
  return value
end

local function unlock_prerequisites(value, seen)
  seen = seen or {}
  if seen[value.name] then return end
  seen[value.name] = true
  for _, prerequisite in pairs(value.prerequisites) do
    unlock_prerequisites(prerequisite, seen)
    prerequisite.enabled = true
    prerequisite.researched = true
  end
end

local function require_lab_packs(inventory, items)
  for _, name in ipairs(items) do
    if inventory.insert{name=name, count=LAB_PACK_COUNT} ~= LAB_PACK_COUNT then
      fail("real lab rejected " .. name)
    end
  end
end

local function create_lab(surface, position, force, packs)
  local lab = surface.create_entity{name="lab", position=position, force=force}
  if not lab or not lab.valid then fail("could not create a real base lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  require_lab_packs(inventory, packs)
  lab.energy = 100000000
  local initial = {}
  for _, name in ipairs(packs) do initial[name] = inventory.get_item_count(name) end
  return lab, initial
end

local function energize(lab)
  if lab and lab.valid then lab.energy = 100000000 end
end

local function assert_direct(state)
  local force = game.forces.player
  local direct = technology(force, target.direct)
  if not direct.researched or not close(force.manual_mining_speed_modifier, state.before_mining + target.direct_effect) then
    fail("real direct lab completion did not apply its mining bonus")
  end
  local inventory = state.direct_lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(target.direct_science) do
    if state.direct_lab_initial[name] - inventory.get_item_count(name) < 1 then
      fail("real direct lab did not consume " .. name)
    end
  end
end

local function assert_numeric_continuation()
  local value = technology(game.forces.player, target.continuation)
  if value.researched or not value.enabled or value.research_unit_count ~= target.continuation_count
      or value.research_unit_energy ~= target.continuation_energy_ticks then
    fail("numeric historical continuation differs from its published finite contract")
  end
end

local function assert_lab_continuation(state)
  local force = game.forces.player
  local value = technology(force, target.continuation)
  if not value.researched or not close(force.stack_inserter_capacity_bonus, state.before_stack_bonus + 1) then
    fail("real continuation lab completion did not retain its generated inserter effect")
  end
  local inventory = state.continuation_lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(target.continuation_science) do
    if state.continuation_lab_initial[name] - inventory.get_item_count(name) < 1 then
      fail("real continuation lab did not consume " .. name)
    end
  end
end

local function assert_complete(state)
  assert_direct(state)
  if target.continuation_mode == "numeric-witness" then
    assert_numeric_continuation()
  else
    assert_lab_continuation(state)
  end
  if game.forces.player.current_research ~= nil then fail("completed fixture retained active research") end
end

local function marker(stage, state)
  local continuation = target.continuation_mode == "lab" and "lab-completed" or "numeric-finite-witness"
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"historical-native\","
    .. "\"stage\":\"" .. stage .. "\","
    .. "\"status\":\"passed\","
    .. "\"target\":\"" .. target.id .. "\","
    .. "\"direct\":\"" .. target.direct .. "\","
    .. "\"direct_lab_completions\":" .. tostring(state.direct_finished) .. ","
    .. "\"direct_mining_bonus\":" .. tostring(game.forces.player.manual_mining_speed_modifier) .. ","
    .. "\"continuation\":\"" .. target.continuation .. "\","
    .. "\"continuation_witness\":\"" .. continuation .. "\","
    .. "\"continuation_lab_completions\":" .. tostring(state.continuation_finished) .. ","
    .. "\"two_cold_reload_witness\":" .. tostring(stage == "reload") .. ","
    .. "\"on_load_read_only\":" .. tostring(stage == "reload")
    .. "}")
end

local function start_research(force, name)
  local value = technology(force, name)
  unlock_prerequisites(value)
  value.enabled = true
  if value.researched then fail("fixture target was already researched " .. name) end
  if target.queue_api then
    if not force.add_research(value) then fail("could not queue real lab research " .. name) end
  else
    force.current_research = name
  end
  if force.current_research == nil then fail("could not start real lab research " .. name) end
end

local function initialize()
  if not game.active_mods["more-infinite-research"] then
    fail("historical fixture requires more-infinite-research")
  end
  local force, surface = game.forces.player, game.surfaces[1]
  game.speed = 16
  local direct = technology(force, target.direct)
  local continuation = technology(force, target.continuation)
  if target.continuation_mode == "numeric-witness" then
    assert_numeric_continuation()
  else
    unlock_prerequisites(continuation)
    continuation.enabled = true
    if continuation.researched then fail("fixture continuation was already researched") end
  end
  unlock_prerequisites(direct)
  direct.enabled = true
  if direct.researched then fail("fixture direct research was already complete") end

  local position = force.get_spawn_position(surface)
  -- The native 0.15+ lab declares seven accepted science-pack identities. Keep
  -- the direct and continuation supplies in separate real labs so neither
  -- probe relies on an undocumented inventory-slot union or extra science.
  local direct_lab, direct_initial = create_lab(surface, position, force, target.direct_science)
  local continuation_lab, continuation_initial
  if target.continuation_mode == "lab" then
    continuation_lab, continuation_initial = create_lab(
      surface, {x=position.x + 4, y=position.y}, force, target.continuation_science)
  end

  global[KEY] = {
    phase="direct", direct_lab=direct_lab, direct_lab_initial=direct_initial,
    continuation_lab=continuation_lab, continuation_lab_initial=continuation_initial,
    before_mining=force.manual_mining_speed_modifier,
    before_stack_bonus=force.stack_inserter_capacity_bonus, direct_finished=0, continuation_finished=0,
    deadline=game.tick + DEADLINE_TICKS,
  }
  start_research(force, target.direct)
end

script.on_init(function()
  local ok, message = pcall(initialize)
  if not ok then
    -- Some old --create processes exit without putting the Lua error in the
    -- native log. Preserve that original diagnostic; still fail the run.
    pcall(function() game.write_file("mir5-historical-init-error.txt", tostring(message), false) end)
    if log then log("[mir5-historical-native] init failed: " .. tostring(message)) end
    error(message)
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = global[KEY]
  if not state or not event.research or event.research.force ~= game.forces.player then return end
  if event.research.name == target.direct then
    state.direct_finished = state.direct_finished + 1
    if state.direct_finished ~= 1 then fail("direct research completed more than once") end
    assert_direct(state)
    if target.continuation_mode == "lab" then
      state.phase = "continuation-pending"
    else
      state.phase = "complete"
    end
  elseif target.continuation_mode == "lab" and event.research.name == target.continuation then
    state.continuation_finished = state.continuation_finished + 1
    if state.continuation_finished ~= 1 then fail("continuation research completed more than once") end
    assert_lab_continuation(state)
    state.phase = "complete"
  end
end)

script.on_load(function()
  local state = global[KEY]
  loaded = state and state.phase == "complete" and {
    direct_finished=state.direct_finished,
    continuation_finished=state.continuation_finished,
    before_mining=state.before_mining,
    before_stack_bonus=state.before_stack_bonus,
  } or nil
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = global[KEY]
  if not state then fail("fixture state is absent") end
  if state.phase ~= "complete" then
    energize(state.direct_lab)
    energize(state.continuation_lab)
    if game.tick > state.deadline then fail("real historical lab research missed its deadline") end
    if state.phase == "continuation-pending" then
      if game.forces.player.current_research ~= nil then return end
      state.phase = "continuation"
      start_research(game.forces.player, target.continuation)
    end
    return
  end
  if not state.saved then
    assert_complete(state)
    state.saved = true
    marker("initial", state)
    game.server_save("mir5-native-complete")
    return
  end
  if loaded and not reported then
    if state.direct_finished ~= loaded.direct_finished
        or state.continuation_finished ~= loaded.continuation_finished
        or state.before_mining ~= loaded.before_mining
        or state.before_stack_bonus ~= loaded.before_stack_bonus then
      fail("on_load changed durable historical research witnesses")
    end
    assert_complete(state)
    marker("reload", state)
    reported = true
  end
end)
