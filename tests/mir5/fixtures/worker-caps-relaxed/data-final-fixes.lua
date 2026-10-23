-- Fixture-only lab acceleration. The native owner/effect/science stay intact;
-- this does not qualify the ordinary cost or time of either upstream profile.
local row = assert(data.raw.technology["worker-robots-speed-7"])
local modifier = mods["Krastorio2-spaced-out"] and 0.6 or 0.65
assert(row.max_level == "infinite" and #row.effects == 1)
assert(row.effects[1].type == "worker-robot-speed" and row.effects[1].modifier == modifier)
assert(row.prerequisites[1] == "worker-robots-speed-6")
local packs = {"production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"}
if not mods["Krastorio2-spaced-out"] then
  packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "space-science-pack", "electromagnetic-science-pack"}
end
assert(row.unit and #row.unit.ingredients == #packs)
for index, name in ipairs(packs) do
  assert(row.unit.ingredients[index][1] == name and row.unit.ingredients[index][2] == 1)
end
row.unit.count, row.unit.count_formula, row.unit.time = nil, "1", 1
