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
local function frame(state)
  local force=game.forces.player;local out={phase=state.phase,ordinary=copy(state.ordinary),science=copy(state.inserted),families={}}
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
    scope={controlled_synthetic_mechanism=true,reporter_reproduction=false,scrap97_separate=true,
      mir_runtime_imported=false,mir_ledger_written=false,shared_world_families=5}}))
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
  for _,family in ipairs(C.families)do
    local main=tech(C.main(family))
    for _,prerequisite in pairs(main.prerequisites)do
      fail(prerequisite.name~=main.name,"self prerequisite")
      prerequisite.research_recursive()
    end
  end
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
  local state={phase="f0-ready",ordinary={},mains={},inserted={}}
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
    each_completed(state,1);assert_state(state,"F1",{positive=0,negative=1,bonus=0})
    save(state,"f1-negative-saved","native-credit-allfive-f1-negative")
  elseif phase=="F2"then
    fail(state and state.phase=="f1-saved" and change.old_version=="0.2.0" and change.new_version=="0.3.0","F2 transition differs")
    each_completed(state,2);assert_state(state,"F2",{positive=1,negative=0,bonus=.1})
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
    if phase=="F0"then each_completed(state,1);assert_state(state,"F0",{positive=0,negative=0,bonus=0});save(state,"f0-saved","native-credit-allfive-f0")
    else each_completed(state,2);assert_state(state,"F1",{positive=0,negative=1,bonus=.1});save(state,"f1-saved","native-credit-allfive-f1")end
  end
end)
script.on_event(defines.events.on_tick,function()
  local state=storage[C.key];if not state then return end
  if cold then
    fail(state.endpoint and game.tick==state.saved_tick+1 and equal(frame(state),state.endpoint),"immutable cold endpoint differs")
    cold=false;marker("cold",state);return
  end
  if state.phase=="f0-earning"or state.phase=="f1-earning"then feed(state)end
end)
