-- Scenario observer only.  It changes the declared map-price input, queues one
-- real technology, and records observations.  It never grants research,
-- changes a carrier, sets a bonus, or makes a research event.
local C=require("__mir-fixture-native-credit-vectors__/contract")
local KEY="mir_native_credit_price_paid_observer"
local cold=false

local function require_ok(value,message)C.require(value,message)end
local function force()return game.forces.player end
local function main()local t=force().technologies[C.main];require_ok(t and t.valid~=false,"missing LDS main");return t end
local function inventory(state)return state.lab.get_inventory(defines.inventory.lab_input)end
local function retained_lab()
  local surface=game.surfaces[1]
  require_ok(surface and type(surface.find_entity)=="function","retained source surface is absent")
  local lab=surface.find_entity(C.lab,{0,0})
  require_ok(lab and lab.valid~=false,"retained source lab is absent")
  return lab
end
local function copy(value)
  if type(value)~="table" then return value end
  local out={};for key,item in pairs(value)do out[key]=copy(item)end;return out
end
local function equal(left,right)
  if type(left)~=type(right)then return false end
  if type(left)~="table"then return type(left)=="number" and C.close(left,right) or left==right end
  for key,value in pairs(left)do if not equal(value,right[key])then return false end end
  for key in pairs(right)do if left[key]==nil then return false end end
  return true
end
local function bonuses()
  local out={};local recipes=force().recipes
  for _,name in ipairs(C.observed_recipes)do
    require_ok(recipes[name],"missing observed recipe "..name);out[name]=recipes[name].productivity_bonus
  end
  return out
end
local function expected_bonus()
  local out={ ["low-density-structure"]=.3,["casting-low-density-structure"]=.3,
    ["scrap-recycling"]=.1,["cerys-nuclear-scrap-recycling"]=.1 }
  for index=1,95 do out["mir-vector-synthetic-scrap-"..index]=.1 end
  return out
end
local function unit(technology)
  local prototype=technology.prototype
  return {formula=prototype.research_unit_count_formula,time=prototype.research_unit_energy,count=technology.research_unit_count}
end
local function prototype(technology)
  local value=technology.prototype
  return {first=value.level,max=value.max_level,hidden=value.hidden,enabled=value.enabled,
    visible=value.visible_when_disabled,effects=copy(value.effects or{})}
end
local function private_costs()
  local out={};local f=force()
  for _,name in ipairs(C.carriers)do
    local technology=f.technologies[name]
    out[name]={ignore=technology.prototype.ignore_tech_cost_multiplier,native_count=technology.research_unit_count,
      prototype_count=technology.prototype.research_unit_count}
  end
  return out
end
local function frame(state)
  local f=force();local out={mains={},queue=C.queue(f),unchanged={references={},sentinel=C.state(f.technologies[C.sentinel])},
    inventory={},units={},bonuses=bonuses(),technologies={},prototypes={},price=game.difficulty_settings.technology_price_multiplier}
  for _,name in ipairs(C.reference_ids)do out.unchanged.references[name]=C.state(f.technologies[name])end
  for _,name in ipairs(C.main_ids)do
    local technology=f.technologies[name];out.mains[name]=C.state(technology);out.units[name]=unit(technology)
  end
  for _,name in ipairs(C.reference_ids)do out.technologies[name]=C.state(f.technologies[name])end
  for _,name in ipairs(C.main_ids)do out.technologies[name]=C.state(f.technologies[name])end
  out.technologies[C.sentinel]=C.state(f.technologies[C.sentinel])
  for _,route in ipairs(C.routes)do
    for _,sign in ipairs({"positive","negative"})do
      local name=C.carrier_for(route.family,route.recipe,sign);out.technologies[name]=C.state(f.technologies[name])
    end
  end
  for name in pairs(out.technologies)do out.prototypes[name]=prototype(f.technologies[name])end
  for _,name in ipairs(C.packs)do out.inventory[name]=inventory(state).get_item_count(name)end
  return out
end
local function marker(kind,state,detail)
  local current={};local inv=inventory(state)
  for _,name in ipairs(C.packs)do current[name]=inv.get_item_count(name)end
  log("[mir-native-credit-price-paid] "..helpers.table_to_json({kind=kind,tick=game.tick,mods=script.active_mods,
    phase=state.phase,map_price=game.difficulty_settings.technology_price_multiplier,frame=frame(state),detail=detail,
    lab={name=state.lab.name,disabled_by_script=state.lab.disabled_by_script},
    private_costs=private_costs(),science={source_inventory=state.source_inventory,inserted=state.inserted or{},
      current_inventory=current,consumed=state.consumed or{},completion_events=state.completion_events or{}},
    saved={name=state.saved_name,tick=state.saved_tick},
    scope={observer_only=true,physical_output=false,original_protected_source_untouched=true,
      controlled_observer_derivative=true}}))
