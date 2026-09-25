Set-StrictMode -Version Latest

$mir42PromotionRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Get-MIR42ExactFourTargetCandidate -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'MIR42TechnicalSeal.ps1')
}

function Get-MIR42PromotionRemoteRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref,[Parameter(Mandatory)][string]$Code)
  $rows = @(& git -C $RepoRoot ls-remote --refs origin $Ref 2>$null)
  if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1 -or $rows[0] -notmatch '^([a-f0-9]{40})\s+') {
    throw "[$Code]"
  }
  return [string]$Matches[1]
}

function Assert-MIR42PromotionExternalPath {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($full.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $full -ceq $repo) { throw "[$Code-repository]" }
  if (Test-Path -LiteralPath $full) {
    try {
      $cursor = $full
      while ($true) {
        if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
        $cursor = $parent
      }
    } catch { throw "[$Code-reparse]" }
  }
  return $full
}

function Assert-MIR42PromotionExternalImmutableFile {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Sha256,[Parameter(Mandatory)][string]$Code)
  $full = Assert-MIR42PromotionExternalPath -RepoRoot $RepoRoot -Path $Path -Code $Code
  $resolved = Resolve-MIR42SealImmutableFile -Path $full -Sha256 $Sha256 -Code $Code
  return $resolved
}

function Test-MIR42PromotionContainedPath {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path)
  try {
    $null = Assert-MIR4DescendantPath -Root $Root -Path $Path
    $null = Assert-MIR4NoReparseAncestors -Root $Root -Path $Path
    return $true
  } catch { return $false }
}

function Get-MIR42PromotionGitBlobSha256 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Revision,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = 'git'
  $info.UseShellExecute = $false
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $null = $info.ArgumentList.Add('-C')
  $null = $info.ArgumentList.Add($RepoRoot)
  $null = $info.ArgumentList.Add('show')
  $null = $info.ArgumentList.Add("$Revision`:$RelativePath")
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  try {
    if (-not $process.Start()) { throw "[$Code-start]" }
    $bytes = [IO.MemoryStream]::new()
    try {
      $process.StandardOutput.BaseStream.CopyTo($bytes)
      $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes.ToArray()))
    } finally { $bytes.Dispose() }
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[$Code-show] $stderr" }
    return $digest
  } finally {
    $process.Dispose()
  }
}

function Get-MIR42GovernedOfflineRestoreLedgerChallengePayload {
  param([Parameter(Mandatory)]$Record)
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetGovernedOfflineRestoreChallengeV1'
    source = $Record.source
    candidate_manifest = $Record.candidate_manifest
    technical_seal = $Record.technical_seal
    protected_signing_ceremony = $Record.protected_signing_ceremony
    recovery_custody = $Record.recovery_custody
    clean_rehydrate = $Record.clean_rehydrate
    restored_inventory = $Record.restored_inventory
    targets = $Record.targets
  }
}

function Assert-MIR42GovernedOfflineRestoreReference {
  param([Parameter(Mandatory)]$Reference,[Parameter(Mandatory)]$Expected,[Parameter(Mandatory)][string]$Code)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('path','sha256','record_sha256') -Code "$Code-shape"
  if ([string]$Reference.sha256 -cne [string]$Expected.sha256 -or [string]$Reference.record_sha256 -cne [string]$Expected.record.record_sha256) {
    throw "[$Code-binding]"
  }
}

