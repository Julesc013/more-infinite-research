param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
)

$ErrorActionPreference = "Stop"
$recordPath = Join-Path $RepoRoot ".mir/releases/reconciliations/3.2.5.json"
if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
  throw "MIR 3.2.5 work-package reconciliation is missing."
}

$record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
if ([int]$record.schema -ne 1 -or
    [string]$record.kind -ne "mir-release-work-package-reconciliation" -or
    [string]$record.release -ne "3.2.5") {
  throw "MIR 3.2.5 work-package reconciliation identity is invalid."
}

$expectedBaseline = [ordered]@{
  commit = "b1144889386cf8bc5e7561bf6399d1127cfa74cb"
  tree = "b2671260c6fb84b75dbd86ad43e9351842cb91bb"
  archive_sha256 = "79965DD6167488013CEEE414897C4F00350B6FE541F4459B80D49C234DBDF208"
  content_sha256 = "489DFFB3C5998773B13256DB2298495FB97CE87F8C45C0A916E062DB1475DE0F"
  bytes = "1051537"
  entries = "299"
}
foreach ($entry in $expectedBaseline.GetEnumerator()) {
  if ([string]$record.source_baseline.($entry.Key) -ne [string]$entry.Value) {
    throw "Immutable development revision 3 field changed: $($entry.Key)."
  }
}
$baselineTree = (& git -C $RepoRoot show -s --format=%T ([string]$record.source_baseline.commit)).Trim()
if ($LASTEXITCODE -ne 0 -or $baselineTree -ne [string]$record.source_baseline.tree) {
  throw "Development revision 3 source commit and tree do not agree."
}

$expectedAdmittedBaseline = [ordered]@{
  revision = "5"
  package_source_commit = "a3bfbc4524b52cede425900e775384eb9c1fc4b3"
  package_source_tree = "a038ba1bcce347c53ee906d466279854c5a8d485"
  archive_sha256 = "AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF"
  content_sha256 = "1A2A37380FDE8EA0C260F90414ECB2BF70314341369D816FDD74D59B50535A7D"
  bytes = "1056249"
  entries = "301"
  package_equivalent_governance_commit = "a3bfbc4524b52cede425900e775384eb9c1fc4b3"
}
foreach ($entry in $expectedAdmittedBaseline.GetEnumerator()) {
  if ([string]$record.admitted_development_baseline.($entry.Key) -ne [string]$entry.Value) {
    throw "Admitted development revision 5 field changed: $($entry.Key)."
  }
}
$admittedTree = (& git -C $RepoRoot show -s --format=%T ([string]$record.admitted_development_baseline.package_source_commit)).Trim()
if ($LASTEXITCODE -ne 0 -or $admittedTree -ne [string]$record.admitted_development_baseline.package_source_tree) {
  throw "Development revision 5 source commit and tree do not agree."
}

$release = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/releases/records/3.2.5.json") |
  ConvertFrom-Json
foreach ($boundary in @{
  candidate_floor = "C32"
  factorio_2_0_release_authority = "not-created"
  mir_3_3_admission = "not-admitted"
  published_dist_mutation = "forbidden"
}.GetEnumerator()) {
  if ([string]$record.boundaries.($boundary.Key) -ne [string]$boundary.Value) {
    throw "Work-package reconciliation widened a forbidden boundary: $($boundary.Key)."
  }
}
if ([string]$release.state -ne [string]$record.boundaries.release_state -or
    [string]$release.candidate_floor -ne [string]$record.boundaries.candidate_floor -or
    [string]$release.candidate_id -ne [string]$record.boundaries.candidate_id) {
  throw "Work-package reconciliation differs from the typed 3.2.5 release authority."
}
$releaseBoundary = "{0}|{1}" -f [string]$record.boundaries.release_state, [string]$record.boundaries.candidate_id
if ($releaseBoundary -notin @(
    "planned|not-assigned",
    "source-frozen|C32",
    "package-built|C32",
    "focused-qualified|C32",
    "candidate-qualified|C32",
    "manually-accepted|C32"
  )) {
  throw "Work-package reconciliation claims an unsupported release boundary: $releaseBoundary"
}
if (Test-Path -LiteralPath (Join-Path $RepoRoot ".mir/releases/records/2.5.5.json")) {
  throw "A forbidden 2.5.5 release authority exists."
}

