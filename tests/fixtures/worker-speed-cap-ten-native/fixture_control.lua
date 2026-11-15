-- Disposable F200/SE worker-speed cap-ten actor. It never imports MIR
-- internals: the real player's configuration/research callbacks own caps.
local M = {}

local KEY = "mir5_worker_speed_cap_ten"
local SAVE = "mir5-worker-speed-cap-ten-complete"
local CASE = "f200-se-worker-speed-cap-ten"
local FIXTURE = "mir-fixture-mir5-worker-speed-cap-ten"
local WORKER = "worker-robots-speed-6"
local PREDECESSOR = "worker-robots-speed-5"
local SPACE_SCIENCE = "space-science-pack"
local PROBE = "automation"
local AUTOMATION_SCIENCE = "automation-science-pack"
local LAB = "mir-worker-speed-cap-ten-fast-lab"
local PARTIAL = 0.27
local FOREIGN_PROGRESS = 0.42
local EFFECT = 0.65
local EARNED_LEVEL = 13
local UINT32_MAX = 4294967295
local DEADLINE_TICKS = 18000
local POST_COMPLETION_HOLD_TICKS = 2
local LAB_TOP_UP_REQUEST = 200
local STAGES = {source = {version = "0.1.0", cap = 0}, cap10 = {version = "0.2.0", cap = 10}}
local CLOSURE = {
  base = "2.0.77", ["more-infinite-research"] = "5.0.20015", ["space-exploration"] = "0.7.57",
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
    if name ~= FIXTURE and CLOSURE[name] == nil then fail("unexpected enabled mod: " .. name) end
  end
  if active[FIXTURE] ~= expected.version then fail("fixture stage version differs") end
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
  local predecessor, space = prerequisites[PREDECESSOR], prerequisites[SPACE_SCIENCE]
  if prerequisite_count ~= 2 or predecessor == nil or predecessor.name ~= PREDECESSOR
      or space == nil or space.name ~= SPACE_SCIENCE then fail(label .. " worker direct prerequisites differ") end
  if type(value.research_unit_count) ~= "number" or value.research_unit_count <= 0
      or value.research_unit_count ~= math.floor(value.research_unit_count)
      or type(value.research_unit_energy) ~= "number" or value.research_unit_energy <= 0 then
    fail(label .. " worker research-unit contract differs")
  end
  local seen = {}
  for _, ingredient in ipairs(value.research_unit_ingredients or {}) do
    if type(ingredient.name) ~= "string" or ingredient.name == "" or seen[ingredient.name]
        or type(ingredient.amount) ~= "number" or ingredient.amount <= 0
        or ingredient.amount ~= math.floor(ingredient.amount) then
      fail(label .. " worker ingredient contract differs")
    end
    seen[ingredient.name] = true
  end
  if next(seen) == nil then fail(label .. " worker ingredients are absent") end
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

local function assert_earned_cap(actual, state, label)
  if actual.level ~= EARNED_LEVEL or actual.researched ~= false or actual.enabled ~= false or actual.visible ~= true
      or not close(actual.bonus, state.earned_bonus) or actual.queue.current ~= false or #actual.queue.queue ~= 0 then
    fail(label .. " earned-above-cap state differs")
  end
end

local function seed_worker_prerequisites(force, label)
  for _, name in ipairs({PREDECESSOR, SPACE_SCIENCE}) do
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
  for _, name in ipairs({PREDECESSOR, SPACE_SCIENCE}) do
    if technology(player, name).researched ~= true then fail(label .. " player worker prerequisite is not researched: " .. name) end
    if technology(foreign, name).researched ~= true or technology(earned, name).researched ~= true then
      fail(label .. " witness worker prerequisite is not researched: " .. name)
    end
  end
  if technology(foreign, AUTOMATION_SCIENCE).researched ~= true then
    fail(label .. " foreign automation science prerequisite is not researched")
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
    mods = mods, active_mod_count = active_mod_count, cap = settings.startup["mir-max-level-worker-robots-speed"].value,
    per_level_speed_effect = EFFECT,
    scripted_setup = {source_level = 10, current_partial = PARTIAL, queued_next_occurrences = 1,
      foreign_disabled = true, earned_above_cap_force = true, lab_feed = state.lab_feed ~= nil},
    ordinary_native_completion_count = state.ordinary_native_completion_count or 0,
    level_eleven_start_count = state.level_eleven_start_count or 0,
    scripted_administrative_events = copy(state.scripted_administrative_events or {}),
    ordinary_events = copy(state.ordinary_events or {}), pre_work = state.pre_work and copy(state.pre_work) or false,
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

local function seed_foreign()
  local foreign = game.create_force("mir5-worker-speed-cap-ten-foreign")
  foreign.enable_all_prototypes()
  seed_worker_prerequisites(foreign, "foreign")
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

local function seed_earned()
  local earned = game.create_force("mir5-worker-speed-cap-ten-earned")
  earned.enable_all_prototypes()
  seed_worker_prerequisites(earned, "earned")
  local owner = technology(earned, WORKER)
  owner.level, owner.researched = EARNED_LEVEL, false
  earned.reset_technology_effects()
  owner.enabled, owner.visible_when_disabled = true, false
  return earned
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
  lab.energy = 100000000
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

function M.apply(stage)
  local expected = STAGES[stage]
  if expected == nil then fail("unknown control stage") end

  script.on_init(function()
    if stage ~= "source" then fail("only source stage may initialize") end
    check_closure(stage)
    if storage[KEY] ~= nil then fail("fixture state already exists") end
    local state = {phase = "source-setup", ordinary_native_completion_count = 0, level_eleven_start_count = 0,
      ordinary_events = {}, scripted_administrative_events = {}}
    storage[KEY] = state
    local player = game.forces.player
    player.enable_all_prototypes()
    seed_worker_prerequisites(player, "player")
    local owner = technology(player, WORKER)
    owner.level, owner.researched = 10, false
    player.reset_technology_effects()
    owner.enabled, owner.visible_when_disabled = true, false
    player.research_queue = {owner, owner}
    player.research_progress = PARTIAL
    local player_state = worker_snapshot(player, "source player")
    assert_player_seed(player_state, "source")
    local foreign, earned = seed_foreign(), seed_earned()
    local foreign_state = worker_snapshot(foreign, "source foreign")
    local earned_state = worker_snapshot(earned, "source earned")
    state.phase, state.foreign_index, state.earned_index = "source-seeded", foreign.index, earned.index
    state.player_bonus_before, state.foreign_bonus, state.earned_bonus = player_state.bonus, foreign_state.bonus, earned_state.bonus
    marker("source", state)
  end)

  script.on_configuration_changed(function()
    if stage ~= "cap10" then fail("source stage does not accept configuration") end
    check_closure(stage)
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= "source-seeded" then fail("scripted source state is absent") end
    local player, foreign, earned = observe_all(state, "cap-ten configuration")
    assert_player_cap(player, state, "cap-ten configuration")
    assert_foreign_cap(foreign, state, "cap-ten configuration")
    assert_earned_cap(earned, state, "cap-ten configuration")
    assert_seeded_prerequisites(state, "cap-ten configuration")
    state.pre_work = {player = copy(player), foreign = copy(foreign), earned_above_cap = copy(earned)}
    create_lab(state)
    state.phase, state.deadline_tick = "await-ordinary-level-ten", game.tick + DEADLINE_TICKS
  end)

  script.on_event(defines.events.on_research_finished, function(event)
    if stage == "source" then
      local research = event.research
      local source_state = storage[KEY]
      if research == nil or research.name ~= WORKER then
        if type(source_state) == "table" and event.by_script == true and research ~= nil
            and (research.name == PREDECESSOR or research.name == SPACE_SCIENCE or research.name == AUTOMATION_SCIENCE)
            and #source_state.scripted_administrative_events < 16 then
          source_state.scripted_administrative_events[#source_state.scripted_administrative_events + 1] = {
            name = research.name, by_script = true, tick = event.tick, setup_class = "scripted-prerequisite"}
        end
        return
      end
      fail("source stage observed non-administrative research completion")
    end
    local state = storage[KEY]
    if type(state) ~= "table" or state.phase ~= "await-ordinary-level-ten" then return end
    local player = game.forces.player
    if event.research == nil or event.research.force ~= player or event.research.name ~= WORKER then return end
    if event.by_script ~= false then fail("scripted completion cannot satisfy ordinary cap-ten work") end
    state.ordinary_native_completion_count = state.ordinary_native_completion_count + 1
    if state.ordinary_native_completion_count ~= 1 then fail("second worker completion occurred") end
    state.ordinary_events[#state.ordinary_events + 1] = {name = WORKER, by_script = false, tick = event.tick}
    state.phase = "ordinary-level-ten-finished"
  end)

  script.on_event(defines.events.on_research_started, function(event)
    if stage ~= "cap10" then return end
    local state = storage[KEY]
    if type(state) ~= "table" then return end
    local player = game.forces.player
    if event.research ~= nil and event.research.force == player and event.research.name == WORKER
        and type(event.research.level) == "number" and event.research.level > 10 then
      state.level_eleven_start_count = state.level_eleven_start_count + 1
      fail("level eleven research started")
    end
  end)

  script.on_load(function()
    -- Cold snapshots set local flags only and read on one later tick.
    cold_requested, cold_logged = true, false
  end)

  script.on_event(defines.events.on_tick, function()
    if stage == "source" then fail("source create-only stage received an actor tick") end
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
