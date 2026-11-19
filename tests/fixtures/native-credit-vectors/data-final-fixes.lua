-- Runs after MIR collection/publication by the exact dependency in each info.
local C=require("contract")
local phase=C.phase(mods)
C.require(settings.startup["mir-prefer-this-mod-for-competing-techs"].value==true,"prefer MIR must be true")
local technologies=data.raw.technology

local function exact_vector(technology,names,sign,label)
  C.require(type(technology)=="table" and type(technology.effects)=="table",label.." effects absent")
  local wanted={}
  for _,name in ipairs(names)do wanted[name]=true end
  local count=0
  for _,effect in ipairs(technology.effects)do
    C.require(effect.type=="change-recipe-productivity" and wanted[effect.recipe]
      and effect.change==sign*.1,label.." vector differs")
    wanted[effect.recipe]=nil;count=count+1
  end
  C.require(count==#names and next(wanted)==nil,label.." vector size differs")
end

-- The private transport must be the exact authored five-family/eleven-route
-- set before the fixture installs either the Cerys excerpt or its test-only
-- aliases. This is neither a recipe discovery pass nor a reporter inference.
local rows=data.raw["mod-data"]["more-infinite-research-native-adoptions"].data.credits
local expected={}
for _,family in ipairs(C.families)do
  expected[family.family]={}
  for _,route in ipairs(family.routes)do expected[family.family][route.recipe]=true end
end
for family,entries in pairs(rows)do
  C.require(expected[family] and #entries==#C.routes_by_family[family],"collected native family differs")
  for _,entry in ipairs(entries)do
    C.require(expected[family][entry.recipe] and entry.change==.1,"collected native route differs")
    expected[family][entry.recipe]=nil
  end
end
for family,remaining in pairs(expected)do C.require(rows[family] and next(remaining)==nil,"missing collected native family")end

for _,family in ipairs(C.families)do
  local main=technologies[family.main]
  C.require(main and main.unit.count_formula==C.formula and main.unit.time==C.seconds,"authored main unit differs "..family.family)
  local ingredients={}
  for _,v in ipairs(main.unit.ingredients)do ingredients[v[1]or v.name]=v[2]or v.amount end
  for _,name in ipairs(C.packs)do C.require(ingredients[name]==1,"authored main pack differs: "..name);ingredients[name]=nil end
  C.require(next(ingredients)==nil,"extra authored main pack")
  C.require(main.hidden==true and #main.effects==0,"stock SA private main baseline differs "..family.family)
end
for reference,names in pairs(C.base_reference_vectors)do
  exact_vector(technologies[reference],names,1,"independent public reference "..reference)
end
for _,route in ipairs(C.routes)do
  C.require(data.raw.recipe[route.recipe] and data.raw.recipe[route.recipe].name==route.recipe,"native route recipe differs "..route.recipe)
  for _,sign in ipairs({"positive","negative"})do
    local holder=technologies[C.carrier_for(route.family,route.recipe,sign)]
    C.require(holder and holder.hidden==true and holder.enabled==false and #holder.effects==1,"owned holder baseline differs")
    local effect=holder.effects[1]
    C.require(effect.type=="change-recipe-productivity" and effect.recipe==route.recipe
      and effect.change==(sign=="positive"and .1 or -.1),"holder scalar differs")
  end
end

local function selected_routes(family)
  local routes={}
  if phase=="F2"then return routes end
  for _,route in ipairs(family.routes)do
    if phase=="F1"or route.f0 then routes[#routes+1]=route end
  end
  return routes
end
local function main_names(family)
  local names={}
  for _,route in ipairs(selected_routes(family))do
    for _,name in ipairs(C.carrier_vector(route))do names[#names+1]=name end
  end
  return names
end

-- Install the selected named main effects before the captured Cerys loop.
-- That preserves its ordinary alias expansion for the private owner as well
-- as each signed holder; only the explicitly public-only producer follows it.
for _,family in ipairs(C.families)do
  local main=technologies[family.main]
  main.effects={}
  if phase=="F2"then main.hidden=true;main.enabled=false
  else
    main.hidden=false;main.enabled=true
    for _,route in ipairs(selected_routes(family))do
      main.effects[#main.effects+1]={type="change-recipe-productivity",recipe=route.recipe,change=.1}
    end
  end
end

-- Introduced after collection: these cannot manufacture MIR descriptors.
local function alias(name,source)
  C.require(data.raw.recipe[name]==nil,"alias already exists: "..name)
  local recipe=table.deepcopy(data.raw.recipe[source]);recipe.name=name;recipe.hidden=true;recipe.enabled=false
  data:extend({recipe})
end
alias("cerys-processing-units-from-nitric-acid","processing-unit")
alias("cerys-nuclear-scrap-recycling","scrap-recycling")
alias(C.noncarrier,"processing-unit")
require("cerys-technology-first45")
for i=1,95 do alias("mir-vector-synthetic-scrap-"..i,"scrap-recycling")end
for _,technology in pairs(technologies)do
  local scrap
  for _,effect in ipairs(technology.effects or{})do
    if effect.type=="change-recipe-productivity"and effect.recipe=="scrap-recycling"then scrap=effect.change end
  end
  if scrap then
    for i=1,95 do technology.effects[#technology.effects+1]={type="change-recipe-productivity",recipe="mir-vector-synthetic-scrap-"..i,change=scrap}end
  end
end
-- A public-only processing recipe proves that a broader reference does not
-- become a carrier component or a saved credit. It is an explicit fixture
-- oracle, not a real Cerys or reporter-production route.
local processing=technologies["processing-unit-productivity"]
processing.effects[#processing.effects+1]={type="change-recipe-productivity",recipe=C.noncarrier,change=.1}

for reference,names in pairs(C.reference_vectors)do exact_vector(technologies[reference],names,1,"final public reference "..reference)end
for _,route in ipairs(C.routes)do
  local names=C.carrier_vector(route)
  exact_vector(technologies[C.carrier_for(route.family,route.recipe,"positive")],names,1,"complete positive carrier "..route.recipe)
  exact_vector(technologies[C.carrier_for(route.family,route.recipe,"negative")],names,-1,"complete negative carrier "..route.recipe)
end
for _,family in ipairs(C.families)do
  local main=technologies[family.main]
  exact_vector(main,main_names(family),1,"phase main vector "..family.family)
  C.require(main.hidden==(phase=="F2"),"main public/private differs "..family.family)
  if phase=="F2"then C.require(main.enabled==false,"retired main prototype is enabled "..family.family)end
end
-- No unit/formula/time/science, force state or MIR transport edits.