function Get-MIR42GovernedOfflineRestoreDrill {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Candidate,
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)]$Signing,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-promotion-governed-restore'
  $record = $receipt.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','source','candidate_manifest','technical_seal','protected_signing_ceremony','recovery_custody','clean_rehydrate','restored_inventory','targets','ledger_challenge','publication_authorized','record_sha256') -Code 'mir42-promotion-governed-restore-shape'
  if ([int]$record.schema -ne 1 -or
      [string]$record.kind -cne 'MIR42FourTargetGovernedOfflineRestoreDrillV1' -or
      [string]$record.status -cne 'MIR-4.2-FOUR-TARGET-GOVERNED-OFFLINE-RESTORE-PASSED-POST-SEAL' -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256 -or
      [bool]$record.publication_authorized) {
    throw '[mir42-promotion-governed-restore-state]'
  }
  Assert-MIR42GovernedOfflineRestoreReference -Reference $record.candidate_manifest -Expected $Candidate.identity -Code 'mir42-promotion-governed-restore-candidate'
  Assert-MIR42GovernedOfflineRestoreReference -Reference $record.technical_seal -Expected $Seal -Code 'mir42-promotion-governed-restore-seal'
  Assert-MIR42GovernedOfflineRestoreReference -Reference $record.protected_signing_ceremony -Expected $Signing -Code 'mir42-promotion-governed-restore-signing'
  foreach ($binding in @(@($record.candidate_manifest,$Candidate.identity),@($record.technical_seal,$Seal),@($record.protected_signing_ceremony,$Signing))) {
    $bound = Read-MIR42SealRecord -Path ([string]$binding[0].path) -Code 'mir42-promotion-governed-restore-bound-record'
    if ([string]$bound.sha256 -cne [string]$binding[1].sha256 -or [string]$bound.record.record_sha256 -cne [string]$binding[1].record.record_sha256) {
      throw '[mir42-promotion-governed-restore-bound-record-drift]'
    }
  }

  Assert-MIR42SealPropertyNames -Value $record.recovery_custody -Expected @('copy_a','copy_b','clean_restore_copy_id') -Code 'mir42-promotion-governed-restore-custody-shape'
  $declaredCopies = @($record.recovery_custody.copy_a,$record.recovery_custody.copy_b)
  if ([string]$record.recovery_custody.clean_restore_copy_id -cne [string]$Signing.record.recovery.clean_restore.copy_id -or
      [string]$declaredCopies[0].copy_id -ceq [string]$declaredCopies[1].copy_id) {
    throw '[mir42-promotion-governed-restore-custody-state]'
  }
  $copyRoots = [Collections.Generic.List[string]]::new()
  foreach ($copy in $declaredCopies) {
    Assert-MIR42SealPropertyNames -Value $copy -Expected @('copy_id','encryption_method','ciphertext_path','ciphertext_sha256','location_class','custodian_class') -Code 'mir42-promotion-governed-restore-copy-shape'
    $trusted = @($Signing.record.recovery.copies | Where-Object { [string]$_.copy_id -ceq [string]$copy.copy_id })
    if ($trusted.Count -ne 1 -or
        [string]$copy.encryption_method -cne [string]$trusted[0].encryption_method -or
        [string]$copy.ciphertext_sha256 -cne [string]$trusted[0].ciphertext_sha256 -or
        [string]$copy.location_class -cne [string]$trusted[0].location_class -or
        [string]$copy.custodian_class -cne [string]$trusted[0].custodian_class -or
        [string]$copy.encryption_method -match '(?i)(^|[-_ ])(none|plain|unencrypted)([-_ ]|$)') {
      throw '[mir42-promotion-governed-restore-copy-binding]'
    }
    $copyPath = Assert-MIR42PromotionExternalImmutableFile -RepoRoot $RepoRoot -Path ([string]$copy.ciphertext_path) -Sha256 ([string]$copy.ciphertext_sha256) -Code 'mir42-promotion-governed-restore-copy'
    $copyRoots.Add((Split-Path -Parent $copyPath))
  }
  if ((Test-MIR42PromotionContainedPath -Root $copyRoots[0] -Path $copyRoots[1]) -or (Test-MIR42PromotionContainedPath -Root $copyRoots[1] -Path $copyRoots[0])) {
    throw '[mir42-promotion-governed-restore-copy-root-separation]'
  }

  Assert-MIR42SealPropertyNames -Value $record.clean_rehydrate -Expected @('root','root_initially_empty','source_candidate_absent','materializer_absent','network_disabled','recovery_copy_id','ephemeral_plaintext_destroyed') -Code 'mir42-promotion-governed-restore-clean-root-shape'
  $cleanRoot = Assert-MIR42PromotionExternalPath -RepoRoot $RepoRoot -Path ([string]$record.clean_rehydrate.root) -Code 'mir42-promotion-governed-restore-clean-root'
  if (-not (Test-Path -LiteralPath $cleanRoot -PathType Container) -or
      -not [bool]$record.clean_rehydrate.root_initially_empty -or
      -not [bool]$record.clean_rehydrate.source_candidate_absent -or
      -not [bool]$record.clean_rehydrate.materializer_absent -or
      -not [bool]$record.clean_rehydrate.network_disabled -or
      -not [bool]$record.clean_rehydrate.ephemeral_plaintext_destroyed -or
      [string]$record.clean_rehydrate.recovery_copy_id -cne [string]$Signing.record.recovery.clean_restore.copy_id -or
      @($declaredCopies | Where-Object { [string]$_.copy_id -ceq [string]$record.clean_rehydrate.recovery_copy_id }).Count -ne 1 -or
      (Test-MIR42PromotionContainedPath -Root $cleanRoot -Path $copyRoots[0]) -or
      (Test-MIR42PromotionContainedPath -Root $cleanRoot -Path $copyRoots[1])) {
    throw '[mir42-promotion-governed-restore-clean-root-state]'
  }

  $restoredInventory = @($record.restored_inventory)
  $requiredRestoredHashes = @([string]$Candidate.identity.sha256,[string]$Seal.sha256) + @($Candidate.targets | ForEach-Object { [string]$_.archive_sha256 })
  if ($restoredInventory.Count -ne $requiredRestoredHashes.Count) { throw '[mir42-promotion-governed-restore-inventory-count]' }
  foreach ($restored in $restoredInventory) {
    Assert-MIR42SealPropertyNames -Value $restored -Expected @('path','sha256') -Code 'mir42-promotion-governed-restore-inventory-row-shape'
    $restoredPath = Assert-MIR42PromotionExternalImmutableFile -RepoRoot $RepoRoot -Path ([string]$restored.path) -Sha256 ([string]$restored.sha256) -Code 'mir42-promotion-governed-restore-inventory-row'
    if (-not (Test-MIR42PromotionContainedPath -Root $cleanRoot -Path $restoredPath)) { throw '[mir42-promotion-governed-restore-inventory-root]' }
  }
  foreach ($requiredHash in $requiredRestoredHashes) {
    if (@($restoredInventory | Where-Object { [string]$_.sha256 -ceq $requiredHash }).Count -ne 1) { throw '[mir42-promotion-governed-restore-inventory-binding]' }
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code 'mir42-promotion-governed-restore'
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1) { throw "[mir42-promotion-governed-restore-target-cardinality] $([string]$candidateTarget.target)" }
    Assert-MIR42SealPropertyNames -Value $row[0] -Expected @('target','restored_archive') -Code 'mir42-promotion-governed-restore-target-shape'
    Assert-MIR42SealPropertyNames -Value $row[0].restored_archive -Expected @('path','sha256','content_sha256','entry_count') -Code 'mir42-promotion-governed-restore-target-archive-shape'
    if ([string]$row[0].restored_archive.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$row[0].restored_archive.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$row[0].restored_archive.entry_count -ne [int]$candidateTarget.entry_count) {
      throw "[mir42-promotion-governed-restore-target-binding] $([string]$candidateTarget.target)"
    }
    $restoredPath = Assert-MIR42PromotionExternalImmutableFile -RepoRoot $RepoRoot -Path ([string]$row[0].restored_archive.path) -Sha256 ([string]$row[0].restored_archive.sha256) -Code 'mir42-promotion-governed-restore-target-archive'
    if (-not (Test-MIR42PromotionContainedPath -Root $cleanRoot -Path $restoredPath)) { throw '[mir42-promotion-governed-restore-target-root]' }
    try { $inventory = Get-MIR4ArchiveInventory -Path $restoredPath } catch { throw "[mir42-promotion-governed-restore-target-archive-invalid] $([string]$candidateTarget.target)" }
    if ([string]$inventory.archive_sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$inventory.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$candidateTarget.entry_count) {
      throw "[mir42-promotion-governed-restore-target-archive-inventory] $([string]$candidateTarget.target)"
    }
  }

  Assert-MIR42SealPropertyNames -Value $record.ledger_challenge -Expected @('ledger_repository','event','predecessor_event','challenge','signature') -Code 'mir42-promotion-governed-restore-ledger-shape'
  Assert-MIR42SealPropertyNames -Value $record.ledger_challenge.ledger_repository -Expected @('root','remote','ref','commit','event_relative_path','predecessor_event_relative_path') -Code 'mir42-promotion-governed-restore-ledger-repository-shape'
  $ledger = $record.ledger_challenge.ledger_repository
  $ledgerRoot = Assert-MIR42PromotionExternalPath -RepoRoot $RepoRoot -Path ([string]$ledger.root) -Code 'mir42-promotion-governed-restore-ledger-root'
  if (-not (Test-Path -LiteralPath (Join-Path $ledgerRoot '.git')) -or [string]$ledger.remote -notmatch '^[A-Za-z0-9._-]+$' -or
      [string]$ledger.ref -notmatch '^refs/heads/[A-Za-z0-9._/-]+$' -or [string]$ledger.commit -notmatch '^[a-f0-9]{40}$' -or
      [string]$ledger.event_relative_path -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted([string]$ledger.event_relative_path) -or
      [string]$ledger.predecessor_event_relative_path -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted([string]$ledger.predecessor_event_relative_path)) {
    throw '[mir42-promotion-governed-restore-ledger-repository-state]'
  }
  $remoteRows = @(& git -C $ledgerRoot ls-remote --refs ([string]$ledger.remote) ([string]$ledger.ref) 2>$null)
  $remoteCommit = if ($remoteRows.Count -eq 1 -and $remoteRows[0] -match '^([a-f0-9]{40})\s+') { [string]$Matches[1] } else { '' }
  $commit = (& git -C $ledgerRoot rev-parse "$([string]$ledger.commit)^{commit}" 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or $remoteCommit -cne [string]$ledger.commit -or $commit -cne [string]$ledger.commit) { throw '[mir42-promotion-governed-restore-ledger-ref]' }
  foreach ($field in @('event','predecessor_event','challenge','signature')) {
    Assert-MIR42SealPropertyNames -Value $record.ledger_challenge.$field -Expected @('path','sha256') -Code "mir42-promotion-governed-restore-ledger-$field-shape"
    $null = Assert-MIR42PromotionExternalImmutableFile -RepoRoot $RepoRoot -Path ([string]$record.ledger_challenge.$field.path) -Sha256 ([string]$record.ledger_challenge.$field.sha256) -Code "mir42-promotion-governed-restore-ledger-$field"
  }
  $eventPath = [string]$record.ledger_challenge.event.path
  if ((Get-MIR42PromotionGitBlobSha256 -RepoRoot $ledgerRoot -Revision ([string]$ledger.commit) -RelativePath ([string]$ledger.event_relative_path) -Code 'mir42-promotion-governed-restore-ledger-event') -cne [string]$record.ledger_challenge.event.sha256 -or
      (Get-MIR42PromotionGitBlobSha256 -RepoRoot $ledgerRoot -Revision ([string]$ledger.commit) -RelativePath ([string]$ledger.predecessor_event_relative_path) -Code 'mir42-promotion-governed-restore-ledger-predecessor') -cne [string]$record.ledger_challenge.predecessor_event.sha256) {
    throw '[mir42-promotion-governed-restore-ledger-event-commit-binding]'
  }
  $eventRaw = Get-Content -Raw -LiteralPath $eventPath
  $eventSchema = Join-Path $RepoRoot 'spec/schemas/mir4-release-ledger-event.schema.json'
  if (-not ($eventRaw | Test-Json -SchemaFile $eventSchema -ErrorAction SilentlyContinue)) { throw '[mir42-promotion-governed-restore-ledger-event-schema]' }
  $predecessorRaw = Get-Content -Raw -LiteralPath ([string]$record.ledger_challenge.predecessor_event.path)
  if (-not ($predecessorRaw | Test-Json -SchemaFile $eventSchema -ErrorAction SilentlyContinue)) { throw '[mir42-promotion-governed-restore-ledger-predecessor-schema]' }
  $event = $eventRaw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$event.event_kind -cne 'Seal' -or [string]$event.subject -cne ('MIR-4.2-FOUR-TARGET-OFFLINE-RESTORE:' + [string]$Seal.record.record_sha256) -or
      [string]$event.signing_namespace -cne 'mir4-ledger' -or [string]$event.signer_fingerprint -cne [string]$Signing.ledger_signer.fingerprint -or
      [string]$event.predecessor_event_sha256 -cne ([string]$record.ledger_challenge.predecessor_event.sha256).ToLowerInvariant()) {
    throw '[mir42-promotion-governed-restore-ledger-event-binding]'
  }
  $challengePath = [string]$record.ledger_challenge.challenge.path
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42GovernedOfflineRestoreLedgerChallengePayload -Record $record)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($payload)))
  if ((Get-Content -Raw -LiteralPath $challengePath) -cne $payload -or
      [string]$record.ledger_challenge.challenge.sha256 -cne $payloadSha -or
      [string]$event.payload_sha256 -cne $payloadSha.ToLowerInvariant()) {
    throw '[mir42-promotion-governed-restore-ledger-challenge-binding]'
  }
  $scratch = Join-Path ([IO.Path]::GetTempPath()) ('mir42-governed-restore-' + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKeyPath = Join-Path $scratch 'ledger-signer.pub'
    [IO.File]::WriteAllText($publicKeyPath, ([string]$Signing.ledger_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath -Identity ([string]$Signing.ledger_signer.principal) -Namespace 'mir4-ledger' -PayloadPath $challengePath -SignaturePath ([string]$record.ledger_challenge.signature.path) -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-promotion-governed-restore-ledger-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
  }
  return $receipt
}

function Assert-MIR42ExpectedTechnicalSeal {
  param([Parameter(Mandatory)]$Seal,[Parameter(Mandatory)]$Readiness)
  $state = $Readiness._state
  $expected = [pscustomobject][ordered]@{
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
  $expected.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $expected
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.record) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expected)) {
    throw '[mir42-promotion-seal-reconstruction]'
  }
}

