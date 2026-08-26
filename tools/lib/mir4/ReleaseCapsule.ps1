Set-StrictMode -Version Latest

if (-not (Get-Command Get-MIR4ArchiveInventory -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')
}
if (-not (Get-Command New-MIR4ComponentInventoryV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'SupplyChain.ps1')
}
if (-not (Get-Command Test-MIR4SupplyChainAttestationV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'SupplyChainAttestation.ps1')
}

$script:MIR4ReleaseCapsuleRootV1 = 'mir4-release-capsule'
$script:MIR4ReleaseCapsuleManifestSchemaV1 = 'spec/schemas/mir4-release-capsule-manifest-v1.schema.json'
$script:MIR4PrivateCustodyInventorySchemaV1 = 'spec/schemas/mir4-private-custody-inventory-v1.schema.json'
$script:MIR4ReleaseCapsuleConstructionSchemaV1 = 'spec/schemas/mir4-release-capsule-construction-receipt-v1.schema.json'
$script:MIR4ReleaseCapsuleRestorationSchemaV1 = 'spec/schemas/mir4-release-capsule-restoration-receipt-v1.schema.json'

function Get-MIR4ReleaseCapsuleRepoRootV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Write-MIR4ReleaseCapsuleRecordV1 {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string]$Path,
    [switch]$AppendOnly
  )

  $text = (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record) + [char]10
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  if ($AppendOnly -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $existing = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    if (-not [Linq.Enumerable]::SequenceEqual([byte[]]$existing, [byte[]]$bytes)) {
      throw "[mir4-release-capsule-append-only-conflict] $Path"
    }
    return
  }
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Read-MIR4ReleaseCapsuleJsonV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(1, 134217728)][long]$MaximumBytes = 16777216
  )

  $item = Get-Item -LiteralPath (Resolve-Path -LiteralPath $Path).Path
  if ([long]$item.Length -gt $MaximumBytes) {
    throw "[mir4-release-capsule-json-bounds] $Path"
  }
  $utf8 = [Text.UTF8Encoding]::new($false, $true)
  return $utf8.GetString([IO.File]::ReadAllBytes($item.FullName)) |
    ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-MIR4ReleaseCapsuleObjectPathV1 {
  param([Parameter(Mandatory)][string]$Sha256)
  $digest = $Sha256.ToUpperInvariant()
  if ($digest -cnotmatch '^[0-9A-F]{64}$') {
    throw '[mir4-release-capsule-object-digest]'
  }
  return "objects/sha256/$($digest.Substring(0, 2))/$digest"
}

function Get-MIR4ReleaseCapsuleStreamSha256V1 {
  param([Parameter(Mandatory)][IO.Stream]$Stream)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return [Convert]::ToHexString($sha.ComputeHash($Stream))
  } finally {
    $sha.Dispose()
  }
}

