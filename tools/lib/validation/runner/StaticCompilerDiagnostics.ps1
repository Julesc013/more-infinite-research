Invoke-RepoCheck "2.2.0 compiler diagnostics are wired" {
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $dataFinalFixesStagePath = Join-Path $repo "prototypes\mir\stage\data_final_fixes.lua"
  $diagnosticsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\report\diagnostics_sink.lua")
  $indexRegistryPath = Join-Path $repo "prototypes\mir\index\registry_builder.lua"
  $capabilityRegistryPath = Join-Path $repo "prototypes\mir\capabilities\registry.lua"
  $capabilityContractPath = Join-Path $repo "prototypes\mir\capabilities\contract.lua"
  $capabilityPolicyPath = Join-Path $repo "prototypes\mir\policy\capabilities.lua"
  $schemaPath = Join-Path $repo "prototypes\mir\core\schema.lua"
  $compilerDiagnosticsPath = Join-Path $repo "prototypes\mir\report\compiler_diagnostics.lua"
  $pipelineCommandsPath = Join-Path $repo "prototypes\mir\pipeline\commands.lua"
  $converterText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1")
  $overnightSummaryText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Show-MIROvernightSummary.ps1")
  $compatPlannerText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\planner.lua")
  $policyLintText = Get-Content -Raw -LiteralPath (Join-Path $repo "tests\tooling\Test-MIRPolicyLints.ps1")

  if (-not (Test-Path -LiteralPath $indexRegistryPath)) {
    throw "Missing MIR index registry builder: prototypes\mir\index\registry_builder.lua"
  }
  if (-not (Test-Path -LiteralPath $capabilityRegistryPath)) {
    throw "Missing capability registry: prototypes\mir\capabilities\registry.lua"
  }
  foreach ($path in @(
      $dataFinalFixesStagePath,
      $compilerDiagnosticsPath,
      $pipelineCommandsPath,
      $capabilityContractPath,
      $capabilityPolicyPath,
      $schemaPath
    )) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Missing 2.2.0 capability kernel artifact: $path"
    }
  }

  $indexRegistryText = Get-Content -Raw -LiteralPath $indexRegistryPath
  $decisionRecordText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\domain\decisions\decision_record.lua")
  $decisionExportText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\report\decision_export.lua")
  $coverageReportText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\report\coverage.lua")
  $capabilityRegistryText = Get-Content -Raw -LiteralPath $capabilityRegistryPath
  $capabilityContractText = Get-Content -Raw -LiteralPath $capabilityContractPath
  $capabilityPolicyText = Get-Content -Raw -LiteralPath $capabilityPolicyPath
  $schemaText = Get-Content -Raw -LiteralPath $schemaPath
  $compilerDiagnosticsText = Get-Content -Raw -LiteralPath $compilerDiagnosticsPath
  $pipelineCommandsText = Get-Content -Raw -LiteralPath $pipelineCommandsPath
  $dataFinalFixesStageText = Get-Content -Raw -LiteralPath $dataFinalFixesStagePath

  $requiredSnippets = @(
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.stage.data_final_fixes").run()' },
    @{ File = "prototypes\mir\stage\data_final_fixes.lua"; Text = $dataFinalFixesStageText; Snippet = 'commands.run_all({return_snapshot = false})' },
    @{ File = "prototypes\mir\pipeline\commands.lua"; Text = $pipelineCommandsText; Snippet = 'require("prototypes.mir.report.compiler_diagnostics").emit()' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = 'function D.decision(row)' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = 'schema.decision(row)' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = '.. " capability=" .. tostring(row.capability or "")' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = '.. " evidence=" .. tostring(row.evidence or "")' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = 'append("rule_mutation", row)' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = 'append("loop_risk", row)' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = 'append("lab_matrix", row)' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'RecipeFact' },
    @{ File = "prototypes\mir\index\recipe_facts.lua"; Text = (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\index\recipe_facts.lua")); Snippet = 'productive_result_names' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'RuleMutationFact' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'schema = schema.fact_registry' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'build_loop_risk_facts' },
    @{ File = "prototypes\mir\domain\decisions\decision_record.lua"; Text = $decisionRecordText; Snippet = 'function M.generated_technology(record)' },
    @{ File = "prototypes\mir\domain\decisions\decision_record.lua"; Text = $decisionRecordText; Snippet = 'schema.decision({' },
    @{ File = "prototypes\mir\report\decision_export.lua"; Text = $decisionExportText; Snippet = 'function M.emit(sink, record)' },
    @{ File = "prototypes\mir\report\decision_export.lua"; Text = $decisionExportText; Snippet = 'sink.decision(record)' },
    @{ File = "prototypes\mir\report\coverage.lua"; Text = $coverageReportText; Snippet = 'kind = "mir-coverage-report"' },
    @{ File = "prototypes\mir\report\coverage.lua"; Text = $coverageReportText; Snippet = 'accounted_recipes = #facts.names' },
    @{ File = "prototypes\mir\report\coverage.lua"; Text = $coverageReportText; Snippet = 'technology_effect_count' },
    @{ File = "prototypes\mir\core\schema.lua"; Text = $schemaText; Snippet = 'S.decision_record = 2' },
    @{ File = "prototypes\mir\capabilities\contract.lua"; Text = $capabilityContractText; Snippet = 'CapabilityResolver' },
    @{ File = "prototypes\mir\capabilities\contract.lua"; Text = $capabilityContractText; Snippet = '"discover"' },
    @{ File = "prototypes\mir\policy\capabilities.lua"; Text = $capabilityPolicyText; Snippet = 'P.schema_version = schema.capability_policy' },
    @{ File = "prototypes\mir\policy\capabilities.lua"; Text = $capabilityPolicyText; Snippet = 'deny_risk_flags' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'Capability resolvers are report-first' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'contract.validate_all(RESOLVERS)' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'schema_version = schema.capability_resolver' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'id = "logistics-loader-manufacturing"' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'id = "mining-drill-manufacturing"' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'id = "native-modifier-ownership"' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'canonical_provider_decision_projection' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'planner_decision_fingerprint = row.decision_fingerprint' },
    @{ File = "prototypes\mir\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'discover,classify,propose,validate,materialize,result' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'local decision_export = require("prototypes.mir.report.decision_export")' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'require("prototypes.mir.index.registry_builder")' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'D.fact_registry({' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'decision_export.emit(D, {' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'decision_export.emit(D, decision_record.generated_technology({' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'emit_generated_technology_decisions' },
    @{ File = "prototypes\mir\report\compiler_diagnostics.lua"; Text = $compilerDiagnosticsText; Snippet = 'capabilities.emit(registry)' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = 'useful_level_estimate = levels' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["atan-ash"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["atan-nuclear-science"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["FluidMustFlow"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["robot_attrition"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["jetpack"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["big-mining-drill"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["equipment-gantry"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["aai-industry"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["aai-containers"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = '["aai-loaders"] = {' },
    @{ File = "prototypes\mir\compatibility\planner.lua"; Text = $compatPlannerText; Snippet = 'belt_productivity_loader_recipe_candidate' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = '"fact_registry", "decision", "rule_mutation", "loop_risk", "lab_matrix"' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = 'capability = [string](Get-MIRObjectProperty -Object $row -Name "capability")' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = '## Capability Decisions' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "Loop Risk Diagnostics" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "rule_surfaces" },
    @{ File = "tests\tooling\Test-MIRPolicyLints.ps1"; Text = $policyLintText; Snippet = "Generated stream manifest row" }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing 2.2.0 compiler diagnostics wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "Air Scrubbing clean-filter policy is wired" {
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $productivityText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\productivity.lua")
  $scienceSelectorText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\capabilities\science_integration\science_selector.lua")
  $plannerPrerequisitesText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\prerequisites.lua")
  $diagnosticsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\report\diagnostics_sink.lua")
  $converterText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1")
  $exactRecipePolicyPath = Join-Path $repo "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"
  $airScrubbingDiagnosticsPath = Join-Path $repo "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"
  $atanAshDiagnosticsPath = Join-Path $repo "prototypes\mir\compatibility\diagnostics\atan_ash.lua"
  $compatibilityDiagnosticsReportPath = Join-Path $repo "prototypes\mir\report\compatibility_diagnostics.lua"
  $manifestPath = Join-Path $repo "prototypes\mir\streams\generated_stream_manifest.json"
  $fixturePath = Join-Path $repo "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"

  foreach ($path in @($exactRecipePolicyPath, $airScrubbingDiagnosticsPath, $atanAshDiagnosticsPath, $compatibilityDiagnosticsReportPath, $manifestPath, $fixturePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Missing Air Scrubbing policy artifact: $path"
    }
  }

  $exactRecipePolicyText = Get-Content -Raw -LiteralPath $exactRecipePolicyPath
  $airScrubbingDiagnosticsText = Get-Content -Raw -LiteralPath $airScrubbingDiagnosticsPath
  $atanAshDiagnosticsText = Get-Content -Raw -LiteralPath $atanAshDiagnosticsPath
  $compatibilityDiagnosticsReportText = Get-Content -Raw -LiteralPath $compatibilityDiagnosticsReportPath
  $manifestText = Get-Content -Raw -LiteralPath $manifestPath
  $fixtureText = Get-Content -Raw -LiteralPath $fixturePath

  $requiredSnippets = @(
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.compatibility.diagnostics.registry").emit_all()' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_air_scrubbing_clean_filter = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'science_packs = "derive-from-unlocks"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'prerequisites = "derive-from-unlocks"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'manifest_id = air_scrubbing_capability.stream.id' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'exact_recipe_patterns(air_scrubbing_capability.exact_recipes)' },
    @{ File = "prototypes\mir\capabilities\science_integration\science_selector.lua"; Text = $scienceSelectorText; Snippet = 'local function science_from_unlocks(key, spec)' },
    @{ File = "prototypes\mir\planner\prerequisites.lua"; Text = $plannerPrerequisitesText; Snippet = 'if spec.prerequisites == "derive-from-unlocks" then' },
    @{ File = "prototypes\mir\report\diagnostics_sink.lua"; Text = $diagnosticsText; Snippet = '.. " rejected=" .. tostring(row.rejected or "")' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = 'rejected = [string](Get-MIRObjectProperty -Object $row -Name "rejected")' },
    @{ File = "tools\commands\compatibility\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = 'generated,rejected,unknown,missing,module_slots' },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = $exactRecipePolicyText; Snippet = 'require("prototypes.mir.platform.factorio.data_raw")' },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = $exactRecipePolicyText; Snippet = 'require("prototypes.mir.report.compatibility_diagnostics")' },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = $exactRecipePolicyText; Snippet = 'overlay_loader.get(config.overlay_id)' },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = $exactRecipePolicyText; Snippet = 'local stream = capability.stream' },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = $exactRecipePolicyText; Snippet = 'local allowed_recipes = capability.exact_recipes or {}' },
    @{ File = "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"; Text = $exactRecipePolicyText; Snippet = 'decision = emitted and "generate_stream" or "diagnose_only"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'overlay_id = "air-scrubbing"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'allowed_generated_reason = "clean_filter_stream_emitted"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'reason = "environmental_removal_loop"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'risk = "scrubbing_environmental"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'reason = "recovery_loop"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'risk = "cleaning_recovery"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"; Text = $airScrubbingDiagnosticsText; Snippet = 'decision = "observe_unknown"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\atan_ash.lua"; Text = $atanAshDiagnosticsText; Snippet = 'overlay_id = "atan-ash"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\atan_ash.lua"; Text = $atanAshDiagnosticsText; Snippet = 'allowed_generated_reason = "ash_separation_stream_emitted"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\atan_ash.lua"; Text = $atanAshDiagnosticsText; Snippet = 'reason = "tile_surface_outside_stream"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\atan_ash.lua"; Text = $atanAshDiagnosticsText; Snippet = 'risk = "tile_surface"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\atan_ash.lua"; Text = $atanAshDiagnosticsText; Snippet = 'reason = "ash_sink_outside_stream"' },
    @{ File = "prototypes\mir\compatibility\diagnostics\atan_ash.lua"; Text = $atanAshDiagnosticsText; Snippet = 'risk = "ash_sink"' },
    @{ File = "prototypes\mir\report\compatibility_diagnostics.lua"; Text = $compatibilityDiagnosticsReportText; Snippet = 'decision_export.emit(sink, row)' },
    @{ File = "prototypes\mir\report\compatibility_diagnostics.lua"; Text = $compatibilityDiagnosticsReportText; Snippet = 'sink.compatibility_plan(row)' },
    @{ File = "prototypes\mir\streams\generated_stream_manifest.json"; Text = $manifestText; Snippet = '"mir-prod-air-scrubbing-clean-filter"' },
    @{ File = "prototypes\mir\streams\generated_stream_manifest.json"; Text = $manifestText; Snippet = '"source": "compat_policy:air-scrubbing"' },
    @{ File = "prototypes\mir\streams\generated_stream_manifest.json"; Text = $manifestText; Snippet = '"atan-pollution-filter"' },
    @{ File = "prototypes\mir\streams\generated_stream_manifest.json"; Text = $manifestText; Snippet = '"atan-spore-filter"' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $fixtureText; Snippet = 'atan-pollution-scrubbing' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $fixtureText; Snippet = 'atan-filter-resin' }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing Air Scrubbing clean-filter wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "ATAN Factorio 2.1 schema repairs are wired" {
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $repairPath = Join-Path $repo "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"
  $modulesText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\modules.yml")
  $compatibilityManifestText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\compatibility.yml")
  $atanAshDocText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\compatibility\targets\atan-ash.md")
  $atanNuclearDocText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\compatibility\targets\atan-nuclear-science.md")

  if (-not (Test-Path -LiteralPath $repairPath)) {
    throw "Missing ATAN Factorio 2.1 schema repair module: $repairPath"
  }

  $repairText = Get-Content -Raw -LiteralPath $repairPath
  $requiredSnippets = @(
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.compatibility.repairs.registry").apply()' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '["atan-ash"]' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '["2.2.1"] = true' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '"atan-landfill-from-ash"' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '"atan-ash-seperation"' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = 'product.independent_probability = product.probability' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = 'product.probability = nil' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '["atan-nuclear-science"]' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '["0.3.3"] = true' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '"automation-science-pack"' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '"fission-reactor-equipment"' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '"nuclear-science-pack"' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = '"uranium-rounds-magazine"' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = 'recipe.categories = categories' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = 'recipe.category = nil' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = 'recipe.additional_categories = nil' },
    @{ File = "prototypes\mir\compatibility\repairs\factorio_2_1_recipe_schema.lua"; Text = $repairText; Snippet = 'D.rule_mutation({' },
    @{ File = ".mir\modules.yml"; Text = $modulesText; Snippet = "prototypes/mir/compatibility/repairs/factorio_2_1_recipe_schema.lua" },
    @{ File = ".mir\compatibility.yml"; Text = $compatibilityManifestText; Snippet = "factorio_2_1_recipe_schema:atan-ash_2.2.1" },
    @{ File = ".mir\compatibility.yml"; Text = $compatibilityManifestText; Snippet = "factorio_2_1_recipe_schema:atan-nuclear-science_0.3.3" },
    @{ File = "docs\compatibility\targets\atan-ash.md"; Text = $atanAshDocText; Snippet = 'exact-version Factorio `2.1` loader-schema repair' },
    @{ File = "docs\compatibility\targets\atan-nuclear-science.md"; Text = $atanNuclearDocText; Snippet = 'exact-version Factorio `2.1` loader-schema repair' }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing ATAN Factorio 2.1 schema repair wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "Corrundum Factorio 2.1 ambient-sound schema repair is bounded and governed" {
  $registryText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\repairs\registry.lua")
  $repairText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\repairs\factorio_2_1_ambient_sound_schema.lua")
  $modulesText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\modules.yml")
  $compatibilityText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\compatibility.yml")
  $docsText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\docs.yml")
  $targetDocText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\compatibility\targets\corrundum.md")
  $scenarioText = Get-Content -Raw -LiteralPath (Join-Path $repo "validation\scenarios\local-2.1.json")
  $testImpactText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\test-impact.yml")
  $sanitationBudgetText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\sanitation-budgets.json")
  $compatAuditText = Get-Content -Raw -LiteralPath (Join-Path $repo "tools\commands\compatibility\Invoke-MIRCompatAudit.ps1")
  foreach ($check in @(
    @{ File = "registry.lua"; Text = $registryText; Snippet = 'require("prototypes.mir.compatibility.repairs.factorio_2_1_ambient_sound_schema").apply()' },
    @{ File = "factorio_2_1_ambient_sound_schema.lua"; Text = $repairText; Snippet = '["1.0.47"] = true' },
    @{ File = "factorio_2_1_ambient_sound_schema.lua"; Text = $repairText; Snippet = 'sound.planets = {sound.planet}' },
    @{ File = "factorio_2_1_ambient_sound_schema.lua"; Text = $repairText; Snippet = 'sound.planet = nil' },
    @{ File = "factorio_2_1_ambient_sound_schema.lua"; Text = $repairText; Snippet = 'D.rule_mutation({' },
    @{ File = ".mir\modules.yml"; Text = $modulesText; Snippet = 'prototypes/mir/compatibility/repairs/factorio_2_1_ambient_sound_schema.lua' },
    @{ File = ".mir\compatibility.yml"; Text = $compatibilityText; Snippet = 'factorio_2_1_ambient_sound_schema:corrundum_1.0.47' },
    @{ File = ".mir\compatibility.yml"; Text = $compatibilityText; Snippet = 'exact_real_roots: [PlanetsLib, corrundum]' },
    @{ File = ".mir\docs.yml"; Text = $docsText; Snippet = 'docs/compatibility/targets/corrundum.md' },
    @{ File = "docs\compatibility\targets\corrundum.md"; Text = $targetDocText; Snippet = 'exact-version Factorio `2.1` loader-schema repair' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $scenarioText; Snippet = '"name": "local-2-1-corrundum-maxcap-13"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $scenarioText; Snippet = '"PlanetsLib"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $scenarioText; Snippet = '"required_log_fragments"' },
    @{ File = "validation\scenarios\local-2.1.json"; Text = $scenarioText; Snippet = '"Maximum-level conflict"' },
    @{ File = "Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = '$runtimeContractPassed' },
    @{ File = "Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'required_audit_assertions = $requiredAuditAssertions' },
    @{ File = ".mir\test-impact.yml"; Text = $testImpactText; Snippet = '"scenarios": ["local-2-1-corrundum-maxcap-13", "local-2-1-cubium-production-routes"]' },
    @{ File = ".mir\sanitation-budgets.json"; Text = $sanitationBudgetText; Snippet = '"local-2-1-corrundum-maxcap-13": {"expected_external_prunes": [], "maximum_unreviewed_external_prunes": 0}' }
  )) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing governed Corrundum ambient-sound schema repair wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "schema-3 MaximumLevelBinding is the governed cross-route cap authority" {
  $bindingText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\domain\technology\maximum_level_binding.lua")
  $orchestratorText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\pipeline\compiler_orchestrator.lua")
  $presentationText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\pipeline\mutations\maximum_level_presentation.lua")
  $runtimeText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\runtime\maximum_level_control.lua")
  $modDataText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\emit\mod_data.lua")
  $fixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-compiler-contracts\data-final-fixes.lua")
  $modulesText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\modules.yml")
  $compatibilityText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\compatibility.yml")
  $docsText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\docs.yml")
  $contractDocText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\reference\maximum-level-binding.md")
  foreach ($check in @(
    @{ File = "maximum_level_binding.lua"; Text = $bindingText; Snippet = 'local SCHEMA = 3' },
    @{ File = "maximum_level_binding.lua"; Text = $bindingText; Snippet = 'local KIND = "MIRMaximumLevelPolicyV3"' },
    @{ File = "maximum_level_binding.lua"; Text = $bindingText; Snippet = '["exact-technology"] = 1' },
    @{ File = "maximum_level_binding.lua"; Text = $bindingText; Snippet = 'semantics = "absolute-highest-technology-level"' },
    @{ File = "maximum_level_binding.lua"; Text = $bindingText; Snippet = 'retain_completed_bonus = true' },
    @{ File = "maximum_level_binding.lua"; Text = $bindingText; Snippet = 'maximum_level_unknown_finalizer_adapter' },
    @{ File = "compiler_orchestrator.lua"; Text = $orchestratorText; Snippet = 'maximum_level_binding.from_plan(latest' },
    @{ File = "compiler_orchestrator.lua"; Text = $orchestratorText; Snippet = 'context:set_state("maximum_level_policy", maximum_level_policy)' },
    @{ File = "maximum_level_presentation.lua"; Text = $presentationText; Snippet = 'maximum_level_binding.observe_finalizers(policy, observations)' },
    @{ File = "maximum_level_control.lua"; Text = $runtimeText; Snippet = 'binding.record_type == "MaximumLevelBinding"' },
    @{ File = "mod_data.lua"; Text = $modDataText; Snippet = 'more-infinite-research.maximum-level-policy-v3' },
    @{ File = "assert-compiler-contracts"; Text = $fixtureText; Snippet = 'unknown MaximumLevelBinding finalizer did not emit a stable blocking diagnostic' },
    @{ File = ".mir\modules.yml"; Text = $modulesText; Snippet = 'prototypes/mir/domain/technology/maximum_level_binding.lua' },
    @{ File = ".mir\compatibility.yml"; Text = $compatibilityText; Snippet = 'maximum_level_binding_policy:' },
    @{ File = ".mir\docs.yml"; Text = $docsText; Snippet = 'docs/reference/maximum-level-binding.md' },
    @{ File = "maximum-level-binding.md"; Text = $contractDocText; Snippet = '`MIRMaximumLevelPolicyV3` is the one maximum-level registry' }
  )) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing schema-3 MaximumLevelBinding wiring in $($check.File): $($check.Snippet)"
    }
  }
  if ($bindingText.Contains("data.raw") -or $bindingText.Contains("prototypes.technology") -or
      $bindingText.Contains('require("prototypes.mir.platform.factorio.target_line")')) {
    throw "MaximumLevelBinding domain authority must remain pure and target-neutral."
  }
}

Invoke-RepoCheck "bounded technology prerequisite cycle repairs are wired" {
  $registryText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\repairs\registry.lua")
  $repairText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\repairs\technology_prerequisite_cycles.lua")
  $fixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\external-technology-cycle\data-final-fixes.lua")
  $compatibilityText = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\compatibility.yml")
  foreach ($check in @(
    @{ File = "registry.lua"; Text = $registryText; Snippet = 'require("prototypes.mir.compatibility.repairs.technology_prerequisite_cycles").apply()' },
    @{ File = "technology_prerequisite_cycles.lua"; Text = $repairText; Snippet = 'id = "muluna-astroponics-space-science-cycle"' },
    @{ File = "technology_prerequisite_cycles.lua"; Text = $repairText; Snippet = 'required_mods = {"astroponics", "planet-muluna"}' },
    @{ File = "technology_prerequisite_cycles.lua"; Text = $repairText; Snippet = 'and reaches(technologies, repair.reverse_path_start, repair.technology)' },
    @{ File = "technology_prerequisite_cycles.lua"; Text = $repairText; Snippet = 'if prerequisite ~= operation.remove_prerequisite' },
    @{ File = "external-technology-cycle fixture"; Text = $fixtureText; Snippet = 'cycle containing a generated technology did not remain fatal' },
    @{ File = ".mir/compatibility.yml"; Text = $compatibilityText; Snippet = 'muluna-astroponics-space-science-cycle' }
  )) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing bounded technology cycle repair wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "compatibility support lanes are wired" {
  $supportLanePath = Join-Path $repo "spec\compatibility\support-lanes.json"
  if (-not (Test-Path -LiteralPath $supportLanePath)) {
    throw "Missing compatibility support-lane ledger: $supportLanePath"
  }

  $supportLaneText = Get-Content -Raw -LiteralPath $supportLanePath
  $requiredSnippets = @(
    '"upstream_factorio_version_is_blocking": false',
    '"mod": "atan-air-scrubbing"',
    '"mod": "atan-nuclear-science"',
    '"mir-fixture-assert-atan-nuclear-science-productivity"',
    '"mod": "big-mining-drill"',
    '"capability_lane": "mining-drill-manufacturing"',
    '"mir-fixture-assert-big-mining-drill-productivity"',
    '"mod": "aai-loaders"',
    '"capability_lane": "logistics-loader-manufacturing"',
    '"mir-fixture-assert-aai-loader-belt-productivity"',
    '"backport_candidate": true'
  )

  foreach ($snippet in $requiredSnippets) {
    if (-not $supportLaneText.Contains($snippet)) {
      throw "Missing compatibility support-lane entry: $snippet"
    }
  }
}

