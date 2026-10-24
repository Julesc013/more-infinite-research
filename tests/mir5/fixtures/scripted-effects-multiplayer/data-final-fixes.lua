local agriculture = assert(data.raw.technology["recipe-prod-research_agricultural_growth_speed-1"])
local spoilage = assert(data.raw.technology["recipe-prod-research_spoilage_preservation-1"])

local expected = {
  ["recipe-prod-research_agricultural_growth_speed-1"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
    "cryogenic-science-pack"
  },
  ["recipe-prod-research_spoilage_preservation-1"] = {
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "space-science-pack", "agricultural-science-pack",
    "cryogenic-science-pack"
  }
}

local function assert_exact_row(name, technology)
  assert(technology.enabled ~= false)
  assert(technology.level == 1 and technology.max_level == "infinite" and technology.upgrade == true)
  assert(technology.unit and technology.unit.count_formula == "1" and technology.unit.time == 1)
  assert(technology.unit.count == nil)
  assert(#technology.effects == 1 and technology.effects[1].type == "nothing")
  assert(technology.effects[1].effect_description[2] == "1")
  assert(#technology.unit.ingredients == #expected[name])
  assert(#technology.prerequisites == #expected[name])
  for index, ingredient in ipairs(expected[name]) do
    local actual = technology.unit.ingredients[index]
    assert(actual[1] == ingredient and actual[2] == 1)
    assert(technology.prerequisites[index] == ingredient)
  end
end

assert_exact_row("recipe-prod-research_agricultural_growth_speed-1", agriculture)
assert_exact_row("recipe-prod-research_spoilage_preservation-1", spoilage)

-- The production item remains a one-hour spoilable. Only this disposable
-- fixture shortens newly inserted yumako clocks after that exact preflight.
local yumako = assert(data.raw.capsule.yumako)
assert(yumako.spoil_ticks == 216000 and yumako.spoil_result == "spoilage")
yumako.spoil_ticks = 600
