local deepcopy = require("prototypes.mir.core.deepcopy")
local effect_safety = require("prototypes.technology-effect-safety")
local U = require("prototypes.util")

local M = {}

function M.available_for_stream(key, spec)
  local out = {}

  for _, effect in ipairs(deepcopy((spec and spec.direct_effects) or {})) do
    effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)
    if effect.type == "gun-speed" and effect.ammo_category and not U.ammo_category_exists(effect.ammo_category) then
      log("[more-infinite-research] Skipping unavailable gun-speed effect for "..key..": missing ammo category "..effect.ammo_category)
    else
      if effect.type == "nothing" and not effect.icon and not effect.icons then
        effect.icons = U.effect_icons_for_stream(spec)
      end
      table.insert(out, effect)
    end
  end

  return out
end

return M
