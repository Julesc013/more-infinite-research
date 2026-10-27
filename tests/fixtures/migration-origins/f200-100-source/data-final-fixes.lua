local fixture = "mir-fixture-mir5-migration-origin-f200-100-source"
local catalogue = require("__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue")
if mods.base ~= "2.0.77" or mods["more-infinite-research"] ~= "1.0.0"
    or mods[fixture] ~= "0.1.0" then
  error("[mir5-migration-origin-f200-100-source] source closure differs")
end

local source_setting = assert(settings.startup[catalogue.unavailable_space_age_setting],
  "[mir5-migration-origin-f200-100-source] source breeding setting is absent")
assert(source_setting.value == false,
  "[mir5-migration-origin-f200-100-source] fixture source breeding setting differs")

local function science_map(value)
  local actual = {}
  for _, ingredient in ipairs(value or {}) do
    local name, amount = ingredient[1], ingredient[2]
    assert(type(name) == "string" and amount == 1,
      "[mir5-migration-origin-f200-100-source] source science row differs")
    assert(actual[name] == nil,
      "[mir5-migration-origin-f200-100-source] source science duplicates a pack")
    actual[name] = amount
  end
  return actual
end

local function expected_science(name)
  local result = {}
  for pack, amount in pairs(catalogue.source_science) do result[pack] = amount end
  local key = name:sub(#catalogue.technology_prefix + 1, #name - #catalogue.technology_suffix)
  for _, pack in ipairs(catalogue.source_science_extras[key] or {}) do
    assert(result[pack] == nil,
      "[mir5-migration-origin-f200-100-source] source science extra duplicates a base pack: " .. name)
    result[pack] = 1
  end
  return result
end

local roster = {}
for name, value in pairs(data.raw.technology or {}) do
  if name:sub(1, #catalogue.technology_prefix) == catalogue.technology_prefix then
    assert(name:sub(-#catalogue.technology_suffix) == catalogue.technology_suffix,
      "[mir5-migration-origin-f200-100-source] source roster suffix differs")
    -- MIR 1.0.0 authoring intentionally omits the optional raw `level` field.
    -- Factorio materializes its runtime prototype level as 1; control.lua checks
    -- that parsed-runtime fact independently. An explicit raw level here would
    -- describe different source bytes, including an explicit level of 1.
    local identity_matches = value.type == "technology" and value.name == name and value.level == nil
      and value.upgrade == true and value.max_level == "infinite" and value.enabled ~= false
    if not identity_matches then
      error("[mir5-migration-origin-f200-100-source] source roster identity differs: " .. name
        .. " type=" .. tostring(value.type) .. " raw_name=" .. tostring(value.name)
        .. " raw_level=" .. tostring(value.level) .. " upgrade=" .. tostring(value.upgrade)
        .. " max_level=" .. tostring(value.max_level) .. " enabled=" .. tostring(value.enabled))
    end
    local unit = assert(value.unit,
      "[mir5-migration-origin-f200-100-source] source roster unit is absent: " .. name)
    assert(unit.count_formula == catalogue.source_formula and unit.time == catalogue.source_time,
      "[mir5-migration-origin-f200-100-source] source roster formula differs: " .. name)
    local actual_science = science_map(unit.ingredients)
    for pack, amount in pairs(expected_science(name)) do
      assert(actual_science[pack] == amount,
        "[mir5-migration-origin-f200-100-source] source roster science differs: " .. name)
      actual_science[pack] = nil
    end
    assert(next(actual_science) == nil,
      "[mir5-migration-origin-f200-100-source] source roster has extra science: " .. name)
    assert(type(value.effects) == "table" and #value.effects > 0,
      "[mir5-migration-origin-f200-100-source] source roster effects are absent: " .. name)
    roster[#roster + 1] = name
  end
end
table.sort(roster)
assert(#roster >= catalogue.minimum_rows and #roster <= catalogue.maximum_rows,
  "[mir5-migration-origin-f200-100-source] source roster count is outside the published bound")
local seen_direct = false
for _, name in ipairs(roster) do if name == catalogue.direct then seen_direct = true end end
assert(seen_direct, "[mir5-migration-origin-f200-100-source] source gear technology is absent")

local gear_effects = 0
for _, effect in ipairs(data.raw.technology[catalogue.direct].effects or {}) do
  if effect.type == "change-recipe-productivity" and effect.recipe == "iron-gear-wheel"
      and effect.change == .10 then
    gear_effects = gear_effects + 1
  end
end
assert(gear_effects == 1,
  "[mir5-migration-origin-f200-100-source] source gear productivity effect differs")

-- Only the selected source gear row is accelerated. The recorded source
-- roster, formula, science multiset and every other source effect remain
-- original input facts for the protected migration-origin save.
local direct = data.raw.technology[catalogue.direct]
direct.unit.count_formula = nil
direct.unit.count = 1
direct.unit.time = 1
