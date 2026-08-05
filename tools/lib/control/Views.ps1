function Get-MIRCPCurrentRelease {
  param(
    [ValidateSet("canonical", "backport_calibration")][string]$Role = "canonical",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $pointer = Read-MIRCPJson -Path ("path:" + [string]$policy.records.current) -RepoRoot $repo
  $release = [string]$pointer.roles.$Role
  return Read-MIRCPJson -Path "path:releases.records/$release.json" -RepoRoot $repo
}

function Get-MIRCPReleaseByVersion {
  param(
    [Parameter(Mandatory)][string]$Release,
    [string]$RepoRoot = ""
  )
  return Read-MIRCPJson -Path "path:releases.records/$Release.json" -RepoRoot $RepoRoot
}

function Get-MIRCPArrayProperty {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name
  )
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return @() }
  return @($property.Value | Where-Object { $null -ne $_ })
}

function Get-MIRCPReleaseStateIndex {
  param(
    [Parameter(Mandatory)][string]$State,
    [string]$RepoRoot = ""
  )
  $states = @((Get-MIRCPPolicy -RepoRoot $RepoRoot).release_states | ForEach-Object { [string]$_ })
  $index = [Array]::IndexOf($states, $State)
  if ($index -lt 0) { throw "Unknown release state '$State'." }
  return $index
}

function Get-MIRCPRemainingReleaseStates {
  param(
    [Parameter(Mandatory)]$Release,
    [string]$RepoRoot = ""
  )
  $states = @((Get-MIRCPPolicy -RepoRoot $RepoRoot).release_states | ForEach-Object { [string]$_ })
  $index = Get-MIRCPReleaseStateIndex -State ([string]$Release.state) -RepoRoot $RepoRoot
  if ($index -ge ($states.Count - 1)) { return @() }
  return @($states[($index + 1)..($states.Count - 1)])
}

function Get-MIRCPEffectiveReleaseStatus {
  param(
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)]$CandidateClosures
  )
  $matches = @($CandidateClosures | Where-Object {
    [string]$_.release -eq [string]$Release.release -and
    [string]$_.candidate_id -eq [string]$Release.candidate_id
  })
  if ($matches.Count -gt 1) {
    throw "Release $($Release.release)/$($Release.candidate_id) has multiple candidate closures."
  }
  if ($matches.Count -eq 1) { return [string]$matches[0].disposition }
  return [string]$Release.state
}

function Get-MIRCPTagProof {
  param([Parameter(Mandatory)]$Release)
  $rows = if ($null -ne $Release.proofs.PSObject.Properties["tag"]) { @($Release.proofs.tag) } else { @() }
  if ($rows.Count -eq 0) { return $null }
  return $rows[0]
}

function ConvertTo-MIRCPLegacyPublishedRelease {
  param([Parameter(Mandatory)]$Release)
  $tag = Get-MIRCPTagProof -Release $Release
  return [pscustomobject][ordered]@{
    mir_version = [string]$Release.release
    branch = [string]$Release.branch
    tag = if ($null -ne $tag) { [string]$tag.name } else { $null }
    tag_commit = if ($null -ne $tag) { [string]$tag.commit } else { $null }
    package_source_commit = [string]$Release.package.source_commit
    archive = [string]$Release.package.archive
    archive_sha256 = [string]$Release.package.archive_sha256
    package_content_sha256 = [string]$Release.package.content_sha256
    status = "release-$($Release.state)"
  }
}

