function Get-MIRCPPolicy {
  param([string]$RepoRoot = "")
  return Read-MIRCPJson -Path "path:control.policy" -RepoRoot $RepoRoot
}

function Get-MIRCPRecordSet {
  param(
    [Parameter(Mandatory)][ValidateSet("changes", "candidate_closures", "incidents", "tasks", "releases", "transitions")][string]$Kind,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $relative = Resolve-MIRCPPathId -Id ([string]$policy.records.$Kind) -RepoRoot $repo
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
    $candidateFloorPattern = '^(?:C[1-9][0-9]*|[0-9]+\.[0-9]+-P[1-9][0-9]*)$'
    $candidateIdentityPattern = '^(?:C[1-9][0-9]*|[0-9]+\.[0-9]+-P[1-9][0-9]*|[0-9]+\.[0-9]+\.[0-9]+-final)$'
    if ([string]$release.state -eq "planned") {
      if ([string]$release.candidate_id -ne "not-assigned" -or
          $null -eq $release.PSObject.Properties["candidate_floor"] -or
          [string]$release.candidate_floor -notmatch $candidateFloorPattern) {
        throw "Planned release $($release.release) must have an unassigned candidate identity and a valid reserved candidate floor."
      }
    } elseif ([string]$release.candidate_id -notmatch $candidateIdentityPattern) {
      throw "Release $($release.release) must bind an exact candidate identity after planning."
    }
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

  $pointer = Read-MIRCPJson -Path ("path:" + [string]$policy.records.current) -RepoRoot $repo
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
    $successorCandidate = if ($null -ne $closure.successor.PSObject.Properties["candidate_id"]) {
      [string]$closure.successor.candidate_id
    } else { [string]$closure.successor.candidate_floor }
    $successor = @($releases | Where-Object {
      [string]$_.release -eq [string]$closure.successor.release -and
      ([string]$_.candidate_id -eq $successorCandidate -or [string]$_.candidate_floor -eq $successorCandidate)
    })
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

. (Join-Path $PSScriptRoot 'PackageSourceAtCommit.ps1')

function Get-MIRCPCommitPackageSourceHash {
  param(
    [Parameter(Mandatory)][string]$Commit,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  return Get-MIRCPCommitPackageSourceHashV2 -Commit $Commit -RepoRoot $repo
}

function Get-MIRCPGitOutputIdentity {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$Arguments
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = "git"
  $startInfo.WorkingDirectory = $RepoRoot
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.UseShellExecute = $false
  foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add($argument) }

  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $bytes = [IO.MemoryStream]::new()
  try {
    $process.StandardOutput.BaseStream.CopyTo($bytes)
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Git command failed: $errorText" }
    $material = $bytes.ToArray()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
      $hash = [BitConverter]::ToString($sha.ComputeHash($material)).Replace("-", "")
    } finally {
      $sha.Dispose()
    }
    return [pscustomobject][ordered]@{sha256=$hash;bytes=[long]$material.Length}
  } finally {
    $bytes.Dispose()
    $process.Dispose()
  }
}

function Get-MIRCPGitBlobIdentity {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Blob
  )

  if ($Blob -cnotmatch '^[a-f0-9]{40}$') { throw "Invalid Git blob identity: $Blob" }
  return Get-MIRCPGitOutputIdentity -RepoRoot $RepoRoot -Arguments @("cat-file", "blob", $Blob)
}

