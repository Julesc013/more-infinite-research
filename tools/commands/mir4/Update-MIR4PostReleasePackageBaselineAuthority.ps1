[CmdletBinding()]
param([string]$RepoRoot = '', [string]$RecordedAt = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PackagePresentation.ps1')

$outputRelative = '.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json'
$schemaRelative = 'spec/schemas/mir4-post-release-package-baseline-authority-evolution-receipt-v1.schema.json'
$predecessorRelative = '.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json'
$predecessorSha256 = '008BA8DE50BF4DC1AD2A3E5190E932B62AAD247BB84E9934A28C2813B79422FB'
$baselineRelative = 'spec/distribution/mir4-package-presentation-baseline-v1.json'
$historicalPackageSource = 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'
$expectedPackageSource = '8D59F97AC6A42917A22E160E492ED94854D3D377C57D22C3FE27AE6A9C77A336'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration -IncludeF210QualificationPolicyEvolution -IncludeFinalMileToolingEvolution -IncludeFinalReleaseClosureEvolution
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) { throw '[mir4-post-release-package-baseline-writer-predecessor]' }
$packageSource = Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if ($packageSource -cne $expectedPackageSource -or (Get-MIR4CurrentPackageSourceSha256 -RepoRoot $RepoRoot) -cne $expectedPackageSource) { throw "[mir4-post-release-package-baseline-writer-package-source] expected=$expectedPackageSource actual=$packageSource" }

$roles = [ordered]@{
  'README.md' = 'package-visible-readme-presentation'
  '.github/workflows/branch-policy.yml' = 'post-release-branch-policy-workflow'
  '.github/workflows/validate.yml' = 'post-release-validation-workflow'
  '.mir/assurance.json' = 'post-release-assurance-routing'
  '.mir/control/paths.yml' = 'current-path-registry'
  '.mir/docs.yml' = 'post-release-documentation-registry'
  '.mir/modules.yml' = 'current-module-boundary'
  'AGENTS.md' = 'post-release-agent-guidance'
  'CONTRIBUTING.md' = 'post-release-contributor-guidance'
  'GOVERNANCE.md' = 'post-release-governance-guidance'
  'docs/architecture/module-boundaries.md' = 'package-baseline-boundary-documentation'
  'docs/maintainer/mir4-release-operations.md' = 'post-release-operations-guidance'
  'docs/reference/generated/documentation-index.md' = 'post-release-documentation-index'
  'docs/reference/generated/documentation-navigation.md' = 'post-release-documentation-navigation'
  'docs/reference/generated/documentation-owner-dashboard.md' = 'post-release-documentation-owner-dashboard'
  'docs/reference/generated/documentation-reference-matrix.md' = 'post-release-documentation-reference-matrix'
  'docs/reference/generated/documentation-review-age.md' = 'post-release-documentation-review-age'
  'mir.lock' = 'regenerated-platform-input-lock'
  'sdk/preview/mir4/reference/compilation-runs.json' = 'regenerated-compilation-run-projection'
  'sdk/preview/mir4/reference/continuity-bundle-template.json' = 'regenerated-continuity-bundle-projection'
  'sdk/preview/mir4/reference/inspection-bundle-v1.json' = 'regenerated-inspection-bundle-projection'
  'sdk/preview/mir4/reference/inspector-workbench-result-v1.json' = 'regenerated-inspector-workbench-projection'
  'sdk/preview/mir4/reference/merge-law-catalogue.json' = 'regenerated-merge-law-projection'
  'sdk/preview/mir4/reference/migration-graph-matrix.json' = 'regenerated-migration-graph-projection'
  'sdk/preview/mir4/reference/query-snapshot-f210.json' = 'regenerated-query-snapshot-projection'
  'tools/lib/mir4/PackagePresentation.ps1' = 'current-package-presentation-reader'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 'append-only-authority-chain-reader'
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1' = 'repository-current-package-baseline-gate'
  'tools/lib/assurance/Evidence.ps1' = 'post-release-assurance-evidence-reader'
  'tools/lib/assurance/Release.ps1' = 'post-release-assurance-release-reader'
  'tools/lib/mir4/ReleaseLifecycleAdapters.ps1' = 'post-release-lifecycle-adapter'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1' = 'post-release-authority-chain-gate'
  'validation/tests/mir4/Test-MIR4ReleaseAdaptersT05.ps1' = 'post-release-release-adapter-gate'
  'validation/tests/mir4/Test-MIR4ReleaseCapsule.ps1' = 'release-capsule-current-package-gate'
  'validation/tests/mir4/Test-MIR4RunnerPublisherConfinement.ps1' = 'runner-current-package-gate'
  'validation/tests/mir4/Test-MIR4SigningCeremonyPreparation.ps1' = 'signing-preparation-current-package-gate'
  'validation/tests/mir4/Test-MIR4SupplyChainAttestation.ps1' = 'supply-chain-attestation-current-package-gate'
  'validation/tests/mir4/Test-MIR4SupplyChainFoundation.ps1' = 'supply-chain-current-package-gate'
  'validation/tests.yml' = 'post-release-test-catalogue'
  'spec/distribution/mir4-package-presentation-baseline-v1.json' = 'current-package-presentation-baseline'
  'spec/schemas/mir4-package-presentation-baseline-v1.schema.json' = 'current-package-presentation-baseline-schema'
  'spec/schemas/mir4-post-release-package-baseline-authority-evolution-receipt-v1.schema.json' = 'post-release-package-baseline-evolution-schema'
  'tools/commands/mir4/Update-MIR4PostReleasePackageBaselineAuthority.ps1' = 'post-release-package-baseline-evolution-writer'
}

