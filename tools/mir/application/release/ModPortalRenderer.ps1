function Render-MIR4ModPortalV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Target, [Parameter(Mandatory)][object[]]$Fragments)
  $selected = Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'mod_portal' -Target ([string]$Target.target)
  $lines = @("## $($Plan.release.title) for Factorio $($Target.factorio_line)",'',[string]$Plan.copy.outcome,'',"Install distribution $($Target.distribution_version) only on Factorio $($Target.factorio_line).",'','### Changes','')
  foreach ($fragment in @($selected | Sort-Object change_id)) { $lines += "- $(Get-MIR4NarrativeSummaryV1 -Fragment $fragment -Surface 'mod_portal')" }
  $lines += @('','### Upgrade','') + @($Plan.copy.upgrade | ForEach-Object { "- $_" })
  $lines += @('','### Compatibility','') + @($Plan.copy.compatibility | ForEach-Object { "- $_" })
  if (@($Plan.copy.known_issues).Count -gt 0) { $lines += @('','### Known issues','') + @($Plan.copy.known_issues | ForEach-Object { "- $_" }) }
  return (($lines -join "`n").TrimEnd() + "`n")
}
