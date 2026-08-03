function Get-MIRCPCurrentRelease {
  param(
    [ValidateSet("canonical", "backport_calibration")][string]$Role = "canonical",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $pointer = Read-MIRCPJson -Path ([string]$policy.records.current) -RepoRoot $repo
  $release = [string]$pointer.roles.$Role
  return Read-MIRCPJson -Path ".mir/releases/$release.json" -RepoRoot $repo
}

function Get-MIRCPReleaseByVersion {
  param(
    [Parameter(Mandatory)][string]$Release,
    [string]$RepoRoot = ""
  )
  return Read-MIRCPJson -Path ".mir/releases/$Release.json" -RepoRoot $RepoRoot
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
  $pointer = Read-MIRCPJson -Path ".mir/releases/current.json" -RepoRoot $repo
  $canonical = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.canonical) -RepoRoot $repo
  $backport = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.backport_calibration) -RepoRoot $repo
  $publishedModern = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.published_factorio_2_1) -RepoRoot $repo
  $publishedBackport = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.published_factorio_2_0) -RepoRoot $repo
  $updated = @($canonical.updated_at, $backport.updated_at, $publishedModern.updated_at, $publishedBackport.updated_at | ForEach-Object { [datetimeoffset]$_ } | Sort-Object -Descending | Select-Object -First 1)
  return [pscustomobject][ordered]@{
    schema = 1
    authority = "canonical-release-ledger"
    generated_from = @(
      ".mir/releases/current.json",
      ".mir/releases/$($canonical.release).json",
      ".mir/releases/$($backport.release).json",
      ".mir/releases/$($publishedModern.release).json",
      ".mir/releases/$($publishedBackport.release).json"
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
      publication_checklist = ".mir/generated/publication-checklist.json"
      backport_queue = ".mir/generated/backport-queue.json"
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
    "| Candidate | $(Format-MIRCPCode $Release.candidate_id) |",
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
    [Parameter(Mandatory)][string]$ReviewDate
  )
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in @(
    "---", "title: `"MIR Control Plane Dashboard`"", "status: current", "applies_to: `"release-engineering`"",
    "audience: release-manager", "doc_type: reference", "owner: mir-maintainers", "last_reviewed: $ReviewDate",
    "supersedes: []", "superseded_by: []", "---", "", "# MIR Control Plane Dashboard", "",
    "> Generated from ``.mir/releases/*.json``, ChangeRecords, IncidentRecords, and TaskNodes. Machine records are authoritative.", "",
    "## Releases", "", "| Release | Candidate | Target | Branch | State | Exceptions |", "| --- | --- | --- | --- | --- | ---: |"
  )) { $lines.Add($line) }
  foreach ($release in @($Releases | Sort-Object @{Expression={ [version]$_.release }; Descending=$true})) {
    $exceptionCount = if ($null -ne $release.PSObject.Properties["assurance_exceptions"]) { @($release.assurance_exceptions).Count } else { 0 }
    $lines.Add("| $(Format-MIRCPCode $release.release) | $(Format-MIRCPCode $release.candidate_id) | $(Format-MIRCPCode $release.target) | $(Format-MIRCPCode $release.branch) | $(Format-MIRCPCode $release.state) | $exceptionCount |")
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
    "| Release | Candidate | State | Next required state |", "| --- | --- | --- | --- |"
  )) { $lines.Add($line) }
  foreach ($release in @($Canonical, $Backport)) {
    $remaining = @(Get-MIRCPRemainingReleaseStates -Release $release -RepoRoot $RepoRoot)
    $next = if ($remaining.Count -gt 0) { $remaining[0] } else { "complete" }
    $lines.Add("| $(Format-MIRCPCode $release.release) | $(Format-MIRCPCode $release.candidate_id) | $(Format-MIRCPCode $release.state) | $(Format-MIRCPCode $next) |")
  }
  $lines.Add("")
  $lines.Add("## Executable TaskNodes")
  $lines.Add("")
  $openTasks = @($Tasks | Where-Object { [string]$_.state -notin @("satisfied", "cancelled") } | Sort-Object id)
  if ($openTasks.Count -eq 0) { $lines.Add("No open TaskNodes.") } else {
    $lines.Add("| Task | Kind | State | Dependencies |")
    $lines.Add("| --- | --- | --- | --- |")
    foreach ($task in $openTasks) { $lines.Add("| $(Format-MIRCPCode $task.id) | $(Format-MIRCPCode $task.kind) | $(Format-MIRCPCode $task.state) | $(@($task.depends_on) -join ', ') |") }
  }
  $lines.Add("")
  $lines.Add("## Open change and incident records")
  $lines.Add("")
  foreach ($change in @($Changes | Where-Object { [string]$_.state -notin @("verified", "closed") } | Sort-Object id)) { $lines.Add("- [ ] $(Format-MIRCPCode $change.id) — $($change.title) ($(Format-MIRCPCode $change.state))") }
  foreach ($incident in @($Incidents | Where-Object { [string]$_.closure.status -ne "closed" } | Sort-Object id)) { $lines.Add("- [ ] $(Format-MIRCPCode $incident.id) — $($incident.title); closure $(Format-MIRCPCode $incident.closure.status)") }
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
    "> Generated from ``.mir/releases/$($Release.release).json``. The typed record is authoritative.", "",
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
  $pointer = Read-MIRCPJson -Path ([string]$policy.records.current) -RepoRoot $repo
  $releases = @(Get-MIRCPRecordSet -Kind releases -RepoRoot $repo)
  $changes = @(Get-MIRCPRecordSet -Kind changes -RepoRoot $repo)
  $incidents = @(Get-MIRCPRecordSet -Kind incidents -RepoRoot $repo)
  $tasks = @(Get-MIRCPRecordSet -Kind tasks -RepoRoot $repo)
  $canonical = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.canonical) -RepoRoot $repo
  $backport = Get-MIRCPReleaseByVersion -Release ([string]$pointer.roles.backport_calibration) -RepoRoot $repo
  $reviewDate = (@($releases.updated_at | ForEach-Object { [datetimeoffset]$_ } | Sort-Object -Descending | Select-Object -First 1)[0]).ToString("yyyy-MM-dd")

  Write-MIRCPJson -Path ".mir/releases.json" -Value (New-MIRCPLegacyReleaseLedger -RepoRoot $repo) -RepoRoot $repo -Check:$Check
  Set-MIRCPGeneratedText -Path ([string]$policy.outputs.current_candidate) -Lines (New-MIRCPCurrentCandidateLines -Release $canonical -ReviewDate $reviewDate -RepoRoot $repo) -RepoRoot $repo -Check:$Check
  Set-MIRCPGeneratedText -Path ([string]$policy.outputs.release_dashboard) -Lines (New-MIRCPDashboardLines -Releases $releases -ReviewDate $reviewDate) -RepoRoot $repo -Check:$Check
  Set-MIRCPGeneratedText -Path ([string]$policy.outputs.todo) -Lines (New-MIRCPTodoLines -Canonical $canonical -Backport $backport -Changes $changes -Incidents $incidents -Tasks $tasks -ReviewDate $reviewDate -RepoRoot $repo) -RepoRoot $repo -Check:$Check

  $branchStatus = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-generated-branch-status-v1"
    generated_from = ".mir/releases/*.json"
    branches = @($releases | Sort-Object branch, release | ForEach-Object { [pscustomobject][ordered]@{branch=[string]$_.branch; release=[string]$_.release; candidate_id=[string]$_.candidate_id; target=[string]$_.target; state=[string]$_.state; source_commit=[string]$_.package.source_commit} })
  }
  Write-MIRCPJson -Path ([string]$policy.outputs.branch_status) -Value $branchStatus -RepoRoot $repo -Check:$Check

  $publication = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-generated-publication-checklist-v1"
    generated_from = @(".mir/releases/current.json", ".mir/releases/$($canonical.release).json")
    release = [string]$canonical.release
    candidate_id = [string]$canonical.candidate_id
    state = [string]$canonical.state
    remaining_states = @(Get-MIRCPRemainingReleaseStates -Release $canonical -RepoRoot $repo)
    assurance_exceptions = @(Get-MIRCPArrayProperty -Object $canonical -Name "assurance_exceptions")
    publication_admitted = ([string]$canonical.state -in @("published", "publicly-verified"))
  }
  Write-MIRCPJson -Path ([string]$policy.outputs.publication_checklist) -Value $publication -RepoRoot $repo -Check:$Check

  $backportQueue = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-generated-backport-queue-v1"
    generated_from = @(".mir/releases/$($backport.release).json", [string]$backport.backport_manifest)
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
