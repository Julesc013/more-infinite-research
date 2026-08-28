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
    $authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json
    $registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
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
        "tests/targets",
        "tests/technology",
        "validation/tests/mir4",
        "validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1",
        "validation/tests/release/Test-MIR4OfflineCandidateCustody.ps1",
        "validation/tests/tooling/Test-MIRAssurance.ps1",
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
        "validation/tests/runtime/Test-MIRUpgrade.ps1",
        "validation/tests/runtime/Test-MIRUpgradeMatrix.ps1",
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

function Get-MIRAssuranceEvidencePaths {
  param([Parameter(Mandatory)][string]$TestId, [Parameter(Mandatory)][string]$InputKey)
  $safeId = $TestId -replace '[^A-Za-z0-9._-]', '_'
  $root = Join-Path $evidenceRoot (Join-Path $safeId $InputKey)
  return [ordered]@{
    root=$root
    attempts=(Join-Path $root "attempts")
    passed=(Join-Path $root "passed.json")
    blocked=(Join-Path $root "blocked.json")
    running=(Join-Path $root "running.json")
  }
}

function Get-MIRAssuranceRepositoryIdentity {
  if (-not [string]::IsNullOrWhiteSpace([string]$env:GITHUB_REPOSITORY)) {
    return [string]$env:GITHUB_REPOSITORY
  }
  $remote = @(& git -C $repo remote get-url origin 2>$null)
  if ($LASTEXITCODE -eq 0 -and $remote.Count -gt 0) {
    $identity = ([string]$remote[0]).Trim()
    $identity = $identity -replace '^git@github\.com:', ''
    $identity = $identity -replace '^https://github\.com/', ''
    $identity = $identity -replace '\.git$', ''
    if ($identity) { return $identity }
  }
  return "local"
}

function Get-MIRAssuranceCurrentTrustClass {
  if ($env:MIR_TRUST_CLASS) { return [string]$env:MIR_TRUST_CLASS }
  if ([string]$env:GITHUB_EVENT_NAME -eq "pull_request" -or [string]$env:GITHUB_EVENT_NAME -eq "pull_request_target") {
    return "untrusted-pr"
  }
  if ($env:GITHUB_ACTIONS) { return "protected-integration" }
  return "untrusted-local"
}

function Get-MIRAssuranceProducer {
  $trustClass = Get-MIRAssuranceCurrentTrustClass
  return [ordered]@{
    repository=(Get-MIRAssuranceRepositoryIdentity)
    workflow=if ($env:GITHUB_WORKFLOW) { [string]$env:GITHUB_WORKFLOW } else { "local" }
    run_id=if ($env:GITHUB_RUN_ID) { [string]$env:GITHUB_RUN_ID } else { "local-$PID" }
    run_attempt=if ($env:GITHUB_RUN_ATTEMPT) { [string]$env:GITHUB_RUN_ATTEMPT } else { "1" }
    job=if ($env:GITHUB_JOB) { [string]$env:GITHUB_JOB } else { "local" }
    actor=if ($env:GITHUB_ACTOR) { [string]$env:GITHUB_ACTOR } else { [Environment]::UserName }
    commit=(& git -C $repo rev-parse HEAD).Trim()
    ref=if ($env:GITHUB_REF) { [string]$env:GITHUB_REF } else { "local" }
    event=if ($env:GITHUB_EVENT_NAME) { [string]$env:GITHUB_EVENT_NAME } else { "local" }
    environment=if ($env:MIR_PROTECTED_ENVIRONMENT) { [string]$env:MIR_PROTECTED_ENVIRONMENT } else { "local" }
    runner_identity=if ($env:MIR_TRUSTED_RUNNER) { [string]$env:MIR_TRUSTED_RUNNER } else { "local" }
    trust_class=$trustClass
    verifier_sha256=(Get-MIRAssuranceRunnerHash)
    policy_sha256=(Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))
  }
}

function Get-MIRAssuranceHostIdentity {
  if (-not [string]::IsNullOrWhiteSpace([string]$env:MIR_HOST_IDENTITY)) {
    return [string]$env:MIR_HOST_IDENTITY
  }
  $machine = [Environment]::MachineName
  if (-not [string]::IsNullOrWhiteSpace([string]$env:RUNNER_NAME)) {
    return "github:$([string]$env:RUNNER_NAME)@$machine"
  }
  return "host:$machine"
}

function Get-MIRAssuranceProcessStartedAt {
  param([int]$ProcessId = $PID)
  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($null -eq $process) { return "" }
  return ([DateTimeOffset]$process.StartTime.ToUniversalTime()).ToString("o")
}

function Get-MIRAssuranceEvidenceProducer {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  $producer = ConvertTo-MIRAssuranceOrderedMap -Object (Get-MIRAssuranceProducer)
  if (-not [bool]$Test.force_fresh) { return $producer }

  $campaignId = [string]$Test.required_campaign_id
  $campaignMaterial = [string]$Test.required_campaign_plan_material_sha256
  if ([string]::IsNullOrWhiteSpace($campaignId) -or $campaignMaterial -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Fresh evidence for '$([string]$Test.id)' is missing its immutable plan-owned campaign identity."
  }
  # A host run is only an execution attempt.  Freshness belongs to the
  # immutable plan campaign so a timeout, runner replacement, or deliberate
  # checkpoint can resume without repeating an already validated row.
  $producer["campaign_id"] = $campaignId
  $producer["campaign_plan_material_sha256"] = $campaignMaterial
  return $producer
}

function Test-MIRAssurancePlanContinuationProducer {
  param(
    [Parameter(Mandatory)]$Producer,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$SourceCommit
  )
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Producer -Context $Context)) { return $false }
  if ([string]$Producer.commit -ne $SourceCommit) { return $false }
  if ([string]$Context.trust_class -eq "untrusted-local") { return $true }
  $current = Get-MIRAssuranceProducer
  # Run identifiers deliberately do not participate: a new protected worker
  # may continue an unchanged plan.  Its repository, workflow authority,
  # source commit, ref, environment, runner, policy and verifier must match.
  foreach ($field in @("repository", "workflow", "commit", "ref", "event", "trust_class", "environment", "runner_identity", "verifier_sha256", "policy_sha256")) {
    if ([string]$Producer.$field -ne [string]$current.$field) { return $false }
  }
  return $true
}

function Test-MIRAssuranceFreshCampaignEvidence {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan
  )
  if (-not [bool]$Test.force_fresh) { return $true }
  try {
    $minimum = ConvertTo-MIRAssuranceDateTimeOffset -Value $Test.minimum_completed_at
    $completed = ConvertTo-MIRAssuranceDateTimeOffset -Value $Capsule.completed_at
  } catch { return $false }
  return $completed -ge $minimum -and
    [string]$Capsule.producer.campaign_id -eq [string]$Test.required_campaign_id -and
    [string]$Capsule.producer.campaign_plan_material_sha256 -eq [string]$Test.required_campaign_plan_material_sha256 -and
    [string]$Capsule.producer.campaign_plan_material_sha256 -eq [string]$Plan.plan_material_sha256 -and
    [string]$Capsule.producer.commit -eq [string]$Plan.source_commit
}

function Test-MIRAssuranceTrustedProducer {
  param([Parameter(Mandatory)]$Producer, [Parameter(Mandatory)]$Context)
  if ($null -eq $Producer) { return $false }
  $repository = [string]$Producer.repository
  if ([string]::IsNullOrWhiteSpace($repository)) { return $false }
  $current = Get-MIRAssuranceRepositoryIdentity
  if ($repository -ne $current -and -not ($repository -eq "local" -and $current -eq "local")) { return $false }
  if ([string]$Producer.trust_class -ne [string]$Context.trust_class) { return $false }
  if ([string]$Producer.verifier_sha256 -ne (Get-MIRAssuranceRunnerHash)) { return $false }
  if ([string]$Producer.policy_sha256 -ne (Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))) { return $false }
  return $true
}

function Test-MIRAssuranceReleaseProducer {
  param(
    [Parameter(Mandatory)]$Producer,
    [Parameter(Mandatory)]$Context,
    [string]$ExpectedCommit = "",
    [switch]$AllowAncestor
  )
  if ($null -eq $Producer -or [string]$Producer.trust_class -ne "protected-release") { return $false }
  $class = $Context.trust_policy.classes."protected-release"
  if ($null -eq $class -or $class.release_eligible -ne $true) { return $false }
  if (@($class.repositories | Where-Object { [string]$_ -eq [string]$Producer.repository }).Count -ne 1) { return $false }
  if (@($class.workflows | Where-Object { [string]$_ -eq [string]$Producer.workflow }).Count -ne 1) { return $false }
  if (@($class.events | Where-Object { [string]$_ -eq [string]$Producer.event }).Count -ne 1) { return $false }
  if (@($class.refs | Where-Object { [string]$_ -eq [string]$Producer.ref }).Count -ne 1) { return $false }
  if ([string]$Producer.environment -ne [string]$class.environment) { return $false }
  if ([string]$Producer.runner_identity -ne [string]$class.runner_identity) { return $false }
  if ($AllowAncestor) {
    & git -C $repo merge-base --is-ancestor ([string]$Producer.commit) HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
  } elseif ([string]::IsNullOrWhiteSpace($ExpectedCommit)) {
    $ExpectedCommit = (& git -C $repo rev-parse HEAD).Trim()
    if ([string]$Producer.commit -ne $ExpectedCommit) { return $false }
  } elseif ([string]$Producer.commit -ne $ExpectedCommit) { return $false }
  if ([string]$Producer.verifier_sha256 -ne (Get-MIRAssuranceRunnerHash)) { return $false }
  if ([string]$Producer.policy_sha256 -ne (Get-MIRAssuranceCanonicalJsonFileHash -Path (Get-MIRAssuranceCanonicalTrustPolicyPath))) { return $false }
  return $true
}

function Get-MIRAssuranceCapsuleDigest {
  param([Parameter(Mandatory)]$Capsule)
  $material = [ordered]@{
    schema=[int]$Capsule.schema
    test_id=[string]$Capsule.test_id
    conclusion=[string]$Capsule.conclusion
    input_key=[string]$Capsule.input_key
    fingerprint_sha256=[string]$Capsule.fingerprint_sha256
    definition_sha256=[string]$Capsule.definition_sha256
    target=[string]$Capsule.target
    command=[string]$Capsule.command
    resolved_command=[string]$Capsule.resolved_command
    inputs=$Capsule.inputs
    producer=$Capsule.producer
    assertions=$Capsule.assertions
    exit_code=[int]$Capsule.exit_code
    result=$Capsule.result
    artifacts=$Capsule.artifacts
    stdout_sha256=[string]$Capsule.stdout_sha256
    stderr_sha256=[string]$Capsule.stderr_sha256
    log_digest=[string]$Capsule.log_digest
    started_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.started_at)
    completed_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.completed_at)
    duration_seconds=[double]$Capsule.duration_seconds
    message=[string]$Capsule.message
  }
  return Get-MIRAssuranceJsonHash -Value $material
}

