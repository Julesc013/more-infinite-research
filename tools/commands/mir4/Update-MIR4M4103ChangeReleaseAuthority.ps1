[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/ReleaseNarratives.ps1')

$outputRelative = 'releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json'
$schemaRelative = 'contracts/repository/mir4-m41-03-change-and-release-authority-evolution-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json'
$predecessorSha256 = '5C8285578229E6B35CD5A54A3665839FA4B6BCB442CFE8FB53F075C2613839BE'
$expectedPackageSource = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration -IncludeF210QualificationPolicyEvolution -IncludeFinalMileToolingEvolution -IncludeFinalReleaseClosureEvolution -IncludePostReleasePackageBaselineEvolution -IncludePostReleaseAutomationCutover -IncludePostReleaseBranchOperatingModel -IncludePostReleasePatchLaneRehearsal
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-m41-03-authority-predecessor]' }
if ((Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot) -cne $expectedPackageSource) { throw '[mir4-m41-03-authority-package-source]' }

$evolvedRoles = [ordered]@{
  '.mir/assurance.json' = 'Register the M41-03 proof and change-authority impact class.'
  '.mir/control/paths.yml' = 'Expose canonical change and release-narrative logical paths.'
  '.mir/control/repository-fixed-point.json' = 'Activate the visible changes root without moving package source.'
  '.mir/docs.yml' = 'Regenerate the documentation projection from canonical front matter.'
  '.mir/modules.yml' = 'Declare the change and release narrative module boundary.'
  'docs/architecture/module-boundaries.md' = 'Document the no-discovery and no-package-write release boundary.'
  'docs/reference/generated/documentation-navigation.md' = 'Regenerate documentation navigation for the new architecture record.'
  'docs/reference/generated/documentation-owner-dashboard.md' = 'Regenerate documentation ownership for the new architecture record.'
  'docs/releases/mir4-post-4.0-roadmap.md' = 'Record M41-03 complete and route the next fixed point.'
  'spec/programmes/mir4-4x-operating-programme-v1.json' = 'Advance the canonical machine roadmap after executable proof.'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1' = 'Advance repository fixed-point proof to the active change authority successor.'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 'Append M41-03 to the authority-chain validator.'
  'tools/mir/domain/repository/RepositoryFixedPoint.ps1' = 'Recognize the active change authority as the current repository migration successor.'
  'tools/mir.ps1' = 'Expose release narratives through the one supported command surface.'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1' = 'Require the M41-03 successor in pre-freeze regression proof.'
  'validation/tests.yml' = 'Register the M41-03 executable proof in the verification catalogue.'
}
$evolved = [Collections.Generic.List[object]]::new()
foreach ($entry in $evolvedRoles.GetEnumerator()) {
  $path = [string]$entry.Key
  if (-not $state.authority_hashes.ContainsKey($path)) { throw "[mir4-m41-03-authority-unbound] $path" }
  $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
  $currentSha = Get-MIR4PreFreezeFileSha256 -Path (Join-Path $RepoRoot $path) -Mode $mode
  $previousSha = [string]$state.authority_hashes[$path]
  if ($currentSha -ceq $previousSha) { throw "[mir4-m41-03-authority-unchanged] $path" }
  $evolved.Add([ordered]@{path=$path;previous_sha256=$previousSha;current_sha256=$currentSha;reason=[string]$entry.Value;scope='package-excluded-change-and-release-authority';package_visible=$false;release_authority=$false})
}

