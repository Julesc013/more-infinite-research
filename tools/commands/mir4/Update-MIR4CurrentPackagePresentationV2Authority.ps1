param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-10T08:28:15+10:00',
  [switch]$Check,
  [string]$CheckAuthorityPath,
  [string]$CheckEvolutionPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Get-MIR4PackagePresentationV2ReceiptHash {
  param([Parameter(Mandatory)]$Receipt)

  $path = Join-Path $repo ([string]$Receipt.path)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "[mir4-package-presentation-v2-receipt-missing] $($Receipt.path)"
  }

  $actual = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$Receipt.hash_mode -ceq 'record-self-hash') {
    if (-not (Test-MIR4BootstrapRecordHash -Record $actual)) {
      throw "[mir4-package-presentation-v2-receipt-self-hash] $($Receipt.path)"
    }
    $actualHash = Get-MIR4BootstrapRecordSha256 -Record $actual
  } elseif ([string]$Receipt.hash_mode -ceq 'canonical-text-v1') {
    $actualHash = Get-MIR4BootstrapTextSha256 -Path $path
  } else {
    throw "[mir4-package-presentation-v2-receipt-hash-mode] $($Receipt.path)"
  }

  if (
    [string]$actual.kind -cne [string]$Receipt.kind -or
    [string]$actual.status -cne [string]$Receipt.status -or
    $actualHash -cne [string]$Receipt.sha256
  ) {
    throw "[mir4-package-presentation-v2-receipt] $($Receipt.path)"
  }
}

function Write-MIR4PackagePresentationV2NewOrIdentical {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Code
  )

  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    if ([IO.File]::ReadAllText($Path) -cne $Text) {
      throw "[$Code-immutable-overwrite] $Path"
    }
    return
  }

  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $temporaryPath = Join-Path $parent ('.' + (Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
  try {
    $stream = [IO.FileStream]::new(
      $temporaryPath,
      [IO.FileMode]::CreateNew,
      [IO.FileAccess]::Write,
      [IO.FileShare]::None,
      4096,
      [IO.FileOptions]::WriteThrough
    )
    try {
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush($true)
    } finally {
      $stream.Dispose()
    }

    try {
      [IO.File]::Move($temporaryPath, $Path)
    } catch [IO.IOException] {
      if (
        -not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        [IO.File]::ReadAllText($Path) -cne $Text
      ) {
        throw "[$Code-immutable-overwrite] $Path"
      }
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
      [IO.File]::Delete($temporaryPath)
    }
  }
}

$expected = @(
  [pscustomobject][ordered]@{
    path = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
    kind = 'MIR4M4105BDocumentationCutoverV1'
    status = 'M41-05B-DOCUMENTATION-CUTOVER-COMPLETE'
    hash_mode = 'record-self-hash'
    sha256 = '41DA3E5346D719AB36279EDA535ACD9E193E03F4C9DC64B7903B6594654B3C5B'
  }
  [pscustomobject][ordered]@{
    path = 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json'
    kind = 'MIR4M41F2EPackageAuthorityCutoverV1'
    status = 'M41-F2E-PACKAGE-SOURCE-CUTOVER-COMPLETE'
    hash_mode = 'canonical-text-v1'
    sha256 = 'C78618600A8185DB774D480932F34A444112155C11B7209C5F9ABFB1A1BC54C9'
  }
  [pscustomobject][ordered]@{
    path = 'releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
    kind = 'MIR4M41CurrentProductBridgeRetirementReceiptV1'
    status = 'M41-CURRENT-PRODUCT-BRIDGES-RETIRED-PRIVATE-QUALIFICATION-PENDING'
    hash_mode = 'record-self-hash'
    sha256 = 'ACFDDFF41EB88505E8D4AFD1B37C3641E68DD13535EBBAF8149384338071AF79'
  }
)
foreach ($receipt in $expected) {
  Get-MIR4PackagePresentationV2ReceiptHash -Receipt $receipt
}

function Assert-MIR4PackagePresentationV2ReceiptSet {
  param(
    [Parameter(Mandatory)]$Actual,
    [Parameter(Mandatory)][string]$Code
  )

  if (@($Actual).Count -ne $expected.Count) {
    throw "[$Code-count]"
  }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    foreach ($name in @('path', 'kind', 'status', 'hash_mode', 'sha256')) {
      if ([string]$Actual[$index].$name -cne [string]$expected[$index].$name) {
        throw "[$Code] $index/$name"
      }
    }
  }
}

