local agriculture = assert(data.raw.technology["recipe-prod-research_agricultural_growth_speed-1"])
local spoilage = assert(data.raw.technology["recipe-prod-research_spoilage_preservation-1"])

local expected = {
  ["recipe-prod-research_agricultural_growth_speed-1"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
    "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
    "space-science-pack", "metallurgic-science-pack", "promethium-science-pack"
  },
  ["recipe-prod-research_spoilage_preservation-1"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "space-science-pack", "agricultural-science-pack",
    "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
    "metallurgic-science-pack", "electromagnetic-science-pack", "promethium-science-pack"
  }
}

local function contains(rows, name)
  for _, row in ipairs(rows or {}) do
    if row == name then return true end
  end
  return false
end

for name, technology in pairs({
  ["recipe-prod-research_agricultural_growth_speed-1"] = agriculture,
  ["recipe-prod-research_spoilage_preservation-1"] = spoilage
}) do
  assert(technology.enabled ~= false)
  assert(technology.level == 1 and technology.max_level == "infinite" and technology.upgrade == true)
  assert(technology.unit and technology.unit.count_formula == "1" and technology.unit.time == 1)
  assert(technology.unit.count == nil)
  assert(#technology.effects == 1 and technology.effects[1].type == "nothing")
  assert(technology.effects[1].effect_description[2] == "1")
  assert(#technology.unit.ingredients == #expected[name])
  for index, ingredient in ipairs(expected[name]) do
    local actual = technology.unit.ingredients[index]
    assert(actual[1] == ingredient and actual[2] == 1)
  end
  -- The selected all-official policy and named Space Age gate must leave an
  -- enabled definition with its bound end-game prerequisite.
  assert(contains(technology.prerequisites, "promethium-science-pack"))
end

-- Fixture-only fast clock. This keeps the test finite without claiming
-- ordinary item or spoilage tuning qualification.
local yumako = assert(data.raw.capsule.yumako)
assert(yumako.spoil_ticks == 216000 and yumako.spoil_result == "spoilage")
yumako.spoil_ticks = 600