function ConvertTo-MIRCPLegacyDevelopmentRelease {
  param(
    [Parameter(Mandatory)]$Release,
    [string]$RepoRoot = ""
  )
  $focused = if ($null -ne $Release.proofs.PSObject.Properties["focused_qualification"]) { @($Release.proofs.focused_qualification) } else { @() }
  $candidate = if ($null -ne $Release.proofs.PSObject.Properties["candidate_qualification"]) { @($Release.proofs.candidate_qualification) } else { @() }
  $manual = if ($null -ne $Release.proofs.PSObject.Properties["manual_acceptance"]) { @($Release.proofs.manual_acceptance) } else { @() }
  $tag = Get-MIRCPTagProof -Release $Release
  $remaining = @(Get-MIRCPRemainingReleaseStates -Release $Release -RepoRoot $RepoRoot)
  [string[]]$exceptionIds = [string[]]::new(0)
  $exceptionIds = [string[]]@(Get-MIRCPArrayProperty -Object $Release -Name "assurance_exceptions" | ForEach-Object { [string]$_.id })
  $result = [ordered]@{
    mir_version = [string]$Release.release
    candidate_id = [string]$Release.candidate_id
    branch = [string]$Release.branch
    development_branch = if ([string]$Release.target -eq "2.1") { "dev" } else { [string]$Release.branch }
    source_anchor = if ($null -ne $Release.PSObject.Properties["source_release"]) { [string]$Release.source_release.tag } else { "3.2.1" }
    archive = [string]$Release.package.archive
    archive_bytes = if ($null -ne $Release.package.PSObject.Properties["bytes"]) { [long]$Release.package.bytes } else { $null }
    archive_entries = if ($null -ne $Release.package.PSObject.Properties["entries"]) { [int]$Release.package.entries } else { $null }
    package_source_commit = [string]$Release.package.source_commit
    package_source_tree = [string]$Release.package.source_tree
    package_source_sha256 = [string]$Release.package.source_sha256
    package_source_material = [pscustomobject][ordered]@{
      schema = 1
      hash_algorithm = "git-commit-normalized-package-v1"
      source_tree = [string]$Release.package.source_tree
      file_count = if ($null -ne $Release.package.PSObject.Properties["entries"]) { [int]$Release.package.entries } else { $null }
    }
    archive_sha256 = [string]$Release.package.archive_sha256
    package_content_sha256 = [string]$Release.package.content_sha256
    archive_class = if ([string]$Release.state -in @("tagged", "published", "publicly-verified")) { "immutable-$($Release.state)-release" } else { "frozen-unreleased-calibration-candidate" }
    qualification = [string]$Release.state
    publication_status = [string]$Release.state
    status = "$($Release.candidate_id)-$($Release.state)"
    remaining_states = $remaining
    assurance_exception_ids = $exceptionIds
  }
  if ($null -ne $Release.PSObject.Properties["candidate_floor"]) {
    $result.candidate_floor = [string]$Release.candidate_floor
  }
  if ($focused.Count -gt 0) {
    $exactPy = @($focused | Where-Object { [string]$_.path -eq ".mir/evidence/3.2.2-py-exact.json" })
    $performance = @($focused | Where-Object { [string]$_.path -eq ".mir/evidence/3.2.2-performance-regression.json" })
    if ($exactPy.Count -eq 1) {
      $result.exact_py_evidence = [string]$exactPy[0].path
      $result.exact_py_evidence_sha256 = [string]$exactPy[0].sha256
    }
    if ($performance.Count -eq 1) {
      $result.performance_evidence = [string]$performance[0].path
      $result.performance_evidence_sha256 = [string]$performance[0].sha256
    }
  }
  if ($candidate.Count -gt 0) {
    $result.candidate_qualification_evidence = [string]$candidate[0].path
    $result.candidate_qualification_sha256 = [string]$candidate[0].sha256
  }
  $result.manual_review = if ($manual.Count -gt 0) { "maintainer-patch-review-approved" } else { "pending" }
  $result.protected_qualification = if (@(Get-MIRCPArrayProperty -Object $Release -Name "assurance_exceptions" | Where-Object { [string]$_.id -match "PROTECTED|SEAL" }).Count -gt 0) { "not-recorded-before-tag" } else { "pending" }
  if ($null -ne $tag) {
    $result.tag = [string]$tag.name
    $result.tag_commit = [string]$tag.commit
  }
  if ([string]$Release.release -eq "3.2.2") {
    $result.approved_delta = "bounded-c21-to-c24-hotfix-reviewed"
    $result.upgrade_qualification = "exact-3.2.1-to-3.2.2-six-archetype-runtime-passed"
  }
  if ($null -ne $Release.PSObject.Properties["remaining_obligations"]) {
    $result.remaining_obligations = @($Release.remaining_obligations | ForEach-Object { [string]$_ })
  }
  return [pscustomobject]$result
}

