[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$RecordedAt = '',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')

$outputRelative = '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json'
$schemaRelative = 'spec/schemas/mir4-final-mile-tooling-authority-evolution-receipt-v1.schema.json'
$predecessorRelative = '.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json'
$predecessorSha256 = 'CAB840352F129A028D2BD061DAD44A29C43BEB5C39F8639C1D8B64CC1E210831'
$expectedPackageSource = 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot `
  -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration `
  -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration `
  -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration `
  -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration `
  -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration `
  -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration `
  -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration `
  -IncludeF210QualificationPolicyEvolution
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or
    [string]$state.prior_receipt_sha256 -cne $predecessorSha256) {
  throw '[mir4-final-mile-tooling-writer-predecessor] F210 policy evolution is not the exact admitted predecessor.'
}
$packageSource = Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if ($packageSource -cne $expectedPackageSource) {
  throw "[mir4-final-mile-tooling-writer-package-source] expected=$expectedPackageSource actual=$packageSource"
}

$roles = [ordered]@{
  '.github/workflows/branch-policy.yml' = 'governed-legacy-alias-controller'
  '.mir/control/paths.yml' = 'final-mile-control-path-projection'
  '.mir/docs.yml' = 'final-mile-documentation-projection'
  '.mir/modules.yml' = 'final-mile-module-boundary-authority'
  'mir.lock' = 'final-mile-platform-input-lock'
  'docs/reference/generated/documentation-index.md' = 'final-mile-generated-documentation-index'
  'docs/reference/generated/documentation-navigation.md' = 'final-mile-generated-documentation-navigation'
  'docs/reference/generated/documentation-owner-dashboard.md' = 'final-mile-generated-documentation-owner-dashboard'
  'docs/reference/generated/documentation-reference-matrix.md' = 'final-mile-generated-documentation-reference-matrix'
  'docs/reference/generated/documentation-review-age.md' = 'final-mile-generated-documentation-review-age'
  'docs/releases/mir4-4.0-publication-copy.md' = 'mir4-4.0-publication-copy'
  'docs/user/mir3-to-mir4.md' = 'mir3-to-mir4-upgrade-guide'
  'fixtures/assert-k2-science-phase-policy/data-final-fixes.lua' = 'exact-v1-v2-k2-policy-qualification-harness'
  'spec/schemas/mir4-final-mile-tooling-authority-evolution-receipt-v1.schema.json' = 'final-mile-tooling-evolution-schema'
  'scripts/Invoke-MIRReleaseTargetedGate.ps1' = 'exact-private-cross-target-release-gate'
  'sdk/preview/mir4/reference/compilation-runs.json' = 'final-mile-platform-compilation-run-projection'
  'sdk/preview/mir4/reference/inspection-bundle-v1.json' = 'final-mile-platform-inspection-bundle-projection'
  'sdk/preview/mir4/reference/inspector-workbench-result-v1.json' = 'final-mile-platform-inspector-result-projection'
  'sdk/preview/mir4/reference/query-snapshot-f210.json' = 'final-mile-platform-query-snapshot-projection'
  'tools/commands/mir4/Update-MIR4FinalMileToolingAuthority.ps1' = 'final-mile-tooling-evolution-writer'
  'tools/commands/release/Test-MIR3TerminalPromotionCandidate.ps1' = 'terminal-post-publication-sync-controller'
  'tools/lib/assurance/Release.ps1' = 'current-private-lane-assurance-planner'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 'final-mile-authority-chain-integration'
  'validation/tests.yml' = 'final-mile-test-catalogue'
  'validation/tests/mir4/Test-MIR4K2ScienceSOL06.ps1' = 'sol06-successor-authority-validator'
  'validation/tests/release/Test-MIR4LocalPlaytestShadow.ps1' = 'private-lane-planner-validator'
  'validation/tests/release/Test-MIRTerminalGovernance.ps1' = 'terminal-controller-validator'
  'validation/tests/mir4/Test-MIR4F210QualificationPolicy.ps1' = 'f210-policy-terminal-chain-validator'
}

