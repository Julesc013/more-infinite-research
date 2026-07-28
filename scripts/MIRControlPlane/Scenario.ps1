function ConvertTo-MIRCPAstText {
  param([Parameter(Mandatory)]$Ast)
  return ([string]$Ast.Extent.Text).Trim() -replace '\s+', ' '
}

function Test-MIRCPAstValueIsStatic {
  param([Parameter(Mandatory)]$Ast)
  $dynamicVariables = @($Ast.FindAll({
    param($node)
    if ($node -isnot [Management.Automation.Language.VariableExpressionAst]) { return $false }
    return [string]$node.VariablePath.UserPath -notin @("true", "false", "null")
  }, $true))
  $dynamicExpressions = @($Ast.FindAll({
    param($node)
    return $node -is [Management.Automation.Language.SubExpressionAst] -or
      $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
  }, $true))
  return $dynamicVariables.Count -eq 0 -and $dynamicExpressions.Count -eq 0
}

function Get-MIRCPCommandParameterRecords {
  param([Parameter(Mandatory)][Management.Automation.Language.CommandAst]$Command)
  $elements = @($Command.CommandElements)
  $records = [Collections.Generic.List[object]]::new()
  for ($index = 1; $index -lt $elements.Count; $index++) {
    $element = $elements[$index]
    if ($element -is [Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
      $records.Add([pscustomobject][ordered]@{
        name = "@splat"
        value_kind = "dynamic"
        value = ConvertTo-MIRCPAstText -Ast $element
        static = $false
        literal_strings = @()
      })
      continue
    }
    if ($element -isnot [Management.Automation.Language.CommandParameterAst]) { continue }
    $argument = $element.Argument
    if ($null -eq $argument -and ($index + 1) -lt $elements.Count -and $elements[$index + 1] -isnot [Management.Automation.Language.CommandParameterAst]) {
      $argument = $elements[$index + 1]
      $index++
    }
    if ($null -eq $argument) {
      $records.Add([pscustomobject][ordered]@{
        name = ([string]$element.ParameterName).ToLowerInvariant()
        value_kind = "switch"
        value = $true
        static = $true
        literal_strings = @()
      })
      continue
    }
    $isStatic = Test-MIRCPAstValueIsStatic -Ast $argument
    $strings = @()
    if ($isStatic) {
      $strings = @($argument.FindAll({param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst]}, $true) |
        ForEach-Object { [string]$_.Value })
    }
    $records.Add([pscustomobject][ordered]@{
      name = ([string]$element.ParameterName).ToLowerInvariant()
      value_kind = if ($isStatic) { "static-ast" } else { "dynamic-ast" }
      value = ConvertTo-MIRCPAstText -Ast $argument
      static = $isStatic
      literal_strings = $strings
    })
  }
  return @($records)
}

