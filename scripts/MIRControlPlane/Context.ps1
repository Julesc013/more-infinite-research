function Get-MIRCPReleaseTransitionForContext {
  param(
    [Parameter(Mandatory)][string]$Release,
    [string]$RepoRoot = ""
  )
  $records = @(Get-MIRCPRecordSet -Kind transitions -RepoRoot $RepoRoot | Where-Object { [string]$_.release -eq $Release } | Sort-Object recorded_at)
  if ($records.Count -eq 0) { throw "Release $Release has no governed transition record." }
  return $records[-1]
}

function Get-MIRCPQualificationBundleForContext {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  foreach ($proof in @($ReleaseRecord.proofs.candidate_qualification)) {
    if ($null -eq $proof) { continue }
    if ($null -eq $proof.PSObject.Properties["path"]) { continue }
    $path = Join-Path $repo ([string]$proof.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $bundle = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $archiveSha = if ($null -ne $bundle.PSObject.Properties["candidate_descriptor"]) { [string]$bundle.candidate_descriptor.sha256 } else { [string]$bundle.candidate.archive_sha256 }
    if ($archiveSha -eq [string]$ReleaseRecord.package.archive_sha256) {
      return [pscustomobject][ordered]@{path=$path; record=$bundle; sha256=(Get-MIRCPSha256File -Path $path)}
    }
  }
  return $null
}

function Get-MIRCPTrackedWorktreeSha256 {
  param([Parameter(Mandatory)][string]$SourceRepoRoot)
  $source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
  $changes = @(& git -C $source status --porcelain --untracked-files=no)
  if ($LASTEXITCODE -ne 0) { throw "Could not inspect qualification source worktree state." }
  if ($changes.Count -eq 0) { return "" }
  $diff = ((& git -C $source diff --binary --no-ext-diff HEAD | Out-String).Replace("`r`n", "`n").Replace("`r", "`n"))
  if ($LASTEXITCODE -ne 0) { throw "Could not fingerprint qualification source tracked changes." }
  return Get-MIRCPSha256Text -Value $diff
}

function Get-MIRCPQualificationSourceIdentity {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $source = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
  $commit = ([string](& git -C $source rev-parse HEAD)).Trim()
  $tree = ([string](& git -C $source rev-parse "HEAD^{tree}")).Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$' -or $tree -notmatch '^[0-9a-f]{40}$') { throw "Qualification source is not an exact Git checkout." }
  $untracked = @(& git -C $source ls-files --others --exclude-standard)
  if ($LASTEXITCODE -ne 0 -or $untracked.Count -ne 0) { throw "Qualification source checkout has untracked governed files." }
  $worktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $source
  $sourceIsController = $source.TrimEnd('\') -eq $repo.TrimEnd('\')
  if (-not [string]::IsNullOrWhiteSpace($worktreeSha256) -and ([string]$ReleaseRecord.target -eq "2.0" -or -not $sourceIsController)) {
    throw "Qualification source checkout has tracked changes."
  }
  $role = "candidate-source"
  $proofDigest = ""
  if ([string]$ReleaseRecord.target -eq "2.0") {
    $proofRows = @($ReleaseRecord.proofs.backport_reconstruction)
    if ($proofRows.Count -ne 1) { throw "Factorio 2.0 qualification requires exactly one governed reconstruction proof." }
    $proofPath = Join-Path $repo ([string]$proofRows[0].path)
    if (-not (Test-Path -LiteralPath $proofPath -PathType Leaf)) { throw "Backport reconstruction proof is missing." }
    $proofDigest = Get-MIRCPSha256File -Path $proofPath
    if ($proofDigest -ne [string]$proofRows[0].sha256) { throw "Backport reconstruction proof digest differs from release authority." }
    $proof = Get-Content -Raw -LiteralPath $proofPath | ConvertFrom-Json
    if ([string]$proof.status -ne "passed" -or [string]$proof.target_release -ne [string]$ReleaseRecord.release -or
        [string]$proof.target_candidate -ne [string]$ReleaseRecord.candidate_id -or
        [string]$proof.archive_sha256 -ne [string]$ReleaseRecord.package.archive_sha256 -or
        $commit -ne [string]$proof.integration_commit -or $tree -ne [string]$proof.integration_tree) {
      throw "Qualification source does not match the exact governed dual-parent integration lineage."
    }
    $role = "dual-parent-integration"
  }
  return [pscustomobject][ordered]@{role=$role;commit=$commit;tree=$tree;worktree_sha256=$worktreeSha256;proof_sha256=$proofDigest}
}

function New-MIRCPContextDomainManifest {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    $QualificationBundle,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  if ($null -ne $QualificationBundle -and $null -ne $QualificationBundle.record.PSObject.Properties["domain_manifest"]) {
    return $QualificationBundle.record.domain_manifest
  }
  $authority = Read-MIRCPJson -Path ".mir/control-plane/domains.json" -RepoRoot $repo
  return [pscustomobject][ordered]@{
    schema = 1
    policy_id = "mir-control-plane-v5-context-domain-manifest"
    target = [string]$ReleaseRecord.target
    version = [string]$ReleaseRecord.release
    artifact = [pscustomobject][ordered]@{
      state = "locked"
      sha256 = [string]$ReleaseRecord.package.archive_sha256
      content_sha256 = [string]$ReleaseRecord.package.content_sha256
    }
    domain_authority_sha256 = Get-MIRCPSha256Object -Value $authority
    domains = [pscustomobject][ordered]@{
      package = [pscustomobject][ordered]@{file_count=[int]$ReleaseRecord.package.entries; sha256=[string]$ReleaseRecord.package.content_sha256}
    }
    manifest_sha256 = Get-MIRCPSha256Object -Value ([pscustomobject][ordered]@{target=[string]$ReleaseRecord.target; archive=[string]$ReleaseRecord.package.archive_sha256; content=[string]$ReleaseRecord.package.content_sha256; authority=(Get-MIRCPSha256Object -Value $authority)})
  }
}

function New-MIRCPEnvironmentLocks {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    $QualificationBundle,
    [Parameter(Mandatory)]$TargetProfile,
    [Parameter(Mandatory)][string]$TargetProfilePath,
    [Parameter(Mandatory)][string]$ScenarioRegistrySha256,
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $sourceRepo = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { $repo } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  $factorioLocks = [Collections.Generic.List[object]]::new()
  if ($null -ne $QualificationBundle -and $null -ne $QualificationBundle.record.PSObject.Properties["evidence"]) {
    foreach ($evidence in @($QualificationBundle.record.evidence)) {
      if ($null -eq $evidence.inputs -or $null -eq $evidence.inputs.PSObject.Properties["factorio"]) { continue }
      $factorio = $evidence.inputs.factorio
      $lock = [pscustomobject][ordered]@{
        source = "candidate-qualification-evidence"
        installation_sha256 = [string]$factorio.sha256
        binary = [pscustomobject][ordered]@{bytes=[int64]$factorio.binary.size_bytes; sha256=[string]$factorio.binary.sha256}
        official_data = [pscustomobject][ordered]@{file_count=[int]$factorio.official_data.file_count; sha256=[string]$factorio.official_data.sha256}
      }
      if (@($factorioLocks | Where-Object { (Get-MIRCPSha256Object -Value $_) -eq (Get-MIRCPSha256Object -Value $lock) }).Count -eq 0) { $factorioLocks.Add($lock) }
    }
  }
  if ($factorioLocks.Count -eq 0 -and [string]$ReleaseRecord.target -eq "2.0") {
    $legacyPath = Join-Path $repo ".mir/evidence/2.4.9-local-automated-qualification.json"
    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
      $legacy = Get-Content -Raw -LiteralPath $legacyPath | ConvertFrom-Json
      $factorioLocks.Add([pscustomobject][ordered]@{
        source = "target-line-baseline-2.4.9"
        version = [string]$legacy.factorio.version
        binary = [pscustomobject][ordered]@{sha256=[string]$legacy.factorio.binary_sha256}
        evidence_sha256 = Get-MIRCPSha256File -Path $legacyPath
      })
    }
  }
  return [pscustomobject][ordered]@{
    schema = 1
    target = [string]$ReleaseRecord.target
    target_profile = [pscustomobject][ordered]@{
      id = [string]$TargetProfile.id
      path = "target-profile.json"
      sha256 = Get-MIRCPSha256File -Path $TargetProfilePath
    }
    factorio = @($factorioLocks)
    fixture_authority_sha256 = Get-MIRCPSha256File -Path (Join-Path $sourceRepo ".mir/fixtures.yml")
    scenario_registry_sha256 = $ScenarioRegistrySha256
  }
}

function Get-MIRCPContextMemberRows {
  param([Parameter(Mandatory)][string]$Directory)
  $excluded = @("context-manifest.json", "context-digest.txt")
  return @(Get-ChildItem -LiteralPath $Directory -File | Where-Object { $_.Name -notin $excluded } | Sort-Object Name | ForEach-Object {
    [pscustomobject][ordered]@{path=$_.Name; bytes=[int64]$_.Length; sha256=(Get-MIRCPSha256File -Path $_.FullName)}
  })
}

function Get-MIRCPContextIdentity {
  param([Parameter(Mandatory)]$Manifest)
  return [pscustomobject][ordered]@{
    context_abi = [int]$Manifest.context_abi
    mode = [string]$Manifest.mode
    target = [string]$Manifest.target
    release = [string]$Manifest.release
    candidate_id = [string]$Manifest.candidate_id
    plan_id = [string]$Manifest.plan_id
    members = @($Manifest.members)
  }
}

function Assert-MIRCPVerificationContext {
  param([Parameter(Mandatory)][string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $manifestPath = Join-Path $resolved "context-manifest.json"
  $digestPath = Join-Path $resolved "context-digest.txt"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $digestPath -PathType Leaf)) { throw "Verification context is incomplete: $resolved" }
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $expectedId = Get-MIRCPSha256Object -Value (Get-MIRCPContextIdentity -Manifest $manifest)
  $digestText = (Get-Content -Raw -LiteralPath $digestPath).Trim()
  if ([string]$manifest.context_id -ne $expectedId -or $digestText -ne $expectedId) { throw "Verification context digest does not match its immutable manifest." }
  $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($member in @($manifest.members)) {
    if (-not $seen.Add([string]$member.path)) { throw "Verification context repeats member $($member.path)." }
    $memberPath = Join-Path $resolved ([string]$member.path)
    if (-not (Test-Path -LiteralPath $memberPath -PathType Leaf)) { throw "Verification context member is missing: $($member.path)" }
    $item = Get-Item -LiteralPath $memberPath
    if ([int64]$item.Length -ne [int64]$member.bytes -or (Get-MIRCPSha256File -Path $memberPath) -ne [string]$member.sha256) { throw "Verification context member changed: $($member.path)" }
  }
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $resolved "candidate-descriptor.json") | ConvertFrom-Json
  if ((Get-MIRCPSha256File -Path (Join-Path $resolved "candidate.zip")) -ne [string]$descriptor.archive_sha256) { throw "Verification context candidate bytes do not match the descriptor." }
  return [pscustomobject][ordered]@{status="valid"; context_id=$expectedId; path=$resolved; members=@($manifest.members).Count; plan_id=[string]$manifest.plan_id}
}

