-- Disposable paid K2SO progression. Only this fixture's lab entity, queue setup,
-- native prerequisites and its own storage are written; MIR owns migration.
local M = {}
local KEY = "mir5_k2so_material_continuation"
local FIXTURE = "mir-fixture-k2so-material-continuation"
local LAB = "lab"
local PROBE = "mir-k2so-material-continuation-probe"
local FOREIGN = "mir-k2so-material-continuation-foreign"
local CASE = "k2so-material-continuation"
local UINT32_MAX = 4294967295
local LAB_SPEED_ACCELERATION = 115199
local WHITE = "space-science-pack"
local PACKS = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", WHITE}
local MATERIALS = {
  {key="rare_metals", recipes={"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals"}, blue=true},
  {key="silicon", recipes={"kr-silicon"}},
  {key="glass", recipes={"kr-glass"}, blue=true},
}
local PREREQUISITES = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "kr-rare-metal-processing", "kr-enriched-ores", "kr-silicon-processing", "kr-stone-processing", WHITE}
local STAGES = {
  source={version="0.1.0", mir="5.0.21017", cap=0},
  upgrade={version="0.2.0", mir="5.0.21018", cap=0, prior="source"},
  finite={version="0.3.0", mir="5.0.21018", cap=3, prior="upgrade"},
  relaxed={version="0.4.0", mir="5.0.21018", cap=0, prior="finite"},
}
local function id(material, suffix) return "recipe-prod-research_material_" .. material.key .. "-" .. suffix end
local SILICON = id(MATERIALS[2], 4)
local function fail(message) error("[mir-k2so-material-continuation] " .. message, 3) end
local function near(a, b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<=0.000001 end
local function tech(force, name)
  local value = force.technologies[name]
  if not value or value.valid == false then fail("missing native technology: " .. name) end
  return value
end
local function queue_names(force)
  local out = {}
  for index, value in ipairs(force.research_queue or {}) do out[index] = value.name end
  return out
end
local function equal_queue(a, b, label)
  if #a ~= #b then fail(label .. " queue size changed") end
  for index, name in ipairs(b) do if a[index] ~= name then fail(label .. " queue order changed") end end
end
local function frame(force)
  local out = {technologies={}, bonuses={}, current=force.current_research and force.current_research.name or false,
    queue=queue_names(force), progress=force.research_progress,
    laboratory_speed_modifier=force.laboratory_speed_modifier,
    laboratory_productivity_bonus=force.laboratory_productivity_bonus}
  local function add(name)
    local value = tech(force, name)
    out.technologies[name] = {level=value.level, researched=value.researched, enabled=value.enabled,
      visible=value.visible_when_disabled, saved_progress=value.saved_progress, maximum=value.prototype.max_level}
  end
  for _, material in ipairs(MATERIALS) do
    add(id(material, 1))
    if force.technologies[id(material, 4)] then add(id(material, 4)) end
    for _, recipe in ipairs(material.recipes) do
      local value = force.recipes[recipe]
      if not value then fail("missing native recipe: " .. recipe) end
      out.bonuses[recipe] = value.productivity_bonus
    end
  end
  add(PROBE)
  return out
end
local function paid(actual, expected, label)
  for name, before in pairs(expected.technologies) do
    local after = actual.technologies[name]
    if not after or after.level ~= before.level or after.researched ~= before.researched
        or after.maximum ~= before.maximum then fail(label .. " paid level changed: " .. name) end
  end
  for name, before in pairs(expected.bonuses) do
    if not near(actual.bonuses[name], before) then fail(label .. " paid recipe changed: " .. name) end
  end
end
function M.assert_snapshot(actual, expected, label)
  paid(actual, expected, label)
  for name in pairs(actual.technologies) do
    if not expected.technologies[name] then fail(label .. " unexpected technology: " .. name) end
  end
  for name, before in pairs(expected.technologies) do
    local after = actual.technologies[name]
    if after.enabled ~= before.enabled or after.visible ~= before.visible
        or not near(after.saved_progress, before.saved_progress) then fail(label .. " saved flags/work changed: " .. name) end
  end
  if actual.current ~= expected.current or not near(actual.progress, expected.progress) then
    fail(label .. " current research changed")
  end
  if actual.laboratory_speed_modifier ~= expected.laboratory_speed_modifier
      or actual.laboratory_productivity_bonus ~= expected.laboratory_productivity_bonus then
    fail(label .. " laboratory modifiers changed")
  end
  equal_queue(actual.queue, expected.queue, label)
end

-- Cap cancellation preserves paid work, not forbidden queued intentions.
-- `uncapped` is the observed frame before tightening, including foreign flags.
function M.assert_transition(actual, before, stage, label, foreign, uncapped)
  paid(actual, before, label)
  for name, value in pairs(actual.technologies) do
    local prior = before.technologies[name]
    if not prior then fail(label .. " unexpected transition technology") end
    local tail = name:sub(-2) == "-4"
    if tail then
      local enabled = stage == "relaxed" and not foreign
      local visible = stage == "finite" or uncapped.technologies[name].visible
      if value.enabled ~= enabled or value.visible ~= visible then fail(label .. " cap ownership changed: " .. name) end
    elseif value.enabled ~= prior.enabled or value.visible ~= prior.visible then
      fail(label .. " unselected flags changed: " .. name)
    end
    local expected_work = stage == "finite" and not foreign and name == SILICON and before.progress or prior.saved_progress
    if not near(value.saved_progress, expected_work) then fail(label .. " suspended work changed: " .. name) end
  end
  if stage == "finite" and not foreign then
    if actual.current ~= PROBE or not near(actual.progress, before.technologies[PROBE].saved_progress) then
      fail(label .. " cancellation changed eligible current work")
    end
    equal_queue(actual.queue, {PROBE}, label)
  else
    if actual.current ~= before.current or not near(actual.progress, before.progress) then
      fail(label .. " transition changed current work")
    end
    equal_queue(actual.queue, before.queue, label)
  end
end

local function closure(stage)
  local expected = STAGES[stage]
  if not expected or script.active_mods[FIXTURE] ~= expected.version
      or script.active_mods["more-infinite-research"] ~= expected.mir then fail("stage/package identity differs") end
  for _, name in ipairs{"base", "space-age", "quality", "recycler", "elevated-rails"} do
    if script.active_mods[name] ~= "2.1.24" then fail("official engine closure differs: " .. name) end
  end
  for name, version in pairs{Krastorio2="2.1.4", ["Krastorio2-spaced-out"]="2.0.19",
      Krastorio2Assets="2.1.0", ["k2so-assets"]="1.0.7", flib="0.17.2",
      Krastorio2MenuSimulations="2.1.0", ["xy-k2so-enhancements-nulls-fork"]="0.8.3"} do
    if script.active_mods[name] ~= version then fail("K2SO closure differs: " .. name) end
  end
  local values = {enable=true, ["cost-base"]=200, ["cost-linear-increment"]=0, ["cost-growth"]=2,
    ["research-time"]=30, ["effect-per-level"]=2, ["max-level"]=expected.cap}
  for _, material in ipairs(MATERIALS) do
    for key, value in pairs(values) do
      local setting = settings.startup["ips-" .. key .. "-research_material_" .. material.key]
      if not setting or setting.value ~= value then fail("effective material setting differs: " .. key) end
    end
  end
  if settings.startup["mir-settings-profile-import"].value ~= ""
      or settings.startup["mir-science-pack-ingredient-policy"].value ~= "configured"
      or game.difficulty_settings.technology_price_multiplier ~= 1 then fail("profile or price differs") end
end

local function check_materials(force, stage, levels, bonus, foreign)
  for _, material in ipairs(MATERIALS) do
    local early = tech(force, id(material, 1))
    if early.level ~= (foreign and 1 or 3) or early.researched ~= not foreign
        or early.prototype.max_level ~= 3 then fail("finite material cursor changed") end
    local tail = force.technologies[id(material, 4)]
    if stage == "source" then
      if tail ~= nil then fail("published predecessor unexpectedly supplies a continuation") end
    elseif not tail or tail.level ~= levels or tail.researched
        or tail.prototype.max_level ~= UINT32_MAX then fail("continuation cursor changed") end
    for _, recipe in ipairs(material.recipes) do
      if not near(force.recipes[recipe].productivity_bonus, bonus) then fail("material bonus differs: " .. recipe) end
    end
  end
end
local function assert_lab_baseline(state, label)
  local force=game.forces.player
  if type(state.lab_speed_baseline)~="number" or state.lab_speed_baseline~=state.lab_speed_baseline
      or state.lab_speed_baseline==math.huge or state.lab_speed_baseline==-math.huge
      or type(state.lab_productivity_baseline)~="number" or state.lab_productivity_baseline~=0 then
    fail("laboratory baseline is invalid")
  end
  if force.laboratory_speed_modifier~=state.lab_speed_baseline
      or force.laboratory_productivity_bonus~=0 then
    fail(label .. " laboratory baseline changed")
  end
end
local function assert_zero_productivity(force, label)
  if type(force.laboratory_productivity_bonus)~="number" or force.laboratory_productivity_bonus~=0 then
    fail(label .. " laboratory productivity baseline differs")
  end
end
local function accelerate_lab(state)
  local force=game.forces.player
  assert_lab_baseline(state,"before ordinary work")
  force.laboratory_speed_modifier=state.lab_speed_baseline+LAB_SPEED_ACCELERATION
  if force.laboratory_speed_modifier~=state.lab_speed_baseline+LAB_SPEED_ACCELERATION then
    fail("temporary laboratory speed differs")
  end
end
local function restore_lab_speed(state)
  local force=game.forces.player
  force.laboratory_speed_modifier=state.lab_speed_baseline
  assert_lab_baseline(state,"restored")
end
local function set_running(state, running)
  if not state.lab or state.lab.valid == false or state.lab.name~=LAB then fail("named original lab is absent") end
  state.lab.disabled_by_script = not running
  if running then
    local capacity = state.lab.electric_buffer_size
    if type(capacity)~="number" or capacity~=capacity or capacity<=0 or capacity==math.huge then
      fail("owned lab electric buffer is invalid")
    end
    state.lab.energy=capacity
  else state.lab.energy=0 end
end
local function inventory(state)
  local value = state.lab.get_inventory(defines.inventory.lab_input)
  if not value then fail("owned lab inventory is absent") end
  return value
end
local function refill(state)
  local inv = inventory(state)
  for _, pack in ipairs(PACKS) do
    local remaining = state.remaining[pack] or 0
    if remaining > 0 then
      local inserted = inv.insert{name=pack, count=remaining}
      if type(inserted) ~= "number" or inserted < 0 or inserted > remaining or inserted % 1 ~= 0 then
        fail("invalid science insertion")
      end
      state.remaining[pack] = remaining - inserted
      state.inserted[pack] = (state.inserted[pack] or 0) + inserted
    end
  end
end
local function budget_complete(state)
  local inv = inventory(state)
  for _, pack in ipairs(PACKS) do
    if (state.remaining[pack] or 0) ~= 0 or inv.get_item_count(pack) ~= 0 then return false end
  end
  return true
end
local function begin_budget(state, count, packs)
  if not inventory(state).is_empty() then fail("previous science budget remains") end
  state.remaining, state.inserted, state.budget = {}, {}, {}
  for _, pack in ipairs(packs) do state.remaining[pack], state.budget[pack] = count, count end
  refill(state)
  set_running(state, true)
end
local function finish_budget(state)
  if not budget_complete(state) then fail("ordinary completion did not consume its exact science budget") end
  for _, pack in ipairs(PACKS) do
    local expected = state.budget[pack] or 0
    if (state.inserted[pack] or 0) ~= expected then fail("science insertion total differs") end
    state.consumed[pack] = (state.consumed[pack] or 0) + expected
  end
end
local function work_plan(stage)
  local jobs = {}
  if stage == "source" then
    for _, material in ipairs(MATERIALS) do
      for level=1,3 do
        local science = {PACKS[1], PACKS[2]}
        if material.blue then science[#science+1] = PACKS[3] end
        jobs[#jobs+1] = {name=id(material,1), level=level, count=200*2^(level-1), budget=200*2^(level-1), science=science, progress=0}
      end
    end
  elseif stage == "upgrade" then
    for _, material in ipairs(MATERIALS) do
      jobs[#jobs+1] = {name=id(material,4), level=4, count=1600, budget=1600, science={WHITE}, progress=0}
    end
  elseif stage == "relaxed" then
    jobs = {{name=PROBE, level=1, count=20, budget=20, science={PACKS[1]}, progress=0},
      {name=SILICON, level=5, count=1800, budget=1440, science={WHITE}, progress=.2},
      {name=SILICON, level=6, count=2000, budget=2000, science={WHITE}, progress=0}}
  end
  return jobs
end
local function start_job(state)
  local job = work_plan(state.stage)[state.work_index]
  if not job then return false end
  local force, value = game.forces.player, tech(game.forces.player, job.name)
  assert_lab_baseline(state,"ordinary work")
  if value.level ~= job.level or value.research_unit_count ~= job.count or not value.enabled then
    fail("ordinary next research cursor/count/enablement differs")
  end
  if not force.current_research and not force.add_research(job.name) then fail("ordinary research was refused") end
  if not force.current_research or force.current_research.name ~= job.name or not near(force.research_progress, job.progress) then
    fail("ordinary research did not retain its own starting work")
  end
  accelerate_lab(state)
  state.phase, state.job_finished = "work", false
  begin_budget(state, job.budget, job.science)
  return true
end
local function settle(state)
  set_running(state, false)
  restore_lab_speed(state)
  if state.foreign_guard then M.assert_snapshot(frame(game.forces[state.foreign_index]),state.foreign_guard,"working foreign") end
  state.phase, state.settle_tick = "settle", game.tick
  state.player, state.foreign = frame(game.forces.player), frame(game.forces[state.foreign_index])
end
local function marker(kind, state)
  local expected = {source={9,4200,4200,2800,0}, upgrade={3,0,0,0,5160},
    finite={0,0,0,0,0}, relaxed={3,20,0,0,3440}}
  local counts=expected[state.stage]
  if not counts or state.finished~=counts[1] then fail("endpoint ordinary completion count differs") end
  for index,pack in ipairs(PACKS) do
    if (state.consumed[pack] or 0)~=counts[index+1] then fail("endpoint science budget differs: " .. pack) end
  end
  log("[MIR5_NATIVE_FIXTURE] RESULT " .. helpers.table_to_json{
    case=CASE, stage=kind, status="passed", role=state.stage,
    witnesses={actual_lab_completions=state.finished, source_finite_completions=9,
      science_consumed=state.consumed, material_count_time_effect_unchanged=true,
      fixture_accelerates_force_speed_only=true, laboratory_speed_baseline=state.lab_speed_baseline,
      laboratory_speed_acceleration=LAB_SPEED_ACCELERATION, ordinary_elapsed_timing_qualified=false,
      physical_manufacturing_observed=false, player=state.player, foreign=state.foreign,
      on_load_read_only=kind=="reload"}})
end

function M.apply(stage)
  local expected = STAGES[stage]
  if not expected then fail("unknown fixture stage") end
  local loaded, reported, setup_grant = false, false, nil
  script.on_init(function()
    if stage ~= "source" then fail("successor cannot initialize a fresh world") end
    closure(stage)
    if storage[KEY] ~= nil then fail("source fixture state already exists") end
    storage[KEY] = {stage=stage, phase="setup", started=game.tick, finished=0, work_index=1, consumed={}, setup_grants={}}
  end)
  script.on_configuration_changed(function()
    if stage == "source" then fail("source cannot accept a configuration transition") end
    closure(stage)
    local state = storage[KEY]
    if not state or state.stage ~= expected.prior or state.phase ~= "complete" then fail("protected predecessor stage differs") end
    assert_lab_baseline(state,"configuration")
    assert_zero_productivity(game.forces[state.foreign_index],"configuration foreign")
    local player, foreign = frame(game.forces.player), frame(game.forces[state.foreign_index])
    if stage == "upgrade" then
      paid(player, state.player, "upgrade player")
      paid(foreign, state.foreign, "upgrade foreign")
      for _, prior in ipairs{{actual=player, before=state.player}, {actual=foreign, before=state.foreign}} do
        for name, value in pairs(prior.before.technologies) do
          local after = prior.actual.technologies[name]
          if after.enabled ~= value.enabled or after.visible ~= value.visible or not near(after.saved_progress,value.saved_progress) then
            fail("upgrade changed an existing flag or saved work")
          end
        end
        if prior.actual.current ~= prior.before.current or not near(prior.actual.progress,prior.before.progress) then fail("upgrade changed current work") end
        equal_queue(prior.actual.queue, prior.before.queue, "upgrade")
      end
      check_materials(game.forces.player, stage, 4, .06, false)
      check_materials(game.forces[state.foreign_index], stage, 4, 0, true)
      for _, material in ipairs(MATERIALS) do
        local value = tech(game.forces[state.foreign_index],id(material,4))
        value.enabled, value.visible_when_disabled = false, false
      end
    else
      M.assert_transition(player, state.player, stage, "player", false, state.uncapped_player)
      M.assert_transition(foreign, state.foreign, stage, "foreign", true, state.uncapped_foreign)
    end
    state.foreign_guard=frame(game.forces[state.foreign_index])
    state.stage, state.started, state.finished, state.work_index, state.consumed = stage, game.tick, 0, 1, {}
    if stage == "finite" then settle(state) else state.phase = "begin" end
  end)
  script.on_load(function() loaded, reported = true, false end)
  script.on_event(defines.events.on_research_finished, function(event)
    local state = storage[KEY]
    if not state or not event.research or event.research.force ~= game.forces.player then return end
    if state.phase=="setup" and setup_grant==event.research and event.by_script==true then
      state.setup_grants[#state.setup_grants+1]=event.research.name
      return
    end
    local selected=event.research.name==PROBE
    for _,material in ipairs(MATERIALS) do
      if event.research.name==id(material,1) or event.research.name==id(material,4) then selected=true end
    end
    if not selected then return end
    local job = work_plan(stage)[state.work_index]
    if state.phase ~= "work" or state.job_finished or not job or event.research.name ~= job.name
        or event.by_script~=false or event.research~=tech(game.forces.player,job.name) then
      fail("unexpected ordinary completion")
    end
    set_running(state, false)
    restore_lab_speed(state)
    state.job_finished, state.finished = true, state.finished+1
  end)
  script.on_event(defines.events.on_tick, function()
    local state = storage[KEY]
    if not state or state.stage ~= stage then fail("fixture state/stage is absent") end
    closure(stage)
    if state.phase == "complete" then
      if loaded and not reported then
        M.assert_snapshot(frame(game.forces.player),state.player,"cold player")
        M.assert_snapshot(frame(game.forces[state.foreign_index]),state.foreign,"cold foreign")
        if not inventory(state).is_empty() or not state.lab.disabled_by_script then fail("cold lab state changed") end
        marker("reload",state); reported=true
      end
      return
    end
    if game.tick-state.started>36000 then fail("bounded ordinary research deadline exceeded") end
    if state.phase == "setup" then
      if game.tick-state.started<2 then return end
      local force = game.forces.player
      state.lab_speed_baseline=force.laboratory_speed_modifier
      state.lab_productivity_baseline=force.laboratory_productivity_bonus
      assert_lab_baseline(state,"source setup")
      for _, name in ipairs(PREREQUISITES) do
        setup_grant=tech(force,name)
        if not setup_grant.researched then setup_grant.researched=true end
        setup_grant=nil
      end
      for _, material in ipairs(MATERIALS) do
        local value=tech(force,id(material,1))
        if value.level~=1 or value.researched or not value.enabled or force.technologies[id(material,4)]~=nil then fail("published initial material state differs") end
        for _, recipe in ipairs(material.recipes) do if not near(force.recipes[recipe].productivity_bonus,0) then fail("source has unearned material bonus") end end
      end
      local foreign=game.create_force(FOREIGN)
      assert_zero_productivity(foreign,"foreign setup")
      state.foreign_index=foreign.index
      for _, material in ipairs(MATERIALS) do
        local value=tech(foreign,id(material,1)); value.enabled,value.visible_when_disabled=false,false
      end
      check_materials(foreign,stage,nil,0,true)
      state.foreign_guard=frame(foreign)
      state.lab=game.surfaces[1].create_entity{name=LAB,position={0,0},force=force}
      set_running(state,false)
      state.phase="begin"
    end
    if state.phase == "begin" then
      if game.tick-state.started<2 then return end
      if stage=="relaxed" then
        local force=game.forces.player
        if not force.add_research(SILICON) or not force.add_research(SILICON) then fail("relaxed queue rejected native silicon") end
        equal_queue(queue_names(force),{PROBE,SILICON,SILICON},"relaxed append")
        if force.current_research.name~=PROBE or not near(force.research_progress,0) then fail("append changed eligible work") end
      end
      start_job(state); return
    end
    if state.phase == "work" then
      if not state.job_finished then set_running(state,true); refill(state); return end
      finish_budget(state)
      state.work_index=state.work_index+1
      if start_job(state) then return end
      if stage=="source" then
        check_materials(game.forces.player,stage,nil,.06,false)
        settle(state)
      elseif stage=="upgrade" then
        check_materials(game.forces.player,stage,5,.08,false)
        local force=game.forces.player
        if not force.add_research(SILICON) or not force.add_research(SILICON) or not force.add_research(PROBE) then fail("partial queue was refused") end
        equal_queue(queue_names(force),{SILICON,SILICON,PROBE},"partial start")
        if tech(force,SILICON).research_unit_count~=1800 or not near(force.research_progress,0) then fail("partial native price differs") end
        accelerate_lab(state)
        state.phase="partial"; begin_budget(state,360,{WHITE})
      else
        local force=game.forces.player
        if tech(force,SILICON).level~=7 or tech(force,SILICON).researched or not near(force.recipes["kr-silicon"].productivity_bonus,.12)
            or tech(force,PROBE).researched~=true or force.current_research~=nil or #force.research_queue~=0 then fail("relaxed completions differ") end
        for _, material in ipairs{MATERIALS[1],MATERIALS[3]} do
          if tech(force,id(material,4)).level~=5 then fail("unselected continuation changed") end
          for _, recipe in ipairs(material.recipes) do if not near(force.recipes[recipe].productivity_bonus,.08) then fail("unselected bonus changed") end end
        end
        M.assert_snapshot(frame(game.forces[state.foreign_index]),state.uncapped_foreign,"relaxed foreign")
        settle(state)
      end
      return
    end
    if state.phase=="partial" then
      set_running(state,true); refill(state)
      if not budget_complete(state) then return end
      set_running(state,false); restore_lab_speed(state); finish_budget(state)
      local force=game.forces.player
      if not force.current_research or force.current_research.name~=SILICON or not near(force.research_progress,.2) then fail("genuine twenty-percent material work was not observed") end
      equal_queue(queue_names(force),{SILICON,SILICON,PROBE},"partial completion")
      settle(state)
      state.uncapped_player,state.uncapped_foreign=state.player,state.foreign
      return
    end
    if state.phase=="settle" and game.tick-state.settle_tick>=2 then
      M.assert_snapshot(frame(game.forces.player),state.player,"settled player")
      M.assert_snapshot(frame(game.forces[state.foreign_index]),state.foreign,"settled foreign")
      if not inventory(state).is_empty() then fail("unaccounted science remains at save") end
      state.phase="complete"
      marker("initial",state)
      game.server_save("mir5-native-complete")
      loaded,reported=false,true
    end
  end)
end

return M
