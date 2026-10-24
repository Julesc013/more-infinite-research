-- The playable migration roles keep their producer. This separate startup
-- role deliberately declares only the same foreign pack/research definitions.
local pack = "mir5-foreign-astral-insight-pack"
assert(mods.base == "2.1.23" and mods["more-infinite-research"] == "5.0.21000"
  and mods["mir-fixture-mir5-foreign-research-preservation"] == "0.3.0",
  "unresolved foreign startup fixture closure differs")
assert(data.raw.tool[pack] and data.raw.recipe[pack] == nil,
  "unresolved foreign startup fixture gained its named pack producer")
for _, level in ipairs({61, 62}) do
  local name = "Space-Lab-Research-" .. level
  local row = assert(data.raw.technology[name], "foreign research disappeared: " .. name)
  local ingredient = row.unit and row.unit.ingredients and row.unit.ingredients[3]
  assert(row.type == "technology" and row.name == name and row.max_level == level
    and row.unit.count == level and row.unit.time == level
    and type(ingredient) == "table" and ingredient[1] == pack and ingredient[2] == 1
    and #row.effects == 1 and row.effects[1].type == "laboratory-speed"
    and row.effects[1].modifier == level / 1000,
    "foreign research changed: " .. name)
end
assert(data.raw.technology["recipe-prod-research_gears-1"],
  "MIR gear research disappeared beside unresolved foreign research")
