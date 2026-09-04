function Get-MIRCPZipPackageObservation {
  param([Parameter(Mandatory)][string]$Path, [string]$RepoRoot = "")
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $archive = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $rows = [Collections.Generic.List[object]]::new()
    $root = ""
    $info = $null
    foreach ($entry in @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)) {
      $parts = ([string]$entry.FullName).Replace('\', '/').Split('/', 2)
      if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Package entry has no versioned root: $($entry.FullName)"
      }
      if ([string]::IsNullOrWhiteSpace($root)) { $root = $parts[0] }
      if ($root -cne $parts[0]) { throw "Package contains more than one versioned root." }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $entrySha = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
      finally { $sha.Dispose(); $stream.Dispose() }
      $rows.Add([pscustomobject][ordered]@{path=$parts[1];sha256=$entrySha;bytes=[int64]$entry.Length})
      if ($parts[1] -ceq "info.json") {
        $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8, $true)
        try { $info = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
      }
    }
  } finally {
    $archive.Dispose()
  }
  if ($null -eq $info) { throw "Package has no root info.json." }
  return [pscustomobject][ordered]@{
    path = $resolved
    name = [string]$info.name
    version = [string]$info.version
    factorio_version = [string]$info.factorio_version
    archive_sha256 = Get-MIRCPSha256File -Path $resolved
    content_sha256 = Get-MIRZipContentFingerprint -Path $resolved
    bytes = [int64](Get-Item -LiteralPath $resolved).Length
    entries = $rows.Count
    files = @($rows)
  }
}

function Test-MIRCPExactPathSet {
  param([object[]]$Expected, [object[]]$Actual)
  $expectedRows = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $actualRows = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  return ($expectedRows -join "`n") -ceq ($actualRows -join "`n")
}

