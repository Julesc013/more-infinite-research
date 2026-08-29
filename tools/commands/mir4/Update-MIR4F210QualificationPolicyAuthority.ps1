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

$outputRelative = '.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json'
$schemaRelative = 'spec/schemas/mir4-f210-qualification-policy-authority-evolution-receipt-v1.schema.json'
$predecessorRelative = 'releases/migrations/MIR4-Release-Tooling-MigrationV1.json'
$predecessorSha256 = 'E9A099B1F54E63C1D23CBE20DC524329931BC769170EA44937C0515EB3675E45'
$expectedPackageSource = 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'

$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot `
  -IncludeT17MachinePreparation -IncludeRepositoryMigration -IncludeCanonicalizationMigration `
  -IncludeDiagnosticsMigration -IncludeTargetKeyMigration -IncludeWholePlatformMigration `
  -IncludeTechnologyAcceptanceMigration -IncludeTargetCompilerMigration `
  -IncludeSemanticCompilerPolicyMigration -IncludeRuntimeContinuityMigration `
  -IncludeModuleSdkMepMigration -IncludeProcessIRExactMigration `
  -IncludeInspectorCompatibilityMigration -IncludeAssuranceOfflineCustodyMigration `
  -IncludeHistoricalToolingMigration -IncludeReleaseToolingMigration
if ([string]$state.prior_receipt_path -cne $predecessorRelative -or
    [string]$state.prior_receipt_sha256 -cne $predecessorSha256) {
  throw '[mir4-f210-policy-writer-predecessor] Release-tooling migration is not the exact admitted predecessor.'
}
$packageSource = Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if ($packageSource -cne $expectedPackageSource) {
  throw "[mir4-f210-policy-writer-package-source] expected=$expectedPackageSource actual=$packageSource"
}

$roles = [ordered]@{
  '.mir/control/paths.yml' = 'f210-policy-control-path-projection'
  '.mir/docs.yml' = 'f210-policy-documentation-projection'
  '.mir/modules.yml' = 'f210-policy-module-boundary-authority'
  '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json' = 'f210-release-qualification-policy'
  'RELEASE-RUNBOOK.md' = 'f210-release-runbook'
  'docs/maintainer/mir4-pre-freeze-hardening.md' = 'f210-pre-freeze-maintainer-guidance'
  'docs/maintainer/mir4-w09-manual-playtest.md' = 'f210-playtest-handoff-runbook'
  'docs/reference/generated/documentation-index.md' = 'f210-generated-documentation-index'
  'docs/reference/generated/documentation-navigation.md' = 'f210-generated-documentation-navigation'
  'docs/reference/generated/documentation-owner-dashboard.md' = 'f210-generated-documentation-owner-dashboard'
  'docs/reference/generated/documentation-reference-matrix.md' = 'f210-generated-documentation-reference-matrix'
  'docs/reference/generated/documentation-review-age.md' = 'f210-generated-documentation-review-age'
  'docs/releases/mir4-4.0-candidate-programme.md' = 'f210-candidate-programme-guidance'
  'spec/schemas/mir4-f210-release-qualification-policy-v1.schema.json' = 'f210-release-qualification-policy-schema'
  'spec/schemas/mir4-f210-qualification-policy-authority-evolution-receipt-v1.schema.json' = 'f210-policy-evolution-receipt-schema'
  'tools/commands/mir4/Update-MIR4F210QualificationPolicyAuthority.ps1' = 'f210-policy-evolution-writer'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 'f210-pre-freeze-policy-integration'
  'tools/mir/application/release/F210QualificationPolicy.ps1' = 'f210-qualification-policy-implementation'
  'validation/tests.yml' = 'f210-policy-test-catalogue'
  'validation/tests/mir4/Test-MIR4F210QualificationPolicy.ps1' = 'f210-policy-validator'
}

$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $roles.GetEnumerator()) {
  $path = [string]$entry.Key
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-f210-policy-writer-missing] $path" }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if ($state.authority_hash_modes.ContainsKey($path)) { [string]$state.authority_hash_modes[$path] } else { 'raw-bytes' }
    $actual = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previous = [string]$state.authority_hashes[$path]
    if ($actual -cne $previous) {
      $evolved.Add([ordered]@{
        path = $path
        previous_sha256 = $previous
        current_sha256 = $actual
        reason = 'Admit exact pre-freeze F210 Steam experimental selection, exact execution and freeze locks, and future stable minimum/latest qualification lanes without granting a release transition.'
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
if ($evolved.Count -lt 1 -or $current.Count -lt 5) {
  throw "[mir4-f210-policy-writer-authority-set] evolved=$($evolved.Count) current=$($current.Count)"
}

$output = Join-Path $RepoRoot $outputRelative
if ($Check) {
  if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw '[mir4-f210-policy-receipt-missing]' }
  $existing = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json -Depth 100 -DateKind String
  $RecordedAt = [string]$existing.recorded_at
} elseif ([string]::IsNullOrWhiteSpace($RecordedAt)) {
  $RecordedAt = [DateTimeOffset]::Now.ToString('o')
}

$policyPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json'
$policy = Get-MIR4F210QualificationPolicyV1 -RepoRoot $RepoRoot
$receipt = [ordered]@{
  schema = 1
  kind = 'MIR4F210QualificationPolicyAuthorityEvolutionReceiptV1'
  recorded_at = $RecordedAt
  programme_id = 'M4C10-WHOLE-4X-IN-4.0'
  change_id = 'MIR4-F210-PREFREEZE-QUALIFICATION-POLICY-2026-08-29'
  predecessor_receipt = [ordered]@{path=$predecessorRelative;sha256=$predecessorSha256}
  execution_state = [ordered]@{
    programme_status = 'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-T18-DEPENDENCY-BLOCKED-RELEASE-BLOCKED'
    t16_status = 'blocked-human'
    t17_status = 'blocked-human'
    t18_status = 'blocked-dependency'
    t19_status = 'blocked-human'
  }
  qualification_policy = [ordered]@{
    path = '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json'
    sha256 = Get-MIR4PreFreezeFileSha256 -Path $policyPath -Mode 'canonical-text-v1'
    record_sha256 = [string]$policy.record_sha256
    pre_freeze_channel = 'experimental'
    support_floor = '2.1.8'
    freeze_requires_explicit_authorization = $true
    future_stable_dual_lane = $true
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
  status = 'F210-PREFREEZE-QUALIFICATION-POLICY-ADMITTED-RELEASE-TRANSITIONS-UNAUTHORIZED'
}

$json = $receipt | ConvertTo-Json -Depth 20
$text = $json.Replace("`r`n","`n") + "`n"
if ($Check) {
  if ([IO.File]::ReadAllText($output).Replace("`r`n","`n") -cne $text) { throw '[mir4-f210-policy-receipt-stale]' }
} else {
  [IO.File]::WriteAllText($output, $text, [Text.UTF8Encoding]::new($false))
}
if (-not ((Get-Content -Raw -LiteralPath $output) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) {
  throw '[mir4-f210-policy-receipt-schema]'
}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$packageSource}
