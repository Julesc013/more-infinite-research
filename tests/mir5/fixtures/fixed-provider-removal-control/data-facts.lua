-- Exact F200 Space Age rows selected from the independently captured
-- fixed-provider facts. Fixture acceleration runs only after these checks.
local M = {}
local function fail(message) error('[mir5-fixed-provider-removal-control] ' .. message) end
local function equal_names(actual, expected, label)
  if type(actual) ~= 'table' or #actual ~= #expected then fail(label .. ' count changed') end
  for i, name in ipairs(expected) do if actual[i] ~= name then fail(label .. ' changed at ' .. tostring(i)) end end
end
local function equal_ingredients(actual, expected, label)
  if type(actual) ~= 'table' or #actual ~= #expected then fail(label .. ' count changed') end
  for i, expected_item in ipairs(expected) do
    local item = actual[i]
    if type(item) ~= 'table' or item[1] ~= expected_item[1] or item[2] ~= expected_item[2] or item[3] ~= nil then
      fail(label .. ' changed at ' .. tostring(i))
    end
  end
end
local function equal_effects(actual, expected, label)
  if type(actual) ~= 'table' or #actual ~= #expected then fail(label .. ' count changed') end
  for i, recipe in ipairs(expected) do
    local effect = actual[i]
    if type(effect) ~= 'table' or effect.type ~= 'change-recipe-productivity' or effect.recipe ~= recipe
        or effect.change ~= .1 then fail(label .. ' changed at ' .. tostring(i)) end
  end
end
local function row(name, prerequisites, effects, formula, time, ingredients, level, enabled, label)
  local value = assert(data.raw.technology[name], label .. ' is absent')
  if value.type ~= 'technology' or value.name ~= name or value.level ~= level or value.max_level ~= 'infinite'
      or value.upgrade ~= true or value.enabled ~= enabled or value.visible_when_disabled ~= nil
      or value.hidden ~= nil then fail(label .. ' identity changed') end
  equal_names(value.prerequisites, prerequisites, label .. ' prerequisites')
  equal_effects(value.effects, effects, label .. ' effects')
  local unit = assert(value.unit, label .. ' unit is absent')
  if unit.count ~= nil or unit.count_formula ~= formula or unit.time ~= time then fail(label .. ' tuning changed') end
  equal_ingredients(unit.ingredients, ingredients, label .. ' science')
  return value
end
local SOURCE = {
  bioflux = {name='bioflux-productivity', prerequisites={'bioflux','production-science-pack'}, effects={'bioflux'}, formula='2^L*600', time=60,
    ingredients={{'automation-science-pack',1},{'logistic-science-pack',1},{'chemical-science-pack',1},{'production-science-pack',1},{'agricultural-science-pack',1}}},
  fish = {name='fish-breeding-productivity', prerequisites={'fish-breeding'}, effects={'fish-breeding'}, formula='1.5^L*1000-500', time=60,
    ingredients={{'space-science-pack',1},{'agricultural-science-pack',1}}},
}
local BREEDING_PREREQUISITES={'automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack','agricultural-science-pack','cryogenic-science-pack'}
local BREEDING_INGREDIENTS={{'automation-science-pack',1},{'logistic-science-pack',1},{'chemical-science-pack',1},{'production-science-pack',1},{'agricultural-science-pack',1},{'cryogenic-science-pack',1}}
local BIOFLUX_PREREQUISITES={'automation-science-pack','logistic-science-pack','chemical-science-pack','production-science-pack','agricultural-science-pack'}
local BIOFLUX_INGREDIENTS={{'automation-science-pack',1},{'logistic-science-pack',1},{'chemical-science-pack',1},{'production-science-pack',1},{'agricultural-science-pack',1}}
function M.source()
  local out={}
  for key, expected in pairs(SOURCE) do
    out[key]=row(expected.name, expected.prerequisites, expected.effects, expected.formula, expected.time, expected.ingredients, nil, nil, 'captured source '..key)
    out[key].unit.count,out[key].unit.count_formula,out[key].unit.time=nil,'1',1
  end
  return out
end
function M.mir(preference, providers_present, accelerate)
  local breeding_effects
  if preference or not providers_present then breeding_effects={'biter-egg','fish-breeding','pentapod-egg'}
  else breeding_effects={'biter-egg','pentapod-egg'} end
  local breeding=row('recipe-prod-research_breeding-1', BREEDING_PREREQUISITES, breeding_effects,
    '8000*2^(L-1)',60,BREEDING_INGREDIENTS,1,nil,'captured MIR breeding')
  local bioflux_enabled
  if preference or not providers_present then bioflux_enabled=nil else bioflux_enabled=false end
  local bioflux=row('recipe-prod-research_bioflux-1', BIOFLUX_PREREQUISITES, {'bioflux'},
    '8000*2^(L-1)',60,BIOFLUX_INGREDIENTS,1,bioflux_enabled,'captured MIR bioflux')
  if accelerate then
    breeding.unit.count,breeding.unit.count_formula,breeding.unit.time=nil,'1',1
    if preference then bioflux.unit.count,bioflux.unit.count_formula,bioflux.unit.time=nil,'1',1 end
  end
  return {breeding=breeding,bioflux=bioflux}
end
return M
