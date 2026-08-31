param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$SshKeygenPath = 'C:/Windows/System32/OpenSSH/ssh-keygen.exe'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/PlatformPreview.ps1')
. (Join-Path $repo 'tools/lib/mir4/ReleaseCapsule.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')

function Assert-MIR4ReleaseCapsuleTest {
  param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Diagnostic)
  if (-not $Condition) { throw "[$Diagnostic]" }
}

function Copy-MIR4ReleaseCapsuleAttackArchive {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$DestinationPath,
    [string]$OmitRelativePath,
    [string]$CorruptRelativePath
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $source = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $SourcePath).Path)
  $output = [IO.File]::Open($DestinationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $destination = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    foreach ($entry in $source.Entries) {
      $relative = [string]$entry.FullName
      if ($relative.StartsWith('mir4-release-capsule/', [StringComparison]::Ordinal)) {
        $relative = $relative.Substring('mir4-release-capsule/'.Length)
      }
      if (-not [string]::IsNullOrWhiteSpace($OmitRelativePath) -and $relative -ceq $OmitRelativePath) {
        continue
      }
      $copy = $destination.CreateEntry([string]$entry.FullName, [IO.Compression.CompressionLevel]::Optimal)
      $copy.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
      $copy.ExternalAttributes = 0
      $input = $entry.Open()
      $outputStream = $copy.Open()
      try {
        if (-not [string]::IsNullOrWhiteSpace($CorruptRelativePath) -and $relative -ceq $CorruptRelativePath) {
          $bytes = Read-MIR4BoundedZipEntryBytes -Entry $entry -MaximumBytes 268435456
          if ($bytes.Length -eq 0) { throw '[mir4-release-capsule-test-empty-attack-object]' }
          $bytes[0] = $bytes[0] -bxor 1
          $outputStream.Write($bytes, 0, $bytes.Length)
        } else {
          $input.CopyTo($outputStream)
        }
      } finally {
        $outputStream.Dispose()
        $input.Dispose()
      }
    }
  } finally {
    $destination.Dispose()
    $output.Dispose()
    $source.Dispose()
  }
}

