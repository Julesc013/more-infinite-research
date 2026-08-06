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
        [string]$proof.archive_sha256 -ne [string]$ReleaseRecord.package.archive_sha256) {
      throw "Qualification source does not match the governed dual-parent reconstruction proof."
    }
    $integrationTree = ([string](& git -C $source rev-parse "$([string]$proof.integration_commit)^{tree}")).Trim()
    & git -C $source merge-base --is-ancestor ([string]$proof.integration_commit) $commit
    $integrationIsAncestor = $LASTEXITCODE -eq 0
    . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
    $currentPackageSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $source
    if (-not $integrationIsAncestor -or $integrationTree -ne [string]$proof.integration_tree -or
        $currentPackageSha256 -ne [string]$ReleaseRecord.package.source_sha256) {
      throw "Qualification source is not a package-identical descendant of the governed dual-parent integration."
    }
    $role = if ($commit -eq [string]$proof.integration_commit -and $tree -eq [string]$proof.integration_tree) {
      "dual-parent-integration"
    } else {
      "dual-parent-integration-successor"
    }
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

function Resolve-MIRCPTargetProfileForRelease {
  param(
    [Parameter(Mandatory)]$BaseProfile,
    [Parameter(Mandatory)]$ReleaseRecord,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $profile = $BaseProfile | ConvertTo-Json -Depth 40 | ConvertFrom-Json
  if ($null -eq $ReleaseRecord.PSObject.Properties["upgrade"]) { return $profile }
  foreach ($field in @("from_version", "to_version", "fixture")) {
    if ($null -eq $ReleaseRecord.upgrade.PSObject.Properties[$field] -or
        [string]::IsNullOrWhiteSpace([string]$ReleaseRecord.upgrade.$field)) {
      throw "Release $($ReleaseRecord.release) upgrade authority is missing $field."
    }
  }
  if ([string]$ReleaseRecord.upgrade.to_version -ne [string]$ReleaseRecord.release) {
    throw "Release $($ReleaseRecord.release) upgrade authority targets $($ReleaseRecord.upgrade.to_version)."
  }
  $baseline = Get-MIRCPReleaseByVersion -Release ([string]$ReleaseRecord.upgrade.from_version) -RepoRoot $repo
  if ([string]$baseline.target -ne [string]$ReleaseRecord.target) {
    throw "Release $($ReleaseRecord.release) upgrade baseline targets $($baseline.target), not $($ReleaseRecord.target)."
  }
  $fixturePath = Join-Path $repo ("fixtures/" + [string]$ReleaseRecord.upgrade.fixture)
  if (-not (Test-Path -LiteralPath $fixturePath -PathType Container)) {
    throw "Release $($ReleaseRecord.release) upgrade fixture is missing: $($ReleaseRecord.upgrade.fixture)"
  }
  $profile.upgrade = [pscustomobject][ordered]@{
    from_version = [string]$ReleaseRecord.upgrade.from_version
    to_version = [string]$ReleaseRecord.upgrade.to_version
    fixture = [string]$ReleaseRecord.upgrade.fixture
  }
  return $profile
}

function Get-MIRCPPerformanceCampaignRelativePath {
  param(
    [Parameter(Mandatory)]$Descriptor,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $release = [string]$Descriptor.release
  $candidateId = [string]$Descriptor.candidate_id
  if ($release -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or $candidateId -notmatch '^[A-Za-z0-9.-]+$') {
    throw "Performance campaign selector received an unsafe release or candidate identity."
  }
  $relativePath = ".mir/performance-campaigns/$release-$candidateId.json"
  if (-not (Test-Path -LiteralPath (Join-Path $repo $relativePath) -PathType Leaf)) {
    throw "Performance campaign authority is missing for $release $candidateId."
  }
  return $relativePath
}

function Get-MIRCPFactorioIdentity {
  param([Parameter(Mandatory)][string]$FactorioBin)
  $binary = (Resolve-Path -LiteralPath $FactorioBin).Path
  $binaryItem = Get-Item -LiteralPath $binary
  if ($null -eq $script:MIRCPFactorioIdentityCache) { $script:MIRCPFactorioIdentityCache = @{} }
  $cacheKey = "$binary|$($binaryItem.Length)|$($binaryItem.LastWriteTimeUtc.Ticks)"
  if ($script:MIRCPFactorioIdentityCache.ContainsKey($cacheKey)) { return $script:MIRCPFactorioIdentityCache[$cacheKey] }
  $installRoot = $binaryItem.Directory.Parent.Parent.FullName
  $officialRoots = @("data/core", "data/base", "data/quality", "data/elevated-rails", "data/space-age")
  $officialFiles = @()
  foreach ($relativeRoot in $officialRoots) {
    $path = Join-Path $installRoot $relativeRoot
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $officialFiles += Get-Item -LiteralPath $path
    } elseif (Test-Path -LiteralPath $path -PathType Container) {
      $officialFiles += Get-ChildItem -LiteralPath $path -Recurse -File
    }
  }
  $officialRows = @(
    foreach ($file in @($officialFiles | Sort-Object FullName -Unique)) {
      $relative = [IO.Path]::GetRelativePath($installRoot, $file.FullName).Replace("\", "/")
      "$relative`t$($file.Length)`t$(Get-MIRCPSha256File -Path $file.FullName)"
    }
  )
  $officialData = [pscustomobject][ordered]@{
    kind = "external-tree"
    state = "present"
    root = $installRoot
    file_count = $officialRows.Count
    sha256 = Get-MIRCPSha256Text -Value $(if ($officialRows.Count -gt 0) { $officialRows -join "`n" } else { "EMPTY:factorio-official-data" })
  }
  $binarySha256 = Get-MIRCPSha256File -Path $binary
  $binaryFingerprint = [pscustomobject][ordered]@{
    kind = "external-file"
    state = "present"
    name = $binaryItem.Name
    size_bytes = [int64]$binaryItem.Length
    sha256 = $binarySha256
  }
  $portableOfficialData = [pscustomobject][ordered]@{
    kind = [string]$officialData.kind
    state = [string]$officialData.state
    file_count = [int]$officialData.file_count
    sha256 = [string]$officialData.sha256
  }
  $installationMaterial = [ordered]@{binary=$binaryFingerprint;official_data=$portableOfficialData}
  $legacyInstallationMaterial = [ordered]@{binary=$binaryFingerprint;official_data=$officialData}
  $installationSha256 = Get-MIRCPSha256Text -Value ($installationMaterial | ConvertTo-Json -Depth 40 -Compress)
  # Qualification evidence imported from v4 used a composite identity containing
  # the absolute installation root. Retain it only as a matching alias while all
  # ABI-3 locks emit the path-independent identity above.
  $legacyInstallationSha256 = Get-MIRCPSha256Text -Value ($legacyInstallationMaterial | ConvertTo-Json -Depth 40 -Compress)
  $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($binary).ProductVersion
  if ([string]::IsNullOrWhiteSpace([string]$version)) { throw "Factorio executable has no product version: $binary" }
  $identity = [pscustomobject][ordered]@{
    path = $binary
    root = $installRoot
    sha256 = $installationSha256
    installation_sha256 = $installationSha256
    legacy_installation_sha256 = $legacyInstallationSha256
    bytes = [int64]$binaryItem.Length
    version = [string]$version
    binary = [pscustomobject][ordered]@{bytes=[int64]$binaryItem.Length;sha256=$binarySha256}
    official_data = $officialData
  }
  $script:MIRCPFactorioIdentityCache[$cacheKey] = $identity
  return $identity
}

function Test-MIRCPFactorioIdentityMatchesLock {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$Lock
  )
  if ($null -ne $Lock.PSObject.Properties["installation_sha256"]) {
    $acceptedInstallationHashes = @([string]$Identity.installation_sha256)
    if ($null -ne $Identity.PSObject.Properties["legacy_installation_sha256"]) {
      $acceptedInstallationHashes += [string]$Identity.legacy_installation_sha256
    }
    if ($acceptedInstallationHashes -notcontains [string]$Lock.installation_sha256) { return $false }
  }
  if ([string]$Lock.binary.sha256 -ne [string]$Identity.binary.sha256) { return $false }
  if ($null -ne $Lock.binary.PSObject.Properties["bytes"] -and [int64]$Lock.binary.bytes -gt 0 -and
      [int64]$Lock.binary.bytes -ne [int64]$Identity.binary.bytes) { return $false }
  if ($null -ne $Lock.PSObject.Properties["version"] -and -not [string]::IsNullOrWhiteSpace([string]$Lock.version) -and
      [string]$Lock.version -ne [string]$Identity.version) { return $false }
  if ($null -ne $Lock.PSObject.Properties["official_data"] -and $null -ne $Lock.official_data) {
    if ([int]$Lock.official_data.file_count -ne [int]$Identity.official_data.file_count -or
        [string]$Lock.official_data.sha256 -ne [string]$Identity.official_data.sha256) { return $false }
  }
  return $true
}

function New-MIRCPFactorioEnvironmentLock {
  param(
    [Parameter(Mandatory)]$Identity,
    [Parameter(Mandatory)]$TargetProfile,
    [string]$Source = "context-materialization"
  )
  $expectedVersion = [string]$TargetProfile.qualification_factorio_version
  if ([string]::IsNullOrWhiteSpace($expectedVersion) -or [string]$Identity.version -ne $expectedVersion) {
    throw "Factorio context seed version $($Identity.version) does not match target qualification version $expectedVersion."
  }
  if ([string]$Identity.installation_sha256 -notmatch '^[0-9A-F]{64}$' -or
      [string]$Identity.binary.sha256 -notmatch '^[0-9A-F]{64}$' -or [int64]$Identity.binary.bytes -le 0 -or
      [string]$Identity.official_data.sha256 -notmatch '^[0-9A-F]{64}$' -or [int]$Identity.official_data.file_count -le 0) {
    throw "Factorio context seed identity is incomplete."
  }
  return [pscustomobject][ordered]@{
    source = $Source
    version = [string]$Identity.version
    installation_sha256 = [string]$Identity.installation_sha256
    binary = [pscustomobject][ordered]@{bytes=[int64]$Identity.binary.bytes;sha256=[string]$Identity.binary.sha256}
    official_data = [pscustomobject][ordered]@{file_count=[int]$Identity.official_data.file_count;sha256=[string]$Identity.official_data.sha256}
  }
}

function New-MIRCPEnvironmentLocks {
  param(
    [Parameter(Mandatory)]$ReleaseRecord,
    $QualificationBundle,
    [Parameter(Mandatory)]$TargetProfile,
    [Parameter(Mandatory)][string]$TargetProfileSha256,
    [Parameter(Mandatory)][string]$ScenarioRegistrySha256,
    $FactorioIdentity = $null,
    [string]$SourceRepoRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $sourceRepo = if ([string]::IsNullOrWhiteSpace($SourceRepoRoot)) { $repo } else { (Resolve-Path -LiteralPath $SourceRepoRoot).Path }
  $factorioLocks = [Collections.Generic.List[object]]::new()
  if ($null -ne $FactorioIdentity) {
    $materializedLock = New-MIRCPFactorioEnvironmentLock -Identity $FactorioIdentity -TargetProfile $TargetProfile
    if (@($factorioLocks | Where-Object { Test-MIRCPFactorioIdentityMatchesLock -Identity $FactorioIdentity -Lock $_ }).Count -eq 0) {
      $factorioLocks.Add($materializedLock)
    }
  }
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
      $matchesSelectedIdentity = $null -ne $FactorioIdentity -and (Test-MIRCPFactorioIdentityMatchesLock -Identity $FactorioIdentity -Lock $lock)
      if (-not $matchesSelectedIdentity -and @($factorioLocks | Where-Object { (Get-MIRCPSha256Object -Value $_) -eq (Get-MIRCPSha256Object -Value $lock) }).Count -eq 0) {
        $factorioLocks.Add($lock)
      }
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
  if ($factorioLocks.Count -eq 0) {
    throw "Verification context requires at least one governed Factorio installation lock; provide -FactorioBin for a new candidate."
  }
  return [pscustomobject][ordered]@{
    schema = 1
    target = [string]$ReleaseRecord.target
    target_profile = [pscustomobject][ordered]@{
      id = [string]$TargetProfile.id
      path = "target-profile.json"
      sha256 = $TargetProfileSha256
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
  if ([int]$manifest.context_abi -ge 3) {
    $environmentLocks = Get-Content -Raw -LiteralPath (Join-Path $resolved "environment-locks.json") | ConvertFrom-Json
    if (@($environmentLocks.factorio).Count -lt 1) { throw "Executable verification context contains no governed Factorio installation lock." }
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
    [string]$FactorioBin = "",
    [string]$OutputRoot = "build/results/verification-context",
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
  $plan = New-MIRCPPlan -Mode $Mode -ChangedPath @("tools/lib/control/Context.ps1") -Target $Target -Release $Release -Stage $Stage -SourceRepoRoot $sourceRepo -RepoRoot $repo
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
  $baseTargetProfile = Get-Content -Raw -LiteralPath $targetProfilePath | ConvertFrom-Json
  $targetProfile = Resolve-MIRCPTargetProfileForRelease -BaseProfile $baseTargetProfile -ReleaseRecord $releaseRecord -RepoRoot $repo
  $targetProfileContent = (($targetProfile | ConvertTo-Json -Depth 40) + "`n").Replace("`r`n", "`n")
  $targetProfileSha256 = Get-MIRCPSha256Text -Value $targetProfileContent
  $factorioIdentity = if ([string]::IsNullOrWhiteSpace($FactorioBin)) { $null } else { Get-MIRCPFactorioIdentity -FactorioBin $FactorioBin }
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
  $performanceCampaignRelativePath = Get-MIRCPPerformanceCampaignRelativePath -Descriptor $candidateDescriptor -RepoRoot $repo
  $shadowAuthority = Read-MIRCPJson -Path ".mir/control-plane/v4-v5-equivalence.json" -RepoRoot $repo
  $cutoverProofFiles = @($shadowAuthority.target_cutovers.PSObject.Properties | ForEach-Object {
    [string]$_.Value.proof_path
  } | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath (Join-Path $repo $_) -PathType Leaf)
  } | Sort-Object -Unique)
  $controllerUntracked = @(& git -C $repo ls-files --others --exclude-standard)
  if ($LASTEXITCODE -ne 0 -or $controllerUntracked.Count -ne 0) { throw "Control-plane checkout has untracked governed files." }
  $controllerWorktreeSha256 = Get-MIRCPTrackedWorktreeSha256 -SourceRepoRoot $repo
  $controlPlaneFiles = @(@(
    ".mir/control-plane/control-plane.json", ".mir/control-plane/domains.json", ".mir/control-plane/freshness.json",
    ".mir/control-plane/v4-v5-equivalence.json",
    ".mir/control-plane/approved-delta-policies.json", ".mir/performance-campaign.json", $performanceCampaignRelativePath,
    ".mir/control-plane/ownership.json", ".mir/control-plane/mutation-calibration.json", ".mir/control-plane/evidence-revocations.json",
    "validation/trust.json", "tools/commands/control/Invoke-MIRControlPlane.ps1", "tools/commands/control/Invoke-MIRControlPlaneWork.ps1",
    "tools/lib/control/Core.ps1", "tools/lib/control/Records.ps1", "tools/lib/control/Planner.ps1",
    "tools/lib/control/Scenario.ps1", "tools/lib/control/Observation.ps1", "tools/lib/control/Evidence.ps1",
    "tools/lib/control/Views.ps1", "tools/lib/control/Context.ps1", "tools/lib/control/Shadow.ps1",
    "tools/lib/control/Executor.ps1", "tools/lib/control/Release.ps1", "tools/lib/control/Calibration.ps1"
  ) + $cutoverProofFiles | Sort-Object -Unique)
  $controlPlaneLock = [pscustomobject][ordered]@{
    schema = 1
    policy_id = "mir-control-plane-v5"
    qualification_source_commit = ([string](& git -C $repo rev-parse HEAD)).Trim()
    qualification_source_worktree_sha256 = $controllerWorktreeSha256
    qualification_source_clean = [string]::IsNullOrWhiteSpace($controllerWorktreeSha256)
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
    "environment-locks.json" = New-MIRCPEnvironmentLocks -ReleaseRecord $releaseRecord -QualificationBundle $bundle -TargetProfile $targetProfile -TargetProfileSha256 $targetProfileSha256 -ScenarioRegistrySha256 $registrySha256 -FactorioIdentity $factorioIdentity -SourceRepoRoot $sourceRepo -RepoRoot $repo
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
  [IO.File]::WriteAllText((Join-Path $stagingDirectory "target-profile.json"), $targetProfileContent, [Text.UTF8Encoding]::new($false))
  Copy-Item -LiteralPath $candidate -Destination (Join-Path $stagingDirectory "candidate.zip")
  $members = @(Get-MIRCPContextMemberRows -Directory $stagingDirectory)
  $manifest = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-verification-context"
    context_abi = 3
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
