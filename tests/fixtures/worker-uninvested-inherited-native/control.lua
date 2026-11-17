-- Scenario (__level__) actor. It is embedded while the fresh published473
-- world is created and remains byte-identical through the published11 and
-- candidate loads. It never reads MIR's private storage.
local KEY = "mir_worker_uninvested_inherited_native"
local CANONICAL = "worker-robots-storage-4"
local OWNER = "mir-worker-storage-default-4"
local DEBIT = "mir-worker-storage-head-4"
local INERT = "mir-worker-uninvested-inherited-addition"
local LAB_FORCE = "mir-worker-uninvested-lab"
local LAB_NAME = "lab"
local BASE_WORKER_BONUS = 3
local SCENARIO_BONUS_DELTA = 4.25
local SCENARIO_LAB_SPEED = 3600
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "utility-science-pack"}
local cold_loaded = false

local function check(value, reason)
  if not value then error("[mir-worker-uninvested-inherited-native] " .. reason, 2) end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function active_snapshot()
  local result = {}
  for name, version in pairs(script.active_mods) do result[name] = version end
  return result
end

local function tuple()
  local base, mir = script.active_mods.base, script.active_mods["more-infinite-research"]
  if base == "2.0.77" then
    return {id = "f200", base = base, source = "4.7.20003", inherited = "5.0.20011",
      negative = "5.0.20016", candidate = "5.0.20017"}
  end
  if base == "2.1.24" then
    return {id = "f210", base = base, source = "4.7.21003", inherited = "5.0.21011",
      negative = "5.0.21016", candidate = "5.0.21017"}
  end
  check(false, "unsupported Base tuple " .. tostring(base) .. "/" .. tostring(mir))
end

local function exact_active(expected)
  local seen = {}
  for name, version in pairs(script.active_mods) do
    check(type(name) == "string" and type(version) == "string" and expected[name] == version,
      "unexpected active mod " .. tostring(name))
    seen[name] = true
  end
  for name in pairs(expected) do check(seen[name], "missing active mod " .. name) end
end

local function changes(event)
  check(type(event) == "table" and type(event.mod_changes) == "table"
    and type(event.mod_startup_settings_changed) == "boolean", "configuration event is malformed")
  local rows = {}
  for name, row in pairs(event.mod_changes) do
    check(type(name) == "string" and type(row) == "table", "configuration row is malformed")
    check((row.old_version == nil or type(row.old_version) == "string")
      and (row.new_version == nil or type(row.new_version) == "string"), "configuration version is malformed")
    rows[name] = {old_version = row.old_version, new_version = row.new_version}
  end
  return rows
end

local function exact_changes(rows, expected)
  for name, row in pairs(rows) do
    local wanted = expected[name]
    check(wanted ~= nil and row.old_version == wanted.old_version and row.new_version == wanted.new_version,
      "unexpected configuration row " .. name)
  end
  for name in pairs(expected) do check(rows[name] ~= nil, "missing configuration row " .. name) end
end

