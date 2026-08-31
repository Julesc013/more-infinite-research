function Render-MIR4SourceChangelogV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][object[]]$Fragments)
  $selected = Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'source_changelog'
  $unreleased = @($selected | Where-Object status -eq 'accepted')
  $released = @($selected | Where-Object status -eq 'released')
  $lines = @('# Changelog','')
  if ($unreleased.Count -gt 0) {
    $lines += @('## Unreleased','')
    $lines += ConvertTo-MIR4NarrativeLinesV1 -Fragments $unreleased -Surface 'source_changelog'
  }
  if ($released.Count -gt 0) {
    $lines += @("## [$($Plan.release.source_version)] - $($Plan.release.date)",'')
    $lines += ConvertTo-MIR4NarrativeLinesV1 -Fragments $released -Surface 'source_changelog'
  }
  return (($lines -join "`n").TrimEnd() + "`n")
}
