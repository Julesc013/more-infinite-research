-- Starts from the saved, actually lab-earned published505 Bob-core world.
-- Uses only native APIs and this fixture's own storage/lab. No MIR handlers,
-- MIR storage, selected paid levels, recipe bonuses or upstream recipes are written.
local M = {}
local KEY = "bob_material_preservation"
local FIXTURE = "mir-fixture-mir5-bob-material-preservation"
local CASE = "bob-material-preservation"
local TIN = "recipe-prod-research_material_tin-4"
local BRONZE = "recipe-prod-research_material_bronze-4"
local LEAD = "recipe-prod-research_material_lead-4"
local LAB = "mir5-bob-material-preservation-lab"
local PROBE = "automation"
local FAMILIES = {"tin", "lead", "bronze", "gunmetal", "invar", "nitinol", "copper_tungsten"}
local RECIPES = {"bob-tin-plate", "bob-lead-plate", "bob-bronze-alloy", "bob-gunmetal-alloy",
  "bob-invar-alloy", "bob-nitinol-alloy", "bob-copper-tungsten-alloy"}
local STAGES = {source={fixture="0.1.0", mir="5.0.21005", cap=4},
  unavailable={fixture="0.2.0", mir="5.0.21006", cap=7},
  readmitted={fixture="0.3.0", mir="5.0.21006", cap=7}}
local loaded, logged = false, false
local function fail(message) error("[mir5-bob-material-preservation] " .. message) end
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a-b) < 0.000001 end
local function tech(force, name)
  local value = force.technologies[name]
  if not value or not value.valid then fail("missing technology: " .. name) end
  return value
end
local function names(queue)
  local result = {}
  for i, value in ipairs(queue or {}) do result[i] = value.name end
  return result
end
local function snapshot(force)
  local result = {technologies={}, bonuses={}, current=force.current_research and force.current_research.name or false,
    queue=names(force.research_queue), progress=force.research_progress,
    lead_saved=force.get_saved_technology_progress(LEAD)}
  for _, key in ipairs(FAMILIES) do
    for _, suffix in ipairs{"1", "4"} do
      local id = "recipe-prod-research_material_" .. key .. "-" .. suffix
      local value = tech(force, id)
      result.technologies[id] = {level=value.level, researched=value.researched, enabled=value.enabled}
    end
  end
  for _, recipe in ipairs(RECIPES) do
    local value = force.recipes[recipe]
    if not value then fail("missing paid recipe: " .. recipe) end
    result.bonuses[recipe] = value.productivity_bonus
  end
  return result
end

-- Called by native checks and opposing host controls. Source observations are
-- retained before the candidate is ever loaded; enabled flags are separate policy.
function M.assert_preserved(actual, expected, label, exact_enabled)
  if actual.current ~= expected.current or #actual.queue ~= #expected.queue
      or not near(actual.progress, expected.progress) or not near(actual.lead_saved, expected.lead_saved) then
    fail(label .. " current/queued/detached work changed")
  end
  for i, id in ipairs(expected.queue) do if actual.queue[i] ~= id then fail(label .. " queue order changed") end end
  for id, before in pairs(expected.technologies) do
    local after = actual.technologies[id]
    if not after or after.level ~= before.level or after.researched ~= before.researched then
      fail(label .. " paid native level changed: " .. id)
    end
    if exact_enabled and after.enabled ~= before.enabled then fail(label .. " saved enablement changed: " .. id) end
  end
  for recipe, before in pairs(expected.bonuses) do
    if not near(actual.bonuses[recipe], before) then fail(label .. " earned recipe effect changed: " .. recipe) end
  end
end

local function closure(stage)
  local spec = STAGES[stage]
  if not spec or script.active_mods[FIXTURE] ~= spec.fixture
      or script.active_mods["more-infinite-research"] ~= spec.mir then fail("source/stage identity differs") end
  for _, name in ipairs{"base", "space-age", "elevated-rails", "quality", "recycler"} do
    if script.active_mods[name] ~= "2.1.23" then fail("engine closure differs: " .. name) end
  end
  for name, version in pairs{bobassembly="3.0.2", bobelectronics="3.0.1", bobenemies="3.0.1",
      bobequipment="3.0.0", bobgreenhouse="3.0.1", bobinserters="3.0.0", boblibrary="3.0.1",
      boblogistics="3.0.2", bobmining="3.0.2", bobmodules="3.0.1", bobores="3.0.0",
      bobplates="3.0.2", bobpower="3.0.1", bobrevamp="3.0.1", bobtech="3.0.0",
      bobvehicleequipment="3.0.0", bobwarfare="3.0.2"} do
    if script.active_mods[name] ~= version then fail("full Bob closure differs: " .. name) end
  end
  if settings.startup["ips-max-level-research_material_tin"].value ~= spec.cap
      or settings.startup["mir-settings-profile-import"].value ~= "" then fail("startup cap/import differs") end