function Test-MIRCPApprovedBootstrapCorrection {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Lock,
    [Parameter(Mandatory)][string]$ObservedPackageSourceSha256
  )

  $recordPath = Join-Path $RepoRoot ".mir\releases\waves\mir4-r0\MIR4-Approved-Bootstrap-Correction-CompositeV2.json"
  if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) { return $false }
  . (Join-Path $RepoRoot "tools\lib\mir4\BootstrapMaterialization.ps1")
  $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
  if (-not (Test-MIR4BootstrapRecordHash -Record $record) -or
      [int]$record.schema -ne 2 -or
      [string]$record.kind -cne "MIR4ApprovedBootstrapCorrectionDeltaV2" -or
      [string]$record.authority_family -cne "MIRApprovedDeltaV1" -or
      [string]$record.status -cne "approved-local-bootstrap-correction-composite-only" -or
      (@($record.findings) -join "|") -cne "MIR3-TERM-0033|MIR3-TERM-0032" -or
      [string]$record.target_key -cne "f210" -or
      [bool]$record.public_output_authorized -or
      [bool]$record.authority_scope.release_admission_authorized -or
      [bool]$record.authority_scope.signing_or_sealing_authorized -or
      [bool]$record.authority_scope.publication_authorized -or
      [bool]$record.authority_scope.transitive_target_inheritance_authorized) {
    return $false
  }
  $imports = @($record.imports)
  if ($imports.Count -ne 1 -or
      [string]$imports[0].path -cne ".mir/releases/waves/mir4-r0/MIR4-Approved-Bootstrap-Correction-MIR3-TERM-0033V1.json") {
    return $false
  }
  $importPath = Join-Path $RepoRoot ([string]$imports[0].path)
  if (-not (Test-Path -LiteralPath $importPath -PathType Leaf) -or
      (Get-MIR4BootstrapTextSha256 -Path $importPath) -cne [string]$imports[0].text_sha256) {
    return $false
  }
  $importRecord = Get-Content -Raw -LiteralPath $importPath | ConvertFrom-Json
  if (-not (Test-MIR4BootstrapRecordHash -Record $importRecord) -or
      [string]$importRecord.record_sha256 -cne [string]$imports[0].record_sha256) {
    return $false
  }
  if ([string]$record.predecessor.release -cne [string]$Lock.release -or
      [string]$record.predecessor.archive_sha256 -cne [string]$Lock.archive_sha256 -or
      [string]$record.predecessor.content_sha256 -cne [string]$Lock.package_source_sha256 -or
      [string]$record.base_source.commit -cne [string]$Lock.package_source_commit -or
      [string]$record.base_source.tree -cne [string]$Lock.package_source_tree -or
      [string]$record.correction_commit -cne [string]$record.integration_source.commit -or
      @($record.deltas).Count -ne 4) {
    return $false
  }

  $integrationTree = @(& git -C $RepoRoot rev-parse "$([string]$record.integration_source.commit)^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or $integrationTree.Count -ne 1 -or
      [string]$integrationTree[0] -cne [string]$record.integration_source.tree) {
    return $false
  }

  $roots = @(Get-MIRPackageSourceRoots)
  $expected = @($record.deltas.path | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $integrationChanged = @(& git -C $RepoRoot diff --name-only ([string]$Lock.package_source_commit) ([string]$record.integration_source.commit) -- @roots)
  if ($LASTEXITCODE -ne 0) { return $false }
  $integrationChanged = @($integrationChanged | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
  $currentChanged = @(& git -C $RepoRoot diff --name-only ([string]$Lock.package_source_commit) -- @roots)
  if ($LASTEXITCODE -ne 0) { return $false }
  $currentChanged = @($currentChanged | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object -Unique)
  if ($expected.Count -ne 4 -or
      ($integrationChanged -join '|') -cne ($expected -join '|') -or
      ($currentChanged -join '|') -cne ($expected -join '|')) {
    return $false
  }

  $patchArguments = @(
    "diff", "--no-ext-diff", "--no-color", "--full-index",
    [string]$Lock.package_source_commit, [string]$record.integration_source.commit, "--"
  ) + @($record.deltas.path | ForEach-Object { [string]$_ })
  $patchIdentity = Get-MIRCPGitOutputIdentity -RepoRoot $RepoRoot -Arguments $patchArguments
  if ([string]$patchIdentity.sha256 -cne [string]$record.canonical_patch.sha256 -or
      [long]$patchIdentity.bytes -ne [long]$record.canonical_patch.bytes) {
    return $false
  }

  foreach ($delta in @($record.deltas)) {
    $path = [string]$delta.path
    $currentPath = Join-Path $RepoRoot $path
    $beforeBlob = @(& git -C $RepoRoot rev-parse "$([string]$Lock.package_source_commit):$path" 2>$null)
    $integrationBlob = @(& git -C $RepoRoot rev-parse "$([string]$record.integration_source.commit):$path" 2>$null)
    $afterBlob = @(& git -C $RepoRoot hash-object -- $currentPath 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $currentPath -PathType Leaf) -or
        $beforeBlob.Count -ne 1 -or $integrationBlob.Count -ne 1 -or $afterBlob.Count -ne 1 -or
        [string]$beforeBlob[0] -cne [string]$delta.before_blob -or
        [string]$integrationBlob[0] -cne [string]$delta.after_blob -or
        [string]$afterBlob[0] -cne [string]$delta.after_blob) {
      return $false
    }
    $beforeIdentity = Get-MIRCPGitBlobIdentity -RepoRoot $RepoRoot -Blob ([string]$delta.before_blob)
    $afterIdentity = Get-MIRCPGitBlobIdentity -RepoRoot $RepoRoot -Blob ([string]$delta.after_blob)
    if ([string]$beforeIdentity.sha256 -cne [string]$delta.before_sha256 -or
        [long]$beforeIdentity.bytes -ne [long]$delta.before_bytes -or
        [string]$afterIdentity.sha256 -cne [string]$delta.after_sha256 -or
        [long]$afterIdentity.bytes -ne [long]$delta.after_bytes) {
      return $false
    }
  }

  return -not [string]::IsNullOrWhiteSpace($ObservedPackageSourceSha256)
}

