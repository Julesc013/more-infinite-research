Invoke-RepoCheck "compat audit automation tooling is wired" {
  $compatAuditText = @(
    Get-Content -Raw -LiteralPath (Join-Path $repo "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1")
    Get-ChildItem -LiteralPath (Join-Path $repo "tools\commands\compatibility\compat-audit") -File -Filter "*.ps1" |
      Sort-Object Name |
      ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
  ) -join "`n"
  $extendedTestsText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1")
  $converterText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1")
  $modPortalText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\compatibility\ModPortal.ps1")
  $dependencyResolverText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\compatibility\DependencyResolver.ps1")
  $diagnosticsParserText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\compatibility\DiagnosticsParser.ps1")
  $stubText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\commands\compatibility\New-MIRCompatProfileStub.ps1")
  $runnerText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\compatibility\FactorioRunner.ps1")
  $releaseTargetedGateText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRReleaseTargetedGate.ps1")
  $localCatalogGateText = Get-Content -Raw -LiteralPath (Join-Path $repo "tests\compatibility\Test-MIRLocalModLibraryCatalog.ps1")
  $mirCliText = @(
    Get-Content -Raw -LiteralPath (Join-Path $repo "tools\mir.ps1")
    Get-Content -Raw -LiteralPath (Join-Path $repo "tools\mir\cli\Invoke-MIRCommandRouter.ps1")
  ) -join "`n"
  $consoleText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\cli\Console.ps1")
  $runContextText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\cli\RunContext.ps1")
  $eventLogText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\cli\EventLog.ps1")
  $processSupervisorText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\cli\ProcessSupervisor.ps1")
  $localModIndexText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\lib\cli\LocalModIndex.ps1")
  $powershellQualityText = Get-Content -Raw -LiteralPath (Join-Path $repo "tests\tooling\Test-MIRPowerShellQuality.ps1")
  $runProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\release-targeted.json")
  $localAuditProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\local-audit-2.1.json")
  $releaseTargeted20ProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\release-targeted-2.0.json")
  $overnight20ProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\overnight-local-2.0.json")
  $localAudit20ProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\local-audit-2.0.json")
  $overnightText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Start-MIROvernightLocalSweep.ps1")
  $overnightSummaryText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Show-MIROvernightSummary.ps1")
  $manualScenariosText = Get-Content -Raw -LiteralPath (Join-Path $repo "validation\scenarios\manual.json")
  $localLibraryScenariosText = Get-Content -Raw -LiteralPath (Join-Path $repo "validation\scenarios\local-2.1.json")
  $localLibraryScenarios20Text = Get-Content -Raw -LiteralPath (Join-Path $repo "validation\scenarios\local-2.0.json")
  $expectedFailuresText = Get-Content -Raw -LiteralPath (Join-Path $repo "validation\assertions\expected-failures.json")
  $workflowText = Get-Content -Raw -LiteralPath (Join-Path $repo ".github\workflows\extended-compat-audit.yml")
  $validateWorkflowText = Get-Content -Raw -LiteralPath (Join-Path $repo ".github\workflows\validate.yml")
  $emergencyPackageWorkflowText = Get-Content -Raw -LiteralPath (Join-Path $repo ".github\workflows\emergency-package.yml")
  $compatDocsText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\compatibility\README.md")
  $devToolsText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\maintainer\developer-tools.md")
  $readmeText = Get-Content -Raw -LiteralPath (Join-Path $repo "README.md")

  $requiredSnippets = @(
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$RunManualScenarios" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string]`$FromLockfile" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[int]`$StartIndex = 0" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string[]]`$CandidateNames = @()" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[int]`$ScenarioTimeoutSeconds = 900" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$ContinueOnDependencyFailure" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string[]]`$LocalModZipDirs = @()" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string[]]`$LocalModLibraryDirs = @()" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string]`$ModUnderTestZip = `"`"" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string]`$ModUnderTestSourceCommit = `"`"" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'kind = "mir-modpack-campaign-evidence"' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'dependencyFailureCount -le $maximumDependencyFailures' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'process_result = $processResult' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Campaign evidence requires SHA-256" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$RunLocalModZips" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$RunGeneratedLocalScenarios" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$GenerateLocalClusterScenarios" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[int]`$GeneratedLocalPairwiseLimit = 40" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$Offline" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string]`$FactorioLine = `"`"" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Get-MIROfficialBuiltinFullMods" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Add-MIROfficialBuiltinDependencyClosure" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Get-MIRUnavailableOfficialMods" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "ConvertTo-MIRLocalFullMod" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Add-MIRLocalFullModToIndex" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "New-MIRGeneratedLocalScenarioDefinitions" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "local_library_zip_count" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "generated_local_scenarios_selected" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "local_zip_scenarios_selected" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = '$resolvedOutputDir = [IO.Path]::GetFullPath($OutputDir)' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = '$resolvedOutputDir = New-MIRDirectory -Path $resolvedOutputDir' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "`$loadResultsPath = Join-Path `$resolvedOutputDir `"load-results.json`"" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'if ($enabled.ContainsKey("space-age"))' },
    @{ File = "scripts\Invoke-MIRValidation.ps1"; Text = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRValidation.ps1"); Snippet = 'not $relative.StartsWith("build/results/")' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "skip_reason = `"dependency_resolution_failure`"" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Invoke-MIRScenarioLoad" },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'tools\lib\validation\SettingsOverrides.ps1' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'Initialize-MIRSettingsOverrideMod -ModsDir $modsDir -FactorioVersion $FactorioLine' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'Enable-CopiedDiagnostics -ModsDir $modsDir' },
    @{ File = "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = '"mir-validation-settings-overrides"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "Get-MIRSafeScenarioFileName" },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "[int]`$ScenarioTimeoutSeconds = 900" },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "Stop-Process -Id `$process.Id -Force" },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"--config", $configPath' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "write-data=`$UserDataDir" },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "source_path" },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '[string]$ZipPath = ""' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"artifacts"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"build"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"dist"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"fixtures"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"scripts"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"tests"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"tmp"' },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "[string[]]`$OfficialBuiltinMods" },
    @{ File = "tools\lib\compatibility\FactorioRunner.ps1"; Text = $runnerText; Snippet = "enabled = `$enabledLookup.ContainsKey" },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $localLibraryScenariosText; Snippet = "local-2-1-crucible-rigor-exact-dist" },
    @{ File = "tools\lib\compatibility\ModPortal.ps1"; Text = $modPortalText; Snippet = '\s+(?:>=|<=|=|>|<)\s*\d' },
    @{ File = "tools\lib\compatibility\DependencyResolver.ps1"; Text = $dependencyResolverText; Snippet = "[switch]`$IncludeRecommendedDependencies" },
    @{ File = "tools\lib\compatibility\DiagnosticsParser.ps1"; Text = $diagnosticsParserText; Snippet = "[AllowEmptyString()][string]`$Line" },
    @{ File = "tools\lib\compatibility\DiagnosticsParser.ps1"; Text = $diagnosticsParserText; Snippet = "IsNullOrWhiteSpace(`$line)" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[string]`$FromLockfile" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[string]`$FactorioLine = `"2.1`"" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "local-2.0.json" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = '"LocalModZips"' },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = '"LocalLibraryScenarios"' },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = '"GeneratedLocalScenarios"' },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[string[]]`$LocalModZipDirs = @()" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[string[]]`$LocalModLibraryDirs = @()" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[switch]`$ShardLocalModZips" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[switch]`$IncludeGeneratedLocalPairwise" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[switch]`$Offline" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[int]`$ScenarioTimeoutSeconds = 900" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[switch]`$FailOnAuditFailures" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[switch]`$CollectAll" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "Assert-MIRNoAuditFailures" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "ManualScenariosPath" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "base-baseline" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "space-age-baseline" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[switch]`$IncludeFullAudit" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = '"ManualScenarios"' },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "Convert-MIRCompatAuditResults.ps1" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "compat-failures.grouped.json" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "profile-candidates.json" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "compat-observations.json" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "recipe_cap" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "compatibility_role" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "missing-dependencies.md" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "missing_dependency_count" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "unexpected_count" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "expected_failures" },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = '"timeout"' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "known_competitor_not_replaced" },
    @{ File = "tools\commands\compatibility\New-MIRCompatProfileStub.ps1"; Text = $stubText; Snippet = "Review and refine this stub before enabling" },
    @{ File = "tools\commands\compatibility\New-MIRCompatProfileStub.ps1"; Text = $stubText; Snippet = "require_review = true" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "strict-current-commit-gate" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "targeted-repair-local-zips" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "representative-local-scenario" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "Assert-MIRReleaseGateNoUnexpectedFailures" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "release-targeted-summary.md" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "FactorioLine" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = 'RepairSmokeModNames' },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = 'RepresentativeScenarioName' },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = 'AuditFactorioVersions' },
    @{ File = "tests\compatibility\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = '[Parameter(Mandatory)][string[]]$LocalModLibraryDirs' },
    @{ File = "tests\compatibility\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = 'Read-MIRModInfoFromZip' },
    @{ File = "tests\compatibility\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = 'missing_scenario_mod_count' },
    @{ File = "tests\compatibility\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = 'AllowMissingScenarioMods' },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = ".\tools\mir.ps1 release gate" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "Invoke-MIRRunProfile" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "--factorio-line" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "factorio_line" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "local-audit-2.1" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "report observations" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "New-MIRProfileOverrides" },
    @{ File = "tools\mir.ps1"; Text = $mirCliText; Snippet = "local-index" },
    @{ File = "tests\tooling\Test-MIRPowerShellQuality.ps1"; Text = $powershellQualityText; Snippet = "duplicate parameter" },
    @{ File = "tests\tooling\Test-MIRPowerShellQuality.ps1"; Text = $powershellQualityText; Snippet = "possible secret output" },
    @{ File = "scripts\Invoke-MIRValidation.ps1"; Text = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRValidation.ps1"); Snippet = "Test-MIRPowerShellQuality.ps1" },
    @{ File = "tools\lib\cli\Console.ps1"; Text = $consoleText; Snippet = "Write-MIRScenarioResult" },
    @{ File = "tools\lib\cli\RunContext.ps1"; Text = $runContextText; Snippet = "run-manifest.json" },
    @{ File = "tools\lib\cli\EventLog.ps1"; Text = $eventLogText; Snippet = "events.jsonl" },
    @{ File = "tools\lib\cli\ProcessSupervisor.ps1"; Text = $processSupervisorText; Snippet = "Invoke-MIRProcess" },
    @{ File = "tools\lib\cli\LocalModIndex.ps1"; Text = $localModIndexText; Snippet = "New-MIRLocalModIndex" },
    @{ File = "fixtures\run-profiles\release-targeted.json"; Text = $runProfileText; Snippet = '"kind": "release-targeted"' },
    @{ File = "fixtures\run-profiles\release-targeted-2.0.json"; Text = $releaseTargeted20ProfileText; Snippet = '"factorio_line": "2.0"' },
    @{ File = "fixtures\run-profiles\overnight-local-2.0.json"; Text = $overnight20ProfileText; Snippet = '"factorio_line": "2.0"' },
    @{ File = "fixtures\run-profiles\local-audit-2.0.json"; Text = $localAudit20ProfileText; Snippet = '"factorio_line": "2.0"' },
    @{ File = "fixtures\run-profiles\local-audit-2.1.json"; Text = $localAuditProfileText; Snippet = '"LocalModZips"' },
    @{ File = "fixtures\run-profiles\local-audit-2.1.json"; Text = $localAuditProfileText; Snippet = '"local_mod_library_dirs"' },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = '$ErrorActionPreference = "Stop"' },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "[string]`$FactorioLine = `"2.1`"" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "testmods_`$FactorioLine" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "[switch]`$DryRun" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "Start-Transcript" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "LocalLibraryScenarios" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "GeneratedLocalScenarios" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "LocalModZips" },
    @{ File = "scripts\Start-MIROvernightLocalSweep.ps1"; Text = $overnightText; Snippet = "Show-MIROvernightSummary.ps1" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "compat-failures.grouped.json" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "compat-observations.json" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "missing-dependencies.csv" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "profile-candidates.json" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "Group-Object mod" },
    @{ File = "validation\scenarios\manual.json"; Text = $manualScenariosText; Snippet = '"space-age-planet-cluster"' },
    @{ File = "validation\scenarios\manual.json"; Text = $manualScenariosText; Snippet = '"base-baseline"' },
    @{ File = "validation\scenarios\manual.json"; Text = $manualScenariosText; Snippet = '"bob-angels"' },
    @{ File = "validation\scenarios\manual.json"; Text = $manualScenariosText; Snippet = '"include_space_age"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-space-age-mega-smash"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-bz-suite-space-age"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-krastorio-space-exploration"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-planet-pack-wrapper-full"' },
    @{ File = "validation\scenarios\local-2.0.json"; Text = $localLibraryScenarios20Text; Snippet = '"local-2-0-base-baseline"' },
    @{ File = "validation\scenarios\local-2.0.json"; Text = $localLibraryScenarios20Text; Snippet = '"local-2-0-bob-angels"' },
    @{ File = "validation\assertions\expected-failures.json"; Text = $expectedFailuresText; Snippet = '"expected_failures"' },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "runs-on: self-hosted" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "Invoke-MIRExtendedTests.ps1" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = '$params = @{' },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "fail_on_audit_failures" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "local_mod_library_dirs" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "offline" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "include_generated_local_pairwise" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "shard_local_mod_zips" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "scenario_timeout_seconds" },
    @{ File = ".github\workflows\validate.yml"; Text = $validateWorkflowText; Snippet = "github.ref == 'refs/heads/tmp/2.0'" },
    @{ File = ".github\workflows\validate.yml"; Text = $validateWorkflowText; Snippet = "github.head_ref == 'tmp/2.0'" },
    @{ File = ".github\workflows\validate.yml"; Text = $validateWorkflowText; Snippet = "github.base_ref == 'tmp/2.0'" },
    @{ File = ".github\workflows\validate.yml"; Text = $validateWorkflowText; Snippet = "--target `$env:MIR_VALIDATION_TARGET" },
    @{ File = ".github\workflows\emergency-package.yml"; Text = $emergencyPackageWorkflowText; Snippet = 'throw "First package build failed: $($_.Exception.Message)"' },
    @{ File = ".github\workflows\emergency-package.yml"; Text = $emergencyPackageWorkflowText; Snippet = 'throw "Second package build failed: $($_.Exception.Message)"' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Manual scenarios can now be executed with `-RunManualScenarios`' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Local modpack zips can be supplied with `-LocalModZipDirs`' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Local dependency libraries can be supplied separately with `-LocalModLibraryDirs`' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = '`Start-MIROvernightLocalSweep.ps1` is the preferred bedtime command' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = '`GeneratedLocalScenarios` creates scenarios from local zip metadata' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Test-MIRLocalModLibraryCatalog.ps1' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'The grouped converter writes `missing-dependencies.md`' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Do not mix Factorio lines unintentionally.' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Sharded or resumed audits can use `-FromLockfile`, `-StartIndex`, `-Count`, and `-CandidateNames`' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = 'Use `-CollectAll` for exploratory or overnight runs.' },
    @{ File = "docs\compatibility\README.md"; Text = $compatDocsText; Snippet = '`AuditSmoke` is intentionally deterministic.' },
    @{ File = "README.md"; Text = $readmeText; Snippet = ".\scripts\Invoke-MIRReleaseTargetedGate.ps1" },
    @{ File = "README.md"; Text = $readmeText; Snippet = (".\scripts" + "\mir.ps1 audit local") },
    @{ File = "README.md"; Text = $readmeText; Snippet = "docs/maintainer/developer-tools.md" },
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "Preferred Commands" },
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "tools/lib/cli/*.ps1" },
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "Test-MIRPowerShellQuality.ps1" }
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "Test-MIRLocalModLibraryCatalog.ps1" }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing compatibility audit automation wiring in $($check.File): $($check.Snippet)"
    }
  }
  if ($validateWorkflowText.Contains("refs/heads/legacy")) {
    throw "The movable legacy terminal alias must use the Factorio 2.1 validation role; only tmp/2.0 selects Factorio 2.0."
  }
}
