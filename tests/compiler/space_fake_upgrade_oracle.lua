-- Controlled checks of the native oracle's opposing cases. No Factorio proof.
local assertions = 0
package.preload["__more-infinite-research__/prototypes/mir/runtime/research_browser_actions"]=function()
  return dofile('source/prototypes/mir/runtime/research_browser_actions.lua')
end
defines={input_action={start_research=1}}
local function check(condition) assert(condition); assertions = assertions + 1 end
local function world(mode)
  storage = {}
  script = {active_mods={['space-is-fake']='controlled', ['space-age']='controlled', ['more-infinite-research']='4.2.20000'}}
  helpers = {table_to_json=function() return 'controlled-observations' end}
  log = function() end
  local force = {technologies={}, laboratory_speed_modifier=0.7,index=1,research_enabled=true,
    get_gun_speed_modifier=function() return 0.4 end, reset_technology_effects=function() end}
  for _, name in ipairs({'weapon-shooting-speed-7','research-speed-7'}) do
    local anchor=name:gsub('7$','6')
    force.technologies[anchor]={name=anchor,level=6,researched=true,enabled=true,saved_progress=0,
      research_unit_ingredients={{name='automation-science-pack',amount=2},{name='utility-science-pack',amount=3}}}
    local values = {name=name,level=7,researched=true,enabled=true,saved_progress=0,
      research_unit_ingredients={{name='automation-science-pack',amount=2},{name='utility-science-pack',amount=3},{name='space-science-pack',amount=1}},
      prerequisites={[name:gsub('7$','6')]={}},prototype={effects={{modifier=0.1}}}}
    -- Match the observed native setter: clearing researched resets the
    -- infinite technology's current level to its prototype's first level.
    force.technologies[name] = setmetatable({}, {__index=values, __newindex=function(_, key, value)
      values[key]=value
      if key=='researched' and value==false then values.level=7 end
    end})
  end
  local introduced={}
  if mode=='introduced' or mode=='manufacturing' then
    script.active_mods['space-is-fake']='1.0.60'
    for _, name in ipairs({'weapon-shooting-speed-7','research-speed-7'}) do
      introduced[name]=force.technologies[name]
      force.technologies[name]=nil
      for _, ingredient in ipairs(force.technologies[name:gsub('7$','6')].research_unit_ingredients) do ingredient.amount=1 end
    end
  elseif mode=='derived-production' then
    script.active_mods['more-infinite-research']='4.2.21000'
    script.active_mods['space-is-fake']='1.0.78'
    table.insert(force.technologies['weapon-shooting-speed-7'].research_unit_ingredients,1,
      {name='production-science-pack',amount=1})
  end
  if mode=='manufacturing' then
    script.active_mods.base='2.0.77'
    force.recipes={}
    force.research_queue={{name='mining-productivity-3'}}
    force.research_progress=0.37
    force.add_research=function(name) table.insert(force.research_queue,force.technologies[name]); return true end
    local families={
      {'low_density_structure','casting-low-density-structure','low-density-structure','scrap-recycling'},
      {'plastic','bioplastic','plastic-bar'}, {'processing_unit','processing-unit'},
      {'rocket_fuel','ammonia-rocket-fuel','rocket-fuel','rocket-fuel-from-jelly'},
      {'steel','casting-steel','steel-plate'}
    }
    for _, row in ipairs(families) do
      local name='recipe-prod-research_'..row[1]..'-1'
      force.technologies[name]={valid=true,force=force,prototype={hidden=true},prerequisites={},name=name,level=1,researched=false,enabled=true,saved_progress=0,
        research_unit_ingredients={{name='automation-science-pack',amount=1}}}
      for slot=2,#row do force.recipes[row[slot]]={productivity_bonus=0} end
    end
    force.reset_technology_effects=function()
      for _, row in ipairs(families) do
        local value=force.technologies['recipe-prod-research_'..row[1]..'-1']
        for slot=2,#row do
          force.recipes[row[slot]].productivity_bonus=(value.level-1)*0.1+(row[slot]=='plastic-bar' and 0.3 or 0)
        end
      end
    end
  end
  game={forces={player=force}}
  game.create_force=function(name)
    local fresh={technologies={},recipes={},reset_technology_effects=function() end}
    for key in pairs(force.technologies) do fresh.technologies[key]={level=1,researched=false,saved_progress=0} end
    for key in pairs(force.recipes) do fresh.recipes[key]={productivity_bonus=0} end
    game.forces[name]=fresh
    return fresh
  end
  local oracle=dofile('tests/support/MIR421SpaceFakeUpgrade.lua')
  oracle.capture()
  local native_verify=oracle.verify
  oracle.verify=function(...)
    local parsing_require=require
    require=function() error("Require cannot be used during a Factorio event") end
    local result={pcall(native_verify,...)}
    require=parsing_require
    if not result[1] then error(result[2]) end
    return table.unpack(result,2)
  end
  if mode=='introduced' or mode=='manufacturing' then
    for name,value in pairs(introduced) do
      value.researched=false
      value.research_unit_ingredients={}
      local packs={'automation','logistic','chemical','military','utility'}
      if name=='research-speed-7' then
        packs={'automation','logistic','chemical','production','utility','military','agricultural','metallurgic','electromagnetic','cryogenic'}
      end
      for _, pack in ipairs(packs) do table.insert(value.research_unit_ingredients,{name=pack..'-science-pack',amount=1}) end
      force.technologies[name]=value
    end
  end
  for name, value in pairs(force.technologies) do
    if name:sub(-1)=='7' and mode~='introduced' and mode~='manufacturing' then table.remove(value.research_unit_ingredients) end
  end
  if mode=='derived-production' then table.remove(force.technologies['weapon-shooting-speed-7'].research_unit_ingredients,1) end
  script.active_mods['more-infinite-research']='4.2.20001'
  return force,oracle
