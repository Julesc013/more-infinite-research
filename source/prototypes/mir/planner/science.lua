local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")
local k2_science_phase = require("prototypes.mir.compatibility.policies.k2_science_phase")

local M = {}

local function names_from_ingredients(ingredients)
  local out, seen = {}, {}
  for _, ingredient in ipairs(ingredients or {}) do
    local name = type(ingredient) == "table" and (ingredient.name or ingredient[1]) or ingredient
    if name and not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  table.sort(out)
  return out
end

local function append_unique(out, seen, name)
  if name and not seen[name] then
    seen[name] = true
    table.insert(out, name)
  end
end

function M.normalize_ingredients(ingredients)
  local normalized, decision = k2_science_phase.normalize(ingredients, factorio_mods.snapshot())
  if #normalized == 0 or not science_packs.valid_research_ingredients(normalized) then
    decision.status = "blocked-invalid-result"
    decision.changed = false
    return ingredients, decision
  end
  return normalized, decision
end

function M.ingredients_for_selected(key, selected)
  local hard_required = science_selector.required_science_packs_for_stream(key)
  local phase_required = science_selector.phase_required_science_packs_for_stream(key, selected)
  -- Derive retirement and phase constraints from the complete intended set.
  -- Lab validation belongs after normalization, including skip/default policy.
  local normalized, decision = k2_science_phase.normalize(selected, factorio_mods.snapshot())
  decision.requested_packs = names_from_ingredients(selected)
  decision.phase_required_packs = names_from_ingredients(phase_required)
  local retired = {}
  for _, name in ipairs(decision.removed_packs or {}) do retired[name] = true end
  for _, name in ipairs(hard_required) do
    if retired[name] then
      decision.status = "blocked-required-retired-conflict"
      decision.conflicting_pack = name
      return nil, "required-retired-conflict", decision
    end
  end

  local required, required_seen = {}, {}
  for _, name in ipairs(hard_required) do append_unique(required, required_seen, name) end
  for _, name in ipairs(phase_required) do
    if not retired[name] then append_unique(required, required_seen, name) end
  end
  table.sort(required)
  decision.retained_required_packs = names_from_ingredients(required)
  local ingredients, lab_status = science_packs.best_lab_compatible_ingredients(
    normalized, key, required, decision.required_any_packs
  )
  if not ingredients then
    decision.status = "blocked-lab-constraints"
    return nil, lab_status or "invalid", decision
  end
  return ingredients, lab_status or "full", decision
end

function M.ingredients_for_stream(key, spec)
  return M.ingredients_for_selected(key, science_selector.pick_science_for_stream(spec, key))
end

return M