function Test-MIRAssuranceCapsule {
  param(
    [Parameter(Mandatory)]$Capsule,
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context
  )
  if ([int]$Capsule.schema -ne $evidenceSchema) { return [ordered]@{valid=$false; reason="schema-mismatch"} }
  if ([string]$Capsule.conclusion -ne "passed" -or [string]$Capsule.status -ne "passed") { return [ordered]@{valid=$false; reason="not-passing"} }
  if ([string]$Capsule.test_id -ne [string]$Fingerprint.test_id) { return [ordered]@{valid=$false; reason="test-id-mismatch"} }
  if ([string]$Capsule.target -ne [string]$Fingerprint.target) { return [ordered]@{valid=$false; reason="target-mismatch"} }
  if ([string]$Capsule.input_key -ne [string]$Fingerprint.input_key) { return [ordered]@{valid=$false; reason="input-key-mismatch"} }
  if ([string]$Capsule.fingerprint_sha256 -ne [string]$Fingerprint.fingerprint_sha256) { return [ordered]@{valid=$false; reason="fingerprint-mismatch"} }
  if ([string]$Capsule.definition_sha256 -ne [string]$Fingerprint.definition_sha256) { return [ordered]@{valid=$false; reason="definition-mismatch"} }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $Capsule.producer -Context $Context)) { return [ordered]@{valid=$false; reason="untrusted-producer"} }
  if ([int]$Capsule.exit_code -ne 0) { return [ordered]@{valid=$false; reason="nonzero-exit"} }
  if ($null -eq $Capsule.result -or [string]$Capsule.result.schema -ne "mir-test-result-v1" -or
      [string]$Capsule.result.status -ne "passed") {
    return [ordered]@{valid=$false; reason="missing-or-invalid-structured-result"}
  }
  $resultPath = Resolve-MIRAssurancePath -Path ([string]$Capsule.result.path)
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { return [ordered]@{valid=$false; reason="structured-result-missing"} }
  if ((Get-MIRAssuranceSha256 -Path $resultPath) -ne [string]$Capsule.result.sha256) {
    return [ordered]@{valid=$false; reason="structured-result-digest-mismatch"}
  }
  try { $structuredResult = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json }
  catch { return [ordered]@{valid=$false; reason="structured-result-invalid-json"} }
  if ([string]$structuredResult.schema -ne "mir-test-result-v1" -or
      [string]$structuredResult.test_id -ne [string]$Capsule.test_id -or
      [string]$structuredResult.status -ne "passed" -or
      [int]$structuredResult.exit_code -ne 0) {
    return [ordered]@{valid=$false; reason="structured-result-content-mismatch"}
  }
  if (@($Capsule.assertions).Count -eq 0 -or
      @($Capsule.assertions | Where-Object { [string]$_.status -ne "passed" }).Count -gt 0) {
    return [ordered]@{valid=$false; reason="assertion-outcomes-not-passing"}
  }
  if ((Get-MIRAssuranceJsonHash -Value @($Capsule.assertions)) -ne
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.assertions))) {
    return [ordered]@{valid=$false; reason="structured-result-assertion-mismatch"}
  }
  if ((Get-MIRAssuranceJsonHash -Value @($Capsule.artifacts)) -ne
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.artifacts))) {
    return [ordered]@{valid=$false; reason="structured-result-artifact-mismatch"}
  }
  foreach ($artifact in @($Capsule.artifacts)) {
    $artifactPath = Resolve-MIRAssurancePath -Path ([string]$artifact.path)
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { return [ordered]@{valid=$false; reason="artifact-missing"} }
    $item = Get-Item -LiteralPath $artifactPath
    if ($item.Length -ne [long]$artifact.bytes -or (Get-MIRAssuranceSha256 -Path $artifactPath) -ne [string]$artifact.sha256) {
      return [ordered]@{valid=$false; reason="artifact-digest-mismatch"}
    }
  }
  $expectedDigest = Get-MIRAssuranceCapsuleDigest -Capsule $Capsule
  if ([string]$Capsule.result_digest -ne $expectedDigest) { return [ordered]@{valid=$false; reason="result-digest-mismatch"} }
  return [ordered]@{valid=$true; reason="exact-trusted-pass"}
}

function Write-MIRAssuranceAtomicJson {
  param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Move-MIRAssuranceCorruptEvidence {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Reason)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $quarantine = Join-Path (Split-Path -Parent $Path) "quarantine"
  New-Item -ItemType Directory -Force -Path $quarantine | Out-Null
  $name = "$(Get-Date -Format 'yyyyMMddTHHmmssfffffffZ')-$Reason-$([guid]::NewGuid().ToString('N')).json"
  Move-Item -LiteralPath $Path -Destination (Join-Path $quarantine $name)
}

