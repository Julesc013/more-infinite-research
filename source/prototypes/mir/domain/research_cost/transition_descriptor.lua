local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")
local validation = require("prototypes.mir.domain.research_cost.validation")

local M = {}

M.schema = 1
M.abi = "mir-research-cost-transition-v1"
M.realization = "factorio-research-unit-count-floor-v1"

local kinds = {fixed = true, linear = true, exponential = true, hybrid = true}

local function fail(reason)
  return nil, reason
end

local function semantic_record(descriptor)
  return {
    schema = descriptor.model_schema,
    formula_abi = descriptor.formula_abi,
    anchor_level = descriptor.anchor_level,
    base_cost = descriptor.base_cost,
    linear_increment = descriptor.linear_increment,
    growth_factor = descriptor.growth_factor,
    derived_kind = descriptor.kind,
    count_formula = descriptor.count_formula
  }
end

function M.from_model(model)
  research_cost_model.assert_valid(model)
  return {
    schema = M.schema,
    abi = M.abi,
    realization = M.realization,
    model_schema = model.schema,
    formula_abi = model.formula_abi,
    kind = model.derived_kind,
    anchor_level = model.anchor_level,
    base_cost = model.base_cost,
    linear_increment = model.linear_increment,
    growth_factor = model.growth_factor,
    count_formula = model.count_formula,
    semantic_digest = model.semantic_digest,
    authority_digest = model.authority_digest,
    qualification_digest = model.qualification_digest
  }
end

function M.validate(descriptor)
  if type(descriptor) ~= "table" then return fail("descriptor_required") end
  if descriptor.schema ~= M.schema or descriptor.abi ~= M.abi
      or descriptor.realization ~= M.realization then return fail("descriptor_abi_mismatch") end
  if descriptor.model_schema ~= research_cost_model.schema
      or descriptor.formula_abi ~= research_cost_model.formula_abi then
    return fail("model_abi_mismatch")
  end
  for _, field in ipairs({"anchor_level", "base_cost", "linear_increment", "growth_factor"}) do
    if type(descriptor[field]) ~= "number" then return fail("descriptor_" .. field .. "_invalid") end
  end
  if type(descriptor.count_formula) ~= "string" or #descriptor.count_formula > 256 then
    return fail("descriptor_formula_invalid")
  end
  local parameters, reason = validation.parameters(descriptor)
  if not parameters then return fail(reason) end
  if not kinds[descriptor.kind] then return fail("unknown_cost_kind") end
  local rebuilt
  local ok, rebuild_error = pcall(function()
    rebuilt = research_cost_model.new({
      anchor_level = parameters.anchor_level,
      base_cost = parameters.base_cost,
      linear_increment = parameters.linear_increment,
      growth_factor = parameters.growth_factor,
      provenance = {}
    })
  end)
  if not ok then return fail("descriptor_model_invalid:" .. tostring(rebuild_error)) end
  if rebuilt.derived_kind ~= descriptor.kind or rebuilt.count_formula ~= descriptor.count_formula then
    return fail("descriptor_derived_material_mismatch")
  end
  if fingerprint.of(semantic_record(descriptor)) ~= descriptor.semantic_digest then
    return fail("descriptor_semantic_digest_mismatch")
  end
  local expected_qualification_digest = fingerprint.of(
    research_cost_model.qualification_identity(rebuilt))
  if descriptor.qualification_digest ~= expected_qualification_digest then
    return fail("descriptor_qualification_digest_mismatch")
  end
  for _, field in ipairs({"authority_digest", "qualification_digest"}) do
    if type(descriptor[field]) ~= "string" or not descriptor[field]:match("^mir32%-%x%x%x%x%x%x%x%x$") then
      return fail("descriptor_" .. field .. "_invalid")
    end
  end
  return deepcopy(parameters)
end

function M.evaluate(descriptor, level)
  local parameters, reason = M.validate(descriptor)
  if not parameters then return fail(reason) end
  level, reason = validation.level(level, parameters.anchor_level)
  if not level then return fail(reason) end
  local offset = level - parameters.anchor_level
  local raw = (parameters.base_cost + parameters.linear_increment * offset)
    * (parameters.growth_factor ^ offset)
  local bounded
  bounded, reason = validation.evaluated_cost(raw)
  if not bounded then return fail(reason) end
  local realized = math.floor(bounded)
  if realized < 1 then return fail("realized_cost_out_of_bounds") end
  return realized
end

function M.convert_fraction(before, previous_descriptor, current_descriptor, level)
  if type(before) ~= "number" or before ~= before or before == math.huge or before == -math.huge then
    return fail("invalid_research_fraction")
  end
  local previous_cost, previous_reason = M.evaluate(previous_descriptor, level)
  if not previous_cost then return fail("previous_" .. tostring(previous_reason)) end
  local current_cost, current_reason = M.evaluate(current_descriptor, level)
  if not current_cost then return fail("current_" .. tostring(current_reason)) end
  local converted = before * previous_cost / current_cost
  if converted ~= converted or converted == math.huge or converted == -math.huge then
    return fail("converted_fraction_out_of_bounds")
  end
  return math.max(0, math.min(1, converted)), {
    previous_cost = previous_cost,
    current_cost = current_cost
  }
end

return M
