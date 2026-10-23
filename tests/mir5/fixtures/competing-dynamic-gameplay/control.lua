-- One private F200 Space Age native continuity controller for the two exact
-- dynamic competing-productivity profiles. The stage folder supplies only
-- metadata/settings/data preflight; it never copies this control body.
local KEY = "mir5_competing_dynamic_gameplay"
local FIXTURE = "mir-fixture-mir5-competing-dynamic-gameplay"
local SAVE = "mir5-native-complete"
local UINT32_MAX = 4294967295
local PROBE = "braking-force-1"
local FOREIGN = "mir5-competing-dynamic-foreign"
local DETACHED = "mir5-competing-dynamic-detached"
-- Exact direct F200 2.0.77 prerequisite names captured with both providers.
local PROBE_PREREQUISITES = {"railway", "chemical-science-pack"}
local DEADLINE = 60 * 60 * 8
local loaded_snapshot, reload_logged, pending_save = nil, false, false

local PROVIDERS = {
  ce = {
    mod = "crafting-efficiency-2", version = "0.2.20", target = "ce-iron-gear-wheel-19",
    predecessor = "ce-iron-gear-wheel-14", recipe = "iron-gear-wheel",
    prerequisites = {"ce-iron-gear-wheel-14", "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"},
    science = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack"},
    ids = {"ce-advanced-circuit-16", "ce-advanced-oil-processing-11", "ce-agricultural-science-pack-30", "ce-automation-science-pack-42", "ce-basic-oil-processing-16", "ce-battery-16", "ce-chemical-science-pack-30", "ce-coal-liquefaction-8", "ce-copper-cable-19", "ce-cryogenic-science-pack-15", "ce-electric-engine-unit-11", "ce-electromagnetic-science-pack-30", "ce-electronic-circuit-19", "ce-engine-unit-19", "ce-firearm-magazine-17", "ce-flying-robot-frame-11", "ce-grenade-14", "ce-iron-gear-wheel-19", "ce-iron-stick-19", "ce-logistic-science-pack-36", "ce-lubricant-8", "ce-metallurgic-science-pack-30", "ce-military-science-pack-30", "ce-production-science-pack-24", "ce-promethium-science-pack-15", "ce-space-science-pack-15", "ce-sulfur-16", "ce-utility-science-pack-15"},
  },
  pr = {
    mod = "ProductivityResearch", version = "1.3.2", target = "sem-prfe_iron-gear-wheel-productivity-1",
    predecessor = false, recipe = "iron-gear-wheel", prerequisites = {}, science = {"automation-science-pack"},
    ids = {"sem-prfe_advanced-circuit-productivity-1", "sem-prfe_advanced-oil-processing-productivity-1", "sem-prfe_agricultural-science-pack-productivity-1", "sem-prfe_artificial-jellynut-soil-productivity-1", "sem-prfe_artificial-yumako-soil-productivity-1", "sem-prfe_automation-science-pack-productivity-1", "sem-prfe_battery-productivity-1", "sem-prfe_bioflux-productivity-1", "sem-prfe_carbon-fiber-productivity-1", "sem-prfe_chemical-science-pack-productivity-1", "sem-prfe_copper-cable-productivity-1", "sem-prfe_copper-plate-productivity-1", "sem-prfe_cryogenic-science-pack-productivity-1", "sem-prfe_electric-engine-unit-productivity-1", "sem-prfe_electromagnetic-science-pack-productivity-1", "sem-prfe_electronic-circuit-productivity-1", "sem-prfe_engine-unit-productivity-1", "sem-prfe_explosives-productivity-1", "sem-prfe_flying-robot-frame-productivity-1", "sem-prfe_holmium-plate-productivity-1", "sem-prfe_iron-gear-wheel-productivity-1", "sem-prfe_iron-plate-productivity-1", "sem-prfe_iron-stick-productivity-1", "sem-prfe_lithium-plate-productivity-1", "sem-prfe_logistic-science-pack-productivity-1", "sem-prfe_lubricant-productivity-1", "sem-prfe_metallurgic-science-pack-productivity-1", "sem-prfe_military-science-pack-productivity-1", "sem-prfe_pentapod-egg-productivity-1", "sem-prfe_production-science-pack-productivity-1", "sem-prfe_promethium-science-pack-productivity-1", "sem-prfe_quantum-processor-productivity-1", "sem-prfe_space-science-pack-productivity-1", "sem-prfe_stone-brick-productivity-1", "sem-prfe_sulfur-productivity-1", "sem-prfe_sulfuric-acid-productivity-1", "sem-prfe_supercapacitor-productivity-1", "sem-prfe_superconductor-productivity-1", "sem-prfe_thruster-fuel-productivity-1", "sem-prfe_thruster-oxidizer-productivity-1", "sem-prfe_tungsten-carbide-productivity-1", "sem-prfe_tungsten-plate-productivity-1", "sem-prfe_utility-science-pack-productivity-1"},
  },
}

