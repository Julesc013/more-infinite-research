-- Replace only the canonical recipe/unlock pair after normal data has loaded.
-- Gear's authored vector omits electromagnetic science; all-official must add
-- this direct replacement instead of changing an authored gear ingredient.
local PACK = "electromagnetic-science-pack"
local CIRCULAR_RECIPE = "a-mir473-circular-electromagnetic-science"
local SEEDED_RECIPE = "z-mir473-seeded-electromagnetic-science"
local CIRCULAR_OWNER = "a-mir473-circular-electromagnetic-owner"
local SEEDED_OWNER = "z-mir473-seeded-electromagnetic-owner"
local FOREIGN = "mir473-named-science-foreign"

local canonical_recipe = assert(data.raw.recipe[PACK], "canonical electromagnetic science recipe is required")
local canonical_owner = assert(data.raw.technology[PACK], "canonical electromagnetic science technology is required")
assert(canonical_recipe.name == PACK, "canonical electromagnetic recipe identity differs")

local retained_effects, removed_unlocks = {}, 0
for _, effect in ipairs(canonical_owner.effects or {}) do
  if effect.type == "unlock-recipe" and effect.recipe == PACK then
    removed_unlocks = removed_unlocks + 1
  else
    retained_effects[#retained_effects + 1] = effect
  end
end
assert(removed_unlocks == 1, "canonical electromagnetic unlock must be removed exactly once")
canonical_owner.effects = retained_effects
data.raw.recipe[PACK] = nil

local function producer(name)
  return {
    type = "recipe",
    name = name,
    enabled = false,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = PACK, amount = 1}}
  }
end

local function owner(name)
  -- Reuse the actual F210 technology presentation so this fixture never
  -- assumes whether the native definition uses icon or icons.
  local technology = table.deepcopy(canonical_owner)
  technology.name = name
  technology.enabled = true
  technology.prerequisites = {}
  technology.unit = nil
  technology.research_trigger = nil
  technology.effects = {}
  return technology
end

local circular = owner(CIRCULAR_OWNER)
circular.unit = {count = 1, time = 1, ingredients = {{PACK, 1}}}
circular.effects = {{type = "unlock-recipe", recipe = CIRCULAR_RECIPE}}
local seeded = owner(SEEDED_OWNER)
seeded.research_trigger = {type = "craft-item", item = "iron-plate", count = 1}
seeded.effects = {{type = "unlock-recipe", recipe = SEEDED_RECIPE}}
local foreign = owner(FOREIGN)
foreign.prerequisites = {PACK}
foreign.unit = {count = 2, time = 5, ingredients = {{PACK, 2}}}
data:extend({
  producer(CIRCULAR_RECIPE),
  producer(SEEDED_RECIPE),
  circular,
  seeded,
  foreign
})
