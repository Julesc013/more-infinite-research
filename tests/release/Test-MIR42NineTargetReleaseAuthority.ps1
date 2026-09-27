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
try {
  $oldPath = Join-Path $repo $four.programme_path
  $oldHash = (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash
  $modernFixture = Read-MIR42SealRecord -Path (Join-Path $repo '.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json') -Code 'mir42-nine-authority-test-modern-fixture'
  $historicalFixtures = @{}
  foreach ($target in $script:MIR42SealHistoricalTargets) { $historicalFixtures[$target] = Get-MIR42HistoricalTerminalAuthority -RepoRoot $repo -Target $target }
  Set-Item Function:Get-MIR42DirectPredecessorAuthority -Value { param($RepoRoot,$Reference) return $modernFixture }
  Set-Item Function:Get-MIR42HistoricalTerminalAuthority -Value { param($RepoRoot,$Target) return $historicalFixtures[$Target] }
  $programmePath = Join-Path $scratch $nine.programme_path
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $programmePath) | Out-Null
  Copy-Item -LiteralPath $oldPath -Destination (Join-Path $scratch $four.programme_path)
  $programme = New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath
  Assert-NineAuthority (($programme.selected_targets -join '|') -ceq ($script:MIR42SealNineTargetCandidates -join '|') -and @($programme.direct_predecessors).Count -eq 9 -and @($programme.historical_predecessor_authorities).Count -eq 5) 'all-nine-predecessors'
  Assert-NineAuthority (@($programme.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0 -and -not $programme.publication_authorized -and -not $programme.release_transition_authority) 'preparation-grants-no-transition'
  Assert-NineAuthority ((Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash -ceq $oldHash) 'old-programme-bytes-preserved'
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-transition-not-authorized' 'actual-transition-required'
  $preparedHash=(Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash
  New-MIR42NineTargetReleaseCutProgramme -RepoRoot $repo -OutputPath $programmePath | Out-Null
  Assert-NineAuthority ((Get-FileHash -LiteralPath $programmePath -Algorithm SHA256).Hash -ceq $preparedHash) 'identical-preparation-preserves-bytes'

  $programme.transition_gate.source_freeze='false'
  Write-MIR42NormalizedRecord -Record $programme -OutputPath $programmePath -Code 'mir42-nine-test-boolean-type' | Out-Null
  Assert-NineAuthorityReject { Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target' } 'mir42-seal-current-programme-transition-type' 'text-cannot-grant-transition'
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
  $transition=Get-MIR42LiveProgrammeTransition -RepoRoot $scratch -Scope 'nine-target'
  Assert-NineAuthority ($transition.path -ceq $nine.programme_path -and $transition.record.kind -ceq $nine.programme_kind) 'explicit-nine-reader-path'

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
  $buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not [IO.Path]::GetFullPath($scratch).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-authority-test-containment]' }
  if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
Write-Output 'MIR42-NINE-TARGET-RELEASE-AUTHORITY-PASSED structural-only engines=0 signing=0 publication=0'
