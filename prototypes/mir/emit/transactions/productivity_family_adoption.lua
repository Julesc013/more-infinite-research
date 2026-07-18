local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local mod_data = require("prototypes.mir.emit.mod_data")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}
local MOD_DATA_NAME = "more-infinite-research-productivity-family-adoption"
local VERSION = 2
local function state()
  return compiler_context.current():state_view("productivity_family_adoption", function()
    return {bindings = {}, adopted_recipes = {}}
  end)
end

local function same(left, right)
  return tostring(left or "") == tostring(right or "")
end

local function record(plan)
  local bindings = state().bindings
  local adopted_productivity_family_recipes = state().adopted_recipes
  table.insert(bindings, {
    key = plan.key,
    owner = plan.owner,
    operation = plan.operation,
    configured_fields = deepcopy(plan.configured_fields or {}),
    input_unit = deepcopy((plan.input_snapshot and plan.input_snapshot.unit) or {}),
    output_unit = deepcopy((plan.expected_snapshot and plan.expected_snapshot.unit) or {}),
    input_fingerprint = plan.input_fingerprint,
    output_fingerprint = plan.output_fingerprint,
    effect_count = #(plan.effects or {})
  })
  for _, effect in ipairs(plan.effects or {}) do
    table.insert(adopted_productivity_family_recipes, {
      key = plan.key,
      owner = plan.owner,
      recipe = effect.recipe,
      change = effect.change
    })
  end
end

function M.apply(plan)
  if not plan then return {} end
  local owner = data_raw.technology(plan.owner)
  if not owner then
    error("Planned native-owner binding target disappeared: " .. tostring(plan.owner), 2)
  end

  local current = native_owner_contract.snapshot(owner)
  local current_fingerprint = native_owner_contract.fingerprint(current)
  if not same(current_fingerprint, plan.input_fingerprint) then
    error("Native-owner binding input changed after planning for " .. tostring(plan.owner)
      .. " expected=" .. tostring(plan.input_fingerprint)
      .. " actual=" .. tostring(current_fingerprint), 2)
  end
  if not same(native_owner_contract.fingerprint(plan.expected_snapshot), plan.output_fingerprint) then
    error("Native-owner binding output fingerprint is invalid for " .. tostring(plan.owner), 2)
  end

  if current_fingerprint ~= plan.output_fingerprint then
    -- Every fallible check happens above. These assignments are the single
    -- emission transaction for the already-validated owner snapshot.
    local staged = deepcopy(plan.expected_snapshot)
    owner.unit = staged.unit
    owner.max_level = staged.max_level
    owner.effects = staged.effects
  end

  local actual_fingerprint = native_owner_contract.fingerprint(native_owner_contract.snapshot(owner))
  if not same(actual_fingerprint, plan.output_fingerprint) then
    error("Native-owner binding transaction produced an unexpected output for " .. tostring(plan.owner)
      .. " expected=" .. tostring(plan.output_fingerprint)
      .. " actual=" .. tostring(actual_fingerprint), 2)
  end

  record(plan)
  log("[more-infinite-research] Applied native-owner binding for " .. tostring(plan.key)
    .. " owner=" .. tostring(plan.owner)
    .. " operation=" .. tostring(plan.operation)
    .. " configured=" .. table.concat(plan.configured_fields or {}, ",")
    .. " adopted-effects=" .. tostring(#(plan.effects or {})) .. ".")
  return deepcopy(plan.effects or {})
end

local function signature()
  local entries = {}
  for _, entry in ipairs(state().bindings) do
    table.insert(entries,
      "schema=" .. tostring(VERSION)
      .. "|stream=" .. tostring(entry.key)
      .. "|owner=" .. tostring(entry.owner)
      .. "|operation=" .. tostring(entry.operation)
      .. "|configured=" .. table.concat(entry.configured_fields or {}, ",")
      .. "|effects=" .. tostring(entry.effect_count)
      .. "|output=" .. tostring(entry.output_fingerprint))
  end
  table.sort(entries)
  return table.concat(entries, ";")
end

function M.emit_mod_data()
  local bindings = state().bindings
  local adopted_productivity_family_recipes = state().adopted_recipes
  mod_data.emit_productivity_family_adoption({
    name = MOD_DATA_NAME,
    data_type = "more-infinite-research.productivity-family-adoption",
    data = {
      version = VERSION,
      adopted = #adopted_productivity_family_recipes > 0,
      adopted_count = #adopted_productivity_family_recipes,
      binding_count = #bindings,
      bindings = deepcopy(bindings),
      signature = signature()
    }
  })
end

function M.snapshot()
  local bindings = state().bindings
  local adopted_productivity_family_recipes = state().adopted_recipes
  return deepcopy({
    version = VERSION,
    bindings = bindings,
    adopted_recipes = adopted_productivity_family_recipes
  })
end

return M
