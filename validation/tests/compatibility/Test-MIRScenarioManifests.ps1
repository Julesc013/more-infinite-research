param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../.."))
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"

$manifestPaths = @(
  "validation\scenarios\manual.json",
  "validation\scenarios\local-2.1.json",
  "validation\scenarios\local-2.0.json"
)
$allowedTargets = @("2.0", "2.1")
$allowedClaims = @("loads", "observed", "cooperates", "diagnostic-only", "partial-support", "full-family-support", "full-pack-support")

function Assert-MIRProperty {
  param($Object, [string]$Name, [string]$Context)
  if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
    throw "$Context is missing required property '$Name'."
  }
  return $Object.$Name
}

foreach ($relativePath in $manifestPaths) {
  $path = Join-Path $RepoRoot $relativePath
  $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$manifest.schema -ne 2) { throw "$relativePath must use scenario manifest schema 2." }

  $seenNames = @{}
  foreach ($scenario in @($manifest.scenarios)) {
    $context = "$relativePath scenario"
    $name = [string](Assert-MIRProperty -Object $scenario -Name "name" -Context $context)
    if ([string]::IsNullOrWhiteSpace($name)) { throw "$context has an empty name." }
    if ($seenNames.ContainsKey($name)) { throw "$relativePath contains duplicate scenario '$name'." }
    $seenNames[$name] = $true
    $context = "$relativePath scenario '$name'"

    $targets = @(Assert-MIRProperty -Object $scenario -Name "targets" -Context $context)
    if ($targets.Count -eq 0) { throw "$context must declare at least one target." }
    foreach ($target in $targets) {
      if ([string]$target -notin $allowedTargets) { throw "$context declares unsupported target '$target'." }
    }

    foreach ($requiredText in @("kind", "group", "claim_level", "notes")) {
      $value = [string](Assert-MIRProperty -Object $scenario -Name $requiredText -Context $context)
      if ([string]::IsNullOrWhiteSpace($value)) { throw "$context has an empty '$requiredText'." }
    }
    if ([string]$scenario.claim_level -notin $allowedClaims) { throw "$context has invalid claim level '$($scenario.claim_level)'." }

    $roots = @(Assert-MIRProperty -Object $scenario -Name "roots" -Context $context)
    foreach ($root in $roots) {
      if ([string]::IsNullOrWhiteSpace([string]$root)) { throw "$context contains an empty root." }
    }

    $setup = Assert-MIRProperty -Object $scenario -Name "setup" -Context $context
    foreach ($setupProperty in @("mode", "include_space_age", "offline", "exact_mir_archive")) {
      $null = Assert-MIRProperty -Object $setup -Name $setupProperty -Context "$context setup"
    }

    $null = Assert-MIRProperty -Object $scenario -Name "settings" -Context $context
    $expectedPlan = Assert-MIRProperty -Object $scenario -Name "expected_plan" -Context $context
    foreach ($planProperty in @("mode", "required_result", "maximum_dependency_failures")) {
      $null = Assert-MIRProperty -Object $expectedPlan -Name $planProperty -Context "$context expected_plan"
    }
    if ($expectedPlan.PSObject.Properties.Name -contains "required_stream_science") {
      $requiredStreamScience = $expectedPlan.required_stream_science
      foreach ($streamProperty in @($requiredStreamScience.PSObject.Properties)) {
        if ([string]::IsNullOrWhiteSpace([string]$streamProperty.Name)) {
          throw "$context expected_plan.required_stream_science contains an empty stream name."
        }
        $requiredPacks = @($streamProperty.Value)
        if ($requiredPacks.Count -eq 0 -or @($requiredPacks | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
          throw "$context expected_plan.required_stream_science.$($streamProperty.Name) must name at least one non-empty science pack."
        }
      }
    }
    if ($expectedPlan.PSObject.Properties.Name -contains "forbidden_stream_science") {
      $forbiddenStreamScience = $expectedPlan.forbidden_stream_science
      foreach ($streamProperty in @($forbiddenStreamScience.PSObject.Properties)) {
        if ([string]::IsNullOrWhiteSpace([string]$streamProperty.Name)) {
          throw "$context expected_plan.forbidden_stream_science contains an empty stream name."
        }
        $forbiddenPacks = @($streamProperty.Value)
        if ($forbiddenPacks.Count -eq 0 -or @($forbiddenPacks | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
          throw "$context expected_plan.forbidden_stream_science.$($streamProperty.Name) must name at least one non-empty science pack."
        }
      }
    }

    $timeout = [int](Assert-MIRProperty -Object $scenario -Name "timeout_seconds" -Context $context)
    if ($timeout -lt 1 -or $timeout -gt 3600) { throw "$context timeout_seconds must be between 1 and 3600." }
    if ($scenario.PSObject.Properties.Name -contains "mods" -or $scenario.PSObject.Properties.Name -contains "include_space_age") {
      throw "$context retains a schema-1 field; use roots and setup.include_space_age."
    }
  }
}

$profileScenarioPaths = [ordered]@{
  "fixtures/run-profiles/release-targeted.json" = "validation/scenarios/local-2.1.json"
  "fixtures/run-profiles/release-targeted-2.1.json" = "validation/scenarios/local-2.1.json"
  "fixtures/run-profiles/release-targeted-2.0.json" = "validation/scenarios/local-2.0.json"
  "fixtures/run-profiles/local-audit-2.0.json" = "validation/scenarios/local-2.0.json"
}
foreach ($profileRelativePath in $profileScenarioPaths.Keys) {
  $profile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $profileRelativePath) | ConvertFrom-Json
  $declaredPath = ([string]$profile.manual_scenarios_path).Replace("\", "/")
  $expectedPath = [string]$profileScenarioPaths[$profileRelativePath]
  if ($declaredPath -cne $expectedPath) {
    throw "$profileRelativePath must bind the canonical scenario authority $expectedPath; found $declaredPath."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $declaredPath) -PathType Leaf)) {
    throw "$profileRelativePath names a missing scenario authority: $declaredPath"
  }
}

$canonicalLocalModRoots = [ordered]@{
  "2.1" = "C:\Projects\Factorio\testmods\2.1"
  "2.0" = "C:\Projects\Factorio\testmods\2.0"
}
foreach ($profileFile in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "fixtures\run-profiles") -Filter "*.json" -File)) {
  $profile = Get-Content -Raw -LiteralPath $profileFile.FullName | ConvertFrom-Json
  $factorioLine = [string]$profile.factorio_line
  if (-not $canonicalLocalModRoots.Contains($factorioLine)) { continue }
  $expectedRoot = [string]$canonicalLocalModRoots[$factorioLine]
  $declaredRoots = @()
  if ($profile.PSObject.Properties.Name -contains "local_mod_dir") { $declaredRoots += [string]$profile.local_mod_dir }
  if ($profile.PSObject.Properties.Name -contains "local_mod_zip_dirs") { $declaredRoots += @($profile.local_mod_zip_dirs | ForEach-Object { [string]$_ }) }
  if ($profile.PSObject.Properties.Name -contains "local_mod_library_dirs") { $declaredRoots += @($profile.local_mod_library_dirs | ForEach-Object { [string]$_ }) }
  foreach ($declaredRoot in @($declaredRoots | Sort-Object -Unique)) {
    if ($declaredRoot -cne $expectedRoot) {
      throw "$($profileFile.Name) must use canonical Factorio $factorioLine local archive root $expectedRoot; found $declaredRoot."
    }
  }
}

Write-Host "[ok] MIR scenario schema 2 manifests and run profiles bind canonical targets, setup, roots, settings, expected plans, timeouts, and claim levels."
