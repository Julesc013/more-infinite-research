local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local PAIRED = "mir-fixture-mir5-agriculture-scale-paired"
local CANDIDATE = "mir-fixture-mir5-agriculture-scale-arm-candidate"
local PUBLISHED = "mir-fixture-mir5-agriculture-scale-arm-published"

local candidate_science = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "metallurgic-science-pack", "promethium-science-pack"
}

-- These seven fields are independently observed published 4.7.21002 facts:
-- result 95B1A1FC…67B536C, raw dump 27FBC90D…7888072.  Do not derive them
-- from the MIR 5 arm or treat matching physical crops as a prototype equality claim.
local published_science = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "agricultural-science-pack", "electromagnetic-science-pack",
  "cryogenic-science-pack"
}

local function descriptor()
  local paired = mods and mods[PAIRED] == "0.1.0"
  local candidate = mods and mods[CANDIDATE] == "0.1.0"
  local published = mods and mods[PUBLISHED] == "0.1.0"
  if paired then
    assert(candidate ~= published, "agriculture paired fixture requires exactly one arm selector")
    if candidate then
      return {name = "candidate-mir5", science = candidate_science,
        requires_not_disabled = true, paired = true}
    end
    return {name = "published-4.7.21002", science = published_science,
      requires_enabled_omission = true, paired = true}
  end
  assert(not candidate and not published, "agriculture arm selector requires the paired selector")
  return {name = "candidate-mir5", science = candidate_science,
    requires_not_disabled = true, paired = false}
end

local function assert_exact_vector(actual, expected, label)
  assert(#(actual or {}) == #expected, "agriculture scale " .. label .. " cardinality differs")
  for index, name in ipairs(expected) do
    local row = actual[index]
    local actual_name, actual_amount
    if type(row) == "string" then
      actual_name, actual_amount = row, 1
    else
      actual_name, actual_amount = row and (row.name or row[1]), row and (row.amount or row[2])
    end
    assert(actual_name == name and (actual_amount == nil or actual_amount == 1),
      "agriculture scale " .. label .. " differs at " .. index)
  end
end

local arm = descriptor()
local agriculture = assert(data.raw.technology[AGRICULTURE],
  "agriculture scale requires MIR agricultural growth research")
local tier_setting = assert(settings.startup["mir5-agriculture-scale-tier"],
  "agriculture scale tier setting is absent")
local tier = tier_setting.value
assert(tier == 1 or tier == 32 or tier == 128, "agriculture scale tier is not an authored fixed tier")
if arm.paired then
  assert(tier == 1, "agriculture paired fixture requires the fixed single-tower tier")
end

assert(agriculture.level == 1 and agriculture.max_level == "infinite" and agriculture.upgrade == true,
  "agriculture scale requires an infinite agriculture definition")
if arm.requires_not_disabled then
  assert(agriculture.enabled ~= false, "agriculture candidate arm must not be disabled")
else
  assert(agriculture.enabled == nil and agriculture.hidden == nil,
    "agriculture published arm requires captured raw enabled/hidden omission")
end
assert(agriculture.unit and agriculture.unit.count_formula == "40000*1.5^(L-1)"
  and agriculture.unit.count == nil and agriculture.unit.time == 90,
  "agriculture scale default agricultural research tuning differs")
assert(#(agriculture.effects or {}) == 1 and agriculture.effects[1].type == "nothing"
  and agriculture.effects[1].effect_description
  and agriculture.effects[1].effect_description[1] == "modifier-description.more-infinite-research.agricultural_growth_speed"
  and agriculture.effects[1].effect_description[2] == "1",
  "agriculture scale agricultural effect contract differs")
assert_exact_vector(agriculture.unit.ingredients, arm.science, arm.name .. " science vector")
assert_exact_vector(agriculture.prerequisites, arm.science, arm.name .. " prerequisite vector")

local yumako = assert(data.raw.capsule and data.raw.capsule.yumako,
  "agriculture scale requires the native yumako item")
assert(yumako.spoil_ticks == 216000 and yumako.spoil_result == "spoilage",
  "agriculture scale native yumako spoilage contract differs")

-- Only the fully validated fixture-world technology is accelerated. The selected
-- research effect, native plant timer, tower event, and spoilable item remain untouched.
agriculture.unit.count_formula, agriculture.unit.count, agriculture.unit.time = nil, 1, 1
