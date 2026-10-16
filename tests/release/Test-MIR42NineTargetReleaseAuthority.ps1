# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')

function Assert-NineAuthority {
  param([bool]$Condition,[string]$Code)
  if (-not $Condition) { throw "[mir42-nine-authority-test-$Code]" }
}
function Assert-NineAuthorityReject {
  param([scriptblock]$Action,[string]$Pattern,[string]$Code)
  $rejected = $false
  try { & $Action | Out-Null } catch { $rejected = $_.Exception.Message -match $Pattern }
  Assert-NineAuthority $rejected $Code
}

function Get-MIR42NineAuthorityHistoricalFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target)

  $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target
  $targetRecordPath = Join-Path $RepoRoot ([string]$identity.target_record_path)
  $targetRecord = Read-MIR42SealRecord -Path $targetRecordPath -Code "mir42-nine-authority-fixture-target-record-$Target"
  $record = $targetRecord.record
  if ([string]$targetRecord.sha256 -cne [string]$identity.target_record_file_sha256 -or
      [string]$record.record_sha256 -cne [string]$identity.target_record_record_sha256 -or
      [int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $Target -or [string]$record.maturity -cne 'private-historical-playtest' -or
      [string]$record.base_materializer_target -cne 'f100' -or [string]$record.factorio_line -cne ([string]$identity.target_id -replace '^factorio-', '') -or
      [string]$record.distribution_version -cne [string]$identity.distribution_version -or
      [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-nine-authority-fixture-target-record] $Target"
  }
  $sealRelative = '.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json'
  $terminalSeal = Read-MIR42SealRecord -Path (Join-Path $RepoRoot $sealRelative) -Code "mir42-nine-authority-fixture-terminal-seal-$Target"
  if ([int]$terminalSeal.record.schema -ne 1 -or [string]$terminalSeal.record.kind -cne 'Mir3TerminalTargetSealV1' -or
      [string]$terminalSeal.record.status -cne 'sealed' -or [string]$terminalSeal.record.release -cne [string]$record.predecessor.version -or
      [string]$terminalSeal.record.target -cne [string]$record.factorio_line -or [string]$terminalSeal.record.archive_sha256 -cne [string]$record.predecessor.sha256 -or
      [string]$terminalSeal.record.engine.version -cne [string]$record.engine.version -or [string]$terminalSeal.record.engine.binary_sha256 -cne [string]$record.engine.sha256) {
    throw "[mir42-nine-authority-fixture-terminal-seal] $Target"
  }
  return [pscustomobject][ordered]@{
    fixture_scope='committed-target-record-and-terminal-seal-only';identity=$identity;target_record=$targetRecord;terminal_seal=$terminalSeal
  }
}

$four = Get-MIR42SealScopeContract -Scope 'four-target'
$nine = Get-MIR42SealScopeContract -Scope 'nine-target'
Assert-NineAuthority ($nine.programme_path -cne $four.programme_path -and $nine.trust_root_kind -cne $four.trust_root_kind) 'separate-current-authority'
Assert-NineAuthority ($nine.seal_kind -ceq 'MIR42NineTargetTechnicalSealV1' -and $nine.restore_kind -ceq 'MIR42NineTargetGovernedOfflineRestoreDrillV1') 'terminal-contract'

