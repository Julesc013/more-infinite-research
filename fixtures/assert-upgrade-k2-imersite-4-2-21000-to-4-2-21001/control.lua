local from_version, to_version = "4.2.21000", "4.2.21001"
local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local stable_name = "recipe-prod-research_copper-1"
local loaded, checked = false, false
local function fail(message) error("MIR K2 published maintenance upgrade: " .. message) end
local function close(name, actual, expected)
  if type(actual) ~= "number" or math.abs(actual - expected) > 0.000001 then
    fail(name .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end
local function profile(version)
  for name, expected in pairs({base="2.1.21", Krastorio2="2.1.3", ["Krastorio2-spaced-out"]="2.0.13", ["more-infinite-research"]=version}) do
    if script.active_mods[name] ~= expected then fail("wrong input " .. name) end
  end
  if settings.startup["ips-max-level-research_material_imersite"].value ~= 0 then fail("expected default Imersite cap") end
end
local function legacy_and_rewards(powder)
  local force = game.forces.player
  local legacy = force.technologies[legacy_name]
  if not legacy or legacy.prototype.max_level ~= 3 or not legacy.researched then fail("completed finite legacy domain changed") end
  close("powder reward", force.recipes["kr-imersite-powder"].productivity_bonus, powder)
  close("separate crystal reward", force.recipes["kr-imersite-crystal"].productivity_bonus, 0.10)
end
local function queue(name, level, progress)
  local force = game.forces.player
  local technology = force.technologies[name]
  if not technology or technology.level ~= level then fail("queued level changed") end
  local rows = force.research_queue or {}
  if #rows ~= 1 or rows[1].name ~= name or not force.current_research or force.current_research.name ~= name then fail("queue changed") end
  close("research progress", force.research_progress, progress)
end
local function continuation(level)
  local force = game.forces.player
  local stage = force.technologies[continuation_name]
  if not stage or stage.prototype.max_level < 4294967295 or stage.level ~= level or not stage.enabled then fail("continuation domain changed") end
  local follows = false
  for _, prerequisite in pairs(stage.prerequisites) do if prerequisite.name == legacy_name then follows = true end end
  if not follows then fail("continuation lost finite prerequisite") end
  local effects = stage.prototype.effects
  if #effects ~= 1 or effects[1].type ~= "change-recipe-productivity" or effects[1].recipe ~= "kr-imersite-powder" then fail("continuation owner changed") end
  close("continuation modifier", effects[1].change, 0.02)
  return stage
end
local function verify_saved(stage)
  profile(to_version)
  local state = storage.mir_k2_maintenance
  if not state or state.source_version ~= from_version or not state.upgrade_complete then fail("fixture state missing") end
  legacy_and_rewards(0.08)
  continuation(5)
  queue(continuation_name, 5, 0.42)
  log("[mir-fixture] K2-421 maintenance state verified stage=" .. stage)
end
script.on_init(function()
  profile(from_version)
  local force = game.forces.player
  -- Published 4.2.0 on this exact 2.1.21 tuple exposes the finite family but
  -- its former 2.1.20-only guard withholds the level-four continuation.
  if force.technologies[continuation_name] then fail("unexpected predecessor continuation") end
  force.research_all_technologies()
  legacy_and_rewards(0.06)
  local stable = force.technologies[stable_name]
  if not stable then fail("stable copper research absent") end
  stable.level = 3
  force.research_queue = {stable}
  force.research_progress = 0.42
  queue(stable_name, 3, 0.42)
  storage.mir_k2_maintenance = {source_version=from_version, count=stable.research_unit_count}
  log("[mir-fixture] K2-421 maintenance state verified stage=source")
  log("[mir-fixture] " .. from_version .. " upgrade source proof complete")
end)
script.on_configuration_changed(function()
  profile(to_version)
  local state = storage.mir_k2_maintenance
  if not state or state.source_version ~= from_version then fail("source state missing") end
  local force = game.forces.player
  local stable = force.technologies[stable_name]
  if not stable then fail("stable research disappeared") end
  queue(stable_name, 3, math.min(1, 0.42 * state.count / stable.research_unit_count))
  legacy_and_rewards(0.06)
  local stage = continuation(4)
  if stage.researched then fail("new continuation already researched") end
  -- Verify preservation first, then complete the newly available level four
  -- using the engine's research transition and retain its next queued level.
  force.research_queue = nil
  stage.researched = true
  force.research_queue = {stage}
  force.research_progress = 0.42
  state.upgrade_complete = true
  verify_saved("upgrade")
  log("[mir-fixture] " .. from_version .. " to " .. to_version .. " upgrade proof complete")
end)
script.on_load(function() loaded = true end)
script.on_event(defines.events.on_tick, function()
  local state = storage.mir_k2_maintenance
  if not state or not state.upgrade_complete then return end
  if loaded and not checked then
    verify_saved("reload")
    log("[mir-fixture] " .. to_version .. " upgraded save reload proof complete archetype=")
    checked = true
  end
  if not state.save_requested then
    state.save_requested = true
    game.server_save("mir-4221001-upgraded")
  end
end)
