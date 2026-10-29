-- The captured Ironclad predecessor adds the mortar category to the ordinary
-- shooting-speed chain. Keep this one known binding outside the Generator.
local M = {}

function M.continuation_effect()
  -- MIR's retained 40-percent anchor scales the native 1.3 mortar bonus.
  return {type = "gun-speed", ammo_category = "mortar-bomb", scale = 3.25}
end

function M.preflight(raw)
  local categories = type(raw) == "table" and raw["ammo-category"]
  if type(categories) ~= "table" or type(categories["mortar-bomb"]) ~= "table" then
    error("MIR Ironclad missing ammo category mortar-bomb", 2)
  end
  local technologies = raw.technology
  local predecessor = type(technologies) == "table" and technologies["weapon-shooting-speed-6"]
  if type(predecessor) ~= "table" or type(predecessor.effects) ~= "table" then
    error("MIR Ironclad missing native shooting-speed predecessor", 2)
  end
  local matches = 0
  for _, effect in ipairs(predecessor.effects) do
    if type(effect) ~= "table" then
      error("MIR Ironclad native shooting-speed effect is malformed", 2)
    end
    if effect.type == "gun-speed" and effect.ammo_category == "mortar-bomb" then
      if effect.modifier ~= 1.3 then
        error("MIR Ironclad native mortar shooting-speed bonus changed", 2)
      end
      matches = matches + 1
    end
  end
  if matches ~= 1 then
    error("MIR Ironclad requires one native mortar shooting-speed bonus", 2)
  end
end

return M
