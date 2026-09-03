# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')

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
Assert-MIR4DocumentationCutover ([IO.FileInfo]::new($readmePath).Length -le 12288) 'mir4-m41-05b-readme-size'
foreach ($heading in @('Choose the right target','What MIR provides','Install or upgrade','Compatibility and safety','Diagnostics and support','Developer entry points','Contributing','Documentation and license')) {
  Assert-MIR4DocumentationCutover ($readme.Contains("## $heading")) "mir4-m41-05b-readme-$($heading.ToLowerInvariant().Replace(' ','-'))"
}
foreach ($term in @('latest installed official Factorio 2.1 experimental build','runtime API','prototype API','changelog identity','review work','4.0.21000','4.0.20000','4.0.11000','4.0.10000')) {
  Assert-MIR4DocumentationCutover ($readme.Contains($term)) 'mir4-m41-05b-current-policy'
}
Assert-MIR4DocumentationCutover ($readme -notmatch 'BEGIN GENERATED MIR (?:PIPELINE|STREAM DEFAULTS)') 'mir4-m41-05b-root-generated-catalogue'
Assert-MIR4DocumentationCutover ($readme -notmatch 'root (?:source tree|package).*authoritative|M4RC1') 'mir4-m41-05b-stale-current-authority'

$files = @(Get-MIR4CanonicalPackageSourceFiles -RepoRoot $RepoRoot)
Assert-MIR4DocumentationCutover ('README.md' -notin $files) 'mir4-m41-05b-root-package-membership'
foreach ($target in @('f210','f200','f110','f100')) {
  Assert-MIR4DocumentationCutover ("targets/$target/generation/README.md.template" -in $files) 'mir4-m41-05b-target-readme-membership'
  Assert-MIR4DocumentationCutover ("targets/$target/generation/changelog.txt.template" -in $files) 'mir4-m41-05b-target-changelog-membership'
}
$expectedPackageSourceSha256 = '632E71A660AB5DEE4C3286E21AAA348BA7162674DFB15AEEECEFEF4B2525948E'
$powerShellCharacterizationPath = Join-Path $RepoRoot 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
if (Test-Path -LiteralPath $powerShellCharacterizationPath -PathType Leaf) {
  $powerShellCharacterizationText = Get-Content -Raw -LiteralPath $powerShellCharacterizationPath
  Assert-MIR4DocumentationCutover ($powerShellCharacterizationText | Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-m42-02-powershell-characterization-v1.schema.json')) 'mir4-m41-05b-powershell-successor-schema'
  $powerShellCharacterization = $powerShellCharacterizationText | ConvertFrom-Json -Depth 100
  Assert-MIR4DocumentationCutover (Test-MIR4BootstrapRecordHash -Record $powerShellCharacterization) 'mir4-m41-05b-powershell-successor-record'
  $expectedPackageSourceSha256 = [string]$powerShellCharacterization.preservation.package_source_sha256
}
Assert-MIR4DocumentationCutover ((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot) -ceq $expectedPackageSourceSha256) 'mir4-m41-05b-package-source-stability'

$programmeText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json')
Assert-MIR4DocumentationCutover ($programmeText | Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-4x-operating-programme-v1.schema.json')) 'mir4-m41-05b-programme-schema'
$programme = $programmeText | ConvertFrom-Json -Depth 30
Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M41-05' -and $_.state -eq 'complete' }).Count -eq 1) 'mir4-m41-05b-programme-complete'
if (Test-Path -LiteralPath $workflowConvergencePath -PathType Leaf) {
  Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M42-01' -and $_.state -eq 'complete' }).Count -eq 1) 'mir4-m42-01-programme-complete'
  Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M42-02' -and $_.state -eq 'active' }).Count -eq 1) 'mir4-m42-02-programme-active'
} else {
  Assert-MIR4DocumentationCutover (@($programme.work_packages | Where-Object { $_.id -eq 'M42-01' -and $_.state -eq 'active' }).Count -eq 1) 'mir4-m42-01-programme-active'
}

$receiptPath = Join-Path $RepoRoot 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
$receiptText = Get-Content -Raw -LiteralPath $receiptPath
Assert-MIR4DocumentationCutover ($receiptText | Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-m41-05b-documentation-cutover-v1.schema.json')) 'mir4-m41-05b-receipt-schema'
$receipt = $receiptText | ConvertFrom-Json -Depth 50
Assert-MIR4DocumentationCutover (Test-MIR4BootstrapRecordHash -Record $receipt) 'mir4-m41-05b-receipt-hash'
Assert-MIR4DocumentationCutover ([string]$receipt.repository_landing.sha256 -ceq (Get-MIR4BootstrapTextSha256 -Path $readmePath)) 'mir4-m41-05b-readme-custody'
Assert-MIR4DocumentationCutover (-not [bool]$receipt.transition_gate.version_allocation -and -not [bool]$receipt.transition_gate.tagging -and -not [bool]$receipt.transition_gate.signing -and -not [bool]$receipt.transition_gate.sealing -and -not [bool]$receipt.transition_gate.publication) 'mir4-m41-05b-release-boundary'

Write-Host '[ok] M41-05B repository/package documentation cutover passed without changing accepted 4.0 package inputs.'
