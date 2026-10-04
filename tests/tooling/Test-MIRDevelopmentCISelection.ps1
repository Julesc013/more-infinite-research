# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,[switch]$PureSelectionOnly)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/assurance/Core.ps1')
. (Join-Path $repo 'tools/mir/application/assurance/DevelopmentValidation.ps1')
$selectionAssertions=0

function Assert-MIRDevelopmentCISelection {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Message)
  if(-not $Condition) { throw $Message }
  $script:selectionAssertions++
}

function New-MIRDevelopmentSelectionRow {
  param([string]$Id,[string[]]$Inputs=@())
  return [pscustomobject]@{id=$Id;kind='static';requires_factorio=$false;inputs=$Inputs;command='./tests/tooling/Test-MIRDevelopmentCISelection.ps1'}
}

function Get-MIRDevelopmentCIWorkflowJobBlock {
  param([Parameter(Mandatory)][string]$Workflow,[Parameter(Mandatory)][string]$JobId)
  $match=[regex]::Match($Workflow,"(?ms)^  $([regex]::Escape($JobId)):\r?\n(?<body>.*?)(?=^  [a-z][a-z0-9-]+:\r?\n|\z)")
  if(-not $match.Success) { throw "Workflow job is missing: $JobId" }
  return [string]$match.Value
}

function New-MIRDevelopmentIdentityInputHashes {
  param([string]$Marker='D')
  return [ordered]@{
    assurance_policy_sha256=($Marker*64);test_catalog_sha256=('C'*64);test_catalog_canonical_sha256=('A'*64);development_epoch_sha256=('E'*64)
    selector_sha256=('F'*64);classifier_sha256=('1'*64);package_authority_sha256=('2'*64)
  }
}

function New-MIRDevelopmentCanonicalCoverageSelection {
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR4DevelopmentCISelectionV1';mode='hosted-development-affected';event_name='pull_request'
    baseline=('a'*40);baseline_state='resolved';source_commit=('b'*40);source_tree=('c'*40);package_source_sha256=('D'*64)
    input_hashes=(New-MIRDevelopmentIdentityInputHashes);classification=[pscustomobject]@{paths=@('source/prototypes/example.lua');classes=@('compiler-data-stage');tests=@('static.compiler');unknown_paths=@();escalated=$false}
    tests=@('static.compiler','static.package');selection_identity=('E'*64);evaluator='MIR4-development-static-selector-v1';trust_scope='hosted-development-authoring'
    release_qualification=$false;release_readiness_gate=$false;reuse_allowed=$false
  }
}

function New-MIRDevelopmentCanonicalCoveragePlan {
  return [pscustomobject][ordered]@{
    schema=4;profile='mir4-development';baseline=('a'*40);source_commit=('b'*40);source_tree=('c'*40);package_source_sha256=('D'*64)
    test_catalog_sha256=('A'*64);catalog_sha256=('A'*64)
    classification=[pscustomobject]@{paths=@('source/prototypes/example.lua');classes=@('compiler-data-stage');tests=@('static.compiler');unknown_paths=@();escalated=$false}
    expected_test_ids=@('static.compiler','static.package','static.unrelated')
  }
}

function Copy-MIRDevelopmentCanonicalCoverageFixture {
  param([Parameter(Mandatory)]$Value)
  return ($Value|ConvertTo-Json -Depth 20|ConvertFrom-Json)
}

function Assert-MIRDevelopmentCanonicalCoverageRejected {
  param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Code,[Parameter(Mandatory)][string]$Message)
  $rejected=$false
  try { & $Action } catch { $rejected=$_.Exception.Message.StartsWith($Code,[StringComparison]::Ordinal) }
  Assert-MIRDevelopmentCISelection -Condition $rejected -Message $Message
}

