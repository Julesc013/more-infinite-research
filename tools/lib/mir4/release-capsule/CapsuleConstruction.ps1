function New-MIR4ReleaseCapsuleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Inventory,
    [Parameter(Mandatory)]$SlsaProvenance,
    [Parameter(Mandatory)]$Attestation,
    [Parameter(Mandatory)][object[]]$ObjectDescriptors,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [string]$SshKeygenPath = 'C:/Windows/System32/OpenSSH/ssh-keygen.exe'
  )

  $repo = Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $RepoRoot
  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory -RepoRoot $repo)) {
    throw '[mir4-release-capsule-inventory]'
  }
  if (-not (Test-MIR4ReleaseCapsuleProvenanceBindingV1 -Inventory $Inventory -Provenance $SlsaProvenance -RepoRoot $repo)) {
    throw '[mir4-release-capsule-provenance]'
  }
  if (-not (Test-MIR4BootstrapRecordHash -Record $Attestation) -or
      [string]$Attestation.kind -cne 'MIR4SupplyChainAttestationV1') {
    throw '[mir4-release-capsule-attestation]'
  }
  $output = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $repo -Path $OutputRoot -Label 'Release capsule output root'
  if (-not (Test-Path -LiteralPath $output -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $output | Out-Null
  }
  $archive = Assert-MIR4DescendantPath -Root $output -Path $ArchivePath
  $receipt = Assert-MIR4DescendantPath -Root $output -Path $ReceiptPath
  $descriptorRows = @(Get-MIR4ReleaseCapsuleDescriptorRowsV1 -ObjectDescriptors $ObjectDescriptors)
  $descriptorByRole = @{}
  foreach ($row in $descriptorRows) {
    if (-not $descriptorByRole.ContainsKey([string]$row.role)) {
      $descriptorByRole[[string]$row.role] = @()
    }
    $descriptorByRole[[string]$row.role] += $row
  }
  foreach ($binding in @(
    [pscustomobject]@{role='component-inventory';value=$Inventory},
    [pscustomobject]@{role='provenance-slsa-v1';value=$SlsaProvenance},
    [pscustomobject]@{role='supply-chain-attestation';value=$Attestation}
  )) {
    $rows = @($descriptorByRole[[string]$binding.role])
    if ($rows.Count -ne 1) { throw "[mir4-release-capsule-input-role] $($binding.role)" }
    $fileValue = Read-MIR4ReleaseCapsuleJsonV1 -Path ([string]$rows[0].source_path) -MaximumBytes 134217728
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $fileValue) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value $binding.value)) {
      throw "[mir4-release-capsule-input-binding] $($binding.role)"
    }
  }
  $spdx301Rows = @($descriptorByRole['sbom-spdx-3.0.1'])
  $spdx23Rows = @($descriptorByRole['sbom-spdx-2.3'])
  if ($spdx301Rows.Count -ne 1 -or $spdx23Rows.Count -ne 1) {
    throw '[mir4-release-capsule-sbom-role]'
  }
  $spdx301 = Read-MIR4ReleaseCapsuleJsonV1 -Path ([string]$spdx301Rows[0].source_path) -MaximumBytes 134217728
  $spdx23 = Read-MIR4ReleaseCapsuleJsonV1 -Path ([string]$spdx23Rows[0].source_path) -MaximumBytes 134217728
  if (-not (Test-MIR4Spdx301Document -Document $spdx301 -Inventory $Inventory -RepoRoot $repo) -or
      -not (Test-MIR4Spdx23CompatibilityDocument -Document $spdx23 -RepoRoot $repo) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $spdx301) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value (New-MIR4Spdx301Document -Inventory $Inventory)) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $spdx23) -cne
        (ConvertTo-MIR4BootstrapCanonicalJson -Value (New-MIR4Spdx23CompatibilityDocument -Inventory $Inventory))) {
    throw '[mir4-release-capsule-sbom-binding]'
  }
  $privateRows = @($descriptorByRole['rights-custody-inventory'])
  $sourceRecordRows = @($descriptorByRole['source-release-record'])
  $targetRecordRows = @($descriptorByRole['target-distribution-record-set'])
  if ($privateRows.Count -ne 1 -or $sourceRecordRows.Count -ne 1 -or $targetRecordRows.Count -ne 1) {
    throw '[mir4-release-capsule-operational-role]'
  }
  $privateInventory = Read-MIR4ReleaseCapsuleJsonV1 -Path ([string]$privateRows[0].source_path)
  $sourceReleaseRecord = Read-MIR4ReleaseCapsuleJsonV1 -Path ([string]$sourceRecordRows[0].source_path)
  $targetRecordSet = Read-MIR4ReleaseCapsuleJsonV1 -Path ([string]$targetRecordRows[0].source_path)
  if (-not (Test-MIR4BootstrapRecordHash -Record $privateInventory) -or
      -not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $privateInventory) |
        Test-Json -SchemaFile (Join-Path $repo $script:MIR4PrivateCustodyInventorySchemaV1) -ErrorAction Stop) -or
      [string]$sourceReleaseRecord.kind -cne 'MIR4PostReadinessMergeReceiptSOL15V1' -or
      [string]$targetRecordSet.kind -cne 'MIR4PreFreezeDevelopmentPlanV1') {
    throw '[mir4-release-capsule-operational-records]'
  }
  $publicKeyRows = @($descriptorByRole['proof-public-key'])
  if ($publicKeyRows.Count -ne 1 -or
      -not (Test-MIR4SupplyChainAttestationV1 -RepoRoot $repo -AttestationPath ([string]$descriptorByRole['supply-chain-attestation'][0].source_path) -SshKeygenPath $SshKeygenPath -TrustedPublicKeyPath ([string]$publicKeyRows[0].source_path) -ScratchRoot (Join-Path $output 'attestation-construction-verification') -ExpectedSourceCommit ([string]$Inventory.source.commit) -ExpectedSourceTree ([string]$Inventory.source.tree) -ExpectedWorkflowRef ([string]$Attestation.payload.workflow.ref) -ExpectedInventoryRecordSha256 ([string]$Inventory.record_sha256) -ExpectedProvenanceSha256 (Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $SlsaProvenance)))) {
    throw '[mir4-release-capsule-attestation-verification]'
  }
  foreach ($preview in @($descriptorByRole['preview-asset'])) {
    $subject = @($Attestation.payload.subjects | Where-Object {
      [string]$_.name -ceq [string]$preview.component_id
    })
    if (-not (Test-MIR4PreviewAssetArchiveV1 -Path ([string]$preview.source_path) -ExpectedCommit ([string]$Inventory.source.commit) -ExpectedTree ([string]$Inventory.source.tree)) -or
        $subject.Count -ne 1 -or
        [string]$subject[0].digest.sha256 -cne ([string]$preview.sha256).ToLowerInvariant()) {
      throw "[mir4-release-capsule-preview-binding] $($preview.logical_name)"
    }
  }
  foreach ($row in $descriptorRows) {
    if ($null -eq $row.component_id) { continue }
    $component = @($Inventory.components | Where-Object { [string]$_.component_id -ceq [string]$row.component_id })
    if ($component.Count -ne 1) {
      throw "[mir4-release-capsule-component] $($row.component_id)"
    }
    if ($null -ne $component[0].artifact -and
        [string]$component[0].artifact.sha256 -cne [string]$row.sha256) {
      throw "[mir4-release-capsule-component-artifact] $($row.component_id)"
    }
  }
  $supportRoot = Join-Path $output 'support'
  if (-not (Test-Path -LiteralPath $supportRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $supportRoot | Out-Null
  }
  $support = New-MIR4ReleaseCapsuleSupportRecordsV1 -RepoRoot $repo -Inventory $Inventory -SlsaProvenance $SlsaProvenance -Attestation $Attestation -DescriptorRows $descriptorRows -OutputRoot $supportRoot
  $supportDescriptors = @(
    [pscustomobject]@{
      role = 'source-archive-envelope'
      logical_name = 'mir4-source-archive-envelope.json'
      path = $support.source_envelope
      media_type = 'application/vnd.mir4.source-envelope+json'
    }
    [pscustomobject]@{
      role = 'proof-closure-summary'
      logical_name = 'mir4-proof-closure-summary.json'
      path = $support.proof_closure
      media_type = 'application/vnd.mir4.proof-closure+json'
    }
    [pscustomobject]@{
      role = 'restore-instructions'
      logical_name = 'mir4-restore-instructions.json'
      path = $support.restore_instructions
      media_type = 'application/vnd.mir4.restore-instructions+json'
    }
  )
  $descriptorRows = @($descriptorRows + @(Get-MIR4ReleaseCapsuleDescriptorRowsV1 -ObjectDescriptors $supportDescriptors))
  if (-not (Test-MIR4ReleaseCapsuleRoleClosureV1 -Objects $descriptorRows)) {
    throw '[mir4-release-capsule-role-closure]'
  }
  $objects = @(
    $descriptorRows |
      Sort-Object role, logical_name -CaseSensitive |
      ForEach-Object {
        [pscustomobject][ordered]@{
          object_id = [string]$_.object_id
          role = [string]$_.role
          logical_name = [string]$_.logical_name
          media_type = [string]$_.media_type
          component_id = $_.component_id
          target = $_.target
          sha256 = [string]$_.sha256
          bytes = [long]$_.bytes
          path = [string]$_.path
          required_for_restore = [bool]$_.required_for_restore
        }
      }
  )
  $identitySets = @(
    $Inventory.identity_sets |
      Sort-Object name -CaseSensitive |
      ForEach-Object {
        [pscustomobject][ordered]@{
          name = [string]$_.name
          root_sha256 = [string]$_.root_sha256
          file_count = [int]$_.file_count
        }
      }
  )
  $targets = @(
    foreach ($targetKey in @('f210', 'f200')) {
      $component = @($Inventory.components | Where-Object { [string]$_.target -ceq $targetKey })
      $attested = @($Attestation.payload.targets | Where-Object { [string]$_.target -ceq $targetKey })
      if ($component.Count -ne 1 -or $attested.Count -ne 1) {
        throw "[mir4-release-capsule-target] $targetKey"
      }
      [pscustomobject][ordered]@{
        target = $targetKey
        component_id = [string]$component[0].component_id
        distribution_version = [string]$component[0].version
        materialization = [string]$component[0].materialization
        content_sha256 = [string]$attested[0].sha256
        publication_intent = $false
      }
    }
  )
  $privateObject = @($objects | Where-Object role -eq 'rights-custody-inventory')
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseCapsuleManifestV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    status = 'non-production-prefreeze-portable-capsule'
    source = [pscustomobject][ordered]@{
      repository = 'Julesc013/more-infinite-research'
      commit = [string]$Inventory.source.commit
      tree = [string]$Inventory.source.tree
      tag_plan = [pscustomobject][ordered]@{
        tag = 'v4.0.0'
        allocated = $false
        authorized = $false
      }
    }
    identity_sets = $identitySets
    targets = $targets
    objects = $objects
    partitions = [pscustomobject][ordered]@{
      public_safe = [pscustomobject][ordered]@{
        embedded = $true
        descriptor_count = [int]$objects.Count
        unique_payload_count = [int]@($objects.path | Sort-Object -Unique -CaseSensitive).Count
      }
      private_custody = [pscustomobject][ordered]@{
        payloads_embedded = $false
        inventory_object_sha256 = [string]$privateObject[0].sha256
        credential_values_embedded = $false
        private_keys_embedded = $false
      }
    }
    proof_closure = [pscustomobject][ordered]@{
      component_inventory_root = [string]$Inventory.record_sha256
      provenance_sha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $SlsaProvenance)
      attestation_record_sha256 = [string]$Attestation.record_sha256
      public_key_fingerprint = [string]$Attestation.payload.signing_provider.public_key_fingerprint
      revocation_source_commit = [string]$Attestation.payload.revocation_snapshot.source_commit
    }
    publication_intents = [pscustomobject][ordered]@{
      source_release = $false
      f210 = $false
      f200 = $false
      developer_previews = $false
    }
    restore = [pscustomobject][ordered]@{
      network_required = $false
      mutable_github_state_required = $false
      clean_root_required = $true
      dummy_publisher_only = $true
      private_reacquisition_explicit = $true
    }
    transition_authority = [pscustomobject][ordered]@{
      source_freeze = $false
      candidate_allocation = $false
      production_signing = $false
      production_seal = $false
      promotion_to_main = $false
      tagging = $false
      publication = $false
    }
    record_sha256 = $null
  }
  $manifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $manifest
  $manifestJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest
  if (-not ($manifestJson | Test-Json -SchemaFile (Join-Path $repo $script:MIR4ReleaseCapsuleManifestSchemaV1) -ErrorAction Stop)) {
    throw '[mir4-release-capsule-manifest-schema]'
  }
  if ($manifestJson -match '(?i)(?:OPENSSH PRIVATE KEY|passphrase|private_key_path|mod_portal_token|github_token)' -or
      $manifestJson -match '(?i)[A-Z]:[\\/]Users[\\/]') {
    throw '[mir4-release-capsule-manifest-private-leak]'
  }

  $staging = Join-Path $output ('staging-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $staging 'metadata') | Out-Null
  try {
    Write-MIR4ReleaseCapsuleRecordV1 -Record $manifest -Path (Join-Path $staging 'metadata/capsule-manifest.json')
    $copied = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $descriptorRows) {
      if (-not $copied.Add([string]$row.path)) { continue }
      $destination = Join-Path $staging ([string]$row.path)
      $parent = Split-Path -Parent $destination
      if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
      }
      $input = [IO.File]::OpenRead([string]$row.source_path)
      $outputStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      try {
        $input.CopyTo($outputStream)
      } finally {
        $outputStream.Dispose()
        $input.Dispose()
      }
    }
    $temporaryArchive = $archive + '.new'
    Write-MIR4DeterministicRawTreeArchive -SourceRoot $staging -EntryRoot $script:MIR4ReleaseCapsuleRootV1 -OutputPath $temporaryArchive -ContainmentRoot $output
    if (Test-Path -LiteralPath $archive -PathType Leaf) {
      if ((Get-MIR4Sha256File -Path $archive) -cne (Get-MIR4Sha256File -Path $temporaryArchive)) {
        throw '[mir4-release-capsule-archive-append-only-conflict]'
      }
      Remove-Item -LiteralPath $temporaryArchive -Force
    } else {
      Move-Item -LiteralPath $temporaryArchive -Destination $archive
    }
  } finally {
    if (Test-MIR4CustodyDescendantPathV1 -Root $output -Path $staging) {
      if (Test-Path -LiteralPath $staging -PathType Container) {
        Remove-Item -LiteralPath $staging -Recurse -Force
      }
    }
  }
  if (-not (Test-MIR4ReleaseCapsuleV1 -RepoRoot $repo -CapsulePath $archive -ExpectedSourceCommit ([string]$Inventory.source.commit) -ExpectedSourceTree ([string]$Inventory.source.tree))) {
    throw '[mir4-release-capsule-independent-verification]'
  }
  $archiveInventory = Get-MIR4ReleaseCapsuleArchiveInventoryV1 -CapsulePath $archive
  $construction = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseCapsuleConstructionReceiptV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    operation = 'construct'
    status = 'passed'
    capsule = [pscustomobject][ordered]@{
      archive_sha256 = [string]$archiveInventory.archive_sha256
      content_sha256 = [string]$archiveInventory.content_sha256
      bytes = [long]$archiveInventory.bytes
      entry_count = [int]$archiveInventory.entry_count
      manifest_record_sha256 = [string]$manifest.record_sha256
    }
    source = [pscustomobject][ordered]@{
      commit = [string]$Inventory.source.commit
      tree = [string]$Inventory.source.tree
    }
    object_descriptor_count = [int]$objects.Count
    unique_payload_count = [int]@($objects.path | Sort-Object -Unique -CaseSensitive).Count
    construction = [pscustomobject][ordered]@{
      network = 'disabled'
      path_order = 'ordinal'
      timestamp = '1980-01-01T00:00:00Z'
      zip_dos_timestamp = '1980-01-01T00:00:00'
      timestamp_projection = 'normalized-utc-policy-instant-to-timezone-free-zip-dos-clock'
      permissions = 0
      append_only_receipt = $true
    }
    production_authority = $false
    release_transition_performed = $false
    record_sha256 = $null
  }
  $construction.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $construction
  $constructionJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $construction
  if (-not ($constructionJson | Test-Json -SchemaFile (Join-Path $repo $script:MIR4ReleaseCapsuleConstructionSchemaV1) -ErrorAction Stop)) {
    throw '[mir4-release-capsule-construction-schema]'
  }
  Write-MIR4ReleaseCapsuleRecordV1 -Record $construction -Path $receipt -AppendOnly
  return [pscustomobject][ordered]@{
    manifest = $manifest
    receipt = $construction
    archive_path = $archive
    receipt_path = $receipt
  }
}
