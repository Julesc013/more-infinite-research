-- The provider and this observer are synthetic test inputs, not the unnamed
-- reported planet. Prerequisites are seeded; MIR levels are earned by a lab.
local MAIN, FOREIGN = "worker-robots-storage-5", "mir-worker-test-unrelated"
local started, finish_tick, requested_mode

-- Server execution creates the protected save needed by upgrade/reload tests.
-- --test-save remains useful for read-only controls but does not produce an
-- autosave on the qualified 2.1.24 headless test runner.
remote.add_interface("mir-worker-storage-native-observer", {
  begin=function(mode)
    assert(not started and not requested_mode, "fixture already started")
    assert(mode=="source" or mode=="successor" or mode=="fresh" or mode=="reload", "unknown test mode")
    requested_mode=mode
    game.speed=16
  end
})

local function completed(technology)
  return technology.level - 5 + (technology.researched and 1 or 0)
end

local function facts(stage)
  local force = game.forces.player
  local main, finite = force.technologies[MAIN], force.technologies["worker-robots-storage-4"]
  local queue = {}
  for _, row in ipairs(force.research_queue or {}) do queue[#queue+1] = row.name end
  return {stage=stage, engine=helpers.game_version, mods=script.active_mods, tick=game.tick,
    next_level=main.level, researched=main.researched, completed=completed(main), enabled=main.enabled,
    worker_bonus=force.worker_robots_storage_bonus, finite_researched=finite.researched,
    finite_maximum=finite.prototype.max_level, finite_effect=finite.prototype.effects[1].modifier,
    research_progress=force.research_progress, saved_progress=main.saved_progress,
    current=force.current_research and force.current_research.name, queue=queue,
    foreign_progress=force.technologies[FOREIGN].saved_progress,
    native_lab_completions=storage.worker_test.completions,
    prototype={count_formula=main.prototype.research_unit_count_formula,
      research_time=main.prototype.research_unit_energy, effects=main.prototype.effects,
      ingredients=main.prototype.research_unit_ingredients}}
end

local function report(stage)
  local text = helpers.table_to_json(facts(stage))
  helpers.write_file("worker-storage/"..stage..".json",text,false)
  log("MIR_WORKER_NATIVE "..text)
end

local function preserved()
  local force, state = game.forces.player, storage.worker_test
  local main, finite = force.technologies[MAIN], force.technologies["worker-robots-storage-4"]
  assert(completed(main)==state.completions,"completed MIR levels changed")
  assert(force.worker_robots_storage_bonus==5+2*state.completions,"earned carrying capacity changed")
  assert(finite.researched and finite.prototype.max_level==4 and finite.prototype.effects[1].modifier==2,
    "foreign finite contribution changed")
  assert(force.current_research==main and math.abs(force.research_progress-.42)<1e-8,"current partial work changed")
  assert(#force.research_queue==2 and force.research_queue[2].name==FOREIGN,"queue changed")
  assert(math.abs(force.technologies[FOREIGN].saved_progress-.27)<1e-8,"unrelated partial work changed")
  assert(state.lab.disabled_by_script,"saved lab must remain stopped")
end

script.on_init(function()
  local force = game.forces.player
  assert(force.technologies[MAIN],"useful fifth continuation missing")
  for _, name in ipairs({"automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","utility-science-pack","worker-robots-storage-1",
      "worker-robots-storage-2","worker-robots-storage-3","worker-robots-storage-4"}) do
    if force.technologies[name] then force.technologies[name].researched=true end
  end
  -- A speed boost accelerates the fixture; candidate science/cost/time and
  -- worker effects are unchanged, and actual lab consumption is required.
  force.laboratory_speed_modifier=1000
  local lab=game.surfaces.nauvis.create_entity{name="lab",position={0,0},force=force}
  assert(lab and lab.valid,"fixture lab not created")
  lab.disabled_by_script=true
  storage.worker_test={completions=0,lab=lab,phase="seeded"}
  assert(force.worker_robots_storage_bonus==5,"foreign baseline differs")
  report("init")
end)

script.on_configuration_changed(function()
  if storage.worker_test.completions>0 then preserved() end
  report("configuration")
end)

script.on_event(defines.events.on_research_finished,function(event)
  if event.research.name~=MAIN then return end
  assert(event.by_script~=true,"MIR research was granted by script")
  local state=storage.worker_test
  state.completions=state.completions+1
  state.lab.disabled_by_script=true;state.lab.energy=0
  state.lab.get_inventory(defines.inventory.lab_input).clear()
  state.phase="completed"
end)

script.on_event(defines.events.on_tick,function(event)
  local mode=requested_mode or script.test_arg
  if not mode then return end
  local force,state=game.forces.player,storage.worker_test
  local main=force.technologies[MAIN]
  if not started then
    started=true
    if mode=="reload" then
      preserved();report("reload")
      if script.test_arg then script.finish_test(true) else game.tick_paused=true end
      return
    end
    assert(mode=="source" or mode=="successor" or mode=="fresh","unknown test mode")
    if mode=="successor" then preserved();assert(state.completions==1);report("before-successor-lab")
    else assert(state.completions==0) end
    force.research_queue={main}
    state.lab.disabled_by_script=false;state.phase="researching"
  end
  if state.phase=="researching" then
    local inventory=state.lab.get_inventory(defines.inventory.lab_input)
    for _, ingredient in ipairs(main.prototype.research_unit_ingredients) do
      inventory.insert{name=ingredient.name,count=1000}
    end
    state.lab.energy=1000000000
  elseif state.phase=="completed" then
    assert(completed(main)==state.completions,"native completion differs from event")
    assert(force.worker_robots_storage_bonus==5+2*state.completions,"native lab gave wrong bonus")
    force.research_queue={main,force.technologies[FOREIGN]}
    force.research_progress=.42
    force.technologies[FOREIGN].saved_progress=.27
    state.phase="saved";finish_tick=event.tick+4
    preserved();report(mode.."-earned")
    if game.is_multiplayer() then game.server_save("worker-"..mode)
    else game.auto_save("worker-"..mode) end
  elseif finish_tick and event.tick>=finish_tick then
    preserved();report(mode.."-finished")
    if script.test_arg then script.finish_test(true) else game.tick_paused=true end
  end
end)
