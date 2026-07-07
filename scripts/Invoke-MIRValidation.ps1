param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$FactorioLog = $env:FACTORIO_LOG,
  [string]$UserDataDir = $env:FACTORIO_USERDATA,
  [switch]$DocsOnly,
  [switch]$ManifestsOnly,
  [switch]$ArchitectureOnly,
  [switch]$StaticOnly
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoInfo = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
$isLegacyFactorio20 = $repoInfo.factorio_version -eq "2.0"
$isFactorio21Line = $repoInfo.factorio_version -eq "2.1"

function Invoke-RepoCheck {
  param([string]$Description, [scriptblock]$Script)
  Write-Host "[check] $Description"
  & $Script
}

function Find-RepositoryText {
  param(
    [string]$Path,
    [string]$Pattern
  )

  $files = Get-ChildItem -LiteralPath $Path -Recurse -File
  if (-not $files) { return @() }
  return @($files | Select-String -Pattern $Pattern)
}

function Get-RepoRelativePath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  return [System.IO.Path]::GetRelativePath($repo.Path, $resolved).Replace("\", "/")
}

function Get-MIRCombinedSourceText {
  param([Parameter(Mandatory)][string[]]$RelativePaths)

  $chunks = @()
  foreach ($relative in $RelativePaths) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path) {
      $chunks += Get-Content -Raw -LiteralPath $path
    }
  }

  return ($chunks -join "`n")
}

function Get-MIRSettingsSourceText {
  return Get-MIRCombinedSourceText -RelativePaths @(
    "settings.lua",
    "prototypes/mir/stage/settings.lua",
    "prototypes/mir/legacy/settings.lua"
  )
}

function Get-MIRDataFinalFixesSourceText {
  return Get-MIRCombinedSourceText -RelativePaths @(
    "data-final-fixes.lua",
    "prototypes/mir/stage/data_final_fixes.lua",
    "prototypes/mir/legacy/data_final_fixes.lua"
  )
}

