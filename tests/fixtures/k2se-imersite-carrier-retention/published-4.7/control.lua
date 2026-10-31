local KEY = "mir5_k2se_imersite_carrier_retention"
local CASE = "k2se-imersite-carrier-retention-source"
local SAVE = "mir5-native-complete"
local FIXTURE = "mir-fixture-mir5-k2se-imersite-carrier-retention"
local EARLY = "mir-k2-imersite-staged-state-1"
local TAIL = "mir-k2-imersite-continuation-state-4"
local POWDER = "kr-imersite-powder"
local FOREIGN = "mir5-k2se-imersite-carrier-foreign"
local UINT32_MAX = 4294967295
local loaded, reported = false, false

local function fail(message) error("[mir5-k2se-imersite-source] " .. message) end
local function close(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) <= 0.000001
end
local function technology(force, name)
  local value = force and force.technologies[name]
  if value == nil or value.valid == false then fail("technology is absent: " .. name) end
  return value
end
local function powder_bonus(force)
  local recipe = force and force.recipes[POWDER]
  if recipe == nil then fail("Imersite powder recipe is absent") end
  return recipe.productivity_bonus
end
local function queue(force)
  local names = {}
  for index, value in ipairs(force.research_queue or {}) do names[index] = value.name end
  return {current=force.current_research and force.current_research.name or false,
    names=names, progress=force.research_progress}
end
local function carrier(force, name, first, formula, label)
  local value = technology(force, name)
  local prototype, effect = value.prototype, value.prototype.effects and value.prototype.effects[1]
  if value.level < first or prototype.hidden ~= true or prototype.max_level ~= UINT32_MAX
      or effect == nil or effect.type ~= "change-recipe-productivity" or effect.recipe ~= POWDER
      or not close(effect.change, 0.02) then
    fail(label .. " carrier identity or effect differs")
  end
  if prototype.level ~= first or prototype.upgrade ~= false then fail(label .. " carrier level identity differs") end
  return value
end
local function settings_match()
  local startup = settings.startup
  return startup["ips-enable-research_material_imersite"].value == true
    and startup["ips-cost-base-research_material_imersite"].value == 200
    and startup["ips-cost-linear-increment-research_material_imersite"].value == 0
    and startup["ips-cost-growth-research_material_imersite"].value == 2
    and startup["ips-max-level-research_material_imersite"].value == 3
    and startup["ips-research-time-research_material_imersite"].value == 30
    and startup["ips-effect-per-level-research_material_imersite"].value == 2
end
local function status(force, label, disabled)
  local early = carrier(force, EARLY, 1, "200*2^(L-1)", label .. " early")
  local tail = carrier(force, TAIL, 4, "1600+200*(L-4)", label .. " tail")
  if early.level ~= 4 or tail.level ~= 6 or early.researched or tail.researched
      or early.visible_when_disabled or tail.visible_when_disabled or not close(powder_bonus(force), 0.10) then
    fail(label .. " native saved-state seed differs")
  end
  if disabled then
    if early.enabled or tail.enabled or not close(tail.saved_progress, 0.27) then
      fail(label .. " independently disabled saved state differs")
    end
    local detached = queue(force)
    if detached.current ~= false or #detached.names ~= 0 or not close(detached.progress, 0) then
      fail(label .. " disabled force has a queue")
    end
    return {early=early.level, tail=tail.level, saved=tail.saved_progress, bonus=powder_bonus(force)}
  end
  if not early.enabled or not tail.enabled or not close(tail.saved_progress, 0) then
    fail(label .. " source player carrier flags differ")
  end
  local active = queue(force)
  if active.current ~= TAIL or #active.names ~= 2 or active.names[1] ~= TAIL or active.names[2] ~= TAIL
      or not close(active.progress, 0.42) then
    fail(label .. " source current/queued investment differs: expected current=" .. TAIL
      .. " queue=[" .. TAIL .. "," .. TAIL .. "] progress=0.42; actual current=" .. tostring(active.current)
      .. " queue=[" .. table.concat(active.names, ",") .. "] progress=" .. tostring(active.progress))
  end
  return {early=early.level, tail=tail.level, queue=active, bonus=powder_bonus(force)}
