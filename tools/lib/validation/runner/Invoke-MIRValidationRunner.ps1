$ErrorActionPreference = "Stop"
$runnerModuleRoot = $PSScriptRoot
$repo = Resolve-Path (Join-Path $runnerModuleRoot "../../../..")
. (Join-Path $repo "tools\lib\validation\PackageIdentity.ps1")
. (Join-Path $repo "tools\lib\validation\TargetProfiles.ps1")
. (Join-Path $repo "tools\lib\validation\ScenarioGroups.ps1")
. (Join-Path $repo "tools\lib\validation\ResultAggregation.ps1")
. (Join-Path $repo "tools\lib\validation\FactorioProcess.ps1")
. (Join-Path $repo "tools\lib\validation\SettingsOverrides.ps1")
. (Join-Path $repo "tools\lib\validation\ScenarioRegistry.ps1")
. (Join-Path $repo "tools\lib\control\Core.ps1")

$validationRunnerCompleted = $false
. (Join-Path $runnerModuleRoot "Bootstrap.ps1")
if ($validationRunnerCompleted) { return }

$moduleSequence = @(
  "StaticCore.ps1",
  "StaticFixtureMods.ps1",
  "StaticSciencePackSettings.ps1",
  "StaticPrototypeLimits.ps1",
  "StaticCompatibilityTooling.ps1",
  "StaticCompilerDiagnostics.ps1",
  "StaticPolicyAndDocs.ps1",
  "StaticPackage.ps1",
  "RuntimeSelection.ps1",
  "RuntimeWorkspace.ps1",
  "RuntimeScenarioSetup.ps1",
  "RuntimeExecution.ps1",
  "RuntimeAssertions.ps1",
  "PackageSmoke.ps1"
)
foreach ($module in $moduleSequence) {
  . (Join-Path $runnerModuleRoot $module)
}

