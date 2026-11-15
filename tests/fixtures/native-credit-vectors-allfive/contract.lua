-- Exact test-only metadata for the five published public references.
local M={mod="mir-fixture-native-credit-vectors-allfive",upstream="a-mir-fixture-native-credit-vectors-allfive-upstream",version="0.1.0",lab="mir-allfive-credit-lab",assembler="mir-allfive-credit-assembler",
  key="mir_native_credit_allfive_fixture",
  formula="8000*2^(L-1)",seconds=60,lab_speed=115200,
  physical_input="iron-plate",physical_output="iron-gear-wheel",physical_batch=10,physical_deadline=18000,
  packs={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}}

M.targets={
  f200={base="2.0.77",mir14="5.0.20014",mir15="5.0.20015",factorio="2.0",recycler=false},
  f210={base="2.1.24",mir14="5.0.21014",mir15="5.0.21015",factorio="2.1",recycler=true},
}

-- `routes` are the authored published native-credit route names. `extra` is
-- controlled fixture data, never a claim about an external provider.
M.families={
  {key="research_low_density_structure",reference="low-density-structure-productivity",
    routes={"low-density-structure","casting-low-density-structure","scrap-recycling"},
    reference_by_route={['scrap-recycling']="scrap-recycling-productivity"}},
  {key="research_plastic",reference="plastic-bar-productivity",routes={"plastic-bar","bioplastic"}},
  {key="research_processing_unit",reference="processing-unit-productivity",routes={"processing-unit"}},
  {key="research_rocket_fuel",reference="rocket-fuel-productivity",
    routes={"rocket-fuel","rocket-fuel-from-jelly","ammonia-rocket-fuel"}},
  {key="research_steel",reference="steel-plate-productivity",routes={"steel-plate","casting-steel"}},
}
for _,family in ipairs(M.families)do
  family.public_only={}
  family.extra={}
  for _,recipe in ipairs(family.routes)do
    family.extra[recipe]="mir-allfive-companion-"..recipe
    family.public_only[recipe]="mir-allfive-public-only-"..recipe
  end
  family.physical=family.routes[1]
end
M.public_physical=M.families[1].public_only[M.families[1].physical]

function M.require(value,message)if not value then error("[mir-native-credit-vectors-allfive] "..message,2)end end
function M.carrier(family,recipe,sign)return "mir-native-credit-"..family.key.."-"..recipe.."-"..sign end
function M.main(family)return "recipe-prod-"..family.key.."-1"end
function M.reference(family,recipe)return family.reference_by_route and family.reference_by_route[recipe]or family.reference end
function M.close(left,right)return type(left)=="number" and type(right)=="number" and math.abs(left-right)<0.0000001 end

function M.target(mods)
  local target
  for name,row in pairs(M.targets)do if mods.base==row.base then target=name end end
  M.require(target,"unsupported Base version")
  local row=M.targets[target]
  M.require(mods["space-age"]==row.base and mods.quality==row.base and mods["elevated-rails"]==row.base,
    "official DLC version differs")
  M.require(mods["more-infinite-research"]==row.mir14 or mods["more-infinite-research"]==row.mir15,"MIR version differs")
  if row.recycler then M.require(mods.recycler==row.base,"Recycler version differs")else M.require(mods.recycler==nil,"unexpected Recycler")end
  M.require(mods[M.upstream]=="0.1.0","upstream scaffold version differs")
  local allowed={base=true,["space-age"]=true,quality=true,["elevated-rails"]=true,
    ["more-infinite-research"]=true,[M.mod]=true,[M.upstream]=true}
  if row.recycler then allowed.recycler=true end
  for name in pairs(mods)do M.require(allowed[name],"undeclared active mod "..name)end
  return target,row
end

function M.phase(mods)
  local target,row=M.target(mods)
  local phase=({["0.1.0"]="F0",["0.2.0"]="F1",["0.3.0"]="F2"})[mods[M.mod]]
  M.require(phase,"fixture version differs")
  return target,row,phase
end

return M
