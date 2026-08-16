param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/mir4/BootstrapMaterialization.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Get-JsonRecord([string]$RelativePath) {
  $path = Join-Path $RepoRoot $RelativePath
  return [pscustomobject]@{
    Path = $path
    Text = Get-Content -Raw -LiteralPath $path
    Value = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  }
}

if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
  throw "Test-Json is required for fail-closed MIR 4 readiness tests."
}

$engineRelativePath = ".mir/evidence/mir4-r0/2026-08-16/MIR4-Bootstrap-Engine-Availability-ObservationV1.json"
$engineSchemaPath = Join-Path $RepoRoot "spec/schemas/mir4-bootstrap-engine-availability-observation.schema.json"
$readinessRelativePath = ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Target-ReadinessV1.json"
$readinessSchemaPath = Join-Path $RepoRoot "spec/schemas/mir4-bootstrap-target-readiness.schema.json"

$engineRecord = Get-JsonRecord $engineRelativePath
$readinessRecord = Get-JsonRecord $readinessRelativePath
$planRecord = Get-JsonRecord ".mir/releases/waves/mir4-r0/MIR4-Bootstrap-Local-Candidate-PlanV1.json"
$entryGateRecord = Get-JsonRecord ".mir/releases/waves/mir4-r0/MIR4-Entry-GateV1.json"
$registryRecord = Get-JsonRecord ".mir/releases/waves/mir4-r0/MIR4-Target-RegistryV2.json"
$targetProfilesRecord = Get-JsonRecord ".mir/targets.json"
$visibilityRecord = Get-JsonRecord ".mir/evidence/terminal-publication/2026-08-16/mod-portal/MIR3-Dot9-ModPortal-VisibilityRecheckV1.json"
$refreshRecord = Get-JsonRecord ".mir/releases/waves/mir4-r0/MIR4-Terminal-Predecessor-RefreshV1.json"

Assert-True ($engineRecord.Text | Test-Json -SchemaFile $engineSchemaPath) "MIR 4 engine-availability observation schema validation failed."
Assert-True ($readinessRecord.Text | Test-Json -SchemaFile $readinessSchemaPath) "MIR 4 target-readiness record schema validation failed."
Assert-True (Test-MIR4BootstrapRecordHash -Record $engineRecord.Value) "MIR 4 engine-availability observation self-hash is stale."
Assert-True (Test-MIR4BootstrapRecordHash -Record $readinessRecord.Value) "MIR 4 target-readiness record self-hash is stale."

Assert-True ($engineRecord.Value.package_visible -eq $false -and
  $engineRecord.Value.semantic_authority -eq $false -and
  $engineRecord.Value.public_output_authorized -eq $false -and
  $engineRecord.Value.construction_authority -eq $false) "Engine availability escaped its non-authoritative boundary."
Assert-True ($readinessRecord.Value.package_visible -eq $false -and
  $readinessRecord.Value.semantic_authority -eq $false -and
  $readinessRecord.Value.public_output_authorized -eq $false -and
  $readinessRecord.Value.construction_authority -eq $false) "Target readiness escaped its non-authoritative boundary."
Assert-True ($engineRecord.Text -notmatch '(?i)[A-Z]:[\\/]' -and $engineRecord.Text -notmatch '\\\\') "Engine observation contains an absolute local path."

# V1 is an immutable dated observation of the superseded 3.2.9 / 2.1.13
# plan. Its old bindings must no longer equal the refreshed executable plan.
Assert-True ((Get-MIR4Sha256File -Path (Join-Path $RepoRoot ([string]$engineRecord.Value.lock_authority.path))) -cne [string]$engineRecord.Value.lock_authority.sha256) "Historical engine observation unexpectedly still binds the current plan."
Assert-True ([string]$refreshRecord.Value.kind -ceq "MIR4-Terminal-Predecessor-RefreshV1" -and
  [string]$refreshRecord.Value.status -ceq "accepted-current-pre-eol-package-excluded" -and
  [string]$refreshRecord.Value.payload.factorio_2_1.predecessor_release -ceq "3.2.10" -and
  [string]$refreshRecord.Value.payload.factorio_2_1.engine.version -ceq "2.1.14" -and
  [string]$refreshRecord.Value.payload.factorio_2_1.engine.executable_sha256 -ceq "E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F" -and
  [string]$refreshRecord.Value.payload.required_m4_003_finding -ceq "MIR3-TERM-0033") "Current MIR 4 predecessor refresh authority is incomplete."
