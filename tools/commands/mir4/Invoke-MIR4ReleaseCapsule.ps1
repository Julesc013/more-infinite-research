param(
  [ValidateSet('Build', 'Verify', 'Restore')]
  [string]$Mode = 'Verify',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$OutputRoot = 'build/results/mir4-t15/release-capsule',
  [string]$SupplyChainRoot = 'build/results/mir4-t15/supply-chain',
  [string]$PreviewRoot = 'build/mir4/platform-preview',
  [string]$PublicKeyPath,
  [string]$CapsulePath,
  [string]$ConstructionReceiptPath,
  [string]$RestoreRoot,
  [string]$SshKeygenPath = 'C:/Windows/System32/OpenSSH/ssh-keygen.exe',
  [string[]]$RevokedFingerprints = @()
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/ReleaseCapsule.ps1')

function Resolve-MIR4ReleaseCapsuleCommandPath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$Existing
  )

  $candidate = if ([IO.Path]::IsPathRooted($Path)) {
    [IO.Path]::GetFullPath($Path)
  } else {
    Assert-MIR4DescendantPath -Root $repo -Path (Join-Path $repo $Path)
  }
  if ($Existing) { return (Resolve-Path -LiteralPath $candidate).Path }
  return $candidate
}

$output = Resolve-MIR4ReleaseCapsuleCommandPath -Path $OutputRoot
$capsule = if ([string]::IsNullOrWhiteSpace($CapsulePath)) {
  Join-Path $output 'capsules/mir4-release-capsule.zip'
} else {
  Resolve-MIR4ReleaseCapsuleCommandPath -Path $CapsulePath
}

if ($Mode -ceq 'Verify') {
  if (-not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsule -RevokedFingerprints $RevokedFingerprints)) {
    throw '[mir4-release-capsule-command-verification]'
  }
  $manifest = Read-MIR4ReleaseCapsuleManifestV1 -CapsulePath $capsule
  [pscustomobject][ordered]@{
    status = 'passed'
    mode = 'verify'
    capsule_sha256 = Get-MIR4Sha256File -Path $capsule
    manifest_record_sha256 = [string]$manifest.record_sha256
    source_commit = [string]$manifest.source.commit
    source_tree = [string]$manifest.source.tree
    production_authority = $false
  }
  exit 0
}

if ($Mode -ceq 'Restore') {
  if ([string]::IsNullOrWhiteSpace($RestoreRoot)) {
    throw '[mir4-release-capsule-command-restore-root]'
  }
  $restore = Resolve-MIR4ReleaseCapsuleCommandPath -Path $RestoreRoot
  $containment = Split-Path -Parent $restore
  Restore-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsule -RestoreRoot $restore -ContainmentRoot $containment -SshKeygenPath $SshKeygenPath -RevokedFingerprints $RevokedFingerprints
  exit 0
}

if (-not (Test-Path -LiteralPath $output -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $output | Out-Null
}
$supply = Resolve-MIR4ReleaseCapsuleCommandPath -Path $SupplyChainRoot -Existing
$preview = Resolve-MIR4ReleaseCapsuleCommandPath -Path $PreviewRoot -Existing
$publicKey = if ([string]::IsNullOrWhiteSpace($PublicKeyPath)) {
  Join-Path $supply '.private/mir4-t15-proof.pub'
} else {
  Resolve-MIR4ReleaseCapsuleCommandPath -Path $PublicKeyPath -Existing
}
$inventoryPath = Join-Path $supply 'component-inventory.json'
$spdx301Path = Join-Path $supply 'sbom.spdx-3.0.1.json'
$spdx23Path = Join-Path $supply 'sbom.spdx-2.3.json'
$provenancePath = Join-Path $supply 'provenance.slsa-v1.json'
$attestationPath = Join-Path $supply 'supply-chain-attestation.json'
foreach ($path in @($inventoryPath, $spdx301Path, $spdx23Path, $provenancePath, $attestationPath, $publicKey)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "[mir4-release-capsule-command-input] $path"
  }
}
$inventory = Read-MIR4ReleaseCapsuleJsonV1 -Path $inventoryPath -MaximumBytes 134217728
$spdx301 = Read-MIR4ReleaseCapsuleJsonV1 -Path $spdx301Path -MaximumBytes 134217728
$spdx23 = Read-MIR4ReleaseCapsuleJsonV1 -Path $spdx23Path -MaximumBytes 134217728
$provenance = Read-MIR4ReleaseCapsuleJsonV1 -Path $provenancePath -MaximumBytes 134217728
$attestation = Read-MIR4ReleaseCapsuleJsonV1 -Path $attestationPath
if (-not (Test-MIR4ComponentInventoryV1 -Inventory $inventory -RepoRoot $repo) -or
    -not (Test-MIR4Spdx301Document -Document $spdx301 -Inventory $inventory -RepoRoot $repo) -or
    -not (Test-MIR4Spdx23CompatibilityDocument -Document $spdx23 -RepoRoot $repo) -or
    -not (Test-MIR4ReleaseCapsuleProvenanceBindingV1 -Inventory $inventory -Provenance $provenance -RepoRoot $repo)) {
  throw '[mir4-release-capsule-command-supply-chain]'
}
$attestationScratch = Join-Path $output 'attestation-verification'
if (-not (Test-MIR4SupplyChainAttestationV1 -RepoRoot $repo -AttestationPath $attestationPath -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $publicKey -ScratchRoot $attestationScratch -ExpectedSourceCommit ([string]$inventory.source.commit) -ExpectedSourceTree ([string]$inventory.source.tree) -ExpectedWorkflowRef ([string]$attestation.payload.workflow.ref) -ExpectedInventoryRecordSha256 ([string]$inventory.record_sha256) -ExpectedProvenanceSha256 (Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $provenance)) -RevokedFingerprints $RevokedFingerprints)) {
  throw '[mir4-release-capsule-command-attestation]'
}

