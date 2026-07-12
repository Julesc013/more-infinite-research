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

function Assert-MIRAbsent {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Get-MIRPath -RelativePath $RelativePath
  if (Test-Path -LiteralPath $path) {
    throw "Obsolete MIR 3 shim path must be absent: $RelativePath"
  }
}

function Assert-MIRNoPatternInLuaTree {
  param(
    [Parameter(Mandatory)][string]$RelativeRoot,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message,
    [string[]]$ExcludeRelative = @()
  )

  $root = Get-MIRPath -RelativePath $RelativeRoot
  if (-not (Test-Path -LiteralPath $root)) { return }

  $matches = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.lua" |
      Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/")
        $ExcludeRelative -notcontains $relative
      } |
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

function Assert-MIRNoTopLevelRequireCycles {
  $luaRoot = Get-MIRPath -RelativePath "prototypes/mir"
  $graph = @{}
  foreach ($file in Get-ChildItem -LiteralPath $luaRoot -Recurse -File -Filter "*.lua") {
    $relative = [System.IO.Path]::GetRelativePath($repo, $file.FullName).Replace("\", "/")
    $module = ($relative -replace '\.lua$', '').Replace("/", ".")
    $dependencies = @()
    $text = Get-Content -Raw -LiteralPath $file.FullName
    foreach ($match in [regex]::Matches($text, '(?m)^(?:local\s+\w+\s*=\s*|return\s+)require\("([^"]+)"\)')) {
      $dependency = $match.Groups[1].Value
      if ($dependency.StartsWith("prototypes.mir.")) {
        $dependencies += $dependency
      }
    }
    $graph[$module] = @($dependencies | Sort-Object -Unique)
  }

  $state = @{}
  $stack = [System.Collections.Generic.List[string]]::new()
  function Visit-MIRModule([string]$Module) {
    if ($state[$Module] -eq 2) { return }
    if ($state[$Module] -eq 1) {
      $start = $stack.IndexOf($Module)
      $cycle = @($stack.GetRange($start, $stack.Count - $start)) + $Module
      throw "Top-level Lua require cycle: $($cycle -join ' -> ')"
    }

    $state[$Module] = 1
    $stack.Add($Module) | Out-Null
    foreach ($dependency in @($graph[$Module])) {
      if ($graph.ContainsKey($dependency)) {
        Visit-MIRModule -Module $dependency
      }
    }
    $stack.RemoveAt($stack.Count - 1)
    $state[$Module] = 2
  }

  foreach ($module in @($graph.Keys | Sort-Object)) {
    Visit-MIRModule -Module $module
  }
}

$entrypoints = @(
  @{
    Root = "settings.lua"
    StageModule = "prototypes.mir.stage.settings"
    StagePath = "prototypes/mir/stage/settings.lua"
    StageNeedle = 'require("prototypes.mir.settings.stage_builder")'
  },
  @{
    Root = "data.lua"
    StageModule = "prototypes.mir.stage.data"
    StagePath = "prototypes/mir/stage/data.lua"
    StageNeedle = 'require("prototypes.mir.streams.registry")'
  },
  @{
    Root = "data-updates.lua"
    StageModule = "prototypes.mir.stage.data_updates"
    StagePath = "prototypes/mir/stage/data_updates.lua"
    StageNeedle = "Reserved for compatibility hooks"
  },
  @{
    Root = "data-final-fixes.lua"
    StageModule = "prototypes.mir.stage.data_final_fixes"
    StagePath = "prototypes/mir/stage/data_final_fixes.lua"
    StageNeedle = 'require("prototypes.mir.pipeline.commands")'
  },
  @{
    Root = "control.lua"
    StageModule = "prototypes.mir.stage.control"
    StagePath = "prototypes/mir/stage/control.lua"
    StageNeedle = 'require("prototypes.mir.runtime.scripted_techs").register()'
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
  Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle $entry.StageNeedle
}

$controlStageText = Read-MIRFile -RelativePath "prototypes/mir/stage/control.lua"
Assert-MIRContains -RelativePath "prototypes/mir/stage/control.lua" -Text $controlStageText -Needle "assert_runtime_stage()"
Assert-MIRContains -RelativePath "prototypes/mir/stage/control.lua" -Text $controlStageText -Needle 'require("prototypes.mir.runtime.settings_profile").register()'

foreach ($relative in @(
  "prototypes/compat",
  "prototypes/lib",
  "prototypes/mir/legacy",
  "prototypes/planner",
  "control",
  "defaults.lua",
  "prototypes/base-tech-extensions.lua",
  "prototypes/config.lua",
  "prototypes/diagnostics.lua",
  "prototypes/max-level-control.lua",
  "prototypes/pipeline-extent.lua",
  "prototypes/pipeline-extent-settings.lua",
  "prototypes/settings-resolver.lua",
  "prototypes/tech-gen.lua",
  "prototypes/technology-effect-safety.lua",
  "prototypes/util.lua",
  "prototypes/weapon-speed-adjustments.lua"
)) {
  Assert-MIRAbsent -RelativePath $relative
}

$requiredMirFiles = @(
  "prototypes/mir/core/schema.lua",
  "prototypes/mir/core/deepcopy.lua",
  "prototypes/mir/core/table.lua",
  "prototypes/mir/platform/factorio/data_raw.lua",
  "prototypes/mir/platform/factorio/mods.lua",
  "prototypes/mir/platform/factorio/prototype_lookup.lua",
  "prototypes/mir/platform/factorio/target_profiles.lua",
  "prototypes/mir/platform/factorio/target_line.lua",
  "prototypes/mir/platform/factorio/runtime_state.lua",
  "prototypes/mir/settings/stage_builder.lua",
  "prototypes/mir/settings/registry.lua",
  "prototypes/mir/settings/defaults.lua",
  "prototypes/mir/settings/visibility.lua",
  "prototypes/mir/settings/builder.lua",
  "prototypes/mir/settings/stage_adapter.lua",
  "prototypes/mir/settings/profile_codec.lua",
  "prototypes/mir/settings/effective.lua",
  "prototypes/mir/settings/effect_contracts.lua",
  "prototypes/mir/settings/effect_scaling.lua",
  "prototypes/mir/settings/resolver.lua",
  "prototypes/mir/settings/pipeline_extent.lua",
  "prototypes/mir/streams/registry.lua",
  "prototypes/mir/pipeline/commands.lua",
  "prototypes/mir/pipeline/extent.lua",
  "prototypes/mir/policy/adoption_policy.lua",
  "prototypes/mir/policy/owner_policy.lua",
  "prototypes/mir/policy/competing_productivity.lua",
  "prototypes/mir/policy/competing_base_extensions.lua",
  "prototypes/mir/policy/productivity_family_adoption.lua",
  "prototypes/mir/policy/max_level.lua",
  "prototypes/mir/policy/weapon_speed.lua",
  "prototypes/mir/policy/capabilities.lua",
  "prototypes/mir/index/registry_builder.lua",
  "prototypes/mir/index/recipe_facts.lua",
  "prototypes/mir/index/relationships.lua",
  "prototypes/mir/index/productivity_owners.lua",
  "prototypes/mir/domain/facts/registry.lua",
  "prototypes/mir/domain/facts/recipe_semantics.lua",
  "prototypes/mir/domain/effects/metadata.lua",
  "prototypes/mir/domain/facts/generated_technology_registry.lua",
  "prototypes/mir/capabilities/contract.lua",
  "prototypes/mir/capabilities/registry.lua",
  "prototypes/mir/capabilities/recipe_productivity/planner.lua",
  "prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua",
  "prototypes/mir/families/rules.lua",
  "prototypes/mir/families/registry.lua",
  "prototypes/mir/families/resolver.lua",
  "prototypes/mir/capabilities/science_integration/science_packs.lua",
  "prototypes/mir/capabilities/science_integration/science_selector.lua",
  "prototypes/mir/planner/compiler.lua",
  "prototypes/mir/planner/compilation_plan.lua",
  "prototypes/mir/planner/stream_compiler.lua",
  "prototypes/mir/planner/generation_plan.lua",
  "prototypes/mir/planner/output_validator.lua",
  "prototypes/mir/planner/costs.lua",
  "prototypes/mir/planner/direct_effects.lua",
  "prototypes/mir/planner/native_modifiers.lua",
  "prototypes/mir/planner/prerequisites.lua",
  "prototypes/mir/planner/requirements.lua",
  "prototypes/mir/planner/science.lua",
  "prototypes/mir/emit/stream_spec_adapter.lua",
  "prototypes/mir/emit/base_extensions.lua",
  "prototypes/mir/emit/icon_builder.lua",
  "prototypes/mir/emit/effect_safety.lua",
  "prototypes/mir/emit/mod_data.lua",
  "prototypes/mir/emit/technology_builder.lua",
  "prototypes/mir/emit/technology_replacement.lua",
  "prototypes/mir/report/decision_export.lua",
  "prototypes/mir/report/compatibility_diagnostics.lua",
  "prototypes/mir/report/diagnostics_sink.lua",
  "prototypes/mir/runtime/scripted_techs.lua",
  "prototypes/mir/runtime/settings_profile.lua",
  "prototypes/mir/runtime/settings_resolver.lua",
  "prototypes/mir/runtime/productivity_family_adoption.lua",
  "prototypes/mir/runtime/effects/spoilage_preservation.lua",
  "prototypes/mir/runtime/effects/agricultural_growth_speed.lua",
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
  "prototypes/mir/compatibility/repairs/factorio_2_1_recipe_schema.lua",
  "prototypes/mir/compatibility/overlays/air_scrubbing.lua",
  "prototypes/mir/compatibility/overlays/atan_ash.lua"
)

foreach ($validationModule in @(
  "scripts/validation/PackageIdentity.ps1",
  "scripts/validation/TargetProfiles.ps1",
  "scripts/validation/ScenarioGroups.ps1",
  "scripts/validation/ResultAggregation.ps1",
  "scripts/validation/FactorioProcess.ps1"
)) {
  if (-not (Test-Path -LiteralPath (Get-MIRPath -RelativePath $validationModule) -PathType Leaf)) {
    throw "Missing validation module: $validationModule"
  }
}

$validationFacadeText = Read-MIRFile -RelativePath "scripts/Invoke-MIRValidation.ps1"
Assert-MIRContains -RelativePath "scripts/Invoke-MIRValidation.ps1" -Text $validationFacadeText -Needle 'scripts\validation\FactorioProcess.ps1'
if ($validationFacadeText -match '(?m)^function\s+(Invoke-FactorioProcess|Remove-CopiedModDirectory|Copy-ModDirectory|Copy-RepositoryModDirectory)\b') {
  throw "Factorio process and copied-mod filesystem operations must live in scripts/validation/FactorioProcess.ps1."
}

foreach ($relative in $requiredMirFiles) {
  $null = Read-MIRFile -RelativePath $relative
}

& (Join-Path $repo "scripts\Sync-MIRTargetProfiles.ps1") -RepoRoot $repo -Check
if ($LASTEXITCODE -ne 0) {
  throw "Generated target profile validation failed with exit code $LASTEXITCODE."
}

$dataFinalFixesStageText = Read-MIRFile -RelativePath "prototypes/mir/stage/data_final_fixes.lua"
Assert-MIRContains -RelativePath "prototypes/mir/stage/data_final_fixes.lua" -Text $dataFinalFixesStageText -Needle "commands.run_all()"
if ($dataFinalFixesStageText -match 'commands\.run\("') {
  throw "Data-final-fixes stage must execute the governed command DAG, not name individual commands."
}

$dataFinalFixesStepsText = (Read-MIRFile -RelativePath "prototypes/mir/stage/data_final_fixes_steps.lua") + "`n" +
  (Read-MIRFile -RelativePath "prototypes/mir/pipeline/commands.lua")
Assert-MIRContains -RelativePath "prototypes/mir/pipeline/commands.lua" -Text $dataFinalFixesStepsText -Needle "function M.order()"
Assert-MIRContains -RelativePath "prototypes/mir/pipeline/commands.lua" -Text $dataFinalFixesStepsText -Needle "ran before dependency"
foreach ($needle in @(
  'require("prototypes.mir.compatibility.repairs.registry").apply()',
  'require("prototypes.mir.settings.pipeline_extent").multiplier()',
  'require("prototypes.mir.pipeline.extent").apply(multiplier)',
  'require("prototypes.mir.policy.competing_productivity").prepare()',
  'require("prototypes.mir.planner.compilation_plan").compile()',
  'require("prototypes.mir.planner.compilation_plan").apply_streams()',
  'require("prototypes.mir.planner.compilation_plan").apply_base_extensions()',
  'require("prototypes.mir.pipeline.mutations.competing_productivity").apply()',
  'require("prototypes.mir.pipeline.mutations.competing_base_extensions").apply()',
  'require("prototypes.mir.pipeline.mutations.weapon_speed").apply()',
  'require("prototypes.mir.pipeline.mutations.max_level").apply()',
  'require("prototypes.mir.compatibility.planner").emit()',
  'require("prototypes.mir.planner.compilation_plan").assert_output()',
  'require("prototypes.mir.emit.effect_safety").assert_registered_technology_effects()',
  'require("prototypes.mir.emit.technology_graph_safety").assert_registered_technologies()',
  'require("prototypes.mir.report.diagnostics_sink").flush()'
)) {
  Assert-MIRContains -RelativePath "prototypes/mir/stage/data_final_fixes_steps.lua" -Text $dataFinalFixesStepsText -Needle $needle
}

$commandCatalogText = Read-MIRFile -RelativePath "prototypes/mir/pipeline/commands.lua"
foreach ($commandId in @(
  "compatibility-repairs",
  "module-permissions",
  "prototype-limits",
  "pipeline-extent",
  "prepare-competing-productivity",
  "prepare-competing-base-extensions",
  "compile-generation-plan",
  "emit-streams",
  "apply-competing-productivity",
  "emit-base-extensions",
  "apply-competing-base-extensions",
  "weapon-speed-adjustments",
  "max-level-control",
  "emit-compatibility-diagnostics",
  "emit-compiler-reports",
  "emit-compatibility-planner",
  "assert-plan-output",
  "assert-technology-safety",
  "flush-diagnostics"
)) {
  Assert-MIRContains `
    -RelativePath "prototypes/mir/pipeline/commands.lua" `
    -Text $commandCatalogText `
    -Needle ('["' + $commandId + '"]')
}
Assert-MIRContains -RelativePath "prototypes/mir/pipeline/commands.lua" -Text $commandCatalogText -Needle "function M.run_all()"

$technologyBuilderText = Read-MIRFile -RelativePath "prototypes/mir/emit/technology_builder.lua"
Assert-MIRContains -RelativePath "prototypes/mir/emit/technology_builder.lua" -Text $technologyBuilderText -Needle 'require("prototypes.mir.platform.factorio.data_raw")'
Assert-MIRContains -RelativePath "prototypes/mir/emit/technology_builder.lua" -Text $technologyBuilderText -Needle "data_raw.extend({ technology })"
if ($technologyBuilderText -match "data:extend") {
  throw "prototypes/mir/emit/technology_builder.lua must emit through the platform data_raw adapter."
}

$streamAdapterText = Read-MIRFile -RelativePath "prototypes/mir/emit/stream_spec_adapter.lua"
Assert-MIRContains -RelativePath "prototypes/mir/emit/stream_spec_adapter.lua" -Text $streamAdapterText -Needle 'require("prototypes.mir.domain.streams.stream_spec")'
Assert-MIRContains -RelativePath "prototypes/mir/emit/stream_spec_adapter.lua" -Text $streamAdapterText -Needle 'require("prototypes.mir.emit.technology_builder")'
Assert-MIRContains -RelativePath "prototypes/mir/emit/stream_spec_adapter.lua" -Text $streamAdapterText -Needle "technology_builder.emit(stream)"
Assert-MIRContains -RelativePath "prototypes/mir/emit/stream_spec_adapter.lua" -Text $streamAdapterText -Needle "generated_registry.register(technology.name,"

$graphSafetyText = Read-MIRFile -RelativePath "prototypes/mir/emit/technology_graph_safety.lua"
Assert-MIRContains -RelativePath "prototypes/mir/emit/technology_graph_safety.lua" -Text $graphSafetyText -Needle "generated_registry.sorted_names()"
Assert-MIRContains -RelativePath "prototypes/mir/emit/technology_graph_safety.lua" -Text $graphSafetyText -Needle "science.pack_production_status(pack_name)"

$modDataText = Read-MIRFile -RelativePath "prototypes/mir/emit/mod_data.lua"
Assert-MIRContains -RelativePath "prototypes/mir/emit/mod_data.lua" -Text $modDataText -Needle 'require("prototypes.mir.platform.factorio.data_raw")'
Assert-MIRContains -RelativePath "prototypes/mir/emit/mod_data.lua" -Text $modDataText -Needle "data_raw.extend({"

$streamCompilerText = Read-MIRFile -RelativePath "prototypes/mir/planner/stream_compiler.lua"
Assert-MIRContains -RelativePath "prototypes/mir/planner/stream_compiler.lua" -Text $streamCompilerText -Needle 'require("prototypes.mir.streams.registry")'
Assert-MIRContains -RelativePath "prototypes/mir/planner/stream_compiler.lua" -Text $streamCompilerText -Needle 'require("prototypes.mir.emit.stream_spec_adapter")'
Assert-MIRContains -RelativePath "prototypes/mir/planner/stream_compiler.lua" -Text $streamCompilerText -Needle "function M.run()"
Assert-MIRContains -RelativePath "prototypes/mir/planner/stream_compiler.lua" -Text $streamCompilerText -Needle 'require("prototypes.mir.families.resolver")'
Assert-MIRContains -RelativePath "prototypes/mir/planner/stream_compiler.lua" -Text $streamCompilerText -Needle "function M.compile()"
Assert-MIRContains -RelativePath "prototypes/mir/planner/stream_compiler.lua" -Text $streamCompilerText -Needle "function M.apply(plan)"

$generationPlanText = Read-MIRFile -RelativePath "prototypes/mir/planner/generation_plan.lua"
Assert-MIRContains -RelativePath "prototypes/mir/planner/generation_plan.lua" -Text $generationPlanText -Needle "function Plan:finalize()"
Assert-MIRContains -RelativePath "prototypes/mir/planner/generation_plan.lua" -Text $generationPlanText -Needle "duplicate technology name"

$familyRegistryText = Read-MIRFile -RelativePath "prototypes/mir/families/registry.lua"
Assert-MIRContains -RelativePath "prototypes/mir/families/registry.lua" -Text $familyRegistryText -Needle "FamilyRule must be data-only"
Assert-MIRContains -RelativePath "prototypes/mir/families/registry.lua" -Text $familyRegistryText -Needle "Duplicate FamilyRule id"

foreach ($relativePath in @(
  "prototypes/mir/policy/competing_productivity.lua",
  "prototypes/mir/policy/competing_base_extensions.lua",
  "prototypes/mir/policy/productivity_family_adoption.lua",
  "prototypes/mir/policy/weapon_speed.lua",
  "prototypes/mir/policy/max_level.lua"
)) {
  $policyText = Read-MIRFile -RelativePath $relativePath
  if ($policyText -match '(?:tech|technology|owner)\.(?:effects|max_level)\s*=(?!=)' -or $policyText -match 'replace_technology\(') {
    throw "Policy module retains prototype mutation: $relativePath"
  }
}

$adoptionTransactionText = Read-MIRFile -RelativePath "prototypes/mir/emit/transactions/productivity_family_adoption.lua"
Assert-MIRContains -RelativePath "prototypes/mir/emit/transactions/productivity_family_adoption.lua" -Text $adoptionTransactionText -Needle "table.insert(owner.effects, effect)"

$settingsProfileText = Read-MIRFile -RelativePath "prototypes/mir/runtime/settings_profile.lua"
Assert-MIRContains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $settingsProfileText -Needle '"mir-settings-export"'
Assert-MIRContains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $settingsProfileText -Needle '"mir-settings-import-check"'
Assert-MIRContains -RelativePath "prototypes/mir/runtime/settings_profile.lua" -Text $settingsProfileText -Needle 'remote.add_interface("more-infinite-research-settings"'

$targetLineText = Read-MIRFile -RelativePath "prototypes/mir/platform/factorio/target_line.lua"
Assert-MIRContains -RelativePath "prototypes/mir/platform/factorio/target_line.lua" -Text $targetLineText -Needle 'require("prototypes.mir.platform.factorio.target_profiles")'
Assert-MIRContains -RelativePath "prototypes/mir/platform/factorio/target_line.lua" -Text $targetLineText -Needle "function M.runtime_state_backend()"

$runtimeStateAdapterText = Read-MIRFile -RelativePath "prototypes/mir/platform/factorio/runtime_state.lua"
Assert-MIRContains -RelativePath "prototypes/mir/platform/factorio/runtime_state.lua" -Text $runtimeStateAdapterText -Needle 'backend == "storage"'
Assert-MIRContains -RelativePath "prototypes/mir/platform/factorio/runtime_state.lua" -Text $runtimeStateAdapterText -Needle 'backend == "global"'

$runtimeStateText = Read-MIRFile -RelativePath "prototypes/mir/runtime/state.lua"
Assert-MIRContains -RelativePath "prototypes/mir/runtime/state.lua" -Text $runtimeStateText -Needle 'require("prototypes.mir.platform.factorio.runtime_state")'

foreach ($relative in @(
  "prototypes/mir/runtime/scripted_techs.lua",
  "prototypes/mir/runtime/effects/spoilage_preservation.lua",
  "prototypes/mir/runtime/effects/agricultural_growth_speed.lua"
)) {
  $text = Read-MIRFile -RelativePath $relative
  Assert-MIRContains -RelativePath $relative -Text $text -Needle "return M"
}

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes" `
  -Pattern 'require\("prototypes\.(compat|lib|config|util|diagnostics|tech-gen|settings-resolver|pipeline-extent|pipeline-extent-settings|technology-effect-safety|base-tech-extensions|max-level-control|weapon-speed-adjustments)' `
  -Message "Production Lua must not require old MIR 2.x shim paths."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes" `
  -Pattern 'require\("control\.' `
  -Message "Production Lua must not require the removed control/ runtime namespace."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/domain" `
  -Pattern "\b(data\.raw|data:extend|mods|settings)\b" `
  -Message "MIR domain modules must not read Factorio globals or mutate prototypes."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/capabilities" `
  -Pattern "data:extend" `
  -Message "MIR capability modules must not emit prototypes directly."

$capabilityRegistryText = Read-MIRFile -RelativePath "prototypes/mir/capabilities/registry.lua"
if ($capabilityRegistryText.Contains("lifecycle_passthrough")) {
  throw "Capability lifecycle stages must perform explicit state transitions, not alias a passthrough function."
}
foreach ($stage in @("discovered", "classified", "proposed", "validated", "materialized", "result")) {
  Assert-MIRContains -RelativePath "prototypes/mir/capabilities/registry.lua" -Text $capabilityRegistryText -Needle ('"' + $stage + '"')
}

foreach ($runtimeHandler in @(
  "prototypes/mir/runtime/scripted_techs.lua",
  "prototypes/mir/runtime/settings_profile.lua",
  "prototypes/mir/runtime/productivity_family_adoption.lua",
  "prototypes/mir/runtime/effects/spoilage_preservation.lua",
  "prototypes/mir/runtime/effects/agricultural_growth_speed.lua"
)) {
  $handlerText = Read-MIRFile -RelativePath $runtimeHandler
  Assert-MIRContains -RelativePath $runtimeHandler -Text $handlerText -Needle "M.requires_features = {"
}

$fixturesManifestText = Read-MIRFile -RelativePath ".mir/fixtures.yml"
foreach ($fixtureId in @(
  "rigor-late-recipe-removal",
  "generated-prerequisite-safety",
  "settings-visibility",
  "prototype-limits",
  "effect-scaling",
  "scripted-runtime-lifecycle",
  "upgrade-3-0-5-to-3-1-0",
  "competing-productivity-transaction",
  "competing-base-extension-transaction",
  "settings-profile-roundtrip",
  "reduced-settings-surface",
  "weapon-speed-safety",
  "air-scrubbing",
  "atan-ash",
  "atan-nuclear-science",
  "aai-loaders",
  "big-mining-drill",
  "omega-drill"
)) {
  if ($fixturesManifestText -notmatch ("(?ms)^  " + [regex]::Escape($fixtureId) + ":\s*\r?\n    requires_features: \[")) {
    throw "Governed fixture $fixtureId must declare positive target feature requirements."
  }
}

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/runtime" `
  -Pattern "\b(global|storage)\b" `
  -Message "MIR runtime modules must access persisted state through the platform runtime-state adapter."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/compatibility/overlays" `
  -Pattern "\bdata\.raw\b|data:extend" `
  -Message "MIR compatibility overlays must stay declarative."

$compatibilityRepairText = Read-MIRFile -RelativePath "prototypes/mir/compatibility/repairs/factorio_2_1_recipe_schema.lua"
foreach ($needle in @(
  '["atan-ash"]',
  '["2.2.1"] = true',
  '"atan-landfill-from-ash"',
  '"atan-ash-seperation"',
  'product.independent_probability = product.probability',
  'product.probability = nil',
  '["atan-nuclear-science"]',
  '["0.3.3"] = true',
  '"automation-science-pack"',
  '"fission-reactor-equipment"',
  '"nuclear-science-pack"',
  '"uranium-rounds-magazine"',
  'recipe.categories = categories',
  'recipe.category = nil',
  'recipe.additional_categories = nil',
  'D.rule_mutation({'
)) {
  Assert-MIRContains -RelativePath "prototypes/mir/compatibility/repairs/factorio_2_1_recipe_schema.lua" -Text $compatibilityRepairText -Needle $needle
}

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/report" `
  -Pattern "\bdata\.raw\b|data:extend" `
  -Message "MIR report modules must not mutate prototypes."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/settings" `
  -Pattern "\bdata\.raw\b|forced_value" `
  -Message "MIR settings modules must not inspect finalized prototypes or force hidden values."

$settingsExtendMatches = @(
  Get-ChildItem -LiteralPath (Get-MIRPath -RelativePath "prototypes/mir/settings") -Recurse -File -Filter "*.lua" |
    Where-Object { [System.IO.Path]::GetRelativePath($repo, $_.FullName).Replace("\", "/") -ne "prototypes/mir/settings/stage_builder.lua" } |
    Select-String -Pattern "data:extend"
)
if ($settingsExtendMatches.Count -gt 0) {
  $settingsExtendMatches | Write-Host
  throw "Only prototypes/mir/settings/stage_builder.lua may register setting prototypes with data:extend."
}

$runtimePrototypePattern = "\bdata\.raw\b|data:extend"
Assert-MIRNoPatternInLuaFile `
  -RelativePath "control.lua" `
  -Pattern $runtimePrototypePattern `
  -Message "MIR root runtime entrypoint must not perform prototype-stage work."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/runtime" `
  -Pattern $runtimePrototypePattern `
  -Message "MIR runtime modules must not perform prototype-stage work."

Assert-MIRNoTopLevelRequireCycles

Write-Host "[ok] MIR architecture boundary lint passed."
