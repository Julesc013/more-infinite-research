local C = require("prototypes.config")
local productivity_owners = require("prototypes.compat.productivity-owners")

local A = {}

local MOD_DATA_NAME = "more-infinite-research-productivity-family-adoption"
local VERSION = 1
local adopted_productivity_family_recipes = {}

local function append_recipe_to_bucket(out, bucket, recipe_name)
  local target = out[#out]
  if not target or target.change ~= bucket.change then
    target = {change = bucket.change, recipes = {}}
    table.insert(out, target)
  end
  table.insert(target.recipes, recipe_name)
end

local function partition_candidates(key, spec, buckets)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  if not adoption then return buckets, {} end

  local eligible_buckets = {}
  local blocked = {}

  for _, bucket in ipairs(buckets or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      local reason = nil
      if not productivity_owners.recipe_allows_productivity(recipe_name) then
        reason = "recipe_productivity_not_allowed"
      elseif not productivity_owners.recipe_outputs_any_product(recipe_name, adoption.products) then
        reason = "recipe_not_in_configured_family_products"
      end

      if reason then
        table.insert(blocked, {
          recipe = recipe_name,
          reason = reason
        })
      else
        append_recipe_to_bucket(eligible_buckets, bucket, recipe_name)
      end
    end
  end

  for _, entry in ipairs(blocked) do
    log("[more-infinite-research] Skipping configured productivity-family candidate for "
      .. key .. " recipe=" .. entry.recipe .. " because " .. entry.reason .. ".")
  end

  return eligible_buckets, blocked
end

local function adoption_owner_for(spec)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  if not (adoption and adoption.tech) then return nil, "no_configured_owner" end

  local owner_name = adoption.tech
  local owner = data.raw.technology and data.raw.technology[owner_name]
  if not owner then return nil, "owner_missing" end
  if adoption.require_infinite ~= false and owner.max_level ~= "infinite" then
    return nil, "owner_not_infinite"
  end

  local owner_effects = productivity_owners.recipe_productivity_effects(owner)
  if adoption.require_existing_recipe_productivity_effects ~= false and #owner_effects == 0 then
    return nil, "owner_has_no_recipe_productivity_effects"
  end

  local change_policy = adoption.change_policy or "copy-owner"
  local change = C.shared.per_level_default
  if change_policy == "copy-owner" then
    change = nil
    for _, effect in ipairs(owner_effects) do
      if effect.change == nil then
        return nil, "owner_missing_change_value"
      end
      if change == nil then
        change = effect.change
      elseif effect.change ~= change then
        return nil, "owner_mixed_change_values"
      end
    end
    if change == nil then return nil, "owner_has_no_recipe_productivity_effects" end
  end

  return {
    name = owner_name,
    tech = owner,
    change = change
  }
end

local function record(key, owner_name, recipe_name, change)
  table.insert(adopted_productivity_family_recipes, {
    key = key,
    owner = owner_name,
    recipe = recipe_name,
    change = change
  })
end

function A.adopt(key, spec, buckets)
  local adoption = spec and spec.adopt_into_existing_productivity_tech
  if not adoption then return buckets, {}, {} end

  local eligible_buckets, blocked = partition_candidates(key, spec, buckets)
  local owner, reason = adoption_owner_for(spec)
  if not owner then
    if #eligible_buckets > 0 or #blocked > 0 then
      log("[more-infinite-research] Could not adopt productivity-family recipes for "
        .. key .. " into "
        .. tostring(adoption.tech)
        .. " because "
        .. tostring(reason)
        .. "; falling back to MIR generation for eligible recipes.")
    end
    return eligible_buckets, {}, blocked
  end

  local adopted = {}
  for _, bucket in ipairs(eligible_buckets or {}) do
    for _, recipe_name in ipairs(bucket.recipes or {}) do
      if not productivity_owners.has_recipe_productivity_effect(owner.tech, recipe_name) then
        local effect = {
          type = "change-recipe-productivity",
          recipe = recipe_name,
          change = owner.change
        }
        owner.tech.effects = owner.tech.effects or {}
        table.insert(owner.tech.effects, effect)
        table.insert(adopted, effect)
        record(key, owner.name, recipe_name, owner.change)
        log("[more-infinite-research] Adopted productivity-family recipe for "
          .. key .. " recipe=" .. recipe_name .. " into " .. owner.name .. ".")
      end
    end
  end

  return {}, adopted, blocked, owner.name
end

local function signature()
  local entries = {}
  for _, entry in ipairs(adopted_productivity_family_recipes) do
    table.insert(entries,
      "schema=" .. tostring(VERSION)
      .. "|owner=" .. tostring(entry.owner)
      .. "|recipe=" .. tostring(entry.recipe)
      .. "|change=" .. tostring(entry.change))
  end
  table.sort(entries)
  return table.concat(entries, ";")
end

function A.emit_mod_data()
  local adoption_signature = signature()
  data:extend({
    {
      type = "mod-data",
      name = MOD_DATA_NAME,
      data_type = "more-infinite-research.productivity-family-adoption",
      data = {
        version = VERSION,
        adopted = #adopted_productivity_family_recipes > 0,
        adopted_count = #adopted_productivity_family_recipes,
        signature = adoption_signature
      }
    }
  })
end

return A
