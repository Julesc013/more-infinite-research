local D = require("prototypes.mir.report.diagnostics_sink")
local competing_productivity = require("prototypes.mir.policy.competing_productivity")
local productivity_owners = require("prototypes.mir.index.productivity_owners")

local M = {}

function M.recipe_names_from_effects(effects)
  return productivity_owners.recipe_names_from_effects(effects)
end

function M.existing_infinite_recipe_productivity_owner_records(recipe_name, spec)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  return productivity_owners.blocking_recipe_productivity_owner_records(recipe_name, {
    ignore_owner = competing_productivity.ignores_existing_owner,
    adoption_tech = adoption and adoption.tech
  })
end

function M.filter_existing_recipe_productivity(key, spec, buckets)
  local filtered_buckets = {}
  local skipped = {}

  for _, bucket in ipairs(buckets or {}) do
    local recipes = {}
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      local owner_records = M.existing_infinite_recipe_productivity_owner_records(recipe_name, spec)
      if #owner_records > 0 then
        table.insert(skipped, {
          recipe = recipe_name,
          owners = productivity_owners.owner_names(owner_records),
          owner_kinds = productivity_owners.owner_kinds(owner_records),
          owner_actions = productivity_owners.owner_actions(owner_records)
        })
      else
        table.insert(recipes, recipe_name)
      end
    end
    if #recipes > 0 then
      table.insert(filtered_buckets, {
        change = bucket.change,
        recipes = recipes
      })
    end
  end

  for _, entry in ipairs(skipped) do
    D.recipe_owner({
      key = key,
      status = "skipped",
      reason = "covered_by_existing_infinite_recipe_productivity",
      recipe = entry.recipe,
      owners = entry.owners,
      owner_kinds = entry.owner_kinds,
      owner_actions = entry.owner_actions
    })
    log("[more-infinite-research] Skipping recipe productivity effect for "
      .. key .. " recipe=" .. entry.recipe
      .. " because existing infinite technology already owns it: "
      .. entry.owners)
  end

  return filtered_buckets, skipped
end

return M
