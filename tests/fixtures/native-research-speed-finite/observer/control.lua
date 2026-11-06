-- One archive for published source, current successor and fresh-current arms.
-- Never reads/writes another mod's storage or manufactures a historical ledger.
local O=require("__mir-fixture-native-research-speed-finite__/oracle")
local KEY="mir_native_research_speed_finite"
local MIR="more-infinite-research"
local PUBLISHED="4.7.21003"
local CASE="native-research-speed-finite"
local TARGET="research-speed-8"
local loaded,reported=false,false
local function check_closure()
  assert(script.active_mods.base=="2.1.23","Base version differs")
  assert(script.active_mods["mir-fixture-finite-base-extension-level"]=="0.1.0"
    and script.active_mods["mir-fixture-native-research-speed-finite"]=="0.1.0","fixture versions differ")
  local version=script.active_mods[MIR]
  assert(version==PUBLISHED or version=="5.0.21007","MIR version differs")
  local cap=settings.startup["mir-max-level-research-speed"]
  assert(cap and cap.value==0,"default cap differs")
  for name,creator in pairs({["research-speed-7"]="mir-fixture-finite-base-extension-level",
      ["research-speed-8"]=MIR}) do
    local history=prototypes.get_history("technology",name)
    assert(type(history)=="table" and history.created==creator,"native creation custody differs: "..name)
  end
end
local function player() return game.forces.player end
local function target(force) return assert(force.technologies[TARGET]) end
local function freeze(state)
  -- Factorio2.1 exposes active as read-only; this writable lab flag stops work.
  state.lab.disabled_by_script=true
  state.lab.energy=0
  state.lab.get_inventory(defines.inventory.lab_input).clear()
end
local function fill(state)
  local inventory=state.lab.get_inventory(defines.inventory.lab_input)
  for _,name in ipairs(O.packs) do inventory.insert{name=name,count=200} end
  state.lab.energy=1000000000
end
local function check_saved(state)
  check_closure()
  assert(state.completions==1 and state.next_level==9,"actual lab completion witness differs")
  O.preserved(O.snapshot(player()),state.player)
  O.preserved(O.snapshot(game.forces[state.paused_index]),state.paused)
  assert(O.close(player().laboratory_speed_modifier,state.before_bonus+.6),"earned native MIR8 bonus differs")
  assert(target(player()).level==9 and not target(player()).researched,"earned MIR8 native level differs")
  assert(state.lab.disabled_by_script and not state.lab.active and state.lab.energy==0
    and state.lab.get_inventory(defines.inventory.lab_input).is_empty(),"saved lab was not frozen")
end
local function marker(stage,state)
  log("[MIR5_NATIVE_FIXTURE] RESULT "..helpers.table_to_json({case=CASE,stage=stage,status="passed",
    qualification="native-runner-readback-required",witnesses={source_mir=state.origin_mir,
      destination_mir=script.active_mods[MIR],actual_lab_completions=state.completions,
      next_level=target(player()).level,native_bonus=player().laboratory_speed_modifier,
      native_bonus_before=state.before_bonus,current=player().current_research.name,
      seven_creator=prototypes.get_history("technology","research-speed-7").created,
      eight_creator=prototypes.get_history("technology","research-speed-8").created,
      current_progress=player().research_progress,queue=O.queue(player()).queue,
      paused_progress=target(game.forces[state.paused_index]).saved_progress,
      foreign7_enabled=player().technologies["research-speed-7"].enabled,on_load_read_only=stage=="reload"}}))
end
script.on_init(function()
  check_closure()
  assert(storage[KEY]==nil,"fixture state already exists")
  local force=player()
  -- Only the fixed prerequisite set is seeded. MIR8 levels/effects are earned
  -- by the real laboratory; full factory/progression qualification is separate.
  for _,name in ipairs(O.gates) do force.technologies[name].researched=true end
  force.reset_technology_effects()
  assert(target(force).level==8 and not target(force).researched,"initial MIR8 differs")
  local entity=assert(game.surfaces[1].create_entity{name="mir-finite-speed-lab",position={0,0},force=force})
  local state={phase="lab",origin_mir=script.active_mods[MIR],completions=0,
    before_bonus=force.laboratory_speed_modifier,lab=entity,deadline=game.tick+36000}
  storage[KEY]=state
  assert(force.add_research(target(force)),"could not queue real MIR8 research")
  fill(state)
end)
script.on_configuration_changed(function(event)
  loaded,reported=false,false
  local state=assert(storage[KEY],"source save witness absent")
  assert(state.phase=="source-complete" and state.origin_mir==PUBLISHED,"exact predecessor save absent")
  local change=event.mod_changes and event.mod_changes[MIR]
  assert(change and change.old_version==PUBLISHED and change.new_version=="5.0.21007","upgrade route differs")
  check_saved(state)
  state.phase="successor-pending-save"
end)
script.on_load(function() loaded,reported=true,false end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[KEY]
  if state and event.research.force==player() and event.research.name==TARGET then
    assert(state.phase=="lab" and state.completions==0,"duplicate/unexpected MIR8 completion")
    state.completions=1
    freeze(state)
    state.phase="observe"
  end
end)
script.on_event(defines.events.on_tick,function()
  local state=assert(storage[KEY],"fixture state absent")
  if state.phase=="lab" then
    assert(game.tick<=state.deadline,"actual laboratory deadline")
    fill(state)
  elseif state.phase=="observe" then
    local force=player()
    assert(target(force).level==9 and O.close(force.laboratory_speed_modifier,state.before_bonus+.6),"MIR8 earned effect differs")
    assert(force.current_research==nil and #(force.research_queue or {})==0,"completed lab queue differs")
    force.technologies["research-speed-7"].enabled=false
    force.research_queue={target(force),force.technologies.automation}
    force.research_progress=.42
    local paused=game.create_force("mir-finite-speed-paused")
    target(paused).saved_progress=.27
    state.paused_index=paused.index
    state.next_level=9
    state.player,state.paused=O.snapshot(force),O.snapshot(paused)
    assert(state.player.queue.current==TARGET and #state.player.queue.queue==2
      and state.player.queue.queue[2]=="automation" and O.close(state.player.queue.progress,.42),"source queue witness differs")
    assert(O.close(state.paused.eight_saved,.27),"source paused witness differs")
    state.phase=state.origin_mir==PUBLISHED and "source-complete" or "fresh-complete"
    check_saved(state)
    marker("initial",state)
    game.server_save("mir5-native-complete")
  elseif state.phase=="successor-pending-save" then
    check_saved(state)
    state.phase="successor-complete"
    marker("initial",state)
    game.server_save("mir5-native-complete")
  elseif loaded and not reported then
    assert(state.phase=="source-complete" or state.phase=="successor-complete" or state.phase=="fresh-complete","reload phase differs")
    check_saved(state)
    marker("reload",state)
    reported=true
  end
end)