function Read-MIRAssuranceEvidencePointer {
  param([Parameter(Mandatory)][string]$Path)
  try { $pointer = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
  catch {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "invalid-json"
    return $null
  }
  if ([int]$pointer.schema -ne 1 -or [string]::IsNullOrWhiteSpace([string]$pointer.capsule_path) -or
      [string]::IsNullOrWhiteSpace([string]$pointer.capsule_sha256)) {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "invalid-pointer"
    return $null
  }
  $capsulePath = Resolve-MIRAssurancePath -Path ([string]$pointer.capsule_path)
  if (-not (Test-Path -LiteralPath $capsulePath -PathType Leaf) -or
      (Get-MIRAssuranceSha256 -Path $capsulePath) -ne [string]$pointer.capsule_sha256) {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "broken-pointer"
    return $null
  }
  try { return Get-Content -Raw -LiteralPath $capsulePath | ConvertFrom-Json }
  catch {
    Move-MIRAssuranceCorruptEvidence -Path $Path -Reason "invalid-capsule"
    return $null
  }
}

function Get-MIRAssuranceWorkerCanonicalPath {
  param([Parameter(Mandatory)][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf([char]0) -ge 0 -or
      [IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or $Path.StartsWith("\\")) {
    throw "Worker evidence path must be repository-relative: $Path"
  }
  $normalized = $Path.Replace("\", "/").Normalize([Text.NormalizationForm]::FormC)
  if ($normalized.StartsWith("/") -or $normalized -match '[<>:"|?*\x00-\x1F]') {
    throw "Worker evidence path contains unsafe Windows path syntax: $Path"
  }
  $segments = @($normalized.Split("/"))
  if ($segments.Count -eq 0 -or @($segments | Where-Object {
      $_ -in @("", ".", "..") -or $_.EndsWith(" ") -or $_.EndsWith(".") -or
      $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
    }).Count -gt 0) {
    throw "Worker evidence path is not canonically representable on Windows: $Path"
  }
  return [pscustomobject][ordered]@{
    path=$normalized
    key=$normalized.ToUpperInvariant()
  }
}

function Get-MIRAssuranceWindowsAlternateDataStreams {
  param([Parameter(Mandatory)][string]$Path)

  if ($env:OS -ne "Windows_NT") { return @() }
  if (-not ("MIR.NativeStreams" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MIR {
  public static class NativeStreams {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct StreamData {
      public long StreamSize;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)] public string StreamName;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindFirstStreamW(string fileName, int infoLevel, out StreamData data, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FindNextStreamW(IntPtr handle, out StreamData data);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FindClose(IntPtr handle);
  }
}
'@
  }
  $fullPath = [IO.Path]::GetFullPath($Path)
  $nativePath = if ($fullPath.StartsWith("\\", [StringComparison]::Ordinal)) {
    "\\?\UNC\" + $fullPath.Substring(2)
  } else {
    "\\?\" + $fullPath
  }
  $data = New-Object MIR.NativeStreams+StreamData
  $handle = [MIR.NativeStreams]::FindFirstStreamW($nativePath, 0, [ref]$data, 0)
  $invalidHandle = [IntPtr](-1)
  if ($handle -eq $invalidHandle) {
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw [ComponentModel.Win32Exception]::new($errorCode, "Unable to enumerate alternate data streams for '$fullPath'.")
  }
  $streams = [Collections.Generic.List[string]]::new()
  try {
    do {
      if ([string]$data.StreamName -ne '::$DATA') { $streams.Add([string]$data.StreamName) }
      $hasNext = [MIR.NativeStreams]::FindNextStreamW($handle, [ref]$data)
    } while ($hasNext)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($errorCode -notin @(18, 38)) {
      throw [ComponentModel.Win32Exception]::new($errorCode, "Unable to complete alternate data stream enumeration for '$fullPath'.")
    }
  } finally {
    [void][MIR.NativeStreams]::FindClose($handle)
  }
  return @($streams)
}

function Assert-MIRAssuranceWorkerArtifactTree {
  param(
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [Parameter(Mandatory)]$Context
  )

  $limits = $Context.config.worker_import
  foreach ($field in @("max_entries_per_artifact", "max_expanded_bytes_per_artifact", "max_file_bytes")) {
    if ([long]$limits.$field -le 0) { throw "Worker-import limit '$field' must be positive." }
  }
  $resolvedRoot = [IO.Path]::GetFullPath($ArtifactRoot)
  $rootItem = Get-Item -LiteralPath $resolvedRoot -Force
  if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Worker artifact root is a symlink or reparse point: $resolvedRoot"
  }
  $directories = [Collections.Generic.Stack[string]]::new()
  $directories.Push($resolvedRoot)
  $canonicalPaths = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  $entryCount = 0
  [long]$expandedBytes = 0
  while ($directories.Count -gt 0) {
    $directory = $directories.Pop()
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
      $entryCount++
      if ($entryCount -gt [int]$limits.max_entries_per_artifact) {
        throw "Worker artifact exceeds the entry-count limit: $resolvedRoot"
      }
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Worker artifact contains a symlink or reparse point: $($item.FullName)"
      }
      $relative = [IO.Path]::GetRelativePath($resolvedRoot, $item.FullName).Replace("\", "/")
      $canonical = Get-MIRAssuranceWorkerCanonicalPath -Path $relative
      if ($canonicalPaths.ContainsKey([string]$canonical.key)) {
        throw "Worker artifact contains a case-fold or Unicode-normalization path collision: $relative"
      }
      $canonicalPaths[[string]$canonical.key] = $relative
      if ($item.PSIsContainer) {
        $directories.Push($item.FullName)
      } elseif ($item -is [IO.FileInfo]) {
        if ($env:OS -eq "Windows_NT") {
          $alternateStreams = @(Get-MIRAssuranceWindowsAlternateDataStreams -Path $item.FullName)
          if ($alternateStreams.Count -gt 0) {
            throw "Worker artifact contains an NTFS alternate data stream: $relative"
          }
        }
        if ([long]$item.Length -gt [long]$limits.max_file_bytes) {
          throw "Worker artifact contains an oversized file: $relative"
        }
        $expandedBytes += [long]$item.Length
        if ($expandedBytes -gt [long]$limits.max_expanded_bytes_per_artifact) {
          throw "Worker artifact exceeds the expanded-byte limit: $resolvedRoot"
        }
      } else {
        throw "Worker artifact contains an unsupported filesystem entry: $relative"
      }
    }
  }
  return [pscustomobject][ordered]@{entries=$entryCount;expanded_bytes=$expandedBytes}
}

function Resolve-MIRAssuranceWorkerObjectPath {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$DestinationRoot,
    [Parameter(Mandatory)][string]$RepoRelativePath
  )

  $canonicalPath = Get-MIRAssuranceWorkerCanonicalPath -Path $RepoRelativePath
  $canonicalDestination = Get-MIRAssuranceWorkerCanonicalPath -Path ((Get-MIRAssuranceRepoRelativePath -Path $DestinationRoot).Replace("\", "/").TrimEnd("/"))
  $normalizedPath = [string]$canonicalPath.path
  $normalizedDestination = [string]$canonicalDestination.path + "/"
  if (-not $normalizedPath.StartsWith($normalizedDestination, [StringComparison]::Ordinal)) {
    throw "Worker evidence path escapes its planned fingerprint subtree: $RepoRelativePath"
  }
  $suffix = $normalizedPath.Substring($normalizedDestination.Length)
  if ([string]::IsNullOrWhiteSpace($suffix)) {
    throw "Worker evidence path is not a safe file path: $RepoRelativePath"
  }

  $resolvedSourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
  $resolved = [IO.Path]::GetFullPath((Join-Path $SourceRoot ($suffix.Replace("/", [IO.Path]::DirectorySeparatorChar))))
  if (-not $resolved.StartsWith($resolvedSourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Worker evidence source path escapes its artifact directory: $RepoRelativePath"
  }
  $sourceItem = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
  if ($null -ne $sourceItem -and ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Worker evidence source is a symlink or reparse point: $RepoRelativePath"
  }
  return $resolved
}

function Write-MIRAssuranceWorkerReceipt {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Capsule
  )

  $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$Test.id) -InputKey ([string]$Test.fingerprint.input_key)
  $capsulePath = Resolve-MIRAssurancePath -Path ([string]$Capsule.attempt_path)
  if (-not (Test-Path -LiteralPath $capsulePath -PathType Leaf)) {
    throw "Cannot write a worker receipt without the immutable evidence capsule for '$([string]$Test.id)'."
  }
  $planMaterialSha256 = [string]$Plan.plan_material_sha256
  if ($planMaterialSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Cannot write a worker receipt without an exact plan-material digest for '$([string]$Test.id)'."
  }
  if ($null -eq $Plan.producer) {
    throw "Cannot write a worker receipt without the plan's coordination producer for '$([string]$Test.id)'."
  }
  $receiptProducer = Get-MIRAssuranceProducer
  $receiptProducerSha256 = Get-MIRAssuranceJsonHash -Value $receiptProducer
  $evidenceProducerSha256 = Get-MIRAssuranceJsonHash -Value $Capsule.producer
  $evidenceDisposition = if ($receiptProducerSha256 -eq $evidenceProducerSha256) {
    "produced-by-worker"
  } else {
    "adopted-exact-trusted-capsule"
  }
  $receipt = [ordered]@{
    schema="mir-assurance-worker-receipt-v3"
    plan=[ordered]@{
      material_sha256=$planMaterialSha256
      required_test_set_sha256=[string]$Plan.required_test_set_sha256
      generated_at=(ConvertTo-MIRAssuranceTimestampText -Value $Plan.generated_at)
      source_commit=[string]$Plan.source_commit
      source_tree=[string]$Plan.source_tree
      target=[string]$Plan.target
      profile=[string]$Plan.profile
      producer=$Plan.producer
    }
    work=[ordered]@{
      test_id=[string]$Test.id
      safe_test_id=[string]$Test.safe_test_id
      input_key=[string]$Test.fingerprint.input_key
      fingerprint_sha256=[string]$Test.fingerprint.fingerprint_sha256
      definition_sha256=[string]$Test.fingerprint.definition_sha256
      force_fresh=[bool]$Test.force_fresh
    }
    result=[ordered]@{
      conclusion=[string]$Capsule.conclusion
      result_digest=[string]$Capsule.result_digest
      capsule_path=[string]$Capsule.attempt_path
      capsule_sha256=(Get-MIRAssuranceSha256 -Path $capsulePath)
    }
    producer=$receiptProducer
    evidence_producer=$Capsule.producer
    evidence_disposition=$evidenceDisposition
    completed_at=(ConvertTo-MIRAssuranceTimestampText -Value $Capsule.completed_at)
  }
  $receiptPath = Join-Path $paths.root "worker-receipts\$planMaterialSha256.json"
  Write-MIRAssuranceAtomicJson -Value $receipt -Path $receiptPath
  return $receipt
}

function Read-MIRAssuranceWorkerObject {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Context
  )

  $fingerprint = $Test.fingerprint
  $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$Test.id) -InputKey ([string]$fingerprint.input_key)
  $planMaterialSha256 = [string]$Plan.plan_material_sha256
  if ($planMaterialSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "Worker import for '$([string]$Test.id)' has no exact plan-material digest."
  }
  $receiptPath = Join-Path $SourceRoot "worker-receipts\$planMaterialSha256.json"
  if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
    throw "Worker artifact for '$([string]$Test.id)' has no immutable worker receipt."
  }
  try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has an invalid worker receipt." }
  $expectedSafeId = ([string]$Test.id) -replace '[^A-Za-z0-9._-]', '_'
  $receiptMismatches = [Collections.Generic.List[string]]::new()
  if ([string]$receipt.schema -ne "mir-assurance-worker-receipt-v3") { $receiptMismatches.Add("schema") }
  if ([string]$receipt.plan.material_sha256 -ne [string]$Plan.plan_material_sha256) { $receiptMismatches.Add("plan-material") }
  if ([string]$receipt.plan.required_test_set_sha256 -ne [string]$Plan.required_test_set_sha256) { $receiptMismatches.Add("required-test-set") }
  $receiptGeneratedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $receipt.plan.generated_at
  $planGeneratedAt = ConvertTo-MIRAssuranceDateTimeOffset -Value $Plan.generated_at
  if ($receiptGeneratedAt.UtcDateTime.Ticks -ne $planGeneratedAt.UtcDateTime.Ticks) { $receiptMismatches.Add("plan-generated-at") }
  if ([string]$receipt.plan.source_commit -ne [string]$Plan.source_commit) { $receiptMismatches.Add("source-commit") }
  if ([string]$receipt.plan.source_tree -ne [string]$Plan.source_tree) { $receiptMismatches.Add("source-tree") }
  if ([string]$receipt.plan.target -ne [string]$Plan.target) { $receiptMismatches.Add("target") }
  if ([string]$receipt.plan.profile -ne [string]$Plan.profile) { $receiptMismatches.Add("profile") }
  if ((Get-MIRAssuranceJsonHash -Value $receipt.plan.producer) -ne (Get-MIRAssuranceJsonHash -Value $Plan.producer)) { $receiptMismatches.Add("plan-producer") }
  if ([string]$receipt.work.test_id -ne [string]$Test.id) { $receiptMismatches.Add("test-id") }
  if ([string]$receipt.work.safe_test_id -ne $expectedSafeId) { $receiptMismatches.Add("safe-test-id") }
  if ([string]$receipt.work.input_key -ne [string]$fingerprint.input_key) { $receiptMismatches.Add("input-key") }
  if ([string]$receipt.work.fingerprint_sha256 -ne [string]$fingerprint.fingerprint_sha256) { $receiptMismatches.Add("fingerprint") }
  if ([string]$receipt.work.definition_sha256 -ne [string]$fingerprint.definition_sha256) { $receiptMismatches.Add("definition") }
  if ([bool]$receipt.work.force_fresh -ne [bool]$Test.force_fresh) { $receiptMismatches.Add("freshness") }
  if ([string]$receipt.result.conclusion -notin @("passed", "failed")) { $receiptMismatches.Add("conclusion") }
  if ([string]$receipt.result.result_digest -notmatch '^[A-Fa-f0-9]{64}$') { $receiptMismatches.Add("result-digest") }
  if ([string]::IsNullOrWhiteSpace([string]$receipt.result.capsule_path)) { $receiptMismatches.Add("capsule-path") }
  if ([string]$receipt.result.capsule_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { $receiptMismatches.Add("capsule-digest") }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $receipt.producer -Context $Context)) { $receiptMismatches.Add("receipt-trust-context") }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $receipt.evidence_producer -Context $Context)) { $receiptMismatches.Add("evidence-trust-context") }
  $receiptProducerSha256 = Get-MIRAssuranceJsonHash -Value $receipt.producer
  $evidenceProducerSha256 = Get-MIRAssuranceJsonHash -Value $receipt.evidence_producer
  $expectedEvidenceDisposition = if ($receiptProducerSha256 -eq $evidenceProducerSha256) {
    "produced-by-worker"
  } else {
    "adopted-exact-trusted-capsule"
  }
  if ([string]$receipt.evidence_disposition -ne $expectedEvidenceDisposition) { $receiptMismatches.Add("evidence-disposition") }
  foreach ($field in @("repository", "workflow", "run_id", "run_attempt", "job", "commit", "ref", "event", "trust_class")) {
    if ([string]::IsNullOrWhiteSpace([string]$receipt.producer.$field)) { $receiptMismatches.Add("receipt-producer-$field") }
  }
  if (-not (Test-MIRAssurancePlanContinuationProducer -Producer $receipt.plan.producer -Context $Context -SourceCommit ([string]$Plan.source_commit))) {
    $receiptMismatches.Add("plan-continuation-authority")
  }
  if ($receiptMismatches.Count -gt 0) {
    throw "Worker artifact for '$([string]$Test.id)' receipt does not match the active plan, work row, or trust context: $($receiptMismatches -join ', ')."
  }
  $capsulePath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath ([string]$receipt.result.capsule_path)
  if (-not (Test-Path -LiteralPath $capsulePath -PathType Leaf) -or
      (Get-MIRAssuranceSha256 -Path $capsulePath) -ne [string]$receipt.result.capsule_sha256) {
    throw "Worker artifact for '$([string]$Test.id)' has a missing or digest-mismatched capsule."
  }
  try { $capsule = Get-Content -Raw -LiteralPath $capsulePath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has an invalid evidence capsule." }
  $outcome = [string]$receipt.result.conclusion
  if ([string]$capsule.attempt_path -ne [string]$receipt.result.capsule_path -or
      [int]$capsule.schema -ne $evidenceSchema -or
      [string]$capsule.test_id -ne [string]$Test.id -or
      [string]$capsule.input_key -ne [string]$fingerprint.input_key -or
      [string]$capsule.fingerprint_sha256 -ne [string]$fingerprint.fingerprint_sha256 -or
      [string]$capsule.definition_sha256 -ne [string]$fingerprint.definition_sha256 -or
      [string]$capsule.target -ne [string]$fingerprint.target -or
      [string]$capsule.status -ne $outcome -or
      [string]$capsule.conclusion -ne $outcome -or
      ($outcome -eq "passed" -and [int]$capsule.exit_code -ne 0) -or
      ($outcome -eq "failed" -and [int]$capsule.exit_code -eq 0)) {
    throw "Worker artifact for '$([string]$Test.id)' does not match its planned test, target, or fingerprint."
  }
  if ([string]$receipt.result.result_digest -ne [string]$capsule.result_digest -or
      (Get-MIRAssuranceJsonHash -Value $receipt.evidence_producer) -ne (Get-MIRAssuranceJsonHash -Value $capsule.producer) -or
      (ConvertTo-MIRAssuranceDateTimeOffset -Value $receipt.completed_at).UtcDateTime.Ticks -ne
        (ConvertTo-MIRAssuranceDateTimeOffset -Value $capsule.completed_at).UtcDateTime.Ticks) {
    throw "Worker artifact for '$([string]$Test.id)' receipt differs from its selected immutable capsule."
  }
  if (-not (Test-MIRAssuranceTrustedProducer -Producer $capsule.producer -Context $Context)) {
    throw "Worker artifact for '$([string]$Test.id)' was produced outside the active trust context."
  }
  if ([bool]$Test.force_fresh) {
    if (-not (Test-MIRAssuranceFreshCampaignEvidence -Capsule $capsule -Test $Test -Plan $Plan)) {
      throw "Worker artifact for '$([string]$Test.id)' does not satisfy the plan-owned freshness binding."
    }
  }

  $resultPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath ([string]$capsule.result.path)
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "Worker artifact for '$([string]$Test.id)' is missing its structured result."
  }
  $resultItem = Get-Item -LiteralPath $resultPath
  if ($resultItem.Length -ne [long]$capsule.result.bytes -or
      (Get-MIRAssuranceSha256 -Path $resultPath) -ne [string]$capsule.result.sha256) {
    throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched structured result."
  }
  try { $structuredResult = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json }
  catch { throw "Worker artifact for '$([string]$Test.id)' has invalid structured-result JSON." }
  if ([string]$structuredResult.schema -ne "mir-test-result-v1" -or
      [string]$structuredResult.test_id -ne [string]$Test.id -or
      [string]$structuredResult.status -ne $outcome -or
      [int]$structuredResult.exit_code -ne [int]$capsule.exit_code -or
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.assertions)) -ne (Get-MIRAssuranceJsonHash -Value @($capsule.assertions)) -or
      (Get-MIRAssuranceJsonHash -Value @($structuredResult.artifacts)) -ne (Get-MIRAssuranceJsonHash -Value @($capsule.artifacts))) {
    throw "Worker artifact for '$([string]$Test.id)' has structured content that differs from its capsule."
  }

  $objectFiles = [Collections.Generic.List[string]]::new()
  $objectFiles.Add([string]$receipt.result.capsule_path)
  $objectFiles.Add([string]$capsule.result.path)
  foreach ($artifact in @($capsule.artifacts)) {
    $artifactPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath ([string]$artifact.path)
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
      throw "Worker artifact for '$([string]$Test.id)' is missing a declared evidence artifact."
    }
    $artifactItem = Get-Item -LiteralPath $artifactPath
    if ($artifactItem.Length -ne [long]$artifact.bytes -or
        (Get-MIRAssuranceSha256 -Path $artifactPath) -ne [string]$artifact.sha256) {
      throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched declared artifact."
    }
    $objectFiles.Add([string]$artifact.path)
  }

  $normalizedResultPath = ([string]$capsule.result.path).Replace("\", "/")
  $resultDirectory = $normalizedResultPath.Substring(0, $normalizedResultPath.LastIndexOf("/"))
  $stdoutRelative = "$resultDirectory/stdout.txt"
  $stderrRelative = "$resultDirectory/stderr.txt"
  $stdoutPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath $stdoutRelative
  $stderrPath = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath $stderrRelative
  if (-not (Test-Path -LiteralPath $stdoutPath -PathType Leaf) -or
      -not (Test-Path -LiteralPath $stderrPath -PathType Leaf) -or
      (Get-MIRAssuranceSha256 -Path $stdoutPath) -ne [string]$capsule.stdout_sha256 -or
      (Get-MIRAssuranceSha256 -Path $stderrPath) -ne [string]$capsule.stderr_sha256 -or
      (Get-MIRAssuranceTextHash -Text ((Get-Content -Raw -LiteralPath $stdoutPath) + "`n" + (Get-Content -Raw -LiteralPath $stderrPath))) -ne [string]$capsule.log_digest) {
    throw "Worker artifact for '$([string]$Test.id)' has missing or digest-mismatched executor logs."
  }
  $objectFiles.Add($stdoutRelative)
  $objectFiles.Add($stderrRelative)
  if ((Get-MIRAssuranceCapsuleDigest -Capsule $capsule) -ne [string]$capsule.result_digest) {
    throw "Worker artifact for '$([string]$Test.id)' has a digest-mismatched evidence capsule."
  }
  $verifiedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($relativePath in @($objectFiles)) {
    $canonical = Get-MIRAssuranceWorkerCanonicalPath -Path $relativePath
    [void]$verifiedKeys.Add([string]$canonical.key)
  }
  foreach ($assertion in @($capsule.assertions)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$assertion.evidence)) {
      $canonicalEvidence = Get-MIRAssuranceWorkerCanonicalPath -Path ([string]$assertion.evidence)
      if (-not $verifiedKeys.Contains([string]$canonicalEvidence.key)) {
        throw "Worker artifact for '$([string]$Test.id)' has assertion evidence that is not digest-bound by its result, logs, or declared artifacts."
      }
    }
  }
  $receiptDestination = Join-Path $paths.root "worker-receipts\$planMaterialSha256.json"
  $receiptRelative = Get-MIRAssuranceRepoRelativePath -Path $receiptDestination
  $objectFiles.Add($receiptRelative)
  $canonicalFiles = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  foreach ($relativePath in @($objectFiles)) {
    $canonical = Get-MIRAssuranceWorkerCanonicalPath -Path $relativePath
    if ($canonicalFiles.ContainsKey([string]$canonical.key)) {
      throw "Worker artifact for '$([string]$Test.id)' contains duplicate canonical object paths."
    }
    $canonicalFiles[[string]$canonical.key] = [string]$canonical.path
    $null = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $SourceRoot -DestinationRoot $paths.root -RepoRelativePath $relativePath
  }
  $pointer = [ordered]@{
    schema=1
    test_id=[string]$Test.id
    input_key=[string]$fingerprint.input_key
    conclusion=$outcome
    capsule_path=[string]$receipt.result.capsule_path
    capsule_sha256=[string]$receipt.result.capsule_sha256
  }
  $suppliedPointerName = if ($outcome -eq "passed") { "passed.json" } else { "blocked.json" }
  $suppliedPointerPath = Join-Path $SourceRoot $suppliedPointerName
  $suppliedPointerStatus = "missing"
  if (Test-Path -LiteralPath $suppliedPointerPath -PathType Leaf) {
    try {
      $suppliedPointer = Get-Content -Raw -LiteralPath $suppliedPointerPath | ConvertFrom-Json
      $suppliedPointerStatus = if ((Get-MIRAssuranceJsonHash -Value $suppliedPointer) -eq (Get-MIRAssuranceJsonHash -Value $pointer)) { "validated" } else { "stale-ignored" }
    } catch {
      $suppliedPointerStatus = "invalid-ignored"
    }
  }
  return [ordered]@{
    receipt=$receipt
    receipt_sha256=(Get-MIRAssuranceSha256 -Path $receiptPath)
    pointer=$pointer
    pointer_status=$suppliedPointerStatus
    outcome=$outcome
    capsule=$capsule
    destination_paths=$paths
    files=@($canonicalFiles.Values | Sort-Object)
  }
}

