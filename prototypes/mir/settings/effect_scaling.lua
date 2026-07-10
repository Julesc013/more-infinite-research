local deepcopy = require("prototypes.mir.core.deepcopy")
local effective_settings = require("prototypes.mir.settings.effective")

-- Effect scaling is deliberately typed.  Technology-effect tables contain
-- several numeric fields, but only the declared field below is a per-level
-- value that MIR may scale on a technology it emits itself.
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

local function close_to_integer(value)
  return math.abs(value - math.floor(value + 0.5)) < 0.000001
end

local function numeric_effect_descriptor(effect)
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

local function descriptor_from_effects(effects)
  local descriptor = nil
  for _, effect in ipairs(effects or {}) do
    local candidate = numeric_effect_descriptor(effect)
    if not candidate then return nil end
    if candidate.value <= 0 then return nil end
    if descriptor and (descriptor.field ~= candidate.field or descriptor.unit ~= candidate.unit) then
      return nil
    end
    if not descriptor or candidate.value > descriptor.canonical_anchor then
      descriptor = {
        field = candidate.field,
        unit = candidate.unit,
        display_multiplier = candidate.display_multiplier,
        canonical_anchor = candidate.value,
        whole_number = candidate.unit == "native" and close_to_integer(candidate.value)
      }
    end
  end
  return descriptor
end

local function productivity_descriptor(spec)
  local anchor = nil
  for _, group in ipairs((spec and spec.groups) or {}) do
    local change = tonumber(group.change)
    if change and change > 0 and (not anchor or change > anchor) then anchor = change end
  end
  if not anchor then anchor = 0.10 end
  return {
    field = "change",
    unit = "percent",
    display_multiplier = 100,
    canonical_anchor = anchor,
    whole_number = false
  }
end

function M.stream_descriptor(spec)
  if spec and spec.direct_effects then
    return descriptor_from_effects(spec.direct_effects)
  end
  return productivity_descriptor(spec)
end

function M.stream_setting_name(key)
  return "ips-effect-per-level-" .. key
end

function M.base_setting_name(key)
  return "mir-effect-per-level-" .. key
end

local function setting_spec(name, descriptor)
  if not descriptor then return nil end
  local default_value = descriptor.canonical_anchor * descriptor.display_multiplier
  local spec = {
    type = descriptor.whole_number and "int-setting" or "double-setting",
    name = name,
    default_value = descriptor.whole_number and math.floor(default_value + 0.5) or default_value,
    minimum_value = descriptor.whole_number and 1 or 0.01,
    maximum_value = 1000000
  }
  return spec
end

function M.stream_setting_spec(key, stream)
  return setting_spec(M.stream_setting_name(key), M.stream_descriptor(stream))
end

-- Base-chain effects are loaded from the active game's technology prototypes,
-- so the descriptor supplied at emission time is the source of truth.  The
-- catalog defaults record the shipped 2.x/3.x anchors for the settings UI.
local base_default_anchors = {
  ["braking-force"] = { unit = "percent", canonical_anchor = 0.10 },
  ["inserter-capacity-bonus"] = { unit = "native", canonical_anchor = 4, whole_number = true },
  ["laser-shooting-speed"] = { unit = "percent", canonical_anchor = 0.40 },
  ["research-speed"] = { unit = "percent", canonical_anchor = 0.10 },
  ["weapon-shooting-speed"] = { unit = "percent", canonical_anchor = 0.40 },
  ["worker-robots-storage"] = { unit = "native", canonical_anchor = 1, whole_number = true }
}

function M.base_setting_spec(key)
  local descriptor = base_default_anchors[key]
  if not descriptor then return nil end
  local out = deepcopy(descriptor)
  out.field = "modifier"
  out.display_multiplier = out.unit == "percent" and 100 or 1
  return setting_spec(M.base_setting_name(key), out)
end

local function selected_factor(setting_name, descriptor)
  local value = effective_settings.get(setting_name)
  if type(value) ~= "number" then return 1 end
  local selected = value / descriptor.display_multiplier
  if selected <= 0 or descriptor.canonical_anchor <= 0 then return 1 end
  return selected / descriptor.canonical_anchor
end

function M.scale_stream_effects(key, spec, effects)
  local descriptor = M.stream_descriptor(spec)
  if not descriptor then return deepcopy(effects or {}) end
  local factor = selected_factor(M.stream_setting_name(key), descriptor)
  if factor == 1 then return deepcopy(effects or {}) end

  local out = deepcopy(effects or {})
  for _, effect in ipairs(out) do
    local candidate = numeric_effect_descriptor(effect)
    if candidate and candidate.field == descriptor.field and candidate.unit == descriptor.unit then
      effect[descriptor.field] = effect[descriptor.field] * factor
    end
  end
  return out
end

function M.scale_base_effects(key, effects)
  local actual = descriptor_from_effects(effects)
  if not actual then return deepcopy(effects or {}) end

  local setting_name = M.base_setting_name(key)
  local selected = effective_settings.get(setting_name)
  local catalog = base_default_anchors[key]
  -- A default setting must preserve a modded base chain exactly.  Only an
  -- intentional non-default selection is recalculated from that chain's
  -- final, already-repaired effect values.
  local catalog_default = catalog and catalog.canonical_anchor * (catalog.unit == "percent" and 100 or 1)
  if selected == nil or selected == catalog_default then return deepcopy(effects or {}) end

  local factor = selected_factor(setting_name, actual)
  if factor == 1 then return deepcopy(effects or {}) end
  local out = deepcopy(effects or {})
  for _, effect in ipairs(out) do
    local candidate = numeric_effect_descriptor(effect)
    if candidate and candidate.field == actual.field and candidate.unit == actual.unit then
      effect[actual.field] = effect[actual.field] * factor
    end
  end
  return out
end

return M
