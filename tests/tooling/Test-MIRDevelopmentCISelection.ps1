# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,[switch]$PureSelectionOnly,[switch]$SdkRepairOnly)
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

. (Join-Path $repo 'tests/support/MIRSdkGenerationRepairControls.ps1')
if($SdkRepairOnly){
  if($PureSelectionOnly){throw 'Select only one focused CI control mode'}
  Test-MIRSdkGenerationRepairControls -RepoRoot $repo
  return
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
$currentEnginePaths=@(
  '.mir/control/MIR4-F210-Current-Engine-Cap-Harness-AdmissionV3.json',
  'spec/engines/mir4-factorio-2.1-experimental-channel-v1.json',
  'spec/schemas/mir4-f210-current-engine-cap-harness-admission-v3.schema.json',
  'tools/commands/mir4/Update-MIR4F210CurrentQualificationPolicyV2Authority.ps1',
  'tools/mir/application/release/F210QualificationPolicy.ps1',
  'tests/mir4/Test-MIR4F210QualificationPolicy.ps1',
  'tests/mir4/Test-MIR4Factorio21ExperimentalChannel.ps1'
)
foreach($currentEnginePath in $currentEnginePaths) {
  $currentEngineClassification=Get-MIRAssuranceClassification -Paths @($currentEnginePath) -Config $actualAssurance
  Assert-MIRDevelopmentCISelection -Condition (-not $currentEngineClassification.escalated) -Message "Current engine input must not request an unknown native campaign: $currentEnginePath"
  $currentEngineRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $currentEngineClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
  foreach($required in @('static.mir4-f210-qualification-policy','static.mir4-factorio-2.1-experimental-channel')) {
    Assert-MIRDevelopmentCISelection -Condition ($required -in @($currentEngineRows.id)) -Message "Current engine input lost its actual static consumer ${required}: $currentEnginePath"
  }
  Assert-MIRDevelopmentCISelection -Condition (@($currentEngineRows|Where-Object requires_factorio).Count -eq 0) -Message 'Hosted engine-admission checks must work without installed engines or a candidate archive.'
  $currentEngineSelection=New-MIRDevelopmentCanonicalCoverageSelection
  $currentEngineSelection.classification=$currentEngineClassification
  $currentEngineSelection.tests=@($currentEngineRows.id)
  $currentEnginePlan=Get-MIR4DevelopmentInitialPlanProfile -Selection $currentEngineSelection
  if(@($currentEngineClassification.tests|Where-Object {$_ -notin $currentEngineSelection.tests}).Count -gt 0 -or
     @($currentEngineSelection.tests|Where-Object {$_ -notin $currentEngineClassification.tests}).Count -gt 0) {
    Assert-MIRDevelopmentCISelection -Condition ($currentEnginePlan.profile -ceq 'mir4-development') -Message 'Mixed native/static or additional catalog selections must retain the complete hosted static plan.'
  } else {
    Assert-MIRDevelopmentCISelection -Condition ($currentEnginePlan.profile -ceq 'auto') -Message 'Fully covered engine checks should use the affected static plan.'
  }
}
$unknownEngineClassification=Get-MIRAssuranceClassification -Paths @('spec/engines/unreviewed-engine.json') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition ($unknownEngineClassification.escalated -and 'runtime.full' -in @($unknownEngineClassification.tests)) -Message 'Exact engine-admission mapping must retain conservative escalation for unreviewed engine authorities.'
$performancePaths=@('tools/lib/validation/ResearchAllPerformance.ps1','fixtures/performance-regression-probe/research-all.lua','fixtures/run-profiles/research-all-f210.json')
$performanceClassification=Get-MIRAssuranceClassification -Paths $performancePaths -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $performanceClassification.escalated -and 'static.research-all-observation' -in @($performanceClassification.tests) -and 'runtime.research-all-observation-f200' -in @($performanceClassification.tests) -and 'runtime.research-all-observation-f210' -in @($performanceClassification.tests)) -Message 'The performance consumer must retain its exact static and native selections without unknown-path escalation.'
$performanceRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $performanceClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
Assert-MIRDevelopmentCISelection -Condition ('static.research-all-observation' -in @($performanceRows.id) -and @($performanceRows|Where-Object requires_factorio).Count -eq 0) -Message 'Hosted performance selection must consume its actual source check without native execution.'
$unknownPerformance=Get-MIRAssuranceClassification -Paths @('tools/lib/validation/UnregisteredPerformanceProbe.ps1') -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition ($unknownPerformance.escalated -and 'runtime.full' -in @($unknownPerformance.tests)) -Message 'Exact performance mapping must not exempt unknown native tooling.'
$labPath='tests/compiler/lab_reachability.lua'
$labClassification=Get-MIRAssuranceClassification -Paths @($labPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $labClassification.escalated -and
  'mir4-science-route-feasibility' -in @($labClassification.classes)) -Message 'The consumed lab fixture is missing its existing acquisition classification.'
