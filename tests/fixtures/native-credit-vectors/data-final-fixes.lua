-- Runs after MIR collection/publication by the exact dependency in each info.
local C=require("contract")
local phase=C.phase(mods)
C.require(settings.startup["mir-prefer-this-mod-for-competing-techs"].value==true,"prefer MIR must be true")
local technologies=data.raw.technology
local main=technologies[C.main]
C.require(main and main.unit.count_formula==C.formula and main.unit.time==C.seconds,"authored main unit differs")
local ingredients={}
for _,v in ipairs(main.unit.ingredients)do ingredients[v[1] or v.name]=v[2] or v.amount end
for _,name in ipairs(C.packs)do C.require(ingredients[name]==1,"authored main pack differs: "..name);ingredients[name]=nil end
C.require(next(ingredients)==nil,"extra authored main pack")
local expected={['low-density-structure']=true,['casting-low-density-structure']=true,['scrap-recycling']=true}
local rows=data.raw['mod-data']['more-infinite-research-native-adoptions'].data.credits.research_low_density_structure
C.require(#rows==3,"collected LDS recipe count differs")
for _,r in ipairs(rows)do C.require(expected[r.recipe] and r.change==0.1,"collected LDS basis differs");expected[r.recipe]=nil end
C.require(next(expected)==nil,"missing collected LDS recipe")
-- Stock SA keeps its public owner; MIR's private paid identity is retained.
-- The fixture explicitly exposes this SAME authored main/unit with declared
-- carrier effects. This is a neutral test mask, not a claim about preference.
C.require(main.hidden==true and #main.effects==0,"stock SA private main baseline differs")
main.effects={};main.hidden=false;main.enabled=true
for _,recipe in ipairs({'scrap-recycling','low-density-structure','casting-low-density-structure'})do
  for _,sign in ipairs({'positive','negative'})do
    local holder=technologies[C.carrier(recipe,sign)]
    C.require(holder and holder.hidden==true and holder.enabled==false and #holder.effects==1,"owned holder baseline differs")
    local e=holder.effects[1]
    C.require(e.type=='change-recipe-productivity' and e.recipe==recipe and e.change==(sign=='positive' and 0.1 or -0.1),"holder scalar differs")
    if sign=='positive'then main.effects[#main.effects+1]=table.deepcopy(e)end
  end
end
local reference=technologies[C.public]
C.require(reference and #reference.effects==1 and reference.effects[1].recipe=='scrap-recycling'
  and reference.effects[1].change==0.1,"independent public Scrap reference differs")
-- Introduced AFTER collection: these cannot manufacture MIR descriptors.
local function alias(name,source)
  C.require(data.raw.recipe[name]==nil,"alias already exists: "..name)
  local r=table.deepcopy(data.raw.recipe[source]);r.name=name;r.hidden=true;r.enabled=false
  data:extend({r})
end
alias('cerys-processing-units-from-nitric-acid','processing-unit')
alias('cerys-nuclear-scrap-recycling','scrap-recycling')
require('cerys-technology-first45')
for i=1,95 do alias('mir-vector-synthetic-scrap-'..i,'scrap-recycling') end
for _,technology in pairs(technologies)do
  local scrap
  for _,e in ipairs(technology.effects or {})do if e.type=='change-recipe-productivity' and e.recipe=='scrap-recycling' then scrap=e.change end end
  if scrap then
    for i=1,95 do technology.effects[#technology.effects+1]={type='change-recipe-productivity',recipe='mir-vector-synthetic-scrap-'..i,change=scrap} end
  end
end
if phase=='F0' then
  local excluded={};for _,name in ipairs(C.recipes)do excluded[name]=true end
  local effects={};for _,e in ipairs(main.effects)do if not excluded[e.recipe] then effects[#effects+1]=e end end
  main.effects=effects
elseif phase=='F2' then main.effects={};main.hidden=true;main.enabled=false end
-- No unit/formula/time/science, force state or MIR transport edits.
