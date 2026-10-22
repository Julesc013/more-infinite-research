local technology_name = "recipe-prod-research_gears-1"
local recipe_name = "iron-gear-wheel"
local api_name = "more-infinite-research.api.v1"
local storage_key = "mir5_native_caps"
local save_name = "mir5-native-complete"
-- `data.raw` expresses an infinite max level as "infinite", while the pinned
-- 2.1.23 runtime API exposes the native LuaTechnologyPrototype uint32 value.
local UINT32_MAX = 4294967295
local sciences = {
  "automation-science-pack", "logistic-science-pack",
  "chemical-science-pack", "production-science-pack"
}

local loaded_snapshot = nil
local reload_logged = false

local function fail(message)
  error("[mir5-caps-native] " .. message)
end

local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.0000001
end

local function technology_for(force)
  local technology = force and force.technologies[technology_name]
  if not technology then fail("gear technology is absent for force " .. tostring(force and force.name)) end
  return technology
end

local function queue_names(force)
  local names = {}
  for _, technology in ipairs(force.research_queue or {}) do names[#names + 1] = technology.name end
  return names
end

local function research_status(force)
  local status, code = remote.call(api_name, "get_research", force.index, technology_name)
  if not status or code ~= nil then fail("public runtime API could not read gear research: " .. tostring(code)) end
  return status
end

local function marker(stage, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage = stage,
    case = "caps",
    status = "passed",
    witnesses = {
      completed_levels = state.completed_levels,
      next_level = state.next_level,
      cap = 2,
      queue_before = state.queue_before,
      queue_after = state.queue_after,
      partial_progress = state.progress_before_queue_write,
      retained_progress = state.progress_after_queue_write,
      native_productivity_bonus = state.native_productivity_bonus,
      lab_energy_seen = state.lab_energy_seen,
      science_units_consumed = state.science_units_consumed,
      foreign_enabled = state.foreign_enabled,
      foreign_visible = state.foreign_visible,
      force_created_events = state.force_created_events,
      force_reset_events = state.force_reset_events,
      merge_source_index = state.merge_source_index,
      merge_destination_index = state.merge_destination_index,
      merge_source_retired = state.merge_source_retired,
      merge_destination_level = state.merge_destination_level,
      merge_destination_enabled = state.merge_destination_enabled,
      merge_destination_productivity_bonus = state.merge_destination_productivity_bonus,
      merge_ownership_note = "source-cap-rights-removed; destination-technology-not-inherited",
      qualification = "native-runner-readback-required",
      on_load_read_only = stage == "reload"
    }
  }))
end

local function ensure_powered_lab(state)
  local lab = state.lab
  if not lab or not lab.valid then fail("native lab disappeared") end
  -- This writes the real lab's documented electric buffer; research still
  -- consumes its native pack inventory and completes through the engine.
  lab.energy = 100000000
  if lab.energy <= 0 then fail("native lab has no stored power") end
  state.lab_energy_seen = true
  return lab
end

local function fill_lab(lab)
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  if not inventory then fail("native lab has no input inventory") end
  for _, name in ipairs(sciences) do
    local inserted = inventory.insert{name = name, count = 16}
    if inserted ~= 16 then fail("could not insert required science pack " .. name) end
  end
  return inventory
end

local function prepare_prerequisites(technology)
  for _, prerequisite in pairs(technology.prerequisites) do prerequisite.research_recursive() end
end

local function start_unrelated_research(force)
  local probe = force.technologies.automation
  if not probe then fail("force has no automation probe technology") end
  if not force.add_research(probe) then fail("could not start native probe research") end
end

local function begin_foreign_witness(state)
  local foreign = game.create_force("mir5-native-caps-foreign")
  foreign.enable_all_prototypes()
  local technology = technology_for(foreign)
  -- This is an opposing external state.  A real unrelated research-start
  -- event makes MIR reconcile the force without granting it an enable right.
  technology.level = 3
  technology.enabled = false
  technology.visible_when_disabled = false
  start_unrelated_research(foreign)
  state.foreign_index = foreign.index
  state.phase = "await-foreign"
end

local function begin_merge_witness(state)
  local destination = game.create_force("mir5-native-caps-merge-destination")
  local source = game.create_force("mir5-native-caps-merge-source")
  destination.enable_all_prototypes()
  source.enable_all_prototypes()
  local source_technology = technology_for(source)
  source_technology.level = 3
  source_technology.enabled = true
  source_technology.visible_when_disabled = false
  start_unrelated_research(source)
  state.merge_source_name = source.name
  state.merge_destination_name = destination.name
  state.merge_source_index = source.index
  state.merge_destination_index = destination.index
  state.phase = "await-merge-source-cap"
