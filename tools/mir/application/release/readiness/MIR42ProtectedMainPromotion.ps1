Set-StrictMode -Version Latest

$mir42PromotionRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Get-MIR42ExactFourTargetCandidate -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'MIR42TechnicalSeal.ps1')
}
if (-not (Get-Command Assert-MIR4NoReparseAncestors -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42PromotionRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR42ProtectedMainRequiredCheckObservations -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'MIR42ProtectedMainChecks.ps1')
}

function Get-MIR42PromotionRemoteRef {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref,[Parameter(Mandatory)][string]$Code)
  $git = (Get-Command git -CommandType Application -ErrorAction Stop).Source
  $rows = @(& $git -C $RepoRoot ls-remote --refs origin $Ref 2>$null)
  if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1 -or $rows[0] -cnotmatch ('^([a-f0-9]{40})\s+' + [regex]::Escape($Ref) + '$')) {
    throw "[$Code]"
  }
  return [string]$Matches[1]
}

function Assert-MIR42PromotionRemoteRefAbsent {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Ref)
  $git = (Get-Command git -CommandType Application -ErrorAction Stop).Source
  $rows = @(& $git -C $RepoRoot ls-remote --refs origin $Ref 2>$null)
  if ($LASTEXITCODE -ne 0) { throw '[mir42-promotion-candidate-ref-readback]' }
  if ($rows.Count -ne 0) { throw '[mir42-promotion-candidate-ref-already-exists]' }
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
  $info.FileName = (Get-Command git -CommandType Application -ErrorAction Stop).Source
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
  param(
    [Parameter(Mandatory)]$Record,
    [ValidateSet('four-target','nine-target')][string]$Scope = 'four-target'
  )
  # The signed ledger challenge carries the scope as a distinct record kind.
  # A nine-target restore therefore cannot be replayed as a four-target proof.
  $challengeKind = [string](Get-MIR42SealScopeContract -Scope $Scope).restore_challenge_kind
  if ([string]::IsNullOrWhiteSpace($challengeKind)) { throw '[mir42-promotion-governed-restore-challenge-contract]' }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = $challengeKind
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
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [ValidateSet('four-target','nine-target')][string]$Scope = 'four-target',
    $PublishedMaintenanceInputs = $null
  )
  $candidateScope = Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-promotion-governed-restore-candidate'
  if ($candidateScope -cne $Scope) { throw '[mir42-promotion-governed-restore-candidate-scope]' }
  $contract = Get-MIR42TechnicalSealInputContract -Candidate $Candidate -PublishedMaintenance:($null -ne $PublishedMaintenanceInputs)
  if ([string]$Seal.record.kind -cne [string]$contract.seal_kind -or
      [string]$Seal.record.status -cne [string]$contract.seal_status -or
      [bool]$Seal.record.protected_main_promotion_authorized -or
      [bool]$Seal.record.tagging_authorized -or [bool]$Seal.record.publication_authorized) {
    throw '[mir42-promotion-governed-restore-seal-scope]'
  }
  if ($null -ne $PublishedMaintenanceInputs) {
    Assert-MIR42EngineEvidenceMaintenanceCustody -Recorded $Seal.record.published_maintenance_predecessor -Current $PublishedMaintenanceInputs -Code 'mir42-promotion-governed-restore-maintenance-custody'
  }
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-promotion-governed-restore'
  $record = $receipt.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','source','candidate_manifest','technical_seal','protected_signing_ceremony','recovery_custody','clean_rehydrate','restored_inventory','targets','ledger_challenge','publication_authorized','record_sha256') -Code 'mir42-promotion-governed-restore-shape'
  if ([int]$record.schema -ne 1 -or
      [string]$record.kind -cne [string]$contract.restore_kind -or
      [string]$record.status -cne [string]$contract.restore_status -or
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
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code 'mir42-promotion-governed-restore' -Scope $Scope
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
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42GovernedOfflineRestoreLedgerChallengePayload -Record $record -Scope $Scope)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($payload)))
  if ((Get-Content -Raw -LiteralPath $challengePath) -cne $payload -or
      [string]$record.ledger_challenge.challenge.sha256 -cne $payloadSha -or
      [string]$event.payload_sha256 -cne $payloadSha.ToLowerInvariant()) {
    throw '[mir42-promotion-governed-restore-ledger-challenge-binding]'
  }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-governed-restore-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKeyPath = Join-Path $scratch 'ledger-signer.pub'
    [IO.File]::WriteAllText($publicKeyPath, ([string]$Signing.ledger_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath -Identity ([string]$Signing.ledger_signer.principal) -Namespace 'mir4-ledger' -PayloadPath $challengePath -SignaturePath ([string]$record.ledger_challenge.signature.path) -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-promotion-governed-restore-ledger-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
  return $receipt
}

function Assert-MIR42ExpectedTechnicalSeal {
  param(
    [Parameter(Mandatory)]$Seal,
    [Parameter(Mandatory)]$Readiness,
    [ValidateSet('four-target','nine-target')][string]$Scope = 'four-target'
  )
  $state = $Readiness._state
  $candidateScope = Get-MIR42SealCandidateScope -Candidate $state.candidate -Code 'mir42-promotion-seal-candidate'
  if ($candidateScope -cne $Scope) { throw '[mir42-promotion-seal-candidate-scope]' }
  $maintenance = $state.PSObject.Properties.Name -ccontains 'maintenance_inputs'
  $contract = Get-MIR42TechnicalSealInputContract -Candidate $state.candidate -PublishedMaintenance:$maintenance
  $expected = [pscustomobject][ordered]@{
    schema = 1
    kind = [string]$contract.seal_kind
    status = [string]$contract.seal_status
    source = $state.candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$state.candidate.identity.sha256;record_sha256=[string]$state.candidate.identity.record.record_sha256}
    qualification = [ordered]@{sha256=[string]$state.qualification.sha256;record_sha256=[string]$state.qualification.record.record_sha256}
    real_engine_campaign = [ordered]@{sha256=[string]$state.campaign.sha256;record_sha256=[string]$state.campaign.record.record_sha256}
    independent_verification = [ordered]@{sha256=[string]$state.independent.sha256;record_sha256=[string]$state.independent.record.record_sha256}
    t16_acl_contract = [ordered]@{owner_sid=[string]$state.t16_acl_contract.record.owner_sid;mutation_sids=@($state.t16_acl_contract.record.mutation_sids);custodian_sid_set_sha256=[string]$state.t16_acl_contract.custodian_sid_set_sha256}
    t16_protected_root = [string]$state.t16_trust_root.protected_root
    t16_immutable_anchor = [string]$state.t16_trust_root.immutable_anchor
    t16_ledger_trust_root = [ordered]@{path=[string]$state.t16_trust_root.path;sha256=[string]$state.t16_trust_root.sha256;record_sha256=[string]$state.t16_trust_root.record.record_sha256}
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
  if ($maintenance) { $expected | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $state.maintenance_inputs }
  $expected.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $expected
  if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $Seal.record) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $expected)) {
    throw '[mir42-promotion-seal-reconstruction]'
  }
}

