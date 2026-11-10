-- Test-only names and independent Base/Space Age default contract.
local M = {
  mod="mir-fixture-native-credit-vectors", main="recipe-prod-research_low_density_structure-1",
  public="scrap-recycling-productivity", sentinel="mir-vector-sentinel",
  lab="mir-vector-lab", lab_speed=115200, formula="8000*2^(L-1)", seconds=60, ticks=3600,
  packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"},
  singles={"low-density-structure","casting-low-density-structure"},
}
M.recipes={"scrap-recycling","cerys-nuclear-scrap-recycling"}
for i=1,95 do M.recipes[#M.recipes+1]="mir-vector-synthetic-scrap-"..i end
function M.carrier(recipe, sign)
  return "mir-native-credit-research_low_density_structure-"..recipe.."-"..sign
end
function M.close(a,b) return type(a)=="number" and type(b)=="number" and math.abs(a-b)<0.0000001 end
function M.require(value,message) if not value then error("[mir-native-credit-vectors] "..message,2) end end
function M.phase(mods)
  local base=mods.base
  local mir=base=="2.0.77" and "5.0.20012" or base=="2.1.23" and "5.0.21012"
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
