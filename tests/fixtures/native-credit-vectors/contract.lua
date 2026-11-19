-- Test-only names and the fixed five-family Base/Space Age vector contract.
-- These lists are deliberately authored, not discovered from data.raw.
local M = {
  mod="mir-fixture-native-credit-vectors", main="recipe-prod-research_low_density_structure-1",
  public="scrap-recycling-productivity", sentinel="mir-vector-sentinel",
  lab="mir-vector-lab", lab_speed=115200, formula="8000*2^(L-1)", seconds=60, ticks=3600,
  packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"},
  singles={"low-density-structure","casting-low-density-structure"},
  noncarrier="mir-vector-independent-processing",
}

-- Keep the captured Cerys loop and its synthetic extension separate from the
-- five real native owners. It is a declared fixture producer, never a Cerys
-- reproduction or an additional MIR descriptor source.
M.recipes={"scrap-recycling","cerys-nuclear-scrap-recycling"}
for i=1,95 do M.recipes[#M.recipes+1]="mir-vector-synthetic-scrap-"..i end

M.families={
  {family="research_low_density_structure",main="recipe-prod-research_low_density_structure-1",routes={
    {recipe="low-density-structure",reference="low-density-structure-productivity",f0=true},
    {recipe="casting-low-density-structure",reference="low-density-structure-productivity",f0=true},
    {recipe="scrap-recycling",reference="scrap-recycling-productivity",f0=false},
  }},
  {family="research_plastic",main="recipe-prod-research_plastic-1",routes={
    {recipe="plastic-bar",reference="plastic-bar-productivity",f0=true},
    {recipe="bioplastic",reference="plastic-bar-productivity",f0=false},
  }},
  {family="research_processing_unit",main="recipe-prod-research_processing_unit-1",routes={
    {recipe="processing-unit",reference="processing-unit-productivity",f0=true},
  }},
  {family="research_rocket_fuel",main="recipe-prod-research_rocket_fuel-1",routes={
    {recipe="rocket-fuel",reference="rocket-fuel-productivity",f0=true},
    {recipe="rocket-fuel-from-jelly",reference="rocket-fuel-productivity",f0=false},
    {recipe="ammonia-rocket-fuel",reference="rocket-fuel-productivity",f0=false},
  }},
  {family="research_steel",main="recipe-prod-research_steel-1",routes={
    {recipe="steel-plate",reference="steel-plate-productivity",f0=true},
    {recipe="casting-steel",reference="steel-plate-productivity",f0=false},
  }},
}

M.base_reference_vectors={
  ["low-density-structure-productivity"]={"low-density-structure","casting-low-density-structure"},
  ["scrap-recycling-productivity"]={"scrap-recycling"},
  ["plastic-bar-productivity"]={"plastic-bar","bioplastic"},
  ["processing-unit-productivity"]={"processing-unit"},
  ["rocket-fuel-productivity"]={"rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel"},
  ["steel-plate-productivity"]={"steel-plate","casting-steel"},
}
M.reference_vectors={
  ["low-density-structure-productivity"]={"low-density-structure","casting-low-density-structure"},
  ["scrap-recycling-productivity"]=M.recipes,
  ["plastic-bar-productivity"]={"plastic-bar","bioplastic"},
  ["processing-unit-productivity"]={"processing-unit","cerys-processing-units-from-nitric-acid",M.noncarrier},
  ["rocket-fuel-productivity"]={"rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel"},
  ["steel-plate-productivity"]={"steel-plate","casting-steel"},
}
M.reference_ids={
  "low-density-structure-productivity", "scrap-recycling-productivity", "plastic-bar-productivity",
  "processing-unit-productivity", "rocket-fuel-productivity", "steel-plate-productivity",
}
M.observed_recipes={"low-density-structure","casting-low-density-structure"}
for _,name in ipairs(M.recipes)do M.observed_recipes[#M.observed_recipes+1]=name end
for _,name in ipairs({"plastic-bar","bioplastic","processing-unit","cerys-processing-units-from-nitric-acid",M.noncarrier,
  "rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel","steel-plate","casting-steel"})do
  M.observed_recipes[#M.observed_recipes+1]=name
end

-- The public owner may cover several recipes, but each named carrier retains
-- only its own paid route and any real post-collection alias.  The unchanged
-- Cerys excerpt expands scrap to 97 rows and processing to its Cerys alias;
-- it never grants the public-only processing producer carrier credit.
function M.carrier_vector(route)
  if route.recipe=="scrap-recycling" then return M.recipes end
  if route.recipe=="processing-unit" then return {"processing-unit","cerys-processing-units-from-nitric-acid"} end
  return {route.recipe}
end

M.main_ids={}
M.main_set={}
M.routes={}
M.routes_by_family={}
for _,family in ipairs(M.families)do
  M.main_ids[#M.main_ids+1]=family.main
  M.main_set[family.main]=true
  M.routes_by_family[family.family]=family.routes
  for _,route in ipairs(family.routes)do
    route.family=family.family
    route.main=family.main
    M.routes[#M.routes+1]=route
  end
end

-- Existing two LDS completions remain first. The other four named mains get
-- exactly one ordinary completion in this same world before the F0 save.
M.f0_sequence={
  "recipe-prod-research_low_density_structure-1", "recipe-prod-research_low_density_structure-1",
  "recipe-prod-research_plastic-1", "recipe-prod-research_processing_unit-1",
  "recipe-prod-research_rocket_fuel-1", "recipe-prod-research_steel-1",
}
M.f0_completed={
  ["recipe-prod-research_low_density_structure-1"]=2,
  ["recipe-prod-research_plastic-1"]=1,
  ["recipe-prod-research_processing_unit-1"]=1,
  ["recipe-prod-research_rocket_fuel-1"]=1,
  ["recipe-prod-research_steel-1"]=1,
}
-- All five private authored mains retain this exact unit. These independent
-- pack totals are five ordinary F0 completions plus the original LDS path.
M.science={f0=56000,f1=88000,f2=152000}

function M.carrier(recipe,sign)
  return "mir-native-credit-research_low_density_structure-"..recipe.."-"..sign
end
function M.carrier_for(family,recipe,sign)
  return "mir-native-credit-"..family.."-"..recipe.."-"..sign
end
function M.close(a,b)return type(a)=="number"and type(b)=="number"and math.abs(a-b)<0.0000001 end
function M.require(value,message)if not value then error("[mir-native-credit-vectors] "..message,2)end end
function M.phase(mods)
  local base=mods.base
  local mir=base=="2.0.77" and "5.0.20015" or base=="2.1.23" and "5.0.21015"
  M.require(mir and mods["more-infinite-research"]==mir and mods["space-age"]==base,"exact engine/MIR/SA tuple differs")
  local allowed={base=true,['space-age']=true,quality=true,['elevated-rails']=true,
    ['more-infinite-research']=true,[M.mod]=true}
  if base=='2.1.23'then allowed.recycler=true;M.require(mods.recycler==base,'exact recycler differs')end
  M.require(mods.quality==base and mods['elevated-rails']==base,'exact official DLC closure differs')
  for name in pairs(mods)do M.require(allowed[name],'undeclared active mod '..name)end
  local phase=({["0.1.0"]="F0",["0.2.0"]="F1",["0.3.0"]="F2"})[mods[M.mod]]
  M.require(phase,"exact fixture version differs")
  return phase
end
return M
