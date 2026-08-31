function Render-MIR4ReleaseManifestChangesV1 {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][object[]]$Fragments)
  $changes = foreach ($fragment in @(Get-MIR4NarrativeSurfaceChangesV1 -Fragments $Fragments -Surface 'manifest' | Sort-Object change_id)) {
    [ordered]@{change_id=[string]$fragment.change_id;change_type=[string]$fragment.change_type;summary=(Get-MIR4NarrativeSummaryV1 -Fragment $fragment -Surface 'manifest');package_visibility=[string]$fragment.package_visibility;security_visibility=[string]$fragment.security_visibility;targets=@($fragment.target_dispositions | ForEach-Object { [ordered]@{target=[string]$_.target;disposition=[string]$_.disposition} })}
  }
  $record = [ordered]@{schema=1;kind='MIR4ReleaseManifestChangeInventoryV1';plan_id=[string]$Plan.plan_id;source_version=[string]$Plan.release.source_version;renderer_abi=[string]$Plan.renderer_abi;changes=@($changes);publication_authorized=$false}
  return (($record | ConvertTo-Json -Depth 30).Replace("`r`n","`n") + "`n")
}