$testRoot = Join-Path $repo ('build/results/mir4-t15/tests/release-capsule-' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $testRoot 'source'
$supplyRoot = Join-Path $testRoot 'supply'
$previewRoot = Join-Path $testRoot 'previews'
$keyRoot = Join-Path $testRoot 'keys'
$privateKey = Join-Path $keyRoot 'proof'
$publicKey = $privateKey + '.pub'
$attestationPath = Join-Path $supplyRoot 'supply-chain-attestation.json'
$sourceA = Join-Path $sourceRoot 'A.zip'
$sourceB = Join-Path $sourceRoot 'B.zip'
$capsuleA = Join-Path $testRoot 'A/capsule.zip'
$capsuleB = Join-Path $testRoot 'B/capsule.zip'
$receiptA = Join-Path $testRoot 'A/construction-receipt.json'
$receiptB = Join-Path $testRoot 'B/construction-receipt.json'
$restoreA = Join-Path $testRoot 'restore/A'
$restoreB = Join-Path $testRoot 'restore/B'
$identity = 'mir4-t15-release-capsule-test'

try {
  foreach ($directory in @($sourceRoot, $supplyRoot, $previewRoot, $keyRoot, (Split-Path $capsuleA -Parent), (Split-Path $capsuleB -Parent), (Split-Path $restoreA -Parent))) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }
  $sourceCommit = (& git -C $repo rev-parse HEAD).Trim()
  $sourceTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  $archiveA = New-MIR4DeterministicGitSourceArchiveV1 -RepoRoot $repo -SourceCommit $sourceCommit -OutputPath $sourceA -ContainmentRoot $testRoot
  $archiveB = New-MIR4DeterministicGitSourceArchiveV1 -RepoRoot $repo -SourceCommit $sourceCommit -OutputPath $sourceB -ContainmentRoot $testRoot
  Assert-MIR4ReleaseCapsuleTest (
    [string]$archiveA.archive_sha256 -ceq [string]$archiveB.archive_sha256 -and
    [string]$archiveA.source_tree -ceq $sourceTree -and
    [string]$archiveA.content_sha256 -ceq [string]$archiveB.content_sha256
  ) 'mir4-release-capsule-source-archive-determinism'

  $preview = New-MIR4PlatformPreviewPackages -RepoRoot $repo -OutputRoot ([IO.Path]::GetRelativePath($repo, $previewRoot))
  $artifactMap = @{
    'mir4-preview-api-sdk-v1' = Join-Path $previewRoot 'mir4-api-sdk-v1-preview.zip'
    'mir4-preview-mep-v1' = Join-Path $previewRoot 'mir4-mep-v1-preview.zip'
    'mir4-preview-reference-extension-v1' = Join-Path $previewRoot 'mir4-reference-extension-v1-preview.zip'
    'mir4-preview-inspector-v1' = Join-Path $previewRoot 'mir4-inspector-v1-preview.zip'
  }
  $inventory = New-MIR4ComponentInventoryV1 -RepoRoot $repo -ArtifactPaths $artifactMap
  $spdx301 = New-MIR4Spdx301Document -Inventory $inventory
  $spdx23 = New-MIR4Spdx23CompatibilityDocument -Inventory $inventory
  $provenance = New-MIR4SlsaProvenanceV1 -Inventory $inventory
  Assert-MIR4ReleaseCapsuleTest (
    (Test-MIR4ComponentInventoryV1 -Inventory $inventory -RepoRoot $repo) -and
    (Test-MIR4Spdx301Document -Document $spdx301 -Inventory $inventory -RepoRoot $repo) -and
    (Test-MIR4Spdx23CompatibilityDocument -Document $spdx23 -RepoRoot $repo) -and
    (Test-MIR4ReleaseCapsuleProvenanceBindingV1 -Inventory $inventory -Provenance $provenance -RepoRoot $repo)
  ) 'mir4-release-capsule-supply-chain-inputs'
  $inventoryPath = Join-Path $supplyRoot 'component-inventory.json'
  $spdx301Path = Join-Path $supplyRoot 'sbom.spdx-3.0.1.json'
  $spdx23Path = Join-Path $supplyRoot 'sbom.spdx-2.3.json'
  $provenancePath = Join-Path $supplyRoot 'provenance.slsa-v1.json'
  Write-MIR4SupplyChainRecord -Record $inventory -Path $inventoryPath
  Write-MIR4SupplyChainRecord -Record $spdx301 -Path $spdx301Path
  Write-MIR4SupplyChainRecord -Record $spdx23 -Path $spdx23Path
  Write-MIR4SupplyChainRecord -Record $provenance -Path $provenancePath
  $null = New-MIR4ProofOnlyEd25519KeyPairV1 -RepoRoot $repo -SshKeygenPath $SshKeygenPath -PrivateKeyPath $privateKey -PublicKeyPath $publicKey -Identity $identity
  $attestation = New-MIR4SupplyChainAttestationV1 -RepoRoot $repo -Inventory $inventory -SlsaProvenance $provenance -SshKeygenPath $SshKeygenPath -PrivateKeyPath $privateKey -PublicKeyPath $publicKey -Identity $identity -ScratchRoot (Join-Path $testRoot 'attestation-scratch') -OutputPath $attestationPath -WorkflowRef 'refs/heads/codex/mir4-t15-supply-chain-preservation'
  Assert-MIR4ReleaseCapsuleTest (
    Test-MIR4SupplyChainAttestationV1 -RepoRoot $repo -AttestationPath $attestationPath -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $publicKey -ScratchRoot (Join-Path $testRoot 'attestation-verify') -ExpectedSourceCommit $sourceCommit -ExpectedSourceTree $sourceTree -ExpectedInventoryRecordSha256 ([string]$inventory.record_sha256) -ExpectedProvenanceSha256 (Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $provenance))
  ) 'mir4-release-capsule-attestation-input'
  $privateInventoryPath = Join-Path $supplyRoot 'private-custody-inventory.json'
  $privateInventory = New-MIR4PrivateCustodyInventoryV1 -RepoRoot $repo -OutputPath $privateInventoryPath

  $descriptors = [Collections.Generic.List[object]]::new()
  foreach ($descriptor in @(
    [pscustomobject]@{role='source-archive';logical_name='mir4-source-release.zip';path=$sourceA;media_type='application/zip';component_id='mir4-source-release'},
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
  foreach ($entry in $artifactMap.GetEnumerator()) {
    $descriptors.Add([pscustomobject]@{
      role = 'preview-asset'
      logical_name = [IO.Path]::GetFileName([string]$entry.Value)
      path = [string]$entry.Value
      media_type = 'application/zip'
      component_id = [string]$entry.Key
    })
  }
  $builtA = New-MIR4ReleaseCapsuleV1 -RepoRoot $repo -Inventory $inventory -SlsaProvenance $provenance -Attestation $attestation -ObjectDescriptors $descriptors.ToArray() -OutputRoot (Split-Path $capsuleA -Parent) -ArchivePath $capsuleA -ReceiptPath $receiptA -SshKeygenPath $SshKeygenPath
  $descriptorsB = @(
    foreach ($descriptor in $descriptors) {
      if ([string]$descriptor.role -ceq 'source-archive') {
        [pscustomobject]@{role=$descriptor.role;logical_name=$descriptor.logical_name;path=$sourceB;media_type=$descriptor.media_type;component_id=$descriptor.component_id}
      } else {
        $descriptor
      }
    }
  )
  $builtB = New-MIR4ReleaseCapsuleV1 -RepoRoot $repo -Inventory $inventory -SlsaProvenance $provenance -Attestation $attestation -ObjectDescriptors $descriptorsB -OutputRoot (Split-Path $capsuleB -Parent) -ArchivePath $capsuleB -ReceiptPath $receiptB -SshKeygenPath $SshKeygenPath
  Assert-MIR4ReleaseCapsuleTest (
    (Get-MIR4Sha256File -Path $capsuleA) -ceq (Get-MIR4Sha256File -Path $capsuleB) -and
    (Get-MIR4Sha256File -Path $receiptA) -ceq (Get-MIR4Sha256File -Path $receiptB) -and
    [string]$builtA.manifest.record_sha256 -ceq [string]$builtB.manifest.record_sha256
  ) 'mir4-release-capsule-ab-determinism'
  Assert-MIR4ReleaseCapsuleTest (
    (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -ExpectedSourceCommit $sourceCommit -ExpectedSourceTree $sourceTree -ExpectedTarget 'f210') -and
    (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -ExpectedTarget 'f200')
  ) 'mir4-release-capsule-valid'

  $restoredA = Restore-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -RestoreRoot $restoreA -ContainmentRoot (Split-Path $restoreA -Parent) -SshKeygenPath $SshKeygenPath
  $restoredB = Restore-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleB -RestoreRoot $restoreB -ContainmentRoot (Split-Path $restoreB -Parent) -SshKeygenPath $SshKeygenPath
  Assert-MIR4ReleaseCapsuleTest (
    [string]$restoredA.receipt.record_sha256 -ceq [string]$restoredB.receipt.record_sha256 -and
    @($restoredA.receipt.private_reacquisition).Count -eq 8 -and
    @($restoredA.receipt.private_reacquisition | Where-Object {
      [string]::IsNullOrWhiteSpace([string]$_.availability) -or
      [string]::IsNullOrWhiteSpace([string]$_.acquisition_requirement)
    }).Count -eq 0 -and
    -not [bool]$restoredA.receipt.private_payloads_restored -and
    [int]$restoredA.receipt.network.network_calls -eq 0 -and
    -not [bool]$restoredA.receipt.publisher.credentials_present
  ) 'mir4-release-capsule-restore-determinism-and-private-reacquisition'

  $fingerprint = [string]$attestation.payload.signing_provider.public_key_fingerprint
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -ExpectedSourceCommit ('0' * 40))
  ) 'mir4-release-capsule-wrong-source'
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -ExpectedSourceTree ('0' * 40))
  ) 'mir4-release-capsule-wrong-tree'
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -ExpectedTarget 'f110')
  ) 'mir4-release-capsule-wrong-target'
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $capsuleA -RevokedFingerprints @($fingerprint))
  ) 'mir4-release-capsule-revoked-proof-root'

  $manifest = Read-MIR4ReleaseCapsuleManifestV1 -CapsulePath $capsuleA
  $previewObject = @($manifest.objects | Where-Object role -eq 'preview-asset')[0]
  $inventoryObject = @($manifest.objects | Where-Object role -eq 'component-inventory')[0]
  $missingPath = Join-Path $testRoot 'attacks/missing-object.zip'
  $digestPath = Join-Path $testRoot 'attacks/wrong-digest.zip'
  $inventoryAttackPath = Join-Path $testRoot 'attacks/corrupt-inventory.zip'
  New-Item -ItemType Directory -Force -Path (Split-Path $missingPath -Parent) | Out-Null
  Copy-MIR4ReleaseCapsuleAttackArchive -SourcePath $capsuleA -DestinationPath $missingPath -OmitRelativePath ([string]$previewObject.path)
  Copy-MIR4ReleaseCapsuleAttackArchive -SourcePath $capsuleA -DestinationPath $digestPath -CorruptRelativePath ([string]$previewObject.path)
  Copy-MIR4ReleaseCapsuleAttackArchive -SourcePath $capsuleA -DestinationPath $inventoryAttackPath -CorruptRelativePath ([string]$inventoryObject.path)
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $missingPath)
  ) 'mir4-release-capsule-missing-object'
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $digestPath)
  ) 'mir4-release-capsule-wrong-digest'
  Assert-MIR4ReleaseCapsuleTest (
    -not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $inventoryAttackPath)
  ) 'mir4-release-capsule-corrupted-inventory'

  $manifestText = ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest
  $receiptText = ConvertTo-MIR4BootstrapCanonicalJson -Value $restoredA.receipt
  Assert-MIR4ReleaseCapsuleTest (
    $manifestText -cnotmatch [regex]::Escape($testRoot) -and
    $receiptText -cnotmatch [regex]::Escape($testRoot) -and
    $manifestText -cnotmatch '(?i)(?:OPENSSH PRIVATE KEY|passphrase|private_key_path|mod_portal_token|github_token)' -and
    $receiptText -cnotmatch '(?i)(?:OPENSSH PRIVATE KEY|passphrase|private_key_path|mod_portal_token|github_token)'
  ) 'mir4-release-capsule-private-path-and-secret-leak'
  Assert-MIR4ReleaseCapsuleTest (
    (Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq (Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo)
  ) 'mir4-release-capsule-package-non-interference'

  [pscustomobject][ordered]@{
    status = 'passed'
    capsule_sha256 = Get-MIR4Sha256File -Path $capsuleA
    capsule_content_sha256 = [string]$builtA.receipt.capsule.content_sha256
    manifest_record_sha256 = [string]$builtA.manifest.record_sha256
    restoration_record_sha256 = [string]$restoredA.receipt.record_sha256
    source_commit = $sourceCommit
    source_tree = $sourceTree
    source_archive_sha256 = [string]$archiveA.archive_sha256
    object_descriptors = @($builtA.manifest.objects).Count
    private_reacquisition_records = @($restoredA.receipt.private_reacquisition).Count
    negative_cases = @('missing-object','wrong-digest','wrong-target','wrong-source','wrong-tree','revoked-proof-root','corrupted-inventory','unavailable-private-explicit')
    package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
    production_authority = [bool]$restoredA.receipt.production_authority
    release_transition_performed = [bool]$restoredA.receipt.release_transition_performed
  }
} finally {
  $buildRoot = Join-Path $repo 'build'
  if ((Test-MIR4CustodyDescendantPathV1 -Root $buildRoot -Path $testRoot) -and
      (Test-Path -LiteralPath $testRoot -PathType Container)) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
