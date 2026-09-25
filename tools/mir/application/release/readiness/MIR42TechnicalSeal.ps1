Set-StrictMode -Version Latest

$mir42SealRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command Test-MIR4OpenSshSignatureV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/custody/OfflineCandidateCustody.ps1')
}
if (-not (Get-Command Assert-MIR42FourTargetPackageExcludedSurface -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
}

$script:MIR42SealTargets = @('f210', 'f200', 'f110', 'f100')

function Read-MIR42SealRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[$Code-missing] $Path" }
  try { $record = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[$Code-json] $Path" }
  if ($null -eq $record) { throw "[$Code-empty] $Path" }
  if ($record.PSObject.Properties.Name -notcontains 'record_sha256' -or
      [string]$record.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[$Code-record-hash] $Path" }
  return [pscustomobject][ordered]@{
    path = (Resolve-Path -LiteralPath $Path).Path
    sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    record = $record
  }
}

function Assert-MIR42SealSource {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Source,[Parameter(Mandatory)][string]$Code)
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ($Source.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Source.$field)) {
      throw "[$Code-source-field] $field"
    }
  }
  $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -cne [string]$Source.commit -or $tree -cne [string]$Source.tree) {
    throw "[$Code-source-tree-drift]"
  }
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  if ($packageSource -cne [string]$Source.package_source_sha256) { throw "[$Code-package-source-drift]" }
  return [pscustomobject][ordered]@{commit=$commit;tree=$tree;package_source_sha256=$packageSource}
}

function Assert-MIR42SealTargetSet {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  if ($actual.Count -ne 4 -or ($actual -join '|') -cne ($script:MIR42SealTargets -join '|')) {
    throw "[$Code-target-set]"
  }
}