$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $roles.GetEnumerator()) {
  $path = [string]$entry.Key
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-post-release-package-baseline-writer-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $actual = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previous = [string]$state.authority_hashes[$path]
    if ($actual -cne $previous) {
      $isReadme = $path -ceq 'README.md'
      $evolved.Add([ordered]@{path=$path;previous_sha256=$previous;current_sha256=$actual;reason=$(if($isReadme){'Record the exact post-release CI badge presentation delta already merged through PR #203.'}else{'Admit the package-presentation successor authority and regenerate its package-excluded readers, checks, and projections.'});scope=$(if($isReadme){'package-presentation'}else{'package-excluded-control-plane'});package_visible=$isReadme;release_authority=$false})
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role=[string]$entry.Value})
  }
}
$visible = @($evolved | Where-Object { [bool]$_.package_visible })
if ($visible.Count -ne 1 -or [string]$visible[0].path -cne 'README.md') { throw '[mir4-post-release-package-baseline-writer-visible-delta]' }
if ($evolved.Count -lt 12 -or $current.Count -lt 4) { throw "[mir4-post-release-package-baseline-writer-authority-set] evolved=$($evolved.Count) current=$($current.Count)" }

$baselinePath = Join-Path $RepoRoot $baselineRelative
$baselineText = [IO.File]::ReadAllText($baselinePath).Replace("`r`n", "`n").Replace("`r", "`n")
$baselineBytes = [Text.UTF8Encoding]::new($false).GetBytes($baselineText)
$baseline = [ordered]@{path=$baselineRelative;bytes=$baselineBytes.Length;sha256=(Get-MIR4PreFreezeFileSha256 -Path $baselinePath -Mode 'canonical-text-v1')}
$output = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw '[mir4-post-release-package-baseline-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema=1;kind='MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1';recorded_at=$RecordedAt
  programme_id='M41-00-POST-RELEASE-RECONCILIATION';change_id='MIR4-POST-RELEASE-PACKAGE-BASELINE-2026-08-31'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256};baseline_authority=$baseline
  evolved_bindings=@($evolved);current_authorities=@($current);historical_package_source_sha256=$historicalPackageSource;player_package_source_sha256=$packageSource;package_visible_delta=@('README.md')
  invariants=[ordered]@{player_executable_sources_unchanged=$true;one_emitter_preserved=$true;gameplay_difference_authorized=$false}
  transition_gate=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;production_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
  status='POST-RELEASE-PACKAGE-PRESENTATION-BASELINE-RECORDED-NO-RELEASE-TRANSITION'
}
$text = (($receipt | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n")
if ($Check) { if ([IO.File]::ReadAllText($output).Replace("`r`n", "`n") -cne $text) { throw '[mir4-post-release-package-baseline-receipt-stale]' } }
else { [IO.File]::WriteAllText($output, $text, [Text.UTF8Encoding]::new($false)) }
if (-not ((Get-Content -Raw -LiteralPath $output) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-post-release-package-baseline-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$packageSource}