function Assert-MIR42PromotionReadinessScope {
  param(
    [Parameter(Mandatory)]$Readiness,
    [Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$RequiredScope
  )
  $state = $Readiness._state
  if ($null -eq $state -or $null -eq $state.candidate) { throw '[mir42-promotion-readiness-state]' }
  $candidateScope = Get-MIR42SealCandidateScope -Candidate $state.candidate -Code 'mir42-promotion-candidate'
  if ($candidateScope -cne $RequiredScope) { throw '[mir42-promotion-candidate-scope]' }
  $maintenance = $state.PSObject.Properties.Name -ccontains 'maintenance_inputs'
  $contract = Get-MIR42TechnicalSealInputContract -Candidate $state.candidate -PublishedMaintenance:$maintenance
  if ([string]$Readiness.kind -cne [string]$contract.readiness_kind -or
      [string]$Readiness.status -cne (([string]$contract.readiness_status_prefix) + 'READY') -or
      -not [bool]$Readiness.technical_seal_authorized -or
      [bool]$Readiness.protected_main_promotion_authorized -or
      -not [bool]$Readiness.human_go_required_after_main_readback -or
      [bool]$Readiness.tagging_authorized -or [bool]$Readiness.publication_authorized) {
    throw '[mir42-promotion-readiness-scope]'
  }
  Assert-MIR42SealTargetSet -Rows @($state.candidate.targets) -Code 'mir42-promotion-candidate' -Scope $RequiredScope
  if ($null -eq $state.programme -or $null -eq $state.programme.record -or
      [string]$state.programme.record.kind -cne [string]$contract.programme_kind) {
    throw '[mir42-promotion-current-programme]'
  }
  Assert-MIR42SealTargetSet -Rows @($state.programme.record.selected_targets | ForEach-Object { [pscustomobject]@{target=[string]$_} }) -Code 'mir42-promotion-current-programme' -Scope $RequiredScope
  Assert-MIR42SealTargetSet -Rows @($state.programme.record.direct_predecessors) -Code 'mir42-promotion-current-programme-predecessors' -Scope $RequiredScope
  if ($null -eq $state.t16_trust_root -or $null -eq $state.t16_trust_root.record -or
      [string]$state.t16_trust_root.record.kind -cne [string]$contract.trust_root_kind) {
    throw '[mir42-promotion-trust-root-scope]'
  }
  return $contract
}

function Get-MIR42PromotionTechnicalSealReadiness {
  param(
    [Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$RequiredScope,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
    [Parameter(Mandatory)][string]$RealEngineCampaignPath,
    [Parameter(Mandatory)][string]$IndependentVerificationPath,
    [Parameter(Mandatory)][string]$SigningCeremonyPath,
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [AllowEmptyString()][string]$ProgrammePath='',
    [AllowEmptyString()][string]$PublishedMaintenancePredecessorManifestPath=''
  )
  if (-not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath) -and $RequiredScope -cne 'nine-target') { throw '[mir42-maintenance-promotion-candidate-scope]' }
  $arguments = @{
    RepoRoot=$RepoRoot;CandidateManifestPath=$CandidateManifestPath;QualificationPath=$QualificationPath
    RealEngineCampaignPath=$RealEngineCampaignPath;IndependentVerificationPath=$IndependentVerificationPath
    SigningCeremonyPath=$SigningCeremonyPath;T16TrustRootPath=$T16TrustRootPath
    OperatorTrustSourcePath=$OperatorTrustSourcePath;T16ProtectedRootPath=$T16ProtectedRootPath
    T16ImmutableAnchorPath=$T16ImmutableAnchorPath;T16ApprovedOwnerSid=$T16ApprovedOwnerSid
    T16ApprovedMutationSids=$T16ApprovedMutationSids;SourceFreezeAuthorityPath=$SourceFreezeAuthorityPath
    ReviewerAttestationPath=$ReviewerAttestationPath;SshKeygenPath=$SshKeygenPath
  }
  if ($RequiredScope -ceq 'nine-target') {
    if (-not [string]::IsNullOrWhiteSpace($ProgrammePath)) { $arguments.ProgrammePath = $ProgrammePath }
    if (-not [string]::IsNullOrWhiteSpace($PublishedMaintenancePredecessorManifestPath)) { $arguments.PublishedMaintenancePredecessorManifestPath = $PublishedMaintenancePredecessorManifestPath }
    return Get-MIR42NineTargetTechnicalSealReadiness @arguments
  }
  return Get-MIR42FourTargetTechnicalSealReadiness @arguments
}

function Get-MIR42ProtectedMainPromotionPlanShared {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateSet('four-target','nine-target')][string]$RequiredScope,
    [switch]$PostPromotionReadback,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
    [Parameter(Mandatory)][string]$RealEngineCampaignPath,
    [Parameter(Mandatory)][string]$IndependentVerificationPath,
    [Parameter(Mandatory)][string]$SigningCeremonyPath,
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$OfflineRestoreDrillPath,
    [AllowEmptyString()][string]$ProgrammePath='',
    [AllowEmptyString()][string]$PublishedMaintenancePredecessorManifestPath=''
  )
  if ($PostPromotionReadback -and $RequiredScope -cne 'nine-target') { throw '[mir42-main-readback-nine-scope-required]' }
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $readiness = Get-MIR42PromotionTechnicalSealReadiness -RequiredScope $RequiredScope -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
    -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath -ProgrammePath $ProgrammePath `
    -PublishedMaintenancePredecessorManifestPath $PublishedMaintenancePredecessorManifestPath
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-promotion-verified-seal-inputs] $($readiness.blockers -join '; ')" }
  $contract = Assert-MIR42PromotionReadinessScope -Readiness $readiness -RequiredScope $RequiredScope
  $candidate = $readiness._state.candidate
  $seal = Read-MIR42SealRecord -Path $TechnicalSealPath -Code 'mir42-promotion-seal'
  Assert-MIR42ExpectedTechnicalSeal -Seal $seal -Readiness $readiness -Scope $RequiredScope
  if ([string]$seal.record.kind -cne [string]$contract.seal_kind -or
      [string]$seal.record.status -cne [string]$contract.seal_status -or
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
    @('t16_ledger_trust_root',$readiness._state.t16_trust_root),
    @('signing_ceremony',$readiness._state.signing),
    @('source_freeze_authority',$readiness._state.freeze),
    @('independent_reviewer_attestation',$readiness._state.reviewer)
  )) {
    $name = [string]$binding[0]; $proof = $binding[1]
    if ($null -eq $proof -or [string]$seal.record.$name.sha256 -cne [string]$proof.sha256 -or
        [string]$seal.record.$name.record_sha256 -cne [string]$proof.record.record_sha256) {
      throw "[mir42-promotion-seal-proof-binding] $name"
    }
  }
  $maintenanceInputs = if ($readiness._state.PSObject.Properties.Name -ccontains 'maintenance_inputs') { $readiness._state.maintenance_inputs } else { $null }
  $restoreDrill = Get-MIR42GovernedOfflineRestoreDrill -RepoRoot $repo -Path $OfflineRestoreDrillPath -Candidate $candidate -Seal $seal -Signing $readiness._state.signing -SshKeygenPath $SshKeygenPath -Scope $RequiredScope -PublishedMaintenanceInputs $maintenanceInputs
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
  $freeze = $readiness._state.freeze.record
  if ([string]$freeze.frozen_dev.commit -cne [string]$candidate.source.commit -or
      [string]$freeze.frozen_dev.tree -cne [string]$candidate.source.tree) {
    throw '[mir42-promotion-frozen-ref-drift]'
  }
  $main = [string]$freeze.promotion_base.commit
  $candidateRef = 'refs/heads/release/mir-4.2-candidate-' + ([string]$candidate.source.commit).Substring(0,12)
  if (-not $PostPromotionReadback) {
    $observedMain = Get-MIR42PromotionRemoteRef -RepoRoot $repo -Ref 'refs/heads/main' -Code 'mir42-promotion-main-ref-readback'
    $dev = Get-MIR42PromotionRemoteRef -RepoRoot $repo -Ref 'refs/heads/dev' -Code 'mir42-promotion-dev-ref-readback'
    if ($main -cne $observedMain -or [string]$freeze.frozen_dev.commit -cne $dev) { throw '[mir42-promotion-frozen-ref-drift]' }
    Assert-MIR42PromotionRemoteRefAbsent -RepoRoot $repo -Ref $candidateRef
  }
  $planKind = if ($RequiredScope -ceq 'nine-target') { 'MIR42NineTargetProtectedMainPromotionPlanV1' } else { 'MIR42ProtectedMainPromotionPlanV1' }
  $planStatus = if ($RequiredScope -ceq 'nine-target') { 'MIR-4.2-NINE-TARGET-PROTECTED-MAIN-PROMOTION-PLAN-ONLY' } else { 'MIR-4.2-PROTECTED-MAIN-PROMOTION-PLAN-ONLY' }
  $plan = [ordered]@{
    schema = 1
    kind = $planKind
    status = $planStatus
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
  if ($RequiredScope -ceq 'nine-target') {
    # Preserve the exact evidence bindings a protected executor must present
    # before it can create the candidate PR. This plan remains non-mutating.
    $plan.scope = 'nine-target'
    $plan.candidate_manifest = [ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    $plan.current_programme = [ordered]@{path=[string]$readiness._state.programme.path;sha256=[string]$readiness._state.programme.sha256;record_sha256=[string]$readiness._state.programme.record.record_sha256}
    $plan.direct_predecessors = @($readiness._state.programme.record.direct_predecessors)
    $plan.target_assets = @($candidate.targets | ForEach-Object { [ordered]@{target=[string]$_.target;distribution_version=[string]$_.distribution_version;archive_sha256=[string]$_.archive_sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count} })
    $plan.proofs = [ordered]@{
      qualification = [ordered]@{sha256=[string]$readiness._state.qualification.sha256;record_sha256=[string]$readiness._state.qualification.record.record_sha256}
      real_engine_campaign = [ordered]@{sha256=[string]$readiness._state.campaign.sha256;record_sha256=[string]$readiness._state.campaign.record.record_sha256}
      independent_verification = [ordered]@{sha256=[string]$readiness._state.independent.sha256;record_sha256=[string]$readiness._state.independent.record.record_sha256}
      t16_ledger_trust_root = [ordered]@{sha256=[string]$readiness._state.t16_trust_root.sha256;record_sha256=[string]$readiness._state.t16_trust_root.record.record_sha256}
      signing_ceremony = [ordered]@{sha256=[string]$readiness._state.signing.sha256;record_sha256=[string]$readiness._state.signing.record.record_sha256}
      source_freeze_authority = [ordered]@{sha256=[string]$readiness._state.freeze.sha256;record_sha256=[string]$readiness._state.freeze.record.record_sha256}
      independent_reviewer_attestation = [ordered]@{sha256=[string]$readiness._state.reviewer.sha256;record_sha256=[string]$readiness._state.reviewer.record.record_sha256}
    }
    if ($null -ne $maintenanceInputs) { $plan.published_maintenance_predecessor = $maintenanceInputs }
    $plan.protected_main_promotion_authorized = $false
  }
  return [pscustomobject]$plan
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
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$OfflineRestoreDrillPath
  )
  return Get-MIR42ProtectedMainPromotionPlanShared -RequiredScope 'four-target' @PSBoundParameters
}

function Get-MIR42NineTargetProtectedMainPromotionPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
    [Parameter(Mandatory)][string]$RealEngineCampaignPath,
    [Parameter(Mandatory)][string]$IndependentVerificationPath,
    [Parameter(Mandatory)][string]$SigningCeremonyPath,
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$OfflineRestoreDrillPath,
    [AllowEmptyString()][string]$ProgrammePath='',
    [AllowEmptyString()][string]$PublishedMaintenancePredecessorManifestPath=''
  )
  return Get-MIR42ProtectedMainPromotionPlanShared -RequiredScope 'nine-target' @PSBoundParameters
}

function Get-MIR42PrimaryMainSnapshot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$PrimaryRepoRoot)
  $primary=(Resolve-Path -LiteralPath $PrimaryRepoRoot).Path
  $git=(Get-Command git -CommandType Application -ErrorAction Stop).Source
  $dirty=@(& $git -C $primary status --porcelain=v1 --untracked-files=all)
  if($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw '[mir42-main-readback-primary-dirty]' }
  $branch=(@(& $git -C $primary branch --show-current)-join '').Trim()
  if($LASTEXITCODE -ne 0 -or $branch -cne 'main') { throw '[mir42-main-readback-primary-branch]' }
  $origin=(@(& $git -C $primary remote get-url origin)-join '').Trim()
  if($LASTEXITCODE -ne 0 -or $origin -notmatch '^(?:https://github[.]com/|git@github[.]com:)Julesc013/more-infinite-research(?:[.]git)?/?$') { throw '[mir42-main-readback-primary-origin]' }
  $commit=(@(& $git -C $primary rev-parse HEAD)-join '').Trim()
  if($LASTEXITCODE -ne 0 -or $commit -cnotmatch '^[0-9a-f]{40}$') { throw '[mir42-main-readback-primary-commit]' }
  $tree=(@(& $git -C $primary rev-parse 'HEAD^{tree}')-join '').Trim()
  if($LASTEXITCODE -ne 0 -or $tree -cnotmatch '^[0-9a-f]{40}$') { throw '[mir42-main-readback-primary-tree]' }
  $parents=(@(& $git -C $primary show -s --format=%P HEAD)-join '').Trim().Split(' ',[StringSplitOptions]::RemoveEmptyEntries)
  if($LASTEXITCODE -ne 0 -or $parents.Count -ne 1) { throw '[mir42-main-readback-primary-parent]' }
  $message=(@(& $git -C $primary show -s --format=%B HEAD)-join "`n").Trim()
  if($LASTEXITCODE -ne 0) { throw '[mir42-main-readback-primary-message]' }
  $remote=@(& $git -C $primary ls-remote --exit-code --heads origin 'refs/heads/main')
  if($LASTEXITCODE -ne 0 -or $remote.Count -ne 1 -or [string]$remote[0] -cnotmatch '^([0-9a-f]{40})\s+refs/heads/main$') { throw '[mir42-main-readback-remote-main]' }
  $remoteCommit=$Matches[1]
  if($remoteCommit -cne $commit) { throw '[mir42-main-readback-primary-remote-drift]' }
  $devCommit=Get-MIR42PromotionRemoteRef -RepoRoot $primary -Ref 'refs/heads/dev' -Code 'mir42-main-readback-frozen-dev'
  $packageSource=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $primary
  if($packageSource -cnotmatch '^[A-F0-9]{64}$') { throw '[mir42-main-readback-primary-package-source]' }
  return [pscustomobject][ordered]@{branch=$branch;commit=$commit;tree=$tree;parents=@($parents);message=$message;package_source_sha256=$packageSource;remote='origin';ref='refs/heads/main';origin=$origin;remote_commit=$remoteCommit;dev_commit=$devCommit;working_tree_clean=$true;observed_at=[DateTimeOffset]::UtcNow.ToString('o')}
}

