-- Test-only observer contract for one ordinary LDS completion.  It deliberately
-- names every accepted input; it neither discovers owners nor reproduces a
-- reporter or physical-output scenario.
local M={
  fixture="mir-fixture-native-credit-vectors",
  old_mir="5.0.21015", new_mir="5.0.21016", old_fixture="0.2.0", new_fixture="0.4.0",
  base="2.1.23", main="recipe-prod-research_low_density_structure-1", lab="mir-vector-lab",
  lab_speed=115200, sentinel="mir-vector-sentinel", formula="8000*2^(L-1)", seconds=60,
  noncarrier="mir-vector-independent-processing",
  price=2, source_stock=168, insertion=63832, consumed=64000, next_count=128000,
  packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"},
  carriers={
    "mir-native-credit-research_low_density_structure-low-density-structure-positive",
    "mir-native-credit-research_low_density_structure-low-density-structure-negative",
    "mir-native-credit-research_low_density_structure-casting-low-density-structure-positive",
    "mir-native-credit-research_low_density_structure-casting-low-density-structure-negative",
    "mir-native-credit-research_low_density_structure-scrap-recycling-positive",
    "mir-native-credit-research_low_density_structure-scrap-recycling-negative",
  },
}

M.recipes={"scrap-recycling","cerys-nuclear-scrap-recycling"}
for index=1,95 do M.recipes[#M.recipes+1]="mir-vector-synthetic-scrap-"..index end
M.families={
  {family="research_low_density_structure",main=M.main,routes={
    {recipe="low-density-structure",f0=true},{recipe="casting-low-density-structure",f0=true},{recipe="scrap-recycling",f0=false}}},
  {family="research_plastic",main="recipe-prod-research_plastic-1",routes={{recipe="plastic-bar",f0=true},{recipe="bioplastic",f0=false}}},
  {family="research_processing_unit",main="recipe-prod-research_processing_unit-1",routes={{recipe="processing-unit",f0=true}}},
  {family="research_rocket_fuel",main="recipe-prod-research_rocket_fuel-1",routes={{recipe="rocket-fuel",f0=true},{recipe="rocket-fuel-from-jelly",f0=false},{recipe="ammonia-rocket-fuel",f0=false}}},
  {family="research_steel",main="recipe-prod-research_steel-1",routes={{recipe="steel-plate",f0=true},{recipe="casting-steel",f0=false}}},
}
M.base_reference_vectors={
  ["low-density-structure-productivity"]={"low-density-structure","casting-low-density-structure"},
  ["scrap-recycling-productivity"]={"scrap-recycling"},["plastic-bar-productivity"]={"plastic-bar","bioplastic"},
  ["processing-unit-productivity"]={"processing-unit"},["rocket-fuel-productivity"]={"rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel"},
  ["steel-plate-productivity"]={"steel-plate","casting-steel"},
}
M.reference_vectors={
  ["low-density-structure-productivity"]={"low-density-structure","casting-low-density-structure"},
  ["scrap-recycling-productivity"]=M.recipes,["plastic-bar-productivity"]={"plastic-bar","bioplastic"},
  ["processing-unit-productivity"]={"processing-unit","cerys-processing-units-from-nitric-acid",M.noncarrier},
  ["rocket-fuel-productivity"]={"rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel"},
  ["steel-plate-productivity"]={"steel-plate","casting-steel"},
}
M.reference_ids={"low-density-structure-productivity","scrap-recycling-productivity","plastic-bar-productivity",
  "processing-unit-productivity","rocket-fuel-productivity","steel-plate-productivity"}
M.routes,M.routes_by_family={},{}
M.main_ids={}
for _,family in ipairs(M.families)do
  M.main_ids[#M.main_ids+1]=family.main
  M.routes_by_family[family.family]=family.routes
  for _,route in ipairs(family.routes)do route.family=family.family;route.main=family.main;M.routes[#M.routes+1]=route end
end
M.observed_recipes={"low-density-structure","casting-low-density-structure"}
for _,name in ipairs(M.recipes)do M.observed_recipes[#M.observed_recipes+1]=name end
for _,name in ipairs({"plastic-bar","bioplastic","processing-unit","cerys-processing-units-from-nitric-acid",M.noncarrier,
  "rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel","steel-plate","casting-steel"})do M.observed_recipes[#M.observed_recipes+1]=name end
function M.carrier_for(family,recipe,sign)return "mir-native-credit-"..family.."-"..recipe.."-"..sign end
function M.carrier_vector(route)
  if route.recipe=="scrap-recycling" then return M.recipes end
  if route.recipe=="processing-unit" then return {"processing-unit","cerys-processing-units-from-nitric-acid"}end
  return {route.recipe}
end
function M.phase(mods)
  M.require(mods.base==M.base and mods["space-age"]==M.base and mods.quality==M.base and mods.recycler==M.base
    and mods["elevated-rails"]==M.base and mods["more-infinite-research"]==M.new_mir and mods[M.fixture]==M.new_fixture,
    "current F1-equivalent data tuple differs")
  local allowed={base=true,["space-age"]=true,quality=true,recycler=true,["elevated-rails"]=true,
    ["more-infinite-research"]=true,[M.fixture]=true}
  for name in pairs(mods)do M.require(allowed[name],"undeclared current fixture mod "..name)end
  return "F1"
end

function M.require(value,message)if not value then error("[mir-paid-price] "..message,2)end end
function M.close(a,b)return type(a)=="number" and type(b)=="number" and math.abs(a-b)<.0000001 end
function M.completed(t)return t.level-1+(t.researched and 1 or 0)end
function M.queue(force)
  local names={}
  for _,technology in ipairs(force.research_queue or{})do names[#names+1]=technology.name end
  return {current=force.current_research and force.current_research.name or false,names=names,progress=force.research_progress}
end
function M.state(technology)
  return {level=technology.level,researched=technology.researched,enabled=technology.enabled,
    visible=technology.visible_when_disabled,saved=technology.saved_progress}
end
function M.require_tuple(mods,event)
  M.require(mods.base==M.base and mods["space-age"]==M.base and mods.quality==M.base and mods.recycler==M.base
    and mods["elevated-rails"]==M.base,"exact official 2.1.23 closure differs")
  M.require(mods["more-infinite-research"]==M.new_mir and mods[M.fixture]==M.new_fixture,"current tuple differs")
  local change=event.mod_changes and event.mod_changes["more-infinite-research"]
  local fixture=event.mod_changes and event.mod_changes[M.fixture]
  M.require(change and change.old_version==M.old_mir and change.new_version==M.new_mir
    and fixture and fixture.old_version==M.old_fixture and fixture.new_version==M.new_fixture,
    "exact 21015-to-21016/0.2-to-0.4 transition differs")
  for name in pairs(event.mod_changes)do M.require(name=="more-infinite-research" or name==M.fixture,"unexpected changed mod "..name)end
  local allowed={base=true,["space-age"]=true,quality=true,recycler=true,["elevated-rails"]=true,
    ["more-infinite-research"]=true,[M.fixture]=true}
  for name in pairs(mods)do M.require(allowed[name],"unexpected active mod "..name)end
end
function M.require_carriers(force)
  local expected={0,0,0,0,0,2}
  for index,name in ipairs(M.carriers)do
    local t=force.technologies[name]
    M.require(t and t.valid~=false,"missing named LDS carrier "..name)
    M.require(M.completed(t)==expected[index] and t.enabled==false and t.visible_when_disabled==false
      and t.prototype.hidden==true and t.prototype.enabled==false and t.prototype.visible_when_disabled==false
      and t.prototype.ignore_tech_cost_multiplier==true and t.research_unit_count==1,
      "LDS carrier state differs "..name)
  end
end
function M.require_source(force,price,inventory)
  local main=force.technologies[M.main];M.require(main and main.valid~=false,"missing LDS main")
  local q=M.queue(force)
  M.require(price==1 and main.level==3 and main.researched==false and main.saved_progress==0
    and q.current==false and #q.names==0 and q.progress==0,"source LDS paid/queue state differs")
  for _,name in ipairs(M.packs)do M.require(inventory.get_item_count(name)==M.source_stock,"source science stock differs "..name)end
end
function M.require_pre_lab(force,price,inventory)
  local main=force.technologies[M.main];local q=M.queue(force)
  M.require(price==M.price and main.prototype.ignore_tech_cost_multiplier==false
    and main.research_unit_count==M.consumed and main.level==3 and main.researched==false
    and main.saved_progress==0 and q.current==false and #q.names==0 and q.progress==0,"pre-lab LDS state differs")
  local ingredients={}
  for _,row in ipairs(main.research_unit_ingredients)do ingredients[row.name or row[1]]=row.amount or row[2]end
  for _,name in ipairs(M.packs)do M.require(ingredients[name]==1,"LDS ingredient differs "..name);ingredients[name]=nil end
  M.require(next(ingredients)==nil,"unexpected LDS ingredient")
  M.require_carriers(force)
  for _,name in ipairs(M.packs)do M.require(inventory.get_item_count(name)==M.source_stock,"pre-lab stock differs "..name)end
end
return M
