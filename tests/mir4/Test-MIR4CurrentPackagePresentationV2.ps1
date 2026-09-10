# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV2Authority.ps1'
$before = Get-MIR4CanonicalPackageSourceFingerprint $repo
$scratchCheckRoot = Join-Path $repo ('build/mir4/test-package-presentation-v2-check-' + [guid]::NewGuid().ToString('N'))
$missingCheckRejected = $false
try {
  & $writer -RepoRoot $repo -Check -CheckAuthorityPath (Join-Path $scratchCheckRoot 'mir4-current-package-presentation-v2.json') -CheckEvolutionPath (Join-Path $scratchCheckRoot 'mir4-current-package-presentation-v2-evolution-receipt.json') | Out-Null
} catch {
  if ($_.Exception.Message -notmatch '\[mir4-package-presentation-v2-stale\]') {
    throw
  }
  $missingCheckRejected = $true
}
if (-not $missingCheckRejected -or (Test-Path -LiteralPath $scratchCheckRoot)) {
  throw '[mir4-package-presentation-v2-check-missing-output-write]'
}
& $writer -RepoRoot $repo -Check | Out-Null
$authorityPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v2.json'
$evolutionPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v2-evolution-receipt.json'
$authorityTextBefore = [IO.File]::ReadAllText($authorityPath)
$evolutionTextBefore = [IO.File]::ReadAllText($evolutionPath)
& $writer -RepoRoot $repo | Out-Null
if (
  [IO.File]::ReadAllText($authorityPath) -cne $authorityTextBefore -or
  [IO.File]::ReadAllText($evolutionPath) -cne $evolutionTextBefore
) {
  throw '[mir4-package-presentation-v2-writer-adoption]'
}

