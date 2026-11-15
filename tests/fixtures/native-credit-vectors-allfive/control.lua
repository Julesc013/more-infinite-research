-- Scenario observer for five real named MIR family mains. This fixture owns
-- neither MIR runtime code nor MIR's native-credit ledger.
local C=require("__mir-fixture-native-credit-vectors-allfive__/contract")
local cold=false
local function fail(value,message)C.require(value,message)end
local function copy(value)if type(value)~="table"then return value end local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out end
local function equal(left,right)
  if type(left)~=type(right)then return false end
  if type(left)~="table"then return type(left)~="number" and left==right or C.close(left,right)end
  for key,value in pairs(left)do if not equal(value,right[key])then return false end end
  for key in pairs(right)do if left[key]==nil then return false end end
  return true
end
local function completed(technology)return technology.level-1+(technology.researched and 1 or 0)end
local function tech(name)local value=game.forces.player.technologies[name];fail(value and value.valid~=false,"missing technology "..name);return value end
local function effect_names(technology,sign)
  local out={}
  for _,row in ipairs(technology.prototype.effects or {})do
    fail(row.type=="change-recipe-productivity" and type(row.recipe)=="string" and C.close(row.change,sign*.1),
      "vector shape differs: "..technology.name)
    fail(out[row.recipe]==nil,"duplicate vector recipe: "..technology.name)
    out[row.recipe]=true
  end
  return out
end
local function exact_set(actual,expected,message)
  for name in pairs(expected)do fail(actual[name]==true,message.." missing "..name)end
  for name in pairs(actual)do fail(expected[name]==true,message.." extra "..name)end
end
local function authored_science(main,family)
  local seen={}
  for _,row in ipairs(main.research_unit_ingredients or {})do
    local name,amount=row.name or row[1],row.amount or row[2]
    fail(type(name)=="string" and amount==1 and seen[name]~=true,"ordinary science differs: "..family.key)
    seen[name]=true
  end
  for _,name in ipairs(C.packs)do fail(seen[name]==true,"ordinary science absent: "..family.key..":"..name);seen[name]=nil end
  fail(next(seen)==nil,"ordinary science extra: "..family.key)
end
local function selected()
  local _,_,phase=C.phase(script.active_mods)
  local force=game.forces.player
  fail(force.laboratory_speed_modifier==0 and force.laboratory_productivity_bonus==0,"lab force modifiers differ")
  return phase
end
local function holder_counts(family,recipe)
  return completed(tech(C.carrier(family,recipe,"positive"))),completed(tech(C.carrier(family,recipe,"negative")))
end
local function contracts(phase)
  for _,family in ipairs(C.families)do
    local main=tech(C.main(family));local expected={}
    authored_science(main,family)
    for _,recipe in ipairs(family.routes)do
      local extra=family.extra[recipe];expected[recipe]=true;expected[extra]=true
      for _,sign in ipairs({"positive","negative"})do
        local holder=tech(C.carrier(family,recipe,sign));local vector=effect_names(holder,sign=="positive"and 1 or-1)
        exact_set(vector,{[recipe]=true,[extra]=true},"signed carrier")
        fail(holder.prototype.hidden==true and holder.prototype.enabled==false and holder.enabled==false,
          "carrier flags differ: "..holder.name)
      end
    end
    local main_vector=effect_names(main,1)
    if phase=="F1"then
      exact_set(main_vector,expected,"F1 main vector")
      fail(main.prototype.hidden==false and main.prototype.enabled==true,"F1 main flags differ")
    else
      exact_set(main_vector,{},phase.." main vector")
      fail(main.prototype.hidden==(phase=="F2") and main.prototype.enabled~=(phase=="F2"),phase.." main flags differ")
    end
    local references={}
    for _,recipe in ipairs(family.routes)do
      local name=C.reference(family,recipe);references[name]=references[name]or{}
      references[name][recipe]=true
    end
    for name,routes in pairs(references)do
      local reference=tech(name);fail(completed(reference)==0,"public reference was researched: "..name)
      local reference_vector=effect_names(reference,1)
      for recipe in pairs(routes)do
        local extra,public_only=family.extra[recipe],family.public_only[recipe]
        fail(reference_vector[recipe]==true and reference_vector[extra]==true,
          "public reference lost carrier component: "..name..":"..recipe)
        fail(reference_vector[public_only]==true,"public-only reference component absent: "..public_only)
        local public=game.forces.player.recipes[public_only]
        fail(public and C.close(public.productivity_bonus,0),"public-only recipe received native credit: "..public_only)
      end
    end
  end
