-- Accelerate exactly the two published F200 ATAN MIR technologies for this
-- private native fixture.  The data-stage guards deliberately retain the
-- Base/Space Age difference: the Space Age filter is one shared MIR research
-- with two named native-owner effects.
assert(mods.base == "2.0.77" and mods["atan-air-scrubbing"] == "0.2.8"
  and mods["atan-ash"] == "2.2.1" and mods["more-infinite-research"] == "5.0.20000",
  "ATAN gameplay fixture loaded with an unexpected F200 closure")

local is_space_age = mods["space-age"] ~= nil
if is_space_age then
  assert(mods["space-age"] == "2.0.77" and mods["elevated-rails"] == "2.0.77"
    and mods.quality == "2.0.77", "ATAN gameplay fixture has an unexpected Space Age closure")
elseif mods["elevated-rails"] ~= nil or mods.quality ~= nil then
  error("ATAN gameplay Base fixture unexpectedly loads Space Age companions")
end

local function fail(message)
  error("[mir5-atan-gameplay] " .. message)
end

local function assert_effects(technology, expected, label)
  if type(technology.effects) ~= "table" or #technology.effects ~= #expected then
    fail(label .. " effect vector changed")
  end
  for index, recipe in ipairs(expected) do
    local effect = technology.effects[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= recipe or effect.change ~= 0.05 then
      fail(label .. " effect changed at " .. tostring(index))
    end
  end
end

local function accelerate(name, expected_effects, expected_time)
  local technology = data.raw.technology and data.raw.technology[name]
  if type(technology) ~= "table" or type(technology.unit) ~= "table" then
    fail("MIR ATAN technology is absent: " .. name)
  end
  if technology.enabled ~= true or technology.max_level ~= "infinite"
      or technology.unit.count ~= nil or technology.unit.count_formula ~= "8000*2^(L-1)"
      or technology.unit.time ~= expected_time then
    fail("MIR ATAN workload changed: " .. name)
  end
  assert_effects(technology, expected_effects, name)
  technology.unit.count, technology.unit.count_formula, technology.unit.time = nil, "1", 1
end

local AIR = "recipe-prod-research_air_scrubbing_clean_filter-1"
local ASH = "recipe-prod-research_ash_separation-1"
accelerate(AIR, is_space_age and {"atan-pollution-filter", "atan-spore-filter"}
  or {"atan-pollution-filter"}, 60)
accelerate(ASH, {"atan-ash-seperation"}, 90)