local function queue_names(force)
  local result = {}
  for _, technology in ipairs(force.research_queue or {}) do result[#result + 1] = technology.name end
  return result
end

local function occurrences(force, id)
  local count = force.current_research and force.current_research.name == id and 1 or 0
  for _, name in ipairs(queue_names(force)) do if name == id then count = count + 1 end end
  return count
end

local function row(force, id)
  local technology = force.technologies[id]
  return technology and {level = technology.level, researched = technology.researched, enabled = technology.enabled,
    visible = technology.visible_when_disabled, saved_progress = technology.saved_progress,
    occurrences = occurrences(force, id)} or false
end

local function force_frame(force)
  return {index = force.index, bonus = force.worker_robots_storage_bonus,
    laboratory_speed = force.laboratory_speed_modifier, current = force.current_research and force.current_research.name or false,
    progress = force.research_progress, queue = queue_names(force), canonical = row(force, CANONICAL),
    owner = row(force, OWNER), debit = row(force, DEBIT), automation = row(force, "automation"),
    logistics = row(force, "logistics"), steel_processing = row(force, "steel-processing")}
end

local function unrelated_frame(force)
  local steel_processing = force.technologies["steel-processing"]
  return {bonus = force.worker_robots_storage_bonus, laboratory_speed = force.laboratory_speed_modifier,
    current = force.current_research and force.current_research.name or false, progress = force.research_progress,
    queue = queue_names(force), steel_processing_saved = steel_processing and steel_processing.saved_progress or false}
end

local function frames()
  local result, count = {}, 0
  for name, force in pairs(game.forces) do result[name] = force_frame(force); count = count + 1 end
  check(count > 0 and count <= 16, "force roster is unavailable or unbounded")
  return result
end

-- Standard labs are not required to expose the get-by-unit-number prototype
-- flag.  This scenario owns an exact fixed placement, so its retained entity
-- is located through that placement and then authenticated by unit and force.
local function saved_lab()
  local surface = game.surfaces[1]
  return surface and surface.find_entity and surface.find_entity(LAB_NAME, {0, 0}) or false
end

local function checked_saved_lab(state, force)
  check(type(state.setup.lab_unit) == "number", "saved source lab unit is unavailable")
  local lab = saved_lab()
  check(lab ~= nil and lab ~= false, "saved source lab entity is unavailable")
  check(lab.valid == true, "saved source lab entity is invalid")
  check(lab.unit_number == state.setup.lab_unit, "saved source lab unit differs")
  check(lab.name == LAB_NAME, "saved source lab name differs")
  check(lab.force and lab.force.index == force.index and lab.force.name == force.name,
    "saved source lab force differs")
  return lab
end

-- This is observational only.  The retained source lab is scenario-owned
-- setup, so an entity change must be diagnosed before the ordinary-research
-- leg considers changing any of its fields.
local function lab_entity_frame()
  local state = storage[KEY]
  local lookup_unit = state and state.setup and state.setup.lab_unit or false
  local entity = saved_lab()
  local result = {lookup_unit = lookup_unit, exists = entity ~= false and entity ~= nil,
    valid = entity and entity.valid == true or false, unit_number = false, name = false,
    force = {index = false, name = false}, same_force = false, disabled_by_script = false, is_updatable = false,
    energy = false, input_inventory = {}}
  if not result.valid then return result end
  result.unit_number = entity.unit_number or false
  result.name = entity.name or false
  result.force = {index = entity.force and entity.force.index or false,
    name = entity.force and entity.force.name or false}
  result.same_force = entity.force == game.forces[LAB_FORCE]
  result.disabled_by_script = entity.disabled_by_script == true
  result.is_updatable = entity.is_updatable == true
  result.energy = entity.energy or false
  local inventory = entity.get_inventory and entity.get_inventory(defines.inventory.lab_input) or false
  for _, name in ipairs(PACKS) do
    result.input_inventory[name] = inventory and inventory.get_item_count and inventory.get_item_count(name) or false
  end
  return result
end

local function marker(name, event)
  local state = storage[KEY]
  local target = tuple()
  local terminal = name == "candidate-saved" or name == "cold"
  local row = {schema = 1, kind = "MIRWorkerUninvestedInheritedScenarioV1", stage = name,
    status = terminal and "passed" or "observed", phase = state.phase, trigger = state.trigger or false,
    tick = game.tick, target = {id = target.id, family = target.id, base = target.base, source = target.source,
      inherited = target.inherited, negative = target.negative, candidate = target.candidate}, active_mods = active_snapshot(), forces = frames(), configuration = event and {
      startup_changed = event.mod_startup_settings_changed, mod_changes = changes(event)} or false,
    setup = copy(state.setup), restoration = copy(state.restoration) or false, ordinary = copy(state.ordinary),
    lab_entity = lab_entity_frame()}
  local text = helpers.table_to_json(row)
  helpers.write_file("worker-uninvested/" .. name .. ".json", text, false)
  log("[MIR_WORKER_UNINVESTED] " .. text)
end

local function assert_empty_canonical(force)
  local value = row(force, CANONICAL)
  check(value and value.level == 4 and value.researched == false and value.saved_progress == 0
    and value.occurrences == 0, "canonical worker4 has prior work for force " .. force.name)
end

local function assert_all_empty_canonical()
  for _, force in pairs(game.forces) do assert_empty_canonical(force) end
end

local function assert_base_worker_prerequisites(force)
  for level = 1, 3 do
    local name = "worker-robots-storage-" .. level
    local technology = force.technologies[name]
    local prototype = prototypes and prototypes.technology and prototypes.technology[name]
    local effects = prototype and prototype.effects
    local effect = effects and #effects == 1 and effects[1]
    check(technology and technology.level == level and technology.researched == true
      and technology.saved_progress == 0 and occurrences(force, name) == 0
      and effect and effect.type == "worker-robot-storage" and effect.modifier == 1,
      "Base worker prerequisite changed before scenario restoration")
  end
end

local function restore_scenario_lab_before_mir(event, stage)
  local state, force = storage[KEY], game.forces[LAB_FORCE]
  check(stage == "published11" or stage == "candidate", "scenario restoration stage is invalid")
  check(state and state.setup and force, "scenario source restoration is unavailable")
  assert_all_empty_canonical()
  assert_base_worker_prerequisites(force)
  local bonus, speed = force.worker_robots_storage_bonus, force.laboratory_speed_modifier
  state.restoration = {role = "scenario-lab-bonus-and-speed", stage = stage, baseline_bonus = BASE_WORKER_BONUS,
    bonus_delta = SCENARIO_BONUS_DELTA, speed_delta = SCENARIO_LAB_SPEED,
    engine_bonus = bonus, engine_speed = speed,
    disposition = bonus == BASE_WORKER_BONUS and speed == 0 and "restore"
      or bonus == BASE_WORKER_BONUS + SCENARIO_BONUS_DELTA and speed == SCENARIO_LAB_SPEED and "unchanged"
      or "refuse"}
  marker(stage == "published11" and "engine-before-scenario-restoration"
    or "candidate-engine-before-scenario-restoration", event)
  if bonus == BASE_WORKER_BONUS and speed == 0 then
    force.worker_robots_storage_bonus = bonus + SCENARIO_BONUS_DELTA
    force.laboratory_speed_modifier = speed + SCENARIO_LAB_SPEED
  else
    check(bonus == BASE_WORKER_BONUS + SCENARIO_BONUS_DELTA and speed == SCENARIO_LAB_SPEED,
      "engine changed scenario-owned lab state before MIR")
  end
  check(force.worker_robots_storage_bonus == BASE_WORKER_BONUS + SCENARIO_BONUS_DELTA
    and force.laboratory_speed_modifier == SCENARIO_LAB_SPEED,
    "scenario lab restoration did not reach its declared frame")
  if state.restoration.disposition == "restore" then state.restoration.disposition = "restored" end
  state.restoration_history = state.restoration_history or {}
  state.restoration_history[stage] = copy(state.restoration)
end

local function equal(value, expected, path)
  path = path or "$"
  check(type(value) == type(expected), "frame type differs at " .. path)
  if type(value) == "table" then
    for key, item in pairs(expected) do equal(value[key], item, path .. "/" .. tostring(key)) end
    for key in pairs(value) do check(expected[key] ~= nil, "frame extra at " .. path .. "/" .. tostring(key)) end
  elseif type(value) == "number" then
    check(math.abs(value - expected) < 1e-9, "frame number differs at " .. path)
  else check(value == expected, "frame value differs at " .. path) end
end

local function setup_source()
  local player = game.forces.player
  check(player and player.technologies["automation-science-pack"] and player.technologies.automation
    and player.technologies.logistics
    and player.technologies["steel-processing"],
    "Base unrelated technologies are unavailable")
  assert_all_empty_canonical()
  player.technologies["automation-science-pack"].researched = true
  player.research_queue = {player.technologies.automation, player.technologies.logistics}
  player.research_progress = .27
  player.technologies["steel-processing"].saved_progress = .31
  local lab_force = game.forces[LAB_FORCE] or game.create_force(LAB_FORCE)
  check(lab_force and lab_force.technologies, "lab force is unavailable")
  for level = 1, 3 do
    local technology = lab_force.technologies["worker-robots-storage-" .. level]
    check(technology ~= nil, "worker prerequisite is unavailable")
    technology.researched = true -- explicitly labelled source setup, never C4.
  end
  assert_empty_canonical(lab_force)
  assert_base_worker_prerequisites(lab_force)
  check(lab_force.worker_robots_storage_bonus == BASE_WORKER_BONUS and lab_force.laboratory_speed_modifier == 0,
    "Base worker/source laboratory baseline differs")
  lab_force.worker_robots_storage_bonus = lab_force.worker_robots_storage_bonus + SCENARIO_BONUS_DELTA
  lab_force.laboratory_speed_modifier = lab_force.laboratory_speed_modifier + SCENARIO_LAB_SPEED
  local surface = game.surfaces.nauvis or game.surfaces[1]
  check(surface and type(surface.create_entity) == "function", "source surface is unavailable")
  local lab = surface.create_entity{name = LAB_NAME, position = {0, 0}, force = lab_force}
  check(lab and lab.valid, "source lab creation failed")
  lab.disabled_by_script = true
  local force_count = 0
  for _ in pairs(game.forces) do force_count = force_count + 1 end
  check(force_count == 4, "source scenario requires the three Base forces and one lab force")
  return {player = unrelated_frame(player), lab = unrelated_frame(lab_force), lab_unit = lab.unit_number,
    administrative_setup = {player_current = "automation", player_queue = {"automation", "logistics"},
      player_detached = {technology = "steel-processing", saved_progress = .31}, lab_force = LAB_FORCE,
      base_worker_bonus = BASE_WORKER_BONUS, foreign_bonus_delta = SCENARIO_BONUS_DELTA,
      foreign_bonus = 7.25, laboratory_speed = SCENARIO_LAB_SPEED, researched_worker_prerequisites = {1, 2, 3}}}
end

local function verify_setup(completed)
  local state = storage[KEY]
  equal(unrelated_frame(game.forces.player), state.setup.player, "player")
  local expected = copy(state.setup.lab)
  if completed then expected.bonus = 8.25 end
  equal(unrelated_frame(game.forces[LAB_FORCE]), expected, "lab-force")
  if not completed then assert_all_empty_canonical() end
end

local function pristine_owner(force)
  local owner, debit = row(force, OWNER), row(force, DEBIT)
  check(owner and owner.level == 4 and owner.researched == false and owner.saved_progress == 0
    and owner.occurrences == 0 and owner.enabled == true and owner.visible == false,
    "ordinary default owner is not pristine")
  check(debit and debit.level == 4 and debit.researched == false and debit.saved_progress == 0
    and debit.occurrences == 0 and debit.enabled == false and debit.visible == false,
    "default head debit is not pristine")
end

local function pristine_owners()
  for _, force in pairs(game.forces) do pristine_owner(force) end
end

local function feed_ordinary_lab()
  local state, force = storage[KEY], game.forces[LAB_FORCE]
  local lab = checked_saved_lab(state, force)
  check(not lab.disabled_by_script, "ordinary lab stopped before completion")
  local inventory = lab.get_inventory(defines.inventory.lab_input)
  lab.energy = 1000000000 -- owned test-power stimulus; native lab energy remains bounded by its buffer.
  for _, name in ipairs(PACKS) do
    local feed = state.ordinary.feed[name]
    local present = inventory.get_item_count(name)
    local consumed = feed.supplied - present
    check(consumed >= feed.consumed and consumed <= 675, "ordinary science changed unexpectedly")
    feed.consumed = consumed
    if feed.supplied < 675 then
      local added = inventory.insert{name = name, count = math.min(100, 675 - feed.supplied)}
      check(type(added) == "number" and added >= 0 and added <= 100, "ordinary lab insert result is invalid")
      feed.supplied = feed.supplied + added
    end
  end
end

local function begin_ordinary()
  local state, force = storage[KEY], game.forces[LAB_FORCE]
  -- The configuration callback has completed before this tick.  Retain the
  -- post-MIR entity facts before an invariant refusal or any ordinary-leg
  -- mutation, so an engine/MIR/entity discrepancy is not collapsed to prose.
  marker("candidate-before-ordinary-lab-check")
  local lab = checked_saved_lab(state, force)
  check(lab.disabled_by_script == true, "saved source lab disabled-by-script flag differs")
  local owner = force.technologies[OWNER]
  check(owner and owner.researched == false and owner.level == 4, "ordinary owner is unavailable")
  check(game.difficulty_settings.technology_price_multiplier == 1, "map price must remain one")
  force.research_queue = {owner}
  lab.disabled_by_script, lab.energy = false, 1000000000
  local feed = {}
  for _, name in ipairs(PACKS) do feed[name] = {supplied = 0, consumed = 0} end
  state.phase, state.ordinary = "ordinary-running", {force = force.name, feed = feed, completed = false,
    deadline = game.tick + 3600}
  marker("candidate-before-ordinary")
end

local function settle_ordinary(event)
  local state, force = storage[KEY], game.forces[LAB_FORCE]
  if not event.research or event.research.force ~= force or event.research.name ~= OWNER then return end
  check(state.phase == "ordinary-running", "ordinary completion has no issued phase")
  check(event.by_script == false, "ordinary worker completion was scripted")
  local lab = checked_saved_lab(state, force)
  local inventory, consumed = lab.get_inventory(defines.inventory.lab_input), {}
  for _, name in ipairs(PACKS) do
    local remaining = inventory.get_item_count(name)
    local feed = state.ordinary.feed[name]
    check(feed.supplied == 675 and remaining == 0, "ordinary science was not fully supplied/consumed")
    consumed[name] = feed.supplied - remaining
    check(consumed[name] == 675, "ordinary science count differs")
  end
  check(force.worker_robots_storage_bonus == 8.25, "ordinary completion did not preserve/increase foreign bonus")
  lab.disabled_by_script, lab.energy = true, 0
  state.ordinary.completed, state.ordinary.consumed, state.ordinary.by_script = true, consumed, event.by_script
  state.phase, state.pending = "ordinary-finished-pending", "ordinary-settle"
end

local function settled_owner(force)
  local owner, debit = row(force, OWNER), row(force, DEBIT)
  check(owner and owner.level == 5 and owner.researched == false and owner.saved_progress == 0
    and owner.occurrences == 0 and owner.enabled == true and owner.visible == false,
    "ordinary owner did not retain its native completed state")
  check(debit and debit.level == 5 and debit.researched == false and debit.saved_progress == 0
    and debit.occurrences == 0 and debit.enabled == false and debit.visible == false,
    "ordinary head debit did not settle")
end

local function settled_candidate()
  verify_setup(true)
  for name, force in pairs(game.forces) do
    if name == LAB_FORCE then
      local canonical = row(force, CANONICAL)
      check(canonical and canonical.level == 5 and canonical.researched == false and canonical.saved_progress == 0
        and canonical.occurrences == 0, "ordinary public canonical worker state differs")
      settled_owner(force)
    else
      assert_empty_canonical(force)
      pristine_owner(force)
    end
  end
end

script.on_init(function()
  local target = tuple()
  exact_active({base = target.base, ["more-infinite-research"] = target.source})
  check(storage[KEY] == nil, "source scenario was already initialized")
  -- Configuration ownership must finish before this scenario performs its
  -- explicitly labelled source setup or asks the server to save.
  storage[KEY] = {schema = 1, phase = "source-entry", target = target.id, pending = "source-setup"}
end)

script.on_configuration_changed(function(event)
  local state, target = storage[KEY], tuple()
  check(state and state.schema == 1 and state.target == target.id, "scenario provenance is unavailable")
  local rows = changes(event)
  if script.active_mods["more-infinite-research"] == target.inherited then
    check(state.phase == "source-saved", "published11 has no source phase")
    exact_active({base = target.base, ["more-infinite-research"] = target.inherited})
    check(event.mod_startup_settings_changed == false, "published11 source settings changed")
    exact_changes(rows, { ["more-infinite-research"] = {old_version = target.source, new_version = target.inherited} })
    restore_scenario_lab_before_mir(event, "published11")
    state.phase, state.pending = "inherited-entry", "inherited"
    marker("inherited11-before-configuration", event)
    return
  end
  local candidate_version = script.active_mods["more-infinite-research"]
  if candidate_version == target.candidate or candidate_version == target.negative then
    check(state.phase == "inherited-saved", "candidate has no inherited11 source")
    local mode
    if event.mod_startup_settings_changed == true then
      exact_active({base = target.base, ["more-infinite-research"] = candidate_version})
      exact_changes(rows, { ["more-infinite-research"] = {old_version = target.inherited, new_version = candidate_version} })
      mode = "startup-changed"
    else
      exact_active({base = target.base, ["more-infinite-research"] = candidate_version, [INERT] = "0.1.0"})
      exact_changes(rows, { ["more-infinite-research"] = {old_version = target.inherited, new_version = candidate_version},
        [INERT] = {old_version = nil, new_version = "0.1.0"}})
      mode = "added-inert"
    end
    state.trigger = mode
    if candidate_version == target.candidate then restore_scenario_lab_before_mir(event, "candidate") end
    state.phase = "candidate-entry"
    if candidate_version == target.negative then state.pending = nil else state.pending = "candidate" end
    marker("before-configuration", event)
    return
  end
  check(false, "unexpected MIR configuration version")
end)

script.on_event(defines.events.on_research_finished, settle_ordinary)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if state and state.phase == "ordinary-running" then
    check(game.tick <= state.ordinary.deadline, "ordinary worker research exceeded its bounded deadline")
    feed_ordinary_lab()
    return
  end
  if not state or not state.pending then
    if state and state.phase == "candidate-saved" and cold_loaded then
      cold_loaded = false
      settled_candidate()
      check(state.ordinary and state.ordinary.completed, "cold load has no ordinary completion")
      marker("cold")
    end
    return
  end
  local pending = state.pending
  state.pending = nil
  if pending == "source-setup" then
    check(state.phase == "source-entry", "source setup phase is invalid")
    state.setup = setup_source()
    state.phase = "source-saved"
    marker("source473-ready")
    marker("source473-saved")
    game.server_save("worker-uninvested-source473")
  elseif pending == "inherited" then
    verify_setup()
    state.phase = "inherited-saved"
    marker("inherited11-saved")
    game.server_save("worker-uninvested-inherited11")
  elseif pending == "candidate" then
    verify_setup()
    pristine_owners()
    begin_ordinary()
  elseif pending == "ordinary-settle" then
    settled_candidate()
    state.phase = "candidate-saved"
    marker("candidate-saved")
    game.server_save("worker-uninvested-candidate")
  else check(false, "unknown deferred configuration phase") end
end)

script.on_load(function()
  local state = storage[KEY]
  if state and state.phase == "candidate-saved" then cold_loaded = true end
end)
