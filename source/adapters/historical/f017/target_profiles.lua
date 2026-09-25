-- Factorio 0.17 has a small, native infinite-research surface.  This adapter
-- deliberately keeps the same reduced feature boundary as the Factorio-1
-- package while selecting the exact older base line at every stage.

local function normalize_line(version)
  if version == nil then return nil end
  local line = tostring(version):match("^(%d+%.%d+)")
  if line == "0.17" then return line end
  error("MIR Factorio-0.17 target profile requires base 0.17, got " .. tostring(version) .. ".", 3)
end

local function current_factorio_line()
  -- Factorio 0.17 has no `script.active_mods` at control stage.  This is a
  -- target-specific package, so validate the base line while `mods` exists
  -- and retain the admitted identity once the runtime bootstrap begins.
  if type(mods) == "table" then return normalize_line(mods.base) end
  return "0.17"
end

local M = {
  schema = 2,
  current_factorio_version = current_factorio_line(),
  profiles = {
    ["0.17"] = {
      factorio_version = "0.17",
      support_class = "historical-private-playtest",
      validation_status = "exact-engine-smoke-required",
      runtime_state_backend = "global",
      science_family = "modern-pre-space-age",
      reduced_legacy = true,
      legacy_factorio_2_0 = false,
      supports_space_age = false,
      weapon_overlap_default = "only-when-dedicated-tech-enabled",
      technology_overlay_policy = "none",
      profile_schema = 2,
      prototype_shapes = {
        recipe_category = "category",
        science_pack_prototype_kinds = {"tool"},
        product_probability_fields = {"probability", "catalyst_amount"},
        technology_formula = true,
        quality = false,
        surface_conditions = false,
        mod_data = false
      },
      emitter_families = {"technology"},
      asset_policy = "factorio-0.17-icons",
      expected_stream_count = 11,
      features = {
        compatibility_repairs = false,
        pipeline_extent = false,
        prototype_limits = false,
        module_permissions = false,
        recipe_productivity = false,
        settings_profiles = false,
        scripted_techs = false,
        technology_constant_overlays = false,
        productivity_family_adoption = false
      },
      supported_required_mods = {},
      supported_effect_types = {
        "character-build-distance",
        "character-crafting-speed",
        "character-inventory-slots-bonus",
        "character-item-drop-distance",
        "character-logistic-trash-slots",
        "character-mining-speed",
        "character-reach-distance",
        "character-resource-reach-distance",
        "character-running-speed",
        "gun-speed",
        "laboratory-productivity",
        "worker-robot-battery"
      },
      required_validation_groups = {
        "static",
        "package",
        "base-load",
        "science-prerequisites",
        "direct-effects",
        "weapon-overlap",
        "reduced-settings-surface",
        "runtime-state",
        "exact-dist"
      }
    }
  }
}

function M.current()
  local profile = M.profiles[M.current_factorio_version]
  if not profile then
    error("MIR target profile is missing for Factorio " .. tostring(M.current_factorio_version) .. ".", 2)
  end
  return profile
end

return M
