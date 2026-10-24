-- The unchanged companion fixture checks the foreign cryogenic unit and the
-- complete affected catalogue first. Accelerate only this extra lab witness.
local gear = assert(data.raw.technology["recipe-prod-research_gears-1"], "cryogenic gameplay requires MIR gear research")
assert(gear.enabled ~= false and gear.unit, "cryogenic gameplay gear research is disabled")
local expected = {
  ["automation-science-pack"]=true, ["logistic-science-pack"]=true,
  ["chemical-science-pack"]=true, ["production-science-pack"]=true,
  ["military-science-pack"]=true, ["utility-science-pack"]=true,
  ["space-science-pack"]=true, ["agricultural-science-pack"]=true,
  ["metallurgic-science-pack"]=true, ["electromagnetic-science-pack"]=true,
  ["cryogenic-science-pack"]=true, ["promethium-science-pack"]=true,
}
assert(#gear.unit.ingredients == 12, "cryogenic gameplay requires all twelve official science inputs")
for _, ingredient in ipairs(gear.unit.ingredients) do
  local name, amount = ingredient.name or ingredient[1], ingredient.amount or ingredient[2]
  assert(expected[name] == true and amount == 1, "cryogenic gameplay science inputs changed")
  expected[name] = nil
end
assert(next(expected) == nil, "cryogenic gameplay lost an official science input")
local gates = 0
for _, name in ipairs(gear.prerequisites or {}) do
  if name == "cryogenic-science-pack" then gates = gates + 1 end
end
assert(gates == 1, "cryogenic gameplay lost its native cryogenic gate")
gear.unit.count_formula, gear.unit.count, gear.unit.time = nil, 1, 1
