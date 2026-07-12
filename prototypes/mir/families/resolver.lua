local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local relationships = require("prototypes.mir.index.relationships")
local rule_registry = require("prototypes.mir.families.registry")
local compatibility_packs = require("prototypes.mir.compatibility.packs.registry")

local M = {}
local canonical = nil

local function sorted_keys(tbl)
  local out = {}
  for key, _ in pairs(tbl or {}) do table.insert(out, key) end
  table.sort(out)
  return out
end

local function has_self_return(fact)
  local ingredients = {}
  for _, entry in ipairs(fact.ingredients or {}) do ingredients[entry.name] = true end
  for _, entry in ipairs(fact.results or {}) do
    if ingredients[entry.name] then return true end
  end
  return false
end

local function is_zero_or_nil(value)
  return value == nil or tonumber(value) == 0
end

local function safe_placeable_output(fact, item_name)
  for _, variant in ipairs(fact.variants or {}) do
    if variant.effective_allow_productivity ~= true then return false, "variant_productivity_not_allowed" end
    if tonumber(variant.maximum_productivity) == 0 then return false, "variant_zero_productivity_cap" end
    if #(variant.results or {}) ~= 1 then return false, "non_exclusive_placeable_output" end
    local result = variant.results[1]
    if result.type ~= "item" or result.name ~= item_name then
      return false, "non_exclusive_placeable_output"
    end
    if tonumber(result.independent_probability or result.probability or 1) ~= 1
      or result.shared_probability ~= nil
      or tonumber(result.extra_count_fraction or 0) ~= 0
      or result.amount_min ~= nil
      or result.amount_max ~= nil
      or not is_zero_or_nil(result.catalyst_amount)
      or not is_zero_or_nil(result.ignored_by_productivity)
    then
      return false, "non_deterministic_placeable_output"
    end
  end
  return true, nil
end

local function risk_denied(rule, risk)
  for _, candidate in ipairs(rule.deny_risks or {}) do
    if candidate == risk then return true end
  end
  return false
end

local function eligibility(rule, fact, item_name)
  if not fact then return false, "recipe_fact_missing" end
  if rule.require.visible_recipe and fact.hidden and risk_denied(rule, "hidden_internal") then
    return false, "hidden_recipe"
  end
  if rule.require.parameter == false and fact.parameter then return false, "parameter_recipe" end
  if fact.source_class == "recycling" and risk_denied(rule, "recycling_loop") then
    return false, "recycling_recipe"
  end
  if rule.require.productivity_supported and fact.effective_allow_productivity ~= true then
    return false, "recipe_productivity_not_allowed"
  end
  if tonumber(fact.maximum_productivity) == 0 then return false, "zero_productivity_cap" end
  if has_self_return(fact) and risk_denied(rule, "catalyst_or_self_return") then
    return false, "self_return_risk"
  end
  if rule.require.output_placeable then
    local output_safe, output_blocker = safe_placeable_output(fact, item_name)
    if not output_safe and risk_denied(rule, "non_deterministic_output") then
      return false, output_blocker
    end
  end
  return true, nil
end

local function module_change(rule, tier)
  tier = tonumber(tier) or 0
  local values = rule.effects.tiers or {}
  return values[tier]
    or (tier > #values and rule.effects.high_tier)
    or rule.effects.default
end

local function candidate_items(rule, indexes)
  local items = {}
  local seen = {}
  local selector = rule.selector.output_item
  for _, entity_type in ipairs(selector.place_result_entity_types or {}) do
    for _, entity_name in ipairs(indexes.entities_by_type[entity_type] or {}) do
      for _, item_name in ipairs(indexes.items_by_place_result[entity_name] or {}) do
        if not seen[item_name] then seen[item_name] = true; table.insert(items, item_name) end
      end
    end
  end
  for _, prototype_type in ipairs(selector.prototype_types or {}) do
    if prototype_type == "module" then
      for _, tier in ipairs(sorted_keys(indexes.modules_by_tier)) do
        for _, item_name in ipairs(indexes.modules_by_tier[tier]) do
          if not seen[item_name] then seen[item_name] = true; table.insert(items, item_name) end
        end
      end
    end
  end
  table.sort(items)
  return items
end

local function build()
  if canonical then return canonical end
  local indexes = relationships.snapshot()
  local rules = rule_registry.snapshot().rules
  local attachments, decisions, ownership = {}, {}, {}

  for _, rule in ipairs(rules) do
    for _, item_name in ipairs(candidate_items(rule, indexes)) do
      for _, recipe_name in ipairs(indexes.recipes_by_output[item_name] or {}) do
        local fact = recipe_facts.get(recipe_name)
        local eligible, blocker = eligibility(rule, fact, item_name)
        local pack_decision = compatibility_packs.resolve_candidate({
          recipe = recipe_name,
          item = item_name,
          family = rule.id,
          stream = rule.grouping.stream,
          blocker = blocker
        })
        if pack_decision.action == "attach" then
          eligible, blocker = true, nil
        elseif pack_decision.action == "diagnose" then
          eligible, blocker = false, pack_decision.reason or blocker
        end
        local external_owners = indexes.technologies_by_recipe_effect[recipe_name] or {}
        if #external_owners > 0 then eligible, blocker = false, "existing_recipe_productivity_owner" end

        local change = rule.effects.default
        if rule.effects.strategy == "tier-table" then
          local item = indexes.items[item_name]
          local tier = nil
          for candidate_tier, names in pairs(indexes.modules_by_tier) do
            for _, name in ipairs(names) do if name == item_name then tier = candidate_tier end end
          end
          change = module_change(rule, tier)
        end
        if tonumber(pack_decision.change) then change = tonumber(pack_decision.change) end

        local decision = rule.grouping.strategy == "proposal-only" and "propose" or "attach"
        if not eligible then decision = "diagnose" end
        table.insert(decisions, {
          schema = 2,
          rule = rule.id,
          capability = rule.capability,
          recipe = recipe_name,
          item = item_name,
          target_stream = rule.grouping.stream,
          decision = decision,
          blocker = blocker or rule.blocker,
          change = change
        })

        if eligible and rule.grouping.strategy == "attach-existing" then
          local previous = ownership[recipe_name]
          if previous and previous ~= rule.grouping.stream then
            error("FamilyRule attachment is ambiguous for recipe " .. recipe_name, 2)
          end
          ownership[recipe_name] = rule.grouping.stream
          attachments[rule.grouping.stream] = attachments[rule.grouping.stream] or {}
          table.insert(attachments[rule.grouping.stream], {
            recipe = recipe_name,
            change = change,
            rule = rule.id
          })
        end
      end
    end
  end

  for _, rows in pairs(attachments) do
    table.sort(rows, function(a, b)
      if a.change ~= b.change then return a.change > b.change end
      return a.recipe < b.recipe
    end)
  end
  table.sort(decisions, function(a, b)
    if a.rule ~= b.rule then return a.rule < b.rule end
    return a.recipe < b.recipe
  end)
  canonical = {schema = 2, attachments = attachments, decisions = decisions}
  return canonical
end

function M.attachments_for_stream(stream_key)
  return deepcopy(build().attachments[stream_key] or {})
end

function M.snapshot()
  return deepcopy(build())
end

return M