end

local function finish_native_witnesses(state)
  local force = game.forces.player
  local technology = technology_for(force)
  local status = research_status(force)
  if technology.level ~= 3 or technology.researched or technology.enabled
      or not technology.visible_when_disabled then
    fail("cap did not disable level three while preserving its native state")
  end
  if force.current_research and force.current_research.name == technology_name then
    fail("above-cap current research survived")
  end
  for _, queued in ipairs(force.research_queue or {}) do
    if queued.name == technology_name then fail("above-cap queued gear research survived") end
  end
  if status.level ~= 3 or status.enabled ~= false or status.researched ~= false
      or status.max_level ~= UINT32_MAX then
    fail("public runtime API did not preserve native cap status")
  end
  local bonus = force.recipes[recipe_name].productivity_bonus
  if not close(bonus, 0.2) then fail("two completed native levels lost productivity") end
  state.native_productivity_bonus = bonus
  state.next_level = technology.level
  state.completed_levels = 2

  local inventory = ensure_powered_lab(state).get_inventory(defines.inventory.lab_input)
  state.science_units_consumed = {}
  for _, name in ipairs(sciences) do
    local consumed = 16 - inventory.get_item_count(name)
    if consumed < 2 then fail("lab did not consume two native units of " .. name) end
    state.science_units_consumed[name] = consumed
  end
  begin_foreign_witness(state)
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods["more-infinite-research"] ~= "5.0.21000" then
    fail("fixture loaded with an unexpected Factorio or MIR version")
  end
  game.speed = 16
  local force = game.forces.player
  force.enable_all_prototypes()
  local technology = technology_for(force)
  if technology.level ~= 1 or technology.researched or not technology.enabled then
    fail("fresh gear research state differs")
  end
  if technology.prototype.max_level ~= UINT32_MAX or technology.research_unit_count ~= 1
      or not close(technology.prototype.research_unit_energy, 60) then
    fail("fixture did not receive the expected native infinite one-unit technology")
  end
  prepare_prerequisites(technology)
  local lab = game.surfaces[1].create_entity{name = "lab", position = {0, 0}, force = force}
  if not lab or not lab.valid then fail("could not create real lab") end
  local inventory = fill_lab(lab)
  storage[storage_key] = {
    phase = "await-partial-progress",
    lab = lab,
    lab_energy_seen = false,
    queue_before = 0,
    queue_after = 0,
    progress_before_queue_write = 0,
    progress_after_queue_write = 0,
    completed_levels = 0,
    next_level = 1,
    force_created_events = 0,
    force_reset_events = 0,
    merge_source_index = 0,
    merge_destination_index = 0,
    merge_source_retired = false,
    deadline_tick = game.tick + 18000
  }
  ensure_powered_lab(storage[storage_key])
  if not force.add_research(technology) then fail("could not start native gear research") end
  if not force.current_research or force.current_research.name ~= technology_name then
    fail("native gear research did not enter the lab queue")
  end
  if inventory.get_item_count(sciences[1]) ~= 16 then fail("native lab inventory changed before research") end
end)

script.on_event(defines.events.on_force_created, function()
  local state = storage[storage_key]
  if state then state.force_created_events = state.force_created_events + 1 end
end)

script.on_event(defines.events.on_force_reset, function(event)
  local state = storage[storage_key]
  if state and event.force and event.force.name == "mir5-native-caps-foreign" then
    state.force_reset_events = state.force_reset_events + 1
  end
end)

script.on_event(defines.events.on_forces_merged, function(event)
  local state = storage[storage_key]
  if state and event.source_index == state.merge_source_index then
    if not event.destination or event.destination.index ~= state.merge_destination_index then
      fail("native merge destination differs from request")
    end
    state.merge_event_seen = true
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[storage_key]
  if not state or not event.research or event.research.force ~= game.forces.player
      or event.research.name ~= technology_name then return end
  state.finished_events = (state.finished_events or 0) + 1
  if state.finished_events == 1 then
    state.phase = "await-level-two"
  elseif state.finished_events == 2 then
    state.phase = "assert-cap"
  else
    fail("native lab completed a level beyond the cap")
  end
end)

