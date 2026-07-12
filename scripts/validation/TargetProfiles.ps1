function Get-MIRTargetManifest {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $path = Join-Path $RepoRoot ".mir\targets.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "MIR target profile manifest not found: $path"
  }

  $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ($manifest.schema -ne 2) { throw ".mir/targets.json schema must be 2." }
  if (-not $manifest.profiles) { throw ".mir/targets.json must define profiles." }
  return $manifest
}

function Get-MIRTargetProfile {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$FactorioVersion
  )

  $manifest = Get-MIRTargetManifest -RepoRoot $RepoRoot
  $profile = $manifest.profiles.PSObject.Properties[$FactorioVersion].Value
  if (-not $profile) { throw "No MIR target profile exists for Factorio $FactorioVersion." }

  foreach ($field in @(
    "factorio_version",
    "support_class",
    "validation_status",
    "runtime_state_backend",
    "science_family",
    "reduced_legacy",
    "legacy_factorio_2_0",
    "supports_space_age",
    "weapon_overlap_default",
    "technology_overlay_policy",
    "profile_schema",
    "prototype_shapes",
    "emitter_families",
    "asset_policy",
    "expected_stream_count",
    "features",
    "required_validation_groups"
  )) {
    if ($null -eq $profile.$field) {
      throw "Factorio $FactorioVersion target profile is missing $field."
    }
  }

  if ($profile.factorio_version -ne $FactorioVersion) {
    throw "Factorio target profile key $FactorioVersion disagrees with its factorio_version field."
  }
  if ($profile.runtime_state_backend -notin @("storage", "global")) {
    throw "Factorio $FactorioVersion has invalid runtime_state_backend $($profile.runtime_state_backend)."
  }
  if ($profile.profile_schema -ne 2) {
    throw "Factorio $FactorioVersion target profile schema must be 2."
  }
  foreach ($shapeField in @("recipe_category", "science_pack_prototype_kinds", "product_probability_fields", "technology_formula", "quality", "surface_conditions")) {
    if ($null -eq $profile.prototype_shapes.$shapeField) {
      throw "Factorio $FactorioVersion target profile is missing prototype shape $shapeField."
    }
  }
  if ([int]$profile.expected_stream_count -le 0) {
    throw "Factorio $FactorioVersion target profile must declare a positive expected_stream_count."
  }

  foreach ($positiveField in @("supported_required_mods", "supported_effect_types")) {
    if ($null -eq $profile.PSObject.Properties[$positiveField]) {
      throw "Factorio $FactorioVersion profile is missing positive field $positiveField."
    }
  }
  foreach ($negativeField in @("unsupported_streams", "unsupported_required_mods", "unsupported_effect_types", "omitted_global_settings")) {
    if ($null -ne $profile.PSObject.Properties[$negativeField]) {
      throw "Factorio $FactorioVersion profile must not use negative field $negativeField."
    }
  }

  return $profile
}
