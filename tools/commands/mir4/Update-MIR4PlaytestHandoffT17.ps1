[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$RecordedAt = ''
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

$outputRelative = '.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json'
$schemaRelative = 'spec/schemas/mir4-t17-machine-preparation-authority-evolution-receipt-v1.schema.json'
$expectedPackageSource = 'F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'
$state = Get-MIR4PreFreezeAuthorityState -RepoRoot $RepoRoot
if ([string]$state.prior_receipt_path -cne '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' -or
    [string]$state.prior_receipt_sha256 -cne '294A1E2001F3BA8E6813329E3C8BC609B0D07413AC365A0AFEF525A1188D76F0') {
  throw '[mir4-t17-writer-predecessor] T15 authority state is not the exact admitted predecessor.'
}
$packageSource = Get-MIRPackageSourceFingerprint -RepoRoot $RepoRoot
if ($packageSource -cne $expectedPackageSource) {
  throw "[mir4-t17-writer-package-source] expected=$expectedPackageSource actual=$packageSource"
}

$roles = [ordered]@{
  '.mir/control/paths.yml' = 't17-control-path-projection'
  '.mir/docs.yml' = 't17-documentation-projection'
  '.mir/modules.yml' = 't17-module-boundary-authority'
  'RELEASE-RUNBOOK.md' = 't17-release-runbook'
  'docs/maintainer/mir4-pre-freeze-hardening.md' = 't17-pre-freeze-maintainer-guidance'
  'docs/maintainer/mir4-w09-manual-playtest.md' = 't17-playtest-handoff-runbook'
  'docs/reference/generated/documentation-index.md' = 't17-generated-documentation-index'
  'docs/reference/generated/documentation-navigation.md' = 't17-generated-documentation-navigation'
  'docs/reference/generated/documentation-owner-dashboard.md' = 't17-generated-documentation-owner-dashboard'
  'docs/reference/generated/documentation-reference-matrix.md' = 't17-generated-documentation-reference-matrix'
  'docs/reference/generated/documentation-review-age.md' = 't17-generated-documentation-review-age'
  'mir.lock' = 't17-repository-fixed-point-lock'
  'spec/schemas/mir4-playtest-evidence-v1.schema.json' = 't17-playtest-evidence-schema'
  'spec/schemas/mir4-t17-machine-preparation-authority-evolution-receipt-v1.schema.json' = 't17-authority-evolution-schema'
  'tools/commands/mir4/Update-MIR4PlaytestHandoffT17.ps1' = 't17-authority-evolution-writer'
  'tools/lib/mir4/PreFreezeRelease.ps1' = 't17-session-and-authority-chain-implementation'
  'validation/generated/execution-registry.json' = 't17-generated-execution-registry'
  'validation/tests.yml' = 't17-test-catalogue'
  'validation/tests/mir4/Test-MIR4PlaytestHandoffT17.ps1' = 't17-playtest-handoff-validator'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1' = 't17-append-only-chain-validator'
}

$evolved = [Collections.Generic.List[object]]::new()
$current = [Collections.Generic.List[object]]::new()
foreach ($entry in $roles.GetEnumerator()) {
  $path = [string]$entry.Key
  $full = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    if ($state.authority_hashes.ContainsKey($path)) { throw "[mir4-t17-writer-missing-authority] $path" }
    continue
  }
  if ($state.authority_hashes.ContainsKey($path)) {
    $mode = if($state.authority_hash_modes.ContainsKey($path)){[string]$state.authority_hash_modes[$path]}else{'raw-bytes'}
    $actual = Get-MIR4PreFreezeFileSha256 -Path $full -Mode $mode
    $previous = [string]$state.authority_hashes[$path]
    if ($actual -cne $previous) {
      $evolved.Add([ordered]@{
        path = $path
        previous_sha256 = $previous
        current_sha256 = $actual
        reason = 'T17 hardens exact isolated playtest preparation and evidence comparison while preserving the human decision gate.'
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
if ($evolved.Count -lt 1 -or $current.Count -lt 4) {
  throw "[mir4-t17-writer-authority-set] evolved=$($evolved.Count) current=$($current.Count)"
}

$branch = (& git -C $RepoRoot branch --show-current).Trim()
$commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
$tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-f0-9]{40}$' -or $tree -notmatch '^[a-f0-9]{40}$') {
  throw '[mir4-t17-writer-git-baseline] Unable to resolve the source baseline.'
}
if ([string]::IsNullOrWhiteSpace($RecordedAt)) { $RecordedAt = [DateTimeOffset]::Now.ToString('o') }

$receipt = [ordered]@{
  schema = 1
  kind = 'MIR4T17MachinePreparationAuthorityEvolutionReceiptV1'
  recorded_at = $RecordedAt
  programme_id = 'M4C10-WHOLE-4X-IN-4.0'
  turn = 'T17'
  predecessor_receipt = [ordered]@{path=[string]$state.prior_receipt_path;sha256=[string]$state.prior_receipt_sha256}
  source_baseline = [ordered]@{branch=$branch;commit=$commit;tree=$tree;working_tree_clean=$false}
  execution_state = [ordered]@{
    programme_status = 'T15-COMPLETE-T16-T17-HUMAN-BLOCKED-RELEASE-BLOCKED'
    completed_turn = $null
    t16_status = 'blocked-human'
    t17_status = 'blocked-human'
    t18_status = 'blocked-dependency'
    next_dependency_ready_turn = $null
  }
  target_handoff = @(
    [ordered]@{target='F210';package_sha256='5058499D4A2802B0F1D9FDC50C1887C36A76AA2C9A4BD9B5F8DFFB58D1ACBD7D';engine_version='2.1.14';engine_sha256='E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F';package_custody_ready=$true;exact_engine_custody_ready=$false;isolated_session_automation_ready=$true;scenario_comparison_ready=$true;human_decision_recorded=$false},
    [ordered]@{target='F200';package_sha256='0078768BDDAEB4E8AE243D406919C38C55AC6C2CB96A492E890175EDEB0860C4';engine_version='2.0.77';engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';package_custody_ready=$true;exact_engine_custody_ready=$true;isolated_session_automation_ready=$true;scenario_comparison_ready=$true;human_decision_recorded=$false}
  )
  evolved_bindings = @($evolved)
  current_authorities = @($current)
  player_package_source_sha256 = $packageSource
  package_visible_delta = @()
  human_gate = [ordered]@{
    f210_decision_recorded = $false
    f200_decision_recorded = $false
    acceptance_inferred = $false
    decision_template_is_evidence = $false
    remaining_actions = @('obtain-exact-f210-engine-custody','execute-exact-f210-maintainer-playtest','execute-exact-f200-maintainer-playtest','record-explicit-decisions')
  }
  transition_gate = [ordered]@{source_freeze=$false;candidate_allocation=$false;production_signing=$false;production_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
  status = 'T17-MACHINE-PREPARATION-HARDENED-F200-READY-F210-EXACT-ENGINE-CUSTODY-BLOCKED-HUMAN-DECISIONS-REQUIRED'
}

$output = Join-Path $RepoRoot $outputRelative
$json = $receipt | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($output, ($json.Replace("`r`n","`n") + "`n"), [Text.UTF8Encoding]::new($false))
if (-not ((Get-Content -Raw -LiteralPath $output) | Test-Json -SchemaFile (Join-Path $RepoRoot $schemaRelative))) {
  throw '[mir4-t17-writer-schema] Generated receipt failed its schema.'
}
[pscustomobject][ordered]@{status='generated';path=$outputRelative;evolved_bindings=$evolved.Count;current_authorities=$current.Count;package_source_sha256=$packageSource}