local function fail(message) error("[mir5-competing-dynamic-gameplay] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end
local function selected()
  local active = script.active_mods
  local provider
  if active[PROVIDERS.ce.mod] == PROVIDERS.ce.version and active[PROVIDERS.pr.mod] == nil then provider = "ce"
  elseif active[PROVIDERS.pr.mod] == PROVIDERS.pr.version and active[PROVIDERS.ce.mod] == nil then provider = "pr"
  else fail("fixture requires exactly one exact dynamic provider") end
  local mir, fixture = active["more-infinite-research"], active[FIXTURE]
  local preference
  if mir == "4.7.20002" and fixture == "0.1.0" then preference = false
  elseif mir == "5.0.20000" and fixture == "0.2.0" then preference = true
  elseif mir == "5.0.20000" and fixture == "0.3.0" then preference = false
  else fail("fixture stage closure differs") end
  if active.base ~= "2.0.77" or active["space-age"] ~= "2.0.77" then fail("fixture engine closure differs") end
  local setting = settings.startup["mir-prefer-this-mod-for-competing-techs"]
  if setting == nil or setting.value ~= preference then fail("fixture preference differs") end
  return provider, PROVIDERS[provider], mir, fixture, preference
end
local function verify_and_seed_prerequisites(value, expected, label)
  local actual, count = value.prerequisites, 0
  for _ in pairs(actual) do count = count + 1 end
  if count ~= #expected then fail(label .. " direct prerequisite count changed") end
  for _, name in ipairs(expected) do
    local prerequisite = actual[name]
    if prerequisite == nil or prerequisite.name ~= name or type(prerequisite.research_recursive) ~= "function" then
      fail(label .. " direct prerequisite changed: " .. name)
    end
    prerequisite.research_recursive()
  end
end
local function status(force, name, recipe)
  local value = technology(force, name)
  local item = force.recipes[recipe]
  if item == nil then fail("productivity recipe is absent: " .. recipe) end
  return {level=value.level, researched=value.researched, enabled=value.enabled,
    visible=value.visible_when_disabled, maximum=value.prototype.max_level,
    saved_progress=value.saved_progress, bonus=item.productivity_bonus}
end
local function copy_status(value)
  return {level=value.level, researched=value.researched, enabled=value.enabled, visible=value.visible,
    maximum=value.maximum, saved_progress=value.saved_progress, bonus=value.bonus}
end
local function assert_status(force, config, expected, label)
  local actual = status(force, config.target, config.recipe)
  for _, key in ipairs({"level", "researched", "enabled", "visible", "maximum"}) do
    if actual[key] ~= expected[key] then fail(label .. " target " .. key .. " differs") end
  end
  if not close(actual.bonus, expected.bonus) or not close(actual.saved_progress, expected.saved_progress) then
    fail(label .. " target bonus/progress differs")
  end
  return actual
end
local function queue_snapshot(force)
  local queue = {}
  for index, value in ipairs(force.research_queue or {}) do queue[index] = value.name end
  return {current=force.current_research and force.current_research.name or false, queue=queue,
    progress=force.research_progress}
end
local function copy_queue(value)
  local queue = {}
  for index, name in ipairs(value.queue) do queue[index] = name end
  return {current=value.current, queue=queue, progress=value.progress}
end
local function assert_queue(force, expected, label)
  local actual = queue_snapshot(force)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue or not close(actual.progress, expected.progress) then
    fail(label .. " queue/progress differs")
  end
  for index, name in ipairs(expected.queue) do
    if actual.queue[index] ~= name then fail(label .. " queue changed at " .. tostring(index)) end
  end
  return actual
end
local function assert_all_rows(force, config, enabled, visible, label)
  for _, name in ipairs(config.ids) do
    local value = technology(force, name)
    if value.prototype.max_level ~= UINT32_MAX then fail(label .. " max level differs: " .. name) end
    if enabled ~= nil and value.enabled ~= enabled then fail(label .. " enabled differs: " .. name) end
    if visible ~= nil and value.visible_when_disabled ~= visible then fail(label .. " visibility differs: " .. name) end
  end
end
local function capture_initial_levels(force, config)
  local rows, by_id = {}, {}
  for index, name in ipairs(config.ids) do
    local value = technology(force, name)
    local row = {id=name, technology_level=value.level, prototype_level=value.prototype.level}
    rows[index], by_id[name] = row, row
  end
  return rows, by_id
end
local function inventory(lab)
  local value = lab and lab.valid ~= false and lab.get_inventory(defines.inventory.lab_input)
  if value == nil then fail("real lab input inventory is absent") end
  return value
end
local function assert_acceleration(value, config)
  if value.research_unit_count ~= 1 or not close(value.research_unit_energy, 60) then
    fail("fixture did not reduce only the captured provider count/time")
  end
  local ingredients, seen = value.research_unit_ingredients, {}
  if #ingredients ~= #config.science then fail("native science count differs") end
  for _, ingredient in ipairs(ingredients) do seen[ingredient.name] = (seen[ingredient.name] or 0) + ingredient.amount end
  for _, name in ipairs(config.science) do if seen[name] ~= 1 then fail("native science differs: " .. name) end end
end
local function fill(lab, config)
  local input = inventory(lab)
  for _, item in ipairs(config.science) do
    if input.insert{name=item, count=4} ~= 4 then fail("could not insert native science " .. item) end
  end
  lab.energy = 1000000000
  if lab.active == false or lab.energy <= 0 then fail("lab cannot consume native science") end
end
local function freeze(state)
  state.lab.active, state.lab.energy = false, 0
  inventory(state.lab).clear()
end
local function snapshot_player(state, config)
  state.player_snapshot = copy_status(status(game.forces.player, config.target, config.recipe))
  state.player_queue = copy_queue(queue_snapshot(game.forces.player))
end
local function assert_frozen(state, config)
  local lab = state.lab
  if lab == nil or lab.valid == false or lab.active ~= false or lab.energy ~= 0 then
    fail("source lab was not frozen before successor preference")
  end
  local input = inventory(lab)
  for _, item in ipairs(config.science) do
    if input.get_item_count(item) ~= 0 then fail("source lab retained science after freeze: " .. item) end
  end
end
local function assert_foreign_and_detached(state, config)
  local foreign = game.forces[state.foreign_force_index]
  local detached = game.forces[state.detached_force_index]
  if foreign == nil or detached == nil then fail("foreign/detached force is absent") end
  assert_all_rows(foreign, config, false, true, "foreign")
  local foreign_probe = technology(foreign, PROBE)
  if foreign_probe.enabled ~= true then fail("foreign probe changed") end
  assert_queue(foreign, state.foreign_queue, "foreign")
  local paused = technology(detached, config.target)
  if paused.enabled ~= true or paused.visible_when_disabled ~= false or not close(paused.saved_progress, 0.27) then
    fail("detached partial target differs")
  end
  if detached.current_research ~= nil or #(detached.research_queue or {}) ~= 0 then fail("detached partial target was queued") end
end
local function assert_source_witness(state, config)
  if state.source_mir ~= "4.7.20002" or state.fixture_version ~= "0.1.0"
      or state.actual_lab_completions ~= 1 or state.milestone ~= "one-native-dynamic-lab"
      or state.prerequisite_seeding ~= "captured-direct-prerequisites"
      or state.predecessor ~= config.predecessor then fail("source completion witness differs") end
end
local function assert_source(state, config)
  if state.phase ~= "source-completed" then fail("source completion phase differs") end
  assert_source_witness(state, config)
  assert_all_rows(game.forces.player, config, true, false, "source player")
  assert_status(game.forces.player, config, {level=2, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, saved_progress=0, bonus=state.player_bonus}, "source player")
  assert_queue(game.forces.player, state.player_queue, "source player")
  if state.player_queue.current ~= config.target or not close(state.player_queue.progress, 0.27)
      or not close(technology(game.forces.player, PROBE).saved_progress, 0.42) then
    fail("source current/inactive progress witness differs")
  end
  assert_foreign_and_detached(state, config)
  assert_frozen(state, config)
end
local function assert_preferred(state, config)
  if state.phase ~= "source-completed" and state.phase ~= "prefer-mir-completed" then fail("preferred source witness differs") end
  assert_source_witness(state, config)
  assert_all_rows(game.forces.player, config, false, true, "preferred player")
  assert_status(game.forces.player, config, {level=2, researched=false, enabled=false, visible=true,
    maximum=UINT32_MAX, saved_progress=state.current_target_progress, bonus=state.player_bonus}, "preferred player")
  assert_queue(game.forces.player, {current=PROBE, queue={PROBE}, progress=0.42}, "preferred player")
  assert_foreign_and_detached(state, config)
end
local function assert_released(state, config)
  if state.phase ~= "prefer-mir-completed" and state.phase ~= "prefer-foreign-completed" then fail("released source witness differs") end
  assert_source_witness(state, config)
  assert_all_rows(game.forces.player, config, true, false, "released player")
  assert_status(game.forces.player, config, {level=2, researched=false, enabled=true, visible=false,
    maximum=UINT32_MAX, saved_progress=state.current_target_progress, bonus=state.player_bonus}, "released player")
  assert_queue(game.forces.player, {current=PROBE, queue={PROBE}, progress=0.42}, "released player")
  assert_foreign_and_detached(state, config)
end
local function marker(stage, state, config)
  local target = status(game.forces.player, config.target, config.recipe)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    stage=stage, case="f200-competing-dynamic-" .. state.provider .. "-continuity", status="passed",
    qualification="native-runner-readback-required", witnesses={provider=state.provider, target=config.target,
      actual_lab_completions=state.actual_lab_completions, target_level=target.level,
      target_bonus=target.bonus, target_enabled=target.enabled, target_saved_progress=target.saved_progress,
      named_predecessor=config.predecessor, direct_prerequisite_count=#config.prerequisites,
      player_queue=queue_snapshot(game.forces.player).queue, foreign_disabled=true,
      detached_partial_progress=technology(game.forces[state.detached_force_index], config.target).saved_progress,
      ownership_count=#config.ids, successor_output_excluded=target.bonus == state.player_bonus,
      on_load_read_only=stage == "reload"},
  }))