Assert-MIRDevelopmentCISelection -Condition ('runtime.researchability-planning-contract' -in @($labClassification.tests) -and
  'static.compiler' -in @($labClassification.tests) -and 'static.architecture' -in @($labClassification.tests)) -Message 'Lab fixture selection lost its actual consumer or source checks.'
$labConsumer=@($actualCatalog.tests|Where-Object id -CEQ 'runtime.researchability-planning-contract')
Assert-MIRDevelopmentCISelection -Condition ($labConsumer.Count -eq 1 -and
  $labPath -in @($labConsumer[0].inputs) -and $labConsumer[0].requires_factorio -eq $true) -Message 'The real native runner must declare its lab input and retain its native execution boundary.'
$impactPath=Join-Path $repo '.mir/test-impact.yml'
$labImpact=Get-MIRAssuranceImpactSelection -Paths @($labPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $labImpact.requires_full -and
  $labPath -in @($labImpact.mapped_paths) -and 'science-prerequisites' -in @($labImpact.groups) -and
  'generated-prerequisite-safety' -in @($labImpact.scenarios) -and 'k2-science-phase-policy' -in @($labImpact.scenarios)) -Message 'The known lab fixture must retain its affected science scenarios without an unrelated full-profile fallback.'
$unknownLabPath='tests/compiler/unowned_lab_reachability.lua'
$unknownLabClassification=Get-MIRAssuranceClassification -Paths @($unknownLabPath) -Config $actualAssurance
$unknownLabImpact=Get-MIRAssuranceImpactSelection -Paths @($unknownLabPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition ('static.full' -in @($unknownLabClassification.tests) -and
  'mir4-science-route-feasibility' -notin @($unknownLabClassification.classes) -and
  $unknownLabImpact.requires_full -and $unknownLabPath -in @($unknownLabImpact.unmapped_runtime_paths)) -Message 'An unknown lab fixture must retain conservative full coverage; the exact mapping is not a wildcard exemption.'
$epochPath='tests/compiler/recipe_source_epoch.lua'
$epochClassification=Get-MIRAssuranceClassification -Paths @($epochPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $epochClassification.escalated -and
  'mir4-science-route-feasibility' -in @($epochClassification.classes) -and
  'runtime.recipe-source-epoch-contract' -in @($epochClassification.tests)) -Message 'The source-epoch fixture lost its exact existing acquisition consumer.'
$epochConsumer=@($actualCatalog.tests|Where-Object id -CEQ 'runtime.recipe-source-epoch-contract')
Assert-MIRDevelopmentCISelection -Condition ($epochConsumer.Count -eq 1 -and
  $epochPath -in @($epochConsumer[0].inputs) -and $epochConsumer[0].requires_factorio -eq $true) -Message 'The source-epoch native runner must retain its declared fixture and execution boundary.'
$epochImpact=Get-MIRAssuranceImpactSelection -Paths @($epochPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $epochImpact.requires_full -and
  $epochPath -in @($epochImpact.mapped_paths) -and 'science-prerequisites' -in @($epochImpact.groups) -and
  'generated-prerequisite-safety' -in @($epochImpact.scenarios) -and 'k2-science-phase-policy' -in @($epochImpact.scenarios)) -Message 'The consumed source-epoch fixture must select affected science scenarios without unrelated profile replay.'
$unknownEpochPath='tests/compiler/unowned_recipe_source_epoch.lua'
$unknownEpochImpact=Get-MIRAssuranceImpactSelection -Paths @($unknownEpochPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition ($unknownEpochImpact.requires_full -and
  $unknownEpochPath -in @($unknownEpochImpact.unmapped_runtime_paths)) -Message 'An unowned epoch fixture must retain full coverage; the mapping is exact.'
$selectorPath='tests/tooling/Test-MIRDevelopmentCISelection.ps1'
$selectorConsumer=@($actualCatalog.tests|Where-Object id -CEQ 'static.mir4-development-ci-selection')
Assert-MIRDevelopmentCISelection -Condition ($selectorConsumer.Count -eq 1 -and
  $selectorPath -in @($selectorConsumer[0].inputs) -and $selectorConsumer[0].requires_factorio -eq $false) -Message 'The selector self-test must retain its actual static consumer and execution boundary.'
$selectorImpact=Get-MIRAssuranceImpactSelection -Paths @($selectorPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition (-not $selectorImpact.requires_full -and
  $selectorPath -in @($selectorImpact.mapped_paths) -and @($selectorImpact.groups).Count -eq 0) -Message 'The known static selector test must not trigger unrelated native profile replay.'
$unknownSelectorPath='tests/tooling/Test-MIRUnownedDevelopmentCISelection.ps1'
$unknownSelectorImpact=Get-MIRAssuranceImpactSelection -Paths @($unknownSelectorPath) -Config $actualAssurance
Assert-MIRDevelopmentCISelection -Condition ($unknownSelectorImpact.requires_full -and
  $unknownSelectorPath -in @($unknownSelectorImpact.unmapped_runtime_paths)) -Message 'The selector mapping must not exempt unrelated tooling scripts from conservative impact selection.'
foreach ($constructionPath in @(
  'tools/mir/application/release/readiness/MIR42CandidateBuild.ps1',
  'tools/mir/application/package/TargetMaterializer.ps1',
  'spec/schemas/mir42-four-target-deterministic-candidate-manifest-v2.schema.json',
  'source/package-source.json',
  'targets/package-authority.json'
)) {
  $constructionClassification=Get-MIRAssuranceClassification -Paths @($constructionPath) -Config $actualAssurance
  $constructionRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $constructionClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
  Assert-MIRDevelopmentCISelection -Condition ((@($constructionRows|ForEach-Object id)) -contains 'static.mir42-candidate-construction') -Message "Candidate construction change omitted its executable development check: $constructionPath"
}
$nineTargetPaths=@('tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
foreach($historicalInputPath in @('tests/runtime/Test-MIR4HistoricalPrivateRuntime.ps1','tests/runtime/Test-MIR4HistoricalPrivateRuntimeStatic.ps1','tests/release/Test-MIR4DistributionCustodyRoutes.ps1','tools/mir/cli/router/MIR4BootstrapCommands.ps1')){
  $historicalInputClassification=Get-MIRAssuranceClassification -Paths @($historicalInputPath) -Config $actualAssurance
  $historicalInputRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $historicalInputClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
  Assert-MIRDevelopmentCISelection -Condition (-not $historicalInputClassification.escalated -and 'static.mir4-historical-runtime-inputs' -in @($historicalInputRows.id) -and 'static.mir4-distribution-custody-routes' -in @($historicalInputRows.id)) -Message "Historical input change omitted its consumed checks: $historicalInputPath"
}
foreach($migrationPath in @('tests/runtime/Test-MIR42V2V3CapMigration.ps1','tests/runtime/Test-MIR42V2V3CapMigrationStatic.ps1','tools/mir/application/package/HistoricalSourceAuthority.ps1')){
  $migrationClassification=Get-MIRAssuranceClassification -Paths @($migrationPath) -Config $actualAssurance
  $migrationRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $migrationClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
  Assert-MIRDevelopmentCISelection -Condition (-not $migrationClassification.escalated -and 'static.f210-v2-v3-migration-inputs' -in @($migrationRows.id)) -Message "V2/V3 input change omitted its executable regression check: $migrationPath"
}
foreach($enginePath in @('tools/commands/release/Invoke-MIR42FourTargetEngineRun.ps1','tests/release/Test-MIR42NineTargetHistoricalEngineRun.ps1')){
  $engineClassification=Get-MIRAssuranceClassification -Paths @($enginePath) -Config $actualAssurance
  $engineRows=@(Select-MIR4DevelopmentAffectedStaticRows -Classification $engineClassification -Catalog $actualCatalog -Assurance $actualAssurance -Profile 'mir4-development')
  Assert-MIRDevelopmentCISelection -Condition (-not $engineClassification.escalated -and 'static.mir42-nine-target-engine-inputs' -in @($engineRows.id)) -Message "Nine-target engine change omitted its executable regression check: $enginePath"
}
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
foreach($extra in @('runtime.affected','runtime.full','static.unselected')) {
  $mixedSelection=Copy-MIRDevelopmentCanonicalCoverageFixture $affectedSelection
  $mixedSelection.classification.tests+=@($extra)
  $mixedPlan=Get-MIR4DevelopmentInitialPlanProfile -Selection $mixedSelection
  Assert-MIRDevelopmentCISelection -Condition ($mixedPlan.profile -ceq 'mir4-development' -and $mixedPlan.use_baseline -and -not $mixedPlan.use_affected_selection) -Message ('Hosted planning admitted an unselected automatic row: '+$extra)
}
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
Test-MIRSdkGenerationRepairControls -RepoRoot $repo
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