function New-MIRCPVerificationContext {
  param(
    [ValidateSet("changed", "qualify-incremental", "calibrate-fresh", "rerun-failure")][string]$Mode = "qualify-incremental",
    [string]$Target = "2.1",
    [string]$Release = "",
    [ValidateSet("verification", "release", "publication", "all")][string]$Stage = "verification",
    [string]$CandidatePath = "",
    [string]$SourceRepoRoot = "",
    [string]$OutputRoot = "out/verification-context",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $sourceRepo = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { $repo } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  if ([string]::IsNullOrWhiteSpace($Release)) { $Release = [string](Get-MIRCPCurrentRelease -RepoRoot $repo).release }
  $releaseRecord = Get-MIRCPReleaseByVersion -Release $Release -RepoRoot $repo
  Write-Verbose "[context] resolved release $Release"
  if ([string]$releaseRecord.target -ne $Target) { throw "Release $Release targets $($releaseRecord.target), not requested target $Target." }
  if ([string]::IsNullOrWhiteSpace($CandidatePath)) { $CandidatePath = [string]$releaseRecord.package.archive }
  $candidate = if ([IO.Path]::IsPathRooted($CandidatePath)) { [IO.Path]::GetFullPath($CandidatePath) } else { [IO.Path]::GetFullPath((Join-Path $repo $CandidatePath)) }
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "Verification context candidate is missing: $candidate" }
  if ((Get-MIRCPSha256File -Path $candidate) -ne [string]$releaseRecord.package.archive_sha256) { throw "Verification context candidate does not match release authority." }
  $qualificationSource = Get-MIRCPQualificationSourceIdentity -ReleaseRecord $releaseRecord -SourceRepoRoot $sourceRepo -RepoRoot $repo
  $plan = New-MIRCPPlan -Mode $Mode -ChangedPath @("scripts/MIRControlPlane/Context.ps1") -Target $Target -Release $Release -Stage $Stage -SourceRepoRoot $sourceRepo -RepoRoot $repo
  Write-Verbose "[context] materialized plan $($plan.plan_id)"
  $registryPath = Join-Path $sourceRepo "validation/generated/execution-registry.json"
  $registry = $null
  $registryContent = ""
  if (Test-Path -LiteralPath $registryPath -PathType Leaf) {
    $candidateRegistry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
    if ([string]$candidateRegistry.target -eq $Target) {
      $registry = $candidateRegistry
      $registryContent = (Get-Content -Raw -LiteralPath $registryPath).Replace("`r`n", "`n")
    }
  }
  if ($null -eq $registry) {
    $registry = New-MIRCPExecutionRegistry -Target $Target -RepoRoot $sourceRepo
    [void](Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $sourceRepo)
    $registryContent = (($registry | ConvertTo-Json -Depth 100) + "`n").Replace("`r`n", "`n")
  }
  $registrySha256 = Get-MIRCPSha256Text -Value $registryContent
  $targetProfilePath = Join-Path $sourceRepo "validation/profiles/factorio-$Target.json"
  $targetProfile = Get-Content -Raw -LiteralPath $targetProfilePath | ConvertFrom-Json
  $transition = Get-MIRCPReleaseTransitionForContext -Release $Release -RepoRoot $repo
  $bundle = Get-MIRCPQualificationBundleForContext -ReleaseRecord $releaseRecord -RepoRoot $repo
  Write-Verbose "[context] resolved registry, profile, transition, and qualification bundle"
  $taskMap = Get-MIRCPTaskMap -RepoRoot $repo
  $expandedTasks = [pscustomobject][ordered]@{
    schema = 1
    plan_id = [string]$plan.plan_id
    tasks = @($plan.plan.tasks | ForEach-Object { [pscustomobject][ordered]@{plan=$_; task=$taskMap[[string]$_.id]} })
  }
  $candidateDescriptor = [pscustomobject][ordered]@{
    schema = 1
    release = $Release
    candidate_id = [string]$releaseRecord.candidate_id
    target = $Target
    archive_sha256 = [string]$releaseRecord.package.archive_sha256
    content_sha256 = [string]$releaseRecord.package.content_sha256
    source_commit = [string]$releaseRecord.package.source_commit
    source_tree = [string]$releaseRecord.package.source_tree
    source_sha256 = [string]$releaseRecord.package.source_sha256
    bytes = [int64]$releaseRecord.package.bytes
    entries = [int]$releaseRecord.package.entries
  }
  $controlPlaneFiles = @(
    ".mir/control-plane/control-plane.json", ".mir/control-plane/domains.json", ".mir/control-plane/freshness.json",
    ".mir/control-plane/ownership.json", ".mir/control-plane/mutation-calibration.json", ".mir/control-plane/evidence-revocations.json",
    "validation/trust.json"
  )
  $controlPlaneLock = [pscustomobject][ordered]@{
    schema = 1
    policy_id = "mir-control-plane-v5"
    qualification_source_commit = ([string](& git -C $repo rev-parse HEAD)).Trim()
    scenario_source_role = [string]$qualificationSource.role
    scenario_source_commit = [string]$qualificationSource.commit
    scenario_source_tree = [string]$qualificationSource.tree
    scenario_source_worktree_sha256 = [string]$qualificationSource.worktree_sha256
    scenario_source_proof_sha256 = [string]$qualificationSource.proof_sha256
    component_abis = (Get-MIRCPPolicy -RepoRoot $repo).component_abis
    files = @($controlPlaneFiles | ForEach-Object { [pscustomobject][ordered]@{path=$_; sha256=(Get-MIRCPSha256File -Path (Join-Path $repo $_))} })
    task_catalog_sha256 = Get-MIRCPSha256Object -Value @(Get-MIRCPTaskRecords -RepoRoot $repo | Sort-Object id)
    release_record_sha256 = Get-MIRCPSha256Object -Value $releaseRecord
    transition_sha256 = Get-MIRCPSha256Object -Value $transition
  }
  Write-Verbose "[context] expanded tasks and control-plane lock"
  $files = [ordered]@{
    "plan.json" = $plan
    "candidate-descriptor.json" = $candidateDescriptor
    "release-transition.json" = $transition
    "expanded-tasks.json" = $expandedTasks
    "domain-manifest.json" = New-MIRCPContextDomainManifest -ReleaseRecord $releaseRecord -QualificationBundle $bundle -RepoRoot $repo
    "environment-locks.json" = New-MIRCPEnvironmentLocks -ReleaseRecord $releaseRecord -QualificationBundle $bundle -TargetProfile $targetProfile -TargetProfilePath $targetProfilePath -ScenarioRegistrySha256 $registrySha256 -SourceRepoRoot $sourceRepo -RepoRoot $repo
    "control-plane-lock.json" = $controlPlaneLock
  }
  Write-Verbose "[context] assembled context member values"
  $root = if ([IO.Path]::IsPathRooted($OutputRoot)) { [IO.Path]::GetFullPath($OutputRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $OutputRoot)) }
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $root) }
  Write-Verbose "[context] staging under $root"
  $stagingDirectory = Join-Path $root ("staging-" + [guid]::NewGuid().ToString("N"))
  [void](New-Item -ItemType Directory -Path $stagingDirectory)
  foreach ($entry in $files.GetEnumerator()) {
    Write-Verbose "[context] writing $($entry.Key)"
    Write-MIRCPJson -Path (Join-Path $stagingDirectory $entry.Key) -Value $entry.Value -RepoRoot $repo
  }
  [IO.File]::WriteAllText((Join-Path $stagingDirectory "expanded-scenarios.json"), $registryContent, [Text.UTF8Encoding]::new($false))
  Copy-Item -LiteralPath $targetProfilePath -Destination (Join-Path $stagingDirectory "target-profile.json")
  Copy-Item -LiteralPath $candidate -Destination (Join-Path $stagingDirectory "candidate.zip")
  $members = @(Get-MIRCPContextMemberRows -Directory $stagingDirectory)
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-verification-context"
    context_abi = 1
    context_id = ""
    mode = $Mode
    target = $Target
    release = $Release
    candidate_id = [string]$releaseRecord.candidate_id
    plan_id = [string]$plan.plan_id
    members = $members
  }
  $manifest.context_id = Get-MIRCPSha256Object -Value (Get-MIRCPContextIdentity -Manifest $manifest)
  Write-MIRCPJson -Path (Join-Path $stagingDirectory "context-manifest.json") -Value $manifest -RepoRoot $repo
  [IO.File]::WriteAllText((Join-Path $stagingDirectory "context-digest.txt"), ([string]$manifest.context_id + "`n"), [Text.UTF8Encoding]::new($false))
  $destination = Join-Path $root ([string]$manifest.context_id)
  if (Test-Path -LiteralPath $destination -PathType Container) {
    $existing = Assert-MIRCPVerificationContext -Path $destination
    if ([string]$existing.context_id -ne [string]$manifest.context_id) { throw "Existing context directory has a conflicting identity." }
    $resolvedStage = [IO.Path]::GetFullPath($stagingDirectory)
    if (-not $resolvedStage.StartsWith(($root.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe context staging cleanup target: $resolvedStage" }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    return $existing
  }
  Move-Item -LiteralPath $stagingDirectory -Destination $destination
  return Assert-MIRCPVerificationContext -Path $destination
}