function Assert-MIRCPPackageFreeze {
  param(
    [string]$RepoRoot = "",
    [switch]$AllLocks,
    [switch]$AllowDevelopmentWorkingTree
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $authority = Read-MIRCPJson -Path ".mir/control-plane/package-locks.json" -RepoRoot $repo
  if ([int]$authority.schema -ne 1 -or [string]$authority.authority -ne "mir-control-plane-v5-package-locks") {
    throw "Package-lock authority is invalid."
  }
  $info = Read-MIRCPJson -Path "info.json" -RepoRoot $repo
  $target = [string]$info.factorio_version
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $current = Read-MIRCPJson -Path ("path:" + [string]$policy.records.current) -RepoRoot $repo
  $canonicalRelease = [string]$current.roles.canonical
  $release = Read-MIRCPJson -Path "path:releases.records/$canonicalRelease.json" -RepoRoot $repo
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
    $developmentContext = $false
    if ($AllowDevelopmentWorkingTree) {
      $profilePath = Join-Path $repo "validation\profiles\factorio-$target.json"
      if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw "Development package-freeze exception has no target profile: $target"
      }
      $profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
      $authorityRelative = ([string]$profile.execution_context).Replace('\', '/')
      if ([string]$profile.execution_context_mode -ne 'development-context' -or
          $authorityRelative -cne 'spec/execution/mir4-4.1-development-context-v1.json') {
        throw "Development package-freeze exception lacks an exact safe execution context: $target"
      }
      $candidateAuthorityPath = Join-Path $repo $authorityRelative
      if (-not (Test-Path -LiteralPath $candidateAuthorityPath -PathType Leaf)) {
        throw "Development package-freeze execution context is absent: $authorityRelative"
      }
      . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
      $candidateAuthorityRaw = Get-Content -Raw -LiteralPath $candidateAuthorityPath
      if (-not ($candidateAuthorityRaw | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-development-execution-context-v1.schema.json'))) {
        throw 'Development package-freeze execution context schema is invalid.'
      }
      $candidateAuthority = $candidateAuthorityRaw | ConvertFrom-Json -Depth 100 -DateKind String
      if (-not (Test-MIR4BootstrapRecordHash -Record $candidateAuthority) -or
          [string]$candidateAuthority.kind -ne 'MIR4DevelopmentExecutionContextV1' -or
          [string]$candidateAuthority.status -ne 'active-private-mir4.1-qualification-no-release-authority' -or
          @($candidateAuthority.allowed) -notcontains 'repository-development' -or
          @($candidateAuthority.forbidden) -notcontains 'production-signing' -or
          @($candidateAuthority.forbidden) -notcontains 'tagging' -or
          @($candidateAuthority.forbidden) -notcontains 'publication' -or
          @($candidateAuthority.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
        throw 'Development package-freeze execution context violates its no-release-authority boundary.'
      }
      $developmentContext = $true
    }
    if (-not $developmentContext -and
        -not (Test-MIRCPApprovedBootstrapCorrection -RepoRoot $repo -Lock $active[0] -ObservedPackageSourceSha256 $currentHash)) {
      throw "Current package roots changed from lock $($active[0].id): expected $($active[0].package_source_sha256), observed $currentHash."
    }
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
  return [pscustomobject][ordered]@{
    lock_id=[string]$active[0].id
    target=$target
    package_source_sha256=$currentHash
    status=if ($currentHash -eq [string]$active[0].package_source_sha256) { 'published-lock-exact' } elseif ($AllowDevelopmentWorkingTree) { 'published-lock-preserved-development-context-active' } else { 'approved-bootstrap-correction' }
  }
}
