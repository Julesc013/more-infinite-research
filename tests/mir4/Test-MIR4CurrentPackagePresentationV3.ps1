# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
. (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')

$writer = Join-Path $repo 'tools/commands/mir4/Update-MIR4CurrentPackagePresentationV3Ledger.ps1'
$ledgerPath = Join-Path $repo 'spec/distribution/mir4-current-package-presentation-v3.json'
$schemaPath = Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v3.schema.json'
$beforeFingerprint = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$beforeText = [IO.File]::ReadAllText($ledgerPath)

function Copy-MIR4V3Ledger {
  param([Parameter(Mandatory)]$Ledger)
  return $Ledger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Set-MIR4V3LedgerRecord {
  param([Parameter(Mandatory)]$Ledger)
  $Ledger.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $Ledger
  return $Ledger
}

function Assert-MIR4V3Reject {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [Parameter(Mandatory)][string]$Name
  )
  $rejected = $false
  try { & $Action } catch { $rejected = $true }
  if (-not $rejected) { throw "[mir4-package-presentation-v3-$Name]" }
}

function Test-MIR4V3Schema {
  param([Parameter(Mandatory)]$Ledger)
  return (($Ledger | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath)
}

function Get-MIR4V3SharedObjectDbSnapshot {
  $snapshot = & git -C $repo count-objects -v 2>$null
  if ($LASTEXITCODE -ne 0) { throw '[mir4-package-presentation-v3-shared-object-db-read]' }
  return [string]($snapshot -join [Environment]::NewLine)
}

$objectDbBefore = Get-MIR4V3SharedObjectDbSnapshot
& $writer -RepoRoot $repo -Check | Out-Null
& $writer -RepoRoot $repo | Out-Null
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-writer-fixed-point]' }

$ledger = Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo
$current = Assert-MIR4CurrentPackagePresentation -RepoRoot $repo -PackageSourceSha256 $beforeFingerprint
$rows = @($ledger.rows)
$finalPredecessor = $rows[-1].ledger_predecessor
if (
  -not (Test-MIR4V3Schema -Ledger $ledger) -or
  -not (Test-MIR4BootstrapRecordHash -Record $ledger) -or
  $rows.Count -ne 2 -or
  [string]$ledger.genesis_row_sha256 -cne 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1' -or
  [string]$ledger.genesis_record_sha256 -cne '7837F146C60944351540005CCDE54E78A637768895DFF884EE2B672727A30AF5' -or
  [string]$current.row_id -cne [string]$rows[-1].row_id -or
  [string](Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo) -cne $beforeFingerprint -or
  [string]$current.package_source.canonical_fingerprint_sha256 -cne $beforeFingerprint -or
  [int]$current.package_source.binding_count -ne 448 -or
  [int]$current.package_source.unique_binding_count -ne 448 -or
  [int]$rows[0].package_source.binding_count -ne 448 -or
  [int]$rows[0].package_source.unique_binding_count -ne 448 -or
  [string]$finalPredecessor.prior_record_sha256 -cne [string]$ledger.genesis_record_sha256 -or
  [string]$finalPredecessor.prior_row_sha256 -cne [string]$rows[0].row_sha256 -or
  [int]$finalPredecessor.prior_row_count -ne 1 -or
  [string]$finalPredecessor.prior_package_fingerprint_sha256 -cne [string]$rows[0].package_source.canonical_fingerprint_sha256 -or
  [string]$finalPredecessor.prior_source_manifest_record_sha256 -cne [string]$rows[0].source_manifest.record_sha256 -or
  [string]$finalPredecessor.prior_package_authority_record_sha256 -cne [string]$rows[0].package_authority.record_sha256 -or
  [string]$finalPredecessor.prior_materializer_sha256 -cne [string]$rows[0].materializer_proof.normalized_text_sha256 -or
  [int]$finalPredecessor.prior_binding_count -ne 448 -or
  [int]$finalPredecessor.prior_unique_binding_count -ne 448
) {
  throw '[mir4-package-presentation-v3-current-selection]'
}

$reordered = Set-MIR4V3LedgerRecord -Ledger (Copy-MIR4V3Ledger -Ledger $ledger)
$reordered.rows = @($reordered.rows[1], $reordered.rows[0])
Set-MIR4V3LedgerRecord -Ledger $reordered | Out-Null
if (-not (Test-MIR4V3Schema -Ledger $reordered)) { throw '[mir4-package-presentation-v3-reorder-schema]' }
Assert-MIR4V3Reject -Name 'reordered-rows' -Action { Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $reordered -RequireLiveCurrent:$false | Out-Null }

$genesisDeleted = Set-MIR4V3LedgerRecord -Ledger (Copy-MIR4V3Ledger -Ledger $ledger)
$genesisDeleted.rows = @($genesisDeleted.rows | Select-Object -Skip 1)
Set-MIR4V3LedgerRecord -Ledger $genesisDeleted | Out-Null
if (-not (Test-MIR4V3Schema -Ledger $genesisDeleted)) { throw '[mir4-package-presentation-v3-genesis-deletion-schema]' }
Assert-MIR4V3Reject -Name 'genesis-deletion' -Action { Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $genesisDeleted -RequireLiveCurrent:$false | Out-Null }

$historicalTamper = Set-MIR4V3LedgerRecord -Ledger (Copy-MIR4V3Ledger -Ledger $ledger)
$historicalTamper.rows[0].package_source.canonical_fingerprint_sha256 = '0' * 64
$historicalTamper.rows[0].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $historicalTamper.rows[0]
Set-MIR4V3LedgerRecord -Ledger $historicalTamper | Out-Null
if (-not (Test-MIR4V3Schema -Ledger $historicalTamper)) { throw '[mir4-package-presentation-v3-historical-tamper-schema]' }
Assert-MIR4V3Reject -Name 'historical-row-tamper' -Action { Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $historicalTamper -RequireLiveCurrent:$false | Out-Null }

$finalTamper = Set-MIR4V3LedgerRecord -Ledger (Copy-MIR4V3Ledger -Ledger $ledger)
$finalTamper.rows[-1].package_source.canonical_fingerprint_sha256 = '0' * 64
$finalTamper.rows[-1].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $finalTamper.rows[-1]
Set-MIR4V3LedgerRecord -Ledger $finalTamper | Out-Null
if (-not (Test-MIR4V3Schema -Ledger $finalTamper)) { throw '[mir4-package-presentation-v3-final-tamper-schema]' }
Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $finalTamper -RequireLiveCurrent:$false | Out-Null
Assert-MIR4V3Reject -Name 'final-row-live-tamper' -Action { Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $finalTamper -RequireLiveCurrent:$true | Out-Null }

$postSquash = Set-MIR4V3LedgerRecord -Ledger (Copy-MIR4V3Ledger -Ledger $ledger)
$postSquash.rows[-1] | Add-Member -NotePropertyName source_identity -NotePropertyValue ([ordered]@{ commit = ('a' * 40) })
$postSquash.rows[-1].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $postSquash.rows[-1]
Set-MIR4V3LedgerRecord -Ledger $postSquash | Out-Null
if (-not (Test-MIR4V3Schema -Ledger $postSquash)) { throw '[mir4-package-presentation-v3-post-squash-provenance-schema]' }
Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $postSquash -RequireLiveCurrent:$true | Out-Null
$postSquash.rows[-1].PSObject.Properties.Remove('source_identity')
$postSquash.rows[-1].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $postSquash.rows[-1]
Set-MIR4V3LedgerRecord -Ledger $postSquash | Out-Null
if (-not (Test-MIR4V3Schema -Ledger $postSquash)) { throw '[mir4-package-presentation-v3-post-squash-schema]' }
Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $postSquash -RequireLiveCurrent:$true | Out-Null
if ([string](Get-MIR4CurrentPackagePresentationV3FinalRow -Ledger $postSquash).row_id -cne [string]$rows[-1].row_id) {
  throw '[mir4-package-presentation-v3-final-row-selector]'
}

Assert-MIR4V3Reject -Name 'duplicate-append' -Action { & $writer -RepoRoot $repo -Append -SourceCommit ('a' * 40) | Out-Null }
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-append-drift]' }

$objectDbAfter = Get-MIR4V3SharedObjectDbSnapshot
if ($objectDbAfter -cne $objectDbBefore) { throw '[mir4-package-presentation-v3-shared-object-db-drift]' }

Write-Host '[ok] MIR4 V3 retains its fixed genesis, content-binds every successor, selects only the live final row, and does not write the shared Git object database.'
