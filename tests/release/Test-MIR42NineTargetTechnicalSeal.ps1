# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [switch]$OnlyClassicSealSnapshotProjection
)

Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$reader = Join-Path $repo 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1'
if (-not (Test-Path -LiteralPath $reader -PathType Leaf)) { throw "[mir42-nine-seal-stage-missing] $reader" }
. $reader

function Assert-MIR42NineSealTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-nine-seal-test-$Code]" }
}
function Test-MIR42ConsumedEngineRunReferences {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $ErrorActionPreference = 'Stop'
  $sourcePath = Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1'
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$null,[ref]$errors)
  if ($errors) { throw '[mir42-engine-reference-source-parser]' }
  $root = Join-Path $RepoRoot ('build/test-results/mir42-engine-reference-' + [guid]::NewGuid().ToString('N'))
  $assertions = 0
  try {
    $campaignWriter = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'New-MIR42NineTargetJoinedRealEngineCampaign'},$true))[0]
    $commands = @($campaignWriter.Body.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true))
    $guards = @($commands | Where-Object {$_.GetCommandName() -ceq 'Assert-MIR42RealEngineCampaignExecution'})
    $writes = @($commands | Where-Object {$_.GetCommandName() -ceq 'Write-MIR42NormalizedRecord'})
    Assert-MIR42NineSealTest -Condition ($guards.Count -eq 1 -and $writes.Count -eq 1) -Code 'campaign-prewrite-native-guard-cardinality'
    $assertions++
    Assert-MIR42NineSealTest -Condition ($guards[0].Extent.StartOffset -lt $writes[0].Extent.StartOffset) -Code 'campaign-native-guard-precedes-qualified-artifact-write'
    $assertions++
    New-Item -ItemType Directory -Path $root | Out-Null
    $path = Join-Path $root 'unqualified-reference-probe.json'
    # This hash-valid, deliberately incomplete record has no native status,
    # observations or qualification. The run reader must always refuse it.
    $record = [pscustomobject][ordered]@{kind='engine-reference-source-contract-probe-not-run';record_sha256=''}
    Write-MIR4BootstrapRecord -Record $record -Path $path | Out-Null
    $engineRun = Read-MIR42SealRecord -Path $path -Code 'mir42-engine-reference-probe'
    foreach ($name in @('New-MIR42FourTargetRealEngineEvidenceBinder','New-MIR42NineTargetJoinedRealEngineCampaign')) {
      $functions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name },$true))
      if ($functions.Count -ne 1) { throw '[mir42-engine-reference-producer-cardinality]' }
      $expressions = @(
        foreach ($table in $functions[0].Body.FindAll({ param($node) $node -is [Management.Automation.Language.HashtableAst] },$true)) {
          foreach ($pair in $table.KeyValuePairs) {
            if ($pair.Item1.Extent.Text -ceq 'engine_run') { $pair.Item2 }
          }
        }
      )
      if ($expressions.Count -ne 1) { throw '[mir42-engine-reference-field-cardinality]' }
      # Consume the producer's actual expression through its real serialized
      # shape. A separately authored reference would miss the omission.
      $produced = & ([scriptblock]::Create($expressions[0].Extent.Text))
      $reference = $produced | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10
      foreach ($scope in @('four-target','nine-target')) {
        $targets = if ($scope -ceq 'four-target') { $script:MIR42SealTargets } else { $script:MIR42SealNineTargetCandidates }
        $candidate = [pscustomobject]@{targets=@($targets | ForEach-Object { [pscustomobject]@{target=$_} })}
        foreach ($case in @('intact','missing-file','changed-raw-hash','changed-record-hash')) {
          $inputReference = $reference | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10
          $expected = '[mir42-seal-engine-run-shape]'
          switch ($case) {
            'missing-file' { $inputReference.path += '-absent'; $expected = '[mir42-seal-engine-run-reference-missing]' }
            'changed-raw-hash' { $inputReference.sha256 = '0' * 64; $expected = '[mir42-seal-engine-run-reference-hash]' }
            'changed-record-hash' { $inputReference.record_sha256 = '0' * 64; $expected = '[mir42-seal-engine-run-reference-binding]' }
          }
          $failure = ''
          try { $null = Get-MIR42BoundEngineRun -Reference $inputReference -Candidate $candidate } catch { $failure = $_.Exception.Message }
          Assert-MIR42NineSealTest -Condition ($failure -ceq $expected) -Code ('engine-reference-' + $name + '-' + $scope + '-' + $case)
          $assertions++
        }
      }
    }
  } finally {
    $approved = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/test-results')).TrimEnd('\') + '\'
    if (-not ([IO.Path]::GetFullPath($root) + '\').StartsWith($approved,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-engine-reference-containment]' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  }
  Write-Output ('MIR42-ENGINE-REFERENCE-CONTRACT-PASSED assertions=' + $assertions + ' native-records=0 engines=0')
}

if (-not $OnlyClassicSealSnapshotProjection) {
  Test-MIR42ConsumedEngineRunReferences -RepoRoot $repo
}

function Test-MIR42MaintenanceSealConsumption {
  param([Parameter(Mandatory)][string]$RepoRoot)
  . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1')
  $arguments = @{
    RepoRoot=$RepoRoot;CandidateManifestPath='absent-maintenance-control.json'
    QualificationPath='unread-control.json';RealEngineCampaignPath='unread-control.json'
    IndependentVerificationPath='unread-control.json';SigningCeremonyPath='unread-control.json'
    SourceFreezeAuthorityPath='unread-control.json';ReviewerAttestationPath='unread-control.json'
    SshKeygenPath='unread-control.exe';PublishedMaintenancePredecessorManifestPath='unread-published-control.json'
  }
  $archiveBindings = @{f210='C:\\synthetic-nonrelease\\more-infinite-research_4.2.21002.zip'}
  $unscopedArguments = @{}; foreach ($key in $arguments.Keys) { $unscopedArguments[$key] = $arguments[$key] }
  $null = $unscopedArguments.Remove('PublishedMaintenancePredecessorManifestPath')
  $unscopedArguments.PublishedMaintenanceArchiveBindings = $archiveBindings
  $failure='';try { Get-MIR42PromotionTechnicalSealReadiness -RequiredScope nine-target @unscopedArguments | Out-Null } catch { $failure=$_.Exception.Message }
  Assert-MIR42NineSealTest -Condition ($failure -ceq '[mir42-maintenance-promotion-archive-bindings-scope]') -Code 'maintenance-promotion-refuses-unscoped-archive-bindings'
  $failure='';try { New-MIR42FourTargetRealEngineEvidenceBinder -RepoRoot $RepoRoot -CandidateManifestPath 'absent-maintenance-control.json' -EvidenceReconciliationPath 'unread-control.json' -EngineRunPath 'unread-control.json' -OutputPath 'unwritten-control.json' -PublishedMaintenanceArchiveBindings $archiveBindings | Out-Null } catch { $failure=$_.Exception.Message }
  Assert-MIR42NineSealTest -Condition ($failure -ceq '[mir42-engine-evidence-maintenance-archive-bindings-scope]') -Code 'maintenance-engine-evidence-refuses-unscoped-archive-bindings'
  $failure='';try { New-MIR42NineTargetJoinedRealEngineCampaign -RepoRoot $RepoRoot -CandidateManifestPath 'absent-maintenance-control.json' -EvidenceReconciliationPath 'unread-control.json' -EngineEvidencePath 'unread-control.json' -CriterionEvidencePaths @('unread-control.json') -OutputPath 'unwritten-control.json' -PublishedMaintenanceArchiveBindings $archiveBindings | Out-Null } catch { $failure=$_.Exception.Message }
  Assert-MIR42NineSealTest -Condition ($failure -ceq '[mir42-joined-campaign-maintenance-archive-bindings-scope]') -Code 'maintenance-joined-campaign-refuses-unscoped-archive-bindings'
  # Missing candidate admission prevents all network, engine, signing and
  # promotion execution. The specific maintenance blocker proves propagation.
  $readiness = Get-MIR42PromotionTechnicalSealReadiness -RequiredScope nine-target @arguments
  Assert-MIR42NineSealTest -Condition (-not $readiness.technical_seal_authorized -and -not $readiness.checks.maintenance_predecessor) -Code 'maintenance-promotion-readiness-propagates-custody-request'
  $failure='';try { Get-MIR42PromotionTechnicalSealReadiness -RequiredScope four-target @arguments | Out-Null } catch { $failure=$_.Exception.Message }
  Assert-MIR42NineSealTest -Condition ($failure -ceq '[mir42-maintenance-promotion-candidate-scope]') -Code 'maintenance-promotion-refuses-four-scope'
  $arguments.TechnicalSealPath='unread-control.json'
  $arguments.OfflineRestoreDrillPath='unread-control.json'
  foreach ($entry in @(
    @{command='Get-MIR42NineTargetProtectedMainPromotionPlan';extra=@{}},
    @{command='Get-MIR42NineTargetProtectedMainReadback';extra=@{PrimaryRepoRoot=(Join-Path $RepoRoot 'tests');PullRequestNumber=1;IntentionPath='unread-control.json';PromotionRequestPath='unread-control.json'}}
  )) {
    $failure='';$extra=$entry.extra
    try { & $entry.command @arguments @extra | Out-Null } catch { $failure=$_.Exception.Message }
    Assert-MIR42NineSealTest -Condition ($failure.StartsWith('[mir42-promotion-verified-seal-inputs]') -and $failure.Contains('[mir42-maintenance-readiness-predecessor-unavailable]')) -Code ('maintenance-consumer-propagation-' + $entry.command)
  }
  # Consume only the custody field from the actual writer and reconstruction
  # expressions. These subsets have no seal status, signature or native proof.
  $custody = [pscustomobject]@{fixture_scope='custody-expression-only-not-executed';targets=@($script:MIR42SealNineTargetCandidates | ForEach-Object { [pscustomobject]@{target=$_;identity=('custody-' + $_)} })}
  $state = [pscustomobject]@{maintenance_inputs=$custody}
  foreach ($entry in @(
    @{path='tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1';name='New-MIR42TechnicalSealForScope';variable='seal'},
    @{path='tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1';name='Assert-MIR42ExpectedTechnicalSeal';variable='expected'}
  )) {
    $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot $entry.path),[ref]$null,[ref]$errors)
    if ($errors) { throw '[mir42-maintenance-seal-custody-expression-parser]' }
    $definitions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $entry.name},$true))
    Assert-MIR42NineSealTest -Condition ($definitions.Count -eq 1) -Code 'maintenance-seal-custody-expression-function'
    $attachments=@($definitions[0].Body.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Add-Member' -and $node.Extent.Text.Contains('published_maintenance_predecessor')},$true))
    Assert-MIR42NineSealTest -Condition ($attachments.Count -eq 1) -Code 'maintenance-seal-custody-expression-cardinality'
    Set-Variable -Name $entry.variable -Value ([pscustomobject]@{fixture_scope='custody-field-only-not-a-seal'})
    . ([scriptblock]::Create($attachments[0].Parent.Extent.Text))
    $serialized=Get-Variable -Name $entry.variable -ValueOnly | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    Assert-MIR42NineSealTest -Condition ((ConvertTo-MIR4BootstrapCanonicalJson -Value $serialized.published_maintenance_predecessor) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $custody)) -Code ('maintenance-seal-preserves-complete-custody-' + $entry.name)
  }
  Write-Output 'MIR42-MAINTENANCE-SEAL-CONSUMPTION-PASSED propagation_checks=4 custody_expression_checks=6 seals=0 engines=0 signatures=0 remote_mutations=0'
}

