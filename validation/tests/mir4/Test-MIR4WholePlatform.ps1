param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')))

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/WholePlatform.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/TechnologyAcceptance.ps1')

$matrix = Test-MIR4WholePlatformProgramme -RepoRoot $RepoRoot
if ($matrix.area_count -ne 18 -or $matrix.later_release_area_count -ne 0 -or $matrix.executable_area_count -ne 18) {
  throw 'Whole-platform matrix is incomplete.'
}
if ((@($matrix.areas.former_slot) -join '|') -cne (@(0..17 | ForEach-Object { "4.$_" }) -join '|')) {
  throw 'Former 4.x slots are not in exact numeric order.'
}

$upper = New-MIR4TargetKeyProjection -Target 'F210'
$lower = New-MIR4TargetKeyProjection -Target 'f210'
if ($upper.target -cne 'F210' -or $lower.target -cne 'F210' -or $upper.legacy_target -cne 'f210' -or $lower.distribution_target_code -cne '210') {
  throw 'Uppercase target-key canonicalization failed.'
}
foreach ($invalid in @('', '210', 'FF210', 'F21', 'F2100', 'X210')) {
  $caught = $false
  try { ConvertTo-MIR4TargetKey -Target $invalid | Out-Null } catch { $caught = $_.Exception.Message.StartsWith('[mir4-target-key]') }
  if (-not $caught) { throw "Invalid target key was accepted: $invalid" }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
  function New-TestAlternative {
    param([string]$CandidateId, [string]$TechnologyId, [string]$Action, [string]$Disposition, [string]$Decision)
    return [ordered]@{
      alternative_id = "$Action`:$TechnologyId"
      action = $Action
      disposition = $Disposition
      design_fingerprint = "design-$TechnologyId"
      qualification_fingerprint = "qualification-$TechnologyId"
      qualification_decision = $Decision
      technology_design = [ordered]@{
        candidate_id = $CandidateId
        technology_id = $TechnologyId
        design_fingerprint = "design-$TechnologyId"
      }
    }
  }
  $material = New-TestAlternative -CandidateId 'candidate/a' -TechnologyId 'mir-a' -Action 'emit' -Disposition 'materialize' -Decision 'qualified'
  $diagnostic = New-TestAlternative -CandidateId 'candidate/b' -TechnologyId 'mir-b' -Action 'diagnose' -Disposition 'safe-diagnostic' -Decision 'qualified'
  $catalog = [ordered]@{
    schema = 3
    phase = 'final'
    mutation_authority = $false
    selection_authority = 'deterministic-policy-v2'
    catalog_fingerprint = 'catalog-fixture'
    selection_fingerprint = 'selection-fixture'
    candidates = @(
      [ordered]@{candidate_id='candidate/a';alternatives=@($material)},
      [ordered]@{candidate_id='candidate/b';alternatives=@($diagnostic)}
    )
    current_selections = @(
      [ordered]@{candidate_id='candidate/a';alternative_id=$material.alternative_id;design_fingerprint=$material.design_fingerprint;qualification_fingerprint=$material.qualification_fingerprint},
      [ordered]@{candidate_id='candidate/b';alternative_id=$diagnostic.alternative_id;design_fingerprint=$diagnostic.design_fingerprint;qualification_fingerprint=$diagnostic.qualification_fingerprint}
    )
  }
  $catalogPath = Join-Path $tempRoot 'technology-catalog.json'
  $catalog | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $catalogPath -Encoding UTF8
  $queue = New-MIR4TechnologyAcceptanceQueue -RepoRoot $RepoRoot -CatalogPath $catalogPath -Target 'f210' -Ecosystem 'aai'
  $queueJson = $queue | ConvertTo-Json -Depth 100
  if (-not ($queueJson | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-technology-acceptance-queue-v1.schema.json') -ErrorAction Stop)) {
    throw 'Technology acceptance queue failed schema validation.'
  }
  if ($queue.target -cne 'F210' -or $queue.legacy_target -cne 'f210' -or $queue.candidate_count -ne 2 -or
      $queue.entries[0].acceptance_state -cne 'awaiting-quality-and-review' -or
      $queue.entries[1].acceptance_state -cne 'diagnostic-or-nonmaterializing' -or
      [string]::IsNullOrWhiteSpace([string]$queue.queue_sha256) -or
      [bool]$queue.mutation_authorized -or [bool]$queue.compatibility_claim_authorized) {
    throw 'Technology acceptance queue changed its fail-closed contract.'
  }
  $outputPath = Join-Path $tempRoot 'queue.json'
  & (Join-Path $RepoRoot 'tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1') -RepoRoot $RepoRoot -CatalogPath $catalogPath -Target F200 -Ecosystem bz -OutputPath $outputPath
  $written = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100
  if ($written.target -cne 'F200' -or $written.ecosystem -cne 'bz' -or $written.queue_sha256 -cne (Get-MIR4AcceptanceSha256 -Value $written)) {
    throw 'Written technology acceptance queue is not canonical or self-bound.'
  }
  $caught = $false
  try { New-MIR4TechnologyAcceptanceQueue -RepoRoot $RepoRoot -CatalogPath $catalogPath -Target F210 -Ecosystem unknown-pack | Out-Null } catch { $caught = $_.Exception.Message.StartsWith('[mir4-acceptance-ecosystem]') }
  if (-not $caught) { throw 'Unknown ecosystem was accepted.' }
} finally {
  Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host '[ok] MIR 4 whole-platform consolidation, F-target casing, and technology acceptance queue passed.'
