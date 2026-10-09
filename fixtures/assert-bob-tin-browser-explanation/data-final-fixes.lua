local technology_name = "recipe-prod-research_material_tin-1"
local stream_key = "research_material_tin"
local recipe_name = "bob-tin-plate"

local function fail(message) error("[mir-bob-tin-browser-explanation] " .. message) end
local function assert_exact(actual, expected, message)
  if actual ~= expected then fail(message .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual)) end
end

for _, name in ipairs({"base", "boblibrary", "bobores", "bobplates", "more-infinite-research"}) do
  if not mods[name] then fail("locked Bob-only route universe is missing " .. name) end
end
for _, name in ipairs({"angelssmelting", "angelsrefining", "angelspetrochem"}) do
  if mods[name] then fail("Bob-only browser fixture refuses " .. name) end
end

local plan = ((data.raw["mod-data"] or {})["more-infinite-research-generation-plan"] or {}).data
if type(plan) ~= "table" or plan.schema ~= 1 or plan.kind ~= "mir-generation-plan-public" then
  fail("public generation-plan projection is absent")
end
local rows = {}
for _, row in ipairs(plan.rows or {}) do
  if row.technology_id == technology_name then table.insert(rows, row) end
end
if #rows ~= 1 then fail("Tin requires exactly one public generation-plan row") end
local row = rows[1]
assert_exact(row.stream_id, stream_key, "public stream")
assert_exact(row.action, "emit", "public action")
assert_exact(row.reason, "recipe_productivity", "public reason")
if type(row.affected_recipe_ids) ~= "table" or #row.affected_recipe_ids ~= 1 or row.affected_recipe_ids[1] ~= recipe_name then
  fail("public affected recipe IDs are not exact")
end
local disposition = row.disposition
if type(disposition) ~= "table" or disposition.schema ~= 1 or disposition.inclusion ~= "included"
  or disposition.action ~= row.action or disposition.reason ~= row.reason
  or type(disposition.route_exclusions) ~= "table"
  or disposition.route_exclusions.state ~= "no-additional-route-exclusions-published-for-current-row"
  or #(disposition.route_exclusions.recipe_ids or {}) ~= 0 then
  fail("public row-local exclusion availability is malformed")
end

local recipe = (data.raw.recipe or {})[recipe_name]
local technology = (data.raw.technology or {})[technology_name]
if not recipe or not technology then fail("exact Bob Tin recipe or MIR technology is absent") end
local owners = 0
for name, candidate in pairs(data.raw.technology or {}) do
  for _, effect in ipairs(candidate.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      owners = owners + 1
      if name ~= technology_name then fail("Tin effect owner differs " .. name) end
      assert_exact(effect.change, 0.02, "Tin effect change")
    end
  end
end
if owners ~= 1 then fail("Tin requires exactly one effect owner") end
local ingredient = ((technology.unit or {}).ingredients or {})[1]
local ingredient_name = type(ingredient) == "table" and (ingredient.name or ingredient[1]) or nil
local ingredient_amount = type(ingredient) == "table" and (ingredient.amount or ingredient[2]) or nil
if not ingredient or ingredient_name ~= "automation-science-pack" or ingredient_amount ~= 1
  or #((technology.unit or {}).ingredients or {}) ~= 1 then
  fail("final Tin science ingredients are not exact")
end

-- Fixture-only valid public non-recipe row: it proves that the provider
-- retains its legacy family/action DTO rather than fabricating a false
-- recipe-benefit result for an empty affected-recipe set.
local non_recipe_name = "mir-browser-non-recipe-regression"
data:extend({{
  type = "technology", name = non_recipe_name,
  icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64,
  unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
}})
table.insert(plan.rows, {
  schema = 1,
  stream_id = "browser_non_recipe_regression",
  action = "emit",
  reason = "emit",
  technology_id = non_recipe_name,
  effect_count = 0,
  effect_identities = {},
  affected_recipe_ids = {},
  disposition = {
    schema = 1, inclusion = "included", action = "emit", reason = "emit",
    route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}
  }
})

-- Two individually valid declarations for one fixture-only technology must be
-- fail-closed by the provider. This is a drift negative for duplicate public
-- row identity, including one that would otherwise have a harmless empty
-- affected-recipe set.
local duplicate_name = "mir-browser-duplicate-row-regression"
data:extend({{
  type = "technology", name = duplicate_name,
  icon = "__base__/graphics/icons/copper-plate.png", icon_size = 64,
  unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
}})
for _ = 1, 2 do
  table.insert(plan.rows, {
    schema = 1, stream_id = "browser_duplicate_row_regression", action = "emit", reason = "emit",
    technology_id = duplicate_name, effect_count = 0, effect_identities = {}, affected_recipe_ids = {},
    disposition = {
      schema = 1, inclusion = "included", action = "emit", reason = "emit",
      route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}
    }
  })
end

local wrong_schema_name = "mir-browser-wrong-schema-row-regression"
local extra_field_name = "mir-browser-extra-field-row-regression"
data:extend({
  {
    type = "technology", name = wrong_schema_name,
    icon = "__base__/graphics/icons/iron-gear-wheel.png", icon_size = 64,
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
  },
  {
    type = "technology", name = extra_field_name,
    icon = "__base__/graphics/icons/copper-cable.png", icon_size = 64,
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
  }
})

table.insert(plan.rows, {
  schema = 99, stream_id = "browser_wrong_schema_row_regression",
  action = "emit", reason = "emit", technology_id = wrong_schema_name,
  effect_count = 0, effect_identities = {}, affected_recipe_ids = {},
  decision_fingerprint = "fixture-only",
  disposition = {
    schema = 1, inclusion = "included", action = "emit", reason = "emit",
    route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}
  }
})

table.insert(plan.rows, {
  schema = 1, stream_id = "browser_extra_field_row_regression",
  action = "emit", reason = "emit", technology_id = extra_field_name,
  effect_count = 0, effect_identities = {}, affected_recipe_ids = {},
  decision_fingerprint = "fixture-only", unexpected = true,
  disposition = {
    schema = 1, inclusion = "included", action = "emit", reason = "emit",
    route_exclusions = {state = "no-additional-route-exclusions-published-for-current-row", recipe_ids = {}}
  }
})
log("[mir-bob-tin-browser-explanation] DATA PASS public-row=emit affected=bob-tin-plate science=automation-science-pack:1")
