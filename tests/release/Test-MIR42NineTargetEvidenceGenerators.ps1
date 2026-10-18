# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,[switch]$Normal431TelemetryOnly)

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
    # Historical engine metadata remains usable when an old mod archive has
    # been retired. This does not authenticate any selected upgrade package.
    foreach ($sourceVersion in @('4.2.1','4.2.2','4.2.3')) {
      $metadata = Get-MIR42QualificationHistoricalAuthority -RepoRoot $fixtureRoot -Target $Target -SourceVersion $sourceVersion -PredecessorIdentityOnly
      Assert-MIR42NineGeneratorTest -Condition ($null -eq $metadata.inventory -and $metadata.identity.source_version -ceq $sourceVersion) -Code "retired-archive-metadata-$sourceVersion-$Target"
    }
    $receipt = [pscustomobject]@{factorio_binary_version=([string]$fixture.record.engine.version+'.1');factorio_binary_sha256=[string]$fixture.record.engine.sha256}
    $environment = Get-MIR42QualificationEnvironment -RepoRoot $fixtureRoot -Target $Target -Receipt $receipt
    Assert-MIR42NineGeneratorTest -Condition ($environment.binary_sha256 -ceq $fixture.record.engine.sha256) -Code "retired-archive-engine-metadata-$Target"
    $receipt.factorio_binary_sha256='0'*64
    $rejected=$false
    try { Get-MIR42QualificationEnvironment -RepoRoot $fixtureRoot -Target $Target -Receipt $receipt | Out-Null }
    catch { $rejected=$_.Exception.Message -ceq "[mir42-qualification-environment-historical] $Target" }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code "retired-archive-engine-hash-refused-$Target"
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
$v12IndependentContract = Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance -SourceVersion '4.5.2'
Assert-MIR42NineGeneratorTest -Condition ([string]$v12IndependentContract.reconciliation_status -ceq 'MIR-4.5.2-NINE-TARGET-MAINTENANCE-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED' -and [string]$v12IndependentContract.rehash_status -ceq 'MIR-4.5.2-NINE-TARGET-MAINTENANCE-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED') -Code '452-independent-contract'
$rejected = $false
try { Get-MIR42IndependentScopeContract -Scope 'nine-target' -PublishedMaintenance -SourceVersion '4.5.1' | Out-Null }
catch { $rejected = $_.Exception -is [Management.Automation.ParameterBindingException] }
Assert-MIR42NineGeneratorTest -Condition $rejected -Code '451-independent-current-candidate-refused'

