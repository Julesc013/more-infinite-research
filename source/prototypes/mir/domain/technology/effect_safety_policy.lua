local M = {}

local BLOCKED_EFFECT_TYPES = {
  ["character-item-pickup-distance"] = "item pickup reach can vacuum nearby belt items into player inventories and cause severe lag",
  ["character-loot-pickup-distance"] = "loot pickup reach can vacuum nearby belt items into player inventories and cause severe lag"
}

function M.assert_effect_allowed(effect, context)
  local effect_type = effect and effect.type
  local reason = BLOCKED_EFFECT_TYPES[effect_type]
  if reason then
    error("MIR safety guard blocked unsafe technology effect "
      .. effect_type .. " in " .. tostring(context or "unknown technology") .. ": " .. reason .. ".")
  end
end

function M.assert_effects_allowed(effects, context)
  for _, effect in ipairs(effects or {}) do M.assert_effect_allowed(effect, context) end
end

function M.blocked_effect_types()
  local out = {}
  for effect_type in pairs(BLOCKED_EFFECT_TYPES) do table.insert(out, effect_type) end
  table.sort(out)
  return out
end

return M