end

local function empty_modules(machine)
  local modules=machine.get_inventory(defines.inventory.crafter_modules)
  return modules==nil or modules.is_empty()
end
local function physical_machine(row)
  local machine=row.machine
  fail(machine and machine.valid~=false and machine.name==C.assembler,"synthetic assembler differs: "..row.id)
  local input=machine.get_inventory(defines.inventory.crafter_input)
  local output=machine.get_inventory(defines.inventory.crafter_output)
  fail(input and output and empty_modules(machine),"synthetic assembler inventory/modules differ: "..row.id)
  fail(type(machine.productivity_bonus)=="number" and C.close(machine.productivity_bonus,0),
    "synthetic assembler productivity differs: "..row.id)
  return machine,input,output
end
local function expected_output(row,phase)return phase=="F1" and row.kind=="companion" and 11 or 10 end
local function expected_bonus(row,phase)return phase=="F1" and row.kind=="companion" and .1 or 0 end
local function contents(inventory)
  local rows={}
  for name,count in pairs(inventory.get_contents())do rows[name]=count end
  return rows
end
local function physical_snapshot(state)
  local rows={}
  for _,row in ipairs(state.physical.rows)do
    local machine,input,output=physical_machine(row)
    local selected_recipe=machine.get_recipe()
    rows[#rows+1]={id=row.id,kind=row.kind,family=row.family,recipe=row.recipe,selected=selected_recipe and selected_recipe.name,
      inserted=row.inserted or 0,input=input.get_item_count(C.physical_input),
      consumed=(row.inserted or 0)-input.get_item_count(C.physical_input),output=output.get_item_count(C.physical_output),
      input_contents=contents(input),output_contents=contents(output),
      progress=machine.crafting_progress,bonus_progress=machine.bonus_progress,machine_productivity=machine.productivity_bonus,
      modules_empty=empty_modules(machine)}
  end
  return rows
end
local function assert_snapshot(rows,phase)
  for _,row in ipairs(rows or {})do
    local output=expected_output(row,phase)
    fail(row.selected==row.recipe and row.inserted==C.physical_batch and row.input==0 and row.consumed==C.physical_batch,
      "synthetic physical input/recipe differs: "..row.id)
    -- The exact integer output is the native productivity witness. `bonus_progress`
    -- is a floating engine field, so only its zero remainder uses the bounded
    -- numeric comparison shared by the fixture's F200/F210 observations.
    fail(equal(row.input_contents,{}) and equal(row.output_contents,{[C.physical_output]=output})
      and row.output==output and C.close(row.progress,0) and C.close(row.bonus_progress,0)
      and C.close(row.machine_productivity,0) and row.modules_empty==true,
      "synthetic physical output/state differs: "..row.id)
  end
