function Render-MIR4TechnicalReleaseV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][object[]]$Fragments)
  $lines = @("# $($Plan.release.title) technical release record",'',"- Source version: $($Plan.release.source_version)","- Source tag: $($Plan.release.tag)","- Renderer ABI: $($Plan.renderer_abi)",'- Publication authority: none (shadow rendering only)','','## Target plan','','| Target | Factorio | Distribution | Action |','| --- | --- | --- | --- |')
  foreach ($target in $Plan.targets) { $lines += "| $($target.target) | $($target.factorio_line) | $($target.distribution_version) | $($target.package_action) |" }
  $lines += @('','## Accepted changes','')
  foreach ($fragment in @(Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'technical' | Sort-Object change_id)) {
    $lines += "### $($fragment.change_id)"
    $lines += ''
    $lines += Get-MIR4NarrativeSummaryV1 -Fragment $fragment -Surface 'technical'
    $lines += ''
    $lines += "- Type: $($fragment.change_type)"
    $lines += "- Package visibility: $($fragment.package_visibility)"
    $lines += "- Security visibility: $($fragment.security_visibility)"
    $lines += "- Targets: " + (@($fragment.target_dispositions | ForEach-Object { "$($_.target)=$($_.disposition)" }) -join ', ')
    $lines += ''
  }
  return (($lines -join "`n").TrimEnd() + "`n")
}