function New-MIR4PrivateCustodyInventoryV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$OutputPath
  )

  $repo = Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $RepoRoot
  $planPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV3.json'
  $plan = Read-MIR4ReleaseCapsuleJsonV1 -Path $planPath
  $engines = @(
    foreach ($targetKey in @('f210', 'f200')) {
      $target = @($plan.targets | Where-Object { [string]$_.target_key -ceq $targetKey })
      if ($target.Count -ne 1) { throw "[mir4-private-custody-target] $targetKey" }
      [pscustomobject][ordered]@{
        object_id = "factorio-engine-$targetKey"
        object_class = 'factorio-engine'
        target = $targetKey
        version = [string]$target[0].engine_lock.version
        expected_sha256 = [string]$target[0].engine_lock.executable_sha256
        custody_class = 'external-private-engine-custody'
        rights_class = 'third-party-license-no-redistribution-asserted'
        availability = 'maintainer-custody-or-authorized-reacquisition-required'
        acquisition_requirement = 'Use the exact maintainer-authorized installed engine or reacquire it through the publisher-authorized channel; never download or retarget a historical Steam depot.'
        payload_embedded = $false
        encrypted_store_required = $false
      }
    }
  )
  $entries = @(
    $engines
    [pscustomobject][ordered]@{
      object_id = 'third-party-mod-closures'
      object_class = 'third-party-mod-archives'
      target = $null
      version = $null
      expected_sha256 = $null
      custody_class = 'external-private-mod-closure-custody'
      rights_class = 'per-mod-rights-not-invented'
      availability = 'exact-target-lock-must-resolve-before-qualification'
      acquisition_requirement = 'Resolve each exact target environment lock through its separately governed acquisition record; do not redistribute without named permission.'
      payload_embedded = $false
      encrypted_store_required = $false
    }
    [pscustomobject][ordered]@{
      object_id = 'unredacted-evidence'
      object_class = 'unredacted-evidence'
      target = $null
      version = $null
      expected_sha256 = $null
      custody_class = 'external-private-evidence-custody'
      rights_class = 'public-redacted-projection-only'
      availability = 'private-proof-store-required-when-applicable'
      acquisition_requirement = 'Use the immutable private proof object named by the accepted evidence receipt.'
      payload_embedded = $false
      encrypted_store_required = $true
    }
    [pscustomobject][ordered]@{
      object_id = 'manual-raw-evidence'
      object_class = 'manual-raw-evidence'
      target = $null
      version = $null
      expected_sha256 = $null
      custody_class = 'external-private-manual-evidence-custody'
      rights_class = 'public-summary-only'
      availability = 'maintainer-capture-required-when-applicable'
      acquisition_requirement = 'Acquire the immutable raw object from the maintainer custody receipt; absence remains explicit.'
      payload_embedded = $false
      encrypted_store_required = $true
    }
    [pscustomobject][ordered]@{
      object_id = 'factorio-saves'
      object_class = 'factorio-saves'
      target = $null
      version = $null
      expected_sha256 = $null
      custody_class = 'external-private-save-custody'
      rights_class = 'player-data-private'
      availability = 'maintainer-custody-required-when-referenced'
      acquisition_requirement = 'Restore only the exact save object named by the playtest or qualification receipt.'
      payload_embedded = $false
      encrypted_store_required = $true
    }
    [pscustomobject][ordered]@{
      object_id = 'private-acquisition-data'
      object_class = 'private-acquisition-data'
      target = $null
      version = $null
      expected_sha256 = $null
      custody_class = 'external-private-acquisition-custody'
      rights_class = 'credentials-and-account-data-forbidden'
      availability = 'external-authority-only'
      acquisition_requirement = 'Use the approved external credential or acquisition authority; no value is recorded here.'
      payload_embedded = $false
      encrypted_store_required = $true
    }
    [pscustomobject][ordered]@{
      object_id = 'protected-signing-material'
      object_class = 'protected-signing-material'
      target = $null
      version = $null
      expected_sha256 = $null
      custody_class = 'separately-governed-encrypted-signing-store'
      rights_class = 'maintainer-secret-authority'
      availability = 'blocked-until-maintainer-ceremony'
      acquisition_requirement = 'Complete the protected Ed25519 maintainer ceremony and its two encrypted recovery-copy receipts.'
      payload_embedded = $false
      encrypted_store_required = $true
    }
  )
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4PrivateCustodyInventoryV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    status = 'public-index-private-payloads-absent'
    private_payloads_embedded = $false
    credentials_embedded = $false
    private_keys_embedded = $false
    entries = @($entries)
    transition_authority = [pscustomobject][ordered]@{
      production_signing = $false
      production_seal = $false
      publication = $false
    }
    record_sha256 = $null
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $record
  if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $script:MIR4PrivateCustodyInventorySchemaV1) -ErrorAction Stop)) {
    throw '[mir4-private-custody-inventory-schema]'
  }
  if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-MIR4ReleaseCapsuleRecordV1 -Record $record -Path $OutputPath -AppendOnly
  }
  return $record
}