end
local force,oracle=world()
check(pcall(oracle.verify,'upgrade'))
check(pcall(oracle.verify,'reload'))
force,oracle=world('derived-production')
check(pcall(oracle.verify,'upgrade'))
check(pcall(oracle.verify,'reload'))
force.technologies['weapon-shooting-speed-6'].research_unit_ingredients[1].amount=1
check(not pcall(oracle.verify,'upgrade'))
force,oracle=world('introduced')
check(pcall(oracle.verify,'upgrade'))
check(pcall(oracle.verify,'reload'))
table.remove(force.technologies['research-speed-7'].research_unit_ingredients)
check(not pcall(oracle.verify,'upgrade'))
force,oracle=world('introduced')
force.technologies['weapon-shooting-speed-7'].level=8
check(not pcall(oracle.verify,'upgrade'))
for _, change in ipairs({
  function(f) f.technologies['research-speed-7']=nil end,
  function(f) table.insert(f.technologies['research-speed-7'].research_unit_ingredients,{name='space-science-pack',amount=1}) end,
  function(f) f.technologies['research-speed-7'].research_unit_ingredients={} end,
  function(f) f.technologies['weapon-shooting-speed-7'].research_unit_ingredients[1].amount=1 end,
  function(f) table.insert(f.technologies['research-speed-7'].research_unit_ingredients,{name='unexpected-pack',amount=1}) end,
  function(f) f.technologies['weapon-shooting-speed-7'].prerequisites={} end,
  function(f) f.technologies['research-speed-7'].prerequisites['space-science-pack']={} end,
  function(f) f.technologies['research-speed-7'].prototype.effects={{modifier=0}} end,
  function(f) f.technologies['research-speed-7'].level=7 end,
  function(f) f.technologies['research-speed-7'].researched=true end,
  function(f) f.technologies['research-speed-7'].enabled=false end,
  function(f) f.technologies['research-speed-7'].saved_progress=0.3 end,
  function(f) f.technologies['research-speed-6'].researched=false end,
  function(f) f.technologies['research-speed-6'].research_unit_ingredients[1].amount=9 end,
  function(f) f.laboratory_speed_modifier=0.5 end,
  function(f) f.get_gun_speed_modifier=function() return 0.2 end end,
  function() script.active_mods['space-is-fake']=nil end,
  function() script.active_mods['space-age']=nil end,
  function() storage.mir421_space_fake_upgrade=nil end
}) do
  force,oracle=world()
  change(force)
  check(not pcall(oracle.verify,'upgrade'))
  -- Reload must independently reject the same changed final state.
  check(not pcall(oracle.verify,'reload'))
end
force,oracle=world('manufacturing')
local earned=storage.mir421_space_fake_upgrade.manufacturing
check(earned.recipe_bonuses['casting-steel']==0.5 and earned.recipe_bonuses['scrap-recycling']==0.1
  and earned.recipe_bonuses['plastic-bar']==0.5)
check(pcall(oracle.verify,'upgrade'))
check(pcall(oracle.verify,'reload'))
for _, change in ipairs({
  function(f) f.technologies['recipe-prod-research_plastic-1']=nil end,
  function(f) f.technologies['recipe-prod-research_steel-1'].level=5 end,
  function(f) f.technologies['recipe-prod-research_plastic-1'].saved_progress=0 end,
  function(f) f.technologies['recipe-prod-research_plastic-1'].enabled=false end,
  function(f) f.technologies['recipe-prod-research_plastic-1'].prototype.hidden=false end,
  function(f) table.remove(f.research_queue,2) end,
  function(f) f.research_queue[1],f.research_queue[2]=f.research_queue[2],f.research_queue[1] end,
  function(f) f.research_progress=0 end,
  function() game.forces['mir421-fresh-manufacturing'].recipes['casting-steel'].productivity_bonus=0.1 end,
  function() game.forces['mir421-fresh-manufacturing'].technologies['recipe-prod-research_plastic-1'].level=2 end
}) do
  force,oracle=world('manufacturing')
  check(pcall(oracle.verify,'upgrade'))
  change(force)
  check(not pcall(oracle.verify,'upgrade'))
  check(not pcall(oracle.verify,'reload'))
end
for name in pairs(earned.recipe_bonuses) do
  force,oracle=world('manufacturing')
  force.recipes[name].productivity_bonus=0
  check(not pcall(oracle.verify,'upgrade'))
  check(not pcall(oracle.verify,'reload'))
end
force,oracle=world('manufacturing')
force.recipes['plastic-bar'].productivity_bonus=0.6
check(not pcall(oracle.verify,'upgrade'))
force,oracle=world('manufacturing')
force.recipes['scrap-recycling']=nil
check(not pcall(oracle.verify,'upgrade'))
print('MIR-SIF-NATIVE-ORACLE-CONTROL-PASS '..assertions)
