param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path $RepoRoot).Path
$runnerPath = Join-Path $RepoRoot "scripts\Invoke-MIRValidation.ps1"
$manifestPath = Join-Path $RepoRoot "fixtures\compat-matrix\expected-scenarios.json"
$factorioVersion = [string]((Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json).factorio_version)

function ConvertTo-AuthorityValue {
  param([AllowNull()]$Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [string] -or $Value -is [bool] -or
      $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or
      $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or
      $Value -is [decimal]) {
    return $Value
  }
  if ($Value -is [Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
      $result[$key] = ConvertTo-AuthorityValue -Value $Value[$key]
    }
    return $result
  }
  if ($Value -is [pscustomobject]) {
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
      $result[[string]$property.Name] = ConvertTo-AuthorityValue -Value $property.Value
    }
    return $result
  }
  if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
    return ,@($Value | ForEach-Object { ConvertTo-AuthorityValue -Value $_ })
  }
  return $Value
}

$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
  throw "Cannot synchronize scenario authority because the validation runner does not parse: $($parseErrors[0].Message)"
}

$functionAst = @($ast.FindAll({
  param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Invoke-RuntimeScenario"
}, $true))
if ($functionAst.Count -ne 1) {
  throw "Expected exactly one Invoke-RuntimeScenario definition; found $($functionAst.Count)."
}

$parameterNames = [ordered]@{}
foreach ($parameter in $functionAst[0].Body.ParamBlock.Parameters) {
  $name = [string]$parameter.Name.VariablePath.UserPath
  $parameterNames[$name.ToLowerInvariant()] = $name
}

$literalInvocations = [ordered]@{}
$calls = @($ast.FindAll({
  param($node)
  $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq "Invoke-RuntimeScenario"
}, $true))
foreach ($call in $calls) {
  $bound = [ordered]@{}
  $isStatic = $true
  $elements = @($call.CommandElements)
  for ($index = 1; $index -lt $elements.Count; $index++) {
    $element = $elements[$index]
    if ($element -isnot [Management.Automation.Language.CommandParameterAst]) {
      $isStatic = $false
      break
    }
    $lookup = $element.ParameterName.ToLowerInvariant()
    if (-not $parameterNames.Contains($lookup)) {
      $isStatic = $false
      break
    }
    $name = [string]$parameterNames[$lookup]
    if (($index + 1) -lt $elements.Count -and
        $elements[$index + 1] -isnot [Management.Automation.Language.CommandParameterAst]) {
      try {
        $bound[$name] = $elements[$index + 1].SafeGetValue()
      } catch {
        $isStatic = $false
        break
      }
      $index++
    } else {
      $bound[$name] = $true
    }
  }
  if ($isStatic -and $bound.Contains("ScenarioName")) {
    # Later calls are the full target-native path when reduced and full branches share a name.
    $literalInvocations[[string]$bound["ScenarioName"]] = $bound
  }
}

