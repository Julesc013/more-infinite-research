local research_cost_classification = require("prototypes.mir.domain.research_cost.classification")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")

local M = {}

local function compact(value)
  return tostring(value or ""):gsub("%s+", "")
end

local function target_formula(contract, formula)
  local compact_formula = compact(formula)
  for _, candidate in ipairs((contract and contract.target_native_formulas) or {}) do
    if compact(candidate) == compact_formula then return true end
  end
  return false
end

function M.classify(unit, contract, options)
  unit = unit or {}
  options = options or {}
  local formula = unit.count_formula
  if type(formula) == "string" and formula ~= "" then
    local classified = research_cost_classification.formula(formula, options)
    if classified.recognized then
      local cost = classified.model
      local native = target_formula(contract, formula)
      return {
        kind = native and ("target-native-" .. cost.derived_kind)
          or ("recognized-" .. cost.derived_kind),
        style = classified.style,
        original_formula = formula,
        base = cost.base_cost,
        growth = cost.growth_factor,
        linear_increment = cost.linear_increment,
        anchor_level = cost.anchor_level,
        research_cost_model = cost
      }
    end
    return {
      kind = "unrecognized-external-formula",
      style = "preserve-only",
      original_formula = formula,
      reason = classified.reason
    }
  end

  if type(unit.count) == "number" then
    return {
      kind = "recognized-fixed-count",
      style = "fixed-count",
      original_count = unit.count,
      base = unit.count,
      growth = 1,
      linear_increment = 0,
      anchor_level = research_cost_classification.anchor_level(options.technology_name, options.anchor_level),
      research_cost_model = research_cost_model.new({
        anchor_level = research_cost_classification.anchor_level(options.technology_name, options.anchor_level),
        base_cost = unit.count,
        linear_increment = 0,
        growth_factor = 1,
        provenance = {
          base_cost = "external-fixed-count",
          linear_increment = "external-fixed-count",
          growth_factor = "external-fixed-count",
          anchor_level = "technology-first-level"
        }
      })
    }
  end

  return {kind = "missing-cost-model", style = "preserve-only"}
end

function M.configure(classified, overrides)
  overrides = overrides or {}
  local base_changed = overrides.base ~= nil
  local growth_changed = overrides.growth ~= nil
  local increment_changed = overrides.linear_increment ~= nil
  if not base_changed and not growth_changed and not increment_changed then
    return {
      changed = false,
      count = classified.original_count,
      count_formula = classified.original_formula,
      model = classified.research_cost_model
    }
  end

  if classified.style == "fixed-count" then
    local configured = research_cost_model.with_overrides(classified.research_cost_model, {
      base_cost = overrides.base,
      linear_increment = overrides.linear_increment,
      growth_factor = overrides.growth
    }, {
      base_cost = base_changed and "user-setting" or "external-fixed-count",
      linear_increment = increment_changed and "user-setting" or "external-fixed-count",
      growth_factor = growth_changed and "user-setting" or "external-fixed-count",
      anchor_level = "technology-first-level"
    })
    if configured.derived_kind == "fixed" then
      return {changed = true, count = configured.base_cost, count_formula = nil, model = configured}
    end
    return {changed = true, count = nil, count_formula = configured.count_formula, model = configured}
  end

  if not classified.research_cost_model then return nil, "unrecognized_cost_formula" end

  local configured = research_cost_model.with_overrides(classified.research_cost_model, {
    base_cost = overrides.base,
    linear_increment = overrides.linear_increment,
    growth_factor = overrides.growth
  }, {
    base_cost = base_changed and "user-setting" or "external-formula",
    linear_increment = increment_changed and "user-setting" or "external-formula",
    growth_factor = growth_changed and "user-setting" or "external-formula",
    anchor_level = "technology-first-level"
  })
  return {changed = true, count = nil, count_formula = configured.count_formula, model = configured}
end

return M
