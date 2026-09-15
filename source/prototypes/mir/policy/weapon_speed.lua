local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local native_effect_coverage = require("prototypes.mir.policy.native_effect_coverage")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

local function strip_categories_for_mode()
  local mode = startup_setting("mir-adjust-vanilla-weapon-speed-techs") or target_line.weapon_overlap_default()
  if mode == "off" then return {} end

  if mode == "always" then
    return {
      rocket = true,
      ["cannon-shell"] = true
    }
  end

  local out = {}
  local replacements = {
    rocket = {
      technology = "recipe-prod-research_rocket_shooting_speed-1",
      effect = { type = "gun-speed", ammo_category = "rocket", modifier = 0.1 }
    },
    ["cannon-shell"] = {
      technology = "recipe-prod-research_cannon_shooting_speed-1",
      effect = { type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.1 }
    }
  }

  for category, replacement in pairs(replacements) do
    if generated_registry.contains(replacement.technology)
      and native_effect_coverage.technology_has_effect_identity(replacement.technology, replacement.effect, {
        positive_numeric_value = true
      }) then
      out[category] = true
    elseif not native_effect_coverage.prefer_mir() then
      local excluded_names = {
        [replacement.technology] = true
      }
      for name, _ in pairs(data_raw.prototypes("technology")) do
        if string.match(name, "^weapon%-shooting%-speed%-%d+$") then
          excluded_names[name] = true
        end
      end
      if #native_effect_coverage.exact_owner_names(replacement.effect, {
        external_only = true,
        excluded_names = excluded_names
      }) > 0 then
        out[category] = true
      end
    end
  end
  return out
end

function M.plan()
  local strip_categories = strip_categories_for_mode()
  local commands = {}
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
      table.insert(commands, {technology = name, effects = filtered})
    end
  end
  return commands
end

return M