function Test-MIR42NineCriterionEvidenceWriter {
  param([Parameter(Mandatory)][string]$RepoRoot,[ValidateSet(1,2,3,4,5,6)][int]$SchemaVersion=1)

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
  # Independent historical fixture identities, rather than one modern version
  # attached to every older construction schema.
  $fixtureSourceVersion = @('4.2.0','4.2.1','4.2.2','4.2.3','4.3.0','4.3.1')[$SchemaVersion-1]
  $fixtureVersion = [version]$fixtureSourceVersion
  $fixtureTargets = if($SchemaVersion-eq1){$script:MIR42QualificationTargets}else{$script:MIR42QualificationNineTargets}
  $fixtureScope = if($SchemaVersion-eq1){'four-target'}else{'nine-target'}
  $candidateRows = @(
    foreach ($target in $fixtureTargets) {
      $distributionVersion = '{0}.{1}.{2:00000}' -f $fixtureVersion.Major,$fixtureVersion.Minor,(100*[int]$target.Substring(1)+$fixtureVersion.Build)
      [pscustomobject][ordered]@{target=$target;scope=$fixtureScope;identity=[pscustomobject][ordered]@{source_version=$fixtureSourceVersion;distribution_version=$distributionVersion};source=$constructionSource;package_source_sha256=$source.package_source_sha256;candidate_manifest=$candidateReference}
    }
  )
  $originalCandidateRows = (Get-Item Function:Get-MIR42QualificationCandidateRows).ScriptBlock
  try {
    Set-Item Function:Get-MIR42QualificationCandidateRows -Value { param($RepoRoot,$CandidateManifestPath) return @($candidateRows) }
    if($SchemaVersion-eq1){
      # V1 predates the nine-target programme. Retain it as an opposing scope
      # case instead of inventing nine-target 4.2.1 rows for a 4.2.0 manifest.
      $legacyOutput=Join-Path $root 'legacy-four-target-criterion.json'
      $rejected=$false
      try {
        $null=New-MIR42NineTargetCriterionEvidence -RepoRoot $RepoRoot -CandidateManifestPath $candidatePath -Criterion 'package-exclusion' `
          -ObservationPaths @($candidatePath) -ObservedTargets @($script:MIR42QualificationNineTargets) -Claim 'invalid legacy fixture' `
          -KnownLimitations 'four-target construction cannot qualify a nine-target release' -OutputPath $legacyOutput
      }catch{$rejected=$_.Exception.Message-ceq'[mir42-criterion-evidence-candidate-scope]'}
      Assert-MIR42NineGeneratorTest -Condition ($rejected-and-not(Test-Path -LiteralPath $legacyOutput)) -Code 'criterion-v1-four-target-refused-without-output'
      return
    }
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
      if($criterion-ceq'performance-telemetry'-and$SchemaVersion-ge5){
        # These metadata fixtures contain neither 4.3.0 stress measurements
        # nor 4.3.1 authenticated engine evidence. They must not qualify as
        # performance evidence. The dedicated normal-performance controls
        # below exercise the latter's positive and opposing cases.
        $expectedFailure=if($SchemaVersion-eq5){'[mir42-criterion-evidence-observation-binding] performance-telemetry'}else{'[mir42-criterion-evidence-observation-normal-performance-engine-input]'}
        $rejected=$false
        try {
          $null=Get-MIR42CriterionEvidenceObservation -Path $observationPath -Criterion $criterion `
            -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$candidateReference}) `
            -Code 'mir42-criterion-evidence-observation' -SourceVersion $fixtureSourceVersion
        }catch{$rejected=$_.Exception.Message-ceq$expectedFailure}
        Assert-MIR42NineGeneratorTest -Condition ($rejected-and-not(Test-Path -LiteralPath $output)) -Code ('criterion-metadata-not-native-performance-v'+$SchemaVersion)
        continue
      }
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
      Get-MIR42CriterionEvidenceObservation -Path $badPath -Criterion 'performance-telemetry' `
        -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$candidateReference}) `
        -Code 'mir42-criterion-evidence-observation' -SourceVersion $fixtureSourceVersion | Out-Null
    } catch { $rejected = $_.Exception.Message -match '^\[mir42-criterion-evidence-observation-binding\] performance-telemetry$' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-performance-general-fps-rejected'
    $reformattedPath = Join-Path $root 'reformatted-construction.json'
    [IO.File]::WriteAllText($reformattedPath, ((Get-Content -Raw -LiteralPath $candidatePath) + [string][char]10), [Text.UTF8Encoding]::new($false))
    $reformatted = Read-MIR42QualificationBootstrapRecord -Path $reformattedPath -Code 'mir42-criterion-reformatted-fixture'
    Assert-MIR42NineGeneratorTest -Condition ([string]$reformatted.record_sha256 -ceq [string]$candidateReference.record_sha256 -and (Get-MIR4Sha256File -Path $reformattedPath) -cne [string]$candidateReference.sha256) -Code ('criterion-same-record-different-raw-bytes-control-v'+$SchemaVersion)
    $rejected = $false
    try {
      New-MIR42NineTargetCriterionEvidence -RepoRoot $RepoRoot -CandidateManifestPath $candidatePath -Criterion 'package-exclusion' `
        -ObservationPaths @($reformattedPath) -ObservedTargets @($script:MIR42QualificationNineTargets) -Claim 'bad fixture' `
        -KnownLimitations 'bad fixture' -OutputPath (Join-Path $root 'reformatted-criterion.json') | Out-Null
    } catch { $rejected = $_.Exception.Message -ceq '[mir42-criterion-evidence-observation-binding] package-exclusion' }
    Assert-MIR42NineGeneratorTest -Condition ($rejected -and -not (Test-Path -LiteralPath (Join-Path $root 'reformatted-criterion.json'))) -Code ('criterion-reformatted-construction-refused-without-output-v'+$SchemaVersion)

    if ($SchemaVersion -eq 6) {
      $wrongManifest = [pscustomobject][ordered]@{
        schema=6;kind='MIR42FourTargetDeterministicCandidateManifestV5';status='private-deterministic-nine-target-candidate-built-unqualified'
        source=$constructionSource;package_source_sha256=$source.package_source_sha256;build_complete=$true;record_sha256=''
      }
      $wrongManifestPath = Join-Path $root 'wrong-v6-manifest-kind.json'
      Write-MIR4BootstrapRecord -Record $wrongManifest -Path $wrongManifestPath | Out-Null
      $wrongManifestReference = [pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $wrongManifestPath);record_sha256=[string]$wrongManifest.record_sha256}
      $rejected = $false
      try {
        Get-MIR42CriterionEvidenceObservation -Path $wrongManifestPath -Criterion 'package-exclusion' `
          -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$wrongManifestReference}) -Code 'mir42-nine-generator-v6' | Out-Null
      } catch { $rejected = $_.Exception.Message -ceq '[mir42-candidate-construction-version-contract]' }
      Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-v6-wrong-manifest-rejected'

      $wrongVersion = [pscustomobject][ordered]@{
        schema=8;kind='MIR42FourTargetDeterministicCandidateManifestV8';status='private-deterministic-nine-target-candidate-built-unqualified'
        source=$constructionSource;package_source_sha256=$source.package_source_sha256;build_complete=$true;record_sha256=''
      }
      $wrongVersionPath = Join-Path $root 'wrong-v6-version.json'
      Write-MIR4BootstrapRecord -Record $wrongVersion -Path $wrongVersionPath | Out-Null
      $wrongVersionReference = [pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $wrongVersionPath);record_sha256=[string]$wrongVersion.record_sha256}
      $rejected = $false
      try {
        Get-MIR42CriterionEvidenceObservation -Path $wrongVersionPath -Criterion 'package-exclusion' `
          -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$wrongVersionReference}) -Code 'mir42-nine-generator-v6' | Out-Null
      } catch { $rejected = $_.Exception.Message -ceq '[mir42-nine-generator-v6-binding] package-exclusion' }
      Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-v6-wrong-version-rejected'
    }

    # The individual reader is the authenticated representation for the
    # nine direct predecessor upgrades plus ten fresh loads.  Keep criterion
    # admission exactly aligned with its bounded maintenance-version contract.
    $individualPublishedInputs = [pscustomobject][ordered]@{
      targets = @(
        foreach ($target in $script:MIR42QualificationNineTargets) {
          [pscustomobject][ordered]@{target=$target;path=('published-'+$target+'.zip');version=('4.2.2-'+$target);sha256=($target.Substring(1,1) * 64)}
        }
      )
    }
    $individualTargets = @(
      foreach ($publishedTarget in @($individualPublishedInputs.targets)) {
        [pscustomobject][ordered]@{
          target=[string]$publishedTarget.target
          engine_execution=[pscustomobject][ordered]@{
            published_maintenance_predecessor=$publishedTarget
            predecessor=[pscustomobject][ordered]@{path=[string]$publishedTarget.path;version=[string]$publishedTarget.version;sha256=[string]$publishedTarget.sha256}
          }
        }
      }
    )
    foreach ($sourceVersion in @('4.2.3','4.3.0','4.3.1','4.4.0','4.4.2','4.5.2')) {
      $individualObservation = [ordered]@{
        schema=1;kind='MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
        status=("MIR-$sourceVersion-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED")
        source=$source;candidate_manifest=$candidateReference
        published_maintenance_predecessor=$individualPublishedInputs;targets=$individualTargets
        engine_input_kind='individual-upgrade-receipts-and-fresh-loads'
        release_qualification='not-performed';release_acceptance='not-performed';record_sha256=''
      }
      $individualPath = Join-Path $root ('individual-' + $sourceVersion + '.json')
      Write-MIR4BootstrapRecord -Record ([pscustomobject]$individualObservation) -Path $individualPath | Out-Null
      $individualEvidence = Get-MIR42CriterionEvidenceObservation -Path $individualPath -Criterion 'fresh-exact-loads' `
        -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$candidateReference}) -Code 'mir42-nine-generator-individual' `
        -PublishedMaintenanceInputs $individualPublishedInputs -SourceVersion $sourceVersion
      $individualReadback = Read-MIR42QualificationBootstrapRecord -Path $individualPath -Code 'mir42-nine-generator-individual-readback'
      Assert-MIR42NineGeneratorTest -Condition ([string]$individualEvidence.record_sha256 -eq [string]$individualReadback.record_sha256) -Code ('criterion-individual-'+$sourceVersion+'-accepted')
    }
    $individualWrongStatus = [ordered]@{
      schema=1;kind='MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
      status='MIR-4.3.0-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
      source=$source;candidate_manifest=$candidateReference
      engine_input_kind='individual-upgrade-receipts-and-fresh-loads'
      release_qualification='not-performed';release_acceptance='not-performed';record_sha256=''
    }
    $individualWrongStatusPath = Join-Path $root 'individual-wrong-status.json'
    Write-MIR4BootstrapRecord -Record ([pscustomobject]$individualWrongStatus) -Path $individualWrongStatusPath | Out-Null
    $rejected = $false
    try {
      Get-MIR42CriterionEvidenceObservation -Path $individualWrongStatusPath -Criterion 'fresh-exact-loads' `
        -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$candidateReference}) -Code 'mir42-nine-generator-individual' `
        -PublishedMaintenanceInputs $individualPublishedInputs -SourceVersion '4.3.1' | Out-Null
    } catch { $rejected = $_.Exception.Message -ceq '[mir42-nine-generator-individual-binding] fresh-exact-loads' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-individual-wrong-status-rejected'
    $rejected = $false
    try {
      Get-MIR42CriterionEvidenceObservation -Path $individualWrongStatusPath -Criterion 'fresh-exact-loads' `
        -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$candidateReference}) -Code 'mir42-nine-generator-individual' `
        -PublishedMaintenanceInputs $individualPublishedInputs -SourceVersion '4.2.2' | Out-Null
    } catch { $rejected = $_.Exception.Message -ceq '[mir42-nine-generator-individual-binding] fresh-exact-loads' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-individual-unsupported-source-rejected'
    $individualMissingKind = [ordered]@{
      schema=1;kind='MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
      status='MIR-4.3.1-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
      source=$source;candidate_manifest=$candidateReference
      release_qualification='not-performed';release_acceptance='not-performed';record_sha256=''
    }
    $individualMissingKindPath = Join-Path $root 'individual-missing-kind.json'
    Write-MIR4BootstrapRecord -Record ([pscustomobject]$individualMissingKind) -Path $individualMissingKindPath | Out-Null
    $rejected = $false
    try {
      Get-MIR42CriterionEvidenceObservation -Path $individualMissingKindPath -Criterion 'fresh-exact-loads' `
        -Candidate ([pscustomobject]@{source=$source;candidate_manifest=$candidateReference}) -Code 'mir42-nine-generator-individual' `
        -PublishedMaintenanceInputs $individualPublishedInputs -SourceVersion '4.3.1' | Out-Null
    } catch { $rejected = $_.Exception.Message -ceq '[mir42-nine-generator-individual-binding] fresh-exact-loads' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'criterion-individual-missing-input-kind-rejected'
  } finally {
    Set-Item Function:Get-MIR42QualificationCandidateRows -Value $originalCandidateRows
    $null = Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $root
    $null = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $root
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  }
}

function Test-MIR431NormalPerformanceTelemetryBinding {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
  $candidateReference = [pscustomobject][ordered]@{sha256=('D' * 64);record_sha256=('E' * 64)}
  $candidate = [pscustomobject][ordered]@{source=$source;candidate_manifest=$candidateReference}
  $engineCandidate = [pscustomobject][ordered]@{
    source=$source;identity=[pscustomobject][ordered]@{sha256=$candidateReference.sha256;record=[pscustomobject][ordered]@{record_sha256=$candidateReference.record_sha256}}
    scope='nine-target';targets=@($script:MIR42QualificationNineTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})
  }
  $reference = [pscustomobject][ordered]@{path='individual-engine-run.json';sha256=('F' * 64);record_sha256=('1' * 64)}
  $published = [pscustomobject][ordered]@{targets=@($script:MIR42QualificationNineTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})}
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR42NineTargetCriterionObservationV1';status='passed';criterion='performance-telemetry'
    telemetry_scope='bounded-candidate-load-and-upgrade-resource-observation';compiler_profile='full'
    source=$source;candidate_manifest=$candidateReference;individual_engine_run=$reference;record_sha256=('2' * 64)
  }
  $original = Get-Item Function:Get-MIR42BoundEngineRun -ErrorAction SilentlyContinue
  $script:mir431NormalPerformanceBoundTargets = @($script:MIR42QualificationNineTargets)
  try {
    Set-Item Function:Get-MIR42BoundEngineRun -Value {
      param($Reference,$Candidate,$PublishedMaintenanceInputs)
      [pscustomobject][ordered]@{
        path='individual-engine-run.json';sha256=('F' * 64);input_kind='individual-upgrade-receipts-and-fresh-loads'
        record=[pscustomobject][ordered]@{record_sha256=('1' * 64);targets=@($script:mir431NormalPerformanceBoundTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})}
      }
    }
    $accepted = Assert-MIR431NormalPerformanceTelemetryObservation -Record $record -Candidate $candidate -IndividualEngineCandidate $engineCandidate -PublishedMaintenanceInputs $published -Code 'mir431-normal-performance-test'
    Assert-MIR42NineGeneratorTest -Condition ([string]$accepted.input_kind -ceq 'individual-upgrade-receipts-and-fresh-loads') -Code '431-normal-performance-binds-individual-engine-run'

    $cases = @(
      [pscustomobject]@{name='source';mutate={param($value) $value.source=[pscustomobject]@{commit=('0'*40);tree=$source.tree;package_source_sha256=$source.package_source_sha256}};expected='binding'}
      [pscustomobject]@{name='candidate';mutate={param($value) $value.candidate_manifest=[pscustomobject]@{sha256=('0'*64);record_sha256=$candidateReference.record_sha256}};expected='binding'}
      [pscustomobject]@{name='missing-ref';mutate={param($value) $value.PSObject.Properties.Remove('individual_engine_run')};expected='shape'}
      [pscustomobject]@{name='changed-ref';mutate={param($value) $value.individual_engine_run=[pscustomobject]@{path='individual-engine-run.json';sha256=('0'*64);record_sha256=('1'*64)}};expected='engine-run-binding'}
    )
    foreach ($case in $cases) {
      $testRecord = $record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
      & $case.mutate $testRecord
      $rejected = $false
      try { Assert-MIR431NormalPerformanceTelemetryObservation -Record $testRecord -Candidate $candidate -IndividualEngineCandidate $engineCandidate -PublishedMaintenanceInputs $published -Code 'mir431-normal-performance-test' | Out-Null } catch { $rejected = $_.Exception.Message -match ('mir431-normal-performance-test-' + $case.expected) }
      Assert-MIR42NineGeneratorTest -Condition $rejected -Code ('431-normal-performance-'+$case.name+'-rejected')
    }
    $script:mir431NormalPerformanceBoundTargets = @($script:MIR42QualificationNineTargets | Select-Object -SkipLast 1)
    $rejected = $false
    try { Assert-MIR431NormalPerformanceTelemetryObservation -Record $record -Candidate $candidate -IndividualEngineCandidate $engineCandidate -PublishedMaintenanceInputs $published -Code 'mir431-normal-performance-test' | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir431-normal-performance-test-engine-run-binding' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '431-normal-performance-target-set-rejected'
  } finally {
    if ($null -eq $original) { Remove-Item Function:Get-MIR42BoundEngineRun -ErrorAction SilentlyContinue } else { Set-Item Function:Get-MIR42BoundEngineRun -Value $original.ScriptBlock }
    Remove-Variable -Name mir431NormalPerformanceBoundTargets -Scope Script -ErrorAction SilentlyContinue
  }
}

