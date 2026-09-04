function Restore-MIR4ReleaseCapsuleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CapsulePath,
    [Parameter(Mandatory)][string]$RestoreRoot,
    [Parameter(Mandatory)][string]$ContainmentRoot,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [string[]]$RevokedFingerprints = @()
  )

  $repo = Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $RepoRoot
  if (-not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $CapsulePath -RevokedFingerprints $RevokedFingerprints)) {
    throw '[mir4-release-capsule-restore-integrity]'
  }
  $root = Assert-MIR4DescendantPath -Root $ContainmentRoot -Path $RestoreRoot
  if (Test-Path -LiteralPath $root) {
    if (@(Get-ChildItem -LiteralPath $root -Force).Count -ne 0) {
      throw '[mir4-release-capsule-restore-root-not-empty]'
    }
  } else {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
  }
  $manifest = Read-MIR4ReleaseCapsuleManifestV1 -CapsulePath $CapsulePath
  $capsuleInventory = Get-MIR4ReleaseCapsuleArchiveInventoryV1 -CapsulePath $CapsulePath
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $CapsulePath).Path)
  try {
    $uniquePaths = @($manifest.objects.path | Sort-Object -Unique -CaseSensitive)
    foreach ($relative in $uniquePaths) {
      $entryName = "$script:MIR4ReleaseCapsuleRootV1/$relative"
      $entry = @($zip.Entries | Where-Object { [string]$_.FullName -ceq $entryName })
      if ($entry.Count -ne 1) {
        throw "[mir4-release-capsule-restore-object] $relative"
      }
      $destination = Assert-MIR4DescendantPath -Root $root -Path (Join-Path $root $relative)
      $parent = Split-Path -Parent $destination
      if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
      }
      $input = $entry[0].Open()
      $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try {
        $input.CopyTo($output)
      } finally {
        $output.Dispose()
        $input.Dispose()
      }
    }
  } finally {
    $zip.Dispose()
  }

  $byRole = @{}
  foreach ($object in $manifest.objects) {
    if (-not $byRole.ContainsKey([string]$object.role)) {
      $byRole[[string]$object.role] = @()
    }
    $byRole[[string]$object.role] += $object
  }
  $getObjectPath = {
    param([string]$Role)
    $rows = @($byRole[$Role])
    if ($rows.Count -ne 1) {
      throw "[mir4-release-capsule-restore-role] $Role"
    }
    return Join-Path $root ([string]$rows[0].path)
  }

  $sourceArchivePath = & $getObjectPath 'source-archive'
  $sourceDestination = Join-Path $root 'source'
  Expand-MIR4SafeArchive -ArchivePath $sourceArchivePath -Destination $sourceDestination -OutputRoot $root -MaxEntries 100000 -MaxEntryBytes 268435456 -MaxExpandedBytes 1073741824 | Out-Null
  $restoredSource = Join-Path $sourceDestination 'mir4-source'
  if (-not (Test-Path -LiteralPath $restoredSource -PathType Container)) {
    throw '[mir4-release-capsule-restored-source]'
  }
  $inventory = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'component-inventory')
  $spdx301 = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'sbom-spdx-3.0.1') -MaximumBytes 134217728
  $spdx23 = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'sbom-spdx-2.3') -MaximumBytes 134217728
  $provenance = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'provenance-slsa-v1')
  $attestationPath = & $getObjectPath 'supply-chain-attestation'
  $attestation = Read-MIR4ReleaseCapsuleJsonV1 -Path $attestationPath
  $publicKeyPath = & $getObjectPath 'proof-public-key'
  $privateInventory = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'rights-custody-inventory')
  $proof = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'proof-closure-summary')
  $sourceEnvelope = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'source-archive-envelope')
  $restoreInstructions = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'restore-instructions')
  $sourceReleaseRecord = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'source-release-record')
  $targetRecordSet = Read-MIR4ReleaseCapsuleJsonV1 -Path (& $getObjectPath 'target-distribution-record-set')
  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $inventory) -or
      -not (Test-MIR4ReleaseCapsuleProvenanceBindingV1 -Inventory $inventory -Provenance $provenance -RepoRoot $repo) -or
      -not (Test-MIR4BootstrapRecordHash -Record $privateInventory) -or
      -not (Test-MIR4BootstrapRecordHash -Record $proof) -or
      -not (Test-MIR4BootstrapRecordHash -Record $sourceEnvelope) -or
      -not (Test-MIR4BootstrapRecordHash -Record $restoreInstructions)) {
    throw '[mir4-release-capsule-restored-record-binding]'
  }
  $expectedSpdx301 = New-MIR4Spdx301Document -Inventory $inventory
  $expectedSpdx23 = New-MIR4Spdx23CompatibilityDocument -Inventory $inventory
  if (-not (Test-MIR4Spdx301Document -Document $spdx301 -Inventory $inventory -RepoRoot $repo) -or
      -not (Test-MIR4Spdx23CompatibilityDocument -Document $spdx23 -RepoRoot $repo) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $spdx301) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedSpdx301) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $spdx23) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $expectedSpdx23)) {
    throw '[mir4-release-capsule-sbom-binding]'
  }
  $expectedSpdx301 = $null
  $expectedSpdx23 = $null
  if ([string]$restoreInstructions.kind -cne 'MIR4ReleaseCapsuleRestoreInstructionsV1' -or
      [string]$restoreInstructions.network_policy -cne 'disabled' -or
      [bool]$restoreInstructions.mutable_github_state_required -or
      [bool]$restoreInstructions.production_authority -or
      [string]$sourceReleaseRecord.kind -cne 'MIR4PostReadinessMergeReceiptSOL15V1' -or
      [string]$targetRecordSet.kind -cne 'MIR4PreFreezeDevelopmentPlanV1') {
    throw '[mir4-release-capsule-operational-records]'
  }
  $privateJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $privateInventory
  if (-not ($privateJson | Test-Json -SchemaFile (Join-Path $repo $script:MIR4PrivateCustodyInventorySchemaV1) -ErrorAction Stop) -or
      [bool]$privateInventory.private_payloads_embedded -or
      @($privateInventory.entries | Where-Object { [bool]$_.payload_embedded }).Count -ne 0) {
    throw '[mir4-release-capsule-private-inventory]'
  }
  if ([string]$sourceEnvelope.source_commit -cne [string]$manifest.source.commit -or
      [string]$sourceEnvelope.source_tree -cne [string]$manifest.source.tree -or
      [string]$sourceEnvelope.archive_sha256 -cne [string]$byRole['source-archive'][0].sha256) {
    throw '[mir4-release-capsule-source-envelope-binding]'
  }

  foreach ($set in $inventory.identity_sets) {
    foreach ($file in $set.files) {
      $path = Assert-MIR4DescendantPath -Root $restoredSource -Path (Join-Path $restoredSource ([string]$file.path))
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
          (Get-MIR4Sha256File -Path $path) -cne [string]$file.sha256) {
        throw "[mir4-release-capsule-identity-set] $($set.name):$($file.path)"
      }
    }
  }
  foreach ($componentId in @('mir4-source-release', 'mir4-player-f210', 'mir4-player-f200')) {
    $component = @($inventory.components | Where-Object { [string]$_.component_id -ceq $componentId })
    if ($component.Count -ne 1) {
      throw "[mir4-release-capsule-source-component] $componentId"
    }
    foreach ($file in $component[0].files) {
      $path = Assert-MIR4DescendantPath -Root $restoredSource -Path (Join-Path $restoredSource ([string]$file.path))
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
          (Get-MIR4Sha256File -Path $path) -cne [string]$file.sha256) {
        throw ("[mir4-release-capsule-source-component] {0}:{1}" -f $componentId, [string]$file.path)
      }
    }
  }

  $provenanceSha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $provenance)
  $scratch = Join-Path $root 'attestation-scratch'
  if (-not (Test-MIR4SupplyChainAttestationV1 -RepoRoot $repo -AttestationPath $attestationPath -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath $publicKeyPath -ScratchRoot $scratch -ExpectedSourceCommit ([string]$manifest.source.commit) -ExpectedSourceTree ([string]$manifest.source.tree) -ExpectedInventoryRecordSha256 ([string]$inventory.record_sha256) -ExpectedProvenanceSha256 $provenanceSha256 -RevokedFingerprints $RevokedFingerprints)) {
    throw '[mir4-release-capsule-attestation-verification]'
  }
  foreach ($preview in @($byRole['preview-asset'])) {
    $path = Join-Path $root ([string]$preview.path)
    $subject = @($attestation.payload.subjects | Where-Object {
      [string]$_.name -ceq [string]$preview.component_id
    })
    if (-not (Test-MIR4PreviewAssetArchiveV1 -Path $path -ExpectedCommit ([string]$manifest.source.commit) -ExpectedTree ([string]$manifest.source.tree))) {
      throw "[mir4-release-capsule-preview] $($preview.logical_name)"
    }
    if ($subject.Count -ne 1 -or
        [string]$subject[0].digest.sha256 -cne ([string]$preview.sha256).ToLowerInvariant()) {
      throw "[mir4-release-capsule-preview-attestation] $($preview.component_id)"
    }
  }
  if ([string]$proof.component_inventory_root -cne [string]$inventory.record_sha256 -or
      [string]$proof.provenance_sha256 -cne $provenanceSha256 -or
      [string]$proof.attestation_record_sha256 -cne [string]$attestation.record_sha256 -or
      [int]$proof.evidence_index.preview_asset_count -ne 4) {
    throw '[mir4-release-capsule-proof-closure]'
  }

  $dummyPublisher = Test-MIR4RestoredPublisherAdmissionV1 -RestoredSourceRoot $restoredSource -CapsuleSha256 ([string]$capsuleInventory.archive_sha256)
  $dummyPath = Join-Path $root 'receipts/dummy-publisher-admission.json'
  Write-MIR4ReleaseCapsuleRecordV1 -Record $dummyPublisher -Path $dummyPath -AppendOnly
  $reacquisition = @(
    $privateInventory.entries |
      Sort-Object object_id -CaseSensitive |
      ForEach-Object {
        [pscustomobject][ordered]@{
          object_id = [string]$_.object_id
          availability = [string]$_.availability
          acquisition_requirement = [string]$_.acquisition_requirement
        }
      }
  )
  $receipt = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseCapsuleRestorationReceiptV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    operation = 'restore'
    status = 'passed-public-safe-private-reacquisition-explicit'
    capsule = [pscustomobject][ordered]@{
      archive_sha256 = [string]$capsuleInventory.archive_sha256
      content_sha256 = [string]$capsuleInventory.content_sha256
      manifest_record_sha256 = [string]$manifest.record_sha256
    }
    source = [pscustomobject][ordered]@{
      commit = [string]$manifest.source.commit
      tree = [string]$manifest.source.tree
      restored = $true
      exact_identity_sets_verified = $true
    }
    targets = @(
      [pscustomobject][ordered]@{target='f210';status='verified-prefreeze-package-source'}
      [pscustomobject][ordered]@{target='f200';status='verified-prefreeze-package-source'}
    )
    checks = [pscustomobject][ordered]@{
      capsule_integrity = $true
      source_archive = $true
      contracts_and_toolchain = $true
      target_package_source = $true
      preview_assets = $true
      sbom_provenance = $true
      attestation_signature = $true
      revocation = $true
      proof_index = $true
      publisher_dummy_admission = $true
    }
    network = [pscustomobject][ordered]@{
      policy = 'disabled'
      mutable_github_state_used = $false
      network_calls = 0
    }
    publisher = [pscustomobject][ordered]@{
      dummy_admission_record_sha256 = [string]$dummyPublisher.record_sha256
      credentials_present = $false
      production_authority = $false
    }
    private_reacquisition = $reacquisition
    private_payloads_restored = $false
    output_was_empty = $true
    production_authority = $false
    release_transition_performed = $false
    record_sha256 = $null
  }
  $receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
  $receiptJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt
  if (-not ($receiptJson | Test-Json -SchemaFile (Join-Path $repo $script:MIR4ReleaseCapsuleRestorationSchemaV1) -ErrorAction Stop)) {
    throw '[mir4-release-capsule-restoration-schema]'
  }
  $receiptPath = Join-Path $root 'receipts/restoration-receipt.json'
  Write-MIR4ReleaseCapsuleRecordV1 -Record $receipt -Path $receiptPath -AppendOnly
  return [pscustomobject][ordered]@{
    receipt = $receipt
    receipt_path = $receiptPath
    restored_source_root = $restoredSource
  }
}
