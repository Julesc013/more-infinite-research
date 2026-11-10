-- Scenario __level__ observer. MIR runs normally; no runtime imports or ledger access.
local C=require('__mir-fixture-native-credit-vectors__/contract')
local KEY='mir_native_credit_vectors_fixture'
local cold, cold_logged=false,false
local function require_ok(value,message) C.require(value,message) end
local function tech(id) local t=game.forces.player.technologies[id];require_ok(t and t.valid~=false,'missing technology '..id);return t end
local function completed(t) return t.level-1+(t.researched and 1 or 0) end
local function copy(value)
  if type(value)~='table' then return value end
  local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
end
local function equal(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return type(a)=='number' and C.close(a,b) or a==b end
  for k,v in pairs(a)do if not equal(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
end
local function selected()
  local phase=C.phase(script.active_mods)
  require_ok(settings.startup['mir-prefer-this-mod-for-competing-techs'].value==true,'prefer MIR differs')
  require_ok(game.difficulty_settings.technology_price_multiplier==1,'map price must be one')
  require_ok(game.forces.player.laboratory_speed_modifier==0
    and game.forces.player.laboratory_productivity_bonus==0,'force lab modifiers must be zero')
  return phase
end
local function vector(t,names,sign)
  local expected={};for _,name in ipairs(names)do expected[name]=true end
  local count=0
  for _,e in pairs(t.prototype.effects or {})do
    require_ok(e.type=='change-recipe-productivity' and expected[e.recipe] and C.close(e.change,sign*.1),'complete vector differs '..t.name)
    expected[e.recipe]=nil;count=count+1
  end
  require_ok(count==#names and next(expected)==nil,'vector size differs '..t.name)
end
local function unit()
  local t=tech(C.main);local p=t.prototype
  require_ok(p.level==1 and p.max_level==4294967295 and p.research_unit_count_formula==C.formula
    and p.research_unit_energy==C.ticks,'main formula/time/first/max changed')
  local packs={};for _,v in pairs(t.research_unit_ingredients)do packs[v.name]=v.amount end
  for _,name in ipairs(C.packs)do require_ok(packs[name]==1,'native main science changed '..name);packs[name]=nil end
  require_ok(next(packs)==nil,'extra native main science')
  return {formula=p.research_unit_count_formula,time=p.research_unit_energy,count=t.research_unit_count}
end
local function contracts(phase)
  unit();vector(tech(C.public),C.recipes,1)
  for _,recipe in ipairs({'scrap-recycling',C.singles[1],C.singles[2]})do
    for _,sign in ipairs({'positive','negative'})do
      local t=tech(C.carrier(recipe,sign));local p=t.prototype
      require_ok(p.level==1 and p.max_level==4294967295 and p.hidden==true and p.enabled==false
        and p.visible_when_disabled==false and t.enabled==false and t.visible_when_disabled==false,'holder flags/shape differ '..t.name)
      vector(t,recipe=='scrap-recycling' and C.recipes or {recipe},sign=='positive' and 1 or -1)
    end
  end
  local names={}
  if phase~='F2'then
    for _,name in ipairs(C.singles)do names[#names+1]=name end
    if phase=='F1'then for _,name in ipairs(C.recipes)do names[#names+1]=name end end
  end
  vector(tech(C.main),names,1)
  require_ok(tech(C.main).prototype.hidden==(phase=='F2'),'main public/private differs')
  if phase=='F2'then require_ok(tech(C.main).prototype.enabled==false,'retired main prototype is enabled')end
end
local function queue()
  local f=game.forces.player;local names={}
  for _,t in ipairs(f.research_queue or {})do names[#names+1]=t.name end
  return {current=f.current_research and f.current_research.name or false,names=names,progress=f.research_progress}
end
local function status(t)
  return {level=t.level,researched=t.researched,enabled=t.enabled,visible=t.visible_when_disabled,saved=t.saved_progress}
end
local function unchanged(state)
  local actual={public=status(tech(C.public)),sentinel=status(tech(C.sentinel))}
  require_ok(state.unchanged and equal(actual,state.unchanged),'unchanged native reference/sentinel state differs')
  return actual
end
local function bonuses()
  local out={};local f=game.forces.player
  for _,name in ipairs(C.recipes)do require_ok(f.recipes[name],'recipe absent '..name);out[name]=f.recipes[name].productivity_bonus end
  for _,name in ipairs(C.singles)do out[name]=f.recipes[name].productivity_bonus end
  for _,name in ipairs({'processing-unit','cerys-processing-units-from-nitric-acid'})do out[name]=f.recipes[name].productivity_bonus end
  return out
end
local function totals(scrap,lds)
  local actual=bonuses()
  for _,name in ipairs(C.recipes)do require_ok(C.close(actual[name],scrap),'native Scrap total differs '..name)end
  for _,name in ipairs(C.singles)do require_ok(C.close(actual[name],lds),'native LDS total differs '..name)end
  require_ok(C.close(actual['processing-unit'],0)and C.close(actual['cerys-processing-units-from-nitric-acid'],0),'unrelated processing bonus changed')
end
local function carrier_counts(scrap,lds)
  for _,recipe in ipairs({'scrap-recycling',C.singles[1],C.singles[2]})do
    local n=recipe=='scrap-recycling'and scrap or lds
    require_ok(completed(tech(C.carrier(recipe,'positive')))==math.max(n,0)
      and completed(tech(C.carrier(recipe,'negative')))==math.max(-n,0),'signed native carrier counts differ '..recipe)
  end
end
local function inventory(state)
  require_ok(state.lab and state.lab.valid~=false,'native lab absent')
  return state.lab.get_inventory(defines.inventory.lab_input)
end
local function work(state)
  local out={main=status(tech(C.main)),queue=queue(),unit=unit(),ordinary=state.ordinary,
    unchanged=unchanged(state),inserted=copy(state.inserted),inventory={}}
  for _,name in ipairs(C.packs)do out.inventory[name]=inventory(state).get_item_count(name)end
  return out
end
local function frame(state)
  local out=work(state);out.bonuses=bonuses();out.technologies={};out.prototypes={}
  for _,recipe in ipairs({'scrap-recycling',C.singles[1],C.singles[2]})do
    for _,sign in ipairs({'positive','negative'})do local id=C.carrier(recipe,sign);out.technologies[id]=status(tech(id))end
  end
  out.technologies[C.public]=status(tech(C.public));out.technologies[C.sentinel]=status(tech(C.sentinel))
  out.technologies[C.main]=status(tech(C.main))
  for id in pairs(out.technologies)do
    local p=tech(id).prototype
    out.prototypes[id]={first=p.level,max=p.max_level,hidden=p.hidden,enabled=p.enabled,
      visible=p.visible_when_disabled,effects=copy(p.effects)}
  end
  return out
end
local function marker(kind,state,extra)
  log('[mir-native-credit-vectors] '..helpers.table_to_json({kind=kind,phase=state.phase,tick=game.tick,
    mods=script.active_mods,ordinary=state.ordinary,frame=frame(state),entry=state.entry,detail=extra,
    scope={synthetic_recipes=95,upstream_excerpt_lines=45,reporter_reproduction=false,full_cerys=false,
      setup='scripted entity placement/science supply/finite prerequisites only',native_earned=true}}))
end
local function save(state,phase,name)
  state.lab.disabled_by_script=true;state.phase=phase;state.endpoint=frame(state);state.saved_tick=game.tick
  marker('save',state,{name=name});game.server_save(name)
end
local function feed(state)
  local f=game.forces.player
  require_ok(f.current_research and f.current_research.name==C.main,'lab has no intended current main')
  local inv=inventory(state)
  for _,name in ipairs(C.packs)do
    local amount=inv.insert{name=name,count=1000}
    state.inserted[name]=(state.inserted[name]or 0)+amount
  end
  state.lab.disabled_by_script=false
end
local function charged(state,completed_cost,partial)
  local inv=inventory(state);local first
  for _,name in ipairs(C.packs)do
    local spent=state.inserted[name]-inv.get_item_count(name)
    if not (spent>=completed_cost-1 and (partial or spent<=completed_cost+1))then
      local f=game.forces.player;local t=tech(C.main)
      marker('science-charge-refusal',state,{name=name,completed_cost=completed_cost,partial=partial,
        spent=spent,inserted=state.inserted[name],inventory_count=inv.get_item_count(name),
        laboratory_productivity_bonus=f.laboratory_productivity_bonus,laboratory_speed_modifier=f.laboratory_speed_modifier,
        main_level=t.level,main_researched=t.researched,main_completed=completed(t),
        current_main_unit=unit(),science=copy(t.research_unit_ingredients),
        predicted_next_paid_level=completed(t)+1,predicted_next_unmultiplied_count=8000*2^completed(t),
        map_price_multiplier=game.difficulty_settings.technology_price_multiplier,
        lab_name=state.lab.name,prototype_lab_researching_speed=state.lab.prototype.get_researching_speed('normal')})
    end
    require_ok(spent>=completed_cost-1 and (partial or spent<=completed_cost+1),'actual science consumption differs '..name)
    if first then require_ok(math.abs(spent-first)<=1,'science pack charges disagree')else first=spent end
  end
end
local function enqueue(state,pending)
  local f=game.forces.player;local main=tech(C.main)
  f.research_queue=pending and {main,tech(C.sentinel)}or{main}
  local q=queue()
  require_ok(q.current==C.main and q.names[1]==C.main and #q.names==(pending and 2 or 1)
    and (not pending or q.names[2]==C.sentinel),'ordered queue selection differs')
  feed(state)
end
local function verify_endpoint(state)
  contracts(selected());require_ok(equal(frame(state),state.endpoint),'immutable endpoint frame changed')
end
script.on_init(function()
  require_ok(selected()=='F0','new game must begin at F0')
  storage[KEY]={phase='initial-pending',ordinary=0,inserted={},deadline=game.tick+60000}
end)
script.on_configuration_changed(function(event)
  local state=storage[KEY];local phase=selected()
  require_ok(state and ((state.phase=='f0-saved'and phase=='F1')or(state.phase=='f1-pending-saved'and phase=='F2')),'configuration phase differs')
  local change=event.mod_changes and event.mod_changes[C.mod]
  require_ok(change and change.old_version==(phase=='F1'and'0.1.0'or'0.2.0')
    and change.new_version==(phase=='F1'and'0.2.0'or'0.3.0'),'fixture version transition differs')
  for name in pairs(event.mod_changes)do require_ok(name==C.mod,'unexpected changed mod '..name)end
  cold,cold_logged=false,false
  local before=work(state);local expected=copy(state.endpoint)
  -- Prototype retirement may affect native flags before ANY mod callback.
  -- Record actual flags; MIR must retain the exact pre-MIR native work frame.
  expected.main.enabled=before.main.enabled;expected.main.visible=before.main.visible
  expected.bonuses=nil;expected.technologies=nil;expected.prototypes=nil
  require_ok(equal(before,expected),'pre-MIR paid/pending frame changed')
  state.entry=frame(state);state.entry_work=copy(before)
  -- This retained native-owner holder is outside authored-generated cap
  -- declarations. Keep its actual incoming force flags and paid queue exact;
  -- the hidden/disabled prototype does not authorize changing those flags.
  state.phase=phase..'-entry-pending';state.deadline=game.tick+60000
  marker('pre-MIR-configuration-entry',state)
end)
script.on_load(function() cold=true;cold_logged=false end)
commands.add_command('mir-native-credit-vectors','Continue only the next declared ordinary lab phase.',function(command)
  local state=storage[KEY]
  require_ok(command.player_index==nil and command.parameter=='continue','server-only exact continue command required')
  require_ok(state and(state.phase=='f1-negative-saved'or state.phase=='f2-positive-saved'),'continue phase differs')
  verify_endpoint(state);cold=false
  state.phase=state.phase=='f1-negative-saved'and'earn-F1'or'earn-F2'
  state.deadline=game.tick+60000
  if state.phase=='earn-F1'then enqueue(state,false)else feed(state)end
end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[KEY];local t=event.research
  if not state or not t or t.force~=game.forces.player then return end
  unchanged(state)
  if t.name~=C.main then
    if t.name:find('mir-native-credit-',1,true)==1 then
      -- Native reconciliation may report its own level-copy events. These
      -- are not ordinary earnings and must end in the exact expected frame.
      require_ok(event.by_script==true and (state.phase=='F1-entry-pending'or state.phase=='F2-entry-pending'
        or state.phase=='deferred-finish'and state.after_finish=='earn-F2'),'carrier event outside reconciliation window')
    else
      require_ok(state.phase=='administrative-prerequisites'and event.by_script==true
        and t.prototype.max_level~=4294967295,'unexpected research completion '..t.name)
    end
    return
  end
  require_ok(event.by_script==false,'main completion was scripted')
  require_ok(state.phase=='earn-F0'or state.phase=='earn-F1'or state.phase=='earn-F2','main completion outside ordinary phase')
  state.ordinary=state.ordinary+1
  require_ok(state.ordinary<=(state.phase=='earn-F0'and 2 or state.phase=='earn-F1'and 3 or 4),'duplicate ordinary completion')
  state.lab.disabled_by_script=true;state.after_finish=state.phase;state.phase='deferred-finish';state.transition_tick=game.tick
end)
script.on_event(defines.events.on_tick,function()
  local state=storage[KEY];if not state then return end
  if state.phase~='initial-pending'then unchanged(state)end
  if cold then
    if not cold_logged then
      require_ok(state.endpoint and game.tick==state.saved_tick+1,'cold is not one update from an immutable saved endpoint')
      verify_endpoint(state);marker('cold',state);cold_logged=true
    end
    return
  end
  if state.phase:find('saved',1,true)then return end
  require_ok(game.tick<=state.deadline,'ordinary native lab deadline exceeded')
  if state.phase=='initial-pending'then
    contracts('F0');totals(0,0);carrier_counts(0,0)
    require_ok(completed(tech(C.main))==0 and completed(tech(C.public))==0,'initial main/reference already earned')
    require_ok(tech(C.sentinel).level==1 and tech(C.sentinel).researched==false
      and tech(C.sentinel).saved_progress==0,'initial sentinel already invested')
    -- One genuine F0 baseline, never replaced at later configuration/saves.
    state.unchanged={public=status(tech(C.public)),sentinel=status(tech(C.sentinel))}
    local s=game.surfaces[1];state.lab=s.create_entity{name=C.lab,position={0,0},force=game.forces.player}
    require_ok(state.lab and state.lab.valid~=false,'could not create actual native lab')
    state.lab.disabled_by_script=true;state.phase='administrative-prerequisites'
    local lab_speed=state.lab.prototype.get_researching_speed('normal')
    require_ok(lab_speed==C.lab_speed and lab_speed/C.ticks==32,'exact whole science quantum differs')
    for _,p in pairs(tech(C.main).prerequisites)do
      require_ok(p.name~=C.main and not p.name:find('mir-native-credit',1,true),'invalid prerequisite setup')
      p.research_recursive()
    end
    contracts('F0');totals(0,0);require_ok(completed(tech(C.main))==0,'prerequisite setup granted main')
    state.phase='earn-F0';enqueue(state,false)
    marker('zero-basis-ready',state,{lab_researching_speed=lab_speed,science_units_per_tick=32,
      laboratory_speed_modifier=game.forces.player.laboratory_speed_modifier,
      laboratory_productivity_bonus=game.forces.player.laboratory_productivity_bonus})
  elseif state.phase=='F1-entry-pending'or state.phase=='F2-entry-pending'then
    local phase=selected();contracts(phase)
    local actual_work=work(state)
    if not equal(actual_work,state.entry_work)then marker('work-mismatch',state,{expected=state.entry_work,actual=actual_work})end
    require_ok(equal(actual_work,state.entry_work),'MIR changed native pending/queue/unit/flags frame')
    if phase=='F1'then
      totals(0,.2);carrier_counts(-2,0)
      save(state,'f1-negative-saved','native-vector-f1-negative')
    else
      totals(.1,.3);carrier_counts(1,3)
      save(state,'f2-positive-saved','native-vector-f2-positive')
    end
  elseif state.phase=='deferred-finish'then
    if game.tick<=state.transition_tick then return end
    require_ok(state.lab.disabled_by_script==true and completed(tech(C.main))==state.ordinary,'native completion/deferred lab stop differs')
    contracts(selected())
    if state.after_finish=='earn-F0'then
      totals(0,state.ordinary*.1);carrier_counts(0,0)
      if state.ordinary==1 then state.phase='earn-F0';enqueue(state,false)
      else game.forces.player.research_queue={};charged(state,24000,false);save(state,'f0-saved','native-vector-f0')end
    elseif state.after_finish=='earn-F1'then
      totals(.1,.3);carrier_counts(-2,0);charged(state,56000,false);state.phase='earn-pending';enqueue(state,true)
    else
      totals(.2,.4);carrier_counts(2,4);charged(state,120000,false);save(state,'f2-final-saved','native-vector-final')
    end
  elseif state.phase=='earn-pending'then
    local q=queue()
    require_ok(q.current==C.main and #q.names==2 and q.names[2]==C.sentinel,'pending ordered queue differs')
    if q.progress>=.2 then
      require_ok(q.progress<.3 and state.ordinary==3,'pending partial/ordinary count differs')
      state.lab.disabled_by_script=true;charged(state,56000,true);totals(.1,.3)
      save(state,'f1-pending-saved','native-vector-f1-pending')
    else feed(state)end
  elseif state.phase=='earn-F0'or state.phase=='earn-F1'or state.phase=='earn-F2'then feed(state)
  else require_ok(false,'unknown fixture phase '..tostring(state.phase))end
end)