function Resolve-MIR42SealContainedArtifactPath {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
      $RelativePath.Replace('\','/') -match '(^|/)\.\.(/|$)') { throw "[$Code-path]" }
  $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
  try {
    $null = Assert-MIR4DescendantPath -Root $Root -Path $candidate
    $null = Assert-MIR4NoReparseAncestors -Root $Root -Path $candidate
  } catch { throw "[$Code-path]" }
  return $candidate
}

function Get-MIR42ExactFourTargetCandidate {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$CandidateManifestPath)
  $candidateInput = Read-MIR42SealRecord -Path $CandidateManifestPath -Code 'mir42-seal-candidate'
  $candidate = $candidateInput.record
  if ([string]$candidate.kind -cne 'MIR42FourTargetDeterministicCandidateManifestV1' -or
      [string]$candidate.status -cne 'private-deterministic-four-target-candidate-built-unqualified' -or
      -not [bool]$candidate.build_complete -or
      [string]$candidate.qualification -cne 'not-performed' -or
      [bool]$candidate.publication_authorized) {
    throw '[mir42-seal-candidate-state]'
  }
  $candidateSource = [pscustomobject][ordered]@{
    commit = [string]$candidate.source.commit
    tree = [string]$candidate.source.tree
    package_source_sha256 = [string]$candidate.package_source_sha256
  }
  $source = Assert-MIR42SealSource -RepoRoot $RepoRoot -Source $candidateSource -Code 'mir42-seal-candidate'
  Assert-MIR42SealTargetSet -Rows @($candidate.targets) -Code 'mir42-seal-candidate'
  $root = Split-Path -Parent $candidateInput.path
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in @($candidate.targets)) {
    foreach ($field in @('target','distribution_version','target_row_path','asset','content_sha256','entry_count')) {
      if ($target.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-field] $([string]$target.target)/$field" }
    }
    if (-not [bool]$target.asset.bytes -or [string]$target.asset.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[mir42-seal-candidate-asset-shape] $([string]$target.target)"
    }
    $assetPath = Resolve-MIR42SealContainedArtifactPath -Root $root -RelativePath ([string]$target.asset.path) -Code 'mir42-seal-candidate-asset'
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$target.asset.sha256 -or
        [int64](Get-Item -LiteralPath $assetPath).Length -ne [int64]$target.asset.bytes) {
      throw "[mir42-seal-candidate-asset-drift] $([string]$target.target)"
    }
    $rowPath = Resolve-MIR42SealContainedArtifactPath -Root $root -RelativePath ([string]$target.target_row_path) -Code 'mir42-seal-candidate-target-row'
    $rowInput = Read-MIR42SealRecord -Path $rowPath -Code 'mir42-seal-target-row'
    $row = $rowInput.record
    $expected = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target ([string]$target.target) -SourceVersion '4.2.0'
    try { $inventory = Get-MIR4ArchiveInventory -Path $assetPath }
    catch { throw "[mir42-seal-candidate-archive-invalid] $([string]$target.target)" }
    if ([IO.Path]::GetFileName($assetPath) -cne [string]$expected.package_name -or
        [string]$inventory.root -cne [string]$expected.distribution_root -or
        [string]$target.distribution_version -cne [string]$expected.distribution_version -or
        [string]$inventory.archive_sha256 -cne [string]$target.asset.sha256 -or
        [string]$inventory.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$target.entry_count) {
      throw "[mir42-seal-candidate-package-identity] $([string]$target.target)"
    }
    Assert-MIR42FourTargetPackageExcludedSurface -Inventory $inventory -Target ([string]$target.target)
    try { $info = Read-MIR4ArchiveText -Path $assetPath -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String }
    catch { throw "[mir42-seal-candidate-info-json] $([string]$target.target)" }
    if ([string]$info.name -cne 'more-infinite-research' -or [string]$info.version -cne [string]$expected.distribution_version -or
        [string]$info.factorio_version -cne ([string]$expected.target_id -replace '^factorio-', '')) {
      throw "[mir42-seal-candidate-info-identity] $([string]$target.target)"
    }
    if ([string]$row.target -cne [string]$target.target -or
        [string]$row.distribution_version -cne [string]$target.distribution_version -or
        [string]$row.asset.sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$row.entry_count -ne [int]$target.entry_count -or
        -not [bool]$row.deterministic_archive_bytes -or -not [bool]$row.package_excluded_surface -or
        [string]$row.build_a_sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.build_b_sha256 -cne [string]$target.asset.sha256) {
      throw "[mir42-seal-candidate-target-row-drift] $([string]$target.target)"
    }
    $rows.Add([pscustomobject][ordered]@{
      target = [string]$target.target
      distribution_version = [string]$target.distribution_version
      archive_sha256 = [string]$target.asset.sha256
      content_sha256 = [string]$target.content_sha256
      entry_count = [int]$target.entry_count
    })
  }
  return [pscustomobject][ordered]@{identity=$candidateInput;source=$source;targets=@($rows)}
}

function Assert-MIR42ReceiptBinding {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code,[string]$ExpectedTargetStatus='passed')
  $record = $Receipt.record
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw "[$Code-candidate-binding]"
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code $Code
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1 -or [string]$row[0].distribution_version -cne [string]$candidateTarget.distribution_version -or
        [string]$row[0].archive.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$row[0].archive.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$row[0].archive.entry_count -ne [int]$candidateTarget.entry_count -or
        [string]$row[0].status -cne $ExpectedTargetStatus) {
      throw "[$Code-target-binding] $([string]$candidateTarget.target)"
    }
  }
}

