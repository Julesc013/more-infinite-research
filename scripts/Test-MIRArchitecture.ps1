param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Get-MIRPath {
  param([Parameter(Mandatory)][string]$RelativePath)
  return Join-Path $repo $RelativePath
}

function Read-MIRFile {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Get-MIRPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required architecture file: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

function Get-MIRCodeLines {
  param([Parameter(Mandatory)][string]$Text)
  return @(
    $Text -split "\r?\n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("--") }
  )
}

function Assert-MIRContains {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  if (-not $Text.Contains($Needle)) {
    throw "$RelativePath is missing required architecture snippet: $Needle"
  }
}

function Assert-MIRNoPatternInLuaTree {
  param(
    [Parameter(Mandatory)][string]$RelativeRoot,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message
  )

  $root = Get-MIRPath -RelativePath $RelativeRoot
  if (-not (Test-Path -LiteralPath $root)) { return }

  $matches = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.lua" |
      Select-String -Pattern $Pattern
  )
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw $Message
  }
}

function Assert-MIRNoPatternInLuaFile {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message
  )

  $path = Get-MIRPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { return }

  $matches = @(Select-String -LiteralPath $path -Pattern $Pattern)
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw $Message
  }
}

$entrypoints = @(
  @{
    Root = "settings.lua"
    StageModule = "prototypes.mir.stage.settings"
    StagePath = "prototypes/mir/stage/settings.lua"
    LegacyModule = "prototypes.mir.legacy.settings"
  },
  @{
    Root = "data.lua"
    StageModule = "prototypes.mir.stage.data"
    StagePath = "prototypes/mir/stage/data.lua"
    LegacyModule = "prototypes.mir.legacy.data"
  },
  @{
    Root = "data-updates.lua"
    StageModule = "prototypes.mir.stage.data_updates"
    StagePath = "prototypes/mir/stage/data_updates.lua"
    LegacyModule = "prototypes.mir.legacy.data_updates"
  },
  @{
    Root = "data-final-fixes.lua"
    StageModule = "prototypes.mir.stage.data_final_fixes"
    StagePath = "prototypes/mir/stage/data_final_fixes.lua"
    LegacyModule = "prototypes.mir.legacy.data_final_fixes"
  },
  @{
    Root = "control.lua"
    StageModule = "prototypes.mir.stage.control"
    StagePath = "prototypes/mir/stage/control.lua"
    LegacyModule = "prototypes.mir.legacy.control"
  }
)

foreach ($entry in $entrypoints) {
  $rootText = Read-MIRFile -RelativePath $entry.Root
  $rootCodeLines = @(Get-MIRCodeLines -Text $rootText)
  if ($rootCodeLines.Count -ne 1) {
    throw "$($entry.Root) must be a thin one-line stage wrapper."
  }

  $expectedRoot = 'require("' + $entry.StageModule + '").run()'
  if ($rootCodeLines[0] -ne $expectedRoot) {
    throw "$($entry.Root) must call $expectedRoot."
  }

  $stageText = Read-MIRFile -RelativePath $entry.StagePath
  Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle "function M.run()"
  if ($entry.Root -eq "control.lua") {
    Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle "assert_runtime_stage()"
    Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle 'require("control.scripted-techs").register()'
  } elseif ($entry.Root -eq "data-final-fixes.lua") {
    Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle 'require("prototypes.mir.stage.data_final_fixes_steps")'
  } else {
    Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle ('require("' + $entry.LegacyModule + '")')
  }
}

$dataFinalFixesStagePath = "prototypes/mir/stage/data_final_fixes.lua"
$dataFinalFixesStepsPath = "prototypes/mir/stage/data_final_fixes_steps.lua"
$dataFinalFixesStageText = Read-MIRFile -RelativePath $dataFinalFixesStagePath
Assert-MIRContains -RelativePath $dataFinalFixesStagePath -Text $dataFinalFixesStageText -Needle "steps.apply_pipeline_extent()"
Assert-MIRContains -RelativePath $dataFinalFixesStagePath -Text $dataFinalFixesStageText -Needle "steps.emit_streams()"
Assert-MIRContains -RelativePath $dataFinalFixesStagePath -Text $dataFinalFixesStageText -Needle 'require("prototypes.mir.compatibility.diagnostics.registry").emit_all()'
Assert-MIRContains -RelativePath $dataFinalFixesStagePath -Text $dataFinalFixesStageText -Needle 'require("prototypes.mir.planner.compiler").emit()'
Assert-MIRContains -RelativePath $dataFinalFixesStagePath -Text $dataFinalFixesStageText -Needle "steps.flush_diagnostics()"
if ($dataFinalFixesStageText.Contains('require("prototypes.mir.compatibility.diagnostics.atan_ash").emit()')) {
  throw "$dataFinalFixesStagePath must emit exact overlay diagnostics through the diagnostics registry."
}

