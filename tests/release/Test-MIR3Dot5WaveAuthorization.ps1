# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path }
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

$outagePath = Join-Path $RepoRoot ".mir/releases/waves/MIR-3.5-Outage-Release-Authorization.json"
if (-not (Test-Path -LiteralPath $outagePath -PathType Leaf)) { throw "MIR 3 .5 outage authorization is missing." }
$outage = Get-Content -Raw -LiteralPath $outagePath | ConvertFrom-Json
if ([int]$outage.schema -ne 1 -or [string]$outage.kind -ne "MIR3Dot5WaveOutageReleaseAuthorizationV1") {
  throw "MIR 3 .5 outage authorization schema or kind changed."
}
if ([string]$outage.maintainer -ne "Julesc013" -or [string]$outage.incident.service -ne "actions") {
  throw "MIR 3 .5 outage authorization maintainer or incident changed."
}
$trust = $outage.trust_contract
if ([string]$trust.seal_kind -ne "MirLocalOutageReleaseSealV1" -or
    [bool]$trust.protected -or
    [string]$trust.remote_producer -ne "none" -or
    [string]$trust.release_authority -ne "maintainer-time-boxed-actions-outage" -or
    -not [bool]$trust.release_eligible_under_outage_exception -or
    [string]$trust.protected_qualification -ne "pending-post-outage" -or
    [string]$trust.public_verification -ne "pending" -or
    -not [bool]$trust.package_immutable_after_tag) {
  throw "The local outage seal trust contract is not truthful and exact."
}
if ([bool]$outage.authorization.remote_push -or [bool]$outage.authorization.github_release_creation -or [bool]$outage.authorization.mod_portal_upload) {
  throw "The outage authorization must not authorize remote publication."
}
if (@($outage.releases).Count -ne 9 -or [string]$outage.c32.archive_sha256 -ne "AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF") {
  throw "The outage authorization release set or C32 package identity changed."
}

$futurePath = Join-Path $RepoRoot ".mir/releases/waves/MIR4-Offline-Release-Authority.json"
if (-not (Test-Path -LiteralPath $futurePath -PathType Leaf)) { throw "MIR4 offline-release future requirement is missing." }
$future = Get-Content -Raw -LiteralPath $futurePath | ConvertFrom-Json
if ([string]$future.requirement_id -ne "MIR4-Offline-Release-Authority" -or
    [string]$future.status -ne "future-requirement-only" -or
    [bool]$future.implementation_admitted -or
    [bool]$future.boundary.mir_4_implementation -or
    [bool]$future.boundary.terminal_dot_9_implementation) {
  throw "MIR4 offline-release requirement crossed its future-only boundary."
}
foreach ($requirement in @("complete-build-and-qualification-without-github", "signed-immutable-local-evidence", "idempotent-later-github-replication", "repository-bundle-recovery")) {
  if ($requirement -notin @($future.requirements)) { throw "MIR4 offline-release requirement is missing: $requirement" }
}

Write-Host "[ok] MIR 3 .5 automated-release authority preserves exact targets, hard gates, truthful review status, and publication boundaries."
