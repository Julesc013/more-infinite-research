local automatic_compiler_policy = require("prototypes.mir.settings.automatic_compiler_policy")
local family_resolver = require("prototypes.mir.families.resolver")
local effect_ownership = require("prototypes.mir.planner.effect_ownership")

local M = {}

function M.attach_family_recipes(key, buckets)
  local policy = automatic_compiler_policy.current()
  if not policy.apply_changes then return buckets end
  local attachments = family_resolver.attachments_for_stream(key)
  if #attachments == 0 then return buckets end

  local assigned, fallback_bucket_by_recipe, buckets_by_change, recipe_sets = {}, {}, {}, {}
  for _, bucket in ipairs(buckets or {}) do
    buckets_by_change[bucket.change] = bucket
    local recipe_set = {}
    recipe_sets[bucket] = recipe_set
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      recipe_set[recipe_name] = true
      assigned[recipe_name] = true
      if bucket.structural_fallback then fallback_bucket_by_recipe[recipe_name] = bucket end
    end
  end
  for _, attachment in ipairs(attachments) do
    local fallback_bucket = fallback_bucket_by_recipe[attachment.recipe]
    if fallback_bucket then
      recipe_sets[fallback_bucket][attachment.recipe] = nil
      assigned[attachment.recipe] = nil
      fallback_bucket_by_recipe[attachment.recipe] = nil
    end
    if not assigned[attachment.recipe] then
      local bucket = buckets_by_change[attachment.change]
      if not bucket then
        bucket = {change = attachment.change, recipes = {}}
        buckets_by_change[attachment.change] = bucket
        recipe_sets[bucket] = {}
        table.insert(buckets, bucket)
      end
      recipe_sets[bucket][attachment.recipe] = true
      assigned[attachment.recipe] = true
    end
  end
  local compact = {}
  for _, bucket in ipairs(buckets or {}) do
    bucket.recipes = {}
    for recipe_name, _ in pairs(recipe_sets[bucket] or {}) do table.insert(bucket.recipes, recipe_name) end
    table.sort(bucket.recipes)
    if #bucket.recipes > 0 then table.insert(compact, bucket) end
  end
  return compact
end

function M.resolve(rows)
  return effect_ownership.resolve(rows, {defer_design_refresh = true})
end

return M
