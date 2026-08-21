local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")
local k2_science_phase = require("prototypes.mir.compatibility.policies.k2_science_phase")

local M = {}

local function k2_capabilities()
  local available = {}
  for _, name in ipairs(k2_science_phase.required_science_packs()) do
    available[name] = science_packs.research_pack_prototype(name) ~= nil
  end
  return {science_packs = available}
end

function M.normalize_ingredients(ingredients)
  local normalized, decision = k2_science_phase.normalize(
    ingredients,
    factorio_mods.snapshot(),
    k2_capabilities()
  )
  if #normalized == 0 or not science_packs.valid_research_ingredients(normalized) then
    decision.status = "blocked-invalid-result"
    decision.changed = false
    return ingredients, decision
  end
  return normalized, decision
end

function M.ingredients_for_stream(key, spec)
  local ingredients, lab_status = science_packs.best_lab_compatible_ingredients(
    science_selector.pick_science_for_stream(spec, key),
    key,
    science_selector.required_science_packs_for_stream(key)
  )
  local normalized, decision = M.normalize_ingredients(ingredients)
  return normalized, lab_status or "full", decision
end

return M
