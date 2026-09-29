local D = require("prototypes.mir.report.diagnostics_sink")
local competing_productivity = require("prototypes.mir.policy.competing_productivity")
local productivity_owners = require("prototypes.mir.index.productivity_owners")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")

local M = {}

function M.recipe_names_from_effects(effects)
  return productivity_owners.recipe_names_from_effects(effects)
end

function M.existing_infinite_recipe_productivity_owner_records(recipe_name, spec)
  local adoption = spec and spec.native_owner_binding
  return productivity_owners.blocking_recipe_productivity_owner_records(recipe_name, {
    ignore_owner = competing_productivity.ignores_existing_owner,
    adoption_tech = adoption and adoption.owner
  })
end

-- An effect on an infinite external technology is only a live owner when the
-- technology itself can still be researched.  A disabled technology, a
-- prerequisite cycle, or an unreachable science route must not silently
-- suppress an otherwise admissible MIR material route.  Keep the structural
-- owner query above intact for diagnostics and replacement planning; this
-- narrower projection is the one that makes an emission decision.
local function researchable_owner_records(recipe_name, spec)
  local records = {}
  local unavailable = {}
  for _, record in ipairs(M.existing_infinite_recipe_productivity_owner_records(recipe_name, spec)) do
    local rejection = science.technology_researchability_reason(record.tech)
    if rejection then
      table.insert(unavailable, {record = record, rejection = rejection})
    else
      table.insert(records, record)
    end
  end
  return records, unavailable
end

function M.filter_existing_recipe_productivity(key, spec, buckets)
  local filtered_buckets = {}
  local skipped = {}
  local unavailable = {}

  for _, bucket in ipairs(buckets or {}) do
    local recipes = {}
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      local owner_records, unavailable_records = researchable_owner_records(recipe_name, spec)
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
      for _, entry in ipairs(unavailable_records) do
        table.insert(unavailable, {
          recipe = recipe_name,
          owner = entry.record.tech,
          owner_kind = entry.record.kind,
          owner_action = entry.record.action,
          rejection = entry.rejection
        })
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

  for _, entry in ipairs(unavailable) do
    D.recipe_owner({
      key = key,
      status = "not_blocking",
      reason = "existing_infinite_recipe_productivity_owner_unresearchable",
      recipe = entry.recipe,
      owners = entry.owner,
      owner_kinds = entry.owner_kind,
      owner_actions = entry.owner_action,
      owner_rejection = entry.rejection
    })
    log("[more-infinite-research] Ignoring unreachable external recipe productivity owner for "
      .. key .. " recipe=" .. entry.recipe
      .. " owner=" .. entry.owner
      .. " reason=" .. entry.rejection)
  end

  return filtered_buckets, skipped
end

return M
