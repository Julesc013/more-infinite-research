param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"

$manifestPaths = @(
  "fixtures\compat-matrix\manual-scenarios.json",
  "fixtures\compat-matrix\local-library-scenarios.json",
  "fixtures\compat-matrix\local-library-scenarios-2.0.json"
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

    $timeout = [int](Assert-MIRProperty -Object $scenario -Name "timeout_seconds" -Context $context)
    if ($timeout -lt 1 -or $timeout -gt 3600) { throw "$context timeout_seconds must be between 1 and 3600." }
    if ($scenario.PSObject.Properties.Name -contains "mods" -or $scenario.PSObject.Properties.Name -contains "include_space_age") {
      throw "$context retains a schema-1 field; use roots and setup.include_space_age."
    }
  }
}

$compatAuditText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRCompatAudit.ps1")
foreach ($requiredSnippet in @(
  '. (Join-Path $PSScriptRoot "validation\SettingsOverrides.ps1")',
  'Initialize-MIRSettingsOverrideMod -ModsDir $modsDir -FactorioVersion $FactorioLine',
  'Set-CopiedStartupSettingDefaults -ModsDir $modsDir -Overrides $scenarioSettings',
  '"mir-validation-settings-overrides"'
)) {
  if (-not $compatAuditText.Contains($requiredSnippet)) {
    throw "Compatibility audit does not apply declared scenario settings through the isolated override mod: $requiredSnippet"
  }
}

$runnerText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\MIRCompatAudit\FactorioRunner.ps1")
if (-not $runnerText.Contains("locale=en") -or $runnerText.Contains("locale=auto")) {
  throw "Compatibility load scenarios must pin the Factorio locale to English for reproducible diagnostics."
}

Write-Host "[ok] MIR scenario schema 2 manifests own targets, setup, roots, settings, expected plans, timeouts, and claim levels."