$expectedIds = @(
  "325-A1b", "325-A0", "325-A1",
  "325-B1", "325-B2", "325-B3", "325-B4", "325-B5",
  "325-C1", "325-D1", "325-D2", "325-D3", "325-D4"
)
$rows = @($record.work_packages)
$actualIds = @($rows | ForEach-Object { [string]$_.id })
if ($actualIds.Count -ne $expectedIds.Count -or
    @($actualIds | Sort-Object -Unique).Count -ne $expectedIds.Count) {
  throw "Open 325 work-package reconciliation has missing or duplicate rows."
}
foreach ($expectedId in $expectedIds) {
  if ($actualIds -notcontains $expectedId) { throw "Open work package is missing: $expectedId" }
}
if ($actualIds -contains "325-A1a") {
  throw "Closed work package 325-A1a must not re-enter the open reconciliation."
}
if ($actualIds -contains "325-B0") {
  throw "Closed work package 325-B0 must not re-enter the open reconciliation."
}
if ([string]$record.priority.next_work_package -notin @("325-D1", "325-D2", "325-D3")) {
  throw "The current bounded priority must remain on the 3.2.5 freeze or qualification path."
}

$arrayFields = @(
  "required_product_surface", "current_implementation", "current_tests",
  "current_evidence", "remaining_gap"
)
$pathPrefixes = @(".mir/", "docs/", "prototypes/", "scripts/", "spec/", "tools/", "validation/")
foreach ($row in $rows) {
  if ([string]::IsNullOrWhiteSpace([string]$row.next_bounded_action)) {
    throw "Work package $($row.id) has no next bounded action."
  }
  foreach ($field in $arrayFields) {
    $values = @($row.$field | ForEach-Object { [string]$_ })
    if ($values.Count -eq 0 -or @($values | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
      throw "Work package $($row.id) has an empty $field contract."
    }
    if (@($values | Sort-Object -Unique).Count -ne $values.Count) {
      throw "Work package $($row.id) repeats $field entries."
    }
  }
  foreach ($reference in @($row.current_tests) + @($row.current_evidence)) {
    $text = [string]$reference
    if (@($pathPrefixes | Where-Object { $text.StartsWith($_, [StringComparison]::Ordinal) }).Count -gt 0 -and
        -not (Test-Path -LiteralPath (Join-Path $RepoRoot $text))) {
      throw "Work package $($row.id) references a missing repository path: $text"
    }
  }
  if ([string]::IsNullOrWhiteSpace([string]$row.target_disposition.factorio_2_1) -or
      [string]::IsNullOrWhiteSpace([string]$row.target_disposition.factorio_2_0)) {
    throw "Work package $($row.id) lacks a two-target disposition."
  }
}
foreach ($authority in @($record.authorities)) {
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ([string]$authority)) -PathType Leaf)) {
    throw "Work-package reconciliation authority is missing: $authority"
  }
}

