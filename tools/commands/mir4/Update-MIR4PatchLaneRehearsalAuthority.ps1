[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$outputRelative = 'releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-patch-lane-rehearsal-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json'
$predecessorSha256 = 'B7EF0E539329446F6347B9A97D7F5C6F63C6E13CD1CA1C6F992C8562F50B5EFD'
$rehearsalRelative = 'releases/rehearsals/MIR4-M40-01-Patch-Lane-Rehearsal-2026-08-31.json'
$rehearsalSchemaRelative = 'contracts/release/mir4-patch-lane-rehearsal-result-v1.schema.json'
$expectedPackageSource = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration -IncludeF210QualificationPolicyEvolution -IncludeFinalMileToolingEvolution -IncludeFinalReleaseClosureEvolution -IncludePostReleasePackageBaselineEvolution -IncludePostReleaseAutomationCutover -IncludePostReleaseBranchOperatingModel
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) {
  throw '[mir4-patch-lane-authority-predecessor]'
}
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackageSource) {
  throw '[mir4-patch-lane-authority-package-source]'
}

$rehearsalPath = Join-Path $RepoRoot $rehearsalRelative
$rehearsalText = [IO.File]::ReadAllText($rehearsalPath)
if (-not ($rehearsalText | Test-Json -SchemaFile (Join-Path $RepoRoot $rehearsalSchemaRelative))) {
  throw '[mir4-patch-lane-authority-rehearsal-schema]'
}
$rehearsal = $rehearsalText | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$rehearsal.status -cne 'passed-unpublished' -or
    [string]$rehearsal.source_identity.release_4_0.commit -cne '5ca449820bdfa5595ca03686f32c74904c46daf3' -or
    @($rehearsal.target_matrix | Where-Object { [string]$_.disposition -ceq 'affected' }).Count -ne 1 -or
    @($rehearsal.target_matrix | Where-Object { [string]$_.disposition -ceq 'unchanged' }).Count -ne 3 -or
    @($rehearsal.firewall.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
  throw '[mir4-patch-lane-authority-rehearsal-result]'
}

$evolvedRoles = [ordered]@{
  '.mir/control/repository-fixed-point.json' = 'Expose the release contract and rehearsal record roots without moving player package source.'
  'docs/releases/mir4-post-4.0-roadmap.md' = 'Record the unpublished maintenance-lane proof and keep M40 active for real corrections.'
  'spec/programmes/mir4-4x-operating-programme-v1.json' = 'Correct the protected stable-to-dev convergence outcome while preserving the accepted roadmap.'
  'tools/mir.ps1' = 'Expose the typed patch-lane rehearsal through the one supported MIR command surface.'
  'validation/tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1' = 'Bind release-adapter proof to the protected PR base while retaining exact-tree detached-mirror portability.'
}
$evolved = [Collections.Generic.List[object]]::new()
foreach ($entry in $evolvedRoles.GetEnumerator()) {
  $path = [string]$entry.Key
  if (-not $state.authority_hashes.ContainsKey($path)) { throw "[mir4-patch-lane-authority-unbound] $path" }
  $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
  $currentSha = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot $path) -Mode $mode
  $previousSha = [string]$state.authority_hashes[$path]
  if ($currentSha -ceq $previousSha) { throw "[mir4-patch-lane-authority-unchanged] $path" }
  $evolved.Add([ordered]@{
    path=$path
    previous_sha256=$previousSha
    current_sha256=$currentSha
    reason=[string]$entry.Value
    scope='package-excluded-maintenance-rehearsal'
    package_visible=$false
    release_authority=$false
  })
}

$currentRoles = [ordered]@{
  '.mir/control/paths.yml' = 'logical-path-projection'
  '.mir/modules.yml' = 'module-boundary-projection'
  'contracts/.mir-root.json' = 'contract-root-marker'
  'contracts/release/mir4-change-realization-v1.schema.json' = 'change-realization-contract'
  'contracts/release/mir4-defect-record-v1.schema.json' = 'defect-record-contract'
  'contracts/release/mir4-patch-lane-rehearsal-result-v1.schema.json' = 'patch-rehearsal-result-contract'
  'contracts/repository/mir4-patch-lane-rehearsal-authority-evolution-v1.schema.json' = 'patch-rehearsal-authority-contract'
  'docs/architecture/module-boundaries.md' = 'patch-rehearsal-boundary-documentation'
  'fixtures/release/m40-01/dev-forward-integration-realization.json' = 'dev-forward-integration-fixture'
  'fixtures/release/m40-01/main-forward-port-realization.json' = 'main-forward-port-fixture'
  'fixtures/release/m40-01/stable-realization.json' = 'stable-realization-fixture'
  'fixtures/release/m40-01/synthetic-f210-defect.json' = 'synthetic-defect-fixture'
  'releases/.mir-root.json' = 'release-root-marker'
  'releases/rehearsals/MIR4-M40-01-Patch-Lane-Rehearsal-2026-08-31.json' = 'patch-rehearsal-proof-receipt'
  'tools/commands/mir4/Update-MIR4PatchLaneRehearsalAuthority.ps1' = 'bounded-patch-authority-writer'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 'append-only-authority-chain-validator'
  'tools/mir/application/release/PatchLaneRehearsal.ps1' = 'patch-rehearsal-application-service'
  'tools/mir/cli/Invoke-MIR4PatchLaneRehearsal.ps1' = 'patch-rehearsal-command-adapter'
  'validation/tests/mir4/Test-MIR4PatchLaneRehearsal.ps1' = 'patch-rehearsal-executable-proof'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1' = 'authority-chain-regression-proof'
  'validation/tests.yml' = 'verification-catalogue-projection'
}
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $currentRoles.GetEnumerator()) {
  $path = [string]$entry.Key
  if ($state.authority_hashes.ContainsKey($path)) { throw "[mir4-patch-lane-authority-current-already-bound] $path" }
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-patch-lane-authority-missing] $path" }
  $current.Add([ordered]@{
    path=$path
    sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1')
    hash_mode='canonical-text-v1'
    role=[string]$entry.Value
  })
}

$outputPath = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-patch-lane-authority-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1
  kind='MIR4PatchLaneRehearsalAuthorityEvolutionV1'
  recorded_at=$RecordedAt
  programme_id='M40-01-PATCH-LANE-REHEARSAL'
  change_id='MIR4-M40-01-PATCH-LANE-REHEARSAL-2026-08-31'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='dev';commit='74c75879246746c8533d2ef7a170aa0dc6bcbbbc';tree='3d2530f34c3937aa56a030a4b7793307ed21d6a8'}
  evolved_bindings=@($evolved)
  current_authorities=@($current)
  rehearsal_receipt=[ordered]@{path=$rehearsalRelative;sha256=(Get-MIR4PreFreezeFileSha256 -Path $rehearsalPath -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';record_digest=[string]$rehearsal.record_digest}
  player_package_source_sha256=$expectedPackageSource
  package_visible_delta=@()
  invariants=[ordered]@{release_4_0_base_exact=$true;disposable_branch_removed=$true;one_affected_target=$true;unchanged_targets_explicit=$true;semantic_forward_ports_planned=$true;remote_refs_unchanged=$true;package_source_unchanged=$true;gameplay_difference_authorized=$false}
  transition_gate=[ordered]@{merge=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='PATCH-LANE-REHEARSAL-PROVED-NO-RELEASE-TRANSITION'
}
$json = (($receipt | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-patch-lane-authority-receipt-stale]' }
} else {
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath))
  [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) {
  throw '[mir4-patch-lane-authority-receipt-schema]'
}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$expectedPackageSource}