function Get-MIR42ProtectedMainPromotionPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
    [Parameter(Mandatory)][string]$RealEngineCampaignPath,
    [Parameter(Mandatory)][string]$IndependentVerificationPath,
    [Parameter(Mandatory)][string]$SigningCeremonyPath,
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$OfflineRestoreDrillPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-promotion-verified-seal-inputs] $($readiness.blockers -join '; ')" }
  $candidate = $readiness._state.candidate
  $seal = Read-MIR42SealRecord -Path $TechnicalSealPath -Code 'mir42-promotion-seal'
  Assert-MIR42ExpectedTechnicalSeal -Seal $seal -Readiness $readiness
  if ([string]$seal.record.kind -cne 'MIR42FourTargetTechnicalSealV1' -or
      [string]$seal.record.status -cne 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR' -or
      [string]$seal.record.candidate_manifest.sha256 -cne [string]$candidate.identity.sha256 -or
      [string]$seal.record.candidate_manifest.record_sha256 -cne [string]$candidate.identity.record.record_sha256 -or
      [string]$seal.record.source.commit -cne [string]$candidate.source.commit -or
      [string]$seal.record.source.tree -cne [string]$candidate.source.tree -or
      [string]$seal.record.source.package_source_sha256 -cne [string]$candidate.source.package_source_sha256 -or
      [bool]$seal.record.protected_main_promotion_authorized -or [bool]$seal.record.tagging_authorized -or
      [bool]$seal.record.publication_authorized) {
    throw '[mir42-promotion-seal-binding]'
  }
  foreach ($binding in @(
    @('qualification',$readiness._state.qualification),
    @('real_engine_campaign',$readiness._state.campaign),
    @('independent_verification',$readiness._state.independent),
    @('signing_ceremony',$readiness._state.signing),
    @('source_freeze_authority',$readiness._state.freeze),
    @('independent_reviewer_attestation',$readiness._state.reviewer)
  )) {
    $name = [string]$binding[0]; $proof = $binding[1]
    if ([string]$seal.record.$name.sha256 -cne [string]$proof.sha256 -or
        [string]$seal.record.$name.record_sha256 -cne [string]$proof.record.record_sha256) {
      throw "[mir42-promotion-seal-proof-binding] $name"
    }
  }
  $restoreDrill = Get-MIR42GovernedOfflineRestoreDrill -RepoRoot $repo -Path $OfflineRestoreDrillPath -Candidate $candidate -Seal $seal -Signing $readiness._state.signing -SshKeygenPath $SshKeygenPath
  $topologyPath = Join-Path $repo 'spec/releases/mir4-protected-main-promotion-topology-v1.json'
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-protected-main-promotion-topology-v1.schema.json'
  $topologyRaw = Get-Content -Raw -LiteralPath $topologyPath
  if (-not ($topologyRaw | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) { throw '[mir42-promotion-topology-schema]' }
  $topology = $topologyRaw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$topology.status -cne 'implemented-and-synthetically-rehearsed-release-blocked' -or
      [string]$topology.promotion.target -cne 'main' -or [string]$topology.promotion.merge_method -cne 'squash' -or
      -not [bool]$topology.promotion.pull_request_required -or -not [bool]$topology.promotion.linear_history_required -or
      -not [bool]$topology.promotion.protected_request_contract_required -or
      ((@($topology.promotion.required_status_checks | Sort-Object) -join '|') -cne 'branch-policy|verification-gate') -or
      [bool]$topology.promotion.force_push -or [bool]$topology.promotion.ruleset_mutation -or
      [int]$topology.promotion.bypass_actor_count -ne 0 -or [bool]$topology.authority.main_mutation -or
      [bool]$topology.authority.tagging -or [bool]$topology.authority.publication) {
    throw '[mir42-promotion-protected-topology]'
  }
  $main = Get-MIR42PromotionRemoteRef -RepoRoot $repo -Ref 'refs/heads/main' -Code 'mir42-promotion-main-ref-readback'
  $dev = Get-MIR42PromotionRemoteRef -RepoRoot $repo -Ref 'refs/heads/dev' -Code 'mir42-promotion-dev-ref-readback'
  $freeze = $readiness._state.freeze.record
  if ([string]$freeze.promotion_base.commit -cne $main -or
      [string]$freeze.frozen_dev.commit -cne $dev -or
      [string]$freeze.frozen_dev.commit -cne [string]$candidate.source.commit -or
      [string]$freeze.frozen_dev.tree -cne [string]$candidate.source.tree) {
    throw '[mir42-promotion-frozen-ref-drift]'
  }
  $candidateRef = 'refs/heads/release/mir-4.2-candidate-' + ([string]$candidate.source.commit).Substring(0,12)
  $candidateRefRows = @(& git -C $repo ls-remote --refs origin $candidateRef 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-promotion-candidate-ref-readback]' }
  if ($candidateRefRows.Count -ne 0) { throw '[mir42-promotion-candidate-ref-already-exists]' }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42ProtectedMainPromotionPlanV1'
    status = 'MIR-4.2-PROTECTED-MAIN-PROMOTION-PLAN-ONLY'
    source = $candidate.source
    technical_seal = [ordered]@{sha256=[string]$seal.sha256;record_sha256=[string]$seal.record.record_sha256}
    governed_offline_restore_drill = [ordered]@{sha256=[string]$restoreDrill.sha256;record_sha256=[string]$restoreDrill.record.record_sha256}
    main_before = $main
    frozen_dev = [ordered]@{ref='refs/heads/dev';commit=[string]$candidate.source.commit;tree=[string]$candidate.source.tree}
    candidate = [ordered]@{
      ref = $candidateRef
      base_ref = 'refs/heads/main'
      base_commit = $main
      parent_count = 1
      exact_tree = [string]$candidate.source.tree
      source_commit_trailer = "MIR4-Frozen-Dev-Commit: $([string]$candidate.source.commit)"
      create_only = $true
      remote_ref_must_be_absent = $true
    }
    target = 'main'
    merge_method = 'squash'
    pull_request_required = $true
    linear_history_required = $true
    required_status_checks = @('branch-policy','verification-gate')
    bypass_actors_allowed = 0
    force_push = $false
    ruleset_mutation = $false
    remote_mutation_performed = $false
    governed_offline_restore_drill_required_after_technical_seal = $true
    governed_offline_restore_drill_completed = $true
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
  }
}
