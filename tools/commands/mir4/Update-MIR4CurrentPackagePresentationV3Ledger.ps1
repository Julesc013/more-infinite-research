[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$SourceCommit = '',
  [string]$RecordedAt = '2026-09-15T00:00:00+10:00',
  [switch]$Append,
  [switch]$MigrateGenesis,
  [switch]$MigrateContentChain,
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$ledgerRelative = 'spec/distribution/mir4-current-package-presentation-v3.json'
$ledgerPath = Join-Path $repo $ledgerRelative
$schemaPath = Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v3.schema.json'
$v2Relative = 'spec/distribution/mir4-current-package-presentation-v2.json'
$v2Path = Join-Path $repo $v2Relative
$genesisRowSha256 = 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1'
$genesisRecordSha256 = '7837F146C60944351540005CCDE54E78A637768895DFF884EE2B672727A30AF5'

function Get-MIR4PackagePresentationV3RowSha256 {
  param([Parameter(Mandatory)]$Row)

  $unsigned = [ordered]@{}
  foreach ($property in $Row.PSObject.Properties) {
    if ([string]$property.Name -cne 'row_sha256') { $unsigned[$property.Name] = $property.Value }
  }
  return Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value ([pscustomobject]$unsigned))
}

function Get-MIR4PackagePresentationV3V2Predecessor {
  $raw = Get-Content -Raw -LiteralPath $v2Path
  $v2Schema = Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v2.schema.json'
  if (-not ($raw | Test-Json -SchemaFile $v2Schema)) { throw '[mir4-package-presentation-v3-v2-schema]' }
  $v2 = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if (
    -not (Test-MIR4BootstrapRecordHash -Record $v2) -or
    [string]$v2.kind -cne 'MIR4CurrentPackagePresentationV2' -or
    [string]$v2.record_sha256 -cne 'C33F1B568CA247108D88C4F2A109C45E29F2C77C4EE026CB4C9047BAA3A2360F'
  ) {
    throw '[mir4-package-presentation-v3-v2-predecessor]'
  }
  return $v2
}

function New-MIR4PackagePresentationV3ContentPredecessor {
  param([Parameter(Mandatory)]$Ledger)

  $rows = @($Ledger.rows)
  if ($rows.Count -lt 1) { throw '[mir4-package-presentation-v3-predecessor-rows]' }
  $prior = $rows[-1]
  return [ordered]@{
    prior_record_sha256 = $(if ($rows.Count -eq 1) { [string]$Ledger.genesis_record_sha256 } else { [string]$Ledger.record_sha256 })
    prior_row_sha256 = [string]$prior.row_sha256
    prior_row_count = $rows.Count
    prior_package_fingerprint_sha256 = [string]$prior.package_source.canonical_fingerprint_sha256
    prior_source_manifest_record_sha256 = [string]$prior.source_manifest.record_sha256
    prior_package_authority_record_sha256 = [string]$prior.package_authority.record_sha256
    prior_materializer_sha256 = [string]$prior.materializer_proof.normalized_text_sha256
    prior_binding_count = [int]$prior.package_source.binding_count
    prior_unique_binding_count = [int]$prior.package_source.unique_binding_count
  }
}

