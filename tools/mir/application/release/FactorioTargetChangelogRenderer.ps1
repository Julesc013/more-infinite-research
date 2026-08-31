function Render-MIR4FactorioTargetChangelogV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Target, [Parameter(Mandatory)][object[]]$Fragments)
  $selected = Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'target_changelog' -Target ([string]$Target.target)
  if ($selected.Count -eq 0) { throw "[mir4-release-narrative-empty-target] $($Target.target)" }
  $separator = '-' * 99
  $lines = @($separator,"Version: $($Target.distribution_version)","Date: $($Plan.release.date)")
  foreach ($group in @($selected | Group-Object { Get-MIR4NarrativeCategoryV1 ([string]$_.change_type) } | Sort-Object Name)) {
    $lines += "  $($group.Name):"
    foreach ($fragment in @($group.Group | Sort-Object change_id)) { $lines += "    - $(Get-MIR4NarrativeSummaryV1 -Fragment $fragment -Surface 'target_changelog')" }
  }
  $text = (($lines -join "`n") + "`n")
  Assert-MIR4FactorioChangelogV1 -Text $text -Version ([string]$Target.distribution_version)
  return $text
}