function Assert-MIR42JoinedAcceptanceCoverage {
  param([Parameter(Mandatory)]$Receipt)
  $expectedCriteria = @(
    'fresh-exact-loads',
    'settings-profile-continuity',
    'research-progression',
    'migrations-two-reload',
    'compatibility-canaries',
    'target-omissions',
    'performance-telemetry',
    'package-exclusion',
    'deterministic-reconstruction'
  )
  $rows = @($Receipt.record.release_acceptance)
  $actualCriteria = @($rows | ForEach-Object { [string]$_.criterion })
  if ($rows.Count -ne $expectedCriteria.Count -or ($actualCriteria -join '|') -cne ($expectedCriteria -join '|')) {
    throw '[mir42-seal-qualification-joined-acceptance-missing]'
  }
  foreach ($row in $rows) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('criterion','status','observed_targets','not_applicable_targets','evidence','limits') -Code 'mir42-seal-qualification-joined-acceptance-shape'
    $observed = @($row.observed_targets | ForEach-Object { [string]$_ })
    $notApplicable = @($row.not_applicable_targets)
    $notApplicableIds = @($notApplicable | ForEach-Object { [string]$_.target })
    foreach ($omission in $notApplicable) {
      Assert-MIR42SealPropertyNames -Value $omission -Expected @('target','reason') -Code 'mir42-seal-qualification-not-applicable-shape'
      if ([string]::IsNullOrWhiteSpace([string]$omission.reason)) {
        throw "[mir42-seal-qualification-not-applicable-binding] $([string]$row.criterion)/$([string]$omission.target)"
      }
    }
    foreach ($evidence in @($row.evidence)) {
      Assert-MIR42SealPropertyNames -Value $evidence -Expected @('sha256','record_sha256') -Code 'mir42-seal-qualification-evidence-shape'
    }
    Assert-MIR42SealPropertyNames -Value $row.limits -Expected @('claim','known_limitations') -Code 'mir42-seal-qualification-limits-shape'
    if ([string]$row.status -cne 'passed' -or $observed.Count -eq 0 -or @($row.evidence).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$row.limits.claim) -or
        @($observed + $notApplicableIds).Count -ne $script:MIR42SealTargets.Count -or
        (@($observed + $notApplicableIds | Sort-Object -Unique).Count -ne $script:MIR42SealTargets.Count) -or
        ((@($observed + $notApplicableIds | Sort-Object { [array]::IndexOf($script:MIR42SealTargets, [string]$_) }) -join '|') -cne ($script:MIR42SealTargets -join '|')) -or
        @($row.evidence | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' -or [string]$_.record_sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0) {
      throw "[mir42-seal-qualification-joined-acceptance-binding] $([string]$row.criterion)"
    }
  }
}

function Get-MIR42ExactQualificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-qualification'
  if ([int]$receipt.record.schema -ne 1 -or [string]$receipt.record.kind -cne 'MIR42FourTargetEvidenceReconciliationV1' -or
      [string]$receipt.record.status -cne 'MIR-4.2-FOUR-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED' -or
      [int]$receipt.record.factorio_processes -ne 0 -or
      [string]$receipt.record.release_qualification -cne 'not-performed' -or
      [string]$receipt.record.independent_verification -cne 'not-performed' -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-evidence-reconciliation-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-qualification' -ExpectedTargetStatus 'reconciled'
  return $receipt
}

