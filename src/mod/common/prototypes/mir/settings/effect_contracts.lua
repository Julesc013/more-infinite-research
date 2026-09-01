local deepcopy = require("prototypes.mir.core.deepcopy")
local effect_metadata = require("prototypes.mir.domain.effects.metadata")

-- Pure setting/effect descriptors shared by the settings stage and emitters.
-- This module must not read Factorio settings: catalog/profile loading depends
-- on it before effective startup settings can safely be resolved.
local M = {}

local identity_fields = effect_metadata.identity_fields()

local base_default_anchors = {
  ["braking-force"] = { unit = "percent", canonical_anchor = 0.15 },
  ["inserter-capacity-bonus"] = { unit = "native", canonical_anchor = 4, whole_number = true },
  ["laser-shooting-speed"] = { unit = "percent", canonical_anchor = 0.50 },
  ["research-speed"] = { unit = "percent", canonical_anchor = 0.60 },
  ["weapon-shooting-speed"] = { unit = "percent", canonical_anchor = 0.40 },
  ["worker-robots-storage"] = { unit = "native", canonical_anchor = 1, whole_number = true }
}

local function close_to_integer(value)
  return math.abs(value - math.floor(value + 0.5)) < 0.000001
end

function M.numeric_effect_descriptor(effect)
  return effect_metadata.numeric_descriptor(effect)
end

function M.effect_identity(effect)
  local identity = {}
  for _, field in ipairs(identity_fields) do
    if effect and effect[field] ~= nil then identity[field] = effect[field] end
  end
  return identity
end

function M.effect_identity_signature(effect)
  local parts = {}
  for _, field in ipairs(identity_fields) do
    if effect and effect[field] ~= nil then
      table.insert(parts, field .. "=" .. tostring(effect[field]))
    end
  end
  return table.concat(parts, ";")
end

function M.effect_has_positive_numeric_value(effect)
  local descriptor = M.numeric_effect_descriptor(effect)
  return descriptor ~= nil and descriptor.value > 0
end

function M.contract_from_effect(effect, selected_effect)
  local canonical = M.numeric_effect_descriptor(effect)
  local emitted = M.numeric_effect_descriptor(selected_effect or effect)
  return {
    identity = M.effect_identity(effect),
    identity_signature = M.effect_identity_signature(effect),
    canonical_value = canonical and canonical.value or nil,
    selected_value = emitted and emitted.value or nil,
    emitted_value = emitted and emitted.value or nil,
    owner_match_policy = "identity-and-policy",
    replacement_policy = "transactional"
  }
end

function M.descriptor_from_effects(effects)
  local descriptor = nil
  for _, effect in ipairs(effects or {}) do
    local candidate = M.numeric_effect_descriptor(effect)
    if not candidate or candidate.value <= 0 then return nil end
    if descriptor and (descriptor.field ~= candidate.field or descriptor.unit ~= candidate.unit) then
      return nil
    end
    if not descriptor then
      descriptor = {
        field = candidate.field,
        unit = candidate.unit,
        display_multiplier = candidate.display_multiplier,
        canonical_anchor = candidate.value,
        whole_number = candidate.unit == "native" and close_to_integer(candidate.value)
      }
    elseif candidate.value > descriptor.canonical_anchor then
      descriptor.canonical_anchor = candidate.value
      descriptor.whole_number = candidate.unit == "native" and close_to_integer(candidate.value)
    end
  end
  return descriptor
end

function M.stream_descriptor(spec)
  local source = spec and spec.descriptor and spec.descriptor.effect
  if type(source) ~= "table" then
    error("MIR stream is missing its canonical typed effect descriptor.", 2)
  end
  return deepcopy(source)
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
  return {
    type = descriptor.whole_number and "int-setting" or "double-setting",
    name = name,
    default_value = descriptor.whole_number and math.floor(default_value + 0.5) or default_value,
    minimum_value = descriptor.whole_number and 1 or 0.01,
    maximum_value = 1000000
  }
end

function M.stream_setting_spec(key, stream)
  return setting_spec(M.stream_setting_name(key), M.stream_descriptor(stream))
end

function M.base_default_descriptor(key)
  local source = base_default_anchors[key]
  if not source then return nil end
  local descriptor = deepcopy(source)
  descriptor.field = descriptor.field or "modifier"
  descriptor.display_multiplier = descriptor.display_multiplier
    or (descriptor.unit == "percent" and 100 or 1)
  return descriptor
end

function M.base_setting_spec(key)
  local descriptor = M.base_default_descriptor(key)
  if not descriptor then return nil end
  return setting_spec(M.base_setting_name(key), descriptor)
end

return M
