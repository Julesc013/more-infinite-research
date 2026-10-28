local plan = require("stage")
assert(mods.base == plan.base and mods["more-infinite-research"] == plan.mir,
  "laser fixture engine/MIR tuple differs")
local row = assert(data.raw.technology[plan.laser], "laser continuation absent")
assert(row.type == "technology" and row.name == plan.laser and row.level == 8
  and row.max_level == 12 and row.upgrade == true and row.enabled ~= false,
  "laser fixture native identity/progression differs")
assert(data.raw.technology[plan.old_or_new_absent] == nil, "obsolete/forward laser identity present")
local unit = assert(row.unit, "laser continuation unit absent")
assert(unit.count == nil and unit.count_formula == "1*(1*1^(L-8))" and unit.time == 1,
  "laser fixture configured formula/time differs")
local packs = {"automation-science-pack", "chemical-science-pack", "logistic-science-pack",
  "military-science-pack", "utility-science-pack"}
assert(#unit.ingredients == #packs, "laser science count differs")
for index, name in ipairs(packs) do
  assert(unit.ingredients[index][1] == name and unit.ingredients[index][2] == 1,
    "laser science payload/order differs")
end
assert(#row.effects == 1 and row.effects[1].type == "gun-speed"
  and row.effects[1].ammo_category == plan.ammo and row.effects[1].modifier == .01,
  "laser native effect differs")
local predecessor_prefix = plan.role == "source" and "laser-turret-speed-" or "laser-shooting-speed-"
local expected = {"chemical-science-pack", predecessor_prefix .. "6", predecessor_prefix .. "7",
  "logistic-science-pack", "military-science-pack", "utility-science-pack"}
assert(#row.prerequisites == #expected, "laser prerequisites count differs")
for index, name in ipairs(expected) do
  assert(row.prerequisites[index] == name, "laser prerequisite payload/order differs")
end
-- No prototype mutation: the shipped settings surface performs acceleration.
