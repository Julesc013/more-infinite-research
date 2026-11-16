-- Disposable F200/SE worker-speed cap-ten actor. It never imports MIR
-- internals: the real player's configuration/research callbacks own caps.
local M = {}

local KEY = "mir5_worker_speed_cap_ten"
local CURRENT_KEY = "mir5_worker_speed_cap_current_state"
local CURRENT_OBSERVE_KEY = "mir5_worker_speed_cap_current_observe"
local SAVE = "mir5-worker-speed-cap-ten-complete"
local CURRENT_SAVE = "mir5-worker-speed-cap-current-state-complete"
local CURRENT_OBSERVE_TOKEN = "MIR_EXPECTED_CURRENT_OBSERVE16_TRACE_COMPLETE"
local CASE = "f200-se-worker-speed-cap-ten"
local FIXTURE = "mir-fixture-mir5-worker-speed-cap-ten"
local WORKER = "worker-robots-speed-10"
local PREDECESSOR = "worker-robots-speed-9"
local DEEP_SCIENCE = "se-deep-space-science-pack-1"
local PROBE = "automation"
local AUTOMATION_SCIENCE = "automation-science-pack"
local ELECTRICITY = "electricity"
local SENTINEL = "stone-wall"
local FOREIGN_FORCE = "mir5-worker-speed-cap-ten-foreign"
local EARNED_FORCE = "mir5-worker-speed-cap-ten-earned"
local LAB = "mir-worker-speed-cap-ten-fast-lab"
local PARTIAL = 0.27
local FOREIGN_PROGRESS = 0.42
local EFFECT = 0.65
local EARNED_LEVEL = 13
local UINT32_MAX = 4294967295
local DEADLINE_TICKS = 18000
local POST_COMPLETION_HOLD_TICKS = 2
local LAB_TOP_UP_REQUEST = 200
local CURRENT_OBSERVE_MAX_EVENTS = 128
local STAGES = {
  source15 = {version = "0.4.0", cap = 0, mir = "5.0.20015"},
  ["old-negative15"] = {version = "0.5.0", cap = 10, mir = "5.0.20015"},
  successor16 = {version = "0.6.0", cap = 10, mir = "5.0.20016"},
  ["current-old15"] = {version = "0.7.0", cap = 10, mir = "5.0.20015"},
  ["current-successor16"] = {version = "0.8.0", cap = 10, mir = "5.0.20016"},
  ["current-observe16"] = {version = "0.9.0", cap = 10, mir = "5.0.20016"},
}
local CLOSURE = {
  base = "2.0.77", ["space-exploration"] = "0.7.57",
  ["aai-containers"] = "0.3.2", ["aai-industry"] = "0.6.16", ["alien-biomes"] = "0.7.4",
  ["alien-biomes-graphics"] = "0.7.1", jetpack = "0.4.17", robot_attrition = "0.6.6",
  ["shield-projector"] = "0.2.2", ["space-exploration-graphics"] = "0.7.5",
  ["space-exploration-graphics-2"] = "0.7.2", ["space-exploration-graphics-3"] = "0.7.2",
  ["space-exploration-graphics-4"] = "0.7.2", ["space-exploration-graphics-5"] = "0.7.3",
  ["space-exploration-menu-simulations"] = "0.7.4", ["space-exploration-postprocess"] = "0.7.5",
  informatron = "0.4.0", ["aai-signal-transmission"] = "0.5.3",
}
local cold_requested, cold_logged = false, false

local function fail(message) error("[mir5-worker-speed-cap-ten] " .. message) end

local function close(left, right)
  return type(left) == "number" and type(right) == "number" and math.abs(left - right) <= 0.0000001
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

