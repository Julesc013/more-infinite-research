local target = require("target")
local KEY = "mir5_historical_transition"
local LAB_PACK_COUNT = 32
local DEADLINE_TICKS = 18000
local loaded, reported = false, false

local function fail(message)
  error("[mir5-historical-transition] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < 0.0000001
end

local function technology(force, name)
  local value = force.technologies[name]
  if not value then fail("missing expected technology " .. name) end
  return value
end

local function current_name(force)
  local value = force.current_research
  return value and value.name or nil
end

local function queue_names(queue)
  local names = {}
  for _, value in ipairs(queue or {}) do
    names[#names + 1] = value and value.name or tostring(value)
  end
  return "[" .. table.concat(names, ",") .. "]"
end

local function queue_enabled(force)
  return target.queue_api == true and force.research_queue_enabled == true
end

local function json_boolean_or_null(value)
  if value == true then return "true" end
  if value == false then return "false" end
  return "null"
end

local function enable_research_queue(force)
  if not target.queue_api then return end
  if force.research_queue_enabled ~= true then force.research_queue_enabled = true end
  if force.research_queue_enabled ~= true then
    fail("could not enable the supported historical research queue")
  end
end

-- 0.17 and later expose current_research as a read-only observation.  The
-- established historical-native fixture uses add_research for those targets;
-- the older targets retain their supported direct setter contract.
local function start_research(force, name)
  local value = technology(force, name)
  if target.queue_api then
    if force.add_research(value) ~= true then fail("could not queue research " .. name) end
  else
    force.current_research = name
  end
  if current_name(force) ~= name then fail("could not start research " .. name) end
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

local function create_lab(surface, position, force, packs)
  local lab = surface.create_entity{name="lab", position=position, force=force}
  if not lab or not lab.valid then fail("could not create a real base lab") end
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("real lab input inventory is absent") end
  local initial = {}
  for _, name in ipairs(packs) do
    if inventory.insert{name=name, count=LAB_PACK_COUNT} ~= LAB_PACK_COUNT then
      fail("real lab rejected " .. name)
    end
    initial[name] = inventory.get_item_count(name)
  end
  lab.energy = 100000000
  return lab, initial
end

local function energize(lab)
  if lab and lab.valid then lab.energy = 100000000 end
end

local function freeze_source_lab(state)
  local lab = state.source_lab
  if not lab or not lab.valid then fail("published source lab is absent") end
  lab.active = false
  lab.energy = 0
  if lab.active or lab.energy ~= 0 then fail("published source lab did not freeze") end
end

local function assert_source_direct(state)
  local force = game.forces.player
  local direct = technology(force, target.direct)
  local complete
  if target.successor_mode == "lab" then complete = direct.level == 2 and not direct.researched
  else complete = direct.researched end
  if not complete or not close(force.manual_mining_speed_modifier, state.before_mining + target.direct_effect) then
    fail("published real direct completion did not retain its earned mining state")
  end
  local inventory = state.source_lab.get_inventory(defines.inventory.lab_input)
  for _, name in ipairs(target.direct_science) do
    if state.source_lab_initial[name] - inventory.get_item_count(name) < 1 then
      fail("published real direct lab did not consume " .. name)
    end
  end
end

local function assert_partial(force)
  if target.successor_mode ~= "lab" then return end
  local current, progress = current_name(force), force.research_progress
  local queue, expected_queue = {}, "unavailable"
  if target.queue_api then
    queue, expected_queue = force.research_queue or {}, "[" .. target.direct .. "," .. target.queue_probe .. "]"
  end
  local queue_matches = not target.queue_api
  if target.queue_api then
    queue_matches = queue_enabled(force) and #queue == 2
      and queue[1].name == target.direct and queue[2].name == target.queue_probe
  end
  if current ~= target.direct or not close(progress, target.partial_progress) or not queue_matches then
    fail("published direct partial research differs: expected_current=" .. target.direct
      .. " actual_current=" .. tostring(current)
      .. " expected_progress=" .. tostring(target.partial_progress)
      .. " actual_progress=" .. tostring(progress)
      .. " expected_queue=" .. expected_queue
      .. " actual_queue=" .. queue_names(queue)
      .. " expected_queue_enabled=" .. tostring(target.queue_api)
      .. " actual_queue_enabled=" .. tostring(queue_enabled(force)))
  end
end

local function configure_partial(state)
  local force = game.forces.player
  if target.successor_mode ~= "lab" then
    if current_name(force) ~= nil then fail("preservation-only target retained unexpected current research") end
    freeze_source_lab(state)
    state.phase = "published-ready"
    return
  end
  if current_name(force) ~= nil then fail("published completion retained active research") end
  if target.queue_api then
    enable_research_queue(force)
    local probe = technology(force, target.queue_probe)
    unlock_prerequisites(probe)
    probe.enabled = true
    if probe.researched then fail("queue probe was already researched") end
    force.research_queue = {technology(force, target.direct), probe}
  else
    start_research(force, target.direct)
  end
  force.research_progress = target.partial_progress
  assert_partial(force)
  freeze_source_lab(state)
  state.phase = "published-ready"
end

local function assert_candidate_input(state)
  local force = game.forces.player
  local direct = technology(force, target.direct)
  if state.origin ~= "published" or state.source_direct_finished ~= 1
      or not state.source_lab or not state.source_lab.valid or state.source_lab.active or state.source_lab.energy ~= 0
      or not close(force.manual_mining_speed_modifier, state.before_mining + target.direct_effect) then
    fail("MIR5 did not receive the published earned direct state")
  end
  if target.successor_mode == "lab" then
    if direct.level ~= 2 or direct.researched then fail("MIR5 direct successor level differs") end
    assert_partial(force)
  elseif not direct.researched or current_name(force) ~= nil then
    fail("MIR5 preservation-only direct state differs")
  end
end

local function assert_candidate_complete(state)
  local force = game.forces.player
  local direct = technology(force, target.direct)
  if target.successor_mode == "preservation-only" then
    if (state.successor_direct_finished or 0) ~= 0 or not direct.researched
        or not close(force.manual_mining_speed_modifier, state.before_mining + target.direct_effect)
        or current_name(force) ~= nil then
      fail("MIR5 changed preservation-only historical direct state")
    end
    return
  end
  if state.successor_direct_finished ~= 1 or direct.level ~= 3 or direct.researched
      or not close(force.manual_mining_speed_modifier, state.before_mining + 2 * target.direct_effect) then
    fail("MIR5 real successor completion did not retain the earned mining state")
  end
  if target.queue_api then
    local queue = force.research_queue
    if not queue_enabled(force) or current_name(force) ~= target.queue_probe or #queue ~= 1 or queue[1].name ~= target.queue_probe
        or technology(force, target.queue_probe).researched then
      fail("MIR5 changed the supported queued research")
    end
  elseif current_name(force) ~= nil then
    fail("MIR5 retained an unexpected old-engine current research")
  end
end

local function marker(stage, state)
  local force = game.forces.player
  -- Older target engines have no queue property. Preserve that capability
  -- distinction as JSON null rather than emitting Lua's invalid JSON `nil`.
  local marker_queue_enabled = nil
  if target.queue_api == true then marker_queue_enabled = queue_enabled(force) end
  log("[MIR5_NATIVE_FIXTURE] RESULT {"
    .. "\"case\":\"historical-transition\","
    .. "\"stage\":\"" .. stage .. "\","
    .. "\"transition_stage\":\"" .. target.stage .. "\","
    .. "\"status\":\"passed\","
    .. "\"target\":\"" .. target.id .. "\","
    .. "\"direct\":\"" .. target.direct .. "\","
    .. "\"source_direct_lab_completions\":" .. tostring(state.source_direct_finished or 0) .. ","
    .. "\"successor_direct_lab_completions\":" .. tostring(state.successor_direct_finished or 0) .. ","
    .. "\"mining_bonus\":" .. tostring(force.manual_mining_speed_modifier) .. ","
    .. "\"current_research\":\"" .. tostring(current_name(force)) .. "\","
    .. "\"research_progress\":" .. tostring(force.research_progress) .. ","
    .. "\"queue_api\":" .. tostring(target.queue_api == true) .. ","
    .. "\"research_queue_enabled\":" .. json_boolean_or_null(marker_queue_enabled) .. ","
    .. "\"two_cold_reload_witness\":" .. tostring(stage == "reload") .. ","
    .. "\"on_load_read_only\":" .. tostring(stage == "reload")
    .. "}")
end

local function initialize_published()
  if not game.active_mods["more-infinite-research"] then fail("published transition requires MIR") end
  local force, surface = game.forces.player, game.surfaces[1]
  local direct = technology(force, target.direct)
  unlock_prerequisites(direct)
  direct.enabled = true
  if direct.researched then fail("published direct probe was already complete") end
  if target.successor_mode == "lab" and direct.level ~= 1 then fail("published direct probe was not at level one") end
  local position = force.get_spawn_position(surface)
  local lab, initial = create_lab(surface, position, force, target.direct_science)
  global[KEY] = {
    origin="published", phase="published-direct", before_mining=force.manual_mining_speed_modifier,
    source_lab=lab, source_lab_initial=initial, source_direct_finished=0,
    deadline=game.tick + DEADLINE_TICKS,
  }
  enable_research_queue(force)
  start_research(force, target.direct)
end

local function initialize_mir5()
  local state = global[KEY]
  if not state then fail("MIR5 transition lacks the published fixture state") end
  assert_candidate_input(state)
  local force, surface = game.forces.player, game.surfaces[1]
  local position = force.get_spawn_position(surface)
  if target.successor_mode == "preservation-only" then
    state.successor_direct_finished = 0
    state.phase = "mir5-complete"
    return
  end
  state.successor_lab, state.successor_lab_initial = create_lab(
    surface, {x=position.x + 4, y=position.y}, force, target.direct_science)
  state.successor_direct_finished = 0
  state.phase = "mir5-successor"
  state.deadline = game.tick + DEADLINE_TICKS
end

script.on_init(function()
  if target.stage == "published" then initialize_published()
  else fail("MIR5 transition fixture requires a published input save") end
end)

script.on_configuration_changed(function()
  -- A source save can load immediately before its successor configuration.
  -- Only a completed save is a cold-reload witness; never carry a source
  -- witness into the successor stage.
  loaded, reported = false, false
  if target.stage == "mir5" then initialize_mir5() end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = global[KEY]
  if not state or not event.research or event.research.force ~= game.forces.player then return end
  if event.research.name ~= target.direct then return end
  if state.phase == "published-direct" then
    state.source_direct_finished = state.source_direct_finished + 1
    if state.source_direct_finished ~= 1 then fail("published direct completed more than once") end
    assert_source_direct(state)
    if target.successor_mode == "lab" then
      -- The historical queue clears its just-finished entry after the event.
      -- Do not attempt to replace that entry from inside on_research_finished.
      freeze_source_lab(state)
      state.phase = "published-partial-pending"
    else
      configure_partial(state)
    end
  elseif state.phase == "mir5-successor" then
    state.successor_direct_finished = state.successor_direct_finished + 1
    if state.successor_direct_finished ~= 1 then fail("MIR5 successor completed more than once") end
    state.phase = "mir5-complete"
  end
end)

script.on_load(function()
  local state = global[KEY]
  -- `--create` saves while the published direct research is still running.
  -- That ordinary load must remain observational.  Cold-reload assertions
  -- apply only after a stage wrote its completed save.
  loaded = state and (state.phase == "published-ready" or state.phase == "mir5-complete") and state.phase or nil
  reported = false
end)

script.on_event(defines.events.on_tick, function()
  local state = global[KEY]
  if not state then fail("historical transition fixture state is absent") end
  if target.stage == "published" and state.phase == "published-partial-pending" then
    if game.tick > state.deadline then fail("published research queue did not settle") end
    if current_name(game.forces.player) ~= nil then return end
    configure_partial(state)
    return
  end
  if state.phase == "published-direct" or state.phase == "mir5-successor" then
    energize(state.source_lab)
    energize(state.successor_lab)
    if game.tick > state.deadline then fail("real historical transition lab missed its deadline") end
    return
  end
  if target.stage == "published" and state.phase == "published-ready" then
    assert_source_direct(state)
    assert_partial(game.forces.player)
    if not state.saved then
      state.saved = true
      marker("initial", state)
      game.server_save("mir5-native-complete")
      return
    end
  elseif target.stage == "mir5" and state.phase == "mir5-complete" then
    assert_candidate_complete(state)
    if not state.saved_mir5 then
      state.saved_mir5 = true
      marker("initial", state)
      game.server_save("mir5-native-complete")
      return
    end
  end
  if loaded and not reported then
    if target.stage == "published" then
      if loaded ~= "published-ready" then fail("published reload phase differs") end
      assert_source_direct(state)
      assert_partial(game.forces.player)
    else
      if loaded ~= "mir5-complete" then fail("MIR5 reload phase differs") end
      assert_candidate_complete(state)
    end
    marker("reload", state)
    reported = true
  end
end)