function Get-DocumentationFiles {
  $files = @()
  $readmePath = Join-Path $repo "README.md"
  if (Test-Path -LiteralPath $readmePath) {
    $files += Get-Item -LiteralPath $readmePath
  }
  $todoPath = Join-Path $repo "todo.md"
  if (Test-Path -LiteralPath $todoPath) {
    $files += Get-Item -LiteralPath $todoPath
  }

  $docsPath = Join-Path $repo "docs"
  if (Test-Path -LiteralPath $docsPath) {
    $files += @(
      Get-ChildItem -LiteralPath $docsPath -Recurse -File |
        Where-Object { $_.Extension -in @(".md", ".txt") }
    )
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-PolicyTextFiles {
  $files = @()
  foreach ($relative in @("README.md", "changelog.txt")) {
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path) {
      $files += Get-Item -LiteralPath $path
    }
  }
  $files += Get-DocumentationFiles
  return @($files | Sort-Object FullName -Unique)
}

if ($DocsOnly -or $ManifestsOnly) {
  Invoke-RepoCheck "docs and governance manifests are linted" {
    & (Join-Path $repo "scripts\Test-MIRGovernance.ps1") -RepoRoot $repo
  }
  exit 0
}

if ($ArchitectureOnly) {
  Invoke-RepoCheck "docs and governance manifests are linted" {
    & (Join-Path $repo "scripts\Test-MIRGovernance.ps1") -RepoRoot $repo
  }
  Invoke-RepoCheck "MIR architecture boundaries are linted" {
    & (Join-Path $repo "scripts\Test-MIRArchitecture.ps1") -RepoRoot $repo
  }
  Invoke-RepoCheck "settings visibility policy is linted" {
    & (Join-Path $repo "scripts\Test-MIRSettingsVisibility.ps1") -RepoRoot $repo
  }
  exit 0
}

Invoke-RepoCheck "info.json parses" {
  $null = $repoInfo
}

Invoke-RepoCheck "release metadata matches Factorio line" {
  $deps = @($repoInfo.dependencies)

  if ($isLegacyFactorio20) {
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
    $hiddenVersionFloors = @($deps | Where-Object { $_ -match "^\(\?\)\s+(elevated-rails|quality)\s+>=\s*2\.1" })
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
  & (Join-Path $repo "scripts\Test-MIRGovernance.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "MIR architecture boundaries are linted" {
  & (Join-Path $repo "scripts\Test-MIRArchitecture.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "settings visibility policy is linted" {
  & (Join-Path $repo "scripts\Test-MIRSettingsVisibility.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "no old tool-based science pack authority remains" {
  $matches = Find-RepositoryText -Path (Join-Path $repo "prototypes") -Pattern "data.raw.tool|tool_exists|has_tool|PACKS_ALL"
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "Old science-pack authority references remain."
  }
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
  $imageFiles = @(
    Get-ChildItem -LiteralPath $repo -Recurse -File |
      Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($repo.Path, $_.FullName).Replace("\", "/")
        $extension = $_.Extension.ToLowerInvariant()
        $imageExtensions -contains $extension `
          -and -not $relative.StartsWith(".git/") `
          -and -not $relative.StartsWith("artifacts/") `
          -and -not $relative.StartsWith("build/") `
          -and -not $relative.StartsWith("dist/")
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
  $controlDir = Join-Path $repo "control"

  if (Test-Path -LiteralPath $controlLua) {
    $luaFiles += Get-Item -LiteralPath $controlLua
  }
  if (Test-Path -LiteralPath $controlDir) {
    $luaFiles += @(Get-ChildItem -LiteralPath $controlDir -Recurse -File -Filter "*.lua")
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

Invoke-RepoCheck "scripted candidate streams remain default-off before manual proof" {
  $defaultsText = Get-Content -Raw -LiteralPath (Join-Path $repo "defaults.lua")
  foreach ($streamKey in @("research_spoilage_preservation", "research_agricultural_growth_speed")) {
    if ($defaultsText -notmatch "(?s)$streamKey\s*=\s*\{.*?enabled\s*=\s*false") {
      throw "Scripted candidate stream $streamKey must remain disabled by default until manual save validation supports release claims."
    }
  }
}

Invoke-RepoCheck "unsafe pickup reach technology effects are blocked" {
  $safetyPath = Join-Path $repo "prototypes\technology-effect-safety.lua"
  if (-not (Test-Path -LiteralPath $safetyPath)) {
    throw "Missing technology effect safety guard: prototypes/technology-effect-safety.lua"
  }

  $safetyText = Get-Content -Raw -LiteralPath $safetyPath
  $techGenText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\tech-gen.lua")
  $streamEmitterText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\legacy\stream_emitter.lua")
  $baseExtensionsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\base-tech-extensions.lua")
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $generationIntegrityFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generation-integrity\data-final-fixes.lua")

  foreach ($effectType in @("character-item-pickup-distance", "character-loot-pickup-distance")) {
    if (-not $safetyText.Contains($effectType)) {
      throw "Technology effect safety guard must block unsafe effect type: $effectType"
    }
  }

  $requiredGuardSnippets = @(
    @{ File = "prototypes\tech-gen.lua"; Text = $techGenText; Snippet = 'effect_safety.assert_effect_allowed(effect, "direct-effect stream " .. key)' },
    @{ File = "prototypes\mir\legacy\stream_emitter.lua"; Text = $streamEmitterText; Snippet = 'effect_safety.register_generated_technology(technology.name)' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'effect_safety.assert_effects_allowed(desired_effects, "base extension " .. key)' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'effect_safety.register_generated_technology(new.name)' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.technology-effect-safety").assert_registered_technology_effects()' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_no_blocked_pickup_effects()' }
  )

  foreach ($check in $requiredGuardSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing unsafe pickup reach guard in $($check.File): $($check.Snippet)"
    }
  }

  $safetyRelative = "prototypes/technology-effect-safety.lua"
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
  & (Join-Path $repo "scripts\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
}

Invoke-RepoCheck "PowerShell scripts parse and avoid duplicate parameters" {
  & (Join-Path $repo "scripts\Test-MIRPowerShellQuality.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "fixture mods have metadata and data entrypoints" {
  $fixtureRootForStatic = Join-Path $repo "fixtures"
  if (-not (Test-Path -LiteralPath $fixtureRootForStatic)) {
    throw "Fixture directory not found: $fixtureRootForStatic"
  }

  $nonModFixtureDirs = @("compat-matrix", "run-profiles")
  foreach ($fixture in Get-ChildItem -LiteralPath $fixtureRootForStatic -Directory) {
    if ($nonModFixtureDirs -contains $fixture.Name) { continue }

    $infoPath = Join-Path $fixture.FullName "info.json"
    if (-not (Test-Path -LiteralPath $infoPath)) {
      throw "Fixture directory is missing info.json: $($fixture.FullName)"
    }

    $info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($info.name) -or $info.name -notmatch "^mir-fixture-") {
      throw "Fixture info.json must declare a mir-fixture-* name: $infoPath"
    }
    if ($info.factorio_version -ne $repoInfo.factorio_version) {
      throw "Fixture $($info.name) must target Factorio $($repoInfo.factorio_version) on this branch; found $($info.factorio_version)."
    }
    $fixtureBaseDependency = @($info.dependencies) | Where-Object { $_ -match "^base\s+>=" } | Select-Object -First 1
    if ($isLegacyFactorio20) {
      if ($fixtureBaseDependency -notmatch "^base\s+>=\s+2\.0(\.|$)") {
        throw "Fixture $($info.name) must use a Factorio 2.0 base dependency on legacy; found '$fixtureBaseDependency'."
      }
    } elseif ($isFactorio21Line) {
      if ($fixtureBaseDependency -notmatch "^base\s+>=\s+2\.1(\.|$)") {
        throw "Fixture $($info.name) must use a Factorio 2.1 base dependency on the main line; found '$fixtureBaseDependency'."
      }
    }

    $entryFiles = @(
      "data.lua",
      "data-updates.lua",
      "data-final-fixes.lua"
    )
    $hasEntry = $false
    foreach ($entryFile in $entryFiles) {
      if (Test-Path -LiteralPath (Join-Path $fixture.FullName $entryFile)) {
        $hasEntry = $true
        break
      }
    }
    if (-not $hasEntry) {
      throw "Fixture $($info.name) has no data-stage entry file."
    }
  }
}

Invoke-RepoCheck "science-pack progression settings are wired" {
  $settingsText = Get-MIRSettingsSourceText
  $utilText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\util.lua")
  $baseExtensionsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\base-tech-extensions.lua")
  $settingsResolverText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\settings-resolver.lua")
  $settingsRegistryText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\registry.lua")
  $settingsVisibilityText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\visibility.lua")
  $settingsBuilderText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\builder.lua")
  $settingsLegacyAdapterText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\settings\legacy_adapter.lua")
  $controlSettingsResolverText = Get-Content -Raw -LiteralPath (Join-Path $repo "control\settings-resolver.lua")
  $spoilageText = Get-Content -Raw -LiteralPath (Join-Path $repo "control\effects\spoilage-preservation.lua")
  $agriculturalGrowthText = Get-Content -Raw -LiteralPath (Join-Path $repo "control\effects\agricultural-growth-speed.lua")
  $scienceText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\lib\science-packs.lua")
  $directEffectsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\direct-effects.lua")
  $productivityText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\productivity.lua")
  $recipeMatchingText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\lib\recipe-matching.lua")
  $prototypeLookupText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\lib\prototype-lookup.lua")
  $technologyIconsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\lib\technology-icons.lua")
  $techGenText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\tech-gen.lua")
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $pipelineExtentText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\pipeline-extent.lua")
  $pipelineExtentSettingsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\pipeline-extent-settings.lua")
  $diagnosticsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\diagnostics.lua")
  $weaponSpeedText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\weapon-speed-adjustments.lua")
  $generationIntegrityFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-generation-integrity\data-final-fixes.lua")
  $fluidProductivityFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-fluid-productivity\data-final-fixes.lua")
  $pipelineExtentFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-pipeline-extent\data-final-fixes.lua")
  $betterBotBatteryFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-better-bot-battery-skip\data-final-fixes.lua")
  $airScrubbingFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua")
  $atanAshFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\atan-ash\data.lua")
  $atanAshAssertText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-atan-ash-separation\data-final-fixes.lua")
  $aaiLoaderFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-aai-loader-belt-productivity\data-final-fixes.lua")
  $bigMiningDrillFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-big-mining-drill-productivity\data-final-fixes.lua")
  $atanNuclearScienceFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-atan-nuclear-science-productivity\data-final-fixes.lua")
  $capabilityNegativeFixtureText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\capability-negative-cases\data.lua")
  $capabilityNegativeAssertText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\assert-capability-negative-cases\data-final-fixes.lua")
  $defaultsText = Get-Content -Raw -LiteralPath (Join-Path $repo "defaults.lua")
  $localeText = Get-Content -Raw -LiteralPath (Join-Path $repo "locale\en\more-infinite-research.cfg")

  $requiredSnippets = @(
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "ips-require-space-gate"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'default_value = false' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-science-pack-ingredient-policy"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'allowed_values = {"configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all"}' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-use-installed-space-age-icons"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'order = "a-120"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local pipeline_extent_settings = require("prototypes.pipeline-extent-settings")' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local settings_adapter = require("prototypes.mir.settings.legacy_adapter")' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-pipeline-extent-multiplier"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'type = "string-setting"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'allowed_values = pipeline_extent_settings.allowed_values' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'order = "a-130"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function append_note(description, note)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function add_technology_setting(group, setting)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local stream_sort_names = {' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_agricultural_growth_speed = "Agricultural growth speed"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_character_reach = "Character reach bonus"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_oil_processing_productivity = "Oil processing productivity"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_spoilage_preservation = "Spoilage preservation"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_thruster_fuel_productivity = "Thruster fuel productivity"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local function group_order_prefix(group)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local technology_setting_groups = {}' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'kind = "stream"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'kind = "base"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'settings_adapter.visibility_for_stream(stream, settings_context)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'settings_adapter.apply(setting, group and group.ui_visibility)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'local bucket = group.enabled and "100" or "000"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'order = "a-900"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "ips-enable-"..key' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'localised_description = append_note({"mod-setting-description.ips-enable-stream", tech_locale}, settings_note)' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'localised_name = {"mod-setting-name.mir-max-level", locale}' },
    @{ File = "prototypes\settings-resolver.lua"; Text = $settingsResolverText; Snippet = 'function R.stream_enabled(key, spec)' },
    @{ File = "prototypes\settings-resolver.lua"; Text = $settingsResolverText; Snippet = 'function R.base_enabled(key, spec)' },
    @{ File = "prototypes\mir\settings\registry.lua"; Text = $settingsRegistryText; Snippet = 'hidden_means_unavailable_not_deleted = true' },
    @{ File = "prototypes\mir\settings\registry.lua"; Text = $settingsRegistryText; Snippet = 'do_not_force_hidden_values_by_default = true' },
    @{ File = "prototypes\mir\settings\visibility.lua"; Text = $settingsVisibilityText; Snippet = 'function M.evaluate(spec, ctx)' },
    @{ File = "prototypes\mir\settings\visibility.lua"; Text = $settingsVisibilityText; Snippet = 'mode == "visible-if-mods-any"' },
    @{ File = "prototypes\mir\settings\visibility.lua"; Text = $settingsVisibilityText; Snippet = 'mode == "visible-if-mods-all"' },
    @{ File = "prototypes\mir\settings\builder.lua"; Text = $settingsBuilderText; Snippet = 'function M.apply_visibility(setting, result)' },
    @{ File = "prototypes\mir\settings\builder.lua"; Text = $settingsBuilderText; Snippet = 'setting.hidden = true' },
    @{ File = "prototypes\mir\settings\legacy_adapter.lua"; Text = $settingsLegacyAdapterText; Snippet = 'factorio_mods.snapshot()' },
    @{ File = "prototypes\settings-resolver.lua"; Text = $settingsResolverText; Snippet = 'startup_setting("ips-enable-" .. key)' },
    @{ File = "prototypes\settings-resolver.lua"; Text = $settingsResolverText; Snippet = 'startup_setting("mir-enable-" .. key)' },
    @{ File = "control\settings-resolver.lua"; Text = $controlSettingsResolverText; Snippet = 'function R.stream_enabled(key)' },
    @{ File = "control\settings-resolver.lua"; Text = $controlSettingsResolverText; Snippet = 'startup_setting("ips-enable-" .. key)' },
    @{ File = "control\effects\spoilage-preservation.lua"; Text = $spoilageText; Snippet = 'settings_resolver.stream_enabled(M.stream_key)' },
    @{ File = "control\effects\spoilage-preservation.lua"; Text = $spoilageText; Snippet = 'spoilage preservation skipped: disabled' },
    @{ File = "control\effects\agricultural-growth-speed.lua"; Text = $agriculturalGrowthText; Snippet = 'settings_resolver.stream_enabled(M.stream_key)' },
    @{ File = "control\effects\agricultural-growth-speed.lua"; Text = $agriculturalGrowthText; Snippet = 'agricultural growth speed force state refreshed enabled=' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'apply_science_pack_ingredient_policy' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'settings_resolver.stream_enabled(key, spec)' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'settings_resolver.base_enabled(key, spec)' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'append_end_game_gate_prerequisite' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'pack_list_official' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'is_official_science_pack' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'space_age_progression_packs_for' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'official_progression_packs_for' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'mod_progression_packs_for' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'desired == "all-official"' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'if data.raw.technology[new_name] then' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = '"target_exists"' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'apply_science_pack_ingredient_policy' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'append_end_game_gate_prerequisite' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'end_game_science_pack' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'icon_candidates={' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'inactive_mod_asset="space-age"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/processing-unit-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/low-density-structure-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/plastics-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/rocket-fuel-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '__space-age__/graphics/technology/research-productivity.png' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology="research-productivity", required_mod="space-age"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology="space-science-pack"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology="processing-unit"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_rocket_fuel = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_thruster_fuel_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_thruster_oxidizer_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_oil_processing_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_oil_cracking_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_lubricant_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_sulfuric_acid_productivity = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'overlay_loader.get("air-scrubbing")' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_air_scrubbing_clean_filter = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'mods_any = air_scrubbing_overlay.applies_when.mods' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'generation_requirements = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'manifest_id = air_scrubbing_capability.stream.id' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'exact_recipe_patterns(air_scrubbing_capability.exact_recipes)' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_ash_separation = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'overlay_loader.get("atan-ash")' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'mods_any = atan_ash_overlay.applies_when.mods' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'manifest_id = atan_ash_capability.stream.id' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'exact_recipe_patterns(atan_ash_capability.exact_recipes)' },
    @{ File = "prototypes\mir\compatibility\overlays\atan_ash.lua"; Text = (Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\compatibility\overlays\atan_ash.lua")); Snippet = '"mir-prod-atan-ash-separation"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'mods_any = {"space-age"}' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_ash_separation = "Ash separation productivity"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"aai-turbo-loader"' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'desired == "derive-from-unlocks"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_air_scrubbing_clean_filter = "Air Scrubbing clean-filter productivity"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{technology = "oil-processing"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"^acid%-neutralisation$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"^acid%-neutralization$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '{fluid = "sulfuric-acid"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'fluids = {"thruster-fuel"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '"^simple%-coal%-liquefaction$"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_walls = { icon_tech="gate", icon_item="stone-wall", groups = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'technology = "elevated-rail", required_mod = "elevated-rails"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'inactive_mod_asset = "elevated-rails"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'change = 0.05, items = { "rail-support" }' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'change = 0.02, items = { "rail-ramp" }' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_heavy_ammo = { icon_item="cannon-shell", groups = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'items={"artillery-shell","railgun-ammo"}' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '^omega%-drill$' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '^omega%-tau$' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "electric-weapons-damage-1", required_mod = "space-age"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '__space-age__/graphics/technology/electric-weapons-damage.png' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "discharge-defense-equipment"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology-description.more-infinite-research.electric_shooting_speed' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology-description.more-infinite-research.flamethrower_shooting_speed' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "laboratory-productivity", modifier = 0.10' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'skip_if_technology_effects = {' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology = "laboratory-productivity-4", type = "laboratory-productivity", modifier = 0.10, max_level = "infinite"' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology = "worker-robots-battery-6", type = "worker-robot-battery", modifier = 0.70, max_level = "infinite"' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "research-productivity", required_mod = "space-age"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = '{technology = "military-science-pack"}' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'ammo_category = "tesla", modifier = 0.1' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'ammo_category = "electric", modifier = 0.1' },
    @{ File = "prototypes\lib\technology-icons.lua"; Text = $technologyIconsText; Snippet = 'local function strip_constant_overlays(icons)' },
    @{ File = "prototypes\lib\technology-icons.lua"; Text = $technologyIconsText; Snippet = 'local function resolve_icon_candidate(candidate)' },
    @{ File = "prototypes\lib\technology-icons.lua"; Text = $technologyIconsText; Snippet = 'function I.icon_source_for_stream(stream)' },
    @{ File = "prototypes\lib\technology-icons.lua"; Text = $technologyIconsText; Snippet = 'mir-use-installed-space-age-icons' },
    @{ File = "prototypes\lib\technology-icons.lua"; Text = $technologyIconsText; Snippet = 'local function icon_from_fluid(name)' },
    @{ File = "prototypes\lib\recipe-matching.lua"; Text = $recipeMatchingText; Snippet = 'add_pattern_outputs(want, options.fluid_patterns, lookup.each_fluid_prototype)' },
    @{ File = "prototypes\lib\prototype-lookup.lua"; Text = $prototypeLookupText; Snippet = 'function L.fluid_prototype(name)' },
    @{ File = "prototypes\tech-gen.lua"; Text = $techGenText; Snippet = 'required_fluids' },
    @{ File = "prototypes\tech-gen.lua"; Text = $techGenText; Snippet = 'technology_requirements.skip_reason(spec)' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.pipeline-extent-settings").multiplier()' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.compat.air-scrubbing").emit()' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'if pipeline_extent_multiplier ~= 1 then' },
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.pipeline-extent").apply(pipeline_extent_multiplier)' },
    @{ File = "prototypes\pipeline-extent-settings.lua"; Text = $pipelineExtentSettingsText; Snippet = 'S.default_value = "100"' },
    @{ File = "prototypes\pipeline-extent-settings.lua"; Text = $pipelineExtentSettingsText; Snippet = 'S.allowed_values = {"50", "75", "100", "125", "150", "200", "250", "300", "400", "500"}' },
    @{ File = "prototypes\pipeline-extent-settings.lua"; Text = $pipelineExtentSettingsText; Snippet = 'function S.parse(value)' },
    @{ File = "prototypes\pipeline-extent-settings.lua"; Text = $pipelineExtentSettingsText; Snippet = 'if numeric > 10 then return numeric / 100 end' },
    @{ File = "prototypes\pipeline-extent.lua"; Text = $pipelineExtentText; Snippet = 'DEFAULT_PIPELINE_EXTENT = 320' },
    @{ File = "prototypes\pipeline-extent.lua"; Text = $pipelineExtentText; Snippet = 'if multiplier == 1 then return end' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = 'icons.icon_source_for_stream(spec or {})' },
    @{ File = "prototypes\lib\technology-icons.lua"; Text = $technologyIconsText; Snippet = 'local out = strip_constant_overlays(base_icons)' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_generated_icon_badge(tech_name, tech)' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_no_space_age_icon_path_in_base(tech_name, tech)' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'mir-use-installed-space-age-icons' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_icon_path("recipe-prod-research_electric_shooting_speed-1", "__space-age__/graphics/technology/electric-weapons-damage.png")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_item_icon("recipe-prod-research_heavy_ammo-1", "cannon-shell")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_electric_shooting_speed-1", "electric-weapons-damage-1")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_walls-1", "gate")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_lab_productivity-1", "military-science-pack")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'assert_tech_uses_technology_icon("recipe-prod-research_rocket_fuel-1", "rocket-fuel")' },
    @{ File = "fixtures\assert-generation-integrity\data-final-fixes.lua"; Text = $generationIntegrityFixtureText; Snippet = 'effect_type == "laboratory-productivity"' },
    @{ File = "fixtures\assert-fluid-productivity\data-final-fixes.lua"; Text = $fluidProductivityFixtureText; Snippet = 'recipe-prod-research_oil_processing_productivity-1' },
    @{ File = "fixtures\assert-fluid-productivity\data-final-fixes.lua"; Text = $fluidProductivityFixtureText; Snippet = 'recipe-prod-research_thruster_fuel_productivity-1' },
    @{ File = "fixtures\assert-pipeline-extent\data-final-fixes.lua"; Text = $pipelineExtentFixtureText; Snippet = 'DEFAULT_PIPELINE_EXTENT = 320' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $airScrubbingFixtureText; Snippet = 'recipe-prod-research_air_scrubbing_clean_filter-1' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $airScrubbingFixtureText; Snippet = 'atan-pollution-filter-cleaning' },
    @{ File = "fixtures\atan-ash\data.lua"; Text = $atanAshFixtureText; Snippet = 'atan-ash-seperation' },
    @{ File = "fixtures\atan-ash\data.lua"; Text = $atanAshFixtureText; Snippet = 'atan-foundation-from-ash' },
    @{ File = "fixtures\assert-atan-ash-separation\data-final-fixes.lua"; Text = $atanAshAssertText; Snippet = 'recipe-prod-research_ash_separation-1' },
    @{ File = "fixtures\assert-atan-ash-separation\data-final-fixes.lua"; Text = $atanAshAssertText; Snippet = 'atan-landfill-from-ash' },
    @{ File = "fixtures\assert-aai-loader-belt-productivity\data-final-fixes.lua"; Text = $aaiLoaderFixtureText; Snippet = 'aai-turbo-loader' },
    @{ File = "fixtures\assert-big-mining-drill-productivity\data-final-fixes.lua"; Text = $bigMiningDrillFixtureText; Snippet = 'big-mining-drill should use +0.05' },
    @{ File = "fixtures\assert-atan-nuclear-science-productivity\data-final-fixes.lua"; Text = $atanNuclearScienceFixtureText; Snippet = 'nuclear-science-pack did not receive science-pack productivity' },
    @{ File = "fixtures\capability-negative-cases\data.lua"; Text = $capabilityNegativeFixtureText; Snippet = 'mir-loader-like-container' },
    @{ File = "fixtures\capability-negative-cases\data.lua"; Text = $capabilityNegativeFixtureText; Snippet = 'maximum_productivity = 0' },
    @{ File = "fixtures\assert-capability-negative-cases\data-final-fixes.lua"; Text = $capabilityNegativeAssertText; Snippet = 'denied_recipes' },
    @{ File = "fixtures\assert-better-bot-battery-skip\data-final-fixes.lua"; Text = $betterBotBatteryFixtureText; Snippet = 'recipe-prod-research_robot_battery-1' },
    @{ File = "fixtures\assert-better-bot-battery-skip\data-final-fixes.lua"; Text = $betterBotBatteryFixtureText; Snippet = 'worker-robots-battery-6' },
    @{ File = "prototypes\weapon-speed-adjustments.lua"; Text = $weaponSpeedText; Snippet = 'tech.unit and tech.unit.count_formula' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = '[modifier-description]' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.electric_shooting_speed=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.flamethrower_shooting_speed=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_heavy_ammo=Cannon shell productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_lab_productivity=Research productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_oil_processing_productivity=Oil processing productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.research_thruster_fuel_productivity=Thruster fuel productivity' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.lab_productivity=Increases research progress gained from each consumed science pack' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-use-installed-space-age-icons=Use installed official DLC icons in base games' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-pipeline-extent-multiplier=Pipeline extent multiplier' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'Factorio cannot recover gracefully from missing icon files during prototype loading.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'flamethrower-shooting-speed-bonus=Flamethrower shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'electric-shooting-speed-bonus=Electric shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'tesla-shooting-speed-bonus=Tesla shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-configured=Configured per technology' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space=Add space science' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space-and-promethium=Add space and promethium science' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space-age-progression=Match Space Age progression' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-official-progression=Fill official progression' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-mod-progression=Match modded progression' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-all-official=Use all official science packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-all=Use all lab science packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = '[string-mod-setting-description]' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-configured=Use the science packs configured for each generated technology. Safest default.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy-reduce=Keep the technology by reducing its science packs to the largest compatible set accepted by an active lab. Safest default for mod packs.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'ips-enable-stream=Enable __1__ technology' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-max-level=Maximum level for infinite __1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'ips-research-time-stream=Research unit time for __1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'ips-require-space-gate=Require finishing the game before generated technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy=Extra science packs for generated technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-lab-incompatibility-policy=What to do when no lab can research a technology' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-prefer-this-mod-for-competing-techs=Use MIR when another mod adds the same infinite research' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-adjust-vanilla-weapon-speed-techs=Remove duplicate rocket/cannon speed from general weapon speed' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-debug-generation-report=Log generated and skipped technologies' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-experimental-spoilage=Experimental and disabled by default in v2.1.0.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-experimental-agriculture=Experimental and disabled by default in v2.1.0.' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-inserter-capacity=Disabled by default.' },
    @{ File = "defaults.lua"; Text = $defaultsText; Snippet = 'settings_note = {"mod-setting-description.mir-note-experimental-spoilage"}' },
    @{ File = "defaults.lua"; Text = $defaultsText; Snippet = 'settings_note = {"mod-setting-description.mir-note-experimental-agriculture"}' },
    @{ File = "defaults.lua"; Text = $defaultsText; Snippet = 'settings_note = {"mod-setting-description.mir-note-inserter-capacity"}' },
    @{ File = "defaults.lua"; Text = $defaultsText; Snippet = 'research_lab_productivity = {' }
  )

  if ($isLegacyFactorio20) {
    $legacyForbiddenCargoSnippets = @(
      'type = "max-cargo-bay-unloading-distance"',
      'type = "cargo-landing-pad-count"'
    )
    foreach ($snippet in $legacyForbiddenCargoSnippets) {
      if ($directEffectsText.Contains($snippet)) {
        throw "Factorio 2.0 legacy must not include Factorio 2.1-only cargo technology modifier in prototypes\streams\direct-effects.lua: $snippet"
      }
    }
  } else {
    $requiredSnippets += @(
      @{ File = "settings.lua"; Text = $settingsText; Snippet = 'research_cargo_landing_pad_count = "Cargo landing pad count"' },
      @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'cargo-landing-pad-count=Cargo landing pads per surface: +__1__' },
      @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-note-sandbox-cargo-pad-count=Sandbox-style and disabled by default.' },
      @{ File = "defaults.lua"; Text = $defaultsText; Snippet = 'settings_note = {"mod-setting-description.mir-note-sandbox-cargo-pad-count"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'research_cargo_landing_pad_count = {' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'required_mods = {"space-age"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'required_technologies = {"rocket-silo"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'icon_tech = "landing-pad-unloading-bay"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'icon_tech = "space-platform"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'science_packs = "all-official"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "max-cargo-bay-unloading-distance", modifier = 10' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "cargo-landing-pad-count", modifier = 1' }
    )
  }

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing science-pack progression setting wiring in $($check.File): $($check.Snippet)"
    }
  }

  $settingsPresetsPath = Join-Path $repo "prototypes\settings-presets.lua"
  if (Test-Path -LiteralPath $settingsPresetsPath) {
    throw "Removed settings preset module should not exist: prototypes\settings-presets.lua"
  }

  $forbiddenSnippets = @(
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'mir-settings-mode' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'mir-enable-policy-' },
    @{ File = "prototypes\settings-resolver.lua"; Text = $settingsResolverText; Snippet = 'settings-presets' },
    @{ File = "prototypes\settings-resolver.lua"; Text = $settingsResolverText; Snippet = 'Force enabled' },
    @{ File = "control\settings-resolver.lua"; Text = $controlSettingsResolverText; Snippet = 'settings-presets' },
    @{ File = "control\settings-resolver.lua"; Text = $controlSettingsResolverText; Snippet = 'mir-enable-policy-' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-settings-mode=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-enable-policy-stream=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-enable-policy-base-tech=' }
  )
  foreach ($check in $forbiddenSnippets) {
    if ($check.Text.Contains($check.Snippet)) {
      throw "Removed preset/enable-policy wiring remains in $($check.File): $($check.Snippet)"
    }
  }

  foreach ($weaponSpeedStream in @("research_rocket_shooting_speed", "research_cannon_shooting_speed")) {
    $match = [regex]::Match($defaultsText, "(?s)$weaponSpeedStream\s*=\s*\{.*?science_packs\s*=\s*\{(?<packs>.*?)\n\s*\}")
    if (-not $match.Success) {
      throw "Missing explicit default science pack list for $weaponSpeedStream in defaults.lua."
    }
    $packs = $match.Groups["packs"].Value
    if (-not $packs.Contains("electromagnetic-science-pack")) {
      throw "$weaponSpeedStream defaults.lua science packs must include electromagnetic-science-pack."
    }
    if ($packs.Contains("agricultural-science-pack")) {
      throw "$weaponSpeedStream defaults.lua science packs must not include agricultural-science-pack."
    }
  }

  if (-not $isLegacyFactorio20) {
    if ($defaultsText -notmatch '(?s)research_cargo_bay_unloading_distance\s*=\s*\{.*?research_time\s*=\s*120') {
      throw "Cargo bay unloading distance default research time must be 120 seconds."
    }
    if ($defaultsText -notmatch '(?s)research_cargo_landing_pad_count\s*=\s*\{.*?research_time\s*=\s*240') {
      throw "Cargo landing pad count default research time must be 240 seconds."
    }
  }
}

Invoke-RepoCheck "compat audit automation tooling is wired" {
  $compatAuditText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRCompatAudit.ps1")
  $extendedTestsText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRExtendedTests.ps1")
  $converterText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1")
  $modPortalText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCompatAudit\ModPortal.ps1")
  $dependencyResolverText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCompatAudit\DependencyResolver.ps1")
  $diagnosticsParserText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCompatAudit\DiagnosticsParser.ps1")
  $stubText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\New-MIRCompatProfileStub.ps1")
  $runnerText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCompatAudit\FactorioRunner.ps1")
  $releaseTargetedGateText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRReleaseTargetedGate.ps1")
  $localCatalogGateText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Test-MIRLocalModLibraryCatalog.ps1")
  $mirCliText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\mir.ps1")
  $consoleText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCli\Console.ps1")
  $runContextText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCli\RunContext.ps1")
  $eventLogText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCli\EventLog.ps1")
  $processSupervisorText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCli\ProcessSupervisor.ps1")
  $localModIndexText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\MIRCli\LocalModIndex.ps1")
  $powershellQualityText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Test-MIRPowerShellQuality.ps1")
  $runProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\release-targeted.json")
  $localAuditProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\local-audit-2.1.json")
  $releaseTargeted20ProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\release-targeted-2.0.json")
  $overnight20ProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\overnight-local-2.0.json")
  $localAudit20ProfileText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\run-profiles\local-audit-2.0.json")
  $overnightText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Start-MIROvernightLocalSweep.ps1")
  $overnightSummaryText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Show-MIROvernightSummary.ps1")
  $manualScenariosText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\compat-matrix\manual-scenarios.json")
  $localLibraryScenariosText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\compat-matrix\local-library-scenarios.json")
  $localLibraryScenarios20Text = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\compat-matrix\local-library-scenarios-2.0.json")
  $expectedFailuresText = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures\compat-matrix\expected-failures.json")
  $workflowText = Get-Content -Raw -LiteralPath (Join-Path $repo ".github\workflows\extended-compat-audit.yml")
  $compatDocsText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\compatibility\README.md")
  $devToolsText = Get-Content -Raw -LiteralPath (Join-Path $repo "docs\maintainer\developer-tools.md")
  $readmeText = Get-Content -Raw -LiteralPath (Join-Path $repo "README.md")

  $requiredSnippets = @(
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$RunManualScenarios" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string]`$FromLockfile" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[int]`$StartIndex = 0" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string[]]`$CandidateNames = @()" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[int]`$ScenarioTimeoutSeconds = 900" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$ContinueOnDependencyFailure" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string[]]`$LocalModZipDirs = @()" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string[]]`$LocalModLibraryDirs = @()" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$RunLocalModZips" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$RunGeneratedLocalScenarios" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$GenerateLocalClusterScenarios" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[int]`$GeneratedLocalPairwiseLimit = 40" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[switch]`$Offline" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "[string]`$FactorioLine = `"`"" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Get-MIROfficialBuiltinFullMods" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Add-MIROfficialBuiltinDependencyClosure" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Get-MIRUnavailableOfficialMods" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "ConvertTo-MIRLocalFullMod" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Add-MIRLocalFullModToIndex" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "New-MIRGeneratedLocalScenarioDefinitions" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "local_library_zip_count" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "generated_local_scenarios_selected" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "local_zip_scenarios_selected" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "`$loadResultsPath = Join-Path `$resolvedOutputDir `"load-results.json`"" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = 'if ($enabled.ContainsKey("space-age"))' },
    @{ File = "scripts\Invoke-MIRValidation.ps1"; Text = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRValidation.ps1"); Snippet = 'not $relative.StartsWith("artifacts/")' },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "skip_reason = `"dependency_resolution_failure`"" },
    @{ File = "scripts\Invoke-MIRCompatAudit.ps1"; Text = $compatAuditText; Snippet = "Invoke-MIRScenarioLoad" },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = "Get-MIRSafeScenarioFileName" },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = "[int]`$ScenarioTimeoutSeconds = 900" },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = "Stop-Process -Id `$process.Id -Force" },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = "source_path" },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = '"artifacts", "build", "dist"' },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = "[string[]]`$OfficialBuiltinMods" },
    @{ File = "scripts\MIRCompatAudit\FactorioRunner.ps1"; Text = $runnerText; Snippet = "enabled = `$enabledLookup.ContainsKey" },
    @{ File = "scripts\MIRCompatAudit\ModPortal.ps1"; Text = $modPortalText; Snippet = '[^\s<>=]+' },
    @{ File = "scripts\MIRCompatAudit\DependencyResolver.ps1"; Text = $dependencyResolverText; Snippet = "[switch]`$IncludeRecommendedDependencies" },
    @{ File = "scripts\MIRCompatAudit\DiagnosticsParser.ps1"; Text = $diagnosticsParserText; Snippet = "[AllowEmptyString()][string]`$Line" },
    @{ File = "scripts\MIRCompatAudit\DiagnosticsParser.ps1"; Text = $diagnosticsParserText; Snippet = "IsNullOrWhiteSpace(`$line)" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[string]`$FromLockfile" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "[string]`$FactorioLine = `"2.1`"" },
    @{ File = "scripts\Invoke-MIRExtendedTests.ps1"; Text = $extendedTestsText; Snippet = "local-library-scenarios-2.0.json" },
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
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "compat-failures.grouped.json" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "profile-candidates.json" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "compat-observations.json" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "recipe_cap" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "compatibility_role" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "missing-dependencies.md" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "missing_dependency_count" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "unexpected_count" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "expected_failures" },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = '"timeout"' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "known_competitor_not_replaced" },
    @{ File = "scripts\New-MIRCompatProfileStub.ps1"; Text = $stubText; Snippet = "Review and refine this stub before enabling" },
    @{ File = "scripts\New-MIRCompatProfileStub.ps1"; Text = $stubText; Snippet = "require_review = true" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "strict-current-commit-gate" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "targeted-repair-local-zips" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "representative-local-scenario" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "Assert-MIRReleaseGateNoUnexpectedFailures" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "release-targeted-summary.md" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = "FactorioLine" },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = 'RepairSmokeModNames' },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = 'RepresentativeScenarioName' },
    @{ File = "scripts\Invoke-MIRReleaseTargetedGate.ps1"; Text = $releaseTargetedGateText; Snippet = 'AuditFactorioVersions' },
    @{ File = "scripts\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = '[Parameter(Mandatory)][string[]]$LocalModLibraryDirs' },
    @{ File = "scripts\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = 'Read-MIRModInfoFromZip' },
    @{ File = "scripts\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = 'missing_scenario_mod_count' },
    @{ File = "scripts\Test-MIRLocalModLibraryCatalog.ps1"; Text = $localCatalogGateText; Snippet = 'AllowMissingScenarioMods' },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = ".\scripts\mir.ps1 release gate" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "Invoke-MIRRunProfile" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "--factorio-line" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "factorio_line" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "local-audit-2.1" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "report observations" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "New-MIRProfileOverrides" },
    @{ File = "scripts\mir.ps1"; Text = $mirCliText; Snippet = "local-index" },
    @{ File = "scripts\Test-MIRPowerShellQuality.ps1"; Text = $powershellQualityText; Snippet = "duplicate parameter" },
    @{ File = "scripts\Test-MIRPowerShellQuality.ps1"; Text = $powershellQualityText; Snippet = "possible secret output" },
    @{ File = "scripts\Invoke-MIRValidation.ps1"; Text = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Invoke-MIRValidation.ps1"); Snippet = "Test-MIRPowerShellQuality.ps1" },
    @{ File = "scripts\MIRCli\Console.ps1"; Text = $consoleText; Snippet = "Write-MIRScenarioResult" },
    @{ File = "scripts\MIRCli\RunContext.ps1"; Text = $runContextText; Snippet = "run-manifest.json" },
    @{ File = "scripts\MIRCli\EventLog.ps1"; Text = $eventLogText; Snippet = "events.jsonl" },
    @{ File = "scripts\MIRCli\ProcessSupervisor.ps1"; Text = $processSupervisorText; Snippet = "Invoke-MIRProcess" },
    @{ File = "scripts\MIRCli\LocalModIndex.ps1"; Text = $localModIndexText; Snippet = "New-MIRLocalModIndex" },
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
    @{ File = "fixtures\compat-matrix\manual-scenarios.json"; Text = $manualScenariosText; Snippet = '"space-age-planet-cluster"' },
    @{ File = "fixtures\compat-matrix\manual-scenarios.json"; Text = $manualScenariosText; Snippet = '"base-baseline"' },
    @{ File = "fixtures\compat-matrix\manual-scenarios.json"; Text = $manualScenariosText; Snippet = '"bob-angels"' },
    @{ File = "fixtures\compat-matrix\manual-scenarios.json"; Text = $manualScenariosText; Snippet = '"include_space_age"' },
    @{ File = "fixtures\compat-matrix\local-library-scenarios.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-space-age-mega-smash"' },
    @{ File = "fixtures\compat-matrix\local-library-scenarios.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-bz-suite-space-age"' },
    @{ File = "fixtures\compat-matrix\local-library-scenarios.json"; Text = $localLibraryScenariosText; Snippet = '"local-2-1-planet-pack-wrapper-full"' },
    @{ File = "fixtures\compat-matrix\local-library-scenarios-2.0.json"; Text = $localLibraryScenarios20Text; Snippet = '"local-2-0-base-baseline"' },
    @{ File = "fixtures\compat-matrix\local-library-scenarios-2.0.json"; Text = $localLibraryScenarios20Text; Snippet = '"local-2-0-bob-angels"' },
    @{ File = "fixtures\compat-matrix\expected-failures.json"; Text = $expectedFailuresText; Snippet = '"expected_failures"' },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "runs-on: self-hosted" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "Invoke-MIRExtendedTests.ps1" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = '$params = @{' },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "fail_on_audit_failures" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "local_mod_library_dirs" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "offline" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "include_generated_local_pairwise" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "shard_local_mod_zips" },
    @{ File = ".github\workflows\extended-compat-audit.yml"; Text = $workflowText; Snippet = "scenario_timeout_seconds" },
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
    @{ File = "README.md"; Text = $readmeText; Snippet = ".\scripts\mir.ps1 audit local" },
    @{ File = "README.md"; Text = $readmeText; Snippet = "docs/maintainer/developer-tools.md" },
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "Preferred Commands" },
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "scripts/MIRCli/*.ps1" },
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "Test-MIRPowerShellQuality.ps1" }
    @{ File = "docs\maintainer\developer-tools.md"; Text = $devToolsText; Snippet = "Test-MIRLocalModLibraryCatalog.ps1" }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing compatibility audit automation wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "2.2.0 compiler diagnostics are wired" {
  $dataFinalFixesText = Get-MIRDataFinalFixesSourceText
  $diagnosticsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\diagnostics.lua")
  $factRegistryPath = Join-Path $repo "prototypes\lib\facts\registry.lua"
  $indexRegistryPath = Join-Path $repo "prototypes\mir\index\registry_builder.lua"
  $capabilityRegistryPath = Join-Path $repo "prototypes\lib\capabilities\registry.lua"
  $capabilityContractPath = Join-Path $repo "prototypes\lib\capabilities\contract.lua"
  $capabilityPolicyPath = Join-Path $repo "prototypes\lib\policy\capabilities.lua"
  $schemaPath = Join-Path $repo "prototypes\lib\mir\schema.lua"
  $compilerPath = Join-Path $repo "prototypes\mir\planner\compiler.lua"
  $compilerShimPath = Join-Path $repo "prototypes\planner\compiler.lua"
  $converterText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1")
  $overnightSummaryText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Show-MIROvernightSummary.ps1")
  $compatPlannerText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\compat\planner.lua")
  $policyLintText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Test-MIRPolicyLints.ps1")

  if (-not (Test-Path -LiteralPath $factRegistryPath)) {
    throw "Missing legacy typed fact registry shim: prototypes\lib\facts\registry.lua"
  }
  if (-not (Test-Path -LiteralPath $indexRegistryPath)) {
    throw "Missing MIR index registry builder: prototypes\mir\index\registry_builder.lua"
  }
  if (-not (Test-Path -LiteralPath $compilerPath)) {
    throw "Missing compiler diagnostics module: prototypes\mir\planner\compiler.lua"
  }
  if (-not (Test-Path -LiteralPath $compilerShimPath)) {
    throw "Missing legacy compiler diagnostics shim: prototypes\planner\compiler.lua"
  }
  if (-not (Test-Path -LiteralPath $capabilityRegistryPath)) {
    throw "Missing capability registry: prototypes\lib\capabilities\registry.lua"
  }
  foreach ($path in @($capabilityContractPath, $capabilityPolicyPath, $schemaPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Missing 2.2.0 capability kernel artifact: $path"
    }
  }

  $factRegistryText = Get-Content -Raw -LiteralPath $factRegistryPath
  $indexRegistryText = Get-Content -Raw -LiteralPath $indexRegistryPath
  $decisionRecordText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\domain\decisions\decision_record.lua")
  $decisionExportText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\mir\report\decision_export.lua")
  $capabilityRegistryText = Get-Content -Raw -LiteralPath $capabilityRegistryPath
  $capabilityContractText = Get-Content -Raw -LiteralPath $capabilityContractPath
  $capabilityPolicyText = Get-Content -Raw -LiteralPath $capabilityPolicyPath
  $schemaText = Get-Content -Raw -LiteralPath $schemaPath
  $compilerText = Get-Content -Raw -LiteralPath $compilerPath
  $compilerShimText = Get-Content -Raw -LiteralPath $compilerShimPath

  $requiredSnippets = @(
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.mir.planner.compiler").emit()' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = 'function D.decision(row)' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = 'schema.decision(row)' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = '.. " capability=" .. tostring(row.capability or "")' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = '.. " evidence=" .. tostring(row.evidence or "")' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = 'append("rule_mutation", row)' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = 'append("loop_risk", row)' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = 'append("lab_matrix", row)' },
    @{ File = "prototypes\lib\facts\registry.lua"; Text = $factRegistryText; Snippet = 'return require("prototypes.mir.index.registry_builder")' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'RecipeFact' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'RuleMutationFact' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'schema = schema.fact_registry' },
    @{ File = "prototypes\mir\index\registry_builder.lua"; Text = $indexRegistryText; Snippet = 'build_loop_risk_facts' },
    @{ File = "prototypes\mir\domain\decisions\decision_record.lua"; Text = $decisionRecordText; Snippet = 'function M.generated_technology(record)' },
    @{ File = "prototypes\mir\domain\decisions\decision_record.lua"; Text = $decisionRecordText; Snippet = 'schema.decision({' },
    @{ File = "prototypes\mir\report\decision_export.lua"; Text = $decisionExportText; Snippet = 'function M.emit(sink, record)' },
    @{ File = "prototypes\mir\report\decision_export.lua"; Text = $decisionExportText; Snippet = 'sink.decision(record)' },
    @{ File = "prototypes\lib\mir\schema.lua"; Text = $schemaText; Snippet = 'S.decision_record = 1' },
    @{ File = "prototypes\lib\capabilities\contract.lua"; Text = $capabilityContractText; Snippet = 'CapabilityResolver' },
    @{ File = "prototypes\lib\capabilities\contract.lua"; Text = $capabilityContractText; Snippet = '"discover"' },
    @{ File = "prototypes\lib\policy\capabilities.lua"; Text = $capabilityPolicyText; Snippet = 'P.schema_version = schema.capability_policy' },
    @{ File = "prototypes\lib\policy\capabilities.lua"; Text = $capabilityPolicyText; Snippet = 'deny_risk_flags' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'Capability resolvers are report-first' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'contract.validate_all(RESOLVERS)' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'schema_version = schema.capability_resolver' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'id = "logistics-loader-manufacturing"' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'id = "mining-drill-manufacturing"' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'id = "native-modifier-ownership"' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'entity_backed_candidates' },
    @{ File = "prototypes\lib\capabilities\registry.lua"; Text = $capabilityRegistryText; Snippet = 'discover,classify,propose,validate,emit,diagnose' },
    @{ File = "prototypes\planner\compiler.lua"; Text = $compilerShimText; Snippet = 'return require("prototypes.mir.planner.compiler")' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'local decision_export = require("prototypes.mir.report.decision_export")' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'require("prototypes.mir.index.registry_builder")' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'D.fact_registry({' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'decision_export.emit(D, {' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'decision_export.emit(D, decision_record.generated_technology({' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'emit_generated_technology_decisions' },
    @{ File = "prototypes\mir\planner\compiler.lua"; Text = $compilerText; Snippet = 'capabilities.emit(registry)' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = 'useful_level_estimate = levels' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["atan-ash"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["atan-nuclear-science"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["FluidMustFlow"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["robot_attrition"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["jetpack"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["big-mining-drill"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["equipment-gantry"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["aai-industry"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["aai-containers"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = '["aai-loaders"] = {' },
    @{ File = "prototypes\compat\planner.lua"; Text = $compatPlannerText; Snippet = 'belt_productivity_loader_recipe_candidate' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = '"fact_registry", "decision", "rule_mutation", "loop_risk", "lab_matrix"' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = 'capability = [string](Get-MIRObjectProperty -Object $row -Name "capability")' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = '## Capability Decisions' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = "Loop Risk Diagnostics" },
    @{ File = "scripts\Show-MIROvernightSummary.ps1"; Text = $overnightSummaryText; Snippet = "rule_surfaces" },
    @{ File = "scripts\Test-MIRPolicyLints.ps1"; Text = $policyLintText; Snippet = "Generated stream manifest row" }
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
  $utilText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\util.lua")
  $diagnosticsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\diagnostics.lua")
  $converterText = Get-Content -Raw -LiteralPath (Join-Path $repo "scripts\Convert-MIRCompatAuditResults.ps1")
  $airScrubbingPolicyPath = Join-Path $repo "prototypes\compat\air-scrubbing.lua"
  $exactRecipePolicyPath = Join-Path $repo "prototypes\mir\compatibility\diagnostics\exact_recipe_policy.lua"
  $airScrubbingDiagnosticsPath = Join-Path $repo "prototypes\mir\compatibility\diagnostics\air_scrubbing.lua"
  $atanAshDiagnosticsPath = Join-Path $repo "prototypes\mir\compatibility\diagnostics\atan_ash.lua"
  $compatibilityDiagnosticsReportPath = Join-Path $repo "prototypes\mir\report\compatibility_diagnostics.lua"
  $manifestPath = Join-Path $repo "prototypes\planner\generated-stream-manifest.json"
  $fixturePath = Join-Path $repo "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"

  foreach ($path in @($airScrubbingPolicyPath, $exactRecipePolicyPath, $airScrubbingDiagnosticsPath, $atanAshDiagnosticsPath, $compatibilityDiagnosticsReportPath, $manifestPath, $fixturePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Missing Air Scrubbing policy artifact: $path"
    }
  }

  $airScrubbingPolicyText = Get-Content -Raw -LiteralPath $airScrubbingPolicyPath
  $exactRecipePolicyText = Get-Content -Raw -LiteralPath $exactRecipePolicyPath
  $airScrubbingDiagnosticsText = Get-Content -Raw -LiteralPath $airScrubbingDiagnosticsPath
  $atanAshDiagnosticsText = Get-Content -Raw -LiteralPath $atanAshDiagnosticsPath
  $compatibilityDiagnosticsReportText = Get-Content -Raw -LiteralPath $compatibilityDiagnosticsReportPath
  $manifestText = Get-Content -Raw -LiteralPath $manifestPath
  $fixtureText = Get-Content -Raw -LiteralPath $fixturePath

  $requiredSnippets = @(
    @{ File = "data-final-fixes.lua"; Text = $dataFinalFixesText; Snippet = 'require("prototypes.compat.air-scrubbing").emit()' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'research_air_scrubbing_clean_filter = {' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'science_packs = "derive-from-unlocks"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'prerequisites = "derive-from-unlocks"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'manifest_id = air_scrubbing_capability.stream.id' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'exact_recipe_patterns(air_scrubbing_capability.exact_recipes)' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'local function science_from_unlocks(spec)' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'if spec.prerequisites == "derive-from-unlocks" then' },
    @{ File = "prototypes\diagnostics.lua"; Text = $diagnosticsText; Snippet = '.. " rejected=" .. tostring(row.rejected or "")' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = 'rejected = [string](Get-MIRObjectProperty -Object $row -Name "rejected")' },
    @{ File = "scripts\Convert-MIRCompatAuditResults.ps1"; Text = $converterText; Snippet = 'generated,rejected,unknown,missing,module_slots' },
    @{ File = "prototypes\compat\air-scrubbing.lua"; Text = $airScrubbingPolicyText; Snippet = 'return require("prototypes.mir.compatibility.diagnostics.air_scrubbing")' },
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
    @{ File = "prototypes\planner\generated-stream-manifest.json"; Text = $manifestText; Snippet = '"mir-prod-air-scrubbing-clean-filter"' },
    @{ File = "prototypes\planner\generated-stream-manifest.json"; Text = $manifestText; Snippet = '"source": "compat_policy:air-scrubbing"' },
    @{ File = "prototypes\planner\generated-stream-manifest.json"; Text = $manifestText; Snippet = '"atan-pollution-filter"' },
    @{ File = "prototypes\planner\generated-stream-manifest.json"; Text = $manifestText; Snippet = '"atan-spore-filter"' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $fixtureText; Snippet = 'atan-pollution-scrubbing' },
    @{ File = "fixtures\assert-air-scrubbing-clean-filter\data-final-fixes.lua"; Text = $fixtureText; Snippet = 'atan-filter-resin' }
  )

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing Air Scrubbing clean-filter wiring in $($check.File): $($check.Snippet)"
    }
  }
}

Invoke-RepoCheck "compatibility support lanes are wired" {
  $supportLanePath = Join-Path $repo "fixtures\compat-matrix\support-lanes.json"
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

Invoke-RepoCheck "compatibility policy and claim lints pass" {
  & (Join-Path $repo "scripts\Test-MIRPolicyLints.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "release documentation lists final manual and API checks" {
  $documentation = @(
    foreach ($file in Get-DocumentationFiles) {
      [pscustomobject]@{
        Path = $file.FullName
        RelativePath = Get-RepoRelativePath $file.FullName
        Text = Get-Content -Raw -LiteralPath $file.FullName
      }
    }
  )

  function Assert-DocumentationSnippet {
    param(
      [string]$Snippet,
      [string]$Label
    )

    $matches = @($documentation | Where-Object { $_.Text.Contains($Snippet) })
    if ($matches.Count -eq 0) {
      throw "Missing required release documentation entry for ${Label}: $Snippet"
    }
  }

  $requiredDocSnippets = @(
    @{ Label = "settings guide"; Snippet = '### Settings Guide' },
    @{ Label = "zero setting semantics"; Snippet = '### What `0` Means' },
    @{ Label = "research unit time wording"; Snippet = '`Research unit time` is Factorio''s seconds-per-research-unit value.' },
    @{ Label = "settings confidence scope"; Snippet = 'Settings confidence pass: clearer labels, ordering, warnings, dropdown help, and docs' },
    @{ Label = "settings confidence TODO"; Snippet = 'Complete a v2.0.5 settings confidence pass without adding real preset behavior.' },
    @{ Label = "character reach manual scenario"; Snippet = '`character-reach-icon`' },
    @{ Label = "merged inventory/trash manual scenario"; Snippet = '`merged-inventory-trash-ui`' },
    @{ Label = "mod structure API proof"; Snippet = 'Mod structure: <https://lua-api.factorio.com/latest/auxiliary/mod-structure.html>' },
    @{ Label = "modifier list API proof"; Snippet = 'Modifier list: <https://lua-api.factorio.com/latest/types/Modifier.html>' },
    @{ Label = "NothingModifier API proof"; Snippet = '`NothingModifier`: <https://lua-api.factorio.com/latest/types/NothingModifier.html>' },
    @{ Label = "DifficultySettings API proof"; Snippet = '`DifficultySettings`: <https://lua-api.factorio.com/latest/concepts/DifficultySettings.html>' },
    @{ Label = "LuaEntity API proof"; Snippet = '`LuaEntity`: <https://lua-api.factorio.com/latest/classes/LuaEntity.html>' }
  )

  foreach ($check in $requiredDocSnippets) {
    Assert-DocumentationSnippet -Snippet $check.Snippet -Label $check.Label
  }

  $apiLinkLabels = @(
    "Mod structure",
    "Modifier list",
    '`NothingModifier`',
    "Migrations",
    "Data lifecycle",
    "Events",
    '`LuaEntity`',
    '`LuaItemStack`',
    '`DifficultySettings`',
    '`PumpPrototype`',
    '`FluidBox`',
    '`LuaTechnology`',
    '`ModulePrototype`',
    '`Effect`'
  )
  foreach ($doc in $documentation) {
    foreach ($line in ($doc.Text -split "`r?`n")) {
      foreach ($label in $apiLinkLabels) {
        if ($line -match "^- $([regex]::Escape($label)):\s*$") {
          throw "$($doc.RelativePath) contains an empty API proof link entry: $line"
        }
      }
    }
  }
}

Invoke-RepoCheck "changelog uses Factorio changelog format" {
  $separator = "-" * 99
  $maxChangelogLineLength = 132
  $blockedChangelogPhrases = @(
    "before release",
    "release-candidate",
    "planned",
    "proposed",
    "reverted",
    "temporary",
    "validation",
    "fixture",
    "smoke",
    "proof",
    "TODO",
    "FIXME",
    "TBD",
    "BROKEN",
    "dirtying git",
    "scaffolding"
  )
  $path = Join-Path $repo "changelog.txt"
  $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
  if ($lines.Count -eq 0) {
    throw "changelog.txt is empty."
  }
  if ($lines[0] -ne $separator) {
    throw "changelog.txt must start with exactly 99 dashes."
  }
  if ($lines -notcontains "Version: $($repoInfo.version)") {
    throw "changelog.txt must contain an entry for the current info.json version $($repoInfo.version)."
  }

  $sectionStart = $true
  $expectVersion = $false
  $seenCategory = $false
  $lineNo = 0
  foreach ($line in $lines) {
    $lineNo++
    if ($line.Length -gt $maxChangelogLineLength) {
      throw "changelog.txt:$lineNo exceeds $maxChangelogLineLength characters."
    }
    foreach ($phrase in $blockedChangelogPhrases) {
      if ($line.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "changelog.txt:$lineNo contains non-shipped or internal-process wording: $phrase"
      }
    }
    if ($line -eq $separator) {
      $sectionStart = $false
      $expectVersion = $true
      $seenCategory = $false
      continue
    }
    if ($line -match '^\s*$') {
      continue
    }
    if ($expectVersion) {
      if ($line -notmatch '^Version: .+$') {
        throw "changelog.txt:$lineNo expected a Version line after the separator."
      }
      $expectVersion = $false
      $sectionStart = $true
      continue
    }
    if ($sectionStart -and $line -match '^Date: \d{4}-\d{2}-\d{2}$') {
      continue
    }
    if ($line -match '^  [^ ].+:$') {
      $seenCategory = $true
      $sectionStart = $false
      continue
    }
    if ($line -match '^    - .+$') {
      if (-not $seenCategory) {
        throw "changelog.txt:$lineNo has an entry before any category."
      }
      continue
    }
    throw "changelog.txt:$lineNo is not valid Factorio changelog syntax: $line"
  }

  if ($expectVersion) {
    throw "changelog.txt ended immediately after a separator."
  }
}

Invoke-RepoCheck "generated package archive matches metadata" {
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  function Read-ZipEntryText {
    param($Entry)
    $stream = $Entry.Open()
    try {
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
      try {
        return $reader.ReadToEnd()
      } finally {
        $reader.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
  }

  function Get-StreamSha256 {
    param([System.IO.Stream]$Stream)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      return -join ($sha.ComputeHash($Stream) | ForEach-Object { $_.ToString("x2") })
    } finally {
      $sha.Dispose()
    }
  }

  function Get-FileSha256 {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
      return Get-StreamSha256 -Stream $stream
    } finally {
      $stream.Dispose()
    }
  }

  function Get-ZipEntrySha256 {
    param($Entry)
    $stream = $Entry.Open()
    try {
      return Get-StreamSha256 -Stream $stream
    } finally {
      $stream.Dispose()
    }
  }

  function Normalize-TextForPackageComparison {
    param([string]$Text)
    return ($Text -replace "`r`n", "`n").TrimEnd()
  }

  function Test-PackageTextPath {
    param([string]$RelativePath)
    $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    if ($extension -in @(".cfg", ".json", ".lua", ".md", ".txt")) {
      return $true
    }

    $fileName = [System.IO.Path]::GetFileName($RelativePath)
    return $fileName -in @("LICENSE")
  }

  $info = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
  $packageName = "$($info.name)_$($info.version)"
  $validationOutputDir = "build/validation-dist"
  & (Join-Path $repo "scripts\Build-MIRPackage.ps1") -OutputDir $validationOutputDir -CompressionLevel "Fastest" | Out-Host

  $zipPath = Join-Path $repo "$validationOutputDir\$packageName.zip"
  if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Validation package not found after build: $zipPath"
  }

  $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entries = @($zip.Entries)
    $entryNames = @($entries | ForEach-Object { $_.FullName })
    $root = "$packageName/"

    $outsideRoot = @($entryNames | Where-Object { -not $_.StartsWith($root) })
    if ($outsideRoot.Count -gt 0) {
      throw "Package entries outside expected root ${root}: $($outsideRoot -join ', ')"
    }

    $requiredEntries = @(
      "${root}info.json",
      "${root}changelog.txt",
      "${root}README.md",
      "${root}LICENSE",
      "${root}thumbnail.png",
      "${root}data.lua",
      "${root}control.lua",
      "${root}data-updates.lua",
      "${root}data-final-fixes.lua",
      "${root}settings.lua",
      "${root}defaults.lua",
      "${root}locale/en/more-infinite-research.cfg",
      "${root}migrations/more-infinite-research_2.0.5.json"
    )
    $missingEntries = @($requiredEntries | Where-Object { $_ -notin $entryNames })
    if ($missingEntries.Count -gt 0) {
      throw "Package is missing expected entries: $($missingEntries -join ', ')"
    }

    $forbiddenPatterns = @(
      "^$([regex]::Escape($root))(\.git|\.github|\.mir|\.codex|build|dist|docs|fixtures|scripts|tests|tools)(/|$)",
      "^$([regex]::Escape($root))(AGENTS\.md|CONTRIBUTING\.md|todo\.md)$",
      "(^|/)(\.DS_Store|Thumbs\.db)$",
      "(^|/)__MACOSX(/|$)",
      "~$",
      "\.(tmp|bak|swp)$"
    )
    $forbiddenEntries = @(
      foreach ($entryName in $entryNames) {
        foreach ($pattern in $forbiddenPatterns) {
          if ($entryName -match $pattern) {
            $entryName
            break
          }
        }
      }
    )
    if ($forbiddenEntries.Count -gt 0) {
      throw "Package contains forbidden entries: $($forbiddenEntries -join ', ')"
    }

    $innerInfoEntry = $entries | Where-Object { $_.FullName -eq "${root}info.json" } | Select-Object -First 1
    $innerInfo = Read-ZipEntryText $innerInfoEntry | ConvertFrom-Json
    if ($innerInfo.name -ne $info.name -or $innerInfo.version -ne $info.version -or $innerInfo.factorio_version -ne $info.factorio_version) {
      throw "Package info.json metadata does not match repository info.json."
    }
    $repoDeps = @($info.dependencies)
    $packageDeps = @($innerInfo.dependencies)
    $depDiff = @(Compare-Object -ReferenceObject $repoDeps -DifferenceObject $packageDeps)
    if ($depDiff.Count -gt 0) {
      throw "Package info.json dependencies do not match repository info.json."
    }

    $repoPath = $repo.Path
    $mustMatchRepo = @(
      "README.md",
      "changelog.txt",
      "control.lua",
      "data.lua",
      "data-updates.lua",
      "data-final-fixes.lua",
      "settings.lua",
      "defaults.lua",
      "thumbnail.png"
    )

    foreach ($directory in @("control", "locale", "migrations", "prototypes")) {
      $directoryPath = Join-Path $repo $directory
      if (Test-Path -LiteralPath $directoryPath) {
        $mustMatchRepo += @(
          Get-ChildItem -LiteralPath $directoryPath -Recurse -File |
          ForEach-Object { [System.IO.Path]::GetRelativePath($repoPath, $_.FullName).Replace("\", "/") }
        )
      }
    }

    $mustMatchRepo = @($mustMatchRepo | Sort-Object -Unique)

    foreach ($relative in $mustMatchRepo) {
      $entryName = "${root}$relative"
      $entry = $entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
      if (-not $entry) {
        throw "Package is missing expected source file: $entryName"
      }

      if (Test-PackageTextPath -RelativePath $relative) {
        $repoText = Get-Content -Raw -LiteralPath (Join-Path $repo $relative)
        $zipText = Read-ZipEntryText $entry
        if ((Normalize-TextForPackageComparison $repoText) -ne (Normalize-TextForPackageComparison $zipText)) {
          throw "Package source file differs from repository source: $relative"
        }
      } else {
        $repoHash = Get-FileSha256 -Path (Join-Path $repo $relative)
        $zipHash = Get-ZipEntrySha256 -Entry $entry
        if ($repoHash -ne $zipHash) {
          throw "Package source file differs from repository source: $relative"
        }
      }
    }
  } finally {
    $zip.Dispose()
  }
}

Invoke-RepoCheck "git whitespace check" {
  git -C $repo diff --check
  if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed."
  }
}

if ($StaticOnly -or [string]::IsNullOrWhiteSpace($FactorioBin)) {
  Write-Host "[skip] Factorio runtime validation skipped. Set FACTORIO_BIN or pass -FactorioBin to run load tests."
  exit 0
}

if (-not (Test-Path -LiteralPath $FactorioBin)) {
  throw "Factorio binary not found: $FactorioBin"
}

$usesGeneratedUserDataDir = [string]::IsNullOrWhiteSpace($UserDataDir)
if ($usesGeneratedUserDataDir) {
  $UserDataDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mir-factorio-userdata-" + [guid]::NewGuid().ToString("N"))
}
$validationRoot = (New-Item -ItemType Directory -Force -Path $UserDataDir).FullName
$validationRootWithSeparator = $validationRoot.TrimEnd("\") + "\"
$factorioBinResolved = (Resolve-Path -LiteralPath $FactorioBin).Path
$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorioBinResolved))
$factorioReadData = Join-Path $factorioRoot "data"
if (-not (Test-Path -LiteralPath $factorioReadData)) {
  throw "Unable to find Factorio read-data directory for validation config: $factorioReadData"
}
$factorioConfigPath = Join-Path $validationRoot "mir-validation-config.ini"
$factorioConfigText = @"
; Generated by More Infinite Research validation.
[path]
read-data=$factorioReadData
write-data=$validationRoot

[general]
locale=auto

[other]
enable-steam-networking=false
disable-blueprint-storage=true
"@
Set-Content -LiteralPath $factorioConfigPath -Value $factorioConfigText -Encoding UTF8

function Invoke-FactorioProcess {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [int]$TimeoutMs = 300000
  )

  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $FilePath
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  foreach ($arg in $Arguments) {
    [void]$processInfo.ArgumentList.Add($arg)
  }

  $process = [System.Diagnostics.Process]::Start($processInfo)
  if (-not $process.WaitForExit($TimeoutMs)) {
    try {
      $process.Kill($true)
    } catch {
      $process.Kill()
    }
    throw "Factorio runtime validation timed out after $TimeoutMs ms."
  }
  return $process.ExitCode
}

function Remove-CopiedModDirectory {
  param([string]$Name, [string]$ModsDir)
  $modsRootWithSeparator = (Resolve-Path -LiteralPath $ModsDir).Path.TrimEnd("\") + "\"
  $target = Join-Path $modsDir $Name
  if (Test-Path -LiteralPath $target) {
    $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
    if (-not $resolvedTarget.StartsWith($modsRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove mod directory outside scenario mods root: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
  }
  return $target
}

function Copy-ModDirectory {
  param([string]$Source, [string]$Name, [string]$ModsDir)
  $target = Remove-CopiedModDirectory -Name $Name -ModsDir $ModsDir
  Copy-Item -LiteralPath $Source -Destination $target -Recurse
}

function Copy-RepositoryModDirectory {
  param([string]$ModsDir)

  $target = Remove-CopiedModDirectory -Name "more-infinite-research" -ModsDir $ModsDir
  New-Item -ItemType Directory -Force -Path $target | Out-Null

  $files = @(
    "changelog.txt",
    "control.lua",
    "data-final-fixes.lua",
    "data-updates.lua",
    "data.lua",
    "defaults.lua",
    "info.json",
    "LICENSE",
    "README.md",
    "settings.lua",
    "thumbnail.png"
  )
  $directories = @(
    "control",
    "migrations",
    "locale",
    "prototypes"
  )

  foreach ($file in $files) {
    $source = Join-Path $repo $file
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $target $file)
    }
  }

  foreach ($directory in $directories) {
    $source = Join-Path $repo $directory
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $target $directory) -Recurse
    }
  }
}

$fixtureRoot = Join-Path $repo "fixtures"
if (-not (Test-Path -LiteralPath $fixtureRoot)) {
  throw "Fixture directory not found: $fixtureRoot"
}

$nonModFixtureDirs = @("compat-matrix", "run-profiles")

$postMirAssertionFixtures = @(
  "mir-fixture-assert-aai-loader-belt-productivity",
  "mir-fixture-assert-air-scrubbing-clean-filter",
  "mir-fixture-assert-atan-ash-separation",
  "mir-fixture-assert-atan-nuclear-science-productivity",
  "mir-fixture-assert-better-bot-battery-skip",
  "mir-fixture-assert-big-mining-drill-productivity",
  "mir-fixture-assert-capability-negative-cases",
  "mir-fixture-assert-generation-integrity",
  "mir-fixture-assert-hidden-setting-readability",
  "mir-fixture-assert-science-pack-productivity",
  "mir-fixture-assert-lab-skip-policy",
  "mir-fixture-assert-lab-productivity-owner-skip",
  "mir-fixture-assert-base-extension-boundary",
  "mir-fixture-assert-cargo-logistics",
  "mir-fixture-assert-fluid-productivity",
  "mir-fixture-assert-omega-drill-productivity",
  "mir-fixture-assert-pipeline-extent",
  "mir-fixture-assert-plates-n-circuit-productivity",
  "mir-fixture-assert-plates-n-circuit-productivity-blocked",
  "mir-fixture-assert-plates-n-circuit-productivity-change-mismatch",
  "mir-fixture-assert-vanilla-family-adoption",
  "mir-fixture-assert-vanilla-family-exact-owner",
  "mir-fixture-assert-vanilla-family-mixed-owner",
  "mir-fixture-assert-vanilla-family-owner-prepatched",
  "mir-fixture-assert-weapon-speed-safety"
)

function Get-FixtureInfos {
  $infos = @()
  foreach ($fixture in Get-ChildItem -LiteralPath $fixtureRoot -Directory) {
    if ($nonModFixtureDirs -contains $fixture.Name) { continue }
    $info = Get-Content -Raw (Join-Path $fixture.FullName "info.json") | ConvertFrom-Json
    $infos += [pscustomobject]@{
      Name = $info.name
      Path = $fixture.FullName
    }
  }
  return $infos
}

function Enable-CopiedDiagnostics {
  param([string]$ModsDir)
  $copiedDiagnosticsPath = Join-Path $ModsDir "more-infinite-research\prototypes\diagnostics.lua"
  $copiedDiagnostics = Get-Content -Raw -LiteralPath $copiedDiagnosticsPath
  $copiedDiagnostics = $copiedDiagnostics -replace 'return startup_setting\("mir-debug-generation-report"\) == true', 'return true'
  Set-Content -LiteralPath $copiedDiagnosticsPath -Value $copiedDiagnostics -Encoding UTF8
}

function Enable-CopiedScriptedDiagnostics {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-debug-scripted-effects" -ValueLiteral "true"
}

function Get-CopiedSettingsImplementationPath {
  param([string]$ModsDir)

  $candidates = @(
    "more-infinite-research\prototypes\mir\legacy\settings.lua",
    "more-infinite-research\settings.lua"
  )

  foreach ($relative in $candidates) {
    $path = Join-Path $ModsDir $relative
    if (Test-Path -LiteralPath $path) {
      return $path
    }
  }

  throw "Unable to find copied settings implementation."
}

function Set-CopiedStartupSettingDefault {
  param(
    [string]$ModsDir,
    [string]$Name,
    [string]$ValueLiteral
  )

  $copiedSettingsPath = Get-CopiedSettingsImplementationPath -ModsDir $ModsDir
  $copiedSettings = Get-Content -Raw -LiteralPath $copiedSettingsPath
  $escapedName = [regex]::Escape($Name)
  $pattern = "(?s)(name\s*=\s*`"$escapedName`".*?default_value\s*=\s*)([^,\r\n]+)"
  $match = [regex]::Match($copiedSettings, $pattern)
  if (-not $match.Success) {
    throw "Unable to find startup setting default for $Name in copied settings implementation."
  }

  $valueGroup = $match.Groups[2]
  $copiedSettings = $copiedSettings.Substring(0, $valueGroup.Index) +
    $ValueLiteral +
    $copiedSettings.Substring($valueGroup.Index + $valueGroup.Length)
  Set-Content -LiteralPath $copiedSettingsPath -Value $copiedSettings -Encoding UTF8
}

function Set-CopiedGeneratedStartupSettingDefault {
  param(
    [string]$ModsDir,
    [string]$Name,
    [string]$ValueLiteral
  )

  $copiedSettingsPath = Get-CopiedSettingsImplementationPath -ModsDir $ModsDir
  $copiedSettings = Get-Content -Raw -LiteralPath $copiedSettingsPath
  if ($copiedSettings -notmatch "data:extend\(settings_data\)") {
    throw "Unable to find data:extend(settings_data) while setting generated startup default for $Name."
  }

  $escapedNameLiteral = $Name.Replace("\", "\\").Replace('"', '\"')
  $override = @"
for _, setting in ipairs(settings_data) do
  if setting.name == "$escapedNameLiteral" then
    setting.default_value = $ValueLiteral
  end
end

"@
  $copiedSettings = $copiedSettings -replace "data:extend\(settings_data\)", ($override + "data:extend(settings_data)")
  Set-Content -LiteralPath $copiedSettingsPath -Value $copiedSettings -Encoding UTF8
}

function Set-CopiedLabPolicySkip {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-lab-incompatibility-policy" -ValueLiteral '"skip"'
}

function Set-CopiedSciencePackIngredientPolicy {
  param(
    [string]$ModsDir,
    [ValidateSet("configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all")]
    [string]$Policy
  )
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-science-pack-ingredient-policy" -ValueLiteral "`"$Policy`""
}

function Set-CopiedRequireSpaceGate {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "ips-require-space-gate" -ValueLiteral "true"
}

function Set-CopiedPipelineExtentMultiplier {
  param(
    [string]$ModsDir,
    [double]$Multiplier
  )
  $percent = [int][Math]::Round($Multiplier * 100)
  $allowedPercents = @(50, 75, 100, 125, 150, 200, 250, 300, 400, 500)
  if ($allowedPercents -notcontains $percent) {
    throw "Unsupported pipeline extent multiplier for dropdown validation: $Multiplier ($percent%)."
  }
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-pipeline-extent-multiplier" -ValueLiteral "`"$percent`""
}

function Set-CopiedStreamCheckboxDefault {
  param(
    [string]$ModsDir,
    [string]$StreamKey,
    [bool]$Enabled
  )

  $valueLiteral = if ($Enabled) { "true" } else { "false" }
  try {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "ips-enable-$StreamKey" -ValueLiteral $valueLiteral
    return
  } catch {
    $copiedDefaultsPath = Join-Path $ModsDir "more-infinite-research\defaults.lua"
    $copiedDefaults = Get-Content -Raw -LiteralPath $copiedDefaultsPath
    if ($copiedDefaults -notmatch "return\s+defaults") {
      throw "Unable to find return defaults in copied defaults.lua while setting stream $StreamKey."
    }

    $escapedStreamKey = $StreamKey.Replace("\", "\\").Replace('"', '\"')
    $override = "defaults.streams[`"$escapedStreamKey`"] = defaults.streams[`"$escapedStreamKey`"] or {}`r`ndefaults.streams[`"$escapedStreamKey`"].enabled = $valueLiteral`r`n"
    $copiedDefaults = $copiedDefaults -replace "return\s+defaults", ($override + "return defaults")
    Set-Content -LiteralPath $copiedDefaultsPath -Value $copiedDefaults -Encoding UTF8
  }
}

function Set-CopiedStreamEnabled {
  param(
    [string]$ModsDir,
    [string]$StreamKey
  )
  Set-CopiedStreamCheckboxDefault -ModsDir $ModsDir -StreamKey $StreamKey -Enabled $true
}

function Set-CopiedStreamDisabled {
  param(
    [string]$ModsDir,
    [string]$StreamKey
  )
  Set-CopiedStreamCheckboxDefault -ModsDir $ModsDir -StreamKey $StreamKey -Enabled $false
}

function Set-CopiedBaseExtensionDefault {
  param(
    [string]$ModsDir,
    [string]$BaseExtensionKey,
    [bool]$Enabled
  )
  $valueLiteral = if ($Enabled) { "true" } else { "false" }
  try {
    Set-CopiedGeneratedStartupSettingDefault -ModsDir $ModsDir -Name "mir-enable-$BaseExtensionKey" -ValueLiteral $valueLiteral
    return
  } catch {
    $copiedDefaultsPath = Join-Path $ModsDir "more-infinite-research\defaults.lua"
    $copiedDefaults = Get-Content -Raw -LiteralPath $copiedDefaultsPath
    if ($copiedDefaults -notmatch "return\s+defaults") {
      throw "Unable to find return defaults in copied defaults.lua while setting base extension $BaseExtensionKey."
    }

    $escapedBaseExtensionKey = $BaseExtensionKey.Replace("\", "\\").Replace('"', '\"')
    $override = "defaults.base_extensions[`"$escapedBaseExtensionKey`"] = defaults.base_extensions[`"$escapedBaseExtensionKey`"] or {}`r`ndefaults.base_extensions[`"$escapedBaseExtensionKey`"].enabled = $valueLiteral`r`n"
    $copiedDefaults = $copiedDefaults -replace "return\s+defaults", ($override + "return defaults")
    Set-Content -LiteralPath $copiedDefaultsPath -Value $copiedDefaults -Encoding UTF8
  }
}

function Set-CopiedBaseExtensionEnabled {
  param(
    [string]$ModsDir,
    [string]$BaseExtensionKey
  )
  Set-CopiedBaseExtensionDefault -ModsDir $ModsDir -BaseExtensionKey $BaseExtensionKey -Enabled $true
}

function Set-CopiedBaseExtensionDisabled {
  param(
    [string]$ModsDir,
    [string]$BaseExtensionKey
  )
  Set-CopiedBaseExtensionDefault -ModsDir $ModsDir -BaseExtensionKey $BaseExtensionKey -Enabled $false
}

function Initialize-RuntimeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$EnabledFixtureNames,
    [string[]]$EnabledStreamKeys = @(),
    [string[]]$EnabledBaseExtensionKeys = @(),
    [string[]]$DisabledStreamKeys = @(),
    [string[]]$DisabledBaseExtensionKeys = @(),
    [switch]$LabPolicySkip,
    [ValidateSet("configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all")]
    [string]$SciencePackIngredientPolicy = "configured",
    [ValidateSet("", "off", "only-when-dedicated-tech-enabled", "always")]
    [string]$WeaponSpeedAdjustmentMode = "",
    [double]$PipelineExtentMultiplier = 1,
    [switch]$RequireSpaceGate,
    [switch]$UseInstalledSpaceAgeIcons,
    [switch]$ScriptedDiagnostics,
    [switch]$EnableSpaceAge
  )

  $scenarioRoot = Join-Path $validationRoot $ScenarioName
  if (Test-Path -LiteralPath $scenarioRoot) {
    $resolvedScenarioRoot = (Resolve-Path -LiteralPath $scenarioRoot).Path
    if (-not $resolvedScenarioRoot.StartsWith($validationRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove scenario directory outside validation root: $resolvedScenarioRoot"
    }
    Remove-Item -LiteralPath $resolvedScenarioRoot -Recurse -Force
  }

  $modsDir = Join-Path $scenarioRoot "mods"
  New-Item -ItemType Directory -Force -Path $modsDir | Out-Null

  Copy-RepositoryModDirectory -ModsDir $modsDir

  $fixtureInfos = Get-FixtureInfos
  foreach ($fixtureInfo in $fixtureInfos) {
    Copy-ModDirectory -Source $fixtureInfo.Path -Name $fixtureInfo.Name -ModsDir $modsDir
  }

  $fixtureNames = @($fixtureInfos | Select-Object -ExpandProperty Name)
  $copiedInfoPath = Join-Path $modsDir "more-infinite-research\info.json"
  $copiedInfo = Get-Content -Raw -LiteralPath $copiedInfoPath | ConvertFrom-Json
  $dependencies = @($copiedInfo.dependencies)
  foreach ($fixtureName in @($fixtureNames | Where-Object { $_ -notin $postMirAssertionFixtures })) {
    $dependency = "? $fixtureName"
    if ($dependencies -notcontains $dependency) {
      $dependencies += $dependency
    }
  }
  $copiedInfo.dependencies = $dependencies
  $copiedInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $copiedInfoPath -Encoding UTF8

  Enable-CopiedDiagnostics -ModsDir $modsDir
  if ($ScriptedDiagnostics) {
    Enable-CopiedScriptedDiagnostics -ModsDir $modsDir
  }
  if ($LabPolicySkip) {
    Set-CopiedLabPolicySkip -ModsDir $modsDir
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

  $mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = "elevated-rails"; enabled = [bool]$EnableSpaceAge },
    @{ name = "recycler"; enabled = [bool]$EnableSpaceAge },
    @{ name = "quality"; enabled = [bool]$EnableSpaceAge },
    @{ name = "space-age"; enabled = [bool]$EnableSpaceAge },
    @{ name = "more-infinite-research"; enabled = $true }
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
  }
}

if ([string]::IsNullOrWhiteSpace($FactorioLog)) {
  $FactorioLog = Join-Path $validationRoot "factorio-current.log"
}

function Clear-FactorioLog {
  if (Test-Path -LiteralPath $FactorioLog) {
    Remove-Item -LiteralPath $FactorioLog -Force
  }
}

function Assert-RuntimeLogHealthy {
  param([string]$ScenarioName)
  Write-Host "[info] Factorio log path: $FactorioLog"
  if (-not (Test-Path -LiteralPath $FactorioLog)) {
    throw "Factorio log not found after $ScenarioName runtime validation: $FactorioLog"
  }

  $fatalMarkers = Select-String -LiteralPath $FactorioLog -Pattern "------------- Error -------------", "Error Util.cpp" -SimpleMatch
  if ($fatalMarkers) {
    $fatalMarkers | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line }
    throw "Factorio runtime validation log contains fatal error markers after $ScenarioName."
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
    [switch]$LabPolicySkip,
    [ValidateSet("configured", "space", "space-and-promethium", "space-age-progression", "official-progression", "mod-progression", "all-official", "all")]
    [string]$SciencePackIngredientPolicy = "configured",
    [ValidateSet("", "off", "only-when-dedicated-tech-enabled", "always")]
    [string]$WeaponSpeedAdjustmentMode = "",
    [double]$PipelineExtentMultiplier = 1,
    [switch]$RequireSpaceGate,
    [switch]$UseInstalledSpaceAgeIcons,
    [switch]$ScriptedDiagnostics,
    [switch]$EnableSpaceAge
  )

  $scenario = Initialize-RuntimeScenario `
    -ScenarioName $ScenarioName `
    -EnabledFixtureNames $EnabledFixtureNames `
    -EnabledStreamKeys $EnabledStreamKeys `
    -EnabledBaseExtensionKeys $EnabledBaseExtensionKeys `
    -DisabledStreamKeys $DisabledStreamKeys `
    -DisabledBaseExtensionKeys $DisabledBaseExtensionKeys `
    -LabPolicySkip:$LabPolicySkip `
    -SciencePackIngredientPolicy $SciencePackIngredientPolicy `
    -WeaponSpeedAdjustmentMode $WeaponSpeedAdjustmentMode `
    -PipelineExtentMultiplier $PipelineExtentMultiplier `
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
  $factorioExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $factorioArgs
  if ($factorioExitCode -ne 0) {
    throw "Factorio runtime validation scenario $ScenarioName exited with code $factorioExitCode"
  }
  if (-not (Test-Path -LiteralPath $scenario.SavePath)) {
    throw "Factorio runtime validation scenario $ScenarioName did not create the expected save: $($scenario.SavePath). Factorio exit code: $factorioExitCode"
  }

  Assert-RuntimeLogHealthy -ScenarioName $ScenarioName
}

function Invoke-RuntimeConfigurationChangeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$InitialFixtureNames = @(),
    [string[]]$ChangedFixtureNames = @(),
    [switch]$EnableSpaceAge
  )

  $initialScenario = Initialize-RuntimeScenario `
    -ScenarioName "$ScenarioName-initial" `
    -EnabledFixtureNames $InitialFixtureNames `
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
  $createExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $createArgs
  if ($createExitCode -ne 0) {
    throw "Factorio configuration-change initial scenario $ScenarioName exited with code $createExitCode"
  }
  if (-not (Test-Path -LiteralPath $initialScenario.SavePath)) {
    throw "Factorio configuration-change initial scenario $ScenarioName did not create the expected save: $($initialScenario.SavePath)."
  }

  Assert-RuntimeLogHealthy -ScenarioName "$ScenarioName initial"

  $changedScenario = Initialize-RuntimeScenario `
    -ScenarioName "$ScenarioName-changed" `
    -EnabledFixtureNames $ChangedFixtureNames `
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
  $benchmarkExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $benchmarkArgs
  if ($benchmarkExitCode -ne 0) {
    throw "Factorio configuration-change load scenario $ScenarioName exited with code $benchmarkExitCode"
  }

  Assert-RuntimeLogHealthy -ScenarioName "$ScenarioName changed"
}

function Get-LastStreamReportLine {
  param([string]$Key)
  $pattern = "kind=stream key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastExtensionReportLine {
  param([string]$Key)
  $pattern = "kind=extension key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain extension diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastNativeModifierOverlapLine {
  param([string]$Key)
  $pattern = "kind=native_modifier_overlap key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain native modifier overlap diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastCompatibilityPlanLine {
  param([string]$Key)
  $pattern = "kind=compatibility_plan key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain compatibility plan diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastDiagnosticReportLine {
  param([string]$Kind, [string]$Key)
  $pattern = "kind=$([regex]::Escape($Kind)) key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain $Kind diagnostics for $Key."
  }
  return $line.Line
}

function Get-DiagnosticReportLineContaining {
  param([string]$Kind, [string]$Key, [string]$Expected)
  $pattern = "kind=$([regex]::Escape($Kind)) key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern |
    Where-Object { $_.Line.Contains($Expected) } |
    Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain $Kind diagnostics for $Key with expected text '$Expected'."
  }
  return $line.Line
}

function Assert-NoDiagnosticReportLineContaining {
  param([string]$Kind, [string]$Key, [string]$Unexpected, [string]$Context)
  $pattern = "kind=$([regex]::Escape($Kind)) key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern |
    Where-Object { $_.Line.Contains($Unexpected) } |
    Select-Object -Last 1
  if ($line) {
    throw "$Context unexpectedly found $Kind diagnostics for $Key with text '$Unexpected': $($line.Line)"
  }
}

function Get-LastRecipeCapReportLine {
  param([string]$Recipe)
  $pattern = "kind=recipe_cap .*recipe=$([regex]::Escape($Recipe))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain recipe cap diagnostics for $Recipe."
  }
  return $line.Line
}

function Assert-ReportLineGenerated {
  param([string]$Line, [string]$Context)
  if ($Line -notmatch "status=generated") {
    throw "$Context did not generate as expected: $Line"
  }
}

function Assert-ReportLineAdopted {
  param([string]$Line, [string]$Context)
  if ($Line -notmatch "status=adopted") {
    throw "$Context did not adopt as expected: $Line"
  }
}

function Assert-ReportLineContains {
  param([string]$Line, [string]$Expected, [string]$Context)
  if (-not $Line.Contains($Expected)) {
    throw "$Context did not include expected text '$Expected': $Line"
  }
}

function Assert-ReportLineDoesNotContain {
  param([string]$Line, [string]$Unexpected, [string]$Context)
  if ($Line.Contains($Unexpected)) {
    throw "$Context unexpectedly included '$Unexpected': $Line"
  }
}

function Get-ReportScienceField {
  param([string]$Line)
  $match = [regex]::Match($Line, " science=([^ ]*) ")
  if (-not $match.Success) {
    throw "Generation report line did not include a parseable science field: $Line"
  }
  return $match.Groups[1].Value
}

function Assert-ReportScienceContains {
  param([string]$Line, [string]$Expected, [string]$Context)
  $science = Get-ReportScienceField -Line $Line
  $packs = @()
  if ($science.Length -gt 0) { $packs = $science -split "," }
  if ($packs -notcontains $Expected) {
    throw "$Context science field did not include expected pack '$Expected': $Line"
  }
}

function Assert-ReportScienceDoesNotContain {
  param([string]$Line, [string]$Unexpected, [string]$Context)
  $science = Get-ReportScienceField -Line $Line
  $packs = @()
  if ($science.Length -gt 0) { $packs = $science -split "," }
  if ($packs -contains $Unexpected) {
    throw "$Context science field unexpectedly included pack '$Unexpected': $Line"
  }
}

function Assert-LogContains {
  param([string]$Expected, [string]$Context)
  $line = Select-String -LiteralPath $FactorioLog -Pattern $Expected -SimpleMatch | Select-Object -Last 1
  if (-not $line) {
    throw "$Context missing expected runtime log text '$Expected'."
  }
  return $line.Line
}

function Assert-LogDoesNotContain {
  param([string]$Unexpected, [string]$Context)
  $line = Select-String -LiteralPath $FactorioLog -Pattern $Unexpected -SimpleMatch | Select-Object -Last 1
  if ($line) {
    throw "$Context unexpectedly found runtime log text '$Unexpected': $($line.Line)"
  }
}

function Assert-NoStreamReportLine {
  param([string]$Key, [string]$Context)
  $pattern = "kind=stream key=$([regex]::Escape($Key))(\s|$)"
  $line = Select-String -LiteralPath $FactorioLog -Pattern $pattern | Select-Object -Last 1
  if ($line) {
    throw "$Context unexpectedly found stream diagnostics for ${Key}: $($line.Line)"
  }
}

$defaultEnabledBaseExtensionKeys = @(
  "braking-force",
  "research-speed",
  "worker-robots-storage",
  "weapon-shooting-speed",
  "laser-shooting-speed"
)

$spaceAgeVanillaOwnedProductivityStreams = @(
  "research_low_density_structure",
  "research_plastic",
  "research_processing_unit",
  "research_rocket_fuel"
)

function Assert-DefaultBaseExtensionDiagnostics {
  param(
    [string]$Context,
    [switch]$InserterCapacityEnabled
  )

  $expectedGenerated = @($defaultEnabledBaseExtensionKeys)
  if ($InserterCapacityEnabled) {
    $expectedGenerated += "inserter-capacity-bonus"
  }

  foreach ($key in $expectedGenerated) {
    $line = Get-LastExtensionReportLine -Key $key
    Assert-ReportLineGenerated -Line $line -Context "$Context base extension $key"
  }

  if (-not $InserterCapacityEnabled) {
    $inserterLine = Get-LastExtensionReportLine -Key "inserter-capacity-bonus"
    if ($inserterLine -notmatch "status=skipped" -or $inserterLine -notmatch "disabled") {
      throw "$Context expected disabled inserter-capacity-bonus extension to skip cleanly: $inserterLine"
    }
  }
}

function Assert-SpaceAgeVanillaOwnedProductivityStreamsSkipped {
  param([string]$Context)

  foreach ($vanillaOwnedStream in $spaceAgeVanillaOwnedProductivityStreams) {
    $vanillaOwnedLine = Get-LastStreamReportLine -Key $vanillaOwnedStream
    if ($vanillaOwnedLine -notmatch "status=skipped" -or $vanillaOwnedLine -notmatch "covered_by_existing_infinite_recipe_productivity") {
      throw "$Context should skip vanilla-owned productivity instead of generating a parallel MIR technology: $vanillaOwnedLine"
    }
  }
}

function Assert-BaseCoreProductivityStreamsGenerated {
  param([string]$Context)

  foreach ($stream in @(
    "research_electronic_circuit",
    "research_advanced_circuit",
    "research_processing_unit",
    "research_low_density_structure",
    "research_plastic",
    "research_rocket_fuel"
  )) {
    $line = Get-LastStreamReportLine -Key $stream
    Assert-ReportLineGenerated -Line $line -Context "$Context stream $stream"
  }
}

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

Invoke-RuntimeScenario -ScenarioName "reduce-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-science-pack-productivity"
)

$sciencePackProductivityLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $sciencePackProductivityLine -Context "Science pack productivity reduce-policy scenario"
Assert-ReportLineContains -Line $sciencePackProductivityLine -Expected "mir-fixture-science-pack" -Context "Science pack productivity reduce-policy scenario"
Assert-ReportLineContains -Line $sciencePackProductivityLine -Expected "tech:space-science-pack" -Context "Base science pack productivity fallback icon scenario"
$effectCountMatch = [regex]::Match($sciencePackProductivityLine, "effects=(\d+)")
if (-not $effectCountMatch.Success) {
  throw "Science pack productivity diagnostics did not include an effect count: $sciencePackProductivityLine"
}
$sciencePackEffectCount = [int]$effectCountMatch.Groups[1].Value
if ($sciencePackEffectCount -lt 1) {
  throw "Science pack productivity stream did not include any recipe productivity effects: $sciencePackProductivityLine"
}
$baseLabProductivityLine = Get-LastStreamReportLine -Key "research_lab_productivity"
Assert-ReportLineGenerated -Line $baseLabProductivityLine -Context "Base research productivity scenario"
Assert-ReportLineContains -Line $baseLabProductivityLine -Expected "effects=1" -Context "Base research productivity scenario"
Assert-ReportLineContains -Line $baseLabProductivityLine -Expected "icon=tech:military-science-pack" -Context "Base research productivity icon scenario"
$compatibilityPlanLine = Get-LastCompatibilityPlanLine -Key "compatibility_planner"
Assert-ReportLineContains -Line $compatibilityPlanLine -Expected "status=diagnostic" -Context "Base compatibility planner diagnostics scenario"
$compilerPlanLine = Get-LastCompatibilityPlanLine -Key "productivity_compiler"
Assert-ReportLineContains -Line $compilerPlanLine -Expected "reason=fact_registry_summary" -Context "Base compiler planner summary scenario"
$ownerRegistryLine = Get-LastCompatibilityPlanLine -Key "owner_registry"
Assert-ReportLineContains -Line $ownerRegistryLine -Expected "reason=owner_facts_indexed" -Context "Base compiler owner registry scenario"
$factRegistryLine = Get-LastDiagnosticReportLine -Kind "fact_registry" -Key "prototype_index"
Assert-ReportLineContains -Line $factRegistryLine -Expected "status=diagnostic" -Context "Base compiler fact registry scenario"
Assert-ReportLineContains -Line $factRegistryLine -Expected "recipes=" -Context "Base compiler fact registry recipe count scenario"
$labMatrixLine = Get-LastDiagnosticReportLine -Kind "lab_matrix" -Key "lab"
Assert-ReportLineContains -Line $labMatrixLine -Expected "reason=lab_inputs_indexed" -Context "Base compiler lab matrix scenario"
$generatedDecisionLine = Get-LastDiagnosticReportLine -Kind "decision" -Key "recipe-prod-research_lab_productivity-1"
Assert-ReportLineContains -Line $generatedDecisionLine -Expected "decision=generate_stream" -Context "Base compiler generated decision scenario"
Assert-ReportLineContains -Line $generatedDecisionLine -Expected "stable_stream_id=recipe-prod-research_lab_productivity-1" -Context "Base compiler stable ID scenario"
$nativeLabCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "laboratory-productivity" -Expected "capability=native-modifier-ownership"
Assert-ReportLineContains -Line $nativeLabCapabilityLine -Expected "decision=observe_existing_owner" -Context "Native modifier ownership resolver scenario"
$nativeMiningCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "mining-drill-productivity-bonus" -Expected "capability=native-modifier-ownership"
Assert-ReportLineContains -Line $nativeMiningCapabilityLine -Expected "subfamily=native_mining_yield" -Context "Native mining-yield resolver scenario"

Invoke-RuntimeScenario -ScenarioName "recipe-cap-diagnostics" -EnabledFixtureNames @(
  "mir-fixture-recipe-cap-diagnostics"
)
$capPlanLine = Get-LastCompatibilityPlanLine -Key "recipe_productivity_caps"
Assert-ReportLineContains -Line $capPlanLine -Expected "warnings=" -Context "Recipe cap diagnostics summary scenario"
$loweredCapLine = Get-LastRecipeCapReportLine -Recipe "iron-gear-wheel"
Assert-ReportLineContains -Line $loweredCapLine -Expected "cap_state=lowered" -Context "Lowered recipe cap diagnostics scenario"
Assert-ReportLineContains -Line $loweredCapLine -Expected "useful_level_estimate=2" -Context "Lowered recipe cap useful-level diagnostics scenario"
$ruleMutationLine = Get-LastDiagnosticReportLine -Kind "rule_mutation" -Key "iron-gear-wheel"
Assert-ReportLineContains -Line $ruleMutationLine -Expected "field=maximum_productivity" -Context "Recipe cap rule-surface diagnostics scenario"
Assert-ReportLineContains -Line $ruleMutationLine -Expected "observed_value=0.2" -Context "Recipe cap rule-surface value scenario"
$raisedCapLine = Get-LastRecipeCapReportLine -Recipe "iron-plate"
Assert-ReportLineContains -Line $raisedCapLine -Expected "cap_state=raised" -Context "Raised recipe cap diagnostics scenario"
$extremeCapLine = Get-LastRecipeCapReportLine -Recipe "copper-cable"
Assert-ReportLineContains -Line $extremeCapLine -Expected "warning_class=uncapped_or_extreme" -Context "Extreme recipe cap diagnostics scenario"

Invoke-RuntimeScenario -ScenarioName "capability-negative-cases" -EnabledFixtureNames @(
  "mir-fixture-capability-negative-cases",
  "mir-fixture-assert-capability-negative-cases"
)
$selfLoopRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-self-loop-filter-cleaning" -Expected "catalyst_or_self_return"
Assert-ReportLineContains -Line $selfLoopRiskLine -Expected "cleaning_or_recovery_loop" -Context "Negative self-loop cleaning risk scenario"
$barrelRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-barrel-return-loop" -Expected "barrel_or_container_return"
Assert-ReportLineContains -Line $barrelRiskLine -Expected "catalyst_or_self_return" -Context "Negative barrel return risk scenario"
$voidRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-voiding-sink" -Expected "voiding_or_destruction"
Assert-ReportLineContains -Line $voidRiskLine -Expected "voiding_or_destruction" -Context "Negative voiding risk scenario"
$matterRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-matter-transmutation" -Expected "matter_or_transmutation"
Assert-ReportLineContains -Line $matterRiskLine -Expected "matter_or_transmutation" -Context "Negative transmutation risk scenario"
$hiddenRiskLine = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "mir-hidden-internal-recipe" -Expected "hidden_internal"
Assert-ReportLineContains -Line $hiddenRiskLine -Expected "hidden_internal" -Context "Negative hidden recipe risk scenario"
$zeroCapRuleLine = Get-DiagnosticReportLineContaining -Kind "rule_mutation" -Key "mir-zero-cap-productivity" -Expected "observed_value=0"
Assert-ReportLineContains -Line $zeroCapRuleLine -Expected "field=maximum_productivity" -Context "Negative zero-cap rule-surface scenario"
Assert-NoDiagnosticReportLineContaining -Kind "decision" -Key "mir-loader-like-container" -Unexpected "capability=logistics-loader-manufacturing" -Context "Negative loader-like container capability scenario"
Assert-NoDiagnosticReportLineContaining -Kind "decision" -Key "mir-drill-like-container" -Unexpected "capability=mining-drill-manufacturing" -Context "Negative drill-like container capability scenario"

Invoke-RuntimeScenario -ScenarioName "lab-productivity-owner-skip" -EnabledFixtureNames @(
  "mir-fixture-lab-productivity-owner",
  "mir-fixture-assert-lab-productivity-owner-skip"
)
$labProductivityOwnerSkipLine = Get-LastStreamReportLine -Key "research_lab_productivity"
if ($labProductivityOwnerSkipLine -notmatch "status=skipped" -or $labProductivityOwnerSkipLine -notmatch "existing technology effect laboratory-productivity-4 laboratory-productivity") {
  throw "MIR research productivity should skip when laboratory-productivity-4 has the expected native effect: $labProductivityOwnerSkipLine"
}

Invoke-RuntimeScenario -ScenarioName "better-bot-battery-owner-skip" -EnabledFixtureNames @(
  "mir-fixture-better-bot-battery-owner",
  "mir-fixture-assert-better-bot-battery-skip"
)
$betterBotBatterySkipLine = Get-LastStreamReportLine -Key "research_robot_battery"
if ($betterBotBatterySkipLine -notmatch "status=skipped" -or $betterBotBatterySkipLine -notmatch "existing technology effect worker-robots-battery-6 worker-robot-battery") {
  throw "MIR robot battery should skip when worker-robots-battery-6 has the expected native effect: $betterBotBatterySkipLine"
}

Invoke-RuntimeScenario -ScenarioName "skip-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-lab-skip-policy"
) -LabPolicySkip

$skipPolicyLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
if ($skipPolicyLine -notmatch "status=skipped" -or $skipPolicyLine -notmatch "lab_status=invalid") {
  throw "Skip-policy runtime validation did not skip incompatible science-pack productivity as expected: $skipPolicyLine"
}

Invoke-RuntimeScenario -ScenarioName "space-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space"
$spacePackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spacePackLine -Context "Space science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spacePackLine -Expected "space-science-pack" -Context "Space science-pack ingredient policy scenario"
$baseElectricShootingLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $baseElectricShootingLine -Context "Base electric shooting speed scenario"
Assert-ReportLineContains -Line $baseElectricShootingLine -Expected "effects=1" -Context "Base electric shooting speed scenario"
Assert-ReportLineContains -Line $baseElectricShootingLine -Expected "icon=tech:discharge-defense-equipment" -Context "Base electric shooting speed scenario"
$baseFlamethrowerShootingLine = Get-LastStreamReportLine -Key "research_flamethrower_shooting_speed"
Assert-ReportLineGenerated -Line $baseFlamethrowerShootingLine -Context "Base flamethrower shooting speed scenario"

Invoke-RuntimeScenario -ScenarioName "character-inventory-merged-effects" -EnabledFixtureNames @()
$inventoryCapacityLine = Get-LastStreamReportLine -Key "research_inventory_capacity"
Assert-ReportLineGenerated -Line $inventoryCapacityLine -Context "Merged character inventory/trash slot scenario"
Assert-ReportLineContains -Line $inventoryCapacityLine -Expected "effects=2" -Context "Merged character inventory/trash slot scenario"
Assert-NoStreamReportLine -Key "research_character_trash_slots" -Context "Merged character inventory/trash slot scenario"

Invoke-RuntimeScenario -ScenarioName "base-generation-integrity" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity",
  "mir-fixture-assert-hidden-setting-readability"
)
Assert-LogDoesNotContain -Unexpected "Applied pipeline extent multiplier" -Context "Default pipeline extent scenario"
Assert-BaseCoreProductivityStreamsGenerated -Context "Base generation integrity scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Base generation integrity scenario"
$baseRailsLine = Get-LastStreamReportLine -Key "research_rails"
Assert-ReportLineContains -Line $baseRailsLine -Expected "effects=1" -Context "Base rail productivity scenario"
Assert-ReportLineContains -Line $baseRailsLine -Expected "icon=item:rail" -Context "Base rail productivity icon scenario"

Invoke-RuntimeScenario -ScenarioName "base-fluid-productivity" -EnabledFixtureNames @(
  "mir-fixture-assert-fluid-productivity"
)
Assert-FluidProductivityStreamsGenerated -Context "Base fluid productivity scenario"
$baseOilCrackingLine = Get-LastStreamReportLine -Key "research_oil_cracking_productivity"
Assert-ReportLineContains -Line $baseOilCrackingLine -Expected "icon=tech:oil-processing" -Context "Base oil cracking icon scenario"
$baseSulfuricAcidLine = Get-LastStreamReportLine -Key "research_sulfuric_acid_productivity"
Assert-ReportLineContains -Line $baseSulfuricAcidLine -Expected "icon=fluid:sulfuric-acid" -Context "Base sulfuric acid icon scenario"
foreach ($baseThrusterStream in @("research_thruster_fuel_productivity", "research_thruster_oxidizer_productivity")) {
  $baseThrusterLine = Get-LastStreamReportLine -Key $baseThrusterStream
  if ($baseThrusterLine -notmatch "status=skipped" -or $baseThrusterLine -notmatch "missing required fluid") {
    throw "Base-only thruster fluid stream $baseThrusterStream should skip for missing fluid: $baseThrusterLine"
  }
}

Invoke-RuntimeScenario -ScenarioName "aai-loader-belt-productivity" -EnabledFixtureNames @(
  "mir-fixture-aai-loaders",
  "mir-fixture-assert-aai-loader-belt-productivity"
)
$aaiLoaderBeltLine = Get-LastStreamReportLine -Key "research_belts"
Assert-ReportLineGenerated -Line $aaiLoaderBeltLine -Context "AAI loader belt productivity scenario"
$aaiLoaderCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "aai-turbo-loader" -Expected "capability=logistics-loader-manufacturing"
Assert-ReportLineContains -Line $aaiLoaderCapabilityLine -Expected "decision=generate_stream" -Context "AAI loader capability resolver scenario"
Assert-ReportLineContains -Line $aaiLoaderCapabilityLine -Expected "subfamily=loader" -Context "AAI loader capability subfamily scenario"
Assert-ReportLineContains -Line $aaiLoaderCapabilityLine -Expected "evidence=item_type:item,item_place_result:aai-turbo-loader,entity_type:loader-1x1,recipe_outputs_item:aai-turbo-loader" -Context "AAI loader entity-backed evidence scenario"

Invoke-RuntimeScenario -ScenarioName "big-mining-drill-productivity" -EnabledFixtureNames @(
  "mir-fixture-big-mining-drill",
  "mir-fixture-assert-big-mining-drill-productivity"
)
$bigMiningDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $bigMiningDrillLine -Context "Big Mining Drill productivity scenario"
$bigMiningCapabilityLine = Get-DiagnosticReportLineContaining -Kind "decision" -Key "big-mining-drill" -Expected "capability=mining-drill-manufacturing"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "decision=generate_stream" -Context "Big Mining Drill capability resolver scenario"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "subfamily=mining_drill" -Context "Big Mining Drill capability subfamily scenario"
Assert-ReportLineContains -Line $bigMiningCapabilityLine -Expected "evidence=item_type:item,item_place_result:big-mining-drill,entity_type:mining-drill,recipe_outputs_item:big-mining-drill" -Context "Big Mining Drill entity-backed evidence scenario"

Invoke-RuntimeScenario -ScenarioName "atan-nuclear-science-productivity" -EnabledFixtureNames @(
  "mir-fixture-atan-nuclear-science",
  "mir-fixture-assert-atan-nuclear-science-productivity"
)
$atanNuclearScienceLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $atanNuclearScienceLine -Context "ATAN Nuclear Science science-pack productivity scenario"
Assert-ReportLineContains -Line $atanNuclearScienceLine -Expected "nuclear-science-pack" -Context "ATAN Nuclear Science lab-input science scenario"
Assert-ReportLineContains -Line $atanNuclearScienceLine -Expected "atan-nuclear-science" -Context "ATAN Nuclear Science unlock prerequisite scenario"

Invoke-RuntimeScenario -ScenarioName "atan-ash-separation" -EnabledFixtureNames @(
  "mir-fixture-atan-ash",
  "mir-fixture-assert-atan-ash-separation"
)
$atanAshLine = Get-LastStreamReportLine -Key "research_ash_separation"
Assert-ReportLineGenerated -Line $atanAshLine -Context "ATAN Ash separation productivity scenario"
Assert-ReportLineContains -Line $atanAshLine -Expected "effects=1" -Context "ATAN Ash separation effect count scenario"
Assert-ReportLineContains -Line $atanAshLine -Expected "atan-ash-processing" -Context "ATAN Ash unlock prerequisite scenario"
Assert-NoDiagnosticReportLineContaining -Kind "stream" -Key "research_landfill" -Unexpected "atan-landfill-from-ash" -Context "ATAN Ash landfill sink exclusion scenario"
Assert-NoDiagnosticReportLineContaining -Kind "stream" -Key "research_concrete" -Unexpected "atan-stone-brick-from-ash" -Context "ATAN Ash brick sink exclusion scenario"
$atanAshPlanLine = Get-LastCompatibilityPlanLine -Key "research_ash_separation"
Assert-ReportLineContains -Line $atanAshPlanLine -Expected "reason=atan_ash_policy_summary" -Context "ATAN Ash policy summary scenario"
Assert-ReportLineContains -Line $atanAshPlanLine -Expected "generated=1" -Context "ATAN Ash generated target count scenario"
Assert-ReportLineContains -Line $atanAshPlanLine -Expected "rejected=4" -Context "ATAN Ash rejected sink count scenario"
$atanAshAllowedDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-ash-seperation" -Expected "stable_stream_id=mir-prod-atan-ash-separation"
Assert-ReportLineContains -Line $atanAshAllowedDecision -Expected "decision=generate_stream" -Context "ATAN Ash allowed decision scenario"
$atanAshTileDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-landfill-from-ash" -Expected "risks=tile_surface"
Assert-ReportLineContains -Line $atanAshTileDecision -Expected "decision=diagnose_only" -Context "ATAN Ash tile-surface deny decision scenario"
$atanAshSinkDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-stone-brick-from-ash" -Expected "risks=ash_sink"
Assert-ReportLineContains -Line $atanAshSinkDecision -Expected "decision=diagnose_only" -Context "ATAN Ash sink deny decision scenario"
$atanAshTileRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-landfill-from-ash" -Expected "risks=tile_surface"
Assert-ReportLineContains -Line $atanAshTileRisk -Expected "risks=tile_surface" -Context "ATAN Ash tile-surface loop-risk scenario"
$atanAshSinkRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-stone-brick-from-ash" -Expected "risks=ash_sink"
Assert-ReportLineContains -Line $atanAshSinkRisk -Expected "risks=ash_sink" -Context "ATAN Ash sink loop-risk scenario"

Invoke-RuntimeScenario -ScenarioName "air-scrubbing-clean-filter" -EnabledFixtureNames @(
  "mir-fixture-air-scrubbing",
  "mir-fixture-assert-air-scrubbing-clean-filter"
)
$airScrubbingLine = Get-LastStreamReportLine -Key "research_air_scrubbing_clean_filter"
Assert-ReportLineGenerated -Line $airScrubbingLine -Context "Air Scrubbing clean-filter productivity scenario"
Assert-ReportLineContains -Line $airScrubbingLine -Expected "effects=2" -Context "Air Scrubbing clean-filter effect count scenario"
Assert-ReportLineContains -Line $airScrubbingLine -Expected "atan-pollution-scrubbing" -Context "Air Scrubbing pollution unlock prerequisite scenario"
Assert-ReportLineContains -Line $airScrubbingLine -Expected "atan-spore-scrubbing" -Context "Air Scrubbing spore unlock prerequisite scenario"
$airScrubbingPlanLine = Get-LastCompatibilityPlanLine -Key "research_air_scrubbing_clean_filter"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "reason=air_scrubbing_policy_summary" -Context "Air Scrubbing policy summary scenario"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "generated=2" -Context "Air Scrubbing generated target count scenario"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "rejected=4" -Context "Air Scrubbing rejected target count scenario"
Assert-ReportLineContains -Line $airScrubbingPlanLine -Expected "unknown=1" -Context "Air Scrubbing unknown target count scenario"
$airScrubbingAllowedDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-pollution-filter" -Expected "stable_stream_id=mir-prod-air-scrubbing-clean-filter"
Assert-ReportLineContains -Line $airScrubbingAllowedDecision -Expected "decision=generate_stream" -Context "Air Scrubbing allowed decision scenario"
Assert-ReportLineContains -Line $airScrubbingAllowedDecision -Expected "stable_stream_id=mir-prod-air-scrubbing-clean-filter" -Context "Air Scrubbing stable stream ID scenario"
$airScrubbingScrubDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-pollution-scrubbing" -Expected "risks=scrubbing_environmental"
Assert-ReportLineContains -Line $airScrubbingScrubDecision -Expected "decision=diagnose_only" -Context "Air Scrubbing scrubbing deny decision scenario"
Assert-ReportLineContains -Line $airScrubbingScrubDecision -Expected "risks=scrubbing_environmental" -Context "Air Scrubbing scrubbing risk scenario"
$airScrubbingScrubRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-pollution-scrubbing" -Expected "risks=scrubbing_environmental"
Assert-ReportLineContains -Line $airScrubbingScrubRisk -Expected "risks=scrubbing_environmental" -Context "Air Scrubbing scrubbing loop-risk scenario"
$airScrubbingCleaningDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-pollution-filter-cleaning" -Expected "risks=cleaning_recovery"
Assert-ReportLineContains -Line $airScrubbingCleaningDecision -Expected "decision=diagnose_only" -Context "Air Scrubbing cleaning deny decision scenario"
Assert-ReportLineContains -Line $airScrubbingCleaningDecision -Expected "risks=cleaning_recovery" -Context "Air Scrubbing cleaning risk scenario"
$airScrubbingCleaningRisk = Get-DiagnosticReportLineContaining -Kind "loop_risk" -Key "atan-pollution-filter-cleaning" -Expected "risks=cleaning_recovery"
Assert-ReportLineContains -Line $airScrubbingCleaningRisk -Expected "risks=cleaning_recovery" -Context "Air Scrubbing cleaning loop-risk scenario"
$airScrubbingUnknownDecision = Get-DiagnosticReportLineContaining -Kind "decision" -Key "atan-filter-resin" -Expected "decision=observe_unknown"
Assert-ReportLineContains -Line $airScrubbingUnknownDecision -Expected "decision=observe_unknown" -Context "Air Scrubbing unknown related decision scenario"

Invoke-RuntimeScenario -ScenarioName "pipeline-extent-multiplier" -EnabledFixtureNames @(
  "mir-fixture-assert-pipeline-extent"
) -PipelineExtentMultiplier 2
Assert-LogContains -Expected "Applied pipeline extent multiplier 2" -Context "Pipeline extent multiplier scenario"

Invoke-RuntimeScenario -ScenarioName "pipeline-extent-multiplier-50" -EnabledFixtureNames @(
  "mir-fixture-assert-pipeline-extent"
) -PipelineExtentMultiplier 0.5
Assert-LogContains -Expected "Applied pipeline extent multiplier 0.5" -Context "Pipeline extent multiplier 50 percent scenario"

Invoke-RuntimeScenario -ScenarioName "base-generation-integrity-inserter-enabled" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -EnabledBaseExtensionKeys @(
  "inserter-capacity-bonus"
)
Assert-BaseCoreProductivityStreamsGenerated -Context "Base generation integrity with inserter enabled scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Base generation integrity with inserter enabled scenario" -InserterCapacityEnabled

Invoke-RuntimeScenario -ScenarioName "base-installed-space-age-icon-assets" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -UseInstalledSpaceAgeIcons
Assert-BaseCoreProductivityStreamsGenerated -Context "Base installed Space Age icon asset scenario"
$baseInstalledElectricIconLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $baseInstalledElectricIconLine -Context "Base installed Space Age electric icon scenario"
Assert-ReportLineContains -Line $baseInstalledElectricIconLine -Expected "icon=__space-age__/graphics/technology/electric-weapons-damage.png" -Context "Base installed Space Age electric icon scenario"
$baseInstalledScienceIconLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $baseInstalledScienceIconLine -Context "Base installed Space Age science productivity icon scenario"
Assert-ReportLineContains -Line $baseInstalledScienceIconLine -Expected "icon=__space-age__/graphics/technology/research-productivity.png" -Context "Base installed Space Age science productivity icon scenario"
$baseInstalledRailsIconLine = Get-LastStreamReportLine -Key "research_rails"
Assert-ReportLineGenerated -Line $baseInstalledRailsIconLine -Context "Base installed official DLC rail productivity icon scenario"
Assert-ReportLineContains -Line $baseInstalledRailsIconLine -Expected "icon=__elevated-rails__/graphics/technology/elevated-rail.png" -Context "Base installed official DLC rail productivity icon scenario"

Invoke-RuntimeScenario -ScenarioName "checkbox-enabled-default-off-features" -EnabledFixtureNames @() `
  -EnabledStreamKeys @("research_character_reach") `
  -EnabledBaseExtensionKeys @("inserter-capacity-bonus")
$checkboxEnabledReachLine = Get-LastStreamReportLine -Key "research_character_reach"
Assert-ReportLineGenerated -Line $checkboxEnabledReachLine -Context "Checkbox-enabled stream scenario"
$checkboxEnabledInserterLine = Get-LastExtensionReportLine -Key "inserter-capacity-bonus"
Assert-ReportLineGenerated -Line $checkboxEnabledInserterLine -Context "Checkbox-enabled base extension scenario"

Invoke-RuntimeScenario -ScenarioName "checkbox-disabled-default-on-features" -EnabledFixtureNames @() `
  -DisabledStreamKeys @("research_gears") `
  -DisabledBaseExtensionKeys @("research-speed")
$checkboxDisabledGearsLine = Get-LastStreamReportLine -Key "research_gears"
if ($checkboxDisabledGearsLine -notmatch "status=skipped" -or $checkboxDisabledGearsLine -notmatch "disabled") {
  throw "Disabled stream checkbox should skip generated research: $checkboxDisabledGearsLine"
}
$checkboxDisabledResearchSpeedLine = Get-LastExtensionReportLine -Key "research-speed"
if ($checkboxDisabledResearchSpeedLine -notmatch "status=skipped" -or $checkboxDisabledResearchSpeedLine -notmatch "disabled") {
  throw "Disabled base extension checkbox should skip generated continuation: $checkboxDisabledResearchSpeedLine"
}

Invoke-RuntimeScenario -ScenarioName "base-space-promethium-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-and-promethium"
$baseSpacePromethiumPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $baseSpacePromethiumPackLine -Context "Base space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $baseSpacePromethiumPackLine -Expected "space-science-pack" -Context "Base space and promethium science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $baseSpacePromethiumPackLine -Unexpected "promethium-science-pack" -Context "Base space and promethium science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-space-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space" -EnableSpaceAge
$spaceAgeSpacePackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeSpacePackLine -Context "Space Age space-only science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePackLine -Expected "space-science-pack" -Context "Space Age space-only science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $spaceAgeSpacePackLine -Unexpected "promethium-science-pack" -Context "Space Age space-only science-pack ingredient policy scenario"
$spaceAgeElectricShootingLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $spaceAgeElectricShootingLine -Context "Space Age electric and Tesla shooting speed scenario"
Assert-ReportLineContains -Line $spaceAgeElectricShootingLine -Expected "effects=2" -Context "Space Age electric and Tesla shooting speed scenario"
Assert-ReportLineContains -Line $spaceAgeElectricShootingLine -Expected "icon=tech:electric-weapons-damage-1" -Context "Space Age electric and Tesla shooting speed icon scenario"
$spaceAgeLabProductivityLine = Get-LastStreamReportLine -Key "research_lab_productivity"
if ($spaceAgeLabProductivityLine -notmatch "status=skipped" -or $spaceAgeLabProductivityLine -notmatch "existing technology effect research-productivity laboratory-productivity") {
  throw "Space Age should skip MIR research productivity because vanilla research-productivity already exists: $spaceAgeLabProductivityLine"
}

Invoke-RuntimeScenario -ScenarioName "space-age-progression-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-age-progression" -EnableSpaceAge
$spaceAgeProgressionGearsLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeProgressionGearsLine -Context "Space Age progression science-pack ingredient policy base stream scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeProgressionGearsLine -Unexpected "space-science-pack" -Context "Space Age progression science-pack ingredient policy base stream scenario"
$spaceAgeProgressionOilLine = Get-LastStreamReportLine -Key "research_oil_processing_productivity"
Assert-ReportLineGenerated -Line $spaceAgeProgressionOilLine -Context "Space Age progression science-pack ingredient policy planet stream scenario"
Assert-ReportScienceContains -Line $spaceAgeProgressionOilLine -Expected "cryogenic-science-pack" -Context "Space Age progression science-pack ingredient policy planet stream scenario"
Assert-ReportScienceContains -Line $spaceAgeProgressionOilLine -Expected "space-science-pack" -Context "Space Age progression science-pack ingredient policy planet stream scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeProgressionOilLine -Unexpected "promethium-science-pack" -Context "Space Age progression science-pack ingredient policy planet stream scenario"

Invoke-RuntimeScenario -ScenarioName "official-progression-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "official-progression" -EnableSpaceAge
$officialProgressionOilLine = Get-LastStreamReportLine -Key "research_oil_processing_productivity"
Assert-ReportLineGenerated -Line $officialProgressionOilLine -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceContains -Line $officialProgressionOilLine -Expected "utility-science-pack" -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceContains -Line $officialProgressionOilLine -Expected "space-science-pack" -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceContains -Line $officialProgressionOilLine -Expected "cryogenic-science-pack" -Context "Official progression science-pack ingredient policy scenario"
Assert-ReportScienceDoesNotContain -Line $officialProgressionOilLine -Unexpected "agricultural-science-pack" -Context "Official progression science-pack ingredient policy should not add unrelated planet packs"

Invoke-RuntimeScenario -ScenarioName "mod-progression-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "mod-progression"
$modProgressionGearsLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $modProgressionGearsLine -Context "Mod progression science-pack ingredient policy base stream scenario"
Assert-ReportScienceDoesNotContain -Line $modProgressionGearsLine -Unexpected "mir-fixture-science-pack" -Context "Mod progression science-pack ingredient policy base stream scenario"
$modProgressionScienceLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $modProgressionScienceLine -Context "Mod progression science-pack ingredient policy selected mod pack scenario"
Assert-ReportScienceContains -Line $modProgressionScienceLine -Expected "mir-fixture-science-pack" -Context "Mod progression science-pack ingredient policy selected mod pack scenario"

if ($isFactorio21Line) {
  Invoke-RuntimeScenario -ScenarioName "base-scripted-candidates-enabled" -EnabledFixtureNames @() -EnabledStreamKeys @(
    "research_spoilage_preservation",
    "research_agricultural_growth_speed"
  )
  foreach ($scriptedStream in @("research_spoilage_preservation", "research_agricultural_growth_speed")) {
    $baseScriptedLine = Get-LastStreamReportLine -Key $scriptedStream
    if ($baseScriptedLine -notmatch "status=skipped" -or $baseScriptedLine -notmatch "missing required mod space-age") {
      throw "Base-only scripted candidate stream $scriptedStream should skip for missing Space Age when force-enabled: $baseScriptedLine"
    }
  }

  Invoke-RuntimeScenario -ScenarioName "space-age-scripted-candidates-enabled" -EnabledFixtureNames @(
    "mir-fixture-assert-generation-integrity"
  ) -EnabledStreamKeys @(
    "research_spoilage_preservation",
    "research_agricultural_growth_speed"
  ) -ScriptedDiagnostics -EnableSpaceAge
  foreach ($scriptedStream in @("research_spoilage_preservation", "research_agricultural_growth_speed")) {
    $spaceAgeScriptedLine = Get-LastStreamReportLine -Key $scriptedStream
    Assert-ReportLineGenerated -Line $spaceAgeScriptedLine -Context "Space Age scripted candidate stream $scriptedStream"
    Assert-ReportLineContains -Line $spaceAgeScriptedLine -Expected "effects=1" -Context "Space Age scripted candidate stream $scriptedStream"
    if ($scriptedStream -eq "research_spoilage_preservation") {
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "space-science-pack" -Context "Space Age spoilage preservation science pack scenario"
    }
    if ($scriptedStream -eq "research_agricultural_growth_speed") {
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "agricultural-science-pack" -Context "Space Age agricultural growth speed agricultural science scenario"
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "electromagnetic-science-pack" -Context "Space Age agricultural growth speed electromagnetic science scenario"
      Assert-ReportScienceContains -Line $spaceAgeScriptedLine -Expected "cryogenic-science-pack" -Context "Space Age agricultural growth speed cryogenic science scenario"
      Assert-ReportLineContains -Line $spaceAgeScriptedLine -Expected "icon=tech:agriculture" -Context "Space Age agricultural growth speed icon scenario"
    }
  }
  Assert-LogContains -Expected "spoilage preservation applied level=0" -Context "Checkbox-enabled scripted spoilage runtime scenario"
  Assert-LogContains -Expected "agricultural growth speed force state refreshed enabled=true" -Context "Checkbox-enabled scripted agricultural runtime scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-scripted-candidates-disabled" -EnabledFixtureNames @() `
    -ScriptedDiagnostics `
    -EnableSpaceAge
  foreach ($disabledScriptedStream in @("research_spoilage_preservation", "research_agricultural_growth_speed")) {
    $disabledScriptedLine = Get-LastStreamReportLine -Key $disabledScriptedStream
    if ($disabledScriptedLine -notmatch "status=skipped" -or $disabledScriptedLine -notmatch "disabled") {
      throw "Default-disabled scripted stream should skip when its checkbox is off: $disabledScriptedLine"
    }
  }
  Assert-LogContains -Expected "spoilage preservation skipped: disabled" -Context "Default-disabled scripted spoilage runtime scenario"
  Assert-LogContains -Expected "agricultural growth speed force state refreshed enabled=false" -Context "Default-disabled scripted agricultural runtime scenario"
}

Invoke-RuntimeScenario -ScenarioName "space-age-generation-integrity" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -EnableSpaceAge
Assert-SpaceAgeVanillaOwnedProductivityStreamsSkipped -Context "Space Age generation integrity scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Space Age generation integrity scenario"
$spaceAgeRailsLine = Get-LastStreamReportLine -Key "research_rails"
Assert-ReportLineContains -Line $spaceAgeRailsLine -Expected "effects=3" -Context "Space Age Elevated Rails productivity scenario"
Assert-ReportLineContains -Line $spaceAgeRailsLine -Expected "icon=tech:elevated-rail" -Context "Space Age Elevated Rails productivity icon scenario"
$spaceAgeArtificialSoilLine = Get-LastStreamReportLine -Key "research_artificial_soil"
Assert-ReportLineGenerated -Line $spaceAgeArtificialSoilLine -Context "Space Age artificial soil productivity scenario"
Assert-ReportScienceContains -Line $spaceAgeArtificialSoilLine -Expected "agricultural-science-pack" -Context "Space Age artificial soil agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeArtificialSoilLine -Expected "space-science-pack" -Context "Space Age artificial soil space science scenario"
$spaceAgeBacteriaCultivationLine = Get-LastStreamReportLine -Key "research_bacteria_cultivation"
Assert-ReportLineGenerated -Line $spaceAgeBacteriaCultivationLine -Context "Space Age bacteria cultivation productivity scenario"
Assert-ReportScienceContains -Line $spaceAgeBacteriaCultivationLine -Expected "agricultural-science-pack" -Context "Space Age bacteria cultivation agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeBacteriaCultivationLine -Expected "cryogenic-science-pack" -Context "Space Age bacteria cultivation cryogenic science scenario"
$spaceAgeBreedingLine = Get-LastStreamReportLine -Key "research_breeding"
Assert-ReportLineGenerated -Line $spaceAgeBreedingLine -Context "Space Age breeding productivity scenario"
Assert-ReportScienceContains -Line $spaceAgeBreedingLine -Expected "agricultural-science-pack" -Context "Space Age breeding agricultural science scenario"
Assert-ReportScienceContains -Line $spaceAgeBreedingLine -Expected "cryogenic-science-pack" -Context "Space Age breeding cryogenic science scenario"
foreach ($weaponSpeedStream in @("research_rocket_shooting_speed", "research_cannon_shooting_speed")) {
  $weaponSpeedLine = Get-LastStreamReportLine -Key $weaponSpeedStream
  Assert-ReportLineGenerated -Line $weaponSpeedLine -Context "Space Age weapon shooting speed stream $weaponSpeedStream"
  Assert-ReportScienceContains -Line $weaponSpeedLine -Expected "electromagnetic-science-pack" -Context "Space Age weapon shooting speed electromagnetic science scenario $weaponSpeedStream"
  Assert-ReportScienceDoesNotContain -Line $weaponSpeedLine -Unexpected "agricultural-science-pack" -Context "Space Age weapon shooting speed agricultural science replacement scenario $weaponSpeedStream"
}

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-compat" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity",
  "mir-fixture-assert-plates-n-circuit-productivity"
) -EnableSpaceAge
foreach ($stream in @("research_copper", "research_iron", "research_electronic_circuit", "research_advanced_circuit")) {
  $line = Get-LastStreamReportLine -Key $stream
  Assert-ReportLineGenerated -Line $line -Context "Plates n Circuit Productivity replacement stream $stream"
}
foreach ($techName in @("basic-plate-productivity", "electric-circuit-productivity", "advanced-circuit-productivity")) {
  Assert-LogContains -Expected "Prepared competing recipe productivity technology for MIR replacement: $techName" -Context "Plates n Circuit Productivity prepare $techName"
  Assert-LogContains -Expected "Removed competing recipe productivity technology: $techName" -Context "Plates n Circuit Productivity cleanup $techName"
}

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-partial-coverage" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity"
) -DisabledStreamKeys @(
  "research_copper"
) -EnableSpaceAge
$partialIronLine = Get-LastStreamReportLine -Key "research_iron"
Assert-ReportLineGenerated -Line $partialIronLine -Context "Partially covered plate competitor can still allow non-owned iron recipes"
Assert-LogContains -Expected "Skipping recipe productivity effect for research_iron recipe=iron-plate because existing infinite technology already owns it: basic-plate-productivity" -Context "Partial coverage should keep exact iron plate owner"
Assert-LogDoesNotContain -Unexpected "Prepared competing recipe productivity technology for MIR replacement: basic-plate-productivity" -Context "Partial coverage should not prepare combined plate competitor"
Assert-LogDoesNotContain -Unexpected "Removed competing recipe productivity technology: basic-plate-productivity" -Context "Partial coverage should not remove combined plate competitor"

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-change-mismatch" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity-change-mismatch",
  "mir-fixture-assert-plates-n-circuit-productivity-change-mismatch"
) -EnableSpaceAge
Assert-LogDoesNotContain -Unexpected "Prepared competing recipe productivity technology for MIR replacement: electric-circuit-productivity" -Context "Change-mismatched competitor should not be prepared"
Assert-LogDoesNotContain -Unexpected "Removed competing recipe productivity technology: electric-circuit-productivity" -Context "Change-mismatched competitor should not be removed"

Invoke-RuntimeScenario -ScenarioName "space-age-plates-n-circuit-productivity-blocked-owner" -EnabledFixtureNames @(
  "mir-fixture-plates-n-circuit-productivity-blocked",
  "mir-fixture-assert-plates-n-circuit-productivity-blocked"
) -EnableSpaceAge
Assert-LogDoesNotContain -Unexpected "Prepared competing recipe productivity technology for MIR replacement: basic-plate-productivity" -Context "Blocked combined competitor should not be prepared"
Assert-LogDoesNotContain -Unexpected "Removed competing recipe productivity technology: basic-plate-productivity" -Context "Blocked combined competitor should not be removed"

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-adoption" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-adoption-recipes",
  "mir-fixture-assert-vanilla-family-adoption"
) -EnableSpaceAge
$adoptedFamilyExpectations = @{
  research_rocket_fuel = "owners=rocket-fuel-productivity";
  research_low_density_structure = "owners=low-density-structure-productivity";
  research_plastic = "owners=plastic-bar-productivity";
  research_processing_unit = "owners=processing-unit-productivity"
}
foreach ($entry in $adoptedFamilyExpectations.GetEnumerator()) {
  $line = Get-LastStreamReportLine -Key $entry.Key
  Assert-ReportLineAdopted -Line $line -Context "Space Age vanilla family adoption stream $($entry.Key)"
  Assert-ReportLineContains -Line $line -Expected $entry.Value -Context "Space Age vanilla family adoption owner $($entry.Key)"
}
Assert-LogContains -Expected "recipe=mir-fixture-no-productivity-rocket-fuel because recipe_productivity_not_allowed" -Context "Space Age vanilla family adoption allow_productivity=false scenario"

Invoke-RuntimeConfigurationChangeScenario -ScenarioName "space-age-vanilla-family-adoption-config-change" `
  -ChangedFixtureNames @(
    "mir-fixture-vanilla-family-adoption-recipes"
  ) `
  -EnableSpaceAge
Assert-LogContains -Expected "Reset technology effects for productivity family adoption signature change" -Context "Space Age vanilla family adoption configuration-change reset scenario"
Assert-LogContains -Expected "schema=1|owner=rocket-fuel-productivity|recipe=mir-fixture-adopt-rocket-fuel|change=0.1" -Context "Space Age vanilla family adoption configuration-change signature scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-owner-prepatched" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-owner-prepatched",
  "mir-fixture-assert-vanilla-family-owner-prepatched"
) -EnableSpaceAge
$prepatchedRocketFuelLine = Get-LastStreamReportLine -Key "research_rocket_fuel"
if ($prepatchedRocketFuelLine -notmatch "status=skipped" -or $prepatchedRocketFuelLine -notmatch "covered_by_existing_infinite_recipe_productivity") {
  throw "Prepatched family owner should skip residual MIR rocket fuel generation: $prepatchedRocketFuelLine"
}

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-exact-owner" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-exact-owner",
  "mir-fixture-assert-vanilla-family-exact-owner"
) -EnableSpaceAge
$exactOwnerRocketFuelLine = Get-LastStreamReportLine -Key "research_rocket_fuel"
if ($exactOwnerRocketFuelLine -notmatch "status=skipped" -or $exactOwnerRocketFuelLine -notmatch "covered_by_existing_infinite_recipe_productivity") {
  throw "External exact family owner should skip residual MIR rocket fuel generation: $exactOwnerRocketFuelLine"
}

Invoke-RuntimeScenario -ScenarioName "space-age-vanilla-family-mixed-owner" -EnabledFixtureNames @(
  "mir-fixture-vanilla-family-mixed-owner",
  "mir-fixture-assert-vanilla-family-mixed-owner"
) -EnableSpaceAge
$mixedOwnerRocketFuelLine = Get-LastStreamReportLine -Key "research_rocket_fuel"
Assert-ReportLineGenerated -Line $mixedOwnerRocketFuelLine -Context "Mixed owner change fallback scenario"
Assert-LogContains -Expected "owner_mixed_change_values; falling back to MIR generation for eligible recipes" -Context "Mixed owner change fallback scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-fluid-productivity" -EnabledFixtureNames @(
  "mir-fixture-assert-fluid-productivity"
) -EnableSpaceAge
Assert-FluidProductivityStreamsGenerated -Context "Space Age fluid productivity scenario" -IncludeThruster
$spaceAgeOilProcessingLine = Get-LastStreamReportLine -Key "research_oil_processing_productivity"
Assert-ReportScienceContains -Line $spaceAgeOilProcessingLine -Expected "cryogenic-science-pack" -Context "Space Age oil processing cryogenic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeOilProcessingLine -Unexpected "space-science-pack" -Context "Space Age oil processing space science replacement scenario"
$spaceAgeOilCrackingLine = Get-LastStreamReportLine -Key "research_oil_cracking_productivity"
Assert-ReportLineContains -Line $spaceAgeOilCrackingLine -Expected "icon=tech:oil-processing" -Context "Space Age oil cracking icon scenario"
Assert-ReportScienceContains -Line $spaceAgeOilCrackingLine -Expected "agricultural-science-pack" -Context "Space Age oil cracking agricultural science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeOilCrackingLine -Unexpected "space-science-pack" -Context "Space Age oil cracking space science replacement scenario"
$spaceAgeLubricantLine = Get-LastStreamReportLine -Key "research_lubricant_productivity"
Assert-ReportScienceContains -Line $spaceAgeLubricantLine -Expected "electromagnetic-science-pack" -Context "Space Age lubricant electromagnetic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeLubricantLine -Unexpected "space-science-pack" -Context "Space Age lubricant space science replacement scenario"
$spaceAgeSulfuricAcidLine = Get-LastStreamReportLine -Key "research_sulfuric_acid_productivity"
Assert-ReportLineContains -Line $spaceAgeSulfuricAcidLine -Expected "icon=fluid:sulfuric-acid" -Context "Space Age sulfuric acid icon scenario"
Assert-ReportScienceContains -Line $spaceAgeSulfuricAcidLine -Expected "metallurgic-science-pack" -Context "Space Age sulfuric acid metallurgic science scenario"
Assert-ReportScienceDoesNotContain -Line $spaceAgeSulfuricAcidLine -Unexpected "space-science-pack" -Context "Space Age sulfuric acid space science replacement scenario"
$spaceAgeThrusterFuelLine = Get-LastStreamReportLine -Key "research_thruster_fuel_productivity"
Assert-ReportLineContains -Line $spaceAgeThrusterFuelLine -Expected "effects=2" -Context "Space Age thruster fuel productivity scenario"
$spaceAgeThrusterOxidizerLine = Get-LastStreamReportLine -Key "research_thruster_oxidizer_productivity"
Assert-ReportLineContains -Line $spaceAgeThrusterOxidizerLine -Expected "effects=2" -Context "Space Age thruster oxidizer productivity scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-generation-integrity-inserter-enabled" -EnabledFixtureNames @(
  "mir-fixture-assert-generation-integrity"
) -EnabledBaseExtensionKeys @(
  "inserter-capacity-bonus"
) -EnableSpaceAge
Assert-SpaceAgeVanillaOwnedProductivityStreamsSkipped -Context "Space Age generation integrity with inserter enabled scenario"
Assert-DefaultBaseExtensionDiagnostics -Context "Space Age generation integrity with inserter enabled scenario" -InserterCapacityEnabled

Invoke-RuntimeScenario -ScenarioName "space-age-space-promethium-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-and-promethium" -EnableSpaceAge
$spaceAgeSpacePromethiumPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeSpacePromethiumPackLine -Context "Space Age space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePromethiumPackLine -Expected "space-science-pack" -Context "Space Age space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePromethiumPackLine -Expected "promethium-science-pack" -Context "Space Age space and promethium science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "all-official-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "all-official"
$allOfficialPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $allOfficialPackLine -Context "All official science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allOfficialPackLine -Expected "space-science-pack" -Context "All official science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $allOfficialPackLine -Unexpected "mir-fixture-science-pack" -Context "All official science-pack ingredient policy scenario"
$allOfficialExtensionLine = Get-LastExtensionReportLine -Key "research-speed"
Assert-ReportLineGenerated -Line $allOfficialExtensionLine -Context "All official base-extension science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allOfficialExtensionLine -Expected "space-science-pack" -Context "All official base-extension science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $allOfficialExtensionLine -Unexpected "mir-fixture-science-pack" -Context "All official base-extension science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "all-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "all"
$allPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $allPackLine -Context "All lab science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allPackLine -Expected "mir-fixture-science-pack" -Context "All lab science-pack ingredient policy scenario"
$allPackExtensionLine = Get-LastExtensionReportLine -Key "braking-force"
Assert-ReportLineGenerated -Line $allPackExtensionLine -Context "All lab base-extension science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allPackExtensionLine -Expected "mir-fixture-science-pack" -Context "All lab base-extension science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "base-extension-boundary-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-finite-base-extension-level",
  "mir-fixture-assert-base-extension-boundary"
) -SciencePackIngredientPolicy "all"
$baseExtensionBoundaryLine = Get-LastExtensionReportLine -Key "research-speed"
Assert-ReportLineGenerated -Line $baseExtensionBoundaryLine -Context "Base extension boundary scenario"
Assert-ReportLineContains -Line $baseExtensionBoundaryLine -Expected "mir-fixture-science-pack" -Context "Base extension boundary scenario"

Invoke-RuntimeScenario -ScenarioName "weapon-speed-overlap-safety" -EnabledFixtureNames @(
  "mir-fixture-assert-weapon-speed-safety"
) -WeaponSpeedAdjustmentMode "only-when-dedicated-tech-enabled"
$weaponSpeedLine = Get-LastExtensionReportLine -Key "weapon-shooting-speed"
Assert-ReportLineGenerated -Line $weaponSpeedLine -Context "Weapon shooting speed overlap safety scenario"

Invoke-RuntimeScenario -ScenarioName "omega-drill-productivity" -EnabledFixtureNames @(
  "mir-fixture-omega-drill",
  "mir-fixture-assert-omega-drill-productivity"
)
$omegaDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $omegaDrillLine -Context "Omega-style drill productivity scenario"
$omegaEffectCountMatch = [regex]::Match($omegaDrillLine, "effects=(\d+)")
if (-not $omegaEffectCountMatch.Success -or [int]$omegaEffectCountMatch.Groups[1].Value -lt 4) {
  throw "Omega-style drill productivity scenario did not include the expected mining drill effect count: $omegaDrillLine"
}

Invoke-RuntimeScenario -ScenarioName "end-game-prerequisite-gate" -EnabledFixtureNames @() -RequireSpaceGate
$gateLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $gateLine -Context "End-game prerequisite gate scenario"
Assert-ReportLineContains -Line $gateLine -Expected "prerequisites=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack" -Context "End-game prerequisite gate scenario"
Assert-ReportLineDoesNotContain -Line $gateLine -Unexpected "science=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack" -Context "End-game prerequisite gate scenario"

if ($isLegacyFactorio20) {
  Write-Host "[skip] Factorio 2.1 cargo runtime fixture scenarios skipped for Factorio 2.0 legacy metadata."
} else {
  Invoke-RuntimeScenario -ScenarioName "base-cargo-space-age-gate" -EnabledFixtureNames @() -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  )
  $cargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  if ($cargoPadLine -notmatch "status=skipped" -or $cargoPadLine -notmatch "missing required mod space-age") {
    throw "Cargo landing pad count generated or skipped for the wrong reason without Space Age: $cargoPadLine"
  }

  Invoke-RuntimeScenario -ScenarioName "space-age-cargo-pad-enabled" -EnabledFixtureNames @() -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  ) -EnableSpaceAge
  $spaceAgeCargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $spaceAgeCargoPadLine -Context "Space Age cargo landing pad count scenario"
  $spaceAgeCargoDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $spaceAgeCargoDistanceLine -Context "Space Age cargo bay unloading distance scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-cargo-logistics-shape" -EnabledFixtureNames @(
    "mir-fixture-assert-cargo-logistics"
  ) -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  ) -EnableSpaceAge
  $spaceAgeCargoShapePadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $spaceAgeCargoShapePadLine -Context "Space Age cargo logistics shape scenario"
  $spaceAgeCargoShapeDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $spaceAgeCargoShapeDistanceLine -Context "Space Age cargo logistics shape scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-duplicate-cargo-diagnostics" -EnabledFixtureNames @(
    "mir-fixture-duplicate-cargo-tech",
    "mir-fixture-assert-cargo-logistics"
  ) -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  ) -EnableSpaceAge
  $duplicateCargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $duplicateCargoPadLine -Context "Duplicate cargo landing pad diagnostics scenario"
  $duplicateCargoPadOverlapLine = Get-LastNativeModifierOverlapLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineContains -Line $duplicateCargoPadOverlapLine -Expected "effect=cargo-landing-pad-count" -Context "Duplicate cargo landing pad diagnostics scenario"
  Assert-ReportLineContains -Line $duplicateCargoPadOverlapLine -Expected "owners=mir-fixture-duplicate-cargo-landing-pad-count" -Context "Duplicate cargo landing pad diagnostics scenario"

  $duplicateCargoDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $duplicateCargoDistanceLine -Context "Duplicate cargo bay diagnostics scenario"
  $duplicateCargoDistanceOverlapLine = Get-LastNativeModifierOverlapLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineContains -Line $duplicateCargoDistanceOverlapLine -Expected "effect=max-cargo-bay-unloading-distance" -Context "Duplicate cargo bay diagnostics scenario"
  Assert-ReportLineContains -Line $duplicateCargoDistanceOverlapLine -Expected "owners=mir-fixture-duplicate-cargo-bay-unloading-distance" -Context "Duplicate cargo bay diagnostics scenario"
}

if ($usesGeneratedUserDataDir -and (Test-Path -LiteralPath $validationRoot)) {
  Remove-Item -LiteralPath $validationRoot -Recurse -Force
}

Write-Host "[ok] Validation completed."
$global:LASTEXITCODE = 0
