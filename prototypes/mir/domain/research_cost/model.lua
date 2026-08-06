local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local formula = require("prototypes.mir.domain.research_cost.formula")
local validation = require("prototypes.mir.domain.research_cost.validation")

local M = {}

M.schema = 1
M.formula_abi = "mir-research-cost-v1"
M.qualification_abi = "mir-research-cost-qualification-v1"

local function semantic_identity(record)
  return {
    schema = M.schema,
    formula_abi = M.formula_abi,
    anchor_level = record.anchor_level,
    base_cost = record.base_cost,
    linear_increment = record.linear_increment,
    growth_factor = record.growth_factor,
    derived_kind = record.derived_kind,
    count_formula = record.count_formula
  }
end

local function qualification_identity(record)
  local proof = validation.assert_algebraic_proof(record)
  return {
    qualification_abi = M.qualification_abi,
    semantic_digest = record.semantic_digest,
    proof_abi = proof.proof_abi,
    property = proof.property,
    constraints = proof.constraints,
    argument = proof.argument,
    maximum_offset = proof.maximum_offset,
    maximum_exponent = proof.maximum_exponent,
    status = proof.status
  }
end

function M.semantic_identity(record)
  return deepcopy(semantic_identity(record))
end


function M.semantic_digest(record)
  return fingerprint.of(semantic_identity(record))
end

function M.qualification_identity(record)
  return deepcopy(qualification_identity(record))
end

function M.new(record)
  local parameters = validation.assert_parameters(record)
  local safe, reason = validation.is_positive_nondecreasing(parameters)
  if not safe then error("ResearchCostModel safety failed: " .. tostring(reason), 2) end
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
  result.semantic_digest = M.semantic_digest(result)
  result.authority_digest = fingerprint.of({
    semantic_digest = result.semantic_digest,
    provenance = result.provenance
  })
  result.qualification_digest = fingerprint.of(qualification_identity(result))
  -- Compatibility alias for consumers that still name the provenance-bound
  -- authority identity as a generic fingerprint.
  result.fingerprint = result.authority_digest
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
    or rebuilt.semantic_digest ~= record.semantic_digest
    or rebuilt.authority_digest ~= record.authority_digest
    or rebuilt.qualification_digest ~= record.qualification_digest
    or rebuilt.fingerprint ~= record.fingerprint then
    error("ResearchCostModel derived material does not match its parameters.", 2)
  end
  local safe, reason = validation.is_positive_nondecreasing(record)
  if not safe then error("ResearchCostModel safety failed: " .. tostring(reason), 2) end
  return true
end

return M