$dataFinalFixesStepsText = Read-MIRFile -RelativePath $dataFinalFixesStepsPath
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle "function M.apply_pipeline_extent()"
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle 'require("prototypes.mir.policy.competing_productivity").prepare()'
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle 'require("prototypes.mir.policy.competing_productivity").apply()'
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle 'require("prototypes.mir.policy.competing_base_extensions").apply()'
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle "function M.emit_streams()"
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle 'require("prototypes.mir.planner.stream_compiler").run()'
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle 'require("prototypes.mir.compatibility.planner").emit()'
Assert-MIRContains -RelativePath $dataFinalFixesStepsPath -Text $dataFinalFixesStepsText -Needle "function M.flush_diagnostics()"
if ($dataFinalFixesStepsText -match 'require\("prototypes\.compat\.') {
  throw "$dataFinalFixesStepsPath must call MIR-owned compatibility and policy modules, not prototypes.compat shims."
}

$dataFinalFixesLegacyPath = "prototypes/mir/legacy/data_final_fixes.lua"
$dataFinalFixesLegacyText = Read-MIRFile -RelativePath $dataFinalFixesLegacyPath
Assert-MIRContains -RelativePath $dataFinalFixesLegacyPath -Text $dataFinalFixesLegacyText -Needle 'return require("prototypes.mir.stage.data_final_fixes_steps")'

$requiredShims = @(
  "prototypes/mir/core/schema.lua",
  "prototypes/mir/core/deepcopy.lua",
  "prototypes/mir/core/table.lua",
  "prototypes/mir/platform/factorio/data_raw.lua",
  "prototypes/mir/platform/factorio/mods.lua",
  "prototypes/mir/platform/factorio/prototype_lookup.lua",
  "prototypes/mir/settings/registry.lua",
  "prototypes/mir/settings/visibility.lua",
  "prototypes/mir/settings/builder.lua",
  "prototypes/mir/settings/legacy_adapter.lua",
  "prototypes/mir/policy/adoption_policy.lua",
  "prototypes/mir/policy/owner_policy.lua",
  "prototypes/mir/policy/competing_productivity.lua",
  "prototypes/mir/policy/competing_base_extensions.lua",
  "prototypes/mir/policy/productivity_family_adoption.lua",
  "prototypes/mir/policy/technology_cleanup.lua",
  "prototypes/mir/policy/capabilities.lua",
  "prototypes/mir/index/registry_builder.lua",
  "prototypes/mir/index/productivity_owners.lua",
  "prototypes/mir/index/recipes.lua",
  "prototypes/mir/index/technologies.lua",
  "prototypes/mir/index/labs.lua",
  "prototypes/mir/index/owners.lua",
  "prototypes/mir/index/rule_surfaces.lua",
  "prototypes/mir/domain/facts/registry.lua",
  "prototypes/mir/capabilities/contract.lua",
  "prototypes/mir/capabilities/registry.lua",
  "prototypes/mir/capabilities/recipe_productivity/planner.lua",
  "prototypes/mir/emit/legacy_stream_adapter.lua",
  "prototypes/mir/report/decision_export.lua",
  "prototypes/mir/report/compatibility_diagnostics.lua",
  "prototypes/mir/report/diagnostics_sink.lua",
  "prototypes/mir/planner/compiler.lua",
  "prototypes/mir/planner/direct_effects.lua",
  "prototypes/mir/planner/native_modifiers.lua",
  "prototypes/mir/planner/requirements.lua",
  "prototypes/mir/planner/technology_requirements.lua",
  "prototypes/mir/planner/science.lua",
  "prototypes/mir/planner/stream_compiler.lua",
  "prototypes/mir/stage/data_final_fixes_steps.lua",
  "prototypes/mir/compatibility/registry.lua",
  "prototypes/mir/compatibility/profiles.lua",
  "prototypes/mir/compatibility/planner.lua",
  "prototypes/mir/compatibility/overlay_loader.lua",
  "prototypes/mir/compatibility/claim_registry.lua",
  "prototypes/mir/compatibility/diagnostics/registry.lua",
  "prototypes/mir/compatibility/diagnostics/exact_recipe_policy.lua",
  "prototypes/mir/compatibility/diagnostics/air_scrubbing.lua",
  "prototypes/mir/compatibility/diagnostics/atan_ash.lua",
  "prototypes/mir/compatibility/overlays/air_scrubbing.lua",
  "prototypes/mir/compatibility/overlays/atan_ash.lua",
  "prototypes/mir/legacy/stream_emitter.lua",
  "prototypes/mir/legacy/tech_gen.lua",
  "prototypes/mir/legacy/recipe_matching.lua",
  "prototypes/mir/legacy/compat_profiles.lua",
  "prototypes/mir/legacy/diagnostics.lua",
  "prototypes/mir/legacy/stream_specs.lua"
)

foreach ($relative in $requiredShims) {
  $null = Read-MIRFile -RelativePath $relative
}