$profileIds=@('static.contracts','static.compiler','static.package','static.historical','static.docs')
$catalog=[pscustomobject]@{tests=@(
  (New-MIRDevelopmentSelectionRow -Id 'static.contracts' -Inputs @('governance/repository/development-epoch-v1.json')),
  (New-MIRDevelopmentSelectionRow -Id 'static.compiler' -Inputs @('source/prototypes/**')),
  (New-MIRDevelopmentSelectionRow -Id 'static.package' -Inputs @('source/package-source.json')),
  (New-MIRDevelopmentSelectionRow -Id 'static.historical' -Inputs @('.mir/releases/**','releases/migrations/**')),
  (New-MIRDevelopmentSelectionRow -Id 'static.docs' -Inputs @('docs/**'))
)}
$assurance=[pscustomobject]@{
  profiles=[pscustomobject]@{'mir4-development'=$profileIds}
  classes=@(
    [pscustomobject]@{id='compiler-data-stage';patterns=@('^source/prototypes/');tests=@('static.compiler','static.package')},
    [pscustomobject]@{id='release-governance';patterns=@('^\.mir/releases/');tests=@('static.package','static.release-history')},
    [pscustomobject]@{id='documentation';patterns=@('^docs/');tests=@('static.docs')}
  )
  unknown_policy=[pscustomobject]@{tests=@('static.contracts')}
}

Assert-MIRDevelopmentCISelection -Condition (Test-MIR4DevelopmentCatalogInputMatch -Path 'source/prototypes/mir/runtime/research_browser.lua' -CatalogInput 'source/prototypes/**') -Message 'Recursive source input does not match its child path.'
Assert-MIRDevelopmentCISelection -Condition (-not (Test-MIR4DevelopmentCatalogInputMatch -Path 'source/prototypes/mir/runtime/research_browser.lua' -CatalogInput 'package-source')) -Message 'Symbolic catalog input must not be treated as a filename glob.'

$compilerPaths=@('source/prototypes/mir/runtime/research_browser.lua')
$compilerClassification=Get-MIRAssuranceClassification -Paths $compilerPaths -Config $assurance
$compilerRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $compilerClassification -Catalog $catalog -Assurance $assurance -Profile 'mir4-development')
Assert-MIRDevelopmentCISelection -Condition ((@($compilerRows|ForEach-Object id)-join ',') -ceq 'static.compiler,static.package') -Message 'Known compiler change must choose only its class-bound static compiler and package checks.'

$historicalPaths=@('.mir/releases/waves/mir4-r0/receipt.json')
$historicalClassification=Get-MIRAssuranceClassification -Paths $historicalPaths -Config $assurance
$historicalRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $historicalClassification -Catalog $catalog -Assurance $assurance -Profile 'mir4-development')
$historicalIds=@($historicalRows|ForEach-Object id)
Assert-MIRDevelopmentCISelection -Condition ($historicalIds -contains 'static.historical') -Message 'Historical path change must retain its development historical-baseline check.'
Assert-MIRDevelopmentCISelection -Condition ($historicalIds -contains 'static.package') -Message 'Historical path change must retain its package check.'

$actualCatalog=Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/tests.yml')|ConvertFrom-Json
$actualAssurance=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/assurance.json')|ConvertFrom-Json
$nineTargetPaths=@('tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
$nineTargetClassification=Get-MIRAssuranceClassification -Paths $nineTargetPaths -Config $actualAssurance
$nineTargetRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $nineTargetClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
$nineTargetExpected=@(
  'static.mir42-nine-target-evidence-generators',
  'static.mir42-nine-target-entrypoint-scope',
  'static.mir42-nine-target-seal-readers',
  'static.mir42-nine-target-release-authority',
  'static.mir42-nine-target-promotion',
  'static.mir42-nine-target-release-assets'
)|Sort-Object
foreach($requiredId in $nineTargetExpected) {
  Assert-MIRDevelopmentCISelection -Condition ((@($nineTargetRows|ForEach-Object id)) -contains $requiredId) -Message "Nine-target release source omitted classified development static check: $requiredId"
}

$workflowProjectionClassification=Get-MIRAssuranceClassification -Paths @('governance/automation/mir4-workflow-purposes-v1.json') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $workflowProjectionClassification.escalated) -Message 'The generated workflow-purpose projection is missing its canonical CI classification.'
$workflowProjectionRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $workflowProjectionClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
Assert-MIRDevelopmentCISelection -Condition ((@($workflowProjectionRows|ForEach-Object id)) -contains 'static.mir4-development-ci-selection') -Message 'Workflow-purpose projection change omitted the development CI selection check.'
$unknownWorkflowProjectionClassification=Get-MIRAssuranceClassification -Paths @('governance/automation/unowned-workflow-purpose.json') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition $unknownWorkflowProjectionClassification.escalated -Message 'The exact workflow projection mapping admitted an unrelated authority.'