$sourceArchivePath = Join-Path $output 'source/mir4-source-release.zip'
$sourceArchive = New-MIR4DeterministicGitSourceArchiveV1 -RepoRoot $repo -SourceCommit ([string]$inventory.source.commit) -OutputPath $sourceArchivePath -ContainmentRoot $output
if ([string]$sourceArchive.source_tree -cne [string]$inventory.source.tree) {
  throw '[mir4-release-capsule-command-source-tree]'
}
$privateInventoryPath = Join-Path $output 'support/private-custody-inventory.json'
$null = New-MIR4PrivateCustodyInventoryV1 -RepoRoot $repo -OutputPath $privateInventoryPath
$descriptors = [Collections.Generic.List[object]]::new()
foreach ($descriptor in @(
  [pscustomobject]@{role='source-archive';logical_name='mir4-source-release.zip';path=$sourceArchivePath;media_type='application/zip';component_id='mir4-source-release'},
  [pscustomobject]@{role='source-release-record';logical_name='MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json';path=(Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json');media_type='application/json'},
  [pscustomobject]@{role='target-distribution-record-set';logical_name='MIR4-Pre-Freeze-Development-PlanV1.json';path=(Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json');media_type='application/json'},
  [pscustomobject]@{role='component-inventory';logical_name='component-inventory.json';path=$inventoryPath;media_type='application/vnd.mir4.component-inventory+json'},
  [pscustomobject]@{role='sbom-spdx-3.0.1';logical_name='sbom.spdx-3.0.1.json';path=$spdx301Path;media_type='application/spdx+json'},
  [pscustomobject]@{role='sbom-spdx-2.3';logical_name='sbom.spdx-2.3.json';path=$spdx23Path;media_type='application/spdx+json'},
  [pscustomobject]@{role='provenance-slsa-v1';logical_name='provenance.slsa-v1.json';path=$provenancePath;media_type='application/vnd.in-toto+json'},
  [pscustomobject]@{role='supply-chain-attestation';logical_name='supply-chain-attestation.json';path=$attestationPath;media_type='application/vnd.mir4.attestation+json'},
  [pscustomobject]@{role='proof-public-key';logical_name='mir4-t15-proof.pub';path=$publicKey;media_type='application/vnd.openssh.key'},
  [pscustomobject]@{role='rights-custody-inventory';logical_name='private-custody-inventory.json';path=$privateInventoryPath;media_type='application/vnd.mir4.custody-inventory+json'}
)) {
  $descriptors.Add($descriptor)
}
$expectedPreviews = [ordered]@{
  'mir4-api-sdk-v1-preview.zip' = 'mir4-preview-api-sdk-v1'
  'mir4-mep-v1-preview.zip' = 'mir4-preview-mep-v1'
  'mir4-reference-extension-v1-preview.zip' = 'mir4-preview-reference-extension-v1'
  'mir4-inspector-v1-preview.zip' = 'mir4-preview-inspector-v1'
}
foreach ($entry in $expectedPreviews.GetEnumerator()) {
  $path = Join-Path $preview ([string]$entry.Key)
  if (-not (Test-MIR4PreviewAssetArchiveV1 -Path $path -ExpectedCommit ([string]$inventory.source.commit) -ExpectedTree ([string]$inventory.source.tree))) {
    throw "[mir4-release-capsule-command-preview] $($entry.Key)"
  }
  $descriptors.Add([pscustomobject]@{
    role = 'preview-asset'
    logical_name = [string]$entry.Key
    path = $path
    media_type = 'application/zip'
    component_id = [string]$entry.Value
  })
}
$receipt = if ([string]::IsNullOrWhiteSpace($ConstructionReceiptPath)) {
  Join-Path $output 'receipts/construction-receipt.json'
} else {
  Resolve-MIR4ReleaseCapsuleCommandPath -Path $ConstructionReceiptPath
}
New-MIR4ReleaseCapsuleV1 -RepoRoot $repo -Inventory $inventory -SlsaProvenance $provenance -Attestation $attestation -ObjectDescriptors $descriptors.ToArray() -OutputRoot $output -ArchivePath $capsule -ReceiptPath $receipt -SshKeygenPath $SshKeygenPath
