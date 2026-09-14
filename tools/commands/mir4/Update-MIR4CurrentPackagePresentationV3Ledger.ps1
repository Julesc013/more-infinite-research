[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$SourceCommit = '',
  [string]$RecordedAt = '2026-09-15T00:00:00+10:00',
  [switch]$Append,
  [switch]$MigrateGenesis,
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

function Get-MIR4PackagePresentationV3CommitTree {
  param([Parameter(Mandatory)][string]$Commit)
  $tree = @(& git -C $repo show -s --format=%T $Commit 2>$null)
  if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1 -or [string]$tree[0] -notmatch '^[a-f0-9]{40}$') {
    throw "[mir4-package-presentation-v3-source-tree] $Commit"
  }
  return [string]$tree[0]
}

function Get-MIR4PackagePresentationV3HeadCommit {
  $head = (@(& git -C $repo rev-parse HEAD 2>$null) | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or [string]$head -notmatch '^[a-f0-9]{40}$') {
    throw '[mir4-package-presentation-v3-head]'
  }
  return [string]$head
}

function Get-MIR4PackagePresentationV3RowSha256 {
  param([Parameter(Mandatory)]$Row)
  $unsigned = [ordered]@{}
  foreach ($property in $Row.PSObject.Properties) {
    if ([string]$property.Name -cne 'row_sha256') { $unsigned[$property.Name] = $property.Value }
  }
  return Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value ([pscustomobject]$unsigned))
}

function Assert-MIR4PackagePresentationV3CleanSource {
  param([Parameter(Mandatory)][string]$Commit)
  $paths = @('src/mod', 'targets', 'tools/mir/application/package/TargetMaterializer.ps1')
  $dirty = @(& git -C $repo status --porcelain -- @paths 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir4-package-presentation-v3-source-status]' }
  if ($dirty.Count -ne 0) { throw '[mir4-package-presentation-v3-source-dirty]' }
  & git -C $repo diff --quiet $Commit -- @paths 2>$null
  if ($LASTEXITCODE -eq 1) { throw "[mir4-package-presentation-v3-source-commit-mismatch] $Commit" }
  if ($LASTEXITCODE -ne 0) { throw "[mir4-package-presentation-v3-source-commit] $Commit" }
}

function Get-MIR4PackagePresentationV3V2Predecessor {
  $raw = Get-Content -Raw -LiteralPath $v2Path
  $v2Schema = Join-Path $repo 'spec/schemas/mir4-current-package-presentation-v2.schema.json'
  if (-not ($raw | Test-Json -SchemaFile $v2Schema)) { throw '[mir4-package-presentation-v3-v2-schema]' }
  $v2 = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $v2) -or
      [string]$v2.kind -cne 'MIR4CurrentPackagePresentationV2' -or
      [string]$v2.record_sha256 -cne 'C33F1B568CA247108D88C4F2A109C45E29F2C77C4EE026CB4C9047BAA3A2360F') {
    throw '[mir4-package-presentation-v3-v2-predecessor]'
  }
  return $v2
}

function Get-MIR4PackagePresentationV3CommittedLedgerPredecessor {
  param(
    [Parameter(Mandatory)]$Ledger,
    [Parameter(Mandatory)][string]$Commit
  )

  $head = Get-MIR4PackagePresentationV3HeadCommit
  if ($Commit -cne $head) { throw "[mir4-package-presentation-v3-append-source-not-head] $Commit" }
  $dirty = @(& git -C $repo status --porcelain -- $ledgerRelative 2>$null)
  if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw '[mir4-package-presentation-v3-append-ledger-dirty]' }
  $workingIdentity = Get-MIRFileContentIdentity -Path $ledgerPath -RelativePath $ledgerRelative
  $committedIdentity = Get-MIRGitTextAtCommitSha256 -RepoRoot $repo -Commit $head -RelativePath $ledgerRelative
  if ([string]$workingIdentity.Sha256 -cne $committedIdentity) { throw '[mir4-package-presentation-v3-append-ledger-uncommitted]' }
  return [ordered]@{
    commit = $head
    tree = Get-MIR4PackagePresentationV3CommitTree -Commit $head
    path = $ledgerRelative
    normalized_text_sha256 = $committedIdentity
    record_sha256 = [string]$Ledger.record_sha256
    final_row_sha256 = [string](@($Ledger.rows)[-1].row_sha256)
    row_count = @($Ledger.rows).Count
  }
}

