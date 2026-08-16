function Get-MIRValidationScenarioGroup {
  param(
    [Parameter(Mandatory)][string]$ScenarioName,
    [ValidateSet("runtime", "configuration-change", "package")]
    [string]$Kind = "runtime",
    [switch]$EnableSpaceAge
  )

  if ($Kind -eq "package") {
    return "exact-dist"
  }
  if ($ScenarioName -eq "generated-prerequisite-safety") {
    return "science-prerequisites"
  }
  if ($ScenarioName -in @("rigor-late-recipe-removal", "space-exploration-recipe-removal")) {
    return "recipe-target-integrity"
  }
  if ($ScenarioName -match "weapon-speed|weapon-overlap") {
    return "weapon-overlap"
  }
  if ($ScenarioName -eq "settings-profile-roundtrip") {
    return "settings-codec"
  }
  if ($ScenarioName -eq "reduced-settings-surface") {
    return "reduced-settings-surface"
  }
  if ($ScenarioName -match "direct-effects|owner-skip|character-inventory-merged-effects") {
    return "direct-effects"
  }
  if ($EnableSpaceAge -or $ScenarioName -match "^space-age-|cargo-|promethium") {
    return "space-age"
  }
  if ($ScenarioName -match "science|pack-policy|progression-pack") {
    return "official-science"
  }
  if ($ScenarioName -match "generation-integrity|base-extension-boundary|checkbox-") {
    return "base-load"
  }
  if ($Kind -eq "configuration-change") {
    return "runtime-state"
  }

  return "local-mod-library"
}