$livePresentation = Assert-MIR4CurrentPackagePresentationV2 -RepoRoot $repo -PackageSourceSha256 $before
$v2 = Get-MIR4CurrentPackagePresentationV2 -RepoRoot $repo
$v1Path = Join-Path $repo 'spec/distribution/mir4-package-presentation-baseline-v1.json'
if (
  [string]$v2.predecessor.path -cne 'spec/distribution/mir4-package-presentation-baseline-v1.json' -or
  [string]$v2.predecessor.kind -cne 'MIR4PackagePresentationBaselineV1' -or
  [string]$v2.predecessor.hash_mode -cne 'canonical-text-v1' -or
  (Get-MIR4BootstrapTextSha256 -Path $v1Path) -cne [string]$v2.predecessor.sha256 -or
  -not [bool]$v2.predecessor.retired_for_current_checkout
) {
  throw '[mir4-package-presentation-v2-predecessor-binding]'
}
$expectedInvariants = [ordered]@{
  one_emitter_preserved = $true
  gameplay_difference_authorized = $false
  source_freeze_authorized = $false
  candidate_allocation_authorized = $false
  signing_or_sealing_authorized = $false
  promotion_authorized = $false
  publication_authorized = $false
  player_package_mutation_authorized = $false
  prototype_write_authorized = $false
  public_support_authorized = $false
}
foreach ($name in $expectedInvariants.Keys) {
  if ([bool]$v2.authority_invariants.PSObject.Properties[$name].Value -ne [bool]$expectedInvariants[$name]) {
    throw "[mir4-package-presentation-v2-authority-invariant] $name"
  }
}
$evolutionText = Get-Content -Raw -LiteralPath $evolutionPath
if (-not ($evolutionText | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json'))) {
  throw '[mir4-package-presentation-v2-evolution-schema]'
}
$evolution = $evolutionText | ConvertFrom-Json -Depth 100 -DateKind String
if (
  -not (Test-MIR4BootstrapRecordHash -Record $evolution) -or
  [string]$evolution.authority.record_sha256 -cne [string]$v2.record_sha256
) {
  throw '[mir4-package-presentation-v2-evolution-binding]'
}
foreach ($name in $expectedInvariants.Keys) {
  if ([bool]$evolution.authority_invariants.PSObject.Properties[$name].Value -ne [bool]$expectedInvariants[$name]) {
    throw "[mir4-package-presentation-v2-evolution-invariant] $name"
  }
}
$expectedExecutableEquality = [ordered]@{
  scope = 'm41-05b-documentation-cutover-only'
  cutover_source_identity = [ordered]@{
    commit = 'fed9ae76cdb99b1dcfacfaf263f612d9c6f01a31'
    tree = '15b2df204cac33121000c36b741738ebfc611237'
    package_source_sha256 = '632E71A660AB5DEE4C3286E21AAA348BA7162674DFB15AEEECEFEF4B2525948E'
  }
  player_executable_sources_equal = $true
  evidence = [ordered]@{
    path = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
    kind = 'MIR4M4105BDocumentationCutoverV1'
    hash_mode = 'record-self-hash'
    sha256 = '41DA3E5346D719AB36279EDA535ACD9E193E03F4C9DC64B7903B6594654B3C5B'
    invariant = 'invariants.player_executable_sources_unchanged'
  }
}
$expectedFrozenV1CurrentRelation = [ordered]@{
  frozen_v1_package_source_sha256 = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
  current_package_source_sha256 = '2BE9A0C5510F6369DBE239746BB525F77952DC5E64C0C0D2DCD9E002B059779E'
  package_source_fingerprints_equal = $false
  player_executable_sources_equality_claimed = $false
}
if (
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $v2.player_executable_source_equality) -cne
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedExecutableEquality) -or
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $v2.frozen_v1_current_package_fingerprint_relation) -cne
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedFrozenV1CurrentRelation)
) {
  throw '[mir4-package-presentation-v2-executable-source-equality]'
}
$evolutionTamper = $evolution | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$evolutionTamper.authority_invariants.public_support_authorized = $true
$evolutionTamper.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $evolutionTamper
$evolutionTamperAccepted = $false
try {
  $evolutionTamperAccepted = ($evolutionTamper | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json')
} catch {
  $evolutionTamperAccepted = $false
}
if ($evolutionTamperAccepted) {
  throw '[mir4-package-presentation-v2-evolution-authority-tamper]'
}
$evolutionUnscopedInvariantTamper = $evolution | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$evolutionUnscopedInvariantTamper.authority_invariants | Add-Member -NotePropertyName player_executable_sources_unchanged -NotePropertyValue $true
$evolutionUnscopedInvariantTamper.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $evolutionUnscopedInvariantTamper
$evolutionUnscopedInvariantAccepted = $false
try {
  $evolutionUnscopedInvariantAccepted = ($evolutionUnscopedInvariantTamper | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json')
} catch {
  $evolutionUnscopedInvariantAccepted = $false
}
if ($evolutionUnscopedInvariantAccepted) {
  throw '[mir4-package-presentation-v2-evolution-unscoped-executable-source-accepted]'
}
$evolutionEqualityTamper = $evolution | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$evolutionEqualityTamper.player_executable_source_equality.player_executable_sources_equal = $false
$evolutionEqualityTamper.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $evolutionEqualityTamper
$evolutionEqualityTamperAccepted = $false
try {
  $evolutionEqualityTamperAccepted = ($evolutionEqualityTamper | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json')
} catch {
  $evolutionEqualityTamperAccepted = $false
}
if ($evolutionEqualityTamperAccepted) {
  throw '[mir4-package-presentation-v2-evolution-executable-source-equality-tamper]'
}
$evolutionUnrelatedPairTamper = $evolution | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$evolutionUnrelatedPairTamper.player_executable_source_equality.cutover_source_identity.package_source_sha256 = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
$evolutionUnrelatedPairTamper.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $evolutionUnrelatedPairTamper
$evolutionUnrelatedPairAccepted = $false
try {
  $evolutionUnrelatedPairAccepted = ($evolutionUnrelatedPairTamper | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json')
} catch {
  $evolutionUnrelatedPairAccepted = $false
}
if ($evolutionUnrelatedPairAccepted) {
  throw '[mir4-package-presentation-v2-evolution-unrelated-pair-accepted]'
}
if (
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.player_executable_source_equality) -cne
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedExecutableEquality) -or
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.frozen_v1_current_package_fingerprint_relation) -cne
  (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedFrozenV1CurrentRelation)
) {
  throw '[mir4-package-presentation-v2-evolution-executable-source-equality]'
}
if (
  -not (Test-MIR4BootstrapRecordHash -Record $livePresentation) -or
  -not (((ConvertTo-MIR4BootstrapCanonicalJson -Value $livePresentation) | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v2.schema.json'))) -or
  [string]$livePresentation.record_sha256 -cne [string]$v2.record_sha256 -or
  (Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo) -cne $before -or
  (Get-MIR4FrozenPackagePresentationV1SourceSha256 -RepoRoot $repo) -cne '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'
) {
  throw '[mir4-package-presentation-v2-helper-identities]'
}
$syntheticFutureFingerprint = 'A' * 64
$syntheticFutureRejected = $false
try {
  Assert-MIR4CurrentPackagePresentationV2FingerprintTriplet -StoredPackageSourceSha256 $before -RequiredPackageSourceSha256 $syntheticFutureFingerprint -RecomputedPackageSourceSha256 $syntheticFutureFingerprint | Out-Null
} catch {
  $syntheticFutureRejected = $_.Exception.Message -eq '[mir4-package-presentation-v2-live-fingerprint]'
}
if (-not $syntheticFutureRejected) {
  throw '[mir4-package-presentation-v2-future-fingerprint-accepted]'
}
if ((Assert-MIR4CurrentPackagePresentationV2FingerprintTriplet -StoredPackageSourceSha256 $before -RequiredPackageSourceSha256 $before -RecomputedPackageSourceSha256 $before) -cne $before) {
  throw '[mir4-package-presentation-v2-current-fingerprint-triplet]'
}

foreach ($receipt in @($v2.receipts | Where-Object { [string]$_.hash_mode -ceq 'record-self-hash' })) {
  $receiptPath = Join-Path $repo ([string]$receipt.path)
  $actual = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (
    -not (Test-MIR4BootstrapRecordHash -Record $actual) -or
    (Get-MIR4BootstrapRecordSha256 -Record $actual) -cne [string]$receipt.sha256
  ) {
    throw "[mir4-package-presentation-v2-receipt-self-hash] $($receipt.path)"
  }
}

foreach ($mutation in @(
  @{path = 'predecessor.sha256'; value = '0' * 64}
  @{path = 'authority_invariants.public_support_authorized'; value = $true}
  @{path = 'player_executable_source_equality.player_executable_sources_equal'; value = $false}
  @{path = 'player_executable_source_equality.cutover_source_identity.package_source_sha256'; value = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'}
  @{path = 'frozen_v1_current_package_fingerprint_relation.package_source_fingerprints_equal'; value = $true}
  @{path = 'frozen_v1_current_package_fingerprint_relation.player_executable_sources_equality_claimed'; value = $true}
  @{path = 'package_authority.record_sha256'; value = '0' * 64}
  @{path = 'source_manifest.record_sha256'; value = '0' * 64}
  @{path = 'package_source.fingerprint_sha256'; value = '0' * 64}
  @{path = 'package_source.sole_writer'; value = 'bad'}
  @{path = 'package_source.roots'; value = @('src/mod', 'targets', 'README.md')}
  @{path = 'presentation.repository_readme_package_excluded'; value = $false}
  @{path = 'receipts'; value = @()}
  @{path = 'transition_gate.tagging'; value = $true}
)) {
  $copy = $v2 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
  $parts = $mutation.path -split '\.'
  $node = $copy
  for ($i = 0; $i -lt $parts.Count - 1; $i++) {
    $node = $node.($parts[$i])
  }
  $node.($parts[-1]) = $mutation.value
  $copy.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $copy
  $rejected = $false
  try {
    Assert-MIR4CurrentPackagePresentationV2Record -Record $copy
  } catch {
    $rejected = $true
  }
  if (-not $rejected) {
    throw "[mir4-package-presentation-v2-tamper] $($mutation.path)"
  }
}
$unscopedInvariantCopy = $v2 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$unscopedInvariantCopy.authority_invariants | Add-Member -NotePropertyName player_executable_sources_unchanged -NotePropertyValue $true
$unscopedInvariantCopy.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $unscopedInvariantCopy
$unscopedInvariantRejected = $false
try {
  Assert-MIR4CurrentPackagePresentationV2Record -Record $unscopedInvariantCopy
} catch {
  $unscopedInvariantRejected = $true
}
if (-not $unscopedInvariantRejected) {
  throw '[mir4-package-presentation-v2-unscoped-executable-source-accepted]'
}

$immutableRejected = $false
try {
  & $writer -RepoRoot $repo -RecordedAt '2026-09-10T08:28:16+10:00' | Out-Null
} catch {
  if ($_.Exception.Message -notmatch '\[mir4-package-presentation-v2-authority-immutable-overwrite\]') {
    throw
  }
  $immutableRejected = $true
}
if (-not $immutableRejected) {
  throw '[mir4-package-presentation-v2-writer-overwrite]'
}
if (
  [IO.File]::ReadAllText($authorityPath) -cne $authorityTextBefore -or
  [IO.File]::ReadAllText($evolutionPath) -cne $evolutionTextBefore
) {
  throw '[mir4-package-presentation-v2-writer-drift]'
}

if (
  [string]$v2.package_source.fingerprint_sha256 -cne '2BE9A0C5510F6369DBE239746BB525F77952DC5E64C0C0D2DCD9E002B059779E' -or
  (Get-MIR4CanonicalPackageSourceFingerprint $repo) -cne $before
) {
  throw '[mir4-package-presentation-v2-fingerprint]'
}

Write-Host '[ok] MIR4 current package presentation V2 is retired-V1-bound, receipt-self-hash-recomputed, immutable, and package-source stable.'