$unknownPaths=@('unowned/new-authority.txt')
$nativeProbeClassification=Get-MIRAssuranceClassification -Paths @('tools/lib/validation/NativeProbeResources.ps1','tests/tooling/Test-MIRNativeProbeResources.ps1') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $nativeProbeClassification.escalated -and 'static.immutable-input-staging' -in $nativeProbeClassification.tests -and 'runtime.material-route-guard' -in $nativeProbeClassification.tests) -Message 'Native probe adapters lack exact static and native test ownership.'
$unknownProbeClassification=Get-MIRAssuranceClassification -Paths @('tools/lib/validation/UnownedNativeProbeResources.ps1') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition $unknownProbeClassification.escalated -Message 'Native probe classification admitted an unrelated helper.'
$targetProfileClassification=Get-MIRAssuranceClassification -Paths @('tools/lib/validation/TargetProfiles.ps1') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $targetProfileClassification.escalated -and 'static.compiler' -in $targetProfileClassification.tests -and 'runtime.affected' -in $targetProfileClassification.tests) -Message 'Target-profile authority reader lacks exact compiler and native impact ownership.'
$unknownTargetProfileClassification=Get-MIRAssuranceClassification -Paths @('tools/lib/validation/UnownedTargetProfiles.ps1') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition $unknownTargetProfileClassification.escalated -Message 'Target-profile ownership admitted an unrelated helper.'
$unknownClassification=Get-MIRAssuranceClassification -Paths $unknownPaths -Config $assurance
Assert-MIRDevelopmentCISelection -Condition $unknownClassification.escalated -Message 'Unknown path did not escalate.'
$unknownRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $unknownClassification -Catalog $catalog -Assurance $assurance -Profile 'mir4-development')
Assert-MIRDevelopmentCISelection -Condition ((@($unknownRows|ForEach-Object id)-join ',') -ceq (($profileIds|Sort-Object)-join ',')) -Message 'Unknown path must select the complete development-static profile.'
Assert-MIRDevelopmentCISelection -Condition ((@($unknownRows|Where-Object {$_.requires_factorio}).Count) -eq 0) -Message 'Development selector must not turn unknown hosted authoring into a runtime/release qualification.'

