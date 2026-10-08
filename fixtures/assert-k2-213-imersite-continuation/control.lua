local expected_mods = {
  Krastorio2 = "2.1.3",
  ["Krastorio2-spaced-out"] = "2.0.13",
  ["more-infinite-research"] = "4.2.21001"
}
local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local powder_recipe = "kr-imersite-powder"
local crystal_recipe = "kr-imersite-crystal"
local loaded_from_save = false

local function fail(message)
  error("MIR K2 2.1.3 Imersite continuation runtime validation failed: " .. message)
end

local function assert_close(name, actual, expected)
  if math.abs(actual - expected) > 0.000001 then
    fail(name .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

local function assert_profile()
  if script.active_mods.base ~= "2.1.20" and script.active_mods.base ~= "2.1.21" then fail("unexpected exact engine") end
  for name, version in pairs(expected_mods) do
    if script.active_mods[name] ~= version then fail("unexpected exact profile " .. name) end
  end
end

local function assert_state(stage)
  local force = game.forces.player
  local legacy = force.technologies[legacy_name]
  local powder = force.recipes[powder_recipe]
  local crystal = force.recipes[crystal_recipe]
  if not legacy or not stage then fail("required Imersite technology absent") end
  if not legacy.researched or legacy.prototype.max_level ~= 3 then
    fail("legacy stage did not retain its completed finite level-three domain")
  end
  if stage.level ~= 5 or stage.prototype.max_level < 4294967295 then
    fail("continuation did not retain the completed level-four state")
  end
  if not force.current_research or force.current_research.name ~= continuation_name then
    fail("continuation was not the queued next level")
  end
  assert_close("continuation progress", force.research_progress, 0.42)
  assert_close("MIR powder bonus", powder.productivity_bonus, 0.08)
  assert_close("native crystal bonus", crystal.productivity_bonus, 0.1)
end

script.on_init(function()
  assert_profile()
  local force = game.forces.player
  force.research_all_technologies()
  local legacy = force.technologies[legacy_name]
  local stage = force.technologies[continuation_name]
  if not legacy or not stage then fail("required Imersite staged technology absent") end
  -- Per the runtime API, assigning level five applies all advancement perks
  -- through level four.  It leaves level five as the next research target.
  stage.level = 5
  force.reset_technology_effects()
  force.research_queue = {stage}
  if not force.current_research or force.current_research.name ~= continuation_name then
    fail("could not queue the level-five continuation target")
  end
  force.research_progress = 0.42
  storage.mir42_k2_213_imersite_continuation = {}
  assert_state(stage)
  log("[MIR42_K2_213_IMERSITE_CONTINUATION] stage=initial;completed_level=4;next_level=5;bonus=0.08;progress=0.42")
end)

script.on_load(function()
  loaded_from_save = true
end)

script.on_event(defines.events.on_tick, function()
  local state = storage.mir42_k2_213_imersite_continuation
  if not state then return end
  if not loaded_from_save then return end
  local stage = game.forces.player.technologies[continuation_name]
  assert_profile()
  assert_state(stage)
  storage.mir42_k2_213_imersite_continuation = nil
  log("[MIR42_K2_213_IMERSITE_CONTINUATION] stage=reload;completed_level=4;next_level=5;bonus=0.08;progress=0.42")
end)