function New-MIR4DeterministicGitSourceArchiveV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ContainmentRoot
  )

  $repo = Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $RepoRoot
  if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { throw '[mir4-release-capsule-source-commit]' }
  $resolvedCommit = (& git -C $repo rev-parse --verify "$SourceCommit^{commit}").Trim()
  if ($LASTEXITCODE -ne 0 -or $resolvedCommit -cne $SourceCommit) {
    throw '[mir4-release-capsule-source-commit-unavailable]'
  }
  $sourceTree = (& git -C $repo rev-parse "$SourceCommit^{tree}").Trim()
  if ($LASTEXITCODE -ne 0 -or $sourceTree -cnotmatch '^[0-9a-f]{40}$') {
    throw '[mir4-release-capsule-source-tree]'
  }
  $output = Assert-MIR4DescendantPath -Root $ContainmentRoot -Path $OutputPath
  $null = Assert-MIR4NoReparseAncestors -Root $ContainmentRoot -Path $output
  $parent = Split-Path -Parent $output
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $temporary = $output + '.new'
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  $git = @(Get-Command git -CommandType Application -ErrorAction Stop | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.Source) -and
    (Test-Path -LiteralPath $_.Source -PathType Leaf)
  } | Select-Object -First 1)
  if ($git.Count -ne 1) { throw '[mir4-release-capsule-git-executable]' }
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = [string]$git[0].Source
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  foreach ($argument in @(
    '-C', $repo, 'archive', '--format=zip', '--prefix=mir4-source/',
    "--output=$temporary", $SourceCommit
  )) {
    $null = $info.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  if (-not $process.Start()) { throw '[mir4-release-capsule-git-archive-start]' }
  $standardOutput = $process.StandardOutput.ReadToEnd()
  $standardError = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $exitCode = $process.ExitCode
  $process.Dispose()
  if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $temporary -PathType Leaf)) {
    throw "[mir4-release-capsule-git-archive] $standardError $standardOutput"
  }
  $inventory = Get-MIR4ArchiveInventory -Path $temporary -MaxEntries 100000 -MaxEntryBytes 268435456 -MaxExpandedBytes 1073741824
  if ([string]$inventory.root -cne 'mir4-source') { throw '[mir4-release-capsule-source-root]' }
  if (Test-Path -LiteralPath $output -PathType Leaf) {
    $existingHash = Get-MIR4Sha256File -Path $output
    $newHash = Get-MIR4Sha256File -Path $temporary
    if ($existingHash -cne $newHash) { throw '[mir4-release-capsule-source-archive-append-only-conflict]' }
    Remove-Item -LiteralPath $temporary -Force
  } else {
    Move-Item -LiteralPath $temporary -Destination $output
  }
  $item = Get-Item -LiteralPath $output
  return [pscustomobject][ordered]@{
    kind = 'MIR4GitSourceArchiveV1'
    source_commit = $SourceCommit
    source_tree = $sourceTree
    root = 'mir4-source'
    archive_sha256 = Get-MIR4Sha256File -Path $output
    content_sha256 = [string]$inventory.content_sha256
    bytes = [long]$item.Length
    entry_count = [int]$inventory.entry_count
    network_required = $false
    path = $output
  }
}

function Get-MIR4ReleaseCapsuleDescriptorRowsV1 {
  param([Parameter(Mandatory)][object[]]$ObjectDescriptors)

  $rows = [Collections.Generic.List[object]]::new()
  $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($descriptor in $ObjectDescriptors) {
    $role = [string]$descriptor.role
    $logicalName = [string]$descriptor.logical_name
    $path = (Resolve-Path -LiteralPath ([string]$descriptor.path)).Path
    if ($role -cnotmatch '^[a-z0-9][a-z0-9.-]{0,63}$' -or
        $logicalName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
        [string]$descriptor.media_type -cnotmatch '^[a-z0-9.+-]+/[a-z0-9.+-]+$') {
      throw '[mir4-release-capsule-object-identity]'
    }
    $objectId = "$role.$logicalName"
    if (-not $ids.Add($objectId)) {
      throw "[mir4-release-capsule-duplicate-object-id] $objectId"
    }
    $item = Get-Item -LiteralPath $path
    $sha256 = Get-MIR4Sha256File -Path $path
    $rows.Add([pscustomobject][ordered]@{
      object_id = $objectId
      role = $role
      logical_name = $logicalName
      media_type = [string]$descriptor.media_type
      component_id = if ($descriptor.PSObject.Properties.Name -contains 'component_id') { $descriptor.component_id } else { $null }
      target = if ($descriptor.PSObject.Properties.Name -contains 'target') { $descriptor.target } else { $null }
      sha256 = $sha256
      bytes = [long]$item.Length
      path = Get-MIR4ReleaseCapsuleObjectPathV1 -Sha256 $sha256
      required_for_restore = if ($descriptor.PSObject.Properties.Name -contains 'required_for_restore') { [bool]$descriptor.required_for_restore } else { $true }
      source_path = $path
    })
  }
  return $rows.ToArray()
}

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
        timestamp = $entry.LastWriteTime.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
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

