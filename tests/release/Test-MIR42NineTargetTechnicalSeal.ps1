# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$reader = Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1'
if (-not (Test-Path -LiteralPath $reader -PathType Leaf)) { throw "[mir42-nine-seal-stage-missing] $reader" }
. $reader

function Assert-MIR42NineSealTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-nine-seal-test-$Code]" }
}

$modern = [pscustomobject][ordered]@{
  targets = @($script:MIR42SealTargets | ForEach-Object { [pscustomobject][ordered]@{target=$_} })
}
$nine = [pscustomobject][ordered]@{
  targets = @($script:MIR42SealNineTargetCandidates | ForEach-Object { [pscustomobject][ordered]@{target=$_} })
}
$modernContract = Get-MIR42SealScopeContract -Scope (Get-MIR42SealCandidateScope -Candidate $modern -Code 'mir42-nine-seal-modern')
$nineContract = Get-MIR42SealScopeContract -Scope (Get-MIR42SealCandidateScope -Candidate $nine -Code 'mir42-nine-seal-nine')
Assert-MIR42NineSealTest -Condition ([string]$modernContract.engine_run_kind -ceq 'MIR42FourTargetEngineRunV1') -Code 'modern-engine-contract'
Assert-MIR42NineSealTest -Condition ([string]$modernContract.campaign_status -ceq 'MIR-4.2-FOUR-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED') -Code 'modern-campaign-contract'
Assert-MIR42NineSealTest -Condition ([string]$nineContract.evidence_kind -ceq 'MIR42NineTargetEvidenceReconciliationV1') -Code 'nine-evidence-contract'
Assert-MIR42NineSealTest -Condition ([string]$nineContract.engine_run_kind -ceq 'MIR42NineTargetEngineRunV1') -Code 'nine-engine-contract'
Assert-MIR42NineSealTest -Condition ([string]$nineContract.binder_status -ceq 'MIR-4.2-NINE-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED') -Code 'nine-binder-contract'
Assert-MIR42NineSealTest -Condition ([string]$nineContract.campaign_status -ceq 'MIR-4.2-NINE-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED') -Code 'nine-campaign-contract'

Assert-MIR42SealCandidateScopeMatch -Rows @($nine.targets) -Candidate $nine -Code 'mir42-nine-seal-match'
$rejected = $false
try { Assert-MIR42SealCandidateScopeMatch -Rows @($modern.targets) -Candidate $nine -Code 'mir42-nine-seal-opposing' } catch { $rejected = $_.Exception.Message -match '^\[mir42-nine-seal-opposing-target-set\]' }
Assert-MIR42NineSealTest -Condition $rejected -Code 'mixed-scope-rejected'

foreach ($target in $script:MIR42SealHistoricalTargets) {
  $authority = Get-MIR42HistoricalTerminalAuthority -RepoRoot $repo -Target $target
  $record = $authority.target_record.record
  $seal = $authority.terminal_seal.record
  Assert-MIR42NineSealTest -Condition ([string]$authority.identity.target -ceq $target) -Code "identity-$target"
  Assert-MIR42NineSealTest -Condition ([string]$record.target -ceq $target -and -not [bool]$record.public_output_authorized -and -not [bool]$record.publication_authorized) -Code "record-$target"
  Assert-MIR42NineSealTest -Condition ([string]$seal.release -ceq [string]$record.predecessor.version -and [string]$seal.archive_sha256 -ceq [string]$record.predecessor.sha256) -Code "terminal-$target"
  $runAuthority = [pscustomobject][ordered]@{
    target_record = [pscustomobject][ordered]@{path=[string]$authority.identity.target_record_path;sha256=[string]$authority.target_record.sha256;record_sha256=[string]$record.record_sha256}
    terminal_seal = [pscustomobject][ordered]@{path=('.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json');sha256=[string]$authority.terminal_seal.sha256;record_sha256=[string]$seal.record_sha256;target=[string]$record.factorio_line;release=[string]$record.predecessor.version}
    engine = [pscustomobject][ordered]@{path=[string]$record.engine.path;version=[string]$record.engine.version;sha256=[string]$record.engine.sha256}
    predecessor = [pscustomobject][ordered]@{path=[string]$record.predecessor.archive;version=[string]$record.predecessor.version;sha256=[string]$record.predecessor.sha256;bytes=[int64]$seal.bytes;content_sha256=[string]$seal.content_sha256;entry_count=[int]$seal.entries}
  }
  $execution = [pscustomobject][ordered]@{
    executable_path=[string]$record.engine.path;executable_sha256=[string]$record.engine.sha256;version=[string]$record.engine.version
    predecessor=[pscustomobject][ordered]@{path=(Join-Path $repo ([string]$record.predecessor.archive));sha256=[string]$record.predecessor.sha256;version=[string]$record.predecessor.version}
    harness_receipt=[pscustomobject][ordered]@{path=$reader;sha256=(Get-FileHash -LiteralPath $reader -Algorithm SHA256).Hash.ToUpperInvariant()};harness_exit_code=0
    logs=@();fresh_loads=@();fresh_exact_load=$true;predecessor_upgrade=$true;reload_count=2;historical_terminal_authority=$runAuthority
  }
  Assert-MIR42HistoricalTerminalExecution -RepoRoot $repo -Target ([pscustomobject][ordered]@{target=$target}) -Execution $execution -HistoricalAuthorities @([pscustomobject][ordered]@{target=$target;authority=$runAuthority})
  $tamperedAuthority = $runAuthority | Select-Object *
  $tamperedAuthority.predecessor = $runAuthority.predecessor | Select-Object *
  $tamperedAuthority.predecessor.sha256 = '0' * 64
  $tampered = $false
  try { Assert-MIR42HistoricalTerminalExecution -RepoRoot $repo -Target ([pscustomobject][ordered]@{target=$target}) -Execution $execution -HistoricalAuthorities @([pscustomobject][ordered]@{target=$target;authority=$tamperedAuthority}) } catch { $tampered = $_.Exception.Message -match '^\[mir42-seal-historical-authority-binding\]' }
  Assert-MIR42NineSealTest -Condition $tampered -Code "terminal-tamper-$target"
}

