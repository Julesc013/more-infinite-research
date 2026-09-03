function Get-MIRAssurancePatternFingerprint {
  param([Parameter(Mandatory)][string[]]$Patterns)
  if ($null -eq $script:MIRAssurancePatternFingerprintCache) { $script:MIRAssurancePatternFingerprintCache = @{} }
  $cacheKey = @($Patterns | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique) -join "`n"
  if ($script:MIRAssurancePatternFingerprintCache.ContainsKey($cacheKey)) {
    return $script:MIRAssurancePatternFingerprintCache[$cacheKey]
  }
  $files = @(Resolve-MIRAssurancePatternFiles -Patterns $Patterns)
  $hash = if ($files.Count -gt 0) {
    Get-MIRAssuranceTreeHash -Paths $files
  } else {
    Get-MIRAssuranceTextHash -Text ("NO_MATCH`n" + (($Patterns | Sort-Object -Unique) -join "`n"))
  }
  $fingerprint = [ordered]@{
    kind="repository-patterns"
    patterns=@($Patterns | Sort-Object -Unique)
    file_count=$files.Count
    sha256=$hash
  }
  $script:MIRAssurancePatternFingerprintCache[$cacheKey] = $fingerprint
  return $fingerprint
}

function Resolve-MIRAssurancePerformanceCampaignPath {
  param([Parameter(Mandatory)]$Context)

  $ledgerPath = Join-Path $repo ".mir\releases.json"
  $ledger = Get-Content -Raw -LiteralPath $ledgerPath | ConvertFrom-Json
  $targetKey = "factorio-$($Context.target)"
  $targetProperty = $ledger.development.PSObject.Properties[$targetKey]
  if ([int]$ledger.schema -ne 1 -or [string]$ledger.authority -ne "canonical-release-ledger" -or $null -eq $targetProperty) {
    throw "Canonical release ledger has no valid performance campaign authority for $targetKey."
  }
  $authority = $targetProperty.Value
  $release = [string]$authority.mir_version
  $candidateId = [string]$authority.candidate_id
  if ($release -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or $candidateId -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') {
    throw "Active performance campaign release or candidate identity is invalid for $targetKey."
  }
  return ".mir/performance-campaigns/$release-$candidateId.json"
}

function Get-MIRAssurancePerformanceCampaignFingerprint {
  param([Parameter(Mandatory)]$Context)

  $versionedCampaign = Resolve-MIRAssurancePerformanceCampaignPath -Context $Context
  return Get-MIRAssurancePatternFingerprint -Patterns @(
    ".mir/performance-campaign.json",
    $versionedCampaign
  )
}

function Resolve-MIRAssuranceApprovedDeltaPath {
  param([Parameter(Mandatory)]$VerificationProfile)
  $fromVersion = [string]$VerificationProfile.upgrade.from_version
  $toVersion = [string]$VerificationProfile.upgrade.to_version
  $versionPattern = '^[0-9]+\.[0-9]+\.[0-9]+$'
  if ($fromVersion -notmatch $versionPattern -or $toVersion -notmatch $versionPattern) {
    throw "Approved-delta transition versions must be exact semantic versions: '$fromVersion' -> '$toVersion'."
  }
  return Resolve-MIRAssuranceRepoPathId -Id "releases.deltas" -Suffix "$fromVersion-to-$toVersion.json"
}

