-- This private acceleration follows the existing fresh-source oracle.  It
-- verifies the emitted all-policy science-productivity witness in full before
-- removing only that witness's research gates, so a native transition can use
-- actual laboratories without granting normal progression or MIR levels.
local TARGET = "recipe-prod-research_science_pack_productivity-1"
local SEEDED = "mir473-seeded-planetary-owner"
local RECIPES = {"a-mir473-circular-planetary-data", "z-mir473-seeded-planetary-data"}
local SCIENCE = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
  "planetary-data",
}
local PREREQUISITES = {
  "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
  "production-science-pack", "military-science-pack", "utility-science-pack",
  "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
  "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack", SEEDED,
}

local function exact_names(rows, expected, label, row_value)
  assert(type(rows) == "table", label .. " is absent")
  local wanted, seen, count = {}, {}, 0
  for _, name in ipairs(expected) do wanted[name] = true end
  for key, row in pairs(rows) do
    assert(type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #rows,
      label .. " is not a dense sequence")
    local name = row_value(row)
    assert(type(name) == "string" and wanted[name] and not seen[name], label .. " differs")
    seen[name], count = true, count + 1
  end
  assert(count == #expected, label .. " differs")
end

local science = (data.raw.technology or {})[TARGET]
assert(type(science) == "table" and science.name == TARGET and science.type == "technology" and science.level == 1
  and science.upgrade == true and science.max_level == "infinite", "fresh science transition target identity changed")
local unit = science.unit
assert(type(unit) == "table" and unit.count == nil and unit.count_formula == "1*2^(L-1)" and unit.time == 1,
  "fresh science transition target cost, time, or growth changed")
exact_names(unit.ingredients, SCIENCE, "fresh science transition inputs", function(row)
  assert(type(row) == "table" and (row.type == nil or row.type == "item"),
    "fresh science transition input type changed")
  local amount = row.amount or row[2]
  assert(type(amount) == "number" and amount == 1, "fresh science transition input quantity changed")
  return row.name or row[1]
end)
exact_names(science.prerequisites, PREREQUISITES, "fresh science transition prerequisites", function(row) return row end)

local expected_effects, seen_effects = {}, {}
for _, recipe in ipairs(RECIPES) do expected_effects[recipe] = true end
for _, effect in ipairs(science.effects or {}) do
  if type(effect) == "table" and expected_effects[effect.recipe] then
    assert(effect.type == "change-recipe-productivity" and effect.change == 0.1 and not seen_effects[effect.recipe],
      "fresh science transition recipe effect changed")
    seen_effects[effect.recipe] = true
  end
end
for _, recipe in ipairs(RECIPES) do
  assert(seen_effects[recipe], "fresh science transition recipe effect was omitted")
end

-- The fixture owns this one transient acceleration only. The dependency's
-- data-final observer has already retained the real all-policy gate proof.
science.prerequisites = {}
