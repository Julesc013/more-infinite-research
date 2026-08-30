param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/technology/TechnologyAcceptance.ps1')

function Assert-MIR4TechnologyAcceptanceV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if (-not $Condition) {
    $suffix=if([string]::IsNullOrWhiteSpace($Detail)){''}else{" $Detail"}
    throw "[$Code]$suffix"
  }
}

function New-MIR4TechnologyAcceptanceTestAlternativeV1 {
  param([string]$CandidateId,[string]$TechnologyId,[string]$Action,[string]$Disposition,[string]$Decision)
  return [ordered]@{
    alternative_id="$Action`:$TechnologyId"
    action=$Action
    disposition=$Disposition
    design_fingerprint="design-$TechnologyId"
    qualification_fingerprint="qualification-$TechnologyId"
    qualification_decision=$Decision
    technology_design=[ordered]@{candidate_id=$CandidateId;technology_id=$TechnologyId;design_fingerprint="design-$TechnologyId"}
  }
}

$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('mir4-technology-acceptance-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
  $material=New-MIR4TechnologyAcceptanceTestAlternativeV1 'candidate/a' 'mir-a' 'emit' 'materialize' 'qualified'
  $diagnostic=New-MIR4TechnologyAcceptanceTestAlternativeV1 'candidate/b' 'mir-b' 'diagnose' 'safe-diagnostic' 'qualified'
  $blocked=New-MIR4TechnologyAcceptanceTestAlternativeV1 'candidate/c' 'mir-c' 'emit' 'materialize' 'blocked'
  $catalog=[ordered]@{
    schema=3;phase='final';mutation_authority=$false;selection_authority='deterministic-policy-v2'
    catalog_fingerprint='catalog-fixture';selection_fingerprint='selection-fixture'
    candidates=@(
      [ordered]@{candidate_id='candidate/a';alternatives=@($material)},
      [ordered]@{candidate_id='candidate/b';alternatives=@($diagnostic)},
      [ordered]@{candidate_id='candidate/c';alternatives=@($blocked)}
    )
    current_selections=@(
      [ordered]@{candidate_id='candidate/a';alternative_id=$material.alternative_id;design_fingerprint=$material.design_fingerprint;qualification_fingerprint=$material.qualification_fingerprint},
      [ordered]@{candidate_id='candidate/b';alternative_id=$diagnostic.alternative_id;design_fingerprint=$diagnostic.design_fingerprint;qualification_fingerprint=$diagnostic.qualification_fingerprint},
      [ordered]@{candidate_id='candidate/c';alternative_id=$blocked.alternative_id;design_fingerprint=$blocked.design_fingerprint;qualification_fingerprint=$blocked.qualification_fingerprint}
    )
  }
  $catalogPath=Join-Path $tempRoot 'technology-catalog.json'
  $catalog | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $catalogPath -Encoding UTF8
  $queue=New-MIR4TechnologyAcceptanceQueue -RepoRoot $repo -CatalogPath $catalogPath -Target f210 -Ecosystem aai
  Assert-MIR4TechnologyAcceptanceV1 ([string]$queue.target -ceq 'F210' -and [string]$queue.legacy_target -ceq 'f210') 'mir4-technology-acceptance-target-key'
  Assert-MIR4TechnologyAcceptanceV1 ([int]$queue.candidate_count -eq 3) 'mir4-technology-acceptance-totality'
  Assert-MIR4TechnologyAcceptanceV1 ((@($queue.entries.acceptance_state)-join'|') -ceq 'awaiting-quality-and-review|diagnostic-or-nonmaterializing|blocked-qualification') 'mir4-technology-acceptance-state'
  Assert-MIR4TechnologyAcceptanceV1 (-not[bool]$queue.mutation_authorized -and -not[bool]$queue.compatibility_claim_authorized -and -not[bool]$queue.publication_authorized) 'mir4-technology-acceptance-firewall'
  Assert-MIR4TechnologyAcceptanceV1 ([string]$queue.queue_sha256 -ceq (Get-MIR4AcceptanceSha256 -Value $queue)) 'mir4-technology-acceptance-digest'
  Assert-MIR4TechnologyAcceptanceV1 ($null -eq $queue.entries[1].technology_id -or [string]$queue.entries[1].technology_id -ceq 'mir-b') 'mir4-technology-acceptance-technology-id'

  $outputPath=Join-Path $tempRoot 'queue.json'
  & (Join-Path $repo 'tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1') -RepoRoot $repo -CatalogPath $catalogPath -Target F200 -Ecosystem bz -OutputPath $outputPath
  $written=Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100
  Assert-MIR4TechnologyAcceptanceV1 ([string]$written.target -ceq 'F200' -and [string]$written.ecosystem -ceq 'bz') 'mir4-technology-acceptance-command'
  Assert-MIR4TechnologyAcceptanceV1 ([string]$written.queue_sha256 -ceq (Get-MIR4AcceptanceSha256 -Value $written)) 'mir4-technology-acceptance-command-digest'

  $caught=$false
  try { New-MIR4TechnologyAcceptanceQueue -RepoRoot $repo -CatalogPath $catalogPath -Target F210 -Ecosystem unknown-pack | Out-Null }
  catch { $caught=$_.Exception.Message.StartsWith('[mir4-acceptance-ecosystem]') }
  Assert-MIR4TechnologyAcceptanceV1 $caught 'mir4-technology-acceptance-unknown-ecosystem'

  $catalog.current_selections[0].design_fingerprint='wrong'
  $catalog | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $catalogPath -Encoding UTF8
  $caught=$false
  try { New-MIR4TechnologyAcceptanceQueue -RepoRoot $repo -CatalogPath $catalogPath -Target F210 -Ecosystem aai | Out-Null }
  catch { $caught=$_.Exception.Message.StartsWith('[mir4-acceptance-selection-fingerprint]') }
  Assert-MIR4TechnologyAcceptanceV1 $caught 'mir4-technology-acceptance-selection-drift'
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

[pscustomobject][ordered]@{
  status='passed'
  canonical_application='tools/mir/application/technology/TechnologyAcceptance.ps1'
  compatibility_entrypoint='tools/lib/mir4/TechnologyAcceptance.ps1'
  package_mutation_authorized=$false
  compatibility_claim_authorized=$false
  publication_authorized=$false
}
