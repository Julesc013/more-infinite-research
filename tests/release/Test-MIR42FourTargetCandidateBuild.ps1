[CmdletBinding()]
param([switch]$IdentityContractsOnly)

Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
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
  $stubInfo = [ordered]@{name='more-infinite-research';version=[string]$identity.distribution_version;factorio_version=([string]$identity.target_id).Substring('factorio-'.Length)}
  [IO.File]::WriteAllText((Join-Path $tree 'info.json'), (($stubInfo | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
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
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1')

$commit = (& git -C $repo rev-parse HEAD).Trim()
$root = Join-Path $repo ('build/test-results/mir42-four-target-candidate-' + [guid]::NewGuid().ToString('N'))
$partialRoot = $root + '-partial'
$historicalRoot = $root + '-historical'
$nineRoot = $root + '-nine'
$identityRoot = $root + '-identity'
$patchRoot = $root + '-patch'
$historicalRecordHashes = @{}
foreach ($target in @('f017','f016','f015','f014','f013')) {
  $historicalRecordHashes[$target] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo "targets/historical/$target/target.json")).Hash
}
try {
  $nineDescriptors = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013'))
  Assert-MIR42CandidateBuildTest (($nineDescriptors | ForEach-Object { [string]$_.target }) -join '|' -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'nine-target-descriptor-order'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [string]$_.materializer -ceq 'canonical-package-source' }).Count -eq 4) 'nine-target-canonical-descriptor-count'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [string]$_.materializer -ceq 'historical-playtest-target' }).Count -eq 5) 'nine-target-historical-descriptor-count'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors | Where-Object { [bool]$_.public_output_authorized -or [bool]$_.publication_authorized }).Count -eq 0) 'nine-target-descriptor-private-boundary'
  $patchDescriptors=@(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SelectedTargets @('f210','f200','f110','f100','f017','f016','f015','f014','f013') -SourceVersion '4.2.1')
  $patchVersions=@('4.2.21001','4.2.20001','4.2.11001','4.2.10001','4.2.01701','4.2.01601','4.2.01501','4.2.01401','4.2.01301')
  Assert-MIR42CandidateBuildTest (($patchDescriptors.distribution_version-join'|')-ceq($patchVersions-join'|')) 'nine-target-requested-source-patch'
  for ($i = 0; $i -lt $patchVersions.Count; $i++) {
    $patchIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target ([string]$patchDescriptors[$i].target) -SourceVersion '4.2.1'
    $baselineIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target ([string]$patchDescriptors[$i].target)
    Assert-MIR42CandidateBuildTest ([string]$patchIdentity.source_version -ceq '4.2.1' -and [string]$patchIdentity.distribution_version -ceq $patchVersions[$i] -and [string]$patchIdentity.distribution_root -ceq "more-infinite-research_$($patchVersions[$i])" -and [string]$patchIdentity.package_name -ceq "more-infinite-research_$($patchVersions[$i]).zip" -and [string]$baselineIdentity.distribution_version -ceq [string]$nineDescriptors[$i].distribution_version) "patch-release-target-reader-and-historical-default-$i"
  }
  $patchDefaults = @(Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.1')
  Assert-MIR42CandidateBuildTest (($patchDefaults.target -join '|') -ceq ($patchDescriptors.target -join '|')) 'patch-default-selects-all-nine'
  $patchFourRejected = $false
  try { Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.1' -SelectedTargets @('f210','f200','f110','f100') | Out-Null } catch { $patchFourRejected = $_.Exception.Message -match 'mir42-candidate-target-selection-unsupported' }
  Assert-MIR42CandidateBuildTest $patchFourRejected 'patch-rejects-explicit-four-target-selection'
  Assert-MIR42CandidateBuildTest (@($patchDescriptors|Where-Object{[string]$_.source_version-cne'4.2.1'-or[bool]$_.public_output_authorized-or[bool]$_.publication_authorized}).Count-eq0) 'nine-target-requested-source-private-boundary'
  Assert-MIR42CandidateBuildTest (@($nineDescriptors|Where-Object{[string]$_.source_version-cne'4.2.0'}).Count-eq0) 'historical-default-source-preserved'
  $unsupportedSourceRejected=$false
  try{Get-MIR42CandidateTargetDescriptors -RepoRoot $repo -SourceVersion '4.2.2'|Out-Null}catch{$unsupportedSourceRejected=$true}
  Assert-MIR42CandidateBuildTest $unsupportedSourceRejected 'unsupported-source-version-rejected'
  foreach ($schemaVersion in @(1,2)) {
    $versionContract = Get-MIR42CandidateConstructionVersionContract -RepoRoot $repo -Manifest ([pscustomobject]@{schema=$schemaVersion;kind="MIR42FourTargetDeterministicCandidateManifestV$schemaVersion"})
    $expectedSource = if ($schemaVersion -eq 1) { '4.2.0' } else { '4.2.1' }
    Assert-MIR42CandidateBuildTest ($versionContract.source_version -ceq $expectedSource -and $versionContract.requires_nine_targets -eq ($schemaVersion -eq 2) -and (Test-Path -LiteralPath $versionContract.schema_path -PathType Leaf)) "construction-version-contract-$schemaVersion"
  }
  foreach ($badContract in @(
    [pscustomobject]@{schema=3;kind='MIR42FourTargetDeterministicCandidateManifestV3'},
    [pscustomobject]@{schema=2;kind='MIR42FourTargetDeterministicCandidateManifestV1'}
  )) {
    $rejected = $false
    try { Get-MIR42CandidateConstructionVersionContract -RepoRoot $repo -Manifest $badContract | Out-Null } catch { $rejected=$_.Exception.Message -match 'mir42-candidate-construction-version-contract' }
    Assert-MIR42CandidateBuildTest $rejected 'construction-version-contract-refuses-unsupported-or-mixed-kind'
  }
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

  $utf8 = [Text.UTF8Encoding]::new($false)
  $lines = @('2.1','2.0','1.1','1.0','0.17','0.16','0.15','0.14','0.13')
  for ($i = 0; $i -lt $patchVersions.Count; $i++) {
    $tree = Join-Path $identityRoot ([string]$patchDescriptors[$i].target)
    New-Item -ItemType Directory -Force -Path $tree | Out-Null
    $baseline = [string]$nineDescriptors[$i].distribution_version
    $inputInfo = [ordered]@{ name='more-infinite-research'; version=$baseline; factorio_version=$lines[$i]; dependencies=@('base'); title='Preserved authored title' }
    $history = "---------------------------------------------------------------------------------------------------`nVersion: $baseline`n  Changes:`n    - Preserved historical entry.`n"
    $readme = "# Preserved authored README`n`nSettings, research catalogue, examples and troubleshooting remain here.`n"
    [IO.File]::WriteAllText((Join-Path $tree 'info.json'), ($inputInfo | ConvertTo-Json -Depth 20), $utf8)
    [IO.File]::WriteAllText((Join-Path $tree 'changelog.txt'), $history, $utf8)
    [IO.File]::WriteAllText((Join-Path $tree 'README.md'), $readme, $utf8)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $patchVersions[$i]
    $info = Get-Content -Raw -LiteralPath (Join-Path $tree 'info.json') | ConvertFrom-Json -Depth 20
    Assert-MIR42CandidateBuildTest ([string]$info.version -ceq $patchVersions[$i] -and [string]$info.factorio_version -ceq $lines[$i] -and [string]$info.title -ceq $inputInfo.title -and @($info.dependencies).Count -eq 1) "patch-metadata-identity-and-preserved-fields-$i"
    $writtenHistory = [IO.File]::ReadAllText((Join-Path $tree 'changelog.txt'))
    Assert-MIR42CandidateBuildTest ($writtenHistory.StartsWith("---------------------------------------------------------------------------------------------------`nVersion: $($patchVersions[$i])`n", [StringComparison]::Ordinal) -and $writtenHistory.EndsWith($history, [StringComparison]::Ordinal)) "patch-current-changelog-and-preserved-history-$i"
    $writtenReadme = [IO.File]::ReadAllText((Join-Path $tree 'README.md'))
    Assert-MIR42CandidateBuildTest ($writtenReadme.StartsWith("MIR $($patchVersions[$i]), source 4.2.1.", [StringComparison]::Ordinal) -and $writtenReadme.EndsWith($readme, [StringComparison]::Ordinal)) "patch-readme-identity-and-preserved-prose-$i"
    $firstHashes = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $patchVersions[$i]
    $secondHashes = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Assert-MIR42CandidateBuildTest (($firstHashes -join '|') -ceq ($secondHashes -join '|')) "patch-metadata-idempotence-$i"
  }
  $negativeTree = Join-Path $identityRoot 'f210'
  foreach ($badVersion in @('4.2.21002','4.2.20001','4.2.99901')) {
    $before = @(Get-ChildItem -LiteralPath $negativeTree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $negativeTree -DistributionVersion $badVersion } catch { $rejected = $true }
    $after = @(Get-ChildItem -LiteralPath $negativeTree -File | Sort-Object Name | Get-FileHash -Algorithm SHA256 | ForEach-Object Hash)
    Assert-MIR42CandidateBuildTest ($rejected -and ($before -join '|') -ceq ($after -join '|')) "patch-invalid-version-no-writes-$badVersion"
  }
  $schemaPath = Join-Path $repo 'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v2.schema.json'
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $schemaPreflight = [pscustomobject]@{
    source=[ordered]@{commit=$commit;tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()}
    package_authority_sha256=[string]$authority.record_sha256
    package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
    target_authority=@($patchDescriptors | Select-Object target,target_id,source_version,distribution_version)
    resource_admission=[ordered]@{admitted=$true;minimum_free_memory_bytes=1;minimum_free_work_bytes=1}
  }
  # These rows are schema fixtures, not package construction or qualification.
  $schemaRows = @(foreach ($descriptor in $patchDescriptors) {
    [pscustomobject]@{
      target=[string]$descriptor.target;distribution_version=[string]$descriptor.distribution_version
      asset=[ordered]@{path="assets/$($descriptor.target)/more-infinite-research_$($descriptor.distribution_version).zip";bytes=1;sha256=('A'*64)}
      content_sha256=('B'*64);entry_count=1
    }
  })
  $schemaRoot = Join-Path $identityRoot 'schema'
  New-Item -ItemType Directory -Force -Path $schemaRoot | Out-Null
  $schemaComplete = Write-MIR42FourTargetManifest -OutputRoot $schemaRoot -Preflight $schemaPreflight -Rows $schemaRows -Failures @()
  Assert-MIR42CandidateBuildTest ($schemaComplete.schema -eq 2 -and $schemaComplete.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV2' -and (Test-MIR4BootstrapRecordHash -Record $schemaComplete)) 'patch-v2-manifest-writer-and-record-hash'
  $schemaPartial = Write-MIR42FourTargetManifest -OutputRoot $schemaRoot -Preflight $schemaPreflight -Rows @($schemaRows[0]) -Failures @([ordered]@{target='f200';message='schema-fixture-only'})
  Assert-MIR42CandidateBuildTest (-not $schemaPartial.build_complete -and $schemaPartial.status -ceq 'private-deterministic-nine-target-candidate-partial') 'patch-partial-manifest-preserves-complete-authority'
  $schemaMutations = [ordered]@{
    'authority-source-zero' = { param($m) $m.target_authority[0].source_version='4.2.0' }
    'authority-wrong-target-version' = { param($m) $m.target_authority[0].distribution_version='4.2.20001' }
    'authority-wrong-engine-line' = { param($m) $m.target_authority[0].target_id='factorio-2.0' }
    'authority-missing-target' = { param($m) $m.target_authority=@($m.target_authority | Select-Object -Skip 1) }
    'authority-duplicate-target' = { param($m) $m.target_authority[8]=$m.target_authority[0] }
    'row-wrong-target-version' = { param($m) $m.targets[0].distribution_version='4.2.20001' }
    'row-patch-two' = { param($m) $m.targets[0].distribution_version='4.2.21002' }
    'row-wrong-target-path' = { param($m) $m.targets[0].target_row_path='target-rows/f200.json' }
    'row-wrong-asset-path' = { param($m) $m.targets[0].asset.path='assets/f200/more-infinite-research_4.2.20001.zip' }
    'complete-missing-target' = { param($m) $m.targets=@($m.targets | Select-Object -Skip 1) }
    'complete-duplicate-target' = { param($m) $m.targets[8]=$m.targets[0] }
    'complete-has-failure' = { param($m) $m.failures=@([ordered]@{target='f200'}) }
    'complete-partial-status' = { param($m) $m.status='private-deterministic-nine-target-candidate-partial' }
    'qualification-claim' = { param($m) $m.qualification='passed' }
    'publication-claim' = { param($m) $m.publication_authorized=$true }
  }
  foreach ($case in $schemaMutations.GetEnumerator()) {
    $invalid = $schemaComplete | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    & $case.Value $invalid
    $valid = $invalid | ConvertTo-Json -Depth 100 | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue
    Assert-MIR42CandidateBuildTest (-not $valid) "patch-schema-refuses-$($case.Key)"
  }
  $invalidPartial = $schemaPartial | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  $duplicatePartialRow = $invalidPartial.targets[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
  $duplicatePartialRow.asset.sha256='C'*64
  $invalidPartial.targets=@($invalidPartial.targets[0],$duplicatePartialRow)
  $valid = $invalidPartial | ConvertTo-Json -Depth 100 | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue
  Assert-MIR42CandidateBuildTest (-not $valid) 'patch-schema-refuses-partial-same-target-different-row'
  if ($IdentityContractsOnly) {
    [pscustomobject][ordered]@{ status='MIR-4.2.1-CANDIDATE-IDENTITY-CONTRACTS-PASSED'; target_identities=9; metadata_idempotence_checks=9; invalid_version_refusals=3; invalid_manifest_refusals=16; engine_runs=0; actual_candidate_zip_builds=0 }
    return
  }

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
  # The historical command imports its own materializer in its script scope.
  # This stub observes only the four modern targets; historical A/B equality
  # is checked through their construction rows below.
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 8) 'nine-build-two-modern-materializations-per-target'
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

  $script:mir42CandidateStubCalls.Clear()
  $patch = New-MIR42FourTargetCandidate -RepoRoot $repo -FinalSourceCommit $commit -BuildId 'PATCH' -SourceVersion '4.2.1' -OutputRoot $patchRoot -MinimumFreeMemoryBytes 1 -MinimumFreeWorkBytes 1
  Assert-MIR42CandidateBuildTest ([bool]$patch.build_complete -and $patch.schema -eq 2 -and $patch.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV2') 'patch-nine-build-v2-complete'
  Assert-MIR42CandidateBuildTest (($patch.targets.distribution_version -join '|') -ceq ($patchVersions -join '|')) 'patch-nine-build-actual-row-identities'
  Assert-MIR42CandidateBuildTest ($script:mir42CandidateStubCalls.Count -eq 8) 'patch-nine-build-two-modern-materializations-per-target'
  Assert-MIR42CandidateBuildTest (Test-MIR4BootstrapRecordHash -Record $patch) 'patch-nine-build-manifest-hash'
  # Portable input-contract control. CI has no delivered terminal ZIPs. Only
  # their inventory lookup uses seal fixtures; all candidate ZIPs are rehashed.
  # This does not execute predecessor custody, upgrades or native qualification.
  $originalArchiveInventory = (Get-Item Function:Get-MIR4ArchiveInventory).ScriptBlock
  $terminalInventoryFixtures = @{}
  foreach ($target in @('f017','f016','f015','f014','f013')) {
    $record = Get-Content -Raw -LiteralPath (Join-Path $repo "targets/historical/$target/target.json") | ConvertFrom-Json -Depth 100
    $seal = Get-Content -Raw -LiteralPath (Join-Path $repo ('.mir/releases/terminal/seals/' + $record.predecessor.version + '.json')) | ConvertFrom-Json -Depth 100
    $terminalInventoryFixtures[[IO.Path]::GetFullPath((Join-Path $repo $record.predecessor.archive))] = [pscustomobject]@{
      archive_sha256=$seal.archive_sha256;bytes=$seal.bytes;content_sha256=$seal.content_sha256;entry_count=$seal.entries
    }
  }
  try {
    Set-Item Function:Get-MIR4ArchiveInventory -Value {
      param([Parameter(Mandatory)][string]$Path)
      $fullPath = [IO.Path]::GetFullPath($Path)
      if ($terminalInventoryFixtures.ContainsKey($fullPath)) { return $terminalInventoryFixtures[$fullPath] }
      return & $originalArchiveInventory -Path $Path
    }
    $patchInputs = @(Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath (Join-Path $patchRoot 'candidate-manifest.json'))
    $legacyInputs = @(Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath (Join-Path $nineRoot 'candidate-manifest.json'))
    Assert-MIR42CandidateBuildTest ($patchInputs.Count -eq 9 -and @($patchInputs | Where-Object { $_.identity.source_version -cne '4.2.1' }).Count -eq 0) 'patch-nine-input-reader-uses-current-source-version'
    Assert-MIR42CandidateBuildTest ($legacyInputs.Count -eq 9 -and @($legacyInputs | Where-Object { $_.identity.source_version -cne '4.2.0' }).Count -eq 0) 'legacy-nine-input-reader-default-preserved'
    $tamperedRowPath = Join-Path $patchRoot 'target-rows/f210.json'
    $originalRowBytes = [IO.File]::ReadAllBytes($tamperedRowPath)
    foreach ($tamper in @('source-version','row-schema')) {
      $badRow = [Text.UTF8Encoding]::new($false).GetString($originalRowBytes) | ConvertFrom-Json -Depth 100
      if ($tamper -ceq 'source-version') { $badRow.source_version='4.2.0' } else { $badRow.schema=2 }
      Write-MIR4BootstrapRecord -Record $badRow -Path $tamperedRowPath | Out-Null
      $rejected = $false
      try { Get-MIR42QualificationCandidateRows -RepoRoot $repo -CandidateManifestPath (Join-Path $patchRoot 'candidate-manifest.json') | Out-Null } catch { $rejected=$_.Exception.Message -match 'mir42-qualification-target-row-binding' }
      Assert-MIR42CandidateBuildTest $rejected "patch-input-reader-refuses-self-hashed-$tamper"
      [IO.File]::WriteAllBytes($tamperedRowPath, $originalRowBytes)
    }
  } finally {
    Set-Item Function:Get-MIR4ArchiveInventory -Value $originalArchiveInventory
  }
  foreach ($target in @('f017','f016','f015','f014','f013')) {
    $row = Get-Content -Raw -LiteralPath (Join-Path $patchRoot "target-rows/$target.json") | ConvertFrom-Json -Depth 100
    Assert-MIR42CandidateBuildTest ([string]$row.distribution_version -ceq "4.2.$($target.Substring(1))01" -and [bool]$row.deterministic_archive_bytes -and -not [bool]$row.publication_authorized) "patch-historical-row-identity-and-private-boundary-$target"
    $recordPath = Join-Path $repo ([string]$row.target_record.path)
    $frozenRecord = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100
    Assert-MIR42CandidateBuildTest ((Test-MIR4BootstrapRecordHash -Record $frozenRecord) -and [string]$frozenRecord.record_sha256 -ceq [string]$row.target_record.sha256 -and (Get-FileHash -Algorithm SHA256 -LiteralPath $recordPath).Hash -ceq $historicalRecordHashes[$target]) "patch-historical-baseline-record-preserved-$target"
  }

  [pscustomobject][ordered]@{
    status = 'MIR-4.2-NINE-TARGET-CONSTRUCTION-ADAPTER-STATIC-PASSED'
    materializer_calls_complete = 8
    partial_successful_targets = @($partial.targets).Count
    historical_target_rows = 5
    patch_target_rows = 9
    predecessor_inventory_control = 'terminal-seal-fixture-only'
    engine_runs = 0
  }
} finally {
  foreach ($path in @($root, $partialRoot, $historicalRoot, $nineRoot, $identityRoot, $patchRoot)) {
    if (Test-Path -LiteralPath $path) {
      $resolvedPath = (Resolve-Path -LiteralPath $path).Path
      $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedPath
      $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedPath
      Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
  }
}
