-- Exact private identities for the two K2 Imersite state carriers.
-- They are neither a stream category nor a research admission rule.  Their
-- cost/time descriptor is supplied by the ordinary Imersite cost authority at
-- planning time, so unchanged custom startup settings retain the source unit.
-- The native mechanism proves Formula/time compatibility is required for
-- fractional progress; ingredient selection is deliberately separate because
-- a historical pack can be unavailable in a later valid profile.
local M = {
  stage_kind = "migration-state-alias",
  registry_kind = "migration_state_alias",
  reason = "hidden_migration_state_alias",
  migration_policy = "retain-hidden-alias",
  legacy_technology = "recipe-prod-research_material_imersite-1",
  continuation_technology = "recipe-prod-research_material_imersite-4",
  powder_recipe = "kr-imersite-powder",
  predecessor_version = "4.6.21000",
  stream_key = "research_material_imersite"
}

M.early = {
  stream_key = "__migration_state/k2_imersite_staged_v1",
  manifest_id = "mir-k2-imersite-staged-state-1",
  technology_name = "mir-k2-imersite-staged-state-1",
  source_technology = M.legacy_technology,
  source_kind = "released-infinite-legacy",
  cost_source = "normal-imersite-stream"
}

M.continuation = {
  stream_key = "__migration_state/k2_imersite_continuation_v1",
  manifest_id = "mir-k2-imersite-continuation-state-4",
  technology_name = "mir-k2-imersite-continuation-state-4",
  source_technology = M.continuation_technology,
  source_kind = "released-staged-continuation",
  cost_source = "normal-imersite-continuation"
}

M.holders = {M.early, M.continuation}
M.technology_name = M.early.technology_name -- compatibility with first-holder callers

local function ingredient_name(ingredient)
  return ingredient and (ingredient.name or ingredient[1])
end

local function ingredient_amount(ingredient)
  return ingredient and (ingredient.amount or ingredient[2])
end

local function same_ingredients(expected_ingredients, actual_ingredients)
  local expected, actual = {}, {}
  for _, ingredient in ipairs(expected_ingredients or {}) do
    local name, amount = ingredient_name(ingredient), ingredient_amount(ingredient)
    if not name or expected[name] ~= nil then return false end
    expected[name] = amount
  end
  for _, ingredient in ipairs(actual_ingredients or {}) do
    local name, amount = ingredient_name(ingredient), ingredient_amount(ingredient)
    if not name or actual[name] ~= nil then return false end
    actual[name] = amount
  end
  for name, amount in pairs(expected) do
    if actual[name] ~= amount then return false end
    actual[name] = nil
  end
  return next(actual) == nil
end

-- The normal stream planner supplies this descriptor from the same configured
-- cost/time authority as the visible Imersite stream.  It is the pre-emission
-- check that prevents a holder from drifting to a fixed default formula.
function M.matches_planned_unit(expected, fields)
  if type(expected) ~= "table" or type(fields) ~= "table" then return false end
  return expected.count_formula == fields.count_formula
    and expected.count == fields.count
    and expected.research_time == fields.research_time
    and same_ingredients(expected.ingredients, fields.ingredients)
end

-- Runtime cannot reconstruct a predecessor prototype after JSON has renamed
-- it.  It therefore checks carrier shape only; exact cost/time are validated
-- by the normal design/executor path before Factorio receives the prototype.
function M.matches_runtime_carrier_shape(holder, technology)
  if type(holder) ~= "table" or not technology then return false end
  if type(technology.research_unit_energy) ~= "number" or technology.research_unit_energy <= 0 then
    return false
  end
  if technology.research_unit_count == nil and technology.research_unit_count_formula == nil then
    return false
  end
  local seen, count = {}, 0
  for _, ingredient in pairs(technology.research_unit_ingredients or {}) do
    local name, amount = ingredient_name(ingredient), ingredient_amount(ingredient)
    if not name or type(amount) ~= "number" or amount <= 0 or seen[name] then return false end
    seen[name] = true
    count = count + 1
  end
  return count > 0
end

function M.holder_for_technology(technology_name)
  for _, holder in ipairs(M.holders) do
    if holder.technology_name == technology_name then return holder end
  end
  return nil
end

function M.is_row(row)
  local holder = type(row) == "table" and M.holder_for_technology(row.technology_name) or nil
  return holder ~= nil and row.action == "emit"
    and row.stream_key == holder.stream_key and row.manifest_id == holder.manifest_id
    and row.stage_kind == M.stage_kind and row.reason == M.reason and type(row.spec) == "table"
    and row.spec.migration_policy == M.migration_policy
end

function M.is_operation(operation)
  local holder = type(operation) == "table" and M.holder_for_technology(operation.technology_name) or nil
  return holder ~= nil and operation.operation == "emit_stream"
    and operation.stream_key == holder.stream_key and operation.manifest_id == holder.manifest_id
    and operation.stage_kind == M.stage_kind
    and operation.registry and operation.registry.kind == M.registry_kind
end

return M
