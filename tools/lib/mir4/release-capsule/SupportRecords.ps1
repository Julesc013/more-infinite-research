function New-MIR4ReleaseCapsuleSupportRecordsV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Inventory,
    [Parameter(Mandatory)]$SlsaProvenance,
    [Parameter(Mandatory)]$Attestation,
    [Parameter(Mandatory)][object[]]$DescriptorRows,
    [Parameter(Mandatory)][string]$OutputRoot
  )

  $sourceObject = @($DescriptorRows | Where-Object { [string]$_.role -ceq 'source-archive' })
  if ($sourceObject.Count -ne 1) { throw '[mir4-release-capsule-source-object]' }
  $sourceEnvelope = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4GitSourceArchiveEnvelopeV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    repository = 'Julesc013/more-infinite-research'
    source_commit = [string]$Inventory.source.commit
    source_tree = [string]$Inventory.source.tree
    archive_sha256 = [string]$sourceObject[0].sha256
    archive_bytes = [long]$sourceObject[0].bytes
    archive_root = 'mir4-source'
    network_required = $false
    record_sha256 = $null
  }
  $sourceEnvelope.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $sourceEnvelope
  $sourceEnvelopePath = Join-Path $OutputRoot 'source-archive-envelope.json'
  Write-MIR4ReleaseCapsuleRecordV1 -Record $sourceEnvelope -Path $sourceEnvelopePath -AppendOnly

  $roleRoots = @(
    $DescriptorRows |
      Sort-Object role, logical_name -CaseSensitive |
      ForEach-Object {
        [pscustomobject][ordered]@{
          role = [string]$_.role
          logical_name = [string]$_.logical_name
          sha256 = [string]$_.sha256
        }
      }
  )
  $proof = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseCapsuleProofClosureV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    source = [pscustomobject][ordered]@{
      commit = [string]$Inventory.source.commit
      tree = [string]$Inventory.source.tree
    }
    component_inventory_root = [string]$Inventory.record_sha256
    provenance_sha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $SlsaProvenance)
    attestation_record_sha256 = [string]$Attestation.record_sha256
    attestation_payload_root = [string]$Attestation.payload.record_sha256
    public_key_fingerprint = [string]$Attestation.payload.signing_provider.public_key_fingerprint
    role_roots = $roleRoots
    evidence_index = [pscustomobject][ordered]@{
      source_release_record_present = @($DescriptorRows | Where-Object role -eq 'source-release-record').Count -eq 1
      target_distribution_record_set_present = @($DescriptorRows | Where-Object role -eq 'target-distribution-record-set').Count -eq 1
      preview_asset_count = @($DescriptorRows | Where-Object role -eq 'preview-asset').Count
      supply_chain_attestation_verified_before_capsule = $true
    }
    gameplay_proof_separate = $true
    source_freeze_authorized = $false
    publication_authorized = $false
    record_sha256 = $null
  }
  $proof.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $proof
  $proofPath = Join-Path $OutputRoot 'proof-closure-summary.json'
  Write-MIR4ReleaseCapsuleRecordV1 -Record $proof -Path $proofPath -AppendOnly

  $restore = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseCapsuleRestoreInstructionsV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    network_policy = 'disabled'
    mutable_github_state_required = $false
    clean_root_required = $true
    command = 'pwsh -NoProfile -File tools/commands/mir4/Invoke-MIR4ReleaseCapsule.ps1 -Mode Restore -CapsulePath <capsule.zip> -RestoreRoot <empty-root> -SshKeygenPath <exact-ssh-keygen>'
    verification = @(
      'capsule-fixity',
      'source-and-identity-sets',
      'target-package-source',
      'preview-assets',
      'sbom-and-provenance',
      'attestation-and-revocation',
      'proof-index',
      'publisher-dummy-admission',
      'private-reacquisition-index'
    )
    private_payload_policy = 'No private payload is embedded; missing required private objects remain explicit acquisition requirements.'
    production_authority = $false
    record_sha256 = $null
  }
  $restore.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $restore
  $restorePath = Join-Path $OutputRoot 'restore-instructions.json'
  Write-MIR4ReleaseCapsuleRecordV1 -Record $restore -Path $restorePath -AppendOnly

  return [pscustomobject][ordered]@{
    source_envelope = $sourceEnvelopePath
    proof_closure = $proofPath
    restore_instructions = $restorePath
  }
}

function Get-MIR4ReleaseCapsuleArchiveInventoryV1 {
  param([Parameter(Mandatory)][string]$CapsulePath)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $CapsulePath).Path
  $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $rows = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $zip.Entries) {
      if ([string]::IsNullOrEmpty($entry.Name)) { throw '[mir4-release-capsule-directory-entry]' }
      $name = [string]$entry.FullName
      Assert-MIR4PortableArchivePath -Path $name
      if (-not $name.StartsWith($script:MIR4ReleaseCapsuleRootV1 + '/', [StringComparison]::Ordinal)) {
        throw "[mir4-release-capsule-root] $name"
      }
      if (-not $seen.Add($name)) { throw "[mir4-release-capsule-colliding-entry] $name" }
      $stream = $entry.Open()
      try { $sha256 = Get-MIR4ReleaseCapsuleStreamSha256V1 -Stream $stream } finally { $stream.Dispose() }
      $rows.Add([pscustomobject][ordered]@{
        path = $name.Substring($script:MIR4ReleaseCapsuleRootV1.Length + 1)
        bytes = [long]$entry.Length
        sha256 = $sha256
        zip_dos_timestamp = $entry.LastWriteTime.DateTime.ToString('yyyy-MM-ddTHH:mm:ss')
        external_attributes = [int]$entry.ExternalAttributes
      })
    }
    if ($rows.Count -eq 0) { throw '[mir4-release-capsule-empty]' }
    $actualOrder = @($rows | ForEach-Object { [string]$_.path })
    $sortedOrder = @($actualOrder | Sort-Object -CaseSensitive)
    if (($actualOrder -join [char]0) -cne ($sortedOrder -join [char]0)) {
      throw '[mir4-release-capsule-entry-order]'
    }
    $identityRows = @($rows | ForEach-Object { "$($_.path)$([char]9)$($_.bytes)$([char]9)$($_.sha256)" })
    return [pscustomobject][ordered]@{
      root = $script:MIR4ReleaseCapsuleRootV1
      archive_sha256 = Get-MIR4Sha256File -Path $resolved
      content_sha256 = Get-MIR4Sha256String -Value ($identityRows -join [char]10)
      bytes = [long](Get-Item -LiteralPath $resolved).Length
      entry_count = [int]$rows.Count
      entries = $rows.ToArray()
    }
  } finally {
    $zip.Dispose()
  }
}