end
local function assert_physical(state,phase)
  local physical=state.physical
  fail(physical and type(physical.rows)=="table" and #physical.rows==#C.families+1,"physical cohort differs")
  fail(physical.f0 and type(physical.f0)=="table","F0 physical baseline absent")
  assert_snapshot(physical.f0,"F0")
  if phase=="F0"then
    fail(physical.phase=="F0-complete" and physical.f1==nil,"F0 physical phase differs")
    fail(equal(physical_snapshot(state),physical.f0),"F0 physical machines drifted")
  else
    fail(physical.phase=="F1-complete" and physical.f1,"F1 physical witness absent")
    assert_snapshot(physical.f1,"F1")
    fail(equal(physical_snapshot(state),physical.f1),"F1 physical machines drifted")
  end
end
local function start_physical(state,phase)
  local physical=state.physical
  if phase=="F1"then
    fail(physical.phase=="F0-complete","F1 physical predecessor differs")
    assert_physical(state,"F0")
  else fail(phase=="F0" and physical.phase=="new","F0 physical predecessor differs")end
  for _,row in ipairs(physical.rows)do
    local machine,input,output=physical_machine(row)
    local prior=output.get_item_count(C.physical_output)
    if phase=="F1"then
      fail(prior==10 and input.get_item_count(C.physical_input)==0 and C.close(machine.crafting_progress,0),
        "F0 physical remainder differs: "..row.id)
      fail(output.remove{name=C.physical_output,count=prior}==prior,"could not retire F0 physical output: "..row.id)
    else fail(prior==0 and input.get_item_count(C.physical_input)==0 and C.close(machine.crafting_progress,0),
      "new physical assembler was not empty: "..row.id)end
    machine.set_recipe(row.recipe)
    local selected_recipe=machine.get_recipe()
    fail(selected_recipe and selected_recipe.name==row.recipe,"synthetic recipe selection differs: "..row.id)
    local bonus=game.forces.player.recipes[row.recipe]
    fail(bonus and C.close(bonus.productivity_bonus,expected_bonus(row,phase)),"synthetic recipe bonus differs: "..row.id)
    local inserted=input.insert{name=C.physical_input,count=C.physical_batch}
    fail(inserted==C.physical_batch,"synthetic physical input was partial: "..row.id)
    row.inserted=inserted
  end
  physical.phase=phase.."-running";physical.deadline=game.tick+C.physical_deadline
end
local function tick_physical(state)
  local physical=state.physical
  if physical.phase~="F0-running" and physical.phase~="F1-running"then return nil end
  fail(game.tick<=physical.deadline,"synthetic physical cohort timed out")
  local phase=physical.phase:sub(1,2);local settled=true
  for _,row in ipairs(physical.rows)do
    local machine,input,output=physical_machine(row)
    local produced=output.get_item_count(C.physical_output)
    fail(produced<=expected_output(row,phase),"synthetic physical output exceeded expectation: "..row.id)
    if input.get_item_count(C.physical_input)~=0 or not C.close(machine.crafting_progress,0)then settled=false
    elseif produced~=expected_output(row,phase)then fail("synthetic physical output differs: "..row.id)end
  end
  if not settled then return nil end
  local snapshot=physical_snapshot(state);assert_snapshot(snapshot,phase)
  physical[phase:lower()]=copy(snapshot);physical.phase=phase.."-complete"
  return phase
end
local function frame(state)
  local force=game.forces.player
  local physical=state.physical and {phase=state.physical.phase,f0=copy(state.physical.f0),f1=copy(state.physical.f1),current=physical_snapshot(state)}or nil
local out={phase=state.phase,ordinary=copy(state.ordinary),science=copy(state.inserted),
  lab={name=state.lab.name,researching_speed=state.lab.prototype.get_researching_speed("normal")},
  physical=physical,families={}}
  for _,family in ipairs(C.families)do
    local row={main=completed(tech(C.main(family))),holders={},bonus={},references={}}
    for _,recipe in ipairs(family.routes)do
      local extra=family.extra[recipe];local p,n=holder_counts(family,recipe)
      row.holders[recipe]={positive=p,negative=n}
      row.bonus[recipe]=force.recipes[recipe].productivity_bonus
      row.bonus[extra]=force.recipes[extra].productivity_bonus
    end
    for _,recipe in ipairs(family.routes)do
      local public_only=family.public_only[recipe]
      row.bonus[public_only]=force.recipes[public_only].productivity_bonus
      local reference=C.reference(family,recipe)
      if row.references[reference]==nil then
        local public=tech(reference)
        row.references[reference]={level=public.level,researched=public.researched}
      end
    end
    out.families[family.key]=row
  end
  return out
end
local function marker(kind,state,detail)
  log("[mir-native-credit-vectors-allfive] "..helpers.table_to_json({kind=kind,tick=game.tick,
    phase=selected(),frame=frame(state),detail=detail,
    scope={controlled_synthetic_mechanism=true,synthetic_companion_production=true,anchor_recipe_mutated=false,
      reporter_reproduction=false,scrap97_separate=true,mir_runtime_imported=false,mir_ledger_written=false,shared_world_families=5}}))
end
local function assert_state(state,phase,wanted)
  contracts(phase)
  local force=game.forces.player
  for _,family in ipairs(C.families)do
    for _,recipe in ipairs(family.routes)do
      local extra=family.extra[recipe];local p,n=holder_counts(family,recipe)
      fail(p==wanted.positive and n==wanted.negative,"signed carrier count differs: "..family.key..":"..recipe)
      fail(C.close(force.recipes[recipe].productivity_bonus,wanted.bonus),"native recipe bonus differs: "..recipe)
      fail(C.close(force.recipes[extra].productivity_bonus,wanted.bonus),"native companion bonus differs: "..extra)
    end
  end
end
local function save(state,phase,name)
  state.phase=phase;state.endpoint=frame(state);state.saved_tick=game.tick
  marker("save",state,{name=name});game.server_save(name)
end
local function inventory(state)return state.lab.get_inventory(defines.inventory.lab_input)end
local function feed(state)
  local current=game.forces.player.current_research
  if not current or state.mains[current.name]~=true then return end
  local input=inventory(state)
  for _,row in ipairs(current.research_unit_ingredients)do
    local name=row.name or row[1];local inserted=input.insert{name=name,count=100}
    state.inserted[name]=(state.inserted[name]or 0)+inserted
  end
end
local function prepare(state)
  local surface=game.surfaces[1];local force=game.forces.player
  state.lab=surface.create_entity{name=C.lab,position={0,0},force=force}
  fail(state.lab and state.lab.valid~=false,"fixture lab creation failed")
  fail(state.lab.prototype.get_researching_speed("normal")==C.lab_speed,"fixture lab speed differs")
  for _,family in ipairs(C.families)do
    local main=tech(C.main(family))
    for _,prerequisite in pairs(main.prerequisites)do
      fail(prerequisite.name~=main.name,"self prerequisite")
      prerequisite.research_recursive()
    end
  end
  state.physical={phase="new",rows={}}
  for index,family in ipairs(C.families)do
    local recipe=family.extra[family.physical]
    state.physical.rows[#state.physical.rows+1]={id=family.key,kind="companion",family=family.key,recipe=recipe,
      machine=surface.create_entity{name=C.assembler,position={index*3,4},force=force}}
  end
  state.physical.rows[#state.physical.rows+1]={id="public-only",kind="public-only",family="research_low_density_structure",
    recipe=C.public_physical,machine=surface.create_entity{name=C.assembler,position={18,4},force=force}}
  for _,row in ipairs(state.physical.rows)do
    local machine=physical_machine(row)
    machine.set_recipe(row.recipe)
  end
  start_physical(state,"F0")
end
local function enqueue_all(state)
  local force=game.forces.player;local queue={};state.mains={};state.inserted={};state.ordinary={}
  for _,family in ipairs(C.families)do
    local main=tech(C.main(family));queue[#queue+1]=main;state.mains[main.name]=true
  end
  force.research_queue=queue
  fail(#force.research_queue==#C.families and force.current_research==queue[1],"shared ordinary queue differs")
  state.lab.disabled_by_script=false
end
local function each_completed(state,wanted)
  for _,family in ipairs(C.families)do fail(completed(tech(C.main(family)))==wanted,"ordinary family completion differs: "..family.key)end
end
remote.add_interface("mir_native_credit_vectors_allfive",{observe=function()local state=storage[C.key];return state and frame(state)end})
script.on_init(function()
  fail(selected()=="F0","new shared world must begin at F0")
  local state={phase="f0-physical",ordinary={},mains={},inserted={}}
  storage[C.key]=state;contracts("F0");assert_state(state,"F0",{positive=0,negative=0,bonus=0})
  prepare(state);marker("initial",state)
end)
-- Factorio permits reading saved storage during on_load but not mutating it.
script.on_load(function()local state=storage[C.key];cold=state and state.endpoint~=nil or false end)
commands.add_command("mir-native-credit-vectors-allfive","Continue the next shared ordinary family cohort.",function(command)
  fail(command.player_index==nil and command.parameter=="continue","server-only exact continue command required")
  local state=storage[C.key];local phase=selected()
  fail((phase=="F0" and state.phase=="f0-ready")or(phase=="F1" and state.phase=="f1-negative-saved"),"continue phase differs")
  state.phase=phase=="F0" and "f0-earning" or "f1-earning";cold=false;enqueue_all(state);marker("ordinary-start",state)
end)
script.on_configuration_changed(function(event)
  local state=storage[C.key];local phase=selected();local change=event.mod_changes and event.mod_changes[C.mod]
  fail(change and change.new_version==script.active_mods[C.mod],"fixture configuration version differs")
  if phase=="F1"then
    fail(state and state.phase=="f0-saved" and change.old_version=="0.1.0" and change.new_version=="0.2.0","F1 transition differs")
    each_completed(state,1);assert_state(state,"F1",{positive=0,negative=1,bonus=0});assert_physical(state,"F0")
    save(state,"f1-negative-saved","native-credit-allfive-f1-negative")
  elseif phase=="F2"then
    fail(state and state.phase=="f1-saved" and change.old_version=="0.2.0" and change.new_version=="0.3.0","F2 transition differs")
    each_completed(state,2);assert_state(state,"F2",{positive=1,negative=0,bonus=.1});assert_physical(state,"F2")
    save(state,"f2-positive-saved","native-credit-allfive-f2-positive")
  else fail(false,"unexpected configuration phase")end
end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[C.key];local research=event.research
  if not state or not research or state.mains[research.name]~=true then return end
  fail(event.by_script==false and (state.phase=="f0-earning"or state.phase=="f1-earning"),"ordinary family completion differs")
  state.ordinary[research.name]=(state.ordinary[research.name]or 0)+1
  fail(state.ordinary[research.name]==1,"ordinary family completion duplicated")
  local all=true;for name in pairs(state.mains)do if state.ordinary[name]~=1 then all=false end end
  if all then
    state.lab.disabled_by_script=true
    local phase=selected()
    if phase=="F0"then
      each_completed(state,1);assert_state(state,"F0",{positive=0,negative=0,bonus=0});assert_physical(state,"F0")
      save(state,"f0-saved","native-credit-allfive-f0")
    else
      each_completed(state,2);assert_state(state,"F1",{positive=0,negative=1,bonus=.1});assert_physical(state,"F0")
      state.phase="f1-physical";start_physical(state,"F1");marker("physical-f1-start",state)
    end
  end
end)
script.on_event(defines.events.on_tick,function()
  local state=storage[C.key];if not state then return end
  local complete=tick_physical(state)
  if complete=="F0"then state.phase="f0-ready";marker("physical-f0-complete",state);return end
  if complete=="F1"then
    assert_physical(state,"F1");save(state,"f1-saved","native-credit-allfive-f1");return
  end
  if cold then
    fail(state.endpoint and game.tick==state.saved_tick+1 and equal(frame(state),state.endpoint),"immutable cold endpoint differs")
    cold=false;marker("cold",state);return
  end
  if state.phase=="f0-earning"or state.phase=="f1-earning"then feed(state)end
end)