function Import-MIRAssuranceWorkerEvidence {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$WorkerRoot,
    [Parameter(Mandatory)][string]$ArtifactPrefix
  )

  if ($ArtifactPrefix -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Worker artifact prefix contains unsafe characters: $ArtifactPrefix"
  }
  $resolvedWorkerRoot = Resolve-MIRAssurancePath -Path $WorkerRoot
  $repoBoundary = [IO.Path]::GetFullPath($repo).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
  if (-not ([IO.Path]::GetFullPath($resolvedWorkerRoot).StartsWith($repoBoundary, [StringComparison]::OrdinalIgnoreCase))) {
    throw "Worker evidence root must stay inside the repository workspace: $resolvedWorkerRoot"
  }
  $work = @($Plan.work | Sort-Object test_id)
  if ($work.Count -eq 0) {
    return [ordered]@{schema=2;status="passed";worker_root=(Get-MIRAssuranceRepoRelativePath -Path $resolvedWorkerRoot);imported=@();failed=@();missing=@();rejected=@();duplicates=@();ignored=@()}
  }
  if (-not (Test-Path -LiteralPath $resolvedWorkerRoot -PathType Container)) {
    return [ordered]@{
      schema=2
      status="failed"
      worker_root=(Get-MIRAssuranceRepoRelativePath -Path $resolvedWorkerRoot)
      imported=@()
      failed=@()
      missing=@($work | ForEach-Object { [string]$_.test_id })
      rejected=@()
      duplicates=@()
      ignored=@()
    }
  }

  $limits = $Context.config.worker_import
  if ([int]$limits.max_artifacts -le 0) { throw "Worker-import limit 'max_artifacts' must be positive." }
  $artifactDirectories = @(Get-ChildItem -LiteralPath $resolvedWorkerRoot -Directory -Force | Sort-Object Name)
  if ($artifactDirectories.Count -gt [int]$limits.max_artifacts) {
    throw "Worker evidence root exceeds the artifact-count limit."
  }
  $artifactNameKeys = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  foreach ($directory in $artifactDirectories) {
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Worker evidence root contains a symlink or reparse-point artifact: $($directory.Name)"
    }
    $canonicalName = Get-MIRAssuranceWorkerCanonicalPath -Path $directory.Name
    if ($artifactNameKeys.ContainsKey([string]$canonicalName.key)) {
      throw "Worker evidence root contains a case-fold or Unicode-normalization artifact collision."
    }
    $artifactNameKeys[[string]$canonicalName.key] = [string]$directory.Name
  }
  $safeIdGroups = @($work | Group-Object safe_test_id | Where-Object Count -gt 1)
  if ($safeIdGroups.Count -gt 0) {
    throw "Verification plan contains ambiguous worker safe IDs: $($safeIdGroups.Name -join ', ')"
  }

  $expectedRows = @{}
  $candidates = @{}
  $preRejected = @{}
  foreach ($row in $work) {
    $expectedRows[[string]$row.test_id] = $row
    $candidates[[string]$row.test_id] = [Collections.Generic.List[object]]::new()
    $preRejected[[string]$row.test_id] = [Collections.Generic.List[string]]::new()
  }
  $ignored = [Collections.Generic.List[object]]::new()
  foreach ($directory in $artifactDirectories) {
    if (-not $directory.Name.StartsWith($ArtifactPrefix, [StringComparison]::Ordinal)) {
      $ignored.Add([ordered]@{artifact=$directory.Name;reason="prefix-mismatch"})
      continue
    }
    $receiptPath = Join-Path $directory.FullName "worker-receipts\$([string]$Plan.plan_material_sha256).json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
      $matchedExpected = @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" })
      if ($matchedExpected.Count -eq 1) {
        $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): missing current-plan receipt")
      } else {
        $ignored.Add([ordered]@{artifact=$directory.Name;reason="irrelevant-or-stale-receipt"})
      }
      continue
    }
    try { $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json }
    catch {
      $matchedExpected = @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" })
      if ($matchedExpected.Count -eq 1) { $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): invalid receipt JSON") }
      else { $ignored.Add([ordered]@{artifact=$directory.Name;reason="invalid irrelevant receipt"}) }
      continue
    }
    $receiptTestId = [string]$receipt.work.test_id
    if ([string]$receipt.schema -ne "mir-assurance-worker-receipt-v3" -or
        [string]$receipt.plan.material_sha256 -ne [string]$Plan.plan_material_sha256 -or
        -not $expectedRows.ContainsKey($receiptTestId)) {
      $matchedExpected = @($work | Where-Object { $directory.Name -eq "$ArtifactPrefix$([string]$_.safe_test_id)" })
      if ($matchedExpected.Count -eq 1) { $preRejected[[string]$matchedExpected[0].test_id].Add("$($directory.Name): receipt does not bind the active plan row") }
      else { $ignored.Add([ordered]@{artifact=$directory.Name;reason="irrelevant-plan-or-row"}) }
      continue
    }
    $candidates[$receiptTestId].Add($directory)
  }

  $imported = @()
  $failed = @()
  $missing = [Collections.Generic.List[string]]::new()
  $rejected = [Collections.Generic.List[object]]::new()
  $duplicates = [Collections.Generic.List[object]]::new()
  foreach ($row in $work) {
    $tests = @($Plan.tests | Where-Object { [string]$_.id -eq [string]$row.test_id })
    if ($tests.Count -ne 1) { throw "Worker row '$([string]$row.test_id)' does not select exactly one planned test." }
    $test = $tests[0]
    $expectedSafeId = ([string]$test.id) -replace '[^A-Za-z0-9._-]', '_'
    if ([string]$row.safe_test_id -ne $expectedSafeId -or
        [string]$test.safe_test_id -ne $expectedSafeId -or
        [string]$row.fingerprint -ne [string]$test.fingerprint.fingerprint_sha256 -or
        [string]$test.fingerprint.input_key -ne [string]$row.fingerprint) {
      throw "Worker row '$([string]$row.test_id)' does not match its planned safe ID and fingerprint."
    }

    $rowCandidates = @($candidates[[string]$test.id])
    if ($rowCandidates.Count -eq 0) {
      if ($preRejected[[string]$test.id].Count -gt 0) {
        $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($preRejected[[string]$test.id])})
      } else {
        $missing.Add([string]$test.id)
      }
      continue
    }
    if ($rowCandidates.Count -gt 1) {
      $duplicates.Add([ordered]@{test_id=[string]$test.id;artifacts=@($rowCandidates.Name | Sort-Object)})
      continue
    }
    $resolvedArtifactRoot = [IO.Path]::GetFullPath([string]$rowCandidates[0].FullName)
    $workerBoundary = [IO.Path]::GetFullPath($resolvedWorkerRoot).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedArtifactRoot.StartsWith($workerBoundary, [StringComparison]::OrdinalIgnoreCase)) {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@("artifact path escaped worker root")})
      continue
    }
    try {
      $tree = Assert-MIRAssuranceWorkerArtifactTree -ArtifactRoot $resolvedArtifactRoot -Context $Context
      $workerObject = Read-MIRAssuranceWorkerObject -SourceRoot $resolvedArtifactRoot -Plan $Plan -Test $test -Context $Context
    } catch {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($_.Exception.Message)})
      continue
    }

    try {
      foreach ($relativePath in @($workerObject.files)) {
        $source = Resolve-MIRAssuranceWorkerObjectPath -SourceRoot $resolvedArtifactRoot -DestinationRoot $workerObject.destination_paths.root -RepoRelativePath $relativePath
        $destination = Resolve-MIRAssurancePath -Path $relativePath
        $resolvedDestination = [IO.Path]::GetFullPath($destination)
        $destinationBoundary = [IO.Path]::GetFullPath($workerObject.destination_paths.root).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedDestination.StartsWith($destinationBoundary, [StringComparison]::OrdinalIgnoreCase)) {
          throw "Refusing to import worker evidence outside its planned fingerprint subtree: $relativePath"
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
        if (Test-Path -LiteralPath $resolvedDestination -PathType Leaf) {
          if ((Get-MIRAssuranceSha256 -Path $source) -ne (Get-MIRAssuranceSha256 -Path $resolvedDestination)) {
            throw "Refusing to overwrite a different immutable worker object: $relativePath"
          }
        } else {
          Copy-Item -LiteralPath $source -Destination $resolvedDestination
        }
      }
      if (Test-Path -LiteralPath $workerObject.destination_paths.running -PathType Leaf) {
        Remove-Item -LiteralPath $workerObject.destination_paths.running -Force
      }
      if ([string]$workerObject.outcome -eq "passed") {
        if (Test-Path -LiteralPath $workerObject.destination_paths.blocked -PathType Leaf) {
          Remove-Item -LiteralPath $workerObject.destination_paths.blocked -Force
        }
        Write-MIRAssuranceAtomicJson -Value $workerObject.pointer -Path $workerObject.destination_paths.passed
        $validation = Test-MIRAssuranceCapsule -Capsule $workerObject.capsule -Fingerprint $test.fingerprint -Context $Context
        if (-not [bool]$validation.valid) {
          Remove-Item -LiteralPath $workerObject.destination_paths.passed -Force
          throw "Imported worker evidence failed canonical validation: $([string]$validation.reason)"
        }
      } else {
        Write-MIRAssuranceAtomicJson -Value $workerObject.pointer -Path $workerObject.destination_paths.blocked
      }
    } catch {
      $rejected.Add([ordered]@{test_id=[string]$test.id;reasons=@($_.Exception.Message)})
      continue
    }
    $record = [ordered]@{
      test_id=[string]$test.id
      input_key=[string]$test.fingerprint.input_key
      outcome=[string]$workerObject.outcome
      result_digest=[string]$workerObject.capsule.result_digest
      capsule_sha256=[string]$workerObject.pointer.capsule_sha256
      receipt_sha256=[string]$workerObject.receipt_sha256
      pointer_status=[string]$workerObject.pointer_status
      artifact=[string]$rowCandidates[0].Name
      entries=[int]$tree.entries
      expanded_bytes=[long]$tree.expanded_bytes
    }
    if ([string]$workerObject.outcome -eq "passed") { $imported += $record }
    else { $failed += $record }
  }
  $passed = $failed.Count -eq 0 -and $missing.Count -eq 0 -and $rejected.Count -eq 0 -and $duplicates.Count -eq 0
  return [ordered]@{
    schema=2
    status=if ($passed) { "passed" } else { "failed" }
    worker_root=(Get-MIRAssuranceRepoRelativePath -Path $resolvedWorkerRoot)
    imported=@($imported | Sort-Object test_id)
    failed=@($failed | Sort-Object test_id)
    missing=@($missing | Sort-Object)
    rejected=@($rejected | Sort-Object test_id)
    duplicates=@($duplicates | Sort-Object test_id)
    ignored=@($ignored | Sort-Object artifact)
  }
}

function ConvertTo-MIRAssuranceOrderedMap {
  param([Parameter(Mandatory)]$Object)
  $map = [ordered]@{}
  if ($Object -is [System.Collections.IDictionary]) {
    foreach ($key in $Object.Keys) { $map[[string]$key] = $Object[$key] }
  } else {
    foreach ($property in $Object.PSObject.Properties) { $map[$property.Name] = $property.Value }
  }
  return $map
}

