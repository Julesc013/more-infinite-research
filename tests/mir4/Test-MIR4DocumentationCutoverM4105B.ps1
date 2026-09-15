# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')

function Assert-MIR4DocumentationCutover([bool]$Condition,[string]$Code) {
  if (-not $Condition) { throw "[$Code]" }
}

& (Join-Path $RepoRoot 'tools/commands/docs/Update-MIRPipelineDocumentation.ps1') -RepoRoot $RepoRoot -Check
& (Join-Path $RepoRoot 'tools/commands/docs/Update-MIRREADMEStreamDefaults.ps1') -RepoRoot $RepoRoot -Check
& (Join-Path $RepoRoot 'tools/commands/docs/Update-MIRDocumentationIndex.ps1') -RepoRoot $RepoRoot -Check | Out-Null
$workflowConvergencePath = Join-Path $RepoRoot 'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json'
if (Test-Path -LiteralPath $workflowConvergencePath -PathType Leaf) {
  $workflowConvergenceText = Get-Content -Raw -LiteralPath $workflowConvergencePath
  Assert-MIR4DocumentationCutover ($workflowConvergenceText | Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-m42-01b-test-workflow-convergence-v1.schema.json')) 'mir4-m41-05b-workflow-successor-schema'
  $workflowConvergence = $workflowConvergenceText | ConvertFrom-Json -Depth 100
  Assert-MIR4DocumentationCutover (Test-MIR4BootstrapRecordHash -Record $workflowConvergence) 'mir4-m41-05b-workflow-successor-record'
  $documentationTestRelocation = @($workflowConvergence.relocated_bindings | Where-Object {
    [string]$_.from_path -ceq 'validation/tests/mir4/Test-MIR4DocumentationContinuityT14.ps1' -and
    [string]$_.to_path -ceq 'tests/mir4/Test-MIR4DocumentationContinuityT14.ps1'
  })
  Assert-MIR4DocumentationCutover ($documentationTestRelocation.Count -eq 1) 'mir4-m41-05b-workflow-successor-relocation'
} else {
  & (Join-Path $RepoRoot 'tools/commands/mir4/Update-MIR4M4105BDocumentationCutoverAuthority.ps1') -RepoRoot $RepoRoot -Check | Out-Null
}

$readmePath = Join-Path $RepoRoot 'README.md'
$readme = [IO.File]::ReadAllText($readmePath)
# The maintainer requires the detailed README to remain intact. The historical
# cutover separated package documentation; its byte limit and landing-page shape
# are not a continuing license to discard the repository reference.
foreach ($heading in @('Development research browser','Player behavior','Install and upgrade','Repository and branches','Stable player plane reference','Cost Model','Science Packs and Labs','Generated Prototype Names','Research Catalog','Startup Settings','Compatibility Specification','Developer Specification','Validation and Release Workflow','Documentation Map','Troubleshooting','Save Compatibility')) {
  Assert-MIR4DocumentationCutover ($readme.Contains("## $heading")) "mir4-readme-section-$($heading.ToLowerInvariant().Replace(' ','-'))"
}
foreach ($badge in @('Mod downloads','Latest release','Last updated','Issues','Validate')) {
  Assert-MIR4DocumentationCutover ($readme.Contains("[![$badge]")) 'mir4-readme-badges-preserved'
}
Assert-MIR4DocumentationCutover ($readme.Contains('Julesc013/more-infinite-research/validate.yml?branch=main')) 'mir4-readme-ci-badge'
# Versioned package claims belong to the target compositions rather than an
# accumulating list of historical release labels on the repository homepage.
$registry = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'targets/registry.json') | ConvertFrom-Json -Depth 30
Assert-MIR4DocumentationCutover ((@($registry.targets | ForEach-Object { [string]$_.target }) -join '|') -ceq 'f210|f200|f110|f100') 'mir4-readme-current-targets'
# Both reference writers above check their README projections against the same
# generated blocks as the standalone documents, preventing a second authority.
foreach ($marker in @('PIPELINE','STREAM DEFAULTS')) {
  Assert-MIR4DocumentationCutover ($readme.Contains("BEGIN GENERATED MIR $marker")) 'mir4-readme-inline-reference'
}
Assert-MIR4DocumentationCutover ($readme.Contains('source') -and $readme.Contains('targets') -and $readme.Contains('repository root is not a player package')) 'mir4-readme-package-boundary'

