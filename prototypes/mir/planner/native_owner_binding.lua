local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local productivity_owners = require("prototypes.mir.index.productivity_owners")
local effective_settings = require("prototypes.mir.settings.effective")
local settings_catalog = require("prototypes.mir.settings.catalog")
local effect_contracts = require("prototypes.mir.settings.effect_contracts")
local cost_model = require("prototypes.mir.domain.native_owner.cost_model")
local contract = require("prototypes.mir.domain.native_owner.contract")

local M = {}

local function selected(name)
  local value = effective_settings.get(name)
  return {
    name = name,
    value = value,
    changed = value ~= nil and not settings_catalog.is_default_value(name, value)
  }
end

local function sorted_keys(values)
  local out = {}
  for key, enabled in pairs(values or {}) do if enabled then table.insert(out, key) end end
  table.sort(out)
  return out
end

local function relevant_effects(owner, binding)
  local effects = {}
  for _, effect in ipairs(productivity_owners.recipe_productivity_effects(owner)) do
    if productivity_owners.recipe_outputs_any_product(effect.recipe, binding.effect_scope.products) then
      table.insert(effects, effect)
    end
  end
  return effects
end

local function common_change(effects)
  local value = nil
  for _, effect in ipairs(effects or {}) do
    if type(effect.change) ~= "number" then return nil, "owner_missing_change_value" end
    if value == nil then value = effect.change
    elseif value ~= effect.change then return nil, "owner_mixed_change_values" end
  end
  if value == nil then return nil, "owner_has_no_relevant_recipe_productivity_effects" end
  return value
end

local function owner_is_reachable(owner)
  if type(owner.unit) ~= "table" or type(owner.unit.ingredients) ~= "table" or #owner.unit.ingredients == 0 then
    return false, "owner_has_no_science_ingredients"
  end
  for _, prerequisite in ipairs(owner.prerequisites or {}) do
    if not data_raw.technology(prerequisite) then return false, "owner_prerequisite_missing" end
  end
  return true
end

local function adopted_recipes(owner, buckets)
  local out = {}
  for _, bucket in ipairs(buckets or {}) do
    for _, recipe in ipairs(bucket.recipes or {}) do
      if not productivity_owners.has_recipe_productivity_effect(owner, recipe) then
        table.insert(out, recipe)
      end
    end
  end
  table.sort(out)
  return out
end

local function fallback_buckets(owner, buckets)
  local out = {}
  for _, bucket in ipairs(buckets or {}) do
    local target = {change = bucket.change, recipes = {}}
    for _, recipe in ipairs(bucket.recipes or {}) do
      if not productivity_owners.has_recipe_productivity_effect(owner, recipe) then
        table.insert(target.recipes, recipe)
      end
    end
    if #target.recipes > 0 then table.insert(out, target) end
  end
  return out
end

