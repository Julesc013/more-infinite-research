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
          [string]$entry.zip_dos_timestamp -cne '1980-01-01T00:00:00' -or
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
          [string]$entryMap[[string]$file.path].raw_sha256 -cne ([string]$file.sha256).ToUpperInvariant() -or
          [long]$entryMap[[string]$file.path].raw_bytes -ne [long]$file.bytes) {
        return $false
      }
    }
    foreach ($embedded in $manifest.embedded_metadata) {
      if (-not $entryMap.ContainsKey([string]$embedded.path) -or
          [string]$entryMap[[string]$embedded.path].raw_sha256 -cne ([string]$embedded.sha256).ToUpperInvariant()) {
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
