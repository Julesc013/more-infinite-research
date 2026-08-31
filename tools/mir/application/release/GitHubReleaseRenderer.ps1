function Render-MIR4GitHubReleaseV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][object[]]$Fragments)
  $selected = Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'github'
  $lines = @([string]$Plan.copy.outcome,'','## Downloads','', '| Factorio | Package |','| --- | --- |')
  foreach ($target in @($Plan.targets | Where-Object package_action -eq 'build')) { $lines += "| $($target.factorio_line) | $($target.asset_name) |" }
  $lines += @('','Install only the package matching the running Factorio line. A target-coded distribution is not an upgrade for a different Factorio line.','','## Changes','')
  foreach ($fragment in @($selected | Sort-Object change_id)) {
    $lines += "- $(Get-MIR4NarrativeSummaryV1 -Fragment $fragment -Surface 'github')"
    if ((Get-MIR4NarrativeDispositionV1 -Fragment $fragment -Surface 'github') -ceq 'include') { foreach ($detail in @($fragment.details)) { $lines += "  - $detail" } }
  }
  $lines += @('','## Upgrade','') + @($Plan.copy.upgrade | ForEach-Object { "- $_" })
  $lines += @('','## Compatibility','') + @($Plan.copy.compatibility | ForEach-Object { "- $_" })
  if (@($Plan.copy.known_issues).Count -gt 0) { $lines += @('','## Known issues','') + @($Plan.copy.known_issues | ForEach-Object { "- $_" }) }
  $lines += @('','## Detailed records','') + @($Plan.copy.details_links | ForEach-Object { "- [$($_.label)]($($_.url))" })
  $lines += @('','This narrative is generated from accepted typed change records. Detailed qualification evidence remains linked rather than embedded in the player-facing release body.')
  $text = (($lines -join "`n").TrimEnd() + "`n")
  Assert-MIR4NarrativePublicCopyV1 -Text $text -Surface 'github' -ReleaseKind ([string]$Plan.release.release_kind)
  return $text
}