function Get-MIRAssuranceReusableEvidence {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.passed -PathType Leaf)) { return $null }
  if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) { return $null }
  $capsule = Read-MIRAssuranceEvidencePointer -Path $paths.passed
  if ($null -eq $capsule) { return $null }
  $validation = Test-MIRAssuranceCapsule -Capsule $capsule -Fingerprint $Fingerprint -Context $Context
  if (-not [bool]$validation.valid) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $capsule
  $result.disposition = "REUSE"
  $result.decision_reason = [string]$validation.reason
  $result.reused_at = (Get-Date).ToUniversalTime().ToString("o")
  $result.source_duration_seconds = [double]$capsule.duration_seconds
  $result.duration_seconds = 0
  $result.evidence_path = Get-MIRAssuranceRepoRelativePath -Path $paths.passed
  return $result
}

function Get-MIRAssuranceCampaignCheckpoint {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  if (-not [bool]$Test.force_fresh) { return $null }
  $checkpoint = Get-MIRAssuranceReusableEvidence -Fingerprint $Test.fingerprint -Context $Context
  if ($null -eq $checkpoint -or -not (Test-MIRAssuranceFreshCampaignEvidence -Capsule $checkpoint -Test $Test -Plan $Plan)) {
    return $null
  }
  $checkpoint.disposition = "CHECKPOINT"
  $checkpoint.decision_reason = "exact-plan-owned-fresh-checkpoint"
  $checkpoint.checkpointed_at = (Get-Date).ToUniversalTime().ToString("o")
  return $checkpoint
}

function Get-MIRAssuranceRunningEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    $Context = $null
  )
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (-not (Test-Path -LiteralPath $paths.running -PathType Leaf)) { return $null }
  try { $running = Get-Content -Raw -LiteralPath $paths.running | ConvertFrom-Json }
  catch {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ([int]$running.schema -ne 2 -or
      [string]$running.test_id -ne [string]$Fingerprint.test_id -or
      [string]$running.input_key -ne [string]$Fingerprint.input_key -or
      [string]$running.fingerprint_sha256 -ne [string]$Fingerprint.fingerprint_sha256) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ($null -ne $Context -and -not (Test-MIRAssuranceTrustedProducer -Producer $running.producer -Context $Context)) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  try { $expires = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.expires_at }
  catch {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  if ($expires -le [DateTimeOffset]::UtcNow) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }

  $hostIdentity = [string]$running.host_identity
  if ([string]::IsNullOrWhiteSpace($hostIdentity)) {
    Remove-Item -LiteralPath $paths.running -Force
    return $null
  }
  switch ([string]$running.lease_scope) {
    "process" {
      if ($hostIdentity -ne (Get-MIRAssuranceHostIdentity) -or [int]$running.process_id -le 0) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      try { $expectedProcessStart = ConvertTo-MIRAssuranceDateTimeOffset -Value $running.process_started_at }
      catch {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      $process = Get-Process -Id ([int]$running.process_id) -ErrorAction SilentlyContinue
      if ($null -eq $process) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      $actualProcessStart = [DateTimeOffset]$process.StartTime.ToUniversalTime()
      if ($actualProcessStart.UtcTicks -ne $expectedProcessStart.UtcTicks) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
    }
    "ci-job" {
      $runId = [string]$running.workflow_run_id
      $runAttempt = [string]$running.workflow_run_attempt
      $job = [string]$running.workflow_job
      if ([string]::IsNullOrWhiteSpace($runId) -or
          [string]::IsNullOrWhiteSpace($runAttempt) -or
          [string]::IsNullOrWhiteSpace($job) -or
          $runId -ne [string]$running.producer.run_id -or
          $runAttempt -ne [string]$running.producer.run_attempt -or
          $job -ne [string]$running.producer.job) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
      $currentProducer = Get-MIRAssuranceProducer
      $sameJob = $runId -eq [string]$currentProducer.run_id -and
        $runAttempt -eq [string]$currentProducer.run_attempt -and
        $job -eq [string]$currentProducer.job
      if ($sameJob -and $hostIdentity -ne (Get-MIRAssuranceHostIdentity)) {
        Remove-Item -LiteralPath $paths.running -Force
        return $null
      }
    }
    default {
      Remove-Item -LiteralPath $paths.running -Force
      return $null
    }
  }
  return $running
}

function Get-MIRAssuranceEvidenceDecision {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$TestId
  )
  $inputMap = if ($null -eq $Fingerprint.inputs) {
    [ordered]@{}
  } else {
    ConvertTo-MIRAssuranceOrderedMap -Object $Fingerprint.inputs
  }
  $missingInputs = @(
    foreach ($inputName in @($inputMap.Keys | Sort-Object)) {
      $inputValue = $inputMap[$inputName]
      if ($null -ne $inputValue -and [string]$inputValue.state -eq "missing") {
        [string]$inputName
      }
    }
  )
  if ($missingInputs.Count -gt 0) {
    return [ordered]@{disposition="INVALID"; reason="required-input-missing:$($missingInputs -join ',')"}
  }
  if (@($Context.rerun_tests | Where-Object { $_ -eq $TestId }).Count -gt 0) {
    return [ordered]@{disposition="RUN"; reason="explicit-rerun"}
  }
  if (-not [bool]$Context.reuse_enabled) {
    return [ordered]@{disposition="RUN"; reason="reuse-disabled"}
  }
  if (Test-MIRAssuranceCanReuseTest -TestId $TestId -Context $Context) {
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $reused) {
      return [ordered]@{disposition="REUSE"; reason="exact-trusted-pass"; evidence=$reused}
    }
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $running) {
      return [ordered]@{disposition="WAIT"; reason="matching-worker-in-progress"; running=$running}
    }
  }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if ((Test-Path -LiteralPath $paths.passed -PathType Leaf) -or (Test-Path -LiteralPath $paths.blocked -PathType Leaf)) {
    return [ordered]@{disposition="INVALID"; reason="stored-evidence-is-not-a-trusted-exact-pass"}
  }
  return [ordered]@{disposition="RUN"; reason="no-exact-evidence"}
}

function Write-MIRAssuranceRunningEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    $Plan = $null,
    $Test = $null
  )
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  $ttl = [int]$Context.verification_profile.running_evidence_ttl_minutes
  if ($ttl -le 0) { $ttl = 360 }
  $producer = Get-MIRAssuranceProducer
  $leaseScope = if ($env:GITHUB_ACTIONS) { "ci-job" } else { "process" }
  $running = [ordered]@{
    schema=2
    test_id=[string]$Fingerprint.test_id
    input_key=[string]$Fingerprint.input_key
    fingerprint_sha256=[string]$Fingerprint.fingerprint_sha256
    target=[string]$Fingerprint.target
    producer=$producer
    lease_scope=$leaseScope
    host_identity=(Get-MIRAssuranceHostIdentity)
    process_id=$PID
    process_started_at=(Get-MIRAssuranceProcessStartedAt)
    workflow_run_id=[string]$producer.run_id
    workflow_run_attempt=[string]$producer.run_attempt
    workflow_job=[string]$producer.job
    started_at=[DateTimeOffset]::UtcNow.ToString("o")
    expires_at=[DateTimeOffset]::UtcNow.AddMinutes($ttl).ToString("o")
  }
  if ($null -ne $Plan -and $null -ne $Test -and [bool]$Test.force_fresh) {
    $running["campaign_id"] = [string]$Test.required_campaign_id
    $running["campaign_plan_material_sha256"] = [string]$Test.required_campaign_plan_material_sha256
  }
  Write-MIRAssuranceAtomicJson -Value $running -Path $paths.running
  return $running
}

function Remove-MIRAssuranceRunningEvidence {
  param([Parameter(Mandatory)]$Fingerprint)
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Fingerprint.test_id -InputKey $Fingerprint.input_key
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
}

function Write-MIRAssuranceAttempt {
  param([Parameter(Mandatory)]$Capsule)
  if (-not $Capsule.Contains("conclusion")) { $Capsule["conclusion"] = [string]$Capsule.status }
  if (-not $Capsule.Contains("producer")) { $Capsule["producer"] = Get-MIRAssuranceProducer }
  $roundTripped = ($Capsule | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json
  $Capsule["result_digest"] = Get-MIRAssuranceCapsuleDigest -Capsule $roundTripped
  $paths = Get-MIRAssuranceEvidencePaths -TestId $Capsule.test_id -InputKey $Capsule.input_key
  New-Item -ItemType Directory -Force -Path $paths.attempts | Out-Null
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffffffZ")
  $attemptPath = Join-Path $paths.attempts ("$stamp-$([guid]::NewGuid().ToString('N')).json")
  $Capsule["attempt_path"] = Get-MIRAssuranceRepoRelativePath -Path $attemptPath
  Write-MIRAssuranceAtomicJson -Value $Capsule -Path $attemptPath
  $pointer = [ordered]@{
    schema=1
    test_id=[string]$Capsule.test_id
    input_key=[string]$Capsule.input_key
    conclusion=[string]$Capsule.conclusion
    capsule_path=(Get-MIRAssuranceRepoRelativePath -Path $attemptPath)
    capsule_sha256=(Get-MIRAssuranceSha256 -Path $attemptPath)
  }
  New-Item -ItemType Directory -Force -Path $paths.root | Out-Null
  if ([string]$Capsule.status -eq "passed") {
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.passed
    if (Test-Path -LiteralPath $paths.blocked) { Remove-Item -LiteralPath $paths.blocked -Force }
  } else {
    Write-MIRAssuranceAtomicJson -Value $pointer -Path $paths.blocked
  }
  if (Test-Path -LiteralPath $paths.running -PathType Leaf) { Remove-Item -LiteralPath $paths.running -Force }
  return $Capsule
}

function Quote-MIRAssuranceCommandArgument {
  param([Parameter(Mandatory)][string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-MIRAssuranceCommandText {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan,
    [string]$TestOutput = ""
  )
  $approvedDeltaPath = if ($Command.Contains("<approved-delta-path>")) {
    Resolve-MIRAssuranceApprovedDeltaPath -VerificationProfile $Context.verification_profile
  } else { "" }
  $values = [ordered]@{
    "<factorio>"=[string]$Context.factorio
    "<candidate>"=[string]$Context.candidate
    "<prior-release>"=[string]$Context.prior_release
    "<mods>"=[string]$Context.mods
    "<baseline>"=[string]$Plan.baseline
    "<seal>"=[string]$Context.seal
    "<target>"=[string]$Context.target
    "<upgrade-from>"=[string]$Context.verification_profile.upgrade.from_version
    "<upgrade-to>"=[string]$Context.verification_profile.upgrade.to_version
    "<upgrade-fixture>"=[string]$Context.verification_profile.upgrade.fixture
    "<approved-delta-path>"=[string]$approvedDeltaPath
    "<source-commit>"=[string]$Plan.source_commit
    "<package-source-commit>"=[string]$Plan.package_source_commit
    "<qualification-factorio-version>"=[string]$Context.verification_profile.qualification_factorio_version
    "<test-output>"=[string]$TestOutput
  }
  $resolved = $Command
  foreach ($entry in $values.GetEnumerator()) {
    if ($resolved.Contains([string]$entry.Key)) {
      if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { throw "Command requires $($entry.Key), but no matching option was supplied." }
      $resolved = $resolved.Replace([string]$entry.Key, (Quote-MIRAssuranceCommandArgument -Value ([string]$entry.Value)))
    }
  }
  if ($resolved -match '<[^>]+>') { throw "Unresolved assurance command placeholder: $resolved" }
  return $resolved
}

function Invoke-MIRAssuranceCommandText {
  param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)][string]$StdoutPath,
    [Parameter(Mandatory)][string]$StderrPath,
    [string]$TestOutput = ""
  )
  $resolved = Resolve-MIRAssuranceCommandText -Command $Command -Context $Context -Plan $Plan -TestOutput $TestOutput
  $tokens = [Management.Automation.PSParser]::Tokenize($resolved, [ref]$null) | Where-Object { $_.Type -notin @("Comment", "NewLine") }
  if ($tokens.Count -eq 0) { throw "Empty assurance command." }
  $commandPath = [string]$tokens[0].Content
  if ($commandPath.StartsWith("./")) { $commandPath = Join-Path $repo $commandPath.Substring(2) }
  $argumentTokens = @($tokens | Select-Object -Skip 1)
  $global:LASTEXITCODE = 0
  $exitCode = 0
  $thrownMessage = ""
  if ([IO.Path]::GetFileName($commandPath) -eq "mir.ps1") {
    $arguments = @($argumentTokens | ForEach-Object { [string]$_.Content })
    try { & $commandPath @arguments 1> $StdoutPath 2> $StderrPath 3>&1 4>&1 5>&1 6>&1 }
    catch { $exitCode = 1; $thrownMessage = $_.Exception.Message }
  } else {
    $named = @{}
    $positional = @()
    for ($i = 0; $i -lt $argumentTokens.Count; $i++) {
      $token = $argumentTokens[$i]
      if ($token.Type -eq [Management.Automation.PSTokenType]::CommandParameter) {
        $name = ([string]$token.Content).TrimStart("-")
        $value = $true
        if ($i + 1 -lt $argumentTokens.Count -and $argumentTokens[$i + 1].Type -ne [Management.Automation.PSTokenType]::CommandParameter) {
          $i++
          $value = [string]$argumentTokens[$i].Content
        }
        $named[$name] = $value
      } else {
        $positional += [string]$token.Content
      }
    }
    try { & $commandPath @named @positional 1> $StdoutPath 2> $StderrPath 3>&1 4>&1 5>&1 6>&1 }
    catch { $exitCode = 1; $thrownMessage = $_.Exception.Message }
  }
  if ($exitCode -eq 0 -and $LASTEXITCODE -ne 0) { $exitCode = [int]$LASTEXITCODE }
  if ($thrownMessage) {
    [IO.File]::AppendAllText($StderrPath, $thrownMessage + "`n", [Text.UTF8Encoding]::new($false))
  }
  if (Test-Path -LiteralPath $StdoutPath -PathType Leaf) {
    Get-Content -LiteralPath $StdoutPath | ForEach-Object { Write-Host $_ }
  }
  if (Test-Path -LiteralPath $StderrPath -PathType Leaf) {
    Get-Content -LiteralPath $StderrPath | ForEach-Object { Write-Warning $_ }
  }
  return [ordered]@{
    resolved_command=$resolved
    exit_code=$exitCode
    thrown_message=$thrownMessage
  }
}

