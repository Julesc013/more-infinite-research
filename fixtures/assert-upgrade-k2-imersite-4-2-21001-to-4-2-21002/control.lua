local from_version, to_version = "4.2.21001", "4.2.21002"
local legacy_name = "recipe-prod-research_material_imersite-1"
local continuation_name = "recipe-prod-research_material_imersite-4"
local copper_name = "recipe-prod-research_copper-1"
local loaded, checked = false, false
local function fail(message) error("MIR K2 4.2.2 maintenance upgrade: " .. message) end
local function close(name, actual, expected)
  if type(actual) ~= "number" or math.abs(actual - expected) > 0.000001 then fail(name .. " changed") end
end
local function cap()
  local value = settings.startup["ips-max-level-research_material_imersite"].value
  if value ~= 0 and value ~= 3 then fail("unsupported cap") end
  return value
end
local function profile(version)
  for name, expected in pairs({base="2.1.21", Krastorio2="2.1.3", ["Krastorio2-spaced-out"]="2.0.13", ["more-infinite-research"]=version}) do
    if script.active_mods[name] ~= expected then fail("wrong input " .. name) end
  end
end
local function domain()
  local force = game.forces.player
  local legacy = force.technologies[legacy_name]
  if not legacy or legacy.prototype.max_level ~= 3 or not legacy.researched then fail("finite earned domain changed") end
  local stage = force.technologies[continuation_name]
  if cap() == 0 then
    if not stage or stage.prototype.max_level ~= 4294967295 or stage.level ~= 5 or stage.researched or not stage.enabled then fail("earned continuation changed") end
    local follows = false
    for _, prerequisite in pairs(stage.prerequisites) do if prerequisite.name == legacy_name then follows = true end end
    if not follows then fail("finite prerequisite lost") end
    local effects = stage.prototype.effects
    if #effects ~= 1 or effects[1].type ~= "change-recipe-productivity" or effects[1].recipe ~= "kr-imersite-powder" then fail("continuation owner changed") end
    close("continuation modifier", effects[1].change, 0.02)
  elseif stage then fail("cap three admitted continuation") end
  close("powder reward", force.recipes["kr-imersite-powder"].productivity_bonus, cap() == 0 and 0.08 or 0.06)
  close("separate crystal reward", force.recipes["kr-imersite-crystal"].productivity_bonus, 0.10)
  return legacy
end
local function queue(name, level, progress)
  local force = game.forces.player
  local selected = force.technologies[name]
  if not selected or selected.level ~= level then fail("queued level changed") end
  local rows = force.research_queue or {}
  if #rows ~= 1 or rows[1].name ~= name or not force.current_research or force.current_research.name ~= name then fail("queue changed") end
  close("research progress", force.research_progress, progress)
  return selected
end
local function marker(stage)
  log("[mir-fixture] K2-422 maintenance state verified stage=" .. stage .. ";cap=" .. cap())
end
local function verify_saved(stage)
  profile(to_version)
  local state = storage.mir_k2_maintenance
  if not state or state.source_version ~= from_version or not state.upgrade_complete then fail("fixture state missing") end
  if cap() ~= state.cap then fail("saved cap changed") end
  local legacy = domain()
  if legacy.level ~= state.legacy_level then fail("earned finite level changed") end
  queue(state.queue_name, state.queue_level, state.upgraded_progress)
  marker(stage)
end
script.on_init(function()
  profile(from_version)
  local force = game.forces.player
  -- Seed earned state on the actual published predecessor. Unlike CCC00,
  -- CCC01 already has a finite legacy domain and (at cap zero) continuation.
  force.research_all_technologies()
  local name, level = cap() == 0 and continuation_name or copper_name, cap() == 0 and 5 or 3
  local selected = force.technologies[name]
  if not selected then fail("queue subject absent") end
  if force.current_research then force.cancel_current_research() end
  selected.level, selected.enabled = level, true
  force.reset_technology_effects()
  local legacy = domain()
  if not force.add_research(selected) then fail("could not queue earned continuation") end
  force.research_queue, force.research_progress = {selected}, 0.42
  queue(name, level, 0.42)
  storage.mir_k2_maintenance = {source_version=from_version, cap=cap(), legacy_level=legacy.level,
    queue_name=name, queue_level=level, count=selected.research_unit_count}
  marker("source")
  log("[mir-fixture] " .. from_version .. " upgrade source proof complete")
end)
script.on_configuration_changed(function()
  profile(to_version)
  local state = storage.mir_k2_maintenance
  if not state or state.source_version ~= from_version or cap() ~= state.cap then fail("source state changed") end
  local selected = game.forces.player.technologies[state.queue_name]
  if not selected then fail("queued research disappeared") end
  state.upgraded_progress = math.min(1, 0.42 * state.count / selected.research_unit_count)
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
    game.server_save("mir-4221002-upgraded")
  end
end)
