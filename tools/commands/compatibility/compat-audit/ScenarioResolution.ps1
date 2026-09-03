$fullCache = @{}
function Get-FullCached {
  param([Parameter(Mandatory)][string]$Name)
  if ($localFullModsByName.ContainsKey($Name)) {
    return $localFullModsByName[$Name]
  }
  if ($Offline) {
    throw "Offline mode is enabled and mod '$Name' is not present in local mod zip roots or libraries."
  }
  if (-not $fullCache.ContainsKey($Name)) {
    $fullCache[$Name] = Get-MIRModPortalFullMod -Name $Name
  }
  return $fullCache[$Name]
}

function Resolve-MIRPortalScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Type,
    [string[]]$RequestedMods = @(),
    [bool]$EnableSpaceAgeBundle,
    [string]$ClaimLevel = "loads",
    [int]$TimeoutSeconds = $ScenarioTimeoutSeconds,
    $Settings = $null,
    $ExpectedPlan = $null,
    [string]$SourceManifest = "",
    [string]$Notes = ""
  )

  $rootModNames = @(Get-MIRPortalRootModNames -ModNames $RequestedMods)
  $explicitOfficialMods = @(Get-MIRExplicitOfficialMods -ModNames $RequestedMods)
  $scenarioFailures = @()
  $scenarioLockEntries = @()

  foreach ($rootName in $rootModNames) {
    try {
      $full = Get-FullCached -Name $rootName
      $release = Select-MIRCompatibleRelease -FullMod $full -FactorioVersions $FactorioVersions
      if (-not $release) {
        $scenarioFailures += [pscustomobject]@{
          name = $rootName
          phase = "release-selection"
          error = "No compatible release for Factorio versions: $($FactorioVersions -join ',')"
        }
        continue
      }

      $deps = @(Get-MIRReleaseDependencies -Release $release)
      $scenarioLockEntries += ConvertTo-MIRScenarioLockEntry -FullMod $full -Release $release -Dependencies $deps

      $closure = Resolve-MIRRequiredDependencyClosure `
        -RootModNames @($rootName) `
        -GetFullMod { param($name) Get-FullCached -Name $name } `
        -SelectRelease { param($fullMod) Select-MIRCompatibleRelease -FullMod $fullMod -FactorioVersions $FactorioVersions } `
        -IncludeRecommendedDependencies:$IncludeRecommendedDependencies `
        -FailFast:$FailFast

      foreach ($dep in @($closure.resolved)) {
        if ($dep.name -eq $rootName) { continue }
        $scenarioLockEntries += ConvertTo-MIRScenarioLockEntry -FullMod $dep.full -Release $dep.release -Dependencies $dep.dependencies
      }
      $scenarioFailures += @($closure.failures | ForEach-Object {
        [pscustomobject]@{
          name = $_.name
          phase = "dependency-resolution"
          error = $_.error
        }
      })
    } catch {
      $scenarioFailures += [pscustomobject]@{
        name = $rootName
        phase = "metadata"
        error = $_.Exception.Message
      }
      if ($FailFast) { throw }
    }
  }

  $scenarioLockEntries = @($scenarioLockEntries | Sort-Object name, version -Unique)
  $resolvedNames = @($scenarioLockEntries | ForEach-Object { $_.name } | Sort-Object -Unique)
  $officialMods = @(Get-MIREnabledOfficialModsFromEntries `
    -LockEntries $scenarioLockEntries `
    -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
    -ExplicitOfficialMods $explicitOfficialMods `
    -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)
  foreach ($missingOfficial in @(Get-MIRUnavailableOfficialMods `
      -LockEntries $scenarioLockEntries `
      -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
      -ExplicitOfficialMods $explicitOfficialMods `
      -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)) {
    $scenarioFailures += [pscustomobject]@{
      name = $missingOfficial
      phase = "official-mod"
      error = "Official built-in mod '$missingOfficial' is not present for Factorio line $FactorioLine at the selected Factorio binary."
    }
  }

  New-MIRScenario `
    -Name $Name `
    -Type $Type `
    -RequestedMods $RequestedMods `
    -RootMods $rootModNames `
    -ResolvedMods $resolvedNames `
    -OfficialMods $officialMods `
    -LockEntries $scenarioLockEntries `
    -Failures $scenarioFailures `
    -ClaimLevel $ClaimLevel `
    -TimeoutSeconds $TimeoutSeconds `
    -Settings $Settings `
    -ExpectedPlan $ExpectedPlan `
    -SourceManifest $SourceManifest `
    -Notes $Notes
}

function Resolve-MIRLockScenario {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$LockEntriesByName,
    [string[]]$RequestedMods = @(),
    [bool]$EnableSpaceAgeBundle
  )

  $rootModNames = @(Get-MIRPortalRootModNames -ModNames $RequestedMods)
  $closure = Resolve-MIRLockDependencyNames `
    -RootModNames $rootModNames `
    -LockEntriesByName $LockEntriesByName `
    -IncludeRecommendedDependencies:$IncludeRecommendedDependencies
  $resolvedNames = @($closure.names)
  $scenarioLockEntries = @(
    foreach ($name in $resolvedNames) {
      if ($LockEntriesByName.ContainsKey([string]$name)) { $LockEntriesByName[[string]$name] }
    }
  )
  $officialMods = @(Get-MIREnabledOfficialModsFromEntries `
    -LockEntries $scenarioLockEntries `
    -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
    -ExplicitOfficialMods (Get-MIRExplicitOfficialMods -ModNames $RequestedMods) `
    -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)
  $scenarioFailures = @($closure.failures)
  foreach ($missingOfficial in @(Get-MIRUnavailableOfficialMods `
      -LockEntries $scenarioLockEntries `
      -EnableSpaceAgeBundle $EnableSpaceAgeBundle `
      -ExplicitOfficialMods (Get-MIRExplicitOfficialMods -ModNames $RequestedMods) `
      -IncludeRecommendedDependencies:$IncludeRecommendedDependencies)) {
    $scenarioFailures += [pscustomobject]@{
      name = $missingOfficial
      phase = "official-mod"
      error = "Official built-in mod '$missingOfficial' is not present for Factorio line $FactorioLine at the selected Factorio binary."
    }
  }

  New-MIRScenario `
    -Name $Name `
    -Type "catalog" `
    -RequestedMods $RequestedMods `
    -RootMods $rootModNames `
    -ResolvedMods $resolvedNames `
    -OfficialMods $officialMods `
    -LockEntries $scenarioLockEntries `
    -Failures $scenarioFailures
}

function Invoke-MIRScenarioLoad {
  param([Parameter(Mandatory)]$Scenario)

  $dependencyFailures = @($Scenario.dependency_failures)
  if ($dependencyFailures.Count -gt 0 -and -not $ContinueOnDependencyFailure) {
    [pscustomobject]@{
      scenario = $Scenario.name
      type = $Scenario.type
      requested_mods = @($Scenario.requested_mods)
      root_mods = @($Scenario.root_mods)
      resolved_mods = @($Scenario.resolved_mods)
      official_mods = @($Scenario.official_mods)
      dependency_failures = $dependencyFailures
      exit_code = $null
      timed_out = $false
      timeout_seconds = [int](Get-MIRObjectProperty -Object $Scenario -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)
      duration_seconds = 0.0
      skipped = $true
      skip_reason = "dependency_resolution_failure"
      process_passed = $false
      passed = $false
      save = ""
      stdout = ""
      stderr = ""
      audit_rows = @()
      sanitation_rows = @()
    }
    return
  }

  $userData = New-MIRCompatUserDataDir -Root $runtimeRunRoot
  $modsDir = Join-Path $userData "mods"
  $null = Copy-MIRModUnderTest -RepoRoot $repo.Path -ModsDir $modsDir -ZipPath $resolvedModUnderTestZip
  Initialize-MIRSettingsOverrideMod -ModsDir $modsDir -FactorioVersion $FactorioLine
  Enable-CopiedDiagnostics -ModsDir $modsDir
  $scenarioSettings = Get-MIRObjectProperty -Object $Scenario -Name "settings" -Default ([pscustomobject]@{})
  $startupOverrides = @{}
  foreach ($property in @($scenarioSettings.PSObject.Properties)) {
    $startupOverrides[[string]$property.Name] = $property.Value
  }
  Set-CopiedStartupSettingDefaults -ModsDir $modsDir -Overrides $startupOverrides
  Complete-MIRSettingsOverrideMod -ModsDir $modsDir

  Copy-MIRCachedModZips -CacheDir $resolvedCacheDir -ModsDir $modsDir -LockEntries $Scenario.lock_entries -LinkMode $LinkMode

  $enabledMods = @("more-infinite-research", "mir-validation-settings-overrides") + @($Scenario.resolved_mods) + @($Scenario.official_mods)
  Write-MIRModList -ModsDir $modsDir -EnabledMods $enabledMods -OfficialBuiltinMods $officialBuiltinMods

  $scenarioTimeout = [int](Get-MIRObjectProperty -Object $Scenario -Name "timeout_seconds" -Default $ScenarioTimeoutSeconds)
  $result = Invoke-MIRFactorioLoadCheck -FactorioBin $FactorioBin -UserDataDir $userData -ScenarioName $Scenario.name -ScenarioTimeoutSeconds $scenarioTimeout
  $result = Move-MIRCompatScenarioEvidence -UserDataDir $userData -EvidenceRoot $retainedRunRoot -Result $result
  $expectedPlan = Get-MIRObjectProperty -Object $Scenario -Name "expected_plan" -Default ([pscustomobject]@{})
  $requiredStreamScience = Get-MIRObjectProperty -Object $expectedPlan -Name "required_stream_science" -Default ([pscustomobject]@{})
  $forbiddenStreamScience = Get-MIRObjectProperty -Object $expectedPlan -Name "forbidden_stream_science" -Default ([pscustomobject]@{})
  $scienceAssertions = @(
    foreach ($requiredStream in @($requiredStreamScience.PSObject.Properties)) {
      $streamName = [string]$requiredStream.Name
      $requiredPacks = @($requiredStream.Value | ForEach-Object { [string]$_ })
      $streamRows = @($result.audit_rows | Where-Object {
        [string]$_.kind -eq "stream" -and
        [string]$_.key -eq $streamName -and
        [string]$_.status -eq "generated"
      })
      $observedPacks = @(
        $streamRows |
          ForEach-Object { @([string]$_.science -split ",") } |
          Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
          Sort-Object -Unique
      )
      $missingPacks = @($requiredPacks | Where-Object { $_ -notin $observedPacks })
      [pscustomobject]@{
        stream = $streamName
        required_packs = $requiredPacks
        observed_packs = $observedPacks
        matching_generated_rows = $streamRows.Count
        missing_packs = $missingPacks
        passed = ($streamRows.Count -gt 0 -and $missingPacks.Count -eq 0)
      }
    }
  )
  $forbiddenScienceAssertions = @(
    foreach ($forbiddenStream in @($forbiddenStreamScience.PSObject.Properties)) {
      $streamName = [string]$forbiddenStream.Name
      $forbiddenPacks = @($forbiddenStream.Value | ForEach-Object { [string]$_ })
      $streamRows = @($result.audit_rows | Where-Object {
        [string]$_.kind -eq "stream" -and
        [string]$_.key -eq $streamName -and
        [string]$_.status -eq "generated"
      })
      $observedPacks = @(
        $streamRows |
          ForEach-Object { @([string]$_.science -split ",") } |
          Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
          Sort-Object -Unique
      )
      $presentForbiddenPacks = @($forbiddenPacks | Where-Object { $_ -in $observedPacks })
      [pscustomobject]@{
        stream = $streamName
        forbidden_packs = $forbiddenPacks
        observed_packs = $observedPacks
        matching_generated_rows = $streamRows.Count
        present_forbidden_packs = $presentForbiddenPacks
        passed = ($streamRows.Count -gt 0 -and $presentForbiddenPacks.Count -eq 0)
      }
    }
  )
  $allScienceAssertions = @($scienceAssertions) + @($forbiddenScienceAssertions)
  $scienceContractPassed = @($allScienceAssertions | Where-Object { $_.passed -ne $true }).Count -eq 0
  $requiredAuditRows = @(Get-MIRObjectProperty -Object $expectedPlan -Name "required_audit_rows" -Default @())
  $requiredAuditAssertions = @(
    foreach ($expectedRow in $requiredAuditRows) {
      $matchingRows = @($result.audit_rows | Where-Object { Test-MIRCompatAuditRowMatch -Row $_ -Expected $expectedRow })
      [pscustomobject]@{
        expected = $expectedRow
        matching_rows = $matchingRows.Count
        passed = ($matchingRows.Count -gt 0)
      }
    }
  )
  $stdoutText = if (-not [string]::IsNullOrWhiteSpace([string]$result.stdout) -and
      (Test-Path -LiteralPath ([string]$result.stdout) -PathType Leaf)) {
    [IO.File]::ReadAllText([string]$result.stdout)
  } else { "" }
  $requiredLogAssertions = @(
    foreach ($fragment in @(Get-MIRObjectProperty -Object $expectedPlan -Name "required_log_fragments" -Default @())) {
      $text = [string]$fragment
      [pscustomobject]@{fragment=$text; passed=$stdoutText.Contains($text, [StringComparison]::Ordinal)}
    }
  )
  $forbiddenLogAssertions = @(
    foreach ($fragment in @(Get-MIRObjectProperty -Object $expectedPlan -Name "forbidden_log_fragments" -Default @())) {
      $text = [string]$fragment
      [pscustomobject]@{fragment=$text; passed=(-not $stdoutText.Contains($text, [StringComparison]::Ordinal))}
    }
  )
  $runtimeAssertions = @($requiredAuditAssertions) + @($requiredLogAssertions) + @($forbiddenLogAssertions)
  $runtimeContractPassed = @($runtimeAssertions | Where-Object { $_.passed -ne $true }).Count -eq 0
  [pscustomobject]@{
    scenario = $Scenario.name
    type = $Scenario.type
    requested_mods = @($Scenario.requested_mods)
    root_mods = @($Scenario.root_mods)
    resolved_mods = @($Scenario.resolved_mods)
    official_mods = @($Scenario.official_mods)
    dependency_failures = $dependencyFailures
    exit_code = $result.exit_code
    timed_out = $result.timed_out
    timeout_seconds = $result.timeout_seconds
    duration_seconds = [double]$result.duration_seconds
    skipped = $false
    skip_reason = ""
    process_passed = [bool]$result.passed
    passed = ($result.passed -and $scienceContractPassed -and $runtimeContractPassed)
    save = $result.save
    stdout = $result.stdout
    stderr = $result.stderr
    audit_rows = @($result.audit_rows)
    sanitation_rows = @($result.sanitation_rows)
    science_contract_passed = $scienceContractPassed
    science_assertions = $scienceAssertions
    forbidden_science_assertions = $forbiddenScienceAssertions
    runtime_contract_passed = $runtimeContractPassed
    required_audit_assertions = $requiredAuditAssertions
    required_log_assertions = $requiredLogAssertions
    forbidden_log_assertions = $forbiddenLogAssertions
  }
}