$v1Path = Join-Path $repo 'spec/distribution/mir4-package-presentation-baseline-v1.json'
$v1Text = Get-Content -Raw -LiteralPath $v1Path
if (-not ($v1Text | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-package-presentation-baseline-v1.schema.json'))) {
  throw '[mir4-package-presentation-v2-predecessor-schema]'
}
$v1 = $v1Text | ConvertFrom-Json -Depth 100 -DateKind String
$v1InvariantValues = [ordered]@{
  player_executable_sources_unchanged = $true
  one_emitter_preserved = $true
  gameplay_difference_authorized = $false
  source_freeze_authorized = $false
  candidate_allocation_authorized = $false
  signing_or_sealing_authorized = $false
  promotion_authorized = $false
  publication_authorized = $false
}
foreach ($name in $v1InvariantValues.Keys) {
  if ([bool]$v1.invariants.PSObject.Properties[$name].Value -ne [bool]$v1InvariantValues[$name]) {
    throw "[mir4-package-presentation-v2-predecessor-invariant] $name"
  }
}
$authorityInvariants = [ordered]@{
  one_emitter_preserved = [bool]$v1.invariants.one_emitter_preserved
  gameplay_difference_authorized = [bool]$v1.invariants.gameplay_difference_authorized
  source_freeze_authorized = [bool]$v1.invariants.source_freeze_authorized
  candidate_allocation_authorized = [bool]$v1.invariants.candidate_allocation_authorized
  signing_or_sealing_authorized = [bool]$v1.invariants.signing_or_sealing_authorized
  promotion_authorized = [bool]$v1.invariants.promotion_authorized
  publication_authorized = [bool]$v1.invariants.publication_authorized
  player_package_mutation_authorized = $false
  prototype_write_authorized = $false
  public_support_authorized = $false
}
$documentationCutoverPath = Join-Path $repo 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
$documentationCutover = Get-Content -Raw -LiteralPath $documentationCutoverPath | ConvertFrom-Json -Depth 100 -DateKind String
if (
  -not (Test-MIR4BootstrapRecordHash -Record $documentationCutover) -or
  [string](Get-MIR4BootstrapRecordSha256 -Record $documentationCutover) -cne '41DA3E5346D719AB36279EDA535ACD9E193E03F4C9DC64B7903B6594654B3C5B' -or
  [string]$documentationCutover.kind -cne 'MIR4M4105BDocumentationCutoverV1' -or
  [string]$documentationCutover.base.commit -cne 'fed9ae76cdb99b1dcfacfaf263f612d9c6f01a31' -or
  [string]$documentationCutover.base.tree -cne '15b2df204cac33121000c36b741738ebfc611237' -or
  [string]$documentationCutover.package_source_sha256 -cne '632E71A660AB5DEE4C3286E21AAA348BA7162674DFB15AEEECEFEF4B2525948E' -or
  -not [bool]$documentationCutover.invariants.player_executable_sources_unchanged
) {
  throw '[mir4-package-presentation-v2-executable-source-equality]'
}
$currentFingerprint = Get-MIR4CanonicalPackageSourceFingerprint $repo
$executableSourceEquality = [ordered]@{
  scope = 'm41-05b-documentation-cutover-only'
  cutover_source_identity = [ordered]@{
    commit = [string]$documentationCutover.base.commit
    tree = [string]$documentationCutover.base.tree
    package_source_sha256 = [string]$documentationCutover.package_source_sha256
  }
  player_executable_sources_equal = $true
  evidence = [ordered]@{
    path = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
    kind = 'MIR4M4105BDocumentationCutoverV1'
    hash_mode = 'record-self-hash'
    sha256 = Get-MIR4BootstrapRecordSha256 -Record $documentationCutover
    invariant = 'invariants.player_executable_sources_unchanged'
  }
}
$frozenV1CurrentRelation = [ordered]@{
  frozen_v1_package_source_sha256 = [string]$v1.current.package_source_sha256
  current_package_source_sha256 = $currentFingerprint
  package_source_fingerprints_equal = $false
  player_executable_sources_equality_claimed = $false
}

$authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
$manifest = Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json') | ConvertFrom-Json -Depth 100 -DateKind String
if (
  [string]$authority.record_sha256 -cne 'BC0D254E4BA34B9B4B8E87995F9817B19B1D64B077331B58DE5A1822BEB1943F' -or
  [string]$manifest.record_sha256 -cne 'B0ADB772013A1BEB3B25E999BBF0235956497294455B164B1C1C4BF998496D3B'
) {
  throw '[mir4-package-presentation-v2-bindings]'
}

$files = @(Get-MIR4CanonicalPackageSourceFiles $repo)
if ('README.md' -in $files) {
  throw '[mir4-package-presentation-v2-root-readme-source]'
}
foreach ($target in @('f210', 'f200', 'f110', 'f100')) {
  $rows = @($manifest.bindings | Where-Object {
    [string]$_.source_path -ceq "targets/$target/generation/README.md.template" -and
    [string]$_.output_path -ceq 'README.md' -and
    [string]$_.semantic_class -ceq 'package-documentation' -and
    [string]$_.transform -ceq 'exact-template-v1' -and
    (@($_.target_scope) -join '|') -ceq $target
  })
  if ($rows.Count -ne 1) {
    throw "[mir4-package-presentation-v2-readme-binding] $target"
  }
}

$authorityPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v2.json'
$evolutionPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v2-evolution-receipt.json'
if ($Check) {
  if (
    [string]::IsNullOrWhiteSpace($CheckAuthorityPath) -xor
    [string]::IsNullOrWhiteSpace($CheckEvolutionPath)
  ) {
    throw '[mir4-package-presentation-v2-check-path-pair]'
  }
  if (-not [string]::IsNullOrWhiteSpace($CheckAuthorityPath)) {
    $repoPrefix = $repo.TrimEnd('\') + '\'
    $authorityPath = [IO.Path]::GetFullPath($CheckAuthorityPath)
    $evolutionPath = [IO.Path]::GetFullPath($CheckEvolutionPath)
    foreach ($path in @($authorityPath, $evolutionPath)) {
      if (-not $path.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "[mir4-package-presentation-v2-check-path-boundary] $path"
      }
    }
  }
  if (
    -not (Test-Path -LiteralPath $authorityPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $evolutionPath -PathType Leaf)
  ) {
    throw '[mir4-package-presentation-v2-stale]'
  }
  . (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
  $observation = Get-MIR4CurrentPackagePresentationV2 -RepoRoot $repo
  $observationText = [IO.File]::ReadAllText($authorityPath)
  if ($observationText -cne ((ConvertTo-MIR4BootstrapCanonicalJson -Value $observation) + [char]10)) {
    throw '[mir4-package-presentation-v2-stale]'
  }
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $observation.authority_invariants) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $authorityInvariants)) {
    throw '[mir4-package-presentation-v2-observation-invariants]'
  }
  if (
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $observation.player_executable_source_equality) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $executableSourceEquality) -or
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $observation.frozen_v1_current_package_fingerprint_relation) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $frozenV1CurrentRelation)
  ) {
    throw '[mir4-package-presentation-v2-observation-source-relation]'
  }
  Assert-MIR4PackagePresentationV2ReceiptSet -Actual @($observation.receipts) -Code 'mir4-package-presentation-v2-observation-receipts'

  $evolutionText = [IO.File]::ReadAllText($evolutionPath)
  $evolutionSchema = Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json'
  if (-not ($evolutionText | Test-Json -SchemaFile $evolutionSchema)) {
    throw '[mir4-package-presentation-v2-evolution-schema]'
  }
  $evolution = $evolutionText | ConvertFrom-Json -Depth 100 -DateKind String
  if (
    -not (Test-MIR4BootstrapRecordHash -Record $evolution) -or
    $evolutionText -cne ((ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution) + [char]10) -or
    [string]$evolution.authority.record_sha256 -cne [string]$observation.record_sha256 -or
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.authority_invariants) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $authorityInvariants) -or
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.player_executable_source_equality) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $executableSourceEquality) -or
    (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.frozen_v1_current_package_fingerprint_relation) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $frozenV1CurrentRelation)
  ) {
    throw '[mir4-package-presentation-v2-evolution-binding]'
  }
  Assert-MIR4PackagePresentationV2ReceiptSet -Actual @($evolution.accepted_receipts) -Code 'mir4-package-presentation-v2-evolution-receipts'
  return $observation
}

