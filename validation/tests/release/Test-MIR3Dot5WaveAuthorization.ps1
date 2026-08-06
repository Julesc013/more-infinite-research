param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path }
$path = Join-Path $RepoRoot ".mir/releases/waves/MIR-3.5-Automated-Release-Authorization.json"
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "MIR 3 .5 wave authorization is missing." }
$authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json

if ([int]$authority.schema -ne 1 -or [string]$authority.kind -ne "MIR3Dot5WaveAutomatedReleaseAuthorizationV1") {
  throw "MIR 3 .5 wave authorization schema or kind changed."
}
if ([string]$authority.authorizer -ne "Julesc013") { throw "MIR 3 .5 wave authorizer changed." }
if ([bool]$authority.scope.mod_portal_upload_authorized) { throw "The wave must not authorize Mod Portal uploads." }
if (-not [bool]$authority.scope.github_release_only) { throw "The wave must remain GitHub-release-only." }

$expected = @(
  [pscustomobject]@{ release="3.2.5"; factorio="2.1"; predecessor="3.2.3"; promotion="main" },
  [pscustomobject]@{ release="2.5.5"; factorio="2.0"; predecessor="2.5.0"; promotion="legacy" },
  [pscustomobject]@{ release="1.9.5"; factorio="1.1"; predecessor="1.9.4"; promotion="immutable-release-tag" },
  [pscustomobject]@{ release="1.8.5"; factorio="1.0"; predecessor="1.8.2"; promotion="immutable-release-tag" },
  [pscustomobject]@{ release="1.7.5"; factorio="0.17"; predecessor="1.7.1"; promotion="immutable-release-tag" },
  [pscustomobject]@{ release="1.6.5"; factorio="0.16"; predecessor="1.6.0"; promotion="immutable-release-tag" },
  [pscustomobject]@{ release="1.5.5"; factorio="0.15"; predecessor="1.5.0"; promotion="immutable-release-tag" },
  [pscustomobject]@{ release="1.4.5"; factorio="0.14"; predecessor="1.4.0"; promotion="immutable-release-tag" },
  [pscustomobject]@{ release="1.3.5"; factorio="0.13"; predecessor="1.3.0"; promotion="immutable-release-tag" }
)
$targets = @($authority.targets)
if ($targets.Count -ne $expected.Count) { throw "The wave must contain exactly nine target rows." }
for ($index = 0; $index -lt $expected.Count; $index++) {
  foreach ($field in @("release", "factorio", "predecessor", "promotion")) {
    if ([string]$targets[$index].$field -ne [string]$expected[$index].$field) { throw "Wave target $index field '$field' changed." }
  }
}
if ([bool]$targets[3].factorio_0_18_bridge_claim) { throw "MIR 1.8.5 must target Factorio 1.0 only." }
if ([string]$authority.sequence.lower_projection_source -ne "immutable-publicly-verified-3.2.5-tag" -or
    [bool]$authority.sequence.lower_projection_formalization_before_3_2_5_publication) {
  throw "Lower projection ordering no longer waits for immutable public MIR 3.2.5."
}
if ([string]$authority.decision.lower_release_manual_review_disposition -ne "waived-by-explicit-maintainer-authorization" -or
    [string]$authority.decision.lower_release_manual_playtest_claim -ne "prohibited" -or
    [bool]$authority.decision.ordinary_release_policy_globally_weakened) {
  throw "The automated-only review boundary changed."
}
if ([string]$authority.decision.factorio_3_2_5_manual_attestation.disposition -ne "retain-existing-exact-hash-attestation" -or
    [bool]$authority.decision.factorio_3_2_5_manual_attestation.replace_or_duplicate) {
  throw "The existing C32 manual attestation must be retained without replacement."
}
$required = @($authority.required_conditions | ForEach-Object { [string]$_ })
foreach ($condition in @("deterministic-double-build-and-reconstruction", "exact-target-engine-load", "direct-predecessor-upgrade-proof", "candidate-seal", "public-byte-redownload-verification")) {
  if ($condition -notin $required) { throw "Required wave condition is missing: $condition" }
}
$prohibited = @($authority.prohibited_actions | ForEach-Object { [string]$_ })
foreach ($action in @("force-push", "tag-movement-or-replacement", "failed-gate-bypass", "fabricated-manual-review-evidence", "mod-portal-upload")) {
  if ($action -notin $prohibited) { throw "Required wave prohibition is missing: $action" }
}

Write-Host "[ok] MIR 3 .5 automated-release authority preserves exact targets, hard gates, truthful review status, and publication boundaries."