function Get-MIRCPNativePatchDeltaPolicy {
  param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion,
    [Parameter(Mandatory)][string]$CandidateId,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $authority = Read-MIRCPJson -Path ".mir/control-plane/approved-delta-policies.json" -RepoRoot $repo
  if ([int]$authority.schema -ne 1 -or [string]$authority.authority -ne "mir-control-plane-v5-approved-delta-policies") {
    throw "Approved-delta policy authority is invalid."
  }
  $matches = @($authority.policies | Where-Object {
    [string]$_.target -eq $Target -and [string]$_.from_version -eq $FromVersion -and
    [string]$_.to_version -eq $ToVersion -and [string]$_.candidate_id -eq $CandidateId
  })
  if ($matches.Count -gt 1) {
    throw "More than one native approved-delta policy matches $FromVersion -> $ToVersion $CandidateId."
  }
  return @($matches)
}
function Invoke-MIRCPNativePatchDeltaMeasurement {
  param(
    [Parameter(Mandatory)]$State,
    [Parameter(Mandatory)]$PlanRow,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][string]$PriorRelease,
    [Parameter(Mandatory)]$Factorio,
    [Parameter(Mandatory)][string]$TrustClass,
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  . (Join-Path $repo "tools/lib/validation/PackageIdentity.ps1")
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $State.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $policyAuthorityPath = Join-Path $repo ".mir/control-plane/approved-delta-policies.json"
  $baseline = Get-MIRCPZipPackageObservation -Path $PriorRelease
  $current = Get-MIRCPZipPackageObservation -Path $Candidate
  $policies = @(Get-MIRCPNativePatchDeltaPolicy -Target ([string]$State.plan.target) `
    -FromVersion ([string]$baseline.version) -ToVersion ([string]$current.version) `
    -CandidateId ([string]$descriptor.candidate_id) -RepoRoot $repo)
  if ($policies.Count -ne 1) { throw "Expected exactly one native approved-delta policy for $($baseline.version) -> $($current.version) $($descriptor.candidate_id)." }
  $policy = $policies[0]
  $baselineByPath = @{}
  foreach ($file in @($baseline.files)) { $baselineByPath[[string]$file.path] = [string]$file.sha256 }
  $currentByPath = @{}
  foreach ($file in @($current.files)) { $currentByPath[[string]$file.path] = [string]$file.sha256 }
  $added = @($currentByPath.Keys | Where-Object { -not $baselineByPath.ContainsKey($_) } | Sort-Object)
  $removed = @($baselineByPath.Keys | Where-Object { -not $currentByPath.ContainsKey($_) } | Sort-Object)
  $changed = @($currentByPath.Keys | Where-Object { $baselineByPath.ContainsKey($_) -and $baselineByPath[$_] -cne $currentByPath[$_] } | Sort-Object)
  $baselineAuthority = $policy.baseline
  $candidateAuthority = $policy.candidate
  $predicates = @(
    [pscustomobject][ordered]@{id="baseline-version";passed=([string]$baseline.version -eq [string]$policy.from_version)},
    [pscustomobject][ordered]@{id="baseline-archive";passed=([string]$baseline.archive_sha256 -eq [string]$baselineAuthority.archive_sha256 -and [string]$baseline.content_sha256 -eq [string]$baselineAuthority.content_sha256 -and [int64]$baseline.bytes -eq [int64]$baselineAuthority.bytes -and [int]$baseline.entries -eq [int]$baselineAuthority.entries)},
    [pscustomobject][ordered]@{id="candidate-version";passed=([string]$current.version -eq [string]$policy.to_version)},
    [pscustomobject][ordered]@{id="candidate-archive";passed=([string]$current.archive_sha256 -eq [string]$candidateAuthority.archive_sha256 -and [string]$current.content_sha256 -eq [string]$candidateAuthority.content_sha256 -and [int64]$current.bytes -eq [int64]$candidateAuthority.bytes -and [int]$current.entries -eq [int]$candidateAuthority.entries)},
    [pscustomobject][ordered]@{id="context-candidate";passed=([string]$descriptor.source_commit -eq [string]$candidateAuthority.source_commit -and [string]$descriptor.archive_sha256 -eq [string]$candidateAuthority.archive_sha256 -and [string]$descriptor.content_sha256 -eq [string]$candidateAuthority.content_sha256)},
    [pscustomobject][ordered]@{id="qualification-source";passed=([string]$Source.commit -eq [string]$candidateAuthority.source_commit)},
    [pscustomobject][ordered]@{id="added-paths";passed=(Test-MIRCPExactPathSet -Expected @($policy.allowed_added_paths) -Actual $added)},
    [pscustomobject][ordered]@{id="removed-paths";passed=(Test-MIRCPExactPathSet -Expected @($policy.allowed_removed_paths) -Actual $removed)},
    [pscustomobject][ordered]@{id="changed-paths";passed=(Test-MIRCPExactPathSet -Expected @($policy.allowed_changed_paths) -Actual $changed)}
  )
  $failedPredicates = @($predicates | Where-Object { -not [bool]$_.passed })
  $unexpected = @(
    @($added | Where-Object { @($policy.allowed_added_paths) -notcontains $_ })
    @($removed | Where-Object { @($policy.allowed_removed_paths) -notcontains $_ })
    @($changed | Where-Object { @($policy.allowed_changed_paths) -notcontains $_ })
  )
  $missing = @(
    @($policy.allowed_added_paths | Where-Object { $added -notcontains [string]$_ })
    @($policy.allowed_removed_paths | Where-Object { $removed -notcontains [string]$_ })
    @($policy.allowed_changed_paths | Where-Object { $changed -notcontains [string]$_ })
  )
  $status = if ($failedPredicates.Count -eq 0) { "approved" } else { "rejected" }
  $output = [pscustomobject][ordered]@{
    schema = 1
    kind = "mir-control-plane-v5-approved-patch-delta"
    policy = [pscustomobject][ordered]@{id=[string]$policy.id;authority_digest_policy="utf8-lf";authority_sha256=(Get-MIRCPPortableTextSha256 -Path $policyAuthorityPath);reason=[string]$policy.reason;migration_impact=[string]$policy.migration_impact;allowed_added_paths=@($policy.allowed_added_paths);allowed_removed_paths=@($policy.allowed_removed_paths);allowed_changed_paths=@($policy.allowed_changed_paths)}
    observation = [pscustomobject][ordered]@{
      baseline = [pscustomobject][ordered]@{version=[string]$baseline.version;source_commit=[string]$baselineAuthority.source_commit;archive_sha256=[string]$baseline.archive_sha256;content_sha256=[string]$baseline.content_sha256;bytes=[int64]$baseline.bytes;entries=[int]$baseline.entries}
      current = [pscustomobject][ordered]@{version=[string]$current.version;candidate_id=[string]$descriptor.candidate_id;source_commit=[string]$candidateAuthority.source_commit;qualification_source_commit=[string]$Source.commit;archive_sha256=[string]$current.archive_sha256;content_sha256=[string]$current.content_sha256;bytes=[int64]$current.bytes;entries=[int]$current.entries}
      delta = [pscustomobject][ordered]@{added=$added;removed=$removed;changed=$changed}
    }
    evaluation = [pscustomobject][ordered]@{status=$status;difference_count=($added.Count + $removed.Count + $changed.Count);unapproved_count=($unexpected.Count + $missing.Count);predicates=$predicates}
  }
  $outputPath = Join-Path $repo "build/results/control-plane-v5/approved-delta/$([string]$State.context.context_id)/evaluation.json"
  Write-MIRCPJson -Path $outputPath -Value $output -RepoRoot $repo
  $taskStatus = if ($status -eq "approved" -and [int]$output.evaluation.unapproved_count -eq 0) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $taskStatus
    measurement_mode = "native-patch-delta-v1"
    policy_id = [string]$policy.id
    policy_authority_digest_policy = "utf8-lf"
    policy_authority_sha256 = Get-MIRCPPortableTextSha256 -Path $policyAuthorityPath
    factorio_installation_sha256 = [string]$Factorio.installation_sha256
    factorio_binary_sha256 = [string]$Factorio.binary.sha256
    prior_archive_sha256 = [string]$baseline.archive_sha256
    difference_count = [int]$output.evaluation.difference_count
    unapproved_count = [int]$output.evaluation.unapproved_count
    artifact_status = $status
  }
  return Write-MIRCPSpecializedTaskEvidence -State $State -PlanRow $PlanRow -ObservationKind environment-capture -Status $taskStatus `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$PlanRow.effective_input_sha256;factorio=$Factorio;prior_archive_sha256=$facts.prior_archive_sha256;source_commit=[string]$Source.commit;policy_authority_sha256=$facts.policy_authority_sha256}) `
    -Facts $facts -ArtifactPath $outputPath -ArtifactKind "approved-patch-delta-evaluation" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}

