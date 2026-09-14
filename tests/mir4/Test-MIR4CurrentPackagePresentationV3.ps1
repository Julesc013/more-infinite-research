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
$previousGitHubActions = $env:GITHUB_ACTIONS
try {
  $env:GITHUB_ACTIONS = 'true'
  & $writer -RepoRoot $repo -Check | Out-Null
} finally {
  if ($null -eq $previousGitHubActions) { Remove-Item Env:GITHUB_ACTIONS -ErrorAction SilentlyContinue }
  else { $env:GITHUB_ACTIONS = $previousGitHubActions }
}

$ledger = Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo
$current = Assert-MIR4CurrentPackagePresentation -RepoRoot $repo -PackageSourceSha256 $beforeFingerprint
$rows = @($ledger.rows)
$finalPredecessor = $rows[-1].ledger_predecessor
if (
  -not (Test-MIR4V3Schema -Ledger $ledger) -or
  -not (Test-MIR4BootstrapRecordHash -Record $ledger) -or
  $rows.Count -ne 2 -or
  [string]$ledger.custody.mode -cne 'protected-remote-prefix-v1' -or
  [string]$ledger.custody.content_chain_proof -cne 'internal-consistency-and-live-final-binding-only' -or
  [string]$ledger.custody.append_only_tail_retention -cne 'operational-protected-remote-custody-property' -or
  [bool]$ledger.custody.standalone_cryptographic_tail_retention_proof -or
  [string]$ledger.custody.bootstrap -cne 'bounded-v3-content-chain-migration-v1' -or
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

$remoteBootstrap = Assert-MIR4CurrentPackagePresentationV3ProtectedCustody -RepoRoot $repo -TrustedBaseRef 'refs/remotes/origin/dev' -HostedContext
if ([string]$remoteBootstrap.status -cne 'trusted-base-v3-absent-bounded-bootstrap' -or -not [bool]$remoteBootstrap.protected_custody_required) {
  throw '[mir4-package-presentation-v3-remote-bootstrap]'
}

foreach ($originUrl in @(
  'https://github.com/Julesc013/more-infinite-research',
  'https://github.com/Julesc013/more-infinite-research.git',
  'git@github.com:Julesc013/more-infinite-research.git',
  'ssh://git@github.com/Julesc013/more-infinite-research.git'
)) {
  if (-not (Test-MIR4CurrentPackagePresentationV3TrustedOriginUrl -OriginUrl $originUrl)) {
    throw "[mir4-package-presentation-v3-trusted-origin-accepted] $originUrl"
  }
}
foreach ($originUrl in @(
  'http://github.com/Julesc013/more-infinite-research.git',
  'https://github.com/Julesc013/other-repository.git',
  'https://evilgithub.com/Julesc013/more-infinite-research.git',
  'git://github.com/Julesc013/more-infinite-research.git'
)) {
  if (Test-MIR4CurrentPackagePresentationV3TrustedOriginUrl -OriginUrl $originUrl) {
    throw "[mir4-package-presentation-v3-trusted-origin-rejected] $originUrl"
  }
}

$legacyMigrationBase = Copy-MIR4V3Ledger -Ledger $ledger
$legacyMigrationBase.PSObject.Properties.Remove('custody')
$legacyMigrationBase.PSObject.Properties.Remove('genesis_record_sha256')
$legacyMigrationBase.rows[1] = [pscustomobject][ordered]@{
  sequence = 2
  row_id = 'mir4-current-package-presentation-v3-0002'
  recorded_at = '2026-09-15T00:00:00+10:00'
  previous_row_sha256 = 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1'
  source_identity = [ordered]@{ commit = '245f05311c62fc6097a1e17f3b3dabf244fb176e'; tree = 'b71199a40c8da5f4123a96f96eeb874a14fa410e' }
  source_manifest = $ledger.rows[1].source_manifest
  package_authority = $ledger.rows[1].package_authority
  package_source = $ledger.rows[1].package_source
  materializer_proof = $ledger.rows[1].materializer_proof
  package_visible_scope = $ledger.rows[1].package_visible_scope
  transition_gate = $ledger.rows[1].transition_gate
  row_sha256 = ''
  ledger_predecessor = [ordered]@{
    commit = '245f05311c62fc6097a1e17f3b3dabf244fb176e'
    tree = 'b71199a40c8da5f4123a96f96eeb874a14fa410e'
    path = 'spec/distribution/mir4-current-package-presentation-v3.json'
    normalized_text_sha256 = '71D97B5A4A5CDDF56DAB22FBB3C0D96E851EFB2C5090D1435D5A42FA10A39C6A'
    record_sha256 = '7837F146C60944351540005CCDE54E78A637768895DFF884EE2B672727A30AF5'
    final_row_sha256 = 'D3CFC1529C32C820458F4EEBD72E2A5A6401762ED037C376624A6534D41EEEF1'
    row_count = 1
  }
}
$legacyMigrationBase.rows[1].row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $legacyMigrationBase.rows[1]
$legacyMigrationBase.record_sha256 = 'E8F9FD3C982C4D531F7E917603DC63F8C07F9C237D3E2932F2CABF8A9E552717'
if (-not (Test-MIR4CurrentPackagePresentationV3LegacyContentChainMigration -Ledger $legacyMigrationBase)) {
  throw '[mir4-package-presentation-v3-legacy-migration-shape]'
}
$migrationCustody = Assert-MIR4CurrentPackagePresentationV3ProtectedCustodyPrefix -RepoRoot $repo -CandidateLedger $ledger -TrustedLedger $legacyMigrationBase -TrustedBaseRef 'synthetic-legacy'
if ([string]$migrationCustody.status -cne 'bounded-content-chain-migration') { throw '[mir4-package-presentation-v3-legacy-migration-custody]' }

$trustedThree = Copy-MIR4V3Ledger -Ledger $ledger
$thirdRow = Copy-MIR4V3Ledger -Ledger ([pscustomobject]@{ rows = @($trustedThree.rows[-1]) })
$thirdRow = $thirdRow.rows[0]
$thirdRow.sequence = 3
$thirdRow.row_id = 'mir4-current-package-presentation-v3-0003'
$thirdRow.recorded_at = '2026-09-15T00:00:01+10:00'
$thirdRow.previous_row_sha256 = [string]$trustedThree.rows[-1].row_sha256
$trustedThree.rows = @($trustedThree.rows) + @($thirdRow)
$prior = $trustedThree.rows[1]
$thirdRow.ledger_predecessor = [pscustomobject][ordered]@{
  prior_record_sha256 = Get-MIR4CurrentPackagePresentationV3PrefixRecordSha256 -Ledger $trustedThree -RowCount 2
  prior_row_sha256 = [string]$prior.row_sha256
  prior_row_count = 2
  prior_package_fingerprint_sha256 = [string]$prior.package_source.canonical_fingerprint_sha256
  prior_source_manifest_record_sha256 = [string]$prior.source_manifest.record_sha256
  prior_package_authority_record_sha256 = [string]$prior.package_authority.record_sha256
  prior_materializer_sha256 = [string]$prior.materializer_proof.normalized_text_sha256
  prior_binding_count = [int]$prior.package_source.binding_count
  prior_unique_binding_count = [int]$prior.package_source.unique_binding_count
}
$thirdRow.row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $thirdRow
Set-MIR4V3LedgerRecord -Ledger $trustedThree | Out-Null
Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $trustedThree -RequireLiveCurrent:$false | Out-Null
$ordinaryAppend = Assert-MIR4CurrentPackagePresentationV3ProtectedCustodyPrefix -RepoRoot $repo -CandidateLedger $trustedThree -TrustedLedger $ledger -TrustedBaseRef 'synthetic-two'
if ([string]$ordinaryAppend.status -cne 'protected-prefix-appended') { throw '[mir4-package-presentation-v3-custody-ordinary-append]' }

$tailDeletion = Copy-MIR4V3Ledger -Ledger $trustedThree
$tailDeletion.rows = @($tailDeletion.rows | Select-Object -SkipLast 1)
Set-MIR4V3LedgerRecord -Ledger $tailDeletion | Out-Null
Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $tailDeletion -RequireLiveCurrent:$false | Out-Null
$tailDeletionRejected = $false
try { Assert-MIR4CurrentPackagePresentationV3ProtectedCustodyPrefix -RepoRoot $repo -CandidateLedger $tailDeletion -TrustedLedger $trustedThree -TrustedBaseRef 'synthetic-three' | Out-Null } catch { $tailDeletionRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-custody-tail-retention\]' }
if (-not $tailDeletionRejected) { throw '[mir4-package-presentation-v3-custody-tail-deletion]' }

$nonconsecutiveReplay = Copy-MIR4V3Ledger -Ledger $ledger
$replaySecond = Copy-MIR4V3Ledger -Ledger ([pscustomobject]@{ rows = @($trustedThree.rows[2]) })
$replaySecond = $replaySecond.rows[0]
$replaySecond.sequence = 2
$replaySecond.row_id = 'mir4-current-package-presentation-v3-0002'
$replaySecond.previous_row_sha256 = [string]$ledger.rows[0].row_sha256
$replaySecond.ledger_predecessor = $ledger.rows[1].ledger_predecessor
$replaySecond.row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $replaySecond
$replayThird = Copy-MIR4V3Ledger -Ledger ([pscustomobject]@{ rows = @($trustedThree.rows[2]) })
$replayThird = $replayThird.rows[0]
$replayThird.sequence = 3
$replayThird.row_id = 'mir4-current-package-presentation-v3-0003'
$replayThird.recorded_at = '2026-09-15T00:00:02+10:00'
$replayThird.previous_row_sha256 = [string]$replaySecond.row_sha256
$nonconsecutiveReplay.rows = @($ledger.rows[0], $replaySecond, $replayThird)
$replayThird.ledger_predecessor = [pscustomobject][ordered]@{
  prior_record_sha256 = Get-MIR4CurrentPackagePresentationV3PrefixRecordSha256 -Ledger $nonconsecutiveReplay -RowCount 2
  prior_row_sha256 = [string]$replaySecond.row_sha256
  prior_row_count = 2
  prior_package_fingerprint_sha256 = [string]$replaySecond.package_source.canonical_fingerprint_sha256
  prior_source_manifest_record_sha256 = [string]$replaySecond.source_manifest.record_sha256
  prior_package_authority_record_sha256 = [string]$replaySecond.package_authority.record_sha256
  prior_materializer_sha256 = [string]$replaySecond.materializer_proof.normalized_text_sha256
  prior_binding_count = [int]$replaySecond.package_source.binding_count
  prior_unique_binding_count = [int]$replaySecond.package_source.unique_binding_count
}
$replayThird.row_sha256 = Get-MIR4CurrentPackagePresentationV3RowSha256 -Row $replayThird
Set-MIR4V3LedgerRecord -Ledger $nonconsecutiveReplay | Out-Null
Assert-MIR4CurrentPackagePresentationV3LedgerRecord -RepoRoot $repo -Ledger $nonconsecutiveReplay -RequireLiveCurrent:$false | Out-Null
$replayRejected = $false
try { Assert-MIR4CurrentPackagePresentationV3ProtectedCustodyPrefix -RepoRoot $repo -CandidateLedger $nonconsecutiveReplay -TrustedLedger $trustedThree -TrustedBaseRef 'synthetic-three' | Out-Null } catch { $replayRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-custody-prefix\]' }
if (-not $replayRejected) { throw '[mir4-package-presentation-v3-custody-nonconsecutive-replay]' }

$hostedUnavailableRejected = $false
try { Assert-MIR4CurrentPackagePresentationV3ProtectedCustody -RepoRoot $repo -TrustedBaseRef 'refs/remotes/origin/mir4-v3-missing' -HostedContext | Out-Null } catch { $hostedUnavailableRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-custody-base-unavailable\]' }
if (-not $hostedUnavailableRejected) { throw '[mir4-package-presentation-v3-hosted-unavailable-base]' }
$hostedUntrustedRejected = $false
try { Assert-MIR4CurrentPackagePresentationV3ProtectedCustody -RepoRoot $repo -TrustedBaseRef 'HEAD' -HostedContext | Out-Null } catch { $hostedUntrustedRejected = $_.Exception.Message -match '\[mir4-package-presentation-v3-custody-base-untrusted\]' }
if (-not $hostedUntrustedRejected) { throw '[mir4-package-presentation-v3-hosted-untrusted-base]' }

Assert-MIR4V3Reject -Name 'duplicate-append' -Action { & $writer -RepoRoot $repo -Append -SourceCommit ('a' * 40) | Out-Null }
if ([IO.File]::ReadAllText($ledgerPath) -cne $beforeText) { throw '[mir4-package-presentation-v3-append-drift]' }

$objectDbAfter = Get-MIR4V3SharedObjectDbSnapshot
if ($objectDbAfter -cne $objectDbBefore) { throw '[mir4-package-presentation-v3-shared-object-db-drift]' }

Write-Host '[ok] MIR4 V3 content-binds internal history and the live final row; protected remote custody, not standalone cryptography, retains the append-only tail.'