function Assert-MIR42NineTargetMainReadbackBinding {
  param([Parameter(Mandatory)]$PromotionPlan,[Parameter(Mandatory)]$PrimarySnapshot)
  if([string]$PromotionPlan.kind -cne 'MIR42NineTargetProtectedMainPromotionPlanV1' -or
      [string]$PromotionPlan.scope -cne 'nine-target' -or
      $PromotionPlan.protected_main_promotion_authorized -isnot [bool] -or $PromotionPlan.protected_main_promotion_authorized -or
      $PromotionPlan.human_go_required_after_main_readback -isnot [bool] -or -not $PromotionPlan.human_go_required_after_main_readback -or
      $PromotionPlan.tagging_authorized -isnot [bool] -or $PromotionPlan.tagging_authorized -or
      $PromotionPlan.publication_authorized -isnot [bool] -or $PromotionPlan.publication_authorized) { throw '[mir42-main-readback-nine-plan-state]' }
  Assert-MIR42SealTargetSet -Rows @($PromotionPlan.target_assets) -Code 'mir42-main-readback-assets' -Scope 'nine-target'
  foreach($row in @($PromotionPlan.target_assets)) {
    if([string]$row.archive_sha256 -cnotmatch '^[A-F0-9]{64}$' -or [string]$row.content_sha256 -cnotmatch '^[A-F0-9]{64}$' -or [int]$row.entry_count -le 0) { throw '[mir42-main-readback-asset-identity]' }
  }
  if($PrimarySnapshot.working_tree_clean -isnot [bool] -or -not $PrimarySnapshot.working_tree_clean -or [string]$PrimarySnapshot.branch -cne 'main' -or
      [string]$PrimarySnapshot.commit -cnotmatch '^[0-9a-f]{40}$' -or [string]$PrimarySnapshot.tree -cnotmatch '^[0-9a-f]{40}$' -or
      [string]$PrimarySnapshot.package_source_sha256 -cnotmatch '^[A-F0-9]{64}$' -or
      [string]$PrimarySnapshot.remote -cne 'origin' -or [string]$PrimarySnapshot.ref -cne 'refs/heads/main' -or
      [string]$PrimarySnapshot.commit -cne [string]$PrimarySnapshot.remote_commit -or
      [string]$PrimarySnapshot.commit -ceq [string]$PromotionPlan.source.commit -or
      [string]$PrimarySnapshot.dev_commit -cne [string]$PromotionPlan.source.commit -or
      @($PrimarySnapshot.parents).Count -ne 1 -or [string]$PrimarySnapshot.parents[0] -cne [string]$PromotionPlan.main_before -or
      @([string]$PrimarySnapshot.message -split '\r?\n' | Where-Object {$_ -ceq [string]$PromotionPlan.candidate.source_commit_trailer}).Count -ne 1 -or
      [string]$PrimarySnapshot.tree -cne [string]$PromotionPlan.source.tree -or
      [string]$PrimarySnapshot.package_source_sha256 -cne [string]$PromotionPlan.source.package_source_sha256) { throw '[mir42-main-readback-qualified-tree-package-binding]' }
}

