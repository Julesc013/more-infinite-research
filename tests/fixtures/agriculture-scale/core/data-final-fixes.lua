local AGRICULTURE = "recipe-prod-research_agricultural_growth_speed-1"
local PAIRED = "mir-fixture-mir5-agriculture-scale-paired"
local CANDIDATE = "mir-fixture-mir5-agriculture-scale-arm-candidate"
local DEFAULTS = "mir-fixture-mir5-agriculture-scale-arm-candidate-defaults"
local PUBLISHED = "mir-fixture-mir5-agriculture-scale-arm-published"
local ACTIVE = "mir-fixture-mir5-agriculture-scale-active"

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
  local active = mods and mods[ACTIVE]
  assert(active == nil or active == "0.1.0", "agriculture active fixture selector version differs")
  local candidate = mods and mods[CANDIDATE] == "0.1.0"
  local defaults = mods and mods[DEFAULTS] == "0.1.0"
  local published = mods and mods[PUBLISHED] == "0.1.0"
  if paired then
    assert((candidate and 1 or 0) + (defaults and 1 or 0) + (published and 1 or 0) == 1,
      "agriculture paired fixture requires exactly one arm selector")
    if candidate then
      return {name = "candidate-mir5", science = candidate_science,
        requires_not_disabled = true, paired = true, active = active ~= nil}
    end
    if defaults then
      return {name = "candidate-defaults-mir5", science = published_science,
        requires_enabled_omission = true, paired = true, active = active ~= nil}
    end
    return {name = "published-4.7.21002", science = published_science,
      requires_enabled_omission = true, paired = true, active = active ~= nil}
  end
  assert(not candidate and not defaults and not published and active == nil,
    "agriculture arm selector requires the paired selector")
  return {name = "candidate-mir5", science = candidate_science,
    requires_not_disabled = true, paired = false}
end

local function assert_exact_science(actual, expected, label)
  assert(#(actual or {}) == #expected, "agriculture scale " .. label .. " cardinality differs")
  for index, name in ipairs(expected) do
    local row = actual[index]
    assert(type(row) == "table", "agriculture scale " .. label .. " row is not a table at " .. index)
    local actual_name = row.name or row[1]
    local actual_amount = row.amount or row[2]
    assert(actual_name == name and actual_amount == 1,
      "agriculture scale " .. label .. " differs at " .. index)
  end
end

local function assert_exact_prerequisites(actual, expected, label)
  assert(#(actual or {}) == #expected, "agriculture scale " .. label .. " cardinality differs")
  for index, name in ipairs(expected) do
    assert(type(actual[index]) == "string" and actual[index] == name,
      "agriculture scale " .. label .. " differs at " .. index)
  end
end

local function assert_string_prerequisites(actual, label)
  for index, prerequisite in ipairs(actual or {}) do
    assert(type(prerequisite) == "string",
      "agriculture scale " .. label .. " is not a string at " .. index)
  end
end

-- The candidate arm retains its pre-existing narrow gate contract.  Its complete
-- prerequisite vector is not used as an oracle until an independent candidate
-- capture binds that vector; only the named gate is asserted here.
local function assert_candidate_promethium_gate(actual)
  local count = 0
  for _, prerequisite in ipairs(actual or {}) do
    if prerequisite == "promethium-science-pack" then count = count + 1 end
  end
  assert(count == 1, "agriculture scale candidate promethium prerequisite gate differs")
end

local arm = descriptor()
local agriculture = assert(data.raw.technology[AGRICULTURE],
  "agriculture scale requires MIR agricultural growth research")
local tier_setting = assert(settings.startup["mir5-agriculture-scale-tier"],
  "agriculture scale tier setting is absent")
local tier = tier_setting.value
assert(tier == 1 or tier == 32 or tier == 128, "agriculture scale tier is not an authored fixed tier")
if arm.paired then
  local selectors = 0
  for _, value in ipairs({1, 32, 128}) do
    if mods["mir-fixture-mir5-agriculture-scale-matched-tier-" .. value] ~= nil then
      assert(mods["mir-fixture-mir5-agriculture-scale-matched-tier-" .. value] == "0.1.0"
        and tier == value, "agriculture matched tier selector differs")
      selectors = selectors + 1
    end
    assert(mods["mir-fixture-mir5-agriculture-scale-tier-" .. value] == nil,
      "agriculture paired fixture cannot combine a scale tier selector")
  end
  assert(selectors <= 1, "agriculture matched fixture requires one tier selector")
  if arm.active then
    assert(selectors == 1, "agriculture active fixture requires exactly one matched tier selector")
  end
  if selectors == 0 then
    assert(tier == 1, "agriculture paired fixture requires the fixed single-tower tier")
    assert(arm.name ~= "candidate-defaults-mir5", "agriculture Defaults arm requires a matched tier selector")
  else
    assert(arm.name ~= "candidate-mir5", "agriculture matched tiers require Defaults or published arm")
  end
else
  for _, value in ipairs({1, 32, 128}) do
    assert(not mods or mods["mir-fixture-mir5-agriculture-scale-matched-tier-" .. value] == nil,
      "agriculture matched tier selector requires a paired arm")
  end
end

assert(agriculture.level == 1 and agriculture.max_level == "infinite" and agriculture.upgrade == true,
  "agriculture scale requires an infinite agriculture definition")
if arm.requires_not_disabled then
  assert(agriculture.enabled ~= false, "agriculture candidate arm must not be disabled")
else
  assert(agriculture.enabled == nil and agriculture.hidden == nil,
    "agriculture " .. arm.name .. " arm requires captured raw enabled/hidden omission")
end
assert(agriculture.unit and agriculture.unit.count_formula == "40000*1.5^(L-1)"
  and agriculture.unit.count == nil and agriculture.unit.time == 90,
  "agriculture scale default agricultural research tuning differs")
assert(#(agriculture.effects or {}) == 1 and agriculture.effects[1].type == "nothing"
  and agriculture.effects[1].effect_description
  and agriculture.effects[1].effect_description[1] == "modifier-description.more-infinite-research.agricultural_growth_speed"
  and agriculture.effects[1].effect_description[2] == "1",
  "agriculture scale agricultural effect contract differs")
assert_exact_science(agriculture.unit.ingredients, arm.science, arm.name .. " science vector")
if arm.requires_enabled_omission then
  assert_exact_prerequisites(agriculture.prerequisites, published_science,
    arm.name .. " prerequisite vector")
else
  assert_string_prerequisites(agriculture.prerequisites, arm.name .. " prerequisite")
  assert_candidate_promethium_gate(agriculture.prerequisites)
end

if arm.name == "candidate-defaults-mir5" then
  assert(settings.startup["mir-science-pack-ingredient-policy"].value == "configured"
    and settings.startup["ips-require-space-gate"].value == false,
    "agriculture Defaults science settings differ")
end

local yumako = assert(data.raw.capsule and data.raw.capsule.yumako,
  "agriculture scale requires the native yumako item")
assert(yumako.spoil_ticks == 216000 and yumako.spoil_result == "spoilage",
  "agriculture scale native yumako spoilage contract differs")

-- Only the fully validated fixture-world technology is accelerated. The selected
-- research effect, native plant timer, tower event, and spoilable item remain untouched.
agriculture.unit.count_formula, agriculture.unit.count, agriculture.unit.time = nil, 1, 1