$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $roles.GetEnumerator()) {
  $path = [string]$entry.Key
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-final-mile-tooling-writer-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $actual = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previous = [string]$state.authority_hashes[$path]
    if ($actual -cne $previous) {
      $evolved.Add([ordered]@{
        path = $path
        previous_sha256 = $previous
        current_sha256 = $actual
        reason = 'Repair the governed post-publication legacy alias controller, advance local-playtest assurance to the exact V3 authority, add exact-candidate version-aware qualification fixtures, regenerate dependent platform projections, and prepare complete release copy without granting a release transition.'
        scope = 'package-excluded-control-plane'
        package_visible = $false
        release_authority = $false
      })
    }
  } else {
    $current.Add([ordered]@{
      path = $path
      sha256 = Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1'
      hash_mode = 'canonical-text-v1'
      role = [string]$entry.Value
    })
  }
}
if ($evolved.Count -lt 5 -or $current.Count -lt 2) {
  throw "[mir4-final-mile-tooling-writer-authority-set] evolved=$($evolved.Count) current=$($current.Count)"
}

$output = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw '[mir4-final-mile-tooling-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) {
  $RecordedAt = [DateTimeOffset]::Now.ToString('o')
}

$receipt = [ordered]@{
  schema = 1
  kind = 'MIR4FinalMileToolingAuthorityEvolutionReceiptV1'
  recorded_at = $RecordedAt
  programme_id = 'M4C10-WHOLE-4X-IN-4.0'
  change_id = 'MIR4-FINAL-MILE-TOOLING-2026-08-29'
  predecessor_receipt = [ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  execution_state = [ordered]@{
    programme_status = 'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-T18-DEPENDENCY-BLOCKED-RELEASE-BLOCKED'
    t16_status = 'blocked-human'
    t17_status = 'blocked-human'
    t18_status = 'blocked-dependency'
    t19_status = 'blocked-human'
  }
  controller = [ordered]@{
    operation = 'post-publication-sync'
    destination = 'legacy'
    exact_published_main_tree_required = $true
    immutable_tag_and_release_bytes_required = $true
    non_force_fast_forward_required = $true
    controller_checkout_separate_from_candidate = $true
  }
  assurance = [ordered]@{
    local_playtest_authority_kind = 'MIR4PrivateLaneAuthorizationV3'
    v2_planning_authority_rejected = $true
    exact_target_engine_and_predecessor_required = $true
  }
  publication_copy = [ordered]@{
    path = 'docs/releases/mir4-4.0-publication-copy.md'
    status = 'prepared-pre-freeze-not-authorized'
    unresolved_fields_fail_closed = $true
    live_portal_mutation_authorized = $false
  }
  evolved_bindings = @($evolved)
  current_authorities = @($current)
  player_package_source_sha256 = $packageSource
  package_visible_delta = @()
  human_gate = [ordered]@{
    protected_signing_authorized = $false
    f210_decision_recorded = $false
    f200_decision_recorded = $false
    acceptance_inferred = $false
  }
  transition_gate = [ordered]@{
    source_freeze = $false
    candidate_allocation = $false
    production_signing = $false
    production_seal = $false
    promotion_to_main = $false
    tagging = $false
    publication = $false
  }
  status = 'FINAL-MILE-TOOLING-AND-COPY-PREPARED-RELEASE-TRANSITIONS-UNAUTHORIZED'
}

$json = $receipt | ConvertTo-Json -Depth 20
$text = $json.Replace("`r`n","`n") + "`n"
if ($Check) {
  if ([IO.File]::ReadAllText($output).Replace("`r`n","`n") -cne $text) { throw '[mir4-final-mile-tooling-receipt-stale]' }
} else {
  [IO.File]::WriteAllText($output, $text, [Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $output) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) {
  throw '[mir4-final-mile-tooling-receipt-schema]'
}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$packageSource}
