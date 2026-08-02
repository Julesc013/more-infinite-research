local deepcopy = require("prototypes.mir.core.deepcopy")
local model = require("prototypes.mir.domain.research_cost.model")

local M = {}

function M.factorio_unit(cost_model, options)
  model.assert_valid(cost_model)
  options = options or {}
  local unit = {
    count_formula = cost_model.count_formula,
    ingredients = deepcopy(options.ingredients or {}),
    time = options.research_time
  }
  if options.prefer_fixed_count and cost_model.derived_kind == "fixed" then
    unit.count = cost_model.base_cost
    unit.count_formula = nil
  end
  return unit
end

function M.summary(cost_model)
  model.assert_valid(cost_model)
  return {
    schema = cost_model.schema,
    formula_abi = cost_model.formula_abi,
    kind = cost_model.derived_kind,
    first_level = cost_model.anchor_level,
    base_cost = cost_model.base_cost,
    linear_increment = cost_model.linear_increment,
    growth_factor = cost_model.growth_factor,
    count_formula = cost_model.count_formula,
    provenance = deepcopy(cost_model.provenance),
    fingerprint = cost_model.fingerprint
  }
end

return M
