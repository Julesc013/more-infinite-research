function Get-MIRCPTaskRecords {
  param([string]$RepoRoot = "")
  return @(Get-MIRCPRecordSet -Kind tasks -RepoRoot $RepoRoot)
}

function Get-MIRCPTaskMap {
  param([string]$RepoRoot = "")
  $map = @{}
  foreach ($task in @(Get-MIRCPTaskRecords -RepoRoot $RepoRoot)) {
    $id = [string]$task.id
    if ($map.ContainsKey($id)) { throw "Duplicate TaskNode id: $id" }
    $map[$id] = $task
  }
  return $map
}

function Get-MIRCPTaskTopologicalOrder {
  param(
    [Parameter(Mandatory)][hashtable]$TaskMap,
    [string[]]$SelectedIds = @()
  )
  $wanted = if ($SelectedIds.Count -gt 0) { @($SelectedIds | Select-Object -Unique) } else { @($TaskMap.Keys) }
  $remaining = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($id in $wanted) { [void]$remaining.Add($id) }
  $resolved = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $ordered = [Collections.Generic.List[string]]::new()
  while ($remaining.Count -gt 0) {
    $ready = @($remaining | Where-Object {
      $id = $_
      @($TaskMap[$id].depends_on | Where-Object { $remaining.Contains([string]$_) }).Count -eq 0
    } | Sort-Object)
    if ($ready.Count -eq 0) { throw "TaskNode graph contains a dependency cycle: $(@($remaining) -join ', ')" }
    foreach ($id in $ready) {
      [void]$remaining.Remove($id)
      [void]$resolved.Add($id)
      $ordered.Add($id)
    }
  }
  return @($ordered)
}

