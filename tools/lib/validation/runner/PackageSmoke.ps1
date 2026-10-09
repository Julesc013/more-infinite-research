function Assert-FluidProductivityStreamsGenerated {
  param(
    [string]$Context,
    [switch]$IncludeThruster
  )

  $streams = @(
    "research_oil_processing_productivity",
    "research_oil_cracking_productivity",
    "research_lubricant_productivity",
    "research_sulfuric_acid_productivity"
  )

  if ($IncludeThruster) {
    $streams += @(
      "research_thruster_fuel_productivity",
      "research_thruster_oxidizer_productivity"
    )
  }

  foreach ($stream in $streams) {
    $line = Get-LastStreamReportLine -Key $stream
    Assert-ReportLineGenerated -Line $line -Context "$Context stream $stream"
  }
}

function Invoke-PackageZipSmokeScenario {
  param(
    [string]$ScenarioName,
    [switch]$EnableSpaceAge
  )

  if (-not (Test-MIRScenarioSelected -Name $ScenarioName)) { return }

  $declaration = Resolve-MIRScenarioDeclaration `
    -Registry $scenarioRegistry `
    -ScenarioName $ScenarioName `
    -Kind "package" `
    -EnableSpaceAge:$EnableSpaceAge
  $scenarioGroup = $declaration.group
  $resultRecord = Start-MIRValidationScenario -Name $ScenarioName -Kind "package" -Group $scenarioGroup -EvidencePaths @($script:ValidationPackageZipPath, $FactorioLog)
  $activation=$null
  try {
    if ([string]::IsNullOrWhiteSpace($script:ValidationPackageZipPath) -or -not (Test-Path -LiteralPath $script:ValidationPackageZipPath)) {
      throw "Validation package zip is unavailable for packaged zip smoke."
    }

  $scenarioRoot = Join-Path $validationRoot (Get-MIRCompactScenarioPathSegment -ScenarioName $ScenarioName)
  if (Test-Path -LiteralPath $scenarioRoot) {
    $resolvedScenarioRoot = (Resolve-Path -LiteralPath $scenarioRoot).Path
    if (-not $resolvedScenarioRoot.StartsWith($validationRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove package smoke directory outside validation root: $resolvedScenarioRoot"
    }
    Remove-Item -LiteralPath $resolvedScenarioRoot -Recurse -Force
  }

  if([string]::IsNullOrWhiteSpace($LibraryDirectory)){throw '[mir-package-library-required] Supply the selected flat archive library; profile staging is retired.'}
  $activation=Start-MIRPackageLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $factorioReadData `
    -ProfilePath (Join-Path $scenarioRoot 'selection.json') -Version ([string]$repoInfo.version) `
    -CandidateSha256 (Get-MIRFileSha256 -Path $script:ValidationPackageZipPath) -EnableSpaceAge:$EnableSpaceAge
  $modsDir=$activation.library

  $savePath = Join-Path $scenarioRoot "mir-package-zip-smoke.zip"
  if (Test-Path -LiteralPath $savePath) {
    Remove-Item -LiteralPath $savePath -Force
  }

  Write-Host "[run] Factorio packaged zip smoke ($ScenarioName)"
  Clear-FactorioLog
  $factorioArgs = @(
    "--config",
    $factorioConfigPath,
    "--no-log-rotation",
    "--disable-audio",
    "--mod-directory",
    $modsDir,
    "--create",
    $savePath
  )
  Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $factorioArgs
  $factorioExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $factorioArgs -TimeoutMs ($declaration.timeout_seconds * 1000)
  if ($factorioExitCode -ne 0) {
    throw "Factorio package zip smoke $ScenarioName exited with code $factorioExitCode"
  }
  if (-not (Test-Path -LiteralPath $savePath)) {
    throw "Factorio package zip smoke $ScenarioName did not create the expected save: $savePath"
  }

    Assert-RuntimeLogHealthy -ScenarioName $ScenarioName
    $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $FactorioLog
    $terminal=Complete-MIRLibraryActivation -Activation $activation;$activation=$null
    [IO.File]::WriteAllText((Join-Path $scenarioRoot 'library-inputs.json'),($terminal|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    Complete-MIRValidationScenario -Record $resultRecord -Status "passed" -AssertionsExecuted @($declaration.assertions).Count
  } catch {
    Complete-MIRValidationScenario -Record $resultRecord -Status "failed" -ErrorMessage $_.Exception.Message
    throw
  } finally {
    if($null -ne $activation -and -not $activation.closed){$null=Complete-MIRLibraryActivation -Activation $activation}
  }
}

function Invoke-WeaponSpeedPolicyMatrix {
  param([string]$Context)

  $dedicatedStreams = @(
    "research_rocket_shooting_speed",
    "research_cannon_shooting_speed"
  )
  $cases = @(
    @{ Name = "weapon-overlap-off-coverage-absent"; Mode = "off"; CoverageAbsent = $true },
    @{ Name = "weapon-overlap-off-coverage-present"; Mode = "off" },
    @{ Name = "weapon-overlap-conditional-coverage-absent"; Mode = "only-when-dedicated-tech-enabled"; CoverageAbsent = $true },
    @{ Name = "weapon-overlap-conditional-coverage-present"; Mode = "only-when-dedicated-tech-enabled" },
    @{ Name = "weapon-overlap-always-coverage-absent"; Mode = "always"; CoverageAbsent = $true },
    @{ Name = "weapon-overlap-always-coverage-present"; Mode = "always" }
  )

  foreach ($case in $cases) {
    $parameters = @{
      ScenarioName = $case.Name
      EnabledFixtureNames = @("mir-fixture-assert-weapon-speed-safety")
      WeaponSpeedAdjustmentMode = $case.Mode
    }
    if ($case.CoverageAbsent) {
      $parameters.DisabledStreamKeys = $dedicatedStreams
    }
    Invoke-RuntimeScenario @parameters
    $extensionLine = Get-LastExtensionReportLine -Key "weapon-shooting-speed"
    Assert-ReportLineGenerated -Line $extensionLine -Context "$Context $($case.Name)"
  }

  Invoke-RuntimeScenario -ScenarioName "scaled-weapon-overlap" -EnabledFixtureNames @(
    "mir-fixture-assert-weapon-speed-safety"
  ) -WeaponSpeedAdjustmentMode "only-when-dedicated-tech-enabled" -EffectPerLevelOverrides @{
    research_rocket_shooting_speed = 20
    research_cannon_shooting_speed = 20
  }
  $scaledExtensionLine = Get-LastExtensionReportLine -Key "weapon-shooting-speed"
  Assert-ReportLineGenerated -Line $scaledExtensionLine -Context "$Context scaled weapon overlap"

  Invoke-RuntimeScenario -ScenarioName "weapon-overlap-conditional-external-owner" -EnabledFixtureNames @(
    "mir-fixture-weapon-speed-external-owner",
    "mir-fixture-assert-weapon-speed-safety"
  ) -WeaponSpeedAdjustmentMode "only-when-dedicated-tech-enabled"
  $externalExtensionLine = Get-LastExtensionReportLine -Key "weapon-shooting-speed"
  if ($externalExtensionLine -notmatch "status=generated" -and
      ($externalExtensionLine -notmatch "status=skipped" -or $externalExtensionLine -notmatch "reason=already_infinite")) {
    throw "$Context external owner neither generated a MIR continuation nor retained an existing infinite continuation: $externalExtensionLine"
  }
  foreach ($stream in $dedicatedStreams) {
    $streamLine = Get-LastStreamReportLine -Key $stream
    Assert-ReportLineContains -Line $streamLine -Expected "status=skipped" -Context "$Context external owner stream $stream"
    Assert-ReportLineContains -Line $streamLine -Expected "reason=covered_by_existing_infinite_native_modifier" -Context "$Context external owner stream $stream"
    Assert-ReportLineContains -Line $streamLine -Expected "owners=mir-fixture-external-weapon-speed-owner" -Context "$Context external owner stream $stream"
  }
}

