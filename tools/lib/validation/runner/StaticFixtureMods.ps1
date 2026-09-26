Invoke-RepoCheck "fixture mods have metadata and data entrypoints" {
  $fixtureRootForStatic = Join-Path $repo "fixtures"
  if (-not (Test-Path -LiteralPath $fixtureRootForStatic)) {
    throw "Fixture directory not found: $fixtureRootForStatic"
  }

  $nonModFixtureDirs = @(
    "compat-matrix",
    "golden-plans",
    "mir4-api-v0",
    "mir4-assurance-scale-v1",
    "mir4-canonical-json-v1",
    "mir4-environment-evidence-v1",
    "mir4-historical-succession-v1",
    "mir4-inspector-compatibility-v1",
    "mir4-mep-discovery-v1",
    "mir4-mep-v0",
    "mir4-mep-v1",
    "mir4-process-ir-v0",
    "mir4-process-ir-v1",
    "museum",
    "run-profiles"
  )
  foreach ($fixture in Get-ChildItem -LiteralPath $fixtureRootForStatic -Directory) {
    if ($nonModFixtureDirs -contains $fixture.Name) { continue }

    $infoPath = Join-Path $fixture.FullName "info.json"
    if (-not (Test-Path -LiteralPath $infoPath)) {
      throw "Fixture directory is missing info.json: $($fixture.FullName)"
    }

    $info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    $externalIdentityFixtures = @{
      "better-robots-extended-competitor" = "Better_Robots_Extended"
      "pypostprocessing-stale-unlock" = "pypostprocessing"
      "space-exploration-recipe-removal" = "space-exploration"
    }
    $allowedExternalIdentity = $externalIdentityFixtures.ContainsKey($fixture.Name) -and
      $externalIdentityFixtures[$fixture.Name] -eq $info.name
    if ([string]::IsNullOrWhiteSpace($info.name) -or
      ($info.name -notmatch "^mir-fixture-" -and -not $allowedExternalIdentity)) {
      throw "Fixture info.json must declare a mir-fixture-* name or an explicitly mapped upstream identity: $infoPath"
    }
    $isHistoricalUpgradeTemplate = $fixture.Name -ceq 'assert-upgrade-historical-terminal-to-mir42'
    if ($isHistoricalUpgradeTemplate -and (
      [string]$info.name -cne 'mir-fixture-assert-upgrade-historical-terminal-to-mir42' -or
      [string]$info.version -cne '1.0.0' -or
      [string]$info.factorio_version -cne '@@FACTORIO_LINE@@' -or
      (@($info.dependencies) -join '|') -cne 'base|more-infinite-research >= @@MIR_UPGRADE_FROM_VERSION@@' -or
      -not (Test-Path -LiteralPath (Join-Path $fixture.FullName 'control.lua') -PathType Leaf))) {
      throw "Historical upgrade fixture must retain its exact staged metadata contract: $infoPath"
    }
    $mir4TargetNativeFixtures = @{
      "assert-upgrade-1-8-9-to-4-0-10000" = "1.0"
      "assert-upgrade-1-9-9-to-4-0-11000" = "1.1"
      "assert-generated-cap-transition-2-0" = "2.0"
      "assert-generated-max-level-2-0" = "2.0"
      "assert-recycler-progression-routes-f200" = "2.0"
      "assert-f200-science-researchability-diagnostic" = "2.0"
      "assert-upgrade-2-5-9-to-4-0-20000" = "2.0"
      "assert-upgrade-2-5-10-to-4-0-20000" = "2.0"
      "assert-upgrade-2-5-10-to-2-5-11" = "2.0"
      "assert-upgrade-2-5-11-to-4-0-20000" = "2.0"
    }
    $allowedMIR4TargetNativeFixture = $isFactorio21Line -and
      $mir4TargetNativeFixtures.ContainsKey($fixture.Name) -and
      [string]$info.factorio_version -eq [string]$mir4TargetNativeFixtures[$fixture.Name]
    if (-not $isHistoricalUpgradeTemplate -and $info.factorio_version -ne $repoInfo.factorio_version) {
      if ($isReducedLegacyLine) { continue }
      if ($allowedMIR4TargetNativeFixture) {
        $fixtureBaseDependency = @($info.dependencies) | Where-Object { $_ -match "^base\s+>=" } | Select-Object -First 1
        $expectedFixtureLine = [regex]::Escape([string]$mir4TargetNativeFixtures[$fixture.Name])
        if ($fixtureBaseDependency -notmatch "^base\s+>=\s+$expectedFixtureLine(\.|$)") {
          throw "Target-native MIR 4 fixture $($info.name) must use its Factorio $($mir4TargetNativeFixtures[$fixture.Name]) base dependency; found '$fixtureBaseDependency'."
        }
        continue
      }
      throw "Fixture $($info.name) must target Factorio $($repoInfo.factorio_version) on this branch; found $($info.factorio_version)."
    }
    $fixtureBaseDependency = @($info.dependencies) | Where-Object { $_ -match "^base\s+>=" } | Select-Object -First 1
    if ($isHistoricalUpgradeTemplate) {
      # Its exact base dependency and staged version anchors were checked above.
    } elseif ($isFactorio017Line) {
      if ($fixtureBaseDependency -notmatch "^base\s+>=\s+0\.17(\.|$)") {
        throw "Fixture $($info.name) must use a Factorio 0.17 base dependency on this branch; found '$fixtureBaseDependency'."
      }
    } elseif ($isFactorio018Line) {
      if ($fixtureBaseDependency -notmatch "^base\s+>=\s+0\.18(\.|$)") {
        throw "Fixture $($info.name) must use a Factorio 0.18 base dependency on this branch; found '$fixtureBaseDependency'."
      }
    } elseif ($isFactorio10Line) {
      if ($fixtureBaseDependency -notmatch "^base\s+>=\s+1\.0(\.|$)") {
        throw "Fixture $($info.name) must use a Factorio 1.0 base dependency on this branch; found '$fixtureBaseDependency'."
      }
    } elseif ($isFactorio11Line) {
      if ($fixtureBaseDependency -notmatch "^base\s+>=\s+1\.1(\.|$)") {
        throw "Fixture $($info.name) must use a Factorio 1.1 base dependency on this branch; found '$fixtureBaseDependency'."
      }
    } elseif ($isLegacyFactorio20) {
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

  # The F200 Bob/Angel diagnostic is explicitly allowed to prebuild the
  # canonical recipe snapshot only in its short-lived parent context. Its
  # child projection must borrow that snapshot, so retain a static ordering
  # guard that catches a fixture which otherwise fails every query closed as
  # recipe-index-unavailable.
  $scienceDiagnosticPath = Join-Path $fixtureRootForStatic "assert-f200-science-researchability-diagnostic/data-final-fixes.lua"
  $scienceDiagnosticText = Get-Content -Raw -LiteralPath $scienceDiagnosticPath
  $contextStart = $scienceDiagnosticText.IndexOf('compiler_context.with_active(')
  $recipeFactsRequire = if ($contextStart -ge 0) {
    $scienceDiagnosticText.IndexOf('local canonical_recipe_facts = require(', $contextStart)
  } else { -1 }
  $recipeIndexBuild = if ($recipeFactsRequire -ge 0) {
    $scienceDiagnosticText.IndexOf('local parent_recipe_index = canonical_recipe_facts.index_view()', $recipeFactsRequire)
  } else { -1 }
  $firstProjection = if ($contextStart -ge 0) {
    $scienceDiagnosticText.IndexOf('reachability.pack_production_rejection_projection(', $contextStart)
  } else { -1 }
  if ($contextStart -lt 0 -or $recipeFactsRequire -lt $contextStart -or $recipeIndexBuild -lt $recipeFactsRequire -or
    $firstProjection -lt $recipeIndexBuild) {
    throw "F200 science researchability diagnostic must initialize its parent recipe snapshot before projections."
  }
}