function New-MIRCPLegacyReleaseLedger {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $pointer = Read-MIRCPJson -Path ("path:" + [string]$policy.records.current) -RepoRoot $repo
  $canonical = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.canonical) -RepoRoot $repo
  $backport = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.backport_calibration) -RepoRoot $repo
  $publishedModern = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.published_factorio_2_1) -RepoRoot $repo
  $publishedBackport = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.published_factorio_2_0) -RepoRoot $repo
  $updated = @($canonical.updated_at, $backport.updated_at, $publishedModern.updated_at, $publishedBackport.updated_at | ForEach-Object { [datetimeoffset]$_ } | Sort-Object -Descending | Select-Object -First 1)
  return [pscustomobject][ordered]@{
    schema = 1
    authority = "canonical-release-ledger"
    generated_from = @(
      "path:releases.current",
      "path:releases.records/$($canonical.release).json",
      "path:releases.records/$($backport.release).json",
      "path:releases.records/$($publishedModern.release).json",
      "path:releases.records/$($publishedBackport.release).json"
    ) | Select-Object -Unique
    updated_at = ([datetimeoffset]$updated[0]).ToString("yyyy-MM-dd")
    published_baselines = [pscustomobject][ordered]@{
      "factorio-2.1" = ConvertTo-MIRCPLegacyPublishedRelease -Release $publishedModern
      "factorio-2.0" = ConvertTo-MIRCPLegacyPublishedRelease -Release $publishedBackport
    }
    development = [pscustomobject][ordered]@{
      "factorio-2.1" = ConvertTo-MIRCPLegacyDevelopmentRelease -Release $canonical -RepoRoot $repo
      "factorio-2.0" = ConvertTo-MIRCPLegacyDevelopmentRelease -Release $backport -RepoRoot $repo
    }
    views = [pscustomobject][ordered]@{
      branch_policy = ".mir/branches.yml"
      release_dashboard = "docs/releases/control-plane-dashboard.md"
      maintainer_queue = "todo.md"
      publication_checklist = "path:views.publication-checklist"
      backport_queue = "path:views.backport-queue"
    }
    rules = [pscustomobject][ordered]@{
      published_archives_are_immutable = $true
      development_archives_are_not_releases = $true
      backports_start_after_canonical_source_freeze = $true
      manual_view_disagreement_fails_validation = $true
      typed_release_records_are_authoritative = $true
    }
  }
}

function Set-MIRCPGeneratedText {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
    [string]$RepoRoot = "",
    [switch]$Check
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $Path = Resolve-MIRCPPathToken -Path $Path -RepoRoot $repo
  $resolved = Join-Path $repo $Path
  $content = ($Lines -join "`n") + "`n"
  if ($Check) {
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Generated text is missing: $Path" }
    $existing = (Get-Content -Raw -LiteralPath $resolved).Replace("`r`n", "`n")
    if ($existing -cne $content) { throw "Generated text is stale: $Path" }
    return
  }
  $parent = Split-Path -Parent $resolved
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    [void](New-Item -ItemType Directory -Force -Path $parent)
  }
  [IO.File]::WriteAllText($resolved, $content, [Text.UTF8Encoding]::new($false))
}

function Format-MIRCPCode {
  param($Value)
  $tick = [char]96
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return [string]::Concat($tick, "pending", $tick) }
  return [string]::Concat($tick, [string]$Value, $tick)
}

function New-MIRCPCurrentCandidateLines {
  param(
    [Parameter(Mandatory)]$Release,
    [Parameter(Mandatory)][string]$ReviewDate,
    [string]$RepoRoot = ""
  )
  $remaining = @(Get-MIRCPRemainingReleaseStates -Release $Release -RepoRoot $RepoRoot)
  $exceptions = @(Get-MIRCPArrayProperty -Object $Release -Name "assurance_exceptions")
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in @(
    "---", "title: `"Current Development Candidate`"", "status: current", "applies_to: `"$($Release.release)`"",
    "audience: release-manager", "doc_type: reference", "owner: mir-maintainers", "last_reviewed: $ReviewDate",
    "supersedes: []", "superseded_by: []", "---", "", "# Current Development Candidate", "",
    "> Generated from typed ReleaseRecords by ``tools/commands/control/Invoke-MIRControlPlane.ps1 views``. Do not edit this view.", "",
    "| Field | Authority |", "| --- | --- |",
    "| MIR version | $(Format-MIRCPCode $Release.release) |",
    "| Candidate identity | $(Format-MIRCPCode $Release.candidate_id) |",
    "| Reserved candidate floor | $(Format-MIRCPCode $Release.candidate_floor) |",
    "| Target | $(Format-MIRCPCode $Release.target) |",
    "| Branch | $(Format-MIRCPCode $Release.branch) |",
    "| State | $(Format-MIRCPCode $Release.state) |",
    "| Package source commit | $(Format-MIRCPCode $Release.package.source_commit) |",
    "| Package source tree | $(Format-MIRCPCode $Release.package.source_tree) |",
    "| Package source SHA-256 | $(Format-MIRCPCode $Release.package.source_sha256) |",
    "| Archive | $(Format-MIRCPCode $Release.package.archive) |",
    "| Archive bytes | $(Format-MIRCPCode $Release.package.bytes) |",
    "| Archive entries | $(Format-MIRCPCode $Release.package.entries) |",
    "| Archive SHA-256 | $(Format-MIRCPCode $Release.package.archive_sha256) |",
    "| Package content SHA-256 | $(Format-MIRCPCode $Release.package.content_sha256) |", "",
    "## Remaining state transitions", ""
  )) { $lines.Add($line) }
  if ($remaining.Count -eq 0) { $lines.Add("None.") } else { foreach ($state in $remaining) { $lines.Add("- [ ] ``$state``") } }
  $lines.Add("")
  $lines.Add("## Assurance exceptions")
  $lines.Add("")
  if ($exceptions.Count -eq 0) { $lines.Add("None.") } else {
    foreach ($exception in $exceptions) { $lines.Add("- $(Format-MIRCPCode $exception.id): $($exception.reason) Disposition: $(Format-MIRCPCode $exception.disposition).") }
  }
  return @($lines)
}