$gate = [ordered]@{
  version_allocation = $false
  tagging = $false
  signing = $false
  sealing = $false
  publication = $false
}
$v2 = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4CurrentPackagePresentationV2'
  status = 'accepted-current-canonical-package-presentation'
  recorded_at = $RecordedAt
  predecessor = [ordered]@{
    path = 'spec/distribution/mir4-package-presentation-baseline-v1.json'
    kind = [string]$v1.kind
    hash_mode = 'canonical-text-v1'
    sha256 = Get-MIR4BootstrapTextSha256 -Path $v1Path
    retired_for_current_checkout = $true
  }
  authority_invariants = $authorityInvariants
  player_executable_source_equality = $executableSourceEquality
  frozen_v1_current_package_fingerprint_relation = $frozenV1CurrentRelation
  package_authority = [ordered]@{
    path = 'targets/package-authority.json'
    kind = $authority.kind
    status = $authority.status
    record_sha256 = $authority.record_sha256
  }
  source_manifest = [ordered]@{
    path = 'src/mod/package-source.json'
    kind = $manifest.kind
    state = $manifest.source_state
    record_sha256 = $manifest.record_sha256
  }
  package_source = [ordered]@{
    fingerprint_sha256 = $currentFingerprint
    materializer_abi = $manifest.materializer_abi
    roots = @(Get-MIR4CanonicalPackageSourceRoots)
    sole_writer = $authority.writer.implementation
    legacy_root_state = $authority.legacy_root_projection.compatibility_state
  }
  presentation = [ordered]@{
    repository_readme_package_excluded = $true
    target_readmes_manifest_bound = $true
  }
  receipts = $expected
  transition_gate = $gate
  record_sha256 = ''
}
$v2.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $v2
$v2Json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $v2) + [char]10
if (-not ($v2Json | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v2.schema.json'))) {
  throw '[mir4-package-presentation-v2-schema]'
}

$evolution = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4CurrentPackagePresentationV2EvolutionReceipt'
  status = 'CURRENT-PACKAGE-PRESENTATION-V2-CUTOVER-COMPLETE'
  recorded_at = $RecordedAt
  authority = [ordered]@{
    path = 'spec/distribution/mir4-current-package-presentation-v2.json'
    record_sha256 = $v2.record_sha256
  }
  authority_invariants = $authorityInvariants
  player_executable_source_equality = $executableSourceEquality
  frozen_v1_current_package_fingerprint_relation = $frozenV1CurrentRelation
  accepted_receipts = $expected
  transition_gate = $gate
  record_sha256 = ''
}
$evolution.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $evolution
$evolutionJson = (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution) + [char]10
if (-not ($evolutionJson | Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-current-package-presentation-v2-evolution-receipt.schema.json'))) {
  throw '[mir4-package-presentation-v2-evolution-schema]'
}

if ($Check) {
  throw '[mir4-package-presentation-v2-stale]'
} else {
  Write-MIR4PackagePresentationV2NewOrIdentical -Path $authorityPath -Text $v2Json -Code 'mir4-package-presentation-v2-authority'
  Write-MIR4PackagePresentationV2NewOrIdentical -Path $evolutionPath -Text $evolutionJson -Code 'mir4-package-presentation-v2-evolution'
}

$v2
