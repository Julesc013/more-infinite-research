[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-15T15:00:00+10:00',
  [switch]$Check,
  [string]$CheckAuthorityPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

function Test-MIR4PackagePresentationV3Schema {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$SchemaPath)
  try { return [bool]((ConvertTo-MIR4BootstrapCanonicalJson -Value $Value) | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop) } catch { return $false }
}

function Get-MIR4PackagePresentationV3FileBinding {
  param([Parameter(Mandatory)][string]$RelativePath)
  return [ordered]@{path=$RelativePath;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $RelativePath))}
}

function Get-MIR4PackagePresentationV3RecordBinding {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Kind)
  $raw = Get-Content -Raw -LiteralPath (Join-Path $repo $RelativePath)
  $record = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$record.kind -cne $Kind -or -not (Test-MIR4BootstrapRecordHash -Record $record)) {
    throw "[mir4-package-presentation-v3-record] $RelativePath"
  }
  return [ordered]@{path=$RelativePath;kind=$Kind;record_sha256=[string]$record.record_sha256}
}

function Assert-MIR4PackagePresentationV3SchemaFile {
  param([Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$SchemaRelativePath,[Parameter(Mandatory)][string]$Code)
  $raw = Get-Content -Raw -LiteralPath (Join-Path $repo $RelativePath)
  if (-not (Test-MIR4PackagePresentationV3Schema -Value ($raw | ConvertFrom-Json -Depth 100 -DateKind String) -SchemaPath (Join-Path $repo $SchemaRelativePath))) {
    throw "[$Code] $RelativePath"
  }
  return $raw
}

$authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
$manifest = Read-MIR4CanonicalPackageAuthorityRecord -RepoRoot $repo -RelativePath ([string]$authority.source_manifest.path) -Kind 'MIR4ComposablePackageSourceV2' -Schema 'spec/schemas/mir4-composable-package-source-v2.schema.json' -Code 'mir4-package-presentation-v3-source-manifest'
$v2 = Get-MIR4PackagePresentationV3RecordBinding -RelativePath 'spec/distribution/mir4-current-package-presentation-v2.json' -Kind 'MIR4CurrentPackagePresentationV2'
$layoutAuthorityRaw = Assert-MIR4PackagePresentationV3SchemaFile -RelativePath 'governance/repository/composable-source-layout-v1.json' -SchemaRelativePath 'contracts/repository/mir4-composable-source-layout-authority-v1.schema.json' -Code 'mir4-package-presentation-v3-layout-authority-schema'
$layoutProofRaw = Assert-MIR4PackagePresentationV3SchemaFile -RelativePath 'assurance/repository/composable-source-layout-v1.json' -SchemaRelativePath 'contracts/repository/mir4-composable-source-layout-proof-policy-v1.schema.json' -Code 'mir4-package-presentation-v3-layout-proof-schema'
$layoutReceiptRaw = Assert-MIR4PackagePresentationV3SchemaFile -RelativePath 'assurance/repository/composable-source-layout-receipt-v1.json' -SchemaRelativePath 'contracts/repository/mir4-composable-source-layout-migration-v1.schema.json' -Code 'mir4-package-presentation-v3-layout-receipt-schema'
$layoutAuthority = Get-MIR4PackagePresentationV3FileBinding -RelativePath 'governance/repository/composable-source-layout-v1.json'
$layoutProof = Get-MIR4PackagePresentationV3FileBinding -RelativePath 'assurance/repository/composable-source-layout-v1.json'
$layoutReceipt = Get-MIR4PackagePresentationV3RecordBinding -RelativePath 'assurance/repository/composable-source-layout-receipt-v1.json' -Kind 'MIR4ComposableSourceLayoutMigrationV1'
$currentFingerprint = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo

if (
  [string]$authority.source_manifest.path -cne 'source/package-source.json' -or
  [string]$authority.source_manifest.record_sha256 -cne [string]$manifest.record_sha256 -or
  [string]$authority.writer.implementation -cne 'tools/mir/application/package/TargetMaterializer.ps1' -or
  [string]$authority.legacy_root_projection.compatibility_state -cne 'retired-historical-read-only' -or
  (@(Get-MIR4CanonicalPackageSourceRoots) -join '|') -cne 'source|targets'
) { throw '[mir4-package-presentation-v3-current-binding]' }
foreach ($target in @('f210','f200','f110','f100')) {
  $rows = @($manifest.bindings | Where-Object {
    [string]$_.source_path -ceq "source/presentation/$target/README.md.template" -and
    [string]$_.output_path -ceq 'README.md' -and
    [string]$_.semantic_class -ceq 'package-documentation' -and
    [string]$_.transform -ceq 'exact-template-v1' -and
    (@($_.target_scope) -join '|') -ceq $target
  })
  if ($rows.Count -ne 1) { throw "[mir4-package-presentation-v3-readme-binding] $target" }
}

$v3 = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4CurrentPackagePresentationV3'
  status = 'accepted-current-composable-source-package-presentation'
  recorded_at = $RecordedAt
  predecessor = [ordered]@{path=$v2.path;kind=$v2.kind;hash_mode='record-self-hash';record_sha256=$v2.record_sha256;frozen_historical_receipt=$true}
  source_layout_successor = [ordered]@{
    migration_id = 'MIR4-COMPOSABLE-SOURCE-LAYOUT-V1'
    authority = $layoutAuthority
    proof_policy = $layoutProof
    receipt = $layoutReceipt
  }
  package_authority = [ordered]@{path='targets/package-authority.json';kind=[string]$authority.kind;record_sha256=[string]$authority.record_sha256}
  source_manifest = [ordered]@{path='source/package-source.json';kind=[string]$manifest.kind;state=[string]$manifest.source_state;record_sha256=[string]$manifest.record_sha256}
  package_source = [ordered]@{fingerprint_sha256=$currentFingerprint;materializer_abi=[string]$manifest.materializer_abi;roots=@(Get-MIR4CanonicalPackageSourceRoots);sole_writer=[string]$authority.writer.implementation;legacy_root_state=[string]$authority.legacy_root_projection.compatibility_state}
  presentation = [ordered]@{repository_readme_package_excluded=$true;target_readmes_manifest_bound=$true}
  authority_invariants = [ordered]@{
    v2_receipts_immutable=$true
    single_editable_source_root=$true
    single_package_writer=$true
    package_bytes_unchanged=$true
    gameplay_semantics_changed=$false
    candidate_allocation_authorized=$false
    signing_or_sealing_authorized=$false
    promotion_authorized=$false
    publication_authorized=$false
    public_support_authorized=$false
  }
  transition_gate = [ordered]@{development_merge=$true;private_build=$false;qualification=$false;technical_seal=$false;main_promotion=$false;version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  record_sha256 = ''
}
$v3.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $v3
$json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $v3) + [char]10
$schemaPath = Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v3.schema.json'
if (-not (Test-MIR4PackagePresentationV3Schema -Value $v3 -SchemaPath $schemaPath)) { throw '[mir4-package-presentation-v3-schema]' }

$authorityPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v3.json'
if (-not [string]::IsNullOrWhiteSpace($CheckAuthorityPath)) {
  if (-not $Check) { throw '[mir4-package-presentation-v3-check-path-mode]' }
  $candidatePath = [IO.Path]::GetFullPath($CheckAuthorityPath)
  $repoPrefix = $repo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  if (-not $candidatePath.StartsWith($repoPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-package-presentation-v3-check-path-boundary]' }
  $authorityPath = $candidatePath
}
if ($Check) {
  if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf) -or [IO.File]::ReadAllText($authorityPath) -cne $json) { throw '[mir4-package-presentation-v3-stale]' }
  return $v3
}
if (Test-Path -LiteralPath $authorityPath -PathType Leaf) {
  if ([IO.File]::ReadAllText($authorityPath) -cne $json) { throw '[mir4-package-presentation-v3-authority-immutable-overwrite]' }
} else {
  [IO.File]::WriteAllText($authorityPath, $json, [Text.UTF8Encoding]::new($false))
}
return $v3