$identityInputs=New-MIRDevelopmentIdentityInputHashes
$identityA=Get-MIR4DevelopmentSelectionIdentity -Mode 'hosted-development-affected' -EventName 'pull_request' -Baseline ('a'*40) -SourceCommit ('b'*40) -SourceTree ('c'*40) -PackageSourceSha256 ('D'*64) -InputHashes $identityInputs -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
$identitySame=Get-MIR4DevelopmentSelectionIdentity -Mode 'hosted-development-affected' -EventName 'pull_request' -Baseline ('a'*40) -SourceCommit ('b'*40) -SourceTree ('c'*40) -PackageSourceSha256 ('D'*64) -InputHashes $identityInputs -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
$identityPush=Get-MIR4DevelopmentSelectionIdentity -Mode 'hosted-development-affected' -EventName 'push' -Baseline ('a'*40) -SourceCommit ('b'*40) -SourceTree ('c'*40) -PackageSourceSha256 ('D'*64) -InputHashes $identityInputs -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
$identityMergedTree=Get-MIR4DevelopmentSelectionIdentity -Mode 'hosted-development-affected' -EventName 'pull_request' -Baseline ('a'*40) -SourceCommit ('b'*40) -SourceTree ('e'*40) -PackageSourceSha256 ('D'*64) -InputHashes $identityInputs -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
$identityDifferentBaseline=Get-MIR4DevelopmentSelectionIdentity -Mode 'hosted-development-affected' -EventName 'pull_request' -Baseline ('f'*40) -SourceCommit ('b'*40) -SourceTree ('c'*40) -PackageSourceSha256 ('D'*64) -InputHashes $identityInputs -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
$identityLocalMode=Get-MIR4DevelopmentSelectionIdentity -Mode 'local-current-profile' -EventName 'pull_request' -Baseline ('a'*40) -SourceCommit ('b'*40) -SourceTree ('c'*40) -PackageSourceSha256 ('D'*64) -InputHashes $identityInputs -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
$identityDifferentCatalog=Get-MIR4DevelopmentSelectionIdentity -Mode 'hosted-development-affected' -EventName 'pull_request' -Baseline ('a'*40) -SourceCommit ('b'*40) -SourceTree ('c'*40) -PackageSourceSha256 ('D'*64) -InputHashes (New-MIRDevelopmentIdentityInputHashes -Marker '9') -Paths $compilerPaths -TestIds @($compilerRows|ForEach-Object id)
Assert-MIRDevelopmentCISelection -Condition ($identityA -ceq $identitySame) -Message 'Equivalent development selection identity changed.'
Assert-MIRDevelopmentCISelection -Condition ($identityA -cne $identityPush) -Message 'Event identity was omitted from development selection identity.'
Assert-MIRDevelopmentCISelection -Condition ($identityA -cne $identityMergedTree) -Message 'Merged-content tree identity was omitted from development selection identity.'
Assert-MIRDevelopmentCISelection -Condition ($identityA -cne $identityDifferentBaseline) -Message 'Baseline identity was omitted from development selection identity.'
Assert-MIRDevelopmentCISelection -Condition ($identityA -cne $identityLocalMode) -Message 'Selection mode was omitted from development selection identity.'
Assert-MIRDevelopmentCISelection -Condition ($identityA -cne $identityDifferentCatalog) -Message 'Catalog or policy input identity was omitted from development selection identity.'

