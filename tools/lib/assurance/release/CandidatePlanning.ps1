function Get-MIRAssuranceCandidateArchiveIdentity {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Candidate does not exist: $Path" }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entryCount = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith("/") }).Count
  } finally {
    $archive.Dispose()
  }
  return [pscustomobject]@{
    bytes = (Get-Item -LiteralPath $Path).Length
    entries = $entryCount
    sha256 = Get-MIRAssuranceSha256 -Path $Path
    content_sha256 = Get-MIRAssuranceZipContentHash -Path $Path
  }
}

function Test-MIRAssuranceReleaseCandidateId {
  param([Parameter(Mandatory)][string]$CandidateId)
  return $CandidateId -match '^(?:C[1-9][0-9]*|[0-9]+\.[0-9]+-P[1-9][0-9]*)$'
}

function Get-MIRAssuranceLocalPlaytestPlanningAuthority {
  param([Parameter(Mandatory)]$Context)

  $targetMap = @{
    "2.0" = [ordered]@{ target_key = "f200"; distribution_version = "4.0.20000" }
    "1.1" = [ordered]@{ target_key = "f110"; distribution_version = "4.0.11000" }
    "1.0" = [ordered]@{ target_key = "f100"; distribution_version = "4.0.10000" }
  }
  $binding = $targetMap[[string]$Context.target]
  if ($null -eq $binding) { return $null }

  # Confirmed package-visible corrections are qualified before source freeze in
  # a separate, private affected-proof lane. This lane does not replace the
  # fixed-point M4C01 materializer or broaden its authority; it only lets the
  # exact f200 correction candidate participate in candidate-bound planning.
  $affectedManifestPath = Join-Path $repo "build\results\mir4-sol\sol08\target-candidates\MIR4_AFFECTED_TARGET_CANDIDATES.json"
  if ([string]$binding.target_key -eq 'f200' -and (Test-Path -LiteralPath $affectedManifestPath -PathType Leaf)) {
    $affectedManifest = Get-Content -Raw -LiteralPath $affectedManifestPath | ConvertFrom-Json
    $affectedRows = @($affectedManifest.targets | Where-Object {
      [string]$_.target_key -eq [string]$binding.target_key -and
      [string]$_.factorio_line -eq [string]$Context.target -and
      [string]$_.version -eq [string]$binding.distribution_version
    })
    if ($affectedRows.Count -eq 1) {
      $affectedRow = $affectedRows[0]
      $affectedCandidate = Join-Path $repo ([string]$affectedRow.archive)
      $requestedAffectedCandidate = -not [string]::IsNullOrWhiteSpace([string]$Context.candidate) -and
        [IO.Path]::GetFullPath($affectedCandidate).Equals(
          [IO.Path]::GetFullPath([string]$Context.candidate),
          [StringComparison]::OrdinalIgnoreCase
        )
      if ($requestedAffectedCandidate) {
        $authorityPath = Join-Path $repo ".mir\releases\waves\mir4-r0\MIR4-Private-Lane-AuthorizationV3.json"
        if ([int]$affectedManifest.schema -ne 1 -or
            [string]$affectedManifest.kind -ne 'MIR4AffectedTargetCandidateSetSOL08V1' -or
            [string]$affectedManifest.status -ne 'built-unqualified-local-development-candidates' -or
            [bool]$affectedManifest.public_output_authorized -or
            [bool]$affectedManifest.publication_authorized -or
            -not (Test-Path -LiteralPath $authorityPath -PathType Leaf)) {
          throw 'MIR 4 affected-correction planning manifest violates its private authority boundary.'
        }
        $authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json
        if (-not (Test-MIR4BootstrapRecordHash -Record $authority) -or
            [string]$authority.kind -ne 'MIR4PrivateLaneAuthorizationV3' -or
            [bool]$authority.release_admission_authorized -or [bool]$authority.public_output_authorized -or
            [bool]$authority.signing_or_sealing_authorized -or [bool]$authority.publication_authorized) {
          throw 'MIR 4 affected-correction planning lacks exact private-lane authority.'
        }
        $authorityRows = @($authority.authorized_targets | Where-Object {
          [string]$_.target_key -eq [string]$binding.target_key -and
          [string]$_.factorio_line -eq [string]$Context.target -and
          [string]$_.distribution_version -eq [string]$binding.distribution_version
        })
        if ($authorityRows.Count -ne 1) { throw 'MIR 4 affected-correction target is absent from private-lane authority.' }
        $authorityRow = $authorityRows[0]
        if (-not (Test-Path -LiteralPath $affectedCandidate -PathType Leaf)) {
          throw 'MIR 4 affected-correction candidate is missing.'
        }
        $candidateIdentity = Get-MIRAssuranceCandidateArchiveIdentity -Path $affectedCandidate
        if ([string]$candidateIdentity.sha256 -ne [string]$affectedRow.archive_sha256 -or
            [string]$candidateIdentity.content_sha256 -ne [string]$affectedRow.content_sha256 -or
            [long]$candidateIdentity.bytes -ne [long]$affectedRow.bytes -or
            [int]$candidateIdentity.entries -ne [int]$affectedRow.entry_count) {
          throw 'MIR 4 affected-correction candidate bytes differ from the exact manifest.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$Context.factorio) -or
            -not (Test-Path -LiteralPath $Context.factorio -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $Context.factorio).Hash -ne [string]$authorityRow.engine_sha256) {
          throw 'MIR 4 affected-correction plan requires the exact target-bound Factorio engine.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$Context.prior_release) -or
            -not (Test-Path -LiteralPath $Context.prior_release -PathType Leaf) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $Context.prior_release).Hash -ne [string]$authorityRow.predecessor_archive_sha256) {
          throw 'MIR 4 affected-correction plan requires the exact target-bound predecessor archive.'
        }
        return [pscustomobject][ordered]@{
          release = [string]$binding.distribution_version
          target = [string]$Context.target
          state = [string]$affectedManifest.status
          authority_class = 'private-affected-correction-testing-only'
          candidate_id = [string]$binding.target_key
          package_source_commit = [string]$affectedManifest.source_commit
        }
      }
    }
  }

  $laneRoot = Join-Path $repo "build\mir4\local-playtest-shadow"
  $manifestPath = Join-Path $laneRoot "manifests\$($binding.target_key).json"
  $authorityPath = Join-Path $repo ".mir\releases\waves\mir4-r0\MIR4-Private-Lane-AuthorizationV3.json"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $authorityPath -PathType Leaf)) {
    throw "Exact MIR 4 local-playtest planning authority is missing for target $($Context.target)."
  }

  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  $authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json
  if (-not (Test-MIR4BootstrapRecordHash -Record $manifest) -or
      -not (Test-MIR4BootstrapRecordHash -Record $authority)) {
    throw "MIR 4 local-playtest planning authority or candidate manifest self-hash is invalid."
  }
  if ([string]$authority.kind -ne "MIR4PrivateLaneAuthorizationV3" -or
      [string]$authority.authority_family -ne "MIRLocalArtifactLaneAuthorizationV1" -or
      [bool]$authority.package_visible -or
      [bool]$authority.release_admission_authorized -or
      [bool]$authority.public_identity_authorized -or
      [bool]$authority.public_output_authorized -or
      [bool]$authority.signing_or_sealing_authorized -or
      [bool]$authority.publication_authorized -or
      [bool]$authority.wildcard_targets_authorized -or
      [bool]$authority.gate_waivers_authorized) {
    throw "MIR 4 local-playtest authority does not preserve the private, release-orthogonal boundary."
  }

  $targetRows = @($authority.authorized_targets | Where-Object {
    [string]$_.target_key -eq [string]$binding.target_key -and
    [string]$_.factorio_line -eq [string]$Context.target -and
    [string]$_.distribution_version -eq [string]$binding.distribution_version
  })
  if ($targetRows.Count -ne 1) {
    throw "MIR 4 local-playtest authority does not bind exactly one row for target $($Context.target)."
  }
  $targetRow = $targetRows[0]
  if ([string]$manifest.kind -ne "MIR4LocalPlaytestCandidateManifestV1" -or
      [string]$manifest.status -notin @(
        "built-unqualified-local-playtest-candidate",
        "locally-smoke-qualified-playtest-candidate",
        "locally-upgrade-qualified-playtest-candidate"
      ) -or
      [string]$manifest.lane -ne "local-playtest-shadow" -or
      [string]$manifest.target_key -ne [string]$binding.target_key -or
      [string]$manifest.factorio_line -ne [string]$Context.target -or
      [string]$manifest.distribution_version -ne [string]$binding.distribution_version -or
      [string]$manifest.admission -ne "non-authoritative-shadow-blocked-by-eol" -or
      [bool]$manifest.public_output_authorized -or
      [bool]$manifest.release_claim_permitted -or
      [string]$manifest.local_lane_authority.record_sha256 -ne [string]$authority.record_sha256) {
    throw "MIR 4 local-playtest manifest is not an exact private planning input."
  }

  $expectedCandidate = Join-Path $laneRoot ([string]$manifest.local_distribution.path)
  if (-not (Test-Path -LiteralPath $expectedCandidate -PathType Leaf) -or
      [string]::IsNullOrWhiteSpace([string]$Context.candidate) -or
      -not [IO.Path]::GetFullPath($expectedCandidate).Equals(
        [IO.Path]::GetFullPath([string]$Context.candidate),
        [StringComparison]::OrdinalIgnoreCase
      )) {
    throw "MIR 4 local-playtest plan must use the exact governed candidate path."
  }
  $candidateIdentity = Get-MIRAssuranceCandidateArchiveIdentity -Path $expectedCandidate
  if ([string]$candidateIdentity.sha256 -ne [string]$manifest.local_distribution.archive_sha256 -or
      [string]$candidateIdentity.content_sha256 -ne [string]$manifest.local_distribution.content_sha256 -or
      [long]$candidateIdentity.bytes -ne [long]$manifest.local_distribution.bytes -or
      [int]$candidateIdentity.entries -ne [int]$manifest.local_distribution.entry_count) {
    throw "MIR 4 local-playtest candidate bytes do not match the governed manifest."
  }
  if ([string]::IsNullOrWhiteSpace([string]$Context.factorio) -or
      -not (Test-Path -LiteralPath $Context.factorio -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $Context.factorio).Hash -ne [string]$targetRow.engine_sha256) {
    throw "MIR 4 local-playtest plan requires the exact target-bound Factorio engine."
  }
  if ([string]::IsNullOrWhiteSpace([string]$Context.prior_release) -or
      -not (Test-Path -LiteralPath $Context.prior_release -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $Context.prior_release).Hash -ne [string]$targetRow.predecessor_archive_sha256) {
    throw "MIR 4 local-playtest plan requires the exact target-bound predecessor archive."
  }

  return [pscustomobject][ordered]@{
    release = [string]$binding.distribution_version
    target = [string]$Context.target
    state = [string]$manifest.status
    authority_class = "private-local-artifact-testing-only"
    candidate_id = [string]$binding.target_key
    package_source_commit = [string]$targetRow.source_commit
  }
}

