# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$evidence = Join-Path $repo 'tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1'
$independent = Join-Path $repo 'tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1'
foreach ($path in @($evidence,$independent)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir42-nine-generator-stage-missing] $path" } }
. $evidence
. $independent

function Assert-MIR42NineGeneratorTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir42-nine-generator-test-$Code]" }
}

function Get-MIR42NineGeneratorHistoricalFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target)

  $identity = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target $Target
  $recordPath = Join-Path $RepoRoot ([string]$identity.target_record_path)
  $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or
      (Get-MIR4Sha256File -Path $recordPath) -cne [string]$identity.target_record_file_sha256 -or
      [string]$record.record_sha256 -cne [string]$identity.target_record_record_sha256 -or
      [string]$record.target -cne $Target -or [string]$record.maturity -cne 'private-historical-playtest' -or
      [string]$record.base_materializer_target -cne 'f100' -or [bool]$record.public_output_authorized -or [bool]$record.publication_authorized) {
    throw "[mir42-nine-generator-fixture-target-record] $Target"
  }
  $sealRelative = '.mir/releases/terminal/seals/' + [string]$record.predecessor.version + '.json'
  $sealPath = Join-Path $RepoRoot $sealRelative
  $seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $seal) -or [int]$seal.schema -ne 1 -or
      [string]$seal.kind -cne 'Mir3TerminalTargetSealV1' -or [string]$seal.status -cne 'sealed' -or
      [string]$seal.release -cne [string]$record.predecessor.version -or [string]$seal.target -cne [string]$record.factorio_line -or
      [string]$seal.archive_sha256 -cne [string]$record.predecessor.sha256 -or
      [string]$seal.engine.version -cne [string]$record.engine.version -or [string]$seal.engine.binary_sha256 -cne [string]$record.engine.sha256) {
    throw "[mir42-nine-generator-fixture-terminal-seal] $Target"
  }
  return [pscustomobject][ordered]@{
    fixture_scope='committed-target-record-and-terminal-seal-only';identity=$identity;record=$record;record_path=$recordPath;seal=$seal;seal_path=$sealPath
  }
}

function Assert-MIR42NineGeneratorHistoricalArchiveRequired {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target)

  $fixtureRoot = Join-Path $RepoRoot ('build/test-results/mir42-nine-generator-missing-archive-' + [guid]::NewGuid().ToString('N'))
  try {
    $fixture = Get-MIR42NineGeneratorHistoricalFixture -RepoRoot $RepoRoot -Target $Target
    $recordRelative = [string]$fixture.identity.target_record_path
    $sealRelative = '.mir/releases/terminal/seals/' + [string]$fixture.record.predecessor.version + '.json'
    foreach ($relative in @($recordRelative,$sealRelative)) {
      $destination = Join-Path $fixtureRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
      Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    $expectedPredecessorPath = [IO.Path]::GetFullPath((Join-Path $fixtureRoot ([string]$fixture.record.predecessor.archive)))
    $failure = $null
    try { Get-MIR42QualificationHistoricalAuthority -RepoRoot $fixtureRoot -Target $Target | Out-Null }
    catch { $failure = $_ }
    $missingExpectedPredecessor = $null -ne $failure -and
      [string]$failure.Exception.Message -like ('*' + $expectedPredecessorPath + '*') -and
      (([string]$failure.FullyQualifiedErrorId -match 'PathNotFound') -or
       ([string]$failure.CategoryInfo.Category -ceq 'ObjectNotFound'))
    Assert-MIR42NineGeneratorTest -Condition $missingExpectedPredecessor -Code "missing-archive-rejected-$Target"
  } finally {
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build'))
    if (-not [IO.Path]::GetFullPath($fixtureRoot).StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir42-nine-generator-fixture-containment]' }
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
  }
}
function Get-MIR42NineGeneratorFunctionParameters {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,[string]$SourceText)
  $errors = $null
  $ast = if ($SourceText) { [System.Management.Automation.Language.Parser]::ParseInput($SourceText,[ref]$null,[ref]$errors) } else { [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$errors) }
  if ($errors) { throw "[mir42-nine-generator-test-parser] $Path" }
  $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true))
  if ($functions.Count -ne 1) { throw "[mir42-nine-generator-test-function] $Name" }
  return @($functions[0].Body.ParamBlock.Parameters | ForEach-Object { [string]$_.Name.VariablePath.UserPath })
}