$coverageSelection=New-MIRDevelopmentCanonicalCoverageSelection
$coveragePlan=New-MIRDevelopmentCanonicalCoveragePlan
$affectedSelection=Copy-MIRDevelopmentCanonicalCoverageFixture $coverageSelection
$affectedSelection.classification.tests=@('static.compiler','static.package')
$initialAffectedPlan=Get-MIR4DevelopmentInitialPlanProfile -Selection $affectedSelection
Assert-MIRDevelopmentCISelection -Condition ($initialAffectedPlan.profile -ceq 'auto' -and $initialAffectedPlan.use_baseline -and $initialAffectedPlan.use_affected_selection -and $initialAffectedPlan.selection_rows_covered_by_auto) -Message 'Known baseline-bound development selection did not reduce to its automatic affected plan.'
$uncoveredStaticSelection=Copy-MIRDevelopmentCanonicalCoverageFixture $affectedSelection
$uncoveredStaticSelection.tests=@('static.compiler','static.package','static.unrelated')
$uncoveredStaticPlan=Get-MIR4DevelopmentInitialPlanProfile -Selection $uncoveredStaticSelection
Assert-MIRDevelopmentCISelection -Condition ($uncoveredStaticPlan.profile -ceq 'mir4-development' -and -not $uncoveredStaticPlan.use_affected_selection -and -not $uncoveredStaticPlan.selection_rows_covered_by_auto) -Message 'Development planning accepted an automatic plan that omitted a selected static row.'
$escalatedSelection=Copy-MIRDevelopmentCanonicalCoverageFixture $affectedSelection
$escalatedSelection.classification.escalated=$true
$escalatedPlan=Get-MIR4DevelopmentInitialPlanProfile -Selection $escalatedSelection
Assert-MIRDevelopmentCISelection -Condition ($escalatedPlan.profile -ceq 'mir4-development' -and -not $escalatedPlan.use_affected_selection) -Message 'Escalated development selection was reduced to an affected plan.'
$unavailableBaselineSelection=Copy-MIRDevelopmentCanonicalCoverageFixture $affectedSelection
$unavailableBaselineSelection.baseline='';$unavailableBaselineSelection.baseline_state='unavailable'
$unavailableBaselinePlan=Get-MIR4DevelopmentInitialPlanProfile -Selection $unavailableBaselineSelection
Assert-MIRDevelopmentCISelection -Condition ($unavailableBaselinePlan.profile -ceq 'mir4-development' -and -not $unavailableBaselinePlan.use_baseline -and -not $unavailableBaselinePlan.use_affected_selection) -Message 'Development planning accepted an unavailable baseline for affected selection.'
$coverage=Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $coveragePlan -CanonicalGateResult 'success'
Assert-MIRDevelopmentCISelection -Condition ($coverage.status -ceq 'covered-by-successful-canonical-verification-gate' -and $coverage.canonical_gate_job -ceq 'verification-gate' -and $coverage.canonical_gate_result -ceq 'success') -Message 'Development coverage did not record the successful canonical gate disposition.'
Assert-MIRDevelopmentCISelection -Condition ($coverage.plan_profile -ceq 'mir4-development') -Message 'Full development coverage did not preserve its plan profile.'
Assert-MIRDevelopmentCISelection -Condition ($coverage.per_test_executions -eq 0 -and @($coverage.executed_test_ids).Count -eq 0) -Message 'Development coverage claimed per-test execution outside the canonical gate.'
Assert-MIRDevelopmentCISelection -Condition (-not $coverage.release_qualification -and -not $coverage.release_readiness_gate -and -not $coverage.reuse_allowed) -Message 'Development coverage gained release, readiness, or reuse authority.'
Assert-MIRDevelopmentCISelection -Condition ($coverage.test_catalog_raw_sha256 -cne $coverage.test_catalog_canonical_sha256 -and $coverage.test_catalog_canonical_sha256 -ceq ('A'*64)) -Message 'Canonical plan coverage did not preserve distinct raw and canonical catalogue identities.'
$rawOrderedSelection=[ordered]@{
  schema=1;kind='MIR4DevelopmentCISelectionV1';mode='hosted-development-affected';event_name='pull_request'
  baseline=('a'*40);baseline_state='resolved';source_commit=('b'*40);source_tree=('c'*40);package_source_sha256=('D'*64)
  input_hashes=[ordered]@{assurance_policy_sha256=('D'*64);test_catalog_sha256=('C'*64);test_catalog_canonical_sha256=('A'*64);development_epoch_sha256=('E'*64);selector_sha256=('F'*64);classifier_sha256=('1'*64);package_authority_sha256=('2'*64)}
  classification=[ordered]@{paths=@('source/prototypes/example.lua');classes=@('compiler-data-stage');tests=@('static.compiler');unknown_paths=@();escalated=$false}
  tests=@('static.compiler','static.package');selection_identity=('E'*64);evaluator='MIR4-development-static-selector-v1';trust_scope='hosted-development-authoring'
  release_qualification=$false;release_readiness_gate=$false;reuse_allowed=$false
}
$rawOrderedCoverage=Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $rawOrderedSelection -Plan $coveragePlan -CanonicalGateResult 'success'
Assert-MIRDevelopmentCISelection -Condition ($rawOrderedCoverage.status -ceq 'covered-by-successful-canonical-verification-gate' -and $rawOrderedCoverage.per_test_executions -eq 0) -Message 'Canonical coverage did not accept the raw ordered selector shape returned by production.'
$autoCoveragePlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan
$autoCoveragePlan.profile='auto'
$autoCoveragePlan.classification.tests=@('static.compiler','static.package')
$autoCoverage=Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $affectedSelection -Plan $autoCoveragePlan -CanonicalGateResult 'success'
Assert-MIRDevelopmentCISelection -Condition ($autoCoverage.plan_profile -ceq 'auto' -and $autoCoverage.selected_test_ids.Count -eq 2) -Message 'Affected automatic coverage did not retain the exact selected static rows.'
$autoMissingClassificationPlan=Copy-MIRDevelopmentCanonicalCoverageFixture $autoCoveragePlan
$autoMissingClassificationPlan.classification.paths=@('source/prototypes/other.lua')
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $affectedSelection -Plan $autoMissingClassificationPlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-classification-paths]' -Message 'Affected automatic coverage accepted another classified change set.'
$autoWrongBaselinePlan=Copy-MIRDevelopmentCanonicalCoverageFixture $autoCoveragePlan
$autoWrongBaselinePlan.baseline=('f'*40)
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $affectedSelection -Plan $autoWrongBaselinePlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-baseline]' -Message 'Affected automatic coverage accepted another baseline.'
$autoEscalatedPlan=Copy-MIRDevelopmentCanonicalCoverageFixture $autoCoveragePlan
$autoEscalatedPlan.classification.escalated=$true
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $affectedSelection -Plan $autoEscalatedPlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-classification-escalated]' -Message 'Affected automatic coverage accepted an escalated classification.'
$wrongSourcePlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan;$wrongSourcePlan.source_commit=('d'*40)
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $wrongSourcePlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-source_commit]' -Message 'Canonical coverage accepted a plan with another source commit.'
$wrongPackagePlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan;$wrongPackagePlan.package_source_sha256=('F'*64)
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $wrongPackagePlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-package-source]' -Message 'Canonical coverage accepted another package-source hash.'
$wrongCatalogPlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan;$wrongCatalogPlan.test_catalog_sha256=('F'*64);$wrongCatalogPlan.catalog_sha256=('F'*64)
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $wrongCatalogPlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-catalog]' -Message 'Canonical coverage accepted another test catalogue.'
$wrongProfilePlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan;$wrongProfilePlan.profile='fast'
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $wrongProfilePlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-profile]' -Message 'Canonical coverage accepted a non-development profile.'
$missingSelectedPlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan;$missingSelectedPlan.expected_test_ids=@('static.compiler')
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $missingSelectedPlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-coverage]' -Message 'Canonical coverage accepted a missing selected static test.'
$caseMismatchedPlan=Copy-MIRDevelopmentCanonicalCoverageFixture $coveragePlan;$caseMismatchedPlan.expected_test_ids=@('static.Compiler','static.package')
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $caseMismatchedPlan -CanonicalGateResult 'success' } -Code '[mir4-development-canonical-plan-coverage]' -Message 'Canonical coverage accepted a case-mismatched selected static test.'
Assert-MIRDevelopmentCanonicalCoverageRejected -Action { Assert-MIR4DevelopmentCanonicalPlanCoverage -Selection $coverageSelection -Plan $coveragePlan -CanonicalGateResult 'failure' } -Code '[mir4-development-canonical-gate]' -Message 'Development coverage accepted an unsuccessful canonical gate.'

