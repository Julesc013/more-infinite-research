local M = {}

local IDENTITY_FIELDS = {"type", "recipe", "ammo_category", "turret_id", "fluid", "item"}

local PERCENTAGE_EFFECTS = {
  ["braking-force"] = true,
  ["character-crafting-speed"] = true,
  ["character-mining-speed"] = true,
  ["character-running-speed"] = true,
  ["gun-speed"] = true,
  ["laboratory-productivity"] = true,
  ["laboratory-speed"] = true,
  ["worker-robot-battery"] = true
}

local WHOLE_NUMBER_EFFECTS = {
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

function M.identity_fields()
  local out = {}
  for _, field in ipairs(IDENTITY_FIELDS) do table.insert(out, field) end
  return out
end

function M.numeric_descriptor(effect)
  if type(effect) ~= "table" then return nil end
  if effect.type == "change-recipe-productivity" and type(effect.change) == "number" then
    return {field = "change", unit = "percent", display_multiplier = 100, value = effect.change}
  end
  if type(effect.modifier) ~= "number" then return nil end
  if PERCENTAGE_EFFECTS[effect.type] then
    return {field = "modifier", unit = "percent", display_multiplier = 100, value = effect.modifier}
  end
  if WHOLE_NUMBER_EFFECTS[effect.type] then
    return {field = "modifier", unit = "native", display_multiplier = 1, value = effect.modifier}
  end
  return nil
end

return M
