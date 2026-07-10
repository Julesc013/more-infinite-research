local contracts = require("prototypes.mir.settings.effect_contracts")
local deepcopy = require("prototypes.mir.core.deepcopy")
local effective_settings = require("prototypes.mir.settings.effective")

-- Runtime setting application stays separate from the pure descriptor module
-- used by the settings catalog. This prevents catalog/profile import cycles.
local M = {}

local function selected_factor(setting_name, descriptor)
  local value = effective_settings.get(setting_name)
  if type(value) ~= "number" then return 1 end
  local selected = value / descriptor.display_multiplier
  if selected <= 0 or descriptor.canonical_anchor <= 0 then return 1 end
  return selected / descriptor.canonical_anchor
end

function M.scale_stream_effects(key, spec, effects)
  local descriptor = contracts.stream_descriptor(spec)
  if not descriptor then return deepcopy(effects or {}) end
  local factor = selected_factor(contracts.stream_setting_name(key), descriptor)
  if factor == 1 then return deepcopy(effects or {}) end

  local out = deepcopy(effects or {})
  for _, effect in ipairs(out) do
    local candidate = contracts.numeric_effect_descriptor(effect)
    if candidate and candidate.field == descriptor.field and candidate.unit == descriptor.unit then
      effect[descriptor.field] = effect[descriptor.field] * factor
    end
  end
  return out
end

function M.scale_base_effects(key, effects)
  local actual = contracts.descriptor_from_effects(effects)
  if not actual then return deepcopy(effects or {}) end

  local setting_name = contracts.base_setting_name(key)
  local selected = effective_settings.get(setting_name)
  local catalog = contracts.base_default_descriptor(key)
  -- A default setting must preserve a modded base chain exactly.  Only an
  -- intentional non-default selection is recalculated from that chain's
  -- final, already-repaired effect values.
  local catalog_default = catalog and catalog.canonical_anchor * (catalog.unit == "percent" and 100 or 1)
  if selected == nil or selected == catalog_default then return deepcopy(effects or {}) end

  -- The catalog value is the stable player-facing primary effect. Modded base
  -- chains are preserved exactly at the default; an explicit selection scales
  -- their final effects relative to that stable control value.
  local factor = selected_factor(setting_name, catalog or actual)
  if factor == 1 then return deepcopy(effects or {}) end
  local out = deepcopy(effects or {})
  for _, effect in ipairs(out) do
    local candidate = contracts.numeric_effect_descriptor(effect)
    if candidate and candidate.field == actual.field and candidate.unit == actual.unit then
      effect[actual.field] = effect[actual.field] * factor
    end
  end
  return out
end

return M