$modernRows = @($script:MIR42QualificationTargets | ForEach-Object { [pscustomobject][ordered]@{target=$_} })
$nineRows = @($script:MIR42QualificationNineTargets | ForEach-Object { [pscustomobject][ordered]@{target=$_} })
$modernScope = Get-MIR42QualificationTargetScope -Rows $modernRows -Code 'mir42-nine-generator-modern'
$nineScope = Get-MIR42QualificationTargetScope -Rows $nineRows -Code 'mir42-nine-generator-nine'
$modernContract = Get-MIR42QualificationScopeContract -Scope $modernScope
$nineContract = Get-MIR42QualificationScopeContract -Scope $nineScope
$nineIndependentContract = Get-MIR42IndependentScopeContract -Scope (Get-MIR42IndependentTargetScope -Rows $nineRows -Code 'mir42-nine-generator-independent')
Assert-MIR42NineGeneratorTest -Condition ([string]$modernContract.kind -ceq 'MIR42FourTargetEvidenceReconciliationV1' -and [string]$modernContract.target_requirement -ceq 'all_four_targets_required') -Code 'modern-contract'
Assert-MIR42NineGeneratorTest -Condition ([string]$nineContract.kind -ceq 'MIR42NineTargetEvidenceReconciliationV1' -and [string]$nineContract.target_requirement -ceq 'all_nine_targets_required') -Code 'nine-reconciliation-contract'
Assert-MIR42NineGeneratorTest -Condition ([string]$nineIndependentContract.rehash_kind -ceq 'MIR42NineTargetIndependentEvidenceRehashV1' -and [string]$nineIndependentContract.target_requirement -ceq 'all_nine_targets_required') -Code 'nine-independent-contract'