function New-MIRCPDashboardLines {
  param(
    [Parameter(Mandatory)]$Releases,
    [Parameter(Mandatory)]$CandidateClosures,
    [Parameter(Mandatory)][string]$ReviewDate
  )
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in @(
    "---", "title: `"MIR Control Plane Dashboard`"", "status: current", "applies_to: `"release-engineering`"",
    "audience: release-manager", "doc_type: reference", "owner: mir-maintainers", "last_reviewed: $ReviewDate",
    "supersedes: []", "superseded_by: []", "---", "", "# MIR Control Plane Dashboard", "",
    "> Generated from ``path:releases.records/*.json``, CandidateClosureRecords, ChangeRecords, IncidentRecords, and TaskNodes. Machine records are authoritative.", "",
    "## Releases", "", "| Release | Candidate | Reserved floor | Target | Branch | Historical state | Effective status | Exceptions |", "| --- | --- | --- | --- | --- | --- | --- | ---: |"
  )) { $lines.Add($line) }
  foreach ($release in @($Releases | Sort-Object @{Expression={ [version]$_.release }; Descending=$true})) {
    $exceptionCount = if ($null -ne $release.PSObject.Properties["assurance_exceptions"]) { @($release.assurance_exceptions).Count } else { 0 }
    $effectiveStatus = Get-MIRCPEffectiveReleaseStatus -Release $release -CandidateClosures $CandidateClosures
    $lines.Add("| $(Format-MIRCPCode $release.release) | $(Format-MIRCPCode $release.candidate_id) | $(Format-MIRCPCode $release.candidate_floor) | $(Format-MIRCPCode $release.target) | $(Format-MIRCPCode $release.branch) | $(Format-MIRCPCode $release.state) | $(Format-MIRCPCode $effectiveStatus) | $exceptionCount |")
  }
  $lines.Add("")
  $lines.Add("A state is an admitted fact, not a mutable job status. Every later transition requires its own immutable proof record.")
  return @($lines)
}

