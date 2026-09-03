function Initialize-RuntimeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$EnabledFixtureNames,
    [string[]]$EnabledStreamKeys = @(),
    [string[]]$EnabledBaseExtensionKeys = @(),
    [string[]]$DisabledStreamKeys = @(),
    [string[]]$DisabledBaseExtensionKeys = @(),
    [hashtable]$EffectPerLevelOverrides = @{},
    [hashtable]$BaseEffectPerLevelOverrides = @{},
    [hashtable]$BaseMaxLevelOverrides = @{},
    [hashtable]$StartupSettingOverrides = @{},
    [ValidateSet("", "default", "disabled", "cost-base", "cost-linear", "cost-growth", "research-time", "max-level", "max-level-import", "effect", "combined", "unrecognized-default", "unrecognized-override")]
    [string]$NativeOwnerSettingsProfile = "",
    [switch]$LabPolicySkip,
    [switch]$LabPolicyEngineDefault,
    [ValidateSet("configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all")]
    [string]$SciencePackIngredientPolicy = "configured",
    [ValidateSet("", "off", "only-when-dedicated-tech-enabled", "always")]
    [string]$WeaponSpeedAdjustmentMode = "",
    [double]$PipelineExtentMultiplier = 1,
    [ValidateSet("", "engine-default", "percent-25", "percent-50", "percent-75", "percent-100", "percent-125", "percent-150", "percent-200", "percent-250", "percent-400", "percent-500", "percent-750", "percent-1000", "percent-2500", "percent-5000", "percent-10000", "percent-25000", "percent-100000")]
    [string]$PrototypeProductivityCap = "",
    [ValidateSet("", "engine-default", "saving-25", "saving-50", "saving-75", "saving-90", "saving-95", "saving-99", "saving-999", "saving-9999")]
    [string]$PrototypeEfficiencyCap = "",
    [ValidateSet("", "engine-default", "saving-25", "saving-50", "saving-75", "saving-90", "saving-95", "saving-99", "saving-999", "saving-9999")]
    [string]$PrototypePollutionCap = "",
    [ValidateSet("", "engine-default", "bonus-25", "bonus-50", "bonus-75", "bonus-100", "bonus-125", "bonus-150", "bonus-200", "bonus-250", "bonus-300", "bonus-400", "bonus-500", "bonus-750", "bonus-1000", "bonus-2500", "bonus-5000", "bonus-10000", "bonus-25000", "bonus-100000")]
    [string]$PrototypeSpeedCap = "",
    [ValidateSet("", "engine-default", "saving-25", "saving-50", "saving-75", "saving-90", "saving-95", "saving-99", "saving-999", "saving-9999")]
    [string]$PrototypeSpeedFloor = "",
    [ValidateSet("", "engine-default", "bonus-25", "bonus-50", "bonus-75", "bonus-100", "bonus-125", "bonus-150", "bonus-200", "bonus-250", "bonus-300", "bonus-400", "bonus-500", "bonus-750", "bonus-1000", "bonus-2500", "bonus-5000", "bonus-10000", "bonus-25000", "bonus-100000")]
    [string]$PrototypeQualityCap = "",
    [ValidateSet("", "engine-default", "match-productivity-cap", "percent-25", "percent-20", "percent-15", "percent-12-5", "percent-10", "percent-7-5", "percent-5", "percent-2-5", "percent-1", "percent-0-5", "percent-0-1")]
    [string]$RecyclingReturnChance = "",
    [switch]$PrototypePositivePowerFloor,
    [switch]$ProductivityCapSelfRecyclingOnly,
    [switch]$UnrestrictedModules,
    [switch]$RequireSpaceGate,
    [switch]$UseInstalledSpaceAgeIcons,
    [switch]$ScriptedDiagnostics,
    [switch]$EnableSpaceAge
  )

  $scenarioRoot = Join-Path $validationRoot (Get-MIRCompactScenarioPathSegment -ScenarioName $ScenarioName)
  if (Test-Path -LiteralPath $scenarioRoot) {
    $resolvedScenarioRoot = (Resolve-Path -LiteralPath $scenarioRoot).Path
    if (-not $resolvedScenarioRoot.StartsWith($validationRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove scenario directory outside validation root: $resolvedScenarioRoot"
    }
    Remove-Item -LiteralPath $resolvedScenarioRoot -Recurse -Force
  }

  $modsDir = Join-Path $scenarioRoot "mods"
  New-Item -ItemType Directory -Force -Path $modsDir | Out-Null

  if ([string]::IsNullOrWhiteSpace($script:ValidationPackageZipPath) -or -not (Test-Path -LiteralPath $script:ValidationPackageZipPath -PathType Leaf)) {
    throw "Validation package zip is unavailable for runtime scenario $ScenarioName."
  }
  $packageDestination = Join-Path $modsDir (Split-Path -Leaf $script:ValidationPackageZipPath)
  Assert-MIRFactorioPathBudget -Path $packageDestination -Context "Validation package archive path"
  Copy-MIRFileWithHardlinkFallback -Source $script:ValidationPackageZipPath -Destination $packageDestination

  $allFixtureInfos = @(Get-FixtureInfos)
  $fixtureInfos = foreach ($fixtureName in @($EnabledFixtureNames | Sort-Object -Unique)) {
    $matches = @($allFixtureInfos | Where-Object Name -eq $fixtureName)
    if ($matches.Count -eq 0) {
      throw "Validation scenario references missing fixture mod: $fixtureName"
    }
    if ($matches.Count -ne 1) {
      throw "Validation scenario fixture identity is ambiguous: $fixtureName"
    }
    $matches[0]
  }
  foreach ($fixtureInfo in $fixtureInfos) {
    Publish-MIRModDirectoryArchive `
      -Source $fixtureInfo.Path `
      -Name $fixtureInfo.Name `
      -Version $fixtureInfo.Version `
      -ModsDir $modsDir | Out-Null
  }

  $fixtureNames = @($fixtureInfos | Select-Object -ExpandProperty Name)
  Initialize-MIRSettingsOverrideMod -ModsDir $modsDir -FactorioVersion ([string]$repoInfo.factorio_version)

  Enable-CopiedDiagnostics -ModsDir $modsDir
  if ($ScriptedDiagnostics) {
    Enable-CopiedScriptedDiagnostics -ModsDir $modsDir
  }
  if ($LabPolicySkip) {
    Set-CopiedLabPolicySkip -ModsDir $modsDir
  }
  if ($LabPolicyEngineDefault) {
    Set-CopiedLabPolicyEngineDefault -ModsDir $modsDir
  }
  if ($SciencePackIngredientPolicy -ne "configured") {
    Set-CopiedSciencePackIngredientPolicy -ModsDir $modsDir -Policy $SciencePackIngredientPolicy
  }
  if (-not [string]::IsNullOrWhiteSpace($WeaponSpeedAdjustmentMode)) {
    Set-CopiedStartupSettingDefault -ModsDir $modsDir -Name "mir-adjust-vanilla-weapon-speed-techs" -ValueLiteral "`"$WeaponSpeedAdjustmentMode`""
  }
  if ($RequireSpaceGate) {
    Set-CopiedRequireSpaceGate -ModsDir $modsDir
  }
  if ($PipelineExtentMultiplier -ne 1) {
    Set-CopiedPipelineExtentMultiplier -ModsDir $modsDir -Multiplier $PipelineExtentMultiplier
  }
  Set-CopiedPrototypeLimitDefaults `
    -ModsDir $modsDir `
    -ProductivityCap $PrototypeProductivityCap `
    -EfficiencyCap $PrototypeEfficiencyCap `
    -PollutionCap $PrototypePollutionCap `
    -SpeedFloor $PrototypeSpeedFloor `
    -SpeedCap $PrototypeSpeedCap `
    -QualityCap $PrototypeQualityCap `
    -RecyclingReturnChance $RecyclingReturnChance `
    -PositivePowerFloor ([bool]$PrototypePositivePowerFloor) `
    -ProductivityCapSelfRecyclingOnly ([bool]$ProductivityCapSelfRecyclingOnly) `
    -UnrestrictedModules ([bool]$UnrestrictedModules)
  if ($UseInstalledSpaceAgeIcons) {
    Set-CopiedStartupSettingDefault -ModsDir $modsDir -Name "mir-use-installed-space-age-icons" -ValueLiteral "true"
  }
  foreach ($streamKey in $EnabledStreamKeys) {
    Set-CopiedStreamEnabled -ModsDir $modsDir -StreamKey $streamKey
  }
  foreach ($baseExtensionKey in $EnabledBaseExtensionKeys) {
    Set-CopiedBaseExtensionEnabled -ModsDir $modsDir -BaseExtensionKey $baseExtensionKey
  }
  foreach ($streamKey in $DisabledStreamKeys) {
    Set-CopiedStreamDisabled -ModsDir $modsDir -StreamKey $streamKey
  }
  foreach ($baseExtensionKey in $DisabledBaseExtensionKeys) {
    Set-CopiedBaseExtensionDisabled -ModsDir $modsDir -BaseExtensionKey $baseExtensionKey
  }
  Set-CopiedEffectPerLevelDefaults -ModsDir $modsDir -Overrides $EffectPerLevelOverrides
  Set-CopiedBaseEffectPerLevelDefaults -ModsDir $modsDir -Overrides $BaseEffectPerLevelOverrides
  foreach ($key in $BaseMaxLevelOverrides.Keys) {
    Set-CopiedBaseExtensionMaxLevel -ModsDir $modsDir -BaseExtensionKey $key -MaxLevel ([int]$BaseMaxLevelOverrides[$key])
  }
  $nativeOwnerOverrides = @{}
  $nativeOwnerStreamKeys = @(
    "research_processing_unit",
    "research_plastic",
    "research_low_density_structure",
    "research_rocket_fuel",
    "research_steel"
  )
  foreach ($key in $nativeOwnerStreamKeys) {
    switch ($NativeOwnerSettingsProfile) {
      "disabled" { $nativeOwnerOverrides["ips-enable-$key"] = $false }
      "cost-base" { $nativeOwnerOverrides["ips-cost-base-$key"] = 2000 }
      "cost-linear" { $nativeOwnerOverrides["ips-cost-linear-increment-$key"] = 2500 }
      "cost-growth" { $nativeOwnerOverrides["ips-cost-growth-$key"] = 1.25 }
      "research-time" { $nativeOwnerOverrides["ips-research-time-$key"] = 90 }
      "max-level" { $nativeOwnerOverrides["ips-max-level-$key"] = 5 }
      "effect" { $nativeOwnerOverrides["ips-effect-per-level-$key"] = 25 }
      "combined" {
        $nativeOwnerOverrides["ips-cost-base-$key"] = 2000
        $nativeOwnerOverrides["ips-cost-linear-increment-$key"] = 2500
        $nativeOwnerOverrides["ips-cost-growth-$key"] = 1.25
        $nativeOwnerOverrides["ips-research-time-$key"] = 90
        $nativeOwnerOverrides["ips-max-level-$key"] = 7
        $nativeOwnerOverrides["ips-effect-per-level-$key"] = 25
      }
    }
  }
  if ($NativeOwnerSettingsProfile -eq "unrecognized-override") {
    $nativeOwnerOverrides["ips-cost-base-research_processing_unit"] = 2000
  }
  foreach ($name in $StartupSettingOverrides.Keys) {
    $nativeOwnerOverrides[$name] = $StartupSettingOverrides[$name]
  }
  Set-CopiedStartupSettingDefaults -ModsDir $modsDir -Overrides $nativeOwnerOverrides
  if ($NativeOwnerSettingsProfile -eq "max-level-import") {
    $profileSettings = @{}
    foreach ($key in $nativeOwnerStreamKeys) {
      $profileSettings["ips-max-level-$key"] = 5
    }
    Set-CopiedMIRSettingsProfileDefault -ModsDir $modsDir -Settings $profileSettings
  }
  Complete-MIRSettingsOverrideMod -ModsDir $modsDir

  $mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = "elevated-rails"; enabled = [bool]$EnableSpaceAge },
    @{ name = "recycler"; enabled = [bool]$EnableSpaceAge },
    @{ name = "quality"; enabled = [bool]$EnableSpaceAge },
    @{ name = "space-age"; enabled = [bool]$EnableSpaceAge },
    @{ name = "more-infinite-research"; enabled = $true }
    @{ name = "mir-validation-settings-overrides"; enabled = $true }
  )
  $enabledFixtures = @{}
  foreach ($fixtureName in $EnabledFixtureNames) {
    $enabledFixtures[$fixtureName] = $true
  }
  foreach ($fixtureName in @($fixtureNames | Sort-Object)) {
    $mods += @{
      name = $fixtureName
      enabled = $enabledFixtures.ContainsKey($fixtureName)
    }
  }

  $modList = @{ mods = $mods } | ConvertTo-Json -Depth 5
  Set-Content -LiteralPath (Join-Path $modsDir "mod-list.json") -Value $modList -Encoding UTF8

  return [pscustomobject]@{
    Name = $ScenarioName
    ModsDir = $modsDir
    SavePath = Join-Path $scenarioRoot "mir-validation.zip"
    EnabledFixtureNames = @($EnabledFixtureNames)
  }
}

if ([string]::IsNullOrWhiteSpace($FactorioLog)) {
  $FactorioLog = Join-Path $validationRoot "factorio-current.log"
}