function Test-MIR42NineCriterionEvidenceWriter {
  param([Parameter(Mandatory)][string]$RepoRoot,[ValidateSet(1,2)][int]$SchemaVersion=1)

  $root = Join-Path $RepoRoot ('build/test-results/mir42-nine-criterion-evidence-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
  # Match real constructor rows: commit/tree are in source; the fingerprint
  # is a separately validated row field supplied by the input reader.
  $constructionSource = [pscustomobject][ordered]@{commit=$source.commit;tree=$source.tree}
  $candidatePath = Join-Path $root 'candidate-manifest.json'
  $candidateRecord = [pscustomobject][ordered]@{
    schema=$SchemaVersion;kind="MIR42FourTargetDeterministicCandidateManifestV$SchemaVersion";status='private-deterministic-nine-target-candidate-built-unqualified'
    source=$constructionSource;package_source_sha256=$source.package_source_sha256;build_complete=$true;record_sha256=''
  }
  Write-MIR4BootstrapRecord -Record $candidateRecord -Path $candidatePath | Out-Null
  $candidateReference = [pscustomobject][ordered]@{
    sha256=(Get-MIR4Sha256File -Path $candidatePath);record_sha256=[string]$candidateRecord.record_sha256
  }
  $candidateRows = @(
    foreach ($target in $script:MIR42QualificationNineTargets) {
      [pscustomobject][ordered]@{target=$target;scope='nine-target';source=$constructionSource;package_source_sha256=$source.package_source_sha256;candidate_manifest=$candidateReference}
    }
  )
  $originalCandidateRows = (Get-Item Function:Get-MIR42QualificationCandidateRows).ScriptBlock
  try {
    Set-Item Function:Get-MIR42QualificationCandidateRows -Value { param($RepoRoot,$CandidateManifestPath) return @($candidateRows) }
    $criterionRecords = @{}
    foreach ($criterion in $script:MIR42ReleaseAcceptanceCriteria) {
      $observationPath = $candidatePath
      if ($criterion -notin @('package-exclusion','deterministic-reconstruction')) {
        $observation = [ordered]@{schema=1;source=$source;candidate_manifest=$candidateReference;record_sha256=''}
        switch ($criterion) {
          'fresh-exact-loads' {
            $observation.kind='MIR42NineTargetRealEngineEvidenceBinderV1'
            $observation.status='MIR-4.2-NINE-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
            $observation.release_qualification='not-performed';$observation.release_acceptance='not-performed'
          }
          'target-omissions' {
            $observation.kind='MIR42NineTargetEvidenceReconciliationV1'
            $observation.status='MIR-4.2-NINE-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED'
            $observation.release_qualification='not-performed'
          }
          default {
            $observation.kind='MIR42NineTargetCriterionObservationV1';$observation.status='passed';$observation.criterion=$criterion
            if ($criterion -ceq 'performance-telemetry') { $observation.telemetry_scope='bounded-candidate-load-and-upgrade-resource-observation' }
          }
        }
        $observationPath = Join-Path $root ('observation-' + $criterion + '.json')
        Write-MIR4BootstrapRecord -Record ([pscustomobject]$observation) -Path $observationPath | Out-Null
      }
      $output = Join-Path $root ('criterion-' + $criterion + '.json')
      $criterionRecords[$criterion] = New-MIR42NineTargetCriterionEvidence -RepoRoot $RepoRoot -CandidateManifestPath $candidatePath -Criterion $criterion `
        -ObservationPaths @($observationPath) -ObservedTargets @($script:MIR42QualificationNineTargets) -Claim ('fixture ' + $criterion) `
        -KnownLimitations 'structural writer fixture only; no release qualification claimed' -OutputPath $output
      Assert-MIR42NineGeneratorTest -Condition ([string]$criterionRecords[$criterion].status -ceq 'passed' -and
        [string]$criterionRecords[$criterion].criterion -ceq $criterion -and
        [string]$criterionRecords[$criterion].source.package_source_sha256 -ceq [string]$source.package_source_sha256 -and
        [string]$criterionRecords[$criterion].candidate_manifest.record_sha256 -ceq [string]$candidateReference.record_sha256) -Code ('criterion-writer-' + $criterion)
    }
    $badObservation = [pscustomobject][ordered]@{
      schema=1;kind='MIR42NineTargetCriterionObservationV1';status='passed';criterion='performance-telemetry';telemetry_scope='general-fps'
      source=$source;candidate_manifest=$candidateReference;record_sha256=''
    }
    $badPath = Join-Path $root 'bad-performance-observation.json'
    Write-MIR4BootstrapRecord -Record $badObservation -Path $badPath | Out-Null
    $rejected = $false
    try {
      New-MIR42NineTargetCriterionEvidence -RepoRoot $RepoRoot -CandidateManifestPath $candidatePath -Criterion 'performance-telemetry' `
        -ObservationPaths @($badPath) -ObservedTargets @($script:MIR42QualificationNineTargets) -Claim 'bad fixture' `
        -KnownLimitations 'bad fixture' -OutputPath (Join-Path $root 'bad-performance-criterion.json') | Out-Null
    } catch { $rejected = $_.Exception.Message -match '^\[mir42-criterion-evidence-observation-binding\] performance-telemetry$' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-performance-general-fps-rejected'
    $reformattedPath = Join-Path $root 'reformatted-construction.json'
    [IO.File]::WriteAllText($reformattedPath, ((Get-Content -Raw -LiteralPath $candidatePath) + [string][char]10), [Text.UTF8Encoding]::new($false))
    $reformatted = Read-MIR42QualificationBootstrapRecord -Path $reformattedPath -Code 'mir42-criterion-reformatted-fixture'
    Assert-MIR42NineGeneratorTest -Condition ([string]$reformatted.record_sha256 -ceq [string]$candidateReference.record_sha256 -and (Get-MIR4Sha256File -Path $reformattedPath) -cne [string]$candidateReference.sha256) -Code 'criterion-same-record-different-raw-bytes-control'
    $rejected = $false
    try {
      New-MIR42NineTargetCriterionEvidence -RepoRoot $RepoRoot -CandidateManifestPath $candidatePath -Criterion 'package-exclusion' `
        -ObservationPaths @($reformattedPath) -ObservedTargets @($script:MIR42QualificationNineTargets) -Claim 'bad fixture' `
        -KnownLimitations 'bad fixture' -OutputPath (Join-Path $root 'reformatted-criterion.json') | Out-Null
    } catch { $rejected = $_.Exception.Message -ceq '[mir42-criterion-evidence-observation-binding] package-exclusion' }
    Assert-MIR42NineGeneratorTest -Condition ($rejected -and -not (Test-Path -LiteralPath (Join-Path $root 'reformatted-criterion.json'))) -Code 'criterion-reformatted-construction-refused-without-output'
  } finally {
    Set-Item Function:Get-MIR42QualificationCandidateRows -Value $originalCandidateRows
    $null = Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $root
    $null = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $root
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  }
}

foreach($schemaVersion in @(1,2)){Test-MIR42NineCriterionEvidenceWriter -RepoRoot $repo -SchemaVersion $schemaVersion}

$rejected = $false
try { $null = Get-MIR42QualificationTargetScope -Rows @($modernRows + [pscustomobject][ordered]@{target='f017'}) -Code 'mir42-nine-generator-opposing' } catch { $rejected = $_.Exception.Message -match '^\[mir42-nine-generator-opposing-target-set\]' }
Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'mixed-scope-rejected'

foreach ($target in $script:MIR42QualificationHistoricalTargets) {
  $authority = Get-MIR42NineGeneratorHistoricalFixture -RepoRoot $repo -Target $target
  Assert-MIR42NineGeneratorTest -Condition ([string]$authority.fixture_scope -ceq 'committed-target-record-and-terminal-seal-only' -and [string]$authority.identity.target -ceq $target -and [string]$authority.record.target -ceq $target) -Code "identity-$target"
  Assert-MIR42NineGeneratorTest -Condition ([string]$authority.seal.release -ceq [string]$authority.record.predecessor.version -and [string]$authority.seal.archive_sha256 -ceq [string]$authority.record.predecessor.sha256) -Code "terminal-$target"
  Assert-MIR42NineGeneratorTest -Condition (-not [bool]$authority.record.public_output_authorized -and -not [bool]$authority.record.publication_authorized) -Code "private-$target"
  Assert-MIR42NineGeneratorTest -Condition ([string]$authority.seal.engine.version -ceq [string]$authority.record.engine.version -and [string]$authority.seal.engine.binary_sha256 -ceq [string]$authority.record.engine.sha256) -Code "engine-binding-$target"
}
Assert-MIR42NineGeneratorTest -Condition (Test-MIR42QualificationHistoricalFileVersion -Target f017 -AuthorityVersion '0.17.79' -ObservedVersion '0.17.79.47865') -Code 'historical-four-part-file-version'
Assert-MIR42NineGeneratorTest -Condition (Test-MIR42QualificationHistoricalFileVersion -Target f013 -AuthorityVersion '0.13.20' -ObservedVersion '') -Code 'historical-013-absent-file-version'
Assert-MIR42NineGeneratorTest -Condition (-not (Test-MIR42QualificationHistoricalFileVersion -Target f017 -AuthorityVersion '0.17.79' -ObservedVersion '0.17.80.47865')) -Code 'historical-different-release-rejected'
Assert-MIR42NineGeneratorTest -Condition (-not (Test-MIR42QualificationHistoricalFileVersion -Target f017 -AuthorityVersion '0.17.79' -ObservedVersion '')) -Code 'historical-unexpected-missing-file-version-rejected'
Assert-MIR42NineGeneratorTest -Condition (-not (Test-MIR42QualificationHistoricalFileVersion -Target f013 -AuthorityVersion '0.13.20' -ObservedVersion '0.13.20.1')) -Code 'historical-013-unexpected-file-version-rejected'
Assert-MIR42NineGeneratorHistoricalArchiveRequired -RepoRoot $repo -Target 'f017'

$fourCommand = Get-Command Invoke-MIR42FourTargetEvidenceReconciliation -CommandType Function
$nineCommand = Get-Command Invoke-MIR42NineTargetEvidenceReconciliation -CommandType Function
$fourRehash = Get-Command Invoke-MIR42FourTargetIndependentEvidenceRehash -CommandType Function
$nineRehash = Get-Command Invoke-MIR42NineTargetIndependentEvidenceRehash -CommandType Function
Assert-MIR42NineGeneratorTest -Condition ($fourCommand.Parameters.Keys -contains 'F210PredecessorZip' -and $fourCommand.Parameters.Keys -contains 'F100UpgradeReceipt' -and $fourRehash.Parameters.Keys -contains 'F210PredecessorZip') -Code 'four-positional-contract-preserved'
Assert-MIR42NineGeneratorTest -Condition ($nineCommand.Parameters.Keys -contains 'PredecessorZips' -and $nineCommand.Parameters.Keys -contains 'UpgradeReceipts' -and $nineRehash.Parameters.Keys -contains 'PredecessorZips' -and $nineRehash.Parameters.Keys -contains 'UpgradeReceipts' -and $nineCommand.Parameters.Keys -notcontains 'F210PredecessorZip') -Code 'nine-keyed-input-contract'
$baseEvidence = (@(& git -C $repo show '8835c01b82c26cfb7634e1727e33903c9c6a39d7:tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1') -join "`n")
if ($LASTEXITCODE -ne 0) { throw '[mir42-nine-generator-baseline-evidence]' }
$baseIndependent = (@(& git -C $repo show '8835c01b82c26cfb7634e1727e33903c9c6a39d7:tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1') -join "`n")
if ($LASTEXITCODE -ne 0) { throw '[mir42-nine-generator-baseline-independent]' }
Assert-MIR42NineGeneratorTest -Condition ((@(Get-MIR42NineGeneratorFunctionParameters -Path $evidence -SourceText $baseEvidence -Name 'Invoke-MIR42FourTargetEvidenceReconciliation') -join '|') -ceq (@(Get-MIR42NineGeneratorFunctionParameters -Path $evidence -Name 'Invoke-MIR42FourTargetEvidenceReconciliation') -join '|')) -Code 'four-evidence-parameter-parity'
Assert-MIR42NineGeneratorTest -Condition ((@(Get-MIR42NineGeneratorFunctionParameters -Path $independent -SourceText $baseIndependent -Name 'Invoke-MIR42FourTargetIndependentEvidenceRehash') -join '|') -ceq (@(Get-MIR42NineGeneratorFunctionParameters -Path $independent -Name 'Invoke-MIR42FourTargetIndependentEvidenceRehash') -join '|')) -Code 'four-independent-parameter-parity'

Write-Output 'MIR42-NINE-TARGET-EVIDENCE-GENERATOR-PASSED scopes=4,9 historical=5 engines=0'