function Get-MIR42RealEngineCandidateCampaign {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Reconciliation)
  $campaign = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-real-engine'
  $record = $campaign.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','source','candidate_manifest','evidence_reconciliation','targets','factorio_processes','release_qualification','release_acceptance','technical_seal','publication_authorized','record_sha256') -Code 'mir42-seal-real-engine-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42FourTargetRealEngineCandidateCampaignV1' -or
      [string]$record.status -cne 'MIR-4.2-FOUR-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED' -or
      [string]$record.evidence_reconciliation.sha256 -cne [string]$Reconciliation.sha256 -or
      [string]$record.evidence_reconciliation.record_sha256 -cne [string]$Reconciliation.record.record_sha256 -or
      [int]$record.factorio_processes -lt 4 -or
      [string]$record.release_qualification -cne 'passed' -or
      [string]$record.technical_seal -cne 'not-performed' -or
      [bool]$record.publication_authorized) {
    throw '[mir42-seal-real-engine-campaign-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $campaign -Candidate $Candidate -Code 'mir42-seal-real-engine'
  foreach ($target in @($record.targets)) {
    Assert-MIR42SealPropertyNames -Value $target.engine_execution -Expected @('executable_sha256','version','harness_exit_code','logs','fresh_exact_load','predecessor_upgrade','reload_count') -Code 'mir42-seal-real-engine-target-shape'
    $logs = @($target.engine_execution.logs)
    $logPhases = @($logs | ForEach-Object { [string]$_.phase })
    foreach ($log in $logs) {
      Assert-MIR42SealPropertyNames -Value $log -Expected @('phase','sha256') -Code 'mir42-seal-real-engine-log-shape'
    }
    if ([string]$target.engine_execution.executable_sha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$target.engine_execution.version) -or
        [int]$target.engine_execution.harness_exit_code -ne 0 -or @($logs).Count -ne 4 -or
        ($logPhases -join '|') -cne 'create|load|reload|second-reload' -or
        @($logs | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0 -or
        -not [bool]$target.engine_execution.fresh_exact_load -or
        -not [bool]$target.engine_execution.predecessor_upgrade -or [int]$target.engine_execution.reload_count -lt 2) {
      throw "[mir42-seal-real-engine-target-binding] $([string]$target.target)"
    }
  }
  Assert-MIR42JoinedAcceptanceCoverage -Receipt $campaign
  return $campaign
}

function Get-MIR42ExactIndependentVerificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Qualification)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-independent'
  if ([int]$receipt.record.schema -ne 1 -or [string]$receipt.record.kind -cne 'MIR42FourTargetIndependentEvidenceRehashV1' -or
      [string]$receipt.record.status -cne 'MIR-4.2-FOUR-TARGET-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED' -or
      [int]$receipt.record.factorio_processes -ne 0 -or
      [string]$receipt.record.release_qualification -cne 'not-performed' -or
      [string]$receipt.record.independent_release_acceptance -cne 'not-performed' -or
      [string]$receipt.record.qualification.sha256 -cne [string]$Qualification.sha256 -or
      [string]$receipt.record.qualification.record_sha256 -cne [string]$Qualification.record.record_sha256 -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-independent-evidence-reconciliation-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-independent' -ExpectedTargetStatus 'reconciled'
  return $receipt
}

function Get-MIR42ProtectedSigningCeremony {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-signing'
  $schema = Join-Path $RepoRoot 'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $receipt.path
  if (-not ($raw | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) { throw '[mir42-seal-signing-schema]' }
  if ([string]$receipt.record.status -cne 'accepted-protected-signing-authority' -or
      [string]$receipt.record.authorization.decision -cne 'AUTHORIZED' -or
      [bool]$receipt.record.secret_values_present) { throw '[mir42-seal-signing-state]' }
  $governancePath = Join-Path $RepoRoot '.mir/releases/governance/mir4/release-governance.json'
  try { $governance = Get-Content -Raw -LiteralPath $governancePath | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw '[mir42-seal-governance-json]' }
  if ([string]$governance.kind -cne 'MIR4ReleaseGovernanceV1' -or
      [string]$governance.state -cne 'RELEASE-GOVERNANCE-READY' -or [string]$governance.acceptance -cne 'ACCEPTED' -or
      [bool]$governance.secret_values_present -or [string]$governance.signing_authority.public_key -cne [string]$receipt.record.public_signer.public_key -or
      [string]$governance.signing_authority.fingerprint -cne [string]$receipt.record.public_signer.fingerprint) {
    throw '[mir42-seal-governance-not-production-ready]'
  }
  $allowedPath = Join-Path $RepoRoot '.mir/releases/governance/mir4/allowed-signers.json'
  $allowed = Read-MIR42SealRecord -Path $allowedPath -Code 'mir42-seal-allowed-signers'
  $namespaces = @($allowed.record.rows | ForEach-Object { [string]$_.namespace } | Sort-Object -Unique)
  $ledgerRows = @($allowed.record.rows | Where-Object { [string]$_.namespace -ceq 'mir4-ledger' })
  if ([string]$receipt.record.allowed_signers.record_sha256 -cne [string]$allowed.record.record_sha256 -or
      [string]$allowed.record.kind -cne 'MIR4AllowedSignersV1' -or [string]$allowed.record.state -ceq 'awaiting-protected-key' -or
      @($allowed.record.rows).Count -ne 3 -or (($namespaces -join '|') -cne 'mir4-ledger|mir4-source|mir4-target') -or
      $ledgerRows.Count -ne 1 -or [string]$ledgerRows[0].status -cne 'active' -or
      [string]$ledgerRows[0].principal -cne [string]$receipt.record.public_signer.principal -or
      [string]$ledgerRows[0].public_key -cne [string]$receipt.record.public_signer.public_key -or
      [string]$ledgerRows[0].fingerprint -cne [string]$receipt.record.public_signer.fingerprint) {
    throw '[mir42-seal-approved-signer-missing]'
  }
  return [pscustomobject][ordered]@{path=$receipt.path;sha256=$receipt.sha256;record=$receipt.record;ledger_signer=$ledgerRows[0]}
}

function Assert-MIR42SealPropertyNames {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Code)
  $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
  if ($actual.Count -ne $Expected.Count -or @($actual | Where-Object { $_ -cnotin $Expected }).Count -ne 0) { throw "[$Code]" }
}

