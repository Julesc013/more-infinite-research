function Render-MIR4SourceChangelogV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][object[]]$Fragments, [object[]]$HistoricalSections=@())
  $selected = Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'source_changelog'
  if ([string]$Plan.plan_id -like 'MIR4-REL-*') {
    $lines = @('# Changelog','',"## [$($Plan.release.source_version)] - $($Plan.release.date)",'')
    $lines += ConvertTo-MIR4NarrativeLinesV1 -Fragments $selected -Surface 'source_changelog'
    foreach($section in $HistoricalSections) {
      $historical = Get-MIR4NarrativeSurfaceChangesV1 -Fragments @($section.fragments) -Surface 'source_changelog'
      $lines += @("## [$([string]$section.source_version)] - $([string]$section.date)",'')
      $lines += ConvertTo-MIR4NarrativeLinesV1 -Fragments $historical -Surface 'source_changelog'
    }
    $lf=[string][char]10
    return (($lines -join $lf).TrimEnd() + $lf)
  }
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
