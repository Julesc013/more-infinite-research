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
  lab.energy = 0
  local initial = {}
  for _, name in ipairs(packs) do initial[name] = inventory.get_item_count(name) end
  return lab, initial
end

local function capture_lab_packs(lab, items)
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  local counts = {}
  for _, name in ipairs(items) do counts[name] = inventory.get_item_count(name) end
  return counts
end

local function report_lab_pack_counts(label, stage, items, counts)
  local rows = {}
  for _, name in ipairs(items) do
    rows[#rows + 1] = name .. "=" .. tostring(counts[name])
  end
  log("[MIR5_HISTORICAL_NATIVE] " .. label .. "_" .. stage .. " " .. table.concat(rows, ","))
end

local function set_lab_energy(lab, amount)
  if lab and lab.valid then lab.energy = amount end
end

local function power_direct_lab(state)
  set_lab_energy(state.direct_lab, 100000000)
  set_lab_energy(state.continuation_lab, 0)
end

local function power_continuation_lab(state)
  set_lab_energy(state.direct_lab, 0)
  set_lab_energy(state.continuation_lab, 100000000)
end

local function freeze_labs(state)
  set_lab_energy(state.direct_lab, 0)
  set_lab_energy(state.continuation_lab, 0)
end

local function assert_lab_research_unit(label, value)
  local count, energy = value.research_unit_count, value.research_unit_energy
  log("[MIR5_HISTORICAL_NATIVE] " .. label .. "_unit count=" .. tostring(count) .. ",energy=" .. tostring(energy))
  if count ~= 1 or energy ~= 60 then
    fail("real " .. label .. " lab research unit differs")
  end
end

local function assert_direct(state)
  local force = game.forces.player
  local direct = technology(force, target.direct)
  if not direct.researched or not close(force.manual_mining_speed_modifier, state.before_mining + target.direct_effect) then
    fail("real direct lab completion did not apply its mining bonus")
  end
  local counts = capture_lab_packs(state.direct_lab, target.direct_science)
  for _, name in ipairs(target.direct_science) do
    if state.direct_lab_initial[name] - counts[name] < 1 then
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

local function continuation_effect(force)
  if target.continuation_gun_speed_ammo ~= nil then
    return force.get_gun_speed_modifier(target.continuation_gun_speed_ammo)
  end
  return force.stack_inserter_capacity_bonus
end

local function assert_lab_continuation(state)
  local force = game.forces.player
  local value = technology(force, target.continuation)
  local expected_delta = target.continuation_effect_delta or 1
  if not value.researched or not close(continuation_effect(force), state.before_continuation_effect + expected_delta) then
    fail("real continuation lab completion did not retain its generated native effect")
  end
  local counts = capture_lab_packs(state.continuation_lab, target.continuation_science)
  for _, name in ipairs(target.continuation_science) do
    if state.continuation_lab_initial[name] - counts[name] < 1 then
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
  if target.science_policy == "all" then
    assert_lab_research_unit("direct", direct)
    assert_lab_research_unit("continuation", continuation)
  end
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
    before_continuation_effect=continuation_effect(force), direct_finished=0, continuation_finished=0,
    deadline=game.tick + DEADLINE_TICKS,
  }
  power_direct_lab(global[KEY])
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
    freeze_labs(state)
    if target.science_policy == "all" then
      state.direct_event_tick = game.tick
      state.direct_event_counts = capture_lab_packs(state.direct_lab, target.direct_science)
      report_lab_pack_counts("direct_lab", "event", target.direct_science, state.direct_event_counts)
      state.phase = "direct-consumption-pending"
      return
    end
    assert_direct(state)
    if target.continuation_mode == "lab" then
      state.phase = "continuation-pending"
    else
      state.phase = "complete"
    end
  elseif target.continuation_mode == "lab" and event.research.name == target.continuation then
    state.continuation_finished = state.continuation_finished + 1
    if state.continuation_finished ~= 1 then fail("continuation research completed more than once") end
    freeze_labs(state)
    if target.science_policy == "all" then
      state.continuation_event_tick = game.tick
      state.continuation_event_counts = capture_lab_packs(state.continuation_lab, target.continuation_science)
      report_lab_pack_counts("continuation_lab", "event", target.continuation_science, state.continuation_event_counts)
      state.phase = "continuation-consumption-pending"
      return
    end
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
    before_continuation_effect=state.before_continuation_effect,
  } or nil
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = global[KEY]
  if not state then fail("fixture state is absent") end
  if state.phase == "direct-consumption-pending" then
    if game.tick <= state.direct_event_tick then return end
    state.direct_next_tick_counts = capture_lab_packs(state.direct_lab, target.direct_science)
    report_lab_pack_counts("direct_lab", "next_tick", target.direct_science, state.direct_next_tick_counts)
    assert_direct(state)
    if target.continuation_mode == "lab" then
      state.phase = "continuation-pending"
    else
      state.phase = "complete"
      return
    end
  elseif state.phase == "continuation-consumption-pending" then
    if game.tick <= state.continuation_event_tick then return end
    state.continuation_next_tick_counts = capture_lab_packs(state.continuation_lab, target.continuation_science)
    report_lab_pack_counts("continuation_lab", "next_tick", target.continuation_science,
      state.continuation_next_tick_counts)
    assert_lab_continuation(state)
    state.phase = "complete"
  end
  if state.phase ~= "complete" then
    if state.phase == "direct" then
      power_direct_lab(state)
    elseif state.phase == "continuation-pending" or state.phase == "continuation" then
      power_continuation_lab(state)
    end
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
        or state.before_continuation_effect ~= loaded.before_continuation_effect then
      fail("on_load changed durable historical research witnesses")
    end
    assert_complete(state)
    marker("reload", state)
    reported = true
  end
end)
