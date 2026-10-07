-- Controlled checks of the native oracle's opposing cases. No Factorio proof.
local assertions = 0
local function check(condition) assert(condition); assertions = assertions + 1 end
local function world(mode)
  storage = {}
  script = {active_mods={['space-is-fake']='controlled', ['space-age']='controlled', ['more-infinite-research']='4.2.20000'}}
  helpers = {table_to_json=function() return 'controlled-observations' end}
  log = function() end
  local force = {technologies={}, laboratory_speed_modifier=0.7,
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
  if mode=='introduced' then
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
  game={forces={player=force}}
  local oracle=dofile('tests/support/MIR421SpaceFakeUpgrade.lua')
  oracle.capture()
  if mode=='introduced' then
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
    if name:sub(-1)=='7' and mode~='introduced' then table.remove(value.research_unit_ingredients) end
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
print('MIR-SIF-NATIVE-ORACLE-CONTROL-PASS '..assertions)