function Get-MIRCPScenarioInvocationAuthority {
  param(
    [Parameter(Mandatory)][string]$RunnerPath,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $tokens = $null
  $parseErrors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($RunnerPath, [ref]$tokens, [ref]$parseErrors)
  if (@($parseErrors).Count -gt 0) {
    throw "Validation runner has PowerShell parser errors: $(@($parseErrors).Message -join '; ')"
  }
  $commands = @($ast.FindAll({
    param($node)
    return $node -is [Management.Automation.Language.CommandAst] -and
      $node.GetCommandName() -in @("Invoke-RuntimeScenario", "Invoke-ConfigurationChangeScenario", "Invoke-PackageZipSmokeScenario")
  }, $true))
  $records = [Collections.Generic.List[object]]::new()
  foreach ($command in $commands) {
    $parameters = @(Get-MIRCPCommandParameterRecords -Command $command)
    $scenarioParameter = @($parameters | Where-Object name -eq "scenarioname")
    $scenarioName = $null
    if ($scenarioParameter.Count -eq 1 -and [bool]$scenarioParameter[0].static -and @($scenarioParameter[0].literal_strings).Count -eq 1) {
      $scenarioName = [string]$scenarioParameter[0].literal_strings[0]
    }
    $environmentParameters = @($parameters | Where-Object name -notin @("scenarioname", "enabledfixturenames") | Sort-Object name, value)
    $fixtureParameter = @($parameters | Where-Object name -eq "enabledfixturenames")
    $fixtureNames = @()
    $fixtureStatic = $true
    if ($fixtureParameter.Count -gt 0) {
      $fixtureStatic = @($fixtureParameter | Where-Object { -not [bool]$_.static }).Count -eq 0
      if ($fixtureStatic) { $fixtureNames = @($fixtureParameter.literal_strings | Sort-Object -Unique) }
    }
    $records.Add([pscustomobject][ordered]@{
      command = [string]$command.GetCommandName()
      scenario_name = $scenarioName
      line = [int]$command.Extent.StartLineNumber
      command_sha256 = Get-MIRCPSha256Text -Value (ConvertTo-MIRCPAstText -Ast $command)
      parameters = $parameters
      environment_parameters = $environmentParameters
      fixture_names = $fixtureNames
      environment_static = ($fixtureStatic -and @($environmentParameters | Where-Object { -not [bool]$_.static }).Count -eq 0)
    })
  }
  return @($records)
}

function ConvertTo-MIRCPAssertionIdPart {
  param([Parameter(Mandatory)][string]$Value)
  $part = $Value.ToLowerInvariant() -replace '[^a-z0-9.-]+', '-'
  return $part.Trim('-')
}

function New-MIRCPExecutionRegistry {
  param(
    [string]$Target = "2.1",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $catalogPath = Join-Path $repo "fixtures/compat-matrix/expected-scenarios.json"
  $runnerPath = Join-Path $repo "scripts/Invoke-MIRValidation.ps1"
  $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
  $targetProperty = $catalog.profiles.PSObject.Properties[$Target]
  if ($null -eq $targetProperty) { throw "Scenario catalog has no target profile $Target." }
  $declarations = @($targetProperty.Value | Sort-Object name)
  $invocations = @(Get-MIRCPScenarioInvocationAuthority -RunnerPath $runnerPath -RepoRoot $repo)
  $literalInvocations = @($invocations | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.scenario_name) })
  $declaredNames = @($declarations.name | ForEach-Object { [string]$_ })
  $extraLiteralNames = @($literalInvocations.scenario_name | Where-Object { $_ -notin $declaredNames } | Sort-Object -Unique)
  $scenarioRows = [Collections.Generic.List[object]]::new()
  $assertionCount = 0
  $literalAuthorityCount = 0
  $fallbackCount = 0
  foreach ($declaration in $declarations) {
    $name = [string]$declaration.name
    $matches = @($literalInvocations | Where-Object scenario_name -eq $name)
    $literalAuthority = $matches.Count -eq 1 -and [bool]$matches[0].environment_static
    $authority = if ($literalAuthority) {
      $literalAuthorityCount++
      [pscustomobject][ordered]@{
        type = "runner-literal-ast"
        command = [string]$matches[0].command
        line = [int]$matches[0].line
        command_sha256 = [string]$matches[0].command_sha256
        environment_parameters = @($matches[0].environment_parameters)
      }
    } else {
      $fallbackCount++
      [pscustomobject][ordered]@{
        type = "declaration-isolated-fallback"
        reason = if ($matches.Count -eq 0) { "no unique literal runner call" } elseif ($matches.Count -gt 1) { "multiple conditional literal runner calls" } else { "runner environment contains dynamic AST values" }
        matching_literal_calls = $matches.Count
        lines = @($matches.line | Sort-Object)
      }
    }
    $fixtures = if ($literalAuthority) { @($matches[0].fixture_names | Sort-Object -Unique) } else { @($declaration.fixtures | ForEach-Object { [string]$_ } | Sort-Object -Unique) }
    $settings = if ($literalAuthority) { @($matches[0].environment_parameters) } else { $declaration.settings }
    $excludedTags = @("configuration-change", "randomized-order", "runtime-state", "scale")
    $tags = @($declaration.tags | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $batchable = $literalAuthority -and [string]$declaration.kind -eq "runtime" -and
      [string]$declaration.isolation -eq "fresh-data-stage" -and [string]$declaration.source_mode -eq "exact-package" -and
      @($tags | Where-Object { $_ -in $excludedTags }).Count -eq 0
    $officialModules = if ([string]$declaration.surface -eq "space-age") { @("base", "elevated-rails", "quality", "space-age") } else { @("base") }
    $template = [pscustomobject][ordered]@{
      target = $Target
      process_kind = if ([string]$declaration.kind -in @("runtime", "configuration-change", "package")) { "factorio" } else { "none" }
      scenario_kind = [string]$declaration.kind
      surface = [string]$declaration.surface
      official_modules = $officialModules
      fixture_bundle = $fixtures
      settings = $settings
      source_mode = [string]$declaration.source_mode
      process_model = "one-factorio-process-per-exact-environment"
      isolation = [string]$declaration.isolation
      observation_abi = 1
      timeout_seconds = [int]$declaration.timeout_seconds
      legacy_scenario = if ($batchable) { $null } else { $name }
    }
    $environmentSignature = Get-MIRCPSha256Object -Value $template
    $assertions = @($declaration.assertions | ForEach-Object {
      $sourceId = [string]$_.id
      $assertionCount++
      [pscustomobject][ordered]@{
        schema = 1
        id = "assertion/$Target/$(ConvertTo-MIRCPAssertionIdPart -Value $name)/$(ConvertTo-MIRCPAssertionIdPart -Value $sourceId)"
        version = 1
        type = "captured-proposition"
        reads = @("facts.assertions.$sourceId.status")
        proposition = "Scenario '$name' satisfies '$([string]$_.type)'."
        expected = "passed"
      }
    })
    $scenarioRows.Add([pscustomobject][ordered]@{
      schema = 1
      id = "scenario/$Target/$(ConvertTo-MIRCPAssertionIdPart -Value $name)"
      name = $name
      target = $Target
      kind = [string]$declaration.kind
      group = [string]$declaration.group
      tags = $tags
      authority = $authority
      batchable = $batchable
      environment = [pscustomobject][ordered]@{signature_sha256=$environmentSignature; template=$template}
      assertions = $assertions
    })
  }
  $batchRows = [Collections.Generic.List[object]]::new()
  foreach ($group in @($scenarioRows | Group-Object { [string]$_.environment.signature_sha256 } | Sort-Object Name)) {
    $members = @($group.Group | Sort-Object id)
    $assertionIds = @($members.assertions.id | Sort-Object)
    $batchRows.Add([pscustomobject][ordered]@{
      schema = 1
      id = "environment/$Target/$(([string]$group.Name).ToLowerInvariant())"
      environment_signature = [string]$group.Name
      process_required = [string]$members[0].environment.template.process_kind -eq "factorio"
      resource_class = if ([string]$members[0].environment.template.process_kind -eq "factorio") { "factorio-exclusive" } else { "cpu-light" }
      scenario_ids = @($members.id)
      assertion_ids = $assertionIds
    })
  }
  $factorioScenarioRows = @($scenarioRows | Where-Object { [string]$_.environment.template.process_kind -eq "factorio" })
  $factorioScenarios = $factorioScenarioRows.Count
  $factorioAssertions = @($factorioScenarioRows.assertions).Count
  $factorioBatches = @($batchRows | Where-Object process_required).Count
  $body = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-execution-registry"
    target = $Target
    observation_abi = 1
    source = [pscustomobject][ordered]@{
      catalog = "fixtures/compat-matrix/expected-scenarios.json"
      catalog_sha256 = Get-MIRCPSha256File -Path $catalogPath
      runner = "scripts/Invoke-MIRValidation.ps1"
      runner_sha256 = Get-MIRCPSha256File -Path $runnerPath
      ast_command_count = $invocations.Count
      unmatched_literal_scenarios = $extraLiteralNames
    }
    metrics = [pscustomobject][ordered]@{
      declarations = $declarations.Count
      assertions = $assertionCount
      literal_runner_authorities = $literalAuthorityCount
      isolated_fallbacks = $fallbackCount
      environment_templates = @($scenarioRows.environment.signature_sha256 | Sort-Object -Unique).Count
      batches = $batchRows.Count
      factorio_scenarios = $factorioScenarios
      factorio_assertions = $factorioAssertions
      projected_factorio_processes = $factorioBatches
      avoided_factorio_launches = $factorioAssertions - $factorioBatches
    }
    scenarios = @($scenarioRows)
    batches = @($batchRows)
  }
  return $body
}

