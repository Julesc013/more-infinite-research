function Get-MIRTargetManifest {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $path = Join-Path $RepoRoot ".mir\targets.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "MIR target profile manifest not found: $path"
  }

  $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ($manifest.schema -ne 1) { throw ".mir/targets.json schema must be 1." }
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

  return $profile
}