function New-MIR4PackagePresentationV3Row {
  param(
    [Parameter(Mandatory)][int]$Sequence,
    [Parameter(Mandatory)][string]$PreviousRowSha256,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$Timestamp,
    $LedgerPredecessor
  )

  Assert-MIR4PackagePresentationV3CleanSource -Commit $Commit
  $authority = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  $manifestPath = Join-Path $repo 'src/mod/package-source.json'
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100 -DateKind String
  $bindingCount = @($manifest.bindings).Count
  $uniqueBindingCount = @($manifest.bindings | ForEach-Object { "{0}|{1}" -f [string]$_.layer, [string]$_.output_path } | Sort-Object -Unique).Count
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest) -or
      [string]$manifest.materializer_abi -cne 'mir4-target-materializer/1' -or
      [string]$authority.writer.implementation -cne 'tools/mir/application/package/TargetMaterializer.ps1' -or
      -not [bool]$authority.writer.sole_current_writer -or
      [string]$authority.legacy_root_projection.compatibility_state -cne 'retired-historical-read-only' -or
      $bindingCount -ne $uniqueBindingCount) {
    throw '[mir4-package-presentation-v3-source-authority]'
  }
  $materializerRelative = 'tools/mir/application/package/TargetMaterializer.ps1'
  $materializerIdentity = Get-MIRFileContentIdentity -Path (Join-Path $repo $materializerRelative) -RelativePath $materializerRelative
  $row = [pscustomobject][ordered]@{
    sequence = $Sequence
    row_id = ('mir4-current-package-presentation-v3-{0:d4}' -f $Sequence)
    recorded_at = $Timestamp
    previous_row_sha256 = $PreviousRowSha256
    source_identity = [ordered]@{
      commit = $Commit
      tree = Get-MIR4PackagePresentationV3CommitTree -Commit $Commit
    }
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
  if ($null -ne $LedgerPredecessor) { $row | Add-Member -NotePropertyName ledger_predecessor -NotePropertyValue $LedgerPredecessor }
  $row.row_sha256 = Get-MIR4PackagePresentationV3RowSha256 -Row $row
  return $row
}

function Write-MIR4PackagePresentationV3NewOrIdentical {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    if ([IO.File]::ReadAllText($Path) -cne $Text) { throw "[mir4-package-presentation-v3-immutable-overwrite] $Path" }
    return
  }
  $parent = Split-Path -Parent $Path
  $temporary = Join-Path $parent ('.' + (Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary, $Path)
  } finally {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  }
}

if ($Check -and ($Append -or $MigrateGenesis)) { throw '[mir4-package-presentation-v3-check-mutation]' }

if ($Check) {
  if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) { throw '[mir4-package-presentation-v3-stale]' }
  . (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
  Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo | Out-Null
  [pscustomobject][ordered]@{status='current';path=$ledgerRelative;append_only=$true;publication_authorized=$false}
  return
}

if ($MigrateGenesis) {
  if ($Append) { throw '[mir4-package-presentation-v3-migrate-append]' }
  if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) { throw '[mir4-package-presentation-v3-migrate-missing-ledger]' }
  $legacy = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json -Depth 100 -DateKind String
  $legacyRows = @($legacy.rows)
  if ($legacyRows.Count -ne 1 -or
      [string]$legacyRows[0].row_sha256 -cne 'F16B81179F463B9C2C01863D7EEE6CEA123F10AFA0ADB64279CDC373F8CC88AC' -or
      $legacyRows[0].PSObject.Properties['ledger_predecessor'] -or
      $legacyRows[0].package_source.PSObject.Properties['binding_count'] -or
      [string]$legacyRows[0].source_identity.commit -cne 'b6cf5f19d24f4474ee9dbb0473e59ce9caa8b75d') {
    throw '[mir4-package-presentation-v3-migrate-genesis-contract]'
  }
  $v2 = Get-MIR4PackagePresentationV3V2Predecessor
  $row = New-MIR4PackagePresentationV3Row -Sequence 1 -PreviousRowSha256 ([string]$v2.record_sha256) -Commit ([string]$legacyRows[0].source_identity.commit) -Timestamp ([string]$legacyRows[0].recorded_at)
  $ledger = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4CurrentPackagePresentationV3Ledger'
    status = 'accepted-current-package-presentation-ledger'
    recorded_at = [string]$legacy.recorded_at
    predecessor = $legacy.predecessor
    authority_invariants = $legacy.authority_invariants
    append_only = $true
    genesis_row_sha256 = [string]$row.row_sha256
    rows = @($row)
    transition_gate = $legacy.transition_gate
    record_sha256 = ''
  }
  $ledger.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $ledger
  $json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $ledger) + [char]10
  if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-package-presentation-v3-migrate-schema]' }
  [IO.File]::WriteAllText($ledgerPath, $json, [Text.UTF8Encoding]::new($false))
  [pscustomobject][ordered]@{status='seed-contract-migrated';path=$ledgerRelative;rows=1;append_only=$true;publication_authorized=$false}
  return
}

