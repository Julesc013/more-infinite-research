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

$outputRelative = '.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json'
$schemaRelative = 'spec/schemas/mir4-final-release-closure-authority-evolution-receipt-v1.schema.json'
$predecessorRelative = '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json'
$predecessorSha256 = 'A51ABC8AF6A22B8122F93BF5467E3A00818B4727EEBA2799540215349FBE91C2'
$authorizationRelative = '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'
$authorizationSha256 = '7A59C83A6DBBFCD803843D49FBBCCAC6990D4C59642C361CB695239277BDA65B'
$candidateAuthorityRelative = '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json'
$candidateAuthoritySha256 = '6832C75E66EDB61BDEFE8573CE56C00CC8E88B6B79113E6764736510371443BF'
$expectedPackageSource = 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot `
  -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration `
  -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration `
  -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration `
  -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration `
  -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration `
  -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration `
  -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration `
  -IncludeF210QualificationPolicyEvolution -IncludeFinalMileToolingEvolution
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or [string]$state.prior_receipt_sha256 -cne $predecessorSha256) {
  throw '[mir4-final-release-closure-writer-predecessor]'
}
$packageSource = Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if ($packageSource -cne $expectedPackageSource) { throw "[mir4-final-release-closure-writer-package-source] expected=$expectedPackageSource actual=$packageSource" }

function Get-RawDescriptor([string]$Relative,[string]$ExpectedSha256) {
  $full = Join-Path $RepoRoot $Relative
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-final-release-closure-writer-missing] $Relative" }
  $item = Get-Item -LiteralPath $full
  $sha256 = Get-MIR4PreFreezeFileSha256 -Path $full
  if ($sha256 -cne $ExpectedSha256) { throw "[mir4-final-release-closure-writer-identity] $Relative" }
  return [ordered]@{path=$Relative;bytes=$item.Length;sha256=$sha256}
}

$authorization = Get-RawDescriptor $authorizationRelative $authorizationSha256
$candidateAuthority = Get-RawDescriptor $candidateAuthorityRelative $candidateAuthoritySha256
Get-MIR4FinalMilePlaytestCandidateAuthorityV1 -RepoRoot $RepoRoot | Out-Null

$roles = [ordered]@{
  '.mir/control/paths.yml' = 'final-release-closure-control-path-projection'
  '.mir/docs.yml' = 'final-release-closure-documentation-projection'
  '.mir/modules.yml' = 'final-release-closure-module-boundary-authority'
  'docs/reference/generated/documentation-index.md' = 'final-release-closure-documentation-index'
  'docs/reference/generated/documentation-navigation.md' = 'final-release-closure-documentation-navigation'
  'docs/reference/generated/documentation-owner-dashboard.md' = 'final-release-closure-documentation-owner-dashboard'
  'docs/reference/generated/documentation-reference-matrix.md' = 'final-release-closure-documentation-reference-matrix'
  'docs/reference/generated/documentation-review-age.md' = 'final-release-closure-documentation-review-age'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 'exact-final-mile-playtest-authority-controller'
  'validation/tests/mir4/Test-MIR4PlaytestHandoffT17.ps1' = 'exact-final-mile-playtest-authority-functional-test'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1' = 'final-release-closure-authority-chain-validator'
  '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json' = 'imported-maintainer-github-release-authorization'
  '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json' = 'exact-f210-f200-playtest-candidate-authority'
  'docs/releases/mir4-4.0-mod-portal-extended-description.md' = 'copy-only-mod-portal-extended-description'
  'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json' = 'maintainer-authorization-schema'
  'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json' = 'exact-playtest-candidate-authority-schema'
  'spec/schemas/mir4-final-release-closure-authority-evolution-receipt-v1.schema.json' = 'final-release-closure-evolution-schema'
  'tools/commands/mir4/Update-MIR4FinalReleaseClosureAuthority.ps1' = 'final-release-closure-evolution-writer'
}

$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $roles.GetEnumerator()) {
  $path = [string]$entry.Key
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-final-release-closure-writer-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $actual = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previous = [string]$state.authority_hashes[$path]
    if ($actual -cne $previous) {
      $evolved.Add([ordered]@{
        path=$path;previous_sha256=$previous;current_sha256=$actual
        reason='Import the exact maintainer GitHub release decision, bind the accepted F210 and F200 candidates to evidence-backed session preparation, regenerate documentation projections, and preserve all human and production transition gates.'
        scope='package-excluded-control-plane';package_visible=$false;release_authority=$false
      })
    }
  } else {
    $current.Add([ordered]@{path=$path;sha256=(Get-MIR4PreFreezeFileSha256 -Path $full -Mode 'canonical-text-v1');hash_mode='canonical-text-v1';role=[string]$entry.Value})
  }
}
if ($evolved.Count -lt 10 -or $current.Count -lt 6) { throw "[mir4-final-release-closure-writer-authority-set] evolved=$($evolved.Count) current=$($current.Count)" }

$output = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw '[mir4-final-release-closure-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) {
  $RecordedAt = [DateTimeOffset]::Now.ToString('o')
}

$receipt = [ordered]@{
  schema=1;kind='MIR4FinalReleaseClosureAuthorityEvolutionReceiptV1';recorded_at=$RecordedAt
  programme_id='M4C10-WHOLE-4X-IN-4.0';change_id='MIR4-FINAL-RELEASE-CLOSURE-2026-08-30'
  predecessor_receipt=[ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  maintainer_authorization=$authorization;playtest_candidate_authority=$candidateAuthority
  execution_state=[ordered]@{
    t16_status='blocked-human-custody-ceremony';t17_status='exact-sessions-prepared-observations-and-captures-pending'
    t18_status='blocked-dependency';source_freeze_status='authorized-conditionally-not-executed';production_release_status='authorized-conditionally-not-executed'
  }
  readme=[ordered]@{path='README.md';player_package_visible=$true;exact_candidate_copy_preserved=$true;post_release_update_deferred=$true}
  portal_copy=[ordered]@{path='docs/releases/mir4-4.0-mod-portal-extended-description.md';status='prepared-copy-only';live_portal_mutation_authorized=$false}
  branch_topology=[ordered]@{dev_role='active-development';main_role='current-stable-after-governed-promotion';legacy_role='previous-major-alias';legacy_mir4_sync_authorized=$false}
  evolved_bindings=@($evolved);current_authorities=@($current);player_package_source_sha256=$packageSource;package_visible_delta=@()
  transition_gate=[ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;production_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
  status='FINAL-RELEASE-AUTHORIZATION-IMPORTED-EXACT-PLAYTEST-SESSIONS-PREPARED-HUMAN-EVIDENCE-AND-CUSTODY-GATES-REMAIN'
}

$text = (($receipt | ConvertTo-Json -Depth 30).Replace("`r`n","`n") + "`n")
if ($Check) {
  if ([IO.File]::ReadAllText($output).Replace("`r`n","`n") -cne $text) { throw '[mir4-final-release-closure-receipt-stale]' }
} else {
  [IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $output) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) { throw '[mir4-final-release-closure-receipt-schema]' }
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$packageSource}