function Read-MIR4ReleaseCapsuleEntryBytesV1 {
  param(
    [Parameter(Mandatory)][string]$CapsulePath,
    [Parameter(Mandatory)][string]$RelativePath,
    [ValidateRange(1, 268435456)][long]$MaximumBytes = 16777216
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $CapsulePath).Path)
  try {
    $fullName = "$script:MIR4ReleaseCapsuleRootV1/$RelativePath"
    $entry = @($zip.Entries | Where-Object { [string]$_.FullName -ceq $fullName })
    if ($entry.Count -ne 1 -or [long]$entry[0].Length -gt $MaximumBytes) {
      throw "[mir4-release-capsule-entry-read] $RelativePath"
    }
    return ,([byte[]](Read-MIR4BoundedZipEntryBytes -Entry $entry[0] -MaximumBytes $MaximumBytes))
  } finally {
    $zip.Dispose()
  }
}

function Read-MIR4ReleaseCapsuleManifestV1 {
  param([Parameter(Mandatory)][string]$CapsulePath)
  $bytes = Read-MIR4ReleaseCapsuleEntryBytesV1 -CapsulePath $CapsulePath -RelativePath 'metadata/capsule-manifest.json'
  return [Text.UTF8Encoding]::new($false, $true).GetString($bytes) |
    ConvertFrom-Json -Depth 100 -DateKind String
}

function Test-MIR4ReleaseCapsuleRoleClosureV1 {
  param([Parameter(Mandatory)][object[]]$Objects)

  $exact = [ordered]@{
    'source-archive' = 1
    'source-archive-envelope' = 1
    'source-release-record' = 1
    'target-distribution-record-set' = 1
    'component-inventory' = 1
    'sbom-spdx-3.0.1' = 1
    'sbom-spdx-2.3' = 1
    'provenance-slsa-v1' = 1
    'supply-chain-attestation' = 1
    'proof-public-key' = 1
    'proof-closure-summary' = 1
    'restore-instructions' = 1
    'rights-custody-inventory' = 1
    'preview-asset' = 4
  }
  foreach ($entry in $exact.GetEnumerator()) {
    if (@($Objects | Where-Object { [string]$_.role -ceq [string]$entry.Key }).Count -ne [int]$entry.Value) {
      return $false
    }
  }
  return @($Objects | Where-Object { [string]$_.role -notin @($exact.Keys) }).Count -eq 0
}

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