$presentation = Get-MIR4CurrentPackagePresentationV3 -RepoRoot $RepoRoot
$manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'source/package-source.json') | ConvertFrom-Json -Depth 100
$files = @(Get-MIR4CanonicalPackageSourceFiles -RepoRoot $RepoRoot)
Assert-MIR4DocumentationCutover ('README.md' -notin $files) 'mir4-m41-05b-root-package-membership'
foreach ($target in @('f210','f200','f110','f100')) {
  $readme = @($manifest.bindings | Where-Object { [string]$_.source_path -ceq "source/presentation/$target/README.md.template" -and [string]$_.output_path -ceq 'README.md' })
  $changelog = @($manifest.bindings | Where-Object { [string]$_.source_path -ceq "source/presentation/$target/changelog.txt.template" -and [string]$_.output_path -ceq 'changelog.txt' })
  Assert-MIR4DocumentationCutover ($readme.Count -eq 1 -and $changelog.Count -eq 1) 'mir4-m41-05b-current-presentation-binding'
}
Assert-MIR4DocumentationCutover ([string]$presentation.package_source.fingerprint_sha256 -ceq (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot)) 'mir4-m41-05b-current-presentation-fingerprint'
Assert-MIR4DocumentationCutover ([string]$presentation.package_source.legacy_root_state -ceq 'retired-historical-read-only') 'mir4-m41-05b-current-presentation-root-state'

$programmeText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json')
Assert-MIR4DocumentationCutover ($programmeText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-4x-operating-programme-v1.schema.json')) 'mir4-m41-05b-programme-schema'
$programme = $programmeText | ConvertFrom-Json -Depth 30
Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M41-05' -and $_.state -eq 'complete' }).Count -eq 1) 'mir4-m41-05b-programme-complete'
if (Test-Path -LiteralPath $workflowConvergencePath -PathType Leaf) {
  Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M42-01' -and $_.state -eq 'complete' }).Count -eq 1) 'mir4-m42-01-programme-complete'
  Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M42-02' -and $_.state -in @('active','complete') }).Count -eq 1) 'mir4-m42-02-programme-progress'
} else {
  Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M42-01' -and $_.state -eq 'active' }).Count -eq 1) 'mir4-m42-01-programme-active'
}

$receiptPath = Join-Path $RepoRoot 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
$receiptText = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4DocumentationCutover ($receiptText | Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-m41-05b-documentation-cutover-v1.schema.json')) 'mir4-m41-05b-receipt-schema'
$receipt = $receiptText | ConvertFrom-Json -Depth 50
Assert-MIR4DocumentationCutover (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m41-05b-receipt-hash'
# Preserve and verify the original cutover receipt against the exact historical
# README it authenticated. Later authorized documentation edits do not rewrite it.
$historicalReadme = @(& git -C $RepoRoot show 'c4597569a3a5499172d39ef814a80bbb0a9d8978:README.md')
Assert-MIR4DocumentationCutover ($LASTEXITCODE -eq 0) 'mir4-m41-05b-historical-readme-object'
$historicalReadmeSha256 = Get-MIR4Sha256String -Value (($historicalReadme -join "`n") + "`n")
Assert-MIR4DocumentationCutover ([string]$receipt.repository_landing.sha256 -ceq $historicalReadmeSha256) 'mir4-m41-05b-readme-custody'
Assert-MIR4DocumentationCutover (-not [bool]$receipt.transition_gate.version_allocation -and -not [bool]$receipt.transition_gate.tagging -and -not [bool]$receipt.transition_gate.signing -and -not [bool]$receipt.transition_gate.sealing -and -not [bool]$receipt.transition_gate.publication) 'mir4-m41-05b-release-boundary'

Write-Host '[ok] Detailed README, generated references, historical cutover custody, and current package-source preservation passed.'
