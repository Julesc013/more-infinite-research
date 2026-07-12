local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local generated_registry = require("prototypes.mir.emit.generated_technology_registry")

local M = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

local function strip_categories_for_mode()
  local mode = startup_setting("mir-adjust-vanilla-weapon-speed-techs") or "off"
  if mode == "off" then return {} end

  if mode == "always" then
    return {
      rocket = true,
      ["cannon-shell"] = true
    }
  end

  local out = {}
  local tech_names = {
    "recipe-prod-research_rocket_shooting_speed-1",
    "recipe-prod-research_cannon_shooting_speed-1"
  }
  for _, tech_name in ipairs(tech_names) do
    local tech = data_raw.technology(tech_name)
    for _, effect in ipairs((tech and tech.effects) or {}) do
      if effect.type == "gun-speed" and effect.ammo_category then
        out[effect.ammo_category] = true
      end
    end
  end
  return out
end

local function strip_weapon_speed_effects()
  local strip_categories = strip_categories_for_mode()
  for _, name in ipairs(generated_registry.sorted_names()) do
    local tech = data_raw.technology(name)
    local is_generated_continuation = tech and tech.unit and tech.unit.count_formula
    if generated_registry.contains(name)
      and string.match(name, "^weapon%-shooting%-speed%-%d+$")
      and tech.effects
      and is_generated_continuation
    then
      local filtered = {}
      for _, effect in ipairs(tech.effects) do
        if effect.type == "gun-speed" then
          local category = effect.ammo_category
          if strip_categories[category] then
            -- Skip only categories this mod has explicitly taken over.
          else
            table.insert(filtered, effect)
          end
        else
          table.insert(filtered, effect)
        end
      end
      tech.effects = filtered
    end
  end
end

function M.apply()
  strip_weapon_speed_effects()
  return M
end

return M
