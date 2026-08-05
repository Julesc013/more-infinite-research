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

$release = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir/releases/records/3.2.5.json") |
  ConvertFrom-Json
foreach ($boundary in @{
  release_state = "planned"
  candidate_floor = "C32"
  candidate_id = "not-assigned"
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
if (Test-Path -LiteralPath (Join-Path $RepoRoot ".mir/releases/records/2.5.5.json")) {
  throw "A forbidden 2.5.5 release authority exists."
}

$expectedIds = @(
  "325-A1b", "325-A0", "325-A1",
  "325-B0", "325-B1", "325-B2", "325-B3", "325-B4", "325-B5",
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
if ([string]$record.priority.next_work_package -ne "325-B0") {
  throw "The current bounded product priority must remain 325-B0 until its vertical slice is admitted."
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

$b0 = @($rows | Where-Object { $_.id -eq "325-B0" })[0]
$b0Gap = @($b0.remaining_gap) -join "`n"
foreach ($required in @("terminal", "proof assertion", "support projection", "Factorio 2.0")) {
  if ($b0Gap -notmatch [regex]::Escape($required)) {
    throw "325-B0 does not expose its required end-to-end gap: $required"
  }
}
foreach ($releaseOnly in @("325-D2", "325-D3", "325-D4")) {
  $row = @($rows | Where-Object { $_.id -eq $releaseOnly })[0]
  if ([string]$row.status -ne "blocked-by-prerequisite" -or
      [string]$row.package_visibility -ne "none-until-admitted") {
    throw "$releaseOnly must remain blocked and non-authoritative."
  }
}

Write-Host "[ok] MIR 3.2.5 open work packages are reconciled against immutable development revision 3 without candidate, 2.5.5, or 3.3 authority."
