-- The Factorio-1 package selects one of two reduced, pre-Space-Age profiles
-- from the running base mod. The canonical profile facts live in
-- .mir/targets.json; this adapter owns only the package representation.

local function normalize_line(version)
  if version == nil then return nil end
  local line = tostring(version):match("^(%d+%.%d+)")
  if line == "1.0" or line == "1.1" then return line end
  error("MIR Factorio-1 target profile requires base 1.0 or 1.1, got " .. tostring(version) .. ".", 3)
end

local function current_factorio_line()
  -- `mods` owns version discovery during settings/data loading. At runtime it
  -- is unavailable, and LuaBootstrap.active_mods owns the same fact instead.
  -- Some test hosts expose both, so reject disagreement rather than letting
  -- module-cache order choose a target profile.
  local data_line = type(mods) == "table" and normalize_line(mods.base) or nil
  local runtime_mods = script and script.active_mods or nil
  local runtime_line = runtime_mods and normalize_line(runtime_mods.base) or nil
  if data_line and runtime_line and data_line ~= runtime_line then
    error("MIR Factorio-1 base version authorities disagree: " .. data_line .. " versus " .. runtime_line .. ".", 2)
  end
  local line = data_line or runtime_line
  if not line then
    error("MIR Factorio-1 target profile could not read the active base version.", 2)
  end
  return line
end

local function reduced_profile(line, technology_overlay_policy)
  return {
    factorio_version = line,
    support_class = "reduced-compatibility-port",
    validation_status = "validated-historical-release",
    runtime_state_backend = "global",
    science_family = "modern-pre-space-age",
    reduced_legacy = true,
    legacy_factorio_2_0 = false,
    supports_space_age = false,
    weapon_overlap_default = "only-when-dedicated-tech-enabled",
    technology_overlay_policy = technology_overlay_policy,
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
    asset_policy = "legacy-modern-icons",
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
end

local M = {
  schema = 2,
  current_factorio_version = current_factorio_line(),
  profiles = {
    ["1.1"] = reduced_profile("1.1", "legacy-1.1"),
    ["1.0"] = reduced_profile("1.0", "none")
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