if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
  $SourceCommit = (& git -C $repo rev-parse HEAD 2>$null).Trim()
}
if ($SourceCommit -notmatch '^[a-f0-9]{40}$') { throw '[mir4-package-presentation-v3-source-commit]' }
$sourceTree = Get-MIR4PackagePresentationV3CommitTree -Commit $SourceCommit
$v2 = Get-MIR4PackagePresentationV3V2Predecessor

if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
  . (Join-Path $repo 'tools/lib/mir4/PackagePresentation.ps1')
  $existing = Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo -RequireLiveCurrent:$false
  if (-not $Append) {
    Assert-MIR4CurrentPackagePresentationV3Ledger -RepoRoot $repo | Out-Null
    [pscustomobject][ordered]@{status='current';path=$ledgerRelative;rows=@($existing.rows).Count;append_only=$true;publication_authorized=$false}
    return
  }
  $previousRow = @($existing.rows)[-1]
  $row = New-MIR4PackagePresentationV3Row -Sequence (@($existing.rows).Count + 1) -PreviousRowSha256 ([string]$previousRow.row_sha256) -Commit $SourceCommit -Timestamp $RecordedAt
  $sameIdentity = (
    [string]$previousRow.package_source.canonical_fingerprint_sha256 -ceq [string]$row.package_source.canonical_fingerprint_sha256 -and
    [string]$previousRow.source_manifest.record_sha256 -ceq [string]$row.source_manifest.record_sha256 -and
    [string]$previousRow.package_authority.record_sha256 -ceq [string]$row.package_authority.record_sha256 -and
    [string]$previousRow.materializer_proof.normalized_text_sha256 -ceq [string]$row.materializer_proof.normalized_text_sha256 -and
    [int]$previousRow.package_source.binding_count -eq [int]$row.package_source.binding_count -and
    [int]$previousRow.package_source.unique_binding_count -eq [int]$row.package_source.unique_binding_count
  )
  if ($sameIdentity) { throw '[mir4-package-presentation-v3-append-duplicate]' }
  $ledgerPredecessor = Get-MIR4PackagePresentationV3CommittedLedgerPredecessor -Ledger $existing -Commit $SourceCommit
  $row = New-MIR4PackagePresentationV3Row -Sequence (@($existing.rows).Count + 1) -PreviousRowSha256 ([string]$previousRow.row_sha256) -Commit $SourceCommit -Timestamp $RecordedAt -LedgerPredecessor $ledgerPredecessor
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
    rows = $rows
    transition_gate = $existing.transition_gate
    record_sha256 = ''
  }
} else {
  if ($Append) { throw '[mir4-package-presentation-v3-append-missing-ledger]' }
  $row = New-MIR4PackagePresentationV3Row -Sequence 1 -PreviousRowSha256 ([string]$v2.record_sha256) -Commit $SourceCommit -Timestamp $RecordedAt
  $ledger = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4CurrentPackagePresentationV3Ledger'
    status = 'accepted-current-package-presentation-ledger'
    recorded_at = $RecordedAt
    predecessor = [ordered]@{
      path = $v2Relative
      kind = [string]$v2.kind
      hash_mode = 'record-self-hash'
      record_sha256 = [string]$v2.record_sha256
      retired_for_current_checkout = $true
    }
    authority_invariants = [ordered]@{
      one_emitter_preserved = $true
      gameplay_difference_authorized = $false
      source_freeze_authorized = $false
      candidate_allocation_authorized = $false
      signing_or_sealing_authorized = $false
      promotion_authorized = $false
      publication_authorized = $false
      player_package_mutation_authorized = $false
      prototype_write_authorized = $false
      public_support_authorized = $false
    }
    append_only = $true
    genesis_row_sha256 = [string]$row.row_sha256
    rows = @($row)
    transition_gate = [ordered]@{
      version_allocation = $false
      tagging = $false
      signing = $false
      sealing = $false
      publication = $false
    }
    record_sha256 = ''
  }
}

$ledger.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $ledger
$json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $ledger) + [char]10
if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-package-presentation-v3-schema]' }
if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
  $beforeRows = @($existing.rows)
  if ($beforeRows.Count -ge @($ledger.rows).Count) { throw '[mir4-package-presentation-v3-append-order]' }
  for ($index = 0; $index -lt $beforeRows.Count; $index++) {
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $beforeRows[$index]) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $ledger.rows[$index])) {
      throw '[mir4-package-presentation-v3-prior-row-mutation]'
    }
  }
  [IO.File]::WriteAllText($ledgerPath, $json, [Text.UTF8Encoding]::new($false))
} else {
  Write-MIR4PackagePresentationV3NewOrIdentical -Path $ledgerPath -Text $json
}

[pscustomobject][ordered]@{status=$(if($Append){'appended'}else{'initialized'});path=$ledgerRelative;source_commit=$SourceCommit;source_tree=$sourceTree;rows=@($ledger.rows).Count;append_only=$true;publication_authorized=$false}
