[CmdletBinding()]
param()

Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script:mir42CandidateStubCalls = [Collections.Generic.List[string]]::new()
$script:mir42CandidateStubFailureTarget = ''

function Assert-MIR42CandidateBuildTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
  if (-not $Condition) { throw "[mir42-candidate-build-test] $Message" }
}

function New-MIR4TargetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$CandidateId,
    [string]$SourceVersion,
    [string]$DistributionVersion,
    [string]$OutputRoot
  )

  $script:mir42CandidateStubCalls.Add("$Target/$CandidateId")
  if ($script:mir42CandidateStubFailureTarget -ceq $Target -and $CandidateId.EndsWith('-B', [StringComparison]::Ordinal)) {
    throw "[mir42-candidate-stub-later-failure] $Target"
  }
  $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $Target -SourceVersion $SourceVersion -DistributionVersion $DistributionVersion
  $candidateRoot = Join-Path $OutputRoot "$Target/$CandidateId"
  $tree = Join-Path $candidateRoot ([string]$identity.distribution_root)
  New-Item -ItemType Directory -Force -Path $tree | Out-Null
  [IO.File]::WriteAllText((Join-Path $tree 'info.json'), ('{"name":"more-infinite-research","version":"' + [string]$identity.distribution_version + '"}' + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $tree 'data.lua'), ('return {}' + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
  $archive = Join-Path $candidateRoot ([string]$identity.package_name)
  Write-MIR4DeterministicRawTreeArchive -SourceRoot $tree -EntryRoot ([string]$identity.distribution_root) -OutputPath $archive -ContainmentRoot $OutputRoot
  $inventory = Get-MIR4ArchiveInventory -Path $archive
  return [pscustomobject][ordered]@{
    target = $Target
    candidate_id = $CandidateId
    source_version = $SourceVersion
    distribution_version = $DistributionVersion
    tree_path = $tree
    archive_path = $archive
    archive_sha256 = [string]$inventory.archive_sha256
    content_sha256 = [string]$inventory.content_sha256
    entry_count = [int]$inventory.entry_count
    record_sha256 = ('A' * 64)
  }
}

. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42CandidateBuild.ps1')

$commit = (& git -C $repo rev-parse HEAD).Trim()
$root = Join-Path $repo ('build/test-results/mir42-four-target-candidate-' + [guid]::NewGuid().ToString('N'))
$partialRoot = $root + '-partial'
$historicalRoot = $root + '-historical'
$nineRoot = $root + '-nine'
try {
  $nineDescriptors = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013'))
  Assert-MIR42CandidateBuildTest (($nineDescriptors | ForEach-Object { [string]$_.target }) -join '|' -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'nine-target-descriptor-order'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [string]$_.materializer -ceq 'canonical-package-source' }).Count -eq 4) 'nine-target-canonical-descriptor-count'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [string]$_.materializer -ceq 'historical-playtest-target' }).Count -eq 5) 'nine-target-historical-descriptor-count'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [bool]$_.public_output_authorized -or [bool]$_.publication_authorized }).Count -eq 0) 'nine-target-descriptor-private-boundary'
  $duplicateRejected = $false
  try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f017', 'f016', 'f015', 'f014', 'f013') | Out-Null } catch { $duplicateRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-duplicate' }
  Assert-MIR42CandidateBuildTest $duplicateRejected 'nine-target-descriptor-duplicate-rejected'
  $unknownRejected = $false
  try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f999') | Out-Null } catch { $unknownRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-unsupported' }
  Assert-MIR42CandidateBuildTest $unknownRejected 'nine-target-descriptor-unknown-rejected'
  $mismatchedHistoricalRecord = Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/historical/f017/target.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $mismatchedHistoricalRecord.factorio_line = '0.13'
  $mismatchedHistoricalRecord.distribution_version = '4.2.01300'
  $mismatchedHistoricalRecord.record_sha256 = ''
  $mismatchedHistoricalRecord.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $mismatchedHistoricalRecord
  $mismatchedHistoricalRejected = $false
  try { Assert-MIR42HistoricalCandidateTargetRecord -Target f017 -Record $mismatchedHistoricalRecord } catch { $mismatchedHistoricalRejected = $_.Exception.Message -match 'mir42-candidate-historical-target-record-invalid' }
  Assert-MIR42CandidateBuildTest $mismatchedHistoricalRejected 'nine-target-descriptor-mismatched-self-hashed-record-rejected'

  $complete = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'STATIC' -OutputRoot $root -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$complete.build_complete) 'complete-build-status'
  Assert-MIR42CandidateBuildTest ($complete.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1') 'complete-build-manifest-kind'
  Assert-MIR42CandidateBuildTest ($complete.status -ceq 'private-deterministic-four-target-candidate-built-unqualified') 'complete-build-private-status'
  Assert-MIR42CandidateBuildTest (@($complete.targets).Count -eq 4) 'complete-build-target-count'
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 8) 'complete-build-serial-two-per-target'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $complete) 'complete-build-manifest-hash'
  Assert-MIR42CandidateBuildTest (-not (($complete | ConvertTo-Json -Depth 100) -match '"engine"')) 'manifest-engine-neutral'

  foreach ($target in @('f210', 'f200', 'f110', 'f100')) {
    $rowPath = Join-Path $root "target-rows/$target.json"
    $row = Get-Content -Raw -LiteralPath $rowPath | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $row) "row-hash-$target"
    Assert-MIR42CandidateBuildTest ([bool]$row.deterministic_archive_bytes -and [bool]$row.package_excluded_surface) "row-determinism-surface-$target"
    $asset = Join-Path $root ([string]$row.asset.path)
    Assert-MIR42CandidateBuildTest ((Get-MIR4Sha256File -Path $asset) -ceq [string]$row.asset.sha256) "row-custody-$target"
  }

  $script:mir42CandidateStubCalls.Clear()
  $script:mir42CandidateStubFailureTarget = 'f200'
  $partial = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'PARTIAL' -OutputRoot $partialRoot -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest (-not [bool]$partial.build_complete) 'partial-build-status'
  Assert-MIR42CandidateBuildTest ($partial.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1') 'partial-build-manifest-kind'
  Assert-MIR42CandidateBuildTest (@($partial.targets).Count -eq 1 -and [string]$partial.targets[0].target -ceq 'f210') 'partial-build-keeps-prior-target-row'
  Assert-MIR42CandidateBuildTest (@($partial.failures).Count -eq 1 -and [string]$partial.failures[0].target -ceq 'f200') 'partial-build-records-later-failure'
  Assert-MIR42CandidateBuildTest (Test-Path -LiteralPath (Join-Path $partialRoot 'target-rows/f210.json') -PathType Leaf) 'partial-build-persists-prior-row'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $partial) 'partial-build-manifest-hash'

  $historicalScript = Join-Path $repo 'tools/commands/release/New-MIR42HistoricalPlaytestCandidate.ps1'
  $historicalManifest = & $historicalScript -RepoRoot $repo -Target f017 -CandidateId 'STATIC' -Repetitions 2 -OutputRoot $historicalRoot -Check
  $historicalDescriptor = @($nineDescriptors | Where-Object { [string]$_.target -ceq 'f017' })
  Assert-MIR42CandidateBuildTest ($historicalDescriptor.Count -eq 1) 'historical-descriptor-f017'
  $historicalRow = Read-MIR42HistoricalCandidateConstructionRow -RepoRoot $repo -Descriptor $historicalDescriptor[0] -ManifestPath (Join-Path $historicalRoot 'manifests/f017.json')
  Assert-MIR42CandidateBuildTest ([string]$historicalManifest.candidate_row.kind -ceq 'MIR42HistoricalCandidateRowV1') 'historical-manifest-row-kind'
  Assert-MIR42CandidateBuildTest ([string]$historicalRow.target -ceq 'f017' -and [bool]$historicalRow.deterministic_archive_bytes -and [bool]$historicalRow.package_excluded_surface) 'historical-row-construction-shape'
  Assert-MIR42CandidateBuildTest (-not [bool]$historicalRow.public_output_authorized -and -not [bool]$historicalRow.publication_authorized) 'historical-row-private-boundary'

  $script:mir42CandidateStubCalls.Clear()
  $script:mir42CandidateStubFailureTarget = ''
  $nine = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'NINE' -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013') -OutputRoot $nineRoot -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$nine.build_complete) 'nine-build-status'
  Assert-MIR42CandidateBuildTest ($nine.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV1') 'nine-build-manifest-kind'
  Assert-MIR42CandidateBuildTest ($nine.status -ceq 'private-deterministic-nine-target-candidate-built-unqualified') 'nine-build-private-status'
  Assert-MIR42CandidateBuildTest ((@($nine.targets | ForEach-Object { [string]$_.target }) -join '|') -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'nine-build-target-order'
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 18) 'nine-build-two-materializations-per-target'
  foreach ($target in @('f017', 'f016', 'f015', 'f014', 'f013')) {
    $rowPath = Join-Path $nineRoot "target-rows/$target.json"
    $row = Get-Content -Raw -LiteralPath $rowPath | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $row) "nine-historical-row-hash-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.materializer -ceq 'historical-playtest-target') "nine-historical-row-materializer-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.target_record.path -ceq "targets/historical/$target/target.json" -and -not [bool]$row.public_output_authorized -and -not [bool]$row.publication_authorized) "nine-historical-row-binding-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.engine.sha256 -match '^[A-Fa-f0-9]{64}$' -and [string]$row.predecessor.sha256 -match '^[A-Fa-f0-9]{64}$') "nine-historical-row-engine-predecessor-$target"
    Assert-MIR42CandidateBuildTest ([string]$row.historical_materializer_manifest_sha256 -match '^[A-Fa-f0-9]{64}$') "nine-historical-row-manifest-receipt-$target"
    $asset = Join-Path $nineRoot ([string]$row.asset.path)
    Assert-MIR42CandidateBuildTest ((Get-MIR4Sha256File -Path $asset) -ceq [string]$row.asset.sha256) "nine-historical-row-custody-$target"
  }

  [pscustomobject][ordered]@{
    status = 'MIR-4.2-NINE-TARGET-CONSTRUCTION-ADAPTER-STATIC-PASSED'
    materializer_calls_complete = 8
    partial_successful_targets = @($partial.targets).Count
    historical_target_rows = 5
    engine_runs = 0
  }
} finally {
  foreach ($path in @($root, $partialRoot, $historicalRoot, $nineRoot)) {
    if (Test-Path -LiteralPath $path) {
      $resolvedPath = (Resolve-Path -LiteralPath $path).Path
      $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedPath
      $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedPath
      Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
  }
}
