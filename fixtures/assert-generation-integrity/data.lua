local prototypes = {}
local previous = "iron-plate"

for index = 1, 1000 do
  local item_name = string.format("mir-fixture-synthetic-item-%04d", index)
  table.insert(prototypes, {
    type = "item",
    name = item_name,
    icon = "__base__/graphics/icons/iron-plate.png",
    icon_size = 64,
    stack_size = 1,
    hidden = true
  })
  table.insert(prototypes, {
    type = "recipe",
    name = string.format("mir-fixture-synthetic-recipe-%04d", index),
    enabled = true,
    hidden = true,
    allow_productivity = true,
    ingredients = {{type = "item", name = previous, amount = 1}},
    results = {{type = "item", name = item_name, amount = 1}}
  })
  previous = item_name
end

local complete_product = {
  type = "item",
  name = "copper-plate",
  amount = 1,
  extra_count_fraction = 0.25
}
local factorio_2_0 = mods and type(mods.base) == "string"
  and string.match(mods.base, "^2%.0%.") ~= nil
if factorio_2_0 then
  complete_product.probability = 0.5
  complete_product.ignored_by_productivity = 0
  complete_product.ignored_by_stats = 0
else
  complete_product.independent_probability = 0.5
  complete_product.percent_spoiled = 0.1
  complete_product.always_fresh = true
  complete_product.reset_freshness_on_craft = true
  complete_product.quality_min = "normal"
  complete_product.quality_max = "normal"
  complete_product.quality_change = 0
  complete_product.affected_by_quality = false
end

table.insert(prototypes, {
  type = "recipe",
  name = "mir-fixture-default-productivity-policy",
  enabled = true,
  ingredients = {{type = "item", name = "iron-plate", amount = 1}},
  results = {{type = "item", name = "iron-gear-wheel", amount = 1}}
})
table.insert(prototypes, {
  type = "recipe",
  name = "mir-fixture-complete-product-shape",
  enabled = true,
  allow_productivity = true,
  ingredients = {{type = "item", name = "iron-plate", amount = 1}},
  results = {complete_product}
})

data:extend(prototypes)

-- Adversarial compatibility input: progression invariants must win over an
-- otherwise schema-valid request to exclude cryogenic science.
data:extend({{
  type = "mod-data",
  name = "more-infinite-research-compatibility-pack",
  data = {
    schema = 2,
    id = "assert-generation-integrity-cryogenic-denial",
    applicability = {mods = {{id = "assert-generation-integrity", version = "*"}}},
    aliases = {},
    exact = {includes = {}, excludes = {}},
    family_hints = {},
    science_roles = {
      {stream = "research_ice", pack = "cryogenic-science-pack", role = "exclude"},
      {stream = "research_platform", pack = "cryogenic-science-pack", role = "exclude"}
    },
    owner_claims = {},
    risk_overrides = {},
    family_authorizations = {},
    candidate_seeds = {},
    targets = {factorio_lines = {"2.1"}},
    evidence = {fixtures = {"assert-generation-integrity"}, real_mod = {}},
    claim = {level = "fixture-only", public = false}
  }
}})