$currentRoles = [ordered]@{
  'changes/.mir-root.json' = 'active-change-root-projection'
  'changes/unreleased/MIR4-CHG-2026-0001.json' = 'accepted-m41-03-change-authority'
  'changes/history/4.0.0/MIR4-HIST-4000-0001.json' = 'historical-source-family-change'
  'changes/history/4.0.0/MIR4-HIST-4000-0002.json' = 'historical-upgrade-continuity-change'
  'changes/history/4.0.0/MIR4-HIST-4000-0003.json' = 'historical-assurance-change'
  'changes/history/4.0.0/MIR4-HIST-4000-0004.json' = 'historical-developer-surface-change'
  'contracts/release/mir4-change-fragment-v2.schema.json' = 'change-fragment-contract'
  'contracts/release/mir4-release-narrative-plan-v1.schema.json' = 'release-narrative-plan-contract'
  'contracts/release/mir4-release-narrative-result-v1.schema.json' = 'release-narrative-result-contract'
  'contracts/repository/mir4-m41-03-change-and-release-authority-evolution-v1.schema.json' = 'm41-03-authority-evolution-contract'
  'docs/architecture/mir4-change-and-release-authority.md' = 'change-and-release-authority-documentation'
  'docs/reference/generated/documentation-index.md' = 'generated-documentation-index-projection'
  'docs/reference/generated/documentation-review-age.md' = 'generated-documentation-review-age-projection'
  'fixtures/release/m41-03/changes/synthetic-f210-patch.json' = 'synthetic-patch-change-fixture'
  'fixtures/release/m41-03/changes/synthetic-multi-target-feature.json' = 'synthetic-multi-target-change-fixture'
  'fixtures/release/m41-03/changes/synthetic-repository-only.json' = 'synthetic-repository-only-change-fixture'
  'fixtures/release/m41-03/changes/synthetic-migration.json' = 'synthetic-migration-change-fixture'
  'fixtures/release/m41-03/changes/synthetic-embargoed-security.json' = 'synthetic-security-change-fixture'
  'fixtures/release/m41-03/changes/synthetic-target-omitted.json' = 'synthetic-target-omission-fixture'
  'fixtures/release/m41-03/plans/historical-4.0.0.json' = 'historical-shadow-render-plan'
  'fixtures/release/m41-03/plans/synthetic-f210-patch.json' = 'synthetic-patch-render-plan'
  'fixtures/release/m41-03/plans/synthetic-multi-target-minor.json' = 'synthetic-minor-render-plan'
  'tools/commands/mir4/Update-MIR4M4103ChangeReleaseAuthority.ps1' = 'bounded-m41-03-authority-writer'
  'tools/mir/application/release/ReleaseNarrativeModel.ps1' = 'release-narrative-domain-model'
  'tools/mir/application/release/SourceChangelogRenderer.ps1' = 'source-changelog-renderer'
  'tools/mir/application/release/FactorioTargetChangelogRenderer.ps1' = 'factorio-target-changelog-renderer'
  'tools/mir/application/release/GitHubReleaseRenderer.ps1' = 'github-release-renderer'
  'tools/mir/application/release/ModPortalRenderer.ps1' = 'mod-portal-renderer'
  'tools/mir/application/release/TechnicalReleaseRenderer.ps1' = 'technical-release-renderer'
  'tools/mir/application/release/ReleaseManifestChangeRenderer.ps1' = 'release-manifest-change-renderer'
  'tools/mir/application/release/ReleaseNarratives.ps1' = 'release-narrative-application-service'
  'tools/mir/cli/Invoke-MIR4ReleaseNarratives.ps1' = 'release-narrative-command-adapter'
  'validation/tests/mir4/Test-MIR4ReleaseNarrativesM4103.ps1' = 'm41-03-executable-proof'
}
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $currentRoles.GetEnumerator()) {
  $path = [string]$entry.Key
  if ($state.authority_hashes.ContainsKey($path)) { throw "[mir4-m41-03-authority-current-already-bound] $path" }
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-m41-03-authority-missing] $path" }
  $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role=[string]$entry.Value})
}

$plans = @(
  @{path='fixtures/release/m41-03/plans/historical-4.0.0.json';output='build/reports/release-rendering/authority/historical-4.0.0'},
  @{path='fixtures/release/m41-03/plans/synthetic-f210-patch.json';output='build/reports/release-rendering/authority/synthetic-patch'},
  @{path='fixtures/release/m41-03/plans/synthetic-multi-target-minor.json';output='build/reports/release-rendering/authority/synthetic-minor'}
)
$proof = [Collections.Generic.List[object]]::new()
foreach ($plan in $plans) {
  $result = Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $RepoRoot -PlanPath $plan.path -OutputRoot $plan.output -Command render
  [void](Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $RepoRoot -PlanPath $plan.path -OutputRoot $plan.output -Command check)
  $proof.Add([ordered]@{plan_id=[string]$result.plan_id;result_digest=[string]$result.result_digest;output_count=@($result.outputs).Count})
}

$outputPath = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-03-authority-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4M4103ChangeAndReleaseAuthorityEvolutionV1';recorded_at=$RecordedAt;programme_id='M41-03-CHANGE-AND-RELEASE-AUTHORITY';change_id='MIR4-CHG-2026-0001'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  base=[ordered]@{branch='dev';commit='df1774bec19173bead7a497b6134d452f2931fd0';tree='3112e36eb90c151fc57b760065b818b244217f12'}
  evolved_bindings=@($evolved);current_authorities=@($current);rendering_proof=@($proof)
  player_package_source_sha256=$expectedPackageSource;package_visible_delta=@()
  invariants=[ordered]@{one_change_authority=$true;six_views_from_one_inventory=$true;historical_4_0_0_shadow_only=$true;selective_target_filtering=$true;security_redaction=$true;factorio_format=$true;deterministic_output=$true;package_source_unchanged=$true}
  transition_gate=[ordered]@{merge=$false;tagging=$false;signing=$false;sealing=$false;version_allocation=$false;publication=$false;remote_write=$false}
  status='M41-03-CHANGE-AND-RELEASE-AUTHORITY-COMPLETE-NO-RELEASE-TRANSITION'
}
$json = (($receipt | ConvertTo-Json -Depth 40).Replace("`r`n","`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n","`n") -cne $json) { throw '[mir4-m41-03-authority-receipt-stale]' }
} else {
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath))
  [IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $outputPath) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-m41-03-authority-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$expectedPackageSource}