function Get-MIR42SourceFreezeLedgerPayload {
  param([Parameter(Mandatory)]$Record)
  Assert-MIR42SealPropertyNames -Value $Record -Expected @('schema','kind','status','source','frozen_dev','promotion_base','candidate_manifest','signing_ceremony','independent_reviewer','transition_gate','ledger_signature','record_sha256') -Code 'mir42-seal-freeze-authority-shape'
  Assert-MIR42SealPropertyNames -Value $Record.frozen_dev -Expected @('ref','commit','tree') -Code 'mir42-seal-freeze-frozen-dev-shape'
  Assert-MIR42SealPropertyNames -Value $Record.promotion_base -Expected @('remote','ref','commit') -Code 'mir42-seal-freeze-promotion-base-shape'
  Assert-MIR42SealPropertyNames -Value $Record.ledger_signature -Expected @('identity','namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-freeze-ledger-signature-shape'
  Assert-MIR42SealPropertyNames -Value $Record.independent_reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-freeze-reviewer-shape'
  return [pscustomobject][ordered]@{
    schema = [int]$Record.schema
    kind = [string]$Record.kind
    status = [string]$Record.status
    source = $Record.source
    frozen_dev = $Record.frozen_dev
    promotion_base = $Record.promotion_base
    candidate_manifest = $Record.candidate_manifest
    signing_ceremony = $Record.signing_ceremony
    independent_reviewer = $Record.independent_reviewer
    transition_gate = $Record.transition_gate
  }
}

function Assert-MIR42SourceFreezeLedgerSignature {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Authority,
    [Parameter(Mandatory)]$Signing,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $record = $Authority.record
  $signature = $record.ledger_signature
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42SourceFreezeLedgerPayload -Record $record)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload)))
  if ([string]$signature.identity -cne [string]$Signing.ledger_signer.principal -or
      [string]$signature.namespace -cne 'mir4-ledger' -or
      [string]$signature.payload_sha256 -cne $payloadSha -or
      [string]$signature.signature_sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not [IO.Path]::IsPathRooted([string]$signature.signature_path)) {
    throw '[mir42-seal-freeze-ledger-signature-binding]'
  }
  $signaturePath = [IO.Path]::GetFullPath([string]$signature.signature_path)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($signaturePath.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $signaturePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$signature.signature_sha256) {
    throw '[mir42-seal-freeze-ledger-signature-path]'
  }
  $scratch = Join-Path ([IO.Path]::GetTempPath()) ('mir42-ledger-signature-' + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKey = Join-Path $scratch 'ledger-signing.pub'
    $payloadPath = Join-Path $scratch 'source-freeze-payload.json'
    [IO.File]::WriteAllText($publicKey, ([string]$Signing.ledger_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payload, [Text.UTF8Encoding]::new($false))
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey -Identity ([string]$Signing.ledger_signer.principal) -Namespace 'mir4-ledger' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-freeze-ledger-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
  }
}