script.on_load(function()
  local state = storage[storage_key]
  if state and state.saved then
    -- Read only: the first later tick verifies these durable fields survived.
    loaded_snapshot = {phase = state.phase, completed_levels = state.completed_levels,
      next_level = state.next_level, productivity = state.native_productivity_bonus}
  else
    loaded_snapshot = nil
  end
  reload_logged = false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[storage_key]
  if not state then fail("fixture state is absent") end
  if state.saved then
    if loaded_snapshot and not reload_logged then
      if state.phase ~= loaded_snapshot.phase or state.completed_levels ~= loaded_snapshot.completed_levels
          or state.next_level ~= loaded_snapshot.next_level
          or not close(state.native_productivity_bonus, loaded_snapshot.productivity) then
        fail("on_load did not preserve the saved caps witness")
      end
      marker("reload", state)
      reload_logged = true
    end
    return
  end
  if game.tick > state.deadline_tick then fail("native capped research did not reach its witness") end

  ensure_powered_lab(state)
  local force = game.forces.player
  local technology = technology_for(force)
  if state.phase == "await-partial-progress" then
    if not force.current_research or force.current_research.name ~= technology_name
        or force.research_progress <= 0 then return end
    state.progress_before_queue_write = force.research_progress
    force.research_queue = {technology, technology, technology}
    state.progress_after_queue_write = force.research_progress
    state.queue_before = 3
    if not close(state.progress_after_queue_write, state.progress_before_queue_write) then
      fail("native queue update lost partial current-research progress")
    end
    state.phase = "await-level-one"
  elseif state.phase == "await-level-two" then
    local queue = queue_names(force)
    if technology.level ~= 2 or #queue ~= 1 or queue[1] ~= technology_name
        or not force.current_research or force.current_research.name ~= technology_name then
      fail("cap did not retain exactly the ordered level-two queue entry")
    end
    state.queue_after = #queue
    state.phase = "await-level-two-finish"
  elseif state.phase == "assert-cap" then
    finish_native_witnesses(state)
  elseif state.phase == "await-foreign" then
    local foreign = game.forces["mir5-native-caps-foreign"]
    local foreign_technology = technology_for(foreign)
    if foreign_technology.level ~= 3 or foreign_technology.enabled
        or not foreign_technology.visible_when_disabled then
      fail("foreign pre-disabled above-cap technology was not preserved")
    end
    local status = research_status(foreign)
    if status.level ~= 3 or status.enabled ~= false then fail("public API lost foreign cap witness") end
    state.foreign_enabled = foreign_technology.enabled
    state.foreign_visible = foreign_technology.visible_when_disabled
    foreign.reset()
    state.phase = "await-foreign-reset"
  elseif state.phase == "await-foreign-reset" then
    local foreign = game.forces["mir5-native-caps-foreign"]
    if state.force_reset_events ~= 1 or technology_for(foreign).level ~= 1 then
      fail("native force reset did not clear its research state")
    end
    begin_merge_witness(state)
  elseif state.phase == "await-merge-source-cap" then
    local source = game.forces[state.merge_source_name]
    local source_technology = technology_for(source)
    if source_technology.level ~= 3 or source_technology.enabled or not source_technology.visible_when_disabled then
      fail("native merge source did not receive a cap-owned disablement")
    end
    -- JSON member order is not the call order: the pinned 2.1.23 API declares
    -- source at order 0 and destination at order 1.
    game.merge_forces(source, game.forces[state.merge_destination_name])
    state.phase = "await-merge"
  elseif state.phase == "await-merge" then
    local source = game.forces[state.merge_source_name]
    if source and source.valid then return end
    local destination = game.forces[state.merge_destination_name]
    if not destination or not destination.valid or not state.merge_event_seen then
      fail("native merge did not retire source and notify destination")
    end
    -- Factorio's merge contract retains the destination's technologies and
    -- bonuses. Source cap ownership must therefore be removed, not copied.
    local destination_technology = technology_for(destination)
    local destination_bonus = destination.recipes[recipe_name].productivity_bonus
    if destination_technology.level ~= 1 or destination_technology.researched
        or not destination_technology.enabled or destination_technology.visible_when_disabled
        or not close(destination_bonus, 0) then
      fail("native merge did not retain the destination technology state")
    end
    state.merge_source_retired = true
    state.merge_destination_level = destination_technology.level
    state.merge_destination_enabled = destination_technology.enabled
    state.merge_destination_productivity_bonus = destination_bonus
    if state.force_created_events < 3 then fail("native force-created lifecycle was not observed") end
    marker("initial", state)
    state.saved = true
    state.phase = "saved"
    game.server_save(save_name)
  elseif state.phase ~= "await-level-one" and state.phase ~= "await-level-two-finish" then
    fail("unknown fixture phase " .. tostring(state.phase))
  end
end)