end
local function lab(state)
  if not state.lab or not state.lab.valid then fail("owned lab absent") end
  return state.lab, state.lab.get_inventory(defines.inventory.lab_input)
end
function M.set_lab_running(entity, running)
  --2.1.23 active is a read-only aggregate. Only the script-owned flag is writable.
  entity.disabled_by_script = not running
  entity.energy = running and 1000000000 or 0
end
local function fill(state, count)
  local entity, inv = lab(state)
  inv.clear()
  for _, name in ipairs{"automation-science-pack", "space-science-pack"} do
    if inv.insert{name=name, count=count} ~= count then fail("owned lab rejected science") end
  end
  M.set_lab_running(entity, true)
end
local function flags(force, stage, foreign)
  for _, key in ipairs(FAMILIES) do
    local unavailable = key ~= "lead" and not (stage == "readmitted" and key == "tin")
    if stage == "source" then unavailable = false end
    for _, suffix in ipairs{"1", "4"} do
      local id = "recipe-prod-research_material_" .. key .. "-" .. suffix
      local value = tech(force, id)
      if unavailable and value.enabled ~= false then fail("unavailable identity force-enabled: " .. id) end
    end
  end
  if foreign and tech(force, TIN).enabled ~= false then fail("foreign disablement was overwritten") end
end
local function marker(kind, state)
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json{case=CASE, stage=kind, status="passed",
    witnesses={stage=state.stage, paid_families=7, source_completed_levels=28,
      source_partial_science_sets=42, repeated_queue=true, detached_progress=0.27,
      native_reset_observed=state.reset_done == true, useful_readmitted_labs=state.finished or 0,
      source_paid_bonuses=state.source.bonuses, current=snapshot(game.forces.player),
      foreign=snapshot(game.forces[state.foreign_index]), ordinary_tuning_qualified=false}})
end
local function finish(state)
  state.phase = "complete"
  state.final, state.foreign_final = snapshot(game.forces.player), snapshot(game.forces[state.foreign_index])
  marker("initial", state)
  game.server_save("mir5-native-complete")
end
local function setup_source(state)
  local player = game.forces.player
  for i, key in ipairs(FAMILIES) do
    if tech(player, "recipe-prod-research_material_" .. key .. "-4").level ~= 5
        or not near(player.recipes[RECIPES[i]].productivity_bonus, 0.08) then
      fail("input lacks actually earned published source: " .. key)
    end
  end
  if tech(player, TIN).enabled ~= false then fail("source cap4 has no actual cap disablement") end
  local surface = game.surfaces[1]
  local old_labs = surface.find_entities_filtered{position=player.get_spawn_position(surface), name="lab", force=player}
  if #old_labs ~= 1 then fail("exact disposable predecessor lab was not found") end
  M.set_lab_running(old_labs[1], false)
  player.set_saved_technology_progress(LEAD, 0.27)
  local foreign = game.create_force("mir5-bob-material-preservation-foreign")
  tech(foreign, "automation-science-pack").researched = true
  if not foreign.add_research(PROBE) then fail("foreign probe rejected") end
  foreign.research_progress = 0.31
  foreign.set_saved_technology_progress(LEAD, 0.17)
  tech(foreign, TIN).enabled = false
  state.foreign_index = foreign.index
  state.lab = surface.create_entity{name=LAB, position={12, 0}, force=player}
  if not state.lab then fail("could not create owned lab") end
  if tech(player, PROBE).researched then fail("source unrelated probe already researched") end
  player.research_queue = {tech(player, BRONZE), tech(player, BRONZE), tech(player, PROBE)}
  state.phase, state.started = "earn-partial", game.tick
  fill(state, 42)
  game.speed = 16
end