function Test-MIR442MaintenanceEvidenceAdmission {
  param([Parameter(Mandatory)][string]$RepoRoot)
  foreach($criterion in @('fresh-exact-loads','target-omissions','performance-telemetry')) {
    $contract = Get-MIR42CriterionObservationContract -Criterion $criterion -PublishedMaintenance -SourceVersion '4.4.2'
    Assert-MIR42NineGeneratorTest -Condition ($criterion -ceq 'performance-telemetry' -or [string]$contract.status -like 'MIR-4.4.2-*') -Code ('442-criterion-admission-'+$criterion)
  }
  $rejected=$false
  try { Get-MIR42CriterionObservationContract -Criterion 'performance-telemetry' -PublishedMaintenance -SourceVersion '4.4.3' | Out-Null }
  catch { $rejected = $_.Exception -is [Management.Automation.ParameterBindingException] }
  Assert-MIR42NineGeneratorTest -Condition $rejected -Code '443-criterion-refused'
  $root=Join-Path $RepoRoot ('build/tmp/mir442-evidence-admission-'+[guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($root)|Out-Null
  try {
    $source=[pscustomobject][ordered]@{commit=('a'*40);tree=('b'*40);package_source_sha256=('C'*64)}
    foreach($kind in @('MIR42FourTargetDeterministicCandidateManifestV9','MIR42FourTargetDeterministicCandidateManifestV8','MIR42FourTargetDeterministicCandidateManifestV7')) {
      $schema=if($kind.EndsWith('V8')){8}else{9}
      $record=[pscustomobject][ordered]@{schema=$schema;kind=$kind;source=$source;package_source_sha256=$source.package_source_sha256;build_complete=$true;record_sha256=''}
      $path=Join-Path $root ($kind+'.json')
      Write-MIR4BootstrapRecord -Record $record -Path $path|Out-Null
      $reference=[pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $path);record_sha256=$record.record_sha256}
      $candidate=[pscustomobject][ordered]@{source=$source;candidate_manifest=$reference}
      if($kind.EndsWith('V9')) {
        $observed=Get-MIR42CriterionEvidenceObservation -Path $path -Criterion 'package-exclusion' -Candidate $candidate -SourceVersion '4.4.2' -Code 'mir442-admission-control'
        Assert-MIR42NineGeneratorTest -Condition ($observed.sha256 -ceq $reference.sha256) -Code '442-v9-construction-consumed'
        $reformatted=Join-Path $root 'reformatted.json'
        [IO.File]::WriteAllText($reformatted,([IO.File]::ReadAllText($path)+"`n"),[Text.UTF8Encoding]::new($false))
        $rejected=$false
        try { Get-MIR42CriterionEvidenceObservation -Path $reformatted -Criterion 'package-exclusion' -Candidate $candidate -SourceVersion '4.4.2' -Code 'mir442-admission-control'|Out-Null }
        catch { $rejected=$_.Exception.Message -ceq '[mir442-admission-control-binding] package-exclusion' }
        Assert-MIR42NineGeneratorTest -Condition $rejected -Code '442-v9-changed-raw-bytes-refused'
      } else {
        $rejected=$false
        try { Get-MIR42CriterionEvidenceObservation -Path $path -Criterion 'package-exclusion' -Candidate $candidate -SourceVersion '4.4.2' -Code 'mir442-admission-control'|Out-Null }
        catch { $rejected=$_.Exception.Message -in @('[mir442-admission-control-binding] package-exclusion','[mir42-candidate-construction-version-contract]') }
        Assert-MIR42NineGeneratorTest -Condition $rejected -Code ('442-wrong-construction-refused-'+$kind)
      }
    }
  } finally {
    $null=Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $root
    $null=Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $root
    Remove-Item -LiteralPath $root -Recurse -Force
  }
  Write-Output 'MIR442-MAINTENANCE-EVIDENCE-ADMISSION-PASSED assertions=8 engines=0 controlled_evidence_only=true'
}

function Test-MIR450ConstructionCriterionAdmission {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $root=Join-Path $RepoRoot ('build/tmp/mir450-construction-criterion-'+[guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($root)|Out-Null
  try {
    $source=[pscustomobject][ordered]@{commit=('a'*40);tree=('b'*40);package_source_sha256=('C'*64)}
    $record=[pscustomobject][ordered]@{schema=10;kind='MIR42FourTargetDeterministicCandidateManifestV10';source=$source;package_source_sha256=$source.package_source_sha256;build_complete=$true;record_sha256=''}
    $path=Join-Path $root 'candidate.json'
    Write-MIR4BootstrapRecord -Record $record -Path $path|Out-Null
    $reference=[pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $path);record_sha256=$record.record_sha256}
    $candidate=[pscustomobject][ordered]@{source=$source;candidate_manifest=$reference}
    foreach($criterion in @('package-exclusion','deterministic-reconstruction')) {
      $observed=Get-MIR42CriterionEvidenceObservation -Path $path -Criterion $criterion -Candidate $candidate -SourceVersion '4.5.0' -Code 'mir450-construction-criterion'
      Assert-MIR42NineGeneratorTest -Condition ($observed.sha256 -ceq $reference.sha256) -Code ('450-v10-construction-consumed-'+$criterion)
      $reformatted=Join-Path $root ($criterion+'-reformatted.json')
      [IO.File]::WriteAllText($reformatted,([IO.File]::ReadAllText($path)+"`n"),[Text.UTF8Encoding]::new($false))
      $rejected=$false
      try { Get-MIR42CriterionEvidenceObservation -Path $reformatted -Criterion $criterion -Candidate $candidate -SourceVersion '4.5.0' -Code 'mir450-construction-criterion'|Out-Null }
      catch { $rejected=$_.Exception.Message -ceq ('[mir450-construction-criterion-binding] '+$criterion) }
      Assert-MIR42NineGeneratorTest -Condition $rejected -Code ('450-v10-raw-bytes-refused-'+$criterion)
      foreach($mutation in @('wrong-schema','incomplete-build','future-kind')) {
        $bad=$record|ConvertTo-Json -Depth 20|ConvertFrom-Json -Depth 20
        switch($mutation){'wrong-schema'{$bad.schema=9};'incomplete-build'{$bad.build_complete=$false};'future-kind'{$bad.schema=11;$bad.kind='MIR42FourTargetDeterministicCandidateManifestV11'}}
        $badPath=Join-Path $root ($criterion+'-'+$mutation+'.json')
        Write-MIR4BootstrapRecord -Record $bad -Path $badPath|Out-Null
        $badCandidate=[pscustomobject][ordered]@{source=$source;candidate_manifest=[pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $badPath);record_sha256=$bad.record_sha256}}
        $rejected=$false
        try { Get-MIR42CriterionEvidenceObservation -Path $badPath -Criterion $criterion -Candidate $badCandidate -SourceVersion '4.5.0' -Code 'mir450-construction-criterion'|Out-Null }
        catch { $rejected=$_.Exception.Message -in @('[mir42-candidate-construction-version-contract]',('[mir450-construction-criterion-binding] '+$criterion)) }
        Assert-MIR42NineGeneratorTest -Condition $rejected -Code ('450-v10-'+$mutation+'-refused-'+$criterion)
      }
    }
  } finally {
    $null=Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $root
    $null=Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $root
    Remove-Item -LiteralPath $root -Recurse -Force
  }
  Write-Output 'MIR450-CONSTRUCTION-CRITERION-ADMISSION-PASSED assertions=10 engines=0 controlled_evidence_only=true'
}

function Test-MIR452CurrentEvidenceAdmission {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $root = Join-Path $RepoRoot ('build/tmp/mir452-current-evidence-' + [guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($root) | Out-Null
  $originalBound = Get-Item Function:Get-MIR42BoundEngineRun -ErrorAction SilentlyContinue
  try {
    $source = [pscustomobject][ordered]@{commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64)}
    $construction = [pscustomobject][ordered]@{
      schema=12;kind='MIR42FourTargetDeterministicCandidateManifestV12';source=$source
      package_source_sha256=$source.package_source_sha256;build_complete=$true;record_sha256=''
    }
    $constructionPath = Join-Path $root 'candidate-v12.json'
    Write-MIR4BootstrapRecord -Record $construction -Path $constructionPath | Out-Null
    $constructionReference = [pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $constructionPath);record_sha256=$construction.record_sha256}
    $candidate = [pscustomobject][ordered]@{source=$source;candidate_manifest=$constructionReference}
    foreach ($criterion in @('package-exclusion','deterministic-reconstruction')) {
      $observed = Get-MIR42CriterionEvidenceObservation -Path $constructionPath -Criterion $criterion -Candidate $candidate -SourceVersion '4.5.2' -Code 'mir452-current-evidence'
      Assert-MIR42NineGeneratorTest -Condition ($observed.sha256 -ceq $constructionReference.sha256) -Code ('452-v12-construction-accepted-' + $criterion)
    }

    $v11 = $construction | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
    $v11.schema = 11; $v11.kind = 'MIR42FourTargetDeterministicCandidateManifestV11'
    $v11Path = Join-Path $root 'candidate-v11.json'
    Write-MIR4BootstrapRecord -Record $v11 -Path $v11Path | Out-Null
    $v11Candidate = [pscustomobject][ordered]@{source=$source;candidate_manifest=[pscustomobject][ordered]@{sha256=(Get-MIR4Sha256File -Path $v11Path);record_sha256=$v11.record_sha256}}
    $rejected = $false
    try { Get-MIR42CriterionEvidenceObservation -Path $v11Path -Criterion 'package-exclusion' -Candidate $v11Candidate -SourceVersion '4.5.2' -Code 'mir452-current-evidence' | Out-Null }
    catch { $rejected = $_.Exception.Message -ceq '[mir452-current-evidence-binding] package-exclusion' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '452-v11-predecessor-not-current-candidate'
    $rejected = $false
    try { Get-MIR42CriterionEvidenceObservation -Path $constructionPath -Criterion 'package-exclusion' -Candidate $candidate -SourceVersion '4.5.0' -Code 'mir452-current-evidence' | Out-Null }
    catch { $rejected = $_.Exception.Message -ceq '[mir452-current-evidence-binding] package-exclusion' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '452-v12-cross-source-construction-refused'
    foreach ($criterion in @('package-exclusion','deterministic-reconstruction')) {
      foreach ($mutation in @('tree','package-source')) {
        $mismatchSource = $source | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        if ($mutation -ceq 'tree') { $mismatchSource.tree = ('0' * 40) } else { $mismatchSource.package_source_sha256 = ('0' * 64) }
        $mismatchCandidate = [pscustomobject][ordered]@{source=$mismatchSource;candidate_manifest=$constructionReference}
        $rejected = $false
        try { Get-MIR42CriterionEvidenceObservation -Path $constructionPath -Criterion $criterion -Candidate $mismatchCandidate -SourceVersion '4.5.2' -Code 'mir452-current-evidence' | Out-Null }
        catch { $rejected = $_.Exception.Message -ceq ('[mir452-current-evidence-binding] ' + $criterion) }
        Assert-MIR42NineGeneratorTest -Condition $rejected -Code ('452-v12-construction-' + $mutation + '-source-refused-' + $criterion)
      }
    }

    $futureRejected = $false
    try { Get-MIR42CriterionObservationContract -Criterion 'performance-telemetry' -PublishedMaintenance -SourceVersion '4.5.3' | Out-Null }
    catch { $futureRejected = $_.Exception -is [Management.Automation.ParameterBindingException] }
    Assert-MIR42NineGeneratorTest -Condition $futureRejected -Code '453-current-evidence-source-refused'

    $published = [pscustomobject][ordered]@{targets=@(
      foreach ($target in $script:MIR42QualificationNineTargets) {
        [pscustomobject][ordered]@{target=$target;path=('published-' + $target + '.zip');version=('4.5.1-' + $target);sha256=($target.Substring(1,1) * 64)}
      }
    )}
    $individualTargets = @(
      foreach ($publishedTarget in @($published.targets)) {
        [pscustomobject][ordered]@{
          target=[string]$publishedTarget.target
          engine_execution=[pscustomobject][ordered]@{
            published_maintenance_predecessor=$publishedTarget
            predecessor=[pscustomobject][ordered]@{path=[string]$publishedTarget.path;version=[string]$publishedTarget.version;sha256=[string]$publishedTarget.sha256}
          }
        }
      }
    )
    $fresh = [pscustomobject][ordered]@{
      schema=1;kind='MIR42NineTargetMaintenanceIndividualRealEngineEvidenceBinderV1'
      status='MIR-4.5.2-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
      source=$source;candidate_manifest=$constructionReference;published_maintenance_predecessor=$published;targets=$individualTargets
      engine_input_kind='individual-upgrade-receipts-and-fresh-loads';release_qualification='not-performed';release_acceptance='not-performed';record_sha256=''
    }
    $freshPath = Join-Path $root 'fresh-v12.json'
    Write-MIR4BootstrapRecord -Record $fresh -Path $freshPath | Out-Null
    $freshObserved = Get-MIR42CriterionEvidenceObservation -Path $freshPath -Criterion 'fresh-exact-loads' -Candidate $candidate -Code 'mir452-current-evidence' -PublishedMaintenanceInputs $published -SourceVersion '4.5.2'
    Assert-MIR42NineGeneratorTest -Condition ([string]$freshObserved.record_sha256 -ceq [string]$fresh.record_sha256) -Code '452-v12-individual-fresh-accepted'

    $wrongStatus = $fresh | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    $wrongStatus.status = 'MIR-4.5.1-NINE-TARGET-MAINTENANCE-INDIVIDUAL-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
    $wrongStatusPath = Join-Path $root 'fresh-wrong-status.json'
    Write-MIR4BootstrapRecord -Record $wrongStatus -Path $wrongStatusPath | Out-Null
    $rejected = $false
    try { Get-MIR42CriterionEvidenceObservation -Path $wrongStatusPath -Criterion 'fresh-exact-loads' -Candidate $candidate -Code 'mir452-current-evidence' -PublishedMaintenanceInputs $published -SourceVersion '4.5.2' | Out-Null }
    catch { $rejected = $_.Exception.Message -ceq '[mir452-current-evidence-binding] fresh-exact-loads' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '452-v12-individual-wrong-status-refused'

    $partial = $fresh | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    $partial.targets = @($partial.targets | Select-Object -First 8)
    $partialPath = Join-Path $root 'fresh-partial.json'
    Write-MIR4BootstrapRecord -Record $partial -Path $partialPath | Out-Null
    $rejected = $false
    try { Get-MIR42CriterionEvidenceObservation -Path $partialPath -Criterion 'fresh-exact-loads' -Candidate $candidate -Code 'mir452-current-evidence' -PublishedMaintenanceInputs $published -SourceVersion '4.5.2' | Out-Null }
    catch { $rejected = $_.Exception.Message -ceq '[mir42-maintenance-criterion-custody-binding]' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '452-v12-individual-partial-targets-refused'

    $crossSource = $fresh | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    $crossSource.source.tree = ('0' * 40)
    $crossSourcePath = Join-Path $root 'fresh-cross-source.json'
    Write-MIR4BootstrapRecord -Record $crossSource -Path $crossSourcePath | Out-Null
    $rejected = $false
    try { Get-MIR42CriterionEvidenceObservation -Path $crossSourcePath -Criterion 'fresh-exact-loads' -Candidate $candidate -Code 'mir452-current-evidence' -PublishedMaintenanceInputs $published -SourceVersion '4.5.2' | Out-Null }
    catch { $rejected = $_.Exception.Message -ceq '[mir452-current-evidence-binding] fresh-exact-loads' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '452-v12-individual-cross-source-refused'

    $performance = [pscustomobject][ordered]@{
      schema=1;kind='MIR42NineTargetCriterionObservationV1';status='passed';criterion='performance-telemetry'
      telemetry_scope='bounded-candidate-load-and-upgrade-resource-observation';compiler_profile='full'
      source=$source;candidate_manifest=$constructionReference
      individual_engine_run=[pscustomobject][ordered]@{path='individual-engine-run.json';sha256=('F' * 64);record_sha256=('1' * 64)};record_sha256=''
    }
    $performancePath = Join-Path $root 'performance-v12.json'
    Write-MIR4BootstrapRecord -Record $performance -Path $performancePath | Out-Null
    $engineCandidate = [pscustomobject][ordered]@{
      source=$source;identity=[pscustomobject][ordered]@{sha256=$constructionReference.sha256;record=[pscustomobject][ordered]@{record_sha256=$constructionReference.record_sha256}}
      scope='nine-target';targets=@($script:MIR42QualificationNineTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})
    }
    Set-Item Function:Get-MIR42BoundEngineRun -Value {
      param($Reference,$Candidate,$PublishedMaintenanceInputs)
      [pscustomobject][ordered]@{
        path='individual-engine-run.json';sha256=('F' * 64);input_kind='individual-upgrade-receipts-and-fresh-loads'
        record=[pscustomobject][ordered]@{record_sha256=('1' * 64);targets=@($script:MIR42QualificationNineTargets | ForEach-Object {[pscustomobject][ordered]@{target=$_}})}
      }
    }
    $performanceObserved = Get-MIR42CriterionEvidenceObservation -Path $performancePath -Criterion 'performance-telemetry' -Candidate $candidate -Code 'mir452-current-evidence' -PublishedMaintenanceInputs $published -IndividualEngineCandidate $engineCandidate -SourceVersion '4.5.2'
    Assert-MIR42NineGeneratorTest -Condition ([string]$performanceObserved.record_sha256 -ceq [string]$performance.record_sha256) -Code '452-v12-individual-performance-accepted'
    $performanceWrong = $performance | ConvertTo-Json -Depth 30 | ConvertFrom-Json -Depth 30
    $performanceWrong.status = 'completed'
    $performanceWrongPath = Join-Path $root 'performance-wrong-status.json'
    Write-MIR4BootstrapRecord -Record $performanceWrong -Path $performanceWrongPath | Out-Null
    $rejected = $false
    try { Get-MIR42CriterionEvidenceObservation -Path $performanceWrongPath -Criterion 'performance-telemetry' -Candidate $candidate -Code 'mir452-current-evidence' -PublishedMaintenanceInputs $published -IndividualEngineCandidate $engineCandidate -SourceVersion '4.5.2' | Out-Null }
    catch { $rejected = $_.Exception.Message -ceq '[mir452-current-evidence-binding] performance-telemetry' }
    Assert-MIR42NineGeneratorTest -Condition $rejected -Code '452-v12-individual-performance-status-refused'
  } finally {
    if ($null -eq $originalBound) { Remove-Item Function:Get-MIR42BoundEngineRun -ErrorAction SilentlyContinue } else { Set-Item Function:Get-MIR42BoundEngineRun -Value $originalBound.ScriptBlock }
    $null = Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $root
    $null = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $root
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
  }
  Write-Output 'MIR452-CURRENT-EVIDENCE-ADMISSION-PREPARED assertions=15 engines=0 controlled_evidence_only=true'
}

Test-MIR442MaintenanceEvidenceAdmission -RepoRoot $repo
Test-MIR450ConstructionCriterionAdmission -RepoRoot $repo
Test-MIR452CurrentEvidenceAdmission -RepoRoot $repo
if ($Normal431TelemetryOnly) {
  Test-MIR431NormalPerformanceTelemetryBinding -RepoRoot $repo
  Write-Output 'MIR431-NORMAL-PERFORMANCE-TELEMETRY-PASSED assertions=6 engines=0 controlled_evidence_only=true'
  return
}
foreach($schemaVersion in @(1,2,3,4,5,6)){Test-MIR42NineCriterionEvidenceWriter -RepoRoot $repo -SchemaVersion $schemaVersion}
Test-MIR431NormalPerformanceTelemetryBinding -RepoRoot $repo

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
Assert-MIR42NineGeneratorTest -Condition ($nineCommand.Parameters.Keys -contains 'PredecessorZips' -and $nineCommand.Parameters.Keys -contains 'UpgradeReceipts' -and $nineCommand.Parameters.Keys -contains 'PublishedMaintenanceArchiveBindings' -and $nineRehash.Parameters.Keys -contains 'PredecessorZips' -and $nineRehash.Parameters.Keys -contains 'UpgradeReceipts' -and $nineCommand.Parameters.Keys -notcontains 'F210PredecessorZip') -Code 'nine-keyed-input-contract'
$directArchiveBindings = @{}
foreach ($target in $script:MIR42QualificationNineTargets) { $directArchiveBindings[$target] = [IO.Path]::GetFullPath((Join-Path $repo ('build/test-results/' + $target + '.zip'))) }
Assert-MIR42MaintenanceArchiveBindingEquality -PredecessorZips $directArchiveBindings -ArchiveBindings $directArchiveBindings -Targets $script:MIR42QualificationNineTargets
$mismatchedArchiveBindings = @{}
foreach ($target in $script:MIR42QualificationNineTargets) { $mismatchedArchiveBindings[$target] = $directArchiveBindings[$target] }
$mismatchedArchiveBindings.f200 = $directArchiveBindings.f210
$rejected = $false
try { Assert-MIR42MaintenanceArchiveBindingEquality -PredecessorZips $directArchiveBindings -ArchiveBindings $mismatchedArchiveBindings -Targets $script:MIR42QualificationNineTargets } catch { $rejected = $_.Exception.Message -ceq '[mir42-reconciliation-maintenance-archive-bindings]' }
Assert-MIR42NineGeneratorTest -Condition $rejected -Code 'maintenance-direct-library-binding-mismatch-refused'
$originalReadCandidate = (Get-Item -LiteralPath Function:Read-MIR42QualificationBootstrapRecord).ScriptBlock
$originalSharedReconciliation = (Get-Item -LiteralPath Function:Invoke-MIR42EvidenceReconciliationShared).ScriptBlock
try {
  $script:capturedPublishedMaintenanceArchiveBindings = $null
  Set-Item -LiteralPath Function:Read-MIR42QualificationBootstrapRecord -Value {
    param($Path,$Code)
    [pscustomobject]@{targets=@($script:MIR42QualificationNineTargets | ForEach-Object { [pscustomobject]@{target=$_} })}
  }
  Set-Item -LiteralPath Function:Invoke-MIR42EvidenceReconciliationShared -Value {
    param($RepoRoot,$CandidateManifestPath,$PredecessorZips,$UpgradeReceipts,$OutputRoot,$RequiredScope,$PublishedMaintenancePredecessorManifestPath,$PublishedMaintenanceArchiveBindings)
    $script:capturedPublishedMaintenanceArchiveBindings = $PublishedMaintenanceArchiveBindings
    [pscustomobject]@{status='controlled'}
  }
  $null = Invoke-MIR42NineTargetEvidenceReconciliation -RepoRoot $repo -CandidateManifestPath 'controlled.json' -PredecessorZips $directArchiveBindings -UpgradeReceipts $directArchiveBindings -OutputRoot (Join-Path $repo 'build/test-results/controlled') -PublishedMaintenancePredecessorManifestPath 'controlled-published.json' -PublishedMaintenanceArchiveBindings $directArchiveBindings
  Assert-MIR42NineGeneratorTest -Condition ($script:capturedPublishedMaintenanceArchiveBindings -is [System.Collections.IDictionary] -and $script:capturedPublishedMaintenanceArchiveBindings.Count -eq $directArchiveBindings.Count) -Code 'maintenance-direct-library-binding-forwarded'
} finally {
  Set-Item -LiteralPath Function:Read-MIR42QualificationBootstrapRecord -Value $originalReadCandidate
  Set-Item -LiteralPath Function:Invoke-MIR42EvidenceReconciliationShared -Value $originalSharedReconciliation
}
$baseEvidence = (@(& git -C $repo show '8835c01b82c26cfb7634e1727e33903c9c6a39d7:tools/mir/application/release/readiness/MIR42EvidenceReconciliation.ps1') -join "`n")
if ($LASTEXITCODE -ne 0) { throw '[mir42-nine-generator-baseline-evidence]' }
$baseIndependent = (@(& git -C $repo show '8835c01b82c26cfb7634e1727e33903c9c6a39d7:tools/mir/application/release/readiness/MIR42IndependentEvidenceRehash.ps1') -join "`n")
if ($LASTEXITCODE -ne 0) { throw '[mir42-nine-generator-baseline-independent]' }
Assert-MIR42NineGeneratorTest -Condition ((@(Get-MIR42NineGeneratorFunctionParameters -Path $evidence -SourceText $baseEvidence -Name 'Invoke-MIR42FourTargetEvidenceReconciliation') -join '|') -ceq (@(Get-MIR42NineGeneratorFunctionParameters -Path $evidence -Name 'Invoke-MIR42FourTargetEvidenceReconciliation') -join '|')) -Code 'four-evidence-parameter-parity'
Assert-MIR42NineGeneratorTest -Condition ((@(Get-MIR42NineGeneratorFunctionParameters -Path $independent -SourceText $baseIndependent -Name 'Invoke-MIR42FourTargetIndependentEvidenceRehash') -join '|') -ceq (@(Get-MIR42NineGeneratorFunctionParameters -Path $independent -Name 'Invoke-MIR42FourTargetIndependentEvidenceRehash') -join '|')) -Code 'four-independent-parameter-parity'

# Consume the upgrade reader's schema-2/schema-3 and opposing controls through
# the registered evidence-generator check, rather than leaving them standalone.
& (Join-Path $repo 'tests/release/Test-MIR42FourTargetEvidenceReconciliation.ps1') | Out-Null

Write-Output 'MIR42-NINE-TARGET-EVIDENCE-GENERATOR-PASSED scopes=4,9 historical=5 engines=0'
