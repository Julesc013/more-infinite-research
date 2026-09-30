local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local stable_name = "recipe-prod-research_copper-1"
local powder_recipe = "kr-imersite-powder"
local crystal_recipe = "kr-imersite-crystal"
local expected_progress = 0.42
local pending_upgrade_save = false
local pending_reload_assertion = false

local function fail(message)
  error("MIR K2 2.1.3 Imersite predecessor migration validation failed: " .. message)
end

local function assert_close(name, actual, expected)
  if math.abs((actual or -1) - expected) > 0.000001 then
    fail(name .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function assert_profile()
  local expected = {
    base = "2.1.20",
    Krastorio2 = "2.1.3",
    ["Krastorio2-spaced-out"] = "2.0.13",
    ["more-infinite-research"] = "4.2.21000"
  }
  for name, version in pairs(expected) do
    if script.active_mods[name] ~= version then fail("exact profile differs for " .. name) end
  end
end

local function queue_names(force)
  local names = {}
  for _, entry in ipairs(force.research_queue or {}) do names[#names + 1] = entry.name end
  return names
end

local function assert_recipe_effects()
  local force = game.forces.player
  local powder = force.recipes[powder_recipe]
  local crystal = force.recipes[crystal_recipe]
  if not powder or not crystal then fail("native K2 Imersite recipes are absent") end
  assert_close("legacy powder productivity", powder.productivity_bonus, 0.06)
  assert_close("native crystal productivity", crystal.productivity_bonus, 0.10)
end

local function assert_predecessor_effects()
  local legacy = game.forces.player.technologies[legacy_name]
  -- The pinned predecessor has an infinite prototype with a runtime cap of
  -- three. Level four is its next (capped) level after three earned effects.
  if not legacy or legacy.prototype.max_level < 4294967295 or legacy.level ~= 4 then
    fail("predecessor Imersite levels 1-3 are not complete")
  end
  assert_recipe_effects()
end

local function assert_upgraded_earned_effects()
  local legacy = game.forces.player.technologies[legacy_name]
  if not legacy or legacy.prototype.max_level ~= 3 or not legacy.researched then
    fail("finite legacy Imersite levels 1-3 were not retained")
  end
  assert_recipe_effects()
end

local function assert_stable_queue(stage)
  local force = game.forces.player
  local stable = force.technologies[stable_name]
  if not stable or stable.level ~= 3 then fail("stable copper technology level differs after " .. stage) end
  if not force.current_research or force.current_research.name ~= stable_name then
    fail("current research differs after " .. stage)
  end
  local queue = queue_names(force)
  if #queue ~= 1 or queue[1] ~= stable_name then fail("research queue differs after " .. stage) end
  assert_close("fractional research progress after " .. stage, force.research_progress, expected_progress)
end

local function assert_continuation(stage)
  local force = game.forces.player
  local legacy = force.technologies[legacy_name]
  local continuation = force.technologies[continuation_name]
  if not legacy or not continuation then fail("legacy or continuation technology is absent after " .. stage) end
  if continuation.prototype.max_level < 4294967295 or continuation.level ~= 4
      or continuation.researched or not continuation.enabled then
    fail("level-four continuation is not the available next technology after " .. stage)
  end
  local follows_legacy = false
  for _, prerequisite in pairs(continuation.prerequisites) do
    if prerequisite.name == legacy_name then follows_legacy = true end
  end
  if not follows_legacy then fail("level-four continuation no longer follows the legacy technology") end
  assert_upgraded_earned_effects()
end

local function assert_upgraded(stage)
  assert_profile()
  assert_upgraded_earned_effects()
  assert_continuation(stage)
  assert_stable_queue(stage)
  local state = storage.mir_k2_213_imersite_migration
  if not state or state.progress ~= expected_progress then fail("persisted migration fixture state differs") end
  log("[MIR42_K2_213_IMERSITE_MIGRATION] stage=" .. stage
    .. ";legacy=1-3;powder=0.06;crystal=0.10;continuation_level=4;stable=copper-3;progress=0.42")
end

local function establish_stable_level_three_queue()
  local force = game.forces.player
  local technology = force.technologies[stable_name]
  if not technology then fail("stable copper technology is absent") end
  if force.current_research then force.cancel_current_research() end
  -- Copper is only a stable queue sentinel. Set its exact current level
  -- directly so this fixture need not simulate unrelated production history.
  technology.enabled = true
  technology.level = 3
  technology.researched = false
  if not force.add_research(technology)
      or not force.current_research or force.current_research.name ~= stable_name then
    fail("could not queue stable copper at level three")
  end
  force.research_queue = {technology}
  force.research_progress = expected_progress
end

script.on_init(function()
  assert_profile()
  local force = game.forces.player
  force.research_all_technologies()
  local legacy = force.technologies[legacy_name]
  if not legacy or legacy.prototype.max_level < 4294967295 or legacy.level ~= 2 then
    fail("predecessor initial Imersite level differs")
  end
  legacy.level = 4
  force.reset_technology_effects()
  assert_predecessor_effects()
  establish_stable_level_three_queue()
  storage.mir_k2_213_imersite_migration = {phase = "predecessor", progress = expected_progress}
  assert_stable_queue("predecessor")
  if force.technologies[continuation_name] then fail("predecessor already contains the MIR continuation") end
  log("[MIR42_K2_213_IMERSITE_MIGRATION] stage=predecessor;legacy=1-3;powder=0.06;crystal=0.10;stable=copper-3;progress=0.42")
end)

script.on_configuration_changed(function()
  local state = storage.mir_k2_213_imersite_migration
  if not state or state.phase ~= "predecessor" then return end
  assert_upgraded("configuration-change")
  state.phase = "upgrade-save-pending"
  pending_upgrade_save = true
end)

script.on_load(function()
  local state = storage.mir_k2_213_imersite_migration
  pending_reload_assertion = state and state.phase == "upgraded" or false
end)

script.on_nth_tick(1, function()
  local state = storage.mir_k2_213_imersite_migration
  if pending_upgrade_save then
    pending_upgrade_save = false
    if not state or state.phase ~= "upgrade-save-pending" then fail("upgrade-save state differs") end
    assert_upgraded("upgrade-save")
    state.phase = "upgraded"
    game.server_save("k2-213-imersite-migration-upgraded")
  elseif pending_reload_assertion then
    pending_reload_assertion = false
    if not state or state.phase ~= "upgraded" then fail("upgraded save state is absent on reload") end
    assert_upgraded("reload")
  end
end)
