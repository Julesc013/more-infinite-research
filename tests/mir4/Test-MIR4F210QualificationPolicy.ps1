# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/F210QualificationPolicy.ps1')

$policy = Get-MIR4F210QualificationPolicyV1 -RepoRoot $repo
if ([string]$policy.kind -cne 'MIR4F210ReleaseQualificationPolicyV1' -or
    [string]$policy.support_floor -cne '2.1.8' -or
    [string]$policy.pre_freeze.steam.branch -cne 'experimental' -or
    [string]$policy.freeze.trigger -cne 'explicit-T19-source-freeze-authorization' -or
    [string]$policy.post_stable.minimum_lane.version -cne '2.1.8' -or
    [string]$policy.post_stable.latest_lane.selection -cne 'latest-official-stable-2.1.x' -or
    @($policy.historical_evidence).Count -lt 3 -or
    @($policy.boundaries.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
  throw '[mir4-f210-policy-contract]'
}

$receiptPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json'
$receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100 -DateKind String
if ([string]$receipt.kind -cne 'MIR4F210QualificationPolicyAuthorityEvolutionReceiptV1' -or
    [string]$receipt.predecessor_receipt.sha256 -cne 'E9A099B1F54E63C1D23CBE20DC524329931BC769170EA44937C0515EB3675E45' -or
    [string]$receipt.qualification_policy.record_sha256 -cne [string]$policy.record_sha256 -or
    [string]$receipt.execution_state.t16_status -cne 'blocked-human' -or
    [string]$receipt.execution_state.t17_status -cne 'blocked-human' -or
    [string]$receipt.execution_state.t18_status -cne 'blocked-dependency' -or
    @($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0 -or
    @($receipt.package_visible_delta).Count -ne 0) {
  throw '[mir4-f210-policy-evolution-contract]'
}
& (Join-Path $repo 'tools/commands/mir4/Update-MIR4FinalMileToolingAuthority.ps1') -RepoRoot $repo -Check | Out-Null

Assert-MIR4F210EngineFactsV1 -Policy $policy -Version '2.1.17' -Build 87315 -FileVersion '2.1.17.87315' `
  -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 24955935 `
  -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) | Out-Null

foreach ($case in @(
  @{id='floor';invoke={ Assert-MIR4F210EngineFactsV1 -Policy $policy -Version '2.1.7' -Build 1 -FileVersion '2.1.7.1' -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 1 -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) }},
  @{id='channel';invoke={ Assert-MIR4F210EngineFactsV1 -Policy $policy -Version '2.1.17' -Build 87315 -FileVersion '2.1.17.87315' -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch public -SteamBuildId 1 -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) }},
  @{id='build';invoke={ Assert-MIR4F210EngineFactsV1 -Policy $policy -Version '2.1.17' -Build 87315 -FileVersion '2.1.17.1' -Distribution steam -Platform win64 -SteamAppId 427520 -SteamBranch experimental -SteamBuildId 1 -ResolvedBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) -ManifestBinaryPath ([string]$policy.pre_freeze.steam.factorio_binary) }}
)) {
  $rejected = $false
  try { & $case.invoke | Out-Null } catch { $rejected = $true }
  if (-not $rejected) { throw "[mir4-f210-negative-case] $($case.id)" }
}

$observation = [pscustomobject][ordered]@{
  schema=1;kind='MIR4F210EngineResolutionV1';status='selected-pre-freeze-experimental-exact-execution-lock'
  selection=[ordered]@{exact_execution_lock=$true}
  policy=[ordered]@{path=$script:MIR4F210PolicyRelativePath;sha256=('A'*64);record_sha256=[string]$policy.record_sha256}
  engine=[ordered]@{version='2.1.17';build=87315;file_version='2.1.17.87315';sha256=('B'*64)}
  steam=[ordered]@{build_id='24955935';app_manifest_sha256=('C'*64)}
  record_sha256=('D'*64)
}
$unauthorized = $false
try { New-MIR4F210FreezeLockV1 -Observation $observation | Out-Null } catch { $unauthorized = $_.Exception.Message -match 'freeze-authorization-required' }
if (-not $unauthorized) { throw '[mir4-f210-freeze-fail-closed]' }
$lock = New-MIR4F210FreezeLockV1 -Observation $observation -FreezeAuthorized
Test-MIR4F210FreezeLockV1 -Lock $lock -Observation $observation | Out-Null
$drifted = $observation | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
$drifted.engine.sha256 = 'E' * 64
$driftRejected = $false
try { Test-MIR4F210FreezeLockV1 -Lock $lock -Observation $drifted | Out-Null } catch { $driftRejected = $_.Exception.Message -match 'freeze-engine-drift' }
if (-not $driftRejected) { throw '[mir4-f210-freeze-drift-fail-closed]' }

$minimum = [pscustomobject]@{id='stable-minimum';channel='stable';version='2.1.8';sha256=('F'*64);exact_candidate_lock=$true}
$latest = [pscustomobject]@{id='stable-latest';channel='stable';version='2.1.17';sha256=('1'*64);exact_candidate_lock=$true}
Test-MIR4F210StableLaneSetV1 -Policy $policy -MinimumLane $minimum -LatestLane $latest | Out-Null
$latest.version = '2.1.7'
$stableRejected = $false
try { Test-MIR4F210StableLaneSetV1 -Policy $policy -MinimumLane $minimum -LatestLane $latest | Out-Null } catch { $stableRejected = $true }
if (-not $stableRejected) { throw '[mir4-f210-stable-lane-fail-closed]' }

if ($IsWindows -and
    (Test-Path -LiteralPath ([string]$policy.pre_freeze.steam.factorio_binary) -PathType Leaf) -and
    (Test-Path -LiteralPath ([string]$policy.pre_freeze.steam.app_manifest) -PathType Leaf)) {
  $live = Get-MIR4F210EngineResolutionV1 -RepoRoot $repo
  if ([string]$live.engine.version -notmatch '^2\.1\.' -or [version][string]$live.engine.version -lt [version]'2.1.8' -or
      [string]$live.steam.branch -cne 'experimental' -or -not [bool]$live.selection.exact_execution_lock -or
      [string]$live.engine.sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir4-f210-live-resolution]'
  }
}

Write-Host '[ok] F210 selects the authorized installed Steam experimental before freeze, fails closed on drift, and defines exact stable minimum/latest lanes.'