function Invoke-MIRCPApprovedDeltaMeasurement {
  param(
    [Parameter(Mandatory)][string]$ContextPath,
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$PriorRelease,
    [Parameter(Mandatory)][string]$SourceRepoRoot,
    [string]$TrustClass = "protected-release",
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $state = Get-MIRCPContextExecutionState -ContextPath $ContextPath -RepoRoot $repo
  $source = Assert-MIRCPExecutionSource -State $state -SourceRepoRoot $SourceRepoRoot
  $candidate = Get-MIRCPCanonicalCandidateArchive -State $state -RepoRoot $repo
  $row = @($state.plan.tasks | Where-Object id -eq "approved-delta.measurement")
  if ($row.Count -ne 1) { throw "Context plan does not contain approved-delta.measurement exactly once." }
  $factorio = Assert-MIRCPFactorioContextLock -State $state -FactorioBin $FactorioBin
  $prior = (Resolve-Path -LiteralPath $PriorRelease).Path
  $descriptor = Get-Content -Raw -LiteralPath (Join-Path $state.context.path "candidate-descriptor.json") | ConvertFrom-Json
  $priorObservation = Get-MIRCPZipPackageObservation -Path $prior
  $nativePolicies = @(Get-MIRCPNativePatchDeltaPolicy -Target ([string]$state.plan.target) `
    -FromVersion ([string]$priorObservation.version) -ToVersion ([string]$descriptor.release) `
    -CandidateId ([string]$descriptor.candidate_id) -RepoRoot $repo)
  if ($nativePolicies.Count -eq 1) {
    return Invoke-MIRCPNativePatchDeltaMeasurement -State $state -PlanRow $row[0] -Source $source -Candidate $candidate `
      -PriorRelease $prior -Factorio $factorio -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
  }
  $outputPath = Join-Path $repo "build/results/control-plane-v5/approved-delta.json"
  $rawRoot = Join-Path $repo "build/results/control-plane-v5/approved-delta-raw"
  & (Join-Path $source.path "scripts/Export-MIRApprovedDelta.ps1") -BaselinePackage $prior `
    -CurrentPackage $candidate -FactorioBin $factorio.path `
    -OutputPath $outputPath -EvidenceRoot $rawRoot -ExpectedBaselineSha256 (Get-MIRCPSha256File -Path $prior) `
    -ExpectedSourceCommit ([string]$source.commit)
  $exportExitCode = $LASTEXITCODE
  if ($exportExitCode -eq 0) {
    & (Join-Path $source.path "tests/release/Test-MIRApprovedDelta.ps1") -Path $outputPath `
      -Candidate $candidate -ExpectedSourceCommit ([string]$source.commit)
  }
  $testExitCode = $LASTEXITCODE
  $artifact = if (Test-Path -LiteralPath $outputPath -PathType Leaf) { Get-Content -Raw -LiteralPath $outputPath | ConvertFrom-Json } else { $null }
  $status = if ($exportExitCode -eq 0 -and $testExitCode -eq 0 -and $null -ne $artifact -and [string]$artifact.summary.status -eq "approved" -and [int]$artifact.summary.unapproved_count -eq 0) { "passed" } else { "failed" }
  $facts = [pscustomobject][ordered]@{
    status = $status
    factorio_installation_sha256 = [string]$factorio.installation_sha256
    factorio_binary_sha256 = [string]$factorio.binary.sha256
    prior_archive_sha256 = Get-MIRCPSha256File -Path $prior
    difference_count = if ($null -eq $artifact) { -1 } else { [int]$artifact.summary.difference_count }
    unapproved_count = if ($null -eq $artifact) { -1 } else { [int]$artifact.summary.unapproved_count }
    artifact_status = if ($null -eq $artifact) { "missing" } else { [string]$artifact.summary.status }
  }
  return Write-MIRCPSpecializedTaskEvidence -State $state -PlanRow $row[0] -ObservationKind engine-realization -Status $status `
    -EnvironmentMaterial ([pscustomobject][ordered]@{task=[string]$row[0].effective_input_sha256;factorio=$factorio;prior_archive_sha256=$facts.prior_archive_sha256;source_commit=[string]$source.commit}) `
    -Facts $facts -ArtifactPath $outputPath -ArtifactKind "approved-delta" -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo
}