# These are structural fixtures. They create no key, signature, engine result,
# freeze, promotion, or publication permission.
$acceptance = [pscustomobject]@{
  key_policy_interpretation='existing-MIR-dedicated-signer-continuity'
  human_acceptance=[pscustomobject]@{maintainer='structural-fixture';decided_at='2026-09-27T10:00:00+10:00';decision='ACCEPTED'}
}
Assert-MIR42NineTargetSigningPolicyAcceptance -Record $acceptance
$changed = $acceptance | Select-Object *
$changed.key_policy_interpretation='automatic-key-reuse'
Assert-NineAuthorityReject { Assert-MIR42NineTargetSigningPolicyAcceptance -Record $changed } 'mir42-nine-seal-signing-policy-interpretation' 'implicit-key-reuse-rejected'
$changed = $acceptance | Select-Object *
$changed.human_acceptance = [pscustomobject]@{maintainer='';decided_at='2026-09-27T10:00:00+10:00';decision='ACCEPTED'}
Assert-NineAuthorityReject { Assert-MIR42NineTargetSigningPolicyAcceptance -Record $changed } 'mir42-nine-seal-signing-current-human-acceptance' 'missing-maintainer-rejected'
$changed.human_acceptance = [pscustomobject]@{maintainer='structural-fixture';decided_at='yesterday';decision='ACCEPTED'}
Assert-NineAuthorityReject { Assert-MIR42NineTargetSigningPolicyAcceptance -Record $changed } 'mir42-nine-seal-signing-current-human-acceptance' 'invalid-decision-time-rejected'

$payloadFixture = [pscustomobject]@{
  schema=1;kind=$nine.trust_root_kind;status='structural-fixture';scope='nine-target-release-cut'
  protected_root='fixture';immutable_anchor='fixture';custodian_policy='fixture';ledger='fixture'
  authorized_signer='fixture';independent_reviewer='fixture';operator_authorization='fixture'
  key_policy_interpretation=$acceptance.key_policy_interpretation;human_acceptance=$acceptance.human_acceptance
}
# Populate the exact existing signature payload properties without creating
# any accepted trust-root record.
$payloadAst = (Get-Item Function:Get-MIR42T16TrustRootSignaturePayload).ScriptBlock.Ast
$propertyNames = @($payloadAst.FindAll({param($node) $node -is [Management.Automation.Language.MemberExpressionAst] -and $node.Expression.Extent.Text -ceq '$Record'},$true) | ForEach-Object { $_.Member.Value } | Sort-Object -Unique)
foreach ($name in $propertyNames) { if ($payloadFixture.PSObject.Properties.Name -notcontains $name) { $payloadFixture | Add-Member -NotePropertyName $name -NotePropertyValue 'fixture' } }
$before = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42T16TrustRootSignaturePayload -Record $payloadFixture)
$payloadFixture.human_acceptance = [pscustomobject]@{maintainer='structural-fixture';decided_at='2026-09-27T10:00:00+10:00';decision='REJECTED'}
$after = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42T16TrustRootSignaturePayload -Record $payloadFixture)
Assert-NineAuthority ($before -cne $after) 'human-decision-covered-by-operator-signature'
$payloadFixture.kind=$four.trust_root_kind
$fourPayload = Get-MIR42T16TrustRootSignaturePayload -Record $payloadFixture
Assert-NineAuthority ($fourPayload.PSObject.Properties.Name -notcontains 'human_acceptance' -and $fourPayload.PSObject.Properties.Name -notcontains 'key_policy_interpretation') 'four-signature-payload-preserved'