foreach ($path in @($refreshRecord.Value.imports)) {
  Assert-True (Test-Path -LiteralPath (Join-Path $RepoRoot ([string]$path)) -PathType Leaf) "Predecessor refresh import does not exist: $path"
}

$engineTargets = @($engineRecord.Value.targets)
$readinessTargets = @($readinessRecord.Value.targets)
$expectedTargetKeys = @("f210", "f200", "f110", "f100")
Assert-True (($engineTargets.target_key -join '|') -ceq ($expectedTargetKeys -join '|')) "Engine observation target order or coverage drifted."
Assert-True (($readinessTargets.target_key -join '|') -ceq ($expectedTargetKeys -join '|')) "Readiness target order or coverage drifted."
Assert-True ((@($readinessTargets | Where-Object local_construction_admitted).target_key -join '|') -ceq "f210") "Readiness admits construction for a target other than f210."
Assert-True ((@($readinessRecord.Value.entry_state.construction_admitted_targets) -join '|') -ceq "f210") "Entry summary admits a target other than f210."
Assert-True ((@($readinessRecord.Value.entry_state.blocked_targets) -join '|') -ceq "f200|f110|f100") "Entry summary no longer blocks the three non-f210 targets."

Assert-True ($entryGateRecord.Value.status -ceq "pre-eol-local-proof-authorized-publication-forbidden") "Live MIR 4 entry-gate state drifted."
Assert-True ($entryGateRecord.Value.target_dispositions.'other-active-targets' -ceq "blocked-until-r1-and-eol") "Live MIR 4 entry gate no longer blocks non-f210 targets."
Assert-True ([string]$visibilityRecord.Value.status -ceq "api-and-rendered-table-two-visible-sha1-matched-redownloads-pending" -and
  (@($visibilityRecord.Value.releases | Where-Object { $_.api_visible -and $_.rendered_table_visible -and $_.sha1_matches_sealed }).Count -eq 2) -and
  [int]$visibilityRecord.Value.custody_state.authenticated_redownloads_complete -eq 0 -and
  $visibilityRecord.Value.custody_state.mir3_eol_blocked -eq $true) "Readiness no longer binds the accurate visibility-only, custody-open portal state."