function Invoke-MIR42PromotionGitHubApiJson {
  param([Parameter(Mandatory)][string]$Endpoint,[Parameter(Mandatory)][string]$Code)
  $gh=(Get-Command gh -CommandType Application -ErrorAction Stop).Source
  $raw=@(& $gh api --hostname github.com $Endpoint)
  if($LASTEXITCODE -ne 0){throw "[$Code]"}
  return ($raw -join "`n")|ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-MIR42NineTargetMergedPromotionObservation {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$PromotionPlan,[Parameter(Mandatory)]$PrimarySnapshot,[Parameter(Mandatory)]$Transport,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequestNumber)
  $repository='Julesc013/more-infinite-research'
  # These observations are made here, never supplied by a caller or fixture.
  $pr=Invoke-MIR42PromotionGitHubApiJson -Endpoint "repos/$repository/pulls/$PullRequestNumber" -Code 'mir42-main-readback-pr-observation'
  if($pr.merged -isnot [bool] -or -not $pr.merged -or $pr.draft -isnot [bool] -or $pr.draft -or
      [string]$pr.state -cne 'closed' -or [string]$pr.base.repo.full_name -cne $repository -or [string]$pr.head.repo.full_name -cne $repository -or
      [string]$pr.base.ref -cne 'main' -or ('refs/heads/'+[string]$pr.head.ref) -cne [string]$PromotionPlan.candidate.ref -or
      [string]$pr.merge_commit_sha -cne [string]$PrimarySnapshot.commit -or [string]$pr.head.sha -cnotmatch '^[0-9a-f]{40}$' -or
      [string]$pr.head.sha -cne [string]$Transport.candidate.commit) {throw '[mir42-main-readback-pr-binding]'}
  $head=[string]$pr.head.sha
  $commit=Invoke-MIR42PromotionGitHubApiJson -Endpoint "repos/$repository/git/commits/$head" -Code 'mir42-main-readback-pr-head-observation'
  if([string]$commit.sha -cne $head -or [string]$commit.tree.sha -cne [string]$PromotionPlan.source.tree -or
      @($commit.parents).Count -ne 1 -or [string]$commit.parents[0].sha -cne [string]$PromotionPlan.main_before -or
      ([string]$commit.message).TrimEnd() -cne [string]$Transport.candidate.expected_commit_message -or
      @([string]$commit.message -split '\r?\n' | Where-Object {$_ -ceq [string]$PromotionPlan.candidate.source_commit_trailer}).Count -ne 1) {throw '[mir42-main-readback-pr-head-topology]'}
  $observed=@(Get-MIR42ProtectedMainRequiredCheckObservations -CandidateHead $head -CandidateRef ([string]$Transport.candidate.ref) -PullRequestNumber $PullRequestNumber -RequiredStatusChecks @($PromotionPlan.required_status_checks))
  return [pscustomobject][ordered]@{repository=$repository;number=$PullRequestNumber;url=[string]$pr.html_url;merged=$true;merged_at=[string]$pr.merged_at;head_commit=$head;merge_commit=[string]$pr.merge_commit_sha;head_tree=[string]$commit.tree.sha;parent_commit=[string]$commit.parents[0].sha;merge_method='squash';required_checks=$observed;observed_at=[DateTimeOffset]::UtcNow.ToString('o')}
}