function New-MIR4PackagePresentationV3Row {
  param(
    [Parameter(Mandatory)][int]$Sequence,
    [Parameter(Mandatory)][string]$PreviousRowSha256,
    [Parameter(Mandatory)][string]$Timestamp,
    $LedgerPredecessor,
    [string]$ProvenanceCommit = ''
  )

  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $manifestPath = Join-Path $repo 'src/mod/package-source.json'
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100 -DateKind String
  $bindingCount = @($manifest.bindings).Count
  $uniqueBindingCount = @($manifest.bindings | ForEach-Object { '{0}|{1}' -f [string]$_.layer, [string]$_.output_path } | Sort-Object -Unique).Count
  if (
    -not (Test-MIR4BootstrapRecordHash -Record $manifest) -or
    -not (Test-MIR4BootstrapRecordHash -Record $authority) -or
    [string]$manifest.materializer_abi -cne 'mir4-target-materializer/1' -or
    [string]$authority.writer.implementation -cne 'tools/mir/application/package/TargetMaterializer.ps1' -or
    -not [bool]$authority.writer.sole_current_writer -or
    [string]$authority.legacy_root_projection.compatibility_state -cne 'retired-historical-read-only' -or
    $bindingCount -ne $uniqueBindingCount
  ) {
    throw '[mir4-package-presentation-v3-source-authority]'
  }

  $materializerRelative = 'tools/mir/application/package/TargetMaterializer.ps1'
  $materializerIdentity = Get-MIRFileContentIdentity -Path (Join-Path $repo $materializerRelative) -RelativePath $materializerRelative
  $row = [pscustomobject][ordered]@{
    sequence = $Sequence
    row_id = ('mir4-current-package-presentation-v3-{0:d4}' -f $Sequence)
    recorded_at = $Timestamp
    previous_row_sha256 = $PreviousRowSha256
    source_manifest = [ordered]@{
      path = 'src/mod/package-source.json'
      kind = [string]$manifest.kind
      state_or_status = [string]$manifest.source_state
      record_sha256 = [string]$manifest.record_sha256
    }
    package_authority = [ordered]@{
      path = 'targets/package-authority.json'
      kind = [string]$authority.kind
      state_or_status = [string]$authority.status
      record_sha256 = [string]$authority.record_sha256
    }
    package_source = [ordered]@{
      canonical_fingerprint_sha256 = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
      materializer_abi = [string]$manifest.materializer_abi
      roots = @(Get-MIR4CanonicalPackageSourceRoots)
      sole_writer = [string]$authority.writer.implementation
      legacy_root_state = [string]$authority.legacy_root_projection.compatibility_state
      binding_count = $bindingCount
      unique_binding_count = $uniqueBindingCount
    }
    materializer_proof = [ordered]@{
      path = $materializerRelative
      normalized_text_sha256 = [string]$materializerIdentity.Sha256
      materializer_abi = [string]$manifest.materializer_abi
      sole_current_writer = [bool]$authority.writer.sole_current_writer
      package_excluded = $true
    }
    package_visible_scope = [ordered]@{
      package_visible = $false
      package_visible_delta = @()
      package_source_roots = @(Get-MIR4CanonicalPackageSourceRoots)
      controller_authority_only = $true
    }
    transition_gate = [ordered]@{
      version_allocation = $false
      tagging = $false
      signing = $false
      sealing = $false
      publication = $false
    }
    row_sha256 = ''
  }
  if ($null -ne $LedgerPredecessor) {
    $row | Add-Member -NotePropertyName ledger_predecessor -NotePropertyValue $LedgerPredecessor
  }
  if (-not [string]::IsNullOrWhiteSpace($ProvenanceCommit)) {
    if ($ProvenanceCommit -notmatch '^[a-f0-9]{40}$') { throw '[mir4-package-presentation-v3-provenance-commit]' }
    $row | Add-Member -NotePropertyName source_identity -NotePropertyValue ([ordered]@{ commit = $ProvenanceCommit })
  }
  $row.row_sha256 = Get-MIR4PackagePresentationV3RowSha256 -Row $row
  return $row
}

function Write-MIR4PackagePresentationV3Ledger {
  param(
    [Parameter(Mandatory)]$Ledger,
    [Parameter(Mandatory)][string]$Status
  )

  $Ledger.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $Ledger
  $json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $Ledger) + [char]10
  if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-package-presentation-v3-schema]' }
  [IO.File]::WriteAllText($ledgerPath, $json, [Text.UTF8Encoding]::new($false))
  return [pscustomobject][ordered]@{
    status = $Status
    path = $ledgerRelative
    rows = @($Ledger.rows).Count
    append_only = $true
    publication_authorized = $false
  }
}

if ($Check -and ($Append -or $MigrateGenesis -or $MigrateContentChain)) {
  throw '[mir4-package-presentation-v3-check-mutation]'
}
if ($MigrateGenesis) {
  throw '[mir4-package-presentation-v3-genesis-migration-retired]'
}
if ($Check) {
  if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) { throw '[mir4-package-presentation-v3-stale]' }
  . (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
  Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo | Out-Null
  [pscustomobject][ordered]@{status='current';path=$ledgerRelative;append_only=$true;publication_authorized=$false}
  return
}

if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
  throw '[mir4-package-presentation-v3-genesis-creation-disabled]'
}