function Test-MIRAssuranceCanReuseTest {
  param([Parameter(Mandatory)][string]$TestId, [Parameter(Mandatory)]$Context)
  if (-not [bool]$Context.reuse_enabled) { return $false }
  if (@($Context.rerun_tests | Where-Object { $_ -eq $TestId }).Count -gt 0) { return $false }
  return $true
}

function Add-MIRAssurancePlanDecisions {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $decorated = @()
  $work = @()
  foreach ($testValue in @($Plan.tests)) {
    $test = ConvertTo-MIRAssuranceOrderedMap -Object $testValue
    if (-not $test.Contains("safe_test_id") -or [string]::IsNullOrWhiteSpace([string]$test.safe_test_id)) {
      $test["safe_test_id"] = ([string]$test.id -replace '[^A-Za-z0-9._-]', '_')
    }
    if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($test.id) start" }
    $fingerprint = Get-MIRAssuranceTestFingerprint -Test $test -Plan $Plan -Context $Context
    if ($env:MIR_ASSURANCE_TIMING) { Write-Host "[assurance-timing] fingerprint $($test.id) done" }
    $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId ([string]$test.id)
    $test["fingerprint"] = $fingerprint
    $test["disposition"] = [string]$decision.disposition
    $test["decision_reason"] = [string]$decision.reason
    $decorated += [pscustomobject]$test
    if ([string]$decision.disposition -ne "REUSE") {
      $work += [pscustomobject][ordered]@{
        test_id=[string]$test.id
        safe_test_id=[string]$test.safe_test_id
        fingerprint=[string]$fingerprint.fingerprint_sha256
        disposition=[string]$decision.disposition
        layer=[string]$test.layer
      }
    }
  }
  $Plan.tests = @($decorated)
  $Plan["work"] = @($work)
  $Plan["counts"] = [ordered]@{
    total=$decorated.Count
    reuse=@($decorated | Where-Object disposition -eq "REUSE").Count
    wait=@($decorated | Where-Object disposition -eq "WAIT").Count
    run=@($decorated | Where-Object disposition -eq "RUN").Count
    invalid=@($decorated | Where-Object disposition -eq "INVALID").Count
  }
  return $Plan
}

function Get-MIRAssurancePlanMaterial {
  param([Parameter(Mandatory)]$Plan)
  $tests = @(
    foreach ($test in @($Plan.tests | Sort-Object id)) {
      [ordered]@{
        id=[string]$test.id
        layer=[string]$test.layer
        definition_sha256=[string]$test.fingerprint.definition_sha256
        fingerprint_sha256=[string]$test.fingerprint.fingerprint_sha256
      }
    }
  )
  return [ordered]@{
    schema=4
    policy_id=[string]$Plan.policy_id
    target=[string]$Plan.target
    profile=[string]$Plan.profile
    baseline=[string]$Plan.baseline
    source_commit=[string]$Plan.source_commit
    source_tree=[string]$Plan.source_tree
    candidate_descriptor_sha256=[string]$Plan.candidate_descriptor.descriptor_sha256
    package_source_sha256=[string]$Plan.package_source_sha256
    digest_policy_ids=[ordered]@{
      text=[string]$Plan.digest_policy_ids.text
      json=[string]$Plan.digest_policy_ids.json
    }
    catalog_sha256=[string]$Plan.test_catalog_sha256
    validation_harness_sha256=[string]$Plan.validation_harness_sha256
    verification_profile_sha256=[string]$Plan.verification_profile_sha256
    domain_policy_sha256=[string]$Plan.domain_policy_sha256
    trust_policy_sha256=[string]$Plan.trust_policy_sha256
    expected_test_ids=@($Plan.expected_test_ids | ForEach-Object { [string]$_ })
    required_test_set_sha256=[string]$Plan.required_test_set_sha256
    reuse_enabled=[bool]$Plan.reuse_enabled
    rerun_tests=@($Plan.rerun_tests | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    tests=$tests
  }
}

function Complete-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $expectedIds = @($Plan.tests | ForEach-Object { [string]$_.id } | Sort-Object)
  $duplicates = @($expectedIds | Group-Object | Where-Object Count -gt 1)
  if ($duplicates.Count -gt 0) { throw "Verification plan contains duplicate tests: $($duplicates.Name -join ', ')" }
  if ($expectedIds.Count -eq 0) { throw "Verification plan cannot be empty." }
  $Plan["expected_test_ids"] = $expectedIds
  $Plan["required_test_set_sha256"] = Get-MIRAssuranceJsonHash -Value $expectedIds
  $Plan["catalog_sha256"] = [string]$Plan.test_catalog_sha256
  $Plan["policy_sha256"] = Get-MIRAssuranceJsonHash -Value ([ordered]@{
    assurance=(Get-MIRAssuranceCanonicalJsonFileHash -Path $configPath)
    domains=[string]$Plan.domain_policy_sha256
    profile=[string]$Plan.verification_profile_sha256
    trust=[string]$Plan.trust_policy_sha256
  })
  $Plan["candidate_descriptor_sha256"] = [string]$Plan.candidate_descriptor.descriptor_sha256
  $producer = $Plan.producer
  if ($null -eq $producer) {
    $producer = Get-MIRAssuranceProducer
    $Plan["producer"] = $producer
  }
  # Plan material deliberately excludes execution time and host identity.  It
  # is therefore a stable campaign namespace for this exact source, candidate,
  # policy and test set.  minimum_completed_at still prevents a later fresh
  # campaign from adopting an older result with the same inputs.
  $Plan["plan_material_sha256"] = Get-MIRAssuranceJsonHash -Value (Get-MIRAssurancePlanMaterial -Plan $Plan)
  $Plan["campaign"] = [ordered]@{
    schema="mir-assurance-campaign-v1"
    id="plan-$(([string]$Plan.plan_material_sha256).ToLowerInvariant())"
    plan_material_sha256=[string]$Plan.plan_material_sha256
    created_at=[string]$Plan.generated_at
  }
  foreach ($test in @($Plan.tests)) {
    $forceFresh = (-not [bool]$Plan.reuse_enabled) -or @($Plan.rerun_tests | Where-Object { [string]$_ -eq [string]$test.id }).Count -gt 0
    $test | Add-Member -NotePropertyName force_fresh -NotePropertyValue $forceFresh -Force
    if ($forceFresh) {
      $test | Add-Member -NotePropertyName minimum_completed_at -NotePropertyValue ([string]$Plan.generated_at) -Force
      $test | Add-Member -NotePropertyName required_campaign_id -NotePropertyValue ([string]$Plan.campaign.id) -Force
      $test | Add-Member -NotePropertyName required_campaign_plan_material_sha256 -NotePropertyValue ([string]$Plan.plan_material_sha256) -Force
    }
  }
  return $Plan
}

function Get-MIRAssuranceReconstructionArgs {
  param([Parameter(Mandatory)]$Plan)
  $filtered = @()
  $takesValue = @("--plan", "--profile", "--baseline", "--rerun", "--target", "--candidate", "--factorio", "--prior", "--seal", "--mods", "--output", "--test", "--fingerprint")
  for ($i = 0; $i -lt $script:Args.Count; $i++) {
    $arg = [string]$script:Args[$i]
    if ($takesValue -contains $arg) { $i++; continue }
    if ($arg -eq "--no-reuse") { continue }
    $filtered += $arg
  }
  $filtered += @("--profile", [string]$Plan.profile)
  if (-not [string]::IsNullOrWhiteSpace([string]$Plan.baseline)) { $filtered += @("--baseline", [string]$Plan.baseline) }
  foreach ($testId in @($Plan.rerun_tests)) { $filtered += @("--rerun", [string]$testId) }
  if (-not [bool]$Plan.reuse_enabled) { $filtered += "--no-reuse" }
  return @($filtered)
}

function Assert-MIRAssurancePlanFreshnessBinding {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  if ($null -eq $Plan.campaign -or
      [string]$Plan.campaign.schema -ne "mir-assurance-campaign-v1" -or
      [string]$Plan.campaign.id -ne "plan-$(([string]$Plan.plan_material_sha256).ToLowerInvariant())" -or
      [string]$Plan.campaign.plan_material_sha256 -ne [string]$Plan.plan_material_sha256 -or
      [string]$Plan.campaign.created_at -ne [string]$Plan.generated_at) {
    throw "Verification plan campaign identity is missing or was altered."
  }
  if (-not (Test-MIRAssurancePlanContinuationProducer -Producer $Plan.producer -Context $Context -SourceCommit ([string]$Plan.source_commit))) {
    throw "Verification plan producer is not an authorized continuation of the plan source and trust context."
  }
  foreach ($test in @($Plan.tests)) {
    $forceFresh = (-not [bool]$Plan.reuse_enabled) -or
      @($Plan.rerun_tests | Where-Object { [string]$_ -eq [string]$test.id }).Count -gt 0
    if ([bool]$test.force_fresh -ne $forceFresh) {
      throw "Verification plan freshness policy was altered for '$([string]$test.id)'."
    }
    if ($forceFresh) {
      if ([string]$test.minimum_completed_at -ne [string]$Plan.generated_at -or
          [string]$test.required_campaign_id -ne [string]$Plan.campaign.id -or
          [string]$test.required_campaign_plan_material_sha256 -ne [string]$Plan.plan_material_sha256) {
        throw "Verification plan fresh-evidence binding was altered for '$([string]$test.id)'."
      }
    }
  }
  return $Plan
}

function Assert-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  if ([int]$Plan.schema -ne 4) { throw "Verification plan schema must be 4." }
  if ([string]$Plan.target -ne [string]$Context.target) { throw "Verification plan target does not match --target." }
  if ([string]::IsNullOrWhiteSpace([string]$Plan.profile)) { throw "Verification plan profile is missing." }
  $ids = @($Plan.tests | ForEach-Object { [string]$_.id })
  if ($ids.Count -eq 0) { throw "Verification plan cannot be empty." }
  $duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
  if ($duplicates.Count -gt 0) { throw "Verification plan contains duplicate tests: $($duplicates.Name -join ', ')" }
  if (@(Compare-Object @($Plan.expected_test_ids | Sort-Object) @($ids | Sort-Object)).Count -gt 0) {
    throw "Verification plan test rows differ from expected_test_ids."
  }
  if ([string]$Plan.required_test_set_sha256 -ne (Get-MIRAssuranceJsonHash -Value @($Plan.expected_test_ids | ForEach-Object { [string]$_ }))) {
    throw "Verification plan required-test-set digest is invalid."
  }
  if ([string]$Plan.plan_material_sha256 -ne (Get-MIRAssuranceJsonHash -Value (Get-MIRAssurancePlanMaterial -Plan $Plan))) {
    throw "Verification plan material digest is invalid."
  }
  $null = Assert-MIRAssurancePlanFreshnessBinding -Plan $Plan -Context $Context

  $originalArgs = @($script:Args)
  $expectedContext = $Context.PSObject.Copy()
  $expectedContext.reuse_enabled = [bool]$Plan.reuse_enabled
  $expectedContext.rerun_tests = @($Plan.rerun_tests | ForEach-Object { [string]$_ })
  try {
    $script:Args = @(Get-MIRAssuranceReconstructionArgs -Plan $Plan)
    $expected = Get-MIRAssurancePlan -Context $expectedContext
  } finally {
    $script:Args = $originalArgs
  }
  if ([string]$expected.plan_material_sha256 -ne [string]$Plan.plan_material_sha256) {
    throw "Verification plan does not match the canonical profile, catalog, inputs, candidate, source, or policy."
  }
  return $Plan
}

