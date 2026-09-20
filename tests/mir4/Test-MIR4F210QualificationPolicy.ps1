# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')

$historical = Test-MIR4F210HistoricalPolicyV1 -RepoRoot $repo
if ([string]$historical.kind -cne 'MIR4F210ReleaseQualificationPolicyV1' -or
    [string]$historical.support_floor -cne '2.1.8' -or
    [string]$historical.pre_freeze.steam.branch -cne 'experimental' -or
    [string]$historical.freeze.trigger -cne 'explicit-T19-source-freeze-authorization') {
  throw '[mir4-f210-historical-policy-contract]'
}

& (Join-Path $repo 'tools/commands/mir4/Update-MIR4F210CurrentQualificationPolicyV2Authority.ps1') -RepoRoot $repo -Check | Out-Null
& (Join-Path $repo 'tools/commands/mir4/Update-MIR4F210QualificationPolicyAuthority.ps1') -RepoRoot $repo -Check | Out-Null
$historicalWriteRejected = $false
try {
  & (Join-Path $repo 'tools/commands/mir4/Update-MIR4F210QualificationPolicyAuthority.ps1') -RepoRoot $repo | Out-Null
} catch {
  $historicalWriteRejected = $_.Exception.Message -match 'historical-policy-receipt-immutable'
}
if (-not $historicalWriteRejected) { throw '[mir4-f210-historical-policy-write-fail-closed]' }
$policy = Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $repo
$receipt = Get-MIR4F210CurrentQualificationPolicySuccessionV1 -RepoRoot $repo
$f210GenerationInput = Get-Content -Raw -LiteralPath (Join-Path $repo 'source/presentation/f210/info.json.template') | ConvertFrom-Json -Depth 20
$requiredF210Dependencies = @('base >= 2.1.18','? recycler >= 2.1.18','? space-age >= 2.1.18')
if (@($requiredF210Dependencies | Where-Object { $_ -notin @($f210GenerationInput.dependencies) }).Count -ne 0 -or
    @($f210GenerationInput.dependencies | Where-Object { $_ -match '^(base|\? recycler|\? space-age) >= 2\.1\.(8|17)$' }).Count -ne 0) {
  throw '[mir4-f210-current-generation-input-floor]'
}
$f210Profile = Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/profiles/factorio-2.1.json') | ConvertFrom-Json -Depth 20
if ([string]$f210Profile.minimum_factorio_version -cne '2.1.18') { throw '[mir4-f210-current-profile-floor]' }
if ([string]$policy.kind -cne 'MIR4F210CurrentQualificationPolicyV2' -or
    [string]$policy.support_floor -cne '2.1.18' -or
    [string]$policy.pre_freeze.steam.branch -cne 'experimental' -or
    [string]$policy.pre_freeze.engine_admission -cne 'pending-exact-engine-api-prototype-data-and-official-mod-capsule' -or
    [string]$policy.post_stable.minimum_lane.floor_rule -cne 'numeric-version-max(requested-2.1.18,first-official-stable-2.1-patch,later-accepted-mandatory-floor)' -or
    [string]$policy.post_stable.latest_lane.selection -cne 'latest-official-stable-2.1.x' -or
    [bool]$policy.qualification.current_engine_api_prototype_data_mod_capsule_admitted -or
    [bool]$policy.qualification.current_engine_qualification_passed -or
    [bool]$policy.qualification.stable_transition_recorded -or
    [bool]$policy.qualification.stable_qualification_passed -or
    -not [bool]$policy.boundaries.compatibility_floor_changed -or
    @($policy.boundaries.PSObject.Properties | Where-Object { $_.Name -ne 'compatibility_floor_changed' -and [bool]$_.Value }).Count -ne 0 -or
    [string]$receipt.current_policy.record_sha256 -cne [string]$policy.record_sha256 -or
    [string]$receipt.historical_policy.record_sha256 -cne [string]$historical.record_sha256 -or
    @($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
  throw '[mir4-f210-current-policy-contract]'
}

Assert-MIR4F210HistoricalEngineFactsV1 -Policy $historical -Version '2.1.17' -Build 87315 -FileVersion '2.1.17.87315' `
  -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 24955935 `
  -ResolvedBinaryPath ([string]$historical.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$historical.pre_freeze.steam.factorio_binary) | Out-Null
Assert-MIR4F210EngineFactsV2 -Policy $policy -Version '2.1.18' -Build 1 -FileVersion '2.1.18.1' `
  -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 1 `
  -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) | Out-Null

