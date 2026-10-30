local plan = require("stage")
assert(mods.base == plan.base and mods["more-infinite-research"] == plan.mir,
  "published forward exact engine/MIR preflight differs")
local row = assert(data.raw.technology["recipe-prod-research_character_mining_speed-1"])
assert(row.level==1 and row.max_level=="infinite" and row.upgrade==true and row.enabled~=false)
local unit = assert(row.unit)
local formula = plan.role=="successor" and plan.target=="f110"
  and "1*(8000*2^(L-1))" or "8000*2^(L-1)"
assert(unit.count_formula==formula and unit.time==60,"published forward mining cost differs")
assert(#row.effects==1 and row.effects[1].type=="character-mining-speed" and row.effects[1].modifier==.05,
  "published forward mining effect differs")
local science = {}
for _, ingredient in ipairs(unit.ingredients) do
  assert(ingredient[2]==1 and not science[ingredient[1]],"published forward science multiplicity differs")
  science[ingredient[1]]=true
end
assert(#unit.ingredients==2 and science["military-science-pack"] and science["utility-science-pack"],
  "published forward mining science differs")
if plan.target=="f210" then
  for _,name in ipairs({"military-science-pack","utility-science-pack"}) do
    local pack=data.raw.item and data.raw.item[name]
    assert(pack and pack.type=="item" and (pack.science_capacity==nil or pack.science_capacity==1),
      "published forward plain-item science capacity differs")
  end
end
-- Acceleration follows exact semantic preflight; startup settings are unchanged.
unit.count_formula,unit.count,unit.time = nil,1,1