foreach ($targetKey in $expectedTargetKeys) {
  $engineRows = @($engineTargets | Where-Object { [string]$_.target_key -ceq $targetKey })
  $readinessRows = @($readinessTargets | Where-Object { [string]$_.target_key -ceq $targetKey })
  $planRows = @($planRecord.Value.targets | Where-Object { [string]$_.target_key -ceq $targetKey })
  Assert-True ($engineRows.Count -eq 1 -and $readinessRows.Count -eq 1 -and $planRows.Count -eq 1) "Target $targetKey is not uniquely represented."

  $engine = $engineRows[0]
  $readiness = $readinessRows[0]
  $plan = $planRows[0]
  if ($targetKey -ceq "f210") {
    Assert-True ([string]$plan.predecessor.release -ceq "3.2.10" -and
      [string]$plan.engine_lock.version -ceq "2.1.14" -and
      [string]$plan.engine_lock.executable_sha256 -ceq [string]$refreshRecord.Value.payload.factorio_2_1.engine.executable_sha256) "Refreshed f210 plan does not bind the current predecessor authority."
  } else {
    Assert-True ([string]$engine.target_id -ceq [string]$plan.target_id -and
      [string]$engine.factorio_line -ceq [string]$plan.factorio_line -and
      [string]$engine.lock_label -ceq [string]$plan.engine_lock.version -and
      [string]$engine.required_engine.executable_sha256 -ceq [string]$plan.engine_lock.executable_sha256) "Engine lock no longer binds the plan row for $targetKey."
  }
  Assert-True ([string]$readiness.target_id -ceq [string]$plan.target_id -and
    [string]$readiness.factorio_line -ceq [string]$plan.factorio_line -and
    [string]$readiness.distribution_version -ceq [string]$plan.distribution_version -and
    [string]$readiness.current_admission -ceq [string]$plan.admission) "Readiness identity no longer binds the plan row for $targetKey."

  $registryRows = @($registryRecord.Value.payload.targets | Where-Object { [string]$_.id -ceq [string]$plan.target_id })
  Assert-True ($registryRows.Count -eq 1) "V2 target registry does not uniquely contain $targetKey."
  Assert-True ([string]$registryRows[0].factorio -ceq [string]$readiness.factorio_line) "Readiness target identity drifted from the V2 registry for $targetKey."
  if ($targetKey -ceq "f210") {
    Assert-True ([string]$readiness.transition.direct_predecessor -ceq "3.2.9" -and [string]$registryRows[0].mir3_predecessor -ceq "3.2.10") "Historical f210 readiness and current registry were not separated at the append-only refresh."
  } else {
    Assert-True ([string]$registryRows[0].mir3_predecessor -ceq [string]$readiness.transition.direct_predecessor) "Readiness predecessor identity drifted from the V2 registry for $targetKey."
  }

  $allIdentityFieldsMatch = [string]$engine.required_engine.version -ceq [string]$engine.observed_engine.version -and
    [int]$engine.required_engine.build -eq [int]$engine.observed_engine.build -and
    [string]$engine.required_engine.platform -ceq [string]$engine.observed_engine.platform -and
    [string]$engine.required_engine.architecture -ceq [string]$engine.observed_engine.architecture
  Assert-True $allIdentityFieldsMatch "Observed engine version/build/platform/architecture drifted for $targetKey."

  $hashMatches = [string]$engine.required_engine.executable_sha256 -ceq [string]$engine.observed_engine.executable_sha256
  Assert-True ($hashMatches -eq [bool]$engine.comparison.executable_sha256_match -and
    $hashMatches -eq [bool]$engine.comparison.exact_lock_match) "Engine match flags are inconsistent for $targetKey."
  if ($targetKey -ceq "f210") {
    Assert-True (-not $hashMatches -and [string]$engine.lock_state -ceq "hash-mismatch" -and
      [string]$readiness.engine.observation_state -ceq "hash-mismatch" -and
      $readiness.engine.executable_lock_available -eq $false -and
      [string]$plan.engine_lock.version -ceq "2.1.14") "Historical f210 mismatch or its current replacement lock is not represented."
  } else {
    Assert-True ($hashMatches -and [string]$engine.lock_state -ceq "exact-lock-match" -and
      [string]$readiness.engine.observation_state -ceq "exact-lock-match" -and
      $readiness.engine.executable_lock_available -eq $true) "$targetKey must record its exact executable lock match without claiming qualification."
  }

  Assert-True ($readiness.projection.state -ceq "not-defined" -and
    $readiness.projection.canonical_source_proven -eq $false -and
    $readiness.projection.complete_target_dispositions -eq $false -and
    $readiness.projection.provider_contract_proven -eq $false) "Readiness falsely claims a completed projection for $targetKey."
  Assert-True ($readiness.transition.fixture_state -ceq "defined-package-excluded" -and
    $readiness.transition.candidate_bound_evidence_present -eq $false -and
    $readiness.transition.historical_evidence_substitution_allowed -eq $false) "Readiness falsely claims transition evidence for $targetKey."

  $currentProfile = $targetProfilesRecord.Value.profiles.PSObject.Properties[[string]$readiness.factorio_line].Value
  Assert-True ([int]$currentProfile.expected_stream_count -eq [int]$readiness.capability.canonical_expected_stream_count) "Current target profile stream count drifted for $targetKey."

  $terminalTargetsText = (& git -C $RepoRoot show "$($plan.source.candidate_commit):.mir/targets.json") -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "Could not read terminal target profile authority for $targetKey." }
  $terminalTargets = $terminalTargetsText | ConvertFrom-Json
  $terminalProfile = $terminalTargets.profiles.PSObject.Properties[[string]$readiness.factorio_line].Value
  Assert-True ([int]$terminalProfile.expected_stream_count -eq [int]$readiness.capability.terminal_expected_stream_count) "Terminal target profile stream count drifted for $targetKey."
  Assert-True ($null -ne $terminalProfile.PSObject.Properties['supported_required_mods'] -and
    $null -ne $terminalProfile.PSObject.Properties['supported_effect_types']) "Terminal target profile lacks the positive capability fields recorded for $targetKey."
}