function Get-MIR42SourceFreezeAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Signing,[Parameter(Mandatory)][string]$SshKeygenPath)
  $authority = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-freeze'
  $record = $authority.record
  $null = Get-MIR42SourceFreezeLedgerPayload -Record $record
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42SourceFreezeAuthorizationV1' -or
      [string]$record.status -cne 'MIR-4.2-SOURCE-FROZEN-AND-CANDIDATE-ALLOCATED' -or
      [string]$record.signing_ceremony.sha256 -cne [string]$Signing.sha256 -or
      [string]$record.signing_ceremony.record_sha256 -cne [string]$Signing.record.record_sha256 -or
      -not [bool]$record.transition_gate.source_freeze -or -not [bool]$record.transition_gate.candidate_allocation -or
      -not [bool]$record.transition_gate.production_signing -or [bool]$record.transition_gate.technical_seal) {
    throw '[mir42-seal-freeze-authority-state]'
  }
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw '[mir42-seal-freeze-authority-binding]'
  }
  if ([string]$record.frozen_dev.ref -cne 'refs/heads/dev' -or
      [string]$record.frozen_dev.commit -cne [string]$Candidate.source.commit -or
      [string]$record.frozen_dev.tree -cne [string]$Candidate.source.tree -or
      [string]$record.promotion_base.remote -cne 'origin' -or
      [string]$record.promotion_base.ref -cne 'refs/heads/main' -or
      [string]$record.promotion_base.commit -notmatch '^[0-9a-f]{40}$') {
    throw '[mir42-seal-freeze-promotion-topology-binding]'
  }
  Assert-MIR42SourceFreezeLedgerSignature -RepoRoot $RepoRoot -Authority $authority -Signing $Signing -SshKeygenPath $SshKeygenPath
  return $authority
}

