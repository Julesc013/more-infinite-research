local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_risk_facts = require("prototypes.mir.index.recipe_risk_facts")

local M = {}
local SCHEMA = 1

local ALLOWED = {
  selectors = {
    ["recipe.visible"] = true,
    ["recipe.parameter-absent"] = true,
    ["recipe.productivity-eligible"] = true,
    ["output.deterministic-single-placeable"] = true,
    ["output.place-result"] = true,
    ["output.prototype-type"] = true,
    ["risk.none"] = true
  },
  normalizers = {["candidate.recipe-item-entity"] = true},
  partitioner = {["partition.single"] = true},
  tier_resolver = {["tier.structural-single"] = true, ["tier.item-prototype"] = true},
  effect_model = {["effect.fixed"] = true, ["effect.tier-table"] = true},
  science_model = {["science.inherit-target-stream"] = true},
  prerequisite_model = {["prerequisite.inherit-target-stream"] = true},
  cost_model = {["cost.inherit-target-stream"] = true},
  presentation_model = {["presentation.inherit-target-stream"] = true},
  ownership_policy = {["ownership.prefer-existing-exact-owner"] = true},
  grouping = {["group.attach-existing"] = true, ["group.proposal-only"] = true}
}

local function assert_data_only(value, path)
  if type(value) == "function" then error("Family operator DSL must be data-only: " .. path, 3) end
  if type(value) ~= "table" then return end
  for key, child in pairs(value) do assert_data_only(child, path .. "." .. tostring(key)) end
end

local function validate_operator(category, descriptor)
  if type(descriptor) ~= "table" or type(descriptor.operator) ~= "string"
    or not ALLOWED[category][descriptor.operator] then
    error("Family operator DSL contains unsupported " .. category .. " operator: "
      .. tostring(descriptor and descriptor.operator), 3)
  end
end

function M.schema_authority()
  local operators = {}
  for category, values in pairs(ALLOWED) do
    operators[category] = {}
    for name, _ in pairs(values) do table.insert(operators[category], name) end
    table.sort(operators[category])
  end
  return {schema = SCHEMA, operators = operators}
end

function M.validate(dsl)
  if type(dsl) ~= "table" or dsl.schema ~= SCHEMA then
    error("Family operator DSL schema 1 record is required.", 2)
  end
  assert_data_only(dsl, "operators")
  if type(dsl.selectors) ~= "table" or #dsl.selectors == 0 then
    error("Family operator DSL selectors are required.", 2)
  end
  for _, descriptor in ipairs(dsl.selectors) do validate_operator("selectors", descriptor) end
  if type(dsl.normalizers) ~= "table" or #dsl.normalizers == 0 then
    error("Family operator DSL normalizers are required.", 2)
  end
  for _, descriptor in ipairs(dsl.normalizers) do validate_operator("normalizers", descriptor) end
  for _, category in ipairs({
    "partitioner", "tier_resolver", "effect_model", "science_model", "prerequisite_model",
    "cost_model", "presentation_model", "ownership_policy", "grouping"
  }) do
    validate_operator(category, dsl[category])
  end
  if dsl.grouping.operator == "group.attach-existing"
    and (type(dsl.grouping.stream) ~= "string" or dsl.grouping.stream == "") then
    error("Family operator attach-existing grouping requires a stream.", 2)
  end
  if dsl.effect_model.operator == "effect.fixed" and type(dsl.effect_model.change) ~= "number" then
    error("Family operator fixed effect requires a numeric change.", 2)
  end
  if dsl.effect_model.operator == "effect.tier-table"
    and (type(dsl.effect_model.tiers) ~= "table" or type(dsl.effect_model.default) ~= "number") then
    error("Family operator tier-table effect is invalid.", 2)
  end
  return deepcopy(dsl)
end

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
      or not is_zero_or_nil(result.ignored_by_productivity) then
      return false, "non_deterministic_placeable_output"
    end
  end
  return true, nil
end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do if value == expected then return true end end
  return false
end

function M.candidate_items(dsl, indexes)
  if type(dsl) ~= "table" or dsl.schema ~= SCHEMA then error("Family operator DSL schema 1 record is required.", 2) end
  local items, seen = {}, {}
  for _, selector in ipairs(dsl.selectors) do
    if selector.operator == "output.place-result" then
      for _, entity_type in ipairs(selector.entity_types or {}) do
        for _, entity_name in ipairs(indexes.entities_by_type[entity_type] or {}) do
          for _, item_name in ipairs(indexes.items_by_place_result[entity_name] or {}) do
            if not seen[item_name] then seen[item_name] = true; table.insert(items, item_name) end
          end
        end
      end
    elseif selector.operator == "output.prototype-type" and selector.prototype_type == "module" then
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

function M.eligibility(dsl, fact, item_name, risk_fact)
  if type(dsl) ~= "table" or dsl.schema ~= SCHEMA then error("Family operator DSL schema 1 record is required.", 2) end
  if not fact then return false, "recipe_fact_missing" end
  for _, selector in ipairs(dsl.selectors) do
    if selector.operator == "recipe.visible" and fact.hidden then
      return false, "hidden_recipe"
    elseif selector.operator == "recipe.parameter-absent" and fact.parameter then
      return false, "parameter_recipe"
    elseif selector.operator == "recipe.productivity-eligible" then
      if fact.effective_allow_productivity ~= true then return false, "recipe_productivity_not_allowed" end
      if tonumber(fact.maximum_productivity) == 0 then return false, "zero_productivity_cap" end
    elseif selector.operator == "output.deterministic-single-placeable" then
      local safe, blocker = safe_placeable_output(fact, item_name)
      if not safe then return false, blocker end
    elseif selector.operator == "risk.none" then
      local disposition, blocker = recipe_risk_facts.primary_disposition(risk_fact)
      if disposition ~= "PASS" then return false, blocker, disposition end
    end
  end
  return true, nil, "PASS"
end

local function item_tier(indexes, item_name)
  for tier, names in pairs(indexes.modules_by_tier or {}) do
    for _, name in ipairs(names) do if name == item_name then return tier end end
  end
  return nil
end

function M.effect_change(dsl, candidate, indexes)
  if type(dsl) ~= "table" or dsl.schema ~= SCHEMA then error("Family operator DSL schema 1 record is required.", 2) end
  local model = dsl.effect_model
  if model.operator == "effect.fixed" then return candidate.change or model.change end
  local tier = candidate.tier or item_tier(indexes, candidate.item)
  tier = tonumber(tier) or 0
  local values = model.tiers or {}
  return candidate.change or values[tier]
    or (tier > #values and model.high_tier)
    or model.default
end

function M.grouping_action(dsl)
  if type(dsl) ~= "table" or dsl.schema ~= SCHEMA then error("Family operator DSL schema 1 record is required.", 2) end
  return dsl.grouping.operator == "group.proposal-only" and "propose" or "attach"
end

function M.grouping_stream(dsl)
  if type(dsl) ~= "table" or dsl.schema ~= SCHEMA then error("Family operator DSL schema 1 record is required.", 2) end
  return dsl.grouping.stream
end

return M
