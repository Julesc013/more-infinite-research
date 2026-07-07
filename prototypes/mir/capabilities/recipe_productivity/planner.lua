local C = require("prototypes.mir.streams.registry")
local D = require("prototypes.mir.report.diagnostics_sink")
local recipes = require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")

local M = {}

function M.match_buckets(key, spec)
  local buckets = recipes.recipes_for_stream(spec, C.shared.per_level_default)
  D.recipe_matches(key, buckets)
  return buckets
end

function M.effects_from_buckets(key, buckets)
  local effects = {}

  for _, bucket in ipairs(buckets or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      table.insert(effects, {
        type = "change-recipe-productivity",
        recipe = recipe_name,
        change = bucket.change or C.shared.per_level_default
      })
      D.record_recipe_match(key, recipe_name)
    end
  end

  return effects
end

return M