$technologyBuilderPath = "prototypes/mir/emit/technology_builder.lua"
$technologyBuilderText = Read-MIRFile -RelativePath $technologyBuilderPath
Assert-MIRContains -RelativePath $technologyBuilderPath -Text $technologyBuilderText -Needle 'require("prototypes.mir.platform.factorio.data_raw")'
Assert-MIRContains -RelativePath $technologyBuilderPath -Text $technologyBuilderText -Needle "data_raw.extend({ technology })"
if ($technologyBuilderText -match "data:extend") {
  throw "$technologyBuilderPath must emit through the platform data_raw adapter."
}

$legacyStreamAdapterPath = "prototypes/mir/emit/legacy_stream_adapter.lua"
$legacyStreamAdapterText = Read-MIRFile -RelativePath $legacyStreamAdapterPath
Assert-MIRContains -RelativePath $legacyStreamAdapterPath -Text $legacyStreamAdapterText -Needle 'require("prototypes.mir.domain.streams.stream_spec")'
Assert-MIRContains -RelativePath $legacyStreamAdapterPath -Text $legacyStreamAdapterText -Needle 'require("prototypes.mir.emit.technology_builder")'
Assert-MIRContains -RelativePath $legacyStreamAdapterPath -Text $legacyStreamAdapterText -Needle "stream_spec.from_legacy_stream({"
Assert-MIRContains -RelativePath $legacyStreamAdapterPath -Text $legacyStreamAdapterText -Needle "technology_builder.emit(stream)"

$legacyStreamEmitterPath = "prototypes/mir/legacy/stream_emitter.lua"
$legacyStreamEmitterText = Read-MIRFile -RelativePath $legacyStreamEmitterPath
Assert-MIRContains -RelativePath $legacyStreamEmitterPath -Text $legacyStreamEmitterText -Needle 'return require("prototypes.mir.emit.legacy_stream_adapter")'

$legacyTechGenPath = "prototypes/tech-gen.lua"
$legacyTechGenText = Read-MIRFile -RelativePath $legacyTechGenPath
Assert-MIRContains -RelativePath $legacyTechGenPath -Text $legacyTechGenText -Needle 'return require("prototypes.mir.planner.stream_compiler").run()'

$legacyCapabilityContractPath = "prototypes/lib/capabilities/contract.lua"
$legacyCapabilityContractText = Read-MIRFile -RelativePath $legacyCapabilityContractPath
Assert-MIRContains -RelativePath $legacyCapabilityContractPath -Text $legacyCapabilityContractText -Needle 'return require("prototypes.mir.capabilities.contract")'

$legacyCapabilityRegistryPath = "prototypes/lib/capabilities/registry.lua"
$legacyCapabilityRegistryText = Read-MIRFile -RelativePath $legacyCapabilityRegistryPath
Assert-MIRContains -RelativePath $legacyCapabilityRegistryPath -Text $legacyCapabilityRegistryText -Needle 'return require("prototypes.mir.capabilities.registry")'

$legacyCapabilityPolicyPath = "prototypes/lib/policy/capabilities.lua"
$legacyCapabilityPolicyText = Read-MIRFile -RelativePath $legacyCapabilityPolicyPath
Assert-MIRContains -RelativePath $legacyCapabilityPolicyPath -Text $legacyCapabilityPolicyText -Needle 'return require("prototypes.mir.policy.capabilities")'

$legacyPrototypeLookupPath = "prototypes/lib/prototype-lookup.lua"
$legacyPrototypeLookupText = Read-MIRFile -RelativePath $legacyPrototypeLookupPath
Assert-MIRContains -RelativePath $legacyPrototypeLookupPath -Text $legacyPrototypeLookupText -Needle 'return require("prototypes.mir.platform.factorio.prototype_lookup")'

$legacyDiagnosticsPath = "prototypes/diagnostics.lua"
$legacyDiagnosticsText = Read-MIRFile -RelativePath $legacyDiagnosticsPath
Assert-MIRContains -RelativePath $legacyDiagnosticsPath -Text $legacyDiagnosticsText -Needle 'return require("prototypes.mir.report.diagnostics_sink")'

$streamCompilerPath = "prototypes/mir/planner/stream_compiler.lua"
$streamCompilerText = Read-MIRFile -RelativePath $streamCompilerPath
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.emit.legacy_stream_adapter")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.policy.adoption_policy")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.policy.owner_policy")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.capabilities.recipe_productivity.planner")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.planner.direct_effects")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.planner.native_modifiers")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.planner.requirements")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle 'require("prototypes.mir.planner.science")'
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "planner_requirements.missing_reason(key, raw_spec)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "planner_science.ingredients_for_stream(key, spec)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "native_modifiers.record_overlaps(key, direct_effects)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "owner_policy.filter_existing_recipe_productivity(key, spec, buckets)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "adoption_policy.adopt_recipe_productivity_family(key, spec, buckets)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "adoption_policy.emit_mod_data()"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "direct_effects_planner.available_for_stream(key, spec)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "recipe_productivity_planner.match_buckets(key, spec)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "recipe_productivity_planner.effects_from_buckets(key, buckets)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "stream_emitter.emit(key, spec, fields)"
Assert-MIRContains -RelativePath $streamCompilerPath -Text $streamCompilerText -Needle "function M.run()"