function Get-MIR42NineTargetProtectedMainReadback {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PrimaryRepoRoot,
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$PullRequestNumber,
    [Parameter(Mandatory)][string]$IntentionPath,
    [Parameter(Mandatory)][string]$PromotionRequestPath,
    [Parameter(Mandatory)][string]$TechnicalSealPath,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$QualificationPath,
    [Parameter(Mandatory)][string]$RealEngineCampaignPath,
    [Parameter(Mandatory)][string]$IndependentVerificationPath,
    [Parameter(Mandatory)][string]$SigningCeremonyPath,
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [Parameter(Mandatory)][string]$SourceFreezeAuthorityPath,
    [Parameter(Mandatory)][string]$ReviewerAttestationPath,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$OfflineRestoreDrillPath,
    [AllowEmptyString()][string]$ProgrammePath='',
    [AllowEmptyString()][string]$PublishedMaintenancePredecessorManifestPath=''
  )
  # RepoRoot is the clean, pinned qualification checkout. PrimaryRepoRoot is
  # the completed-work handoff on actual main. Reconstruct all accepted proof
  # through existing readers; never relax their frozen-commit checks.
  if((Resolve-Path -LiteralPath $RepoRoot).Path -eq (Resolve-Path -LiteralPath $PrimaryRepoRoot).Path){throw '[mir42-main-readback-distinct-checkouts-required]'}
  $arguments=@{};foreach($key in $PSBoundParameters.Keys){if($key -cnotin @('PrimaryRepoRoot','PullRequestNumber','IntentionPath','PromotionRequestPath')){$arguments[$key]=$PSBoundParameters[$key]}}
  $plan=Get-MIR42ProtectedMainPromotionPlanShared -RequiredScope 'nine-target' -PostPromotionReadback @arguments
  if(-not (Get-Command Read-MIR4A08NineTargetPromotionTransport -ErrorAction SilentlyContinue)){
    . (Join-Path $mir42PromotionRepoRoot 'tools/lib/mir4/pre-freeze-release/ProtectedPromotionTopology.ps1')
  }
  $transport=Read-MIR4A08NineTargetPromotionTransport -IntentionPath $IntentionPath -PromotionRequestPath $PromotionRequestPath -PromotionPlan $plan
  $snapshot=Get-MIR42PrimaryMainSnapshot -PrimaryRepoRoot $PrimaryRepoRoot
  Assert-MIR42NineTargetMainReadbackBinding -PromotionPlan $plan -PrimarySnapshot $snapshot
  if([string]$snapshot.message -cne [string]$transport.request.expected_commit_message){throw '[mir42-main-readback-exact-promotion-message]'}
  $candidateRemote=Get-MIR42PromotionRemoteRef -RepoRoot $PrimaryRepoRoot -Ref ([string]$transport.candidate.ref) -Code 'mir42-main-readback-allocated-candidate'
  if($candidateRemote -cne [string]$transport.candidate.commit){throw '[mir42-main-readback-allocated-candidate-drift]'}
  $gh=Get-Command gh -CommandType Application -ErrorAction Stop
  $policy=Get-MIR4A08PolicyObservation -CanonicalRepository 'Julesc013/more-infinite-research' -PolicyProvider (New-MIR4A08GitHubRestPolicyProvider -GhExecutable $gh.Source)
  if([string]$policy.policy_sha256 -cne [string]$transport.policy.policy_sha256){throw '[mir42-main-readback-protected-policy-drift]'}
  $promotion=Get-MIR42NineTargetMergedPromotionObservation -PromotionPlan $plan -PrimarySnapshot $snapshot -Transport $transport -PullRequestNumber $PullRequestNumber
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetProtectedMainReadbackV1';status='MIR-4.2-NINE-TARGET-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST';scope='nine-target'
    source=$plan.source;primary_main=$snapshot
    protected_pull_request=$promotion
    promotion_transport=[ordered]@{scope='nine-target';binding_sha256=[string]$transport.binding_sha256;promotion_plan_sha256=[string]$transport.promotion_plan_sha256;allocated_candidate=$transport.candidate;intention=$transport.intention;request=$transport.request;policy_sha256=[string]$policy.policy_sha256}
    source_rebinding=[ordered]@{qualified_commit=[string]$plan.source.commit;promoted_main_commit=[string]$snapshot.commit;qualified_tree=[string]$plan.source.tree;promoted_main_tree=[string]$snapshot.tree;package_source_sha256=[string]$snapshot.package_source_sha256;package_bytes_preserved=$true;explicit_commit_rebinding=$true}
    candidate_manifest=$plan.candidate_manifest;technical_seal=$plan.technical_seal
    current_programme=$plan.current_programme;direct_predecessors=$plan.direct_predecessors;governed_offline_restore_drill=$plan.governed_offline_restore_drill
    targets=@($plan.target_assets | ForEach-Object {[string]$_.target});target_assets=$plan.target_assets;proofs=$plan.proofs
    main_readback_verified=$true;remote_mutation_performed=$false;protected_main_promotion_authorized=$false
    human_go_required_after_main_readback=$true;tagging_authorized=$false;publication_authorized=$false
    record_sha256=''
  }
  if ($plan.PSObject.Properties.Name -ccontains 'published_maintenance_predecessor') {
    $record | Add-Member -NotePropertyName published_maintenance_predecessor -NotePropertyValue $plan.published_maintenance_predecessor
  }
  $record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Write-MIR42NineTargetProtectedMainReadback {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$PrimaryRepoRoot,[Parameter(Mandatory)][string]$OutputPath)
  if([string]$Record.kind -cne 'MIR42NineTargetProtectedMainReadbackV1' -or
      [string]$Record.scope -cne 'nine-target' -or -not (Test-MIR4BootstrapRecordHash -Record $Record)) {throw '[mir42-main-readback-output-record]'}
  $primary=(Resolve-Path -LiteralPath $PrimaryRepoRoot).Path
  $outputRoot=Join-Path $primary 'build/release-readback'
  try {
    if(((Get-Item -LiteralPath $primary -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'reparse'}
    $output=Assert-MIR4DescendantPath -Root $outputRoot -Path $OutputPath
    $null=Assert-MIR4NoReparseAncestors -Root $primary -Path $output
  } catch {throw '[mir42-main-readback-output-containment]'}
  if(Test-Path -LiteralPath $output){throw '[mir42-main-readback-output-exists]'}
  $parent=Split-Path -Parent $output
  if(-not (Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  $null=Assert-MIR4NoReparseAncestors -Root $primary -Path $output
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4BootstrapCanonicalJson -Value $Record)+"`n")
  $stream=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
  return Read-MIR42SealRecord -Path $output -Code 'mir42-main-readback-output'
}
