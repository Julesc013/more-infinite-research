local M = {}

local function compact(value)
  return tostring(value or ""):gsub("%s+", "")
end

local function number_text(value)
  local numeric = assert(tonumber(value), "native-owner cost value must be numeric")
  if numeric == math.floor(numeric) then return tostring(math.floor(numeric)) end
  return tostring(numeric)
end

local function target_formula(contract, formula)
  local compact_formula = compact(formula)
  for _, candidate in ipairs((contract and contract.target_native_formulas) or {}) do
    if compact(candidate) == compact_formula then return true end
  end
  return false
end

function M.classify(unit, contract)
  unit = unit or {}
  local formula = unit.count_formula
  if type(formula) == "string" and formula ~= "" then
    local normalized = compact(formula)
    local growth, base = normalized:match("^([%d%.]+)%^L%*([%d%.]+)$")
    if growth and base then
      return {
        kind = target_formula(contract, formula) and "target-native-exponential" or "recognized-exponential",
        style = "growth-to-level-times-base",
        original_formula = formula,
        base = tonumber(base),
        growth = tonumber(growth)
      }
    end

    base, growth = normalized:match("^([%d%.]+)%*([%d%.]+)%^%(L%-1%)$")
    if base and growth then
      return {
        kind = target_formula(contract, formula) and "target-native-exponential" or "recognized-exponential",
        style = "base-times-growth-to-level-minus-one",
        original_formula = formula,
        base = tonumber(base),
        growth = tonumber(growth)
      }
    end

    return {
      kind = "unrecognized-external-formula",
      style = "preserve-only",
      original_formula = formula
    }
  end

  if type(unit.count) == "number" then
    return {
      kind = "recognized-fixed-count",
      style = "fixed-count",
      original_count = unit.count,
      base = unit.count
    }
  end

  return {
    kind = "missing-cost-model",
    style = "preserve-only"
  }
end

function M.configure(model, overrides)
  overrides = overrides or {}
  local base_changed = overrides.base ~= nil
  local growth_changed = overrides.growth ~= nil
  if not base_changed and not growth_changed then
    return {
      changed = false,
      count = model.original_count,
      count_formula = model.original_formula
    }
  end

  if model.style == "fixed-count" then
    if growth_changed then return nil, "fixed_count_has_no_growth_factor" end
    return {
      changed = true,
      count = overrides.base,
      count_formula = nil
    }
  end

  if model.style ~= "growth-to-level-times-base"
      and model.style ~= "base-times-growth-to-level-minus-one" then
    return nil, "unrecognized_cost_formula"
  end

  local base = overrides.base or model.base
  local growth = overrides.growth or model.growth
  local formula
  if model.style == "growth-to-level-times-base" then
    formula = number_text(growth) .. "^L*" .. number_text(base)
  else
    formula = number_text(base) .. "*" .. number_text(growth) .. "^(L-1)"
  end
  return {
    changed = true,
    count = nil,
    count_formula = formula
  }
end

return M
