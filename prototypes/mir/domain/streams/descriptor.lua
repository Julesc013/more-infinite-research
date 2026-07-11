local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

local percentage_effects = {
  ["braking-force"] = true,
  ["character-crafting-speed"] = true,
  ["character-mining-speed"] = true,
  ["character-running-speed"] = true,
  ["gun-speed"] = true,
  ["laboratory-productivity"] = true,
  ["laboratory-speed"] = true,
  ["worker-robot-battery"] = true
}

local whole_number_effects = {
  ["bulk-inserter-capacity-bonus"] = true,
  ["cargo-landing-pad-count"] = true,
  ["character-build-distance"] = true,
  ["character-inventory-slots-bonus"] = true,
  ["character-item-drop-distance"] = true,
  ["character-logistic-trash-slots"] = true,
  ["character-reach-distance"] = true,
  ["character-resource-reach-distance"] = true,
  ["inserter-stack-size-bonus"] = true,
  ["max-cargo-bay-unloading-distance"] = true,
  ["stack-inserter-capacity-bonus"] = true,
  ["worker-robot-storage"] = true
}

local function append_unique(out, seen, value)
  if value ~= nil and not seen[value] then
    seen[value] = true
    table.insert(out, value)
  end
end

local function sorted_unique(values)
  local out = {}
  local seen = {}
  for _, value in ipairs(values or {}) do append_unique(out, seen, value) end
  table.sort(out)
  return out
end

local function numeric_effect(effect)
  if type(effect) ~= "table" then return nil end
  if effect.type == "change-recipe-productivity" and type(effect.change) == "number" then
    return { field = "change", unit = "percent", display_multiplier = 100, value = effect.change }
  end
  if type(effect.modifier) ~= "number" then return nil end
  if percentage_effects[effect.type] then
    return { field = "modifier", unit = "percent", display_multiplier = 100, value = effect.modifier }
  end
  if whole_number_effects[effect.type] then
    return { field = "modifier", unit = "native", display_multiplier = 1, value = effect.modifier }
  end
  return nil
end

local function close_to_integer(value)
  return math.abs(value - math.floor(value + 0.5)) < 0.000001
end

local function explicit_effect(spec)
  local source = spec and spec.effect_per_level
  if type(source) ~= "table" then return nil end
  local anchor = tonumber(source.canonical_anchor)
  if not anchor or anchor <= 0 then
    error("Explicit MIR effect contract requires a positive canonical_anchor.", 3)
  end
  local unit = source.unit == "native" and "native" or "percent"
  return {
    field = source.field or "modifier",
    unit = unit,
    display_multiplier = tonumber(source.display_multiplier) or (unit == "percent" and 100 or 1),
    canonical_anchor = anchor,
    whole_number = source.whole_number == true,
    runtime_multiplier_delta = source.runtime_multiplier_delta == true
  }
end

local function direct_effect_contract(key, spec)
  local explicit = explicit_effect(spec)
  if explicit then return explicit end

  local contract = nil
  for _, effect in ipairs(spec.direct_effects or {}) do
    local candidate = numeric_effect(effect)
    if candidate and candidate.value > 0 then
      if contract and (contract.field ~= candidate.field or contract.unit ~= candidate.unit) then
        error("MIR stream " .. key .. " mixes incompatible numeric effect contracts.", 3)
      end
      if not contract then
        contract = {
          field = candidate.field,
          unit = candidate.unit,
          display_multiplier = candidate.display_multiplier,
          canonical_anchor = candidate.value
        }
      elseif candidate.value > contract.canonical_anchor then
        contract.canonical_anchor = candidate.value
      end
    end
  end
  if not contract then
    error("MIR direct-effect stream " .. key .. " has no typed positive effect contract.", 3)
  end
  contract.whole_number = contract.unit == "native" and close_to_integer(contract.canonical_anchor)
  contract.runtime_multiplier_delta = false
  return contract
end

local function productivity_effect_contract(spec)
  local explicit = explicit_effect(spec)
  if explicit then return explicit end

  local anchor = nil
  for _, group in ipairs(spec.groups or {}) do
    local change = tonumber(group.change)
    if change and change > 0 and (not anchor or change > anchor) then anchor = change end
  end
  anchor = anchor or 0.10
  return {
    field = "change",
    unit = "percent",
    display_multiplier = 100,
    canonical_anchor = anchor,
    whole_number = false,
    runtime_multiplier_delta = false
  }
end

local function target_requirements(spec, kind, effect)
  local features = {}
  if kind == "recipe-productivity" then table.insert(features, "recipe_productivity") end
  if effect.runtime_multiplier_delta then table.insert(features, "scripted_techs") end
  for _, feature in ipairs(spec.requires_features or {}) do table.insert(features, feature) end

  local effect_types = {}
  for _, row in ipairs(spec.direct_effects or {}) do
    if row.type and row.type ~= "nothing" then table.insert(effect_types, row.type) end
  end

  return {
    requires_features = sorted_unique(features),
    required_mods = sorted_unique(spec.required_mods),
    required_items = sorted_unique(spec.required_items),
    required_fluids = sorted_unique(spec.required_fluids),
    required_technologies = sorted_unique(spec.required_technologies),
    required_effect_types = sorted_unique(effect_types)
  }
end

function M.normalize(key, raw_spec)
  if type(key) ~= "string" or key == "" then error("MIR stream descriptor requires a stable id.", 2) end
  if type(raw_spec) ~= "table" then error("MIR stream " .. key .. " must be a table.", 2) end
  if raw_spec.descriptor ~= nil then
    error("Raw MIR stream " .. key .. " must not inject a canonical descriptor through an overlay.", 2)
  end

  local spec = deepcopy(raw_spec)
  local kind = spec.direct_effects and "direct-effect" or "recipe-productivity"
  local effect = kind == "direct-effect"
    and direct_effect_contract(key, spec)
    or productivity_effect_contract(spec)
  spec.descriptor = {
    schema = 1,
    id = key,
    kind = kind,
    effect = effect,
    targets = target_requirements(spec, kind, effect)
  }
  return spec
end

function M.clone(spec)
  return deepcopy(spec)
end

return M
