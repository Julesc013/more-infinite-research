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
try {
  $complete = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'STATIC' -OutputRoot $root -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$complete.build_complete) 'complete-build-status'
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
  Assert-MIR42CandidateBuildTest (@($partial.targets).Count -eq 1 -and [string]$partial.targets[0].target -ceq 'f210') 'partial-build-keeps-prior-target-row'
  Assert-MIR42CandidateBuildTest (@($partial.failures).Count -eq 1 -and [string]$partial.failures[0].target -ceq 'f200') 'partial-build-records-later-failure'
  Assert-MIR42CandidateBuildTest (Test-Path -LiteralPath (Join-Path $partialRoot 'target-rows/f210.json') -PathType Leaf) 'partial-build-persists-prior-row'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $partial) 'partial-build-manifest-hash'

  [pscustomobject][ordered]@{
    status = 'MIR-4.2-FOUR-TARGET-CANDIDATE-BUILD-STATIC-PASSED'
    materializer_calls_complete = 8
    partial_successful_targets = @($partial.targets).Count
    engine_runs = 0
  }
} finally {
  foreach ($path in @($root, $partialRoot)) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  }
}
