local deepcopy = require("prototypes.mir.core.deepcopy")
local effect_safety = require("prototypes.mir.emit.effect_safety")
local icon_builder = require("prototypes.mir.emit.icon_builder")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

function M.available_for_stream(key, spec)
  local out = {}

  for _, effect in ipairs(deepcopy((spec and spec.direct_effects) or {})) do
    effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)
    if not target_line.effect_supported(effect) then
      log("[more-infinite-research] Skipping unsupported technology effect for "..key..": "..tostring(effect.type))
    elseif effect.type == "gun-speed" and effect.ammo_category and not lookup.ammo_category_exists(effect.ammo_category) then
      log("[more-infinite-research] Skipping unavailable gun-speed effect for "..key..": missing ammo category "..effect.ammo_category)
    else
      if effect.type == "nothing" then
        local effect_icons = icon_builder.effect_icons_for_stream(spec)
        if effect_icons and #effect_icons > 0 then
          if not effect.icons then effect.icons = effect_icons end
          if not effect.icon then
            effect.icon = effect_icons[1].icon
            effect.icon_size = effect_icons[1].icon_size or spec.icon_size or 64
          end
        end
      end
      table.insert(out, effect)
    end
  end

  return out
end

return M
