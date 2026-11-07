-- Localized, per-level benefit captions. These are presentation units only;
-- Factorio remains authoritative for earned effects and combined bonuses.
local M = {}

local PERCENT = {
  ["artillery-range"] = true,
  ["character-crafting-speed"] = true,
  ["character-mining-speed"] = true,
  ["character-running-speed"] = true,
  ["laboratory-productivity"] = true,
  ["laboratory-speed"] = true,
  ["mining-drill-productivity-bonus"] = true,
  ["train-braking-force-bonus"] = true,
  ["worker-robot-battery"] = true,
  ["worker-robot-speed"] = true,
}
local COUNT = {
  ["bulk-inserter-capacity-bonus"] = true,
  ["character-build-distance"] = true,
  ["character-health-bonus"] = true,
  ["character-inventory-slots-bonus"] = true,
  ["character-item-drop-distance"] = true,
  ["character-item-pickup-distance"] = true,
  ["character-logistic-trash-slots"] = true,
  ["character-loot-pickup-distance"] = true,
  ["character-reach-distance"] = true,
  ["character-resource-reach-distance"] = true,
  ["inserter-stack-size-bonus"] = true,
  ["maximum-following-robots-count"] = true,
  ["max-cargo-bay-unloading-distance"] = true,
  ["cargo-landing-pad-count"] = true,
  ["stack-inserter-capacity-bonus"] = true,
  ["worker-robot-storage"] = true,
}

local function number(value, percent)
  if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
  value = percent and value * 100 or value
  if math.abs(value) == math.huge then return nil end
  return string.format("%+.6g", value) .. (percent and "%" or "")
end

function M.caption(effect)
  if type(effect) ~= "table" then return nil end
  local kind = effect.type
  if kind == "nothing" then return effect.effect_description end
  if kind == "change-recipe-productivity" then
    local value = number(effect.change, true)
    if value then
      if effect.change < 0 then return {"", {"gui-bonus.productivity-bonus"}, ": ", value} end
      -- Preserve the authored productivity caption and its existing units.
      return {"mir-browser.productivity-increment", string.format("%.6g", effect.change * 100)}
    end
    return nil
  end
  local percent = PERCENT[kind] or kind == "ammo-damage" or kind == "gun-speed" or kind == "turret-attack"
  if not percent and not COUNT[kind] then return nil end
  local value = number(effect.modifier, percent)
  if not value then return nil end
  if kind == "ammo-damage" or kind == "gun-speed" then
    if type(effect.ammo_category) ~= "string" or effect.ammo_category == "" then return nil end
    local subject = {"?", {"ammo-category-name." .. effect.ammo_category}, effect.ammo_category}
    return {"", subject, " — ", {"gui-bonus." .. (kind == "gun-speed" and "shooting-speed-bonus" or "damage-bonus")}, ": ", value}
  elseif kind == "turret-attack" then
    if type(effect.turret_id) ~= "string" or effect.turret_id == "" then return nil end
    return {"", {"?", {"entity-name." .. effect.turret_id}, effect.turret_id}, " — ", {"gui-bonus.damage-bonus"}, ": ", value}
  elseif kind == "max-cargo-bay-unloading-distance" then
    return {"", {"technology-name.more-infinite-research.research_cargo_bay_unloading_distance"}, ": ", value}
  elseif kind == "cargo-landing-pad-count" then
    return {"", {"technology-name.more-infinite-research.research_cargo_landing_pad_count"}, ": ", value}
  elseif kind == "stack-inserter-capacity-bonus" then
    return {"", {"?", {"gui-bonus.stack-inserter-capacity-bonus"}, {"gui-bonus.bulk-inserter-capacity-bonus"}}, ": ", value}
  end
  return {"", {"gui-bonus." .. kind}, ": ", value}
end

return M
