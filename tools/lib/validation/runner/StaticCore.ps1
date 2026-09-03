Invoke-RepoCheck "info.json parses" {
  $null = $repoInfo
}

Invoke-RepoCheck "target profile views match canonical manifest" {
  & (Join-Path $repo "tools\commands\targets\Sync-MIRTargetProfiles.ps1") -RepoRoot $repo -Check
}

Invoke-RepoCheck "release authority views match the canonical ledger" {
  & (Join-Path $repo "tests\release\Test-MIRReleaseAuthority.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "terminal baseline calibrations are exact and deterministic" {
  & (Join-Path $repo "tests\release\Test-MIRTerminalBaselineCapture.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 R0 distribution identity is exact and V2-only" {
  & (Join-Path $repo "tests\release\Test-MIR4R0Identity.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 W00 release governance is separated and honestly classified" {
  & (Join-Path $repo "tests\mir4\Test-MIR4ReleaseGovernanceW00.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 W01 repository shadow fixed point has one writer and no unknown path" {
  & (Join-Path $repo "tests\repository\Test-MIR4RepositoryFixedPoint.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 W02 target compiler separates identity, support, profiles, and product policy" {
  & (Join-Path $repo "tests\mir4\Test-MIR4TargetCompilerW02.ps1") -RepoRoot $repo
}

  Invoke-RepoCheck "MIR 4 W03 semantic compiler is a complete non-mutating reference aggregate" {
    & (Join-Path $repo "tests\mir4\Test-MIR4SemanticCompilationW03.ps1") -RepoRoot $repo
  }

  Invoke-RepoCheck "MIR 4 W04 runtime, state, migration, and continuity contracts are package-excluded" {
    & (Join-Path $repo "tests\mir4\Test-MIR4RuntimeContinuityW04.ps1") -RepoRoot $repo -CandidateZip $CandidateZip
  }

Invoke-RepoCheck "MIR 4 public feedback has one governed reproducer and authority map per family" {
  & (Join-Path $repo "tests\mir4\Test-MIR4PublicFeedbackIntake.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-03 normalized maximum-level binding and exact runtime evidence are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4MaximumLevelSOL03.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-04 production-route policy and exact runtime evidence are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4ProductionRouteSOL04.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-05 ResearchCostModel V2 preview and stable-defer boundary are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4ResearchCostV2SOL05.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-06 bounded K2 science policy and exact target evidence are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4K2ScienceSOL06.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-07 exact compatibility subject ledger and bounded campaign outcomes are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4CompatibilityCampaignSOL07.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-08 affected-target packages, exact loads, and two-reload upgrade proof are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4AffectedProofSOL08.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 SOL-09 M4C01 development closeout and exact release blockers are complete" {
  & (Join-Path $repo "tests\mir4\Test-MIR4M4C01CloseoutSOL09.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR 4 bootstrap materialization and offline custody are deterministic and proof-only" {
  & (Join-Path $repo "tools\commands\release\Test-MIR4R0Bootstrap.ps1") -RepoRoot $repo
  & (Join-Path $repo "tests\release\Test-MIR4FinalProgrammeReconciliation.ps1") -RepoRoot $repo
  & (Join-Path $repo "tests\release\Test-MIR3Dot9ModPortalVisibilityRecheck.ps1") -RepoRoot $repo
  & (Join-Path $repo "tests\release\Test-MIR4BootstrapTargetReadiness.ps1") -RepoRoot $repo
  & (Join-Path $repo "tests\release\Test-MIR4LocalPlaytestShadow.ps1") -RepoRoot $repo
  & (Join-Path $repo "tests\release\Test-MIR4BootstrapMaterialization.ps1") -RepoRoot $repo
  & (Join-Path $repo "tests\release\Test-MIR4OfflineCandidateCustody.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "terminal exact-engine observation normalization is deterministic" {
  & (Join-Path $repo "tests\release\Test-MIRTerminalEngineObservation.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "backport source lock is current when present" {
  & (Join-Path $repo "tests\release\Test-MIRBackportSourceLock.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "canonical backport reconstruction manifests are complete" {
  $manifestRoot = Join-Path $repo ".mir\backports"
  if (Test-Path -LiteralPath $manifestRoot -PathType Container) {
    foreach ($manifest in @(Get-ChildItem -LiteralPath $manifestRoot -Filter "*.json" -File | Sort-Object Name)) {
      & (Join-Path $repo "tests\release\Test-MIRBackportManifest.ps1") -RepoRoot $repo -ManifestPath $manifest.FullName -AllowPendingTags
    }
  }
}

Invoke-RepoCheck "release candidate evidence is fresh or explicitly rebuilding" {
  & (Join-Path $repo "tests\release\Test-MIRCandidateFreshness.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "release metadata matches Factorio line" {
  $deps = @($repoInfo.dependencies)

  if ($isFactorio017Line) {
    if ($deps -notcontains "base >= 0.17") {
      throw "Factorio 0.17 metadata must declare base >= 0.17."
    }

    $newerDeps = @($deps | Where-Object { $_ -match ">=\s*(0\.18|1|2)\." -or $_ -match "(space-age|quality|recycler|elevated-rails)" })
    if ($newerDeps.Count -gt 0) {
      throw "Factorio 0.17 metadata must not carry Factorio 0.18, 1.x, 2.x, or DLC dependencies: $($newerDeps -join ', ')"
    }
  } elseif ($isFactorio018Line) {
    if ($deps -notcontains "base >= 0.18") {
      throw "Factorio 0.18 metadata must declare base >= 0.18."
    }

    $newerDeps = @($deps | Where-Object { $_ -match ">=\s*(1|2)\." -or $_ -match "(space-age|quality|recycler|elevated-rails)" })
    if ($newerDeps.Count -gt 0) {
      throw "Factorio 0.18 metadata must not carry Factorio 1.x, 2.x, or DLC dependencies: $($newerDeps -join ', ')"
    }
  } elseif ($isFactorio10Line) {
    if ($deps -notcontains "base >= 1.0") {
      throw "Factorio 1.0 metadata must declare base >= 1.0."
    }

    $newerDeps = @($deps | Where-Object { $_ -match ">=\s*(1\.1|2)\." -or $_ -match "(space-age|quality|recycler|elevated-rails)" })
    if ($newerDeps.Count -gt 0) {
      throw "Factorio 1.0 metadata must not carry Factorio 1.1, 2.x, or DLC dependencies: $($newerDeps -join ', ')"
    }
  } elseif ($isFactorio11Line) {
    if ($deps -notcontains "base >= 1.1") {
      throw "Factorio 1.1 metadata must declare base >= 1.1."
    }

    $newerDeps = @($deps | Where-Object { $_ -match ">=\s*2\." -or $_ -match "(space-age|quality|recycler|elevated-rails)" })
    if ($newerDeps.Count -gt 0) {
      throw "Factorio 1.1 metadata must not carry Factorio 2.x or DLC dependencies: $($newerDeps -join ', ')"
    }
  } elseif ($isLegacyFactorio20) {
    if ($deps -notcontains "base >= 2.0") {
      throw "Factorio 2.0 legacy metadata must declare base >= 2.0."
    }

    $factorio21Deps = @($deps | Where-Object { $_ -match ">=\s*2\.1" })
    if ($factorio21Deps.Count -gt 0) {
      throw "Factorio 2.0 legacy metadata must not carry Factorio 2.1 dependency floors: $($factorio21Deps -join ', ')"
    }
  } elseif ($isFactorio21Line) {
    $requiredDeps = @(
      "base >= 2.1.8",
      "(?) elevated-rails",
      "? recycler >= 2.1.8",
      "(?) quality",
      "(?) Krastorio2",
      "(?) Krastorio2-spaced-out",
      "(?) space-exploration",
      "? space-age >= 2.1.8"
    )
    foreach ($requiredDep in $requiredDeps) {
      if ($deps -notcontains $requiredDep) {
        throw "Factorio 2.1 metadata must declare dependency '$requiredDep'."
      }
    }
    if ($deps | Where-Object { $_ -match "^\?\s+elevated-rails(\s|$)" }) {
      throw "Elevated Rails must be a hidden optional dependency because MIR's Rail productivity support for it is opportunistic."
    }
    if ($deps | Where-Object { $_ -match "^\?\s+quality(\s|$)" }) {
      throw "Quality must be a hidden optional dependency so module productivity can see quality module recipes without advertising a visible dependency."
    }
    if ($deps | Where-Object { $_ -match "^\?\s+space-exploration(\s|$)" }) {
      throw "Space Exploration must be a hidden optional dependency so its final recipe removals run before MIR without advertising broad support."
    }
    if ($deps | Where-Object { $_ -match "^\?\s+(Krastorio2|Krastorio2-spaced-out)(\s|$)" }) {
      throw "Krastorio load-order contracts must be hidden optional dependencies so final science and lab rewrites run before MIR without advertising broad support."
    }
    $hiddenVersionFloors = @($deps | Where-Object { $_ -match "^\(\?\)\s+(elevated-rails|quality|Krastorio2|Krastorio2-spaced-out|space-exploration)\s+>=" })
    if ($hiddenVersionFloors.Count -gt 0) {
      throw "Hidden optional dependency version floors should not gate graceful degradation: $($hiddenVersionFloors -join ', ')"
    }
  } else {
    throw "Unsupported factorio_version in info.json: $($repoInfo.factorio_version)"
  }
}

Invoke-RepoCheck "release metadata avoids compatibility mod dependencies" {
  $deps = @($repoInfo.dependencies)
  $compatDependencyModIds = @(
    "Advanced-Electric-Revamped-v16",
    "Better_Robots_Extended",
    "OCs_ammo_casting",
    "OCs_stone_casting",
    "fluid-quality-imprinting",
    "plates-n-circuit-productivity"
  )
  $present = @(
    foreach ($dep in $deps) {
      foreach ($modId in $compatDependencyModIds) {
        if ($dep -match "^\?\s+$([regex]::Escape($modId))(\s|$)") {
          $dep
        }
      }
    }
  )
  if ($present.Count -gt 0) {
    throw "Unexpected compatibility mod dependencies in info.json: $($present -join ', ')"
  }
}

Invoke-RepoCheck "docs match opportunistic compatibility policy" {
  $forbiddenPhrases = @(
    "declared as optional dependencies so More Infinite Research",
    "optional load-order dependencies",
    "optional dependencies for Space Age and known compatibility targets",
    "add optional or hidden optional dependencies"
  )
  foreach ($file in Get-PolicyTextFiles) {
    $text = Get-Content -Raw -LiteralPath $file.FullName
    foreach ($phrase in $forbiddenPhrases) {
      if ($text.Contains($phrase)) {
        throw "Forbidden optional dependency policy phrase found in $(Get-RepoRelativePath $file.FullName): $phrase"
      }
    }
  }
}

Invoke-RepoCheck "docs and governance manifests are linted" {
  & (Join-Path $repo "tests\tooling\Test-MIRGovernance.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR architecture boundaries are linted" {
  & (Join-Path $repo "tests\architecture\Test-MIRArchitecture.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "settings visibility policy is linted" {
  & (Join-Path $repo "tests\compiler\Test-MIRSettingsVisibility.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "legacy inventory thresholds pass" {
  & (Join-Path $repo "tools\commands\workspace\Get-MIRLegacyInventory.ps1") -RepoRoot $repo -CheckThresholds
}

Invoke-RepoCheck "no old tool-based science pack authority remains" {
  $matches = Find-RepositoryText -Path (Join-Path $repo "prototypes") -Pattern "data.raw.tool|tool_exists|has_tool|PACKS_ALL"
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "Old science-pack authority references remain."
  }
}

Invoke-RepoCheck "generated count formulas use the unified canonical research-cost model" {
  & (Join-Path $repo "tests\compiler\Test-MIRResearchCostModels.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "generated icons do not use icon_mipmaps" {
  $matches = Find-RepositoryText -Path (Join-Path $repo "prototypes") -Pattern "icon_mipmaps"
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "icon_mipmaps references remain in prototypes."
  }
}

Invoke-RepoCheck "local image assets have source notes and do not bundle Space Age art" {
  $assetSourcePath = Join-Path $repo "docs\reference\asset-sources.md"
  if (-not (Test-Path -LiteralPath $assetSourcePath)) {
    throw "Missing local asset source manifest: docs/reference/asset-sources.md"
  }

  $assetSourceText = Get-Content -Raw -LiteralPath $assetSourcePath
  $imageExtensions = @(".png", ".jpg", ".jpeg", ".webp", ".gif")
  $governedPaths = @(& git -C $repo ls-files --cached --others --exclude-standard)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate governed repository assets." }
  $imageFiles = @(
    foreach ($candidatePath in @($governedPaths | Sort-Object -Unique)) {
      $relative = ([string]$candidatePath).Replace("\", "/")
      $path = Join-Path $repo $relative
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
        if (
        $imageExtensions -contains $extension `
          -and -not $relative.StartsWith(".mir/target-lines/") `
          -and -not $relative.StartsWith("build/results/") `
          -and -not $relative.StartsWith("build/") `
          -and -not $relative.StartsWith("dist/") `
          -and -not $relative.StartsWith("tmp/")
        ) { Get-Item -LiteralPath $path }
      }
    }
  )

  foreach ($imageFile in $imageFiles) {
    $relative = [System.IO.Path]::GetRelativePath($repo.Path, $imageFile.FullName).Replace("\", "/")
    if ($relative -match "(^|/|[-_.])space[-_]?age($|/|[-_.])" -or $relative -match "__space-age__") {
      throw "Local image asset appears to bundle Space Age art by path/name and is not allowed in MIR: $relative"
    }
    if (-not $assetSourceText.Contains($relative)) {
      throw "Local image asset is missing an explicit source/license note in docs/reference/asset-sources.md: $relative"
    }
  }
}

Invoke-RepoCheck "control runtime avoids tick handlers" {
  $luaFiles = @()
  $controlLua = Join-Path $repo "control.lua"
  $runtimeDir = Join-Path $repo "prototypes\mir\runtime"

  if (Test-Path -LiteralPath $controlLua) {
    $luaFiles += Get-Item -LiteralPath $controlLua
  }
  if (Test-Path -LiteralPath $runtimeDir) {
    $luaFiles += @(Get-ChildItem -LiteralPath $runtimeDir -Recurse -File -Filter "*.lua")
  }

  $matches = @(
    foreach ($file in $luaFiles) {
      Select-String -LiteralPath $file.FullName -Pattern "defines\.events\.on_tick|script\.on_nth_tick"
    }
  )

  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "Runtime tick handlers are not allowed without an explicit documented allowlist and disabled-by-default feature gate."
  }
}

Invoke-RepoCheck "scripted technology defaults and risks remain explicit" {
  $defaultsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\defaults.lua")
  if ($isReducedLegacyLine) {
    if ($defaultsText -match "research_(spoilage_preservation|agricultural_growth_speed)\s*=") {
      throw "Factorio $($repoInfo.factorio_version) must omit scripted Space Age streams instead of carrying disabled settings."
    }
    return
  }
  if ($defaultsText -notmatch "(?s)research_spoilage_preservation\s*=\s*\{.*?enabled\s*=\s*true") {
    throw "Spoilage preservation must be enabled by default."
  }
  $directEffectsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\direct-effects.lua")
  if ($directEffectsText -notmatch '(?s)research_spoilage_preservation\s*=\s*\{.*?technology_risk\s*=\s*\{.*?class\s*=\s*"factory-disruptive"') {
    throw "Spoilage preservation must retain its explicit factory-disruptive classification independently of its default."
  }
  if ($defaultsText -notmatch "(?s)research_agricultural_growth_speed\s*=\s*\{.*?enabled\s*=\s*true") {
    throw "Agricultural growth speed should be enabled by default as a promoted special technology."
  }
}

Invoke-RepoCheck "unsafe pickup reach technology effects are blocked" {
  $safetyPath = Join-Path $repo "prototypes\mir\domain\technology\effect_safety_policy.lua"
  if (-not (Test-Path -LiteralPath $safetyPath)) {
    throw "Missing technology effect safety policy: prototypes/mir/domain/technology/effect_safety_policy.lua"
  }

  $safetyText = Get-Content -Raw -LiteralPath $safetyPath
  $directEffectsPlannerText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\direct_effects.lua")
  $streamAdapterText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\emit\stream_spec_adapter.lua")
  $technologyDesignAdapterText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\emit\technology_design_adapter.lua")
  $baseContinuationsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\planner\base_continuations.lua")
  $technologyOperationExecutorText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\emit\technology_operation_executor.lua")
  $graphSafetyText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\emit\technology_graph_safety.lua")
  $pipelineCommandsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\pipeline\commands.lua")
  $integrityContractsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\integrity\effect_contracts.lua")
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $dataFinalFixesStageText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\stage\data_final_fixes.lua")
  $generationIntegrityFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generation-integrity\data-final-fixes.lua")

  foreach ($effectType in @("character-item-pickup-distance", "character-loot-pickup-distance")) {
    if (-not $safetyText.Contains($effectType)) {
      throw "Technology effect safety guard must block unsafe effect type: $effectType"
    }
  }

  $requiredGuardSnippets = @(
    @{ File = "prototypes\mir\planner\direct_effects.lua"; Text = $directEffectsPlannerText; Snippet = 'effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)' },
    @{ File = "prototypes\mir\emit\technology_design_adapter.lua"; Text = $technologyDesignAdapterText; Snippet = 'generated_registry.register(technology.name,' },
    @{ File = "prototypes\mir\planner\base_continuations.lua"; Text = $baseContinuationsText; Snippet = 'effect_safety.assert_effects_allowed(desired_effects, "base extension " .. key)' },
    @{ File = "prototypes\mir\emit\technology_operation_executor.lua"; Text = $technologyOperationExecutorText; Snippet = 'technology_design_adapter.emit(design, {' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.stage.data_final_fixes").run()' },
    @{ File = "prototypes\mir\stage\data_final_fixes.lua"; Text = $dataFinalFixesStageText; Snippet = 'commands.run_all({return_snapshot = false})' },
    @{ File = "prototypes\mir\pipeline\commands.lua"; Text = $pipelineCommandsText; Snippet = '.sanitize_all_technology_effects({pass = "input"})' },
    @{ File = "prototypes\mir\pipeline\commands.lua"; Text = $pipelineCommandsText; Snippet = 'local ledger = effect_safety.sanitize_all_technology_effects({' },
    @{ File = "prototypes\mir\pipeline\commands.lua"; Text = $pipelineCommandsText; Snippet = 'pass = "output",' },
    @{ File = "prototypes\mir\pipeline\commands.lua"; Text = $pipelineCommandsText; Snippet = 'effect_safety.assert_registered_technology_effects(target_inventory)' },
    @{ File = "prototypes\mir\integrity\effect_contracts.lua"; Text = $integrityContractsText; Snippet = 'for _, target in ipairs(contract.targets or {}) do' },
    @{ File = "prototypes\mir\emit\technology_graph_safety.lua"; Text = $graphSafetyText; Snippet = 'generated_registry.sorted_names()' },
    @{ File = "prototypes\mir\emit\technology_graph_safety.lua"; Text = $graphSafetyText; Snippet = 'graph_snapshot.matches_prototypes(expected.graph_snapshot, actual_technologies)' },
    @{ File = "prototypes\mir\emit\technology_graph_safety.lua"; Text = $graphSafetyText; Snippet = 'graph_diff.compare(expected.graph_snapshot, actual_snapshot)' },
    @{ File = "prototypes\mir\emit\technology_graph_safety.lua"; Text = $graphSafetyText; Snippet = 'proof.status ~= "passed"' },
    @{ File = "prototypes\mir\emit\technology_graph_safety.lua"; Text = $graphSafetyText; Snippet = 'assert_equal("graph fingerprint", comparison_snapshot.graph_fingerprint, actual_snapshot.graph_fingerprint)' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_no_blocked_pickup_effects()' }
  )

  foreach ($check in $requiredGuardSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing unsafe pickup reach guard in $($check.File): $($check.Snippet)"
    }
  }

  $safetyRelative = "prototypes/mir/domain/technology/effect_safety_policy.lua"
  $prototypeLuaFiles = Get-ChildItem -LiteralPath (Join-Path $repo "prototypes") -Recurse -File -Filter "*.lua"
  foreach ($file in $prototypeLuaFiles) {
    $relative = Get-RepoRelativePath $file.FullName
    if ($relative -eq $safetyRelative) { continue }
    $text = Get-Content -Raw -LiteralPath $file.FullName
    foreach ($effectType in @("character-item-pickup-distance", "character-loot-pickup-distance")) {
      if ($text.Contains($effectType)) {
        throw "Unsafe pickup reach effect type appears outside the safety guard in ${relative}: $effectType"
      }
    }
  }
}

Invoke-RepoCheck "merged trash-slot technology has save migration" {
  $migrationPath = Join-Path $repo "migrations\more-infinite-research_2.0.5.json"
  if (-not (Test-Path -LiteralPath $migrationPath)) {
    throw "Missing migration for removed character trash-slot technology: $migrationPath"
  }

  $migration = Get-Content -Raw -LiteralPath $migrationPath | ConvertFrom-Json
  $found = $false
  foreach ($mapping in @($migration.technology)) {
    $values = @($mapping)
    if ($values.Count -eq 2 `
        -and $values[0] -eq "recipe-prod-research_character_trash_slots-1" `
        -and $values[1] -eq "recipe-prod-research_inventory_capacity-1") {
      $found = $true
      break
    }
  }

  if (-not $found) {
    throw "Migration must map recipe-prod-research_character_trash_slots-1 to recipe-prod-research_inventory_capacity-1."
  }
}

Invoke-RepoCheck "locale files match English fallback" {
  & (Join-Path $repo "tests\docs\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
}

Invoke-RepoCheck "PowerShell scripts parse and avoid duplicate parameters" {
  & (Join-Path $repo "tests\tooling\Test-MIRPowerShellQuality.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "scenario schema 2 manifests own complete execution records" {
  & (Join-Path $repo "tests\compatibility\Test-MIRScenarioManifests.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "runtime scenario authority matches target-native invocations" {
  & (Join-Path $repo "tools\commands\targets\Sync-MIRRuntimeScenarioAuthority.ps1") -RepoRoot $repo -Check
}

Invoke-RepoCheck "ecosystem campaigns declare exact sanitation budgets" {
  & (Join-Path $repo "tests\release\Test-MIRSanitationBudgets.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "active release evidence is portable and summary-oriented" {
  & (Join-Path $repo "tests\release\Test-MIREvidenceHygiene.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "planner artifact tools are deterministic and schema-bound" {
  & (Join-Path $repo "tests\tooling\Test-MIRPlannerTools.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "the exact active-release approved delta is complete" {
  & (Join-Path $repo "tests\release\Test-MIRApprovedDelta.ps1") -ValidateStructureOnly
}

Invoke-RepoCheck "compiler schema authorities and reference docs do not drift" {
  & (Join-Path $repo "tests\compiler\Test-MIRCompilerSchemaDrift.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "compiler contract coverage and mutation sentinels are complete" {
  & (Join-Path $repo "tests\compiler\Test-MIRCompilerContractCoverage.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "technology lifecycle records and review tooling are schema-bound" {
  & (Join-Path $repo "tests\compiler\Test-MIRTechnologyLifecycle.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "technology policy corpora and applicability envelopes are governed" {
  & (Join-Path $repo "tests\compiler\Test-MIRTechnologyPolicy.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "offline family-rule synthesis is deterministic and review-only" {
  & (Join-Path $repo "tests\compiler\Test-MIRRuleSynthesis.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "semantic mod interactions and combination campaigns are complete" {
  & (Join-Path $repo "tests\compatibility\Test-MIRModInteractions.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "compatibility dependency declarations preserve full mod names" {
  & (Join-Path $repo "tests\compatibility\Test-MIRDependencyResolver.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "performance budgets declare every required surface" {
  & (Join-Path $repo "tests\release\Test-MIRPerformanceBudgets.ps1") -RepoRoot $repo -ValidateManifestOnly
}

Invoke-RepoCheck "validation scenario groups and partial result aggregation are stable" {
  & (Join-Path $repo "tests\tooling\Test-MIRValidationResults.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "package and harness fingerprints are checkout-line-ending invariant" {
  & (Join-Path $repo "tests\package\Test-MIRPackageIdentity.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "Markdown formatter preserves structural syntax" {
  & (Join-Path $repo "tests\docs\Test-MIRMarkdownFormatting.ps1") -RepoRoot $repo
}