$adoptionPolicyPath = "prototypes/mir/policy/adoption_policy.lua"
$adoptionPolicyText = Read-MIRFile -RelativePath $adoptionPolicyPath
Assert-MIRContains -RelativePath $adoptionPolicyPath -Text $adoptionPolicyText -Needle 'require("prototypes.mir.policy.productivity_family_adoption")'
Assert-MIRContains -RelativePath $adoptionPolicyPath -Text $adoptionPolicyText -Needle "function M.adopt_recipe_productivity_family(key, spec, buckets)"
Assert-MIRContains -RelativePath $adoptionPolicyPath -Text $adoptionPolicyText -Needle "function M.emit_mod_data()"

$ownerPolicyPath = "prototypes/mir/policy/owner_policy.lua"
$ownerPolicyText = Read-MIRFile -RelativePath $ownerPolicyPath
Assert-MIRContains -RelativePath $ownerPolicyPath -Text $ownerPolicyText -Needle 'require("prototypes.mir.policy.competing_productivity")'
Assert-MIRContains -RelativePath $ownerPolicyPath -Text $ownerPolicyText -Needle 'require("prototypes.mir.index.productivity_owners")'
Assert-MIRContains -RelativePath $ownerPolicyPath -Text $ownerPolicyText -Needle "function M.filter_existing_recipe_productivity(key, spec, buckets)"
Assert-MIRContains -RelativePath $ownerPolicyPath -Text $ownerPolicyText -Needle "D.recipe_owner({"

$compatibilityShimExpectations = @{
  "prototypes/compat/profiles.lua" = 'return require("prototypes.mir.compatibility.profiles")'
  "prototypes/compat/planner.lua" = 'return require("prototypes.mir.compatibility.planner")'
  "prototypes/compat/productivity-owners.lua" = 'return require("prototypes.mir.index.productivity_owners")'
  "prototypes/compat/competing-productivity.lua" = 'return require("prototypes.mir.policy.competing_productivity")'
  "prototypes/compat/competing-base-extensions.lua" = 'return require("prototypes.mir.policy.competing_base_extensions")'
  "prototypes/compat/productivity-family-adoption.lua" = 'return require("prototypes.mir.policy.productivity_family_adoption")'
}

foreach ($relativePath in $compatibilityShimExpectations.Keys) {
  $shimText = Read-MIRFile -RelativePath $relativePath
  $shimCodeLines = @(Get-MIRCodeLines -Text $shimText)
  if ($shimCodeLines.Count -ne 1) {
    throw "$relativePath must remain a one-line MIR compatibility shim."
  }
  if ($shimCodeLines[0] -ne $compatibilityShimExpectations[$relativePath]) {
    throw "$relativePath must call $($compatibilityShimExpectations[$relativePath])."
  }
}

$recipeProductivityPlannerPath = "prototypes/mir/capabilities/recipe_productivity/planner.lua"
$recipeProductivityPlannerText = Read-MIRFile -RelativePath $recipeProductivityPlannerPath
Assert-MIRContains -RelativePath $recipeProductivityPlannerPath -Text $recipeProductivityPlannerText -Needle "function M.match_buckets(key, spec)"
Assert-MIRContains -RelativePath $recipeProductivityPlannerPath -Text $recipeProductivityPlannerText -Needle "U.recipes_for_stream(spec)"
Assert-MIRContains -RelativePath $recipeProductivityPlannerPath -Text $recipeProductivityPlannerText -Needle "D.recipe_matches(key, buckets)"
Assert-MIRContains -RelativePath $recipeProductivityPlannerPath -Text $recipeProductivityPlannerText -Needle "function M.effects_from_buckets(key, buckets)"
Assert-MIRContains -RelativePath $recipeProductivityPlannerPath -Text $recipeProductivityPlannerText -Needle 'type = "change-recipe-productivity"'

$indexRegistryPath = "prototypes/mir/index/registry_builder.lua"
$indexRegistryText = Read-MIRFile -RelativePath $indexRegistryPath
Assert-MIRContains -RelativePath $indexRegistryPath -Text $indexRegistryText -Needle "RecipeFact"
Assert-MIRContains -RelativePath $indexRegistryPath -Text $indexRegistryText -Needle "RuleMutationFact"
Assert-MIRContains -RelativePath $indexRegistryPath -Text $indexRegistryText -Needle "build_loop_risk_facts"

