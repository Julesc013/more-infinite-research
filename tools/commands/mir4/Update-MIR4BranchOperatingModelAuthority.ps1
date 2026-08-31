[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$outputRelative = 'releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-branch-operating-model-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json'
$predecessorSha256 = '40B660FED308DB5A947D4CCF126AC3A4A2B32A8F0182CEF52003A6950F911C3F'
$snapshotRelative = 'releases/governance/mir4-ruleset-snapshot-2026-08-31.json'
$snapshotSchemaRelative = 'spec/schemas/mir4-ruleset-snapshot-v1.schema.json'
$expectedPackageSource = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration -IncludeF210QualificationPolicyEvolution -IncludeFinalMileToolingEvolution -IncludeFinalReleaseClosureEvolution -IncludePostReleasePackageBaselineEvolution -IncludePostReleaseAutomationCutover
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) {
  throw '[mir4-branch-operating-model-predecessor]'
}
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackageSource) {
  throw '[mir4-branch-operating-model-package-source]'
}

$snapshotPath = Join-Path $RepoRoot $snapshotRelative
$snapshotText = [IO.File]::ReadAllText($snapshotPath)
if (-not ($snapshotText | Test-Json -SchemaFile (Join-Path $RepoRoot $snapshotSchemaRelative))) {
  throw '[mir4-branch-operating-model-ruleset-snapshot-schema]'
}
$snapshot = $snapshotText | ConvertFrom-Json -Depth 50 -DateKind String
$rulesetNames = @($snapshot.rulesets.name | Sort-Object)
if (($rulesetNames -join '|') -cne 'MIR 4.0 maintenance integrity|MIR dev integration integrity|MIR main stable integrity' -or
    @($snapshot.rulesets | Where-Object { @($_.bypass_actors).Count -ne 0 -or [string]$_.current_user_can_bypass -cne 'never' }).Count -ne 0 -or
    @($snapshot.rulesets | Where-Object { 'required_linear_history' -notin @($_.rule_types) -or 'pull_request' -notin @($_.rule_types) }).Count -ne 0) {
  throw '[mir4-branch-operating-model-ruleset-snapshot-policy]'
}

$evolvedRoles = [ordered]@{
  'AGENTS.md' = 'Replace exact-tree mirror completion guidance with branch-local readback and explicit cross-lane dispositions.'
  'CONTRIBUTING.md' = 'Route latest-stable corrections to main and next-minor or next-major development to dev.'
  'docs/maintainer/mir4-release-operations.md' = 'Separate stable patch freeze from dev release freeze and exact qualified promotion.'
}
$evolved = [Collections.Generic.List[object]]::new()
foreach ($entry in $evolvedRoles.GetEnumerator()) {
  $path = [string]$entry.Key
  if (-not $state.authority_hashes.ContainsKey($path)) { throw "[mir4-branch-operating-model-unbound] $path" }
  $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
  $currentSha = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot $path) -Mode $mode
  $previousSha = [string]$state.authority_hashes[$path]
  if ($currentSha -ceq $previousSha) { throw "[mir4-branch-operating-model-unchanged] $path" }
  $evolved.Add([ordered]@{
    path=$path
    previous_sha256=$previousSha
    current_sha256=$currentSha
    reason=[string]$entry.Value
    scope='package-excluded-branch-governance'
    package_visible=$false
    release_authority=$false
  })
}

$currentRoles = [ordered]@{
  '.mir/branches.yml' = 'branch-routing-authority'
  'docs/releases/mir4-post-4.0-roadmap.md' = 'human-operating-programme-view'
  'spec/programmes/mir4-4x-operating-programme-v1.json' = 'machine-operating-programme-authority'
  'validation/tests/release/Test-MIRBranchPolicy.ps1' = 'branch-routing-static-gate'
  'spec/schemas/mir4-ruleset-snapshot-v1.schema.json' = 'remote-ruleset-readback-contract'
  'contracts/repository/mir4-branch-operating-model-authority-evolution-v1.schema.json' = 'branch-authority-evolution-contract'
  'tools/commands/mir4/Update-MIR4BranchOperatingModelAuthority.ps1' = 'bounded-branch-authority-writer'
  'releases/governance/mir4-ruleset-snapshot-2026-08-31.json' = 'remote-ruleset-application-readback'
}
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $currentRoles.GetEnumerator()) {
  $path = [string]$entry.Key
  if ($state.authority_hashes.ContainsKey($path)) { throw "[mir4-branch-operating-model-current-already-bound] $path" }
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-branch-operating-model-missing] $path" }
  $current.Add([ordered]@{
    path=$path
    sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1')
    hash_mode='canonical-text-v1'
    role=[string]$entry.Value
  })
}

$outputPath = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-branch-operating-model-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$snapshotCanonicalSha = Get-MIR4PreFreezeFileSha256 -Path $snapshotPath -Mode 'canonical-text-v1'
$receipt = [ordered]@{
  schema=1
  kind='MIR4BranchOperatingModelAuthorityEvolutionV1'
  recorded_at=$RecordedAt
  programme_id='M41-06-BRANCH-OPERATING-MODEL'
  change_id='MIR4-BRANCH-OPERATING-MODEL-2026-08-31'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='main';commit='831daa2552f7f3c4820f7fcad24653da15995b7b';tree='250c9846299782a711862895fe97803bcfb5b816'}
  evolved_bindings=@($evolved)
  current_authorities=@($current)
  remote_ruleset_snapshot=[ordered]@{path=$snapshotRelative;sha256=$snapshotCanonicalSha;hash_mode='canonical-text-v1';captured_at=[string]$snapshot.captured_at;authoritative_for_remote_current_state=$false}
  player_package_source_sha256=$expectedPackageSource
  package_visible_delta=@()
  invariants=[ordered]@{main_latest_stable=$true;dev_next_release_integration=$true;release_4_0_maintenance=$true;pull_requests_required=$true;linear_history_required=$true;ordinary_bypass_actor_count=0;package_source_unchanged=$true;gameplay_difference_authorized=$false}
  transition_gate=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;production_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
  status='BRANCH-OPERATING-MODEL-APPLIED-NO-RELEASE-TRANSITION'
}
$json = (($receipt | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n", "`n") -cne $json) { throw '[mir4-branch-operating-model-receipt-stale]' }
} else {
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath))
  [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) {
  throw '[mir4-branch-operating-model-receipt-schema]'
}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$expectedPackageSource}