function New-MIRCPTodoLines {
  param(
    [Parameter(Mandatory)]$Canonical,
    [Parameter(Mandatory)]$Backport,
    [Parameter(Mandatory)]$Changes,
    [Parameter(Mandatory)]$Incidents,
    [Parameter(Mandatory)]$Tasks,
    [Parameter(Mandatory)][string]$ReviewDate,
    [string]$RepoRoot = ""
  )
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in @(
    "# MIR Executable Queue", "", "> Generated by Control Plane v5 from typed records. Edit the records, not this file.", "",
    "Generated: $ReviewDate", "", "## Release queue", "",
    "| Release | Candidate | Reserved floor | State | Next required state |", "| --- | --- | --- | --- | --- |"
  )) { $lines.Add($line) }
  foreach ($release in @($Canonical, $Backport)) {
    $remaining = @(Get-MIRCPRemainingReleaseStates -Release $release -RepoRoot $RepoRoot)
    $next = if ($remaining.Count -gt 0) { $remaining[0] } else { "complete" }
    $lines.Add("| $(Format-MIRCPCode $release.release) | $(Format-MIRCPCode $release.candidate_id) | $(Format-MIRCPCode $release.candidate_floor) | $(Format-MIRCPCode $release.state) | $(Format-MIRCPCode $next) |")
  }
  $lines.Add("")
  $lines.Add("## Canonical execution programme")
  $lines.Add("")
  $lines.Add("The ordered release train, freeze packet, stop conditions, conditional 2.5.5 projection, and 3.3/2.6 handoff are defined in [MIR 3.2.5 To 2.6 Convergence Programme](docs/releases/3.2.5-to-2.6-convergence-programme.md). The [development readiness record](docs/releases/3.2.5-development-readiness.md) distinguishes implemented development work from open release proof, and the [follow-up audit prompt](docs/maintainer/ultimate-convergence-follow-up-prompt.md) is the worker handoff.")
  $lines.Add("")
  $lines.Add("Change-record IDs are identities, not execution order. Follow the programme's critical path and exit gates.")
  $lines.Add("")
  $lines.Add("## Immediate convergence gates")
  $lines.Add("")
  $lines.Add("| Gate | Current boundary | Completion proof |")
  $lines.Add("| --- | --- | --- |")
  $lines.Add("| ``325-A1a`` deterministic fan-in | Closed by ``INC-2026-0056`` after PR 45 merged | Isolated per-fingerprint artifacts, immutable plan/work/trust receipts for pass and failure, non-authoritative worker pointers, digest and path validation, mixed-plan/order/duplicate regressions, protected content-addressed import, and exact latest-head hosted proof closure |")
  $lines.Add("| ``325-A1b`` temporary Git environment isolation | Implemented locally; admission pending | Markdown-format and artifact-cleanup temporary repositories sanitize inherited ``GIT_INDEX_FILE``, repository/worktree, common-dir, and object-store variables; run the regression with a decoy alternate index |")
  $lines.Add("| ``325-B0`` first complete compatibility slice | Closed by ``CHG-2026-0017`` after PR 51 merged | Research-cost default parity traced through disposition, typed proof, bounded support output, exact Factorio 2.0 adapter disposition, 127/127 local admission, and latest-head hosted closure |")
  $lines.Add("| ``325-B1`` essential research-cost correctness | Terminal after PR 53 | Exact committed-head 128-row local and latest-head hosted proof admits the algebraic/numeric/parser contract, 3.2.3 defaults, ownership dispositions, all transitions, and first/second reload equivalence |")
  $lines.Add("| ``325-D1`` narrowed freeze packet | Terminal; C32 source frozen | Exact revision-5 lineage, package composition, bounded product/target contracts, environment/privacy/localization/performance/manual authorities, release documents, and the 125/125 committed-head plan were admitted before package construction |")
  $lines.Add("| ``325-D2`` deterministic candidate package | Terminal; C32 package built | Two builds from frozen source produced exact archive ``AC81CAD1...A11ADF``, content ``1A2A3738...35A7D``, 1,056,249 bytes, and 301 entries |")
  $lines.Add("| ``325-D3`` candidate qualification | In progress | Full fresh exact-candidate proof, paired performance, manual playtest, protected qualification, seal, and promotion remain distinct gates |")
  $lines.Add("| Minimum compatibility product | Frozen for 3.2.5 | Factorio 2.1 Base/Space Age and explicit non-authorizing Factorio 2.0 dispositions cover every shipped feature in the narrowed release |")
  $lines.Add("| Bounded ecosystem matrix | Frozen for candidate qualification | Exact Base, Space Age, maintained ecosystem, owner, overhaul, and negative/conflict rows retain their version/hash locks, claim levels, fixtures, and budgets |")
  $lines.Add("")
  $plannedChanges = @($Changes | Where-Object { [string]$_.state -in @("proposed", "planned") } | Sort-Object id)
  if ($plannedChanges.Count -gt 0) {
    $lines.Add("| Planned change | Package visible | Targets | Completion boundary |")
    $lines.Add("| --- | --- | --- | --- |")
    foreach ($change in $plannedChanges) {
      $targets = @($change.affected_targets | ForEach-Object { Format-MIRCPCode ([string]$_) }) -join ", "
      $boundary = ([string]$change.migration_impact) -replace '\|', '\|'
      $lines.Add("| $(Format-MIRCPCode $change.id) | $(Format-MIRCPCode ([string][bool]$change.package_visible).ToLowerInvariant()) | $targets | $boundary |")
    }
    $lines.Add("")
  }
  $lines.Add("## Executable TaskNodes")
  $lines.Add("")
  $openTasks = @($Tasks | Where-Object { [string]$_.state -notin @("satisfied", "cancelled") } | Sort-Object id)
  if ($openTasks.Count -eq 0) { $lines.Add("No open TaskNodes.") } else {
    $lines.Add("| Task | Kind | State | Dependencies |")
    $lines.Add("| --- | --- | --- | --- |")
    foreach ($task in $openTasks) { $lines.Add("| $(Format-MIRCPCode $task.id) | $(Format-MIRCPCode $task.kind) | $(Format-MIRCPCode $task.state) | $(@($task.depends_on) -join ', ') |") }
  }
  $lines.Add("")
  $lines.Add("## Active change and incident records")
  $lines.Add("")
  $activeChanges = @($Changes | Where-Object { [string]$_.state -ne "closed" } | Sort-Object id)
  $activeIncidents = @($Incidents | Where-Object { [string]$_.closure.status -notlike "closed*" } | Sort-Object id)
  if (($activeChanges.Count + $activeIncidents.Count) -eq 0) {
    $lines.Add("No active change or incident records.")
  } else {
    $lines.Add("| Record | Type | State | Title |")
    $lines.Add("| --- | --- | --- | --- |")
    foreach ($change in $activeChanges) { $lines.Add("| $(Format-MIRCPCode $change.id) | $(Format-MIRCPCode ("change/$($change.kind)")) | $(Format-MIRCPCode $change.state) | $($change.title) |") }
    foreach ($incident in $activeIncidents) { $lines.Add("| $(Format-MIRCPCode $incident.id) | ``incident`` | $(Format-MIRCPCode $incident.closure.status) | $($incident.title) |") }
  }
  $lines.Add("")
  $lines.Add("## Explicit release obligations")
  $lines.Add("")
  foreach ($obligation in @($Backport.remaining_obligations)) { $lines.Add("- [ ] ``$obligation`` for $(Format-MIRCPCode $Backport.candidate_id)") }
  return @($lines)
}