$f200 = @($readinessTargets | Where-Object { [string]$_.target_key -ceq "f200" })[0]
Assert-True ($f200.capability.state -ceq "terminal-authority-reconciled" -and
  [int]$f200.capability.canonical_expected_stream_count -eq 74 -and
  [int]$f200.capability.terminal_expected_stream_count -eq 74 -and
  @($f200.capability.drift).Count -eq 0) "f200 stream-count authority was not reconciled to the exact terminal value 74."
Assert-True (@($f200.blockers | Where-Object { [string]$_ -match 'rendering-discrepancy' }).Count -eq 0 -and
  @($f200.blockers | Where-Object { [string]$_ -ceq 'mir3-authenticated-redownload-and-eol-custody-pending' }).Count -eq 1) "f200 readiness retains the disproven portal-rendering discrepancy or drops the real custody blocker."

foreach ($targetKey in @("f110", "f100")) {
  $readiness = @($readinessTargets | Where-Object { [string]$_.target_key -ceq $targetKey })[0]
  $currentProfile = $targetProfilesRecord.Value.profiles.PSObject.Properties[[string]$readiness.factorio_line].Value
  $expectedEffects = @('character-build-distance', 'character-crafting-speed', 'character-inventory-slots-bonus', 'character-item-drop-distance', 'character-logistic-trash-slots', 'character-mining-speed', 'character-reach-distance', 'character-resource-reach-distance', 'character-running-speed', 'gun-speed', 'laboratory-productivity', 'worker-robot-battery')
  Assert-True (@($currentProfile.supported_required_mods).Count -eq 0 -and
    (@($currentProfile.supported_effect_types) -join '|') -ceq ($expectedEffects -join '|') -and
    [string]$readiness.capability.state -ceq "terminal-positive-allowlists-reconciled" -and
    [string]$readiness.capability.current_positive_allowlist_state -ceq 'present' -and
    @($readiness.capability.drift).Count -eq 0) "Canonical positive capability allowlists are not exact for $targetKey."
}

$badReadiness = $readinessRecord.Text | ConvertFrom-Json
$badF200 = @($badReadiness.targets | Where-Object { [string]$_.target_key -ceq "f200" })[0]
$badF200.local_construction_admitted = $true
$badReadinessText = $badReadiness | ConvertTo-Json -Depth 100
Assert-True (-not ($badReadinessText | Test-Json -SchemaFile $readinessSchemaPath -ErrorAction SilentlyContinue)) "Readiness schema admitted f200 construction."

$badEngine = $engineRecord.Text | ConvertFrom-Json
$badEngine.targets[0].observed_engine | Add-Member -NotePropertyName local_path -NotePropertyValue "D:\\Programs\\Factorio\\factorio.exe"
$badEngineText = $badEngine | ConvertTo-Json -Depth 100
Assert-True (-not ($badEngineText | Test-Json -SchemaFile $engineSchemaPath -ErrorAction SilentlyContinue)) "Engine observation schema accepted an absolute local path field."

Write-Host "[ok] MIR 4 historical readiness and current 3.2.10 / 2.1.14 predecessor refresh are fail-closed"