foreach ($case in @(
  @{id='current-floor';invoke={ Assert-MIR4F210EngineFactsV2 -Policy $policy -Version '2.1.17' -Build 87315 -FileVersion '2.1.17.87315' -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 1 -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) }},
  @{id='channel';invoke={ Assert-MIR4F210EngineFactsV2 -Policy $policy -Version '2.1.18' -Build 1 -FileVersion '2.1.18.1' -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch public -SteamBuildId 1 -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) }},
  @{id='build';invoke={ Assert-MIR4F210EngineFactsV2 -Policy $policy -Version '2.1.18' -Build 1 -FileVersion '2.1.18.2' -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 1 -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) }}
)) {
  $rejected = $false
  try { & $case.invoke | Out-Null } catch { $rejected = $true }
  if (-not $rejected) { throw "[mir4-f210-current-negative-case] $($case.id)" }
}

$observation = [pscustomobject][ordered]@{
  schema=2;kind='MIR4F210EngineResolutionV2';status='selected-pre-freeze-experimental-exact-execution-lock'
  selection=[ordered]@{exact_execution_lock=$true}
  policy=[ordered]@{path=$script:MIR4F210CurrentPolicyRelativePath;sha256=('A'*64);record_sha256=[string]$policy.record_sha256}
  engine=[ordered]@{version='2.1.18';build=1;file_version='2.1.18.1';sha256=('B'*64)}
  steam=[ordered]@{build_id='1';app_manifest_sha256=('C'*64)}
  record_sha256=('D'*64)
}
$unauthorized = $false
try { New-MIR4F210FreezeLockV2 -Observation $observation | Out-Null } catch { $unauthorized = $_.Exception.Message -match 'freeze-authorization-required' }
if (-not $unauthorized) { throw '[mir4-f210-current-freeze-fail-closed]' }
$lock = New-MIR4F210FreezeLockV2 -Observation $observation -FreezeAuthorized
Test-MIR4F210FreezeLockV2 -Lock $lock -Observation $observation | Out-Null
$drifted = $observation | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
$drifted.engine.sha256 = 'E' * 64
$driftRejected = $false
try { Test-MIR4F210FreezeLockV2 -Lock $lock -Observation $drifted | Out-Null } catch { $driftRejected = $_.Exception.Message -match 'freeze-engine-drift' }
if (-not $driftRejected) { throw '[mir4-f210-current-freeze-drift-fail-closed]' }

foreach ($case in @(
  @{first='2.1.18';later='2.1.18';minimum='2.1.18'},
  @{first='2.1.20';later='2.1.19';minimum='2.1.20'},
  @{first='2.1.18';later='2.1.23';minimum='2.1.23'}
)) {
  $minimum = [pscustomobject]@{id='stable-minimum';channel='stable';floor_rule=[string]$policy.post_stable.minimum_lane.floor_rule;version=$case.minimum;first_official_stable_version=$case.first;later_accepted_mandatory_floor=$case.later;sha256=('F'*64);exact_candidate_lock=$true}
  $latest = [pscustomobject]@{id='stable-latest';channel='stable';version=$case.minimum;sha256=('1'*64);exact_candidate_lock=$true}
  Test-MIR4F210StableLaneSetV2 -Policy $policy -MinimumLane $minimum -LatestLane $latest | Out-Null
}
$invalidStable = [pscustomobject]@{id='stable-minimum';channel='stable';floor_rule=[string]$policy.post_stable.minimum_lane.floor_rule;version='2.1.17';first_official_stable_version='2.1.17';later_accepted_mandatory_floor='2.1.17';sha256=('F'*64);exact_candidate_lock=$true}
$invalidLatest = [pscustomobject]@{id='stable-latest';channel='stable';version='2.1.18';sha256=('1'*64);exact_candidate_lock=$true}
$stableRejected = $false
try { Test-MIR4F210StableLaneSetV2 -Policy $policy -MinimumLane $invalidStable -LatestLane $invalidLatest | Out-Null } catch { $stableRejected = $true }
if (-not $stableRejected) { throw '[mir4-f210-current-stable-floor-fail-closed]' }

if ($IsWindows -and (Test-Path -LiteralPath ([string]$policy.pre_freeze.steam.factorio_binary) -PathType Leaf)) {
  $installedBelowFloor = $false
  try { Get-MIR4F210EngineResolutionV2 -RepoRoot $repo | Out-Null } catch { $installedBelowFloor = $_.Exception.Message -match 'mir4-f210-current-engine-floor' }
  if (-not $installedBelowFloor) { throw '[mir4-f210-current-engine-admission-boundary]' }
}

Write-Host '[ok] Historical F210 2.1.8/2.1.17 evidence is immutable; the current policy requires 2.1.18, computes the stable lane by numeric maximum, and remains engine-unqualified.'