function Get-MIRAssuranceApprovedDeltaTransitionFingerprint {
  param([Parameter(Mandatory)]$Context)

  $relativePath = Resolve-MIRAssuranceApprovedDeltaPath -VerificationProfile $Context.verification_profile
  $fromVersion = [string]$Context.verification_profile.upgrade.from_version
  $toVersion = [string]$Context.verification_profile.upgrade.to_version
  $releaseRoot = Resolve-MIRAssuranceRepoPathId -Id "releases.records"
  $releaseRelativePath = Join-Path $releaseRoot "$($Context.info.version).json"
  $releasePath = Join-Path $repo $releaseRelativePath
  if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
    $release = Get-Content -Raw -LiteralPath $releasePath | ConvertFrom-Json
    if ([string]$release.release -eq $toVersion -and [string]$release.target -eq [string]$Context.target) {
      foreach ($field in @("from_version", "to_version", "fixture")) {
        if ([string]$release.upgrade.$field -ne [string]$Context.verification_profile.upgrade.$field) {
          throw "Approved-delta profile does not match current release upgrade authority for $field."
        }
      }
      if ([string]$release.state -in @("planned", "source-frozen", "package-built")) {
        $hasApprovedDeltaProof = $null -ne $release.proofs -and
          $null -ne $release.proofs.PSObject.Properties["approved_delta"]
        $remaining = @($release.remaining_obligations | ForEach-Object { [string]$_ })
        if ($hasApprovedDeltaProof -or $remaining -notcontains "focused-qualification") {
          throw "Pre-qualification release $toVersion has inconsistent approved-delta authority."
        }
        $material = [ordered]@{
          kind="approved-delta-transition"
          state="pending"
          from_version=$fromVersion
          to_version=$toVersion
          path=$relativePath
          release_record=(Get-MIRAssuranceRepoRelativePath -Path $releasePath)
          release_state=[string]$release.state
          release_record_sha256=(Get-MIRAssuranceSha256 -Path $releasePath)
        }
        $material["sha256"] = Get-MIRAssuranceJsonHash -Value $material
        return $material
      }
    }
  }

  # MIR 4 candidate-programme profiles intentionally exist before a typed
  # release record or approved-delta artifact. Bind the pending fingerprint to
  # the exact implementation authorization and target registry instead of
  # fabricating release authority or treating the absent future artifact as an
  # assurance-tooling failure.
  if ([string]$Context.verification_profile.release_authority_mode -eq 'candidate-programme') {
    $authorityRelative = ([string]$Context.verification_profile.release_authority).Replace('\', '/')
    if ($authorityRelative -notmatch '^\.mir/releases/waves/mir4-r0/[A-Za-z0-9._-]+\.json$') {
      throw "Candidate-programme approved-delta authority path is unsafe: $authorityRelative"
    }
    $authorityPath = Join-Path $repo $authorityRelative
    $registryRelative = '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV5.json'
    $registryPath = Join-Path $repo $registryRelative
    if (-not (Test-Path -LiteralPath $authorityPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
      throw 'Candidate-programme approved-delta authority or target registry is absent.'
    }
    # These self-hashed authorities preserve lexical RFC 3339 timestamps.
    # PowerShell otherwise converts them through the runner's local time zone.
    $authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json -DateKind String
    $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json -DateKind String
    $targetRows = @($registry.payload.targets | Where-Object {
      [string]$_.factorio -eq [string]$Context.target
    })
    if (-not (Test-MIR4BootstrapRecordHash -Record $authority) -or
        -not (Test-MIR4BootstrapRecordHash -Record $registry) -or
        [string]$authority.kind -ne 'MIR4M4C01ImplementationAuthorizationV1' -or
        [string]$authority.status -ne 'authorized-in-progress' -or
        @($authority.authorized) -notcontains 'exact-engine-development-proof' -or
        @($authority.not_authorized) -notcontains 'production-seal' -or
        @($authority.not_authorized) -notcontains 'github-release-publication' -or
        @($authority.not_authorized) -notcontains 'mod-portal-mir4-upload' -or
        [string]$registry.kind -ne 'MIR4-Target-RegistryV5' -or
        [string]$registry.status -ne 'accepted-candidate-programme-current' -or
        $registry.package_visible -or $targetRows.Count -ne 1) {
      throw 'Candidate-programme approved-delta authority boundary is invalid.'
    }
    $targetRow = $targetRows[0]
    $expectedVersion = "4.0.$([string]$targetRow.distribution_target_code)00"
    if ([string]$targetRow.mir3_predecessor -ne $fromVersion -or
        $expectedVersion -ne $toVersion -or
        [string]$targetRow.disposition -notin @('candidate-mandatory', 'candidate-conditional')) {
      throw 'Candidate-programme approved-delta profile does not match the exact target registry row.'
    }
    $material = [ordered]@{
      kind='approved-delta-transition'
      state='pending'
      from_version=$fromVersion
      to_version=$toVersion
      path=$relativePath
      release_record=$authorityRelative
      release_state=[string]$authority.status
      release_record_sha256=(Get-MIRAssuranceSha256 -Path $authorityPath)
      target_registry=$registryRelative
      target_registry_sha256=(Get-MIRAssuranceSha256 -Path $registryPath)
      authority_class='candidate-programme-development-only'
    }
    $material['sha256'] = Get-MIRAssuranceJsonHash -Value $material
    return $material
  }

  $path = Join-Path $repo $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Approved-delta transition artifact is absent: $relativePath"
  }
  return [ordered]@{
    kind="approved-delta-transition"
    state="present"
    from_version=$fromVersion
    to_version=$toVersion
    path=$relativePath
    sha256=(Get-MIRAssuranceSha256 -Path $path)
  }
}

