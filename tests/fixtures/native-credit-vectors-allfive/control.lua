-- Read-only observer plus one ordinary fixture-owned science completion.
-- It does not import MIR runtime code or access the MIR native-credit ledger.
local C=require("__mir-fixture-native-credit-vectors-allfive__/contract")
local cold=false
local function fail(value,message)C.require(value,message)end
local function copy(value)if type(value)~="table"then return value end local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out end
local function equal(left,right)
  if type(left)~=type(right)then return false end
  if type(left)~="table"then return type(left)~="number" or C.close(left,right)end
  for key,value in pairs(left)do if not equal(value,right[key])then return false end end
  for key in pairs(right)do if left[key]==nil then return false end end
  return true
end
local function completed(technology)return technology.level-1+(technology.researched and 1 or 0)end
local function observe()
  local target=C.target(script.active_mods)
  local force=game.forces.player
  fail(force.laboratory_speed_modifier==0 and force.laboratory_productivity_bonus==0,"lab force modifiers differ")
  local out={target=target,public_only={},references={},sentinel=completed(force.technologies[C.sentinel])}
  for _,family in ipairs(C.families)do
    local reference=force.technologies[family.reference]
    fail(reference and reference.valid~=false and completed(reference)==0,"public reference changed: "..family.reference)
    local recipe=force.recipes[family.public_only]
    fail(recipe and C.close(recipe.productivity_bonus,0),"public-only recipe received native credit: "..family.public_only)
    out.references[family.reference]={level=reference.level,researched=reference.researched}
    out.public_only[family.public_only]=recipe.productivity_bonus
  end
  return out
end
local function marker(kind,state,detail)
  log("[mir-native-credit-vectors-allfive] "..helpers.table_to_json({kind=kind,tick=game.tick,
    target=C.target(script.active_mods),state=state.phase,ordinary=state.ordinary,endpoint=state.endpoint,detail=detail,
    scope={controlled_synthetic_mechanism=true,reporter_reproduction=false,scrap97_separate=true,
      mir_runtime_imported=false,mir_ledger_written=false}}))
end
remote.add_interface("mir_native_credit_vectors_allfive",{observe=observe})
script.on_init(function()
  observe();storage[C.key]={phase="ready",ordinary=0}
  marker("initial",storage[C.key])
end)
-- `on_load` deliberately changes only this Lua upvalue. Saved state must stay
-- immutable while the cold process observes the endpoint on its next tick.
script.on_load(function()
  local state=storage[C.key]
  cold=state and state.phase=="saved" or false
end)
commands.add_command("mir-native-credit-vectors-allfive","Run the one ordinary fixture science completion.",function(command)
  fail(command.player_index==nil and command.parameter=="continue","server-only exact continue command required")
  local state=storage[C.key];fail(state and state.phase=="ready","fixture is not ready")
  local force=game.forces.player;local surface=game.surfaces[1]
  state.lab=surface.create_entity{name=C.lab,position={0,0},force=force}
  fail(state.lab and state.lab.valid~=false,"fixture lab creation failed")
  local inventory=state.lab.get_inventory(defines.inventory.lab_input)
  state.inserted={}
  for _,name in ipairs(C.packs)do
    local amount=inventory.insert{name=name,count=100}
    fail(amount==100,"fixture science supply failed: "..name)
    state.inserted[name]=amount
  end
  fail(state.lab.prototype.get_researching_speed("normal")==3600,"fixture lab speed differs")
  force.research_queue={force.technologies[C.sentinel]};state.phase="earning"
  marker("ordinary-start",state)
end)
script.on_event(defines.events.on_research_finished,function(event)
  local state=storage[C.key]
  if not state or event.research.name~=C.sentinel then return end
  fail(state.phase=="earning" and event.by_script==false,"ordinary fixture completion differs")
  state.ordinary=state.ordinary+1;fail(state.ordinary==1,"ordinary fixture completion duplicated")
  local inventory=state.lab.get_inventory(defines.inventory.lab_input)
  for _,name in ipairs(C.packs)do
    fail(state.inserted[name]-inventory.get_item_count(name)==100,"ordinary fixture science differs: "..name)
  end
  state.lab.disabled_by_script=true;state.endpoint=observe();state.phase="saved"
  marker("save",state);game.server_save("native-credit-allfive")
end)
script.on_event(defines.events.on_tick,function()
  local state=storage[C.key]
  if not state or cold~=true then return end
  fail(state.phase=="saved" and state.endpoint and equal(observe(),state.endpoint),"immutable cold endpoint differs")
  cold=false;marker("cold",state)
end)
