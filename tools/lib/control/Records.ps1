function Get-MIRCPPolicy {
  param([string]$RepoRoot = "")
  return Read-MIRCPJson -Path ".mir/control-plane/control-plane.json" -RepoRoot $RepoRoot
}

function Get-MIRCPRecordSet {
  param(
    [Parameter(Mandatory)][ValidateSet("changes", "candidate_closures", "incidents", "tasks", "releases", "transitions")][string]$Kind,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $relative = [string]$policy.records.$Kind
  $root = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $root -Filter *.json -File | Where-Object Name -ne "current.json" | Sort-Object Name | ForEach-Object {
    Read-MIRCPJson -Path $_.FullName -RepoRoot $repo
  })
}

function Assert-MIRCPRequiredProperties {
  param(
    [Parameter(Mandatory)]$Record,
    [Parameter(Mandatory)][string[]]$Names,
    [Parameter(Mandatory)][string]$Context
  )
  foreach ($name in $Names) {
    $property = $Record.PSObject.Properties[$name]
    if ($null -eq $property -or $null -eq $property.Value) {
      throw "$Context is missing required property '$name'."
    }
  }
}

function Assert-MIRCPRecords {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  if ([int]$policy.schema -ne 1 -or [string]$policy.policy_id -ne "mir-control-plane-v5") {
    throw "Control-plane policy schema or identity is invalid."
  }

  $changes = @(Get-MIRCPRecordSet -Kind changes -RepoRoot $repo)
  $candidateClosures = @(Get-MIRCPRecordSet -Kind candidate_closures -RepoRoot $repo)
  $incidents = @(Get-MIRCPRecordSet -Kind incidents -RepoRoot $repo)
  $releases = @(Get-MIRCPRecordSet -Kind releases -RepoRoot $repo)
  $transitions = @(Get-MIRCPRecordSet -Kind transitions -RepoRoot $repo)
  if ($changes.Count -eq 0 -or $releases.Count -eq 0) { throw "Control-plane change and release authorities must not be empty." }

  foreach ($change in $changes) {
    Assert-MIRCPRequiredProperties -Record $change -Names @("schema", "id", "title", "kind", "package_visible", "domains_read", "domains_written", "affected_targets", "test_obligations", "state") -Context "ChangeRecord"
    if ([string]$change.id -notmatch '^CHG-[0-9]{4}-[0-9]{4}$') { throw "Invalid ChangeRecord id: $($change.id)" }
  }
  foreach ($incident in $incidents) {
    Assert-MIRCPRequiredProperties -Record $incident -Names @("schema", "id", "title", "state", "failing_environment", "root_cause", "regression_propositions", "candidate_binding", "closure") -Context "IncidentRecord"
    if ([string]$incident.id -notmatch '^INC-[0-9]{4}-[0-9]{4}$') { throw "Invalid IncidentRecord id: $($incident.id)" }
  }

  $states = @($policy.release_states | ForEach-Object { [string]$_ })
  foreach ($release in $releases) {
    Assert-MIRCPRequiredProperties -Record $release -Names @("schema", "release", "candidate_id", "target", "branch", "state", "package", "proofs", "updated_at") -Context "ReleaseRecord"
    if ($states -notcontains [string]$release.state) { throw "Release $($release.release) uses unknown state '$($release.state)'." }
    $stateIndex = [Array]::IndexOf($states, [string]$release.state)
    $requiredPackageFields = if ($stateIndex -eq 0) {
      @()
    } elseif ($stateIndex -eq 1) {
      @("source_commit", "source_tree", "source_sha256")
    } else {
      @("source_commit", "source_tree", "source_sha256", "archive", "archive_sha256", "content_sha256", "bytes", "entries")
    }
    foreach ($field in $requiredPackageFields) {
      if ($null -eq $release.package.PSObject.Properties[$field]) { throw "Release $($release.release) package is missing '$field' for state '$($release.state)'." }
    }
    foreach ($arrayField in @("assurance_exceptions", "remaining_obligations", "incident_ids")) {
      $property = $release.PSObject.Properties[$arrayField]
      if ($null -ne $property -and @($property.Value | Where-Object { $null -eq $_ }).Count -gt 0) {
        throw "Release $($release.release) array '$arrayField' contains null."
      }
    }
  }

  $pointer = Read-MIRCPJson -Path ([string]$policy.records.current) -RepoRoot $repo
  $known = @($releases | ForEach-Object { [string]$_.release })
  foreach ($role in @($pointer.roles.PSObject.Properties)) {
    if ($known -notcontains [string]$role.Value) {
      throw "Current release role '$($role.Name)' points to unknown record '$($role.Value)'."
    }
  }
  $closureKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($closure in $candidateClosures) {
    Assert-MIRCPRequiredProperties -Record $closure -Names @("schema", "id", "release", "candidate_id", "disposition", "reason", "successor", "package", "remaining_obligations_disposition", "evidence_policy", "closed_at") -Context "CandidateClosureRecord"
    $key = "$([string]$closure.release)/$([string]$closure.candidate_id)"
    if (-not $closureKeys.Add($key)) { throw "Duplicate CandidateClosureRecord for $key." }
    $source = @($releases | Where-Object { [string]$_.release -eq [string]$closure.release -and [string]$_.candidate_id -eq [string]$closure.candidate_id })
    if ($source.Count -ne 1) { throw "CandidateClosureRecord $($closure.id) does not identify one ReleaseRecord." }
    if ([string]$source[0].state -in @("tagged", "published", "publicly-verified")) { throw "Published release $key cannot be closed as an unpublished candidate." }
    foreach ($field in @("source_commit", "source_tree", "source_sha256", "archive", "archive_sha256", "content_sha256", "bytes", "entries")) {
      if ([string]$closure.package.$field -cne [string]$source[0].package.$field) { throw "CandidateClosureRecord $($closure.id) package field '$field' differs from its immutable ReleaseRecord." }
    }
    $successor = @($releases | Where-Object { [string]$_.release -eq [string]$closure.successor.release -and [string]$_.candidate_id -eq [string]$closure.successor.candidate_id })
    if ($successor.Count -ne 1) { throw "CandidateClosureRecord $($closure.id) does not identify one successor ReleaseRecord." }
    if ([string]$pointer.roles.canonical -eq [string]$closure.release) { throw "Canonical release $($closure.release) is closed and cannot remain active." }
  }
  foreach ($transition in $transitions) {
    Assert-MIRCPRequiredProperties -Record $transition -Names @("schema", "id", "release", "from", "to", "admission", "proofs", "recorded_at") -Context "ReleaseTransition"
    if ([string]$transition.id -notmatch '^REL-[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9-]+$') { throw "Invalid ReleaseTransition id: $($transition.id)" }
    if ($known -notcontains [string]$transition.release) { throw "Transition $($transition.id) points to unknown release $($transition.release)." }
    $fromIndex = [Array]::IndexOf($states, [string]$transition.from)
    $toIndex = [Array]::IndexOf($states, [string]$transition.to)
    if ($fromIndex -lt 0 -or $toIndex -le $fromIndex) { throw "Transition $($transition.id) does not advance through known release states." }
    if ([string]$transition.admission -eq "proof" -and $toIndex -ne ($fromIndex + 1)) { throw "Proof transition $($transition.id) skips a required state." }
    if (@($transition.proofs).Count -eq 0) { throw "Transition $($transition.id) has no admission proof." }
    if ([string]$transition.admission -eq "grandfathered-import" -and [string]::IsNullOrWhiteSpace([string]$transition.exception)) { throw "Grandfathered transition $($transition.id) requires an explicit exception." }
  }
  $taskGraph = Assert-MIRCPTaskGraph -RepoRoot $repo
  return [pscustomobject][ordered]@{
    changes = $changes.Count
    incidents = $incidents.Count
    releases = $releases.Count
    candidate_closures = $candidateClosures.Count
    transitions = $transitions.Count
    tasks = $taskGraph.tasks
    executable_tasks = $taskGraph.executable
    aggregate_tasks = $taskGraph.aggregates
    states = $states.Count
  }
}

