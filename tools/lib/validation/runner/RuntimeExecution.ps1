function Clear-FactorioLog {
  if (Test-Path -LiteralPath $FactorioLog) {
    Remove-Item -LiteralPath $FactorioLog -Force
  }
}

function Assert-RuntimeLogHealthy {
  param(
    [string]$ScenarioName,
    [switch]$RequireDiagnostics
  )
  Write-Host "[info] Factorio log path: $FactorioLog"
  if (-not (Test-Path -LiteralPath $FactorioLog)) {
    throw "Factorio log not found after $ScenarioName runtime validation: $FactorioLog"
  }

  $fatalMarkers = Select-String -LiteralPath $FactorioLog -Pattern "------------- Error -------------", "Error Util.cpp" -SimpleMatch
  if ($fatalMarkers) {
    $fatalMarkers | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line }
    throw "Factorio runtime validation log contains fatal error markers after $ScenarioName."
  }
  if ($RequireDiagnostics) {
    if (-not (Select-String -LiteralPath $FactorioLog -Pattern "Loading mod settings mir-validation-settings-overrides" -SimpleMatch -Quiet)) {
      throw "Factorio runtime validation did not load the deterministic settings-override mod after $ScenarioName."
    }
    if (-not (Select-String -LiteralPath $FactorioLog -Pattern "[more-infinite-research] Generation report start" -SimpleMatch -Quiet)) {
      throw "Factorio runtime validation did not emit the required MIR generation report after $ScenarioName."
    }
  }
}

function Invoke-RuntimeScenario {
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

  if (-not (Test-MIRScenarioSelected -Name $ScenarioName)) { return }

  $declaration = Resolve-MIRScenarioDeclaration `
    -Registry $scenarioRegistry `
    -ScenarioName $ScenarioName `
    -Kind "runtime" `
    -EnableSpaceAge:$EnableSpaceAge
  $scenarioGroup = $declaration.group
  $resultRecord = Start-MIRValidationScenario -Name $ScenarioName -Kind "runtime" -Group $scenarioGroup -EvidencePaths @($FactorioLog)
  try {
    $scenario = Initialize-RuntimeScenario `
      -ScenarioName $ScenarioName `
      -EnabledFixtureNames $EnabledFixtureNames `
      -EnabledStreamKeys $EnabledStreamKeys `
      -EnabledBaseExtensionKeys $EnabledBaseExtensionKeys `
      -DisabledStreamKeys $DisabledStreamKeys `
      -DisabledBaseExtensionKeys $DisabledBaseExtensionKeys `
      -EffectPerLevelOverrides $EffectPerLevelOverrides `
      -BaseEffectPerLevelOverrides $BaseEffectPerLevelOverrides `
      -BaseMaxLevelOverrides $BaseMaxLevelOverrides `
      -StartupSettingOverrides $StartupSettingOverrides `
      -NativeOwnerSettingsProfile $NativeOwnerSettingsProfile `
      -LabPolicySkip:$LabPolicySkip `
      -LabPolicyEngineDefault:$LabPolicyEngineDefault `
      -SciencePackIngredientPolicy $SciencePackIngredientPolicy `
      -WeaponSpeedAdjustmentMode $WeaponSpeedAdjustmentMode `
      -PipelineExtentMultiplier $PipelineExtentMultiplier `
      -PrototypeProductivityCap $PrototypeProductivityCap `
      -PrototypeEfficiencyCap $PrototypeEfficiencyCap `
      -PrototypePollutionCap $PrototypePollutionCap `
      -PrototypeSpeedCap $PrototypeSpeedCap `
      -PrototypeSpeedFloor $PrototypeSpeedFloor `
      -PrototypeQualityCap $PrototypeQualityCap `
      -RecyclingReturnChance $RecyclingReturnChance `
      -PrototypePositivePowerFloor:$PrototypePositivePowerFloor `
      -ProductivityCapSelfRecyclingOnly:$ProductivityCapSelfRecyclingOnly `
      -UnrestrictedModules:$UnrestrictedModules `
      -RequireSpaceGate:$RequireSpaceGate `
      -UseInstalledSpaceAgeIcons:$UseInstalledSpaceAgeIcons `
      -ScriptedDiagnostics:$ScriptedDiagnostics `
      -EnableSpaceAge:$EnableSpaceAge
    if (Test-Path -LiteralPath $scenario.SavePath) {
      Remove-Item -LiteralPath $scenario.SavePath -Force
    }

    Write-Host "[run] Factorio load check with fixture mods ($ScenarioName)"
    Clear-FactorioLog
    $factorioArgs = @(
      "--config",
      $factorioConfigPath,
      "--no-log-rotation",
      "--disable-audio",
      "--mod-directory",
      $scenario.ModsDir,
      "--create",
      $scenario.SavePath
    )
    $factorioExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $factorioArgs -TimeoutMs ($declaration.timeout_seconds * 1000)
    if ($factorioExitCode -ne 0) {
      throw "Factorio runtime validation scenario $ScenarioName exited with code $factorioExitCode"
    }
    if (-not (Test-Path -LiteralPath $scenario.SavePath)) {
      throw "Factorio runtime validation scenario $ScenarioName did not create the expected save: $($scenario.SavePath). Factorio exit code: $factorioExitCode"
    }

    Assert-RuntimeLogHealthy -ScenarioName $ScenarioName -RequireDiagnostics
    Complete-MIRValidationScenario -Record $resultRecord -Status "passed" -AssertionsExecuted @($declaration.assertions).Count
  } catch {
    Complete-MIRValidationScenario -Record $resultRecord -Status "failed" -ErrorMessage $_.Exception.Message
    throw
  }

}

function Invoke-RuntimeConfigurationChangeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$InitialFixtureNames = @(),
    [string[]]$ChangedFixtureNames = @(),
    [string[]]$EnabledStreamKeys = @(),
    [string[]]$InitialEnabledStreamKeys = @(),
    [string[]]$ChangedEnabledStreamKeys = @(),
    [string[]]$InitialDisabledStreamKeys = @(),
    [string[]]$ChangedDisabledStreamKeys = @(),
    [hashtable]$EffectPerLevelOverrides = @{},
    [hashtable]$InitialStartupSettingOverrides = @{},
    [hashtable]$ChangedStartupSettingOverrides = @{},
    [ValidateSet("", "default", "disabled", "cost-base", "cost-linear", "cost-growth", "research-time", "max-level", "effect", "combined", "unrecognized-default", "unrecognized-override")]
    [string]$InitialNativeOwnerSettingsProfile = "",
    [ValidateSet("", "default", "disabled", "cost-base", "cost-linear", "cost-growth", "research-time", "max-level", "effect", "combined", "unrecognized-default", "unrecognized-override")]
    [string]$ChangedNativeOwnerSettingsProfile = "",
    [switch]$ScriptedDiagnostics,
    [switch]$EnableSpaceAge
  )
  if (-not (Test-MIRScenarioSelected -Name $ScenarioName)) { return }

  $declaration = Resolve-MIRScenarioDeclaration `
    -Registry $scenarioRegistry `
    -ScenarioName $ScenarioName `
    -Kind "configuration-change" `
    -EnableSpaceAge:$EnableSpaceAge
  $scenarioGroup = $declaration.group
  $resultRecord = Start-MIRValidationScenario -Name $ScenarioName -Kind "configuration-change" -Group $scenarioGroup -EvidencePaths @($FactorioLog)
  try {
    $initialScenario = Initialize-RuntimeScenario `
      -ScenarioName "$ScenarioName-initial" `
      -EnabledFixtureNames $InitialFixtureNames `
      -EnabledStreamKeys @($EnabledStreamKeys + $InitialEnabledStreamKeys) `
      -DisabledStreamKeys $InitialDisabledStreamKeys `
      -EffectPerLevelOverrides $EffectPerLevelOverrides `
      -StartupSettingOverrides $InitialStartupSettingOverrides `
      -NativeOwnerSettingsProfile $InitialNativeOwnerSettingsProfile `
      -ScriptedDiagnostics:$ScriptedDiagnostics `
      -EnableSpaceAge:$EnableSpaceAge
    if (Test-Path -LiteralPath $initialScenario.SavePath) {
      Remove-Item -LiteralPath $initialScenario.SavePath -Force
    }

    Write-Host "[run] Factorio initial save for configuration-change check ($ScenarioName)"
    Clear-FactorioLog
    $createArgs = @(
      "--config",
      $factorioConfigPath,
      "--no-log-rotation",
      "--disable-audio",
      "--mod-directory",
      $initialScenario.ModsDir,
      "--create",
      $initialScenario.SavePath
    )
    $createExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $createArgs -TimeoutMs ($declaration.timeout_seconds * 1000)
    if ($createExitCode -ne 0) {
      throw "Factorio configuration-change initial scenario $ScenarioName exited with code $createExitCode"
    }
    if (-not (Test-Path -LiteralPath $initialScenario.SavePath)) {
      throw "Factorio configuration-change initial scenario $ScenarioName did not create the expected save: $($initialScenario.SavePath)."
    }

    Assert-RuntimeLogHealthy -ScenarioName "$ScenarioName initial" -RequireDiagnostics

    $changedScenario = Initialize-RuntimeScenario `
      -ScenarioName "$ScenarioName-changed" `
      -EnabledFixtureNames $ChangedFixtureNames `
      -EnabledStreamKeys @($EnabledStreamKeys + $ChangedEnabledStreamKeys) `
      -DisabledStreamKeys $ChangedDisabledStreamKeys `
      -EffectPerLevelOverrides $EffectPerLevelOverrides `
      -StartupSettingOverrides $ChangedStartupSettingOverrides `
      -NativeOwnerSettingsProfile $ChangedNativeOwnerSettingsProfile `
      -ScriptedDiagnostics:$ScriptedDiagnostics `
      -EnableSpaceAge:$EnableSpaceAge

    Write-Host "[run] Factorio configuration-change load check with fixture mods ($ScenarioName)"
    Clear-FactorioLog
    $benchmarkArgs = @(
      "--config",
      $factorioConfigPath,
      "--no-log-rotation",
      "--disable-audio",
      "--mod-directory",
      $changedScenario.ModsDir,
      "--benchmark",
      $initialScenario.SavePath,
      "--benchmark-ticks",
      "1",
      "--benchmark-runs",
      "1",
      "--benchmark-sanitize"
    )
    $benchmarkExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $benchmarkArgs -TimeoutMs ($declaration.timeout_seconds * 1000)
    if ($benchmarkExitCode -ne 0) {
      throw "Factorio configuration-change load scenario $ScenarioName exited with code $benchmarkExitCode"
    }

    Assert-RuntimeLogHealthy -ScenarioName "$ScenarioName changed" -RequireDiagnostics
    Complete-MIRValidationScenario -Record $resultRecord -Status "passed" -AssertionsExecuted @($declaration.assertions).Count
  } catch {
    Complete-MIRValidationScenario -Record $resultRecord -Status "failed" -ErrorMessage $_.Exception.Message
    throw
  }
}