function Resolve-MIRAssuranceManualReviewAttestationPath {
  param([Parameter(Mandatory)]$Info)
  $version = [string]$Info.version
  if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "Manual-review attestation version must be an exact semantic version: '$version'."
  }
  return ".mir/evidence/$version-manual-review-attestation.json"
}

function Get-MIRAssuranceInputFingerprint {
  param(
    [Parameter(Mandatory)][string]$InputName,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Test
  )
  switch ($InputName) {
    "candidate" { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.candidate -MissingLabel "candidate" }
    "factorio" { return Get-MIRAssuranceFactorioInstallationFingerprint -FactorioPath $Context.factorio }
    "factorio-installation" { return Get-MIRAssuranceFactorioInstallationFingerprint -FactorioPath $Context.factorio }
    "museum-installations" {
      Import-Module (Join-Path $repo "tools\lib\museum\MuseumCompiler.psm1") -Force
      $museumCatalog = Get-MIRMuseumCatalog -Path (Join-Path $repo ".mir\museum-targets.json")
      $installations = @(
        foreach ($museumTarget in @($museumCatalog.targets)) {
          $installation = Resolve-MIRMuseumInstallation -Target $museumTarget -RepoRoot $repo
          $validation = Test-MIRMuseumExactInstallation -Catalog $museumCatalog -Target $museumTarget -Installation $installation
          if (-not $validation.passed) { throw ($validation.errors -join "`n") }
          [ordered]@{
            target=[string]$museumTarget.factorio
            installation_id=[string]$museumTarget.installation_id
            binary_sha256=[string]$validation.binary_sha256
            base_file_count=[int]$validation.base_file_count
            base_data_bytes=[long]$validation.base_data_bytes
            base_data_sha256=[string]$validation.base_data_sha256
          }
        }
      )
      return [ordered]@{
        kind="museum-installations"
        installations=$installations
        sha256=(Get-MIRAssuranceJsonHash -Value $installations)
      }
    }
    "prior-release" { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.prior_release -MissingLabel "prior-release" }
    "approved-delta-transition" {
      return Get-MIRAssuranceApprovedDeltaTransitionFingerprint -Context $Context
    }
    "manual-review-attestation" {
      $relativePath = Resolve-MIRAssuranceManualReviewAttestationPath -Info $Context.info
      $path = Join-Path $repo $relativePath
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Manual-review attestation is absent: $relativePath"
      }
      return [ordered]@{
        kind="manual-review-attestation"
        version=[string]$Context.info.version
        path=$relativePath
        sha256=(Get-MIRAssuranceSha256 -Path $path)
      }
    }
    "package-source" {
      $files = @(Get-MIRAssurancePackageFiles)
      return [ordered]@{ kind="package-source"; file_count=$files.Count; sha256=(Get-MIRAssuranceTreeHash -Paths $files) }
    }
    "repository" {
      $files = @(Get-MIRAssuranceRepositoryFiles)
      return [ordered]@{ kind="repository"; file_count=$files.Count; sha256=(Get-MIRAssuranceTreeHash -Paths $files) }
    }
    "release-history" {
      $sourceLock = Get-MIRAssuranceGitIndexFingerprint -Pathspecs @(
        ".mir/releases/sources/published-source-locks.json"
      )
      if ([int]$sourceLock.file_count -ne 1) {
        throw "Unable to resolve the staged compact source-lock authority for release-history fingerprinting."
      }
      $inventory = Get-MIRAssuranceGitIndexFingerprint -Pathspecs @(".mir/distributions.json", "dist")
      $successorAuthority = Get-MIRAssuranceGitIndexFingerprint -Pathspecs @(
        ".gitattributes",
        ".mir/assurance.json",
        ".mir/compatibility.yml",
        ".mir/control",
        ".mir/control-plane/ownership.json",
        ".mir/docs.yml",
        ".mir/modules.yml",
        ".mir/releases/governance/mir4/supply-chain.json",
        ".mir/releases/waves/mir4-r0",
        "assurance/.mir-root.json",
        "releases/migrations",
        "contracts/repository",
        "governance/.mir-root.json",
        "governance/repository/migrations",
        "assurance/repository",
        "tests/.mir-root.json",
        "validation/tests.yml",
        "tools/mir.ps1",
        "mir.lock",
        "spec/compatibility/claims.json",
        "spec/schemas",
        "tools/mir/application/migration",
        "tools/mir/application/targets",
        "tools/mir/application/compiler",
        "tools/mir/application/runtime",
        "tools/mir/application/extensions",
        "tools/mir/application/processir",
        "tools/mir/application/inspection",
        "tools/mir/application/assurance",
        "tools/mir/application/custody",
        "tools/mir/application/history",
        "tools/mir/application/release",
        "tools/mir/application/technology",
        "tools/mir/domain/safety",
        "tools/mir/domain/policy",
        "tools/mir/cli",
        "tools/lib/assurance",
        "tools/lib/mir4",
        "tools/commands/mir4",
        "tests/compiler",
        "tests/runtime",
        "tests/extensions",
        "tests/processir",
        "tests/inspection",
        "tests/assurance",
        "tests/history",
        "tests/release-tooling",
        "tests/targets",
        "tests/technology",
        "tests/mir4",
        "tests/release/Test-MIRPublishedSnapshotIntegrity.ps1",
        "tests/release/Test-MIR4OfflineCandidateCustody.ps1",
        "tests/tooling/Test-MIRAssurance.ps1",
        "docs/architecture",
        "docs/compatibility",
        "docs/developer/environment-locks.md",
        "docs/reference/generated",
        "docs/releases",
        "sdk/preview/mir4/reference/t13"
      )
      if ([int]$successorAuthority.file_count -lt 5) {
        throw "Unable to resolve the staged append-only pre-freeze authority closure for release-history fingerprinting."
      }
      $packageFiles = @(Get-MIRAssurancePackageFiles)
      $packageSource = [ordered]@{
        kind="package-source"
        file_count=$packageFiles.Count
        sha256=(Get-MIRAssuranceTreeHash -Paths $packageFiles)
      }
      $material = [ordered]@{
        source_lock=$sourceLock
        inventory=$inventory
        successor_authority=$successorAuthority
        package_source=$packageSource
      }
      return [ordered]@{
        kind="release-history"
        source_lock=$sourceLock
        inventory=$inventory
        successor_authority=$successorAuthority
        package_source=$packageSource
        sha256=(Get-MIRAssuranceJsonHash -Value $material)
      }
    }
    "test-catalog" { return [ordered]@{ kind="manifest"; path="validation/tests.yml"; digest_policy=$script:MIRAssuranceCanonicalJsonDigestPolicyId; sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path $catalogPath) } }
    "target-profile" {
      return Get-MIRAssurancePatternFingerprint -Patterns @(".mir/targets.json", "tools/lib/validation/TargetProfiles.ps1")
    }
    "verification-profile" {
      $path = Get-MIRAssuranceVerificationProfilePath -Target $Context.target
      return [ordered]@{ kind="verification-profile"; path=(Get-MIRAssuranceRepoRelativePath -Path $path); digest_policy=$script:MIRAssuranceCanonicalJsonDigestPolicyId; sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path $path) }
    }
    "performance-campaign" { return Get-MIRAssurancePerformanceCampaignFingerprint -Context $Context }
    "selected-scenarios" {
      $selectionHash = Get-MIRAssuranceJsonHash -Value $Plan.impact_selection
      $registryHash = Get-MIRAssuranceCanonicalJsonFileHash -Path $scenarioRegistryPath
      return [ordered]@{
        kind="selected-scenarios"
        selection_sha256=$selectionHash
        registry_sha256=$registryHash
        sha256=(Get-MIRAssuranceTextHash -Text "$selectionHash`n$registryHash")
      }
    }
    "exact-dist-scenarios" {
      $registryHash = Get-MIRAssuranceCanonicalJsonFileHash -Path $scenarioRegistryPath
      return [ordered]@{ kind="exact-dist-scenarios"; registry_sha256=$registryHash; selector="smoke"; sha256=(Get-MIRAssuranceTextHash -Text "$registryHash`nsmoke") }
    }
    "required-scenarios" {
      return [ordered]@{ kind="required-scenarios"; sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path $scenarioRegistryPath) }
    }
    "harness" { return Get-MIRAssuranceScenarioHarnessFingerprint }
    "scenario-harness" { return Get-MIRAssuranceScenarioHarnessFingerprint }
    "scenario-record" { return Get-MIRAssuranceScenarioRecordFingerprint -Test $Test }
    "scenario-fixtures" { return Get-MIRAssuranceScenarioFixtureFingerprint -Test $Test }
    "scenario-domains" { return Get-MIRAssuranceScenarioDomainFingerprint -Test $Test -Context $Context }
    "balance-contract" { return Get-MIRAssuranceBalanceContractFingerprint }
    "fixtures" { return Get-MIRAssurancePatternFingerprint -Patterns @("fixtures/**") }
    "settings" {
      return Get-MIRAssurancePatternFingerprint -Patterns @("settings*.lua", "prototypes/mir/settings/**", ".mir/settings.yml")
    }
    "mod-lock" {
      $policy = Get-MIRAssurancePatternFingerprint -Patterns @(
        ".mir/fixtures.yml",
        "spec/compatibility/**",
        "validation/adapters/**",
        "validation/assertions/**",
        "validation/scenarios/**",
        "fixtures/local-mod-library/**"
      )
      $closure = Get-MIRAssuranceModClosureFingerprint -ModsRoot $Context.mods
      return [ordered]@{
        kind="mod-lock-and-closure"
        policy=$policy
        closure=$closure
        sha256=(Get-MIRAssuranceJsonHash -Value ([ordered]@{policy=$policy; closure=$closure}))
      }
    }
    "mod-closure" { return Get-MIRAssuranceModClosureFingerprint -ModsRoot $Context.mods }
    "ecosystem-profile" {
      return Get-MIRAssurancePatternFingerprint -Patterns @(
        "fixtures/run-profiles/**",
        "spec/compatibility/**",
        "validation/adapters/**",
        "validation/assertions/**",
        "validation/scenarios/**"
      )
    }
    "upgrade-fixture" {
      $fixture = [string]$Context.verification_profile.upgrade.fixture
      return Get-MIRAssurancePatternFingerprint -Patterns @(
        "fixtures/$fixture/**",
        "fixtures/upgrade-modset-source/**",
        "tests/runtime/Test-MIRUpgrade.ps1",
        "tests/runtime/Test-MIRUpgradeMatrix.ps1",
        "spec/schemas/upgrade-matrix.schema.json"
      )
    }
    "mir4-bootstrap-governed-output" {
      $governedRoot = Join-Path $repo "build/mir4/emergency-lane"
      $rootItem = if (Test-Path -LiteralPath $governedRoot) { Get-Item -LiteralPath $governedRoot -Force } else { $null }
      $isDirectory = $null -ne $rootItem -and $rootItem.PSIsContainer
      $isReparse = $null -ne $rootItem -and (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
      $state = if ($null -eq $rootItem) { "missing" } elseif (-not $isDirectory) { "invalid-file" } `
        elseif ($isReparse) { "invalid-reparse-directory" } else { "directory" }
      $files = if ($isDirectory -and -not $isReparse) {
        @(Get-ChildItem -LiteralPath $governedRoot -Recurse -File -Force | ForEach-Object {
          Get-MIRAssuranceRepoRelativePath -Path $_.FullName
        })
      } elseif ($null -ne $rootItem -and -not $isDirectory) {
        @(Get-MIRAssuranceRepoRelativePath -Path $rootItem.FullName)
      } else { @() }
      return [ordered]@{
        kind="mir4-bootstrap-governed-output"
        state=$state
        file_count=$files.Count
        sha256=$(if ($files.Count -gt 0) {
          Get-MIRAssuranceTreeHash -Paths $files
        } elseif ($isDirectory -and -not $isReparse) {
          Get-MIRAssuranceTextHash -Text "EMPTY:mir4-bootstrap-governed-output"
        } else {
          Get-MIRAssuranceTextHash -Text "$($state.ToUpperInvariant()):mir4-bootstrap-governed-output"
        })
      }
    }
    "mir4-bootstrap-toolchain" {
      $pwshPath = (Get-Process -Id $PID).Path
      $toolchainRoot = (Resolve-Path -LiteralPath $PSHOME).Path
      $rootItem = Get-Item -LiteralPath $toolchainRoot -Force
      $rows = [Collections.Generic.List[string]]::new()
      [int]$fileCount = 0
      foreach ($item in @(Get-ChildItem -LiteralPath $toolchainRoot -Recurse -Force)) {
        $relative = [IO.Path]::GetRelativePath($toolchainRoot, $item.FullName).Replace('\', '/')
        $isReparse = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($item.PSIsContainer) {
          $rows.Add("D`t$relative`t$([bool]$isReparse)")
        } else {
          $rows.Add("F`t$relative`t$([long]$item.Length)`t$(Get-MIRAssuranceSha256 -Path $item.FullName)`t$([bool]$isReparse)")
          $fileCount++
        }
      }
      $rows.Sort([StringComparer]::Ordinal)
      $portableTree = [ordered]@{
        kind='external-tree'
        state=$(if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { 'reparse-root' } else { 'present' })
        entry_count=[int]$rows.Count
        file_count=$fileCount
        sha256=(Get-MIRAssuranceTextHash -Text $(if ($rows.Count -gt 0) { $rows -join "`n" } else { 'EMPTY:mir4-bootstrap-toolchain' }))
      }
      $material = [ordered]@{
        powershell_version=[string]$PSVersionTable.PSVersion
        dotnet_runtime_version=[string][Environment]::Version
        os_platform=[string][Environment]::OSVersion.Platform
        os_version=[string][Environment]::OSVersion.Version
        process_architecture=[string][Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
        executable=[IO.Path]::GetFileName($pwshPath)
        files=$portableTree
      }
      return [ordered]@{
        kind='mir4-bootstrap-toolchain'
        powershell_version=[string]$material.powershell_version
        dotnet_runtime_version=[string]$material.dotnet_runtime_version
        os_platform=[string]$material.os_platform
        os_version=[string]$material.os_version
        process_architecture=[string]$material.process_architecture
        executable=[string]$material.executable
        files=$portableTree
        sha256=(Get-MIRAssuranceJsonHash -Value $material)
      }
    }
    "candidate-seal" {
      if ($Context.seal) { return Get-MIRAssuranceExternalFileFingerprint -Path $Context.seal -MissingLabel "candidate-seal" }
      return Get-MIRAssurancePatternFingerprint -Patterns @(".mir/evidence/candidate-seals/**")
    }
    "evidence" {
      $paths = @()
      if ($Context.seal -and (Test-Path -LiteralPath $Context.seal -PathType Leaf)) {
        $paths += Get-MIRAssuranceRepoRelativePath -Path $Context.seal
        $seal = Get-Content -Raw -LiteralPath $Context.seal | ConvertFrom-Json
        if ($seal.qualification_summary) { $paths += ([string]$seal.qualification_summary).Replace("\", "/") }
      } else {
        $paths = @(Resolve-MIRAssurancePatternFiles -Patterns @(".mir/evidence/**"))
      }
      return [ordered]@{ kind="evidence"; file_count=$paths.Count; sha256=(Get-MIRAssuranceTreeHash -Paths $paths) }
    }
    "runtime.full" {
      $material = [ordered]@{
        target=[string]$Context.target
        scenario_registry_sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path $scenarioRegistryPath)
        domain_manifest_sha256=if ($Plan.domain_manifest) { [string]$Plan.domain_manifest.manifest_sha256 } else { "" }
        harness=(Get-MIRAssuranceScenarioHarnessFingerprint).sha256
      }
      return [ordered]@{ kind="required-runtime-set"; sha256=(Get-MIRAssuranceJsonHash -Value $material) }
    }
    default {
      $looksLikePath = $InputName.Contains("/") -or $InputName.Contains("\") -or $InputName.Contains("*") -or $InputName.Contains(".")
      if (-not $looksLikePath) { throw "Unknown assurance input token '$InputName'. Declare a supported token or repository path pattern." }
      return Get-MIRAssurancePatternFingerprint -Patterns @($InputName)
    }
  }
}

function Get-MIRAssuranceTestFingerprint {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  $definition = [ordered]@{
    id=[string]$Test.id
    template_id=[string]$Test.template_id
    kind=[string]$Test.kind
    layer=[string]$Test.layer
    command=[string]$Test.command
    requires_factorio=[bool]$Test.requires_factorio
    requires_candidate=[bool]$Test.requires_candidate
    inputs=@($Test.inputs | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    domain_dependencies=@($Test.domain_dependencies | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    scenario_sha256=if ($Test.scenario) { Get-MIRAssuranceJsonHash -Value $Test.scenario } else { "" }
  }
  $definitionHash = Get-MIRAssuranceJsonHash -Value $definition
  $inputFingerprints = [ordered]@{}
  $runnerHash = Get-MIRAssuranceRunnerHash
  if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($Test.id) runner" }
  $inputFingerprints["assurance-runner"] = [ordered]@{ kind="runner"; version=$assuranceRunnerVersion; sha256=$runnerHash }
  foreach ($inputName in @($definition.inputs)) {
    if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($Test.id) input=$inputName start" }
    $inputFingerprints[$inputName] = Get-MIRAssuranceInputFingerprint -InputName $inputName -Plan $Plan -Context $Context -Test $Test
    if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($Test.id) input=$inputName done" }
  }
  $material = [ordered]@{
    schema=$evidenceSchema
    test_id=[string]$Test.id
    target=[string]$Context.target
    definition_sha256=$definitionHash
    inputs=$inputFingerprints
  }
  $fingerprintHash = Get-MIRAssuranceJsonHash -Value $material
  return [ordered]@{
    schema=$evidenceSchema
    test_id=[string]$Test.id
    target=[string]$Context.target
    definition=$definition
    definition_sha256=$definitionHash
    inputs=$inputFingerprints
    fingerprint_sha256=$fingerprintHash
    input_key=$fingerprintHash
  }
}