if ($selectionActive -and -not $checkpointActive) {
  try {
    $selectedExecutable = @($scenarioRegistry.records | Where-Object kind -ne "gate" | Sort-Object name)
    if ($MaxParallel -gt 1 -and @($selectedExecutable | Where-Object kind -ne "runtime").Count -eq 0) {
      $history = @{}
      $historyPath = Join-Path $repo "build\results\validation\factorio-$($repoInfo.factorio_version)-summary.json"
      if (Test-Path -LiteralPath $historyPath) {
        try {
          $historical = Get-Content -Raw -LiteralPath $historyPath | ConvertFrom-Json
          foreach ($row in @($historical.scenarios)) { $history[[string]$row.name] = [double]$row.duration_seconds }
        } catch { $history = @{} }
      }
      $tasks = @()
      foreach ($declaration in $selectedExecutable) {
        $parameters = @{
          ScenarioName = $declaration.name
          EnabledFixtureNames = @($declaration.fixtures)
          EnableSpaceAge = ($declaration.surface -eq "space-age")
        }
        foreach ($property in $declaration.settings.PSObject.Properties) {
          $parameters[$property.Name] = ConvertTo-MIRScenarioParameterValue -Value $property.Value
        }
        $scenarioState = Initialize-RuntimeScenario @parameters
        $scenarioRoot = Split-Path -Parent $scenarioState.SavePath
        $workerData = Join-Path $scenarioRoot "userdata"
        New-Item -ItemType Directory -Force -Path $workerData | Out-Null
        $workerConfig = Join-Path $scenarioRoot "factorio-config.ini"
        $workerConfigText = $factorioConfigText.Replace("write-data=$validationRoot", "write-data=$workerData")
        Set-Content -LiteralPath $workerConfig -Value $workerConfigText -Encoding UTF8
        $workerLog = Join-Path $workerData "factorio-current.log"
        $record = Start-MIRValidationScenario -Name $declaration.name -Kind "runtime" -Group $declaration.group -EvidencePaths @($workerLog)
        $estimate = if ($history.ContainsKey($declaration.name)) { $history[$declaration.name] } elseif ($declaration.surface -eq "space-age") { 90.0 } else { 20.0 }
        $tasks += [pscustomobject]@{
          Declaration = $declaration
          Scenario = $scenarioState
          Config = $workerConfig
          Log = $workerLog
          Record = $record
          Estimate = $estimate
          Process = $null
          Started = $null
        }
      }
      $pending = [System.Collections.ArrayList]@($tasks | Sort-Object `
        @{Expression={$_.Estimate};Descending=$true}, `
        @{Expression={$_.Declaration.name};Ascending=$true})
      $running = [System.Collections.ArrayList]::new()
      while ($pending.Count -gt 0 -or $running.Count -gt 0) {
        while ($pending.Count -gt 0 -and $running.Count -lt $MaxParallel) {
          $task = $pending[0]
          $pending.RemoveAt(0)
          $info = [System.Diagnostics.ProcessStartInfo]::new()
          $info.FileName = $FactorioBin
          $info.UseShellExecute = $false
          $info.CreateNoWindow = $true
          $info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
          foreach ($argument in @("--config", $task.Config, "--no-log-rotation", "--disable-audio", "--mod-directory", $task.Scenario.ModsDir, "--create", $task.Scenario.SavePath)) {
            [void]$info.ArgumentList.Add([string]$argument)
          }
          $task.Process = [System.Diagnostics.Process]::Start($info)
          $task.Started = [DateTime]::UtcNow
          $null = $running.Add($task)
          Write-Host "[run] parallel Factorio load check ($($task.Declaration.name))"
        }
        foreach ($task in @($running)) {
          $elapsed = ([DateTime]::UtcNow - $task.Started).TotalSeconds
          if (-not $task.Process.HasExited -and $elapsed -gt $task.Declaration.timeout_seconds) {
            try { $task.Process.Kill($true) } catch { $task.Process.Kill() }
            Complete-MIRValidationScenario -Record $task.Record -Status "failed" -ErrorMessage "Scenario timed out after $($task.Declaration.timeout_seconds) seconds."
            throw "Parallel validation scenario $($task.Declaration.name) timed out."
          }
          if ($task.Process.HasExited) {
            $running.Remove($task)
            if ($task.Process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $task.Scenario.SavePath)) {
              Complete-MIRValidationScenario -Record $task.Record -Status "failed" -ErrorMessage "Factorio exited with code $($task.Process.ExitCode)."
              throw "Parallel validation scenario $($task.Declaration.name) failed with code $($task.Process.ExitCode)."
            }
            if (-not (Test-Path -LiteralPath $task.Log)) { throw "Parallel validation log is missing: $($task.Log)" }
            $fatal = Select-String -LiteralPath $task.Log -Pattern "------------- Error -------------", "Error Util.cpp" -SimpleMatch
            if ($fatal) { throw "Parallel validation log contains fatal markers: $($task.Declaration.name)" }
            if (-not (Select-String -LiteralPath $task.Log -Pattern "Loading mod settings mir-validation-settings-overrides" -SimpleMatch -Quiet)) {
              throw "Parallel validation scenario $($task.Declaration.name) did not load the deterministic settings-override mod."
            }
            if (-not (Select-String -LiteralPath $task.Log -Pattern "[more-infinite-research] Generation report start" -SimpleMatch -Quiet)) {
              throw "Parallel validation scenario $($task.Declaration.name) did not emit the required MIR generation report."
            }
            Complete-MIRValidationScenario -Record $task.Record -Status "passed" -AssertionsExecuted @($task.Declaration.assertions).Count
          }
        }
        if ($running.Count -gt 0) { Start-Sleep -Milliseconds 200 }
      }
    } else {
    foreach ($declaration in @($scenarioRegistry.records | Where-Object kind -ne "gate" | Sort-Object name)) {
      if ($declaration.kind -eq "package") {
        Invoke-PackageZipSmokeScenario -ScenarioName $declaration.name -EnableSpaceAge:($declaration.surface -eq "space-age")
      } elseif ($declaration.kind -eq "runtime") {
        $parameters = @{
          ScenarioName = $declaration.name
          EnabledFixtureNames = @($declaration.fixtures)
          EnableSpaceAge = ($declaration.surface -eq "space-age")
        }
        foreach ($property in $declaration.settings.PSObject.Properties) {
          $parameterName = Resolve-MIRScenarioSettingParameterName -Name ([string]$property.Name)
          $parameters[$parameterName] = ConvertTo-MIRScenarioParameterValue -Value $property.Value
        }
        Invoke-RuntimeScenario @parameters
        if ($declaration.name -eq "space-age-generation-integrity") {
          Assert-SpaceAgeVanillaOwnedProductivityStreamsBound -Context "Space Age generation integrity scenario"
        } elseif ($declaration.name -eq "space-age-generation-integrity-inserter-enabled") {
          Assert-SpaceAgeVanillaOwnedProductivityStreamsBound -Context "Space Age generation integrity with inserter enabled scenario"
        } elseif ($declaration.name -eq "space-age-native-owner-settings-max-level-late-conflict") {
          Assert-LogContains -Expected "Maximum-level conflict technology=processing-unit-productivity selected=5 planned=5 final-observed=9 binding-operation=configure_native_owner source=native-owner reason=late_prototype_mutation" -Context $declaration.name
        }
      } elseif ($declaration.kind -eq "configuration-change") {
        switch ($declaration.name) {
          "generated-maximum-level-lowering-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-generated-cap-transition") `
              -ChangedFixtureNames @("mir-fixture-assert-generated-cap-transition") `
              -InitialStartupSettingOverrides @{ "ips-max-level-research_copper" = 0 } `
              -ChangedStartupSettingOverrides @{ "ips-max-level-research_copper" = 5 }
            Assert-LogContains -Expected "[mir-fixture] generated lowered cap retained completed levels and removed invalid research" -Context $declaration.name
          }
          "generated-maximum-level-lowering-config-change-2-0" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-generated-cap-transition-2-0") `
              -ChangedFixtureNames @("mir-fixture-assert-generated-cap-transition-2-0") `
              -InitialStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 0 } `
              -ChangedStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 5 }
            Assert-LogContains -Expected "[mir-fixture] Factorio 2.0 lowered cap retained completed levels and removed invalid research" -Context $declaration.name
          }
          "base-continuation-maximum-level-lowering-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @(
                "mir-fixture-finite-base-extension-level",
                "mir-fixture-assert-base-continuation-cap-transition"
              ) `
              -ChangedFixtureNames @(
                "mir-fixture-finite-base-extension-level",
                "mir-fixture-assert-base-continuation-cap-transition"
              ) `
              -InitialStartupSettingOverrides @{ "mir-max-level-research-speed" = 0 } `
              -ChangedStartupSettingOverrides @{ "mir-max-level-research-speed" = 5 }
            Assert-LogContains -Expected "[mir-fixture] base continuation survived a cap below its first level without losing completed research" -Context $declaration.name
          }
          "space-age-native-owner-settings-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
            -InitialFixtureNames @(
              "mir-fixture-native-owner-settings-source",
              "mir-fixture-assert-native-owner-settings",
              "mir-fixture-assert-native-owner-progress"
            ) `
            -ChangedFixtureNames @(
              "mir-fixture-native-owner-settings-source",
              "mir-fixture-assert-native-owner-settings",
              "mir-fixture-assert-native-owner-progress"
            ) `
              -InitialNativeOwnerSettingsProfile "default" `
              -ChangedNativeOwnerSettingsProfile "combined" `
              -EnableSpaceAge
          Assert-LogContains -Expected "Preserved technology effects without a force-wide reset for productivity family adoption signature change" -Context $declaration.name
          Assert-LogContains -Expected "Retained Factorio-normalized current research progress for native owner low-density-structure-productivity" -Context $declaration.name
          Assert-LogContains -Expected "[mir-fixture] native-owner force-state preservation proof complete" -Context $declaration.name
          Assert-LogContains -Expected "[mir-fixture] native-owner progress configuration-change proof complete" -Context $declaration.name
          Assert-LogContains -Expected "[mir-fixture] research-cost transition matrix proof complete phase=configuration-changed rows=16" -Context $declaration.name
          Assert-NativeOwnerResearchWorkPreserved -Context $declaration.name
          Assert-LogContains -Expected "schema=4|stream=research_rocket_fuel|owner=rocket-fuel-productivity|operation=configure_native_owner|configured=cost_model,effect_per_level,max_level,research_time|effects=0|input-cost=" -Context $declaration.name
          }
          "space-age-native-owner-cap-lowering-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-native-owner-cap-transition") `
              -ChangedFixtureNames @("mir-fixture-assert-native-owner-cap-transition") `
              -InitialNativeOwnerSettingsProfile "default" `
              -ChangedNativeOwnerSettingsProfile "max-level" `
              -EnableSpaceAge
            Assert-LogContains -Expected "[mir-fixture] native-owner lowered cap retained completed levels and removed invalid current/queued research" -Context $declaration.name
          }
          "space-age-native-owner-cap-raising-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
              -ChangedFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
              -InitialStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 5 } `
              -ChangedStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 7 } `
              -EnableSpaceAge
            Assert-LogContains -Expected "[mir-fixture] native-owner relaxed cap retained valid progress and restored future levels changed=7" -Context $declaration.name
          }
          "space-age-native-owner-cap-removal-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
              -ChangedFixtureNames @("mir-fixture-assert-native-owner-cap-relaxation") `
              -InitialStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 5 } `
              -ChangedStartupSettingOverrides @{ "ips-max-level-research_processing_unit" = 0 } `
              -EnableSpaceAge
            Assert-LogContains -Expected "[mir-fixture] native-owner relaxed cap retained valid progress and restored future levels changed=0" -Context $declaration.name
          }
          "space-age-vanilla-family-adoption-config-change" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -ChangedFixtureNames @("mir-fixture-vanilla-family-adoption-recipes") `
              -EnableSpaceAge
            Assert-LogContains -Expected "Preserved technology effects without a force-wide reset for productivity family adoption signature change" -Context $declaration.name
            Assert-LogContains -Expected "schema=4|stream=research_rocket_fuel|owner=rocket-fuel-productivity|operation=adopt_native_owner_effects|configured=|effects=1|input-cost=" -Context $declaration.name
          }
          "space-age-scripted-runtime-lifecycle" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
              -ChangedFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
              -EnabledStreamKeys @("research_spoilage_preservation") `
              -EffectPerLevelOverrides @{ research_spoilage_preservation = 2 } `
              -ScriptedDiagnostics `
              -EnableSpaceAge
            Assert-LogContains -Expected "[mir-fixture] scripted lifecycle retention proof complete" -Context $declaration.name
          }
          "space-age-scripted-runtime-disable-restoration" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
              -ChangedFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
              -InitialEnabledStreamKeys @("research_spoilage_preservation") `
              -ChangedDisabledStreamKeys @("research_spoilage_preservation") `
              -EffectPerLevelOverrides @{ research_spoilage_preservation = 2 } `
              -ScriptedDiagnostics `
              -EnableSpaceAge
            Assert-LogContains -Expected "[mir-fixture] scripted lifecycle disable proof complete" -Context $declaration.name
          }
          "space-age-scripted-runtime-reenable" {
            Invoke-RuntimeConfigurationChangeScenario `
              -ScenarioName $declaration.name `
              -InitialFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
              -ChangedFixtureNames @("mir-fixture-assert-scripted-runtime-lifecycle") `
              -InitialDisabledStreamKeys @("research_spoilage_preservation") `
              -ChangedEnabledStreamKeys @("research_spoilage_preservation") `
              -EffectPerLevelOverrides @{ research_spoilage_preservation = 2 } `
              -ScriptedDiagnostics `
              -EnableSpaceAge
            Assert-LogContains -Expected "[mir-fixture] scripted lifecycle enable proof complete" -Context $declaration.name
          }
          default {
            throw "Selected validation has no configuration-change executor for $($declaration.name)."
          }
        }
      } else {
        throw "Selected validation currently requires a manifest-driven runtime or package scenario: $($declaration.name)"
      }
    }
    }
    Complete-MIRValidationRun
    Remove-MIRGeneratedValidationUserData
    Write-Host "[ok] Selected validation completed."
    $global:LASTEXITCODE = 0
    return
  } catch {
    Fail-MIRValidationRun -ErrorMessage $_.Exception.Message
    throw
  }
}

try {
  if (-not $checkpointActive) {
    $validationCampaignCompleted = $false
    . (Join-Path $runnerModuleRoot "DefaultCampaign00.ps1")
    if ($validationCampaignCompleted) { return }
    . (Join-Path $runnerModuleRoot "DefaultCampaign01.ps1")
    . (Join-Path $runnerModuleRoot "DefaultCampaign02.ps1")
    . (Join-Path $runnerModuleRoot "DefaultCampaign03.ps1")
  } else {
    Write-Host "[resume] Starting full-assertion validation at $StartAtScenario."
  }
  . (Join-Path $runnerModuleRoot "CheckpointCampaign.ps1")
  . (Join-Path $runnerModuleRoot "FinalCampaign.ps1")

  Complete-MIRValidationRun
  Remove-MIRGeneratedValidationUserData

  Write-Host "[ok] Validation completed."
  $global:LASTEXITCODE = 0
} catch {
  Fail-MIRValidationRun -ErrorMessage $_.Exception.Message
  throw
}