function Test-MIR4ReleaseCapsuleV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CapsulePath,
    [string]$ExpectedSourceCommit,
    [string]$ExpectedSourceTree,
    [string]$ExpectedTarget,
    [string[]]$RevokedFingerprints = @()
  )

  try {
    $repo = Get-MIR4ReleaseCapsuleRepoRootV1 -RepoRoot $RepoRoot
    $manifest = Read-MIR4ReleaseCapsuleManifestV1 -CapsulePath $CapsulePath
    if (-not (Test-MIR4BootstrapRecordHash -Record $manifest)) { return $false }
    $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $manifest
    if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $script:MIR4ReleaseCapsuleManifestSchemaV1) -ErrorAction Stop)) {
      return $false
    }
    if (-not (Test-MIR4ReleaseCapsuleRoleClosureV1 -Objects @($manifest.objects)) -or
        [bool]$manifest.partitions.private_custody.payloads_embedded -or
        [bool]$manifest.partitions.private_custody.credential_values_embedded -or
        [bool]$manifest.partitions.private_custody.private_keys_embedded) {
      return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceCommit) -and
        [string]$manifest.source.commit -cne $ExpectedSourceCommit) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceTree) -and
        [string]$manifest.source.tree -cne $ExpectedSourceTree) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedTarget) -and
        @($manifest.targets | Where-Object { [string]$_.target -ceq $ExpectedTarget }).Count -ne 1) {
      return $false
    }
    if ($RevokedFingerprints -ccontains [string]$manifest.proof_closure.public_key_fingerprint) {
      return $false
    }
    foreach ($property in $manifest.transition_authority.PSObject.Properties) {
      if ([bool]$property.Value) { return $false }
    }
    foreach ($property in $manifest.publication_intents.PSObject.Properties) {
      if ([bool]$property.Value) { return $false }
    }
    if ($json -match '(?i)(?:OPENSSH PRIVATE KEY|passphrase|private_key_path|mod_portal_token|github_token)' -or
        $json -match '(?i)[A-Z]:[\\/]Users[\\/]') {
      return $false
    }
    $archive = Get-MIR4ReleaseCapsuleArchiveInventoryV1 -CapsulePath $CapsulePath
    $byPath = @{}
    foreach ($entry in $archive.entries) { $byPath[[string]$entry.path] = $entry }
    $expected = @('metadata/capsule-manifest.json') + @($manifest.objects.path | Sort-Object -Unique -CaseSensitive)
    $expectedOrder = @($expected | Sort-Object -CaseSensitive)
    $actualOrder = @($archive.entries.path | Sort-Object -CaseSensitive)
    if (($expectedOrder -join [char]0) -cne ($actualOrder -join [char]0)) {
      return $false
    }
    foreach ($object in $manifest.objects) {
      if (-not $byPath.ContainsKey([string]$object.path)) { return $false }
      $entry = $byPath[[string]$object.path]
      if ([string]$entry.sha256 -cne [string]$object.sha256 -or
          [long]$entry.bytes -ne [long]$object.bytes -or
          [string]$entry.timestamp -cne '1980-01-01T00:00:00Z' -or
          [int]$entry.external_attributes -ne 0) {
        return $false
      }
    }
    $privateObject = @($manifest.objects | Where-Object role -eq 'rights-custody-inventory')
    if ($privateObject.Count -ne 1) { return $false }
    $privateBytes = Read-MIR4ReleaseCapsuleEntryBytesV1 -CapsulePath $CapsulePath -RelativePath ([string]$privateObject[0].path)
    $privateInventory = [Text.UTF8Encoding]::new($false, $true).GetString($privateBytes) |
      ConvertFrom-Json -Depth 100 -DateKind String
    if (-not (Test-MIR4BootstrapRecordHash -Record $privateInventory) -or
        -not ((ConvertTo-MIR4BootstrapCanonicalJson -Value $privateInventory) |
          Test-Json -SchemaFile (Join-Path $repo $script:MIR4PrivateCustodyInventorySchemaV1) -ErrorAction Stop)) {
      return $false
    }
    return $true
  } catch {
    return $false
  }
}

function Test-MIR4ReleaseCapsuleProvenanceBindingV1 {
  param(
    [Parameter(Mandatory)]$Inventory,
    [Parameter(Mandatory)]$Provenance,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  if (-not (Test-MIR4ComponentInventoryV1 -Inventory $Inventory) -or
      -not (Test-MIR4SlsaProvenanceV1 -Statement $Provenance -RepoRoot $RepoRoot)) {
    return $false
  }
  $subjects = @(
    foreach ($component in $Inventory.components) {
      $digest = if ($null -ne $component.artifact) {
        [string]$component.artifact.sha256
      } else {
        [string]$component.content_root.sha256
      }
      [pscustomobject][ordered]@{
        name = [string]$component.component_id
        digest = [pscustomobject][ordered]@{ sha256 = $digest.ToLowerInvariant() }
      }
    }
  )
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $subjects) -cne
      (ConvertTo-MIR4BootstrapCanonicalJson -Value @($Provenance.subject))) {
    return $false
  }
  $dependencies = @($Provenance.predicate.buildDefinition.resolvedDependencies | Where-Object {
    [string]$_.uri -like 'git+https://github.com/Julesc013/more-infinite-research@*'
  })
  $byproducts = @($Provenance.predicate.runDetails.byproducts | Where-Object {
    [string]$_.name -ceq 'component-inventory.json'
  })
  return $dependencies.Count -eq 1 -and
    [string]$dependencies[0].digest.gitCommit -ceq [string]$Inventory.source.commit -and
    [string]$dependencies[0].digest.gitTree -ceq [string]$Inventory.source.tree -and
    $byproducts.Count -eq 1 -and
    [string]$byproducts[0].digest.sha256 -ceq ([string]$Inventory.record_sha256).ToLowerInvariant()
}

