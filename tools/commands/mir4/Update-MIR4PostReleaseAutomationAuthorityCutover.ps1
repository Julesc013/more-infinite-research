[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$outputRelative = 'releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json'
$schemaRelative = 'contracts/repository/mir4-post-release-automation-authority-cutover-v1.schema.json'
$predecessorRelative = '.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json'
$predecessorSha256 = 'CAD8AA2A0ED6AB17E0295D8EB5FC78A0B33DD3D7D70F7F5E52EC0178A9B0B6B4'
$currentLockRelative = 'governance/automation/github-actions-lock.json'
$currentContractRelative = 'contracts/repository/mir-github-actions-lock-v1.schema.json'
$expectedPackageSource = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'

$stateArgs = @{
  RepoRoot=$RepoRoot;IncludeT17MachinePreparation=$true;IncludeRepositoryMigration=$true;IncludeCanonicalizationMigration=$true
  IncludeDiagnosticsMigration=$true;IncludeTargetKeyMigration=$true;IncludeWholePlatformMigration=$true;IncludeTechnologyAcceptanceMigration=$true
  IncludeTargetCompilerMigration=$true;IncludeSemanticCompilerPolicyMigration=$true;IncludeRuntimeContinuityMigration=$true;IncludeModuleSdkMepMigration=$true
  IncludeProcessIRExactMigration=$true;IncludeInspectorCompatibilityMigration=$true;IncludeAssuranceOfflineCustodyMigration=$true
  IncludeHistoricalToolingMigration=$true;IncludeReleaseToolingMigration=$true;IncludeF210QualificationPolicyEvolution=$true
  IncludeFinalMileToolingEvolution=$true;IncludeFinalReleaseClosureEvolution=$true;IncludePostReleasePackageBaselineEvolution=$true
}
$state = Get-MIR4PreFreezeAuthorityState @stateArgs
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) {
  throw '[mir4-post-release-automation-cutover-predecessor]'
}

$currentLockPath = Join-Path $RepoRoot $currentLockRelative
$currentContractPath = Join-Path $RepoRoot $currentContractRelative
$lockText = [IO.File]::ReadAllText($currentLockPath)
if (-not ($lockText | Test-Json -SchemaFile $currentContractPath)) { throw '[mir4-post-release-automation-cutover-lock-schema]' }
$lock = $lockText | ConvertFrom-Json -Depth 40 -DateKind String
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackageSource) { throw '[mir4-post-release-automation-cutover-package-source]' }

$registryPaths = @(
  '.mir/control/paths.yml',
  '.mir/modules.yml',
  'docs/architecture/module-boundaries.md',
  'docs/maintainer/mir4-supply-chain-preservation.md',
  'docs/reference/generated/documentation-index.md',
  'docs/reference/generated/documentation-review-age.md',
  'mir.lock',
  'sdk/preview/mir4/reference/compilation-runs.json',
  'sdk/preview/mir4/reference/inspection-bundle-v1.json',
  'sdk/preview/mir4/reference/inspector-workbench-result-v1.json',
  'sdk/preview/mir4/reference/query-snapshot-f210.json'
)
$proofPaths = @(
  'spec/schemas/mir4-runner-publisher-confinement-receipt-v1.schema.json',
  'tools/lib/mir4/PreFreezeRelease.ps1',
  'tools/lib/mir4/RunnerPublisherConfinement.ps1',
  'validation/tests.yml',
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1',
  'validation/tests/mir4/Test-MIR4RunnerPublisherConfinement.ps1'
)
$automationPaths = @($lock.repository_workflows) + @('.mir/releases/governance/mir4/github-actions-lock-v2.json')
$retirement = [Collections.Generic.List[object]]::new()
foreach ($path in @($automationPaths + $registryPaths + $proofPaths | Sort-Object -Unique)) {
  if (-not $state.authority_hashes.ContainsKey([string]$path)) { throw "[mir4-post-release-automation-cutover-unbound] $path" }
  $control = if ($path -in $automationPaths) { 'visible-action-lock-and-workflow-closure' }
    elseif ($path -in $registryPaths) { 'visible-repository-registry' }
    else { 'current-contract-and-static-proof' }
  $retirement.Add([ordered]@{
    path=[string]$path
    historical_sha256=[string]$state.authority_hashes[[string]$path]
    disposition='retired-from-current-prefreeze-byte-binding'
    current_control=$control
  })
}
if ($retirement.Count -lt 30) { throw "[mir4-post-release-automation-cutover-retirement-count] $($retirement.Count)" }

function Get-MIR4AutomationCanonicalSha256([string]$Path) {
  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($text)))
}

$outputPath = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-post-release-automation-cutover-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$record = [ordered]@{
  schema=1
  kind='MIR4PostReleaseAutomationAuthorityCutoverV1'
  recorded_at=$RecordedAt
  programme_id='M41-02-ACTION-RUNTIME-CUTOVER'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='main';commit='49ba61d1023ad155860b4fea3ce298d7c6f0775b';tree='fd7771762359ccc156bb696fae36e855fea8de4e'}
  evolved_bindings=@()
  current_authorities=@()
  retired_bindings=@($retirement)
  successor_authorities=@(
    [ordered]@{path=$currentLockRelative;sha256=(Get-MIR4AutomationCanonicalSha256 $currentLockPath);hash_mode='canonical-text-v1';role='current-github-actions-lock'},
    [ordered]@{path=$currentContractRelative;sha256=(Get-MIR4AutomationCanonicalSha256 $currentContractPath);hash_mode='canonical-text-v1';role='current-github-actions-lock-contract'}
  )
  runner_preflight=[ordered]@{host='AERO-15X-WIN10';runner_version='2.336.0';minimum_version='2.327.1';powershell_version='7.6.5';node24_compatible=$true;runner_registration_present=$false}
  invariants=[ordered]@{historical_mir_lock_immutable=$true;visible_current_authority=$true;full_sha_pins=$true;package_source_unchanged=$true;gameplay_difference_authorized=$false}
  transition_gate=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;production_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
  status='CURRENT-AUTOMATION-AUTHORITY-VISIBLE-HISTORICAL-PREFREEZE-BINDINGS-RETIRED'
}
$json = (($record | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-post-release-automation-cutover-stale]' }
} else {
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath))
  [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) {
  throw '[mir4-post-release-automation-cutover-schema]'
}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;retired_bindings=$retirement.Count;package_source_sha256=$expectedPackageSource}