end

script.on_init(function()
  local provider, config, mir, fixture, preference = selected()
  if mir ~= "4.7.20002" or fixture ~= "0.1.0" or preference ~= false then fail("source stage differs") end
  if storage[KEY] ~= nil then fail("source fixture storage already exists") end
  game.speed = 16
  local player = game.forces.player
  player.enable_all_prototypes()
  assert_all_rows(player, config, true, false, "source player")
  local target = technology(player, config.target)
  local initial_levels, initial_by_id = capture_initial_levels(player, config)
  log("[MIR5_DYNAMIC_INITIAL_LEVELS] " .. helpers.table_to_json({
    provider=provider, target=config.target, levels=initial_levels,
  }))
  if config.predecessor ~= false and config.prerequisites[1] ~= config.predecessor then
    fail("captured named predecessor disposition differs")
  end
  verify_and_seed_prerequisites(target, config.prerequisites, "captured target")
  if target.researched then fail("captured target was researched before source lab") end
  local before = status(player, config.target, config.recipe)
  local foreign = game.create_force(FOREIGN)
  local detached = game.create_force(DETACHED)
  for _, force in ipairs({foreign, detached}) do force.enable_all_prototypes() end
  local foreign_target = technology(foreign, config.target)
  verify_and_seed_prerequisites(foreign_target, config.prerequisites, "captured foreign target")
  for _, name in ipairs(config.ids) do
    local value = technology(foreign, name)
    value.enabled, value.visible_when_disabled = false, true
  end
  local foreign_probe = technology(foreign, PROBE)
  verify_and_seed_prerequisites(foreign_probe, PROBE_PREREQUISITES, "captured braking probe")
  if foreign_probe.researched then fail("foreign probe was already researched") end
  foreign_probe.saved_progress = 0.42
  foreign.research_queue = {foreign_probe}
  local foreign_queue = assert_queue(foreign, {current=PROBE, queue={PROBE}, progress=0.42}, "foreign setup")
  local detached_target = technology(detached, config.target)
  detached_target.saved_progress = 0.27
  local lab = game.surfaces[1].create_entity{name="lab", position={0, 0}, force=player}
  if lab == nil or lab.valid == false then fail("could not create real lab") end
  assert_acceleration(technology(player, config.target), config)
  local state = {provider=provider, source_mir=mir, fixture_version=fixture, predecessor=config.predecessor,
    prerequisite_seeding="captured-direct-prerequisites", phase="await-source-lab", actual_lab_completions=0,
    milestone="prerequisites-seeded", player_start_bonus=before.bonus, player_bonus=before.bonus,
    initial_levels=initial_levels, target_initial=initial_by_id[config.target],
    foreign_force_index=foreign.index, detached_force_index=detached.index, foreign_queue=foreign_queue,
    lab=lab, deadline_tick=game.tick + DEADLINE}
  storage[KEY] = state
  fill(lab, config)
  if player.add_research(target) ~= true then fail("could not queue captured native target") end
  assert_queue(player, {current=config.target, queue={config.target}, progress=0}, "source target")
end)