function Assert-MIRCPExecutionRegistry {
  param(
    [Parameter(Mandatory)]$Registry,
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  if ([int]$Registry.schema -ne 1 -or [string]$Registry.authority -ne "mir-control-plane-v5-execution-registry") { throw "Execution registry identity is invalid." }
  $catalog = Get-Content -Raw -LiteralPath (Join-Path $repo "fixtures/compat-matrix/expected-scenarios.json") | ConvertFrom-Json
  $expected = @($catalog.profiles.PSObject.Properties[[string]$Registry.target].Value)
  if (@($Registry.scenarios).Count -ne $expected.Count) { throw "Execution registry does not cover every declared scenario." }
  $ids = @($Registry.scenarios.id | ForEach-Object { [string]$_ })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw "Execution registry contains duplicate scenario ids." }
  $assertionIds = @($Registry.scenarios.assertions.id | ForEach-Object { [string]$_ })
  if (@($assertionIds | Sort-Object -Unique).Count -ne $assertionIds.Count) { throw "Execution registry contains duplicate assertion ids." }
  $coveredScenarios = @($Registry.batches | ForEach-Object { @($_.scenario_ids) } | ForEach-Object { [string]$_ })
  $coveredText = (($coveredScenarios | Sort-Object) -join "`n")
  $expectedText = (($ids | Sort-Object) -join "`n")
  if ($coveredText -cne $expectedText) { throw "Execution batches do not cover every scenario exactly once." }
  foreach ($scenario in @($Registry.scenarios)) {
    $actual = Get-MIRCPSha256Object -Value $scenario.environment.template
    if ($actual -ne [string]$scenario.environment.signature_sha256) { throw "Scenario $($scenario.id) has a stale environment signature." }
  }
  foreach ($batch in @($Registry.batches)) {
    $members = @($Registry.scenarios | Where-Object { [string]$_.id -in @($batch.scenario_ids) })
    $signatures = @($members.environment.signature_sha256 | Sort-Object -Unique)
    if ($signatures.Count -ne 1 -or [string]$signatures[0] -ne [string]$batch.environment_signature) { throw "Batch $($batch.id) combines incompatible environments." }
    if ($members.Count -gt 1 -and @($members | Where-Object { -not [bool]$_.batchable }).Count -gt 0) { throw "Batch $($batch.id) combines an isolated scenario." }
  }
  if ([int]$Registry.metrics.declarations -ne @($Registry.scenarios).Count -or [int]$Registry.metrics.assertions -ne $assertionIds.Count -or [int]$Registry.metrics.batches -ne @($Registry.batches).Count) {
    throw "Execution registry metrics are stale."
  }
  return [pscustomobject][ordered]@{
    scenarios = $ids.Count
    assertions = $assertionIds.Count
    batches = @($Registry.batches).Count
    projected_factorio_processes = [int]$Registry.metrics.projected_factorio_processes
    avoided_factorio_launches = [int]$Registry.metrics.avoided_factorio_launches
    isolated_fallbacks = [int]$Registry.metrics.isolated_fallbacks
  }
}

function Update-MIRCPExecutionRegistry {
  param(
    [string]$Target = "2.1",
    [string]$RepoRoot = "",
    [switch]$Check
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $registry = New-MIRCPExecutionRegistry -Target $Target -RepoRoot $repo
  [void](Assert-MIRCPExecutionRegistry -Registry $registry -RepoRoot $repo)
  Write-MIRCPJson -Path "validation/generated/execution-registry.json" -Value $registry -RepoRoot $repo -Check:$Check
  return $registry
}
