param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/ExecutableTestAuthority.ps1')
. (Join-Path $repo 'tools/mir/application/tooling/TestWorkflowCatalogues.ps1')

function Assert-MIR4TestWorkflowConvergenceV1([bool]$Condition,[string]$Code) {
  if (-not $Condition) { throw "[$Code]" }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$projection = Update-MIR4ExecutableTestAuthorityProjectionsV1 -RepoRoot $repo -Check
$tests = Update-MIR4ToolingCatalogueV1 -RepoRoot $repo -Catalogue tests -Check
$workflows = Update-MIR4ToolingCatalogueV1 -RepoRoot $repo -Catalogue workflows -Check
$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check

Assert-MIR4TestWorkflowConvergenceV1 ([string]$projection.canonical_root -ceq 'tests' -and @($projection.compatibility_forwarders).Count -eq 3) 'mir4-m42-01b-test-authority'
Assert-MIR4TestWorkflowConvergenceV1 ([int]$tests.summary.compatibility_selected -eq 0 -and [int]$tests.summary.duplicate_test_ids -eq 0) 'mir4-m42-01b-test-catalogue'
Assert-MIR4TestWorkflowConvergenceV1 ((@($tests.tests | Where-Object canonical_implementation -match '^validation/tests/')).Count -eq 0) 'mir4-m42-01b-compatibility-selected'
Assert-MIR4TestWorkflowConvergenceV1 (($workflows.public_purposes -join ',') -ceq 'ci,qualification,release,nightly,governance') 'mir4-m42-01b-workflow-purposes'
Assert-MIR4TestWorkflowConvergenceV1 (-not [bool]$workflows.summary.publisher_can_build -and [int]$workflows.summary.release_phase_public_cli_routes -eq 9) 'mir4-m42-01b-workflow-boundaries'
Assert-MIR4TestWorkflowConvergenceV1 ([int]$inventory.summary.unknown -eq 0 -and [int]$inventory.summary.duplicate_command_keys -eq 0) 'mir4-m42-01b-command-inventory'

$canonicalMoved = @(Get-ChildItem -LiteralPath (Join-Path $repo 'tests') -File -Filter '*.ps1' -Recurse | Where-Object {
  (Get-Content -LiteralPath $_.FullName -TotalCount 1) -ceq '# MIR4-CANONICAL-EXECUTABLE-TEST'
})
$postConvergenceDecompositions = @(Get-ChildItem -LiteralPath (Join-Path $repo 'releases/migrations') -File -Filter 'MIR4-M42-02-*-DecompositionV1.json')
$postConvergenceCharacterizations = @(Get-ChildItem -LiteralPath (Join-Path $repo 'releases/migrations') -File -Filter 'MIR4-M42-02-*-CharacterizationV1.json')
Assert-MIR4TestWorkflowConvergenceV1 ($canonicalMoved.Count -eq (137 + $postConvergenceDecompositions.Count + $postConvergenceCharacterizations.Count)) 'mir4-m42-01b-relocation-count'
Assert-MIR4TestWorkflowConvergenceV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-m42-01b-package-mutation'

$receiptPath = Join-Path $repo 'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json'
if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100
  Assert-MIR4TestWorkflowConvergenceV1 ([string]$receipt.status -ceq 'M42-01-TOOLING-TEST-WORKFLOW-CONVERGENCE-COMPLETE') 'mir4-m42-01b-receipt'
  Assert-MIR4TestWorkflowConvergenceV1 (@($receipt.relocated_bindings).Count -eq 137) 'mir4-m42-01b-receipt-relocations'
}

[pscustomobject][ordered]@{
  status='M42-01-TOOLING-TEST-WORKFLOW-CONVERGENCE-PASSED'
  registered_tests=[int]$tests.test_count
  canonical_relocations=$canonicalMoved.Count
  workflows=[int]$workflows.workflow_count
  public_purposes=@($workflows.public_purposes)
  publisher_can_build=$false
  package_source_sha256=$packageBefore
  package_visible=$false
  release_transition_authority=$false
}