function Get-MIRAssurancePlanFromOption {
  param([Parameter(Mandatory)]$Context, [switch]$RequirePlan)
  $planOption = Get-MIRAssuranceOption -Name "--plan"
  if ($planOption) {
    $path = Resolve-MIRAssurancePath -Path $planOption
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Verification plan not found: $path" }
    $plan = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $validatedPlan = Assert-MIRAssurancePlan -Plan $plan -Context $Context
    Sync-MIRAssuranceContextFromPlan -Context $Context -Plan $validatedPlan
    return $validatedPlan
  }
  if ($RequirePlan) { throw "This command requires --plan <verification-plan.json>." }
  return Get-MIRAssurancePlan -Context $Context
}

function Sync-MIRAssuranceContextFromPlan {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$Plan
  )
  $Context.reuse_enabled = [bool]$Plan.reuse_enabled
  $Context.rerun_tests = @($Plan.rerun_tests | ForEach-Object { [string]$_ })
}

function Get-MIRAssurancePlannedTest {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$TestId)
  if ([string]::IsNullOrWhiteSpace($TestId)) { throw "--test <stable-id> is required." }
  $matches = @($Plan.tests | Where-Object { [string]$_.id -eq $TestId })
  if ($matches.Count -ne 1) { throw "Verification plan does not contain exactly one test '$TestId'." }
  return $matches[0]
}

function Wait-MIRAssuranceEvidence {
  param(
    [Parameter(Mandatory)]$Fingerprint,
    [Parameter(Mandatory)]$Context,
    [int]$PollSeconds = 5
  )
  while ($true) {
    $reused = Get-MIRAssuranceReusableEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -ne $reused) { return $reused }
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $Fingerprint -Context $Context
    if ($null -eq $running) { return $null }
    Start-Sleep -Seconds $PollSeconds
  }
}

function Get-MIRAssuranceArtifactDescriptor {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Kind
  )
  $resolved = Resolve-MIRAssurancePath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "Required assurance artifact does not exist: $resolved"
  }
  $item = Get-Item -LiteralPath $resolved
  return [ordered]@{
    kind=$Kind
    path=(Get-MIRAssuranceRepoRelativePath -Path $item.FullName)
    bytes=$item.Length
    sha256=(Get-MIRAssuranceSha256 -Path $item.FullName)
  }
}

function Get-MIRAssuranceScenarioResult {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)][string]$SummaryPath
  )
  if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    throw "Scenario worker did not create its structured validation summary: $SummaryPath"
  }
  try { $summary = Get-Content -Raw -LiteralPath $SummaryPath | ConvertFrom-Json }
  catch { throw "Scenario worker summary is invalid JSON: $SummaryPath" }
  if ([int]$summary.schema -ne 2 -or [string]$summary.status -ne "passed") {
    throw "Scenario worker summary is not a passing schema-2 result."
  }
  $scenarioName = [string]$Test.scenario.name
  $expected = @($summary.expected_scenarios | ForEach-Object { [string]$_ })
  $scenarios = @($summary.scenarios | Where-Object { [string]$_.name -eq $scenarioName })
  if ($expected.Count -ne 1 -or $expected[0] -ne $scenarioName -or $scenarios.Count -ne 1) {
    throw "Scenario worker summary does not contain exactly the planned scenario '$scenarioName'."
  }
  $scenario = $scenarios[0]
  $declaredAssertions = @($Test.scenario.assertions)
  if ([string]$scenario.status -ne "passed" -or
      [int]$scenario.assertions_executed -lt $declaredAssertions.Count -or
      $declaredAssertions.Count -eq 0) {
    throw "Scenario '$scenarioName' did not report all declared assertions as executed and passing."
  }
  $summaryDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $SummaryPath -Kind "validation-summary"
  $assertions = @(
    foreach ($assertion in $declaredAssertions) {
      [ordered]@{
        id=[string]$assertion.id
        status="passed"
        evidence=[string]$summaryDescriptor.path
      }
    }
  )
  return [ordered]@{
    assertions=$assertions
    artifacts=@($summaryDescriptor)
  }
}

function Invoke-MIRAssuranceTest {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context
  )
  New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
  $id = [string]$Test.id
  if ([bool]$Test.requires_factorio -and (-not $Context.factorio -or -not (Test-Path -LiteralPath $Context.factorio -PathType Leaf))) {
    throw "Test $id requires --factorio with a matching Factorio binary."
  }
  if ($id -eq "runtime.upgrade" -and (-not $Context.prior_release -or -not (Test-Path -LiteralPath $Context.prior_release -PathType Leaf))) {
    throw "Test runtime.upgrade requires --prior with the exact prior-release archive."
  }
  if ([bool]$Test.requires_candidate -or @($Test.inputs | Where-Object { [string]$_ -eq "candidate" }).Count -gt 0) {
    if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) {
      throw "Test $id requires the exact candidate archive: $($Context.candidate)"
    }
  }

  $fingerprint = if ($Test.fingerprint) { $Test.fingerprint } else { Get-MIRAssuranceTestFingerprint -Test $Test -Plan $Plan -Context $Context }
  # Fresh campaigns do not reuse arbitrary historical evidence.  They do,
  # however, adopt a cryptographically exact row that was completed for this
  # same immutable campaign before an interruption.  That makes the boundary
  # between process attempts recoverable without weakening the release gate.
  $checkpoint = Get-MIRAssuranceCampaignCheckpoint -Test $Test -Plan $Plan -Context $Context
  if ($null -ne $checkpoint) {
    Write-Host "[CHECKPOINT] $id $($fingerprint.input_key)"
    return $checkpoint
  }
  if ([bool]$Test.force_fresh) {
    $running = Get-MIRAssuranceRunningEvidence -Fingerprint $fingerprint -Context $Context
    if ($null -ne $running) {
      Write-Host "[WAIT] $id $($fingerprint.input_key)"
      $adopted = Wait-MIRAssuranceEvidence -Fingerprint $fingerprint -Context $Context
      if ($null -ne $adopted) {
        $checkpoint = Get-MIRAssuranceCampaignCheckpoint -Test $Test -Plan $Plan -Context $Context
        if ($null -ne $checkpoint) {
          $checkpoint.disposition = "WAIT"
          $checkpoint.decision_reason = "adopted-exact-plan-owned-fresh-checkpoint"
          return $checkpoint
        }
      }
      Write-Host "[RUN] no exact campaign checkpoint after prior worker; continuing $id"
    }
  }
  $decision = Get-MIRAssuranceEvidenceDecision -Fingerprint $fingerprint -Context $Context -TestId $id
  if ([string]$decision.disposition -eq "REUSE") {
    Write-Host "[REUSE] $id $($fingerprint.input_key)"
    return $decision.evidence
  }
  if ([string]$decision.disposition -eq "WAIT") {
    Write-Host "[WAIT] $id $($fingerprint.input_key)"
    $adopted = Wait-MIRAssuranceEvidence -Fingerprint $fingerprint -Context $Context
    if ($null -ne $adopted) {
      $adopted.disposition = "WAIT"
      $adopted.decision_reason = "adopted-matching-worker-result"
      return $adopted
    }
    Write-Host "[RUN] matching worker expired without reusable evidence; adopting $id"
  } else {
    Write-Host "[$($decision.disposition)] $id $($fingerprint.input_key)"
  }

  $evidenceProducer = Get-MIRAssuranceEvidenceProducer -Test $Test -Plan $Plan -Context $Context
  $null = Write-MIRAssuranceRunningEvidence -Fingerprint $fingerprint -Context $Context -Plan $Plan -Test $Test
  $started = Get-Date
  $status = "failed"
  $message = ""
  $resolvedCommand = ""
  $exitCode = 1
  $assertions = @()
  $artifacts = @()
  $paths = Get-MIRAssuranceEvidencePaths -TestId $id -InputKey ([string]$fingerprint.input_key)
  $workRoot = Join-Path $paths.root (Join-Path "work" ([guid]::NewGuid().ToString("N")))
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  $stdoutPath = Join-Path $workRoot "stdout.txt"
  $stderrPath = Join-Path $workRoot "stderr.txt"
  $resultPath = Join-Path $workRoot "result.json"
  $performanceOutputPath = Join-Path $workRoot "performance-regression.json"
  [IO.File]::WriteAllText($stdoutPath, "", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($stderrPath, "", [Text.UTF8Encoding]::new($false))
  try {
    $commandResult = Invoke-MIRAssuranceCommandText `
      -Command ([string]$Test.command) `
      -Context $Context `
      -Plan $Plan `
      -StdoutPath $stdoutPath `
      -StderrPath $stderrPath `
      -TestOutput $performanceOutputPath
    $resolvedCommand = [string]$commandResult.resolved_command
    $exitCode = [int]$commandResult.exit_code
    if ($exitCode -ne 0) {
      throw "Command exited with code $exitCode."
    }
    if ([string]$Test.kind -eq "factorio-scenario") {
      $scenarioSummaryPath = Join-Path $repo "build\results\validation\$([string]$Test.safe_test_id).json"
      $capturedScenarioSummaryPath = Join-Path $workRoot "scenario-summary.json"
      Copy-Item -LiteralPath $scenarioSummaryPath -Destination $capturedScenarioSummaryPath -Force
      $scenarioResult = Get-MIRAssuranceScenarioResult -Test $Test -SummaryPath $capturedScenarioSummaryPath
      $assertions = @($scenarioResult.assertions)
      $artifacts = @($scenarioResult.artifacts)
    } elseif ($id -eq "runtime.performance-regression") {
      $performanceEvidence = Test-MIRRuntimePerformanceEvidence `
        -RepoRoot $repo `
        -Path $performanceOutputPath `
        -Candidate $Context.candidate `
        -PriorRelease $Context.prior_release `
        -FactorioBin $Context.factorio `
        -ExpectedSourceCommit ([string]$Plan.source_commit) `
        -ExpectedBaselineVersion ([string]$Context.verification_profile.upgrade.from_version) `
        -ExpectedFactorioVersion ([string]$Context.verification_profile.qualification_factorio_version) `
        -CampaignPath (Resolve-MIRAssurancePerformanceCampaignPath -Context $Context)
      $performanceDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $performanceEvidence.path -Kind "runtime-performance-evidence"
      $assertions = @(
        [ordered]@{
          id="runtime-performance-evidence-validated"
          status="passed"
          evidence=[string]$performanceDescriptor.path
        }
      )
      $artifacts = @($performanceDescriptor)
    } else {
      $assertions = @(
        [ordered]@{
          id="executor-exit-zero"
          status="passed"
          evidence=(Get-MIRAssuranceRepoRelativePath -Path $stdoutPath)
        }
      )
    }
    $status = "passed"
  } catch {
    $status = "failed"
    $message = $_.Exception.Message
    if ($exitCode -eq 0) { $exitCode = 1 }
    $assertions = @(
      [ordered]@{
        id="executor-exit-zero"
        status="failed"
        evidence=(Get-MIRAssuranceRepoRelativePath -Path $stderrPath)
      }
    )
  }
  $completed = Get-Date
  $duration = [Math]::Round(($completed - $started).TotalSeconds, 3)
  $structuredResult = [ordered]@{
    schema="mir-test-result-v1"
    test_id=$id
    status=$status
    exit_code=$exitCode
    assertions=@($assertions)
    artifacts=@($artifacts)
    started_at=$started.ToUniversalTime().ToString("o")
    completed_at=$completed.ToUniversalTime().ToString("o")
    message=$message
  }
  Write-MIRAssuranceAtomicJson -Value $structuredResult -Path $resultPath
  $resultDescriptor = Get-MIRAssuranceArtifactDescriptor -Path $resultPath -Kind "structured-test-result"
  $resultDescriptor["schema"] = "mir-test-result-v1"
  $resultDescriptor["status"] = $status
  $capsule = [ordered]@{
    schema=$evidenceSchema
    test_id=$id
    status=$status
    conclusion=$status
    disposition="RUN"
    input_key=[string]$fingerprint.input_key
    fingerprint_sha256=[string]$fingerprint.fingerprint_sha256
    definition_sha256=[string]$fingerprint.definition_sha256
    target=[string]$Context.target
    layer=[string]$Test.layer
    command=[string]$Test.command
    resolved_command=$resolvedCommand
    inputs=$fingerprint.inputs
    producer=$evidenceProducer
    assertions=$assertions
    exit_code=$exitCode
    result=$resultDescriptor
    artifacts=@($artifacts)
    stdout_sha256=(Get-MIRAssuranceSha256 -Path $stdoutPath)
    stderr_sha256=(Get-MIRAssuranceSha256 -Path $stderrPath)
    log_digest=(Get-MIRAssuranceTextHash -Text ((Get-Content -Raw -LiteralPath $stdoutPath) + "`n" + (Get-Content -Raw -LiteralPath $stderrPath)))
    started_at=$started.ToUniversalTime().ToString("o")
    completed_at=$completed.ToUniversalTime().ToString("o")
    duration_seconds=$duration
    message=$message
  }
  $capsule = Write-MIRAssuranceAttempt -Capsule $capsule
  if ($status -ne "passed") { throw "Assurance test failed: $id - $message" }
  return $capsule
}

function Invoke-MIRAssurancePlan {
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)]$Context,
    [int]$TimeBudgetSeconds = -1,
    $ExecutionState = $null
  )
  $results = @()
  $startedAt = [DateTimeOffset]::UtcNow
  $deadline = if ($TimeBudgetSeconds -ge 0) { $startedAt.AddSeconds($TimeBudgetSeconds) } else { $null }
  if ($null -ne $ExecutionState) {
    $ExecutionState["status"] = "complete"
    $ExecutionState["started_at"] = $startedAt.ToString("o")
    $ExecutionState["time_budget_seconds"] = $TimeBudgetSeconds
  }
  foreach ($test in @($Plan.tests)) {
    if ($null -ne $deadline -and [DateTimeOffset]::UtcNow -ge $deadline) {
      if ($null -ne $ExecutionState) {
        $ExecutionState["status"] = "checkpointed"
        $ExecutionState["next_test_id"] = [string]$test.id
        $ExecutionState["completed_at"] = [DateTimeOffset]::UtcNow.ToString("o")
      }
      Write-Host "[CHECKPOINT] Time budget reached before '$([string]$test.id)'; completed rows are durable and the same --plan will resume only the remaining rows."
      break
    }
    try {
      $results += Invoke-MIRAssuranceTest -Test $test -Plan $Plan -Context $Context
    } catch {
      $capturedFailure = $false
      $paths = Get-MIRAssuranceEvidencePaths -TestId ([string]$test.id) -InputKey ([string]$test.fingerprint.input_key)
      if (Test-Path -LiteralPath $paths.blocked -PathType Leaf) {
        $blocked = Read-MIRAssuranceEvidencePointer -Path $paths.blocked
        if ($null -ne $blocked) {
          $results += $blocked
          $capturedFailure = $true
        }
      }
      if (-not $capturedFailure) {
        $results += [pscustomobject][ordered]@{
          schema="mir-plan-execution-error-v1"
          test_id=[string]$test.id
          status="failed"
          conclusion="failed"
          disposition="RUN"
          input_key=[string]$test.fingerprint.input_key
          fingerprint_sha256=[string]$test.fingerprint.fingerprint_sha256
          exit_code=1
          message=$_.Exception.Message
          completed_at=(Get-Date).ToUniversalTime().ToString("o")
        }
      }
      break
    }
  }
  if ($null -ne $ExecutionState -and -not $ExecutionState.Contains("completed_at")) {
    $ExecutionState["completed_at"] = [DateTimeOffset]::UtcNow.ToString("o")
  }
  return @($results)
}

