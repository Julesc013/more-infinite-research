# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/assurance/Core.ps1')
. (Join-Path $repo 'tools/mir/application/assurance/DevelopmentValidation.ps1')

function Assert-MIRDevelopmentCISelection {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Message)
  if(-not $Condition) { throw $Message }
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
    assurance_policy_sha256=($Marker*64);test_catalog_sha256=('C'*64);development_epoch_sha256=('E'*64)
    selector_sha256=('F'*64);classifier_sha256=('1'*64);package_authority_sha256=('2'*64)
  }
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

$temporaryRepo=Join-Path ([IO.Path]::GetTempPath()) ('mir-development-ci-selection-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temporaryRepo|Out-Null
try {
  & git -C $temporaryRepo init -q
  & git -C $temporaryRepo config user.email 'mir-development-ci@example.invalid'
  & git -C $temporaryRepo config user.name 'MIR development CI selection test'
  & git -C $temporaryRepo config core.autocrlf false
  [IO.File]::WriteAllText((Join-Path $temporaryRepo 'tracked.txt'),"clean`n",[Text.UTF8Encoding]::new($false))
  & git -C $temporaryRepo add tracked.txt
  & git -C $temporaryRepo commit -qm 'fixture'
  [IO.File]::WriteAllText((Join-Path $temporaryRepo 'dirty.txt'),"dirty`n",[Text.UTF8Encoding]::new($false))
  $dirtyRejected=$false
  try { Assert-MIR4DevelopmentHostedCheckoutClean -RepoRoot $temporaryRepo } catch { $dirtyRejected=$_.Exception.Message -eq '[mir4-development-hosted-dirty-checkout]' }
  Assert-MIRDevelopmentCISelection -Condition $dirtyRejected -Message 'Hosted selection accepted a dirty checkout as HEAD-bound input.'
} finally {
  if(Test-Path -LiteralPath $temporaryRepo) {
    $resolvedTemporaryRepo=(Resolve-Path -LiteralPath $temporaryRepo).Path
    $temporaryRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $resolvedTemporaryRepo.StartsWith($temporaryRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Temporary dirty-checkout fixture escaped the system temporary directory.' }
    Remove-Item -LiteralPath $resolvedTemporaryRepo -Recurse -Force
  }
}

$workflow=Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/validate.yml')
$developmentWorkflowBlock=Get-MIRDevelopmentCIWorkflowJobBlock -Workflow $workflow -JobId 'development-static'
$releaseWorkflowBlock=Get-MIRDevelopmentCIWorkflowJobBlock -Workflow $workflow -JobId 'verification-gate'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('name: MIR / development-static-gate') -Message 'Development workflow gate has no distinct name.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('hosted-development-affected') -Message 'Development workflow does not bind the affected-static selection mode.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('github.event.pull_request.base.sha') -Message 'Pull-request base identity is absent from the development selection.'
Assert-MIRDevelopmentCISelection -Condition $developmentWorkflowBlock.Contains('github.event.before') -Message 'Push baseline identity is absent from the development selection.'
Assert-MIRDevelopmentCISelection -Condition (-not $developmentWorkflowBlock.Contains('name: verification-gate')) -Message 'Development static evaluator reuses the release gate name.'
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
Write-Host '[ok] development CI selects affected static checks by exact baseline/event/tree/mode identity, escalates unknown paths within development scope, and keeps its gate distinct from release readiness.'