script.on_event(defines.events.on_research_finished, function(event)
  local state = storage[KEY]
  if type(state) ~= "table" or state.phase ~= "await-source-lab" or event.research == nil
      or event.research.force ~= game.forces.player then return end
  local config = PROVIDERS[state.provider]
  if event.research.name ~= config.target then return end
  state.actual_lab_completions = state.actual_lab_completions + 1
  if state.actual_lab_completions ~= 1 then fail("fixture completed more than one target level") end
  state.phase = "await-source-freeze"
end)

script.on_configuration_changed(function()
  local state = storage[KEY]
  local provider, config, mir, fixture, preference = selected()
  if type(state) ~= "table" or state.provider ~= provider or mir ~= "5.0.20000" then fail("successor source identity differs") end
  loaded_snapshot, reload_logged = nil, false
  if fixture == "0.2.0" and preference == true then
    assert_preferred(state, config)
    state.phase, pending_save = "prefer-mir-completed", true
  elseif fixture == "0.3.0" and preference == false then
    assert_released(state, config)
    state.phase, pending_save = "prefer-foreign-completed", true
  else fail("successor stage differs") end
end)

script.on_load(function()
  local state = storage[KEY]
  if type(state) == "table" and (state.phase == "source-completed" or state.phase == "prefer-mir-completed"
      or state.phase == "prefer-foreign-completed") and type(state.player_snapshot) == "table"
      and type(state.player_queue) == "table" then
    loaded_snapshot = {phase=state.phase, player=copy_status(state.player_snapshot),
      queue=copy_queue(state.player_queue), labs=state.actual_lab_completions}
  else loaded_snapshot = nil end
  reload_logged, pending_save = false, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then return end
  local config = PROVIDERS[state.provider]
  if pending_save then
    if state.phase == "prefer-mir-completed" then assert_preferred(state, config)
    elseif state.phase == "prefer-foreign-completed" then assert_released(state, config)
    else fail("unexpected successor save phase") end
    snapshot_player(state, config)
    marker("initial", state, config); game.server_save(SAVE); pending_save = false; return
  end
  if loaded_snapshot and not reload_logged then
    if loaded_snapshot.phase == "source-completed" then assert_source(state, config)
    elseif loaded_snapshot.phase == "prefer-mir-completed" then assert_preferred(state, config)
    elseif loaded_snapshot.phase == "prefer-foreign-completed" then assert_released(state, config)
    else fail("cold reload phase differs") end
    assert_status(game.forces.player, config, loaded_snapshot.player, "cold reload player")
    assert_queue(game.forces.player, loaded_snapshot.queue, "cold reload player")
    if state.actual_lab_completions ~= loaded_snapshot.labs then fail("cold reload changed lab count") end
    marker("reload", state, config); reload_logged = true; return
  end
  if state.phase == "source-completed" or state.phase == "prefer-mir-completed" or state.phase == "prefer-foreign-completed" then return end
  if game.tick > state.deadline_tick then fail("fixture did not complete its native target lab") end
  if state.phase == "await-source-freeze" then
    local player = game.forces.player
    local target = status(player, config.target, config.recipe)
    if target.level ~= 2 or target.researched ~= false or not close(target.bonus, state.player_start_bonus + 0.1) then
      local initial = state.target_initial
      fail("native target completion/effect differs: id=" .. config.target
        .. " expected_level=2 actual_level=" .. tostring(target.level)
        .. " prototype_level=" .. tostring(technology(player, config.target).prototype.level)
        .. " initial_level=" .. tostring(initial and initial.technology_level)
        .. " initial_prototype_level=" .. tostring(initial and initial.prototype_level)
        .. " baseline_bonus=" .. tostring(state.player_start_bonus)
        .. " actual_bonus=" .. tostring(target.bonus)
        .. " expected_bonus=" .. tostring(state.player_start_bonus + 0.1))
    end
    freeze(state)
    local target_technology, probe = technology(player, config.target), technology(player, PROBE)
    if probe.researched then fail("unrelated probe was researched by captured predecessor seeding") end
    target_technology.saved_progress, probe.saved_progress = 0.27, 0.42
    player.research_queue = {target_technology, probe}
    player.research_progress = 0.27
    state.player_bonus, state.current_target_progress = target.bonus, 0.27
    state.player_queue = assert_queue(player, {current=config.target, queue={config.target, PROBE}, progress=0.27}, "source saved queue")
    state.milestone, state.phase = "one-native-dynamic-lab", "source-completed"
    assert_source(state, config)
    snapshot_player(state, config)
    marker("initial", state, config); game.server_save(SAVE)
  elseif state.phase == "await-source-lab" then state.lab.energy = 1000000000 end
end)