function M.apply(stage)
  script.on_init(function()
    if stage ~= "source" then fail("successor cannot initialize a fresh world") end
    storage[KEY] = {phase="source-pending", stage=stage, finished=0}
  end)
  script.on_configuration_changed(function()
    closure(stage)
    local state = storage[KEY]
    if stage == "source" then
      if not state then storage[KEY] = {phase="source-pending", stage=stage, finished=0} end
      return
    end
    local prior = stage == "unavailable" and "source" or "unavailable"
    if not state or state.phase ~= "complete" or state.stage ~= prior then fail("missing exact previous fixture stage") end
    M.assert_preserved(snapshot(game.forces.player), state.final, "configuration player")
    M.assert_preserved(snapshot(game.forces[state.foreign_index]), state.foreign_final, "configuration foreign")
    state.phase, state.stage, state.started = "observe-transition", stage, game.tick
    flags(game.forces.player, stage, false)
    flags(game.forces[state.foreign_index], stage, true)
    if stage == "readmitted" then
      if tech(game.forces.player, TIN).enabled ~= true then fail("qualified cap right was not readmitted") end
      game.forces.player.research_queue = {tech(game.forces.player, TIN), tech(game.forces.player, TIN),
        tech(game.forces.player, TIN), tech(game.forces.player, TIN)}
      state.phase, state.finished = "useful-research", 0
      fill(state, 400)
    else
      -- An available current research would consume these and change42%.
      fill(state, 2)
    end
  end)
  script.on_load(function() loaded, logged = true, false end)
  script.on_event(defines.events.on_research_finished, function(event)
    local state = storage[KEY]
    if not state or not event.research or event.research.force ~= game.forces.player then return end
    if state.phase ~= "useful-research" or event.research.name ~= TIN then fail("unexpected native lab completion") end
    state.finished = state.finished + 1
    if state.finished > 3 then fail("research passed the finite cap7") end
    if state.finished == 3 then
      M.set_lab_running(state.lab, false)
      state.phase, state.started = "observe-cap", game.tick
    end
  end)
  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if not state then fail("fixture state absent") end
    closure(stage)
    if state.phase == "complete" then
      if loaded and not logged then
        M.assert_preserved(snapshot(game.forces.player), state.final, "cold reload player", true)
        M.assert_preserved(snapshot(game.forces[state.foreign_index]), state.foreign_final, "cold reload foreign", true)
        flags(game.forces.player, stage, false); flags(game.forces[state.foreign_index], stage, true)
        marker("reload", state); logged = true
      end
      return
    end
    if state.phase == "source-pending" then setup_source(state); return end
    if game.tick - state.started > 3600 then fail("bounded fixture did not finish") end
    local entity, inv = lab(state)
    entity.energy = 1000000000
    if state.phase == "earn-partial" then
      if not inv.is_empty() then return end
      M.set_lab_running(entity, false)
      local player = game.forces.player
      if player.current_research.name ~= BRONZE or not near(player.research_progress, 0.42)
          or #player.research_queue ~= 3 or player.research_queue[2].name ~= BRONZE then
        fail("42 actual consumed science sets/repeated queue were not observed")
      end
      state.source = snapshot(player)
      state.foreign_source = snapshot(game.forces[state.foreign_index])
      finish(state)
    elseif state.phase == "observe-transition" then
      M.assert_preserved(snapshot(game.forces.player), state.source, "unavailable player")
      M.assert_preserved(snapshot(game.forces[state.foreign_index]), state.foreign_source, "unavailable foreign")
      flags(game.forces.player, stage, false); flags(game.forces[state.foreign_index], stage, true)
      if game.tick - state.started == 20 then
        game.forces.player.reset_technology_effects(); state.reset_done = true
      elseif game.tick - state.started >= 40 then
        M.set_lab_running(entity, false)
        finish(state)
      end
    elseif state.phase == "observe-cap" and game.tick - state.started >= 40 then
      local player = game.forces.player
      if tech(player, TIN).level ~= 8 or tech(player, TIN).enabled ~= false
          or player.add_research(TIN) ~= false then fail("finite cap7 did not reject the next native research") end
      for i, recipe in ipairs(RECIPES) do
        if not near(player.recipes[recipe].productivity_bonus, i == 1 and 0.14 or 0.08) then
          fail("readmission paid/useful effect differs: " .. recipe)
        end
      end
      if not near(player.get_saved_technology_progress(BRONZE), 0.42)
          or not near(player.get_saved_technology_progress(LEAD), 0.27) then fail("readmission lost paused work") end
      M.assert_preserved(snapshot(game.forces[state.foreign_index]), state.foreign_source, "readmitted foreign")
      finish(state)
    end
  end)
end

return M