if($PureSelectionOnly) {
  [pscustomobject]@{status='passed';assertions=$selectionAssertions;scope='Pure classifier, selector identity and canonical coverage fixtures';native_factorio=$false;checkout_fixture_created=$false}
  return
}
. (Join-Path $repo 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
$temporaryRoot=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $repo 'build/tmp')
$temporaryRepo=Resolve-MIR441RecoveryScratchPath -Path (Join-Path $temporaryRoot ('mir-development-ci-selection-'+[guid]::NewGuid().ToString('N')))
$expectedTemporaryRepo=$temporaryRepo
New-Item -ItemType Directory -Force -Path $temporaryRepo|Out-Null
try {
  & git -C $temporaryRepo init -q
  & git -C $temporaryRepo config user.email 'mir-development-ci@example.invalid'
  & git -C $temporaryRepo config user.name 'MIR development CI selection test'
  & git -C $temporaryRepo config core.autocrlf false
  [IO.File]::WriteAllText((Join-Path $temporaryRepo 'tracked.txt'),"clean`n",[Text.UTF8Encoding]::new($false))
  & git -C $temporaryRepo add tracked.txt
  & git -C $temporaryRepo commit -qm 'fixture'
  $cleanCommit=(& git -C $temporaryRepo rev-parse HEAD).Trim()
  [IO.File]::WriteAllText((Join-Path $temporaryRepo 'tracked.txt'),"trailing `n",[Text.UTF8Encoding]::new($false))
  & git -C $temporaryRepo add tracked.txt
  & git -C $temporaryRepo commit -qm 'committed whitespace fixture'
  $whitespaceCommit=(& git -C $temporaryRepo rev-parse HEAD).Trim()
  Assert-MIR4DevelopmentHostedCheckoutClean -RepoRoot $temporaryRepo
  Assert-MIRDevelopmentCanonicalCoverageRejected -Action {
    Assert-MIR4DevelopmentWhitespace -RepoRoot $temporaryRepo -SourceCommit $whitespaceCommit -Baseline $cleanCommit
  } -Code '[mir4-development-whitespace]' -Message 'Committed whitespace was accepted because the worktree was clean.'
  [IO.File]::WriteAllText((Join-Path $temporaryRepo 'tracked.txt'),"corrected`n",[Text.UTF8Encoding]::new($false))
  & git -C $temporaryRepo add tracked.txt
  & git -C $temporaryRepo commit -qm 'corrected whitespace fixture'
  $correctedCommit=(& git -C $temporaryRepo rev-parse HEAD).Trim()
  $whitespace=Assert-MIR4DevelopmentWhitespace -RepoRoot $temporaryRepo -SourceCommit $correctedCommit -Baseline $whitespaceCommit
  Assert-MIRDevelopmentCISelection -Condition ($whitespace.status -eq 'passed' -and $whitespace.scope -eq 'baseline-merge-base-to-source-commit' -and $whitespace.per_test_executions -eq 0) -Message 'Corrected committed range failed the cheap whitespace check.'
  $withoutBaseline=Assert-MIR4DevelopmentWhitespace -RepoRoot $temporaryRepo -SourceCommit $correctedCommit -Baseline ''
  Assert-MIRDevelopmentCISelection -Condition ($withoutBaseline.scope -eq 'working-tree-only-baseline-unavailable') -Message 'Missing baseline gained committed-range whitespace coverage.'
  [IO.File]::WriteAllText((Join-Path $temporaryRepo 'dirty.txt'),"dirty`n",[Text.UTF8Encoding]::new($false))
  $dirtyRejected=$false
  try { Assert-MIR4DevelopmentHostedCheckoutClean -RepoRoot $temporaryRepo } catch { $dirtyRejected=$_.Exception.Message -eq '[mir4-development-hosted-dirty-checkout]' }
  Assert-MIRDevelopmentCISelection -Condition $dirtyRejected -Message 'Hosted selection accepted a dirty checkout as HEAD-bound input.'
} finally {
  if(Test-Path -LiteralPath $temporaryRepo) {
    $resolvedTemporaryRepo=Resolve-MIR441RecoveryScratchPath -Path $temporaryRepo
    if(-not $resolvedTemporaryRepo.Equals($expectedTemporaryRepo,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Split-Path -Parent $resolvedTemporaryRepo).Equals($temporaryRoot,[StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolvedTemporaryRepo) -cnotmatch '^mir-development-ci-selection-[0-9a-f]{32}$') {
      throw 'Dirty-checkout fixture does not match its allocated project scratch path.'
    }
    Remove-Item -LiteralPath $resolvedTemporaryRepo -Recurse -Force
  }
}

$workflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/validate.yml')
$planWorkflowBlock=Get-MIRDevelopmentCIWorkflowJobBlock -Workflow $workflow -JobId 'plan'
$developmentWorkflowBlock=Get-MIRDevelopmentCIWorkflowJobBlock -Workflow $workflow -JobId 'development-static'
$releaseWorkflowBlock=Get-MIRDevelopmentCIWorkflowJobBlock -Workflow $workflow -JobId 'verification-gate'
Assert-MIRDevelopmentCISelection -Condition $planWorkflowBlock.Contains('Get-MIR4DevelopmentCISelection') -Message 'Development affected selection is not evaluated before verification-plan materialization.'
Assert-MIRDevelopmentCISelection -Condition $planWorkflowBlock.Contains('--profile'', $profile, ''--baseline'', $baseline') -Message 'Development affected verification plans do not bind their exact baseline.'
Assert-MIRDevelopmentCISelection -Condition $planWorkflowBlock.Contains('Get-MIR4DevelopmentInitialPlanProfile') -Message 'Development planning does not use the bounded affected-plan selector.'
Assert-MIRDevelopmentCISelection -Condition $planWorkflowBlock.Contains('[bool]$planning.use_baseline') -Message 'Development planning does not retain full-profile fallback for an unavailable baseline.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('name: MIR / development-static-gate') -Message 'Development workflow gate has no distinct name.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('Invoke-MIR4DevelopmentCanonicalCoverage') -Message 'Development workflow does not bind affected-static coverage to the canonical gate.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('github.event.pull_request.base.sha') -Message 'Pull-request base identity is absent from the development selection.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('github.event.before') -Message 'Push baseline identity is absent from the development selection.'
Assert-MIRDevelopmentCISelection -Condition (-not $developmentWorkflowBlock.Contains('name: verification-gate')) -Message 'Development static evaluator reuses the release gate name.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('needs:') -Message 'Development coverage does not depend on the canonical plan and gate.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('needs.verification-gate.result == ''success''') -Message 'Development coverage can run without a successful canonical verification gate.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('needs.plan.outputs.plan_artifact') -Message 'Development coverage does not consume the exact canonical plan artifact.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('Invoke-MIR4DevelopmentCanonicalCoverage') -Message 'Development workflow does not use the canonical coverage evaluator.'
Assert-MIRDevelopmentCISelection -Condition (-not $developmentWorkflowBlock.Contains('Invoke-MIR4DevelopmentStaticChecks')) -Message 'Development workflow independently re-executes canonical static checks.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('-CanonicalGateResult ''${{ needs.verification-gate.result }}''') -Message 'Development coverage does not bind the canonical gate result.'
Assert-MIRDevelopmentCISelection -Condition $releaseWorkflowBlock.Contains('name: verification-gate') -Message 'Main/release verification gate name changed.'
Assert-MIRDevelopmentCISelection -Condition $releaseWorkflowBlock.Contains('needs:') -Message 'Main/release verification gate no longer consumes the original plan and worker jobs.'
Assert-MIRDevelopmentCISelection -Condition (-not $releaseWorkflowBlock.Contains('refs/heads/dev')) -Message 'Required verification gate excludes development events while the current protection policy still requires it.'
Assert-MIRDevelopmentCISelection -Condition $releaseWorkflowBlock.Contains('always() && needs.plan.result == ''success''') -Message 'Required verification gate no longer evaluates the selected plan on development and release events.'
Assert-MIRDevelopmentCISelection -Condition (-not $releaseWorkflowBlock.Contains('DevelopmentValidation.ps1')) -Message 'Main/release verification gate was routed through the development static evaluator.'
$localSelection=Get-MIR4DevelopmentCISelection -RepoRoot $repo -Mode local-current-profile
Assert-MIRDevelopmentCISelection -Condition ($localSelection.trust_scope -ceq 'local-development-authoring') -Message 'Local development selection claimed a hosted trust context.'
Assert-MIRDevelopmentCISelection -Condition (-not $localSelection.release_qualification -and -not $localSelection.release_readiness_gate -and -not $localSelection.reuse_allowed) -Message 'Local selection gained release or reusable authority.'
& (Join-Path $repo 'tools/mir.ps1') mir4 tooling workflows-check | Out-Null
if($LASTEXITCODE -ne 0) { throw 'Generated workflow-purpose authority does not match the workflow.' }
Write-Host '[ok] development CI selects affected static checks before planning by exact baseline/event/tree/mode identity, uses automatic planning only when it covers every selected static row, retains full escalation and canonical coverage without per-test replay, and keeps its gate distinct from release readiness.'
