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
$before = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$beforeText = [IO.File]::ReadAllText($ledgerPath)

& $writer -RepoRoot $repo -Check | Out-Null
& $writer -RepoRoot $repo | Out-Null
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-writer-fixed-point]' }

$ledger = Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo
$current = Assert-MIR4CurrentPackagePresentation -RepoRoot $repo -PackageSourceSha256 $before
$rows = @($ledger.rows)
if (
  -not (($beforeText | Test-Json -SchemaFile $schemaPath)) -or
  -not (Test-MIR4BootstrapRecordHash -Record $ledger) -or
  $rows.Count -lt 1 -or
  [string]$current.row_id -cne [string]$rows[-1].row_id -or
  [string](Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo) -cne $before -or
  [string]$current.package_source.canonical_fingerprint_sha256 -cne $before -or
  [string]$current.source_identity.commit -cne 'b6cf5f19d24f4474ee9dbb0473e59ce9caa8b75d' -or
  [string]$current.source_identity.tree -cne '35b1c9bfbd734ccbddac9b217d15ef7f8d4b9780'
) { throw '[mir4-package-presentation-v3-current-selection]' }

$rowTamper = $ledger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$rowTamper.rows[0].package_source.canonical_fingerprint_sha256 = '0' * 64
$rowTamper.rows[0].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $rowTamper.rows[0]
$rowTamper.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $rowTamper
$rowTamperRejected = $false
try {
  if ((($rowTamper | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath)) {
    if ([string]$rowTamper.genesis_row_sha256 -ne [string]$rowTamper.rows[0].row_sha256) { throw '[expected-genesis-rejection]' }
    Assert-MIR4CurrentPackagePresentationV3Row -RepoRoot $repo -Row $rowTamper.rows[0] -Sequence 1 -PreviousRowSha256 ([string]$ledger.predecessor.record_sha256) | Out-Null
  }
} catch { $rowTamperRejected = $true }
if (-not $rowTamperRejected) { throw '[mir4-package-presentation-v3-prior-row-tamper]' }

$deletion = $ledger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$deletion.rows = @()
$deletion.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $deletion
$deletionRejected = $false
try { $deletionRejected = -not (($deletion | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $schemaPath) } catch { $deletionRejected = $true }
if (-not $deletionRejected) { throw '[mir4-package-presentation-v3-prior-row-deletion]' }

$selectorLedger = $ledger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$selectorRow = $selectorLedger.rows[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$selectorRow.sequence = 2
$selectorRow.row_id = 'mir4-current-package-presentation-v3-0002'
$selectorRow.previous_row_sha256 = [string]$selectorLedger.rows[0].row_sha256
$selectorRow.row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $selectorRow
$selectorLedger.rows = @($selectorLedger.rows[0], $selectorRow)
if ([string](Get-MIR4CurrentPackagePresentationV3FinalRow -Ledger $selectorLedger).row_id -cne 'mir4-current-package-presentation-v3-0002') {
  throw '[mir4-package-presentation-v3-final-row-selector]'
}

$duplicateAppendRejected = $false
try {
  & $writer -RepoRoot $repo -Append -SourceCommit b6cf5f19d24f4474ee9dbb0473e59ce9caa8b75d | Out-Null
} catch { $duplicateAppendRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-append-duplicate\]' }
if (-not $duplicateAppendRejected) { throw '[mir4-package-presentation-v3-duplicate-append]' }
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-append-drift]' }

Write-Host '[ok] MIR4 current package presentation V3 selects the final verified ledger row and rejects prior-row mutation or deletion.'