$legacyFactRegistryPath = "prototypes/lib/facts/registry.lua"
$legacyFactRegistryText = Read-MIRFile -RelativePath $legacyFactRegistryPath
Assert-MIRContains -RelativePath $legacyFactRegistryPath -Text $legacyFactRegistryText -Needle 'return require("prototypes.mir.index.registry_builder")'

$settingsVisibilityPath = "prototypes/mir/settings/visibility.lua"
$settingsVisibilityText = Read-MIRFile -RelativePath $settingsVisibilityPath
Assert-MIRContains -RelativePath $settingsVisibilityPath -Text $settingsVisibilityText -Needle "function M.evaluate(spec, ctx)"
Assert-MIRContains -RelativePath $settingsVisibilityPath -Text $settingsVisibilityText -Needle 'mode == "visible-if-mods-any"'
Assert-MIRContains -RelativePath $settingsVisibilityPath -Text $settingsVisibilityText -Needle 'mode == "visible-if-mods-all"'
Assert-MIRContains -RelativePath $settingsVisibilityPath -Text $settingsVisibilityText -Needle 'reason = "unknown-visibility-rule"'

$settingsBuilderPath = "prototypes/mir/settings/builder.lua"
$settingsBuilderText = Read-MIRFile -RelativePath $settingsBuilderPath
Assert-MIRContains -RelativePath $settingsBuilderPath -Text $settingsBuilderText -Needle 'require("prototypes.mir.settings.registry")'
Assert-MIRContains -RelativePath $settingsBuilderPath -Text $settingsBuilderText -Needle "function M.apply_visibility(setting, result)"
Assert-MIRContains -RelativePath $settingsBuilderPath -Text $settingsBuilderText -Needle "setting.hidden = true"
Assert-MIRContains -RelativePath $settingsBuilderPath -Text $settingsBuilderText -Needle "function M.stream_setting_names(stream_key)"

$settingsLegacyAdapterPath = "prototypes/mir/settings/legacy_adapter.lua"
$settingsLegacyAdapterText = Read-MIRFile -RelativePath $settingsLegacyAdapterPath
Assert-MIRContains -RelativePath $settingsLegacyAdapterPath -Text $settingsLegacyAdapterText -Needle 'require("prototypes.mir.platform.factorio.mods")'
Assert-MIRContains -RelativePath $settingsLegacyAdapterPath -Text $settingsLegacyAdapterText -Needle 'require("prototypes.mir.settings.builder")'
Assert-MIRContains -RelativePath $settingsLegacyAdapterPath -Text $settingsLegacyAdapterText -Needle "factorio_mods.snapshot()"

$mirCliPath = "scripts/mir.ps1"
$mirCliText = Read-MIRFile -RelativePath $mirCliPath
Assert-MIRContains -RelativePath $mirCliPath -Text $mirCliText -Needle '.\scripts\mir.ps1 legacy inventory [--output <path>]'
Assert-MIRContains -RelativePath $mirCliPath -Text $mirCliText -Needle '"legacy" {'
Assert-MIRContains -RelativePath $mirCliPath -Text $mirCliText -Needle 'Get-MIRLegacyInventory.ps1'

$legacyInventoryPath = "scripts/Get-MIRLegacyInventory.ps1"
$legacyInventoryText = Read-MIRFile -RelativePath $legacyInventoryPath
Assert-MIRContains -RelativePath $legacyInventoryPath -Text $legacyInventoryText -Needle "shipped-mod-legacy.json"
Assert-MIRContains -RelativePath $legacyInventoryPath -Text $legacyInventoryText -Needle "repo-legacy.json"
Assert-MIRContains -RelativePath $legacyInventoryPath -Text $legacyInventoryText -Needle "legacy-summary.md"
Assert-MIRContains -RelativePath $legacyInventoryPath -Text $legacyInventoryText -Needle "generated_streams_without_manifest"
Assert-MIRContains -RelativePath $legacyInventoryPath -Text $legacyInventoryText -Needle "compat_active_modules"

$decisionExportPath = "prototypes/mir/report/decision_export.lua"
$decisionExportText = Read-MIRFile -RelativePath $decisionExportPath
Assert-MIRContains -RelativePath $decisionExportPath -Text $decisionExportText -Needle "function M.emit(sink, record)"
Assert-MIRContains -RelativePath $decisionExportPath -Text $decisionExportText -Needle "sink.decision(record)"

$compatibilityDiagnosticsReportPath = "prototypes/mir/report/compatibility_diagnostics.lua"
$compatibilityDiagnosticsReportText = Read-MIRFile -RelativePath $compatibilityDiagnosticsReportPath
Assert-MIRContains -RelativePath $compatibilityDiagnosticsReportPath -Text $compatibilityDiagnosticsReportText -Needle 'require("prototypes.mir.report.decision_export")'
Assert-MIRContains -RelativePath $compatibilityDiagnosticsReportPath -Text $compatibilityDiagnosticsReportText -Needle "function M.compatibility_plan(sink, row)"
Assert-MIRContains -RelativePath $compatibilityDiagnosticsReportPath -Text $compatibilityDiagnosticsReportText -Needle "sink.loop_risk(row)"