function Assert-MIRCPTaskGraph {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $tasks = @(Get-MIRCPTaskRecords -RepoRoot $repo)
  if ($tasks.Count -eq 0) { throw "TaskNode authority is empty." }
  $map = Get-MIRCPTaskMap -RepoRoot $repo
  $freshness = Read-MIRCPJson -Path ".mir/control-plane/freshness.json" -RepoRoot $repo
  $knownFreshness = @($freshness.classes.PSObject.Properties.Name)
  $owners = @((Get-MIRCPRecordSet -Kind changes -RepoRoot $repo).id) + @((Get-MIRCPRecordSet -Kind incidents -RepoRoot $repo).id)
  $changes = @(Get-MIRCPRecordSet -Kind changes -RepoRoot $repo)
  $domains = Read-MIRCPJson -Path ".mir/control-plane/domains.json" -RepoRoot $repo
  $domainIds = @($domains.domains | ForEach-Object { [string]$_.id })
  $duplicateDomains = @($domainIds | Group-Object | Where-Object Count -gt 1)
  if ($duplicateDomains.Count -gt 0) { throw "Duplicate semantic domains: $($duplicateDomains.Name -join ', ')." }
  foreach ($domain in @($domains.domains)) {
    $domainOwner = $domains.domain_owners.PSObject.Properties[[string]$domain.id]
    if ($null -eq $domainOwner -or [string]::IsNullOrWhiteSpace([string]$domainOwner.Value)) {
      throw "Semantic domain $($domain.id) has no declared owner."
    }
    foreach ($downstream in @($domain.downstream)) {
      if ($domainIds -notcontains [string]$downstream) {
        throw "Semantic domain $($domain.id) has unknown downstream domain $downstream."
      }
    }
  }
  $knownObligations = @($changes | ForEach-Object { @($_.test_obligations) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  foreach ($alias in @($domains.obligation_aliases.PSObject.Properties)) {
    if ($domainIds -notcontains [string]$alias.Name -and $knownObligations -notcontains [string]$alias.Name) {
      throw "Obligation alias source '$($alias.Name)' is not a semantic domain or declared change obligation."
    }
    foreach ($target in @($alias.Value)) {
      if (-not $map.ContainsKey([string]$target)) { throw "Obligation alias '$($alias.Name)' targets unknown TaskNode $target." }
    }
  }
  $ownership = Read-MIRCPJson -Path ".mir/control-plane/ownership.json" -RepoRoot $repo
  foreach ($rule in @($ownership.owners)) {
    foreach ($domain in @($rule.writes)) {
      if ($domainIds -notcontains [string]$domain) {
        throw "Ownership rule $($rule.pattern) writes unknown semantic domain $domain."
      }
    }
  }
  foreach ($composition in @($ownership.compositions)) {
    foreach ($domain in @($composition.writes)) {
      if ($domainIds -notcontains [string]$domain) {
        throw "Ownership composition $($composition.module) writes unknown semantic domain $domain."
      }
    }
  }
  foreach ($task in $tasks) {
    Assert-MIRCPRequiredProperties -Record $task -Names @("schema", "id", "owner", "kind", "layer", "depends_on", "reads", "writes", "effective_inputs", "outputs", "resource_class", "freshness", "side_effect", "retry", "completion_proof", "state") -Context "TaskNode"
    if ([string]$task.id -notmatch '^[a-z0-9][a-z0-9.-]+$') { throw "Invalid TaskNode id: $($task.id)" }
    if ($owners -notcontains [string]$task.owner) { throw "TaskNode $($task.id) has unknown owner $($task.owner)." }
    if ($knownFreshness -notcontains [string]$task.freshness) { throw "TaskNode $($task.id) uses unknown freshness $($task.freshness)." }
    foreach ($domain in @($task.reads) + @($task.writes)) {
      if ($domainIds -notcontains [string]$domain) { throw "TaskNode $($task.id) references unknown semantic domain $domain." }
    }
    foreach ($dependency in @($task.depends_on)) {
      if (-not $map.ContainsKey([string]$dependency)) { throw "TaskNode $($task.id) depends on unknown node $dependency." }
      if ([string]$dependency -eq [string]$task.id) { throw "TaskNode $($task.id) depends on itself." }
    }
    if ([string]$task.kind -eq "aggregate") {
      if ($null -ne $task.PSObject.Properties["command"]) { throw "Aggregate TaskNode $($task.id) must not execute a command." }
      $members = @($task.aggregate_members | ForEach-Object { [string]$_ } | Sort-Object)
      $dependencies = @($task.depends_on | ForEach-Object { [string]$_ } | Sort-Object)
      if (($members -join "`n") -cne ($dependencies -join "`n")) { throw "Aggregate TaskNode $($task.id) members must exactly match its dependencies." }
    } else {
      if ($null -eq $task.PSObject.Properties["command"]) { throw "Executable TaskNode $($task.id) has no command." }
      $scriptIndex = [Array]::IndexOf(@($task.command.arguments), "-File")
      if ($scriptIndex -ge 0 -and ($scriptIndex + 1) -lt @($task.command.arguments).Count) {
        $scriptPath = Join-Path $repo ([string]$task.command.arguments[$scriptIndex + 1])
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "TaskNode $($task.id) command script is missing: $scriptPath" }
      }
    }
  }
  $order = @(Get-MIRCPTaskTopologicalOrder -TaskMap $map)
  return [pscustomobject][ordered]@{
    tasks = $tasks.Count
    executable = @($tasks | Where-Object kind -ne "aggregate").Count
    aggregates = @($tasks | Where-Object kind -eq "aggregate").Count
    topological_order = $order
  }
}

function Test-MIRCPOwnershipPattern {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Pattern
  )
  $normalized = $Path.Replace("\", "/")
  $wildcard = [Management.Automation.WildcardPattern]::new($Pattern, [Management.Automation.WildcardOptions]::IgnoreCase)
  return $wildcard.IsMatch($normalized)
}

function Get-MIRCPChangedPaths {
  param(
    [string]$ChangedSince = "",
    [string[]]$ChangedPath = @(),
    [string]$RepoRoot = ""
  )
  if ($ChangedPath.Count -gt 0) { return @($ChangedPath | ForEach-Object { $_.Replace("\", "/") } | Sort-Object -Unique) }
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  if ([string]::IsNullOrWhiteSpace($ChangedSince)) { $ChangedSince = "HEAD~1" }
  $tracked = @(& git -C $repo diff --name-only $ChangedSince HEAD 2>$null)
  if ($LASTEXITCODE -ne 0) { throw "Unable to compute changed paths from $ChangedSince." }
  $working = @(& git -C $repo diff --name-only HEAD 2>$null)
  $untracked = @(& git -C $repo ls-files --others --exclude-standard 2>$null)
  return @($tracked + $working + $untracked | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-MIRCPSemanticImpact {
  param(
    [Parameter(Mandatory)][string[]]$ChangedPaths,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $ownership = Read-MIRCPJson -Path ".mir/control-plane/ownership.json" -RepoRoot $repo
  $domainAuthority = Read-MIRCPJson -Path ".mir/control-plane/domains.json" -RepoRoot $repo
  $modules = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $direct = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $unknown = [Collections.Generic.List[string]]::new()
  foreach ($path in $ChangedPaths) {
    try { $match = Resolve-MIRPathOwnership -Path $path -Ownership $ownership }
    catch { $unknown.Add($path); continue }
    if ($null -eq $match) { $unknown.Add($path); continue }
    [void]$modules.Add([string]$match.module)
    foreach ($domain in @($match.writes)) { [void]$direct.Add([string]$domain) }
  }
  $affected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($domain in $direct) { [void]$affected.Add($domain) }
  $domainMap = @{}
  foreach ($domain in @($domainAuthority.domains)) { $domainMap[[string]$domain.id] = @($domain.downstream | ForEach-Object { [string]$_ }) }
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($domain in @($affected)) {
      foreach ($downstream in @($domainMap[$domain])) {
        if ($affected.Add($downstream)) { $changed = $true }
      }
    }
  }
  return [pscustomobject][ordered]@{
    changed_paths = @($ChangedPaths | Sort-Object -Unique)
    modules = @($modules | Sort-Object)
    direct_domains = @($direct | Sort-Object)
    affected_domains = @($affected | Sort-Object)
    unknown_paths = @($unknown | Sort-Object)
    governance_failure = ($unknown.Count -gt 0)
    unknown_policy = [string]$ownership.unknown_policy
  }
}

function Add-MIRCPTaskPrerequisiteClosure {
  param(
    [Parameter(Mandatory)][Collections.Generic.HashSet[string]]$Selected,
    [Parameter(Mandatory)][hashtable]$TaskMap
  )
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($id in @($Selected)) {
      foreach ($dependency in @($TaskMap[$id].depends_on)) {
        if ($Selected.Add([string]$dependency)) { $changed = $true }
      }
    }
  }
}

function Get-MIRCPRepositoryInputFiles {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $paths = @(& git -C $repo ls-files --cached --others --exclude-standard 2>$null)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate governed repository inputs." }
  return @($paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function ConvertTo-MIRCPInputGlobRegex {
  param([Parameter(Mandatory)][string]$Pattern)
  $escaped = [regex]::Escape($Pattern.Replace("\", "/"))
  $escaped = $escaped.Replace("\*\*/", "(?:.*/)?")
  $escaped = $escaped.Replace("\*\*", ".*")
  $escaped = $escaped.Replace("\*", "[^/]*")
  $escaped = $escaped.Replace("\?", "[^/]")
  return "^$escaped$"
}

function Get-MIRCPInputFileIdentity {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [hashtable]$IdentityCache = @{},
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $cacheKey = $RelativePath.ToLowerInvariant()
  if ($IdentityCache.ContainsKey($cacheKey)) { return $IdentityCache[$cacheKey] }
  $path = Join-Path $repo $RelativePath
  $extension = [IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
  $isText = $extension -in @(".cfg", ".json", ".jsonl", ".lua", ".md", ".ps1", ".psm1", ".txt", ".yml", ".yaml") -or [IO.Path]::GetFileName($RelativePath) -eq "LICENSE"
  if ($isText) {
    $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $identity = [pscustomobject][ordered]@{path=$RelativePath;kind="text";bytes=$bytes.Length;sha256=(Get-MIRCPSha256Text -Value $text)}
    [void]($IdentityCache[$cacheKey] = $identity)
    return $identity
  }
  $item = Get-Item -LiteralPath $path
  $identity = [pscustomobject][ordered]@{path=$RelativePath;kind="binary";bytes=[int64]$item.Length;sha256=(Get-MIRCPSha256File -Path $path)}
  [void]($IdentityCache[$cacheKey] = $identity)
  return $identity
}

function Get-MIRCPEffectiveInputManifest {
  param(
    [Parameter(Mandatory)]$Task,
    [Parameter(Mandatory)]$ReleaseRecord,
    [Parameter(Mandatory)][string]$Target,
    [string[]]$RepositoryFiles = @(),
    [string[]]$SourceRepositoryFiles = @(),
    [hashtable]$IdentityCache = @{},
    [hashtable]$SourceIdentityCache = @{},
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $sourceRepo = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { $repo } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  $sourceCommit = ([string](& git -C $sourceRepo rev-parse HEAD 2>$null)).Trim()
  if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw "Unable to resolve immutable source repository identity." }
  $controllerCommit = ([string](& git -C $repo rev-parse HEAD 2>$null)).Trim()
  if ($LASTEXITCODE -ne 0 -or $controllerCommit -notmatch '^[0-9a-fA-F]{40}$') { throw "Unable to resolve control-plane repository identity." }
  if ($RepositoryFiles.Count -eq 0) { $RepositoryFiles = @(Get-MIRCPRepositoryInputFiles -RepoRoot $repo) }
  if ($SourceRepositoryFiles.Count -eq 0) { $SourceRepositoryFiles = @(Get-MIRCPRepositoryInputFiles -RepoRoot $sourceRepo) }
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($input in @($Task.effective_inputs | ForEach-Object { [string]$_ } | Sort-Object -Unique)) {
    if ($input -in @("candidate-archive", "context:candidate")) {
      $rows.Add([pscustomobject][ordered]@{input=$input;kind="release-candidate";release=[string]$ReleaseRecord.release;archive_sha256=[string]$ReleaseRecord.package.archive_sha256;content_sha256=[string]$ReleaseRecord.package.content_sha256;bytes=[int64]$ReleaseRecord.package.bytes;entries=[int]$ReleaseRecord.package.entries})
      continue
    }
    if ($input -eq "package-source") {
      $rows.Add([pscustomobject][ordered]@{input=$input;kind="release-package-source";source_commit=[string]$ReleaseRecord.package.source_commit;source_tree=[string]$ReleaseRecord.package.source_tree;source_sha256=[string]$ReleaseRecord.package.source_sha256})
      continue
    }
    if ($input -in @("prior-release-archive", "factorio-installation", "mod-closure")) {
      $rows.Add([pscustomobject][ordered]@{input=$input;kind="runtime-context-input";resolution="worker-required";target=$Target})
      continue
    }
    if ($input.StartsWith("result:", [StringComparison]::Ordinal)) {
      $rows.Add([pscustomobject][ordered]@{input=$input;kind="aggregate-result"})
      continue
    }
    $scope = if ($input.StartsWith("source:", [StringComparison]::Ordinal)) { "source" } else { "control-plane" }
    $pattern = if ($scope -eq "source") { $input.Substring("source:".Length) } else { $input }
    $inputRepo = if ($scope -eq "source") { $sourceRepo } else { $repo }
    # Logical path IDs belong to the locked control plane. Historical source
    # commits may predate the repository path catalog, but the resolved
    # relative path must still be evaluated against that exact source tree.
    $pattern = Resolve-MIRCPPathToken -Path $pattern -RepoRoot $repo
    $inputFiles = if ($scope -eq "source") { $SourceRepositoryFiles } else { $RepositoryFiles }
    $inputCache = if ($scope -eq "source") { $SourceIdentityCache } else { $IdentityCache }
    $regex = ConvertTo-MIRCPInputGlobRegex -Pattern $pattern
    $matchedFiles = @($inputFiles | Where-Object { $_ -match $regex } | Sort-Object -Unique)
    $containsWildcard = $pattern.Contains("*") -or $pattern.Contains("?")
    if ($scope -eq "source" -and -not $containsWildcard -and $matchedFiles.Count -eq 0) {
      if ($sourceCommit -eq $controllerCommit) { throw "Exact-source TaskNode input is missing: $pattern" }
      $rows.Add([pscustomobject][ordered]@{
        input = $input
        kind = "source-absent"
        scope = "source"
        source_commit = $sourceCommit
        reason = "not-present-in-immutable-source-commit"
      })
      continue
    }
    $files = [Collections.Generic.List[object]]::new()
    foreach ($matchedFile in $matchedFiles) {
      $files.Add((Get-MIRCPInputFileIdentity -RelativePath ([string]$matchedFile) -IdentityCache $inputCache -RepoRoot $inputRepo))
    }
    $row = [ordered]@{input=$input;kind="repository-content";scope=$scope;matches=@($files)}
    if ($scope -eq "source") { $row.source_commit = $sourceCommit }
    $rows.Add([pscustomobject]$row)
  }
  $identity = [pscustomobject][ordered]@{schema=1;task_id=[string]$Task.id;target=$Target;inputs=@($rows)}
  $fileCount = @($rows | ForEach-Object { if ([string]$_.kind -eq "repository-content") { @($_.matches).Count } else { 0 } } | Measure-Object -Sum).Sum
  return [pscustomobject][ordered]@{schema=1;sha256=(Get-MIRCPSha256Object -Value $identity);file_count=[int]$fileCount;rows=@($rows)}
}

function New-MIRCPPlan {
  param(
    [ValidateSet("changed", "qualify-incremental", "calibrate-fresh", "rerun-failure")][string]$Mode = "changed",
    [string]$ChangedSince = "",
    [string[]]$ChangedPath = @(),
    [string[]]$FailedTask = @(),
    [string]$EvidenceIndex = "",
    [string]$TrustClass = "",
    [string]$Target = "2.1",
    [string]$Release = "",
    [ValidateSet("verification", "release", "publication", "all")][string]$Stage = "verification",
    [switch]$SelectionOnly,
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $sourceRepo = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { $repo } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  $graph = Assert-MIRCPTaskGraph -RepoRoot $repo
  $taskMap = Get-MIRCPTaskMap -RepoRoot $repo
  if ([string]::IsNullOrWhiteSpace($Release)) { $Release = [string](Get-MIRCPCurrentRelease -RepoRoot $repo).release }
  $releaseRecord = Get-MIRCPReleaseByVersion -Release $Release -RepoRoot $repo
  $eligible = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $allowedActivations = switch ($Stage) {
    "verification" { @("verification") }
    "release" { @("release") }
    "publication" { @("release", "publication") }
    default { @("verification", "release", "publication") }
  }
  foreach ($task in $taskMap.Values) {
    $activation = if ($null -eq $task.PSObject.Properties["activation"]) { "verification" } else { [string]$task.activation }
    $targetEligible = $null -eq $task.PSObject.Properties["targets"] -or @($task.targets | ForEach-Object { [string]$_ }) -contains $Target
    if ($targetEligible -and $activation -in $allowedActivations) { [void]$eligible.Add([string]$task.id) }
  }
  $paths = @(Get-MIRCPChangedPaths -ChangedSince $ChangedSince -ChangedPath $ChangedPath -RepoRoot $repo)
  $impact = Get-MIRCPSemanticImpact -ChangedPaths $paths -RepoRoot $repo
  $selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $reasons = @{}
  function Select-Task([string]$Id, [string]$Reason) {
    if (-not $taskMap.ContainsKey($Id)) { throw "Planner selected unknown TaskNode $Id." }
    if (-not $eligible.Contains($Id)) { return }
    [void]$selected.Add($Id)
    if (-not $reasons.ContainsKey($Id)) { $reasons[$Id] = [Collections.Generic.List[string]]::new() }
    if (-not $reasons[$Id].Contains($Reason)) { $reasons[$Id].Add($Reason) }
  }

  if ($Mode -eq "calibrate-fresh" -or $impact.governance_failure) {
    $fullSelectionReason = if ($impact.governance_failure) { "unknown ownership requires conservative full selection" } else { "fresh independent calibration" }
    foreach ($id in $eligible) { Select-Task $id $fullSelectionReason }
  } else {
    $affectedDomains = @($impact.affected_domains)
    foreach ($task in $taskMap.Values) {
      if ([string]$task.kind -eq "aggregate") { continue }
      $matches = @($task.reads | Where-Object { $affectedDomains -contains [string]$_ })
      if ($matches.Count -gt 0) { Select-Task ([string]$task.id) "reads affected domain(s): $($matches -join ', ')" }
    }
    $domainAuthority = Read-MIRCPJson -Path ".mir/control-plane/domains.json" -RepoRoot $repo
    foreach ($change in @(Get-MIRCPRecordSet -Kind changes -RepoRoot $repo | Where-Object { [string]$_.state -notin @("verified", "closed") })) {
      foreach ($obligation in @($change.test_obligations)) {
        $property = $domainAuthority.obligation_aliases.PSObject.Properties[[string]$obligation]
        if ($null -ne $property) { foreach ($id in @($property.Value)) { Select-Task ([string]$id) "required by $($change.id) obligation $obligation" } }
      }
    }
  }

  if ($Mode -eq "qualify-incremental") {
    foreach ($task in $taskMap.Values) {
      if ([string]$task.freshness -in @("candidate-bound", "transition-bound", "protected-release-fresh", "always-fresh")) { Select-Task ([string]$task.id) "release qualification freshness: $($task.freshness)" }
    }
    Select-Task "static.full" "candidate qualification aggregate"
  }
  if ($Mode -eq "rerun-failure") {
    foreach ($failed in $FailedTask) { Select-Task $failed "failed task requested for repair rerun" }
    $changed = $true
    while ($changed) {
      $changed = $false
      foreach ($task in $taskMap.Values) {
        if (@($task.depends_on | Where-Object { $selected.Contains([string]$_) }).Count -gt 0 -and $selected.Add([string]$task.id)) {
          if (-not $reasons.ContainsKey([string]$task.id)) { $reasons[[string]$task.id] = [Collections.Generic.List[string]]::new() }
          $reasons[[string]$task.id].Add("downstream of failed or invalidated prerequisite")
          $changed = $true
        }
      }
    }
    foreach ($task in $taskMap.Values) {
      if ([string]$task.freshness -in @("protected-release-fresh", "always-fresh")) { Select-Task ([string]$task.id) "remaining release-fresh obligation" }
    }
  }

  $beforeClosure = @($selected)
  Add-MIRCPTaskPrerequisiteClosure -Selected $selected -TaskMap $taskMap
  foreach ($id in @($selected)) {
    if ($beforeClosure -notcontains $id -and -not $reasons.ContainsKey($id)) {
      $reasons[$id] = [Collections.Generic.List[string]]::new()
      $reasons[$id].Add("prerequisite of selected task")
    }
  }
  $order = @(Get-MIRCPTaskTopologicalOrder -TaskMap $taskMap -SelectedIds @($selected))
  $repositoryFiles = @(Get-MIRCPRepositoryInputFiles -RepoRoot $repo)
  $sourceRepositoryFiles = @(Get-MIRCPRepositoryInputFiles -RepoRoot $sourceRepo)
  $inputIdentityCache = @{}
  $sourceInputIdentityCache = @{}
  $rows = @($order | ForEach-Object {
    $task = $taskMap[$_]
    $inputManifest = if ($SelectionOnly) {
      [pscustomobject][ordered]@{sha256=(Get-MIRCPSha256Object -Value @($task.effective_inputs));file_count=0}
    } else {
      Get-MIRCPEffectiveInputManifest -Task $task -ReleaseRecord $releaseRecord -Target $Target -RepositoryFiles $repositoryFiles -SourceRepositoryFiles $sourceRepositoryFiles -IdentityCache $inputIdentityCache -SourceIdentityCache $sourceInputIdentityCache -SourceRepoRoot $sourceRepo -RepoRoot $repo
    }
    $effectiveInputSha256 = Get-MIRCPSha256Object -Value ([pscustomobject][ordered]@{task=$task; effective_input_manifest_sha256=[string]$inputManifest.sha256; release=[string]$releaseRecord.release; candidate_sha256=[string]$releaseRecord.package.archive_sha256; target=$Target})
    $evidenceDecision = if ([string]$task.kind -eq "aggregate") {
      [pscustomobject][ordered]@{action="AGGREGATE"; reason="result-only aggregate"; object_digest=""; followup=""}
    } elseif ($null -ne (Get-Command Resolve-MIRCPTaskEvidenceAction -ErrorAction SilentlyContinue)) {
      Resolve-MIRCPTaskEvidenceAction -Task $task -EffectiveInputSha256 $effectiveInputSha256 -Mode $Mode -EvidenceIndex $EvidenceIndex -TrustClass $TrustClass -RepoRoot $repo
    } else {
      [pscustomobject][ordered]@{action="RUN"; reason="evidence resolver not loaded"; object_digest=""; followup=""}
    }
    [pscustomobject][ordered]@{
      id = [string]$task.id
      kind = [string]$task.kind
      layer = [string]$task.layer
      action = [string]$evidenceDecision.action
      freshness = [string]$task.freshness
      resource_class = [string]$task.resource_class
      depends_on = @($task.depends_on | Where-Object { $selected.Contains([string]$_) })
      reasons = @($reasons[[string]$task.id])
      effective_input_sha256 = $effectiveInputSha256
      effective_input_manifest_sha256 = [string]$inputManifest.sha256
      effective_input_file_count = [int]$inputManifest.file_count
      evidence_decision = $evidenceDecision
    }
  })
  $body = [pscustomobject][ordered]@{
    schema = 1
    policy_id = "mir-control-plane-v5"
    mode = $Mode
    target = $Target
    stage = $Stage
    release = $Release
    candidate_id = [string]$releaseRecord.candidate_id
    candidate_sha256 = [string]$releaseRecord.package.archive_sha256
    control_plane_abis = (Get-MIRCPPolicy -RepoRoot $repo).component_abis
    impact = $impact
    task_count = $rows.Count
    tasks = $rows
    aggregate_is_result_only = $true
  }
  $planId = Get-MIRCPSha256Object -Value $body
  return [pscustomobject][ordered]@{schema=1; plan_id=$planId; plan=$body}
}

function Assert-MIRCPMutationCalibration {
  param([string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Read-MIRCPJson -Path ".mir/control-plane/mutation-calibration.json" -RepoRoot $repo
  if ([int]$authority.schema -ne 1 -or [int]$authority.false_negative_budget -ne 0) { throw "Impact mutation calibration must require zero false negatives." }
  $checked = 0
  foreach ($case in @($authority.cases)) {
    $result = New-MIRCPPlan -Mode changed -ChangedPath @($case.changed_paths) -SelectionOnly -RepoRoot $repo
    $selected = @($result.plan.tasks.id | ForEach-Object { [string]$_ })
    $requiredTasks = if ($null -ne $case.PSObject.Properties["required_tasks"]) { @($case.required_tasks) } else { @() }
    $forbiddenTasks = if ($null -ne $case.PSObject.Properties["forbidden_tasks"]) { @($case.forbidden_tasks) } else { @() }
    foreach ($required in $requiredTasks) {
      if ($selected -notcontains [string]$required) { throw "Impact calibration $($case.id) missed required TaskNode $required." }
    }
    foreach ($forbidden in $forbiddenTasks) {
      if ($selected -contains [string]$forbidden) { throw "Impact calibration $($case.id) selected forbidden TaskNode $forbidden." }
    }
    if ($null -ne $case.PSObject.Properties["required_policy"]) {
      if (-not [bool]$result.plan.impact.governance_failure -or [string]$result.plan.impact.unknown_policy -ne [string]$case.required_policy) {
        throw "Impact calibration $($case.id) did not apply required unknown policy $($case.required_policy)."
      }
    }
    $checked++
  }
  return [pscustomobject][ordered]@{cases=$checked; false_negative_budget=[int]$authority.false_negative_budget}
}
