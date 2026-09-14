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

function Invoke-MIR4V3Git {
  param([string[]]$Arguments)
  $result = & git @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "[mir4-package-presentation-v3-test-git] $($result -join [Environment]::NewLine)" }
  return [string]($result -join [Environment]::NewLine).Trim()
}

function New-MIR4V3SyntheticLedgerCommit {
  param(
    [string]$BaseCommit,
    [string]$LedgerRepositoryPath,
    [string]$LedgerText,
    [string]$Message
  )
  $indexPath = Join-Path ([IO.Path]::GetTempPath()) ("mir4-v3-ledger-$([guid]::NewGuid().ToString('N')).index")
  $previousIndex = $env:GIT_INDEX_FILE
  try {
    $env:GIT_INDEX_FILE = $indexPath
    Invoke-MIR4V3Git -Arguments @('read-tree', $BaseCommit) | Out-Null
    $blob = $LedgerText | git hash-object -w --stdin
    if ($LASTEXITCODE -ne 0) { throw '[mir4-package-presentation-v3-test-blob]' }
    Invoke-MIR4V3Git -Arguments @('update-index', '--add', '--cacheinfo', "100644,$($blob.Trim()),$LedgerRepositoryPath") | Out-Null
    $tree = Invoke-MIR4V3Git -Arguments @('write-tree')
    return Invoke-MIR4V3Git -Arguments @('commit-tree', $tree, '-p', $BaseCommit, '-m', $Message)
  } finally {
    $env:GIT_INDEX_FILE = $previousIndex
    if (Test-Path -LiteralPath $indexPath -PathType Leaf) { [IO.File]::Delete($indexPath) }
  }
}

& $writer -RepoRoot $repo -Check | Out-Null
& $writer -RepoRoot $repo | Out-Null
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-writer-fixed-point]' }

$ledger = Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo
$current = Assert-MIR4CurrentPackagePresentation -RepoRoot $repo -PackageSourceSha256 $before
$rows = @($ledger.rows)
if (
  -not (($beforeText | Test-Json -SchemaFile $schemaPath)) -or
  -not (Test-MIR4BootstrapRecordHash -Record $ledger) -or
  $rows.Count -ne 1 -or
  [string]$current.row_id -cne [string]$rows[-1].row_id -or
  [string](Get-MIR4CurrentPackageSourceSha256 -RepoRoot $repo) -cne $before -or
  [string]$current.package_source.canonical_fingerprint_sha256 -cne $before -or
  [int]$current.package_source.binding_count -ne 448 -or
  [int]$current.package_source.unique_binding_count -ne 448 -or
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

$head = Invoke-MIR4V3Git -Arguments @('rev-parse', 'HEAD')
$headTree = Invoke-MIR4V3Git -Arguments @('rev-parse', 'HEAD^{tree}')
$syntheticSource = Invoke-MIR4V3Git -Arguments @('commit-tree', $headTree, '-p', $head, '-m', 'MIR4 V3 synthetic source identity')
$priorLedgerSha256 = Get-MIRGitTextAtCommitSha256 -RepoRoot $repo -Commit $syntheticSource -RelativePath 'spec/distribution/mir4-current-package-presentation-v3.json'
$twoRowLedger = $ledger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$secondRow = $twoRowLedger.rows[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$secondRow.sequence = 2
$secondRow.row_id = 'mir4-current-package-presentation-v3-0002'
$secondRow.previous_row_sha256 = [string]$twoRowLedger.rows[0].row_sha256
$secondRow.source_identity.commit = $syntheticSource
$secondRow.source_identity.tree = Invoke-MIR4V3Git -Arguments @('rev-parse', "$syntheticSource^{tree}")
$secondRow | Add-Member -NotePropertyName ledger_predecessor -NotePropertyValue ([pscustomobject][ordered]@{
  commit = $syntheticSource
  tree = [string]$secondRow.source_identity.tree
  path = 'spec/distribution/mir4-current-package-presentation-v3.json'
  normalized_text_sha256 = $priorLedgerSha256
  record_sha256 = [string]$ledger.record_sha256
  final_row_sha256 = [string]$ledger.rows[0].row_sha256
  row_count = 1
})
$secondRow.row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $secondRow
$twoRowLedger.rows = @($twoRowLedger.rows[0], $secondRow)
$twoRowLedger.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $twoRowLedger
$twoRowText = $twoRowLedger | ConvertTo-Json -Depth 100
$twoRowCommit = New-MIR4V3SyntheticLedgerCommit -BaseCommit $syntheticSource -LedgerRepositoryPath 'spec/distribution/mir4-current-package-presentation-v3.json' -LedgerText $twoRowText -Message 'MIR4 V3 synthetic appended ledger'

Assert-MIR4CurrentPackagePresentationV3GitLineage -RepoRoot $repo -Ledger $twoRowLedger -LatestLedgerCommit $twoRowCommit | Out-Null
if ([string](Get-MIR4CurrentPackagePresentationV3FinalRow -Ledger $twoRowLedger).row_id -cne 'mir4-current-package-presentation-v3-0002') {
  throw '[mir4-package-presentation-v3-final-row-selector]'
}

$recomputedMutation = $twoRowLedger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$recomputedMutation.rows[-1].recorded_at = '2026-09-15T00:00:00Z'
$recomputedMutation.rows[-1].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $recomputedMutation.rows[-1]
$recomputedMutation.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $recomputedMutation
$recomputedMutationCommit = New-MIR4V3SyntheticLedgerCommit -BaseCommit $twoRowCommit -LedgerRepositoryPath 'spec/distribution/mir4-current-package-presentation-v3.json' -LedgerText ($recomputedMutation | ConvertTo-Json -Depth 100) -Message 'MIR4 V3 synthetic recomputed mutation'
$recomputedMutationRejected = $false
try {
  Assert-MIR4CurrentPackagePresentationV3GitLineage -RepoRoot $repo -Ledger $recomputedMutation -LatestLedgerCommit $recomputedMutationCommit | Out-Null
} catch { $recomputedMutationRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-ledger-lineage-parent\]' }
if (-not $recomputedMutationRejected) { throw '[mir4-package-presentation-v3-recomputed-prior-row-mutation]' }

$trailingDeletion = $twoRowLedger | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
$trailingDeletion.rows = @($trailingDeletion.rows[0])
$trailingDeletion.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $trailingDeletion
$trailingDeletionCommit = New-MIR4V3SyntheticLedgerCommit -BaseCommit $twoRowCommit -LedgerRepositoryPath 'spec/distribution/mir4-current-package-presentation-v3.json' -LedgerText ($trailingDeletion | ConvertTo-Json -Depth 100) -Message 'MIR4 V3 synthetic recomputed trailing deletion'
$trailingDeletionRejected = $false
try {
  Assert-MIR4CurrentPackagePresentationV3GitLineage -RepoRoot $repo -Ledger $trailingDeletion -LatestLedgerCommit $trailingDeletionCommit | Out-Null
} catch { $trailingDeletionRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-ledger-lineage-regression\]' }
if (-not $trailingDeletionRejected) { throw '[mir4-package-presentation-v3-recomputed-trailing-row-deletion]' }

$duplicateAppendRejected = $false
try {
  & $writer -RepoRoot $repo -Append -SourceCommit $head | Out-Null
} catch { $duplicateAppendRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-append-duplicate\]' }
if (-not $duplicateAppendRejected) { throw '[mir4-package-presentation-v3-duplicate-append]' }
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-append-drift]' }

Write-Host '[ok] MIR4 current package presentation V3 selects the final verified row and rejects recomputed mutation, trailing deletion, and duplicate package identity.'