if ($MigrateContentChain) {
  if ($Append) { throw '[mir4-package-presentation-v3-migrate-append]' }
  $legacy = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json -Depth 100 -DateKind String
  $legacyRows = @($legacy.rows)
  if (
    $legacyRows.Count -ne 2 -or
    [string]$legacyRows[0].row_sha256 -cne $genesisRowSha256 -or
    $legacyRows[0].PSObject.Properties['ledger_predecessor'] -or
    [string]$legacyRows[1].row_sha256 -cne '7B6B4DC410BC89DD5322F83803306B41F048785D47A4CD7E6891507000E9EEFC' -or
    [string]$legacyRows[1].ledger_predecessor.record_sha256 -cne $genesisRecordSha256
  ) {
    throw '[mir4-package-presentation-v3-content-migration-contract]'
  }
  $v2 = Get-MIR4PackagePresentationV3V2Predecessor
  $migrationEnvelope = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4CurrentPackagePresentationV3Ledger'
    status = 'accepted-current-package-presentation-ledger'
    recorded_at = [string]$legacy.recorded_at
    predecessor = $legacy.predecessor
    authority_invariants = $legacy.authority_invariants
    append_only = $true
    genesis_row_sha256 = $genesisRowSha256
    genesis_record_sha256 = $genesisRecordSha256
    rows = @($legacyRows[0])
    transition_gate = $legacy.transition_gate
    record_sha256 = $genesisRecordSha256
  }
  $row = New-MIR4PackagePresentationV3Row -Sequence 2 -PreviousRowSha256 $genesisRowSha256 -Timestamp ([string]$legacyRows[1].recorded_at) -LedgerPredecessor (New-MIR4PackagePresentationV3ContentPredecessor -Ledger $migrationEnvelope)
  $ledger = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4CurrentPackagePresentationV3Ledger'
    status = 'accepted-current-package-presentation-ledger'
    recorded_at = [string]$legacy.recorded_at
    predecessor = $legacy.predecessor
    authority_invariants = $legacy.authority_invariants
    append_only = $true
    genesis_row_sha256 = $genesisRowSha256
    genesis_record_sha256 = $genesisRecordSha256
    rows = @($legacyRows[0], $row)
    transition_gate = $legacy.transition_gate
    record_sha256 = ''
  }
  Write-MIR4PackagePresentationV3Ledger -Ledger $ledger -Status 'content-chain-migrated'
  return
}

. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
$existing = Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo -RequireLiveCurrent:$false
if (-not $Append) {
  Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo | Out-Null
  [pscustomobject][ordered]@{status='current';path=$ledgerRelative;rows=@($existing.rows).Count;append_only=$true;publication_authorized=$false}
  return
}

$previousRow = @($existing.rows)[-1]
$row = New-MIR4PackagePresentationV3Row -Sequence (@($existing.rows).Count + 1) -PreviousRowSha256 ([string]$previousRow.row_sha256) -Timestamp $RecordedAt -LedgerPredecessor (New-MIR4PackagePresentationV3ContentPredecessor -Ledger $existing) -ProvenanceCommit $SourceCommit
$sameIdentity = (
  [string]$previousRow.package_source.canonical_fingerprint_sha256 -ceq [string]$row.package_source.canonical_fingerprint_sha256 -and
  [string]$previousRow.source_manifest.record_sha256 -ceq [string]$row.source_manifest.record_sha256 -and
  [string]$previousRow.package_authority.record_sha256 -ceq [string]$row.package_authority.record_sha256 -and
  [string]$previousRow.materializer_proof.normalized_text_sha256 -ceq [string]$row.materializer_proof.normalized_text_sha256 -and
  [int]$previousRow.package_source.binding_count -eq [int]$row.package_source.binding_count -and
  [int]$previousRow.package_source.unique_binding_count -eq [int]$row.package_source.unique_binding_count
)
if ($sameIdentity) { throw '[mir4-package-presentation-v3-append-duplicate]' }

$rows = @($existing.rows) + @($row)
$ledger = [pscustomobject][ordered]@{
  schema = 1
  kind = 'MIR4CurrentPackagePresentationV3Ledger'
  status = 'accepted-current-package-presentation-ledger'
  recorded_at = [string]$existing.recorded_at
  predecessor = $existing.predecessor
  authority_invariants = $existing.authority_invariants
  append_only = $true
  genesis_row_sha256 = [string]$existing.genesis_row_sha256
  genesis_record_sha256 = [string]$existing.genesis_record_sha256
  rows = $rows
  transition_gate = $existing.transition_gate
  record_sha256 = ''
}
for ($index = 0; $index -lt @($existing.rows).Count; $index++) {
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $existing.rows[$index]) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $ledger.rows[$index])) {
    throw '[mir4-package-presentation-v3-prior-row-mutation]'
  }
}
Write-MIR4PackagePresentationV3Ledger -Ledger $ledger -Status 'appended'