$plannerCompilerShimPath = "prototypes/planner/compiler.lua"
$plannerCompilerShimText = Read-MIRFile -RelativePath $plannerCompilerShimPath
Assert-MIRContains -RelativePath $plannerCompilerShimPath -Text $plannerCompilerShimText -Needle 'return require("prototypes.mir.planner.compiler")'

$plannerCompilerPath = "prototypes/mir/planner/compiler.lua"
$plannerCompilerText = Read-MIRFile -RelativePath $plannerCompilerPath
Assert-MIRContains -RelativePath $plannerCompilerPath -Text $plannerCompilerText -Needle 'require("prototypes.mir.index.registry_builder")'
Assert-MIRContains -RelativePath $plannerCompilerPath -Text $plannerCompilerText -Needle 'require("prototypes.mir.report.decision_export")'
Assert-MIRContains -RelativePath $plannerCompilerPath -Text $plannerCompilerText -Needle "decision_export.emit(D, decision_record.generated_technology({"

$plannerRequirementsPath = "prototypes/mir/planner/requirements.lua"
$plannerRequirementsText = Read-MIRFile -RelativePath $plannerRequirementsPath
Assert-MIRContains -RelativePath $plannerRequirementsPath -Text $plannerRequirementsText -Needle "function M.missing_reason(key, spec)"
Assert-MIRContains -RelativePath $plannerRequirementsPath -Text $plannerRequirementsText -Needle 'require("prototypes.mir.planner.technology_requirements")'
Assert-MIRContains -RelativePath $plannerRequirementsPath -Text $plannerRequirementsText -Needle "U.mod_exists(mod_name)"
Assert-MIRContains -RelativePath $plannerRequirementsPath -Text $plannerRequirementsText -Needle "U.ammo_category_exists(category)"

$plannerNativeModifiersPath = "prototypes/mir/planner/native_modifiers.lua"
$plannerNativeModifiersText = Read-MIRFile -RelativePath $plannerNativeModifiersPath
Assert-MIRContains -RelativePath $plannerNativeModifiersPath -Text $plannerNativeModifiersText -Needle 'require("prototypes.mir.platform.factorio.data_raw")'
Assert-MIRContains -RelativePath $plannerNativeModifiersPath -Text $plannerNativeModifiersText -Needle "function M.identity(effect)"
Assert-MIRContains -RelativePath $plannerNativeModifiersPath -Text $plannerNativeModifiersText -Needle 'data_raw.prototypes("technology")'
Assert-MIRContains -RelativePath $plannerNativeModifiersPath -Text $plannerNativeModifiersText -Needle "function M.record_overlaps(key, effects)"

$plannerDirectEffectsPath = "prototypes/mir/planner/direct_effects.lua"
$plannerDirectEffectsText = Read-MIRFile -RelativePath $plannerDirectEffectsPath
Assert-MIRContains -RelativePath $plannerDirectEffectsPath -Text $plannerDirectEffectsText -Needle 'require("prototypes.technology-effect-safety")'
Assert-MIRContains -RelativePath $plannerDirectEffectsPath -Text $plannerDirectEffectsText -Needle "function M.available_for_stream(key, spec)"
Assert-MIRContains -RelativePath $plannerDirectEffectsPath -Text $plannerDirectEffectsText -Needle 'effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)'
Assert-MIRContains -RelativePath $plannerDirectEffectsPath -Text $plannerDirectEffectsText -Needle "U.effect_icons_for_stream(spec)"

$plannerSciencePath = "prototypes/mir/planner/science.lua"
$plannerScienceText = Read-MIRFile -RelativePath $plannerSciencePath
Assert-MIRContains -RelativePath $plannerSciencePath -Text $plannerScienceText -Needle "function M.ingredients_for_stream(key, spec)"
Assert-MIRContains -RelativePath $plannerSciencePath -Text $plannerScienceText -Needle "U.pick_science_for_stream(spec, key)"
Assert-MIRContains -RelativePath $plannerSciencePath -Text $plannerScienceText -Needle "U.best_lab_compatible_ingredients"
Assert-MIRContains -RelativePath $plannerSciencePath -Text $plannerScienceText -Needle 'lab_status or "full"'

