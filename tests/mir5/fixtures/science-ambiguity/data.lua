-- SCI-UNLOCK-01 is retained as a ledger reference only. This representative
-- opponent is not the reported player profile and does not close that subject.
-- Factorio 2.1.23's prototype-api.json defines TechnologyUnit.ingredients as
-- ResearchIngredient tuples: [ItemID, uint16], not ItemIngredientPrototype.
local science_pack = "automation-science-pack"
local alternative_name = "mir-science-ambiguity-automation-science-pack"
local owner_names = {
  "mir-science-ambiguity-owner-a",
  "mir-science-ambiguity-owner-b"
}

local original = assert(data.raw.recipe[science_pack], "base automation science recipe is required")
assert(data.raw.technology[science_pack], "base automation science technology is required")

-- Copy only the named native recipe. Its original disabled seed path remains
-- untouched; the copy keeps the same declared product and recipe fields.
local alternative = table.deepcopy(original)
alternative.name = alternative_name

local function owner(name)
  return {
    type = "technology",
    name = name,
    icon = "__base__/graphics/technology/automation-science-pack.png",
    icon_size = 256,
    prerequisites = {science_pack},
    unit = {
      count = 1,
      time = 1,
      ingredients = {{science_pack, 1}}
    },
    effects = {{type = "unlock-recipe", recipe = science_pack}}
  }
end

data:extend({alternative, owner(owner_names[1]), owner(owner_names[2])})