$closurePath = Join-Path $RepoRoot ".mir/lifecycle/changes/CHG-2026-0017.json"
$closure = Get-Content -Raw -LiteralPath $closurePath | ConvertFrom-Json
if ([string]$closure.state -ne "implemented" -or [bool]$closure.package_visible -or
    [string]$closure.work_package_closure.id -ne "325-B0" -or
    [string]$closure.work_package_closure.status -ne "closed-development-product-slice") {
  throw "CHG-2026-0017 does not close 325-B0 as a package-excluded admitted development slice."
}
$closureEvidence = $closure.work_package_closure
foreach ($required in @{
  implementation_head = "5264ab2285b56ac2a79dc1bc99724554fb558c7f"
  implementation_tree = "0d3fc58d69eed64bcb2199a051f9fc9f6a6c9c30"
  merge_commit = "489b62fda979c5192ddbb8294c27a3886f6ba13e"
}.GetEnumerator()) {
  if ([string]$closureEvidence.($required.Key) -ne [string]$required.Value) {
    throw "325-B0 closure identity differs: $($required.Key)."
  }
}
if ([int]$closureEvidence.local_admission.executed -ne 127 -or
    [int]$closureEvidence.local_admission.passed -ne 127 -or
    [int]$closureEvidence.local_admission.failed -ne 0 -or
    [int]$closureEvidence.hosted_admission.worker_import.imported -ne 8 -or
    [int]$closureEvidence.hosted_admission.worker_import.rejected -ne 0) {
  throw "325-B0 closure admission counts are incomplete."
}
foreach ($required in @(
  "3.2.4",
  "superseded-unpublished",
  "3.2.6-or-3.3",
  "no-gate-weakening"
)) {
  $scopeText = $record.scope_decision | ConvertTo-Json -Depth 10 -Compress
  if ($scopeText -notmatch [regex]::Escape($required)) {
    throw "The narrowed 3.2.5 scope decision is missing: $required"
  }
}
$c31Closure = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/releases/closures/3.2.4-C31.json") | ConvertFrom-Json
if ([string]$c31Closure.disposition -ne "superseded-unpublished" -or
    [string]$c31Closure.successor.release -ne "3.2.5") {
  throw "C31 must remain superseded-unpublished in favor of 3.2.5."
}
$distributions = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/distributions.json") | ConvertFrom-Json
if ([int]$distributions.distribution_count -ne @($distributions.distributions).Count -or
    @($distributions.distributions | Where-Object {
      [string]$_.version -eq "3.2.4" -and
      [string]$_.kind -eq "frozen-unreleased-calibration-candidate" -and
      [string]$_.sha256 -eq "64094ED6DFE48B058BB22E2AA55AF1EF11B30ED4264C3BBD5ECE0CE9DB22FCB1"
    }).Count -ne 1 -or
    -not (Test-Path -LiteralPath (Join-Path $RepoRoot "dist/more-infinite-research_3.2.4.zip") -PathType Leaf)) {
  throw "The superseded-unpublished C31 archive must remain in exact governed custody without becoming an active release."
}
foreach ($expectedStatus in @{
  "325-B2" = "deferred-explicitly"
  "325-B3" = "terminal-release-specific-product"
  "325-B4" = "terminal-release-specific-product"
  "325-B5" = "deferred-explicitly"
  "325-C1" = "terminal-shipped-features-only"
}.GetEnumerator()) {
  $row = @($rows | Where-Object { $_.id -eq $expectedStatus.Key })[0]
  if ([string]$row.status -ne [string]$expectedStatus.Value) {
    throw "$($expectedStatus.Key) does not preserve the explicit narrowed/deferred status."
  }
}
$branchStatus = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/views/branch-status.json") | ConvertFrom-Json
$c31View = @($branchStatus.branches | Where-Object { [string]$_.release -eq "3.2.4" -and [string]$_.candidate_id -eq "C31" })
if ($c31View.Count -ne 1 -or [string]$c31View[0].state -ne "package-built" -or
    [string]$c31View[0].effective_status -ne "superseded-unpublished") {
  throw "Generated branch status must distinguish C31 historical state from effective status."
}
foreach ($releaseOnly in @("325-D2", "325-D3", "325-D4")) {
  $row = @($rows | Where-Object { $_.id -eq $releaseOnly })[0]
  $allowedStatuses = switch ($releaseOnly) {
    "325-D2" { @("blocked-by-prerequisite", "in-progress", "terminal") }
    "325-D3" { @("blocked-by-prerequisite", "in-progress", "awaiting-manual-gate") }
    default { @("blocked-by-prerequisite") }
  }
  if ([string]$row.status -notin $allowedStatuses -or
      ([string]$releaseOnly -eq "325-D4" -and [string]$row.package_visibility -ne "none-until-admitted")) {
    throw "$releaseOnly has advanced outside the governed freeze/qualification boundary."
  }
}
$d1 = @($rows | Where-Object { $_.id -eq "325-D1" })[0]
if ([string]$d1.status -notin @("prepared-awaiting-admission", "terminal")) {
  throw "325-D1 has an unsupported freeze-packet state."
}

Write-Host "[ok] MIR 3.2.5 closes B0/B1, narrows the release contract, and preserves immutable development baselines without 2.5.5 or 3.3 authority."