function Get-MIRAssuranceReleasePlanningAuthority {
  param([Parameter(Mandatory)]$Context)

  $localPlaytest = Get-MIRAssuranceLocalPlaytestPlanningAuthority -Context $Context
  if ($null -ne $localPlaytest) { return $localPlaytest }

  $version = [string]$Context.info.version
  $recordPath = Join-Path $repo ".mir\releases\records\$version.json"
  if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
    throw "Typed release authority is missing: .mir/releases/records/$version.json"
  }
  $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
  if ([int]$record.schema -ne 1 -or
      [string]$record.release -ne $version -or
      [string]$record.target -ne [string]$Context.target) {
    throw "Typed release authority does not match the verification context."
  }

  $states = @(
    "planned", "source-frozen", "package-built", "focused-qualified", "candidate-qualified",
    "automated-qualified-awaiting-human-review", "manually-accepted", "protected-qualified",
    "sealed", "promoted", "tagged", "published", "publicly-verified"
  )
  if ($states -notcontains [string]$record.state) {
    throw "Typed release authority state is invalid: $($record.state)"
  }

  $authorityClass = "exact-candidate"
  $packageSourceCommit = [string]$record.package.source_commit
  if ([string]$record.state -eq "planned") {
    if ([string]$record.candidate_id -ne "not-assigned" -or
        [string]$record.candidate_floor -notmatch '^(?:C[1-9][0-9]*|[0-9]+\.[0-9]+-P[1-9][0-9]*)$' -or
        @($record.package.PSObject.Properties).Count -ne 0) {
      throw "Planned release authority must contain only an unassigned candidate reservation and no frozen package identity."
    }
    $authorityClass = "planned-reservation"
    $packageSourceCommit = Resolve-MIRAssuranceCommit -Commit HEAD
  } else {
    if (-not (Test-MIRAssuranceReleaseCandidateId -CandidateId ([string]$record.candidate_id)) -or
        $packageSourceCommit -notmatch '^[0-9a-f]{40}$') {
      throw "Post-planning release authority must bind an exact candidate and package-source commit."
    }
    $packageSourceCommit = Resolve-MIRAssuranceCommit -Commit $packageSourceCommit
  }

  return [pscustomobject][ordered]@{
    release = $version
    target = [string]$record.target
    state = [string]$record.state
    authority_class = $authorityClass
    candidate_id = [string]$record.candidate_id
    candidate_floor = [string]$record.candidate_floor
    package_source_commit = $packageSourceCommit
  }
}