$scratch = Join-Path $repo ('build/test-results/mir42-nine-authority-' + [guid]::NewGuid().ToString('N'))
$modernReader = (Get-Item Function:Get-MIR42DirectPredecessorAuthority).ScriptBlock
$historicalReader = (Get-Item Function:Get-MIR42HistoricalTerminalAuthority).ScriptBlock
$candidateReader = (Get-Item Function:Get-MIR42ExactFourTargetCandidate).ScriptBlock
$programmeReader = (Get-Item Function:Get-MIR42LiveProgrammeTransition).ScriptBlock
$programmeAuthorizationReader = (Get-Item Function:Read-MIR42NineTargetProgrammeWrittenAuthorization).ScriptBlock
try {
  $oldPath = Join-Path $repo $four.programme_path
  $oldHash = (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash
  $modernFixture = Read-MIR42SealRecord -Path (Join-Path $repo '.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json') -Code 'mir42-nine-authority-test-modern-fixture'
  $historicalFixtures = @{}
  foreach ($target in $script:MIR42SealHistoricalTargets) {
    $fixture = Get-MIR42NineAuthorityHistoricalFixture -RepoRoot $repo -Target $target
    Assert-NineAuthority ([string]$fixture.fixture_scope -ceq 'committed-target-record-and-terminal-seal-only' -and
      [string]$fixture.identity.target -ceq $target -and [string]$fixture.target_record.record.target -ceq $target) "historical-identity-$target"
    Assert-NineAuthority ([string]$fixture.terminal_seal.record.release -ceq [string]$fixture.target_record.record.predecessor.version -and
      [string]$fixture.terminal_seal.record.archive_sha256 -ceq [string]$fixture.target_record.record.predecessor.sha256) "historical-terminal-binding-$target"
    $historicalFixtures[$target] = $fixture
  }
  Set-Item Function:Get-MIR42DirectPredecessorAuthority -Value { param($RepoRoot,$Reference) return $modernFixture }
  Set-Item Function:Get-MIR42HistoricalTerminalAuthority -Value { param($RepoRoot,$Target) return $historicalFixtures[$Target] }
  $programmePath = Join-Path $scratch $nine.programme_path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $programmePath) | Out-Null
  $programmeSchemaRelative = 'spec/schemas/mir42-nine-target-release-cut-programme-v1.schema.json'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $scratch $programmeSchemaRelative)) | Out-Null
  Copy-Item -LiteralPath (Join-Path $repo $programmeSchemaRelative) -Destination (Join-Path $scratch $programmeSchemaRelative)
  Copy-Item -LiteralPath $oldPath -Destination (Join-Path $scratch $four.programme_path)
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath
  $committedProgramme = Read-MIR42SealRecord -Path (Join-Path $repo $nine.programme_path) -Code 'mir42-nine-authority-committed-programme'
  Assert-NineAuthority ((ConvertTo-MIR4BootstrapCanonicalJson -Value $committedProgramme.record) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $programme)) 'committed-pending-programme-matches-current-authorities'
  Assert-NineAuthority (($programme.selected_targets -join '|') -ceq ($script:MIR42SealNineTargetCandidates -join '|') -and @($programme.direct_predecessors).Count -eq 9 -and @($programme.historical_predecessor_authorities).Count -eq 5) 'all-nine-predecessors'
  Assert-NineAuthority (@($programme.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0 -and -not $programme.publication_authorized -and -not $programme.release_transition_authority) 'preparation-grants-no-transition'

  # A 4.4 release-cut programme retains the five terminal historical authorities
  # but takes its immediate rows only from the authenticated published 4.3
  # maintenance predecessor; stale 4.2 direct-predecessor rows are forbidden.
  $programme440Path = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1-440.json'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $programme440Path) | Out-Null
  $programme440 = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programme440Path -SourceVersion '4.4.0'
  Assert-NineAuthority ([string]$programme440.release_line -ceq '4.4' -and [string]$programme440.candidate.version_line -ceq '4.4' -and
    [string]$programme440.status -ceq 'active-current-4.4-release-cut-pre-freeze-no-transition-authority' -and
    $programme440.PSObject.Properties.Name -ccontains 'published_maintenance_predecessor' -and
    $programme440.PSObject.Properties.Name -cnotcontains 'direct_predecessor_authority' -and
    $programme440.PSObject.Properties.Name -cnotcontains 'direct_predecessors' -and
    [string]$programme440.published_maintenance_predecessor.source_version -ceq '4.3.0') '440-maintenance-programme-contract'
  $programme440Read = Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $programme440Path -AllowPendingTransition
  Assert-NineAuthority ([string]$programme440Read.record.release_line -ceq '4.4') '440-maintenance-programme-reader'
  $programme442Path = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1-442.json'
  $programme442 = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programme442Path -SourceVersion '4.4.2'
  $expected442 = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.4.2'
  Assert-NineAuthority ([string]$programme442.release_line -ceq '4.4' -and [string]$programme442.candidate.version_line -ceq '4.4' -and
    [string]$programme442.published_maintenance_predecessor.source_version -ceq '4.4.1' -and
    [string]$programme442.published_maintenance_predecessor.source_tag -ceq 'v4.4.1' -and
    [string]$programme442.published_maintenance_predecessor.manifest_sha256 -ceq [string]$expected442.manifest_sha256) '442-maintenance-programme-binds-published-441'
  $programme442Read = Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $programme442Path -AllowPendingTransition
  Assert-NineAuthority ([string]$programme442Read.record.published_maintenance_predecessor.source_version -ceq '4.4.1') '442-maintenance-programme-reader-resolves-published-441'
  $programme450Path = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1-450.json'
  $programme450 = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programme450Path -SourceVersion '4.5.0'
  $expected450 = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.5.0'
  Assert-NineAuthority ([string]$programme450.release_line -ceq '4.5' -and [string]$programme450.candidate.version_line -ceq '4.5' -and
    [string]$programme450.status -ceq 'active-current-4.5-release-cut-pre-freeze-no-transition-authority' -and
    [string]$programme450.published_maintenance_predecessor.source_version -ceq '4.4.2' -and
    [string]$programme450.published_maintenance_predecessor.source_tag -ceq 'v4.4.2' -and
    [string]$programme450.published_maintenance_predecessor.manifest_sha256 -ceq [string]$expected450.manifest_sha256 -and
    $programme450.PSObject.Properties.Name -cnotcontains 'direct_predecessors') '450-maintenance-programme-binds-exact-r24'
  $programme450Read = Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $programme450Path -AllowPendingTransition
  Assert-NineAuthority ([string]$programme450Read.record.release_line -ceq '4.5' -and [string]$programme450Read.record.published_maintenance_predecessor.source_version -ceq '4.4.2') '450-maintenance-programme-reader-resolves-exact-r24'
  $wrong450 = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme450 | ConvertFrom-Json -Depth 100 -DateKind String
  $wrong450.published_maintenance_predecessor.source_version = '4.4.1'
  $wrong450.published_maintenance_predecessor.source_tag = 'v4.4.1'
  Write-MIR42NormalizedRecord -Record $wrong450 -OutputPath $programme450Path -Code 'mir42-nine-test-450-wrong-maintenance' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $programme450Path -AllowPendingTransition } 'mir42-seal-current-programme-schema' '450-schema-rejects-published-441-predecessor'
  $lineMixed450 = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme450 | ConvertFrom-Json -Depth 100 -DateKind String
  $lineMixed450.published_maintenance_predecessor = $expected442
  Assert-NineAuthorityReject { Resolve-MIR42NineTargetProgrammeSourceVersion -Programme $lineMixed450 } 'mir42-seal-current-programme-maintenance-binding' '450-resolver-rejects-442-predecessor-on-450-line'
  $lineMixed442 = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme442 | ConvertFrom-Json -Depth 100 -DateKind String
  $lineMixed442.published_maintenance_predecessor = $expected450
  Assert-NineAuthorityReject { Resolve-MIR42NineTargetProgrammeSourceVersion -Programme $lineMixed442 } 'mir42-seal-current-programme-maintenance-binding' '442-resolver-rejects-r24-predecessor-on-44-line'
  $wrong442R24 = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme442 | ConvertFrom-Json -Depth 100 -DateKind String
  $wrong442R24.published_maintenance_predecessor = $expected450
  $wrong442R24Path = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1-442-r24.json'
  Write-MIR42NormalizedRecord -Record $wrong442R24 -OutputPath $wrong442R24Path -Code 'mir42-nine-test-442-r24-maintenance' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $wrong442R24Path -AllowPendingTransition } 'mir42-seal-current-programme-schema' '442-schema-rejects-r24-predecessor'
  $wrong440Status = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme440 | ConvertFrom-Json -Depth 100 -DateKind String
  $wrong440Status.status = 'active-current-4.5-release-cut-pre-freeze-no-transition-authority'
  $wrong440StatusPath = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1-440-wrong-status.json'
  Write-MIR42NormalizedRecord -Record $wrong440Status -OutputPath $wrong440StatusPath -Code 'mir42-nine-test-440-wrong-status' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $wrong440StatusPath -AllowPendingTransition } 'mir42-seal-current-programme-schema' '440-schema-rejects-450-status'
  $wrong450Status = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme450 | ConvertFrom-Json -Depth 100 -DateKind String
  $wrong450Status.status = 'active-current-4.4-release-cut-pre-freeze-no-transition-authority'
  $wrong450StatusPath = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1-450-wrong-status.json'
  Write-MIR42NormalizedRecord -Record $wrong450Status -OutputPath $wrong450StatusPath -Code 'mir42-nine-test-450-wrong-status' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $wrong450StatusPath -AllowPendingTransition } 'mir42-seal-current-programme-schema' '450-schema-rejects-440-status'
  $wrong442 = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme442 | ConvertFrom-Json -Depth 100 -DateKind String
  $wrong442.published_maintenance_predecessor.manifest_sha256 = '0' * 64
  Write-MIR42NormalizedRecord -Record $wrong442 -OutputPath $programme442Path -Code 'mir42-nine-test-442-wrong-maintenance' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $programme442Path -AllowPendingTransition } 'mir42-seal-current-programme-maintenance-binding' '442-wrong-published-441-binding-rejected'
  Assert-NineAuthorityReject { Get-MIR42NineTargetCandidateReleaseLineContract -Candidate ([pscustomobject]@{source_version='4.4.1'}) | Out-Null } 'mir42-nine-target-release-line-candidate-version' 'published-441-is-not-normal-programme-candidate'
  $wrong440 = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme440 | ConvertFrom-Json -Depth 100 -DateKind String
  $wrong440.candidate.version_line = '4.2'
  Write-MIR42NormalizedRecord -Record $wrong440 -OutputPath $programme440Path -Code 'mir42-nine-test-440-wrong-line' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $programme440Path -AllowPendingTransition } 'mir42-seal-current-programme-schema' '440-wrong-line-rejected'
  Remove-Item -LiteralPath $programme440Path -Force
  Assert-NineAuthority ((Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash -ceq $oldHash) 'old-programme-bytes-preserved'
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-transition-not-authorized' 'actual-transition-required'
  $preparedHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath | Out-Null
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $preparedHash) 'identical-preparation-preserves-bytes'

  # A canonical historical target record can change while this pending
  # programme is still pre-freeze.  The default writer must preserve the
  # stale authority; the explicit refresh may replace only those five
  # target-record fingerprint pairs and must checkpoint the original bytes.
  $stalePending = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme | ConvertFrom-Json -Depth 100 -DateKind String
  $stalePending.historical_predecessor_authorities[0].target_record.sha256 = 'A' * 64
  $stalePending.historical_predecessor_authorities[0].target_record.record_sha256 = 'B' * 64
  $stalePending = Write-MIR42NormalizedRecord -Record $stalePending -OutputPath $programmePath -Code 'mir42-nine-test-pending-refresh-stale'
  $stalePendingHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  Assert-NineAuthorityReject { New-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $programmePath } 'mir42-nine-programme-existing-authority-preserved' 'stale-pending-default-preserved'
  $refreshCheckpointRoot = Join-Path $scratch 'build/release-programme-checkpoints'
  $refreshedPending = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $programmePath -RefreshPendingAuthority -CheckpointRoot $refreshCheckpointRoot
  Assert-NineAuthority ((ConvertTo-MIR4BootstrapCanonicalJson -Value $refreshedPending) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $programme) -and
    -not [bool]$refreshedPending.release_transition_authority -and -not [bool]$refreshedPending.publication_authorized -and
    @($refreshedPending.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'pending-refresh-preserves-gates'
  $refreshCheckpoint = Join-Path $refreshCheckpointRoot (([IO.Path]::GetFileNameWithoutExtension($programmePath)) + '-before-pending-authority-refresh-' + $stalePendingHash + '.json')
  Assert-NineAuthority ((Test-Path -LiteralPath $refreshCheckpoint -PathType Leaf) -and
    (Get-FileHash -LiteralPath $refreshCheckpoint -Algorithm SHA256).Hash -ceq $stalePendingHash -and
    (ConvertTo-MIR4BootstrapCanonicalJson -Value (Read-MIR42SealRecord -Path $refreshCheckpoint -Code 'mir42-nine-test-pending-refresh-checkpoint').record) -ceq
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $stalePending)) 'pending-refresh-checkpoints-original-authority'

  $unsafePending = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme | ConvertFrom-Json -Depth 100 -DateKind String
  $unsafePending.direct_predecessors[-1].sha256 = 'C' * 64
  Write-MIR42NormalizedRecord -Record $unsafePending -OutputPath $programmePath -Code 'mir42-nine-test-pending-refresh-predecessor' | Out-Null
  $unsafePendingHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  Assert-NineAuthorityReject { New-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $programmePath -RefreshPendingAuthority -CheckpointRoot $refreshCheckpointRoot } 'mir42-nine-programme-existing-authority-preserved' 'pending-refresh-cannot-change-predecessor'
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $unsafePendingHash) 'rejected-pending-refresh-preserves-predecessor-bytes'
  $unsafePending = ConvertTo-MIR4BootstrapCanonicalJson -Value $programme | ConvertFrom-Json -Depth 100 -DateKind String
  $unsafePending.transition_gate.source_freeze = $true
  Write-MIR42NormalizedRecord -Record $unsafePending -OutputPath $programmePath -Code 'mir42-nine-test-pending-refresh-gate' | Out-Null
  $unsafePendingHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  Assert-NineAuthorityReject { New-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $programmePath -RefreshPendingAuthority -CheckpointRoot $refreshCheckpointRoot } 'mir42-nine-programme-existing-authority-preserved' 'pending-refresh-cannot-change-gate'
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $unsafePendingHash) 'rejected-pending-refresh-preserves-gate-bytes'
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath

  $programme.transition_gate.source_freeze='false'
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-boolean-type' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-schema' 'text-cannot-grant-transition'
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath

  $programme.required_gates[1].state='accepted'
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-gate-progress' | Out-Null
  $progressHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  Assert-NineAuthorityReject { New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath } 'mir42-nine-programme-existing-authority-preserved' 'state-only-gate-progress-cannot-reset'
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $progressHash) 'state-only-gate-bytes-preserved'
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath

  $programme.direct_predecessors[-1].sha256='0' * 64
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-tamper' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-predecessor-binding' 'ninth-predecessor-drift-rejected'
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath
  $programme.historical_predecessor_authorities[-1].terminal_seal.sha256='0' * 64
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-tamper' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-historical-binding' 'ninth-terminal-seal-drift-rejected'
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath
  $programme.required_gates[-1].scope='four-target-release-cut'
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-tamper' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-gate-scope' 'mixed-gate-scope-rejected'
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath
  $programme.transition_gate.source_freeze=$true
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-transition' | Out-Null
  $authorizedHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  Assert-NineAuthorityReject { New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath } 'mir42-nine-programme-existing-authority-preserved' 'preparation-cannot-reset-transition'
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $authorizedHash) 'rejected-writer-preserves-bytes'
  $programme.transition_gate.candidate_allocation=$true
  $programme.transition_gate.production_signing=$true
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-transition' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-nine-programme-pending-state' 'manual-gates-without-written-reference-rejected'

  # The current written GO authorizes only the procedural transition.  This
  # structural fixture contains no technical, signing, reviewer, restore,
  # promotion, tag, or publication proof.
  Remove-Item -LiteralPath $programmePath
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath
  $authorizationPath = Join-Path $scratch 'written-maintainer-authorization.json'
  $candidatePath = Join-Path $scratch 'candidate-manifest.json'
  $transitionPath = Join-Path $scratch 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json'
  [IO.File]::WriteAllText($authorizationPath, '{}')
  [IO.File]::WriteAllText($candidatePath, '{}')
  $authorizationFixture = [pscustomobject][ordered]@{
    path=$authorizationPath;sha256=('A' * 64)
    record=[pscustomobject][ordered]@{record_sha256=('B' * 64);recorded_from_user_turn_date='2026-10-02'}
  }
  $advanceCandidate = [pscustomobject][ordered]@{
    identity=[pscustomobject][ordered]@{path=$candidatePath;sha256=('C' * 64);record=[pscustomobject][ordered]@{record_sha256=('D' * 64)}}
    source=[pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('E' * 64)}
    source_version='4.2.0';scope='nine-target';targets=@($script:MIR42SealNineTargetCandidates | ForEach-Object {[pscustomobject][ordered]@{target=[string]$_}})
  }
  Set-Item Function:Read-MIR42NineTargetProgrammeWrittenAuthorization -Value { param($Path) if((Resolve-Path -LiteralPath $Path).Path -cne $authorizationPath){throw '[mir42-nine-test-written-go-path]'};return $authorizationFixture }
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value { param($RepoRoot,$CandidateManifestPath) if((Resolve-Path -LiteralPath $CandidateManifestPath).Path -cne $candidatePath){throw '[mir42-nine-test-written-go-candidate-path]'};return $advanceCandidate }
  $oldProgrammeSha = (Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  $checkpointRoot = Join-Path $scratch 'build/release-programme-checkpoints'
  Assert-NineAuthorityReject { Advance-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $programmePath -MaintainerAuthorizationPath $authorizationPath -CandidateManifestPath $candidatePath -CheckpointRoot $checkpointRoot } 'mir42-nine-programme-external-path-containment' 'tracked-programme-cannot-be-advanced'
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $oldProgrammeSha) 'tracked-programme-bytes-preserved-after-rejected-advance'
  $advanced = Advance-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $transitionPath -MaintainerAuthorizationPath $authorizationPath -CandidateManifestPath $candidatePath -CheckpointRoot $checkpointRoot
  Assert-NineAuthority ([bool]$advanced.advanced -and (Test-Path -LiteralPath $advanced.checkpoint_path -PathType Leaf) -and [string]$advanced.checkpoint_sha256 -ceq $oldProgrammeSha -and
    (Get-FileHash -LiteralPath $advanced.checkpoint_path -Algorithm SHA256).Hash -ceq $oldProgrammeSha -and
    [bool]$advanced.record.transition_gate.source_freeze -and [bool]$advanced.record.transition_gate.candidate_allocation -and [bool]$advanced.record.transition_gate.production_signing -and
    -not [bool]$advanced.record.transition_gate.technical_seal -and -not [bool]$advanced.record.transition_gate.promotion -and -not [bool]$advanced.record.transition_gate.tagging -and -not [bool]$advanced.record.transition_gate.publication -and
    -not [bool]$advanced.record.release_transition_authority -and -not [bool]$advanced.record.publication_authorized) 'written-go-advance-is-procedural-only'
  $advancedReadback = Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' -ProgrammePath $transitionPath
  Assert-NineAuthority ([string]$advancedReadback.record.written_transition_authorization.maintainer_authorization.record_sha256 -ceq ('B' * 64) -and [string]$advancedReadback.record.written_transition_authorization.candidate_manifest.record_sha256 -ceq ('D' * 64) -and
    [string]$advancedReadback.record.written_transition_authorization.baseline_programme.sha256 -ceq $oldProgrammeSha -and
    [string]$advancedReadback.path -ceq 'build/release-programme-transitions/MIR42-Nine-Target-Release-Cut-ProgrammeV1.json' -and
    (Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $oldProgrammeSha) 'written-go-reference-reread'
  $repeatAdvance = Advance-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $transitionPath -MaintainerAuthorizationPath $authorizationPath -CandidateManifestPath $candidatePath -CheckpointRoot $checkpointRoot
  Assert-NineAuthority (-not [bool]$repeatAdvance.advanced -and [string]$repeatAdvance.record.record_sha256 -ceq [string]$advanced.record.record_sha256) 'written-go-advance-idempotent'
  $advanceCandidate.identity.sha256 = ('F' * 64)
  Assert-NineAuthorityReject { Advance-MIR42NineTargetReleaseCutProgramme -RepoRoot $scratch -OutputPath $transitionPath -MaintainerAuthorizationPath $authorizationPath -CandidateManifestPath $candidatePath -CheckpointRoot $checkpointRoot } 'mir42-nine-programme-transition-candidate-binding' 'written-go-candidate-substitution-rejected'
  $advanceCandidate.identity.sha256 = ('C' * 64)
  Set-Item Function:Read-MIR42NineTargetProgrammeWrittenAuthorization -Value $programmeAuthorizationReader
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value $candidateReader

  $candidateFixture = [pscustomobject]@{targets=@($script:MIR42SealNineTargetCandidates | ForEach-Object { [pscustomobject]@{target=$_} })}
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value { param($RepoRoot,$CandidateManifestPath) return $candidateFixture }
  Set-Item Function:Get-MIR42LiveProgrammeTransition -Value { param($RepoRoot,$Scope='four-target') throw "[structural-programme-read-$Scope]" }
  $readiness = Get-MIR42NineTargetTechnicalSealReadiness -RepoRoot $repo -CandidateManifestPath $programmePath
  Assert-NineAuthority ($readiness.checks.candidate -and -not $readiness.technical_seal_authorized -and @($readiness.blockers | Where-Object { $_ -match 'structural-programme-read-nine-target' }).Count -eq 1) 'nine-readiness-selected'
  $candidateFixture.targets = @($candidateFixture.targets | Where-Object { $_.target -cin $script:MIR42SealTargets })
  $readiness = Get-MIR42NineTargetTechnicalSealReadiness -RepoRoot $repo -CandidateManifestPath $programmePath
  Assert-NineAuthority (-not $readiness.checks.candidate -and @($readiness.blockers | Where-Object { $_ -match 'mir42-nine-target-seal-candidate-target-set' }).Count -eq 1 -and @($readiness.blockers | Where-Object { $_ -match 'structural-programme-read' }).Count -eq 0) 'four-cannot-enter-nine-authority'
  $sealPath = Join-Path $scratch 'forbidden-seal.json'
  Assert-NineAuthorityReject { New-MIR42NineTargetTechnicalSeal -RepoRoot $repo -CandidateManifestPath $programmePath -OutputPath $sealPath } 'mir42-seal-not-authorized.*mir42-nine-target-seal-candidate-target-set' 'wrong-scope-seal-rejected'
  Assert-NineAuthority (-not (Test-Path -LiteralPath $sealPath)) 'wrong-scope-no-seal-output'
  Assert-NineAuthorityReject { New-MIR42NineTargetRealEngineEvidenceBinder -RepoRoot $repo -CandidateManifestPath $programmePath -EvidenceReconciliationPath $programmePath -EngineRunPath $programmePath -OutputPath $sealPath } 'mir42-nine-target-engine-evidence-candidate-target-set' 'wrong-scope-engine-binder-rejected'
  Assert-NineAuthority (-not (Test-Path -LiteralPath $sealPath)) 'wrong-scope-no-engine-binder-output'
} finally {
  Set-Item Function:Get-MIR42DirectPredecessorAuthority -Value $modernReader
  Set-Item Function:Get-MIR42HistoricalTerminalAuthority -Value $historicalReader
  Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value $candidateReader
  Set-Item Function:Get-MIR42LiveProgrammeTransition -Value $programmeReader
  Set-Item Function:Read-MIR42NineTargetProgrammeWrittenAuthorization -Value $programmeAuthorizationReader
  $buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not [IO.Path]::GetFullPath($scratch).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-authority-test-containment]' }
  if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
Write-Output 'MIR42-NINE-TARGET-RELEASE-AUTHORITY-PASSED structural-only engines=0 signing=0 publication=0'
