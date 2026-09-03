# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../.."))
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"

$manifestPaths = @(
  "validation\scenarios\manual.json",
  "validation\scenarios\local-2.1.json",
  "validation\scenarios\local-2.0.json"
)
$allowedTargets = @("2.0", "2.1")
$allowedClaims = @("loads", "observed", "cooperates", "diagnostic-only", "partial-support", "full-family-support", "full-pack-support")

$compatAuditSource = @(
  Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools/commands/compatibility/Invoke-MIRCompatAudit.ps1")
  Get-ChildItem -LiteralPath (Join-Path $RepoRoot "tools/commands/compatibility/compat-audit") -File -Filter "*.ps1" |
    Sort-Object Name |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
) -join "`n"
$factorioProcessIndex = $compatAuditSource.IndexOf("FactorioProcess.ps1", [StringComparison]::Ordinal)
$settingsOverridesIndex = $compatAuditSource.IndexOf("SettingsOverrides.ps1", [StringComparison]::Ordinal)
if ($factorioProcessIndex -lt 0 -or $settingsOverridesIndex -lt 0 -or
    $factorioProcessIndex -gt $settingsOverridesIndex) {
  throw "Compatibility audit must load Factorio path-budget helpers before settings override materialization."
}

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

    $settings = Assert-MIRProperty -Object $scenario -Name "settings" -Context $context
    foreach ($settingProperty in @($settings.PSObject.Properties)) {
      if ([string]::IsNullOrWhiteSpace([string]$settingProperty.Name)) {
        throw "$context settings contains an empty startup-setting name."
      }
      if ($null -eq $settingProperty.Value -or
          $settingProperty.Value -isnot [bool] -and
          $settingProperty.Value -isnot [string] -and
          $settingProperty.Value -isnot [byte] -and
          $settingProperty.Value -isnot [sbyte] -and
          $settingProperty.Value -isnot [int16] -and
          $settingProperty.Value -isnot [uint16] -and
          $settingProperty.Value -isnot [int32] -and
          $settingProperty.Value -isnot [uint32] -and
          $settingProperty.Value -isnot [int64] -and
          $settingProperty.Value -isnot [uint64] -and
          $settingProperty.Value -isnot [single] -and
          $settingProperty.Value -isnot [double] -and
          $settingProperty.Value -isnot [decimal]) {
        throw "$context setting '$($settingProperty.Name)' must be a scalar startup-setting value."
      }
    }
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
    if ($expectedPlan.PSObject.Properties.Name -contains "required_audit_rows") {
      $requiredAuditRows = @($expectedPlan.required_audit_rows)
      if ($requiredAuditRows.Count -eq 0) { throw "$context expected_plan.required_audit_rows must not be empty." }
      foreach ($expectedRow in $requiredAuditRows) {
        $properties = @($expectedRow.PSObject.Properties)
        if ($properties.Count -eq 0 -or @($properties | Where-Object {
              [string]::IsNullOrWhiteSpace([string]$_.Name) -or
              [string]::IsNullOrWhiteSpace([string]$_.Value)
            }).Count -gt 0) {
          throw "$context expected_plan.required_audit_rows entries must contain non-empty exact property matches."
        }
      }
    }
    foreach ($fragmentField in @("required_log_fragments", "forbidden_log_fragments")) {
      if ($expectedPlan.PSObject.Properties.Name -notcontains $fragmentField) { continue }
      $fragments = @($expectedPlan.$fragmentField)
      if ($fragments.Count -eq 0 -or @($fragments | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw "$context expected_plan.$fragmentField must contain non-empty literal fragments."
      }
    }

    $timeout = [int](Assert-MIRProperty -Object $scenario -Name "timeout_seconds" -Context $context)
    if ($timeout -lt 1 -or $timeout -gt 3600) { throw "$context timeout_seconds must be between 1 and 3600." }
    if ($scenario.PSObject.Properties.Name -contains "mods" -or $scenario.PSObject.Properties.Name -contains "include_space_age") {
      throw "$context retains a schema-1 field; use roots and setup.include_space_age."
    }
  }
}

$local21Manifest = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\scenarios\local-2.1.json") | ConvertFrom-Json
$corrundumScenario = @($local21Manifest.scenarios | Where-Object { $_.name -eq "local-2-1-corrundum-maxcap-13" })
if ($corrundumScenario.Count -ne 1) {
  throw "validation/scenarios/local-2.1.json must contain exactly one local-2-1-corrundum-maxcap-13 scenario."
}
$corrundumRoots = @($corrundumScenario[0].roots | ForEach-Object { [string]$_ })
if ($corrundumRoots -notcontains "PlanetsLib" -or $corrundumRoots -notcontains "corrundum") {
  throw "local-2-1-corrundum-maxcap-13 must root both exact PlanetsLib and Corrundum archives."
}
if ([int]$corrundumScenario[0].settings.'ips-max-level-research_processing_unit' -ne 13 -or
    [int]$corrundumScenario[0].settings.'ips-max-level-research_lubricant_productivity' -ne 13 -or
    [int]$corrundumScenario[0].settings.'mir-max-level-braking-force' -ne 13) {
  throw "local-2-1-corrundum-maxcap-13 must retain the cap-13 reproduction settings."
}
if (@($corrundumScenario[0].expected_plan.required_log_fragments).Count -ne 9 -or
    @($corrundumScenario[0].expected_plan.required_audit_rows).Count -ne 1 -or
    @($corrundumScenario[0].expected_plan.forbidden_log_fragments) -notcontains "Maximum-level conflict") {
  throw "local-2-1-corrundum-maxcap-13 must machine-check the schema repair and all nine cap-13 bindings without conflicts."
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