function Get-MIRAssuranceReleaseCandidateAuthority {
  param([Parameter(Mandatory)]$Context)

  $ledgerPath = Join-Path $repo ".mir\releases.json"
  $ledger = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
  if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne "canonical-release-ledger") {
    throw "Canonical release ledger is invalid."
  }
  $targetKey = "factorio-$($Context.target)"
  $property = $ledger.development.PSObject.Properties[$targetKey]
  if ($null -eq $property) { throw "Canonical release ledger has no development authority for $targetKey." }
  $authority = $property.Value
  if ([string]$authority.mir_version -ne [string]$Context.info.version) {
    throw "Release authority version does not match the candidate version."
  }
  if (-not (Test-MIRAssuranceReleaseCandidateId -CandidateId ([string]$authority.candidate_id))) {
    throw "Release authority candidate_id is invalid."
  }
  if ([string]$authority.package_source_commit -notmatch '^[0-9a-f]{40}$') {
    throw "Release authority package_source_commit must be a full lowercase Git commit."
  }
  foreach ($field in @("package_source_sha256", "archive_sha256", "package_content_sha256")) {
    if ([string]$authority.$field -notmatch '^[0-9A-F]{64}$') {
      throw "Release authority $field must be an uppercase SHA-256 digest."
    }
  }
  $material = $authority.package_source_material
  $materialAlgorithm = [string]$material.hash_algorithm
  $legacyMaterial = $materialAlgorithm -eq "git-index-with-captured-worktree-v1" -and
    [string]$material.source_parent_commit -match '^[0-9a-f]{40}$' -and
    @($material.changed_files).Count -gt 0
  $cleanMaterial = $materialAlgorithm -eq "git-commit-normalized-package-v1" -and
    [string]$material.source_tree -match '^[0-9a-f]{40}$' -and
    [int]$material.file_count -gt 0
  if ([int]$material.schema -ne 1 -or (-not $legacyMaterial -and -not $cleanMaterial)) {
    throw "Release authority package_source_material is invalid."
  }
  if ([long]$authority.archive_bytes -le 0) { throw "Release authority archive_bytes must be positive." }
  $null = Resolve-MIRAssuranceCommit -Commit ([string]$authority.package_source_commit)
  return $authority
}