$airScrubbingOverlayPath = "prototypes/mir/compatibility/overlays/air_scrubbing.lua"
$airScrubbingOverlayText = Read-MIRFile -RelativePath $airScrubbingOverlayPath
Assert-MIRContains -RelativePath $airScrubbingOverlayPath -Text $airScrubbingOverlayText -Needle 'id = "air-scrubbing"'
Assert-MIRContains -RelativePath $airScrubbingOverlayPath -Text $airScrubbingOverlayText -Needle 'exact_recipes = {'
Assert-MIRContains -RelativePath $airScrubbingOverlayPath -Text $airScrubbingOverlayText -Needle 'deny_families = {'
if ($airScrubbingOverlayText -match 'require\("prototypes\.compat\.air-scrubbing"\)') {
  throw "$airScrubbingOverlayPath must be policy data, not a legacy behavior shim."
}

$productivityStreamsPath = "prototypes/streams/productivity.lua"
$productivityStreamsText = Read-MIRFile -RelativePath $productivityStreamsPath
Assert-MIRContains -RelativePath $productivityStreamsPath -Text $productivityStreamsText -Needle 'overlay_loader.get("air-scrubbing")'
Assert-MIRContains -RelativePath $productivityStreamsPath -Text $productivityStreamsText -Needle "air_scrubbing_capability.stream.id"
Assert-MIRContains -RelativePath $productivityStreamsPath -Text $productivityStreamsText -Needle "exact_recipe_patterns(air_scrubbing_capability.exact_recipes)"
Assert-MIRContains -RelativePath $productivityStreamsPath -Text $productivityStreamsText -Needle 'overlay_loader.get("atan-ash")'
Assert-MIRContains -RelativePath $productivityStreamsPath -Text $productivityStreamsText -Needle "atan_ash_capability.stream.id"
Assert-MIRContains -RelativePath $productivityStreamsPath -Text $productivityStreamsText -Needle "exact_recipe_patterns(atan_ash_capability.exact_recipes)"

$atanAshOverlayPath = "prototypes/mir/compatibility/overlays/atan_ash.lua"
$atanAshOverlayText = Read-MIRFile -RelativePath $atanAshOverlayPath
Assert-MIRContains -RelativePath $atanAshOverlayPath -Text $atanAshOverlayText -Needle 'id = "atan-ash"'
Assert-MIRContains -RelativePath $atanAshOverlayPath -Text $atanAshOverlayText -Needle '"mir-prod-atan-ash-separation"'
Assert-MIRContains -RelativePath $atanAshOverlayPath -Text $atanAshOverlayText -Needle '"atan-ash-seperation"'
Assert-MIRContains -RelativePath $atanAshOverlayPath -Text $atanAshOverlayText -Needle '"ash_sink"'
if ($atanAshOverlayText -match "data:extend") {
  throw "$atanAshOverlayPath must be policy data, not prototype emission."
}

$legacyAirScrubbingPath = "prototypes/compat/air-scrubbing.lua"
$legacyAirScrubbingText = Read-MIRFile -RelativePath $legacyAirScrubbingPath
Assert-MIRContains -RelativePath $legacyAirScrubbingPath -Text $legacyAirScrubbingText -Needle 'return require("prototypes.mir.compatibility.diagnostics.air_scrubbing")'

$exactRecipePolicyPath = "prototypes/mir/compatibility/diagnostics/exact_recipe_policy.lua"
$exactRecipePolicyText = Read-MIRFile -RelativePath $exactRecipePolicyPath
Assert-MIRContains -RelativePath $exactRecipePolicyPath -Text $exactRecipePolicyText -Needle 'require("prototypes.mir.platform.factorio.data_raw")'
Assert-MIRContains -RelativePath $exactRecipePolicyPath -Text $exactRecipePolicyText -Needle 'require("prototypes.mir.compatibility.overlay_loader")'
Assert-MIRContains -RelativePath $exactRecipePolicyPath -Text $exactRecipePolicyText -Needle 'require("prototypes.mir.report.compatibility_diagnostics")'
Assert-MIRContains -RelativePath $exactRecipePolicyPath -Text $exactRecipePolicyText -Needle 'data_raw.prototypes("recipe")'
Assert-MIRContains -RelativePath $exactRecipePolicyPath -Text $exactRecipePolicyText -Needle "report.decision(D, row)"
Assert-MIRContains -RelativePath $exactRecipePolicyPath -Text $exactRecipePolicyText -Needle "report.compatibility_plan(D, {"

$diagnosticsRegistryPath = "prototypes/mir/compatibility/diagnostics/registry.lua"
$diagnosticsRegistryText = Read-MIRFile -RelativePath $diagnosticsRegistryPath
Assert-MIRContains -RelativePath $diagnosticsRegistryPath -Text $diagnosticsRegistryText -Needle 'id = "air-scrubbing"'
Assert-MIRContains -RelativePath $diagnosticsRegistryPath -Text $diagnosticsRegistryText -Needle 'id = "atan-ash"'
Assert-MIRContains -RelativePath $diagnosticsRegistryPath -Text $diagnosticsRegistryText -Needle 'require("prototypes.mir.compatibility.diagnostics.air_scrubbing")'
Assert-MIRContains -RelativePath $diagnosticsRegistryPath -Text $diagnosticsRegistryText -Needle 'require("prototypes.mir.compatibility.diagnostics.atan_ash")'
Assert-MIRContains -RelativePath $diagnosticsRegistryPath -Text $diagnosticsRegistryText -Needle "function M.emit_all()"

