param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')))

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/platform/WholePlatform.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/technology/TechnologyAcceptance.ps1')

$matrix = Test-MIR4WholePlatformProgramme -RepoRoot $RepoRoot
if ($matrix.area_count -ne 18 -or $matrix.later_release_area_count -ne 0 -or $matrix.executable_area_count -ne 18) {
  throw 'Whole-platform matrix is incomplete.'
}
if ((@($matrix.areas.former_slot) -join '|') -cne (@(0..17 | ForEach-Object { "4.$_" }) -join '|')) {
  throw 'Former 4.x slots are not in exact numeric order.'
}

$packageSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'source/package-source.json') | ConvertFrom-Json -Depth 100
foreach ($historicalLocator in @(
  'prototypes/mir/settings/registry.lua',
  'prototypes/mir/planner/compiler.lua',
  'prototypes/mir/emit/technology_operation_executor.lua',
  'prototypes/mir/stage/control.lua',
  'migrations'
)) {
  $resolved = @(Resolve-MIR4WholePlatformImplementation -RepoRoot $RepoRoot -RelativePath $historicalLocator)
  if ($resolved.Count -eq 0 -or @($resolved | Where-Object { -not $_.StartsWith((Join-Path $RepoRoot 'source'), [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
    throw "Historical package locator did not resolve through the current source manifest: $historicalLocator"
  }
}

$directImplementation = 'tools/mir/application/platform/WholePlatform.ps1'
$directResolved = @(Resolve-MIR4WholePlatformImplementation -RepoRoot $RepoRoot -RelativePath $directImplementation -PackageSourcePath (Join-Path $RepoRoot 'missing-package-source.json'))
if ($directResolved.Count -ne 1 -or $directResolved[0] -cne (Resolve-Path -LiteralPath (Join-Path $RepoRoot $directImplementation)).Path) {
  throw 'A direct current implementation path was unnecessarily remapped.'
}

$ambiguousOutput = 'prototypes/mir/settings/registry.lua'
$ambiguousRows = @($packageSource.bindings | Where-Object { [string]$_.output_path -ceq $ambiguousOutput })
if ($ambiguousRows.Count -ne 1) {
  throw 'Whole-platform ambiguity fixture expected one current settings binding.'
}
$ambiguousManifest = [ordered]@{
  schema = 2
  kind = 'MIR4ComposablePackageSourceV2'
  bindings = @(
    $ambiguousRows[0],
    [ordered]@{ output_path = $ambiguousOutput; source_path = 'source/prototypes/mir/planner/compiler.lua' }
  )
}
$ambiguousPath = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-ambiguous-' + [guid]::NewGuid().ToString('N') + '.json')
$missingPath = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-missing-' + [guid]::NewGuid().ToString('N') + '.json')
$missingSourcePath = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-missing-source-' + [guid]::NewGuid().ToString('N') + '.json')
$outsideRepoPath = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-outside-repo-' + [guid]::NewGuid().ToString('N') + '.json')
$outsideSourcePath = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-outside-source-' + [guid]::NewGuid().ToString('N') + '.json')
$staleLeafPath = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-stale-leaf-' + [guid]::NewGuid().ToString('N') + '.json')
$directDirectoryRoot = Join-Path ([IO.Path]::GetTempPath()) ('mir4-whole-platform-direct-directory-' + [guid]::NewGuid().ToString('N'))
try {
  $ambiguousManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ambiguousPath -Encoding UTF8
  [ordered]@{ schema = 2; kind = 'MIR4ComposablePackageSourceV2'; bindings = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $missingPath -Encoding UTF8
  [ordered]@{ schema = 2; kind = 'MIR4ComposablePackageSourceV2'; bindings = @([ordered]@{ output_path = 'prototypes/mir/absent-source.lua'; source_path = 'source/prototypes/mir/absent-source.lua' }) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $missingSourcePath -Encoding UTF8
  [ordered]@{ schema = 2; kind = 'MIR4ComposablePackageSourceV2'; bindings = @([ordered]@{ output_path = 'prototypes/mir/outside-repo.lua'; source_path = '../outside-repo.lua' }) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outsideRepoPath -Encoding UTF8
  [ordered]@{ schema = 2; kind = 'MIR4ComposablePackageSourceV2'; bindings = @([ordered]@{ output_path = 'prototypes/mir/outside-source.lua'; source_path = $directImplementation }) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outsideSourcePath -Encoding UTF8
  New-Item -ItemType Directory -Path (Join-Path $directDirectoryRoot 'migrations') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $directDirectoryRoot 'source') -Force | Out-Null
  [ordered]@{ schema = 2; kind = 'MIR4ComposablePackageSourceV2'; bindings = @() } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $directDirectoryRoot 'source/package-source.json') -Encoding UTF8
  $staleRelative = 'prototypes/mir/settings/registry.lua'
  $staleFullPath = Join-Path $directDirectoryRoot $staleRelative
  $canonicalRelative = 'source/current/settings_registry.lua'
  $canonicalFullPath = Join-Path $directDirectoryRoot $canonicalRelative
  New-Item -ItemType Directory -Path (Split-Path -Parent $staleFullPath) -Force | Out-Null
  New-Item -ItemType Directory -Path (Split-Path -Parent $canonicalFullPath) -Force | Out-Null
  Set-Content -LiteralPath $staleFullPath -Value 'stale historical leaf' -Encoding UTF8
  Set-Content -LiteralPath $canonicalFullPath -Value 'canonical source leaf' -Encoding UTF8
  [ordered]@{ schema = 2; kind = 'MIR4ComposablePackageSourceV2'; bindings = @([ordered]@{ output_path = $staleRelative; source_path = $canonicalRelative }) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $staleLeafPath -Encoding UTF8
  $caught = $false
  try { Resolve-MIR4WholePlatformImplementation -RepoRoot $RepoRoot -RelativePath $ambiguousOutput -PackageSourcePath $ambiguousPath | Out-Null } catch { $caught = $_.Exception.Message.StartsWith('[mir4-whole-platform-package-source] Ambiguous') }
  if (-not $caught) { throw 'An ambiguous package-to-source binding was accepted.' }
  $caught = $false
  try { Resolve-MIR4WholePlatformImplementation -RepoRoot $RepoRoot -RelativePath 'prototypes/mir/absent.lua' -PackageSourcePath $missingPath | Out-Null } catch { $caught = $_.Exception.Message.StartsWith('[mir4-whole-platform-package-source] No current source binding') }
  if (-not $caught) { throw 'A missing package-to-source binding was accepted.' }
  foreach ($negative in @(
    @{ label = 'missing source file'; locator = 'prototypes/mir/absent-source.lua'; manifest = $missingSourcePath; root = $RepoRoot },
    @{ label = 'outside-repository traversal'; locator = 'prototypes/mir/outside-repo.lua'; manifest = $outsideRepoPath; root = $RepoRoot },
    @{ label = 'inside-repository but outside-source path'; locator = 'prototypes/mir/outside-source.lua'; manifest = $outsideSourcePath; root = $RepoRoot },
    @{ label = 'direct directory collision'; locator = 'migrations'; manifest = (Join-Path $directDirectoryRoot 'source/package-source.json'); root = $directDirectoryRoot }
  )) {
    $caught = $false
    try { Resolve-MIR4WholePlatformImplementation -RepoRoot $negative.root -RelativePath $negative.locator -PackageSourcePath $negative.manifest | Out-Null } catch { $caught = $_.Exception.Message.StartsWith('[mir4-whole-platform-package-source]') }
    if (-not $caught) { throw "An invalid $($negative.label) implementation locator was accepted." }
  }
  $staleResolution = @(Resolve-MIR4WholePlatformImplementation -RepoRoot $directDirectoryRoot -RelativePath $staleRelative -PackageSourcePath $staleLeafPath)
  if ($staleResolution.Count -ne 1 -or $staleResolution[0] -cne (Resolve-Path -LiteralPath $canonicalFullPath).Path) {
    throw 'A stale historical package leaf bypassed the canonical source binding.'
  }
} finally {
  Remove-Item -LiteralPath @($ambiguousPath,$missingPath,$missingSourcePath,$outsideRepoPath,$outsideSourcePath,$staleLeafPath) -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $directDirectoryRoot -Recurse -Force -ErrorAction SilentlyContinue
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
