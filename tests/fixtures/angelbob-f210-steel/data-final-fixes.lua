-- Validate the named native owner after all admitted final-fix effects.  The
-- fixture neither replaces this technology nor edits its cost or effect array.
local facts = require("__mir-fixture-mir5-angelbob-f210-steel__/fixture_facts")
local function fail(message) error("[mir5-angelbob-f210-steel] " .. message) end

local function exact_strings(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do
    if actual[index] ~= name then
      fail(label .. " differs at " .. tostring(index))
    end
  end
end

local function exact_ingredients(actual, expected, label)
  if type(actual) ~= "table" or #actual ~= #expected then fail(label .. " count differs") end
  for index, name in ipairs(expected) do
    local row = actual[index]
    if type(row) ~= "table" or (row.name or row[1]) ~= name or (row.amount or row[2]) ~= 1 then
      fail(label .. " differs at " .. tostring(index))
    end
  end
end

local function named_effects(actual)
  local wanted, seen = {}, {}
  for _, recipe in ipairs(facts.named_recipes) do wanted[recipe] = true end
  for _, effect in ipairs(type(actual) == "table" and actual or {}) do
    if type(effect) == "table" and effect.type == "change-recipe-productivity" and wanted[effect.recipe] then
      seen[effect.recipe] = (seen[effect.recipe] or 0) + 1
      if not facts.close(effect.change, facts.effect_change) then fail("named productivity change differs: " .. effect.recipe) end
    end
  end
  for _, recipe in ipairs(facts.named_recipes) do
    if seen[recipe] ~= 1 then fail("named productivity effect count differs: " .. recipe) end
  end
end

facts.assert_exact_mods(mods, fail)
local owner = data.raw.technology and data.raw.technology[facts.owner]
if type(owner) ~= "table" or owner.name ~= facts.owner or owner.level ~= 1 or owner.max_level ~= "infinite"
    or type(owner.unit) ~= "table" or owner.unit.count ~= nil or owner.unit.count_formula ~= "1.5^L*1000"
    or owner.unit.time ~= 60 then
  fail("native steel owner identity or ordinary cost differs")
end
exact_strings(owner.prerequisites, facts.prerequisites, "native steel prerequisites")
exact_ingredients(owner.unit.ingredients, facts.ingredients, "native steel ingredients")
named_effects(owner.effects)
