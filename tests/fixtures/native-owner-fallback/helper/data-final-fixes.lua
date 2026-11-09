local native=assert(data.raw.technology["steel-plate-productivity"])
assert(serpent.block(native,{comment=false,sortkeys=true})==mir_fixture_foreign_native_before,"complete foreign native changed")
local t=assert(data.raw.technology["recipe-prod-research_steel-1"])
assert(t.hidden~=true and t.max_level=="infinite" and t.upgrade==true,"public residual progression")
assert(t.unit.count==nil and t.unit.count_formula=="(2+3*(L-1))*1.25^(L-1)" and t.unit.time==1,"public residual cost/time")
local science={"automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack"}
assert(#t.unit.ingredients==4 and #t.prerequisites==4,"historical fallback science/prerequisites")
for i,name in ipairs(science)do assert(t.unit.ingredients[i][1]==name and t.unit.ingredients[i][2]==1 and t.prerequisites[i]==name,"fallback science")end
assert(#t.effects==1 and t.effects[1].type=="change-recipe-productivity" and t.effects[1].recipe=="mir-fixture-adopt-steel-plate" and math.abs(t.effects[1].change-.17)<1e-8,"residual only reward")
local ids={};for name,version in pairs(mods)do if name~="core"then ids[#ids+1]=name.."@"..version end end;table.sort(ids);log("[MIR_ACTIVE_MODS] "..table.concat(ids,"|"))