if (-not $OnlyClassicSealSnapshotProjection) {
  Test-MIR42MaintenanceSealConsumption -RepoRoot $repo
}

function Get-MIR42NineSealCommittedHistoricalFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target)

  $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target
  $targetRecordPath = Join-Path $RepoRoot ([string]$identity.target_record_path)
  $targetRecord = Read-MIR42SealRecord -Path $targetRecordPath -Code "mir42-nine-seal-fixture-target-record-$Target"
  $record = $targetRecord.record
  if ([string]$targetRecord.sha256 -cne [string]$identity.target_record_file_sha256 -or
      [string]$record.record_sha256 -cne [string]$identity.target_record_record_sha256 -or
      [int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42HistoricalPlaytestTargetV1' -or
      [string]$record.target -cne $Target -or [string]$record.maturity -cne 'private-historical-playtest' -or
      [string]$record.base_materializer_target -cne 'f100' -or [string]$record.factorio_line -cne ([string]$identity.target_id -replace '^factorio-', '') -or
      [string]$record.distribution_version -cne [string]$identity.distribution_version -or
      [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-nine-seal-fixture-target-record] $Target"
  }
  $sealRelative = '.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json'
  $seal = Read-MIR42SealRecord -Path (Join-Path $RepoRoot $sealRelative) -Code "mir42-nine-seal-fixture-terminal-seal-$Target"
  if ([int]$seal.record.schema -ne 1 -or [string]$seal.record.kind -cne 'Mir3TerminalTargetSealV1' -or
      [string]$seal.record.status -cne 'sealed' -or [string]$seal.record.release -cne [string]$record.predecessor.version -or
      [string]$seal.record.target -cne [string]$record.factorio_line -or [string]$seal.record.archive_sha256 -cne [string]$record.predecessor.sha256 -or
      [string]$seal.record.engine.version -cne [string]$record.engine.version -or [string]$seal.record.engine.binary_sha256 -cne [string]$record.engine.sha256) {
    throw "[mir42-nine-seal-fixture-terminal-seal] $Target"
  }
  return [pscustomobject][ordered]@{
    fixture_scope='committed-target-record-and-terminal-seal-only';identity=$identity;target_record=$targetRecord;terminal_seal=$seal
  }
}
function New-MIR42NineSealSyntheticHistoricalFixture {
  param([Parameter(Mandatory)][string]$FixtureRoot,[Parameter(Mandatory)][string]$Target)

  $line = '0.' + $Target.Substring(1)
  $enginePath = Join-Path $FixtureRoot ("engine-$Target.bin")
  $predecessorPath = Join-Path $FixtureRoot ("predecessor-$Target.zip")
  [IO.File]::WriteAllText($enginePath,"synthetic historical engine $Target",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($predecessorPath,"synthetic historical predecessor $Target",[Text.UTF8Encoding]::new($false))
  $engineHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $predecessorHash = (Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $predecessorVersion = "fixture-$Target"
  $predecessorArchive = ('tests/synthetic/' + [IO.Path]::GetFileName($predecessorPath))
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR42HistoricalPlaytestTargetV1';target=$Target;maturity='structural-fixture';base_materializer_target='f100';factorio_line=$line
    distribution_version=('4.2.' + $Target.Substring(1) + '00');engine=[pscustomobject][ordered]@{path=$enginePath;version="fixture-$Target";sha256=$engineHash}
    predecessor=[pscustomobject][ordered]@{version=$predecessorVersion;archive=$predecessorArchive;sha256=$predecessorHash};public_output_authorized=$false;publication_authorized=$false;record_sha256=$engineHash
  }
  $sealRecord = [pscustomobject][ordered]@{
    schema=1;kind='Mir3TerminalTargetSealV1';status='sealed';release=$predecessorVersion;target=$line;archive_sha256=$predecessorHash
    bytes=[int64](Get-Item -LiteralPath $predecessorPath).Length;content_sha256=$predecessorHash;entries=1
    engine=[pscustomobject][ordered]@{version="fixture-$Target";binary_sha256=$engineHash};record_sha256=$predecessorHash
  }
  return [pscustomobject][ordered]@{
    fixture_scope='synthetic-structural-reader-only';identity=[pscustomobject][ordered]@{target=$Target;target_record_path=('tests/synthetic/target-' + $Target + '.json')}
    target_record=[pscustomobject][ordered]@{sha256=$engineHash;record=$record};terminal_seal=[pscustomobject][ordered]@{sha256=$predecessorHash;record=$sealRecord};predecessor_path=$predecessorPath
  }
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
$release450 = Get-MIR42NineTargetReleaseLineContract -SourceVersion '4.5.0'
Assert-MIR42NineSealTest -Condition ([string]$release450.release_line -ceq '4.5' -and
  [string]$release450.programme_pending_status -ceq 'active-current-4.5-release-cut-pre-freeze-no-transition-authority' -and
  [string]$release450.promotion_plan_status -ceq 'MIR-4.5-NINE-TARGET-PROTECTED-MAIN-PROMOTION-PLAN-ONLY' -and
  [string]$release450.candidate_ref_prefix -ceq 'refs/heads/release/mir-4.5-candidate-') -Code '450-release-line-contract-is-exact'
$candidateRelease450 = Get-MIR42NineTargetCandidateReleaseLineContract -Candidate ([pscustomobject]@{source_version='4.5.0'})
Assert-MIR42NineSealTest -Condition ([string]$candidateRelease450.release_line -ceq '4.5') -Code '450-candidate-release-line-is-explicit'

function Test-MIR42NineCriterionEvidenceReader {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $root = Join-Path $RepoRoot ('build/test-results/mir42-nine-criterion-reader-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
  $candidate = [pscustomobject][ordered]@{
    source=$source
    identity=[pscustomobject][ordered]@{sha256=('D' * 64);record=[pscustomobject][ordered]@{record_sha256=('E' * 64)}}
  }
  $path = Join-Path $root 'criterion.json'
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetReleaseAcceptanceCriterionEvidenceV1';status='passed';criterion='settings-profile-continuity'
    source=$source;candidate_manifest=[pscustomobject][ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    observed_targets=@($script:MIR42SealNineTargetCandidates);not_applicable_targets=@();evidence=@();limits=[pscustomobject][ordered]@{claim='structural fixture';known_limitations='reader only'};record_sha256=''
  }
  Write-MIR4BootstrapRecord -Record $record -Path $path | Out-Null
  $accepted = Get-MIR42NineTargetCriterionEvidenceRecord -Path $path -Candidate $candidate
  Assert-MIR42NineSealTest -Condition ([string]$accepted.record.criterion -ceq 'settings-profile-continuity') -Code 'criterion-reader-accepted'
  $record.criterion='outside-authorized-criterion-set'
  Write-MIR4BootstrapRecord -Record $record -Path $path | Out-Null
  $rejected=$false
  try { Get-MIR42NineTargetCriterionEvidenceRecord -Path $path -Candidate $candidate | Out-Null } catch { $rejected=$_.Exception.Message -match '^\[mir42-joined-campaign-criterion-binding\]' }
  Assert-MIR42NineSealTest -Condition $rejected -Code 'criterion-reader-unrecognized-rejected'
}

if (-not $OnlyClassicSealSnapshotProjection) {
  Test-MIR42NineCriterionEvidenceReader -RepoRoot $repo
}

Assert-MIR42SealCandidateScopeMatch -Rows @($nine.targets) -Candidate $nine -Code 'mir42-nine-seal-match'
$rejected = $false
try { Assert-MIR42SealCandidateScopeMatch -Rows @($modern.targets) -Candidate $nine -Code 'mir42-nine-seal-opposing' } catch { $rejected = $_.Exception.Message -match '^\[mir42-nine-seal-opposing-target-set\]' }
Assert-MIR42NineSealTest -Condition $rejected -Code 'mixed-scope-rejected'

foreach ($target in $script:MIR42SealHistoricalTargets) {
  $committed = Get-MIR42NineSealCommittedHistoricalFixture -RepoRoot $repo -Target $target
  $record = $committed.target_record.record
  $seal = $committed.terminal_seal.record
  Assert-MIR42NineSealTest -Condition ([string]$committed.fixture_scope -ceq 'committed-target-record-and-terminal-seal-only' -and
    [string]$committed.identity.target -ceq $target -and [string]$record.target -ceq $target) -Code "committed-identity-$target"
  Assert-MIR42NineSealTest -Condition ([string]$seal.release -ceq [string]$record.predecessor.version -and
    [string]$seal.archive_sha256 -ceq [string]$record.predecessor.sha256 -and
    [string]$seal.engine.binary_sha256 -ceq [string]$record.engine.sha256) -Code "committed-binding-$target"
}
$terminalFixtureRoot = Join-Path $repo ('build/test-results/mir42-nine-terminal-reader-' + [guid]::NewGuid().ToString('N'))
$historicalReader = (Get-Item Function:Get-MIR42HistoricalTerminalAuthority).ScriptBlock
try {
  New-Item -ItemType Directory -Force -Path $terminalFixtureRoot | Out-Null
  $historicalFixtures = @{}
  foreach ($target in $script:MIR42SealHistoricalTargets) { $historicalFixtures[$target] = New-MIR42NineSealSyntheticHistoricalFixture -FixtureRoot $terminalFixtureRoot -Target $target }
  Set-Item Function:Get-MIR42HistoricalTerminalAuthority -Value { param($RepoRoot,$Target) return $historicalFixtures[$Target] }
  foreach ($target in $script:MIR42SealHistoricalTargets) {
    $authority = $historicalFixtures[$target]
    $record = $authority.target_record.record
    $seal = $authority.terminal_seal.record
    Assert-MIR42NineSealTest -Condition ([string]$authority.fixture_scope -ceq 'synthetic-structural-reader-only' -and [string]$authority.identity.target -ceq $target) -Code "identity-$target"
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
      predecessor=[pscustomobject][ordered]@{path=[string]$authority.predecessor_path;sha256=[string]$record.predecessor.sha256;version=[string]$record.predecessor.version}
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
} finally {
  Set-Item Function:Get-MIR42HistoricalTerminalAuthority -Value $historicalReader
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build'))
  if (-not [IO.Path]::GetFullPath($terminalFixtureRoot).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-terminal-fixture-containment]' }
  if (Test-Path -LiteralPath $terminalFixtureRoot) { Remove-Item -LiteralPath $terminalFixtureRoot -Recurse -Force }
}

$readerFixtureRoot = Join-Path $repo ('build/test-results/mir42-nine-seal-reader-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $readerFixtureRoot | Out-Null
  # Historical fresh loads have a compact V1 receipt and Factorio normalizes
  # the leading zero in the archive version when logging the loaded mod.
  $freshLog = Join-Path $readerFixtureRoot 'historical-fresh.log'
  $freshSave = Join-Path $readerFixtureRoot 'historical-fresh.zip'
  $freshEnginePath = Join-Path $readerFixtureRoot 'historical-engine.bin'
  $freshCandidatePath = Join-Path $readerFixtureRoot 'historical-candidate.zip'
  $freshStdout = Join-Path $readerFixtureRoot 'historical-fresh.stdout'
  $freshStderr = Join-Path $readerFixtureRoot 'historical-fresh.stderr'
  [IO.File]::WriteAllText($freshLog,"Loading mod more-infinite-research 4.2.1700 (data.lua)`nFactorio initialised`nCreating new map",[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($freshSave,'synthetic historical save',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($freshEnginePath,'synthetic historical engine',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($freshCandidatePath,'synthetic historical candidate',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($freshStdout,'synthetic stdout',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($freshStderr,'',[Text.UTF8Encoding]::new($false))
  $freshLogHash = (Get-FileHash -LiteralPath $freshLog -Algorithm SHA256).Hash.ToUpperInvariant()
  $freshSource = 'a' * 40
  $freshArchive = (Get-FileHash -LiteralPath $freshCandidatePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $freshEngine = (Get-FileHash -LiteralPath $freshEnginePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $freshRecord = [pscustomobject][ordered]@{
    schema=1;kind='MIR42HistoricalFreshLoadV1';status='passed';target='f017';source_commit=$freshSource;factorio_line='0.17'
    engine=[pscustomobject][ordered]@{path=$freshEnginePath;sha256=$freshEngine}
    candidate=[pscustomobject][ordered]@{path=$freshCandidatePath;sha256=$freshArchive;version='4.2.01700'}
    staged_candidate_sha256=$freshArchive
    save=[pscustomobject][ordered]@{path=$freshSave;sha256=(Get-FileHash -LiteralPath $freshSave -Algorithm SHA256).Hash.ToUpperInvariant()}
    log=[pscustomobject][ordered]@{path=$freshLog;sha256=$freshLogHash}
    assertions=@('exact-engine','exact-candidate','fresh-save-created','exact-mod-loaded','map-created','healthy-log')
    record_sha256=''
  }
  $freshReceipt = Join-Path $readerFixtureRoot 'historical-fresh.json'
  Write-MIR4BootstrapRecord -Record $freshRecord -Path $freshReceipt | Out-Null
  $freshRefs = [pscustomobject][ordered]@{
    scenario='package-zip-base'
    receipt=[pscustomobject][ordered]@{path=$freshReceipt;sha256=(Get-FileHash -LiteralPath $freshReceipt -Algorithm SHA256).Hash.ToUpperInvariant()}
    log=[pscustomobject][ordered]@{path=$freshLog;sha256=$freshLogHash}
    stdout=[pscustomobject][ordered]@{path=$freshStdout;sha256=(Get-FileHash -LiteralPath $freshStdout -Algorithm SHA256).Hash.ToUpperInvariant()}
    stderr=[pscustomobject][ordered]@{path=$freshStderr;sha256=(Get-FileHash -LiteralPath $freshStderr -Algorithm SHA256).Hash.ToUpperInvariant()}
  }
  $freshTarget = [pscustomobject][ordered]@{target='f017';target_id='factorio-0.17';distribution_version='4.2.01700';archive=[pscustomobject][ordered]@{sha256=$freshArchive}}
  $freshCandidate = [pscustomobject][ordered]@{source=[pscustomobject][ordered]@{commit=$freshSource}}
  $freshExecution = [pscustomobject][ordered]@{executable_path=$freshEnginePath;executable_sha256=$freshEngine;version='0.17.79';fresh_loads=@($freshRefs)}
  Assert-MIR42FreshEngineLoads -Target $freshTarget -CandidateTarget $freshCandidate -Execution $freshExecution
  $writeFreshVersionFixture = {
    param([string]$DistributionVersion,[string]$LoggedVersion)
    $freshTarget.distribution_version = $DistributionVersion
    $freshRecord.candidate.version = $DistributionVersion
    [IO.File]::WriteAllText($freshLog,"Loading mod more-infinite-research $LoggedVersion (data.lua)`nFactorio initialised`nCreating new map",[Text.UTF8Encoding]::new($false))
    $freshRecord.log.sha256 = (Get-FileHash -LiteralPath $freshLog -Algorithm SHA256).Hash.ToUpperInvariant()
    $freshRefs.log.sha256 = $freshRecord.log.sha256
    $freshRecord.record_sha256 = ''
    Write-MIR4BootstrapRecord -Record $freshRecord -Path $freshReceipt | Out-Null
    $freshRefs.receipt.sha256 = (Get-FileHash -LiteralPath $freshReceipt -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  foreach ($versionCase in @(
    @{distribution='4.3.01700';logged='4.3.1700'},
    @{distribution='4.4.01700';logged='4.4.1700'},
    @{distribution='4.4.01702';logged='4.4.1702'}
  )) {
    & $writeFreshVersionFixture $versionCase.distribution $versionCase.logged
    Assert-MIR42FreshEngineLoads -Target $freshTarget -CandidateTarget $freshCandidate -Execution $freshExecution
  }
  # Hash-valid observations must still reject an unadmitted minor and a
  # different loaded patch; expanding 4.4 support must not loosen either guard.
  & $writeFreshVersionFixture '4.5.01700' '4.5.1700'
  $futureMinorRejected = $false
  try { Assert-MIR42FreshEngineLoads -Target $freshTarget -CandidateTarget $freshCandidate -Execution $freshExecution }
  catch { $futureMinorRejected = $_.Exception.Message -ceq '[mir42-seal-historical-distribution-version] f017' }
  Assert-MIR42NineSealTest -Condition $futureMinorRejected -Code 'historical-fresh-unadmitted-minor-rejected'
  & $writeFreshVersionFixture '4.4.01702' '4.4.1701'
  $wrongLoadedPatchRejected = $false
  try { Assert-MIR42FreshEngineLoads -Target $freshTarget -CandidateTarget $freshCandidate -Execution $freshExecution }
  catch { $wrongLoadedPatchRejected = $_.Exception.Message -ceq '[mir42-seal-real-engine-fresh-load-log-marker] f017/package-zip-base' }
  Assert-MIR42NineSealTest -Condition $wrongLoadedPatchRejected -Code 'historical-fresh-wrong-loaded-patch-rejected'
  & $writeFreshVersionFixture '4.4.01702' '4.4.1702'
  $freshRecord.source_commit = 'b' * 40
  $freshRecord.record_sha256 = ''
  $wrongFreshReceipt = Join-Path $readerFixtureRoot 'historical-fresh-wrong-source.json'
  Write-MIR4BootstrapRecord -Record $freshRecord -Path $wrongFreshReceipt | Out-Null
  $freshRefs.receipt = [pscustomobject][ordered]@{path=$wrongFreshReceipt;sha256=(Get-FileHash -LiteralPath $wrongFreshReceipt -Algorithm SHA256).Hash.ToUpperInvariant()}
  $wrongFreshRejected = $false
  try { Assert-MIR42FreshEngineLoads -Target $freshTarget -CandidateTarget $freshCandidate -Execution $freshExecution }
  catch { $wrongFreshRejected = $_.Exception.Message -match '^\[mir42-seal-real-engine-fresh-load-binding\] f017/package-zip-base' }
  Assert-MIR42NineSealTest -Condition $wrongFreshRejected -Code 'historical-fresh-wrong-source-rejected'

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

function Test-MIR42IndividualNativeInputReader {
  param([Parameter(Mandatory)][string]$RepoRoot)

  # These files are deliberately host-only structural inputs. They exercise the
  # reader's exact receipt and fresh-load bindings without launching Factorio or
  # claiming native qualification.
  . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
  . (Join-Path $RepoRoot 'tests/support/MIR423ReleaseUpgradeControls.ps1')
  if (-not (Get-Command Get-MIRImmutableInputFileIdentity -ErrorAction SilentlyContinue)) {
    . (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
  }
  $root = Join-Path $RepoRoot ('build/test-results/mir42-individual-native-reader-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  # A fixture cannot satisfy the real frozen-candidate construction reader.
  # Keep that provenance contract outside this host-only fixture, while still
  # exercising the individual-input reader's complete receipt, custody and
  # fresh-load binding path below.
  $individualContractReader = (Get-Command Get-MIR42IndividualEngineEvidenceBindingContract -CommandType Function -ErrorAction Stop).ScriptBlock
  $checks = 0
  function Get-HostHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
  function Write-HostText([string]$Path,[string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
    return [pscustomobject][ordered]@{path=$Path;sha256=(Get-HostHash $Path)}
  }
  function Write-HostJson([string]$Path,$Value) {
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    return [pscustomobject][ordered]@{path=$Path;sha256=(Get-HostHash $Path)}
  }
  function Write-HostBootstrap([string]$Path,$Record) {
    # Mutated fixtures must be normalized as fresh immutable records; retaining
    # a predecessor's record hash would correctly be rejected as tampering.
    $recordForWrite = if ($Record -is [Collections.IDictionary]) { [pscustomobject]$Record } else { $Record }
    $recordForWrite.record_sha256 = ''
    Write-MIR4BootstrapRecord -Record $recordForWrite -Path $Path | Out-Null
    return Read-MIR42SealRecord -Path $Path -Code 'mir42-individual-reader-fixture'
  }
  function Get-HostBootstrapReference($Identity) {
    return [pscustomobject][ordered]@{path=[string]$Identity.path;sha256=[string]$Identity.sha256;record_sha256=[string]$Identity.record.record_sha256}
  }
  function Copy-HostValue($Value) { $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100 }
  function Set-HostReceiptField($Record,[int]$Index,[hashtable]$Receipt) {
    $receiptRoot = Split-Path -Parent ([string]$Record.individual_upgrade_receipts[$Index].receipt.path)
    $reference = Write-HostJson (Join-Path $receiptRoot ('reader-mutation-' + $Index + '-' + [guid]::NewGuid().ToString('N') + '.json')) $Receipt
    $Record.individual_upgrade_receipts[$Index].receipt = [ordered]@{path=$reference.path;sha256=$reference.sha256}
  }
  function Assert-HostReaderRefusal([string]$Name,$Record,[string]$Prefix) {
    $path = Join-Path $root ($Name + '.json')
    $reference = Get-HostBootstrapReference (Write-HostBootstrap $path $Record)
    $failure = ''
    try { $null = Get-MIR42BoundEngineRun -Reference $reference -Candidate $script:mir42IndividualReaderCandidate -PublishedMaintenanceInputs $script:mir42IndividualReaderPublished }
    catch { $failure = $_.Exception.Message }
    if (-not $failure.StartsWith($Prefix,[StringComparison]::Ordinal)) {
      throw "[mir42-individual-reader-unexpected-refusal] $Name :: $failure"
    }
    $script:mir42IndividualReaderChecks++
  }
  try {
    Set-Item -LiteralPath Function:script:Get-MIR42IndividualEngineEvidenceBindingContract -Value {
      param($Candidate,[switch]$PublishedMaintenance)
      if (-not $PublishedMaintenance) { throw '[mir42-individual-engine-run-maintenance-required]' }
      return [pscustomobject][ordered]@{
        maintenance_source_version='4.2.3'
        engine_run_kind='MIR42NineTargetMaintenanceIndividualEngineRunV1'
        engine_run_status='nine-target-maintenance-individual-real-engine-probes-passed-private-unqualified'
        binder_kind='MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
        binder_status='MIR-4.2.3-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
      }
    }
    $script:mir42IndividualReaderChecks = 0
    $source = [pscustomobject][ordered]@{commit=('A' * 40);tree=('B' * 40);package_source_sha256=('C' * 64)}
    $packages = @()
    foreach ($target in $script:MIR42SealNineTargetCandidates) {
      $code = $target.Substring(1)
      $version = '4.2.' + $code + '03'
      $archive = Write-HostText (Join-Path $root ('more-infinite-research_' + $version + '.zip')) ('host-only candidate ' + $target)
      $packages += [pscustomobject][ordered]@{
        target=$target;distribution_version=$version;archive_sha256=$archive.sha256;content_sha256=$archive.sha256;entry_count=1;archive_path=$archive.path
      }
    }
    $manifestRecord = [pscustomobject][ordered]@{
      schema=1;kind='MIR42IndividualReaderCandidateFixtureV1';source=$source;build_complete=$true;record_sha256=''
    }
    $manifest = Write-HostBootstrap (Join-Path $root 'candidate-manifest.json') $manifestRecord
    $script:mir42IndividualReaderCandidate = [pscustomobject][ordered]@{identity=$manifest;source=$source;targets=$packages}

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $engineHash = Get-HostHash $pwsh
    $engineVersion = [string](Get-Item -LiteralPath $pwsh).VersionInfo.FileVersion
    $engineProductVersion = [string](Get-Item -LiteralPath $pwsh).VersionInfo.ProductVersion
    if ($engineProductVersion -match '^([0-9]+[.][0-9]+[.][0-9]+)') { $engineProductVersion = [string]$Matches[1] }
    $packageAssets = @($packages | ForEach-Object { [pscustomobject][ordered]@{target=$_.target;distribution_version=$_.distribution_version;sha256=$_.archive_sha256} })
    $control = Invoke-MIR423ReleaseUpgradeControls -Root (Join-Path $root 'upgrade-controls') -PackageAssets $packageAssets
    Assert-MIR42NineSealTest -Condition ([int]$control.checks -gt 0 -and [int]$control.native_runs -eq 0) -Code 'individual-host-control-only-upgrade-fixtures'
    $checks++
    $upgradeEvidence = Get-Content -LiteralPath $control.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $publishedTargets = @()
    foreach ($target in $script:MIR42SealNineTargetCandidates) {
      $published = Get-MIR423PublishedUpgradePredecessor -Target $target -PredecessorSourceVersion '4.2.2'
      $publishedTargets += [pscustomobject][ordered]@{
        target=$target;version=[string]$published.target.distribution_version;path=(Join-Path $root ('published-' + $target + '.zip'))
        sha256=[string]$published.target.sha256;bytes=[int64]$published.target.bytes;content_sha256=[string]$published.target.content_sha256;entry_count=[int]$published.target.entry_count
        source_tag=[string]$published.source_tag;manifest=[pscustomobject][ordered]@{sha256=[string]$published.manifest.sha256}
      }
    }
    $script:mir42IndividualReaderPublished = [pscustomobject][ordered]@{
      release_id=408949558;source_tag='v4.2.2';source=[pscustomobject][ordered]@{commit=('D' * 40);tree=('E' * 40)}
      tag_object=('9' * 40);remote_tag_readback=$true
      manifest=[pscustomobject][ordered]@{path='host-only-published-422-manifest.json';sha256=[string]$publishedTargets[0].manifest.sha256;bytes=1};signed=$false
      targets=$publishedTargets;native_qualification='not-performed';release_qualification='not-performed'
    }
    $receipts = @()
    $nativeLibrary = Join-Path $root 'host-only-native-library'
    New-Item -ItemType Directory -Force -Path $nativeLibrary | Out-Null
    foreach ($target in $script:MIR42SealNineTargetCandidates) {
      $row = @($upgradeEvidence.rows | Where-Object { [string]$_.target -ceq $target -and [string]$_.predecessor_source_version -ceq '4.2.2' })
      Assert-MIR42NineSealTest -Condition ($row.Count -eq 1) -Code ('individual-selected-422-row-' + $target)
      $receipt = Get-Content -LiteralPath $row[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
      $published = @($publishedTargets | Where-Object { [string]$_.target -ceq $target })[0]
      $candidateTarget = @($packages | Where-Object { [string]$_.target -ceq $target })[0]
      $nativeArchivePath = Join-Path $nativeLibrary ('more-infinite-research_' + [string]$candidateTarget.distribution_version + '.zip')
      # A tiny synthetic archive for a host-only reader fixture. It is neither
      # a Factorio package nor an engine-library input.
      [IO.File]::WriteAllBytes($nativeArchivePath,[IO.File]::ReadAllBytes([string]$candidateTarget.archive_path))
      $nativeArchiveHash = Get-HostHash $nativeArchivePath
      $receipt.git_commit = [string]$source.commit
      $receipt.factorio_binary_sha256 = $engineHash
      $receipt.factorio_binary_version = $engineVersion
      $receipt.published_maintenance_predecessor = [ordered]@{
        release_id=[int64]$script:mir42IndividualReaderPublished.release_id;source_tag=[string]$script:mir42IndividualReaderPublished.source_tag
        source=$script:mir42IndividualReaderPublished.source;tag_object=[string]$script:mir42IndividualReaderPublished.tag_object
        remote_tag_readback=[bool]$script:mir42IndividualReaderPublished.remote_tag_readback;manifest=$script:mir42IndividualReaderPublished.manifest
        signed=[bool]$script:mir42IndividualReaderPublished.signed;targets=@($published)
        native_qualification=[string]$script:mir42IndividualReaderPublished.native_qualification
        release_qualification=[string]$script:mir42IndividualReaderPublished.release_qualification
        local_custody_scope='selected-native-archive'
      }
      $receipt.library_activation.selected = @([ordered]@{
        name='more-infinite-research';version=[string]$candidateTarget.distribution_version;path=$nativeArchivePath;builtin=$false
        identity=(Get-MIRImmutableInputFileIdentity -Path $nativeArchivePath);sha256=$nativeArchiveHash;bytes=[int64](Get-Item -LiteralPath $nativeArchivePath).Length
      })
      for ($ledgerIndex=0; $ledgerIndex -lt @($receipt.resource_ledgers).Count; $ledgerIndex++) {
        $ledger = $receipt.resource_ledgers[$ledgerIndex]
        $exitCode = if ($ledgerIndex -eq 0) { -1 } else { 0 }
        $completed = $true
        $peak = [int64](4096 + $ledgerIndex)
        $ledgerPath = Join-Path (Split-Path -Parent $row[0].receipt.path) ([string]$ledger.filename)
        ([ordered]@{phase='completed';exit_code=$exitCode;completion_predicate_observed=$completed;peak_working_set_bytes=$peak} | ConvertTo-Json -Compress) | Set-Content -LiteralPath $ledgerPath -Encoding utf8NoBOM
        $ledger.sha256 = Get-HostHash $ledgerPath
        $ledger.exit_code = $exitCode
        $ledger.completion_predicate_observed = $completed
        $ledger.peak_working_set_bytes = $peak
        $ledger.duration_seconds = [double]0.01
      }
      # Keep each receipt beside its relative logs, ledgers, and snapshots so
      # the reader exercises the same immutable-relative-path checks as a run.
      $reference = Write-HostJson ([string]$row[0].receipt.path) $receipt
      $receipts += [pscustomobject][ordered]@{
        target=$target;engine=[pscustomobject][ordered]@{path=$pwsh;sha256=$engineHash;version=$engineVersion}
        receipt=[pscustomobject][ordered]@{path=$reference.path;sha256=$reference.sha256};harness_exit_code=0
      }
    }
    $fresh = @()
    foreach ($target in $script:MIR42SealNineTargetCandidates) {
      $candidateTarget = @($packages | Where-Object { [string]$_.target -ceq $target })[0]
      $targetIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $target -SourceVersion '4.2.3'
      $scenarios = if ($target -ceq 'f210') { @('package-zip-base','package-zip-space-age') } else { @('package-zip-base') }
      foreach ($scenario in $scenarios) {
        $prefix = $target + '-' + $scenario
        $logVersion = if ($target -in $script:MIR42SealHistoricalTargets) { '4.2.' + [int]([string]$candidateTarget.distribution_version -replace '^4[.]2[.]','') } else { [string]$candidateTarget.distribution_version }
        $log = Write-HostText (Join-Path $root ($prefix + '.log')) ("Loading mod more-infinite-research $logVersion (data.lua)`nFactorio initialised`nCreating new map")
        $stdout = Write-HostText (Join-Path $root ($prefix + '.stdout')) 'host-only stdout'
        $stderr = Write-HostText (Join-Path $root ($prefix + '.stderr')) ''
        if ($target -in $script:MIR42SealHistoricalTargets) {
          $save = Write-HostText (Join-Path $root ($prefix + '.zip')) 'host-only historical save'
          $summary = [pscustomobject][ordered]@{
            schema=1;kind='MIR42HistoricalFreshLoadV1';status='passed';target=$target;source_commit=$source.commit
            factorio_line=([string]$targetIdentity.target_id -replace '^factorio-','');engine=[pscustomobject][ordered]@{path=$pwsh;sha256=$engineHash}
            candidate=[pscustomobject][ordered]@{path=$candidateTarget.archive_path;sha256=$candidateTarget.archive_sha256;version=$candidateTarget.distribution_version}
            staged_candidate_sha256=$candidateTarget.archive_sha256;save=$save;log=$log
            assertions=@('exact-engine','exact-candidate','fresh-save-created','exact-mod-loaded','map-created','healthy-log');record_sha256=''
          }
          $summaryReference = Write-HostBootstrap (Join-Path $root ($prefix + '.json')) $summary
        } else {
          $summary = [pscustomobject][ordered]@{
            schema=2;status='passed';git_commit=$source.commit;validation_package_sha256=$candidateTarget.archive_sha256
            validation_package_content_sha256=$candidateTarget.content_sha256;factorio_binary_version=$engineProductVersion
            expected_scenarios=@($scenario);scenarios=@([pscustomobject][ordered]@{name=$scenario;status='passed';assertions_executed=1})
          }
          $summaryReference = Write-HostJson (Join-Path $root ($prefix + '.json')) $summary
        }
        $fresh += [pscustomobject][ordered]@{
          target=$target;scenario=$scenario;receipt=[pscustomobject][ordered]@{path=$summaryReference.path;sha256=$summaryReference.sha256}
          log=$log;stdout=$stdout;stderr=$stderr
        }
      }
    }
    $baseRecord = [pscustomobject][ordered]@{
      schema=1;kind='MIR42NineTargetMaintenanceIndividualEngineRunV1';status='nine-target-maintenance-individual-real-engine-probes-passed-private-unqualified'
      source=$source;candidate_manifest=[pscustomobject][ordered]@{path=$manifest.path;sha256=$manifest.sha256;record_sha256=$manifest.record.record_sha256}
      predecessor_authority=[pscustomobject][ordered]@{path='host-only-predecessor-authority.json';sha256=('1' * 64);record_sha256=('2' * 64)}
      public_v410_checksum_asset=[pscustomobject][ordered]@{release_id=1;asset_id=2;digest=('sha256:' + ('3' * 64));bytes=1;download_verified=$true}
      runner=(Write-HostText (Join-Path $root 'runner.ps1') 'Test-MIRUpgrade.ps1');harness=(Write-HostText (Join-Path $root 'harness.ps1') 'upgraded-save-second-reload-passed')
      historical_target_authorities=@($script:MIR42SealHistoricalTargets | ForEach-Object { [pscustomobject][ordered]@{target=$_;authority=[pscustomobject][ordered]@{host_only=$true;target=$_}} })
      published_maintenance_predecessor=$script:mir42IndividualReaderPublished;individual_upgrade_receipts=$receipts;fresh_loads=$fresh
      factorio_processes=46;release_qualification='not-performed';publication_authorized=$false;record_sha256=''
    }
    $basePath = Join-Path $root 'individual-input.json'
    $baseReference = Get-HostBootstrapReference (Write-HostBootstrap $basePath $baseRecord)
    $bound = Get-MIR42BoundEngineRun -Reference $baseReference -Candidate $script:mir42IndividualReaderCandidate -PublishedMaintenanceInputs $script:mir42IndividualReaderPublished
    Assert-MIR42NineSealTest -Condition ([string]$bound.input_kind -ceq 'individual-upgrade-receipts-and-fresh-loads' -and @($bound.record.targets).Count -eq 9 -and [int]$bound.record.factorio_processes -eq 46) -Code 'individual-positive-nine-receipt-ten-fresh-reader'
    $checks++;$script:mir42IndividualReaderChecks++

    # Factorio 0.13 has no Windows PE version metadata.  The fallback is
    # admissible only for its exact sealed binary and semantic version; a
    # populated receipt value, or either version/hash drift, remains a refusal.
    $f013Authority = Get-MIR42HistoricalTerminalAuthority -RepoRoot $RepoRoot -Target 'f013' -PredecessorIdentityOnly
    $f013Engine = $f013Authority.target_record.record.engine
    $f013FallbackAccepted = Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $true -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version)
    $f013MissingReceiptRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $false -ReceiptVersionTokenIsBlank $false -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    $f013WhitespaceReceiptRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $false -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    $f013ArrayReceiptRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $false -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    $f013ForgedReceiptRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $false -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    $f013ForgedFileVersionRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $true -FileVersion ([string]$f013Engine.version) -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    $f013ForgedPEFieldRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $true -FileVersion '' -ProductVersion ([string]$f013Engine.version) `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    $f013ForgedVersionRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $true -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion '0.13.999')
    $f013ForgedHashRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $true -FileVersion '' -ProductVersion '' `
      -EnginePath ([string]$f013Engine.path) -EngineSha256 ('0' * 64) -EngineVersion ([string]$f013Engine.version))
    $f013ForgedPathRejected = -not (Test-MIR42F013BlankPEVersionReceiptFallback -ReceiptVersionPresent $true -ReceiptVersionTokenIsBlank $true -FileVersion '' -ProductVersion '' `
      -EnginePath (Join-Path (Split-Path -Parent ([string]$f013Engine.path)) 'factorio-other.exe') -EngineSha256 ([string]$f013Engine.sha256) -EngineVersion ([string]$f013Engine.version))
    Assert-MIR42NineSealTest -Condition ($f013FallbackAccepted -and $f013MissingReceiptRejected -and $f013WhitespaceReceiptRejected -and $f013ArrayReceiptRejected -and $f013ForgedReceiptRejected -and $f013ForgedFileVersionRejected -and $f013ForgedPEFieldRejected -and $f013ForgedVersionRejected -and $f013ForgedHashRejected -and $f013ForgedPathRejected) -Code 'individual-f013-blank-pe-version-requires-sealed-engine'
    $checks++

    # The integrated reader case needs a real local file so it can verify the
    # exact immutable-file binding.  This deliberately plain-text .exe has no
    # Windows PE version resources; it is a host-only structural fixture, not
    # a substitute for the sealed 0.13 engine or native qualification.
    $f013ReaderEngineRoot = Join-Path $root 'f013-blank-pe-version-engine'
    New-Item -ItemType Directory -Force -Path $f013ReaderEngineRoot | Out-Null
    $f013ReaderEngineFile = Write-HostText (Join-Path $f013ReaderEngineRoot 'factorio.exe') 'host-only f013 blank-pe-version fixture'
    $f013ReaderEngineInfo = Get-Item -LiteralPath $f013ReaderEngineFile.path
    $f013ReaderFileVersion = [string]$f013ReaderEngineInfo.VersionInfo.FileVersion
    $f013ReaderProductVersion = [string]$f013ReaderEngineInfo.VersionInfo.ProductVersion
    Assert-MIR42NineSealTest -Condition ($f013ReaderFileVersion -ceq '' -and $f013ReaderProductVersion -ceq '') -Code 'individual-f013-host-fixture-has-blank-pe-version'
    $checks++
    $f013ReaderEngine = [pscustomobject][ordered]@{
      path = [string]$f013ReaderEngineFile.path
      sha256 = [string]$f013ReaderEngineFile.sha256
      version = [string]$f013Engine.version
    }
    # The production reader always loads the sealed historical authority.  The
    # host-only integrated case replaces only that read with equivalent sealed
    # fixture metadata, so hosted CI never requires D:\Programs\Factorio\0.13.
    $f013ReaderAuthority = [pscustomobject][ordered]@{
      target_record = [pscustomobject][ordered]@{
        record = [pscustomobject][ordered]@{
          engine = [pscustomobject][ordered]@{
            path = [string]$f013ReaderEngine.path
            sha256 = [string]$f013ReaderEngine.sha256
            version = [string]$f013ReaderEngine.version
          }
        }
      }
      terminal_seal = [pscustomobject][ordered]@{
        record = [pscustomobject][ordered]@{
          engine = [pscustomobject][ordered]@{
            binary_sha256 = [string]$f013ReaderEngine.sha256
            version = [string]$f013ReaderEngine.version
          }
        }
      }
    }
    function New-F013BlankPEVersionReaderRecord {
      $record = Copy-HostValue $baseRecord
      $f013EnginePath = Resolve-MIR42SealImmutableFile -Path ([string]$f013ReaderEngine.path) -Sha256 ([string]$f013ReaderEngine.sha256) -Code 'mir42-individual-f013-reader-engine'
      $receiptIndex = @($record.individual_upgrade_receipts | ForEach-Object { [string]$_.target }).IndexOf('f013')
      Assert-MIR42NineSealTest -Condition ($receiptIndex -ge 0) -Code 'individual-f013-reader-row'
      $receipt = Get-Content -LiteralPath $record.individual_upgrade_receipts[$receiptIndex].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
      $receipt.factorio_binary_sha256 = [string]$f013ReaderEngine.sha256
      $receipt.factorio_binary_version = $null
      Set-HostReceiptField $record $receiptIndex $receipt
      $record.individual_upgrade_receipts[$receiptIndex].engine = [ordered]@{path=$f013EnginePath;sha256=[string]$f013ReaderEngine.sha256;version=[string]$f013ReaderEngine.version}
      foreach ($freshIndex in 0..($record.fresh_loads.Count - 1)) {
        if ([string]$record.fresh_loads[$freshIndex].target -cne 'f013') { continue }
        $summary = Get-Content -LiteralPath $record.fresh_loads[$freshIndex].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $summary.engine = [ordered]@{path=$f013EnginePath;sha256=[string]$f013ReaderEngine.sha256}
        $reference = Write-HostBootstrap (Join-Path $root ('f013-fresh-reader-' + [guid]::NewGuid().ToString('N') + '.json')) $summary
        $record.fresh_loads[$freshIndex].receipt = [ordered]@{path=$reference.path;sha256=$reference.sha256}
      }
      return $record
    }
    $f013AuthorityReader = (Get-Item -LiteralPath Function:Get-MIR42HistoricalTerminalAuthority).ScriptBlock
    try {
      $script:mir42F013ReaderFixtureAuthority = $f013ReaderAuthority
      $script:mir42F013ReaderAuthorityReader = $f013AuthorityReader
      Set-Item -LiteralPath Function:Get-MIR42HistoricalTerminalAuthority -Value {
        param($RepoRoot,$Target,[switch]$PredecessorIdentityOnly)
        if ([string]$Target -ceq 'f013') { return $script:mir42F013ReaderFixtureAuthority }
        return & $script:mir42F013ReaderAuthorityReader -RepoRoot $RepoRoot -Target $Target -PredecessorIdentityOnly:$PredecessorIdentityOnly
      }
      $f013NullVersionRecord = New-F013BlankPEVersionReaderRecord
      $f013NullVersionReference = Get-HostBootstrapReference (Write-HostBootstrap (Join-Path $root 'f013-null-pe-version.json') $f013NullVersionRecord)
      $f013NullVersionBound = Get-MIR42BoundEngineRun -Reference $f013NullVersionReference -Candidate $script:mir42IndividualReaderCandidate -PublishedMaintenanceInputs $script:mir42IndividualReaderPublished
      Assert-MIR42NineSealTest -Condition ((@($f013NullVersionBound.record.targets | Where-Object target -CEQ 'f013').engine_execution.executable_sha256) -ceq [string]$f013ReaderEngine.sha256) -Code 'individual-f013-null-pe-version-reader'
      $checks++
      $f013MissingVersionRecord = New-F013BlankPEVersionReaderRecord
      $f013MissingVersionIndex = @($f013MissingVersionRecord.individual_upgrade_receipts | ForEach-Object { [string]$_.target }).IndexOf('f013')
      $f013MissingVersionReceipt = Get-Content -LiteralPath $f013MissingVersionRecord.individual_upgrade_receipts[$f013MissingVersionIndex].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
      $null = $f013MissingVersionReceipt.Remove('factorio_binary_version');Set-HostReceiptField $f013MissingVersionRecord $f013MissingVersionIndex $f013MissingVersionReceipt
      Assert-HostReaderRefusal 'f013-missing-pe-version' $f013MissingVersionRecord '[mir42-individual-engine-run-engine-version]'
      $f013WhitespaceVersionRecord = New-F013BlankPEVersionReaderRecord
      $f013WhitespaceVersionIndex = @($f013WhitespaceVersionRecord.individual_upgrade_receipts | ForEach-Object { [string]$_.target }).IndexOf('f013')
      $f013WhitespaceVersionReceipt = Get-Content -LiteralPath $f013WhitespaceVersionRecord.individual_upgrade_receipts[$f013WhitespaceVersionIndex].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
      $f013WhitespaceVersionReceipt.factorio_binary_version = ' ';Set-HostReceiptField $f013WhitespaceVersionRecord $f013WhitespaceVersionIndex $f013WhitespaceVersionReceipt
      Assert-HostReaderRefusal 'f013-whitespace-pe-version' $f013WhitespaceVersionRecord '[mir42-individual-engine-run-engine-version]'
      $f013ArrayVersionRecord = New-F013BlankPEVersionReaderRecord
      $f013ArrayVersionIndex = @($f013ArrayVersionRecord.individual_upgrade_receipts | ForEach-Object { [string]$_.target }).IndexOf('f013')
      $f013ArrayVersionReceipt = Get-Content -LiteralPath $f013ArrayVersionRecord.individual_upgrade_receipts[$f013ArrayVersionIndex].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
      $f013ArrayVersionReceipt.factorio_binary_version = @();Set-HostReceiptField $f013ArrayVersionRecord $f013ArrayVersionIndex $f013ArrayVersionReceipt
      Assert-HostReaderRefusal 'f013-array-pe-version' $f013ArrayVersionRecord '[mir42-individual-engine-run-engine-version]'
      foreach ($arrayCase in @(
        [pscustomobject]@{name='null-array';value=@($null)},
        [pscustomobject]@{name='empty-string-array';value=@('')}
      )) {
        $arrayRecord = New-F013BlankPEVersionReaderRecord
        $arrayIndex = @($arrayRecord.individual_upgrade_receipts | ForEach-Object { [string]$_.target }).IndexOf('f013')
        $arrayReceipt = Get-Content -LiteralPath $arrayRecord.individual_upgrade_receipts[$arrayIndex].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $arrayReceipt.factorio_binary_version = $arrayCase.value;Set-HostReceiptField $arrayRecord $arrayIndex $arrayReceipt
        Assert-HostReaderRefusal ('f013-' + $arrayCase.name + '-pe-version') $arrayRecord '[mir42-individual-engine-run-engine-version]'
      }
    } finally {
      Set-Item -LiteralPath Function:Get-MIR42HistoricalTerminalAuthority -Value $f013AuthorityReader
      Remove-Variable -Name mir42F013ReaderFixtureAuthority -Scope Script -ErrorAction SilentlyContinue
      Remove-Variable -Name mir42F013ReaderAuthorityReader -Scope Script -ErrorAction SilentlyContinue
    }

    # The normal reader still refuses an empty version on a modern executable;
    # the F013 target guard cannot relax its PE-version contract.
    $modernBlankVersion = Copy-HostValue $baseRecord
    $modernBlankReceipt = Get-Content -LiteralPath $modernBlankVersion.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $modernBlankReceipt.factorio_binary_version = ''
    Set-HostReceiptField $modernBlankVersion 0 $modernBlankReceipt
    Assert-HostReaderRefusal 'modern-blank-pe-version' $modernBlankVersion '[mir42-individual-engine-run-engine-version]'

    $wrongRunner = Copy-HostValue $baseRecord;$wrongRunner.runner = Write-HostText (Join-Path $root 'runner-no-upgrade-invocation.ps1') 'upgraded-save-second-reload-passed'
    Assert-HostReaderRefusal 'runner-without-upgrade-invocation' $wrongRunner '[mir42-individual-engine-run-runner-content]'
    $wrongHarness = Copy-HostValue $baseRecord;$wrongHarness.harness = Write-HostText (Join-Path $root 'harness-without-reload-marker.ps1') 'Test-MIRUpgrade.ps1'
    Assert-HostReaderRefusal 'harness-without-reload-marker' $wrongHarness '[mir42-individual-engine-run-harness-content]'

    $missing = Copy-HostValue $baseRecord;$missing.individual_upgrade_receipts = @($missing.individual_upgrade_receipts | Select-Object -Skip 1)
    Assert-HostReaderRefusal 'missing-receipt' $missing '[mir42-individual-engine-run-receipt-target-set]'
    $duplicate = Copy-HostValue $baseRecord;$duplicate.individual_upgrade_receipts[1] = $duplicate.individual_upgrade_receipts[0]
    Assert-HostReaderRefusal 'duplicate-receipt' $duplicate '[mir42-individual-engine-run-receipt-target-set]'
    $wrongTarget = Copy-HostValue $baseRecord;$wrongTarget.individual_upgrade_receipts[0].target = 'f200'
    Assert-HostReaderRefusal 'mixed-target' $wrongTarget '[mir42-individual-engine-run-receipt-target-set]'
    $wrongCount = Copy-HostValue $baseRecord;$wrongCount.factorio_processes = 45
    Assert-HostReaderRefusal 'process-count' $wrongCount '[mir42-individual-engine-run-process-count]'
    $wrongFresh = Copy-HostValue $baseRecord;$wrongFresh.fresh_loads = @($wrongFresh.fresh_loads | Select-Object -Skip 1)
    Assert-HostReaderRefusal 'missing-fresh' $wrongFresh '[mir42-individual-engine-run-fresh-set]'
    $wrongFreshHash = Copy-HostValue $baseRecord;$wrongFreshHash.fresh_loads[0].log.sha256 = ('0' * 64)
    Assert-HostReaderRefusal 'fresh-log-hash' $wrongFreshHash '[mir42-individual-engine-run-fresh-log-hash]'
    $wrongEngine = Copy-HostValue $baseRecord;$wrongEngine.individual_upgrade_receipts[0].engine.sha256 = ('0' * 64)
    Assert-HostReaderRefusal 'engine-hash' $wrongEngine '[mir42-individual-engine-run-receipt-binding]'
    $wrongEngineVersion = Copy-HostValue $baseRecord;$engineVersionReceipt = Get-Content -LiteralPath $wrongEngineVersion.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $engineVersionReceipt.factorio_binary_version = if ($engineProductVersion -cne $engineVersion) { $engineProductVersion } else { '0.0.0.0' };Set-HostReceiptField $wrongEngineVersion 0 $engineVersionReceipt
    Assert-HostReaderRefusal 'engine-version' $wrongEngineVersion '[mir42-individual-engine-run-engine-version]'
    $wrongExit = Copy-HostValue $baseRecord;$wrongExit.individual_upgrade_receipts[0].harness_exit_code = 1
    Assert-HostReaderRefusal 'harness-exit' $wrongExit '[mir42-individual-engine-run-harness-exit]'

    $sourceDrift = Copy-HostValue $baseRecord;$sourceReceipt = Get-Content -LiteralPath $sourceDrift.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $sourceReceipt.git_commit = ('9' * 40);Set-HostReceiptField $sourceDrift 0 $sourceReceipt
    Assert-HostReaderRefusal 'receipt-source' $sourceDrift '[mir42-individual-engine-run-receipt-binding]'
    $packageDrift = Copy-HostValue $baseRecord;$packageReceipt = Get-Content -LiteralPath $packageDrift.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $packageReceipt.to.sha256 = ('0' * 64);Set-HostReceiptField $packageDrift 0 $packageReceipt
    Assert-HostReaderRefusal 'receipt-package' $packageDrift '[mir423-upgrade-native-binding]'
    $onlyOneReload = Copy-HostValue $baseRecord;$reloadReceipt = Get-Content -LiteralPath $onlyOneReload.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $reloadReceipt.assertions = @($reloadReceipt.assertions | Where-Object { $_ -cne 'upgraded-save-second-reload-passed' });Set-HostReceiptField $onlyOneReload 0 $reloadReceipt
    Assert-HostReaderRefusal 'one-reload' $onlyOneReload '[mir423-upgrade-phase-skipped]'
    $missingState = Copy-HostValue $baseRecord;$stateReceipt = Get-Content -LiteralPath $missingState.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $null = $stateReceipt.Remove('full_state_evaluator_snapshots');Set-HostReceiptField $missingState 0 $stateReceipt
    Assert-HostReaderRefusal 'missing-full-state' $missingState '[mir423-upgrade-receipt-snapshot-required]'
    $ledgerMetadata = Copy-HostValue $baseRecord;$ledgerMetadataReceipt = Get-Content -LiteralPath $ledgerMetadata.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $ledgerMetadataReceipt.resource_ledgers[0].peak_working_set_bytes = [int64]($ledgerMetadataReceipt.resource_ledgers[0].peak_working_set_bytes + 1);Set-HostReceiptField $ledgerMetadata 0 $ledgerMetadataReceipt
    Assert-HostReaderRefusal 'ledger-metadata' $ledgerMetadata '[mir42-individual-engine-run-resource-ledger-terminal]'
    $wrongNativeArchive = Copy-HostValue $baseRecord;$nativeReceipt = Get-Content -LiteralPath $wrongNativeArchive.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $nativeReceipt.library_activation.selected[0].path = [string]$packages[0].archive_path;Set-HostReceiptField $wrongNativeArchive 0 $nativeReceipt
    Assert-HostReaderRefusal 'native-authority-path' $wrongNativeArchive '[mir42-individual-engine-run-native-candidate-authority-path]'
    $wrongNativeIdentity = Copy-HostValue $baseRecord;$identityReceipt = Get-Content -LiteralPath $wrongNativeIdentity.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $identityReceipt.library_activation.selected[0].identity = 'host-only-wrong-native-identity';Set-HostReceiptField $wrongNativeIdentity 0 $identityReceipt
    Assert-HostReaderRefusal 'native-identity' $wrongNativeIdentity '[mir42-individual-engine-run-native-candidate-identity]'
    $interruptedLedger = Copy-HostValue $baseRecord;$interruptReceipt = Get-Content -LiteralPath $interruptedLedger.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $interruptLedgerPath = Join-Path (Split-Path -Parent $interruptedLedger.individual_upgrade_receipts[0].receipt.path) ([string]$interruptReceipt.resource_ledgers[0].filename)
    $interruptOriginalBytes = [IO.File]::ReadAllBytes($interruptLedgerPath)
    try {
      ([ordered]@{phase='interrupted';exit_code=0;completion_predicate_observed=$true;peak_working_set_bytes=[int64]$interruptReceipt.resource_ledgers[0].peak_working_set_bytes} | ConvertTo-Json -Compress) | Set-Content -LiteralPath $interruptLedgerPath -Encoding utf8NoBOM
      $interruptReceipt.resource_ledgers[0].sha256 = Get-HostHash $interruptLedgerPath;Set-HostReceiptField $interruptedLedger 0 $interruptReceipt
      Assert-HostReaderRefusal 'interrupted-ledger' $interruptedLedger '[mir42-individual-engine-run-resource-ledger-interrupted]'
    } finally { [IO.File]::WriteAllBytes($interruptLedgerPath,$interruptOriginalBytes) }
    $failedLedger = Copy-HostValue $baseRecord;$ledgerReceipt = Get-Content -LiteralPath $failedLedger.individual_upgrade_receipts[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $ledgerRoot = Join-Path $root 'failed-ledger';New-Item -ItemType Directory -Force -Path $ledgerRoot | Out-Null
    $originalReceiptRoot = Split-Path -Parent $failedLedger.individual_upgrade_receipts[0].receipt.path
    foreach ($name in @($ledgerReceipt.create_log,$ledgerReceipt.load_log,$ledgerReceipt.reload_log,$ledgerReceipt.second_reload_log) + @($ledgerReceipt.resource_ledgers | ForEach-Object { $_.filename })) { Copy-Item -LiteralPath (Join-Path $originalReceiptRoot $name) -Destination (Join-Path $ledgerRoot $name) }
    $ledgerReceipt.resource_ledgers[0].exit_code = 1;$ledgerReceipt.resource_ledgers[0].completion_predicate_observed = $false
    $ledger = Join-Path $ledgerRoot $ledgerReceipt.resource_ledgers[0].filename;$ledgerReceipt.resource_ledgers[0].sha256 = Get-HostHash $ledger
    # The receipt must live beside the copied relative logs and ledgers.
    $failedReceiptReference = Write-HostJson (Join-Path $ledgerRoot 'receipt.json') $ledgerReceipt
    $failedLedger.individual_upgrade_receipts[0].receipt = [ordered]@{path=$failedReceiptReference.path;sha256=$failedReceiptReference.sha256}
    Assert-HostReaderRefusal 'failed-ledger' $failedLedger '[mir423-upgrade-process-failed]'
    $prior = @($upgradeEvidence.rows | Where-Object { [string]$_.target -ceq 'f210' -and [string]$_.predecessor_source_version -ceq '4.2.1' })[0]
    $priorReceipt = Get-Content -LiteralPath $prior.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $priorReceipt.git_commit = $source.commit;$priorReceipt.factorio_binary_sha256 = $engineHash;$priorReceipt.factorio_binary_version = $engineVersion;$priorReceipt.published_maintenance_predecessor = $publishedTargets[0]
    $priorReference = Write-HostJson (Join-Path $root 'prior-421.json') $priorReceipt
    $priorPatch = Copy-HostValue $baseRecord;$priorPatch.individual_upgrade_receipts[0].receipt = [ordered]@{path=$priorReference.path;sha256=$priorReference.sha256}
    Assert-HostReaderRefusal 'prior-421-receipt' $priorPatch '[mir423-upgrade-native-binding]'
    $checks += $script:mir42IndividualReaderChecks
  } finally {
    Set-Item -LiteralPath Function:script:Get-MIR42IndividualEngineEvidenceBindingContract -Value $individualContractReader
    Remove-Variable -Name mir42IndividualReaderCandidate -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name mir42IndividualReaderPublished -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name mir42IndividualReaderChecks -Scope Script -ErrorAction SilentlyContinue
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build'))
    if (-not ([IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-individual-reader-fixture-containment]' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  }
  Write-Output ('MIR42-INDIVIDUAL-NATIVE-INPUT-READER-PASSED assertions=' + $checks + ' native-records=0 engines=0')
}

function Test-MIR42HistoricalReceiptCustodyProjection {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $root = Join-Path $RepoRoot ('build/test-results/mir43-historical-receipt-custody-' + [guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory((Join-Path $root 'materializations')) | Out-Null
  $checks = 0
  function New-MIR42HistoricalReceiptControlRow([string]$Path) {
    $identity = Get-MIR4RawFileIdentity -Path $Path
    $record = Read-MIR42SealRecord -Path $Path -Code 'mir42-historical-receipt-control'
    return [pscustomobject][ordered]@{
      historical_materializer_manifest_sha256 = [string]$record.record.record_sha256
      historical_materializer_manifest = [pscustomobject][ordered]@{
        path = 'materializations/f017.json'
        bytes = [int64]$identity.bytes
        sha256 = [string]$identity.sha256
        record_sha256 = [string]$record.record.record_sha256
      }
    }
  }
  function Assert-MIR42HistoricalReceiptControlRejected($Action,[string]$Expected,[string]$Code) {
    $failure = ''
    try { $null = & $Action } catch { $failure = $_.Exception.Message }
    Assert-MIR42NineSealTest -Condition ($failure.StartsWith($Expected,[StringComparison]::Ordinal)) -Code $Code
  }
  try {
    $receiptPath = Join-Path $root 'materializations/f017.json'
    $receipt = [pscustomobject][ordered]@{schema=1;kind='MIR43HistoricalReceiptCustodyControlV1';target='f017';record_sha256=''}
    Write-MIR4BootstrapRecord -Record $receipt -Path $receiptPath | Out-Null
    $row = New-MIR42HistoricalReceiptControlRow -Path $receiptPath
    $verified = Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target f017 -Row $row
    Assert-MIR42NineSealTest -Condition (
      [string]$verified.path -ceq (Resolve-Path -LiteralPath $receiptPath).Path -and
      [string]$verified.descriptor.path -ceq 'materializations/f017.json' -and
      [int64]$verified.descriptor.bytes -eq [int64]$row.historical_materializer_manifest.bytes -and
      [string]$verified.descriptor.sha256 -ceq [string]$row.historical_materializer_manifest.sha256 -and
      [string]$verified.descriptor.record_sha256 -ceq [string]$row.historical_materializer_manifest_sha256
    ) -Code 'historical-receipt-custody-accepted'
    $checks++

    $wrongPath = $row | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $wrongPath.historical_materializer_manifest.path = 'materializations/f016.json'
    Assert-MIR42HistoricalReceiptControlRejected { Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target f017 -Row $wrongPath } '[mir42-seal-candidate-historical-receipt-path]' 'historical-receipt-custody-path-rejected'
    $checks++
    $wrongRaw = $row | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $wrongRaw.historical_materializer_manifest.sha256 = '0' * 64
    Assert-MIR42HistoricalReceiptControlRejected { Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target f017 -Row $wrongRaw } '[mir42-seal-candidate-historical-receipt-sha256]' 'historical-receipt-custody-raw-hash-rejected'
    $checks++
    $wrongPin = $row | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $wrongPin.historical_materializer_manifest_sha256 = '0' * 64
    Assert-MIR42HistoricalReceiptControlRejected { Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target f017 -Row $wrongPin } '[mir42-seal-candidate-historical-receipt-legacy-pin]' 'historical-receipt-custody-legacy-pin-rejected'
    $checks++
    $wrongShape = $row | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $wrongShape.historical_materializer_manifest | Add-Member -NotePropertyName extra -NotePropertyValue 'forged'
    Assert-MIR42HistoricalReceiptControlRejected { Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target f017 -Row $wrongShape } '[mir42-seal-candidate-historical-receipt-shape]' 'historical-receipt-custody-shape-rejected'
    $checks++

    # Bind a raw receipt even when its descriptor is self-consistent: the
    # reader must still reject a malformed logical record rather than treating
    # raw custody as a substitute for the recorded construction proof.
    [IO.File]::WriteAllText($receiptPath, '{"schema":1,"record_sha256":"' + ('0' * 64) + '"}', [Text.UTF8Encoding]::new($false))
    $invalidIdentity = Get-MIR4RawFileIdentity -Path $receiptPath
    $invalidRow = [pscustomobject][ordered]@{
      historical_materializer_manifest_sha256 = ('0' * 64)
      historical_materializer_manifest = [pscustomobject][ordered]@{path='materializations/f017.json';bytes=[int64]$invalidIdentity.bytes;sha256=[string]$invalidIdentity.sha256;record_sha256=('0' * 64)}
    }
    Assert-MIR42HistoricalReceiptControlRejected { Get-MIR42HistoricalMaterializerReceiptCustody -Root $root -Target f017 -Row $invalidRow } '[mir42-seal-candidate-historical-receipt-record-hash]' 'historical-receipt-custody-self-hash-rejected'
    $checks++
  } finally {
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/test-results')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/')
    if (-not (($resolvedRoot + [IO.Path]::DirectorySeparatorChar).StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)) -or
        [IO.Path]::GetFileName($resolvedRoot) -notlike 'mir43-historical-receipt-custody-*') {
      throw '[mir43-historical-receipt-custody-fixture-containment]'
    }
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
  }
  Write-Output ('MIR43-HISTORICAL-RECEIPT-CUSTODY-PROJECTION-PASSED assertions=' + $checks + ' native-records=0')
}

function Test-MIR430ClassicSnapshotProjection {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $ErrorActionPreference = 'Stop'
  . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
  $requiredStressProfile = 'fixtures/run-profiles/mir430-startup-omni-bob-angel-46-f200.json'
  Assert-MIR42NineSealTest -Condition ($script:MIR42SealVerifierDependencyPaths -contains $requiredStressProfile) -Code 'mir430-stress-profile-dependency-is-current'
  Assert-MIR42NineSealTest -Condition (-not ($script:MIR42SealVerifierDependencyPaths -contains 'fixtures/run-profiles/mir430-startup-omni-bob-angel-46.json')) -Code 'mir430-stress-profile-dependency-does-not-name-absent-fixture'
  Assert-MIR42NineSealTest -Condition (Test-Path -LiteralPath (Join-Path $RepoRoot $requiredStressProfile) -PathType Leaf) -Code 'mir430-stress-profile-dependency-exists'
  . (Join-Path $RepoRoot 'tests/support/MIR421ReleaseAssetControls.ps1')
  $root = Join-Path $RepoRoot ('build/test-results/mir430-classic-seal-projection-' + [guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($root) | Out-Null
  $checks = 0
  $contractReader = (Get-Command Get-MIR42IndividualEngineEvidenceBindingContract -CommandType Function -ErrorAction Stop).ScriptBlock
  $nativeSelectionReader = (Get-Command Assert-MIR42IndividualNativeCandidateSelection -CommandType Function -ErrorAction Stop).ScriptBlock
  $ledgerReader = (Get-Command Assert-MIR42IndividualResourceLedgers -CommandType Function -ErrorAction Stop).ScriptBlock
  function Write-ClassicSealJson([string]$Path,$Value) {
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    return [pscustomobject]@{path=$Path;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
  }
  function Copy-ClassicSealValue($Value) { $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100 }
  function New-ClassicSealReceiptRow($Row,[string]$Commit,[string]$EngineHash,[string]$EngineVersion,$Published) {
    $record = Get-Content -LiteralPath $Row.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $record.git_commit = $Commit
    $record.factorio_binary_sha256 = $EngineHash
    $record.factorio_binary_version = $EngineVersion
    $record.published_maintenance_predecessor = [ordered]@{
      release_id=[int64]$Published.release_id;source_tag=[string]$Published.source_tag;source=$Published.source
      tag_object=[string]$Published.tag_object;remote_tag_readback=[bool]$Published.remote_tag_readback;manifest=$Published.manifest
      signed=[bool]$Published.signed;targets=@($Published.targets);native_qualification=[string]$Published.native_qualification
      release_qualification=[string]$Published.release_qualification;local_custody_scope='selected-native-archive'
    }
    $reference = Write-ClassicSealJson (Join-Path (Split-Path -Parent $Row.receipt.path) ('seal-' + [guid]::NewGuid().ToString('N') + '.json')) $record
    return [pscustomobject]@{row=[pscustomobject]@{target=$Row.target;predecessor_source_version=$Row.predecessor_source_version;receipt=$reference;snapshots=$Row.snapshots};receipt=$record}
  }
  try {
    Set-Item -LiteralPath Function:script:Get-MIR42IndividualEngineEvidenceBindingContract -Value {
      param($Candidate,[switch]$PublishedMaintenance)
      if (-not $PublishedMaintenance) { throw '[mir42-individual-engine-run-maintenance-required]' }
      return [pscustomobject]@{maintenance_source_version='4.3.0'}
    }
    # The native archive and process-ledger checks have dedicated controls. This
    # fixture isolates the seal's field projection while retaining the actual
    # policy reader, immutable snapshot references, and phase-log checks.
    Set-Item -LiteralPath Function:script:Assert-MIR42IndividualNativeCandidateSelection -Value {
      param($Receipt,$ReceiptPath,$CandidateTarget)
      return [pscustomobject]@{path='host-only';sha256=[string]$CandidateTarget.archive_sha256;bytes=1;identity='host-only'}
    }
    Set-Item -LiteralPath Function:script:Assert-MIR42IndividualResourceLedgers -Value { param($Receipt,$ReceiptPath) }
    $packages = @(
      foreach ($target in $script:MIR42SealNineTargetCandidates) {
        [pscustomobject]@{target=$target;distribution_version=('4.3.' + $target.Substring(1) + '00');sha256=('A' * 64);archive_sha256=('A' * 64)}
      }
    )
    $control = Invoke-MIR430ReleaseUpgradeControls -Root (Join-Path $root 'controls') -PackageAssets $packages
    Assert-MIR42NineSealTest -Condition ([int]$control.checks -gt 0 -and [int]$control.native_runs -eq 0) -Code 'classic-seal-control-fixture-host-only'
    $enginePath = (Get-Command pwsh -ErrorAction Stop).Source
    $engineHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash
    $engineVersion = [string](Get-Item -LiteralPath $enginePath).VersionInfo.FileVersion
    $commit = 'A' * 40
    $candidate = [pscustomobject]@{source=[pscustomobject]@{commit=$commit}}

    foreach ($case in @(
      @{target='f210';policy='full';snapshot_field='full_state_evaluator_snapshots'},
      @{target='f017';policy='full';snapshot_field='full_state_evaluator_snapshots'}
    )) {
      $original = @((Get-Content -LiteralPath $control.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100).rows | Where-Object {
        [string]$_.target -ceq $case.target -and [string]$_.predecessor_source_version -ceq '4.2.2'
      })
      Assert-MIR42NineSealTest -Condition ($original.Count -eq 1) -Code ('classic-seal-row-' + $case.target)
      $proof = Get-Content -LiteralPath $original[0].receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
      $publishedInput = [pscustomobject]@{target=$case.target;path='host-only-predecessor.zip';sha256=[string]$proof.from.sha256;version=[string]$proof.from.version}
      $published = [pscustomobject]@{
        release_id=1;source_tag=[string]$proof.published_maintenance_predecessor.source_tag;source=[pscustomobject]@{commit=('D' * 40);tree=('E' * 40)}
        tag_object=('9' * 40);remote_tag_readback=$true;manifest=[pscustomobject]@{path='host-only-manifest.json';sha256=[string]$proof.published_maintenance_predecessor.manifest.sha256;bytes=1}
        signed=$false;targets=@($publishedInput);native_qualification='not-performed';release_qualification='not-performed'
      }
      $sealed = New-ClassicSealReceiptRow -Row $original[0] -Commit $commit -EngineHash $engineHash -EngineVersion $engineVersion -Published $published
      $candidateTarget = @($packages | Where-Object { [string]$_.target -ceq $case.target })[0]
      $result = Assert-MIR42IndividualUpgradeReceipt -ReceiptReference $sealed.row.receipt -CandidateTarget $candidateTarget -PublishedInput $publishedInput -PublishedMaintenanceInputs $published -Engine ([pscustomobject]@{path=$enginePath;sha256=$engineHash;version=$engineVersion}) -HarnessExitCode 0 -Candidate $candidate
      Assert-MIR42NineSealTest -Condition ($result.execution.predecessor_upgrade -and $result.execution.reload_count -eq 2) -Code ('classic-seal-projection-' + $case.policy)
      $checks++
    }

    $classicRow = @((Get-Content -LiteralPath $control.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100).rows | Where-Object {
      [string]$_.target -ceq 'f210' -and [string]$_.predecessor_source_version -ceq '4.2.2'
    })[0]
    $classicProof = Get-Content -LiteralPath $classicRow.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $classicInput = [pscustomobject]@{target='f210';path='host-only-predecessor.zip';sha256=[string]$classicProof.from.sha256;version=[string]$classicProof.from.version}
    $classicPublished = [pscustomobject]@{release_id=1;source_tag=[string]$classicProof.published_maintenance_predecessor.source_tag;source=[pscustomobject]@{commit=('D'*40);tree=('E'*40)};tag_object=('9'*40);remote_tag_readback=$true;manifest=[pscustomobject]@{path='host-only-manifest.json';sha256=[string]$classicProof.published_maintenance_predecessor.manifest.sha256;bytes=1};signed=$false;targets=@($classicInput);native_qualification='not-performed';release_qualification='not-performed'}
    $forged = New-ClassicSealReceiptRow -Row $classicRow -Commit $commit -EngineHash $engineHash -EngineVersion $engineVersion -Published $classicPublished
    $forgedRecord = Copy-ClassicSealValue $forged.receipt
    $forgedRecord.upgrade_policy = @{kind='MIR430ClassicReducedUpgradePolicyV1'}
    $forgedReference = Write-ClassicSealJson (Join-Path (Split-Path -Parent $forged.row.receipt.path) 'forged-policy.json') $forgedRecord
    $forged.row.receipt = $forgedReference
    $failure = ''
    try {
      $null = Assert-MIR42IndividualUpgradeReceipt -ReceiptReference $forged.row.receipt -CandidateTarget (@($packages | Where-Object { $_.target -ceq 'f210' })[0]) -PublishedInput $classicInput -PublishedMaintenanceInputs $classicPublished -Engine ([pscustomobject]@{path=$enginePath;sha256=$engineHash;version=$engineVersion}) -HarnessExitCode 0 -Candidate $candidate
    } catch { $failure = $_.Exception.Message }
    Assert-MIR42NineSealTest -Condition ($failure.StartsWith('[mir430-upgrade-classic-reduced-policy-not-release-preservation]',[StringComparison]::Ordinal)) -Code 'classic-seal-forged-policy-cannot-enter-release-preservation'
    $checks++

    # A forged historical receipt must be rejected before its policy can select
    # the Classic snapshot projection.  This exercises the individual seal
    # boundary independently of the matrix reader's matching guard.
    $historicalRow = @((Get-Content -LiteralPath $control.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100).rows | Where-Object {
      [string]$_.target -ceq 'f017' -and [string]$_.predecessor_source_version -ceq '4.2.2'
    })[0]
    $historicalProof = Get-Content -LiteralPath $historicalRow.receipt.path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    $historicalInput = [pscustomobject]@{target='f017';path='host-only-predecessor.zip';sha256=[string]$historicalProof.from.sha256;version=[string]$historicalProof.from.version}
    $historicalPublished = [pscustomobject]@{release_id=1;source_tag=[string]$historicalProof.published_maintenance_predecessor.source_tag;source=[pscustomobject]@{commit=('D'*40);tree=('E'*40)};tag_object=('9'*40);remote_tag_readback=$true;manifest=[pscustomobject]@{path='host-only-manifest.json';sha256=[string]$historicalProof.published_maintenance_predecessor.manifest.sha256;bytes=1};signed=$false;targets=@($historicalInput);native_qualification='not-performed';release_qualification='not-performed'}
    $historicalForged = New-ClassicSealReceiptRow -Row $historicalRow -Commit $commit -EngineHash $engineHash -EngineVersion $engineVersion -Published $historicalPublished
    $historicalRecord = Copy-ClassicSealValue $historicalForged.receipt
    $historicalRecord.upgrade_policy = @{kind='MIR430ClassicReducedUpgradePolicyV1'}
    $historicalForged.row.receipt = Write-ClassicSealJson (Join-Path (Split-Path -Parent $historicalForged.row.receipt.path) 'forged-historical-classic.json') $historicalRecord
    $failure = ''
    try {
      $null = Assert-MIR42IndividualUpgradeReceipt -ReceiptReference $historicalForged.row.receipt -CandidateTarget (@($packages | Where-Object { $_.target -ceq 'f017' })[0]) -PublishedInput $historicalInput -PublishedMaintenanceInputs $historicalPublished -Engine ([pscustomobject]@{path=$enginePath;sha256=$engineHash;version=$engineVersion}) -HarnessExitCode 0 -Candidate $candidate
    } catch { $failure = $_.Exception.Message }
    Assert-MIR42NineSealTest -Condition ($failure.StartsWith('[mir430-upgrade-classic-reduced-policy-not-release-preservation]',[StringComparison]::Ordinal)) -Code 'classic-seal-historical-policy-rejected-before-projection'
    $checks++
  } finally {
    Set-Item -LiteralPath Function:script:Get-MIR42IndividualEngineEvidenceBindingContract -Value $contractReader
    Set-Item -LiteralPath Function:script:Assert-MIR42IndividualNativeCandidateSelection -Value $nativeSelectionReader
    Set-Item -LiteralPath Function:script:Assert-MIR42IndividualResourceLedgers -Value $ledgerReader
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/')
    if (-not (($resolvedRoot + [IO.Path]::DirectorySeparatorChar).StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)) -or
        [IO.Path]::GetFileName($resolvedRoot) -notlike 'mir430-classic-seal-projection-*') {
      throw '[mir430-classic-seal-fixture-containment]'
    }
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
  }
  Write-Output ('MIR430-CLASSIC-SEAL-SNAPSHOT-PROJECTION-PASSED assertions=' + $checks + ' native-records=0')
}

if (-not $OnlyClassicSealSnapshotProjection) {
  Test-MIR42IndividualNativeInputReader -RepoRoot $repo
}
Test-MIR42HistoricalReceiptCustodyProjection -RepoRoot $repo
Test-MIR430ClassicSnapshotProjection -RepoRoot $repo

if ($OnlyClassicSealSnapshotProjection) {
  Write-Output 'MIR430-CLASSIC-TECHNICAL-SEAL-PROJECTION-PASSED engines=0'
} else {
  Write-Output 'MIR42-NINE-TARGET-TECHNICAL-SEAL-PASSED scopes=4,9 historical=5 engines=0'
}
