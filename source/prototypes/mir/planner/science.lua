local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")
local k2_science_phase = require("prototypes.mir.compatibility.policies.k2_science_phase")

local M = {}

function M.normalize_ingredients(ingredients)
  local normalized, decision = k2_science_phase.normalize(ingredients, factorio_mods.snapshot())
  if #normalized == 0 or not science_packs.valid_research_ingredients(normalized) then
    decision.status = "blocked-invalid-result"
    decision.changed = false
    return ingredients, decision
  end
  return normalized, decision
end

function M.ingredients_for_stream(key, spec)
  local selected = science_selector.pick_science_for_stream(spec, key)
  local required = science_selector.required_science_packs_for_stream(key)
  -- Derive retirement and phase constraints from the complete intended set.
  -- Lab validation belongs after normalization, including skip/default policy.
  local normalized, decision = k2_science_phase.normalize(selected, factorio_mods.snapshot())
  local retired = {}
  for _, name in ipairs(decision.removed_packs or {}) do retired[name] = true end
  for _, name in ipairs(required) do
    if retired[name] then
      decision.status = "blocked-required-retired-conflict"
      decision.conflicting_pack = name
      return nil, "required-retired-conflict", decision
    end
  end
  local ingredients, lab_status = science_packs.best_lab_compatible_ingredients(
    normalized, key, required, decision.required_any_packs
  )
  if not ingredients then
    decision.status = "blocked-lab-constraints"
    return nil, lab_status or "invalid", decision
  end
  return ingredients, lab_status or "full", decision
end

return M