function Invoke-MIRAssuranceGate {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  $Plan = Assert-MIRAssurancePlan -Plan $Plan -Context $Context
  $checks = @()
  $evidence = @()
  if ($Plan.domain_manifest) {
    $currentManifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
    if ([string]$currentManifest.manifest_sha256 -ne [string]$Plan.domain_manifest.manifest_sha256) {
      throw "Candidate domain manifest changed after the verification plan was created."
    }
  }
  foreach ($test in @($Plan.tests)) {
    $fingerprint = $test.fingerprint
    $capsule = Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint -Context $Context
    $passed = $null -ne $capsule
    if ($passed -and [bool]$test.force_fresh) {
      if (-not (Test-MIRAssuranceFreshCampaignEvidence -Capsule $capsule -Test $test -Plan $Plan)) { $passed = $false }
    }
    $checks += [ordered]@{
      test_id=[string]$test.id
      fingerprint=[string]$fingerprint.fingerprint_sha256
      status=if ($passed) { "passed" } else { "missing-or-invalid" }
    }
    if ($passed) { $evidence += $capsule }
  }
  $failed = @($checks | Where-Object status -ne "passed")
  $evidenceIds = @($evidence | ForEach-Object { [string]$_.test_id } | Sort-Object)
  $evidenceSetMatches = @(Compare-Object @($Plan.expected_test_ids | Sort-Object) $evidenceIds).Count -eq 0
  $capsuleDigests = @(
    foreach ($capsule in @($evidence | Sort-Object test_id)) {
      [ordered]@{
        test_id=[string]$capsule.test_id
        input_key=[string]$capsule.input_key
        result_digest=[string]$capsule.result_digest
      }
    }
  )
  $bundle = [ordered]@{
    schema=2
    policy_id=[string]$Plan.policy_id
    status=if ($failed.Count -eq 0) { "passed" } else { "failed" }
    target=[string]$Plan.target
    plan_generated_at=[string]$Plan.generated_at
    plan_sha256=(Get-MIRAssuranceJsonHash -Value $Plan)
    plan_material_sha256=[string]$Plan.plan_material_sha256
    required_test_set_sha256=[string]$Plan.required_test_set_sha256
    candidate_descriptor=$Plan.candidate_descriptor
    candidate_descriptor_sha256=[string]$Plan.candidate_descriptor_sha256
    candidate=[string]$Plan.candidate
    domain_manifest=$Plan.domain_manifest
    checks=$checks
    evidence=$evidence
    capsule_set=$capsuleDigests
    capsule_set_sha256=(Get-MIRAssuranceJsonHash -Value $capsuleDigests)
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $bundle["bundle_sha256"] = Get-MIRAssuranceJsonHash -Value $bundle
  $bundlePath = "build/results/assurance/evidence-bundle.json"
  Write-MIRAssuranceJsonFile -Value $bundle -Path $bundlePath | Out-Null
  $requestedOutput = Get-MIRAssuranceOption -Name "--output"
  if ($requestedOutput -and (Resolve-MIRAssurancePath -Path $requestedOutput) -ne (Resolve-MIRAssurancePath -Path $bundlePath)) {
    Write-MIRAssuranceJsonFile -Value $bundle -Path $requestedOutput | Out-Null
  }
  if (Test-MIRAssuranceSwitch -Name "--json") {
    $bundle | ConvertTo-Json -Depth 40 | Write-Output
  }
  if ($failed.Count -gt 0) {
    throw "MIR verification gate is missing trusted exact evidence for $($failed.Count) test(s): $(@($failed.test_id) -join ', ')"
  }
  if (-not $evidenceSetMatches) {
    throw "Evidence bundle test set differs from the canonical verification plan."
  }
  return $bundle
}

function Get-MIRAssuranceBuildFingerprint {
  param([Parameter(Mandatory)]$Context)
  $material = [ordered]@{
    schema=$buildReceiptSchema
    target=[string]$Context.target
    source_tree=(& git -C $repo rev-parse "HEAD^{tree}").Trim()
    package_source_sha256=(Get-MIRAssurancePackageSourceHash)
    build_script_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "tools\commands\package\Build-MIRPackage.ps1"))
    package_identity_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1"))
    info_sha256=(Get-MIRAssuranceRepositoryFileHash -Path (Join-Path $repo "info.json"))
  }
  return [ordered]@{ material=$material; input_key=(Get-MIRAssuranceJsonHash -Value $material) }
}

function Test-MIRAssuranceBuildReceipt {
  param([Parameter(Mandatory)]$Fingerprint, [Parameter(Mandatory)]$Context)
  $path = Join-Path $buildRoot "$($Fingerprint.input_key).json"
  if (-not $Context.reuse_enabled -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { return $null }
  try { $receipt = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json }
  catch { return $null }
  if ([int]$receipt.schema -ne $buildReceiptSchema) { return $null }
  if ([string]$receipt.input_key -ne [string]$Fingerprint.input_key) { return $null }
  if ([string]$receipt.candidate_sha256 -ne (Get-MIRAssuranceSha256 -Path $Context.candidate)) { return $null }
  if ([string]$receipt.candidate_content_sha256 -ne (Get-MIRAssuranceZipContentHash -Path $Context.candidate)) { return $null }
  $result = ConvertTo-MIRAssuranceOrderedMap -Object $receipt
  $result.disposition = "reused"
  $result.receipt = Get-MIRAssuranceRepoRelativePath -Path $path
  return $result
}

function Invoke-MIRAssuranceBuild {
  param([Parameter(Mandatory)]$Context)
  New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
  $fingerprint = Get-MIRAssuranceBuildFingerprint -Context $Context
  $reused = Test-MIRAssuranceBuildReceipt -Fingerprint $fingerprint -Context $Context
  if ($null -ne $reused) {
    Write-Host "[reuse] candidate build $($fingerprint.input_key)"
    return $reused
  }
  Write-Host "[run] candidate build $($fingerprint.input_key)"
  $candidateFullPath = [IO.Path]::GetFullPath([string]$Context.candidate)
  $distRoot = [IO.Path]::GetFullPath((Join-Path $repo "dist"))
  if ($candidateFullPath.StartsWith($distRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Assurance builds may not write through immutable published dist authority: $candidateFullPath"
  }
  $mir4BootstrapCandidate = [IO.Path]::GetFullPath((Join-Path $repo "build\mir4\emergency-lane\distributions\more-infinite-research_4.0.21000.zip"))
  $isMir4BootstrapBuild = $candidateFullPath.Equals($mir4BootstrapCandidate, [StringComparison]::OrdinalIgnoreCase)
  $recordPath = Join-Path $repo ".mir\releases\records\$($Context.info.version).json"
  if (-not $isMir4BootstrapBuild -and (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
    $record = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
    if ([string]$record.state -in @("tagged", "published", "publicly-verified")) {
      $observedSource = Get-MIRAssurancePackageSourceHash
      if ($observedSource -ne [string]$record.package.source_sha256) {
        throw "Refusing to build published version $($Context.info.version) from changed package roots: expected $($record.package.source_sha256), observed $observedSource. Restore the governed published source baseline first."
      }
    }
  }
  if ($isMir4BootstrapBuild) {
    . (Join-Path $repo "tools\lib\mir4\BootstrapMaterialization.ps1")
    $correctionPath = Join-Path $repo ".mir\releases\waves\mir4-r0\MIR4-Approved-Bootstrap-Correction-CompositeV2.json"
    if (-not (Test-Path -LiteralPath $correctionPath -PathType Leaf)) {
      throw "MIR 4 bootstrap assurance build requires the exact approved correction authority."
    }
    $correction = Get-Content -Raw -LiteralPath $correctionPath | ConvertFrom-Json
    if (-not (Test-MIR4BootstrapRecordHash -Record $correction) -or
        [string]$correction.kind -ne "MIR4ApprovedBootstrapCorrectionDeltaV2" -or
        (@($correction.findings | Sort-Object) -join '+') -ne "MIR3-TERM-0032+MIR3-TERM-0033" -or
        [string]$correction.target_key -ne "f210" -or
        [bool]$correction.public_output_authorized -or
        [bool]$correction.authority_scope.release_admission_authorized -or
        [bool]$correction.authority_scope.signing_or_sealing_authorized -or
        [bool]$correction.authority_scope.publication_authorized) {
      throw "MIR 4 bootstrap assurance build correction authority is invalid or release-capable."
    }
    & (Join-Path $repo "tools\commands\release\New-MIR4BootstrapLocalCandidate.ps1") `
      -Target f210 -Lane emergency -OutputRoot (Join-Path $repo "build\mir4\emergency-lane") -Repetitions 3 | Out-Host
  } else {
    $candidateRoot = Split-Path -Parent $candidateFullPath
    $candidateOutputDir = Get-MIRAssuranceRepoRelativePath -Path $candidateRoot
    & (Join-Path $repo "tools\commands\package\Build-MIRPackage.ps1") -OutputDir $candidateOutputDir | Out-Host
  }
  if ($LASTEXITCODE -ne 0) { throw "Candidate build failed." }
  if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { throw "Candidate was not created: $($Context.candidate)" }
  $receipt = [ordered]@{
    schema=$buildReceiptSchema
    status="passed"
    disposition="executed"
    input_key=[string]$fingerprint.input_key
    target=[string]$Context.target
    candidate=(Get-MIRAssuranceRepoRelativePath -Path $Context.candidate)
    candidate_sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    candidate_content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    package_source_sha256=[string]$fingerprint.material.package_source_sha256
    size_bytes=(Get-Item -LiteralPath $Context.candidate).Length
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $path = Join-Path $buildRoot "$($fingerprint.input_key).json"
  [IO.File]::WriteAllText($path, (($receipt | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  $receipt["receipt"] = Get-MIRAssuranceRepoRelativePath -Path $path
  return $receipt
}

function Get-MIRAssuranceResultCounts {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()]$Results,
    [int]$ExpectedTotal = -1
  )
  $total = @($Results).Count
  $expected = if ($ExpectedTotal -ge 0) { $ExpectedTotal } else { $total }
  return [ordered]@{
    expected=$expected
    total=$total
    executed=@($Results | Where-Object { [string]$_.disposition -eq "RUN" }).Count
    reused=@($Results | Where-Object { [string]$_.disposition -in @("REUSE", "WAIT") }).Count
    checkpointed=@($Results | Where-Object { [string]$_.disposition -eq "CHECKPOINT" }).Count
    failed=@($Results | Where-Object { [string]$_.status -ne "passed" }).Count
    incomplete=[Math]::Max(0, $expected - $total)
    unexpected=[Math]::Max(0, $total - $expected)
  }
}
