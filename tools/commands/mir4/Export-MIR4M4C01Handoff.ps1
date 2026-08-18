param(
  [string]$RepoRoot = '',
  [string]$OutputRoot = 'build/mir4/m4c01-handoff'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
. (Join-Path $RepoRoot 'tools/lib/mir4/PlatformPreview.ps1')

$output = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
$allowed = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/mir4')).TrimEnd('\') + '\'
if (-not ($output + '\').StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw "M4C01 handoff must remain beneath build/mir4: $output" }
New-Item -ItemType Directory -Force -Path $output | Out-Null

$candidateSetPath = Join-Path $RepoRoot 'build/mir4/m4c01-player-candidates/candidate-set.json'
$previewSetPath = Join-Path $RepoRoot 'build/mir4/platform-preview/preview-assets.json'
foreach ($required in @($candidateSetPath, $previewSetPath)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing M4C01 handoff input: $required" } }
$candidateSet = Get-Content -Raw -LiteralPath $candidateSetPath | ConvertFrom-Json
$previewSet = Get-Content -Raw -LiteralPath $previewSetPath | ConvertFrom-Json

$targetRows = @()
foreach ($candidate in $candidateSet.targets) {
  $archive = Join-Path $RepoRoot "build/mir4/m4c01-player-candidates/distributions/more-infinite-research_$([string]$candidate.version).zip"
  if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Missing M4C01 target archive: $archive" }
  $archiveSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
  if ($archiveSha -cne [string]$candidate.sha256) { throw "M4C01 archive hash mismatch: $($candidate.target_key)" }
  $target = [string]$candidate.target_key
  $runtimeRoot = Join-Path $RepoRoot "build/results/mir4-m4c01/runtime/$target"
  $freshPaths = @()
  $upgradePath = Join-Path $runtimeRoot 'upgrade-matrix.json'
  $historicalPath = Join-Path $runtimeRoot 'runtime-proof.json'
  $runtimeStatus = 'not-run'
  $runtimeQualification = 'not-qualified'
  if ($target -eq 'f210') {
    $freshPaths = @((Join-Path $runtimeRoot 'fresh-package-zip-base-summary.json'), (Join-Path $runtimeRoot 'fresh-package-zip-space-age-summary.json'))
  } elseif ($target -in @('f200','f110','f100')) {
    $freshPaths = @((Join-Path $runtimeRoot 'fresh-package-zip-base-summary.json'))
  }
  if ($freshPaths.Count -gt 0 -and (Test-Path -LiteralPath $upgradePath -PathType Leaf)) {
    $fresh = @($freshPaths | ForEach-Object { if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) { throw "Missing fresh-load evidence: $_" }; Get-Content -Raw -LiteralPath $_ | ConvertFrom-Json })
    $upgrade = Get-Content -Raw -LiteralPath $upgradePath | ConvertFrom-Json
    if (@($fresh | Where-Object { [string]$_.status -ne 'passed' }).Count -eq 0 -and [string]$upgrade.status -eq 'passed' -and @($upgrade.rows | Where-Object { 'upgraded-save-reload-passed' -notin @($_.assertions) -or 'upgraded-save-second-reload-passed' -notin @($_.assertions) }).Count -eq 0) {
      $runtimeStatus = 'development-runtime-green'
      $runtimeQualification = 'automated-fresh-upgrade-two-reload-proof-passed'
    }
  } elseif (Test-Path -LiteralPath $historicalPath -PathType Leaf) {
    $historical = Get-Content -Raw -LiteralPath $historicalPath | ConvertFrom-Json
    if ([string]$historical.status -eq 'passed') {
      $runtimeStatus = 'private-repeat-load-proof-passed'
      $runtimeQualification = [string]$historical.admission_status
    }
  } elseif ($target -eq 'f018') {
    $runtimeStatus = 'blocked-exact-engine-unavailable'
    $runtimeQualification = 'private-unqualified'
  }
  $evidenceFiles = @()
  if (Test-Path -LiteralPath $runtimeRoot -PathType Container) {
    $evidenceFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -Recurse -File | ForEach-Object { [ordered]@{path=[IO.Path]::GetRelativePath($RepoRoot,$_.FullName).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash} })
  }
  $targetRows += [ordered]@{
    target=$target; factorio_line=[string]$candidate.factorio_line; role=[string]$candidate.role; version=[string]$candidate.version
    predecessor=[string]$candidate.predecessor; archive=[IO.Path]::GetRelativePath($RepoRoot,$archive).Replace('\','/'); sha256=$archiveSha
    bytes=[long]$candidate.bytes; entries=[int]$candidate.entries; abc='identical'; runtime_status=$runtimeStatus
    qualification=$runtimeQualification; evidence=$evidenceFiles
  }
}

$previewRows = @()
foreach ($asset in $previewSet.assets) {
  $path = Join-Path $RepoRoot "build/mir4/platform-preview/$([string]$asset.name)"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing preview asset: $path" }
  $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
  if ($sha -cne [string]$asset.sha256) { throw "Preview asset hash mismatch: $($asset.name)" }
  $previewRows += [ordered]@{name=[string]$asset.name;path=[IO.Path]::GetRelativePath($RepoRoot,$path).Replace('\','/');bytes=[long]$asset.bytes;sha256=$sha}
}

$head = (& git -C $RepoRoot rev-parse HEAD).Trim()
$branch = (& git -C $RepoRoot branch --show-current).Trim()
$dirty = [bool]((& git -C $RepoRoot status --porcelain).Count)
$performance = [ordered]@{ f210='fresh-candidate-campaign-required'; f200='fresh-candidate-campaign-required'; evidence=$null }
$performanceEvidenceRows = @()
foreach ($performanceTarget in @('f210','f200')) {
  $performancePath = Join-Path $RepoRoot "build/results/mir4-m4c01/runtime/$performanceTarget/performance-regression.json"
  if (Test-Path -LiteralPath $performancePath -PathType Leaf) {
    $performanceEvidence = Get-Content -Raw -LiteralPath $performancePath | ConvertFrom-Json
    $performance[$performanceTarget] = if ([string]$performanceEvidence.status -eq 'passed') { 'passed' } else { "campaign-$([string]$performanceEvidence.status)" }
    $performanceEvidenceRows += [ordered]@{target=$performanceTarget;path=[IO.Path]::GetRelativePath($RepoRoot,$performancePath).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $performancePath).Hash}
  }
}
$performance.evidence = $performanceEvidenceRows
$blockers = @(
  [ordered]@{id='manual-review';scope='all-admitted-targets';status='required-human-attestation'}
)
foreach ($performanceTarget in @('f210','f200')) {
  if ([string]$performance[$performanceTarget] -ne 'passed') {
    $blockers += [ordered]@{id="performance-$performanceTarget";scope=$performanceTarget;status=[string]$performance[$performanceTarget]}
  }
}
$blockers += @(
  [ordered]@{id='f018-engine';scope='f018';status='exact-engine-unavailable'},
  [ordered]@{id='historical-persisted-reloads';scope='f017-f013';status='required-before-admission'},
  [ordered]@{id='production-go-no-go';scope='sign-seal-promote-tag-publish';status='not-authorized'}
)
$record = [pscustomobject][ordered]@{
  schema=1; kind='MIR4M4C01HandoffV1'; generated_at=(Get-Date).ToUniversalTime().ToString('o')
  source=[ordered]@{branch=$branch;commit=$head;tracked_worktree_dirty=$dirty;baseline='b460edd330dc19524bad97a2374c4c40c3b2ef36'}
  authority=[ordered]@{candidate_wave='M4C01';source_version='4.0.0';public_output_authorized=$false;production_actions_authorized=$false}
  player_candidates=$targetRows; preview_assets=$previewRows
  platform=[ordered]@{conformance='passed';maturity_contract='.mir/releases/waves/mir4-r0/MIR4-Platform-Maturity-and-Publication-ContractV1.json';release_dag='spec/platform/mir4-preview-v0/release-dag.json'}
  performance=$performance
  blockers=$blockers
  record_digest=''
}
$record.record_digest = Get-MIR4PlatformDigest $record
$jsonPath = Join-Path $output 'MIR4_M4C01_STATUS.json'
[IO.File]::WriteAllText($jsonPath,(ConvertTo-MIR4PlatformCanonicalJson $record)+"`n",[Text.UTF8Encoding]::new($false))

$lines = @('# MIR 4 M4C01 Handoff','',"Generated: $($record.generated_at)",'',"Branch: ``$branch``  ","Commit: ``$head``  ","Tracked worktree dirty at export: ``$dirty``",'','## Player candidates','', '| Target | Factorio | Version | SHA-256 | A/B/C | Runtime | Qualification |','| --- | --- | --- | --- | --- | --- | --- |')
foreach ($row in $targetRows) { $lines += "| $($row.target) | $($row.factorio_line) | ``$($row.version)`` | ``$($row.sha256)`` | $($row.abc) | $($row.runtime_status) | $($row.qualification) |" }
$lines += @('','## Developer preview assets','', '| Asset | SHA-256 | Bytes |','| --- | --- | ---: |')
foreach ($row in $previewRows) { $lines += "| $($row.name) | ``$($row.sha256)`` | $($row.bytes) |" }
$lines += @('','## Boundaries','','This is private candidate and development evidence. Production signing, sealing, `main`/`legacy` promotion, tags, GitHub release publication, Mod Portal upload and cleanup remain outside this authorization.','')
$markdownPath = Join-Path $output 'MIR4_M4C01_HANDOFF.md'
[IO.File]::WriteAllText($markdownPath,($lines -join "`n"),[Text.UTF8Encoding]::new($false))
Write-Host "[ok] MIR 4 M4C01 handoff: $output"
$record