function Get-MIR42IndependentReviewerAttestation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Independent,
    [Parameter(Mandatory)]$Campaign,
    [Parameter(Mandatory)]$Freeze,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $attestation = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-reviewer'
  $record = $attestation.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','independent_verification','real_engine_campaign','source_freeze_authority','acceptance_coverage','reviewer','review_signature','record_sha256') -Code 'mir42-seal-reviewer-shape'
  Assert-MIR42SealPropertyNames -Value $record.reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-reviewer-identity-shape'
  Assert-MIR42SealPropertyNames -Value $record.review_signature -Expected @('namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-reviewer-signature-shape'
  $trusted = $Freeze.record.independent_reviewer
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42IndependentReviewerAttestationV1' -or
      [string]$record.status -cne 'MIR-4.2-INDEPENDENT-REVIEW-ACCEPTED' -or
      [string]$record.independent_verification.sha256 -cne [string]$Independent.sha256 -or
      [string]$record.independent_verification.record_sha256 -cne [string]$Independent.record.record_sha256 -or
      [string]$record.real_engine_campaign.sha256 -cne [string]$Campaign.sha256 -or
      [string]$record.real_engine_campaign.record_sha256 -cne [string]$Campaign.record.record_sha256 -or
      [string]$record.source_freeze_authority.sha256 -cne [string]$Freeze.sha256 -or
      [string]$record.source_freeze_authority.record_sha256 -cne [string]$Freeze.record.record_sha256 -or
      [string]$record.reviewer.identity -cne [string]$trusted.identity -or
      [string]$record.reviewer.public_key -cne [string]$trusted.public_key -or
      [string]$record.reviewer.fingerprint -cne [string]$trusted.fingerprint -or
      [string]$record.review_signature.namespace -cne 'mir4-independent-review' -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $record.acceptance_coverage) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Campaign.record.release_acceptance) -or
      [string]$record.review_signature.signature_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir42-seal-reviewer-binding]'
  }
  $payload = [pscustomobject][ordered]@{
    schema = [int]$record.schema
    kind = [string]$record.kind
    status = [string]$record.status
    independent_verification = $record.independent_verification
    real_engine_campaign = $record.real_engine_campaign
    source_freeze_authority = $record.source_freeze_authority
    acceptance_coverage = $record.acceptance_coverage
    reviewer = $record.reviewer
  }
  $payloadJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $payload
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payloadJson)))
  $signaturePath = [string]$record.review_signature.signature_path
  if ([string]$record.review_signature.payload_sha256 -cne $payloadSha -or -not [IO.Path]::IsPathRooted($signaturePath)) {
    throw '[mir42-seal-reviewer-signature-path]'
  }
  $signaturePath = [IO.Path]::GetFullPath($signaturePath)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($signaturePath.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $signaturePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.review_signature.signature_sha256) {
    throw '[mir42-seal-reviewer-signature-path]'
  }
  $scratch = Join-Path ([IO.Path]::GetTempPath()) ('mir42-review-signature-' + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKey = Join-Path $scratch 'reviewer.pub'; $payloadPath = Join-Path $scratch 'review.json'
    [IO.File]::WriteAllText($publicKey, ([string]$trusted.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payloadJson, [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey) -cne [string]$trusted.fingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey -Identity ([string]$trusted.identity) -Namespace 'mir4-independent-review' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-reviewer-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
  }
  return $attestation
}

function Get-MIR42FourTargetTechnicalSealReadiness {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$QualificationPath='',
    [string]$RealEngineCampaignPath='',
    [string]$IndependentVerificationPath='',
    [string]$SigningCeremonyPath='',
    [string]$SourceFreezeAuthorityPath='',
    [string]$ReviewerAttestationPath='',
    [string]$SshKeygenPath=''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $checks = [ordered]@{}
  $blockers = [Collections.Generic.List[string]]::new()
  $state = [ordered]@{candidate=$null;qualification=$null;campaign=$null;independent=$null;signing=$null;freeze=$null;reviewer=$null}
  try { $state.candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath; $checks.candidate = $true } catch { $checks.candidate = $false; $blockers.Add($_.Exception.Message) }
  if ($checks.candidate -and -not [string]::IsNullOrWhiteSpace($QualificationPath)) { try { $state.qualification = Get-MIR42ExactQualificationReceipt -Path $QualificationPath -Candidate $state.candidate; $checks.qualification = $true } catch { $checks.qualification = $false; $blockers.Add($_.Exception.Message) } } else { $checks.qualification = $false; $blockers.Add('[mir42-seal-qualification-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($RealEngineCampaignPath)) { try { $state.campaign = Get-MIR42RealEngineCandidateCampaign -Path $RealEngineCampaignPath -Candidate $state.candidate -Reconciliation $state.qualification; $checks.campaign = $true } catch { $checks.campaign = $false; $blockers.Add($_.Exception.Message) } } else { $checks.campaign = $false; $blockers.Add('[mir42-seal-real-engine-campaign-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($IndependentVerificationPath)) { try { $state.independent = Get-MIR42ExactIndependentVerificationReceipt -Path $IndependentVerificationPath -Candidate $state.candidate -Qualification $state.qualification; $checks.independent = $true } catch { $checks.independent = $false; $blockers.Add($_.Exception.Message) } } else { $checks.independent = $false; $blockers.Add('[mir42-seal-independent-missing]') }
  if (-not [string]::IsNullOrWhiteSpace($SigningCeremonyPath)) { try { $state.signing = Get-MIR42ProtectedSigningCeremony -RepoRoot $repo -Path $SigningCeremonyPath; $checks.signing = $true } catch { $checks.signing = $false; $blockers.Add($_.Exception.Message) } } else { $checks.signing = $false; $blockers.Add('[mir42-seal-signing-missing]') }
  if ($checks.candidate -and $checks.signing -and -not [string]::IsNullOrWhiteSpace($SourceFreezeAuthorityPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.freeze = Get-MIR42SourceFreezeAuthority -RepoRoot $repo -Path $SourceFreezeAuthorityPath -Candidate $state.candidate -Signing $state.signing -SshKeygenPath $SshKeygenPath; $checks.freeze = $true } catch { $checks.freeze = $false; $blockers.Add($_.Exception.Message) } } else { $checks.freeze = $false; $blockers.Add('[mir42-seal-freeze-authority-or-verifier-missing]') }
  if ($checks.qualification -and $checks.campaign -and $checks.independent -and $checks.freeze -and -not [string]::IsNullOrWhiteSpace($ReviewerAttestationPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.reviewer = Get-MIR42IndependentReviewerAttestation -RepoRoot $repo -Path $ReviewerAttestationPath -Independent $state.independent -Campaign $state.campaign -Freeze $state.freeze -SshKeygenPath $SshKeygenPath; $checks.reviewer = $true } catch { $checks.reviewer = $false; $blockers.Add($_.Exception.Message) } } else { $checks.reviewer = $false; $blockers.Add('[mir42-seal-independent-reviewer-attestation-missing]') }
  $ready = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalSealReadinessV1'
    status = if ($ready) { 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-READY' } else { 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-BLOCKED' }
    checks = [pscustomobject]$checks
    blockers = @($blockers | Select-Object -Unique)
    technical_seal_authorized = $ready
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    _state = [pscustomobject]$state
  }
}

function New-MIR42FourTargetTechnicalSeal {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [AllowEmptyString()][string]$QualificationPath='',
    [AllowEmptyString()][string]$RealEngineCampaignPath='',
    [AllowEmptyString()][string]$IndependentVerificationPath='',
    [AllowEmptyString()][string]$SigningCeremonyPath='',
    [AllowEmptyString()][string]$SourceFreezeAuthorityPath='',
    [AllowEmptyString()][string]$ReviewerAttestationPath='',
    [AllowEmptyString()][string]$SshKeygenPath='',
    [Parameter(Mandatory)][string]$OutputPath
  )
  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-seal-not-authorized] $($readiness.blockers -join '; ')" }
  $state = $readiness._state
  $seal = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalSealV1'
    status = 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    source = $state.candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$state.candidate.identity.sha256;record_sha256=[string]$state.candidate.identity.record.record_sha256}
    qualification = [ordered]@{sha256=[string]$state.qualification.sha256;record_sha256=[string]$state.qualification.record.record_sha256}
    real_engine_campaign = [ordered]@{sha256=[string]$state.campaign.sha256;record_sha256=[string]$state.campaign.record.record_sha256}
    independent_verification = [ordered]@{sha256=[string]$state.independent.sha256;record_sha256=[string]$state.independent.record.record_sha256}
    signing_ceremony = [ordered]@{sha256=[string]$state.signing.sha256;record_sha256=[string]$state.signing.record.record_sha256}
    source_freeze_authority = [ordered]@{sha256=[string]$state.freeze.sha256;record_sha256=[string]$state.freeze.record.record_sha256}
    independent_reviewer_attestation = [ordered]@{sha256=[string]$state.reviewer.sha256;record_sha256=[string]$state.reviewer.record.record_sha256}
    targets = @($state.candidate.targets)
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  $seal.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $seal
  Write-MIR4BootstrapRecord -Record $seal -Path $OutputPath | Out-Null
  return $seal
}
