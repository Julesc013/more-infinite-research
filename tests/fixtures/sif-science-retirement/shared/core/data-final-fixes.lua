local fixture = script and script.mod_name or nil
-- Data stage does not expose script. Derive the target from the exact fixture
-- name that Factorio makes active in `mods`.
local target, fixture_version
for _, id in ipairs({"f200", "f210"}) do
  local name = "mir-fixture-mir5-sif-science-retirement-" .. id
  if mods[name] ~= nil then
    if target ~= nil then error("[mir5-sif] multiple core fixtures are active") end
    target, fixture, fixture_version = id, name, mods[name]
  end
end
assert(target ~= nil, "[mir5-sif] target core fixture is absent")
local expected_engine = target == "f200" and "2.0.77" or "2.1.23"
local expected_sif = target == "f200" and "1.0.60" or "1.0.78"
local expected_commons = target == "f200" and "1.0.27" or "1.0.33"
local expected_mir = fixture_version == "0.1.0" and "4.7." .. (target == "f200" and "20002" or "21002")
  or fixture_version == "0.2.0" and "5.0." .. (target == "f200" and "20000" or "21000")
assert(expected_mir ~= nil, "[mir5-sif] fixture version is not an admitted source or successor")
assert(mods.base == expected_engine and mods["elevated-rails"] == expected_engine
  and mods.quality == expected_engine and mods["space-age"] == expected_engine
  and mods["space-is-fake"] == expected_sif and mods["cr-commons"] == expected_commons
  and mods["more-infinite-research"] == expected_mir, "[mir5-sif] exact engine or native archive closure differs")
if target == "f210" then
  assert(mods.recycler == expected_engine and mods["cr-extras"] == "1.0.1", "[mir5-sif] F210 closure differs")
else
  assert(mods.recycler == nil and mods["cr-extras"] == nil, "[mir5-sif] F200 unexpectedly selects an F210-only component")
end

local selectors = {
  "configured", "space", "space-and-promethium", "space-age-progression",
  "official-progression", "mod-progression", "all-official", "all"
}
local selected, selector_count
for _, policy in ipairs(selectors) do
  local name = "mir-fixture-mir5-sif-policy-" .. policy .. "-" .. target
  if mods[name] ~= nil then selected, selector_count = policy, (selector_count or 0) + 1 end
end
assert(selector_count == 1, "[mir5-sif] exactly one policy selector is required")
local setting = assert(settings.startup["mir-science-pack-ingredient-policy"], "[mir5-sif] MIR policy setting is absent")
assert(setting.value == selected, "[mir5-sif] selector did not establish the effective policy")
assert(fixture_version ~= "0.1.0" or selected == "configured", "[mir5-sif] published upgrade seed is configured-only")

local contract = require("__" .. fixture .. "__/contract")
-- Both exact engine inputs define Biolab's 50% science drain.  The fixture
-- uses two research units so each completed full research consumes one of
-- every one-unit science input without changing any owned science row.
local biolab = assert(data.raw.lab and data.raw.lab.biolab, "[mir5-sif] native biolab is absent")
assert(biolab.science_pack_drain_rate_percent == 50, "[mir5-sif] native biolab drain differs")
local function check_sequence(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, "[mir5-sif] " .. label .. " count differs")
  for index, wanted in ipairs(expected) do
    local row = actual[index]
    local name, amount = row and (row.name or row[1]), row and (row.amount or row[2])
    assert(name == wanted[1] and amount == wanted[2] and row[3] == nil,
      "[mir5-sif] " .. label .. " differs at " .. tostring(index))
  end
end
local function check_names(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, "[mir5-sif] " .. label .. " count differs")
  for index, wanted in ipairs(expected) do
    assert(actual[index] == wanted, "[mir5-sif] " .. label .. " differs at " .. tostring(index))
  end
end
local function check_effects(actual, expected, label)
  assert(type(actual) == "table" and #actual == #expected, "[mir5-sif] " .. label .. " count differs")
  for index, wanted in ipairs(expected) do
    local got = actual[index]
    assert(type(got) == "table" and got.type == wanted.type and got.modifier == wanted.modifier
      and got.ammo_category == wanted.ammo_category and got.recipe == nil,
      "[mir5-sif] " .. label .. " differs at " .. tostring(index))
  end
end
local function expected_row(row)
  if fixture_version == "0.1.0" then return row.published.science, row.published.prerequisites end
  return row.science[selected], row.prerequisites[selected]
end
local pending = {}
for name, expected in pairs(contract.rows) do
  local technology = assert(data.raw.technology[name], "[mir5-sif] missing " .. name)
  assert(technology.type == "technology" and technology.name == name and technology.level == 7
    and technology.upgrade == true and technology.max_level == "infinite" and technology.hidden == false,
    "[mir5-sif] " .. name .. " identity differs")
  local unit = assert(technology.unit, "[mir5-sif] " .. name .. " research unit is absent")
  assert(unit.count == nil and unit.count_formula == expected.formula and unit.time == expected.time,
    "[mir5-sif] " .. name .. " tuning differs")
  local science, prerequisites = expected_row(expected)
  check_sequence(unit.ingredients, science, name .. " science")
  check_names(technology.prerequisites, prerequisites, name .. " prerequisites")
  check_effects(technology.effects, expected.effects, name .. " effects")
  for _, row in ipairs(unit.ingredients) do assert((row.name or row[1]) ~= "space-science-pack", "[mir5-sif] retired space science survived") end
  for _, prerequisite in ipairs(technology.prerequisites) do assert(prerequisite ~= "space-science-pack", "[mir5-sif] retired space prerequisite survived") end
  pending[#pending + 1] = unit
end
-- All selected rows passed complete prototype preflight. Only now reduce their
-- disposable test-world count/time; no science, prerequisite, or effect moves.
for _, unit in ipairs(pending) do unit.count, unit.count_formula, unit.time = 2, nil, 1 end