function Get-MIRCPCommitPackageSourceHash {
  param(
    [Parameter(Mandatory)][string]$Commit,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-cp-package-" + [guid]::NewGuid().ToString("N"))
  $archive = Join-Path $temporaryRoot "source.zip"
  $source = Join-Path $temporaryRoot "source"
  try {
    [void](New-Item -ItemType Directory -Force -Path $temporaryRoot)
    $roots = @(Get-MIRPackageSourceRoots)
    & git -C $repo archive --format=zip --output=$archive $Commit -- @roots 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract package roots at commit $Commit." }
    Expand-Archive -LiteralPath $archive -DestinationPath $source
    return Get-MIRPackageSourceFingerprint -RepoRoot $source
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
      Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
  }
}

function Assert-MIRCPPackageFreeze {
  param(
    [string]$RepoRoot = "",
    [switch]$AllLocks
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $authority = Read-MIRCPJson -Path ".mir/control-plane/package-locks.json" -RepoRoot $repo
  if ([int]$authority.schema -ne 1 -or [string]$authority.authority -ne "mir-control-plane-v5-package-locks") {
    throw "Package-lock authority is invalid."
  }
  $info = Read-MIRCPJson -Path "info.json" -RepoRoot $repo
  $target = [string]$info.factorio_version
  $current = Read-MIRCPJson -Path ".mir/releases/current.json" -RepoRoot $repo
  $canonicalRelease = [string]$current.roles.canonical
  $release = Read-MIRCPJson -Path ".mir/releases/$canonicalRelease.json" -RepoRoot $repo
  $active = @($authority.locks | Where-Object {
    [string]$_.target -eq $target -and [string]$_.release -eq $canonicalRelease
  })
  if ([string]$release.state -eq "planned") {
    if ($active.Count -ne 0) { throw "Planned canonical release $canonicalRelease must not have a frozen package lock." }
    return [pscustomobject][ordered]@{status="development-unlocked";release=$canonicalRelease;target=$target}
  }
  if ($active.Count -ne 1) {
    throw "Expected exactly one package lock for canonical release $canonicalRelease on target $target."
  }
  $currentHash = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($currentHash -ne [string]$active[0].package_source_sha256) {
    throw "Current package roots changed from lock $($active[0].id): expected $($active[0].package_source_sha256), observed $currentHash."
  }
  $archivePath = Join-Path $repo ([string]$active[0].archive)
  if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
    if ((Get-MIRCPSha256File -Path $archivePath) -ne [string]$active[0].archive_sha256) { throw "Locked archive hash changed: $($active[0].archive)" }
    if ((Get-Item -LiteralPath $archivePath).Length -ne [long]$active[0].archive_bytes) { throw "Locked archive size changed: $($active[0].archive)" }
  }
  if ($AllLocks) {
    foreach ($lock in @($authority.locks)) {
      $commitHash = Get-MIRCPCommitPackageSourceHash -Commit ([string]$lock.package_source_commit) -RepoRoot $repo
      if ($commitHash -ne [string]$lock.package_source_sha256) {
        throw "Committed package source for lock $($lock.id) differs: expected $($lock.package_source_sha256), observed $commitHash."
      }
    }
  }
  return [pscustomobject][ordered]@{lock_id=[string]$active[0].id; target=$target; package_source_sha256=$currentHash}
}
