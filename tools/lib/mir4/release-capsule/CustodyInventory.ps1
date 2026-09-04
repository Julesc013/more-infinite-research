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