function Get-MIRAssuranceCommitCandidateIdentity {
  param([Parameter(Mandatory)][string]$Commit)

  $resolvedCommit = Resolve-MIRAssuranceCommit -Commit $Commit
  $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-seal-source-" + [guid]::NewGuid().ToString("N"))
  $sourceRoot = Join-Path $temporaryRoot "source"
  $sourceArchive = Join-Path $temporaryRoot "source.zip"
  try {
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    . (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
    $canonicalBuilder = "tools/commands/package/Build-MIRPackage.ps1"
    $legacyBuilder = "scripts/Build-MIRPackage.ps1"
    & git -C $repo cat-file -e "${resolvedCommit}:$canonicalBuilder" 2>$null
    $builderPath = if ($LASTEXITCODE -eq 0) { $canonicalBuilder } else { $legacyBuilder }
    $archivePaths = @(
      @(Get-MIRPackageSourceRoots)
      $builderPath
      "tools/lib/validation/PackageIdentity.ps1"
    )
    & git -C $repo archive --format=zip --output=$sourceArchive $resolvedCommit -- @archivePaths 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract committed package inputs for $resolvedCommit." }
    Expand-Archive -LiteralPath $sourceArchive -DestinationPath $sourceRoot
    $powerShell = (Get-Process -Id $PID).Path
    & $powerShell -NoProfile -NonInteractive -File (Join-Path $sourceRoot $builderPath) -OutputDir "authority-dist" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Deterministic package reconstruction failed for $resolvedCommit." }
    $info = Get-Content -Raw -LiteralPath (Join-Path $sourceRoot "info.json") | ConvertFrom-Json
    $candidate = Join-Path $sourceRoot "authority-dist\$($info.name)_$($info.version).zip"
    $identity = Get-MIRAssuranceCandidateArchiveIdentity -Path $candidate
    return [pscustomobject]@{
      commit = $resolvedCommit
      bytes = [long]$identity.bytes
      entries = [int]$identity.entries
      sha256 = [string]$identity.sha256
      content_sha256 = [string]$identity.content_sha256
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
      Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
  }
}