$readerFixtureRoot = Join-Path $repo ('build/test-results/mir42-nine-seal-reader-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $readerFixtureRoot | Out-Null
  $fixtureCandidate = [pscustomobject][ordered]@{
    identity = [pscustomobject][ordered]@{sha256=('A' * 64);record=[pscustomobject][ordered]@{record_sha256=('B' * 64)}}
    source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
    targets = @(
      foreach ($target in $script:MIR42SealNineTargetCandidates) {
        [pscustomobject][ordered]@{target=$target;distribution_version=('4.2.' + $target.Substring(1) + '00');archive_sha256=('D' * 64);content_sha256=('E' * 64);entry_count=1}
      }
    )
  }
  $fixtureTargets = @(
    foreach ($target in @($fixtureCandidate.targets)) {
      [pscustomobject][ordered]@{
        target=[string]$target.target;distribution_version=[string]$target.distribution_version
        archive=[pscustomobject][ordered]@{sha256=[string]$target.archive_sha256;content_sha256=[string]$target.content_sha256;entry_count=[int]$target.entry_count}
        status='reconciled'
      }
    }
  )
  $reconciliationRecord = [pscustomobject][ordered]@{
    schema=1;kind=[string]$nineContract.evidence_kind;status=[string]$nineContract.evidence_status
    reconciliation_scope='reader structural fixture only; no Factorio process or release qualification'
    source=$fixtureCandidate.source;candidate_manifest=[pscustomobject][ordered]@{sha256=[string]$fixtureCandidate.identity.sha256;record_sha256=[string]$fixtureCandidate.identity.record.record_sha256}
    targets=$fixtureTargets;all_nine_targets_required=$true;cross_target_substitution=$false;factorio_processes=0
    release_qualification='not-performed';independent_verification='not-performed';technical_seal='not-performed'
    source_freeze_authorized=$false;signing_authorized=$false;tagging_authorized=$false;publication_authorized=$false
    nonclaims=@('structural reader fixture only');record_sha256=''
  }
  $reconciliationPath = Join-Path $readerFixtureRoot 'evidence-reconciliation.json'
  Write-MIR4BootstrapRecord -Record $reconciliationRecord -Path $reconciliationPath | Out-Null
  $reconciliation = Get-MIR42ExactQualificationReceipt -Path $reconciliationPath -Candidate $fixtureCandidate
  Assert-MIR42NineSealTest -Condition ([string]$reconciliation.record.status -ceq [string]$nineContract.evidence_status -and -not [bool]$reconciliation.record.publication_authorized) -Code 'nine-reconciliation-reader'

  $independentRecord = [pscustomobject][ordered]@{
    schema=1;kind=[string]$nineContract.independent_kind;status=[string]$nineContract.independent_status;source=$fixtureCandidate.source
    evaluator=[pscustomobject][ordered]@{implementation='reader-structural-fixture';git_commit=('c' * 40);sha256=('F' * 64)}
    candidate_manifest=[pscustomobject][ordered]@{sha256=[string]$fixtureCandidate.identity.sha256;record_sha256=[string]$fixtureCandidate.identity.record.record_sha256}
    qualification=[pscustomobject][ordered]@{sha256=[string]$reconciliation.sha256;record_sha256=[string]$reconciliation.record.record_sha256}
    targets=$fixtureTargets;all_nine_targets_required=$true;factorio_processes=0;release_qualification='not-performed'
    independent_release_acceptance='not-performed';technical_seal='not-performed';signing_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  $independentPath = Join-Path $readerFixtureRoot 'independent-evidence-rehash.json'
  Write-MIR4BootstrapRecord -Record $independentRecord -Path $independentPath | Out-Null
  $independent = Get-MIR42ExactIndependentVerificationReceipt -Path $independentPath -Candidate $fixtureCandidate -Qualification $reconciliation
  Assert-MIR42NineSealTest -Condition ([string]$independent.record.status -ceq [string]$nineContract.independent_status -and
    [string]$independent.record.technical_seal -ceq 'not-performed' -and -not [bool]$independent.record.publication_authorized) -Code 'nine-independent-reader'

  $wrongScopeRecord = $independentRecord | Select-Object *
  $wrongScopeRecord.kind = [string]$modernContract.independent_kind
  $wrongScopeRecord.status = [string]$modernContract.independent_status
  $wrongScopeRecord.record_sha256 = ''
  $wrongScopePath = Join-Path $readerFixtureRoot 'independent-wrong-scope.json'
  Write-MIR4BootstrapRecord -Record $wrongScopeRecord -Path $wrongScopePath | Out-Null
  $wrongScopeRejected = $false
  try { $null = Get-MIR42ExactIndependentVerificationReceipt -Path $wrongScopePath -Candidate $fixtureCandidate -Qualification $reconciliation } catch { $wrongScopeRejected = $_.Exception.Message -match '^\[mir42-seal-independent-evidence-reconciliation-state\]' }
  Assert-MIR42NineSealTest -Condition $wrongScopeRejected -Code 'nine-independent-wrong-scope-rejected'

  # Isolate the terminal authority boundary after a candidate reader succeeds.
  # These mocked private records have no qualification or signing authority.
  $candidateReader = (Get-Item Function:Get-MIR42ExactFourTargetCandidate).ScriptBlock
  $programmeReader = (Get-Item Function:Get-MIR42LiveProgrammeTransition).ScriptBlock
  try {
    Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value {
      param($RepoRoot, $CandidateManifestPath)
      return $fixtureCandidate
    }
    Set-Item Function:Get-MIR42LiveProgrammeTransition -Value { throw '[test-programme-must-not-be-read]' }
    $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $repo -CandidateManifestPath $reconciliationPath
    Assert-MIR42NineSealTest -Condition (-not [bool]$readiness.technical_seal_authorized -and
      -not [bool]$readiness.checks.candidate -and
      @($readiness.blockers | Where-Object { $_ -match '^\[mir42-four-target-seal-candidate-target-set\]' }).Count -eq 1 -and
      @($readiness.blockers | Where-Object { $_ -match 'test-programme-must-not-be-read' }).Count -eq 0) -Code 'nine-candidate-cannot-enter-four-seal-authority'
    $sealPath = Join-Path $readerFixtureRoot 'wrong-four-target-seal.json'
    $sealRejected = $false
    try { $null = New-MIR42FourTargetTechnicalSeal -RepoRoot $repo -CandidateManifestPath $reconciliationPath -OutputPath $sealPath }
    catch { $sealRejected = $_.Exception.Message -match '^\[mir42-seal-not-authorized\].*mir42-four-target-seal-candidate-target-set' }
    Assert-MIR42NineSealTest -Condition ($sealRejected -and -not (Test-Path -LiteralPath $sealPath)) -Code 'nine-candidate-four-seal-output-forbidden'
    $fixtureCandidate.targets = @($fixtureCandidate.targets | Where-Object { [string]$_.target -cin $script:MIR42SealTargets })
    $modernReadiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $repo -CandidateManifestPath $reconciliationPath
    Assert-MIR42NineSealTest -Condition ([bool]$modernReadiness.checks.candidate -and
      @($modernReadiness.blockers | Where-Object { $_ -match 'test-programme-must-not-be-read' }).Count -eq 1) -Code 'four-candidate-retains-terminal-authority-path'
  } finally {
    Set-Item Function:Get-MIR42ExactFourTargetCandidate -Value $candidateReader
    Set-Item Function:Get-MIR42LiveProgrammeTransition -Value $programmeReader
  }
} finally {
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not $readerFixtureRoot.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-seal-fixture-containment]' }
  if (Test-Path -LiteralPath $readerFixtureRoot) { Remove-Item -LiteralPath $readerFixtureRoot -Recurse -Force }
}

Write-Output 'MIR42-NINE-TARGET-TECHNICAL-SEAL-PASSED scopes=4,9 historical=5 engines=0'