end
local function assert_source(label)
  local state = storage[KEY]
  if type(state) ~= "table" or state.seed_kind ~= "native-saved-state-not-lab-earned"
      or state.actual_lab_completions ~= 0 or state.k2so_runtime_bridge_exercised ~= false
      or state.source_mir ~= "4.7.21003" or state.fixture_version ~= "0.1.0" then
    fail(label .. " source fixture state differs")
  end
  if not settings_match() then fail(label .. " configured Imersite tuning differs") end
  local player = status(game.forces.player, label .. " player", false)
  local foreign = game.forces[FOREIGN]
  local foreign_state = status(foreign, label .. " foreign", true)
  return player, foreign_state
end
local function marker(stage)
  local player, foreign = assert_source("source marker")
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json({
    case=CASE, stage=stage, status="passed", qualification="native-runner-readback-required",
    witnesses={source_mir="4.7.21003", native_saved_state_seeds=true, source_actual_lab_completions=0,
      k2so_runtime_bridge_exercised=false, player_early_level=player.early, player_tail_level=player.tail,
      player_current=player.queue.current, player_queue_count=#player.queue.names,
      player_research_progress=player.queue.progress, player_powder_productivity=player.bonus,
      foreign_tail_saved_progress=foreign.saved, foreign_disabled=true,
      foreign_powder_productivity=foreign.bonus, configured_base_cost=200, configured_effect_percent=2,
      on_load_read_only=stage == "reload"},
  }))
end

script.on_init(function()
  if script.active_mods.base ~= "2.1.23" or script.active_mods.Krastorio2 ~= "2.1.4"
      or script.active_mods["space-exploration"] ~= "0.7.63" or script.active_mods["Krastorio2-spaced-out"] ~= nil
      or script.active_mods["more-infinite-research"] ~= "4.7.21003" or script.active_mods[FIXTURE] ~= "0.1.0" then
    fail("source requires exact published K2SE F210 input")
  end
  if storage[KEY] ~= nil or not settings_match() then fail("source fixture state or configured tuning differs") end
  local player = game.forces.player
  local early, tail = carrier(player, EARLY, 1, "200*2^(L-1)", "source"), carrier(player, TAIL, 4, "1600+200*(L-4)", "source")
  -- Infinite-technology `level` is the next level.  Four on the first
  -- carrier plus six on the tail retains three plus two 2%-effect levels.
  early.level, tail.level = 4, 6
  local foreign = game.forces[FOREIGN] or game.create_force(FOREIGN)
  foreign.enable_all_prototypes()
  local foreign_early, foreign_tail = carrier(foreign, EARLY, 1, "200*2^(L-1)", "foreign"), carrier(foreign, TAIL, 4, "1600+200*(L-4)", "foreign")
  foreign_early.level, foreign_tail.level = 4, 6
  player.reset_technology_effects()
  foreign.reset_technology_effects()
  -- Establish this deliberately seeded source only after force/effect setup.
  -- Nothing in the successor or cold-reload callbacks repairs investment.
  if player.add_research(tail) ~= true or player.add_research(tail) ~= true then fail("could not queue native saved tail") end
  player.research_progress = 0.42
  foreign_tail.saved_progress = 0.27
  foreign_early.enabled, foreign_tail.enabled = false, false
  foreign_early.visible_when_disabled, foreign_tail.visible_when_disabled = false, false
  storage[KEY] = {phase="source-ready", seed_kind="native-saved-state-not-lab-earned",
    actual_lab_completions=0, k2so_runtime_bridge_exercised=false, source_mir="4.7.21003",
    fixture_version="0.1.0", foreign_force=FOREIGN}
  assert_source("source initialization")
end)

script.on_load(function()
  loaded, reported = true, false
end)

script.on_event(defines.events.on_tick, function()
  local state = storage[KEY]
  if type(state) ~= "table" then fail("source fixture state is absent") end
  if state.phase == "source-ready" then
    assert_source("source initial")
    state.phase = "source-complete"
    marker("initial")
    game.server_save(SAVE)
  elseif state.phase == "source-complete" and loaded and not reported then
    assert_source("source cold reload")
    marker("reload")
    reported = true
  end
end)