local function check_closure(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown fixture stage") end
  local active = script.active_mods
  for name, version in pairs(CLOSURE) do if active[name] ~= version then fail("F200 SE closure differs: " .. name) end end
  for name in pairs(active) do
    if name ~= FIXTURE and name ~= "more-infinite-research" and CLOSURE[name] == nil then
      fail("unexpected enabled mod: " .. name)
    end
  end
  if active[FIXTURE] ~= expected.version or active["more-infinite-research"] ~= expected.mir then
    fail("fixture stage version differs")
  end
  local setting = settings.startup and settings.startup["mir-max-level-worker-robots-speed"]
  local imported = settings.startup and settings.startup["mir-settings-profile-import"]
  if type(setting) ~= "table" or setting.value ~= expected.cap or type(imported) ~= "table" or imported.value ~= "" then
    fail("fixture startup settings differ")
  end
  return expected
end

local function active_mods_snapshot()
  local active = copy(script.active_mods)
  local count = 0
  for _ in pairs(active) do count = count + 1 end
  if count ~= 20 then fail("F200 SE active mod count differs") end
  return active, count
end

local function current_observe_active_mod_tuple()
  local active = active_mods_snapshot()
  local rows = {}
  for name, version in pairs(active) do
    if type(name) ~= "string" or name == "" or type(version) ~= "string"
        or version:match("^%d+%.%d+%.%d+$") == nil then
      fail("current observe active mod identity differs")
    end
    rows[#rows + 1] = name .. "@" .. version
  end
  table.sort(rows)
  return table.concat(rows, "|")
end

local function technology(force, name)
  local value = force and force.technologies and force.technologies[name]
  if value == nil or value.valid == false or value.name ~= name then fail("technology is absent: " .. tostring(name)) end
  return value
end

local function assert_worker(value, label)
  local prototype = value.prototype
  if prototype == nil or prototype.max_level ~= UINT32_MAX then fail(label .. " worker maximum differs") end
  local effects = prototype.effects
  if type(effects) ~= "table" or #effects ~= 1 or effects[1].type ~= "worker-robot-speed"
      or not close(effects[1].modifier, EFFECT) then fail(label .. " worker effect differs") end
  local prerequisites, prerequisite_count = value.prerequisites or {}, 0
  for _ in pairs(prerequisites) do prerequisite_count = prerequisite_count + 1 end
  local predecessor, deep = prerequisites[PREDECESSOR], prerequisites[DEEP_SCIENCE]
  if prerequisite_count ~= 2 or predecessor == nil or predecessor.name ~= PREDECESSOR
      or deep == nil or deep.name ~= DEEP_SCIENCE then fail(label .. " worker direct prerequisites differ") end
  if type(value.research_unit_count) ~= "number" or value.research_unit_count <= 0
      or value.research_unit_count ~= math.floor(value.research_unit_count)
      or value.research_unit_energy ~= 3600 then
    fail(label .. " worker research-unit contract differs")
  end
  local expected = { ["automation-science-pack"] = true, ["logistic-science-pack"] = true,
    ["chemical-science-pack"] = true, ["utility-science-pack"] = true, ["space-science-pack"] = true,
    ["se-rocket-science-pack"] = true, ["se-energy-science-pack-4"] = true,
    ["se-deep-space-science-pack-1"] = true }
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    if expected[ingredient.name] ~= true or ingredient.amount ~= 1 then
      fail(label .. " worker ingredient contract differs")
    end
    expected[ingredient.name] = nil
  end
  if next(expected) ~= nil then fail(label .. " worker ingredient contract differs") end
end

local function queue_snapshot(force)
  local names = {}
  for index, value in ipairs(force.research_queue or {}) do names[index] = value.name end
  return {current = force.current_research and force.current_research.name or false,
    queue = names, progress = force.research_progress}
end

local function same_queue(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or left.current ~= right.current
      or #left.queue ~= #right.queue or not close(left.progress, right.progress) then return false end
  for index, name in ipairs(left.queue) do if right.queue[index] ~= name then return false end end
  return true
end

local function worker_snapshot(force, label)
  local value = technology(force, WORKER)
  assert_worker(value, label)
  if type(force.worker_robots_speed_modifier) ~= "number" then fail(label .. " worker bonus is absent") end
  return {level = value.level, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, saved_progress = value.saved_progress,
    bonus = force.worker_robots_speed_modifier, per_level_speed_effect = value.prototype.effects[1].modifier,
    research_unit_count = value.research_unit_count, research_unit_energy = value.research_unit_energy,
    queue = queue_snapshot(force)}
end

local function assert_player_seed(actual, label)
  if actual.level ~= 10 or actual.researched ~= false or actual.enabled ~= true or actual.visible ~= false
      or not close(actual.saved_progress, 0) or actual.queue.current ~= WORKER
      or #actual.queue.queue ~= 2 or actual.queue.queue[1] ~= WORKER or actual.queue.queue[2] ~= WORKER
      or not close(actual.queue.progress, PARTIAL) then fail(label .. " scripted player seed differs") end
end

local function assert_player_cap(actual, state, label)
  if actual.level ~= 10 or actual.researched ~= false or actual.enabled ~= true or actual.visible ~= false
      or actual.queue.current ~= WORKER or #actual.queue.queue ~= 1 or actual.queue.queue[1] ~= WORKER
      or not close(actual.queue.progress, PARTIAL) or not close(actual.bonus, state.player_bonus_before) then
    fail(label .. " cap-ten did not retain only current level-ten work")
  end
end

local function assert_foreign_cap(actual, state, label)
  if actual.level ~= 11 or actual.researched ~= false or actual.enabled ~= false or actual.visible ~= true
      or not close(actual.bonus, state.foreign_bonus) or actual.queue.current ~= PROBE
      or #actual.queue.queue ~= 1 or actual.queue.queue[1] ~= PROBE
      or not close(actual.queue.progress, FOREIGN_PROGRESS) then
    fail(label .. " foreign disabled sentinel differs")
  end
end

local function assert_foreign_seed(actual, state, label)
  if actual.level ~= 11 or actual.researched ~= false or actual.enabled ~= false or actual.visible ~= false
      or not close(actual.bonus, state.foreign_bonus) or actual.queue.current ~= PROBE
      or #actual.queue.queue ~= 1 or actual.queue.queue[1] ~= PROBE
      or not close(actual.queue.progress, FOREIGN_PROGRESS) then
    fail(label .. " foreign source sentinel differs")
  end
end

local function assert_earned_cap(actual, state, label)
  if actual.level ~= EARNED_LEVEL or actual.researched ~= false or actual.enabled ~= false or actual.visible ~= true
      or not close(actual.bonus, state.earned_bonus) or actual.queue.current ~= false or #actual.queue.queue ~= 0 then
    fail(label .. " earned-above-cap state differs")
  end
end

local function assert_earned_seed(actual, state, label)
  if actual.level ~= EARNED_LEVEL or actual.researched ~= false or actual.enabled ~= true or actual.visible ~= false
      or not close(actual.bonus, state.earned_bonus) or actual.queue.current ~= false or #actual.queue.queue ~= 0 then
    fail(label .. " earned source state differs")
  end
end

local function seed_worker_prerequisites(force, label)
  for _, name in ipairs({PREDECESSOR, DEEP_SCIENCE}) do
    local prerequisite = technology(force, name)
    prerequisite.researched, prerequisite.enabled = true, true
    if prerequisite.researched ~= true then fail(label .. " worker prerequisite could not be seeded: " .. name) end
  end
end

local force_by_index

local function assert_seeded_prerequisites(state, label)
  local player = game.forces.player
  local foreign = force_by_index(state.foreign_index, label .. " foreign")
  local earned = force_by_index(state.earned_index, label .. " earned")
  for _, name in ipairs({PREDECESSOR, DEEP_SCIENCE}) do
    if technology(player, name).researched ~= true then fail(label .. " player worker prerequisite is not researched: " .. name) end
    if technology(foreign, name).researched ~= true or technology(earned, name).researched ~= true then
      fail(label .. " witness worker prerequisite is not researched: " .. name)
    end
  end
  if technology(foreign, AUTOMATION_SCIENCE).researched ~= true then
    fail(label .. " foreign automation science prerequisite is not researched")
  end
  if technology(foreign, ELECTRICITY).researched ~= true then
    fail(label .. " foreign automation electricity prerequisite is not researched")
  end
end

force_by_index = function(index, label)
  local value = game.forces[index]
  if value == nil or value.valid == false then fail(label .. " force is absent") end
  return value
end

local function observe_all(state, label)
  local player = worker_snapshot(game.forces.player, label .. " player")
  local foreign = worker_snapshot(force_by_index(state.foreign_index, label .. " foreign"), label .. " foreign")
  local earned = worker_snapshot(force_by_index(state.earned_index, label .. " earned"), label .. " earned")
  return player, foreign, earned
end

local function feed_total(feed)
  local total = 0
  for _, count in pairs(feed or {}) do total = total + count end
  return total
end

local function lab_snapshot(state, label)
  if state.lab == nil then return {present = false, scripted_feed_total = 0, scripted_feed_by_name = {}, input_total = 0, input_by_name = {}} end
  if state.lab.valid ~= true then fail(label .. " fixture lab is absent") end
  if state.lab.disabled_by_script ~= false then fail(label .. " fixture lab was stopped") end
  local inventory = state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail(label .. " fixture lab input is absent") end
  local input_total, input_by_name = 0, {}
  for name in pairs(state.lab_feed or {}) do
    local count = inventory.get_item_count(name)
    input_total, input_by_name[name] = input_total + count, count
  end
  return {present = true, valid = true, disabled_by_script = false, unit_number = state.lab.unit_number,
    scripted_feed_total = feed_total(state.lab_feed), scripted_feed_by_name = copy(state.lab_feed),
    input_total = input_total, input_by_name = input_by_name}
end

local function marker(phase, state)
  local player, foreign, earned = observe_all(state, phase)
  local mods, active_mod_count = active_mods_snapshot()
  local snapshot = {
    case = CASE, phase = phase, fixture_stage = script.active_mods[FIXTURE],
    mir_version = script.active_mods["more-infinite-research"],
    mods = mods, active_mod_count = active_mod_count, cap = settings.startup["mir-max-level-worker-robots-speed"].value,
    per_level_speed_effect = EFFECT,
    scripted_setup = {target = WORKER, source_level = 10, current_partial = PARTIAL,
      queued_next_occurrences = 1, formula = "0.2*(2^(L-6)*1000)", research_time = 60,
      foreign_disabled = true, earned_above_cap_force = true, lab_feed = state.lab_feed ~= nil},
    ordinary_native_completion_count = state.ordinary_native_completion_count or 0,
    level_eleven_start_count = state.level_eleven_start_count or 0,
    scripted_administrative_events = copy(state.scripted_administrative_events or {}),
    ordinary = copy(state.ordinary_events or {}), ordinary_events = copy(state.ordinary_events or {}),
    pre_work = state.pre_work and copy(state.pre_work) or false,
    post_completion = state.post_completion and copy(state.post_completion) or false,
    post_completion_hold_ticks = state.post_completion_hold_ticks or 0,
    level_eleven_queue_attempt = state.level_eleven_queue_attempt and copy(state.level_eleven_queue_attempt) or false,
    lab = lab_snapshot(state, phase),
    player = player, foreign = foreign, earned_above_cap = earned,
    scripted_lab_feed = copy(state.lab_feed or {}),
    scripted_lab_post_completion_top_up = copy(state.lab_post_completion_top_up or {}),
    on_load_read_only = phase == "cold",
  }
  local body = helpers.table_to_json(snapshot)
  helpers.write_file("worker-speed-cap-ten/" .. phase .. ".json", body .. "\n", false)
  log("[MIR_WORKER_SPEED_CAP_TEN phase=" .. phase .. "] " .. body)
end

-- This snapshot is deliberately observational.  It is emitted before the
-- existing prerequisite assertion so a native diagnostic can distinguish a
-- source-state normalization from a fixture setup failure without changing
-- that assertion, queue, force, laboratory, or fixture storage.
local function prerequisite_flags(force, label)
  local values = {}
  for _, name in ipairs({PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, PROBE}) do
    local value = technology(force, name)
    values[name] = {researched = value.researched, enabled = value.enabled, level = value.level, valid = value.valid}
  end
  return values
end

local function preconditions_marker(state)
  local player, foreign, earned = observe_all(state, "preconditions")
  local mods, active_mod_count = active_mods_snapshot()
  local snapshot = {
    case = CASE, phase = "preconditions", fixture_stage = script.active_mods[FIXTURE],
    mir_version = script.active_mods["more-infinite-research"], mods = mods, active_mod_count = active_mod_count,
    source_snapshot_role = "pre-assert-configuration",
    source_state = {phase = state.phase, source_mir = state.source_mir},
    worker_frames = {player = player, foreign = foreign, earned_above_cap = earned},
    prerequisite_flags = {
      player = prerequisite_flags(game.forces.player, "preconditions player"),
      foreign = prerequisite_flags(force_by_index(state.foreign_index, "preconditions foreign"), "preconditions foreign"),
      earned_above_cap = prerequisite_flags(force_by_index(state.earned_index, "preconditions earned"), "preconditions earned"),
    },
  }
  local body = helpers.table_to_json(snapshot)
  helpers.write_file("worker-speed-cap-ten/preconditions.json", body .. "\n", false)
  log("[MIR_WORKER_SPEED_CAP_TEN phase=preconditions] " .. body)
end

local function seed_foreign(foreign)
  seed_worker_prerequisites(foreign, "foreign")
  local electricity = technology(foreign, ELECTRICITY)
  electricity.researched, electricity.enabled = true, true
  if electricity.researched ~= true then fail("foreign electricity prerequisite could not be seeded") end
  local science = technology(foreign, AUTOMATION_SCIENCE)
  science.researched, science.enabled = true, true
  local owner = technology(foreign, WORKER)
  owner.level, owner.researched = 11, false
  foreign.reset_technology_effects()
  owner.enabled, owner.visible_when_disabled = false, false
  local probe = technology(foreign, PROBE)
  probe.researched, probe.enabled = false, true
  if foreign.add_research(probe) ~= true then fail("could not queue foreign sentinel") end
  foreign.research_progress = FOREIGN_PROGRESS
  return foreign
end

local function seed_earned(earned)
  seed_worker_prerequisites(earned, "earned")
  local owner = technology(earned, WORKER)
  owner.level, owner.researched = EARNED_LEVEL, false
  earned.reset_technology_effects()
  owner.enabled, owner.visible_when_disabled = true, false
  return earned
end

local function actor_force(state, force)
  local index = force and force.index
  return type(index) == "number" and (index == state.player_force_index
    or index == state.foreign_index or index == state.earned_index)
end

local function refill_lab(state, label)
  local inventory = state.lab and state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail(label .. " fixture fast lab input is absent") end
  local owner = technology(game.forces.player, WORKER)
  assert_worker(owner, label .. " worker")
  for _, ingredient in ipairs(owner.research_unit_ingredients) do
    local inserted = inventory.insert({name = ingredient.name, count = LAB_TOP_UP_REQUEST})
    if type(inserted) ~= "number" or inserted < 0 or inserted > LAB_TOP_UP_REQUEST then
      fail(label .. " fixture lab returned an invalid accepted input count")
    end
    state.lab_feed[ingredient.name] = (state.lab_feed[ingredient.name] or 0) + inserted
    if label == "post-completion" then
      state.lab_post_completion_top_up[ingredient.name] = (state.lab_post_completion_top_up[ingredient.name] or 0) + inserted
    end
  end
end

local function create_lab(state)
  local player = game.forces.player
  local surface = game.surfaces[1]
  if surface == nil then fail("fixture surface is absent") end
  local lab = surface.create_entity({name = LAB, position = {0, 0}, force = player})
  if lab == nil or lab.valid == false then fail("fixture fast lab could not be created") end
  lab.disabled_by_script = false
  if lab.get_inventory(defines.inventory.lab_input) == nil then fail("fixture fast lab input is absent") end
  state.lab, state.lab_feed, state.lab_post_completion_top_up = lab, {}, {}
end

local function assert_feed_consumed_and_remaining(state, label)
  local inventory = state.lab and state.lab.get_inventory(defines.inventory.lab_input)
  if inventory == nil then fail("fixture fast lab input disappeared") end
  for name in pairs(state.lab_feed or {}) do
    local inserted = state.lab_feed[name]
    local remaining = inventory.get_item_count(name)
    if inserted <= remaining then fail(label .. " did not consume scripted feed: " .. name) end
    if remaining <= 0 then fail(label .. " did not retain positive scripted input: " .. name) end
  end
end

local function assert_post_completion(state, label)
  local player, foreign, earned = observe_all(state, label)
  if state.level_eleven_start_count ~= 0 or player.level ~= 11 or player.researched ~= false or player.enabled ~= false or player.visible ~= true
      or player.queue.current ~= false or #player.queue.queue ~= 0 or not close(player.queue.progress, 0)
      or not close(player.bonus, state.player_bonus_before + EFFECT) then
    fail(label .. " started or consumed level eleven")
  end
  assert_foreign_cap(foreign, state, label)
  assert_earned_cap(earned, state, label)
  assert_feed_consumed_and_remaining(state, label)
  return player, foreign, earned
end

local function assert_level_eleven_cannot_queue(state)
  local player = game.forces.player
  local before = queue_snapshot(player)
  local accepted = player.add_research(technology(player, WORKER))
  local after = queue_snapshot(player)
  if accepted ~= false or not same_queue(before, after) then
    fail("disabled level eleven unexpectedly entered the research queue")
  end
  state.level_eleven_queue_attempt = {accepted = false, before = before, after = after}
end

-- The current-state roles deliberately begin from the controller's ordinary
-- Base save rather than the source15 fixture save.  They observe the player
-- after the provider's configuration work, then construct only this literal
-- three-force public boundary before making the one native reset call per
-- force.  They never inspect MIR storage or invoke its lifecycle directly.
local CURRENT_FLAGS = {PREDECESSOR, DEEP_SCIENCE, AUTOMATION_SCIENCE, ELECTRICITY, PROBE}

local function current_technology_snapshot(force, name, label)
  local value = technology(force, name)
  return {name = name, researched = value.researched, enabled = value.enabled,
    visible = value.visible_when_disabled, level = value.level, valid = value.valid}
end

local function current_flags_snapshot(force, label)
  local flags = {}
  for _, name in ipairs(CURRENT_FLAGS) do flags[name] = current_technology_snapshot(force, name, label) end
  return flags
end

local function current_force_snapshot(force, label, allow_unprepared_sentinel)
  local sentinel = current_technology_snapshot(force, SENTINEL, label)
  if allow_unprepared_sentinel ~= true and sentinel.enabled ~= false then
    fail(label .. " unrelated sentinel is enabled")
  end
  return {force_index = force.index, force_name = force.name, worker = worker_snapshot(force, label),
    prerequisite_flags = current_flags_snapshot(force, label), unrelated_sentinel = sentinel}
end

local function same_current_row(left, right)
  return type(left) == "table" and type(right) == "table" and left.name == right.name
    and left.researched == right.researched and left.enabled == right.enabled and left.visible == right.visible
    and left.level == right.level and left.valid == right.valid
end

local function same_current_frame(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  local worker_left, worker_right = left.worker, right.worker
  if type(worker_left) ~= "table" or type(worker_right) ~= "table"
      or left.force_index ~= right.force_index or left.force_name ~= right.force_name
      or worker_left.level ~= worker_right.level or worker_left.researched ~= worker_right.researched
      or worker_left.enabled ~= worker_right.enabled or worker_left.visible ~= worker_right.visible
      or not close(worker_left.saved_progress, worker_right.saved_progress)
      or not close(worker_left.bonus, worker_right.bonus)
      or not close(worker_left.per_level_speed_effect, worker_right.per_level_speed_effect)
      or worker_left.research_unit_count ~= worker_right.research_unit_count
      or worker_left.research_unit_energy ~= worker_right.research_unit_energy
      or not same_queue(worker_left.queue, worker_right.queue) then return false end
  if not same_current_row(left.unrelated_sentinel, right.unrelated_sentinel) then return false end
  for _, name in ipairs(CURRENT_FLAGS) do
    if not same_current_row(left.prerequisite_flags[name], right.prerequisite_flags[name]) then return false end
  end
  return true
end

local function same_current_support_rows(left, right)
  if not same_current_row(left.unrelated_sentinel, right.unrelated_sentinel) then return false end
  for _, name in ipairs(CURRENT_FLAGS) do
    if not same_current_row(left.prerequisite_flags[name], right.prerequisite_flags[name]) then return false end
  end
  return true
end

local function current_emit(phase, snapshot)
  local body = helpers.table_to_json(snapshot)
  helpers.write_file("worker-speed-cap-ten/current-" .. phase .. ".json", body .. "\n", false)
  log("[MIR_WORKER_SPEED_CAP_TEN phase=current-" .. phase .. "] " .. body)
end

local current_admin_intent

local function current_header(phase, stage)
  local mods, active_mod_count = active_mods_snapshot()
  return {case = CASE, phase = "current-" .. phase, role = "reduced-synthetic-current-state-reset-event",
    fixture_stage = script.active_mods[FIXTURE], mir_version = script.active_mods["more-infinite-research"],
    mods = mods, active_mod_count = active_mod_count, cap = settings.startup["mir-max-level-worker-robots-speed"].value,
    stage = stage, target = WORKER, per_level_speed_effect = EFFECT,
    formula = "0.2*(2^(L-6)*1000)", research_time = 60, admin_intent = current_admin_intent()}
end

local function current_named_forces(label)
  local player = game.forces.player
  local foreign = game.forces[FOREIGN_FORCE]
  local earned = game.forces[EARNED_FORCE]
  if player == nil or player.valid == false or foreign == nil or foreign.valid == false or earned == nil or earned.valid == false then
    fail(label .. " current-state named forces are absent")
  end
  return player, foreign, earned
end

local function current_provider_marker(stage)
  local player_force, foreign_force, earned_force = current_named_forces("current provider")
  local snapshot = current_header("provider", stage)
  snapshot.snapshot_role = "post-provider-normalization-before-fixture-admin"
  snapshot.source_base = {identity = "controller-bound-A0-base-input-only",
    fixture_source_phase = "not-read-no-continuation-precondition"}
  snapshot.player = current_force_snapshot(player_force, "current provider player", true)
  snapshot.foreign = current_force_snapshot(foreign_force, "current provider foreign", true)
  snapshot.earned_above_cap = current_force_snapshot(earned_force, "current provider earned", true)
  current_emit("provider", snapshot)
end

current_admin_intent = function()
  local function player_flags()
    return {worker_predecessor = true, deep_science = true, automation_science = false,
      electricity = false, automation = false}
  end
  local foreign_flags = {worker_predecessor = true, deep_science = true, automation_science = true,
    electricity = true, automation = false}
  return {
    player = {worker = {level = 10, researched = false, enabled = true, queue = {WORKER, WORKER}, progress = PARTIAL},
      prerequisites = player_flags()},
    foreign = {worker = {level = 11, researched = false, enabled = true}, queue = {PROBE}, progress = FOREIGN_PROGRESS,
      prerequisites = foreign_flags},
    earned_above_cap = {worker = {level = EARNED_LEVEL, researched = false, enabled = true, queue = {}},
      prerequisites = player_flags()},
    unrelated_sentinel = {name = SENTINEL, enabled = false},
  }
end

local function set_current_technology(force, name, researched, enabled, label)
  local value = technology(force, name)
  value.researched, value.enabled, value.visible_when_disabled = researched, enabled, false
  if value.researched ~= researched or value.enabled ~= enabled then fail(label .. " named current-state setup differs: " .. name) end
  return value
end

local function set_current_prerequisites(force, foreign, label)
  set_current_technology(force, PREDECESSOR, true, true, label)
  set_current_technology(force, DEEP_SCIENCE, true, true, label)
  set_current_technology(force, AUTOMATION_SCIENCE, foreign, true, label)
  set_current_technology(force, ELECTRICITY, foreign, true, label)
  set_current_technology(force, PROBE, false, true, label)
  set_current_technology(force, SENTINEL, false, false, label)
end

local function assert_current_baseline(state, label)
  local player = current_force_snapshot(game.forces.player, label .. " player")
  local foreign = current_force_snapshot(force_by_index(state.foreign_index, label .. " foreign"), label .. " foreign")
  local earned = current_force_snapshot(force_by_index(state.earned_index, label .. " earned"), label .. " earned")
  local function required(frame, foreign_flags, force_label)
    if frame.prerequisite_flags[PREDECESSOR].researched ~= true or frame.prerequisite_flags[DEEP_SCIENCE].researched ~= true
        or frame.prerequisite_flags[AUTOMATION_SCIENCE].researched ~= foreign_flags
        or frame.prerequisite_flags[ELECTRICITY].researched ~= foreign_flags
        or frame.prerequisite_flags[PROBE].researched ~= false or frame.unrelated_sentinel.enabled ~= false then
      fail(force_label .. " current-state prerequisite baseline differs")
    end
  end
  required(player, false, label .. " player")
  required(foreign, true, label .. " foreign")
  required(earned, false, label .. " earned")
  local worker = player.worker
  if worker.level ~= 10 or worker.researched ~= false or worker.enabled ~= true or worker.queue.current ~= WORKER
      or #worker.queue.queue ~= 2 or worker.queue.queue[1] ~= WORKER or worker.queue.queue[2] ~= WORKER
      or not close(worker.queue.progress, PARTIAL) then fail(label .. " player current-state baseline differs") end
  worker = foreign.worker
  if worker.level ~= 11 or worker.researched ~= false or worker.enabled ~= true or worker.queue.current ~= PROBE
      or #worker.queue.queue ~= 1 or worker.queue.queue[1] ~= PROBE
      or not close(worker.queue.progress, FOREIGN_PROGRESS) then fail(label .. " foreign current-state baseline differs") end
  worker = earned.worker
  if worker.level ~= EARNED_LEVEL or worker.researched ~= false or worker.enabled ~= true or worker.queue.current ~= false
      or #worker.queue.queue ~= 0 then fail(label .. " earned current-state baseline differs") end
  return player, foreign, earned
end

local function current_reset_force(state, force, role, label)
  local before = current_force_snapshot(force, label .. " before reset")
  state.reset_call_count = state.reset_call_count + 1
  state.resetting_force_index = force.index
  local event_start = #(state.native_reset_events or {})
  force.reset_technology_effects()
  state.resetting_force_index = false
  local delivered = false
  for index = event_start + 1, #(state.native_reset_events or {}) do
    if state.native_reset_events[index].force_index == force.index then delivered = true end
  end
  if not delivered then fail(label .. " native reset event was not delivered synchronously") end
  local after = current_force_snapshot(force, label .. " after reset")
  -- The reset API itself preserves native research state, while the candidate's
  -- real reset-event handler may then enforce the declared cap.  Keep named
  -- prerequisite and unrelated-sentinel state strict here and export both
  -- complete frames so the consumer can distinguish that event result.
  if not same_current_support_rows(before, after) then fail(label .. " native reset changed support state") end
  state.reset_rows[#state.reset_rows + 1] = {call_count = state.reset_call_count, force_role = role,
    force_name = force.name, force_index = force.index, before = before, post_reset = after,
    native_event_delivered = delivered}
  return after
end

local function current_reset_sequence(state)
  local forces = {game.forces.player, force_by_index(state.foreign_index, "current reset foreign"),
    force_by_index(state.earned_index, "current reset earned")}
  local roles = {"player", "foreign", "earned_above_cap"}
  for index, force in ipairs(forces) do current_reset_force(state, force, roles[index], "current reset " .. roles[index]) end
  if state.reset_call_count ~= 3 or #state.reset_rows ~= 3 then fail("current-state reset call count differs") end
end

local function assert_current_old_post_reset(state, label)
  local player = current_force_snapshot(game.forces.player, label .. " player")
  local foreign = current_force_snapshot(force_by_index(state.foreign_index, label .. " foreign"), label .. " foreign")
  local earned = current_force_snapshot(force_by_index(state.earned_index, label .. " earned"), label .. " earned")
  if player.worker.level ~= 10 or player.worker.enabled ~= true or player.worker.queue.current ~= WORKER or #player.worker.queue.queue ~= 2
      or not close(player.worker.queue.progress, PARTIAL) then fail(label .. " published15 player reset state differs") end
  if foreign.worker.level ~= 11 or foreign.worker.enabled ~= true or foreign.worker.queue.current ~= PROBE or #foreign.worker.queue.queue ~= 1
      or not close(foreign.worker.queue.progress, FOREIGN_PROGRESS) then fail(label .. " published15 foreign reset state differs") end
  if earned.worker.level ~= EARNED_LEVEL or earned.worker.enabled ~= true or earned.worker.queue.current ~= false or #earned.worker.queue.queue ~= 0 then
    fail(label .. " published15 earned reset state differs")
  end
  return player, foreign, earned
end

local function assert_current_candidate_post_reset(state, label)
  local player = current_force_snapshot(game.forces.player, label .. " player")
  local foreign = current_force_snapshot(force_by_index(state.foreign_index, label .. " foreign"), label .. " foreign")
  local earned = current_force_snapshot(force_by_index(state.earned_index, label .. " earned"), label .. " earned")
  if player.worker.level ~= 10 or player.worker.researched ~= false or player.worker.enabled ~= true or player.worker.queue.current ~= WORKER
      or #player.worker.queue.queue ~= 1 or player.worker.queue.queue[1] ~= WORKER or not close(player.worker.queue.progress, PARTIAL) then
    fail(label .. " candidate player reset state differs")
  end
  if foreign.worker.level ~= 11 or foreign.worker.researched ~= false or foreign.worker.enabled ~= false or foreign.worker.queue.current ~= PROBE
      or #foreign.worker.queue.queue ~= 1 or foreign.worker.queue.queue[1] ~= PROBE or not close(foreign.worker.queue.progress, FOREIGN_PROGRESS) then
    fail(label .. " candidate foreign reset state differs")
  end
  if earned.worker.level ~= EARNED_LEVEL or earned.worker.researched ~= false or earned.worker.enabled ~= false
      or earned.worker.queue.current ~= false or #earned.worker.queue.queue ~= 0 then fail(label .. " candidate earned reset state differs") end
  return player, foreign, earned
end

local function assert_current_post_completion(state, label)
  local player, foreign, earned = observe_all(state, label)
  local player_support = current_force_snapshot(game.forces.player, label .. " player")
  local foreign_support = current_force_snapshot(force_by_index(state.foreign_index, label .. " foreign"), label .. " foreign")
  local earned_support = current_force_snapshot(force_by_index(state.earned_index, label .. " earned"), label .. " earned")
  local ordinary = state.ordinary_events
  if type(ordinary) ~= "table" or #ordinary ~= 1 or type(ordinary[1]) ~= "table"
      or ordinary[1].name ~= WORKER or ordinary[1].by_script ~= false or type(ordinary[1].tick) ~= "number" then
    fail(label .. " ordinary native level-ten event differs")
  end
  if not same_current_support_rows(state.current_pre_work_frames.player, player_support)
      or not same_current_support_rows(state.current_pre_work_frames.foreign, foreign_support)
      or not same_current_support_rows(state.current_pre_work_frames.earned_above_cap, earned_support) then
    fail(label .. " changed named prerequisite or unrelated sentinel state")
  end
  if state.level_eleven_start_count ~= 0 or player.level ~= 11 or player.researched ~= false or player.enabled ~= false
      or player.queue.current ~= false or #player.queue.queue ~= 0 or not close(player.queue.progress, 0)
      or not close(player.bonus, state.current_player_bonus_before + EFFECT) then
    fail(label .. " current-state completion started or consumed level eleven")
  end
  if foreign.level ~= 11 or foreign.enabled ~= false or foreign.queue.current ~= PROBE or #foreign.queue.queue ~= 1
      or not close(foreign.queue.progress, FOREIGN_PROGRESS) then fail(label .. " current-state foreign state differs") end
  if earned.level ~= EARNED_LEVEL or earned.enabled ~= false or earned.queue.current ~= false or #earned.queue.queue ~= 0 then
    fail(label .. " current-state earned state differs")
  end
  assert_feed_consumed_and_remaining(state, label)
  return player_support, foreign_support, earned_support
end

local function current_observe_sequence(state)
  state.observe_sequence = state.observe_sequence + 1
  return state.observe_sequence
end

local function current_observe_frame(state, boundary)
  local player = current_force_snapshot(game.forces.player, "current observe " .. boundary .. " player", true)
  local foreign = current_force_snapshot(force_by_index(state.foreign_index, "current observe " .. boundary .. " foreign"),
    "current observe " .. boundary .. " foreign", true)
  local earned = current_force_snapshot(force_by_index(state.earned_index, "current observe " .. boundary .. " earned"),
    "current observe " .. boundary .. " earned", true)
  state.observe_frames[#state.observe_frames + 1] = {
    sequence = current_observe_sequence(state), boundary = boundary,
    player = player, foreign = foreign, earned_above_cap = earned,
  }
end

local function current_observe_event(state, event_name, event)
  if #state.observe_events >= CURRENT_OBSERVE_MAX_EVENTS then fail("current observe event limit exceeded") end
  local research = event.research
  local force = event.force or (research and research.force)
  local row = {sequence = current_observe_sequence(state), boundary = state.observe_boundary, event = event_name}
  if force ~= nil then
    row.force_index, row.force_name = force.index, force.name
  end
  if research ~= nil then
    row.research_name = research.name
    if type(research.level) == "number" then row.research_level = research.level end
  end
  if type(event.by_script) == "boolean" then
    row.by_script_present, row.by_script = true, event.by_script
  else
    row.by_script_present = false
  end
  state.observe_events[#state.observe_events + 1] = row
end

local function current_observe_trace(state)
  local trace = current_header("observe", "current-observe16")
  trace.role = "reduced-synthetic-current-state-callback-observation"
  trace.trace_schema = "MIR516SECapCallbackTraceV1"
  trace.snapshot_role = "public-admin-write-boundary-observation-before-native-reset"
  trace.source_base = {identity = "controller-bound-A0-base-input-only",
    fixture_source_phase = "not-read-no-continuation-precondition"}
  trace.frames, trace.events = copy(state.observe_frames), copy(state.observe_events)
  trace.terminal = {expected_token = CURRENT_OBSERVE_TOKEN, explicit_reset_calls = 0,
    lab_created = false, save_requested = false, cold_requested = false}
  current_emit("observe", trace)
end

-- The reset and observation roles deliberately share this exact public
-- administrative write sequence.  Only the observer supplies boundary hooks;
-- the reset roles retain their original writes and no extra emitted state.
local function apply_current_admin_sequence(player, foreign, earned, label, hooks)
  local function before(action)
    if hooks ~= nil and hooks.before ~= nil then hooks.before(action) end
  end
  local function after(action)
    if hooks ~= nil and hooks.after ~= nil then hooks.after(action) end
  end

  before("prerequisites")
  set_current_prerequisites(player, false, label .. " player")
  set_current_prerequisites(foreign, true, label .. " foreign")
  set_current_prerequisites(earned, false, label .. " earned")
  after("prerequisites")

  before("player-target")
  local owner = technology(player, WORKER)
  owner.level, owner.researched, owner.enabled, owner.visible_when_disabled = 10, false, true, false
  after("player-target")
  before("player-queue")
  player.research_queue = {owner, owner}
  after("player-queue")
  before("player-progress")
  player.research_progress = PARTIAL
  after("player-progress")

  before("foreign-target")
  owner = technology(foreign, WORKER)
  owner.level, owner.researched, owner.enabled, owner.visible_when_disabled = 11, false, true, false
  after("foreign-target")
  before("foreign-queue")
  foreign.research_queue = {technology(foreign, PROBE)}
  after("foreign-queue")
  before("foreign-progress")
  foreign.research_progress = FOREIGN_PROGRESS
  after("foreign-progress")

  before("earned-target")
  owner = technology(earned, WORKER)
  owner.level, owner.researched, owner.enabled, owner.visible_when_disabled = EARNED_LEVEL, false, true, false
  after("earned-target")
  before("earned-queue")
  earned.research_queue = {}
  after("earned-queue")
end

local function begin_current_observe()
  current_provider_marker("current-observe16")
  if storage[CURRENT_OBSERVE_KEY] ~= nil then fail("current observe fixture state already exists") end
  local player, foreign, earned = current_named_forces("current observe fixture admin")
  local state = {phase = "current-observe-admin", current_observe = true, player_force_index = player.index,
    foreign_index = foreign.index, earned_index = earned.index, admin_intent = current_admin_intent(),
    observe_sequence = 0, observe_frames = {}, observe_events = {}, observe_boundary = "before-admin"}
  storage[CURRENT_OBSERVE_KEY] = state

  current_observe_frame(state, "before-admin")
  apply_current_admin_sequence(player, foreign, earned, "current observe", {
    before = function(action) state.observe_boundary = action end,
    after = function(action) current_observe_frame(state, "after-" .. action) end,
  })

  state.observe_boundary = "after-admin"
  current_observe_frame(state, "after-admin")
  state.phase = "current-observe-await-passive-tick"
end

local function begin_current_state(stage)
  current_provider_marker(stage)
  if storage[CURRENT_KEY] ~= nil then fail("current-state fixture state already exists") end
  local player, foreign, earned = current_named_forces("current fixture admin")
  local state = {phase = "current-admin-setup", current_state = true, player_force_index = player.index,
    ordinary_native_completion_count = 0, level_eleven_start_count = 0, ordinary_events = {},
    reset_call_count = 0, reset_rows = {}, native_reset_events = {}, admin_intent = current_admin_intent()}
  storage[CURRENT_KEY] = state
  state.foreign_index, state.earned_index = foreign.index, earned.index
  apply_current_admin_sequence(player, foreign, earned, "current", nil)
  local admin_observed = current_header("admin-observed", stage)
  admin_observed.snapshot_role = "after-declared-admin-before-baseline-validation"
  admin_observed.player = current_force_snapshot(player, "current admin observed player", true)
  admin_observed.foreign = current_force_snapshot(foreign, "current admin observed foreign", true)
  admin_observed.earned_above_cap = current_force_snapshot(earned, "current admin observed earned", true)
  current_emit("admin-observed", admin_observed)
  local player_frame, foreign_frame, earned_frame = assert_current_baseline(state, "current pre-reset")
  local pre_reset = current_header("pre-reset", stage)
  pre_reset.snapshot_role = "fixture-admin-current-state-before-native-reset"
  pre_reset.player, pre_reset.foreign, pre_reset.earned_above_cap = player_frame, foreign_frame, earned_frame
  state.pre_reset = copy(pre_reset)
  current_emit("pre-reset", pre_reset)
  current_reset_sequence(state)
  local post_reset = current_header("post-reset", stage)
  post_reset.snapshot_role = "after-one-native-reset-per-actor-force"
  post_reset.reset_call_count, post_reset.reset_rows, post_reset.native_reset_events = state.reset_call_count, copy(state.reset_rows), copy(state.native_reset_events)
  post_reset.player, post_reset.foreign, post_reset.earned_above_cap = observe_all(state, "current post-reset")
  state.post_reset = copy(post_reset)
  return state, post_reset
end

local function tick_current_state(state)
  if #(state.outside_reset_events or {}) ~= 0 then
    fail("current-state observed reset outside the declared three-force boundary")
  end
  if state.phase == "current-await-ordinary-level-ten" then
    if state.current_pre_work_checked ~= true then
      local player = current_force_snapshot(game.forces.player, "current pre-work player")
      local foreign = current_force_snapshot(force_by_index(state.foreign_index, "current pre-work foreign"), "current pre-work foreign")
      local earned = current_force_snapshot(force_by_index(state.earned_index, "current pre-work earned"), "current pre-work earned")
      if not same_current_frame(state.current_pre_work_frames.player, player)
          or not same_current_frame(state.current_pre_work_frames.foreign, foreign)
          or not same_current_frame(state.current_pre_work_frames.earned_above_cap, earned) then
        fail("current-state post-reset public state changed before ordinary lab work")
      end
      state.current_pre_work_checked = true
    end
    refill_lab(state, "current await")
    if game.tick > state.deadline_tick then fail("current-state ordinary level-ten completion timed out") end
    return
  end
  if state.phase == "current-ordinary-level-ten-finished" then
    refill_lab(state, "current post-completion")
    local player, foreign, earned = assert_current_post_completion(state, "current ordinary completion")
    state.post_completion = {tick = game.tick, player = copy(player), foreign = copy(foreign),
      earned_above_cap = copy(earned), lab = lab_snapshot(state, "current ordinary completion")}
    state.post_completion_hold_started_tick = game.tick
    assert_level_eleven_cannot_queue(state)
    state.phase = "current-post-completion-hold"
    return
  end
  if state.phase == "current-post-completion-hold" then
    local player, foreign, earned = assert_current_post_completion(state, "current post-completion hold")
    state.post_completion_hold_ticks = game.tick - state.post_completion_hold_started_tick
    if state.post_completion_hold_ticks < POST_COMPLETION_HOLD_TICKS then return end
    local ending_lab = lab_snapshot(state, "current post-completion hold end")
    if ending_lab.input_total ~= state.post_completion.lab.input_total
        or ending_lab.scripted_feed_total ~= state.post_completion.lab.scripted_feed_total then
      fail("current-state post-completion hold changed fixture science accounting")
    end
    state.post_completion.end_tick = game.tick
    state.post_completion.end_player = copy(player)
    state.post_completion.end_foreign = copy(foreign)
    state.post_completion.end_earned_above_cap = copy(earned)
    state.post_completion.end_lab = ending_lab
    state.phase = "current-complete"
    local complete = current_header("complete", "current-successor16")
    complete.pre_reset, complete.post_reset, complete.post_reset_player_bonus = copy(state.pre_reset), copy(state.post_reset),
      state.current_player_bonus_before
    complete.pre_work, complete.post_completion = copy(state.pre_work), copy(state.post_completion)
    complete.ordinary_native_completion_count, complete.level_eleven_start_count = state.ordinary_native_completion_count,
      state.level_eleven_start_count
    complete.level_eleven_queue_attempt, complete.lab = copy(state.level_eleven_queue_attempt), ending_lab
    complete.post_completion_hold_ticks, complete.reset_rows, complete.native_reset_events = state.post_completion_hold_ticks,
      copy(state.reset_rows), copy(state.native_reset_events)
    complete.ordinary_events = copy(state.ordinary_events)
    complete.player, complete.foreign, complete.earned_above_cap = player, foreign, earned
    complete.completed_forces = {player = copy(player), foreign = copy(foreign), earned_above_cap = copy(earned)}
    current_emit("complete", complete)
    game.server_save(CURRENT_SAVE)
    cold_requested, cold_logged = false, true
    return
  end
  if state.phase ~= "current-complete" then fail("current-state fixture phase differs") end
  if not cold_requested or cold_logged then return end
  local player, foreign, earned = assert_current_post_completion(state, "current cold")
  local cold = current_header("cold", "current-successor16")
  cold.pre_reset, cold.post_reset, cold.pre_work, cold.post_completion = copy(state.pre_reset), copy(state.post_reset),
    copy(state.pre_work), copy(state.post_completion)
  cold.post_reset_player_bonus, cold.player, cold.foreign, cold.earned_above_cap = state.current_player_bonus_before,
    player, foreign, earned
  cold.ordinary_native_completion_count, cold.level_eleven_start_count = state.ordinary_native_completion_count,
    state.level_eleven_start_count
  cold.on_load_read_only, cold.lab = true, lab_snapshot(state, "current cold")
  cold.post_completion_hold_ticks, cold.reset_rows, cold.native_reset_events = state.post_completion_hold_ticks,
    copy(state.reset_rows), copy(state.native_reset_events)
  cold.ordinary_events = copy(state.ordinary_events)
  cold.completed_forces = {player = copy(player), foreign = copy(foreign), earned_above_cap = copy(earned)}
  current_emit("cold", cold)
  cold_logged = true
end

function M.apply(stage, report_active_mods)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown control stage") end
  if stage == "current-observe16" then
    if type(report_active_mods) ~= "function" then fail("current observe active-mod observer callback differs") end
    check_closure(stage)
    report_active_mods(current_observe_active_mod_tuple())
  end

  script.on_init(function()
    if stage ~= "source15" then fail("only source stage may initialize") end
    check_closure(stage)
    if storage[KEY] ~= nil then fail("fixture state already exists") end
    local state = {phase = "source-setup", ordinary_native_completion_count = 0, level_eleven_start_count = 0,
      ordinary_events = {}, scripted_administrative_events = {}}
    storage[KEY] = state
    local player = game.forces.player
    state.player_force_index = player.index
    seed_worker_prerequisites(player, "player")
    local owner = technology(player, WORKER)
    owner.level, owner.researched = 10, false
    player.reset_technology_effects()
    owner.enabled, owner.visible_when_disabled = true, false
    player.research_queue = {owner, owner}
    player.research_progress = PARTIAL
    local player_state = worker_snapshot(player, "source player")
    assert_player_seed(player_state, "source")
    local foreign = game.create_force("mir5-worker-speed-cap-ten-foreign")
    state.foreign_index = foreign.index
    seed_foreign(foreign)
    local earned = game.create_force("mir5-worker-speed-cap-ten-earned")
    state.earned_index = earned.index
    seed_earned(earned)
    local foreign_state = worker_snapshot(foreign, "source foreign")
    local earned_state = worker_snapshot(earned, "source earned")
    state.phase, state.source_mir = "source-seeded", script.active_mods["more-infinite-research"]
    state.player_bonus_before, state.foreign_bonus, state.earned_bonus = player_state.bonus, foreign_state.bonus, earned_state.bonus
    marker("source", state)
  end)

  script.on_configuration_changed(function()
    if stage == "source15" then fail("source stage does not accept configuration") end
    check_closure(stage)
    if stage == "current-observe16" then
      begin_current_observe()
      return
    end
    if stage == "current-old15" or stage == "current-successor16" then
      local state, post_reset = begin_current_state(stage)
      if stage == "current-old15" then
        local player, foreign, earned = assert_current_old_post_reset(state, "current published15 adverse")
        post_reset.outcome, post_reset.player, post_reset.foreign, post_reset.earned_above_cap =
          "published15-reset-event-not-enforced", player, foreign, earned
        state.post_reset = copy(post_reset)
        current_emit("post-reset", post_reset)
        error("MIR_EXPECTED_CURRENT_OLD15_RESET_NOT_ENFORCED")
      end
      local player, foreign, earned = assert_current_candidate_post_reset(state, "current candidate pre-work")
      post_reset.outcome, post_reset.player, post_reset.foreign, post_reset.earned_above_cap =
        "candidate16-reset-event-enforced", player, foreign, earned
      state.post_reset = copy(post_reset)
      current_emit("post-reset", post_reset)
      state.current_player_bonus_before = player.worker.bonus
      state.pre_work = {player = copy(player), foreign = copy(foreign), earned_above_cap = copy(earned),
        reset_rows = copy(state.reset_rows), native_reset_events = copy(state.native_reset_events)}
      local pre_work = current_header("pre-work", stage)
      pre_work.snapshot_role = "candidate-current-state-after-native-reset-before-lab"
      pre_work.player, pre_work.foreign, pre_work.earned_above_cap = player, foreign, earned
      pre_work.post_reset_player_bonus, pre_work.reset_rows, pre_work.native_reset_events = state.current_player_bonus_before,
        copy(state.reset_rows), copy(state.native_reset_events)
      current_emit("pre-work", pre_work)
      state.current_pre_work_frames = {player = copy(player), foreign = copy(foreign), earned_above_cap = copy(earned)}
      create_lab(state)
      state.phase, state.deadline_tick = "current-await-ordinary-level-ten", game.tick + DEADLINE_TICKS
      return
    end
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= "source-seeded" or state.source_mir ~= "5.0.20015" then
      fail("scripted source state is absent")
    end
    preconditions_marker(state)
    local player, foreign, earned = observe_all(state, "cap-ten configuration")
    assert_seeded_prerequisites(state, "cap-ten configuration")
    state.pre_work = {source_mir = state.source_mir, active_mir = script.active_mods["more-infinite-research"],
      player = copy(player), foreign = copy(foreign), earned_above_cap = copy(earned)}
    if stage == "old-negative15" then
      assert_player_seed(player, "published15 adverse")
      assert_foreign_seed(foreign, state, "published15 adverse")
      assert_earned_seed(earned, state, "published15 adverse")
      marker("old-negative", state)
      error("MIR_EXPECTED_OLD15_CAP_NOT_ENFORCED")
    end
    if stage ~= "successor16" then fail("unknown cap-ten configuration stage") end
    assert_player_cap(player, state, "successor configuration")
    assert_foreign_cap(foreign, state, "successor configuration")
    assert_earned_cap(earned, state, "successor configuration")
    marker("pre-work", state)
    create_lab(state)
    state.phase, state.deadline_tick = "await-ordinary-level-ten", game.tick + DEADLINE_TICKS
  end)

  script.on_event(defines.events.on_research_finished, function(event)
    if stage == "current-observe16" then
      local state = storage[CURRENT_OBSERVE_KEY]
      if type(state) == "table" then current_observe_event(state, "on_research_finished", event) end
      return
    end
    if stage == "current-successor16" then
      local state = storage[CURRENT_KEY]
      if type(state) ~= "table" or state.phase ~= "current-await-ordinary-level-ten" then return end
      local player = game.forces.player
      if event.research == nil or event.research.force ~= player or event.research.name ~= WORKER then return end
      if event.by_script ~= false or event.research.level ~= 10 then
        fail("scripted or non-level-ten current-state completion cannot satisfy ordinary cap-ten work")
      end
      state.ordinary_native_completion_count = state.ordinary_native_completion_count + 1
      if state.ordinary_native_completion_count ~= 1 then fail("second current-state worker completion occurred") end
      state.ordinary_events[#state.ordinary_events + 1] = {name = WORKER, by_script = false, tick = event.tick}
      state.phase = "current-ordinary-level-ten-finished"
      return
    end
    if stage == "source15" then
      local research = event.research
      local source_state = storage[KEY]
      if research == nil or research.name ~= WORKER then
        if type(source_state) == "table" and event.by_script == true and research ~= nil
            and (research.name == PREDECESSOR or research.name == DEEP_SCIENCE
              or research.name == AUTOMATION_SCIENCE or research.name == ELECTRICITY)
            and actor_force(source_state, research.force)
            and #source_state.scripted_administrative_events < 16 then
          source_state.scripted_administrative_events[#source_state.scripted_administrative_events + 1] = {
            name = research.name, force_index = research.force.index, by_script = true, tick = event.tick,
            setup_class = "scripted-prerequisite"}
        end
        return
      end
      fail("source stage observed non-administrative research completion")
    end
    local state = storage[stage == "current-successor16" and CURRENT_KEY or KEY]
    if type(state) ~= "table" or state.phase ~= "await-ordinary-level-ten" then return end
    local player = game.forces.player
    if event.research == nil or event.research.force ~= player or event.research.name ~= WORKER then return end
    if event.by_script ~= false or event.research.level ~= 10 then
      fail("scripted or non-level-ten completion cannot satisfy ordinary cap-ten work")
    end
    state.ordinary_native_completion_count = state.ordinary_native_completion_count + 1
    if state.ordinary_native_completion_count ~= 1 then fail("second worker completion occurred") end
    state.ordinary_events[#state.ordinary_events + 1] = {name = WORKER, by_script = false, tick = event.tick}
    state.phase = "ordinary-level-ten-finished"
  end)

  script.on_event(defines.events.on_research_started, function(event)
    if stage == "current-observe16" then
      local state = storage[CURRENT_OBSERVE_KEY]
      if type(state) == "table" then current_observe_event(state, "on_research_started", event) end
      return
    end
    if stage ~= "successor16" and stage ~= "current-successor16" then return end
    local state = storage[stage == "current-successor16" and CURRENT_KEY or KEY]
    if type(state) ~= "table" then return end
    local player = game.forces.player
    if event.research ~= nil and event.research.force == player and event.research.name == WORKER
        and type(event.research.level) == "number" and event.research.level > 10 then
      state.level_eleven_start_count = state.level_eleven_start_count + 1
      fail("level eleven research started")
    end
  end)

  script.on_event(defines.events.on_technology_effects_reset, function(event)
    if stage == "current-observe16" then
      local state = storage[CURRENT_OBSERVE_KEY]
      if type(state) == "table" then current_observe_event(state, "on_technology_effects_reset", event) end
      return
    end
    if stage ~= "current-old15" and stage ~= "current-successor16" then return end
    local state = storage[CURRENT_KEY]
    if type(state) ~= "table" or state.current_state ~= true or event.force == nil then return end
    local row = {force_index = event.force.index, force_name = event.force.name,
      during_fixture_reset = event.force.index == state.resetting_force_index}
    state.native_reset_events[#state.native_reset_events + 1] = row
    if row.during_fixture_reset ~= true then
      state.outside_reset_events = state.outside_reset_events or {}
      state.outside_reset_events[#state.outside_reset_events + 1] = copy(row)
    end
  end)

  script.on_event(defines.events.on_research_cancelled, function(event)
    if stage ~= "current-observe16" then return end
    local state = storage[CURRENT_OBSERVE_KEY]
    if type(state) == "table" then current_observe_event(state, "on_research_cancelled", event) end
  end)

  script.on_event(defines.events.on_research_reversed, function(event)
    if stage ~= "current-observe16" then return end
    local state = storage[CURRENT_OBSERVE_KEY]
    if type(state) == "table" then current_observe_event(state, "on_research_reversed", event) end
  end)

  script.on_load(function()
    -- Cold snapshots set local flags only and read on one later tick.
    cold_requested, cold_logged = true, false
  end)

  script.on_event(defines.events.on_tick, function()
    if stage == "current-observe16" then
      local state = storage[CURRENT_OBSERVE_KEY]
      if type(state) ~= "table" or state.phase ~= "current-observe-await-passive-tick" then
        fail("current observe fixture state is absent")
      end
      state.observe_boundary = "passive-next-tick"
      current_observe_frame(state, "passive-next-tick")
      state.phase = "current-observe-complete"
      current_observe_trace(state)
      error(CURRENT_OBSERVE_TOKEN)
    end
    if stage == "current-successor16" then
      local state = storage[CURRENT_KEY]
      if type(state) ~= "table" then fail("current-state fixture state is absent") end
      tick_current_state(state)
      return
    end
    if stage == "source15" then fail("source create-only stage received an actor tick") end
    if stage == "old-negative15" then fail("published15 adverse stage received an actor tick") end
    local state = storage[KEY]
    if type(state) ~= "table" then fail("fixture state is absent") end
    if state.phase == "await-ordinary-level-ten" then
      refill_lab(state, "await")
      if game.tick > state.deadline_tick then fail("ordinary level-ten completion timed out") end
      return
    end
    if state.phase == "ordinary-level-ten-finished" then
      refill_lab(state, "post-completion")
      local player, foreign, earned = assert_post_completion(state, "ordinary completion")
      state.post_completion = {tick = game.tick, player = copy(player), foreign = copy(foreign),
        earned_above_cap = copy(earned), lab = lab_snapshot(state, "ordinary completion")}
      state.post_completion_hold_started_tick = game.tick
      assert_level_eleven_cannot_queue(state)
      state.phase = "post-completion-hold"
      return
    end
    if state.phase == "post-completion-hold" then
      local player, foreign, earned = assert_post_completion(state, "post-completion hold")
      state.post_completion_hold_ticks = game.tick - state.post_completion_hold_started_tick
      if state.post_completion_hold_ticks < POST_COMPLETION_HOLD_TICKS then return end
      local ending_lab = lab_snapshot(state, "post-completion hold end")
      if ending_lab.input_total ~= state.post_completion.lab.input_total
          or ending_lab.scripted_feed_total ~= state.post_completion.lab.scripted_feed_total then
        fail("post-completion hold changed fixture science accounting")
      end
      state.post_completion.end_tick = game.tick
      state.post_completion.end_player = copy(player)
      state.post_completion.end_foreign = copy(foreign)
      state.post_completion.end_earned_above_cap = copy(earned)
      state.post_completion.end_lab = ending_lab
      state.phase = "complete"
      marker("complete", state)
      game.server_save(SAVE)
      cold_requested, cold_logged = false, true
      return
    end
    if state.phase ~= "complete" then fail("fixture phase differs") end
    if not cold_requested or cold_logged then return end
    local player, foreign, earned = observe_all(state, "cold")
    if player.level ~= 11 or player.enabled ~= false or player.queue.current ~= false or #player.queue.queue ~= 0
        or not close(player.bonus, state.player_bonus_before + EFFECT) then fail("cold player cap state differs") end
    assert_foreign_cap(foreign, state, "cold")
    assert_earned_cap(earned, state, "cold")
    assert_feed_consumed_and_remaining(state, "cold")
    marker("cold", state)
    cold_logged = true
  end)
end

return M