function Set-MIRCPReleaseNoteIdentityBlock {
  param(
    [Parameter(Mandatory)]$Release,
    [string]$RepoRoot = "",
    [switch]$Check
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $path = Join-Path $repo ([string]$Release.release_notes)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release notes are missing: $($Release.release_notes)" }
  $begin = "<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->"
  $end = "<!-- MIR-CONTROL-PLANE-IDENTITY:END -->"
  $exceptions = @(Get-MIRCPArrayProperty -Object $Release -Name "assurance_exceptions" | ForEach-Object { [string]$_.id })
  $tag = Get-MIRCPTagProof -Release $Release
  $block = @(
    $begin, "## Immutable release identity", "",
    "> Generated from ``path:releases.records/$($Release.release).json``. The typed record is authoritative.", "",
    "| Field | Value |", "| --- | --- |",
    "| State | $(Format-MIRCPCode $Release.state) |",
    "| Candidate | $(Format-MIRCPCode $Release.candidate_id) |",
    "| Package source commit | $(Format-MIRCPCode $Release.package.source_commit) |",
    "| Archive SHA-256 | $(Format-MIRCPCode $Release.package.archive_sha256) |",
    "| Content SHA-256 | $(Format-MIRCPCode $Release.package.content_sha256) |",
    "| Tag | $(Format-MIRCPCode $tag.name) |",
    "| Tag commit | $(Format-MIRCPCode $tag.commit) |",
    "| Assurance exceptions | $(Format-MIRCPCode ($exceptions -join ', ')) |",
    "", $end
  ) -join "`n"
  $content = (Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n").TrimEnd("`n")
  $pattern = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)
  $updated = if ($content -match $pattern) { [regex]::Replace($content, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $block }) } else { $content + "`n`n" + $block }
  $updated += "`n"
  if ($Check) {
    if (((Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n")) -cne $updated) { throw "Generated release-note identity is stale: $($Release.release_notes)" }
    return
  }
  [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($false))
}

function Update-MIRCPViews {
  param(
    [string]$RepoRoot = "",
    [switch]$Check
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $pointer = Read-MIRCPJson -Path ("path:" + [string]$policy.records.current) -RepoRoot $repo
  $releases = @(Get-MIRCPRecordSet -Kind releases -RepoRoot $repo)
  $candidateClosures = @(Get-MIRCPRecordSet -Kind candidate_closures -RepoRoot $repo)
  $changes = @(Get-MIRCPRecordSet -Kind changes -RepoRoot $repo)
  $incidents = @(Get-MIRCPRecordSet -Kind incidents -RepoRoot $repo)
  $tasks = @(Get-MIRCPRecordSet -Kind tasks -RepoRoot $repo)
  $canonical = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.canonical) -RepoRoot $repo
  $backport = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.backport_calibration) -RepoRoot $repo
  $reviewDate = (@($releases.updated_at | ForEach-Object { [datetimeoffset]$_ } | Sort-Object -Descending | Select-Object -First 1)[0]).ToString("yyyy-MM-dd")

  Write-MIRCPJson -Path "path:releases.ledger" -Value (New-MIRCPLegacyReleaseLedger -RepoRoot $repo) -RepoRoot $repo -Check:$Check
  Set-MIRCPGeneratedText -Path ([string]$policy.outputs.current_candidate) -Lines (New-MIRCPCurrentCandidateLines -Release $canonical -ReviewDate $reviewDate -RepoRoot $repo) -RepoRoot $repo -Check:$Check
  Set-MIRCPGeneratedText -Path ([string]$policy.outputs.release_dashboard) -Lines (New-MIRCPDashboardLines -Releases $releases -CandidateClosures $candidateClosures -ReviewDate $reviewDate) -RepoRoot $repo -Check:$Check
  Set-MIRCPGeneratedText -Path ([string]$policy.outputs.todo) -Lines (New-MIRCPTodoLines -Canonical $canonical -Backport $backport -Changes $changes -Incidents $incidents -Tasks $tasks -ReviewDate $reviewDate -RepoRoot $repo) -RepoRoot $repo -Check:$Check

  $branchStatus = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-generated-branch-status-v1"
    generated_from = @("path:releases.records/*.json", "path:releases.candidate-closures/*.json")
    branches = @($releases | Sort-Object branch, release | ForEach-Object {
      [pscustomobject][ordered]@{
        branch = [string]$_.branch
        release = [string]$_.release
        candidate_id = [string]$_.candidate_id
        candidate_floor = [string]$_.candidate_floor
        target = [string]$_.target
        state = [string]$_.state
        effective_status = Get-MIRCPEffectiveReleaseStatus -Release $_ -CandidateClosures $candidateClosures
        source_commit = [string]$_.package.source_commit
      }
    })
  }
  Write-MIRCPJson -Path ([string]$policy.outputs.branch_status) -Value $branchStatus -RepoRoot $repo -Check:$Check

  $publication = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-generated-publication-checklist-v1"
    generated_from = @("path:releases.current", "path:releases.records/$($canonical.release).json")
    release = [string]$canonical.release
    candidate_id = [string]$canonical.candidate_id
    candidate_floor = [string]$canonical.candidate_floor
    state = [string]$canonical.state
    remaining_states = @(Get-MIRCPRemainingReleaseStates -Release $canonical -RepoRoot $repo)
    assurance_exceptions = @(Get-MIRCPArrayProperty -Object $canonical -Name "assurance_exceptions")
    publication_admitted = ([string]$canonical.state -in @("published", "publicly-verified"))
  }
  Write-MIRCPJson -Path ([string]$policy.outputs.publication_checklist) -Value $publication -RepoRoot $repo -Check:$Check

  $backportQueue = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-generated-backport-queue-v1"
    generated_from = @("path:releases.records/$($backport.release).json", [string]$backport.backport_manifest)
    release = [string]$backport.release
    candidate_id = [string]$backport.candidate_id
    target = [string]$backport.target
    state = [string]$backport.state
    remaining_states = @(Get-MIRCPRemainingReleaseStates -Release $backport -RepoRoot $repo)
    remaining_obligations = @($backport.remaining_obligations)
  }
  Write-MIRCPJson -Path ([string]$policy.outputs.backport_queue) -Value $backportQueue -RepoRoot $repo -Check:$Check
  Set-MIRCPReleaseNoteIdentityBlock -Release $canonical -RepoRoot $repo -Check:$Check

  return [pscustomobject][ordered]@{status=if ($Check) { "current" } else { "updated" }; releases=$releases.Count; changes=$changes.Count; incidents=$incidents.Count; tasks=$tasks.Count}
}