$airScrubbingDiagnosticsPath = "prototypes/mir/compatibility/diagnostics/air_scrubbing.lua"
$airScrubbingDiagnosticsText = Read-MIRFile -RelativePath $airScrubbingDiagnosticsPath
Assert-MIRContains -RelativePath $airScrubbingDiagnosticsPath -Text $airScrubbingDiagnosticsText -Needle 'require("prototypes.mir.compatibility.diagnostics.exact_recipe_policy")'
Assert-MIRContains -RelativePath $airScrubbingDiagnosticsPath -Text $airScrubbingDiagnosticsText -Needle 'overlay_id = "air-scrubbing"'
Assert-MIRContains -RelativePath $airScrubbingDiagnosticsPath -Text $airScrubbingDiagnosticsText -Needle 'allowed_generated_reason = "clean_filter_stream_emitted"'
Assert-MIRContains -RelativePath $airScrubbingDiagnosticsPath -Text $airScrubbingDiagnosticsText -Needle 'scrubbing_environmental = {'
Assert-MIRContains -RelativePath $airScrubbingDiagnosticsPath -Text $airScrubbingDiagnosticsText -Needle 'cleaning_recovery = {'

$atanAshDiagnosticsPath = "prototypes/mir/compatibility/diagnostics/atan_ash.lua"
$atanAshDiagnosticsText = Read-MIRFile -RelativePath $atanAshDiagnosticsPath
Assert-MIRContains -RelativePath $atanAshDiagnosticsPath -Text $atanAshDiagnosticsText -Needle 'require("prototypes.mir.compatibility.diagnostics.exact_recipe_policy")'
Assert-MIRContains -RelativePath $atanAshDiagnosticsPath -Text $atanAshDiagnosticsText -Needle 'overlay_id = "atan-ash"'
Assert-MIRContains -RelativePath $atanAshDiagnosticsPath -Text $atanAshDiagnosticsText -Needle 'allowed_generated_reason = "ash_separation_stream_emitted"'
Assert-MIRContains -RelativePath $atanAshDiagnosticsPath -Text $atanAshDiagnosticsText -Needle 'tile_surface = {'
Assert-MIRContains -RelativePath $atanAshDiagnosticsPath -Text $atanAshDiagnosticsText -Needle 'resource_recovery = {'

$claimRegistryPath = "prototypes/mir/compatibility/claim_registry.lua"
$claimRegistryText = Read-MIRFile -RelativePath $claimRegistryPath
Assert-MIRContains -RelativePath $claimRegistryPath -Text $claimRegistryText -Needle 'governance = ".mir/compatibility.yml"'
Assert-MIRContains -RelativePath $claimRegistryPath -Text $claimRegistryText -Needle 'fixture_claims = "fixtures/compat-matrix/claims.json"'
Assert-MIRContains -RelativePath $claimRegistryPath -Text $claimRegistryText -Needle 'mod = "atan-air-scrubbing"'
Assert-MIRContains -RelativePath $claimRegistryPath -Text $claimRegistryText -Needle 'mod = "aai-industry"'
Assert-MIRContains -RelativePath $claimRegistryPath -Text $claimRegistryText -Needle 'function M.get_by_mod(mod)'

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/domain" `
  -Pattern "\b(data\.raw|data:extend|mods|settings)\b" `
  -Message "MIR domain modules must not read Factorio globals or mutate prototypes."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/capabilities" `
  -Pattern "data:extend" `
  -Message "MIR capability modules must not emit prototypes directly."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/compatibility/overlays" `
  -Pattern "\bdata\.raw\b|data:extend" `
  -Message "MIR compatibility overlays must stay declarative."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/report" `
  -Pattern "\bdata\.raw\b|data:extend" `
  -Message "MIR report modules must not mutate prototypes."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/settings" `
  -Pattern "\bdata\.raw\b|data:extend|forced_value" `
  -Message "MIR settings modules must not inspect finalized prototypes, mutate prototypes, or force hidden values."

$runtimePrototypePattern = "\bdata\.raw\b|data:extend"
foreach ($relative in @(
  "control.lua",
  "prototypes/mir/stage/control.lua",
  "prototypes/mir/legacy/control.lua"
)) {
  Assert-MIRNoPatternInLuaFile `
    -RelativePath $relative `
    -Pattern $runtimePrototypePattern `
    -Message "MIR runtime control entrypoints must not perform prototype-stage work."
}

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "control" `
  -Pattern $runtimePrototypePattern `
  -Message "MIR runtime control modules must not perform prototype-stage work."

Write-Host "[ok] MIR architecture boundary lint passed."