local function build_plan(key, spec, owner, binding, buckets)
  local relevant = relevant_effects(owner, binding)
  if binding.eligibility.require_existing_recipe_productivity_effects ~= false and #relevant == 0 then
    return nil, "owner_has_no_relevant_recipe_productivity_effects"
  end

  local reachable, reachability_reason = owner_is_reachable(owner)
  if not reachable then return nil, reachability_reason end

  local base = selected("ips-cost-base-" .. key)
  local growth = selected("ips-cost-growth-" .. key)
  local max_level = selected("ips-max-level-" .. key)
  local research_time = selected("ips-research-time-" .. key)
  local effect_value = selected(effect_contracts.stream_setting_name(key))

  local model = cost_model.classify(owner.unit, binding.cost_model)
  local configured_cost, cost_reason = cost_model.configure(model, {
    base = base.changed and base.value or nil,
    growth = growth.changed and growth.value or nil
  })
  if not configured_cost then return nil, cost_reason end

  local recipes = adopted_recipes(owner, buckets)
  local new_change
  if effect_value.changed then
    local descriptor = effect_contracts.stream_descriptor(spec)
    new_change = effect_value.value / descriptor.display_multiplier
  elseif #recipes > 0 then
    local reason
    new_change, reason = common_change(relevant)
    if not new_change then return nil, reason end
  end

  local input = contract.snapshot(owner)
  local expected = deepcopy(input)
  local configured = {}

  if configured_cost.changed then
    expected.unit.count = configured_cost.count
    expected.unit.count_formula = configured_cost.count_formula
    configured.cost_model = true
  end
  if research_time.changed and research_time.value > 0 then
    expected.unit.time = research_time.value
    configured.research_time = true
  end
  if max_level.changed then
    expected.max_level = max_level.value <= 0 and "infinite" or math.floor(max_level.value)
    configured.max_level = true
  end

  local relevant_recipe_set = {}
  for _, effect in ipairs(relevant) do relevant_recipe_set[effect.recipe] = true end
  if effect_value.changed then
    for _, effect in ipairs(expected.effects or {}) do
      if effect.type == "change-recipe-productivity" and relevant_recipe_set[effect.recipe] then
        effect.change = new_change
      end
    end
    configured.effect_per_level = true
  end

  local effects = {}
  for _, recipe in ipairs(recipes) do
    local effect = {type = "change-recipe-productivity", recipe = recipe, change = new_change}
    table.insert(effects, effect)
    table.insert(expected.effects, deepcopy(effect))
  end

  local configured_fields = sorted_keys(configured)
  local operation
  if #configured_fields > 0 and #effects > 0 then operation = "configure_and_adopt_native_owner"
  elseif #configured_fields > 0 then operation = "configure_native_owner"
  elseif #effects > 0 then operation = "adopt_native_owner_effects"
  else operation = "preserve_native_owner" end

  return {
    schema = 2,
    key = key,
    owner = owner.name,
    operation = operation,
    configured_fields = configured_fields,
    cost_model = model,
    effects = effects,
    relevant_recipes = (function()
      local out = {}
      for recipe in pairs(relevant_recipe_set) do table.insert(out, recipe) end
      table.sort(out)
      return out
    end)(),
    input_snapshot = input,
    expected_snapshot = expected,
    input_fingerprint = contract.fingerprint(input),
    output_fingerprint = contract.fingerprint(expected)
  }
end

function M.plan(key, spec, buckets)
  local binding = spec and spec.native_owner_binding
  if not binding then return buckets, {}, {}, nil, nil end
  if not binding.effect_scope or binding.effect_scope.type ~= "change-recipe-productivity"
      or type(binding.effect_scope.products) ~= "table" or #binding.effect_scope.products == 0 then
    error("Native-owner binding is missing a recipe-productivity effect scope for " .. tostring(key), 2)
  end

  local eligible, blocked = {}, {}
  for _, bucket in ipairs(buckets or {}) do
    local target = {change = bucket.change, recipes = {}}
    for _, recipe in ipairs(bucket.recipes or {}) do
      local reason
      if not productivity_owners.recipe_allows_productivity(recipe) then
        reason = "recipe_productivity_not_allowed"
      elseif not productivity_owners.recipe_outputs_any_product(recipe, binding.effect_scope.products) then
        reason = "recipe_not_in_native_owner_effect_scope"
      end
      if reason then table.insert(blocked, {recipe = recipe, reason = reason})
      else table.insert(target.recipes, recipe) end
    end
    if #target.recipes > 0 then table.insert(eligible, target) end
  end

  for _, row in ipairs(blocked) do
    log("[more-infinite-research] Skipping native-owner candidate for " .. key
      .. " recipe=" .. row.recipe .. " because " .. row.reason .. ".")
  end

  local owner = data_raw.technology(binding.owner)
  if not owner then return eligible, {}, blocked, nil, nil, "owner_missing" end
  local eligibility = binding.eligibility or {}
  if eligibility.require_infinite ~= false and owner.max_level ~= "infinite" then
    return eligible, {}, blocked, nil, nil, "owner_not_infinite"
  end

  local plan, reason = build_plan(key, spec, owner, binding, eligible)
  if not plan then
    log("[more-infinite-research] Native-owner binding for " .. key .. " owner=" .. binding.owner
      .. " was rejected because " .. tostring(reason) .. "; eligible recipes fall back to MIR generation.")
    table.insert(blocked, {owner = owner.name, reason = reason})
    return fallback_buckets(owner, eligible), {}, blocked, nil, nil, reason
  end

  return {}, deepcopy(plan.effects), blocked, owner.name, plan, nil
end

return M
