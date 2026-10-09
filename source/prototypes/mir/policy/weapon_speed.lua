local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local effective_settings = require("prototypes.mir.settings.effective")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local native_effect_coverage = require("prototypes.mir.policy.native_effect_coverage")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local direct_streams = require("prototypes.streams.direct-effects")

local M = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

local function has_non_continuation_owner(effect)
  for _, owner in ipairs(native_effect_coverage.identity_owner_names(effect, {
    external_only = true,
    positive_numeric_value = true
  })) do
    if not native_effect_coverage.is_mir_weapon_speed_base_extension_owner(owner) then return true end
  end
  return false
end

-- A category can leave the general continuation only when the exact positive
-- identity has a dedicated emitted MIR owner, or a separate native owner.  A
-- disabled direct stream, an omitted identity, or the setting's "always"
-- mode alone are never authority to remove a paid effect.
local function strip_categories_for_mode()
  local mode = startup_setting("mir-adjust-vanilla-weapon-speed-techs") or target_line.weapon_overlap_default()
  if mode == "off" then return {} end
  local out = {}

  for key, spec in pairs(direct_streams) do
    if spec.adopt_exact_native_effect_owner then
      local technology = spec.technology_name or ("recipe-prod-" .. key .. "-1")
      for _, effect in ipairs(spec.direct_effects or {}) do
        if effect.type == "gun-speed" and type(effect.ammo_category) == "string" then
          if generated_registry.contains(technology)
            and native_effect_coverage.technology_has_effect_identity(technology, effect, {
              positive_numeric_value = true
            }) then
            out[effect.ammo_category] = true
          elseif has_non_continuation_owner(effect) then
            out[effect.ammo_category] = true
          end
        end
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
