local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local formula = require("prototypes.mir.domain.research_cost.formula")
local validation = require("prototypes.mir.domain.research_cost.validation")

local M = {}

M.schema = 1
M.formula_abi = "mir-research-cost-v1"

local function identity(record)
  return {
    schema = M.schema,
    formula_abi = M.formula_abi,
    anchor_level = record.anchor_level,
    base_cost = record.base_cost,
    linear_increment = record.linear_increment,
    growth_factor = record.growth_factor,
    derived_kind = record.derived_kind,
    count_formula = record.count_formula,
    provenance = record.provenance
  }
end

function M.new(record)
  local parameters = validation.assert_parameters(record)
  local result = {
    schema = M.schema,
    formula_abi = M.formula_abi,
    anchor_level = parameters.anchor_level,
    base_cost = parameters.base_cost,
    linear_increment = parameters.linear_increment,
    growth_factor = parameters.growth_factor,
    derived_kind = formula.kind(parameters),
    provenance = deepcopy(record.provenance or {})
  }
  result.count_formula = formula.compile(result)
  result.fingerprint = fingerprint.of(identity(result))
  return result
end

function M.with_overrides(source, overrides, provenance)
  overrides = overrides or {}
  return M.new({
    anchor_level = overrides.anchor_level or source.anchor_level,
    base_cost = overrides.base_cost or source.base_cost,
    linear_increment = overrides.linear_increment == nil
      and source.linear_increment or overrides.linear_increment,
    growth_factor = overrides.growth_factor or source.growth_factor,
    provenance = provenance or source.provenance
  })
end

function M.evaluate(record, level)
  return formula.evaluate(record, level)
end

function M.assert_valid(record)
  if type(record) ~= "table" or record.schema ~= M.schema or record.formula_abi ~= M.formula_abi then
    error("ResearchCostModel schema or formula ABI mismatch.", 2)
  end
  local rebuilt = M.new(record)
  if rebuilt.derived_kind ~= record.derived_kind
    or rebuilt.count_formula ~= record.count_formula
    or rebuilt.fingerprint ~= record.fingerprint then
    error("ResearchCostModel derived material does not match its parameters.", 2)
  end
  local safe, reason = validation.is_positive_nondecreasing(record)
  if not safe then error("ResearchCostModel safety failed: " .. tostring(reason), 2) end
  return true
end

return M