$configurationFunctionAst = @($ast.FindAll({
  param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq "Invoke-RuntimeConfigurationChangeScenario"
}, $true))
if ($configurationFunctionAst.Count -ne 1) {
  throw "Expected exactly one Invoke-RuntimeConfigurationChangeScenario definition; found $($configurationFunctionAst.Count)."
}
$configurationParameterNames = [ordered]@{}
foreach ($parameter in $configurationFunctionAst[0].Body.ParamBlock.Parameters) {
  $name = [string]$parameter.Name.VariablePath.UserPath
  $configurationParameterNames[$name.ToLowerInvariant()] = $name
}
$configurationInvocations = [ordered]@{}
$configurationCalls = @($ast.FindAll({
  param($node)
  $node -is [Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq "Invoke-RuntimeConfigurationChangeScenario"
}, $true))
foreach ($call in $configurationCalls) {
  $bound = [ordered]@{}
  $isStatic = $true
  $elements = @($call.CommandElements)
  for ($index = 1; $index -lt $elements.Count; $index++) {
    $element = $elements[$index]
    if ($element -isnot [Management.Automation.Language.CommandParameterAst]) {
      $isStatic = $false
      break
    }
    $lookup = $element.ParameterName.ToLowerInvariant()
    if (-not $configurationParameterNames.Contains($lookup)) {
      $isStatic = $false
      break
    }
    $name = [string]$configurationParameterNames[$lookup]
    if (($index + 1) -lt $elements.Count -and
        $elements[$index + 1] -isnot [Management.Automation.Language.CommandParameterAst]) {
      try {
        $bound[$name] = $elements[$index + 1].SafeGetValue()
      } catch {
        $isStatic = $false
        break
      }
      $index++
    } else {
      $bound[$name] = $true
    }
  }
  if ($isStatic -and $bound.Contains("ScenarioName")) {
    $configurationInvocations[[string]$bound["ScenarioName"]] = $bound
  }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ([int]$manifest.schema -ne 3) { throw "Expected scenario authority schema 3." }
$records = @($manifest.profiles.($factorioVersion))
if ($records.Count -eq 0) { throw "No scenario authority exists for Factorio $factorioVersion." }

$runtimeNames = @($records | Where-Object kind -eq "runtime" | ForEach-Object { [string]$_.name })
$expectedLiteralOnly = @(
  "base-cargo-space-age-gate",
  "reduced-settings-surface",
  "space-age-cargo-logistics-shape",
  "space-age-cargo-pad-enabled",
  "space-age-duplicate-cargo-diagnostics"
)
$literalOnly = @($literalInvocations.Keys | Where-Object { $_ -notin $runtimeNames } | Sort-Object)
if (($literalOnly -join "`n") -cne ($expectedLiteralOnly -join "`n")) {
  throw "Unexpected literal-only runtime calls for target $factorioVersion. Expected [$($expectedLiteralOnly -join ', ')]; actual [$($literalOnly -join ', ')]."
}

$configurationNames = @($records | Where-Object kind -eq "configuration-change" | ForEach-Object { [string]$_.name } | Sort-Object)
$literalConfigurationNames = @($configurationInvocations.Keys | Sort-Object)
if (($literalConfigurationNames -join "`n") -cne ($configurationNames -join "`n")) {
  throw "Configuration-change calls differ from target $factorioVersion authority. Expected [$($configurationNames -join ', ')]; actual [$($literalConfigurationNames -join ', ')]."
}
$expectedDynamic = @(
  "space-age-native-owner-settings-combined",
  "space-age-native-owner-settings-cost-base",
  "space-age-native-owner-settings-cost-growth",
  "space-age-native-owner-settings-default",
  "space-age-native-owner-settings-disabled",
  "space-age-native-owner-settings-effect",
  "space-age-native-owner-settings-max-level",
  "space-age-native-owner-settings-research-time",
  "space-age-native-owner-settings-unrecognized-default",
  "space-age-native-owner-settings-unrecognized-override",
  "weapon-overlap-always-coverage-absent",
  "weapon-overlap-always-coverage-present",
  "weapon-overlap-conditional-coverage-absent",
  "weapon-overlap-conditional-coverage-present",
  "weapon-overlap-off-coverage-absent",
  "weapon-overlap-off-coverage-present"
)
$dynamicNames = @($runtimeNames | Where-Object { -not $literalInvocations.Contains($_) } | Sort-Object)
if (($dynamicNames -join "`n") -cne ($expectedDynamic -join "`n")) {
  throw "Unexpected manifest-driven runtime calls for target $factorioVersion. Expected [$($expectedDynamic -join ', ')]; actual [$($dynamicNames -join ', ')]."
}

$matched = 0
$matchedConfiguration = 0
$preservedDynamic = 0
foreach ($record in $records) {
  if ([string]$record.kind -eq "configuration-change") {
    $scenarioName = [string]$record.name
    $invocation = $configurationInvocations[$scenarioName]
    $record.fixtures = @(
      @($invocation["InitialFixtureNames"]) + @($invocation["ChangedFixtureNames"]) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [string]$_ } |
        Sort-Object -Unique
    )
    $settings = [ordered]@{}
    foreach ($parameterName in $configurationParameterNames.Values) {
      if ($parameterName -in @("ScenarioName", "EnableSpaceAge")) { continue }
      if ($invocation.Contains($parameterName)) {
        $settings[$parameterName] = ConvertTo-AuthorityValue -Value $invocation[$parameterName]
      }
    }
    $record.settings = $settings
    $matchedConfiguration++
    continue
  }
  if ([string]$record.kind -ne "runtime") { continue }
  $scenarioName = [string]$record.name
  if (-not $literalInvocations.Contains($scenarioName)) {
    $preservedDynamic++
    continue
  }
  $invocation = $literalInvocations[$scenarioName]
  $record.fixtures = @($invocation["EnabledFixtureNames"] | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $settings = [ordered]@{}
  foreach ($parameterName in $parameterNames.Values) {
    if ($parameterName -in @("ScenarioName", "EnabledFixtureNames", "EnableSpaceAge")) { continue }
    if ($invocation.Contains($parameterName)) {
      $settings[$parameterName] = ConvertTo-AuthorityValue -Value $invocation[$parameterName]
    }
  }
  $record.settings = $settings
  $matched++
}

$expected = (($manifest | ConvertTo-Json -Depth 100).Replace("`r`n", "`n").Replace("`r", "`n")) + "`n"
$actual = (Get-Content -Raw -LiteralPath $manifestPath).Replace("`r`n", "`n").Replace("`r", "`n")
if ($Check) {
  if ($actual -cne $expected) {
    throw "Runtime scenario authority differs from the static target-native runner. Run scripts/Sync-MIRRuntimeScenarioAuthority.ps1."
  }
  Write-Host "[ok] Runtime scenario authority matches $matched static calls and $matchedConfiguration configuration-change calls; $preservedDynamic manifest-driven calls remain authoritative."
  return
}

[IO.File]::WriteAllText($manifestPath, $expected, [Text.UTF8Encoding]::new($false))
Write-Host "[write] Synchronized $matched static runtime scenarios and $matchedConfiguration configuration-change scenarios; preserved $preservedDynamic manifest-driven runtime scenarios."