end
local function assert_endpoint(state)
  local f=force();local q=C.queue(f);local t=main();local wanted=expected_bonus()
  require_ok(state.lab.disabled_by_script==true,"saved observer lab is not disabled")
  require_ok(game.difficulty_settings.technology_price_multiplier==C.price and t.level==4 and t.researched==false
    and t.saved_progress==0 and q.current==false and #q.names==0 and q.progress==0,"saved LDS state differs")
  require_ok(t.research_unit_count==C.next_count,"post-completion LDS next count differs")
  C.require_carriers(f)
  for name,value in pairs(wanted)do require_ok(C.close(f.recipes[name].productivity_bonus,value),"F1 vector differs "..name)end
  local source=state.source_frame;require_ok(source,"source frame was not captured")
  local current=frame(state)
  for name,value in pairs(source.bonuses)do
    if wanted[name]==nil then require_ok(C.close(current.bonuses[name],value),"unrelated F1 bonus changed "..name)end
  end
  for name,value in pairs(source.mains)do
    if name~=C.main then require_ok(equal(current.mains[name],value),"unrelated F1 main state changed "..name)end
  end
  for name,value in pairs(source.technologies)do
    if name~=C.main then require_ok(equal(current.technologies[name],value),"unrelated F1 technology changed "..name)end
  end
  require_ok(equal(current.unchanged,source.unchanged) and equal(current.prototypes,source.prototypes),
    "unrelated F1 native frame changed")
  if state.endpoint then require_ok(equal(frame(state),state.endpoint),"immutable paid endpoint differs")end
end
local function begin(state)
  local f=force();local inv=inventory(state)
  require_ok(state.lab.disabled_by_script==true,"pre-lab observer lab is not disabled")
  game.difficulty_settings.technology_price_multiplier=C.price
  C.require_pre_lab(f,game.difficulty_settings.technology_price_multiplier,inv)
  state.phase="feeding";state.inserted={};state.deadline=game.tick+60000
end
local function start_work(state)
  require_ok(state.phase=="feeding" and state.lab.disabled_by_script==true,"paid LDS start differs")
  force().research_queue={main()}
  local q=C.queue(force());require_ok(q.current==C.main and #q.names==1 and q.names[1]==C.main and q.progress==0,
    "LDS queue differs after pre-lab")
  state.lab.disabled_by_script=false;state.phase="earning"
end
local function refill(state)
  local inv=inventory(state)
  for _,name in ipairs(C.packs)do
    local prior=state.inserted[name] or 0
    local remaining=C.insertion-prior
    if remaining>0 then
      local requested=math.min(C.refill_request,remaining)
      local accepted=inv.insert{name=name,count=requested}
      require_ok(type(accepted)=="number" and accepted==math.floor(accepted) and accepted>=0 and accepted<=requested,
        "native science refill return differs "..name)
      state.inserted[name]=prior+accepted
    end
  end
end

script.on_configuration_changed(function(event)
  C.require_tuple(script.active_mods,event)
  require_ok(storage[KEY]==nil,"paid observer already initialized")
  local state={phase="source-retained",lab=retained_lab(),source_inventory={}}
  require_ok(state.lab.disabled_by_script==true,"source observer lab is not disabled")
  for _,name in ipairs(C.packs)do state.source_inventory[name]=inventory(state).get_item_count(name)end
  C.require_source(force(),game.difficulty_settings.technology_price_multiplier,inventory(state))
  C.require_carriers(force())
  storage[KEY]=state
  cold=false;state.phase="await-continue";state.source_frame=frame(state);marker("source",state,{})
end)
commands.add_command("mir-native-credit-price-paid","Continue only the reviewed paid LDS observer.",function(command)
  local state=storage[KEY]
  require_ok(command.player_index==nil and command.parameter=="continue","server-only exact continue command required")
  require_ok(state and state.phase=="await-continue" and state.source_frame and equal(frame(state),state.source_frame),
    "reviewed source frame differs before continuation")
  begin(state);marker("pre-lab",state)
  start_work(state)
  rcon.print("[MIR516_PAID_CONTINUE]")
end)
script.on_load(function()cold=true end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[KEY];if not state or not event.research or event.research.name~=C.main then return end
  require_ok(event.research.force==force() and event.by_script==false and state.phase=="earning","ordinary LDS completion differs")
  state.lab.disabled_by_script=true
  state.completion_events=state.completion_events or{}
  state.completion_events[#state.completion_events+1]={name=event.research.name,by_script=event.by_script,tick=game.tick}
  for _,name in ipairs(C.packs)do
    local spent=(state.source_inventory[name]+state.inserted[name])-inventory(state).get_item_count(name)
    require_ok(spent==C.consumed,"exact LDS science consumption differs "..name)
    require_ok(state.inserted[name]==C.insertion and inventory(state).get_item_count(name)==0,
      "paid LDS refill endpoint differs "..name)
    state.consumed=state.consumed or{};state.consumed[name]=spent
  end
  state.phase="save-pending";state.finished_tick=game.tick
end)
script.on_event(defines.events.on_tick,function()
  local state=storage[KEY];if not state then return end
  if state.phase=="await-continue" then return end
  if cold then
    require_ok(state.phase=="saved" and game.tick==state.saved_tick+1,"cold observation is not one update after save")
    assert_endpoint(state);marker("cold",state);cold=false;return
  end
  require_ok(game.tick<=state.deadline,"paid LDS observer deadline exceeded")
  if state.phase=="earning"then refill(state)
  elseif state.phase=="save-pending"then
    assert_endpoint(state);state.endpoint=frame(state);state.phase="saved";state.saved_tick=game.tick
    state.saved_name="mir516-native-credit-price-paid";marker("save",state);game.server_save(state.saved_name)
  end
end)