function Test-MIR4PreviewAssetArchiveV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [Parameter(Mandatory)][string]$ExpectedTree
  )

  try {
    $inventory = Get-MIR4ArchiveInventory -Path $Path -MaxEntries 10000 -MaxEntryBytes 67108864 -MaxExpandedBytes 536870912
    $manifest = (Read-MIR4ArchiveText -Path $Path -RelativePath 'manifest.json' -MaximumBytes 16777216) |
      ConvertFrom-Json -Depth 100 -DateKind String
    if ([string]$manifest.kind -cne 'MIR4PreviewAssetManifestV1' -or
        [string]$manifest.source.commit -cne $ExpectedCommit -or
        [string]$manifest.source.tree -cne $ExpectedTree -or
        [bool]$manifest.production_candidate -or
        [bool]$manifest.publication_authorized) {
      return $false
    }
    $entryMap = @{}
    foreach ($entry in $inventory.entries) { $entryMap[[string]$entry.path] = $entry }
    foreach ($file in $manifest.files) {
      if (-not $entryMap.ContainsKey([string]$file.path) -or
          [string]$entryMap[[string]$file.path].raw_sha256 -cne [string]$file.sha256 -or
          [long]$entryMap[[string]$file.path].raw_bytes -ne [long]$file.bytes) {
        return $false
      }
    }
    foreach ($embedded in $manifest.embedded_metadata) {
      if (-not $entryMap.ContainsKey([string]$embedded.path) -or
          [string]$entryMap[[string]$embedded.path].raw_sha256 -cne [string]$embedded.sha256) {
        return $false
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Test-MIR4RestoredPublisherAdmissionV1 {
  param(
    [Parameter(Mandatory)][string]$RestoredSourceRoot,
    [Parameter(Mandatory)][string]$CapsuleSha256
  )

  $workflowPath = Join-Path $RestoredSourceRoot '.github/workflows/mir4-target-publication.yml'
  if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
    throw '[mir4-release-capsule-publisher-workflow]'
  }
  $workflow = [IO.File]::ReadAllText($workflowPath)
  if ($workflow -match 'actions/checkout|Build-MIRPackage|mir4\s+platform\s+package' -or
      $workflow -notmatch 'seal-verifier/Test-MIR4PublicationAdmission\.ps1' -or
      $workflow -notmatch 'publication_authorized') {
    throw '[mir4-release-capsule-publisher-confinement]'
  }
  foreach ($field in @(
    'source_release_record',
    'candidate_id',
    'source_commit',
    'source_tree',
    'target_distribution_record_set',
    'release_plan_digest',
    'proof_root',
    'seal_root'
  )) {
    $pattern = '\[string\]\$admission\.' + [regex]::Escape($field)
    if ($workflow -notmatch $pattern) {
      throw "[mir4-release-capsule-publisher-admission] $field"
    }
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ReleaseCapsuleDummyPublisherAdmissionV1'
    capsule_sha256 = $CapsuleSha256
    credential_mode = 'dummy-none'
    credentials_present = $false
    network_calls = 0
    source_checkout_available = $false
    package_builder_available = $false
    mutation_authorized = $false
    publication_authorized = $false
    admission_contract_verified = $true
    record_sha256 = $null
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

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
  Expand-MIR4SafeArchive -ArchivePath $sourceArchivePath -Destination $sourceDestination -OutputRoot $root | Out-Null
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
